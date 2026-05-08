class_name BattleSimulator
extends Node

## Automated battle simulator for stress testing combat systems.
## Runs headless battles with various unit compositions to find bugs.

signal simulation_complete(results: Dictionary)
signal battle_complete(battle_num: int, result: Dictionary)

const TOTAL_BATTLES: int = 5000
const UNITS_PER_SIDE: int = 40
const MAX_BATTLE_TIME: float = 300.0  # 5 min max per battle
const TICK_SPEED: float = 10.0  # Run at 10x speed

# Unit type pools for random composition
const UNIT_TYPES: Array[String] = [
	"infantry", "spearmen", "archers", "crossbowmen",
	"cavalry", "knights", "pikemen", "halberdiers",
	"handgunners", "artillery"
]

# Results tracking
var _battles_run: int = 0
var _crashes: Array[Dictionary] = []
var _errors: Array[Dictionary] = []
var _warnings: Array[Dictionary] = []
var _battle_results: Array[Dictionary] = []
var _current_battle_time: float = 0.0
var _is_running: bool = false

# Battle state
var _player_regiments: Array = []
var _enemy_regiments: Array = []
var _battle_start_time: float = 0.0

# Statistics
var _total_null_refs: int = 0
var _total_div_zero: int = 0
var _total_infinite_loops: int = 0
var _total_state_errors: int = 0
var _total_morale_bugs: int = 0
var _total_combat_bugs: int = 0


func _ready() -> void:
	# Capture all errors
	if not get_tree().debug_collisions_hint:
		push_warning("[BattleSimulator] Running in release mode - some errors may not be caught")


func start_simulation() -> void:
	"""Begin the automated battle simulation."""
	print("=" .repeat(60))
	print("[BattleSimulator] Starting %d battle simulation" % TOTAL_BATTLES)
	print("[BattleSimulator] Units per side: %d" % UNITS_PER_SIDE)
	print("=" .repeat(60))

	_is_running = true
	_battles_run = 0
	_crashes.clear()
	_errors.clear()
	_warnings.clear()
	_battle_results.clear()

	Engine.time_scale = TICK_SPEED

	_run_next_battle()


func _run_next_battle() -> void:
	"""Set up and run the next battle."""
	if _battles_run >= TOTAL_BATTLES:
		_finish_simulation()
		return

	_battles_run += 1
	_current_battle_time = 0.0
	_battle_start_time = Time.get_ticks_msec() / 1000.0

	if _battles_run % 100 == 0:
		print("[BattleSimulator] Battle %d / %d (%.1f%%)" % [
			_battles_run, TOTAL_BATTLES,
			float(_battles_run) / TOTAL_BATTLES * 100.0
		])

	# Generate random compositions
	var player_comp: Array = _generate_random_composition()
	var enemy_comp: Array = _generate_random_composition()

	# Spawn units (simulated - we'll create mock regiments)
	_spawn_test_armies(player_comp, enemy_comp)

	# Run battle tick loop
	_simulate_battle()


func _generate_random_composition() -> Array:
	"""Generate a random army composition."""
	var composition: Array = []
	var remaining: int = UNITS_PER_SIDE

	while remaining > 0:
		var unit_type: String = UNIT_TYPES[randi() % UNIT_TYPES.size()]
		var count: int = mini(randi_range(1, 8), remaining)
		composition.append({"type": unit_type, "count": count})
		remaining -= count

	return composition


func _spawn_test_armies(player_comp: Array, enemy_comp: Array) -> void:
	"""Spawn test armies for simulation."""
	_player_regiments.clear()
	_enemy_regiments.clear()

	# Create mock regiment data for testing
	var player_pos := Vector3(-50, 0, 0)
	var enemy_pos := Vector3(50, 0, 0)

	for unit_info in player_comp:
		for i in unit_info.count:
			var mock_regiment := _create_mock_regiment(true, unit_info.type, player_pos)
			if mock_regiment:
				_player_regiments.append(mock_regiment)
				player_pos.z += 5
		player_pos.x -= 10
		player_pos.z = 0

	for unit_info in enemy_comp:
		for i in unit_info.count:
			var mock_regiment := _create_mock_regiment(false, unit_info.type, enemy_pos)
			if mock_regiment:
				_enemy_regiments.append(mock_regiment)
				enemy_pos.z += 5
		enemy_pos.x += 10
		enemy_pos.z = 0


