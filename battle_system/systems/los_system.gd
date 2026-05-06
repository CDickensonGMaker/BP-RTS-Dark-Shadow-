# LOSSystem - Line of Sight and Detection Radius System
# Inspired by Spring 1944's visibility mechanics
# Manages unit detection ranges based on type, movement state, and terrain

extends Node


## Default detection ranges by unit type (in world units)
## Still = not moving, Moving = actively moving
const DETECTION_RANGES := {
	"stealth":    { "still": 10.0,  "moving": 25.0  },  # Assassins, rogues
	"infantry":   { "still": 40.0,  "moving": 80.0  },  # Archers, footmen
	"heavy":      { "still": 50.0,  "moving": 100.0 },  # Heavy infantry
	"cavalry":    { "still": 60.0,  "moving": 150.0 },  # Knights, riders
	"large":      { "still": 80.0,  "moving": 200.0 },  # Giants, siege, dragons
	"structure":  { "still": 200.0, "moving": 200.0 },  # Towers, buildings
}

## Scout bonus multiplier (scouts see farther)
const SCOUT_MULTIPLIER: float = 1.5

## Cover zone concealment multiplier (units in cover harder to spot)
const COVER_MULTIPLIER: float = 0.4  # 40% of normal detection

# Visibility state cache
var _visibility_cache: Dictionary = {}  # {Regiment: {Regiment: bool}}
var _detection_cache: Dictionary = {}   # {Regiment: detection_radius}

# Update intervals
var _cache_timer: float = 0.0
const CACHE_UPDATE_INTERVAL: float = 0.5  # Update every 0.5 seconds

# Cover zones (map-defined areas providing concealment)
var _cover_zones: Array[Dictionary] = []  # [{center: Vector3, radius: float}]


func _ready() -> void:
	if BattleSignals:
		BattleSignals.regiment_dead.connect(_on_regiment_dead)


func _process(delta: float) -> void:
	# Don't process during deployment phase
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		return

	_cache_timer += delta
	if _cache_timer >= CACHE_UPDATE_INTERVAL:
		_cache_timer = 0.0
		_update_detection_cache()


# --- PUBLIC API ---

func get_detection_radius(regiment: Regiment) -> float:
	## Get the distance at which this regiment can be detected by enemies.
	## Based on unit type, movement state, and cover.
	if regiment in _detection_cache:
		return _detection_cache[regiment]

	return _calculate_detection_radius(regiment)


func can_see(observer: Regiment, target: Regiment) -> bool:
	## Check if observer can see target.
	## Returns true if target is within observer's sight range.
	if not is_instance_valid(observer) or not is_instance_valid(target):
		return false

	# Same team always visible
	if observer.is_player_controlled == target.is_player_controlled:
		return true

	# Get target's detection radius (how visible they are)
	var target_detection := get_detection_radius(target)

	# Get observer's sight range (how far they can see)
	var observer_sight := _get_sight_range(observer)

	# Distance between units
	var distance := observer.global_position.distance_to(target.global_position)

	# Can see if within the lesser of sight range and detection radius
	return distance <= minf(observer_sight, target_detection)


func is_visible_to_team(regiment: Regiment, player_team: bool) -> bool:
	## Check if regiment is visible to the player's team.
	## Used for fog of war / visibility rendering.
	if not is_instance_valid(regiment):
		return false

	# Own team always visible
	if regiment.is_player_controlled == player_team:
		return true

	# Check if any friendly unit can see this regiment
	var group_name := "player_regiments" if player_team else "enemy_regiments"
	for observer in get_tree().get_nodes_in_group(group_name):
		if observer is Regiment and can_see(observer, regiment):
			return true

	return false


func get_units_in_sight(observer: Regiment) -> Array[Regiment]:
	## Get all enemy units visible to observer.
	var result: Array[Regiment] = []
	var enemy_group := "enemy_regiments" if observer.is_player_controlled else "player_regiments"

	for target in get_tree().get_nodes_in_group(enemy_group):
		if target is Regiment and can_see(observer, target):
			result.append(target)

	return result


func add_cover_zone(center: Vector3, radius: float) -> void:
	## Add a cover zone to the map.
	_cover_zones.append({"center": center, "radius": radius})


func clear_cover_zones() -> void:
	## Clear all cover zones.
	_cover_zones.clear()


func is_in_cover(position: Vector3) -> bool:
	## Check if position is within any cover zone.
	for zone in _cover_zones:
		var dist := position.distance_to(zone["center"])
		if dist <= zone["radius"]:
			return true
	return false


# --- PRIVATE METHODS ---

func _calculate_detection_radius(regiment: Regiment) -> float:
	## Calculate how far away this unit can be detected.
	var unit_type := _get_unit_type_category(regiment)
	var ranges: Dictionary = DETECTION_RANGES.get(unit_type, DETECTION_RANGES["infantry"])

	# Check if moving
	var is_moving: bool = regiment.state == Regiment.State.MARCHING or \
						  regiment.state == Regiment.State.ROUTING

	var base_radius: float = ranges["moving"] if is_moving else ranges["still"]

	# Apply cover modifier if in cover zone
	if is_in_cover(regiment.global_position):
		base_radius *= COVER_MULTIPLIER

	return base_radius


func _get_sight_range(regiment: Regiment) -> float:
	## Get how far this unit can see.
	## Scouts/rangers get bonus range.
	var base_range: float = 100.0  # Base sight range

	# Check if unit has scout ability (via custom params or data)
	if regiment.data and regiment.data.has_meta("is_scout"):
		base_range *= SCOUT_MULTIPLIER

	# Ranged units see farther (up to their weapon range)
	if regiment.data and regiment.data.range_distance > 0:
		base_range = maxf(base_range, regiment.data.range_distance * 1.2)

	return base_range


func _get_unit_type_category(regiment: Regiment) -> String:
	## Map regiment to detection category.
	if not regiment.data:
		return "infantry"

	match regiment.data.unit_type:
		UnitType.Type.INFANTRY:
			# Heavy infantry (high defense) or light
			if regiment.data.defense >= 12:
				return "heavy"
			return "infantry"
		UnitType.Type.CAVALRY:
			return "cavalry"
		UnitType.Type.RANGED:
			# Ranged could be stealthy scouts
			if regiment.data.has_meta("is_scout"):
				return "stealth"
			return "infantry"
		UnitType.Type.ARTILLERY:
			return "large"
		UnitType.Type.GENERAL:
			return "cavalry"  # Generals on horseback
		_:
			return "infantry"


func _update_detection_cache() -> void:
	## Update detection radius cache for all regiments.
	_detection_cache.clear()

	for regiment in get_tree().get_nodes_in_group("all_regiments"):
		if regiment is Regiment and regiment.state != Regiment.State.DEAD:
			_detection_cache[regiment] = _calculate_detection_radius(regiment)


func _on_regiment_dead(regiment: Regiment) -> void:
	_detection_cache.erase(regiment)
	_visibility_cache.erase(regiment)


# --- DEBUG ---

func debug_print_visibility() -> void:
	## Print visibility matrix for debugging.
	print("=== LOS System Visibility ===")
	for observer in get_tree().get_nodes_in_group("player_regiments"):
		if observer is Regiment:
			var visible_enemies := get_units_in_sight(observer)
			print("  %s sees %d enemies" % [observer.name, visible_enemies.size()])
