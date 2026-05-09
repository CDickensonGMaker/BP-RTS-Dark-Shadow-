@tool
class_name AgentTestRunner
extends Node

## Agent Test Runner
## Reads experiment specs from user://agent/spec.json and runs specific battle configurations.
## Used by the BattleDebug agent to test specific hypotheses.
##
## Run from Godot editor:
##   godot --headless --script res://tools/agent/agent_test_runner.gd
##
## Or include in a scene and call run_experiment()

const REGIMENT_SCENE: PackedScene = preload("res://battle_system/nodes/regiment.tscn")

# Configuration paths
const SPEC_PATH: String = "user://agent/spec.json"
const RESULTS_PATH: String = "user://agent/results.json"

# State
var _spec: Dictionary = {}
var _results: Dictionary = {}
var _current_battle_idx: int = 0
var _current_repeat_idx: int = 0
var _battle_events: Array = []
var _battle_start_time: float = 0.0
var _running: bool = false

# References
var _unit_container: Node3D = null
var _player_regiments: Array[Node] = []
var _enemy_regiments: Array[Node] = []

# Export control
@export var auto_run: bool = false  # Auto-run on _ready if spec exists
@export var quit_when_done: bool = true  # Quit Godot when test completes


func _ready() -> void:
	if auto_run:
		call_deferred("_auto_run")


func _auto_run() -> void:
	await get_tree().create_timer(0.5).timeout
	if FileAccess.file_exists(SPEC_PATH):
		print("[AgentTestRunner] Found spec file, starting experiment...")
		run_experiment()
	else:
		print("[AgentTestRunner] No spec file found at %s" % SPEC_PATH)
		if quit_when_done:
			get_tree().quit(1)


## Run the experiment from spec.json
func run_experiment() -> void:
	if _running:
		push_warning("[AgentTestRunner] Already running!")
		return

	# Load spec
	if not _load_spec():
		push_error("[AgentTestRunner] Failed to load spec")
		if quit_when_done:
			get_tree().quit(1)
		return

	_running = true
	_results = {
		"experiment_name": _spec.get("experiment_name", "unnamed"),
		"hypothesis": _spec.get("hypothesis", ""),
		"started_at": Time.get_datetime_string_from_system(),
		"battles": []
	}

	print("[AgentTestRunner] Starting experiment: %s" % _results.experiment_name)
	print("[AgentTestRunner] Hypothesis: %s" % _results.hypothesis)

	# Create unit container if needed
	if not _unit_container:
		_unit_container = Node3D.new()
		_unit_container.name = "TestUnits"
		add_child(_unit_container)

	# Run battles
	var battles: Array = _spec.get("battles", [])
	for battle_idx in battles.size():
		_current_battle_idx = battle_idx
		var battle_spec: Dictionary = battles[battle_idx]
		var repeats: int = battle_spec.get("repeats", 1)

		print("\n[AgentTestRunner] Battle %d/%d: %s (x%d)" % [
			battle_idx + 1, battles.size(), battle_spec.get("label", "unlabeled"), repeats])

		var battle_results: Dictionary = {
			"label": battle_spec.get("label", "battle_%d" % battle_idx),
			"repeats": repeats,
			"runs": []
		}

		for repeat_idx in repeats:
			_current_repeat_idx = repeat_idx
			var run_result = await _run_single_battle(battle_spec)
			battle_results.runs.append(run_result)

			if repeat_idx % 5 == 0 and repeat_idx > 0:
				print("[AgentTestRunner]   Completed %d/%d repeats" % [repeat_idx, repeats])

		# Calculate aggregate stats
		battle_results["aggregate"] = _calculate_aggregate(battle_results.runs)
		_results.battles.append(battle_results)

	# Finalize and save
	_results["completed_at"] = Time.get_datetime_string_from_system()
	_save_results()

	_running = false
	print("\n[AgentTestRunner] Experiment complete!")
	print("[AgentTestRunner] Results saved to: %s" % RESULTS_PATH)

	if quit_when_done:
		get_tree().quit(0)


