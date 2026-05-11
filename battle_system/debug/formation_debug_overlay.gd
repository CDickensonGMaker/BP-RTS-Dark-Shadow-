## FormationDebugOverlay - Visual debug overlay for formation and melee systems.
## Toggle with F5 key to show:
## - Formation front arrow (green) showing unit facing direction when selected
## - Melee engagement box (red) showing interlocking combat zone when engaging
## - Formation width/depth boundaries (yellow dashed)
##
## Uses ImmediateMesh for 3D world-space rendering that follows units correctly.
class_name FormationDebugOverlay
extends Node3D

# === REFERENCES ===
var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D

# === STATE ===
var is_enabled: bool = false
var show_for_all_units: bool = false  # When true, show for all units, not just selected

# === COLORS ===
const COLOR_FORMATION_ARROW: Color = Color(0.2, 0.9, 0.3, 0.9)       # Green - facing direction
const COLOR_FORMATION_ARROW_ENEMY: Color = Color(0.9, 0.3, 0.2, 0.9) # Red - enemy facing
const COLOR_MELEE_BOX: Color = Color(0.9, 0.3, 0.3, 0.6)             # Red - melee zone
const COLOR_MELEE_BOX_ACTIVE: Color = Color(1.0, 0.5, 0.0, 0.8)      # Orange - active combat
const COLOR_FORMATION_BOUNDS: Color = Color(0.9, 0.9, 0.2, 0.5)      # Yellow - formation bounds
const COLOR_FRONT_RANK_LINE: Color = Color(0.2, 0.8, 0.9, 0.8)       # Cyan - front rank line

# === SIZING ===
const ARROW_LENGTH: float = 4.0
const ARROW_HEAD_SIZE: float = 1.2
const ARROW_HEAD_WIDTH: float = 0.8
const ARROW_HEIGHT: float = 0.5          # Height above ground
const MELEE_BOX_HEIGHT: float = 0.3      # Height above ground
const MELEE_MIN_GAP: float = 0.8         # Minimum gap between formations (from melee_resolver)
const MELEE_BOX_DEPTH: float = 1.5       # Depth of melee zone
const DEFAULT_SOLDIER_SPACING: float = 1.2  # Default spacing between soldiers


func _ready() -> void:
	_setup_mesh()

	# Print toggle hint after startup
	get_tree().create_timer(2.0).timeout.connect(func():
		print("")
		print("=== FORMATION DEBUG ===")
		print("Press F5 to toggle formation debug overlay (facing arrows, melee boxes)")
		print("Press F6 to toggle showing all units vs selected only")
		print("=======================")
		print("")
	)


func _setup_mesh() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.name = "FormationDebugMesh"

	# Create unshaded material with vertex colors
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # See from both sides
	_material.no_depth_test = true  # Always visible (on top of terrain)
	_mesh_instance.material_override = _material

	add_child(_mesh_instance)
	_mesh_instance.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			toggle_overlay()
		elif event.keycode == KEY_F6:
			toggle_all_units()


func toggle_overlay() -> void:
	is_enabled = not is_enabled
	_mesh_instance.visible = is_enabled

	if is_enabled:
		print("FormationDebugOverlay: ENABLED (F5 to toggle, F6 for all units)")
	else:
		print("FormationDebugOverlay: DISABLED")


func toggle_all_units() -> void:
	show_for_all_units = not show_for_all_units
	if show_for_all_units:
		print("FormationDebugOverlay: Showing ALL units")
	else:
		print("FormationDebugOverlay: Showing SELECTED units only")


func _process(_delta: float) -> void:
	if not is_enabled:
		return

	_draw_overlays()


func _draw_overlays() -> void:
	_immediate_mesh.clear_surfaces()

	var regiments_to_draw: Array = []

	if show_for_all_units:
		# Draw for all regiments
		regiments_to_draw = get_tree().get_nodes_in_group("all_regiments")
	else:
		# Draw only for selected regiments
		if SelectionManager:
			regiments_to_draw = SelectionManager.selected_regiments.duplicate()

	if regiments_to_draw.is_empty():
		return

	# Start drawing
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)

	for regiment in regiments_to_draw:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD:
			continue

		_draw_formation_arrow(regiment)
		_draw_front_rank_line(regiment)
		_draw_melee_box(regiment)
		_draw_formation_bounds(regiment)

	_immediate_mesh.surface_end()


func _draw_formation_arrow(regiment: Regiment) -> void:
	## Draw arrow showing formation facing direction.
	var center: Vector3 = regiment.global_position + Vector3(0, ARROW_HEIGHT, 0)
	var facing: Vector3 = regiment.get_facing_direction()
	facing.y = 0
	facing = facing.normalized()

	if facing.length_squared() < 0.001:
		return

	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	# Choose color based on player/enemy
	var color: Color = COLOR_FORMATION_ARROW if regiment.is_player_controlled else COLOR_FORMATION_ARROW_ENEMY

	# Arrow shaft
	var arrow_start: Vector3 = center
	var arrow_end: Vector3 = center + facing * ARROW_LENGTH

	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(arrow_start)
	_immediate_mesh.surface_add_vertex(arrow_end)

	# Arrow head (V shape)
	var head_back: Vector3 = arrow_end - facing * ARROW_HEAD_SIZE
	var head_left: Vector3 = head_back + right * ARROW_HEAD_WIDTH * 0.5
	var head_right: Vector3 = head_back - right * ARROW_HEAD_WIDTH * 0.5

	_immediate_mesh.surface_add_vertex(arrow_end)
	_immediate_mesh.surface_add_vertex(head_left)
	_immediate_mesh.surface_add_vertex(arrow_end)
	_immediate_mesh.surface_add_vertex(head_right)

	# Close the head
	_immediate_mesh.surface_add_vertex(head_left)
	_immediate_mesh.surface_add_vertex(head_right)


func _draw_front_rank_line(regiment: Regiment) -> void:
	## Draw a line at the front rank position.
	var center: Vector3 = regiment.global_position + Vector3(0, ARROW_HEIGHT * 0.5, 0)
	var facing: Vector3 = regiment.get_facing_direction()
	facing.y = 0
	facing = facing.normalized()

	if facing.length_squared() < 0.001:
		return

	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	# Get front rank offset
	var front_offset: float = regiment.get_front_rank_offset()
	var formation_width: float = _estimate_formation_width(regiment)
	var half_width: float = formation_width / 2.0

	# Front rank line position
	var front_center: Vector3 = center + facing * front_offset
	var front_left: Vector3 = front_center + right * half_width
	var front_right: Vector3 = front_center - right * half_width

	_immediate_mesh.surface_set_color(COLOR_FRONT_RANK_LINE)
	_immediate_mesh.surface_add_vertex(front_left)
	_immediate_mesh.surface_add_vertex(front_right)

	# Small perpendicular ticks at ends
	var tick_size: float = 0.5
	_immediate_mesh.surface_add_vertex(front_left)
	_immediate_mesh.surface_add_vertex(front_left - facing * tick_size)
	_immediate_mesh.surface_add_vertex(front_right)
	_immediate_mesh.surface_add_vertex(front_right - facing * tick_size)


func _draw_melee_box(regiment: Regiment) -> void:
	## Draw melee engagement zone box when in combat.
	# Only show when engaging or for debugging
	if regiment.state != Regiment.State.ENGAGING and not show_for_all_units:
		return

	var center: Vector3 = regiment.global_position + Vector3(0, MELEE_BOX_HEIGHT, 0)
	var facing: Vector3 = regiment.get_facing_direction()
	facing.y = 0
	facing = facing.normalized()

	if facing.length_squared() < 0.001:
		return

	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	# Get formation dimensions
	var front_offset: float = regiment.get_front_rank_offset()
	var formation_width: float = _estimate_formation_width(regiment)
	var half_width: float = formation_width / 2.0

	# Melee box extends from front rank forward
	var box_front: Vector3 = center + facing * (front_offset + MELEE_BOX_DEPTH)
	var box_back: Vector3 = center + facing * front_offset

	# Four corners
	var fl: Vector3 = box_front + right * half_width
	var fr: Vector3 = box_front - right * half_width
	var bl: Vector3 = box_back + right * half_width
	var br: Vector3 = box_back - right * half_width

	# Choose color based on combat state
	var color: Color = COLOR_MELEE_BOX_ACTIVE if regiment.state == Regiment.State.ENGAGING else COLOR_MELEE_BOX
	_immediate_mesh.surface_set_color(color)

	# Draw box outline
	# Front edge
	_immediate_mesh.surface_add_vertex(fl)
	_immediate_mesh.surface_add_vertex(fr)

	# Back edge
	_immediate_mesh.surface_add_vertex(bl)
	_immediate_mesh.surface_add_vertex(br)

	# Left edge
	_immediate_mesh.surface_add_vertex(fl)
	_immediate_mesh.surface_add_vertex(bl)

	# Right edge
	_immediate_mesh.surface_add_vertex(fr)
	_immediate_mesh.surface_add_vertex(br)

	# Cross pattern for visibility
	_immediate_mesh.surface_add_vertex(fl)
	_immediate_mesh.surface_add_vertex(br)
	_immediate_mesh.surface_add_vertex(fr)
	_immediate_mesh.surface_add_vertex(bl)


