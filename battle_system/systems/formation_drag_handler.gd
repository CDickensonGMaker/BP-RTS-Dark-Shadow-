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
var min_formation_width: float = 3.0  # Minimum world units (narrow column)
var max_formation_width: float = 80.0  # Maximum world units (very wide line)

# Ghost markers for unit positions (spring1944-style preview)
# Phase 10.2: Rectangular footprints instead of rings
var ghost_markers: Array[MeshInstance3D] = []
var ghost_facing_pips: Array[MeshInstance3D] = []  # Phase 10.4: Front-edge indicators
var ghost_material: StandardMaterial3D = null
var ghost_material_stretched: StandardMaterial3D = null  # Phase 10.3: Yellow for stretched
var ghost_material_invalid: StandardMaterial3D = null    # Phase 10.3: Red for invalid
const GHOST_MARKER_RADIUS: float = 1.5  # Base size reference
const MAX_GHOST_MARKERS: int = 20  # Max markers to pool
const SOLDIER_SPACING: float = 1.5  # Units between soldiers in formation
const MIN_FILES_PER_REGIMENT: int = 2  # Allow narrow formations (columns) - was 8


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
	# Phase 10.3: Create materials for different validity states
	# Cyan = valid placement
	ghost_material = StandardMaterial3D.new()
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.albedo_color = Color(0.3, 0.8, 1.0, 0.6)  # Cyan, semi-transparent
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Yellow = stretched formation (unit will be thin/wide)
	ghost_material_stretched = StandardMaterial3D.new()
	ghost_material_stretched.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material_stretched.albedo_color = Color(1.0, 0.9, 0.3, 0.6)  # Yellow
	ghost_material_stretched.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material_stretched.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Red = invalid placement (outside bounds, overlapping)
	ghost_material_invalid = StandardMaterial3D.new()
	ghost_material_invalid.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material_invalid.albedo_color = Color(1.0, 0.3, 0.3, 0.6)  # Red
	ghost_material_invalid.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material_invalid.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Pre-create marker pool (Phase 10.2: start with default rectangle, resize later)
	for i in MAX_GHOST_MARKERS:
		var marker := MeshInstance3D.new()
		marker.mesh = _create_rect_mesh(5.0, 3.0)  # Default 5x3 rectangle
		marker.material_override = ghost_material
		marker.visible = false
		add_child(marker)
		ghost_markers.append(marker)

		# Phase 10.4: Create front-edge facing pip
		var pip := MeshInstance3D.new()
		pip.mesh = _create_pip_mesh()
		pip.material_override = ghost_material
		pip.visible = false
		add_child(pip)
		ghost_facing_pips.append(pip)


func _create_ring_mesh(radius: float) -> Mesh:
	## Create a ring/circle mesh for ghost markers (legacy, kept for reference).
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


func _create_rect_mesh(width: float, depth: float) -> Mesh:
	## Phase 10.2: Create a rectangular outline mesh for formation footprint.
	## Width is along X (files), Depth is along Z (ranks).
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var hw := width * 0.5
	var hd := depth * 0.5
	var y := 0.3  # Slight Y offset above ground

	# Rectangle corners (clockwise from front-left)
	immediate.surface_add_vertex(Vector3(-hw, y, -hd))  # Front-left
	immediate.surface_add_vertex(Vector3(hw, y, -hd))   # Front-right
	immediate.surface_add_vertex(Vector3(hw, y, hd))    # Back-right
	immediate.surface_add_vertex(Vector3(-hw, y, hd))   # Back-left
	immediate.surface_add_vertex(Vector3(-hw, y, -hd))  # Close the loop

	immediate.surface_end()
	return immediate


func _create_pip_mesh() -> Mesh:
	## Phase 10.4: Create a small triangle pip to indicate front facing direction.
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var y := 0.35  # Slightly above rectangle
	var size := 0.8

	# Triangle pointing forward (-Z direction)
	immediate.surface_add_vertex(Vector3(0, y, -size))       # Tip (front)
	immediate.surface_add_vertex(Vector3(-size * 0.5, y, 0)) # Back-left
	immediate.surface_add_vertex(Vector3(size * 0.5, y, 0))  # Back-right

	immediate.surface_end()
	return immediate