## Run a single battle from spec
func _run_single_battle(battle_spec: Dictionary) -> Dictionary:
	_battle_events.clear()
	_battle_start_time = Time.get_ticks_msec() / 1000.0

	# Clear existing units
	_clear_units()
	await get_tree().process_frame

	# Connect to all BattleSignals BEFORE spawning units
	_connect_all_battle_signals()

	# Spawn player units
	var player_spec: Array = battle_spec.get("player", [])
	for unit_spec in player_spec:
		var reg = await _spawn_unit(unit_spec, true)
		if reg:
			_player_regiments.append(reg)

	# Spawn enemy units
	var enemy_spec: Array = battle_spec.get("enemy", [])
	for unit_spec in enemy_spec:
		var reg = await _spawn_unit(unit_spec, false)
		if reg:
			_enemy_regiments.append(reg)

	# Apply orders AFTER all units spawned (so target references resolve)
	_apply_orders()

	# Record starting state
	var player_start_soldiers: int = 0
	var enemy_start_soldiers: int = 0
	for reg in _player_regiments:
		player_start_soldiers += reg.current_soldiers
	for reg in _enemy_regiments:
		enemy_start_soldiers += reg.current_soldiers

	# Start battle
	if DeploymentManager:
		DeploymentManager.start_battle()

	await get_tree().create_timer(0.5).timeout

	# Run for duration
	var duration: float = battle_spec.get("duration_sec", 60.0)
	var elapsed: float = 0.0

	while elapsed < duration:
		await get_tree().create_timer(1.0).timeout
		elapsed += 1.0

		# Check if battle ended
		if _is_battle_over():
			break

	# Calculate result
	var player_survivors: int = 0
	var enemy_survivors: int = 0
	for reg in _player_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0:
			player_survivors += reg.current_soldiers
	for reg in _enemy_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0:
			enemy_survivors += reg.current_soldiers

	var outcome: String = "draw"
	if player_survivors > 0 and enemy_survivors == 0:
		outcome = "player_win"
	elif enemy_survivors > 0 and player_survivors == 0:
		outcome = "enemy_win"
	elif player_survivors > enemy_survivors:
		outcome = "player_advantage"
	elif enemy_survivors > player_survivors:
		outcome = "enemy_advantage"

	return {
		"duration_sec": elapsed,
		"outcome": outcome,
		"player_start": player_start_soldiers,
		"enemy_start": enemy_start_soldiers,
		"player_survivors": player_survivors,
		"enemy_survivors": enemy_survivors,
		"player_casualties": player_start_soldiers - player_survivors,
		"enemy_casualties": enemy_start_soldiers - enemy_survivors,
		"events": _battle_events.duplicate()
	}


## Spawn a unit from spec
## Supports: unit, soldiers/count, pos, facing, order, target
func _spawn_unit(unit_spec: Dictionary, is_player: bool) -> Node:
	var unit_id: String = unit_spec.get("unit", "")
	if unit_id.is_empty():
		push_warning("[AgentTestRunner] Unit spec missing 'unit' field")
		return null

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		push_warning("[AgentTestRunner] Unknown unit: %s" % unit_id)
		return null

	# Duplicate data to allow per-unit modifications
	data = data.duplicate()

	# Set soldier count if specified (support both 'soldiers' and 'count' keys)
	var soldiers: int = unit_spec.get("soldiers", unit_spec.get("count", data.max_soldiers))
	data.max_soldiers = soldiers  # max_soldiers is on RegimentData, not Regiment

	var regiment: Node3D = REGIMENT_SCENE.instantiate()
	regiment.data = data
	regiment.is_player_controlled = is_player
	regiment.current_soldiers = soldiers  # current_soldiers IS on Regiment

	# Position - support explicit pos or default positions
	var pos: Array = unit_spec.get("pos", [])
	if pos.size() >= 3:
		regiment.global_position = Vector3(pos[0], pos[1], pos[2])
	else:
		# Default positions: player on left, enemy on right
		var x_pos: float = -20.0 if is_player else 20.0
		regiment.global_position = Vector3(x_pos, 0, 0)

	# Facing - support explicit facing vector
	var facing: Array = unit_spec.get("facing", [1.0, 0.0, 0.0] if is_player else [-1.0, 0.0, 0.0])
	var facing_vec: Vector3 = Vector3(facing[0], facing[1], facing[2])
	regiment.look_at(regiment.global_position + facing_vec, Vector3.UP)

	_unit_container.add_child(regiment)
	regiment.add_to_group("all_regiments")

	# Store order/target for deferred application after all units spawned
	if unit_spec.has("order"):
		regiment.set_meta("_agent_order", unit_spec.get("order", "hold"))
		regiment.set_meta("_agent_target", unit_spec.get("target", ""))

	return regiment


## Apply orders to all spawned units (called after all units created)
func _apply_orders() -> void:
	for reg in _player_regiments:
		if is_instance_valid(reg) and reg.has_meta("_agent_order"):
			_apply_single_order(reg, true)

	for reg in _enemy_regiments:
		if is_instance_valid(reg) and reg.has_meta("_agent_order"):
			_apply_single_order(reg, false)


