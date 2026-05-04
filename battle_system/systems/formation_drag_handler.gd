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

# Ghost markers for unit positions (spring1944-style preview)
var ghost_markers: Array[MeshInstance3D] = []
var ghost_material: StandardMaterial3D = null
const GHOST_MARKER_RADIUS: float = 1.5  # Size of ghost markers
const MAX_GHOST_MARKERS: int = 20  # Max markers to pool


func _ready():
	_create_preview_line()
	_create_ghost_markers()


func _create_preview_line():
	preview_line = MeshInstance3D.new()
	preview_line.visible = false

	preview_material = StandardMaterial3D.new()
	preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_material.albedo_color = Color(0.2, 1.0, 0.3, 0.9)
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# We'll update the mesh dynamically
	add_child(preview_line)


func _create_ghost_markers():
	# Create ghost marker material (semi-transparent circles)
	ghost_material = StandardMaterial3D.new()
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.albedo_color = Color(0.3, 0.8, 1.0, 0.6)  # Light blue, semi-transparent
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides

	# Pre-create marker pool
	var ring_mesh := _create_ring_mesh(GHOST_MARKER_RADIUS)
	for i in MAX_GHOST_MARKERS:
		var marker := MeshInstance3D.new()
		marker.mesh = ring_mesh
		marker.material_override = ghost_material
		marker.visible = false
		add_child(marker)
		ghost_markers.append(marker)


func _create_ring_mesh(radius: float) -> Mesh:
	## Create a ring/circle mesh for ghost markers.
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var segments := 24
	for i in range(segments + 1):
		var angle := float(i) / float(segments) * TAU
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		immediate.surface_add_vertex(Vector3(x, 0.3, z))  # Slight Y offset above ground

	immediate.surface_end()
	return immediate


func _update_ghost_markers():
	## Update ghost markers to show where each unit will go.
	## Uses optimal assignment to show actual destinations.
	if not SelectionManager:
		_hide_all_ghost_markers()
		return

	var regiments := SelectionManager.selected_regiments
	if regiments.is_empty():
		_hide_all_ghost_markers()
		return

	# Calculate formation positions (same logic as _apply_formation)
	var width := drag_start_world.distance_to(drag_end_world)
	width = clamp(width, min_formation_width, max_formation_width)

	var midpoint := (drag_start_world + drag_end_world) / 2.0
	var drag_dir := (drag_end_world - drag_start_world).normalized()
	var facing := Vector3(-drag_dir.z, 0, drag_dir.x)
	if facing.z > 0:
		facing = -facing
	var right_dir := Vector3(facing.z, 0, -facing.x)

	var num_regiments := regiments.size()

	# Calculate target positions
	var target_positions: Array[Vector3] = []
	for i in range(num_regiments):
		var offset: float
		if num_regiments == 1:
			offset = 0.0
		else:
			var t := float(i) / float(num_regiments - 1)
			offset = (t - 0.5) * width
		target_positions.append(midpoint + right_dir * offset)

	# Get optimal assignments (same algorithm used in _apply_formation)
	var assignments := _assign_units_optimal(regiments, target_positions)

	# Show markers at assigned positions
	var marker_idx := 0
	for regiment in regiments:
		if marker_idx >= MAX_GHOST_MARKERS:
			break
		if not is_instance_valid(regiment) or regiment not in assignments:
			continue

		var target_pos: Vector3 = assignments[regiment]
		ghost_markers[marker_idx].global_position = target_pos
		ghost_markers[marker_idx].visible = true
		marker_idx += 1

	# Hide unused markers
	for i in range(marker_idx, MAX_GHOST_MARKERS):
		ghost_markers[i].visible = false


func _hide_all_ghost_markers():
	for marker in ghost_markers:
		marker.visible = false


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
		_hide_all_ghost_markers()
		return

	var ground_pos = _raycast_ground(screen_pos)
	if ground_pos == Vector3.INF:
		return

	drag_end_world = ground_pos
	_update_preview_line()
	_update_ghost_markers()  # Show where each unit will go

	# Emit update signal
	if SelectionManager.selected_regiments.size() > 0:
		var regiment = SelectionManager.selected_regiments[0]
		BattleSignals.formation_preview_updated.emit(regiment, drag_start_world, drag_end_world)


func _end_drag(screen_pos: Vector2):
	if not is_dragging:
		return

	is_dragging = false
	preview_line.visible = false
	_hide_all_ghost_markers()

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
	# First, check if we clicked on an enemy unit
	var enemy_target: Regiment = _raycast_enemy(screen_pos)

	if enemy_target:
		print("FormationDragHandler: Attack target ", enemy_target.name)
		for regiment in SelectionManager.selected_regiments:
			if is_instance_valid(regiment):
				_issue_attack_order(regiment, enemy_target)
		return

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

	# Calculate target positions for the formation line
	var num_regiments = regiments.size()
	var right_direction = Vector3(facing.z, 0, -facing.x)  # Perpendicular to facing
	var target_positions: Array[Vector3] = []

	for i in range(num_regiments):
		var offset: float
		if num_regiments == 1:
			offset = 0.0
		else:
			var t = float(i) / float(num_regiments - 1)
			offset = (t - 0.5) * width
		target_positions.append(center + right_direction * offset)

	# Use optimal assignment to minimize path crossings (spring1944-style)
	var assignments := _assign_units_optimal(regiments, target_positions)

	# Apply assignments
	for regiment: Regiment in assignments.keys():
		if not is_instance_valid(regiment):
			continue

		var target_pos: Vector3 = assignments[regiment]

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

		BattleSignals.formation_applied.emit(regiment, target_pos, facing, width)


func _assign_units_optimal(units: Array, positions: Array[Vector3]) -> Dictionary:
	## Greedy nearest-neighbor assignment (spring1944-inspired).
	## Assigns each unit to nearest available position to minimize path crossings.
	## O(n²) but simple and effective for typical selection sizes (<20 units).
	var assignments: Dictionary = {}
	var available_positions: Array[Vector3] = positions.duplicate()

	# Sort units by their X position to reduce crossing likelihood
	var sorted_units := units.duplicate()
	sorted_units.sort_custom(func(a, b):
		if not is_instance_valid(a) or not is_instance_valid(b):
			return false
		return a.global_position.x < b.global_position.x
	)

	for unit in sorted_units:
		if not is_instance_valid(unit) or available_positions.is_empty():
			continue

		# Find nearest available position
		var best_idx := -1
		var best_dist := INF

		for i in available_positions.size():
			var dist: float = unit.global_position.distance_squared_to(available_positions[i])
			if dist < best_dist:
				best_dist = dist
				best_idx = i

		if best_idx >= 0:
			assignments[unit] = available_positions[best_idx]
			available_positions.remove_at(best_idx)

	return assignments


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


func _raycast_enemy(screen_pos: Vector2) -> Regiment:
	## Raycast to find enemy regiment under cursor.
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return null

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 1000

	var space = get_viewport().get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 2  # Units layer
	query.collide_with_areas = true

	var result = space.intersect_ray(query)
	if result and result.collider:
		# MeleeArea is child of Regiment, get parent
		var collider = result.collider
		var regiment: Regiment = null

		if collider is Area3D:
			regiment = collider.get_parent() as Regiment
		elif collider is Regiment:
			regiment = collider

		if regiment and not regiment.is_player_controlled and regiment.state != Regiment.State.DEAD:
			print("FormationDragHandler: Enemy raycast hit ", regiment.name)
			return regiment

	return null


func _issue_attack_order(regiment: Regiment, target: Regiment) -> void:
	## Issue appropriate attack order based on unit capabilities.
	## Ranged units fire from distance, melee units charge in.

	# Check if unit has ranged capability
	var has_ranged: bool = regiment.data.ballistic_skill > 0 and regiment.current_ammo > 0

	if has_ranged:
		# Ranged unit - enable AI assist to handle firing behavior
		# This lets TaskFireRanged manage range, movement, and firing
		regiment.enable_ai_assist(true)
		if regiment.ai_controller:
			regiment.ai_controller.set_target(target)
			# Set stance to SKIRMISH for ranged units (fire and avoid melee)
			regiment.ai_controller.set_stance(CommanderAI.Stance.SKIRMISH)
		print("FormationDragHandler: %s targeting %s (ranged attack)" % [regiment.name, target.name])
	else:
		# Melee unit - charge towards enemy
		var attack_pos: Vector3 = target.global_position
		regiment.give_order(OrderType.Type.ATTACK_MOVE, attack_pos)
		print("FormationDragHandler: %s charging %s (melee attack)" % [regiment.name, target.name])
