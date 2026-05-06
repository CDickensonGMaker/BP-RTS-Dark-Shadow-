## TerrainHelper - Centralized terrain access (Phase 6.4 deduplication)
## Provides static methods for finding and querying terrain.
## Used by Regiment, RegimentLeader, SpriteFormation, SoldierFormation, etc.

class_name TerrainHelper
extends RefCounted


## Cached terrain reference (cleared on scene change)
static var _cached_terrain: DaggerfallTerrain = null
static var _cache_frame: int = -1


static func get_terrain(tree: SceneTree) -> DaggerfallTerrain:
	## Get the active terrain, using cache when possible.
	## Returns null if no terrain found.

	# Return cached terrain if still valid and same frame
	var current_frame: int = Engine.get_process_frames()
	if _cached_terrain and is_instance_valid(_cached_terrain) and _cache_frame == current_frame:
		return _cached_terrain

	# Search for terrain in group
	var terrains = tree.get_nodes_in_group("terrain")
	if terrains.size() > 0:
		_cached_terrain = terrains[0] as DaggerfallTerrain
		_cache_frame = current_frame
		return _cached_terrain

	# Fallback: search through regiment parents
	for node in tree.get_nodes_in_group("all_regiments"):
		var parent = node.get_parent()
		while parent:
			if parent is DaggerfallTerrain:
				_cached_terrain = parent
				_cache_frame = current_frame
				return _cached_terrain
			for child in parent.get_children():
				if child is DaggerfallTerrain:
					_cached_terrain = child
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

	var h_center := terrain.get_height_at(pos)
	var h_forward := terrain.get_height_at(pos + Vector3(0, 0, sample_dist))
	var h_right := terrain.get_height_at(pos + Vector3(sample_dist, 0, 0))

	var slope_z := (h_forward - h_center) / sample_dist
	var slope_x := (h_right - h_center) / sample_dist

	var max_slope := maxf(absf(slope_z), absf(slope_x))
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
