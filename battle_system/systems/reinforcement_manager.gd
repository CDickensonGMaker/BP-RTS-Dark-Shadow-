# Manages reinforcement waves during battle.
# Spawns additional regiments based on casualties, time, or player request.
extends Node


# Configuration
const MAX_CORE_UNITS := 8           # Maximum units in first wave
const REINFORCEMENT_WAVE_SIZE := 3  # Units per reinforcement wave
const TIME_TRIGGER_SECONDS := 90.0  # Seconds between time-based waves
const CASUALTY_TRIGGER := 0.4       # Spawn when core strength drops to 40%
const MORALE_COST_MANUAL := 10.0    # Morale penalty for manual reinforcement call

# State
var is_active := false
var battle_setup: Resource = null  # BattleSetupData

var core_regiments: Array = []          # Currently deployed
var reinforcement_queue: Array = []     # Waiting to deploy
var all_regiments: Array = []           # Full roster for reference

var current_wave := 0
var time_since_last_wave := 0.0
var original_core_strength := 0
var reinforcements_spawned := 0

# Entry points on battlefield
var entry_points: Array[Vector3] = []
var friendly_edge_direction := Vector3.BACK  # Direction to friendly map edge


func _ready() -> void:
	set_process(false)

	# Connect to battle signals
	if BattleSignals:
		BattleSignals.battle_started.connect(_on_battle_started)
		BattleSignals.battle_ended.connect(_on_battle_ended)
		BattleSignals.regiment_dead.connect(_on_regiment_dead)
		BattleSignals.regiment_routing.connect(_on_regiment_routing)


func _process(delta: float) -> void:
	if not is_active:
		return

	# Time-based reinforcement check
	time_since_last_wave += delta
	if time_since_last_wave >= TIME_TRIGGER_SECONDS:
		if _can_spawn_reinforcements():
			_try_time_based_reinforcement()


# =============================================================================
# Setup
# =============================================================================

func setup_from_campaign(setup_data: Resource) -> void:
	battle_setup = setup_data

	core_regiments = setup_data.core_regiments.duplicate()
	reinforcement_queue = setup_data.reinforcement_regiments.duplicate()
	all_regiments = core_regiments + reinforcement_queue

	original_core_strength = _calculate_strength(core_regiments)
	current_wave = 0
	reinforcements_spawned = 0
	time_since_last_wave = 0.0


func setup_from_battalion(battalion: Resource) -> void:
	# Alternative setup directly from battalion data
	var all_units: Array = battalion.regiments.duplicate()

	core_regiments.clear()
	reinforcement_queue.clear()

	for i in range(all_units.size()):
		if i < MAX_CORE_UNITS:
			core_regiments.append(all_units[i])
		else:
			reinforcement_queue.append(all_units[i])

	all_regiments = all_units
	original_core_strength = _calculate_strength(core_regiments)
	current_wave = 0
	reinforcements_spawned = 0
	time_since_last_wave = 0.0


func set_entry_points(points: Array[Vector3], friendly_direction: Vector3) -> void:
	entry_points = points
	friendly_edge_direction = friendly_direction


func get_core_regiments() -> Array:
	return core_regiments


func get_reinforcement_queue() -> Array:
	return reinforcement_queue


# =============================================================================
# Reinforcement Triggers
# =============================================================================

func _on_battle_started() -> void:
	is_active = true
	set_process(true)
	time_since_last_wave = 0.0

	# Emit initial state
	if reinforcement_queue.size() > 0:
		BattleSignals.emit_signal("reinforcements_available", 1, reinforcement_queue.size())


func _on_battle_ended(_result: Dictionary) -> void:
	is_active = false
	set_process(false)


func _on_regiment_dead(regiment) -> void:
	# Check if this was a core regiment
	var idx: int = core_regiments.find(regiment)
	if idx >= 0:
		core_regiments.remove_at(idx)
		_check_casualty_trigger()


func _on_regiment_routing(_regiment) -> void:
	# Routing units count as 50% strength loss for trigger calculation
	_check_casualty_trigger()


func _check_casualty_trigger() -> void:
	if not _can_spawn_reinforcements():
		return

	var current_strength := _calculate_effective_strength(core_regiments)
	var strength_ratio := float(current_strength) / original_core_strength

	if strength_ratio <= CASUALTY_TRIGGER:
		_spawn_reinforcement_wave("casualty")


func _try_time_based_reinforcement() -> void:
	time_since_last_wave = 0.0

	# Only spawn if there's active combat
	if _is_combat_active():
		_spawn_reinforcement_wave("time")


func request_manual_reinforcement() -> bool:
	# Player-triggered reinforcement (costs morale)
	if not _can_spawn_reinforcements():
		return false

	# Apply morale penalty to all core units
	for regiment in core_regiments:
		if regiment.has_method("apply_morale_modifier"):
			regiment.apply_morale_modifier(-MORALE_COST_MANUAL, "forced_march")

	_spawn_reinforcement_wave("manual")
	return true


