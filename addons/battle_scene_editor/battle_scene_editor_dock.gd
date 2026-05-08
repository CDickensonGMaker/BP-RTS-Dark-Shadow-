@tool
extends Control
class_name BattleSceneEditorDock
## Main dock UI for the Battle Scene Editor

const EXPORT_DIR := "res://battle_system/data/battle_maps/"

var map_state: BattleSceneEditorData.BattleMapState
var editor_state: BattleSceneEditorData.EditorState
var scene_file_dialog: FileDialog
var loaded_scene_path: String = ""  # Track the currently loaded scene file

# UI References
var canvas: BattleSceneEditorCanvas
var map_name_edit: LineEdit
var map_id_edit: LineEdit
var grid_width_spin: SpinBox
var grid_height_spin: SpinBox
var tool_buttons: Dictionary = {}
var terrain_grid: GridContainer
var object_grid: GridContainer
var brush_size_group: ButtonGroup
var time_option: OptionButton
var weather_option: OptionButton
var show_grid_check: CheckButton
var show_deploy_check: CheckButton
var show_objects_check: CheckButton
var status_label: Label
var zoom_label: Label


func _ready() -> void:
	map_state = BattleSceneEditorData.BattleMapState.new()
	editor_state = BattleSceneEditorData.EditorState.new()

	_build_ui()
	_connect_signals()


func _build_ui() -> void:
	custom_minimum_size = Vector2(900, 650)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 4)
	add_child(main_vbox)

	# Header
	var header := _create_header()
	main_vbox.add_child(header)

	# Main split
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = -300
	main_vbox.add_child(split)

	# LEFT: Canvas
	var canvas_container := PanelContainer.new()
	canvas_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_container.custom_minimum_size = Vector2(400, 400)
	split.add_child(canvas_container)

	canvas = BattleSceneEditorCanvas.new()
	canvas.map_state = map_state
	canvas.editor_state = editor_state
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_container.add_child(canvas)

	# RIGHT: Tools
	var tools_scroll := ScrollContainer.new()
	tools_scroll.custom_minimum_size.x = 280
	tools_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(tools_scroll)

	var tools_panel := VBoxContainer.new()
	tools_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_scroll.add_child(tools_panel)

	_create_map_settings_section(tools_panel)
	_create_tool_section(tools_panel)
	_create_terrain_palette(tools_panel)
	_create_object_palette(tools_panel)
	_create_brush_section(tools_panel)
	_create_view_section(tools_panel)
	_create_battle_settings(tools_panel)

	# Footer
	var footer := _create_footer()
	main_vbox.add_child(footer)


func _create_header() -> Control:
	var hbox := HBoxContainer.new()

	var title := Label.new()
	title.text = "Battle Scene Editor"
	title.add_theme_font_size_override("font_size", 16)
	hbox.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var fit_btn := Button.new()
	fit_btn.text = "Fit View"
	fit_btn.pressed.connect(func(): canvas.fit_to_view())
	hbox.add_child(fit_btn)

	var center_btn := Button.new()
	center_btn.text = "Center"
	center_btn.pressed.connect(func(): canvas.center_on_map())
	hbox.add_child(center_btn)

	zoom_label = Label.new()
	zoom_label.text = "Zoom: 100%"
	zoom_label.custom_minimum_size.x = 80
	hbox.add_child(zoom_label)

	return hbox


