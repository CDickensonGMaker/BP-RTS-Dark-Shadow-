@tool
extends Control
## 3D Model Viewer Dock - Preview and scale 3D models with reference objects

const MODELS_PATH := "res://assets/models/"
const REGIMENTS_PATH := "res://battle_system/data/regiments/"

# Map of model files to their wrapper scene files (for "Save to Scene" feature)
const MODEL_SCENE_MAP := {
	"res://assets/models/arrow.glb": "res://battle_system/nodes/arrow_3d.tscn",
	"res://assets/models/3d units/great_cannon.glb": "res://assets/models/3d units/artillery_great_cannon.tscn",
	"res://assets/models/3d units/medieval_mortar.glb": "res://assets/models/3d units/artillery_mortar.tscn",
	"res://assets/models/3d units/great_catapult.glb": "res://assets/models/3d units/artillery_catapult.tscn",
}

# Reference dimensions
const SOLDIER_HEIGHT := 1.8  # meters (reference soldier)
const GRID_SIZE := 20.0      # meters square
const GRID_DIVISIONS := 20   # 1m per division

# UI References
@onready var model_list: ItemList = $HSplitContainer/LeftPanel/VBoxContainer/ModelList
@onready var filter_line: LineEdit = $HSplitContainer/LeftPanel/VBoxContainer/FilterContainer/FilterLine
@onready var folder_dropdown: OptionButton = $HSplitContainer/LeftPanel/VBoxContainer/FolderContainer/FolderDropdown
@onready var viewport_container: SubViewportContainer = $HSplitContainer/CenterPanel/ViewportContainer
@onready var viewport_3d: SubViewport = $HSplitContainer/CenterPanel/ViewportContainer/SubViewport
@onready var camera_3d: Camera3D = $HSplitContainer/CenterPanel/ViewportContainer/SubViewport/Camera3D
@onready var model_root: Node3D = $HSplitContainer/CenterPanel/ViewportContainer/SubViewport/ModelRoot
@onready var grid_mesh: MeshInstance3D = $HSplitContainer/CenterPanel/ViewportContainer/SubViewport/GridMesh
@onready var reference_soldier: MeshInstance3D = $HSplitContainer/CenterPanel/ViewportContainer/SubViewport/ReferenceSoldier
@onready var bounds_wireframe: MeshInstance3D = $HSplitContainer/CenterPanel/ViewportContainer/SubViewport/BoundsWireframe
@onready var directional_light: DirectionalLight3D = $HSplitContainer/CenterPanel/ViewportContainer/SubViewport/DirectionalLight3D

# Scale controls
@onready var scale_x_slider: HSlider = $HSplitContainer/RightPanel/VBoxContainer/ScalePanel/ScaleX/ScaleXSlider
@onready var scale_y_slider: HSlider = $HSplitContainer/RightPanel/VBoxContainer/ScalePanel/ScaleY/ScaleYSlider
@onready var scale_z_slider: HSlider = $HSplitContainer/RightPanel/VBoxContainer/ScalePanel/ScaleZ/ScaleZSlider
@onready var uniform_check: CheckButton = $HSplitContainer/RightPanel/VBoxContainer/ScalePanel/UniformCheck
@onready var scale_value_label: Label = $HSplitContainer/RightPanel/VBoxContainer/ScalePanel/ScaleValueLabel

# Toggles
@onready var grid_check: CheckButton = $HSplitContainer/CenterPanel/TogglePanel/GridCheck
@onready var soldier_check: CheckButton = $HSplitContainer/CenterPanel/TogglePanel/SoldierCheck
@onready var bounds_check: CheckButton = $HSplitContainer/CenterPanel/TogglePanel/BoundsCheck

# Stats and status
@onready var stats_label: Label = $HSplitContainer/RightPanel/VBoxContainer/StatsPanel/StatsLabel
@onready var size_label: Label = $HSplitContainer/RightPanel/VBoxContainer/StatsPanel/SizeLabel
@onready var status_label: Label = $HSplitContainer/BottomPanel/StatusLabel

# Export buttons
@onready var export_scene_button: Button = $HSplitContainer/RightPanel/VBoxContainer/ExportPanel/ExportSceneButton
@onready var save_to_scene_button: Button = $HSplitContainer/RightPanel/VBoxContainer/ExportPanel/SaveToSceneButton
@onready var apply_regiment_button: Button = $HSplitContainer/RightPanel/VBoxContainer/ExportPanel/ApplyRegimentButton
@onready var regiment_dropdown: OptionButton = $HSplitContainer/RightPanel/VBoxContainer/ExportPanel/RegimentDropdown

# State
var current_model: Node3D = null
var current_model_path: String = ""
var current_model_aabb: AABB = AABB()
var model_paths: Array[String] = []
var regiment_paths: Array[String] = []
var folder_paths: Array[String] = []

# Camera orbit
var orbit_angle: float = 0.0
var orbit_distance: float = 10.0
var orbit_height: float = 5.0
var is_orbiting: bool = false
var last_mouse_pos: Vector2

# Scale
var model_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	_setup_3d_scene()
	_populate_folders()
	_populate_model_list()
	_populate_regiment_dropdown()
	_connect_signals()
	_update_camera_position()


func _process(_delta: float) -> void:
	# Handle camera orbit with mouse
	if is_orbiting:
		var mouse_pos := get_viewport().get_mouse_position()
		var delta := mouse_pos - last_mouse_pos
		orbit_angle += delta.x * 0.01
		orbit_height = clampf(orbit_height - delta.y * 0.05, 1.0, 30.0)
		_update_camera_position()
		last_mouse_pos = mouse_pos


func _setup_3d_scene() -> void:
	# Setup grid
	_create_grid_mesh()

	# Setup reference soldier (capsule)
	_create_reference_soldier()

	# Setup bounds wireframe
	_create_bounds_wireframe()

	# Setup lighting
	if directional_light:
		directional_light.rotation_degrees = Vector3(-45, 45, 0)


func _create_grid_mesh() -> void:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)

	var half := GRID_SIZE / 2.0
	for i in range(-GRID_DIVISIONS / 2, GRID_DIVISIONS / 2 + 1):
		var pos := float(i)
		# X lines (red tint for X axis)
		if i == 0:
			immediate.surface_set_color(Color(0.8, 0.3, 0.3, 0.8))
		else:
			immediate.surface_set_color(Color(0.5, 0.5, 0.5, 0.5))
		immediate.surface_add_vertex(Vector3(pos, 0.01, -half))
		immediate.surface_add_vertex(Vector3(pos, 0.01, half))

		# Z lines (blue tint for Z axis)
		if i == 0:
			immediate.surface_set_color(Color(0.3, 0.3, 0.8, 0.8))
		else:
			immediate.surface_set_color(Color(0.5, 0.5, 0.5, 0.5))
		immediate.surface_add_vertex(Vector3(-half, 0.01, pos))
		immediate.surface_add_vertex(Vector3(half, 0.01, pos))

	immediate.surface_end()

	if grid_mesh:
		grid_mesh.mesh = immediate
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		grid_mesh.material_override = mat


