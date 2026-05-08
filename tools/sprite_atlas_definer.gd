@tool
extends Control
## Sprite Atlas Definer - Visual tool for defining animation frame sequences on atlas sheets.
## Similar to the Catacombs of Gore Actor Zoo, but for defining frame ranges.

# === CONSTANTS ===
# Direction order matches WorldCompass convention (clockwise from North)
# See battle_system/data/world_compass.gd for canonical compass definition
# Matches SotHR extractor output: N, NE, E, SE, S, SW, W, NW
const DIRECTION_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const DIRECTION_FULL_NAMES := ["North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"]
const DEFAULT_ANIMATIONS := ["idle", "walk", "attack", "dead"]
const ANIMATION_COLORS := {
	"idle": Color(0.3, 0.5, 0.9, 0.4),      # Blue
	"walk": Color(0.3, 0.8, 0.3, 0.4),      # Green
	"attack": Color(0.9, 0.3, 0.3, 0.4),    # Red
	"dead": Color(0.5, 0.5, 0.5, 0.4),      # Gray
	"default": Color(0.8, 0.6, 0.2, 0.4)    # Orange for custom
}

# === STATE ===
var current_atlas_path: String = ""
var current_texture: Texture2D = null
var frame_size: Vector2 = Vector2(80, 80)
var columns: int = 13
var rows: int = 8
var animation_speed: float = 8.0

# Animation definitions: {name: {start_frame: int, frame_count: int, color: Color, per_direction: {dir_idx: {row, start_frame, frame_count}}}}
var animations: Dictionary = {}
var selected_animation: String = ""
var selecting_start: bool = true  # true = next click sets start, false = sets end
var editing_direction: int = 0  # Which direction we're currently editing (0-7)

# Preview state
var preview_direction: int = 0
var preview_frame: float = 0.0
var preview_playing: bool = true

# Direction-to-row mapping mode
var direction_rows: Dictionary = {}  # {direction_index: row_index}
var mapping_direction: int = -1  # Which direction we're mapping (-1 = not mapping)
var dir_row_labels: Array[Label] = []  # Labels showing current row for each direction

# UI References
var atlas_display: Control
var atlas_texture_rect: TextureRect
var grid_overlay: Control
var frame_labels: Control
var selection_overlay: Control
var preview_sprite: TextureRect
var preview_anim_timer: float = 0.0

var animations_list: ItemList
var anim_name_edit: LineEdit
var start_frame_spin: SpinBox
var frame_count_spin: SpinBox
var direction_buttons: Array[Button] = []
var fps_slider: HSlider
var fps_label: Label
var status_label: Label
var preview_row_label: Label

var atlas_dropdown: OptionButton
var frame_width_spin: SpinBox
var frame_height_spin: SpinBox
var columns_spin: SpinBox
var rows_spin: SpinBox
var editing_dir_label: Label

# Zoom/Pan for atlas view
var atlas_zoom: float = 1.0
var atlas_pan: Vector2 = Vector2.ZERO
var is_panning: bool = false
var pan_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	_build_ui()
	_scan_atlases()
	_setup_default_animations()


func _process(delta: float) -> void:
	if preview_playing and selected_animation != "" and animations.has(selected_animation):
		var anim_data = animations[selected_animation]
		var frame_count = anim_data.get("frame_count", 1)
		if frame_count > 1:
			preview_anim_timer += delta * animation_speed
			if preview_anim_timer >= 1.0:
				preview_anim_timer -= 1.0
				preview_frame = fmod(preview_frame + 1, frame_count)
				_update_preview_frame()