func _draw_formation_bounds(regiment: Regiment) -> void:
	## Draw formation boundary rectangle (dashed via segments).
	var center: Vector3 = regiment.global_position + Vector3(0, MELEE_BOX_HEIGHT * 0.5, 0)
	var facing: Vector3 = regiment.get_facing_direction()
	facing.y = 0
	facing = facing.normalized()

	if facing.length_squared() < 0.001:
		return

	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	# Get formation dimensions
	var front_offset: float = regiment.get_front_rank_offset()
	var formation_width: float = _estimate_formation_width(regiment)
	var formation_depth: float = _estimate_formation_depth(regiment)
	var half_width: float = formation_width / 2.0

	# Four corners of formation
	var fl: Vector3 = center + facing * front_offset + right * half_width
	var fr: Vector3 = center + facing * front_offset - right * half_width
	var bl: Vector3 = center - facing * (formation_depth - front_offset) + right * half_width
	var br: Vector3 = center - facing * (formation_depth - front_offset) - right * half_width

	_immediate_mesh.surface_set_color(COLOR_FORMATION_BOUNDS)

	# Draw as dashed lines (segments)
	_draw_dashed_line_3d(fl, fr, 0.5, 0.3)
	_draw_dashed_line_3d(bl, br, 0.5, 0.3)
	_draw_dashed_line_3d(fl, bl, 0.5, 0.3)
	_draw_dashed_line_3d(fr, br, 0.5, 0.3)


func _draw_dashed_line_3d(from: Vector3, to: Vector3, dash_length: float, gap_length: float) -> void:
	## Draw a dashed line in 3D space.
	var direction: Vector3 = (to - from).normalized()
	var total_length: float = from.distance_to(to)
	var current_pos: float = 0.0
	var drawing: bool = true

	while current_pos < total_length:
		var segment_length: float = dash_length if drawing else gap_length
		segment_length = minf(segment_length, total_length - current_pos)

		if drawing:
			var start: Vector3 = from + direction * current_pos
			var end: Vector3 = from + direction * (current_pos + segment_length)
			_immediate_mesh.surface_add_vertex(start)
			_immediate_mesh.surface_add_vertex(end)

		current_pos += segment_length
		drawing = not drawing


func _estimate_formation_width(regiment: Regiment) -> float:
	## Estimate formation width based on soldier count and formation type.
	var formation_type: FormationType.Type = regiment.current_formation
	var soldier_count: int = regiment.current_soldiers

	# Get formation info
	var ranks: int = FormationType.RANKS.get(formation_type, 3)
	if ranks == 0:
		ranks = maxi(2, ceili(sqrt(float(soldier_count)) / 2.0))

	var spacing: float = DEFAULT_SOLDIER_SPACING
	var cols: int = ceili(float(soldier_count) / float(ranks))

	return cols * spacing


func _estimate_formation_depth(regiment: Regiment) -> float:
	## Estimate formation depth based on soldier count and formation type.
	var formation_type: FormationType.Type = regiment.current_formation

	var ranks: int = FormationType.RANKS.get(formation_type, 3)
	if ranks == 0:
		ranks = maxi(2, ceili(sqrt(float(regiment.current_soldiers)) / 2.0))

	var spacing: float = DEFAULT_SOLDIER_SPACING

	return ranks * spacing