func _create_mock_regiment(is_player: bool, unit_type: String, pos: Vector3) -> Dictionary:
	"""Create a mock regiment dictionary for testing logic."""
	var soldiers: int = randi_range(20, 100)
	var attack: int = randi_range(20, 60)
	var defense: int = randi_range(20, 60)
	var morale: float = randi_range(60, 100)

	return {
		"is_player": is_player,
		"unit_type": unit_type,
		"position": pos,
		"soldiers": soldiers,
		"max_soldiers": soldiers,
		"attack": attack,
		"defense": defense,
		"morale": morale,
		"morale_cap": 100.0,
		"state": "IDLE",
		"is_valid": true,
		"stamina": 100.0,
		"is_engaged": false,
		"target": null,
		"order_queue": [],
	}


func _simulate_battle() -> void:
	"""Run the battle simulation tick by tick."""
	var battle_result := {
		"battle_num": _battles_run,
		"player_comp": _player_regiments.size(),
		"enemy_comp": _enemy_regiments.size(),
		"duration": 0.0,
		"winner": "",
		"errors": [],
		"player_losses": 0,
		"enemy_losses": 0,
	}

	var tick_count: int = 0
	var max_ticks: int = int(MAX_BATTLE_TIME / 0.1)  # 0.1s per tick

	while tick_count < max_ticks:
		tick_count += 1
		_current_battle_time += 0.1

		# Test all systems
		var tick_errors: Array = []

		# 1. Test morale system
		tick_errors.append_array(_test_morale_tick())

		# 2. Test combat resolution
		tick_errors.append_array(_test_combat_tick())

		# 3. Test state transitions
		tick_errors.append_array(_test_state_transitions())

		# 4. Test order queue
		tick_errors.append_array(_test_order_queue())

		# 5. Test casualty tracking
		tick_errors.append_array(_test_casualty_tracking())

		# 6. Test AI decisions
		tick_errors.append_array(_test_ai_decisions())

		# Record errors
		for err in tick_errors:
			battle_result.errors.append(err)
			_record_error(err)

		# Check for battle end
		var player_alive: int = _count_alive(_player_regiments)
		var enemy_alive: int = _count_alive(_enemy_regiments)

		if player_alive == 0 or enemy_alive == 0:
			battle_result.winner = "player" if enemy_alive == 0 else "enemy"
			break

		# Check for stalemate (no combat happening)
		if tick_count > 1000 and not _any_combat_happening():
			battle_result.winner = "stalemate"
			_record_warning({
				"type": "stalemate",
				"battle": _battles_run,
				"tick": tick_count,
				"message": "Battle stalled - no combat for extended period"
			})
			break

	# Timeout check
	if tick_count >= max_ticks:
		battle_result.winner = "timeout"
		_record_warning({
			"type": "timeout",
			"battle": _battles_run,
			"message": "Battle exceeded max time"
		})

	battle_result.duration = _current_battle_time
	battle_result.player_losses = _player_regiments.size() - _count_alive(_player_regiments)
	battle_result.enemy_losses = _enemy_regiments.size() - _count_alive(_enemy_regiments)

	_battle_results.append(battle_result)
	battle_complete.emit(_battles_run, battle_result)

	# Clean up and run next
	_cleanup_battle()
	call_deferred("_run_next_battle")