func _build_ui() -> void:
	# Main layout: VBox with top bar, then HBox with atlas + tools panel
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 0)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(main_vbox)

	# === TOP BAR ===
	var top_bar_panel := PanelContainer.new()
	main_vbox.add_child(top_bar_panel)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	top_bar_panel.add_child(top_bar)

	# Atlas dropdown
	var atlas_label := Label.new()
	atlas_label.text = "Atlas:"
	top_bar.add_child(atlas_label)

	atlas_dropdown = OptionButton.new()
	atlas_dropdown.custom_minimum_size.x = 200
	atlas_dropdown.item_selected.connect(_on_atlas_selected)
	top_bar.add_child(atlas_dropdown)

	top_bar.add_child(VSeparator.new())

	# Frame size controls
	var frame_label := Label.new()
	frame_label.text = "Frame Size:"
	top_bar.add_child(frame_label)

	frame_width_spin = SpinBox.new()
	frame_width_spin.min_value = 8
	frame_width_spin.max_value = 512
	frame_width_spin.value = 80
	frame_width_spin.value_changed.connect(_on_frame_size_changed)
	top_bar.add_child(frame_width_spin)

	var x_label := Label.new()
	x_label.text = "x"
	top_bar.add_child(x_label)

	frame_height_spin = SpinBox.new()
	frame_height_spin.min_value = 8
	frame_height_spin.max_value = 512
	frame_height_spin.value = 80
	frame_height_spin.value_changed.connect(_on_frame_size_changed)
	top_bar.add_child(frame_height_spin)

	top_bar.add_child(VSeparator.new())

	# Grid size controls
	var cols_label := Label.new()
	cols_label.text = "Cols:"
	top_bar.add_child(cols_label)

	columns_spin = SpinBox.new()
	columns_spin.min_value = 1
	columns_spin.max_value = 64
	columns_spin.value = 13
	columns_spin.value_changed.connect(_on_grid_changed)
	top_bar.add_child(columns_spin)

	var rows_label := Label.new()
	rows_label.text = "Rows:"
	top_bar.add_child(rows_label)

	rows_spin = SpinBox.new()
	rows_spin.min_value = 1
	rows_spin.max_value = 16
	rows_spin.value = 8
	rows_spin.value_changed.connect(_on_grid_changed)
	top_bar.add_child(rows_spin)

	top_bar.add_child(VSeparator.new())

	# Auto-detect button
	var auto_btn := Button.new()
	auto_btn.text = "Auto-Detect"
	auto_btn.pressed.connect(_auto_detect_grid)
	top_bar.add_child(auto_btn)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	# Save button
	var save_btn := Button.new()
	save_btn.text = "Save .tres"
	save_btn.pressed.connect(_save_tres)
	top_bar.add_child(save_btn)

	# Status
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_color_override("font_color", Color.GREEN)
	top_bar.add_child(status_label)

	# === CONTENT AREA ===
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 0)
	content_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_vbox.add_child(content_hbox)

	# === ATLAS DISPLAY AREA ===
	var atlas_panel := PanelContainer.new()
	atlas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atlas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(atlas_panel)

	# Clip container for atlas
	var atlas_clip := Control.new()
	atlas_clip.clip_contents = true
	atlas_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atlas_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	atlas_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atlas_panel.add_child(atlas_clip)

	# Atlas display container (for zoom/pan)
	atlas_display = Control.new()
	atlas_display.mouse_filter = Control.MOUSE_FILTER_STOP
	atlas_display.gui_input.connect(_on_atlas_gui_input)
	atlas_clip.add_child(atlas_display)

	# The actual texture
	atlas_texture_rect = TextureRect.new()
	atlas_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP
	atlas_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	atlas_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atlas_display.add_child(atlas_texture_rect)

	# Grid overlay (drawn on top)
	grid_overlay = Control.new()
	grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_overlay.draw.connect(_draw_grid_overlay)
	atlas_display.add_child(grid_overlay)

	# Frame labels overlay
	frame_labels = Control.new()
	frame_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_labels.draw.connect(_draw_frame_labels)
	atlas_display.add_child(frame_labels)

	# Selection/animation color overlay
	selection_overlay = Control.new()
	selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_overlay.draw.connect(_draw_selection_overlay)
	atlas_display.add_child(selection_overlay)

	# === TOOLS PANEL (RIGHT SIDE) ===
	var tools_panel := PanelContainer.new()
	tools_panel.custom_minimum_size.x = 300
	content_hbox.add_child(tools_panel)

	var tools_scroll := ScrollContainer.new()
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tools_panel.add_child(tools_scroll)

	var tools_vbox := VBoxContainer.new()
	tools_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_vbox.add_theme_constant_override("separation", 8)
	tools_scroll.add_child(tools_vbox)

	# === ANIMATIONS SECTION ===
	var anim_header := Label.new()
	anim_header.text = "=== Animations ==="
	tools_vbox.add_child(anim_header)

	# Animations list
	animations_list = ItemList.new()
	animations_list.custom_minimum_size.y = 120
	animations_list.item_selected.connect(_on_animation_selected)
	tools_vbox.add_child(animations_list)

	# Add/Remove buttons
	var anim_btn_row := HBoxContainer.new()
	tools_vbox.add_child(anim_btn_row)

	var add_anim_btn := Button.new()
	add_anim_btn.text = "+ Add"
	add_anim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_anim_btn.pressed.connect(_add_animation)
	anim_btn_row.add_child(add_anim_btn)

	var remove_anim_btn := Button.new()
	remove_anim_btn.text = "- Remove"
	remove_anim_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_anim_btn.pressed.connect(_remove_animation)
	anim_btn_row.add_child(remove_anim_btn)

	tools_vbox.add_child(HSeparator.new())

	# === SELECTED ANIMATION EDITING ===
	var edit_header := Label.new()
	edit_header.text = "=== Edit Selected ==="
	tools_vbox.add_child(edit_header)

	# Current direction being edited indicator
	var dir_edit_row := HBoxContainer.new()
	tools_vbox.add_child(dir_edit_row)

	var dir_edit_label := Label.new()
	dir_edit_label.text = "Editing Dir:"
	dir_edit_label.custom_minimum_size.x = 80
	dir_edit_row.add_child(dir_edit_label)

	editing_dir_label = Label.new()
	editing_dir_label.text = "S (South)"
	editing_dir_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	editing_dir_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dir_edit_row.add_child(editing_dir_label)

	# Animation name
	var name_row := HBoxContainer.new()
	tools_vbox.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.custom_minimum_size.x = 80
	name_row.add_child(name_label)

	anim_name_edit = LineEdit.new()
	anim_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_name_edit.text_changed.connect(_on_anim_name_changed)
	name_row.add_child(anim_name_edit)

	# Start frame
	var start_row := HBoxContainer.new()
	tools_vbox.add_child(start_row)

	var start_label := Label.new()
	start_label.text = "Start Frame:"
	start_label.custom_minimum_size.x = 80
	start_row.add_child(start_label)

	start_frame_spin = SpinBox.new()
	start_frame_spin.min_value = 0
	start_frame_spin.max_value = 63
	start_frame_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_frame_spin.value_changed.connect(_on_start_frame_changed)
	start_row.add_child(start_frame_spin)

	# Frame count
	var count_row := HBoxContainer.new()
	tools_vbox.add_child(count_row)

	var count_label := Label.new()
	count_label.text = "Frame Count:"
	count_label.custom_minimum_size.x = 80
	count_row.add_child(count_label)

	frame_count_spin = SpinBox.new()
	frame_count_spin.min_value = 1
	frame_count_spin.max_value = 64
	frame_count_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_count_spin.value_changed.connect(_on_frame_count_changed)
	count_row.add_child(frame_count_spin)

	# Click instruction
	var click_info := Label.new()
	click_info.text = "For 1-frame: use spinboxes above\nFor multi-frame: Click start, Shift+Click end"
	click_info.add_theme_font_size_override("font_size", 11)
	click_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	tools_vbox.add_child(click_info)

	tools_vbox.add_child(HSeparator.new())

	# === PREVIEW SECTION ===
	var preview_header := Label.new()
	preview_header.text = "=== Preview ==="
	tools_vbox.add_child(preview_header)

	# Preview sprite container
	var preview_container := PanelContainer.new()
	preview_container.custom_minimum_size = Vector2(200, 200)
	tools_vbox.add_child(preview_container)

	var preview_center := CenterContainer.new()
	preview_container.add_child(preview_center)

	preview_sprite = TextureRect.new()
	preview_sprite.custom_minimum_size = Vector2(160, 160)
	preview_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_center.add_child(preview_sprite)

	# Direction buttons (8 directions in a grid pattern)
	var dir_header := Label.new()
	dir_header.text = "Direction:"
	tools_vbox.add_child(dir_header)

	var dir_grid := GridContainer.new()
	dir_grid.columns = 3
	dir_grid.add_theme_constant_override("h_separation", 4)
	dir_grid.add_theme_constant_override("v_separation", 4)
	tools_vbox.add_child(dir_grid)

	# Layout: NW N NE / W [X] E / SW S SE
	# Direction indices (clockwise from North): N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7
	var dir_layout := [
		["NW", 7], ["N", 0], ["NE", 1],
		["W", 6], ["", -1], ["E", 2],
		["SW", 5], ["S", 4], ["SE", 3]
	]

	for item in dir_layout:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(50, 30)
		if item[1] >= 0:
			btn.text = item[0]
			btn.pressed.connect(_on_direction_pressed.bind(item[1]))
			direction_buttons.append(btn)
		else:
			btn.text = "●"
			btn.disabled = true
		dir_grid.add_child(btn)

	# Preview row indicator
	preview_row_label = Label.new()
	preview_row_label.text = "Dir: S → Row 0"
	preview_row_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	tools_vbox.add_child(preview_row_label)

	tools_vbox.add_child(HSeparator.new())

	# === DIRECTION ROW MAPPING ===
	var map_header := Label.new()
	map_header.text = "=== Row Mapping ==="
	tools_vbox.add_child(map_header)

	var map_info := Label.new()
	map_info.text = "Click [Set], then click row on atlas"
	map_info.add_theme_font_size_override("font_size", 10)
	map_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	tools_vbox.add_child(map_info)

	# Direction row mapping grid - 2 columns: direction name + row assignment
	var map_grid := GridContainer.new()
	map_grid.columns = 3
	map_grid.add_theme_constant_override("h_separation", 4)
	map_grid.add_theme_constant_override("v_separation", 2)
	tools_vbox.add_child(map_grid)

	for dir_idx in range(8):
		# Direction name label
		var dir_label := Label.new()
		dir_label.text = DIRECTION_NAMES[dir_idx] + ":"
		dir_label.custom_minimum_size.x = 30
		map_grid.add_child(dir_label)

		# Row assignment label
		var row_label := Label.new()
		row_label.text = "Row %d" % dir_idx
		row_label.custom_minimum_size.x = 50
		row_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		map_grid.add_child(row_label)
		dir_row_labels.append(row_label)

		# Set button
		var set_btn := Button.new()
		set_btn.text = "Set"
		set_btn.custom_minimum_size.x = 40
		set_btn.pressed.connect(_on_map_direction_pressed.bind(dir_idx))
		map_grid.add_child(set_btn)

	# Reset mapping button
	var reset_map_btn := Button.new()
	reset_map_btn.text = "Reset to Default (row=dir)"
	reset_map_btn.pressed.connect(_reset_direction_mapping)
	tools_vbox.add_child(reset_map_btn)

	tools_vbox.add_child(HSeparator.new())

	# FPS slider
	var fps_row := HBoxContainer.new()
	tools_vbox.add_child(fps_row)

	var fps_text := Label.new()
	fps_text.text = "FPS:"
	fps_row.add_child(fps_text)

	fps_slider = HSlider.new()
	fps_slider.min_value = 1
	fps_slider.max_value = 30
	fps_slider.value = 8
	fps_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_slider.value_changed.connect(_on_fps_changed)
	fps_row.add_child(fps_slider)

	fps_label = Label.new()
	fps_label.text = "8.0"
	fps_label.custom_minimum_size.x = 40
	fps_row.add_child(fps_label)

	# Play/Pause button
	var play_row := HBoxContainer.new()
	tools_vbox.add_child(play_row)

	var play_btn := Button.new()
	play_btn.text = "Play/Pause"
	play_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_btn.pressed.connect(func(): preview_playing = not preview_playing)
	play_row.add_child(play_btn)

	tools_vbox.add_child(HSeparator.new())

	# === HELP TEXT ===
	var help_label := Label.new()
	help_label.text = "Workflow:\n1. Select animation\n2. Click direction to edit\n3. Set Start Frame + Count\n   (auto-saves per direction!)\n4. Use Row Mapping for custom rows\n5. Ctrl+S to save .tres\n\n*N = N directions customized"
	help_label.add_theme_font_size_override("font_size", 11)
	help_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	tools_vbox.add_child(help_label)

	# Unlock/Clear buttons
	var unlock_row := HBoxContainer.new()
	tools_vbox.add_child(unlock_row)

	var unlock_dir_btn := Button.new()
	unlock_dir_btn.text = "Unlock Dir"
	unlock_dir_btn.tooltip_text = "Clear per-direction override for current direction"
	unlock_dir_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unlock_dir_btn.pressed.connect(_unlock_direction_settings)
	unlock_row.add_child(unlock_dir_btn)

	var unlock_all_btn := Button.new()
	unlock_all_btn.text = "Unlock All"
	unlock_all_btn.tooltip_text = "Clear all per-direction overrides for selected animation"
	unlock_all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unlock_all_btn.pressed.connect(_unlock_all_direction_settings)
	unlock_row.add_child(unlock_all_btn)


