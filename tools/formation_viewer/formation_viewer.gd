extends Control
## Formation Editor - Edit and preview unit formations with full rotation control
## Shows all soldiers (3D models or 2D sprites) in formation layout
## - Rotate formation front direction using WorldCompass conventions (0-7)
## - Edit formation parameters: spacing, depth, rows, frontage
## - Models/sprites face the formation front direction
## - LOS cone visualization aligned with formation front

const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")
const FormationDataScript = preload("res://battle_system/ai/data/formation_data.gd")

# Regiment data paths
const REGIMENTS_PATH := "res://battle_system/data/regiments/"

# UI References
@onready var unit_dropdown: OptionButton = $HSplitContainer/LeftPanel/UnitSelector/UnitDropdown
@onready var soldier_count_spin: SpinBox = $HSplitContainer/LeftPanel/CountPanel/CountSpin
@onready var formation_dropdown: OptionButton = $HSplitContainer/LeftPanel/FormationPanel/FormationDropdown
@onready var rotation_slider: HSlider = $HSplitContainer/LeftPanel/RotationPanel/RotationSlider
@onready var rotation_label: Label = $HSplitContainer/LeftPanel/RotationPanel/RotationLabel

# Unit view direction controls (rotates models/sprites independently from formation)
@onready var unit_view_dir_label: Label = $HSplitContainer/LeftPanel/UnitViewPanel/UnitViewButtons/UnitViewDirLabel
@onready var unit_ccw_button: Button = $HSplitContainer/LeftPanel/UnitViewPanel/UnitViewButtons/UnitCCWButton
@onready var unit_cw_button: Button = $HSplitContainer/LeftPanel/UnitViewPanel/UnitViewButtons/UnitCWButton
@onready var save_front_button: Button = $HSplitContainer/LeftPanel/UnitViewPanel/SaveFrontButton
@onready var anim_dropdown: OptionButton = $HSplitContainer/LeftPanel/AnimPanel/AnimDropdown
@onready var play_button: Button = $HSplitContainer/LeftPanel/AnimPanel/PlayButton
@onready var los_angle_spin: SpinBox = $HSplitContainer/LeftPanel/LOSPanel/LOSAngleSpin
@onready var los_range_spin: SpinBox = $HSplitContainer/LeftPanel/LOSPanel/LOSRangeSpin
@onready var viewport_3d: SubViewport = $HSplitContainer/RightPanel/ViewportContainer/SubViewport
@onready var viewport_container: SubViewportContainer = $HSplitContainer/RightPanel/ViewportContainer
@onready var camera_3d: Camera3D = $HSplitContainer/RightPanel/ViewportContainer/SubViewport/Camera3D
@onready var formation_root: Node3D = $HSplitContainer/RightPanel/ViewportContainer/SubViewport/FormationRoot
@onready var ground_plane: MeshInstance3D = $HSplitContainer/RightPanel/ViewportContainer/SubViewport/Ground
@onready var direction_arrow: MeshInstance3D = $HSplitContainer/RightPanel/ViewportContainer/SubViewport/DirectionArrow
@onready var los_cone: MeshInstance3D = $HSplitContainer/RightPanel/ViewportContainer/SubViewport/LOSCone
@onready var status_label: Label = $HSplitContainer/LeftPanel/StatusLabel
@onready var camera_orbit_slider: HSlider = $HSplitContainer/LeftPanel/CameraPanel/OrbitSlider
@onready var camera_zoom_slider: HSlider = $HSplitContainer/LeftPanel/CameraPanel/ZoomSlider
@onready var render_mode_dropdown: OptionButton = $HSplitContainer/LeftPanel/RenderModePanel/RenderModeDropdown

# Formation editing controls
@onready var spacing_spin: SpinBox = $HSplitContainer/LeftPanel/SpacingPanel/SpacingSpin
@onready var depth_spin: SpinBox = $HSplitContainer/LeftPanel/DepthPanel/DepthSpin
@onready var rows_spin: SpinBox = $HSplitContainer/LeftPanel/RowsPanel/RowsSpin
@onready var frontage_spin: SpinBox = $HSplitContainer/LeftPanel/FrontagePanel/FrontageSpin

# State
var current_regiment: RegimentData = null
var current_regiment_path: String = ""  # Path to currently loaded regiment for saving
var regiment_paths: Array[String] = []
var current_formation: int = FormationDataScript.Type.LINE
var current_soldier_count: int = 40

## Formation front direction as WorldCompass direction index (0-7)
## 0=North(-Z), 1=NE, 2=East(+X), 3=SE, 4=South(+Z), 5=SW, 6=West(-X), 7=NW
var current_facing_dir_index: int = 0

## Unit view direction - controls which direction models/sprites face (independent of formation)
## This is for previewing how units look from different angles
var unit_view_dir_index: int = 0

var camera_orbit_angle: float = 0.0  # Camera Y rotation in radians
var camera_distance: float = 40.0
var los_angle: float = 90.0  # LOS cone angle in degrees
var los_range: float = 30.0  # LOS cone range in world units

# Custom formation parameters (editable)
var custom_spacing: float = 1.2      # Horizontal spacing between soldiers
var custom_depth: float = 1.0        # Vertical spacing between rows
var custom_rows: int = 3             # Number of rows
var custom_frontage: float = 1.0     # Width multiplier
var use_custom_formation: bool = true  # Always use custom params in editor

# Render mode
enum RenderMode { SPRITES_2D, MODELS_3D, AUTO }
var render_mode: RenderMode = RenderMode.AUTO

# 3D Model soldiers (for MODELS_3D mode)
var _model_instances: Array[Node3D] = []
var _model_scene: PackedScene = null

# MultiMesh for 2D sprites
var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _material: ShaderMaterial
var _shader: Shader

# Soldier arrays
var _soldier_positions: PackedVector3Array
var _soldier_alive: PackedFloat32Array
var _soldier_directions: PackedFloat32Array
var _soldier_time_offsets: PackedFloat32Array

# Animation
var is_playing: bool = false
var current_animation: String = "idle"
var anim_key_map: Dictionary = {}

const STANDARD_ANIMS := ["idle", "walk", "attack", "death"]
const SPRITE_SCALE := Vector2(2.5, 3.0)
const HEIGHT_OFFSET := 0.5
const MAX_SOLDIERS := 200
const MODEL_SCALE := Vector3(1.0, 1.0, 1.0)


func _ready() -> void:
	_populate_unit_dropdown()
	_populate_formation_dropdown()
	_populate_render_mode_dropdown()
	_connect_signals()
	_setup_3d_scene()
	_setup_multimesh()

	# Load first unit if available
	if regiment_paths.size() > 0:
		_load_regiment(regiment_paths[0])


func _process(delta: float) -> void:
	if is_playing:
		_update_animations(delta)


func _populate_unit_dropdown() -> void:
	unit_dropdown.clear()
	regiment_paths.clear()

	var dir := DirAccess.open(REGIMENTS_PATH)
	if not dir:
		push_error("Could not open regiments directory: " + REGIMENTS_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			regiment_paths.append(REGIMENTS_PATH + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	regiment_paths.sort()
	for path in regiment_paths:
		var display_name := path.get_file().get_basename()
		unit_dropdown.add_item(display_name)


func _populate_formation_dropdown() -> void:
	formation_dropdown.clear()
	formation_dropdown.add_item("Line", FormationDataScript.Type.LINE)
	formation_dropdown.add_item("Column", FormationDataScript.Type.COLUMN)
	formation_dropdown.add_item("Wedge", FormationDataScript.Type.WEDGE)
	formation_dropdown.add_item("Square", FormationDataScript.Type.SQUARE)
	formation_dropdown.add_item("Skirmish", FormationDataScript.Type.SKIRMISH)


func _populate_render_mode_dropdown() -> void:
	render_mode_dropdown.clear()
	render_mode_dropdown.add_item("Auto", RenderMode.AUTO)
	render_mode_dropdown.add_item("2D Sprites", RenderMode.SPRITES_2D)
	render_mode_dropdown.add_item("3D Models", RenderMode.MODELS_3D)


func _populate_animations() -> void:
	anim_dropdown.clear()
	anim_key_map.clear()

	# For 3D models, get animations from the model
	if _is_using_3d_models() and _model_instances.size() > 0:
		var model := _model_instances[0]
		var anim_player := _find_animation_player(model)
		if anim_player:
			for anim_name in anim_player.get_animation_list():
				anim_dropdown.add_item(anim_name)
				anim_key_map[anim_name] = anim_name
	elif current_regiment and current_regiment.sprite_atlas:
		# For sprites, get from atlas
		var atlas: SpriteUnitAtlas = current_regiment.sprite_atlas
		var atlas_anims: Dictionary = atlas.animations

		for anim_name in STANDARD_ANIMS:
			var key := _find_anim_key(atlas_anims, anim_name)
			if key != "":
				anim_dropdown.add_item(anim_name)
				anim_key_map[anim_name] = key
	else:
		for anim_name in STANDARD_ANIMS:
			anim_dropdown.add_item(anim_name)
			anim_key_map[anim_name] = anim_name

	if anim_dropdown.item_count > 0:
		anim_dropdown.select(0)
		current_animation = anim_key_map.get(anim_dropdown.get_item_text(0), "idle")


func _find_anim_key(atlas_anims: Dictionary, display_name: String) -> String:
	if display_name == "death" and atlas_anims.has("dead"):
		return "dead"
	if atlas_anims.has(display_name):
		return display_name
	return ""


func _connect_signals() -> void:
	unit_dropdown.item_selected.connect(_on_unit_selected)
	soldier_count_spin.value_changed.connect(_on_soldier_count_changed)
	formation_dropdown.item_selected.connect(_on_formation_selected)
	rotation_slider.value_changed.connect(_on_rotation_changed)
	anim_dropdown.item_selected.connect(_on_animation_selected)
	play_button.pressed.connect(_on_play_pressed)
	camera_orbit_slider.value_changed.connect(_on_camera_orbit_changed)
	camera_zoom_slider.value_changed.connect(_on_camera_zoom_changed)
	los_angle_spin.value_changed.connect(_on_los_angle_changed)
	los_range_spin.value_changed.connect(_on_los_range_changed)
	render_mode_dropdown.item_selected.connect(_on_render_mode_changed)

	# Formation editing controls
	spacing_spin.value_changed.connect(_on_spacing_changed)
	depth_spin.value_changed.connect(_on_depth_changed)
	rows_spin.value_changed.connect(_on_rows_changed)
	frontage_spin.value_changed.connect(_on_frontage_changed)

	# Unit view direction buttons (rotate model/sprite view, not formation)
	unit_ccw_button.pressed.connect(_on_unit_ccw_pressed)
	unit_cw_button.pressed.connect(_on_unit_cw_pressed)
	save_front_button.pressed.connect(_on_save_front_pressed)


func _setup_3d_scene() -> void:
	# Setup ground plane
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(100, 100)
	ground_plane.mesh = plane_mesh

	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.3, 0.35, 0.25)
	ground_plane.material_override = ground_mat

	# Setup direction arrow (points in facing direction)
	_create_direction_arrow()

	# Setup LOS cone
	_create_los_cone()

	# Setup camera
	_update_camera_position()


func _create_direction_arrow() -> void:
	## Creates arrow pointing in -Z direction (North), will be rotated by facing angle
	var immediate_mesh := ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var shaft_width := 0.5
	var shaft_length := 8.0
	var head_width := 1.5
	var head_length := 3.0

	# Arrow pointing -Z (North direction in WorldCompass)
	# Shaft
	immediate_mesh.surface_add_vertex(Vector3(-shaft_width, 0.15, 0))
	immediate_mesh.surface_add_vertex(Vector3(shaft_width, 0.15, 0))
	immediate_mesh.surface_add_vertex(Vector3(shaft_width, 0.15, -shaft_length))

	immediate_mesh.surface_add_vertex(Vector3(-shaft_width, 0.15, 0))
	immediate_mesh.surface_add_vertex(Vector3(shaft_width, 0.15, -shaft_length))
	immediate_mesh.surface_add_vertex(Vector3(-shaft_width, 0.15, -shaft_length))

	# Arrow head
	immediate_mesh.surface_add_vertex(Vector3(-head_width, 0.15, -shaft_length))
	immediate_mesh.surface_add_vertex(Vector3(head_width, 0.15, -shaft_length))
	immediate_mesh.surface_add_vertex(Vector3(0, 0.15, -shaft_length - head_length))

	immediate_mesh.surface_end()

	direction_arrow.mesh = immediate_mesh

	var arrow_mat := StandardMaterial3D.new()
	arrow_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.9)
	arrow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arrow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	direction_arrow.material_override = arrow_mat


func _create_los_cone() -> void:
	_update_los_cone_mesh()


func _update_los_cone_mesh() -> void:
	## Creates LOS cone pointing -Z (North), will be rotated by facing angle
	var immediate_mesh := ImmediateMesh.new()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 32
	var half_angle := deg_to_rad(los_angle / 2.0)

	for i in range(segments):
		# Angles relative to -Z (North)
		var angle1 := -half_angle + (float(i) / segments) * 2.0 * half_angle
		var angle2 := -half_angle + (float(i + 1) / segments) * 2.0 * half_angle

		# Points on the cone edge
		var x1 := sin(angle1) * los_range
		var z1 := -cos(angle1) * los_range
		var x2 := sin(angle2) * los_range
		var z2 := -cos(angle2) * los_range

		# Triangle from origin to edge
		immediate_mesh.surface_add_vertex(Vector3(0, 0.1, 0))
		immediate_mesh.surface_add_vertex(Vector3(x1, 0.1, z1))
		immediate_mesh.surface_add_vertex(Vector3(x2, 0.1, z2))

	immediate_mesh.surface_end()

	los_cone.mesh = immediate_mesh

	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 0.8, 0.2, 0.25)
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	los_cone.material_override = cone_mat


func _setup_multimesh() -> void:
	var quad := QuadMesh.new()
	quad.size = SPRITE_SCALE
	quad.orientation = PlaneMesh.FACE_Z

	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_SOLDIERS

	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	formation_root.add_child(_multimesh_instance)

	_soldier_positions.resize(MAX_SOLDIERS)
	_soldier_alive.resize(MAX_SOLDIERS)
	_soldier_directions.resize(MAX_SOLDIERS)
	_soldier_time_offsets.resize(MAX_SOLDIERS)

	for i in MAX_SOLDIERS:
		_soldier_positions[i] = Vector3.ZERO
		_soldier_alive[i] = 0.0
		_soldier_directions[i] = 0.0
		_soldier_time_offsets[i] = randf()


func _is_using_3d_models() -> bool:
	match render_mode:
		RenderMode.MODELS_3D:
			return true
		RenderMode.SPRITES_2D:
			return false
		RenderMode.AUTO:
			# AUTO: Prefer sprites if regiment has a sprite atlas
			# Only use 3D models if regiment explicitly has artillery_model or unit-specific model
			if current_regiment and current_regiment.sprite_atlas and current_regiment.sprite_atlas.texture:
				return false  # Has valid sprites, use them
			# Fall back to 3D models only if we have one
			return _model_scene != null
	return false