# =============================================================================
# Spawning
# =============================================================================

func _can_spawn_reinforcements() -> bool:
	return is_active and reinforcement_queue.size() > 0


func _spawn_reinforcement_wave(trigger_type: String) -> void:
	if reinforcement_queue.is_empty():
		return

	current_wave += 1
	var wave_size := mini(REINFORCEMENT_WAVE_SIZE, reinforcement_queue.size())
	var spawned_regiments: Array = []

	for i in range(wave_size):
		var regiment: Resource = reinforcement_queue.pop_front()
		spawned_regiments.append(regiment)
		reinforcements_spawned += 1

	# Spawn at entry points
	_spawn_regiments_at_entry(spawned_regiments)

	# Add to core regiments (now deployed)
	core_regiments.append_array(spawned_regiments)

	# Emit signals
	BattleSignals.emit_signal("reinforcements_arrived", current_wave)

	# Notify if more reinforcements available
	if reinforcement_queue.size() > 0:
		BattleSignals.emit_signal("reinforcements_available", current_wave + 1, reinforcement_queue.size())

	print("[ReinforcementManager] Wave %d spawned (%s trigger): %d units" % [current_wave, trigger_type, wave_size])


func _spawn_regiments_at_entry(regiments: Array) -> void:
	if entry_points.is_empty():
		_generate_default_entry_points()

	for i in range(regiments.size()):
		var regiment: Resource = regiments[i]
		var entry_point: Vector3 = entry_points[i % entry_points.size()]

		# Offset each regiment slightly
		var offset := Vector3(randf_range(-10, 10), 0, randf_range(-5, 5))
		var spawn_pos := entry_point + offset

		_spawn_regiment_at_position(regiment, spawn_pos)


func _spawn_regiment_at_position(regiment_data: Resource, position: Vector3) -> void:
	# This would interface with BattleManager to spawn the actual regiment node
	# For now, emit signal that BattleManager should handle

	var spawn_info := {
		"regiment_data": regiment_data,
		"position": position,
		"facing": -friendly_edge_direction,  # Face toward enemy
		"is_reinforcement": true,
		"wave": current_wave
	}

	# BattleManager should listen for this and spawn the regiment
	BattleSignals.emit_signal("spawn_reinforcement", spawn_info)


func _generate_default_entry_points() -> void:
	# Generate entry points along friendly edge
	# This is a fallback - should be set properly by BattleManager
	var base_z := 50.0  # Friendly edge
	entry_points = [
		Vector3(-30, 0, base_z),
		Vector3(0, 0, base_z),
		Vector3(30, 0, base_z)
	]


# =============================================================================
# Utility
# =============================================================================

func _calculate_strength(regiments: Array) -> int:
	var total := 0
	for regiment in regiments:
		if regiment.get("current_soldiers"):
			total += regiment.current_soldiers
		elif regiment.has_meta("current_soldiers"):
			total += regiment.get_meta("current_soldiers")
	return total


func _calculate_effective_strength(regiments: Array) -> int:
	# Accounts for routing units at 50% value
	var total := 0
	for regiment in regiments:
		var soldiers: int
		if regiment.get("current_soldiers"):
			soldiers = regiment.current_soldiers
		elif regiment.has_meta("current_soldiers"):
			soldiers = regiment.get_meta("current_soldiers")
		else:
			soldiers = 0

		# Check if routing (would need actual regiment node reference)
		var is_routing := false
		if regiment.has_method("is_routing"):
			is_routing = regiment.is_routing()

		if is_routing:
			total += soldiers / 2
		else:
			total += soldiers

	return total


func _is_combat_active() -> bool:
	# Check if there's active combat happening
	# This would check with CombatManager
	if CombatManager and CombatManager.has_method("has_active_combat"):
		return CombatManager.has_active_combat()
	return true  # Assume combat is active


# =============================================================================
# Queries
# =============================================================================

func get_reinforcement_count() -> int:
	return reinforcement_queue.size()


func get_total_reinforcement_strength() -> int:
	return _calculate_strength(reinforcement_queue)


func get_waves_remaining() -> int:
	return ceili(float(reinforcement_queue.size()) / REINFORCEMENT_WAVE_SIZE)


func get_current_wave() -> int:
	return current_wave


func get_status() -> Dictionary:
	return {
		"is_active": is_active,
		"current_wave": current_wave,
		"reinforcements_spawned": reinforcements_spawned,
		"reinforcements_remaining": reinforcement_queue.size(),
		"waves_remaining": get_waves_remaining(),
		"core_strength": _calculate_strength(core_regiments),
		"original_core_strength": original_core_strength,
		"time_until_next": TIME_TRIGGER_SECONDS - time_since_last_wave
	}