func _update_ghost_markers():
	## Update ghost markers to show where each unit will go.
	## Phase 10.2: Uses rectangular footprints sized to actual formation layout.
	## Phase 10.3: Color-codes by validity (cyan/yellow/red).
	## Phase 10.4: Shows front-facing pip.
	if not SelectionManager:
		_hide_all_ghost_markers()
		return

	var regiments := SelectionManager.selected_regiments
	if regiments.is_empty():
		_hide_all_ghost_markers()
		return

	# Calculate formation positions (same logic as _apply_formation)
	var total_width := drag_start_world.distance_to(drag_end_world)
	total_width = clamp(total_width, min_formation_width, max_formation_width)

	var midpoint := (drag_start_world + drag_end_world) / 2.0
	var drag_dir := (drag_end_world - drag_start_world).normalized()
	var facing := Vector3(-drag_dir.z, 0, drag_dir.x)
	var right_dir := Vector3(facing.z, 0, -facing.x)

	var num_regiments := regiments.size()

	# Phase 10.1: Calculate per-regiment dimensions
	# Use MIN_FILES_PER_REGIMENT to prevent squished formations when drag is narrow
	var width_per_regiment: float = total_width / maxf(float(num_regiments), 1.0)
	var files_per_regiment: int = clampi(roundi(width_per_regiment / SOLDIER_SPACING), MIN_FILES_PER_REGIMENT, 40)

	# Calculate target positions
	var target_positions: Array[Vector3] = []
	for i in range(num_regiments):
		var offset: float
		if num_regiments == 1:
			offset = 0.0
		else:
			var t := float(i) / float(num_regiments - 1)
			offset = (t - 0.5) * total_width
		target_positions.append(midpoint + right_dir * offset)

	# Get optimal assignments (same algorithm used in _apply_formation)
	var assignments := _assign_units_optimal(regiments, target_positions)

	# Get arena bounds for validity check
	var map_bound: float = 90.0
	if AIAutoload:
		map_bound = AIAutoload.get_map_bounds()
	var safe_bound: float = map_bound - 5.0

	# Show markers at assigned positions
	var marker_idx := 0
	for regiment in regiments:
		if marker_idx >= MAX_GHOST_MARKERS:
			break
		if not is_instance_valid(regiment) or regiment not in assignments:
			continue

		var target_pos: Vector3 = assignments[regiment]

		# Calculate formation footprint size based on regiment soldiers
		var soldier_count: int = regiment.current_soldiers if regiment else 20
		var ranks: int = ceili(float(soldier_count) / float(files_per_regiment))
		var footprint_width: float = files_per_regiment * SOLDIER_SPACING
		var footprint_depth: float = ranks * SOLDIER_SPACING

		# Phase 10.2: Update rectangle mesh to match footprint
		ghost_markers[marker_idx].mesh = _create_rect_mesh(footprint_width, footprint_depth)
		ghost_markers[marker_idx].global_position = target_pos

		# Phase 10.3: Determine color based on validity
		var is_outside_bounds: bool = absf(target_pos.x) > safe_bound or absf(target_pos.z) > safe_bound
		var is_stretched: bool = files_per_regiment > 12 or files_per_regiment < 3  # Abnormally wide/thin

		if is_outside_bounds:
			ghost_markers[marker_idx].material_override = ghost_material_invalid
		elif is_stretched:
			ghost_markers[marker_idx].material_override = ghost_material_stretched
		else:
			ghost_markers[marker_idx].material_override = ghost_material

		# Set rotation to match facing
		var facing_angle: float = atan2(facing.x, facing.z)
		ghost_markers[marker_idx].rotation.y = facing_angle
		ghost_markers[marker_idx].visible = true

		# Phase 10.4: Position front-edge pip
		var pip_offset: float = footprint_depth * 0.5 + 0.5  # Just in front of formation
		var pip_pos: Vector3 = target_pos + facing * pip_offset
		ghost_facing_pips[marker_idx].global_position = pip_pos
		ghost_facing_pips[marker_idx].rotation.y = facing_angle
		ghost_facing_pips[marker_idx].material_override = ghost_markers[marker_idx].material_override
		ghost_facing_pips[marker_idx].visible = true

		marker_idx += 1

	# Hide unused markers
	for i in range(marker_idx, MAX_GHOST_MARKERS):
		ghost_markers[i].visible = false
		ghost_facing_pips[i].visible = false


func _hide_all_ghost_markers():
	for marker in ghost_markers:
		marker.visible = false
	for pip in ghost_facing_pips:
		pip.visible = false


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

	# Calculate facing direction (perpendicular to A-B line)
	var drag_direction = (drag_end_world - drag_start_world).normalized()
	# Perpendicular in XZ plane - rotate 90 degrees
	var facing_direction = Vector3(-drag_direction.z, 0, drag_direction.x)
	# REMOVED auto-flip: per game bible §5.3, drag direction determines facing
	# Player controls facing by dragging in different directions

	# Apply formation to all selected regiments
	_apply_formation(midpoint, facing_direction, formation_width)


func _issue_simple_move(screen_pos: Vector2):
	# First, check if we clicked on an enemy unit
	var enemy_target: Regiment = _raycast_enemy(screen_pos)

	if enemy_target:
		for regiment in SelectionManager.selected_regiments:
			if is_instance_valid(regiment):
				_issue_attack_order(regiment, enemy_target)
		return

	# Fallback to normal move order
	var ground_pos = _raycast_ground(screen_pos)
	if ground_pos == Vector3.INF:
		return

	# Set up movement group for speed sync (spring1944-inspired)
	var move_group: Array[Regiment] = []
	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment):
			move_group.append(regiment)

	# Calculate spread vectors to prevent clustering (spring1944-inspired)
	var spread_positions := _calculate_spread_positions(move_group, ground_pos)

	# Issue orders with spread positions and set movement group
	for regiment in move_group:
		regiment.set_movement_group(move_group)
		var target_pos: Vector3 = spread_positions.get(regiment, ground_pos)
		regiment.give_order(OrderType.Type.MOVE, target_pos)


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

	# Build movement group for speed sync (spring1944-inspired)
	var move_group: Array[Regiment] = []
	for regiment: Regiment in assignments.keys():
		if is_instance_valid(regiment):
			move_group.append(regiment)

	# Phase 10.1: Calculate per-regiment width from total drag width
	# Each regiment gets a portion of the formation line
	# Use MIN_FILES_PER_REGIMENT to prevent squished formations when drag is narrow
	var width_per_regiment: float = width / maxf(float(num_regiments), 1.0)
	# Convert world width to file count (soldiers per row)
	var files_per_regiment: int = clampi(roundi(width_per_regiment / SOLDIER_SPACING), MIN_FILES_PER_REGIMENT, 40)

	# Apply assignments
	for regiment: Regiment in assignments.keys():
		if not is_instance_valid(regiment):
			continue

		var target_pos: Vector3 = assignments[regiment]

		# Phase 10.1: Apply formation deformation based on drag width
		if regiment.has_method("set_formation_dimensions"):
			regiment.set_formation_dimensions(files_per_regiment, true)

		if DeploymentManager and DeploymentManager.is_deployment_phase():
			# During deployment, instantly reposition (no movement group needed)
			regiment.global_position = target_pos
			regiment.leader.global_position = target_pos
			if regiment.formation:
				regiment.formation.global_position = target_pos
			_face_regiment(regiment, facing)
			BattleSignals.unit_repositioned.emit(regiment, target_pos)
		else:
			# During combat, set movement group and issue move order
			regiment.set_movement_group(move_group)
			regiment.give_order(OrderType.Type.MOVE, target_pos)

		BattleSignals.formation_applied.emit(regiment, target_pos, facing, width)


func _assign_units_optimal(units: Array, positions: Array[Vector3]) -> Dictionary:
	## Optimal assignment using Hungarian algorithm (spring1944-inspired).
	## Guarantees minimum total travel distance.
	## Falls back to greedy for very large selections or if Hungarian fails.

	var valid_units: Array = []
	for unit in units:
		if is_instance_valid(unit):
			valid_units.append(unit)

	if valid_units.is_empty() or positions.is_empty():
		return {}

	var n: int = valid_units.size()

	# For small selections or if sizes don't match, use greedy
	if n != positions.size() or n > 20:
		return _assign_units_greedy(valid_units, positions)

	# Try Hungarian algorithm
	var result := _hungarian_assignment(valid_units, positions)
	if result.is_empty():
		# Fallback to greedy if Hungarian fails
		return _assign_units_greedy(valid_units, positions)

	return result


func _assign_units_greedy(units: Array, positions: Array[Vector3]) -> Dictionary:
	## Greedy nearest-neighbor assignment.
	## O(n²) but simple and effective.
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