func _create_reference_soldier() -> void:
	if not reference_soldier:
		return

	var capsule := CapsuleMesh.new()
	capsule.height = SOLDIER_HEIGHT
	capsule.radius = 0.3
	reference_soldier.mesh = capsule
	reference_soldier.position = Vector3(3, SOLDIER_HEIGHT / 2.0, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.6, 0.4, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	reference_soldier.material_override = mat


func _create_bounds_wireframe() -> void:
	if not bounds_wireframe:
		return
	# Initially empty, updated when model loads
	bounds_wireframe.mesh = null


func _update_bounds_wireframe() -> void:
	if not bounds_wireframe or current_model_aabb.size == Vector3.ZERO:
		if bounds_wireframe:
			bounds_wireframe.mesh = null
		return

	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)

	var min_pt := current_model_aabb.position * model_scale
	var max_pt := (current_model_aabb.position + current_model_aabb.size) * model_scale

	# Bottom face
	immediate.surface_add_vertex(Vector3(min_pt.x, min_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, min_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, min_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, min_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, min_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, min_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, min_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, min_pt.y, min_pt.z))

	# Top face
	immediate.surface_add_vertex(Vector3(min_pt.x, max_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, max_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, max_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, max_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, max_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, max_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, max_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, max_pt.y, min_pt.z))

	# Vertical edges
	immediate.surface_add_vertex(Vector3(min_pt.x, min_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, max_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, min_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, max_pt.y, min_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, min_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(max_pt.x, max_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, min_pt.y, max_pt.z))
	immediate.surface_add_vertex(Vector3(min_pt.x, max_pt.y, max_pt.z))

	immediate.surface_end()

	bounds_wireframe.mesh = immediate
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.2, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bounds_wireframe.material_override = mat


func _populate_folders() -> void:
	if not folder_dropdown:
		return

	folder_dropdown.clear()
	folder_paths.clear()

	folder_dropdown.add_item("All Models")
	folder_paths.append("")

	folder_dropdown.add_item("3D Units (Artillery)")
	folder_paths.append("3d units")

	folder_dropdown.add_item("Props")
	folder_paths.append("props")

	folder_dropdown.add_item("Buildings")
	folder_paths.append("buildings")


func _populate_model_list() -> void:
	if not model_list:
		return

	model_list.clear()
	model_paths.clear()

	var filter := filter_line.text.to_lower() if filter_line else ""
	var folder_filter := folder_paths[folder_dropdown.selected] if folder_dropdown and folder_dropdown.selected < folder_paths.size() else ""

	_scan_models_recursive(MODELS_PATH, filter, folder_filter)

	if status_label:
		status_label.text = "Found %d models" % model_paths.size()


func _scan_models_recursive(path: String, filter: String, folder_filter: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			_scan_models_recursive(path + file_name + "/", filter, folder_filter)
		elif file_name.ends_with(".glb") or file_name.ends_with(".gltf") or file_name.ends_with(".obj"):
			var full_path := path + file_name
			var relative_path := full_path.replace(MODELS_PATH, "")

			# Apply filters
			var matches_filter := filter.is_empty() or file_name.to_lower().contains(filter)
			var matches_folder := folder_filter.is_empty() or relative_path.to_lower().begins_with(folder_filter)

			if matches_filter and matches_folder:
				model_paths.append(full_path)
				model_list.add_item(relative_path)

		file_name = dir.get_next()
	dir.list_dir_end()


func _populate_regiment_dropdown() -> void:
	if not regiment_dropdown:
		return

	regiment_dropdown.clear()
	regiment_paths.clear()

	regiment_dropdown.add_item("-- Select Regiment --")
	regiment_paths.append("")

	var dir := DirAccess.open(REGIMENTS_PATH)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var full_path := REGIMENTS_PATH + file_name
			# Check if regiment has artillery model
			var regiment := load(full_path) as Resource
			if regiment and regiment.get("artillery_model"):
				regiment_paths.append(full_path)
				regiment_dropdown.add_item(file_name.get_basename())
		file_name = dir.get_next()
	dir.list_dir_end()


func _connect_signals() -> void:
	if model_list:
		model_list.item_selected.connect(_on_model_selected)
	if filter_line:
		filter_line.text_changed.connect(_on_filter_changed)
	if folder_dropdown:
		folder_dropdown.item_selected.connect(_on_folder_selected)

	if scale_x_slider:
		scale_x_slider.value_changed.connect(_on_scale_x_changed)
	if scale_y_slider:
		scale_y_slider.value_changed.connect(_on_scale_y_changed)
	if scale_z_slider:
		scale_z_slider.value_changed.connect(_on_scale_z_changed)

	if grid_check:
		grid_check.toggled.connect(_on_grid_toggled)
	if soldier_check:
		soldier_check.toggled.connect(_on_soldier_toggled)
	if bounds_check:
		bounds_check.toggled.connect(_on_bounds_toggled)

	if export_scene_button:
		export_scene_button.pressed.connect(_on_export_scene_pressed)
	if save_to_scene_button:
		save_to_scene_button.pressed.connect(_on_save_to_scene_pressed)
	if apply_regiment_button:
		apply_regiment_button.pressed.connect(_on_apply_regiment_pressed)


func _update_camera_position() -> void:
	if not camera_3d:
		return

	camera_3d.position = Vector3(
		sin(orbit_angle) * orbit_distance,
		orbit_height,
		cos(orbit_angle) * orbit_distance
	)
	camera_3d.look_at(Vector3.ZERO, Vector3.UP)


func _load_model(path: String) -> void:
	# Clear existing model
	if current_model:
		current_model.queue_free()
		current_model = null

	current_model_path = path

	var packed := load(path) as PackedScene
	if not packed:
		if status_label:
			status_label.text = "Failed to load: " + path
		return

	current_model = packed.instantiate() as Node3D
	if not current_model:
		if status_label:
			status_label.text = "Not a 3D scene: " + path
		return

	model_root.add_child(current_model)

	# Reset scale
	model_scale = Vector3.ONE
	current_model.scale = model_scale
	_update_scale_sliders()

	# Calculate AABB
	current_model_aabb = _calculate_aabb(current_model)

	# Update displays
	_update_stats_display()
	_update_bounds_wireframe()

	# Adjust camera to fit model
	var model_size := current_model_aabb.size.length()
	orbit_distance = maxf(model_size * 2.0, 5.0)
	orbit_height = maxf(model_size, 3.0)
	_update_camera_position()

	if status_label:
		status_label.text = "Loaded: " + path.get_file()


func _calculate_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var first := true

	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst := child as MeshInstance3D
			if mesh_inst.mesh:
				var mesh_aabb := mesh_inst.mesh.get_aabb()
				# Transform to parent space
				mesh_aabb = mesh_inst.transform * mesh_aabb
				if first:
					result = mesh_aabb
					first = false
				else:
					result = result.merge(mesh_aabb)

		if child is Node3D:
			var child_aabb := _calculate_aabb(child)
			if child_aabb.size != Vector3.ZERO:
				child_aabb = child.transform * child_aabb
				if first:
					result = child_aabb
					first = false
				else:
					result = result.merge(child_aabb)

	return result


func _calculate_model_stats() -> Dictionary:
	var stats := {
		"polygon_count": 0,
		"vertex_count": 0,
		"mesh_count": 0,
		"material_count": 0,
		"node_count": 0
	}

	if current_model:
		var materials: Array[Material] = []
		_count_stats_recursive(current_model, stats, materials)
		stats["material_count"] = materials.size()

	return stats


func _count_stats_recursive(node: Node, stats: Dictionary, materials: Array) -> void:
	stats["node_count"] += 1

	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh:
			stats["mesh_count"] += 1

			for surf_idx in mesh_inst.mesh.get_surface_count():
				var arrays := mesh_inst.mesh.surface_get_arrays(surf_idx)
				if arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX]:
					stats["vertex_count"] += arrays[Mesh.ARRAY_VERTEX].size()
				if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX]:
					stats["polygon_count"] += arrays[Mesh.ARRAY_INDEX].size() / 3

				var mat := mesh_inst.mesh.surface_get_material(surf_idx)
				if mat and not materials.has(mat):
					materials.append(mat)

	for child in node.get_children():
		_count_stats_recursive(child, stats, materials)


