# DeploymentManager - handles pre-battle unit positioning
# Players can place units anywhere on their side of the map
# Supports free repositioning and rotation during deployment phase
#
# ORIENTATION: X-axis based deployment
# - Player deploys on NEGATIVE X side (west/left), facing EAST toward enemy
# - Enemy deploys on POSITIVE X side (east/right), facing WEST toward player
# - This matches battle_scene.tscn and unit_zoo layouts
extends Node

# Preload to avoid parse-order issues with class_name
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")

enum Phase { DEPLOYMENT, COMBAT }

var current_phase: Phase = Phase.DEPLOYMENT
var deployment_zone_x: float = 0.0  # Center line - player deploys on negative X side
var map_bounds: Rect2 = Rect2(-75, -75, 150, 150)  # Default, updated from terrain

# Drag state for repositioning units during deployment
var dragging_regiment: Regiment = null
var drag_offset: Vector3 = Vector3.ZERO


func _ready():
	# Start in deployment phase
	current_phase = Phase.DEPLOYMENT
	call_deferred("_init_deployment")


func _init_deployment():
	# Try to get map bounds from terrain (Phase 6.4: use helper)
	var terrain := TerrainHelperScript.get_terrain(get_tree())
	if terrain:
		var size = terrain.terrain_size
		map_bounds = Rect2(-size.x / 2, -size.y / 2, size.x, size.y)
		deployment_zone_x = 0.0  # Center line (X-axis)

	BattleSignals.deployment_started.emit()


func _input(event):
	if current_phase != Phase.DEPLOYMENT:
		return

	# Skip mouse input if not in battle viewport (e.g., clicking control panel in unit zoo)
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if not _is_mouse_in_battle_viewport():
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
	if regiment:
		if regiment.is_player_controlled:
			dragging_regiment = regiment
			var ground_pos = _raycast_ground(screen_pos)
			if ground_pos != Vector3.INF:
				drag_offset = regiment.global_position - ground_pos
				print("[Deployment] Started dragging: %s" % (regiment.data.regiment_name if regiment.data else regiment.name))
		else:
			print("[Deployment] Clicked enemy unit (can't drag): %s" % (regiment.data.regiment_name if regiment.data else regiment.name))


func _update_drag(screen_pos: Vector2):
	if not dragging_regiment:
		return

	var ground_pos = _raycast_ground(screen_pos)
	if ground_pos == Vector3.INF:
		return

	var new_pos = ground_pos + drag_offset

	# Constrain to player's deployment zone (negative X half - west side)
	new_pos = _constrain_to_deployment_zone(new_pos)

	dragging_regiment.global_position = new_pos
	dragging_regiment.leader.global_position = new_pos
	if dragging_regiment.formation:
		dragging_regiment.formation.global_position = new_pos


func _end_drag(_screen_pos: Vector2):
	if dragging_regiment:
		print("[Deployment] Dropped unit: %s at %s" % [
			dragging_regiment.data.regiment_name if dragging_regiment.data else dragging_regiment.name,
			dragging_regiment.global_position
		])
		BattleSignals.unit_repositioned.emit(dragging_regiment, dragging_regiment.global_position)
	dragging_regiment = null
	drag_offset = Vector3.ZERO


func _constrain_to_deployment_zone(pos: Vector3) -> Vector3:
	# Player deploys on negative X side (west half of the map)
	# Clamp within map bounds and deployment zone
	var constrained = pos
	# X: player can only go from left edge to center line (negative X)
	constrained.x = clamp(pos.x, map_bounds.position.x + 5, deployment_zone_x - 5)
	# Z: full range within map bounds
	constrained.z = clamp(pos.z, map_bounds.position.y + 5, map_bounds.end.y - 5)
	return constrained


func is_in_player_deployment_zone(pos: Vector3) -> bool:
	# Player zone is negative X (west/left side)
	return pos.x < deployment_zone_x and map_bounds.has_point(Vector2(pos.x, pos.z))


func is_in_enemy_deployment_zone(pos: Vector3) -> bool:
	# Enemy zone is positive X (east/right side)
	return pos.x > deployment_zone_x and map_bounds.has_point(Vector2(pos.x, pos.z))


