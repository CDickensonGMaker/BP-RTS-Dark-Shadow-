## TerrainHelper - Centralized terrain access (Phase 6.4 deduplication)
## Provides static methods for finding and querying terrain.
## Used by Regiment, RegimentLeader, SpriteFormation, SoldierFormation, etc.
## Works with any terrain that has get_height_at() method (DaggerfallTerrain, BlenderMapTerrain, etc.)

class_name TerrainHelper
extends RefCounted


## Cached terrain reference (cleared on scene change)
## Using Node3D to support any terrain type with get_height_at() method
static var _cached_terrain: Node3D = null
static var _cache_frame: int = -1


static func get_terrain(tree: SceneTree) -> Node3D:
	## Get the active terrain, using cache when possible.
	## Returns null if no terrain found.
	## Works with any Node3D that has get_height_at() method.

	# Return cached terrain if still valid and same frame
	var current_frame: int = Engine.get_process_frames()
	if _cached_terrain and is_instance_valid(_cached_terrain) and _cache_frame == current_frame:
		return _cached_terrain

	# Search for terrain in group
	var terrains = tree.get_nodes_in_group("terrain")
	if terrains.size() > 0:
		# Find first terrain with get_height_at method
		for terrain in terrains:
			if terrain.has_method("get_height_at"):
				_cached_terrain = terrain as Node3D
				_cache_frame = current_frame
				return _cached_terrain

	# Fallback: search through regiment parents for DaggerfallTerrain
	for node in tree.get_nodes_in_group("all_regiments"):
		var parent = node.get_parent()
		while parent:
			if parent.has_method("get_height_at"):
				_cached_terrain = parent as Node3D
				_cache_frame = current_frame
				return _cached_terrain
			for child in parent.get_children():
				if child.has_method("get_height_at"):
					_cached_terrain = child as Node3D
					_cache_frame = current_frame
					return _cached_terrain
			parent = parent.get_parent()

	return null


static func get_height_at(tree: SceneTree, pos: Vector3) -> float:
	## Get terrain height at a world position.
	## Returns 0.0 if no terrain found.
	var terrain := get_terrain(tree)
	if terrain:
		return terrain.get_height_at(pos)
	return 0.0


static func get_slope_at(tree: SceneTree, pos: Vector3, sample_dist: float = 1.0) -> float:
	## Get terrain slope angle at a position (in degrees).
	## Returns 0.0 if no terrain found.
	var terrain := get_terrain(tree)
	if not terrain:
		return 0.0

	var h_center: float = terrain.get_height_at(pos)
	var h_forward: float = terrain.get_height_at(pos + Vector3(0, 0, sample_dist))
	var h_right: float = terrain.get_height_at(pos + Vector3(sample_dist, 0, 0))

	var slope_z: float = (h_forward - h_center) / sample_dist
	var slope_x: float = (h_right - h_center) / sample_dist

	var max_slope: float = maxf(absf(slope_z), absf(slope_x))
	return rad_to_deg(atan(max_slope))


static func snap_to_terrain(tree: SceneTree, pos: Vector3) -> Vector3:
	## Snap a position to terrain height.
	## Returns original position if no terrain found.
	var terrain := get_terrain(tree)
	if terrain:
		pos.y = terrain.get_height_at(pos)
	return pos


static func clear_cache() -> void:
	## Clear the terrain cache (call on scene change).
	_cached_terrain = null
	_cache_frame = -1
