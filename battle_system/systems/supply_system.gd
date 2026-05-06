# SupplySystem - Manages all supply wagons and resupply mechanics
# Inspired by Spring 1944's supply depot system
# Provides queries for finding nearest supply, checking in-range status
# Autoload: Access via global SupplySystem singleton

extends Node


# All registered supply wagons (untyped to avoid load-order issues)
var _wagons: Array = []

# Cache for regiment supply status (updated periodically)
var _regiment_supply_status: Dictionary = {}  # Regiment -> bool (in supply range)

# Update interval for supply status cache
var _cache_timer: float = 0.0
const CACHE_UPDATE_INTERVAL: float = 0.5  # Update every 0.5 seconds


func _ready() -> void:
	# Connect to battle signals for regiment tracking
	if BattleSignals:
		BattleSignals.regiment_dead.connect(_on_regiment_dead)


func _process(delta: float) -> void:
	_cache_timer += delta
	if _cache_timer >= CACHE_UPDATE_INTERVAL:
		_cache_timer = 0.0
		_update_supply_status_cache()


func register_wagon(wagon: Node) -> void:
	## Register a supply wagon with the system.
	if wagon not in _wagons:
		_wagons.append(wagon)


func unregister_wagon(wagon: Node) -> void:
	## Unregister a supply wagon from the system.
	_wagons.erase(wagon)


func get_all_wagons() -> Array:
	return _wagons


func get_wagons_for_faction(faction: int) -> Array:
	## Get all wagons belonging to a faction.
	var result: Array = []
	for wagon in _wagons:
		if is_instance_valid(wagon) and wagon.faction == faction:
			result.append(wagon)
	return result


func find_nearest_wagon(position: Vector3, faction: int) -> Node:
	## Find the nearest supply wagon for a given faction.
	var nearest: Node = null
	var nearest_dist: float = INF

	for wagon in _wagons:
		if not is_instance_valid(wagon):
			continue
		if wagon.faction != faction:
			continue

		var dist: float = position.distance_to(wagon.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = wagon

	return nearest


func find_nearest_wagon_in_range(position: Vector3, faction: int) -> Node:
	## Find the nearest supply wagon that the position is within range of.
	var nearest: Node = null
	var nearest_dist: float = INF

	for wagon in _wagons:
		if not is_instance_valid(wagon):
			continue
		if wagon.faction != faction:
			continue

		var dist: float = position.distance_to(wagon.global_position)
		if dist <= wagon.supply_range and dist < nearest_dist:
			nearest_dist = dist
			nearest = wagon

	return nearest


func is_in_supply_range(regiment: Regiment) -> bool:
	## Check if a regiment is within any friendly supply wagon's range.
	## Uses cached value for performance.
	if regiment in _regiment_supply_status:
		return _regiment_supply_status[regiment]

	# Calculate if not cached
	return _check_supply_status(regiment)


func _check_supply_status(regiment: Regiment) -> bool:
	## Actually check if regiment is in supply range.
	var faction: int = 0 if regiment.is_player_controlled else 1

	for wagon in _wagons:
		if not is_instance_valid(wagon):
			continue
		if wagon.faction != faction:
			continue
		if wagon.is_in_range(regiment.global_position):
			return true

	return false


func _update_supply_status_cache() -> void:
	## Update the supply status cache for all regiments.
	_regiment_supply_status.clear()

	for regiment in get_tree().get_nodes_in_group("all_regiments"):
		if regiment is Regiment and regiment.state != Regiment.State.DEAD:
			_regiment_supply_status[regiment] = _check_supply_status(regiment)


func _on_regiment_dead(regiment: Regiment) -> void:
	## Clean up when a regiment dies.
	_regiment_supply_status.erase(regiment)


func get_supply_status_description(regiment: Regiment) -> String:
	## Get a human-readable supply status for UI display.
	if not is_instance_valid(regiment):
		return "Invalid"

	if is_in_supply_range(regiment):
		return "In Supply"

	var faction: int = 0 if regiment.is_player_controlled else 1
	var nearest := find_nearest_wagon(regiment.global_position, faction)

	if nearest:
		var dist: float = regiment.global_position.distance_to(nearest.global_position)
		return "Out of Supply (%.0fm)" % dist

	return "No Supply Available"