func start_battle():
	"""Called when player clicks Start Battle button"""
	if current_phase != Phase.DEPLOYMENT:
		print("[Deployment] Already in combat phase")
		return

	print("[Deployment] === STARTING COMBAT PHASE ===")
	print("[Deployment] AI will now process, units can move and fight")
	current_phase = Phase.COMBAT
	dragging_regiment = null

	BattleSignals.deployment_ended.emit()
	BattleManager.start_battle()


func is_deployment_phase() -> bool:
	return current_phase == Phase.DEPLOYMENT


func is_combat_phase() -> bool:
	return current_phase == Phase.COMBAT


# === VIEWPORT HELPERS (for SubViewport support in Unit Zoo) ===

func _get_battle_camera() -> Camera3D:
	"""Get the battle camera from scene group."""
	var cameras := get_tree().get_nodes_in_group("battle_camera")
	return cameras[0] as Camera3D if cameras.size() > 0 else null


func _get_battle_viewport() -> Viewport:
	"""Get the viewport containing the battle camera.
	This supports both main viewport (battle scene) and SubViewport (unit zoo)."""
	var camera := _get_battle_camera()
	if camera:
		return camera.get_viewport()
	return get_viewport()


func _convert_to_battle_viewport_pos(screen_pos: Vector2) -> Vector2:
	"""Convert main window screen position to battle viewport position.
	Handles SubViewport offset when unit zoo uses embedded viewport."""
	var battle_vp := _get_battle_viewport()
	var main_vp := get_viewport()

	# If same viewport, no conversion needed
	if battle_vp == main_vp:
		return screen_pos

	# Find the SubViewportContainer that holds the battle viewport
	var container := _find_viewport_container(battle_vp)
	if container:
		# Convert to container-local coordinates
		var container_rect := container.get_global_rect()
		var local_pos := screen_pos - container_rect.position
		# Scale if container is stretched
		var scale_x := float(battle_vp.size.x) / container_rect.size.x if container_rect.size.x > 0 else 1.0
		var scale_y := float(battle_vp.size.y) / container_rect.size.y if container_rect.size.y > 0 else 1.0
		return Vector2(local_pos.x * scale_x, local_pos.y * scale_y)

	return screen_pos


func _find_viewport_container(viewport: Viewport) -> SubViewportContainer:
	"""Find the SubViewportContainer that holds a SubViewport."""
	if viewport is SubViewport:
		var parent := viewport.get_parent()
		if parent is SubViewportContainer:
			return parent
	return null


func _is_mouse_in_battle_viewport() -> bool:
	"""Check if mouse is within the battle viewport bounds."""
	var battle_vp := _get_battle_viewport()
	var main_vp := get_viewport()

	# If same viewport, always valid
	if battle_vp == main_vp:
		return true

	# Check if mouse is within the SubViewportContainer
	var container := _find_viewport_container(battle_vp)
	if container:
		var mouse_pos := main_vp.get_mouse_position()
		return container.get_global_rect().has_point(mouse_pos)

	return true


# === RAYCASTING ===

func _raycast_regiment(screen_pos: Vector2) -> Regiment:
	var viewport := _get_battle_viewport()
	if not viewport:
		return null
	var camera := viewport.get_camera_3d()
	if camera == null:
		return null

	# Convert screen position to battle viewport coordinates
	var vp_pos := _convert_to_battle_viewport_pos(screen_pos)

	var ray_origin = camera.project_ray_origin(vp_pos)
	var ray_end = ray_origin + camera.project_ray_normal(vp_pos) * 1000

	var world_3d := viewport.get_world_3d()
	if not world_3d:
		return null
	var space = world_3d.direct_space_state
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
	var viewport := _get_battle_viewport()
	if not viewport:
		return Vector3.INF
	var camera := viewport.get_camera_3d()
	if camera == null:
		return Vector3.INF

	# Convert screen position to battle viewport coordinates
	var vp_pos := _convert_to_battle_viewport_pos(screen_pos)

	var ray_origin = camera.project_ray_origin(vp_pos)
	var ray_dir = camera.project_ray_normal(vp_pos)
	var ray_end = ray_origin + ray_dir * 1000

	var world_3d := viewport.get_world_3d()
	if not world_3d:
		return Vector3.INF
	var space = world_3d.direct_space_state
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