func _hungarian_assignment(units: Array, positions: Array[Vector3]) -> Dictionary:
	## Hungarian algorithm for optimal assignment (spring1944-inspired).
	## O(n³) complexity, optimal for minimizing total distance.
	var n: int = units.size()
	if n == 0:
		return {}

	# Build cost matrix (squared distances for efficiency)
	var cost: Array[Array] = []
	for i in n:
		var row: Array[float] = []
		for j in n:
			row.append(units[i].global_position.distance_squared_to(positions[j]))
		cost.append(row)

	# Hungarian algorithm implementation
	var INF_COST := 1e18

	# Step 1: Subtract row minima
	for i in n:
		var row_min: float = INF_COST
		for j in n:
			row_min = minf(row_min, cost[i][j])
		for j in n:
			cost[i][j] -= row_min

	# Step 2: Subtract column minima
	for j in n:
		var col_min: float = INF_COST
		for i in n:
			col_min = minf(col_min, cost[i][j])
		for i in n:
			cost[i][j] -= col_min

	# Augmenting path algorithm
	var u: Array[float] = []  # Potential for rows
	var v: Array[float] = []  # Potential for cols
	var p: Array[int] = []    # Assignment col -> row
	var way: Array[int] = []  # Path tracking

	for _i in n + 1:
		u.append(0.0)
		v.append(0.0)
		p.append(0)
		way.append(0)

	for i in range(1, n + 1):
		p[0] = i
		var j0: int = 0

		var minv: Array[float] = []
		var used: Array[bool] = []
		for _j in n + 1:
			minv.append(INF_COST)
			used.append(false)

		while p[j0] != 0:
			used[j0] = true
			var i0: int = p[j0]
			var delta: float = INF_COST
			var j1: int = 0

			for j in range(1, n + 1):
				if not used[j]:
					# Use original cost matrix (indices are 0-based internally)
					var cur: float = cost[i0 - 1][j - 1] - u[i0] - v[j]
					if cur < minv[j]:
						minv[j] = cur
						way[j] = j0
					if minv[j] < delta:
						delta = minv[j]
						j1 = j

			for j in n + 1:
				if used[j]:
					u[p[j]] += delta
					v[j] -= delta
				else:
					minv[j] -= delta

			j0 = j1

		# Trace back the path
		while j0 != 0:
			var j1: int = way[j0]
			p[j0] = p[j1]
			j0 = j1

	# Build result dictionary
	var result: Dictionary = {}
	for j in range(1, n + 1):
		var row_idx: int = p[j] - 1
		var col_idx: int = j - 1
		if row_idx >= 0 and row_idx < n:
			result[units[row_idx]] = positions[col_idx]

	return result


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
	# REMOVED auto-flip: facing determined by drag direction

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
	var viewport := get_viewport()
	if not viewport:
		return Vector3.INF
	var camera := viewport.get_camera_3d()
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

	# Fallback: intersect with y=0 plane (terrain is usually near y=0)
	if ray_dir.y != 0:
		var t = (0.0 - ray_origin.y) / ray_dir.y  # Use y=0 as fallback
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF


func _raycast_enemy(screen_pos: Vector2) -> Regiment:
	## Raycast to find enemy regiment under cursor.
	var viewport := get_viewport()
	if not viewport:
		return null
	var camera := viewport.get_camera_3d()
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
			return regiment

	return null


func _calculate_spread_positions(regiments: Array[Regiment], center: Vector3) -> Dictionary:
	## Calculate DETERMINISTIC grid positions to prevent unit clustering.
	## Uses a grid layout instead of random spread for predictable behavior.
	## Same click = same positions every time.
	var result: Dictionary = {}

	if regiments.size() <= 1:
		# Single unit, no spread needed
		for regiment in regiments:
			result[regiment] = center
		return result

	# Calculate center of selected units to determine approach direction
	var units_center := Vector3.ZERO
	var valid_count := 0
	for regiment in regiments:
		if is_instance_valid(regiment):
			units_center += regiment.global_position
			valid_count += 1
	if valid_count == 0:
		for regiment in regiments:
			result[regiment] = center
		return result
	units_center /= float(valid_count)

	# Direction from units to destination
	var approach_dir := (center - units_center)
	approach_dir.y = 0
	if approach_dir.length_squared() < 0.1:
		approach_dir = Vector3.FORWARD
	approach_dir = approach_dir.normalized()

	# Tangent vector (perpendicular to approach)
	var tangent := Vector3(-approach_dir.z, 0, approach_dir.x)

	# Deterministic grid spacing based on unit count
	var base_spread: float = 6.0  # Base spacing between units
	var num_units: int = regiments.size()

	# Calculate grid dimensions
	var grid_cols: int = ceili(sqrt(float(num_units)))
	var grid_rows: int = ceili(float(num_units) / float(grid_cols))

	# Sort regiments by current tangent position to preserve relative positions
	# (leftmost stays leftmost)
	var sorted_regiments: Array[Regiment] = []
	for r in regiments:
		if is_instance_valid(r):
			sorted_regiments.append(r)
	sorted_regiments.sort_custom(func(a, b):
		if not is_instance_valid(a) or not is_instance_valid(b):
			return false
		return a.global_position.dot(tangent) < b.global_position.dot(tangent)
	)

	var idx := 0
	for regiment in sorted_regiments:
		var col: int = idx % grid_cols
		var row: int = idx / grid_cols

		# Calculate offset from center
		var col_offset: float = (float(col) - float(grid_cols - 1) / 2.0) * base_spread
		var row_offset: float = (float(row) - float(grid_rows - 1) / 2.0) * base_spread * 0.5

		# Apply offsets along tangent (width) and approach (depth)
		var spread: Vector3 = tangent * col_offset - approach_dir * row_offset
		result[regiment] = center + spread

		idx += 1

	return result


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
	else:
		# Melee unit - charge towards enemy approach point (not center)
		var attack_pos: Vector3 = Regiment.get_attack_approach_position(regiment.global_position, target.global_position)
		regiment.give_order(OrderType.Type.ATTACK_MOVE, attack_pos)
