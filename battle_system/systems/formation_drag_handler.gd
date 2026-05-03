# FormationDragHandler - Total War style formation stretching
# Right-click drag: point A to point B
# - Unit positions at midpoint
# - Faces perpendicular to A-B line (toward enemy)
# - Formation width = distance A to B
extends Node


# Drag state
var is_dragging: bool = false
var drag_start_world: Vector3 = Vector3.ZERO
var drag_end_world: Vector3 = Vector3.ZERO
var drag_start_screen: Vector2 = Vector2.ZERO

# Preview visualization
var preview_line: MeshInstance3D = null
var preview_material: StandardMaterial3D = null
var min_drag_distance: float = 5.0  # Minimum pixels to start drag
var min_formation_width: float = 5.0  # Minimum world units
var max_formation_width: float = 50.0  # Maximum world units


func _ready():
	_create_preview_line()


func _create_preview_line():
	preview_line = MeshInstance3D.new()
	preview_line.visible = false

	preview_material = StandardMaterial3D.new()
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.albedo_color = Color(0.2, 1.0, 0.3, 0.9)
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# We'll update the mesh dynamically
	add_child(preview_line)


func _input(event):
	# Only handle formation drag during combat phase or if deployment allows it
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		# During deployment, also allow formation setting
		pass

	if not SelectionManager or SelectionManager.selected_regiments.is_empty():
		return

	# Right-click press - start drag
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_start_drag(event.position)
		else:
			_end_drag(event.position)
		return

	# Mouse motion during drag
	if event is InputEventMouseMotion and is_dragging:
		_update_drag(event.position)


func _start_drag(screen_pos: Vector2):
	var ground_pos = _raycast_ground(screen_pos)
	if ground_pos == Vector3.INF:
		return

	is_dragging = true
	drag_start_world = ground_pos
	drag_end_world = ground_pos
	drag_start_screen = screen_pos

	# Emit signal for any listeners
	if SelectionManager.selected_regiments.size() > 0:
		var regiment = SelectionManager.selected_regiments[0]
		BattleSignals.formation_preview_started.emit(regiment, ground_pos)


func _update_drag(screen_pos: Vector2):
	if not is_dragging:
		return

	# Check if we've dragged far enough
	if screen_pos.distance_to(drag_start_screen) < min_drag_distance:
		preview_line.visible = false
		return

	var ground_pos = _raycast_ground(screen_pos)
	if ground_pos == Vector3.INF:
		return

	drag_end_world = ground_pos
	_update_preview_line()

	# Emit update signal
	if SelectionManager.selected_regiments.size() > 0:
		var regiment = SelectionManager.selected_regiments[0]
		BattleSignals.formation_preview_updated.emit(regiment, drag_start_world, drag_end_world)


func _end_drag(screen_pos: Vector2):
	if not is_dragging:
		return

	is_dragging = false
	preview_line.visible = false

	# Check if this was a simple click (not a drag)
	if screen_pos.distance_to(drag_start_screen) < min_drag_distance:
		# Simple right-click - issue move order normally
		_issue_simple_move(screen_pos)
		return

	# Calculate formation parameters
	var formation_width = drag_start_world.distance_to(drag_end_world)
	formation_width = clamp(formation_width, min_formation_width, max_formation_width)

	var midpoint = (drag_start_world + drag_end_world) / 2.0

	# Calculate facing direction (perpendicular to A-B line, facing "forward")
	var drag_direction = (drag_end_world - drag_start_world).normalized()
	# Perpendicular in XZ plane - rotate 90 degrees
	var facing_direction = Vector3(-drag_direction.z, 0, drag_direction.x)

	# Determine which perpendicular direction faces the enemy (negative Z in our setup)
	# We want units to face toward negative Z (enemy side)
	if facing_direction.z > 0:
		facing_direction = -facing_direction

	# Apply formation to all selected regiments
	_apply_formation(midpoint, facing_direction, formation_width)


func _issue_simple_move(screen_pos: Vector2):
	# Fallback to normal move order
	var ground_pos = _raycast_ground(screen_pos)
	if ground_pos == Vector3.INF:
		print("FormationDragHandler: Ground raycast failed!")
		return

	print("FormationDragHandler: Moving ", SelectionManager.selected_regiments.size(), " units to ", ground_pos)
	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment):
			regiment.give_order(OrderType.Type.MOVE, ground_pos)