func _scan_atlases() -> void:
	atlas_dropdown.clear()
	atlas_dropdown.add_item("-- Select Atlas --")

	var dir := DirAccess.open("res://assets/sprites/units/")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") and not file_name.ends_with(".import"):
				atlas_dropdown.add_item(file_name.get_basename())
			file_name = dir.get_next()
		dir.list_dir_end()


func _setup_default_animations() -> void:
	# Set up standard animation slots
	animations = {
		"idle": {"start_frame": 0, "frame_count": 1, "color": ANIMATION_COLORS["idle"]},
		"walk": {"start_frame": 1, "frame_count": 9, "color": ANIMATION_COLORS["walk"]},
		"attack": {"start_frame": 10, "frame_count": 2, "color": ANIMATION_COLORS["attack"]},
		"dead": {"start_frame": 12, "frame_count": 1, "color": ANIMATION_COLORS["dead"]}
	}
	_refresh_animations_list()


func _refresh_animations_list() -> void:
	animations_list.clear()
	for anim_name in animations.keys():
		var anim_data = animations[anim_name]
		var start = anim_data.get("start_frame", 0)
		var count = anim_data.get("frame_count", 1)
		var end_frame = start + count - 1

		# Check if has per-direction overrides
		var per_dir_count = 0
		if anim_data.has("per_direction"):
			per_dir_count = anim_data["per_direction"].size()

		var per_dir_marker = " *%d" % per_dir_count if per_dir_count > 0 else ""
		animations_list.add_item("%s [%d-%d]%s" % [anim_name, start, end_frame, per_dir_marker])

		# Set item color
		var idx = animations_list.item_count - 1
		var color = anim_data.get("color", ANIMATION_COLORS["default"])
		animations_list.set_item_custom_bg_color(idx, Color(color.r, color.g, color.b, 0.3))

	selection_overlay.queue_redraw()