func _update_stats_display() -> void:
	var stats := _calculate_model_stats()

	if stats_label:
		stats_label.text = """Polygons: %d
Vertices: %d
Meshes: %d
Materials: %d
Nodes: %d""" % [
			stats["polygon_count"],
			stats["vertex_count"],
			stats["mesh_count"],
			stats["material_count"],
			stats["node_count"]
		]

	if size_label:
		var scaled_size := current_model_aabb.size * model_scale
		size_label.text = "Size: %.2fm x %.2fm x %.2fm" % [
			scaled_size.x, scaled_size.y, scaled_size.z
		]


func _update_scale_sliders() -> void:
	if scale_x_slider:
		scale_x_slider.set_value_no_signal(model_scale.x)
	if scale_y_slider:
		scale_y_slider.set_value_no_signal(model_scale.y)
	if scale_z_slider:
		scale_z_slider.set_value_no_signal(model_scale.z)

	if scale_value_label:
		scale_value_label.text = "(%.2f, %.2f, %.2f)" % [model_scale.x, model_scale.y, model_scale.z]


func _apply_scale() -> void:
	if current_model:
		current_model.scale = model_scale
	_update_stats_display()
	_update_bounds_wireframe()
	_update_scale_sliders()


# === Signal Handlers ===

func _on_model_selected(index: int) -> void:
	if index >= 0 and index < model_paths.size():
		_load_model(model_paths[index])


func _on_filter_changed(_text: String) -> void:
	_populate_model_list()


func _on_folder_selected(_index: int) -> void:
	_populate_model_list()


func _on_scale_x_changed(value: float) -> void:
	if uniform_check and uniform_check.button_pressed:
		model_scale = Vector3(value, value, value)
	else:
		model_scale.x = value
	_apply_scale()


func _on_scale_y_changed(value: float) -> void:
	if uniform_check and uniform_check.button_pressed:
		model_scale = Vector3(value, value, value)
	else:
		model_scale.y = value
	_apply_scale()


func _on_scale_z_changed(value: float) -> void:
	if uniform_check and uniform_check.button_pressed:
		model_scale = Vector3(value, value, value)
	else:
		model_scale.z = value
	_apply_scale()


func _on_grid_toggled(pressed: bool) -> void:
	if grid_mesh:
		grid_mesh.visible = pressed


func _on_soldier_toggled(pressed: bool) -> void:
	if reference_soldier:
		reference_soldier.visible = pressed


func _on_bounds_toggled(pressed: bool) -> void:
	if bounds_wireframe:
		bounds_wireframe.visible = pressed


