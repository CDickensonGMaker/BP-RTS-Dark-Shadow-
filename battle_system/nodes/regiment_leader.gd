# The leader is a hidden node that does all the actual pathfinding.
# Soldiers in the regiment follow offsets from the leader's position.
# This keeps formation shape while navigating around obstacles.

class_name RegimentLeader
extends Node3D


@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
var target_position: Vector3
var move_speed: float = 1.5  # Reduced for Total War-like pacing (was 4.0)

# Terrain reference for height following
var _terrain: DaggerfallTerrain = null


func _ready():
	# Find the terrain for height following
	await get_tree().process_frame
	_find_terrain()


func _find_terrain():
	# Search for DaggerfallTerrain in the scene
	var terrains = get_tree().get_nodes_in_group("terrain")
	if terrains.size() > 0:
		_terrain = terrains[0]
	else:
		# Fallback: search by class
		for node in get_tree().get_nodes_in_group("all_regiments"):
			var parent = node.get_parent()
			while parent:
				if parent is DaggerfallTerrain:
					_terrain = parent
					return
				for child in parent.get_children():
					if child is DaggerfallTerrain:
						_terrain = child
						return
				parent = parent.get_parent()


func stop_movement():
	## Stop all movement immediately - for combat engagement
	target_position = global_position
	nav_agent.target_position = global_position


func move_to(pos: Vector3):
	# Re-find terrain if not set
	if not _terrain:
		_find_terrain()
	target_position = pos
	# Adjust target height to terrain
	if _terrain:
		pos.y = _terrain.get_height_at(pos)

	# Check if navigation map is available
	var nav_map = nav_agent.get_navigation_map()
	var _nav_available = NavigationServer3D.map_get_iteration_id(nav_map) > 0

	nav_agent.target_position = pos


func _physics_process(delta):
	# Always follow terrain height
	_apply_terrain_height()

	if nav_agent.is_navigation_finished():
		return

	# Check if nav map is available
	var nav_map = nav_agent.get_navigation_map()
	var nav_available = nav_map != RID() and NavigationServer3D.map_get_iteration_id(nav_map) > 0

	var next: Vector3
	var dist_to_target = global_position.distance_to(nav_agent.target_position)

	if nav_available:
		next = nav_agent.get_next_path_position()
	else:
		# No navigation available - move directly towards target
		next = nav_agent.target_position

	var dist_to_next = global_position.distance_to(next)

	# Check if we've arrived at target
	if dist_to_target < 1.0:
		return

	# If next position is basically our current position but we're not at target, move directly
	if dist_to_next < 0.1 and dist_to_target > 1.0:
		# Navigation is stuck - move directly towards target
		var dir_to_target = (nav_agent.target_position - global_position)
		dir_to_target.y = 0
		if dir_to_target.length() > 0.5:
			var direction = dir_to_target.normalized()
			var new_pos = global_position + direction * move_speed * delta
			if _terrain:
				new_pos.y = _terrain.get_height_at(new_pos)
			global_position = new_pos
			# Face movement direction
			if direction.length() > 0.01:
				look_at(global_position + direction, Vector3.UP)
		return

	var direction = (next - global_position).normalized()
	direction.y = 0  # Keep movement horizontal

	# Move horizontally
	var new_pos = global_position + direction * move_speed * delta

	# Apply terrain height
	if _terrain:
		new_pos.y = _terrain.get_height_at(new_pos)

	global_position = new_pos

	# Face movement direction
	if direction.length() > 0.01:
		var look_target = global_position + direction
		look_at(look_target, Vector3.UP)


func _apply_terrain_height():
	## Snap to terrain height
	if _terrain:
		var terrain_height = _terrain.get_height_at(global_position)
		global_position.y = terrain_height


func get_terrain_height(pos: Vector3) -> float:
	## Get terrain height at a position
	if _terrain:
		return _terrain.get_height_at(pos)
	return 0.0


func get_terrain_slope() -> float:
	## Get slope angle at current position (in degrees)
	if not _terrain:
		return 0.0

	# Sample heights in a small area to calculate slope
	var sample_dist = 1.0
	var h_center = _terrain.get_height_at(global_position)
	var h_forward = _terrain.get_height_at(global_position + Vector3(0, 0, sample_dist))
	var h_right = _terrain.get_height_at(global_position + Vector3(sample_dist, 0, 0))

	# Calculate slope from height differences
	var slope_z = (h_forward - h_center) / sample_dist
	var slope_x = (h_right - h_center) / sample_dist

	var max_slope = maxf(absf(slope_z), absf(slope_x))
	return rad_to_deg(atan(max_slope))
