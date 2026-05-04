extends Node

## AIAutoload - Central coordinator for all AI systems.
## Manages tick rates, spatial queries, and coordinates General/Commander AI.
##
## Add to project.godot autoload:
##   AIAutoload="*res://battle_system/ai/ai_autoload.gd"

# =============================================================================
# SIGNALS
# =============================================================================

signal ai_tick_general()          # 3s strategic tick
signal ai_tick_commander()        # 0.5s tactical tick
signal ai_tick_fast()             # 0.1s fast tick for urgent responses

# =============================================================================
# CONSTANTS
# =============================================================================

const GENERAL_TICK_RATE: float = 3.0
const COMMANDER_TICK_RATE: float = 0.5
const FAST_TICK_RATE: float = 0.1
const SPATIAL_CELL_SIZE: float = 20.0

# =============================================================================
# PROPERTIES
# =============================================================================

var spatial_hash: SpatialHash
var threat_heatmap: ThreatHeatmap  # spring1944-style threat assessment
var is_ai_enabled: bool = true

# General AI instances (one per faction)
var _general_ais: Dictionary = {}  # faction_id -> GeneralAI

# Commander AI instances
var _commander_ais: Array = []

# Tick accumulators
var _general_tick_acc: float = 0.0
var _commander_tick_acc: float = 0.0
var _fast_tick_acc: float = 0.0

# Staggering for commander ticks (process 1/4 per tick)
var _commander_tick_index: int = 0
const COMMANDER_STAGGER_GROUPS: int = 4

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	spatial_hash = SpatialHash.new(SPATIAL_CELL_SIZE)
	threat_heatmap = ThreatHeatmap.new()

	# Connect to battle signals for entity tracking
	BattleSignals.regiment_dead.connect(_on_regiment_dead)


func _process(delta: float) -> void:
	if not is_ai_enabled:
		return

	# Fast tick (0.1s)
	_fast_tick_acc += delta
	if _fast_tick_acc >= FAST_TICK_RATE:
		_fast_tick_acc -= FAST_TICK_RATE
		ai_tick_fast.emit()

	# Commander tick (0.5s) with staggering
	_commander_tick_acc += delta
	if _commander_tick_acc >= COMMANDER_TICK_RATE:
		_commander_tick_acc -= COMMANDER_TICK_RATE
		var start := Time.get_ticks_usec()
		_tick_commanders_staggered()
		# Update threat heatmap from all regiments
		if threat_heatmap:
			threat_heatmap.decay_threats(COMMANDER_TICK_RATE)
			threat_heatmap.update_from_regiments(get_all_regiments())
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		if elapsed > 16.0:
			print("[PERF_WARN] Commander tick took %.1fms" % elapsed)
		ai_tick_commander.emit()

	# General tick (3s)
	_general_tick_acc += delta
	if _general_tick_acc >= GENERAL_TICK_RATE:
		_general_tick_acc -= GENERAL_TICK_RATE
		var start := Time.get_ticks_usec()
		_tick_generals()
		var elapsed := (Time.get_ticks_usec() - start) / 1000.0
		if elapsed > 16.0:
			print("[PERF_WARN] General tick took %.1fms" % elapsed)
		ai_tick_general.emit()

# =============================================================================
# GENERAL AI MANAGEMENT
# =============================================================================

func register_general_ai(general_ai, faction: int) -> void:
	## Register a GeneralAI instance for a faction.
	_general_ais[faction] = general_ai


func unregister_general_ai(faction: int) -> void:
	## Remove a GeneralAI instance.
	_general_ais.erase(faction)


func get_general_ai(faction: int):
	## Get the GeneralAI for a faction.
	return _general_ais.get(faction)


func _tick_generals() -> void:
	## Tick all registered GeneralAIs.
	for faction in _general_ais:
		var general_ai = _general_ais[faction]
		if general_ai and general_ai.has_method("tick"):
			var start_time := Time.get_ticks_usec()
			general_ai.tick()
			var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
			if elapsed > 16.0:  # More than 16ms = frame drop
				print("[PERF_WARN] General AI faction %d tick took %.1fms" % [faction, elapsed])

# =============================================================================
# COMMANDER AI MANAGEMENT
# =============================================================================

func register_commander_ai(commander_ai) -> void:
	## Register a CommanderAI instance.
	if commander_ai not in _commander_ais:
		_commander_ais.append(commander_ai)


func unregister_commander_ai(commander_ai) -> void:
	## Remove a CommanderAI instance.
	var idx: int = _commander_ais.find(commander_ai)
	if idx >= 0:
		_commander_ais.remove_at(idx)


func _tick_commanders_staggered() -> void:
	## Tick 1/4 of commanders per tick for load distribution.
	if _commander_ais.is_empty():
		return

	var group_size: int = ceili(float(_commander_ais.size()) / float(COMMANDER_STAGGER_GROUPS))
	var start_idx: int = _commander_tick_index * group_size
	var end_idx: int = mini(start_idx + group_size, _commander_ais.size())

	for i in range(start_idx, end_idx):
		var commander_ai = _commander_ais[i]
		if commander_ai and commander_ai.has_method("tick"):
			var start_time := Time.get_ticks_usec()
			commander_ai.tick()
			var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
			if elapsed > 16.0:  # More than 16ms = frame drop
				var reg_name: String = commander_ai.regiment.name if commander_ai.regiment else "unknown"
				print("[PERF_WARN] Commander %s tick took %.1fms" % [reg_name, elapsed])

	_commander_tick_index = (_commander_tick_index + 1) % COMMANDER_STAGGER_GROUPS