func _on_export_scene_pressed() -> void:
	if current_model_path.is_empty():
		if status_label:
			status_label.text = "No model loaded!"
		return

	var output_name := current_model_path.get_file().get_basename() + "_scaled.tscn"
	var output_path := current_model_path.get_base_dir() + "/" + output_name

	var content := _generate_tscn_content()

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		if status_label:
			status_label.text = "Exported: " + output_name
	else:
		if status_label:
			status_label.text = "Export failed!"


func _generate_tscn_content() -> String:
	var model_name := current_model_path.get_file().get_basename()
	var lines: Array[String] = []

	lines.append('[gd_scene load_steps=2 format=3]')
	lines.append('')
	lines.append('[ext_resource type="PackedScene" path="%s" id="1_model"]' % current_model_path)
	lines.append('')
	lines.append('[node name="%s" type="Node3D"]' % model_name.capitalize().replace("_", ""))
	lines.append('')
	lines.append('[node name="Model" parent="." instance=ExtResource("1_model")]')
	lines.append('transform = Transform3D(%f, 0, 0, 0, %f, 0, 0, 0, %f, 0, 0, 0)' % [
		model_scale.x, model_scale.y, model_scale.z
	])
	lines.append('')

	return "\n".join(lines)


func _on_save_to_scene_pressed() -> void:
	## Save the current scale to the model's existing wrapper scene file
	if current_model_path.is_empty():
		if status_label:
			status_label.text = "No model loaded!"
		return

	# Check if this model has a known scene mapping
	var scene_path: String = MODEL_SCENE_MAP.get(current_model_path, "")
	if scene_path.is_empty():
		if status_label:
			status_label.text = "No scene mapping for this model. Use 'Export as Scene' instead."
		return

	# Read the existing scene file to get its UID
	var existing_content := FileAccess.get_file_as_string(scene_path)
	if existing_content.is_empty():
		if status_label:
			status_label.text = "Could not read: " + scene_path
		return

	# Extract UID from existing file
	var uid_line := ""
	for line in existing_content.split("\n"):
		if line.contains("uid="):
			uid_line = line
			break

	# Generate updated scene content
	var lines: Array[String] = []
	lines.append(uid_line if not uid_line.is_empty() else '[gd_scene load_steps=2 format=3]')
	lines.append('')
	lines.append('[ext_resource type="PackedScene" path="%s" id="1_model"]' % current_model_path)
	lines.append('')

	# Get root node name from existing scene
	var root_name := scene_path.get_file().get_basename().to_pascal_case()
	lines.append('[node name="%s" type="Node3D"]' % root_name)
	lines.append('')
	lines.append('[node name="Model" parent="." instance=ExtResource("1_model")]')
	lines.append('transform = Transform3D(%f, 0, 0, 0, %f, 0, 0, 0, %f, 0, 0, 0)' % [
		model_scale.x, model_scale.y, model_scale.z
	])
	lines.append('')

	var content := "\n".join(lines)

	var file := FileAccess.open(scene_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		if status_label:
			status_label.text = "Saved scale (%.2f) to: %s" % [model_scale.x, scene_path.get_file()]
	else:
		if status_label:
			status_label.text = "Failed to save: " + scene_path


func _on_apply_regiment_pressed() -> void:
	if not regiment_dropdown or regiment_dropdown.selected <= 0:
		if status_label:
			status_label.text = "Select a regiment first!"
		return

	var regiment_path := regiment_paths[regiment_dropdown.selected]
	var regiment := load(regiment_path) as Resource
	if not regiment:
		if status_label:
			status_label.text = "Failed to load regiment!"
		return

	regiment.set("artillery_model_scale", model_scale)

	var error := ResourceSaver.save(regiment, regiment_path)
	if error == OK:
		if status_label:
			status_label.text = "Applied scale to: " + regiment_path.get_file().get_basename()
	else:
		if status_label:
			status_label.text = "Failed to save regiment!"


func _gui_input(event: InputEvent) -> void:
	if not viewport_container:
		return

	var in_viewport := viewport_container.get_global_rect().has_point(get_global_mouse_position())

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed and in_viewport:
				is_orbiting = true
				last_mouse_pos = get_viewport().get_mouse_position()
			else:
				is_orbiting = false

		if in_viewport:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				orbit_distance = maxf(2.0, orbit_distance - 1.0)
				_update_camera_position()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				orbit_distance = minf(50.0, orbit_distance + 1.0)
				_update_camera_position()

	if event is InputEventMouseMotion and is_orbiting:
		# Handled in _process
		pass