## Apply order to a single regiment
func _apply_single_order(reg: Node, is_player: bool) -> void:
	var order_str: String = reg.get_meta("_agent_order", "hold")
	var target_str: String = reg.get_meta("_agent_target", "")

	# Parse target reference like "enemy[0]" or "player[1]"
	var target_reg: Node = null
	var target_pos: Vector3 = Vector3.ZERO

	if target_str.begins_with("enemy["):
		var idx_str: String = target_str.trim_prefix("enemy[").trim_suffix("]")
		var idx: int = int(idx_str)
		var pool: Array = _enemy_regiments if is_player else _player_regiments
		if idx >= 0 and idx < pool.size():
			target_reg = pool[idx]
			if is_instance_valid(target_reg):
				target_pos = target_reg.global_position
	elif target_str.begins_with("player["):
		var idx_str: String = target_str.trim_prefix("player[").trim_suffix("]")
		var idx: int = int(idx_str)
		var pool: Array = _player_regiments if is_player else _enemy_regiments
		if idx >= 0 and idx < pool.size():
			target_reg = pool[idx]
			if is_instance_valid(target_reg):
				target_pos = target_reg.global_position

	# Default target position if no specific target
	if target_pos == Vector3.ZERO:
		var enemy_pool: Array = _enemy_regiments if is_player else _player_regiments
		if not enemy_pool.is_empty() and is_instance_valid(enemy_pool[0]):
			target_pos = enemy_pool[0].global_position

	# Apply order
	if reg.has_method("set_order"):
		var order_type: int = OrderType.Type.HOLD_POSITION
		match order_str.to_lower():
			"charge":
				order_type = OrderType.Type.CHARGE
			"march", "move":
				order_type = OrderType.Type.MOVE
			"hold", _:
				order_type = OrderType.Type.HOLD_POSITION

		reg.set_order(order_type, target_pos, target_reg)

	# Clear meta after applying
	reg.remove_meta("_agent_order")
	reg.remove_meta("_agent_target")


## Clear all spawned units
func _clear_units() -> void:
	for reg in _player_regiments:
		if is_instance_valid(reg):
			reg.queue_free()
	for reg in _enemy_regiments:
		if is_instance_valid(reg):
			reg.queue_free()
	_player_regiments.clear()
	_enemy_regiments.clear()


## Check if battle is over
func _is_battle_over() -> bool:
	var player_alive: int = 0
	var enemy_alive: int = 0

	for reg in _player_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0 and reg.state != reg.State.DEAD:
			player_alive += 1

	for reg in _enemy_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0 and reg.state != reg.State.DEAD:
			enemy_alive += 1

	return player_alive == 0 or enemy_alive == 0


## Calculate aggregate stats from runs
func _calculate_aggregate(runs: Array) -> Dictionary:
	if runs.is_empty():
		return {}

	var total_runs: int = runs.size()
	var player_wins: int = 0
	var enemy_wins: int = 0
	var draws: int = 0
	var total_player_casualties: int = 0
	var total_enemy_casualties: int = 0

	for run in runs:
		var outcome: String = run.get("outcome", "draw")
		if outcome in ["player_win", "player_advantage"]:
			player_wins += 1
		elif outcome in ["enemy_win", "enemy_advantage"]:
			enemy_wins += 1
		else:
			draws += 1

		total_player_casualties += run.get("player_casualties", 0)
		total_enemy_casualties += run.get("enemy_casualties", 0)

	return {
		"total_runs": total_runs,
		"player_wins": player_wins,
		"enemy_wins": enemy_wins,
		"draws": draws,
		"player_win_rate": float(player_wins) / float(total_runs),
		"enemy_win_rate": float(enemy_wins) / float(total_runs),
		"avg_player_casualties": float(total_player_casualties) / float(total_runs),
		"avg_enemy_casualties": float(total_enemy_casualties) / float(total_runs)
	}


## Load experiment spec from file
func _load_spec() -> bool:
	if not FileAccess.file_exists(SPEC_PATH):
		push_error("[AgentTestRunner] Spec file not found: %s" % SPEC_PATH)
		return false

	var file := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if file == null:
		push_error("[AgentTestRunner] Failed to open spec file")
		return false

	var json_string: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)
	if error != OK:
		push_error("[AgentTestRunner] Failed to parse spec JSON: %s" % json.get_error_message())
		return false

	_spec = json.data
	return true


## Save results to file
func _save_results() -> void:
	# Ensure directory exists
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("agent"):
		dir.make_dir("agent")

	var file := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[AgentTestRunner] Failed to open results file for writing")
		return

	var json_string: String = JSON.stringify(_results, "\t")
	file.store_string(json_string)
	file.close()


# =============================================================================
# SIGNAL CAPTURE SYSTEM
# =============================================================================
# Captures all BattleSignals events for expectation checking.
# The referee uses this data to verify scenario expectations.

var _signal_connections: Array[Dictionary] = []  # Track connections for cleanup