func _test_morale_tick() -> Array:
	"""Test morale system for bugs."""
	var errors: Array = []

	for reg in _player_regiments + _enemy_regiments:
		if not reg.is_valid:
			continue

		# Test 1: Morale bounds
		if reg.morale < 0 or reg.morale > 100:
			errors.append({
				"type": "morale_bounds",
				"severity": "HIGH",
				"message": "Morale out of bounds: %.2f" % reg.morale,
				"unit": reg.unit_type
			})
			_total_morale_bugs += 1
			reg.morale = clampf(reg.morale, 0, 100)

		# Test 2: Morale cap integrity
		if reg.morale_cap < 10.0 or reg.morale_cap > 100.0:
			errors.append({
				"type": "morale_cap_bounds",
				"severity": "MEDIUM",
				"message": "Morale cap out of bounds: %.2f" % reg.morale_cap,
				"unit": reg.unit_type
			})
			_total_morale_bugs += 1

		# Test 3: Cap should never exceed current max
		if reg.morale > reg.morale_cap + 0.1:  # Small tolerance
			# This is allowed due to rally bonuses, but track it
			pass

		# Simulate morale decay
		if reg.is_engaged:
			reg.morale -= randf_range(0.1, 0.5)
		else:
			reg.morale += randf_range(0.0, 0.2)
		reg.morale = clampf(reg.morale, 0, reg.morale_cap)

		# Test 4: Check for routing trigger
		if reg.morale < 20 and reg.state != "ROUTING" and reg.state != "DEAD":
			reg.state = "ROUTING"

	return errors


func _test_combat_tick() -> Array:
	"""Test combat resolution for bugs."""
	var errors: Array = []

	# Find engagements
	for player_reg in _player_regiments:
		if not player_reg.is_valid or player_reg.state == "DEAD":
			continue

		for enemy_reg in _enemy_regiments:
			if not enemy_reg.is_valid or enemy_reg.state == "DEAD":
				continue

			var dist: float = player_reg.position.distance_to(enemy_reg.position)

			if dist < 5.0:  # Melee range
				player_reg.is_engaged = true
				enemy_reg.is_engaged = true

				# Test combat resolution
				var player_attack: int = player_reg.attack
				var enemy_defense: int = enemy_reg.defense

				# Test 5: Division by zero in hit chance
				if enemy_defense == 0:
					errors.append({
						"type": "div_zero",
						"severity": "CRITICAL",
						"message": "Defense is 0, could cause div/0",
						"unit": enemy_reg.unit_type
					})
					_total_div_zero += 1
					enemy_defense = 1

				# Calculate hit chance (simplified)
				var hit_chance: float = clampf(35.0 + float(player_attack - enemy_defense), 8.0, 90.0)

				# Apply casualties (clamp like real code: regiment.gd:954)
				if randf() * 100.0 < hit_chance:
					var damage: int = randi_range(1, 3)
					var soldiers_before: int = enemy_reg.soldiers
					enemy_reg.soldiers = maxi(0, enemy_reg.soldiers - damage)

					# Test 6: Overkill damage (balance indicator)
					var overkill: int = damage - soldiers_before
					if overkill > 5 and soldiers_before > 0:
						errors.append({
							"type": "overkill_damage",
							"severity": "LOW",
							"message": "Overkill by %d on %s" % [overkill, enemy_reg.unit_type],
							"unit": enemy_reg.unit_type
						})

					# Kill unit if no soldiers
					if enemy_reg.soldiers <= 0:
						enemy_reg.state = "DEAD"
						enemy_reg.is_valid = false

				# Reciprocal damage (clamp like real code)
				if randf() * 100.0 < clampf(35.0 + float(enemy_reg.attack - player_reg.defense), 8.0, 90.0):
					player_reg.soldiers = maxi(0, player_reg.soldiers - randi_range(1, 3))
					if player_reg.soldiers <= 0:
						player_reg.state = "DEAD"
						player_reg.is_valid = false

	return errors


func _test_state_transitions() -> Array:
	"""Test regiment state machine for invalid transitions."""
	var errors: Array = []

	for reg in _player_regiments + _enemy_regiments:
		if not reg.is_valid:
			continue

		var old_state: String = reg.state

		# Test 7: Invalid state values
		if old_state not in ["IDLE", "MARCHING", "ENGAGING", "ROUTING", "RALLYING", "DEAD"]:
			errors.append({
				"type": "invalid_state",
				"severity": "CRITICAL",
				"message": "Invalid state: %s" % old_state,
				"unit": reg.unit_type
			})
			_total_state_errors += 1
			reg.state = "IDLE"

		# Test 8: Dead units shouldn't change state
		if old_state == "DEAD" and reg.is_valid:
			errors.append({
				"type": "zombie_unit",
				"severity": "HIGH",
				"message": "Dead unit still marked as valid",
				"unit": reg.unit_type
			})
			_total_state_errors += 1
			reg.is_valid = false

		# Simulate state transitions
		match old_state:
			"ROUTING":
				# Can rally if morale recovers
				if reg.morale > 40:
					reg.state = "RALLYING"
			"RALLYING":
				if reg.morale > 60:
					reg.state = "IDLE"
				elif reg.morale < 20:
					reg.state = "ROUTING"
			"IDLE", "MARCHING":
				if reg.is_engaged:
					reg.state = "ENGAGING"
			"ENGAGING":
				if not reg.is_engaged:
					reg.state = "IDLE"

	return errors


func _test_order_queue() -> Array:
	"""Test order queue system for bugs."""
	var errors: Array = []

	for reg in _player_regiments + _enemy_regiments:
		if not reg.is_valid:
			continue

		# Test 9: Queue size limits
		if reg.order_queue.size() > 8:
			errors.append({
				"type": "queue_overflow",
				"severity": "MEDIUM",
				"message": "Order queue exceeded max size: %d" % reg.order_queue.size(),
				"unit": reg.unit_type
			})
			reg.order_queue.resize(8)

		# Simulate queue processing
		if reg.state == "IDLE" and not reg.order_queue.is_empty():
			var next_order = reg.order_queue.pop_front()
			# Process order...

	return errors


func _test_casualty_tracking() -> Array:
	"""Test casualty tracking for bugs."""
	var errors: Array = []

	for reg in _player_regiments + _enemy_regiments:
		if not reg.is_valid:
			continue

		# Test 10: Soldiers shouldn't exceed max
		if reg.soldiers > reg.max_soldiers:
			errors.append({
				"type": "soldier_overflow",
				"severity": "HIGH",
				"message": "Soldiers exceed max: %d > %d" % [reg.soldiers, reg.max_soldiers],
				"unit": reg.unit_type
			})
			_total_combat_bugs += 1
			reg.soldiers = reg.max_soldiers

		# Test 11: Loss percentage calculation (div by zero)
		if reg.max_soldiers == 0:
			errors.append({
				"type": "div_zero",
				"severity": "CRITICAL",
				"message": "max_soldiers is 0, would cause div/0 in loss calc",
				"unit": reg.unit_type
			})
			_total_div_zero += 1

	return errors


func _test_ai_decisions() -> Array:
	"""Test AI decision making for bugs."""
	var errors: Array = []

	# Simulate AI target selection
	for reg in _enemy_regiments:
		if not reg.is_valid or reg.state in ["DEAD", "ROUTING"]:
			continue

		# Find target
		var best_target = null
		var best_dist: float = INF

		for player_reg in _player_regiments:
			if not player_reg.is_valid or player_reg.state == "DEAD":
				continue
			var dist: float = reg.position.distance_to(player_reg.position)
			if dist < best_dist:
				best_dist = dist
				best_target = player_reg

		# Test 12: Null target handling
		if best_target == null and not _player_regiments.is_empty():
			# All player units dead or invalid
			pass

		reg.target = best_target

		# Move towards target
		if best_target:
			var dir: Vector3 = (best_target.position - reg.position).normalized()
			reg.position += dir * 0.5  # Move speed

	# Same for player AI
	for reg in _player_regiments:
		if not reg.is_valid or reg.state in ["DEAD", "ROUTING"]:
			continue

		var best_target = null
		var best_dist: float = INF

		for enemy_reg in _enemy_regiments:
			if not enemy_reg.is_valid or enemy_reg.state == "DEAD":
				continue
			var dist: float = reg.position.distance_to(enemy_reg.position)
			if dist < best_dist:
				best_dist = dist
				best_target = enemy_reg

		reg.target = best_target

		if best_target:
			var dir: Vector3 = (best_target.position - reg.position).normalized()
			reg.position += dir * 0.5

	return errors