func _on_atlas_selected(index: int) -> void:
	if index == 0:
		current_texture = null
		current_atlas_path = ""
		atlas_texture_rect.texture = null
		return

	var atlas_name = atlas_dropdown.get_item_text(index)
	current_atlas_path = "res://assets/sprites/units/%s.png" % atlas_name

	current_texture = load(current_atlas_path)
	if current_texture:
		atlas_texture_rect.texture = current_texture
		_update_atlas_display_size()
		# Only auto-detect if no .tres file exists - otherwise use .tres values
		var loaded_tres = _try_load_existing_tres(atlas_name)
		if not loaded_tres:
			_auto_detect_grid()
		else:
			_update_atlas_display_size()  # Refresh with loaded values


func _try_load_existing_tres(atlas_name: String) -> bool:
	var tres_path = "res://assets/sprites/units/%s.tres" % atlas_name
	if not ResourceLoader.exists(tres_path):
		return false

	var res = load(tres_path)
	if not res or not res is Resource:
		return false

	# Load existing animation definitions
	if "columns" in res:
		columns = res.columns
		columns_spin.value = columns
	if "rows" in res:
		rows = res.rows
		rows_spin.value = rows
	if "frame_size" in res:
		frame_size = res.frame_size
		frame_width_spin.value = frame_size.x
		frame_height_spin.value = frame_size.y
	if "animation_speed" in res:
		animation_speed = res.animation_speed
		fps_slider.value = animation_speed
		fps_label.text = "%.1f" % animation_speed
	if "animations" in res:
		animations.clear()
		for anim_name in res.animations.keys():
			var anim_data = res.animations[anim_name]
			var color = ANIMATION_COLORS.get(anim_name, ANIMATION_COLORS["default"])
			var new_anim = {
				"start_frame": anim_data.get("start_frame", 0),
				"frame_count": anim_data.get("frame_count", 1),
				"color": color
			}
			# Load per_direction data if it exists
			if anim_data.has("per_direction") and anim_data["per_direction"] is Dictionary:
				new_anim["per_direction"] = {}
				for dir_idx in anim_data["per_direction"].keys():
					var dir_data = anim_data["per_direction"][dir_idx]
					new_anim["per_direction"][int(dir_idx)] = {
						"start_frame": dir_data.get("start_frame", 0),
						"frame_count": dir_data.get("frame_count", 1),
						"row": dir_data.get("row", 0)
					}
			animations[anim_name] = new_anim
		_refresh_animations_list()

	# Load custom direction-to-row mapping
	direction_rows.clear()
	if "direction_rows" in res and res.direction_rows is Dictionary:
		for dir_idx in res.direction_rows.keys():
			direction_rows[int(dir_idx)] = int(res.direction_rows[dir_idx])
	_update_dir_row_labels()

	start_frame_spin.max_value = columns * rows - 1
	_update_direction_buttons()

	var custom_count = direction_rows.size()
	var custom_note = " (%d custom)" % custom_count if custom_count > 0 else ""
	status_label.text = "Loaded: %s (%d×%d, %dpx)%s" % [atlas_name, columns, rows, int(frame_size.x), custom_note]
	return true


func _update_atlas_display_size() -> void:
	if not current_texture:
		return

	var tex_size = current_texture.get_size()
	var display_size = tex_size * atlas_zoom

	atlas_texture_rect.custom_minimum_size = display_size
	atlas_texture_rect.size = display_size
	atlas_display.custom_minimum_size = display_size
	atlas_display.size = display_size

	grid_overlay.custom_minimum_size = display_size
	grid_overlay.size = display_size
	frame_labels.custom_minimum_size = display_size
	frame_labels.size = display_size
	selection_overlay.custom_minimum_size = display_size
	selection_overlay.size = display_size

	atlas_display.position = atlas_pan

	grid_overlay.queue_redraw()
	frame_labels.queue_redraw()
	selection_overlay.queue_redraw()


