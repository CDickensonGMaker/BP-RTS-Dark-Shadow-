class_name SpatialHash
extends RefCounted

## O(1) spatial queries for soldiers and regiments.
## Uses a grid of cells to quickly find nearby entities.
##
## Usage:
##   var hash = SpatialHash.new(20.0)  # 20-unit cells
##   hash.register(soldier, position, SpatialHash.EntityType.SOLDIER, faction)
##   var nearby = hash.query_radius(position, 15.0, faction)

# =============================================================================
# TYPES
# =============================================================================

enum EntityType {
	ALL = -1,  # Filter value meaning "match any type"
	SOLDIER,
	REGIMENT,
	GENERAL,
}

class EntityData:
	var entity: Node
	var entity_type: EntityType
	var faction: int
	var position: Vector3
	var cell_key: Vector2i

	func _init(p_entity: Node, p_type: EntityType, p_faction: int, p_pos: Vector3) -> void:
		entity = p_entity
		entity_type = p_type
		faction = p_faction
		position = p_pos
		cell_key = Vector2i.ZERO

# =============================================================================
# PROPERTIES
# =============================================================================

var cell_size: float = 20.0

# Grid storage: Vector2i -> Array[EntityData]
var _cells: Dictionary = {}

# Entity -> EntityData lookup for fast updates
var _entity_map: Dictionary = {}

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_cell_size: float = 20.0) -> void:
	cell_size = p_cell_size

# =============================================================================
# REGISTRATION
# =============================================================================

func register(entity: Node, position: Vector3, entity_type: EntityType, faction: int) -> void:
	## Add an entity to the hash.
	if _entity_map.has(entity):
		# Already registered, just update
		update_position(entity, position)
		return

	var data: EntityData = EntityData.new(entity, entity_type, faction, position)
	data.cell_key = _get_cell_key(position)

	_entity_map[entity] = data
	_add_to_cell(data.cell_key, data)


func unregister(entity: Node) -> void:
	## Remove an entity from the hash.
	if not _entity_map.has(entity):
		return

	var data: EntityData = _entity_map[entity]
	_remove_from_cell(data.cell_key, data)
	_entity_map.erase(entity)


func update_position(entity: Node, new_position: Vector3) -> void:
	## Update an entity's position. Only moves between cells if necessary.
	if not _entity_map.has(entity):
		return

	var data: EntityData = _entity_map[entity]
	var new_cell_key: Vector2i = _get_cell_key(new_position)

	# Only update cell if actually changed
	if new_cell_key != data.cell_key:
		_remove_from_cell(data.cell_key, data)
		data.cell_key = new_cell_key
		_add_to_cell(new_cell_key, data)

	data.position = new_position

# =============================================================================
# QUERIES
# =============================================================================

func query_radius(center: Vector3, radius: float, faction_filter: int = -1, type_filter: EntityType = EntityType.ALL) -> Array[Node]:
	## Find all entities within radius of center.
	## faction_filter: -1 = all, 0 = player, 1 = enemy
	## type_filter: -1 = all types
	var results: Array[Node] = []
	var radius_sq: float = radius * radius

	# Calculate cells to check
	var min_cell: Vector2i = _get_cell_key(center - Vector3(radius, 0, radius))
	var max_cell: Vector2i = _get_cell_key(center + Vector3(radius, 0, radius))

	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell_key: Vector2i = Vector2i(x, y)
			if not _cells.has(cell_key):
				continue

			var cell: Array = _cells[cell_key]
			for data: EntityData in cell:
				# Filter by faction
				if faction_filter >= 0 and data.faction != faction_filter:
					continue

				# Filter by type
				if type_filter >= 0 and data.entity_type != type_filter:
					continue

				# Distance check (2D, ignoring Y)
				var dx: float = data.position.x - center.x
				var dz: float = data.position.z - center.z
				var dist_sq: float = dx * dx + dz * dz

				if dist_sq <= radius_sq:
					if is_instance_valid(data.entity):
						results.append(data.entity)

	return results


func query_radius_enemies(center: Vector3, radius: float, my_faction: int) -> Array[Node]:
	## Find enemies within radius.
	var enemy_faction: int = 1 if my_faction == 0 else 0
	return query_radius(center, radius, enemy_faction)


func query_radius_allies(center: Vector3, radius: float, my_faction: int) -> Array[Node]:
	## Find allies within radius.
	return query_radius(center, radius, my_faction)


func query_nearest(center: Vector3, max_radius: float, faction_filter: int = -1, type_filter: EntityType = EntityType.ALL) -> Node:
	## Find the nearest entity within max_radius.
	var candidates: Array[Node] = query_radius(center, max_radius, faction_filter, type_filter)

	var nearest: Node = null
	var nearest_dist_sq: float = INF

	for entity in candidates:
		if not is_instance_valid(entity):
			continue
		var dist_sq: float = center.distance_squared_to(entity.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = entity

	return nearest


func query_nearest_enemy(center: Vector3, max_radius: float, my_faction: int) -> Node:
	## Find nearest enemy within radius.
	var enemy_faction: int = 1 if my_faction == 0 else 0
	return query_nearest(center, max_radius, enemy_faction)


func query_cell(cell_key: Vector2i) -> Array:
	## Get all entities in a specific cell.
	if _cells.has(cell_key):
		return _cells[cell_key].duplicate()
	return []


func query_regiments_in_radius(center: Vector3, radius: float, faction_filter: int = -1) -> Array[Node]:
	## Find regiments within radius.
	return query_radius(center, radius, faction_filter, EntityType.REGIMENT)


func query_soldiers_in_radius(center: Vector3, radius: float, faction_filter: int = -1) -> Array[Node]:
	## Find soldiers within radius.
	return query_radius(center, radius, faction_filter, EntityType.SOLDIER)

# =============================================================================
# COUNT QUERIES
# =============================================================================

func count_in_radius(center: Vector3, radius: float, faction_filter: int = -1) -> int:
	## Count entities in radius without allocating array.
	var count: int = 0
	var radius_sq: float = radius * radius

	var min_cell: Vector2i = _get_cell_key(center - Vector3(radius, 0, radius))
	var max_cell: Vector2i = _get_cell_key(center + Vector3(radius, 0, radius))

	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell_key: Vector2i = Vector2i(x, y)
			if not _cells.has(cell_key):
				continue

			var cell: Array = _cells[cell_key]
			for data: EntityData in cell:
				if faction_filter >= 0 and data.faction != faction_filter:
					continue

				var dx: float = data.position.x - center.x
				var dz: float = data.position.z - center.z
				var dist_sq: float = dx * dx + dz * dz

				if dist_sq <= radius_sq:
					if is_instance_valid(data.entity):
						count += 1

	return count


func count_enemies_in_radius(center: Vector3, radius: float, my_faction: int) -> int:
	## Count enemies in radius.
	var enemy_faction: int = 1 if my_faction == 0 else 0
	return count_in_radius(center, radius, enemy_faction)


func count_allies_in_radius(center: Vector3, radius: float, my_faction: int) -> int:
	## Count allies in radius.
	return count_in_radius(center, radius, my_faction)

# =============================================================================
# INTERNAL
# =============================================================================

func _get_cell_key(position: Vector3) -> Vector2i:
	## Convert world position to cell key.
	return Vector2i(
		floori(position.x / cell_size),
		floori(position.z / cell_size)
	)


func _add_to_cell(cell_key: Vector2i, data: EntityData) -> void:
	## Add entity to a cell.
	if not _cells.has(cell_key):
		_cells[cell_key] = []
	_cells[cell_key].append(data)


func _remove_from_cell(cell_key: Vector2i, data: EntityData) -> void:
	## Remove entity from a cell.
	if not _cells.has(cell_key):
		return
	var cell: Array = _cells[cell_key]
	var idx: int = cell.find(data)
	if idx >= 0:
		cell.remove_at(idx)
	# Clean up empty cells
	if cell.is_empty():
		_cells.erase(cell_key)

# =============================================================================
# UTILITY
# =============================================================================

func clear() -> void:
	## Remove all entities.
	_cells.clear()
	_entity_map.clear()


func get_entity_count() -> int:
	## Returns total number of registered entities.
	return _entity_map.size()


func get_cell_count() -> int:
	## Returns number of active cells.
	return _cells.size()


func get_entity_data(entity: Node) -> EntityData:
	## Get stored data for an entity.
	return _entity_map.get(entity, null)


func get_debug_info() -> Dictionary:
	## Returns debug information.
	return {
		"entity_count": _entity_map.size(),
		"cell_count": _cells.size(),
		"cell_size": cell_size,
	}