# =============================================================================
# SPATIAL QUERIES (Convenience wrappers)
# =============================================================================

func register_entity(entity: Node, position: Vector3, entity_type: SpatialHash.EntityType, faction: int) -> void:
	## Register an entity in the spatial hash.
	spatial_hash.register(entity, position, entity_type, faction)


func unregister_entity(entity: Node) -> void:
	## Remove an entity from the spatial hash.
	spatial_hash.unregister(entity)


func update_entity_position(entity: Node, position: Vector3) -> void:
	## Update an entity's position in the hash.
	spatial_hash.update_position(entity, position)


func query_radius(center: Vector3, radius: float, faction_filter: int = -1) -> Array[Node]:
	## Find entities within radius.
	return spatial_hash.query_radius(center, radius, faction_filter)


func query_enemies(center: Vector3, radius: float, my_faction: int) -> Array[Node]:
	## Find enemies within radius.
	return spatial_hash.query_radius_enemies(center, radius, my_faction)


func query_allies(center: Vector3, radius: float, my_faction: int) -> Array[Node]:
	## Find allies within radius.
	return spatial_hash.query_radius_allies(center, radius, my_faction)


func query_nearest_enemy(center: Vector3, radius: float, my_faction: int) -> Node:
	## Find nearest enemy.
	return spatial_hash.query_nearest_enemy(center, radius, my_faction)


func query_regiments(center: Vector3, radius: float, faction_filter: int = -1) -> Array[Node]:
	## Find regiments within radius.
	return spatial_hash.query_regiments_in_radius(center, radius, faction_filter)


func count_enemies(center: Vector3, radius: float, my_faction: int) -> int:
	## Count enemies in radius.
	return spatial_hash.count_enemies_in_radius(center, radius, my_faction)


func count_allies(center: Vector3, radius: float, my_faction: int) -> int:
	## Count allies in radius.
	return spatial_hash.count_allies_in_radius(center, radius, my_faction)

# =============================================================================
# REGIMENT TRACKING
# =============================================================================

func register_regiment(regiment: Node) -> void:
	## Register a regiment for AI tracking.
	var faction: int = 0 if regiment.is_player_controlled else 1
	spatial_hash.register(regiment, regiment.global_position, SpatialHash.EntityType.REGIMENT, faction)


func _on_regiment_dead(regiment: Node) -> void:
	## Clean up when a regiment dies.
	spatial_hash.unregister(regiment)

# =============================================================================
# AI CONTROL
# =============================================================================

func enable_ai(enabled: bool) -> void:
	## Enable or disable all AI processing.
	is_ai_enabled = enabled


func pause_ai() -> void:
	## Pause AI processing.
	is_ai_enabled = false


func resume_ai() -> void:
	## Resume AI processing.
	is_ai_enabled = true

# =============================================================================
# UTILITY
# =============================================================================

func get_all_regiments(faction_filter: int = -1) -> Array:
	## Get all regiments, optionally filtered by faction.
	var group: String = "all_regiments"
	if faction_filter == 0:
		group = "player_regiments"
	elif faction_filter == 1:
		group = "enemy_regiments"

	return get_tree().get_nodes_in_group(group)


func get_enemy_regiments(my_faction: int) -> Array:
	## Get all enemy regiments.
	var enemy_faction: int = 1 if my_faction == 0 else 0
	return get_all_regiments(enemy_faction)


func get_friendly_regiments(my_faction: int) -> Array:
	## Get all friendly regiments.
	return get_all_regiments(my_faction)


func get_debug_info() -> Dictionary:
	## Returns debug information about the AI system.
	return {
		"is_enabled": is_ai_enabled,
		"general_ais": _general_ais.size(),
		"commander_ais": _commander_ais.size(),
		"spatial_hash": spatial_hash.get_debug_info() if spatial_hash else {},
		"threat_heatmap": threat_heatmap.get_debug_info() if threat_heatmap else {},
	}


# =============================================================================
# THREAT HEATMAP QUERIES
# =============================================================================

func get_threat_at(position: Vector3, my_faction: int) -> float:
	## Get enemy threat level at a position.
	if threat_heatmap:
		return threat_heatmap.get_threat_at(position, my_faction)
	return 0.0


func should_retreat(position: Vector3, my_faction: int, my_firepower: float, hp_ratio: float) -> bool:
	## Check if a unit should retreat based on threat.
	if threat_heatmap:
		return threat_heatmap.should_retreat(position, my_faction, my_firepower, hp_ratio)
	return false


func get_safest_retreat_position(position: Vector3, my_faction: int) -> Vector3:
	## Get safest nearby position to retreat to.
	if threat_heatmap:
		return threat_heatmap.get_safest_retreat_position(position, my_faction)
	return position + Vector3.BACK * 30.0  # Fallback


func get_flanking_direction(position: Vector3, target_position: Vector3, my_faction: int) -> Vector3:
	## Get best direction for flanking maneuver.
	if threat_heatmap:
		return threat_heatmap.get_flanking_direction(position, target_position, my_faction)
	return Vector3.RIGHT  # Fallback