func _auto_detect_grid() -> void:
	if not current_texture:
		return

	var tex_size = current_texture.get_size()

	# Try common frame sizes (prefer larger)
	var common_sizes = [80, 64, 48, 32]
	var best_size = 80

	for test_size in common_sizes:
		if int(tex_size.x) % test_size == 0 and int(tex_size.y) % test_size == 0:
			best_size = test_size
			break

	frame_size = Vector2(best_size, best_size)
	columns = int(tex_size.x / frame_size.x)
	rows = int(tex_size.y / frame_size.y)

	frame_width_spin.value = frame_size.x
	frame_height_spin.value = frame_size.y
	columns_spin.value = columns
	rows_spin.value = rows

	# Max frame is total frames across all rows
	start_frame_spin.max_value = columns * rows - 1

	# Clear custom direction mapping on auto-detect
	direction_rows.clear()
	_update_direction_buttons()
	_update_dir_row_labels()
	_update_atlas_display_size()
	status_label.text = "Auto-detected: %dx%d frames, %d cols x %d rows" % [int(frame_size.x), int(frame_size.y), columns, rows]


func _on_frame_size_changed(_value: float) -> void:
	frame_size = Vector2(frame_width_spin.value, frame_height_spin.value)
	_update_atlas_display_size()


func _on_grid_changed(_value: float) -> void:
	columns = int(columns_spin.value)
	rows = int(rows_spin.value)
	start_frame_spin.max_value = columns * rows - 1
	_update_direction_buttons()
	_update_dir_row_labels()
	_update_atlas_display_size()


func _draw_grid_overlay() -> void:
	if not current_texture:
		return

	var scaled_frame = frame_size * atlas_zoom

	# Draw vertical lines (columns)
	for col in range(columns + 1):
		var x = col * scaled_frame.x
		grid_overlay.draw_line(
			Vector2(x, 0),
			Vector2(x, rows * scaled_frame.y),
			Color(1, 1, 1, 0.3),
			1.0
		)

	# Draw horizontal lines (rows)
	for row in range(rows + 1):
		var y = row * scaled_frame.y
		grid_overlay.draw_line(
			Vector2(0, y),
			Vector2(columns * scaled_frame.x, y),
			Color(1, 1, 1, 0.3),
			1.0
		)


func _draw_frame_labels() -> void:
	if not current_texture:
		return

	var scaled_frame = frame_size * atlas_zoom
	var font = ThemeDB.fallback_font
	var font_size = int(10 * atlas_zoom)

	# Draw column numbers at top
	for col in range(columns):
		var pos = Vector2(col * scaled_frame.x + 4, 12)
		frame_labels.draw_string(font, pos, str(col), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 0, 0.7))

	# Draw direction labels on left
	for row in range(mini(rows, 8)):
		var pos = Vector2(4, row * scaled_frame.y + scaled_frame.y / 2)
		frame_labels.draw_string(font, pos, DIRECTION_NAMES[row], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 1, 0.7, 0.7))


func _draw_selection_overlay() -> void:
	if not current_texture:
		return

	var scaled_frame = frame_size * atlas_zoom

	# Draw current preview row highlight (yellow tint) - uses direction row mapping
	var use_row = _get_row_for_direction(preview_direction)
	var row_highlight = Rect2(
		0,
		use_row * scaled_frame.y,
		columns * scaled_frame.x,
		scaled_frame.y
	)
	selection_overlay.draw_rect(row_highlight, Color(1, 1, 0, 0.15))

	# Draw colored rectangles for each animation
	for anim_name in animations.keys():
		var anim_data = animations[anim_name]
		var start = anim_data.get("start_frame", 0)
		var count = anim_data.get("frame_count", 1)
		var color = anim_data.get("color", ANIMATION_COLORS["default"])

		# Highlight if selected
		if anim_name == selected_animation:
			color = Color(color.r, color.g, color.b, 0.6)

		# Draw for all rows (directions)
		for row in range(rows):
			for frame_idx in range(count):
				var col = start + frame_idx
				if col >= columns:
					break
				var rect = Rect2(
					col * scaled_frame.x,
					row * scaled_frame.y,
					scaled_frame.x,
					scaled_frame.y
				)
				selection_overlay.draw_rect(rect, color)

				# Draw border if selected
				if anim_name == selected_animation:
					selection_overlay.draw_rect(rect, Color(1, 1, 1, 0.8), false, 2.0)


func _on_atlas_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			atlas_zoom = clampf(atlas_zoom * 1.1, 0.25, 4.0)
			_update_atlas_display_size()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			atlas_zoom = clampf(atlas_zoom / 1.1, 0.25, 4.0)
			_update_atlas_display_size()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				is_panning = true
				pan_start = mb.position
			else:
				is_panning = false
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			# Use local mouse position to account for container offsets and panning
			var local_pos = atlas_display.get_local_mouse_position()
			_handle_frame_click(local_pos, mb.shift_pressed)

	elif event is InputEventMouseMotion and is_panning:
		var mm := event as InputEventMouseMotion
		atlas_pan += mm.relative
		atlas_display.position = atlas_pan