func _create_map_settings_section(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var label := Label.new()
	label.text = "Map Settings"
	section.add_child(label)

	# Name
	var name_row := HBoxContainer.new()
	name_row.add_child(_make_label("Name:"))
	map_name_edit = LineEdit.new()
	map_name_edit.placeholder_text = "Battle Map Name"
	map_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_name_edit.text_changed.connect(func(t: String): map_state.map_name = t)
	name_row.add_child(map_name_edit)
	section.add_child(name_row)

	# ID
	var id_row := HBoxContainer.new()
	id_row.add_child(_make_label("ID:"))
	map_id_edit = LineEdit.new()
	map_id_edit.placeholder_text = "battle_map_id"
	map_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_id_edit.text_changed.connect(func(t: String): map_state.map_id = t.to_snake_case())
	id_row.add_child(map_id_edit)
	section.add_child(id_row)

	# Grid size
	var size_row := HBoxContainer.new()
	size_row.add_child(_make_label("Size:"))

	grid_width_spin = SpinBox.new()
	grid_width_spin.min_value = 16
	grid_width_spin.max_value = 128
	grid_width_spin.value = 32
	grid_width_spin.custom_minimum_size.x = 60
	size_row.add_child(grid_width_spin)

	size_row.add_child(_make_label("x"))

	grid_height_spin = SpinBox.new()
	grid_height_spin.min_value = 16
	grid_height_spin.max_value = 128
	grid_height_spin.value = 32
	grid_height_spin.custom_minimum_size.x = 60
	size_row.add_child(grid_height_spin)

	var resize_btn := Button.new()
	resize_btn.text = "Resize"
	resize_btn.pressed.connect(_on_resize_pressed)
	size_row.add_child(resize_btn)

	section.add_child(size_row)


func _create_tool_section(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var label := Label.new()
	label.text = "Tool"
	section.add_child(label)

	var row := HBoxContainer.new()
	var tool_group := ButtonGroup.new()

	var tools: Array = ["terrain", "object", "deployment", "erase"]
	var tool_labels: Array = ["Terrain", "Object", "Deploy", "Erase"]

	for i: int in range(tools.size()):
		var btn := Button.new()
		btn.text = tool_labels[i]
		btn.toggle_mode = true
		btn.button_group = tool_group
		btn.button_pressed = (i == 0)
		btn.pressed.connect(_on_tool_selected.bind(tools[i]))
		tool_buttons[tools[i]] = btn
		row.add_child(btn)

	section.add_child(row)


func _create_terrain_palette(parent: Control) -> void:
	var section := VBoxContainer.new()
	section.name = "TerrainSection"
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var label := Label.new()
	label.text = "Terrain"
	section.add_child(label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(scroll)

	terrain_grid = GridContainer.new()
	terrain_grid.columns = 4
	terrain_grid.add_theme_constant_override("h_separation", 2)
	terrain_grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(terrain_grid)

	var terrain_group := ButtonGroup.new()
	for terrain: String in BattleSceneEditorData.TERRAIN_VALUES:
		var btn := Button.new()
		btn.text = terrain.capitalize().replace("_", " ").substr(0, 8)
		btn.tooltip_text = terrain.capitalize()
		btn.custom_minimum_size = Vector2(55, 28)
		btn.toggle_mode = true
		btn.button_group = terrain_group
		btn.button_pressed = (terrain == "grass")

		var color: Color = BattleSceneEditorData.TERRAIN_COLORS.get(terrain, Color.GRAY)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		style.border_width_left = 3
		style.border_color = Color.BLACK
		btn.add_theme_stylebox_override("normal", style)

		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = color.lightened(0.2)
		pressed_style.border_width_left = 3
		pressed_style.border_width_bottom = 2
		pressed_style.border_color = Color.WHITE
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.pressed.connect(_on_terrain_selected.bind(terrain))
		terrain_grid.add_child(btn)


func _create_object_palette(parent: Control) -> void:
	var section := VBoxContainer.new()
	section.name = "ObjectSection"
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var label := Label.new()
	label.text = "Objects"
	section.add_child(label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 120
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	section.add_child(scroll)

	object_grid = GridContainer.new()
	object_grid.columns = 5
	object_grid.add_theme_constant_override("h_separation", 2)
	object_grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(object_grid)

	var obj_group := ButtonGroup.new()
	for obj_type: String in BattleSceneEditorData.OBJECT_VALUES:
		var btn := Button.new()
		btn.text = BattleSceneEditorData.OBJECT_ICONS.get(obj_type, "?")
		btn.tooltip_text = obj_type.capitalize().replace("_", " ")
		btn.custom_minimum_size = Vector2(32, 32)
		btn.toggle_mode = true
		btn.button_group = obj_group
		btn.button_pressed = (obj_type == "tree_small")

		var color: Color = BattleSceneEditorData.OBJECT_COLORS.get(obj_type, Color.WHITE)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		btn.add_theme_stylebox_override("normal", style)

		btn.pressed.connect(_on_object_selected.bind(obj_type))
		object_grid.add_child(btn)


func _create_brush_section(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var row := HBoxContainer.new()
	row.add_child(_make_label("Brush:"))

	brush_size_group = ButtonGroup.new()
	for size_val: int in [1, 3, 5, 7]:
		var btn := Button.new()
		btn.text = "%d" % size_val
		btn.toggle_mode = true
		btn.button_group = brush_size_group
		btn.button_pressed = (size_val == 1)
		btn.pressed.connect(func(): editor_state.brush_size = size_val)
		row.add_child(btn)

	section.add_child(row)


func _create_view_section(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var label := Label.new()
	label.text = "View"
	section.add_child(label)

	show_grid_check = CheckButton.new()
	show_grid_check.text = "Show Grid"
	show_grid_check.button_pressed = true
	show_grid_check.toggled.connect(func(p: bool): editor_state.show_grid = p; canvas.queue_redraw())
	section.add_child(show_grid_check)

	show_deploy_check = CheckButton.new()
	show_deploy_check.text = "Show Deployment"
	show_deploy_check.button_pressed = true
	show_deploy_check.toggled.connect(func(p: bool): editor_state.show_deployment = p; canvas.queue_redraw())
	section.add_child(show_deploy_check)

	show_objects_check = CheckButton.new()
	show_objects_check.text = "Show Objects"
	show_objects_check.button_pressed = true
	show_objects_check.toggled.connect(func(p: bool): editor_state.show_objects = p; canvas.queue_redraw())
	section.add_child(show_objects_check)


func _create_battle_settings(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var label := Label.new()
	label.text = "Battle Settings"
	section.add_child(label)

	# Time of day
	var time_row := HBoxContainer.new()
	time_row.add_child(_make_label("Time:"))
	time_option = OptionButton.new()
	time_option.add_item("Day")
	time_option.add_item("Dawn")
	time_option.add_item("Dusk")
	time_option.add_item("Night")
	time_option.item_selected.connect(_on_time_changed)
	time_row.add_child(time_option)
	section.add_child(time_row)

	# Weather
	var weather_row := HBoxContainer.new()
	weather_row.add_child(_make_label("Weather:"))
	weather_option = OptionButton.new()
	weather_option.add_item("Clear")
	weather_option.add_item("Rain")
	weather_option.add_item("Fog")
	weather_option.add_item("Snow")
	weather_option.item_selected.connect(_on_weather_changed)
	weather_row.add_child(weather_option)
	section.add_child(weather_row)


func _create_footer() -> Control:
	var vbox := VBoxContainer.new()

	var row := HBoxContainer.new()

	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.pressed.connect(_on_new_pressed)
	row.add_child(new_btn)

	var save_btn := Button.new()
	save_btn.text = "Save JSON"
	save_btn.pressed.connect(_on_save_pressed)
	row.add_child(save_btn)

	var load_btn := Button.new()
	load_btn.text = "Load JSON"
	load_btn.pressed.connect(_on_load_pressed)
	row.add_child(load_btn)

	var open_scene_btn := Button.new()
	open_scene_btn.text = "Open Scene"
	open_scene_btn.tooltip_text = "Open an existing .tscn battle map for editing"
	open_scene_btn.pressed.connect(_on_open_scene_pressed)
	row.add_child(open_scene_btn)

	var export_btn := Button.new()
	export_btn.text = "Export Scene"
	export_btn.tooltip_text = "Generate .tscn battle scene file"
	export_btn.pressed.connect(_on_export_scene_pressed)
	row.add_child(export_btn)

	vbox.add_child(row)

	status_label = Label.new()
	status_label.text = "Ready"
	vbox.add_child(status_label)

	# Create file dialog for opening scenes
	_create_scene_file_dialog()

	return vbox


func _create_scene_file_dialog() -> void:
	scene_file_dialog = FileDialog.new()
	scene_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	scene_file_dialog.access = FileDialog.ACCESS_RESOURCES
	scene_file_dialog.filters = PackedStringArray(["*.tscn ; Godot Scene Files"])
	scene_file_dialog.current_dir = EXPORT_DIR
	scene_file_dialog.title = "Open Battle Map Scene"
	scene_file_dialog.size = Vector2i(700, 500)
	scene_file_dialog.file_selected.connect(_on_scene_file_selected)
	add_child(scene_file_dialog)


func _connect_signals() -> void:
	canvas.terrain_painted.connect(_on_terrain_painted)
	canvas.terrain_erased.connect(_on_terrain_erased)
	canvas.object_placed.connect(_on_object_placed)
	canvas.object_removed.connect(_on_object_removed)
	canvas.canvas_zoomed.connect(_on_canvas_zoomed)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 55
	return label


# --- Event handlers ---

func _on_tool_selected(tool_name: String) -> void:
	editor_state.current_tool = tool_name


func _on_terrain_selected(terrain: String) -> void:
	editor_state.current_terrain = terrain
	editor_state.current_tool = "terrain"
	if tool_buttons.has("terrain"):
		tool_buttons["terrain"].button_pressed = true


func _on_object_selected(obj_type: String) -> void:
	editor_state.current_object = obj_type
	editor_state.current_tool = "object"
	if tool_buttons.has("object"):
		tool_buttons["object"].button_pressed = true


func _on_terrain_painted(x: int, y: int, terrain: String) -> void:
	map_state.set_terrain(x, y, terrain)
	canvas.queue_redraw()


func _on_terrain_erased(x: int, y: int) -> void:
	map_state.set_terrain(x, y, "grass")
	canvas.queue_redraw()


func _on_object_placed(x: int, y: int, obj_type: String) -> void:
	# Check if deployment zone marker
	if obj_type == "deployment_player":
		map_state.player_deployment.position = Vector2(x, y)
		_set_status("Set player deployment at (%d, %d)" % [x, y])
	elif obj_type == "deployment_enemy":
		map_state.enemy_deployment.position = Vector2(x, y)
		_set_status("Set enemy deployment at (%d, %d)" % [x, y])
	else:
		map_state.add_object(obj_type, x, y)
	canvas.queue_redraw()


func _on_object_removed(x: int, y: int) -> void:
	map_state.remove_object_at(x, y)
	canvas.queue_redraw()


func _on_canvas_zoomed(zoom: float) -> void:
	zoom_label.text = "Zoom: %d%%" % int(zoom * 100)


func _on_resize_pressed() -> void:
	var new_w: int = int(grid_width_spin.value)
	var new_h: int = int(grid_height_spin.value)
	map_state.resize(new_w, new_h)
	canvas.queue_redraw()
	_set_status("Resized to %dx%d" % [new_w, new_h])


func _on_time_changed(index: int) -> void:
	var times: Array = ["day", "dawn", "dusk", "night"]
	if index >= 0 and index < times.size():
		map_state.time_of_day = times[index]


func _on_weather_changed(index: int) -> void:
	var weathers: Array = ["clear", "rain", "fog", "snow"]
	if index >= 0 and index < weathers.size():
		map_state.weather = weathers[index]


# --- File operations ---

func _on_new_pressed() -> void:
	map_state = BattleSceneEditorData.BattleMapState.new()
	editor_state = BattleSceneEditorData.EditorState.new()
	canvas.map_state = map_state
	canvas.editor_state = editor_state
	map_name_edit.text = ""
	map_id_edit.text = ""
	grid_width_spin.value = 32
	grid_height_spin.value = 32
	loaded_scene_path = ""  # Clear any loaded scene reference
	canvas.queue_redraw()
	_set_status("New map created")


func _on_save_pressed() -> void:
	if map_state.map_id.is_empty():
		_set_status("Set a map ID first!")
		return

	var dir_path := "user://battle_maps/"
	DirAccess.make_dir_recursive_absolute(dir_path)

	var file_path := dir_path + map_state.map_id + ".json"
	var data: Dictionary = map_state.to_dict()
	var json_str: String = JSON.stringify(data, "  ")

	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		_set_status("Saved: %s" % file_path)
	else:
		_set_status("Failed to save!")


func _on_load_pressed() -> void:
	# For now, prompt for ID
	if map_id_edit.text.is_empty():
		_set_status("Enter map ID to load")
		return

	var file_path := "user://battle_maps/" + map_id_edit.text + ".json"
	if not FileAccess.file_exists(file_path):
		_set_status("File not found: %s" % file_path)
		return

	var file := FileAccess.open(file_path, FileAccess.READ)
	if not file:
		_set_status("Failed to open file!")
		return

	var json_str: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		_set_status("JSON parse error!")
		return

	if json.data is Dictionary:
		map_state.from_dict(json.data)
		map_name_edit.text = map_state.map_name
		grid_width_spin.value = map_state.grid_width
		grid_height_spin.value = map_state.grid_height
		canvas.queue_redraw()
		_set_status("Loaded: %s" % file_path)


func _on_export_scene_pressed() -> void:
	if map_state.map_id.is_empty():
		_set_status("Set a map ID first!")
		return

	# Use original path if editing existing scene, otherwise create new path
	var scene_path: String
	if not loaded_scene_path.is_empty() and map_state.map_id == loaded_scene_path.get_file().get_basename():
		scene_path = loaded_scene_path
	else:
		scene_path = EXPORT_DIR + map_state.map_id + ".tscn"

	# Build scene content
	var tscn_content := _generate_tscn_content()

	# Ensure directory exists
	DirAccess.make_dir_recursive_absolute(scene_path.get_base_dir())

	var file := FileAccess.open(scene_path, FileAccess.WRITE)
	if file:
		file.store_string(tscn_content)
		file.close()
		loaded_scene_path = scene_path  # Update tracked path
		_set_status("Exported scene: %s" % scene_path)
	else:
		_set_status("Failed to export scene!")


func _generate_tscn_content() -> String:
	# Generate a basic .tscn file structure
	var lines: Array[String] = []

	lines.append('[gd_scene format=3]')
	lines.append('')
	lines.append('[node name="%s" type="Node3D"]' % map_state.map_name.replace(" ", ""))
	lines.append('')

	# Add comment with map info
	lines.append('# Battle Map: %s' % map_state.map_name)
	lines.append('# Size: %dx%d tiles' % [map_state.grid_width, map_state.grid_height])
	lines.append('# Time: %s, Weather: %s' % [map_state.time_of_day, map_state.weather])
	lines.append('')

	# Terrain node (placeholder)
	lines.append('[node name="Terrain" type="Node3D" parent="."]')
	lines.append('')

	# Deployment markers
	lines.append('[node name="PlayerDeployment" type="Marker3D" parent="."]')
	var player_pos := Vector3(
		map_state.player_deployment.position.x * map_state.tile_size,
		0,
		map_state.player_deployment.position.y * map_state.tile_size
	)
	lines.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %f, 0, %f)' % [player_pos.x, player_pos.z])
	lines.append('')

	lines.append('[node name="EnemyDeployment" type="Marker3D" parent="."]')
	var enemy_pos := Vector3(
		map_state.enemy_deployment.position.x * map_state.tile_size,
		0,
		map_state.enemy_deployment.position.y * map_state.tile_size
	)
	lines.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %f, 0, %f)' % [enemy_pos.x, enemy_pos.z])
	lines.append('')

	# Objects container
	lines.append('[node name="Objects" type="Node3D" parent="."]')

	return "\n".join(lines)


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
	print("[BattleSceneEditor] %s" % text)


# --- Scene Import ---

func _on_open_scene_pressed() -> void:
	if scene_file_dialog:
		scene_file_dialog.current_dir = EXPORT_DIR
		scene_file_dialog.popup_centered()


func _on_scene_file_selected(path: String) -> void:
	_import_scene_file(path)


func _import_scene_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		_set_status("Scene file not found: %s" % path)
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		_set_status("Failed to open scene file!")
		return

	var content: String = file.get_as_text()
	file.close()

	# Parse the .tscn file
	var parsed := _parse_tscn_content(content)
	if parsed.is_empty():
		_set_status("Failed to parse scene file!")
		return

	# Create new map state and populate from parsed data
	map_state = BattleSceneEditorData.BattleMapState.new()

	# Set basic properties
	map_state.map_name = parsed.get("map_name", "Unnamed Battle")
	map_state.map_id = path.get_file().get_basename()
	map_state.grid_width = parsed.get("grid_width", 32)
	map_state.grid_height = parsed.get("grid_height", 32)
	map_state.time_of_day = parsed.get("time_of_day", "day")
	map_state.weather = parsed.get("weather", "clear")

	# Resize terrain grid to match
	map_state.resize(map_state.grid_width, map_state.grid_height)

	# Set deployment positions
	var player_pos: Vector2 = parsed.get("player_deployment_pos", Vector2(2, 2))
	var enemy_pos: Vector2 = parsed.get("enemy_deployment_pos", Vector2(22, 24))
	map_state.player_deployment.position = player_pos
	map_state.enemy_deployment.position = enemy_pos

	# Track the loaded file
	loaded_scene_path = path

	# Update UI
	_update_ui_from_map_state()

	canvas.map_state = map_state
	canvas.queue_redraw()

	_set_status("Opened: %s (%dx%d)" % [path.get_file(), map_state.grid_width, map_state.grid_height])


func _parse_tscn_content(content: String) -> Dictionary:
	var result: Dictionary = {}

	var lines := content.split("\n")

	for line in lines:
		line = line.strip_edges()

		# Parse root node name: [node name="MapName" type="Node3D"]
		if line.begins_with("[node name=") and 'type="Node3D"]' in line and 'parent=' not in line:
			var name_match := _extract_quoted_value(line, "name")
			if not name_match.is_empty():
				# Convert PascalCase to readable name
				result["map_name"] = _pascal_to_title(name_match)

		# Parse comments for size, time, weather
		# # Size: 34x34 tiles
		if line.begins_with("# Size:"):
			var size_part: String = line.substr(7).strip_edges()
			var size_match: RegEx = RegEx.new()
			size_match.compile("(\\d+)x(\\d+)")
			var match_result := size_match.search(size_part)
			if match_result:
				result["grid_width"] = int(match_result.get_string(1))
				result["grid_height"] = int(match_result.get_string(2))

		# # Time: dawn, Weather: fog
		if line.begins_with("# Time:"):
			var settings_part: String = line.substr(7).strip_edges()
			# Parse "dawn, Weather: fog"
			var parts := settings_part.split(",")
			if parts.size() >= 1:
				result["time_of_day"] = parts[0].strip_edges().to_lower()
			if parts.size() >= 2:
				var weather_part: String = parts[1].strip_edges()
				if weather_part.begins_with("Weather:"):
					result["weather"] = weather_part.substr(8).strip_edges().to_lower()

		# Parse deployment transforms
		# transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 20.000000, 0, 20.000000)
		if line.begins_with("transform = Transform3D"):
			# Store the transform for the next relevant node we identify
			pass

	# Second pass - parse deployment nodes with their transforms
	var current_node: String = ""
	for i in range(lines.size()):
		var line: String = lines[i].strip_edges()

		if line.begins_with('[node name="PlayerDeployment"'):
			current_node = "player"
		elif line.begins_with('[node name="EnemyDeployment"'):
			current_node = "enemy"
		elif line.begins_with("[node"):
			current_node = ""

		if line.begins_with("transform = Transform3D") and not current_node.is_empty():
			var pos := _parse_transform3d(line)
			# Convert world position back to grid position (divide by tile_size, default 10.0)
			var grid_pos := Vector2(pos.x / 10.0, pos.z / 10.0)
			if current_node == "player":
				result["player_deployment_pos"] = grid_pos
			elif current_node == "enemy":
				result["enemy_deployment_pos"] = grid_pos

	return result


func _extract_quoted_value(line: String, key: String) -> String:
	# Extract value from: key="value"
	var pattern := key + '="'
	var start_idx := line.find(pattern)
	if start_idx == -1:
		return ""
	start_idx += pattern.length()
	var end_idx := line.find('"', start_idx)
	if end_idx == -1:
		return ""
	return line.substr(start_idx, end_idx - start_idx)


func _parse_transform3d(line: String) -> Vector3:
	# Parse: transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, X, Y, Z)
	# Position is the last 3 values
	var start := line.find("(")
	var end := line.rfind(")")
	if start == -1 or end == -1:
		return Vector3.ZERO

	var values_str := line.substr(start + 1, end - start - 1)
	var parts := values_str.split(",")
	if parts.size() < 12:
		return Vector3.ZERO

	# Last 3 values are X, Y, Z position
	var x := float(parts[9].strip_edges())
	var y := float(parts[10].strip_edges())
	var z := float(parts[11].strip_edges())
	return Vector3(x, y, z)


func _pascal_to_title(pascal: String) -> String:
	# Convert "DustyMud" to "Dusty Mud"
	var result := ""
	for i in range(pascal.length()):
		var c := pascal[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower():
			result += " "
		result += c
	return result


func _update_ui_from_map_state() -> void:
	map_name_edit.text = map_state.map_name
	map_id_edit.text = map_state.map_id
	grid_width_spin.value = map_state.grid_width
	grid_height_spin.value = map_state.grid_height

	# Update time option
	var times: Array = ["day", "dawn", "dusk", "night"]
	var time_idx := times.find(map_state.time_of_day)
	if time_idx >= 0:
		time_option.select(time_idx)

	# Update weather option
	var weathers: Array = ["clear", "rain", "fog", "snow"]
	var weather_idx := weathers.find(map_state.weather)
	if weather_idx >= 0:
		weather_option.select(weather_idx)