func _load_model_scene() -> void:
	_model_scene = null

	if current_regiment:
		# Only use artillery model if explicitly set
		if current_regiment.artillery_model:
			_model_scene = current_regiment.artillery_model
			return

		# Look for unit-specific 3D model (not the generic fallback)
		var regiment_name := current_regiment.regiment_name.to_lower().replace(" ", "_")
		var possible_paths := [
			"res://assets/models/units/%s.glb" % regiment_name,
			"res://assets/models/%s.glb" % regiment_name,
		]

		for path in possible_paths:
			if ResourceLoader.exists(path):
				_model_scene = load(path)
				break

	# Load generic model only for MODELS_3D mode (not AUTO)
	if _model_scene == null and render_mode == RenderMode.MODELS_3D:
		if ResourceLoader.exists("res://soldier_regiment.glb"):
			_model_scene = load("res://soldier_regiment.glb")


func _setup_shader_material() -> void:
	if not current_regiment or not current_regiment.sprite_atlas:
		_multimesh_instance.material_override = null
		return

	_shader = load("res://battle_system/shaders/unit_sprite.gdshader")
	if not _shader:
		push_error("FormationViewer: Failed to load shader!")
		return

	_material = ShaderMaterial.new()
	_material.shader = _shader

	var atlas: SpriteUnitAtlas = current_regiment.sprite_atlas
	if atlas.texture:
		_material.set_shader_parameter("sprite_atlas", atlas.texture)

	_material.set_shader_parameter("atlas_columns", atlas.columns)
	_material.set_shader_parameter("atlas_rows", atlas.rows)
	_material.set_shader_parameter("anim_speed", atlas.animation_speed)
	_material.set_shader_parameter("debug_mode", false)

	var dir_row_map := PackedInt32Array()
	dir_row_map.resize(8)
	for i in range(8):
		if atlas.direction_rows.has(i):
			dir_row_map[i] = mini(int(atlas.direction_rows[i]), atlas.rows - 1)
		else:
			dir_row_map[i] = mini(i, atlas.rows - 1)
	_material.set_shader_parameter("direction_row_map", dir_row_map)

	var dir_frame_map := PackedInt32Array()
	dir_frame_map.resize(8)
	for i in range(8):
		dir_frame_map[i] = 0
	_material.set_shader_parameter("direction_frame_map", dir_frame_map)

	var death_start := atlas.get_animation_start("death")
	var death_frames := atlas.get_animation_frame_count("death")
	_material.set_shader_parameter("death_anim_start", death_start)
	_material.set_shader_parameter("death_anim_frames", death_frames)

	_multimesh_instance.material_override = _material
	_set_animation_params("idle")


func _load_regiment(path: String) -> void:
	current_regiment = load(path) as RegimentData
	if not current_regiment:
		push_error("Failed to load regiment: " + path)
		return

	current_regiment_path = path
	current_soldier_count = current_regiment.max_soldiers
	soldier_count_spin.value = current_soldier_count

	# Load saved sprite front direction
	unit_view_dir_index = current_regiment.sprite_front_direction

	_load_model_scene()
	_setup_shader_material()
	_populate_animations()
	_rebuild_formation()

	var mode_str := "3D Models" if _is_using_3d_models() else "2D Sprites"
	var front_dir := WorldCompassScript.direction_name(current_regiment.sprite_front_direction, true)
	status_label.text = "Loaded: %s (%s, front=%s)" % [current_regiment.regiment_name, mode_str, front_dir]


func _clear_model_instances() -> void:
	for model in _model_instances:
		if is_instance_valid(model):
			model.queue_free()
	_model_instances.clear()


func _rebuild_formation() -> void:
	if not current_regiment:
		return

	# Get facing direction vector from WorldCompass (for formation positions)
	var facing := WorldCompassScript.vector_from_direction(current_facing_dir_index)

	# Calculate formation positions using custom editable parameters
	var center := Vector3.ZERO
	var positions: Array[Vector3] = _calculate_custom_positions(
		current_soldier_count,
		center,
		facing
	)

	# Get Godot rotation angle for the UNIT VIEW direction (not formation front)
	# This controls how the models/sprites visually face
	var unit_rotation_y: float = WorldCompassScript.angle_from_direction(unit_view_dir_index)

	# Direction arrow points in formation front direction
	var formation_rotation_y: float = WorldCompassScript.angle_from_direction(current_facing_dir_index)
	direction_arrow.rotation.y = formation_rotation_y

	# LOS cone aligned with formation front
	los_cone.rotation.y = formation_rotation_y

	if _is_using_3d_models():
		# 3D models use unit view direction for rotation
		_rebuild_formation_3d_models(positions, unit_rotation_y)
	else:
		# Sprites use unit view direction index for sprite row selection
		_rebuild_formation_sprites(positions, unit_view_dir_index)

	# Update formation front label
	var formation_dir_name := WorldCompassScript.direction_name(current_facing_dir_index, true)
	var formation_degrees := current_facing_dir_index * 45
	rotation_label.text = "%s (%d°)" % [formation_dir_name, formation_degrees]

	# Update unit view direction label
	var unit_dir_name := WorldCompassScript.direction_name(unit_view_dir_index, true)
	var unit_degrees := unit_view_dir_index * 45
	unit_view_dir_label.text = "%s (%d°)" % [unit_dir_name, unit_degrees]


func _calculate_custom_positions(soldier_count: int, center: Vector3, facing: Vector3) -> Array[Vector3]:
	## Calculate soldier positions using custom editable parameters.
	var positions: Array[Vector3] = []

	# Calculate formation dimensions using custom parameters
	var cols: int = ceili(float(soldier_count) / float(custom_rows))

	# Calculate basis vectors
	facing = facing.normalized()
	facing.y = 0
	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	# Standard grid formation with custom parameters
	var soldier_idx: int = 0
	for row in custom_rows:
		for col in cols:
			if soldier_idx >= soldier_count:
				break

			var x_offset: float = (col - (cols - 1) / 2.0) * custom_spacing * custom_frontage
			var z_offset: float = (row - (custom_rows - 1) / 2.0) * custom_depth

			var pos: Vector3 = center + right * x_offset - facing * z_offset
			positions.append(pos)
			soldier_idx += 1

	return positions


func _rebuild_formation_3d_models(positions: Array[Vector3], model_rotation_y: float) -> void:
	# Hide sprite multimesh
	_multimesh_instance.visible = false

	# Clear existing models
	_clear_model_instances()

	if not _model_scene:
		return

	# Spawn models
	for i in range(positions.size()):
		var model: Node3D = _model_scene.instantiate() as Node3D
		if not model:
			continue

		model.position = positions[i]
		# Rotate model to face the formation front direction
		model.rotation.y = model_rotation_y

		# Apply scale
		var scale_factor := MODEL_SCALE
		if current_regiment.artillery_model:
			scale_factor = current_regiment.artillery_model_scale
		model.scale = scale_factor

		formation_root.add_child(model)
		_model_instances.append(model)

		# Start animation with offset for variety
		var anim_player := _find_animation_player(model)
		if anim_player and anim_player.has_animation(current_animation):
			anim_player.play(current_animation)
			anim_player.seek(randf() * anim_player.current_animation_length)


func _rebuild_formation_sprites(positions: Array[Vector3], facing_dir_index: int) -> void:
	## Rebuild sprite formation with all sprites facing the given direction index (0-7)
	# Show sprite multimesh
	_multimesh_instance.visible = true

	# Clear 3D models
	_clear_model_instances()

	# Update multimesh instances - all sprites face the formation front direction
	for i in MAX_SOLDIERS:
		if i < positions.size():
			_soldier_positions[i] = positions[i] + Vector3(0, SPRITE_SCALE.y * 0.5 + HEIGHT_OFFSET, 0)
			_soldier_alive[i] = 1.0
			_soldier_directions[i] = float(facing_dir_index)  # Direct control over sprite direction
		else:
			_soldier_positions[i] = Vector3.ZERO
			_soldier_alive[i] = 0.0

		_update_sprite_instance(i)