func _handle_frame_click(pos: Vector2, is_shift: bool) -> void:
	if not current_texture:
		return

	var scaled_frame = frame_size * atlas_zoom
	var col = int(pos.x / scaled_frame.x)
	var row = int(pos.y / scaled_frame.y)

	if col < 0 or col >= columns or row < 0 or row >= rows:
		return

	# Check if we're in direction row mapping mode
	if mapping_direction >= 0:
		direction_rows[mapping_direction] = row
		# Also auto-save row to per_direction if an animation is selected
		if selected_animation != "" and selected_animation in animations:
			_auto_save_direction_setting_for_dir(mapping_direction, "row", row)
		status_label.text = "%s → Row %d (saved)" % [DIRECTION_NAMES[mapping_direction], row]
		mapping_direction = -1
		_update_dir_row_labels()
		_update_editing_dir_label()
		_update_preview_frame()
		return

	# Normal animation frame click handling
	if selected_animation == "":
		return

	if selected_animation in animations:
		if is_shift:
			# Set end frame (calculate count from start)
			var start = animations[selected_animation]["start_frame"]
			var count = col - start + 1
			if count >= 1:
				animations[selected_animation]["frame_count"] = count
				frame_count_spin.value = count
		else:
			# Set start frame
			animations[selected_animation]["start_frame"] = col
			start_frame_spin.value = col

		_refresh_animations_list()
		selection_overlay.queue_redraw()
		_update_preview_frame()


func _on_animation_selected(index: int) -> void:
	var keys = animations.keys()
	if index >= 0 and index < keys.size():
		selected_animation = keys[index]
		anim_name_edit.text = selected_animation

		# Load direction-specific settings if available, otherwise base values
		_load_direction_settings(editing_direction)
		_update_editing_dir_label()

		preview_frame = 0
		_update_preview_frame()
		selection_overlay.queue_redraw()


func _on_anim_name_changed(new_name: String) -> void:
	if selected_animation == "" or new_name == "" or new_name == selected_animation:
		return

	if new_name in animations:
		return  # Name already exists

	# Rename the animation
	var anim_data = animations[selected_animation]
	animations.erase(selected_animation)
	animations[new_name] = anim_data
	selected_animation = new_name
	_refresh_animations_list()


func _on_start_frame_changed(value: float) -> void:
	if selected_animation != "" and selected_animation in animations:
		# Auto-save to per_direction for current editing direction
		_auto_save_direction_setting("start_frame", int(value))
		_refresh_animations_list()
		_update_preview_frame()


func _on_frame_count_changed(value: float) -> void:
	if selected_animation != "" and selected_animation in animations:
		# Auto-save to per_direction for current editing direction
		_auto_save_direction_setting("frame_count", int(value))
		_refresh_animations_list()
		_update_preview_frame()


func _auto_save_direction_setting(key: String, value: int) -> void:
	"""Automatically save a setting to the current editing direction's per_direction data."""
	_auto_save_direction_setting_for_dir(editing_direction, key, value)


func _auto_save_direction_setting_for_dir(dir_idx: int, key: String, value: int) -> void:
	"""Automatically save a setting to a specific direction's per_direction data."""
	if selected_animation == "" or not selected_animation in animations:
		return

	var anim_data = animations[selected_animation]

	# Initialize per_direction if needed
	if not anim_data.has("per_direction"):
		anim_data["per_direction"] = {}

	# Initialize this direction's data if needed
	if not anim_data["per_direction"].has(dir_idx):
		# Copy current base values as starting point
		anim_data["per_direction"][dir_idx] = {
			"start_frame": anim_data.get("start_frame", 0),
			"frame_count": anim_data.get("frame_count", 1),
			"row": _get_row_for_direction(dir_idx)
		}

	# Update the specific key
	anim_data["per_direction"][dir_idx][key] = value

	# Update status to show it saved
	var dir_name = DIRECTION_NAMES[dir_idx]
	status_label.text = "Auto-saved %s=%d for %s/%s" % [key, value, selected_animation, dir_name]
	_update_editing_dir_label()


func _add_animation() -> void:
	var new_name = "anim_%d" % animations.size()
	var idx = 1
	while new_name in animations:
		new_name = "anim_%d" % idx
		idx += 1

	animations[new_name] = {
		"start_frame": 0,
		"frame_count": 1,
		"color": ANIMATION_COLORS["default"]
	}
	_refresh_animations_list()

	# Select the new animation
	animations_list.select(animations_list.item_count - 1)
	_on_animation_selected(animations_list.item_count - 1)


func _remove_animation() -> void:
	if selected_animation == "":
		return

	animations.erase(selected_animation)
	selected_animation = ""
	anim_name_edit.text = ""
	_refresh_animations_list()
	selection_overlay.queue_redraw()


func _on_direction_pressed(dir_index: int) -> void:
	preview_direction = dir_index
	editing_direction = dir_index
	_update_editing_dir_label()
	_load_direction_settings(dir_index)
	_update_preview_frame()

	# Highlight selected direction button
	for i in range(direction_buttons.size()):
		direction_buttons[i].button_pressed = (i == _dir_to_button_index(dir_index))


func _dir_to_button_index(dir_index: int) -> int:
	# Map direction index to button array index
	# Direction indices (North-first): N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7
	# Button array order (as added): NW, N, NE, W, E, SW, S, SE
	# So: button[0]=NW(dir7), button[1]=N(dir0), button[2]=NE(dir1),
	#     button[3]=W(dir6), button[4]=E(dir2),
	#     button[5]=SW(dir5), button[6]=S(dir4), button[7]=SE(dir3)
	var mapping = [1, 2, 4, 7, 6, 5, 3, 0]  # dir_index -> button_index
	return mapping[dir_index] if dir_index < 8 else 0


func _button_to_dir_index(button_idx: int) -> int:
	# Reverse mapping: button array index to direction index
	# Button array: [NW, N, NE, W, E, SW, S, SE]
	# Dir indices:  [7,  0, 1,  6, 2, 5,  4, 3]
	var mapping = [7, 0, 1, 6, 2, 5, 4, 3]
	return mapping[button_idx] if button_idx < 8 else 0