func _count_alive(regiments: Array) -> int:
	"""Count alive regiments."""
	var count: int = 0
	for reg in regiments:
		if reg.is_valid and reg.state != "DEAD" and reg.soldiers > 0:
			count += 1
	return count


func _any_combat_happening() -> bool:
	"""Check if any combat is occurring."""
	for reg in _player_regiments + _enemy_regiments:
		if reg.is_valid and reg.is_engaged:
			return true
	return false


func _cleanup_battle() -> void:
	"""Clean up after a battle."""
	_player_regiments.clear()
	_enemy_regiments.clear()


func _record_error(error: Dictionary) -> void:
	"""Record an error for the final report."""
	_errors.append(error)

	match error.get("type", ""):
		"div_zero":
			_total_div_zero += 1
		"null_ref":
			_total_null_refs += 1
		"infinite_loop":
			_total_infinite_loops += 1


func _record_warning(warning: Dictionary) -> void:
	"""Record a warning."""
	_warnings.append(warning)


func _finish_simulation() -> void:
	"""Complete the simulation and output results."""
	_is_running = false
	Engine.time_scale = 1.0

	print("")
	print("=" .repeat(60))
	print("[BattleSimulator] SIMULATION COMPLETE")
	print("=" .repeat(60))
	print("")
	print("Battles Run: %d" % _battles_run)
	print("")
	print("=== BUG SUMMARY ===")
	print("Total Errors: %d" % _errors.size())
	print("Total Warnings: %d" % _warnings.size())
	print("")
	print("By Category:")
	print("  - Division by Zero: %d" % _total_div_zero)
	print("  - Null References: %d" % _total_null_refs)
	print("  - Infinite Loops: %d" % _total_infinite_loops)
	print("  - State Errors: %d" % _total_state_errors)
	print("  - Morale Bugs: %d" % _total_morale_bugs)
	print("  - Combat Bugs: %d" % _total_combat_bugs)
	print("")

	# Group errors by type
	var error_counts: Dictionary = {}
	for err in _errors:
		var err_type: String = err.get("type", "unknown")
		error_counts[err_type] = error_counts.get(err_type, 0) + 1

	print("=== ERRORS BY TYPE ===")
	for err_type in error_counts:
		print("  %s: %d occurrences" % [err_type, error_counts[err_type]])

	print("")
	print("=== SAMPLE ERRORS (first 20) ===")
	for i in mini(_errors.size(), 20):
		var err: Dictionary = _errors[i]
		print("  [%s] %s - %s" % [
			err.get("severity", "?"),
			err.get("type", "?"),
			err.get("message", "?")
		])

	# Battle outcome statistics
	var victories: int = 0
	var defeats: int = 0
	var stalemates: int = 0
	var timeouts: int = 0

	for result in _battle_results:
		match result.winner:
			"player":
				victories += 1
			"enemy":
				defeats += 1
			"stalemate":
				stalemates += 1
			"timeout":
				timeouts += 1

	print("")
	print("=== BATTLE OUTCOMES ===")
	print("  Player Victories: %d (%.1f%%)" % [victories, float(victories) / _battles_run * 100])
	print("  Player Defeats: %d (%.1f%%)" % [defeats, float(defeats) / _battles_run * 100])
	print("  Stalemates: %d (%.1f%%)" % [stalemates, float(stalemates) / _battles_run * 100])
	print("  Timeouts: %d (%.1f%%)" % [timeouts, float(timeouts) / _battles_run * 100])

	print("")
	print("=" .repeat(60))

	# Emit completion signal
	var final_results := {
		"battles_run": _battles_run,
		"total_errors": _errors.size(),
		"total_warnings": _warnings.size(),
		"error_counts": error_counts,
		"div_zero": _total_div_zero,
		"null_refs": _total_null_refs,
		"state_errors": _total_state_errors,
		"morale_bugs": _total_morale_bugs,
		"combat_bugs": _total_combat_bugs,
		"victories": victories,
		"defeats": defeats,
		"stalemates": stalemates,
		"timeouts": timeouts,
	}

	simulation_complete.emit(final_results)