func _update_sprite_instance(index: int) -> void:
	var xform := Transform3D()
	xform.origin = _soldier_positions[index]
	_multimesh.set_instance_transform(index, xform)

	var custom := Color(
		_soldier_time_offsets[index],
		_soldier_directions[index],
		_soldier_alive[index],
		0.0
	)
	_multimesh.set_instance_custom_data(index, custom)


func _find_animation_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _set_animation_params(anim_name: String) -> void:
	if not current_regiment or not current_regiment.sprite_atlas or not _material:
		return

	var atlas: SpriteUnitAtlas = current_regiment.sprite_atlas
	var default_start := atlas.get_animation_start(anim_name)
	var default_frames := atlas.get_animation_frame_count(anim_name)

	var dir_frame_map := PackedInt32Array()
	var dir_row_map := PackedInt32Array()
	dir_frame_map.resize(8)
	dir_row_map.resize(8)

	for i in range(8):
		dir_frame_map[i] = atlas.get_animation_start_for_direction(anim_name, i)
		dir_row_map[i] = atlas.get_row_for_direction_and_anim(anim_name, i)

	_material.set_shader_parameter("current_anim_start", default_start)
	_material.set_shader_parameter("current_anim_frames", default_frames)
	_material.set_shader_parameter("direction_frame_map", dir_frame_map)
	_material.set_shader_parameter("direction_row_map", dir_row_map)


func _update_animations(_delta: float) -> void:
	# Animations are handled by AnimationPlayer (3D) or shader TIME (sprites)
	pass


func _update_camera_position() -> void:
	var height := camera_distance * 0.6
	var horizontal := camera_distance * 0.8

	camera_3d.position = Vector3(
		sin(camera_orbit_angle) * horizontal,
		height,
		cos(camera_orbit_angle) * horizontal
	)
	camera_3d.look_at(Vector3.ZERO, Vector3.UP)


# === Signal handlers ===

func _on_unit_selected(index: int) -> void:
	if index >= 0 and index < regiment_paths.size():
		_load_regiment(regiment_paths[index])


func _on_soldier_count_changed(value: float) -> void:
	current_soldier_count = int(value)
	_rebuild_formation()


func _on_formation_selected(index: int) -> void:
	current_formation = formation_dropdown.get_item_id(index)

	# Load formation preset values into the editing spinboxes
	var info: FormationDataScript.FormationInfo = FormationDataScript.get_formation(current_formation)
	if info:
		custom_spacing = info.spacing
		custom_depth = info.depth_spacing
		custom_rows = info.rows
		custom_frontage = info.frontage_mult

		# Update UI without triggering signals (block signals temporarily)
		spacing_spin.set_block_signals(true)
		depth_spin.set_block_signals(true)
		rows_spin.set_block_signals(true)
		frontage_spin.set_block_signals(true)

		spacing_spin.value = custom_spacing
		depth_spin.value = custom_depth
		rows_spin.value = custom_rows
		frontage_spin.value = custom_frontage

		spacing_spin.set_block_signals(false)
		depth_spin.set_block_signals(false)
		rows_spin.set_block_signals(false)
		frontage_spin.set_block_signals(false)

	_rebuild_formation()


func _on_rotation_changed(value: float) -> void:
	# Slider controls formation front direction (affects positions, arrow, LOS cone)
	# 0° = North (index 0), 45° = NE (index 1), 90° = East (index 2), etc.
	current_facing_dir_index = int(value / 45.0) % 8
	_rebuild_formation()


func _on_unit_ccw_pressed() -> void:
	## Rotate unit view direction counter-clockwise by 45 degrees
	## This only affects how models/sprites visually face, not formation positions
	unit_view_dir_index = (unit_view_dir_index - 1 + 8) % 8
	_rebuild_formation()


func _on_unit_cw_pressed() -> void:
	## Rotate unit view direction clockwise by 45 degrees
	## This only affects how models/sprites visually face, not formation positions
	unit_view_dir_index = (unit_view_dir_index + 1) % 8
	_rebuild_formation()


func _on_save_front_pressed() -> void:
	## Save the current unit view direction as the regiment's sprite front direction
	if not current_regiment:
		status_label.text = "No regiment loaded!"
		return

	if current_regiment_path.is_empty():
		status_label.text = "No regiment path set!"
		return

	# Update the regiment data
	current_regiment.sprite_front_direction = unit_view_dir_index

	# Save the resource back to disk
	var error := ResourceSaver.save(current_regiment, current_regiment_path)
	if error == OK:
		var dir_name := WorldCompassScript.direction_name(unit_view_dir_index, true)
		status_label.text = "Saved! Front direction = %s (%d)" % [dir_name, unit_view_dir_index]
		print("[FormationEditor] Saved sprite_front_direction=%d (%s) to %s" % [
			unit_view_dir_index, dir_name, current_regiment_path
		])
	else:
		status_label.text = "Save FAILED! Error: %d" % error
		push_error("Failed to save regiment: " + current_regiment_path)


func _on_animation_selected(index: int) -> void:
	var display_name := anim_dropdown.get_item_text(index)
	current_animation = anim_key_map.get(display_name, display_name)

	if _is_using_3d_models():
		for model in _model_instances:
			var anim_player := _find_animation_player(model)
			if anim_player and anim_player.has_animation(current_animation):
				anim_player.play(current_animation)
	else:
		_set_animation_params(current_animation)


func _on_play_pressed() -> void:
	is_playing = not is_playing
	play_button.text = "Stop" if is_playing else "Play"

	if _is_using_3d_models():
		for model in _model_instances:
			var anim_player := _find_animation_player(model)
			if anim_player:
				if is_playing:
					anim_player.play(current_animation)
				else:
					anim_player.pause()


func _on_camera_orbit_changed(value: float) -> void:
	camera_orbit_angle = deg_to_rad(value)
	_update_camera_position()
	# Note: Sprites now use world-space direction directly (controlled by rotation slider)
	# so we don't need to rebuild when camera moves


func _on_camera_zoom_changed(value: float) -> void:
	camera_distance = value
	_update_camera_position()


func _on_los_angle_changed(value: float) -> void:
	los_angle = value
	_update_los_cone_mesh()


func _on_los_range_changed(value: float) -> void:
	los_range = value
	_update_los_cone_mesh()


func _on_render_mode_changed(index: int) -> void:
	render_mode = index as RenderMode
	# Reload model scene based on new render mode
	_load_model_scene()
	_rebuild_formation()
	_populate_animations()

	var mode_str := "3D Models" if _is_using_3d_models() else "2D Sprites"
	status_label.text = "Mode: %s" % mode_str


# === Formation Editing Handlers ===

func _on_spacing_changed(value: float) -> void:
	custom_spacing = value
	_rebuild_formation()


func _on_depth_changed(value: float) -> void:
	custom_depth = value
	_rebuild_formation()


func _on_rows_changed(value: float) -> void:
	custom_rows = int(value)
	_rebuild_formation()


func _on_frontage_changed(value: float) -> void:
	custom_frontage = value
	_rebuild_formation()


func _input(event: InputEvent) -> void:
	if not viewport_container.get_global_rect().has_point(get_global_mouse_position()):
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				# Rotate unit view CCW
				_on_unit_ccw_pressed()
			KEY_RIGHT:
				# Rotate unit view CW
				_on_unit_cw_pressed()
			KEY_SPACE:
				_on_play_pressed()
			KEY_Q:
				camera_orbit_slider.value -= 15
			KEY_E:
				camera_orbit_slider.value += 15
			KEY_MINUS, KEY_KP_SUBTRACT:
				camera_zoom_slider.value += 5
			KEY_EQUAL, KEY_KP_ADD:
				camera_zoom_slider.value -= 5