func _update_direction_buttons() -> void:
	# All 8 direction buttons stay enabled - game maps 8 directions to available rows
	# Preview will clamp to available rows when displaying
	for i in range(direction_buttons.size()):
		direction_buttons[i].disabled = false

	_update_preview_frame()


func _on_map_direction_pressed(dir_idx: int) -> void:
	# Toggle mapping mode for this direction
	if mapping_direction == dir_idx:
		# Cancel mapping
		mapping_direction = -1
		status_label.text = "Mapping cancelled"
	else:
		# Start mapping this direction
		mapping_direction = dir_idx
		status_label.text = "Click a ROW on atlas for %s direction" % DIRECTION_NAMES[dir_idx]


func _reset_direction_mapping() -> void:
	direction_rows.clear()
	_update_dir_row_labels()
	status_label.text = "Direction mapping reset to default"
	_update_preview_frame()


func _update_dir_row_labels() -> void:
	for dir_idx in range(8):
		if dir_idx < dir_row_labels.size():
			var actual_row = direction_rows.get(dir_idx, dir_idx)
			actual_row = mini(actual_row, rows - 1)
			dir_row_labels[dir_idx].text = "Row %d" % actual_row
			# Color: green if default, yellow if custom
			if direction_rows.has(dir_idx):
				dir_row_labels[dir_idx].add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
			else:
				dir_row_labels[dir_idx].add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))


func _get_row_for_direction(dir_idx: int) -> int:
	# Returns the actual row to use for a given direction
	if direction_rows.has(dir_idx):
		return mini(direction_rows[dir_idx], rows - 1)
	else:
		return mini(dir_idx, rows - 1)


func _update_editing_dir_label() -> void:
	var dir_name = DIRECTION_NAMES[editing_direction] if editing_direction < 8 else "?"
	var full_name = DIRECTION_FULL_NAMES[editing_direction] if editing_direction < 8 else "Unknown"

	# Check if this direction has custom data saved
	var has_custom = false
	if selected_animation != "" and selected_animation in animations:
		var anim_data = animations[selected_animation]
		if anim_data.has("per_direction") and anim_data["per_direction"].has(editing_direction):
			has_custom = true

	var locked_marker = " [LOCKED]" if has_custom else ""
	editing_dir_label.text = "%s (%s)%s" % [dir_name, full_name, locked_marker]

	if has_custom:
		editing_dir_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))  # Green = saved
	else:
		editing_dir_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))  # Yellow = unsaved


func _load_direction_settings(dir_idx: int) -> void:
	"""Load saved per-direction settings into the UI spinboxes."""
	if selected_animation == "" or not selected_animation in animations:
		return

	var anim_data = animations[selected_animation]

	# Check if per-direction override exists
	if anim_data.has("per_direction") and anim_data["per_direction"].has(dir_idx):
		var dir_data = anim_data["per_direction"][dir_idx]
		# Load direction-specific values
		start_frame_spin.value = dir_data.get("start_frame", anim_data.get("start_frame", 0))
		frame_count_spin.value = dir_data.get("frame_count", anim_data.get("frame_count", 1))
		# If direction has a saved row, update the direction_rows mapping
		if dir_data.has("row"):
			direction_rows[dir_idx] = dir_data["row"]
			_update_dir_row_labels()
		status_label.text = "Loaded %s settings for %s" % [selected_animation, DIRECTION_NAMES[dir_idx]]
	else:
		# Use default animation values (shared/base values)
		start_frame_spin.value = anim_data.get("start_frame", 0)
		frame_count_spin.value = anim_data.get("frame_count", 1)


func _lock_direction_settings() -> void:
	"""Save current spinbox values as this direction's custom settings."""
	if selected_animation == "" or not selected_animation in animations:
		status_label.text = "Select an animation first!"
		return

	var anim_data = animations[selected_animation]

	# Initialize per_direction dict if needed
	if not anim_data.has("per_direction"):
		anim_data["per_direction"] = {}

	# Save current values for this direction
	anim_data["per_direction"][editing_direction] = {
		"start_frame": int(start_frame_spin.value),
		"frame_count": int(frame_count_spin.value),
		"row": _get_row_for_direction(editing_direction)
	}

	var dir_name = DIRECTION_NAMES[editing_direction]
	status_label.text = "Locked %s for %s (frame %d, count %d, row %d)" % [
		selected_animation, dir_name,
		int(start_frame_spin.value), int(frame_count_spin.value),
		_get_row_for_direction(editing_direction)
	]

	_update_editing_dir_label()
	_refresh_animations_list()


func _unlock_direction_settings() -> void:
	"""Remove per-direction override for current direction."""
	if selected_animation == "" or not selected_animation in animations:
		status_label.text = "Select an animation first!"
		return

	var anim_data = animations[selected_animation]
	if not anim_data.has("per_direction") or not anim_data["per_direction"].has(editing_direction):
		status_label.text = "No locked settings for %s" % DIRECTION_NAMES[editing_direction]
		return

	anim_data["per_direction"].erase(editing_direction)
	status_label.text = "Unlocked %s for %s" % [selected_animation, DIRECTION_NAMES[editing_direction]]

	# Load base animation values
	start_frame_spin.value = anim_data.get("start_frame", 0)
	frame_count_spin.value = anim_data.get("frame_count", 1)

	_update_editing_dir_label()
	_refresh_animations_list()
	_update_preview_frame()


func _unlock_all_direction_settings() -> void:
	"""Remove all per-direction overrides for selected animation."""
	if selected_animation == "" or not selected_animation in animations:
		status_label.text = "Select an animation first!"
		return

	var anim_data = animations[selected_animation]
	if not anim_data.has("per_direction") or anim_data["per_direction"].is_empty():
		status_label.text = "No locked settings for %s" % selected_animation
		return

	var count = anim_data["per_direction"].size()
	anim_data["per_direction"].clear()
	status_label.text = "Unlocked all %d directions for %s" % [count, selected_animation]

	# Load base animation values
	start_frame_spin.value = anim_data.get("start_frame", 0)
	frame_count_spin.value = anim_data.get("frame_count", 1)

	_update_editing_dir_label()
	_refresh_animations_list()
	_update_preview_frame()


func _on_fps_changed(value: float) -> void:
	animation_speed = value
	fps_label.text = "%.1f" % value


func _update_preview_frame() -> void:
	if not current_texture or selected_animation == "" or not selected_animation in animations:
		preview_sprite.texture = null
		return

	var anim_data = animations[selected_animation]

	# Check for per-direction override
	var start: int
	var count: int
	var use_row: int
	var has_per_dir = false

	if anim_data.has("per_direction") and anim_data["per_direction"].has(preview_direction):
		var dir_data = anim_data["per_direction"][preview_direction]
		start = dir_data.get("start_frame", anim_data.get("start_frame", 0))
		count = dir_data.get("frame_count", anim_data.get("frame_count", 1))
		use_row = dir_data.get("row", _get_row_for_direction(preview_direction))
		has_per_dir = true
	else:
		# Use base animation values
		start = anim_data.get("start_frame", 0)
		count = anim_data.get("frame_count", 1)
		# Determine which row to use - use custom direction mapping if available
		if rows > 1 and rows <= 8:
			# Multi-direction atlas: use direction row mapping
			use_row = _get_row_for_direction(preview_direction)
		else:
			# Single-direction atlas or very tall atlas
			use_row = 0

	var frame_offset = int(preview_frame) % maxi(count, 1)
	var actual_frame = start + frame_offset

	# Calculate column from linear frame index (handles wrapping across rows)
	var frame_col = actual_frame % columns

	# Create an AtlasTexture for the specific frame
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = current_texture
	atlas_tex.region = Rect2(
		frame_col * frame_size.x,
		use_row * frame_size.y,
		frame_size.x,
		frame_size.y
	)
	preview_sprite.texture = atlas_tex

	# Update row indicator label
	var dir_name = DIRECTION_NAMES[preview_direction] if preview_direction < 8 else "?"
	var locked_marker = " [LOCKED]" if has_per_dir else ""
	var custom_row_marker = "*" if direction_rows.has(preview_direction) else ""
	preview_row_label.text = "Dir: %s → Row %d%s%s" % [dir_name, use_row, custom_row_marker, locked_marker]

	# Trigger redraw to update row highlight on atlas
	selection_overlay.queue_redraw()


func _save_tres() -> void:
	if current_atlas_path == "":
		status_label.text = "No atlas loaded!"
		return

	var atlas_name = current_atlas_path.get_file().get_basename()
	var tres_path = "res://assets/sprites/units/%s.tres" % atlas_name

	# Build the .tres file content
	var content := "[gd_resource type=\"Resource\" script_class=\"SpriteUnitAtlas\" load_steps=3 format=3]\n\n"
	content += "[ext_resource type=\"Texture2D\" path=\"%s\" id=\"1\"]\n" % current_atlas_path
	content += "[ext_resource type=\"Script\" path=\"res://battle_system/data/sprite_unit_atlas.gd\" id=\"2\"]\n\n"
	content += "[resource]\n"
	content += "script = ExtResource(\"2\")\n"
	content += "texture = ExtResource(\"1\")\n"
	content += "columns = %d\n" % columns
	content += "rows = %d\n" % rows
	content += "frame_size = Vector2(%d, %d)\n" % [int(frame_size.x), int(frame_size.y)]
	content += "directions = %d\n" % rows
	content += "animation_speed = %.1f\n" % animation_speed

	# Save direction_rows if any custom mappings exist
	if not direction_rows.is_empty():
		content += "direction_rows = {\n"
		var dir_lines := []
		for dir_idx in direction_rows.keys():
			dir_lines.append("%d: %d" % [dir_idx, direction_rows[dir_idx]])
		content += ",\n".join(dir_lines)
		content += "\n}\n"

	content += "animations = {\n"

	var anim_lines := []
	for anim_name in animations.keys():
		var anim_data = animations[anim_name]
		var anim_entry = "\"%s\": {\"start_frame\": %d, \"frame_count\": %d" % [
			anim_name,
			anim_data.get("start_frame", 0),
			anim_data.get("frame_count", 1)
		]

		# Include per_direction data if it exists
		if anim_data.has("per_direction") and not anim_data["per_direction"].is_empty():
			anim_entry += ", \"per_direction\": {"
			var per_dir_entries := []
			for dir_idx in anim_data["per_direction"].keys():
				var dir_data = anim_data["per_direction"][dir_idx]
				per_dir_entries.append("%d: {\"start_frame\": %d, \"frame_count\": %d, \"row\": %d}" % [
					dir_idx,
					dir_data.get("start_frame", 0),
					dir_data.get("frame_count", 1),
					dir_data.get("row", 0)
				])
			anim_entry += ", ".join(per_dir_entries) + "}"

		anim_entry += "}"
		anim_lines.append(anim_entry)

	content += ",\n".join(anim_lines)
	content += "\n}\n"

	# Write the file
	var file := FileAccess.open(tres_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		status_label.text = "Saved: %s" % tres_path.get_file()
		print("Saved: %s" % tres_path)
	else:
		status_label.text = "Error saving file!"
		push_error("Failed to save: %s" % tres_path)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key := event as InputEventKey
		if key.ctrl_pressed and key.keycode == KEY_S:
			_save_tres()
			get_viewport().set_input_as_handled()