## Connect to all BattleSignals for event capture
func _connect_all_battle_signals() -> void:
	if not BattleSignals:
		push_warning("[AgentTestRunner] BattleSignals autoload not available")
		return

	# Disconnect any existing connections
	_disconnect_all_battle_signals()

	# Get all signals from BattleSignals
	for sig_info in BattleSignals.get_signal_list():
		var sig_name: String = sig_info.name

		# Skip Object built-in signals
		if sig_name in ["script_changed", "property_list_changed", "changed", "tree_entered", "tree_exiting", "tree_exited"]:
			continue

		# Create a callback based on signal argument count
		var arg_count: int = sig_info.args.size()
		var callback: Callable

		match arg_count:
			0:
				callback = func(): _record_event_0(sig_name)
			1:
				callback = func(a0): _record_event_1(sig_name, a0)
			2:
				callback = func(a0, a1): _record_event_2(sig_name, a0, a1)
			3:
				callback = func(a0, a1, a2): _record_event_3(sig_name, a0, a1, a2)
			4:
				callback = func(a0, a1, a2, a3): _record_event_4(sig_name, a0, a1, a2, a3)
			_:
				# For signals with 5+ args, use generic handler
				callback = func(a0 = null, a1 = null, a2 = null, a3 = null, a4 = null):
					_record_event_generic(sig_name, [a0, a1, a2, a3, a4])

		BattleSignals.connect(sig_name, callback)
		_signal_connections.append({"signal": sig_name, "callable": callback})


## Disconnect all signal connections
func _disconnect_all_battle_signals() -> void:
	for conn in _signal_connections:
		if BattleSignals and BattleSignals.is_connected(conn.signal, conn.callable):
			BattleSignals.disconnect(conn.signal, conn.callable)
	_signal_connections.clear()


## Record events - arity-specific handlers for type safety
func _record_event_0(sig_name: String) -> void:
	_battle_events.append({
		"t": (Time.get_ticks_msec() / 1000.0) - _battle_start_time,
		"type": sig_name,
		"data": []
	})


func _record_event_1(sig_name: String, a0) -> void:
	_battle_events.append({
		"t": (Time.get_ticks_msec() / 1000.0) - _battle_start_time,
		"type": sig_name,
		"data": [_serialize_arg(a0)]
	})


func _record_event_2(sig_name: String, a0, a1) -> void:
	_battle_events.append({
		"t": (Time.get_ticks_msec() / 1000.0) - _battle_start_time,
		"type": sig_name,
		"data": [_serialize_arg(a0), _serialize_arg(a1)]
	})


func _record_event_3(sig_name: String, a0, a1, a2) -> void:
	_battle_events.append({
		"t": (Time.get_ticks_msec() / 1000.0) - _battle_start_time,
		"type": sig_name,
		"data": [_serialize_arg(a0), _serialize_arg(a1), _serialize_arg(a2)]
	})


func _record_event_4(sig_name: String, a0, a1, a2, a3) -> void:
	_battle_events.append({
		"t": (Time.get_ticks_msec() / 1000.0) - _battle_start_time,
		"type": sig_name,
		"data": [_serialize_arg(a0), _serialize_arg(a1), _serialize_arg(a2), _serialize_arg(a3)]
	})


func _record_event_generic(sig_name: String, args: Array) -> void:
	var serialized: Array = []
	for arg in args:
		if arg != null:
			serialized.append(_serialize_arg(arg))
	_battle_events.append({
		"t": (Time.get_ticks_msec() / 1000.0) - _battle_start_time,
		"type": sig_name,
		"data": serialized
	})


## Serialize an argument to JSON-safe form
func _serialize_arg(a) -> Variant:
	if a == null:
		return null

	# Regiment nodes - extract key data
	if a is Node and a.has_method("get") and "data" in a:
		var is_player: bool = a.is_player_controlled if "is_player_controlled" in a else false
		var unit_id: String = ""
		var unit_name: String = ""
		var soldiers: int = 0

		if a.data:
			unit_id = a.data.id if "id" in a.data else ""
			unit_name = a.data.regiment_name if "regiment_name" in a.data else ""
		if "current_soldiers" in a:
			soldiers = a.current_soldiers

		return {
			"node_name": a.name,
			"unit_id": unit_id,
			"unit_name": unit_name,
			"is_player": is_player,
			"soldiers": soldiers
		}

	# Vector3 - convert to array
	if a is Vector3:
		return [a.x, a.y, a.z]

	# Dictionary - pass through (should already be JSON-safe)
	if a is Dictionary:
		return a

	# Primitives - pass through
	if a is bool or a is int or a is float or a is String:
		return a

	# Arrays - serialize each element
	if a is Array:
		var result: Array = []
		for item in a:
			result.append(_serialize_arg(item))
		return result

	# Fallback - convert to string
	return str(a)