func _apply_formation(center: Vector3, facing: Vector3, width: float):
	var regiments = SelectionManager.selected_regiments.duplicate()
	if regiments.is_empty():
		return

	# Calculate positions for each regiment along the formation line
	var num_regiments = regiments.size()
	var right_direction = Vector3(facing.z, 0, -facing.x)  # Perpendicular to facing

	for i in range(num_regiments):
		var regiment = regiments[i]
		if not is_instance_valid(regiment):
			continue

		# Calculate position along the formation line
		var offset: float
		if num_regiments == 1:
			offset = 0.0
		else:
			# Spread regiments evenly across the width
			var t = float(i) / float(num_regiments - 1)  # 0 to 1
			offset = (t - 0.5) * width  # -width/2 to +width/2

		var target_pos = center + right_direction * offset

		# Apply to regiment
		if DeploymentManager and DeploymentManager.is_deployment_phase():
			# During deployment, instantly reposition
			regiment.global_position = target_pos
			regiment.leader.global_position = target_pos
			if regiment.formation:
				regiment.formation.global_position = target_pos
			_face_regiment(regiment, facing)
			BattleSignals.unit_repositioned.emit(regiment, target_pos)
		else:
			# During combat, issue move order
			regiment.give_order(OrderType.Type.MOVE, target_pos)
			# After arrival, we'd want them to face this direction
			# Store facing for later application

		BattleSignals.formation_applied.emit(regiment, target_pos, facing, width)


func _face_regiment(regiment: Regiment, facing: Vector3):
	# Make the regiment face the given direction
	if facing.length() < 0.01:
		return

	var look_target = regiment.global_position + facing * 10.0
	# Use look_at but only for Y rotation
	var current_pos = regiment.global_position
	var angle = atan2(facing.x, facing.z)
	regiment.rotation.y = angle

	if regiment.leader:
		regiment.leader.rotation.y = angle

	if regiment.formation:
		regiment.formation.rotation.y = angle


func _update_preview_line():
	if not preview_line:
		return

	var width = drag_start_world.distance_to(drag_end_world)
	if width < 0.1:
		preview_line.visible = false
		return

	# Create line mesh
	var immediate_mesh = ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Main formation line (A to B)
	immediate_mesh.surface_set_color(Color(0.2, 1.0, 0.3))
	immediate_mesh.surface_add_vertex(drag_start_world + Vector3(0, 0.5, 0))
	immediate_mesh.surface_add_vertex(drag_end_world + Vector3(0, 0.5, 0))

	# Calculate midpoint and facing direction for indicator
	var midpoint = (drag_start_world + drag_end_world) / 2.0
	var drag_dir = (drag_end_world - drag_start_world).normalized()
	var facing = Vector3(-drag_dir.z, 0, drag_dir.x)
	if facing.z > 0:
		facing = -facing

	# Facing arrow from midpoint
	var arrow_length = 5.0
	var arrow_end = midpoint + facing * arrow_length
	immediate_mesh.surface_add_vertex(midpoint + Vector3(0, 0.5, 0))
	immediate_mesh.surface_add_vertex(arrow_end + Vector3(0, 0.5, 0))

	# Arrowhead
	var arrow_head_size = 1.5
	var arrow_right = Vector3(facing.z, 0, -facing.x)
	immediate_mesh.surface_add_vertex(arrow_end + Vector3(0, 0.5, 0))
	immediate_mesh.surface_add_vertex(arrow_end - facing * arrow_head_size + arrow_right * arrow_head_size * 0.5 + Vector3(0, 0.5, 0))
	immediate_mesh.surface_add_vertex(arrow_end + Vector3(0, 0.5, 0))
	immediate_mesh.surface_add_vertex(arrow_end - facing * arrow_head_size - arrow_right * arrow_head_size * 0.5 + Vector3(0, 0.5, 0))

	# End markers
	var marker_size = 1.0
	# Start marker
	immediate_mesh.surface_add_vertex(drag_start_world + Vector3(0, 0.5, 0) + drag_dir * marker_size)
	immediate_mesh.surface_add_vertex(drag_start_world + Vector3(0, 0.5, 0) - drag_dir * marker_size)
	immediate_mesh.surface_add_vertex(drag_start_world + Vector3(0, 0.5, 0) + facing * marker_size)
	immediate_mesh.surface_add_vertex(drag_start_world + Vector3(0, 0.5, 0) - facing * marker_size)
	# End marker
	immediate_mesh.surface_add_vertex(drag_end_world + Vector3(0, 0.5, 0) + drag_dir * marker_size)
	immediate_mesh.surface_add_vertex(drag_end_world + Vector3(0, 0.5, 0) - drag_dir * marker_size)
	immediate_mesh.surface_add_vertex(drag_end_world + Vector3(0, 0.5, 0) + facing * marker_size)
	immediate_mesh.surface_add_vertex(drag_end_world + Vector3(0, 0.5, 0) - facing * marker_size)

	immediate_mesh.surface_end()

	preview_line.mesh = immediate_mesh
	preview_line.material_override = preview_material
	preview_line.visible = true


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		print("FormationDragHandler: No camera!")
		return Vector3.INF

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 1000

	var space = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer

	var result = space.intersect_ray(query)
	if result:
		print("FormationDragHandler: Hit terrain at ", result.position)
		return result.position

	# Fallback: intersect with y=0 plane (terrain is usually near y=0)
	print("FormationDragHandler: No terrain hit, using y=0 plane fallback")
	if ray_dir.y != 0:
		var t = (0.0 - ray_origin.y) / ray_dir.y  # Use y=0 as fallback
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF
