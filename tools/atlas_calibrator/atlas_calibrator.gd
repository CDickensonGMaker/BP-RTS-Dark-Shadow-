extends Control
## Atlas Calibrator Tool - Comprehensive tool for calibrating sprite atlases
##
## Features:
## - Real 3D camera with orbit controls (like battle camera)
## - Isolated SpriteFormation display (actual sprite rendering)
## - Formation front indicator (green arrow)
## - LOS cone visualization
## - Animation-to-direction mapping editor
## - Direction offset calibration
## - Save changes to .tres files
##
## This tool shows EXACTLY how sprites will appear in-game with all the
## same rendering logic as the actual battle system.

const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")
const SpriteUnitAtlasScript = preload("res://battle_system/data/sprite_unit_atlas.gd")

# Paths
const ATLASES_PATH := "res://assets/sprites/units/"
const SHADER_PATH := "res://battle_system/shaders/unit_sprite.gdshader"

# Direction constants
const DIR_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const DIR_FULL_NAMES := ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
const DIR_ANGLES := [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]

# UI References (set in _ready via @onready or find_child)
var viewport_container: SubViewportContainer
var sub_viewport: SubViewport
var world_root: Node3D
var camera: Camera3D
var unit_anchor: Node3D

# Control panel
var atlas_dropdown: OptionButton
var animation_dropdown: OptionButton
var direction_offset_spin: SpinBox
var formation_dir_buttons: Array[Button] = []
var sprite_row_buttons: Array[Button] = []
var los_toggle: CheckButton
var save_button: Button
var status_label: Label

# Info labels
var atlas_info_label: Label
var current_row_label: Label
var current_anim_label: Label
var formation_dir_label: Label
var los_dir_label: Label
var camera_angle_label: Label

# 3D Visualization
var formation_arrow: MeshInstance3D
var los_cone: MeshInstance3D
var los_cone_pivot: Node3D
var compass_labels: Array[Label3D] = []

# Sprite display (using MultiMesh like SpriteFormation)
var sprite_multimesh: MultiMeshInstance3D
var sprite_material: ShaderMaterial
var sprite_shader: Shader

# State
var current_atlas: Resource = null
var current_atlas_path: String = ""
var atlas_paths: Array[String] = []

var current_sprite_row: int = 0  # Raw sprite row being displayed (0-7)
var formation_facing_index: int = 4  # Direction index for formation facing (default: South)
var current_animation: String = "idle"
var direction_offset: int = 0

# Camera state
var camera_orbit_angle: float = 0.0  # Horizontal orbit angle
var camera_tilt_angle: float = -45.0  # Vertical tilt
var camera_distance: float = 15.0
var camera_target: Vector3 = Vector3.ZERO
var is_orbiting: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

# LOS settings
var los_cone_angle: float = 90.0
var los_cone_distance: float = 8.0
var show_los: bool = true


func _ready() -> void:
	_build_ui()
	_build_3d_world()
	_scan_atlases()
	_connect_signals()

	# Load first atlas if available
	if atlas_paths.size() > 0:
		_load_atlas(atlas_paths[0])


func _process(delta: float) -> void:
	_update_camera_position()
	_update_info_labels()
	_update_sprite_display()


func _input(event: InputEvent) -> void:
	# Only handle input when mouse is over viewport
	if not viewport_container or not viewport_container.get_global_rect().has_point(get_global_mouse_position()):
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Middle mouse for orbit
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			is_orbiting = mb.pressed
			last_mouse_pos = mb.position
		# Scroll for zoom
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			camera_distance = maxf(5.0, camera_distance - 2.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			camera_distance = minf(50.0, camera_distance + 2.0)

	elif event is InputEventMouseMotion and is_orbiting:
		var motion := event as InputEventMouseMotion
		var delta_mouse := motion.position - last_mouse_pos
		camera_orbit_angle -= delta_mouse.x * 0.005
		camera_tilt_angle = clampf(camera_tilt_angle - delta_mouse.y * 0.3, -85.0, -10.0)
		last_mouse_pos = motion.position


func _build_ui() -> void:
	# Main layout: HSplit with viewport on left, controls on right
	var main_split := HSplitContainer.new()
	main_split.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_split.split_offset = -380
	add_child(main_split)

	# === LEFT: 3D Viewport ===
	var viewport_panel := PanelContainer.new()
	viewport_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_child(viewport_panel)

	viewport_container = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_panel.add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.size = Vector2i(1024, 768)
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.handle_input_locally = false
	viewport_container.add_child(sub_viewport)

	# === RIGHT: Control Panel ===
	var control_panel := PanelContainer.new()
	control_panel.custom_minimum_size.x = 380
	main_split.add_child(control_panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	control_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Atlas Calibrator"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# === ATLAS SELECTION ===
	var atlas_header := Label.new()
	atlas_header.text = "Select Atlas:"
	vbox.add_child(atlas_header)

	atlas_dropdown = OptionButton.new()
	atlas_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(atlas_dropdown)

	atlas_info_label = Label.new()
	atlas_info_label.text = "No atlas loaded"
	atlas_info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(atlas_info_label)

	vbox.add_child(HSeparator.new())

	# === ANIMATION SELECTION ===
	var anim_header := Label.new()
	anim_header.text = "Animation:"
	vbox.add_child(anim_header)

	animation_dropdown = OptionButton.new()
	animation_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(animation_dropdown)

	current_anim_label = Label.new()
	current_anim_label.text = "Frames: 0-0"
	vbox.add_child(current_anim_label)

	vbox.add_child(HSeparator.new())

	# === SPRITE ROW SELECTION (Yellow) ===
	var sprite_header := Label.new()
	sprite_header.text = "== SPRITE ROW (Yellow Arrow) =="
	sprite_header.add_theme_color_override("font_color", Color(0.9, 0.9, 0.2))
	sprite_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sprite_header)

	var sprite_desc := Label.new()
	sprite_desc.text = "Click to view each sprite sheet row directly"
	sprite_desc.add_theme_font_size_override("font_size", 11)
	sprite_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(sprite_desc)

	current_row_label = Label.new()
	current_row_label.text = "Row 0 (N)"
	current_row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(current_row_label)

	var sprite_grid := GridContainer.new()
	sprite_grid.columns = 4
	vbox.add_child(sprite_grid)

	for i in range(8):
		var btn := Button.new()
		btn.text = "%s (%d)" % [DIR_NAMES[i], i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_sprite_row_pressed.bind(i))
		sprite_grid.add_child(btn)
		sprite_row_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	# === FORMATION FACING (Green) ===
	var form_header := Label.new()
	form_header.text = "== FORMATION FACING (Green Arrow) =="
	form_header.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))
	form_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(form_header)

	var form_desc := Label.new()
	form_desc.text = "Simulates regiment facing direction"
	form_desc.add_theme_font_size_override("font_size", 11)
	form_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(form_desc)

	formation_dir_label = Label.new()
	formation_dir_label.text = "Facing: S (South)"
	formation_dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(formation_dir_label)

	var form_grid := GridContainer.new()
	form_grid.columns = 4
	vbox.add_child(form_grid)

	for i in range(8):
		var btn := Button.new()
		btn.text = DIR_NAMES[i]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_formation_dir_pressed.bind(i))
		form_grid.add_child(btn)
		formation_dir_buttons.append(btn)

	vbox.add_child(HSeparator.new())

	# === DIRECTION OFFSET ===
	var offset_header := Label.new()
	offset_header.text = "== DIRECTION OFFSET =="
	offset_header.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	offset_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(offset_header)

	var offset_desc := Label.new()
	offset_desc.text = "Rotates which row = which direction"
	offset_desc.add_theme_font_size_override("font_size", 11)
	offset_desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(offset_desc)

	var offset_row := HBoxContainer.new()
	vbox.add_child(offset_row)

	var offset_label := Label.new()
	offset_label.text = "Offset:"
	offset_label.custom_minimum_size.x = 60
	offset_row.add_child(offset_label)

	direction_offset_spin = SpinBox.new()
	direction_offset_spin.min_value = 0
	direction_offset_spin.max_value = 7
	direction_offset_spin.value = 0
	direction_offset_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offset_row.add_child(direction_offset_spin)

	var offset_btns := HBoxContainer.new()
	vbox.add_child(offset_btns)

	var dec_btn := Button.new()
	dec_btn.text = "< CW"
	dec_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dec_btn.pressed.connect(func(): direction_offset_spin.value = (int(direction_offset_spin.value) - 1 + 8) % 8)
	offset_btns.add_child(dec_btn)

	var inc_btn := Button.new()
	inc_btn.text = "CCW >"
	inc_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inc_btn.pressed.connect(func(): direction_offset_spin.value = (int(direction_offset_spin.value) + 1) % 8)
	offset_btns.add_child(inc_btn)

	vbox.add_child(HSeparator.new())

	# === LOS CONE ===
	var los_header := Label.new()
	los_header.text = "== LOS CONE =="
	los_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(los_header)

	los_dir_label = Label.new()
	los_dir_label.text = "LOS: S (180°)"
	los_dir_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(los_dir_label)

	los_toggle = CheckButton.new()
	los_toggle.text = "Show LOS Cone"
	los_toggle.button_pressed = true
	vbox.add_child(los_toggle)

	vbox.add_child(HSeparator.new())

	# === CAMERA INFO ===
	camera_angle_label = Label.new()
	camera_angle_label.text = "Camera: 0°"
	camera_angle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(camera_angle_label)

	vbox.add_child(HSeparator.new())

	# === SAVE ===
	save_button = Button.new()
	save_button.text = "Save Changes to Atlas"
	vbox.add_child(save_button)

	status_label = Label.new()
	status_label.text = "Ready"
	status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	vbox.add_child(HSeparator.new())

	# === HELP ===
	var help := Label.new()
	help.text = """Controls:
Middle Mouse Drag - Orbit camera
Scroll - Zoom in/out

Arrows:
Yellow = Sprite row being displayed
Green = Formation facing direction
Cone = Line of sight

Calibration:
1. Set Formation to South (S)
2. Find which row shows unit's FRONT
3. Adjust Offset until front = South row"""
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(help)


func _build_3d_world() -> void:
	# World root
	world_root = Node3D.new()
	world_root.name = "World"
	sub_viewport.add_child(world_root)

	# Camera
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 200.0
	world_root.add_child(camera)

	# Environment
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.4, 0.6)
	sky_mat.sky_horizon_color = Color(0.6, 0.65, 0.7)
	sky_mat.ground_bottom_color = Color(0.2, 0.2, 0.2)
	sky_mat.ground_horizon_color = Color(0.4, 0.4, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world_root.add_child(world_env)

	# Directional light
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	world_root.add_child(light)

	# Ground
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(40, 0.1, 40)
	ground.mesh = ground_mesh
	ground.position.y = -0.05
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.3, 0.35, 0.3)
	ground.material_override = ground_mat
	world_root.add_child(ground)

	# Unit anchor
	unit_anchor = Node3D.new()
	unit_anchor.name = "UnitAnchor"
	world_root.add_child(unit_anchor)

	# Compass markers
	_create_compass_markers()

	# Formation arrow (green)
	_create_formation_arrow()

	# LOS cone
	_create_los_cone()

	# Sprite display
	_create_sprite_display()


func _create_compass_markers() -> void:
	var compass_data := [
		["N", Vector3(0, 0.1, -10), Color(0.2, 0.5, 1.0)],
		["S", Vector3(0, 0.1, 10), Color(1.0, 0.3, 0.3)],
		["E", Vector3(10, 0.1, 0), Color.WHITE],
		["W", Vector3(-10, 0.1, 0), Color.WHITE],
	]

	for data in compass_data:
		var label := Label3D.new()
		label.text = data[0]
		label.font_size = 48
		label.position = data[1]
		label.modulate = data[2]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		world_root.add_child(label)
		compass_labels.append(label)


func _create_formation_arrow() -> void:
	formation_arrow = MeshInstance3D.new()
	formation_arrow.name = "FormationArrow"

	# Create arrow mesh (box pointing forward)
	var arrow_mesh := BoxMesh.new()
	arrow_mesh.size = Vector3(0.4, 0.3, 5.0)
	formation_arrow.mesh = arrow_mesh
	formation_arrow.position = Vector3(0, 0.5, -2.5)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 0.2, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	formation_arrow.material_override = mat

	# Create pivot for rotation
	var pivot := Node3D.new()
	pivot.name = "FormationPivot"
	unit_anchor.add_child(pivot)
	pivot.add_child(formation_arrow)


func _create_los_cone() -> void:
	los_cone_pivot = Node3D.new()
	los_cone_pivot.name = "LOSPivot"
	los_cone_pivot.position = Vector3(0, 1.5, 0)
	unit_anchor.add_child(los_cone_pivot)

	los_cone = MeshInstance3D.new()
	los_cone.name = "LOSCone"

	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = los_cone_distance * tan(deg_to_rad(los_cone_angle / 2.0))
	cone_mesh.height = los_cone_distance
	cone_mesh.radial_segments = 16
	los_cone.mesh = cone_mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.2, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	los_cone.material_override = mat

	# Rotate to point forward
	los_cone.rotation_degrees.x = 90
	los_cone.position.z = -los_cone_distance / 2.0

	los_cone_pivot.add_child(los_cone)


func _create_sprite_display() -> void:
	# Load shader
	sprite_shader = load(SHADER_PATH)
	if not sprite_shader:
		push_error("AtlasCalibrator: Failed to load sprite shader!")
		return

	sprite_material = ShaderMaterial.new()
	sprite_material.shader = sprite_shader

	# Create MultiMesh for sprite soldiers (simplified - just a few instances)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.5, 3.0)
	quad.orientation = PlaneMesh.FACE_Z

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = 16  # 4x4 formation

	sprite_multimesh = MultiMeshInstance3D.new()
	sprite_multimesh.name = "SpriteDisplay"
	sprite_multimesh.multimesh = multimesh
	sprite_multimesh.material_override = sprite_material
	sprite_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	unit_anchor.add_child(sprite_multimesh)

	# Set up initial formation positions
	var spacing := 1.5
	var idx := 0
	for row in range(4):
		for col in range(4):
			var x := (col - 1.5) * spacing
			var z := (row - 1.5) * spacing
			var xform := Transform3D()
			xform.origin = Vector3(x, 2.0, z)
			multimesh.set_instance_transform(idx, xform)
			# Custom data: r=time_offset, g=direction, b=visible, a=dead
			multimesh.set_instance_custom_data(idx, Color(randf(), 0.0, 1.0, 0.0))
			idx += 1


func _scan_atlases() -> void:
	atlas_paths.clear()
	atlas_dropdown.clear()

	var dir := DirAccess.open(ATLASES_PATH)
	if not dir:
		push_error("AtlasCalibrator: Could not open atlases directory")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			atlas_paths.append(ATLASES_PATH + file_name)
			atlas_dropdown.add_item(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()

	atlas_paths.sort()


func _connect_signals() -> void:
	atlas_dropdown.item_selected.connect(_on_atlas_selected)
	animation_dropdown.item_selected.connect(_on_animation_selected)
	direction_offset_spin.value_changed.connect(_on_offset_changed)
	los_toggle.toggled.connect(_on_los_toggled)
	save_button.pressed.connect(_save_atlas)


func _load_atlas(path: String) -> void:
	current_atlas = load(path)
	current_atlas_path = path

	if not current_atlas:
		status_label.text = "Failed to load atlas!"
		return

	# Load direction_offset
	if "direction_offset" in current_atlas:
		direction_offset = current_atlas.direction_offset
		direction_offset_spin.value = direction_offset
	else:
		direction_offset = 0
		direction_offset_spin.value = 0

	# Update shader with atlas texture
	if sprite_material and "texture" in current_atlas and current_atlas.texture:
		sprite_material.set_shader_parameter("sprite_atlas", current_atlas.texture)
		sprite_material.set_shader_parameter("atlas_columns", current_atlas.columns)
		sprite_material.set_shader_parameter("atlas_rows", current_atlas.rows)
		sprite_material.set_shader_parameter("anim_speed", current_atlas.animation_speed)
		sprite_material.set_shader_parameter("debug_mode", false)

		# Set direction row map
		var dir_row_map := PackedInt32Array()
		dir_row_map.resize(8)
		for i in range(8):
			if current_atlas.direction_rows.has(i):
				dir_row_map[i] = mini(int(current_atlas.direction_rows[i]), current_atlas.rows - 1)
			else:
				dir_row_map[i] = mini(i, current_atlas.rows - 1)
		sprite_material.set_shader_parameter("direction_row_map", dir_row_map)

	# Populate animation dropdown
	animation_dropdown.clear()
	if "animations" in current_atlas:
		for anim_name in current_atlas.animations.keys():
			animation_dropdown.add_item(anim_name)

	# Select first animation
	if animation_dropdown.item_count > 0:
		animation_dropdown.select(0)
		_on_animation_selected(0)

	var atlas_name := path.get_file().get_basename()
	atlas_info_label.text = "%s (%dx%d, %d cols)" % [
		atlas_name,
		current_atlas.rows if "rows" in current_atlas else 8,
		current_atlas.columns if "columns" in current_atlas else 13,
		current_atlas.columns if "columns" in current_atlas else 13
	]
	status_label.text = "Loaded: %s" % atlas_name


func _on_atlas_selected(index: int) -> void:
	if index >= 0 and index < atlas_paths.size():
		_load_atlas(atlas_paths[index])


func _on_animation_selected(index: int) -> void:
	if not current_atlas or not "animations" in current_atlas:
		return

	var anim_names: Array = current_atlas.animations.keys()
	if index >= 0 and index < anim_names.size():
		current_animation = anim_names[index]
		var anim_data = current_atlas.animations[current_animation]
		var start_frame: int = anim_data.get("start_frame", 0)
		var frame_count: int = anim_data.get("frame_count", 1)

		current_anim_label.text = "Frames: %d-%d (%d total)" % [start_frame, start_frame + frame_count - 1, frame_count]

		# Update shader animation params
		if sprite_material:
			sprite_material.set_shader_parameter("current_anim_start", start_frame)
			sprite_material.set_shader_parameter("current_anim_frames", frame_count)


func _on_sprite_row_pressed(row: int) -> void:
	current_sprite_row = row
	_update_sprite_row_buttons()


func _on_formation_dir_pressed(dir_index: int) -> void:
	formation_facing_index = dir_index
	_update_formation_dir_buttons()
	_update_formation_arrow()
	_update_los_cone()


func _on_offset_changed(value: float) -> void:
	direction_offset = int(value)
	_update_sprite_display()


func _on_los_toggled(enabled: bool) -> void:
	show_los = enabled
	if los_cone_pivot:
		los_cone_pivot.visible = enabled


func _update_camera_position() -> void:
	if not camera:
		return

	var x: float = sin(camera_orbit_angle) * camera_distance
	var z: float = cos(camera_orbit_angle) * camera_distance
	var y: float = camera_distance * 0.6 * absf(sin(deg_to_rad(camera_tilt_angle)))

	camera.position = Vector3(x, y + 5.0, z)
	camera.look_at(camera_target + Vector3(0, 2, 0))


func _update_info_labels() -> void:
	# Sprite row
	var remapped_dir: int = (current_sprite_row + direction_offset) % 8
	current_row_label.text = "Row %d → %s (%s)" % [current_sprite_row, DIR_NAMES[remapped_dir], DIR_FULL_NAMES[remapped_dir]]

	# Formation facing
	formation_dir_label.text = "Facing: %s (%s)" % [DIR_NAMES[formation_facing_index], DIR_FULL_NAMES[formation_facing_index]]

	# LOS
	var los_angle: float = DIR_ANGLES[formation_facing_index]
	los_dir_label.text = "LOS: %s (%.0f°)" % [DIR_NAMES[formation_facing_index], los_angle]

	# Camera angle
	var cam_deg: float = rad_to_deg(camera_orbit_angle)
	if cam_deg < 0:
		cam_deg += 360.0
	camera_angle_label.text = "Camera: %.0f°" % cam_deg


func _update_sprite_row_buttons() -> void:
	for i in range(sprite_row_buttons.size()):
		sprite_row_buttons[i].button_pressed = (i == current_sprite_row)


func _update_formation_dir_buttons() -> void:
	for i in range(formation_dir_buttons.size()):
		formation_dir_buttons[i].button_pressed = (i == formation_facing_index)


func _update_formation_arrow() -> void:
	var pivot: Node3D = unit_anchor.get_node_or_null("FormationPivot")
	if pivot:
		# Use WorldCompass for consistent angle (already Godot-compatible)
		pivot.rotation.y = WorldCompassScript.angle_from_direction(formation_facing_index)


func _update_los_cone() -> void:
	if los_cone_pivot:
		# Use WorldCompass for consistent angle (already Godot-compatible)
		los_cone_pivot.rotation.y = WorldCompassScript.angle_from_direction(formation_facing_index)


func _update_sprite_display() -> void:
	if not sprite_multimesh or not sprite_multimesh.multimesh:
		return

	# Apply current sprite row with direction offset to all instances
	var display_dir: int = (current_sprite_row + direction_offset) % 8

	# Also need to account for camera-relative display (like the real system does)
	var camera_angle: float = camera_orbit_angle
	var screen_dir: int = WorldCompassScript.world_to_screen_direction(display_dir, camera_angle)

	var mm: MultiMesh = sprite_multimesh.multimesh
	for i in range(mm.instance_count):
		var custom: Color = mm.get_instance_custom_data(i)
		custom.g = float(screen_dir)  # Direction in green channel
		mm.set_instance_custom_data(i, custom)


func _save_atlas() -> void:
	if not current_atlas or current_atlas_path == "":
		status_label.text = "No atlas loaded!"
		return

	# Update direction_offset
	current_atlas.direction_offset = direction_offset

	# Save
	var err := ResourceSaver.save(current_atlas, current_atlas_path)
	if err == OK:
		status_label.text = "Saved! offset=%d" % direction_offset
	else:
		status_label.text = "Save failed! Error: %d" % err
