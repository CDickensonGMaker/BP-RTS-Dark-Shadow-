# DeploymentManager - handles pre-battle unit positioning
# Players can place units anywhere on their side of the map
# Supports free repositioning and rotation during deployment phase
extends Node


enum Phase { DEPLOYMENT, COMBAT }

var current_phase: Phase = Phase.DEPLOYMENT
var deployment_zone_z: float = 0.0  # Center line - player deploys on positive Z side
var map_bounds: Rect2 = Rect2(-75, -75, 150, 150)  # Default, updated from terrain

# Drag state for repositioning units during deployment
var dragging_regiment: Regiment = null
var drag_offset: Vector3 = Vector3.ZERO


func _ready():
	# Start in deployment phase
	current_phase = Phase.DEPLOYMENT
	call_deferred("_init_deployment")


func _init_deployment():
	# Try to get map bounds from terrain
	var terrain = _find_terrain()
	if terrain:
		var size = terrain.terrain_size
		map_bounds = Rect2(-size.x / 2, -size.y / 2, size.x, size.y)
		deployment_zone_z = 0.0  # Center line

	BattleSignals.deployment_started.emit()


func _find_terrain() -> Node:
	var terrains = get_tree().get_nodes_in_group("terrain")
	if terrains.size() > 0:
		return terrains[0]
	# Fallback: look for BattleTerrain by class
	for node in get_tree().get_nodes_in_group("all_regiments"):
		var parent = node.get_parent()
		while parent:
			if parent.has_method("get_height_at"):
				return parent
			for child in parent.get_children():
				if child is Node3D and child.name == "BattleTerrain":
					return child
			parent = parent.get_parent()
	return null


func _input(event):
	if current_phase != Phase.DEPLOYMENT:
		return

	# Handle deployment repositioning with left-click drag on units
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_start_drag(event.position)
		else:
			_end_drag(event.position)

	if event is InputEventMouseMotion and dragging_regiment:
		_update_drag(event.position)


func _try_start_drag(screen_pos: Vector2):
	# Only allow dragging player units during deployment
	var regiment = _raycast_regiment(screen_pos)
	if regiment and regiment.is_player_controlled:
		dragging_regiment = regiment
		var ground_pos = _raycast_ground(screen_pos)
		if ground_pos != Vector3.INF:
			drag_offset = regiment.global_position - ground_pos


func _update_drag(screen_pos: Vector2):
	if not dragging_regiment:
		return

	var ground_pos = _raycast_ground(screen_pos)
	if ground_pos == Vector3.INF:
		return

	var new_pos = ground_pos + drag_offset

	# Constrain to player's deployment zone (positive Z half)
	new_pos = _constrain_to_deployment_zone(new_pos)

	dragging_regiment.global_position = new_pos
	dragging_regiment.leader.global_position = new_pos
	if dragging_regiment.formation:
		dragging_regiment.formation.global_position = new_pos


func _end_drag(_screen_pos: Vector2):
	if dragging_regiment:
		BattleSignals.unit_repositioned.emit(dragging_regiment, dragging_regiment.global_position)
	dragging_regiment = null
	drag_offset = Vector3.ZERO


func _constrain_to_deployment_zone(pos: Vector3) -> Vector3:
	# Player deploys on positive Z side (their half of the map)
	# Clamp within map bounds and deployment zone
	var constrained = pos
	constrained.x = clamp(pos.x, map_bounds.position.x + 5, map_bounds.end.x - 5)
	constrained.z = clamp(pos.z, deployment_zone_z + 5, map_bounds.end.y - 5)  # Only positive Z
	return constrained


func is_in_player_deployment_zone(pos: Vector3) -> bool:
	return pos.z > deployment_zone_z and map_bounds.has_point(Vector2(pos.x, pos.z))


func is_in_enemy_deployment_zone(pos: Vector3) -> bool:
	return pos.z < deployment_zone_z and map_bounds.has_point(Vector2(pos.x, pos.z))


func start_battle():
	"""Called when player clicks Start Battle button"""
	if current_phase != Phase.DEPLOYMENT:
		return

	current_phase = Phase.COMBAT
	dragging_regiment = null

	BattleSignals.deployment_ended.emit()
	BattleManager.start_battle()


func is_deployment_phase() -> bool:
	return current_phase == Phase.DEPLOYMENT


func is_combat_phase() -> bool:
	return current_phase == Phase.COMBAT


func _raycast_regiment(screen_pos: Vector2) -> Regiment:
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return null
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_end = ray_origin + camera.project_ray_normal(screen_pos) * 1000
	var space = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true  # Detect MeleeArea (Area3D)
	query.collide_with_bodies = false  # Don't hit terrain
	query.collision_mask = 2  # Only check layer 2 (units)
	var result = space.intersect_ray(query)
	if result:
		# Walk up parent tree to find Regiment (MeleeArea is a child of Regiment)
		var parent = result.collider.get_parent()
		while parent:
			if parent is Regiment:
				return parent
			parent = parent.get_parent()
	return null


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 1000

	var space = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer

	var result = space.intersect_ray(query)
	if result:
		return result.position

	# Fallback: intersect with y=0 plane
	if ray_dir.y != 0:
		var t = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF
