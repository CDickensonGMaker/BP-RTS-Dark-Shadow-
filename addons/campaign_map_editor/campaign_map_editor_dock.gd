@tool
extends Control
class_name CampaignMapEditorDock
## Main dock UI for the Campaign Map Editor

const EXPORT_PATH := "user://campaign_map_editor.json"

var map_state: CampaignMapEditorData.MapState
var editor_state: CampaignMapEditorData.EditorState

# UI References
var canvas: CampaignMapEditorCanvas
var region_list: ItemList
var terrain_option: OptionButton
var owner_option: OptionButton
var new_region_edit: LineEdit
var region_name_edit: LineEdit
var passable_check: CheckButton
var brush_size_group: ButtonGroup
var color_by_option: OptionButton
var show_grid_check: CheckButton
var show_labels_check: CheckButton
var show_pois_check: CheckButton
var status_label: Label
var zoom_label: Label
var coords_label: Label
var selected_region_panel: VBoxContainer

# Settlement UI
var settlement_panel: VBoxContainer
var capital_name_edit: LineEdit
var capital_place_btn: Button
var minor_list: ItemList
var minor_name_edit: LineEdit
var settlement_tool_active: bool = false


func _ready() -> void:
	map_state = CampaignMapEditorData.MapState.new()
	editor_state = CampaignMapEditorData.EditorState.new()

	_build_ui()
	_connect_signals()

	# Load existing data on startup
	call_deferred("_load_on_startup")


func _load_on_startup() -> void:
	# Try to load from JSON file
	if FileAccess.file_exists(EXPORT_PATH):
		_on_import_pressed()
		print("[CampaignMapEditor] Loaded from: %s" % EXPORT_PATH)
	else:
		# Load from existing .tres files
		_load_from_tres_files()
		print("[CampaignMapEditor] Loaded from .tres files")


func _build_ui() -> void:
	custom_minimum_size = Vector2(800, 600)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 4)
	add_child(main_vbox)

	# Header
	var header := _create_header()
	main_vbox.add_child(header)

	# Main content: HSplitContainer
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = -280
	main_vbox.add_child(split)

	# LEFT: Canvas
	var canvas_container := PanelContainer.new()
	canvas_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_container.custom_minimum_size = Vector2(400, 400)
	split.add_child(canvas_container)

	canvas = CampaignMapEditorCanvas.new()
	canvas.map_state = map_state
	canvas.editor_state = editor_state
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_container.add_child(canvas)

	# RIGHT: Tools panel
	var tools_scroll := ScrollContainer.new()
	tools_scroll.custom_minimum_size.x = 260
	tools_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(tools_scroll)

	var tools_panel := VBoxContainer.new()
	tools_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools_scroll.add_child(tools_panel)

	# Region list section
	_create_region_list_section(tools_panel)

	# Region properties section
	_create_region_properties_section(tools_panel)

	# Settlement section
	_create_settlement_section(tools_panel)

	# Brush controls
	_create_brush_controls(tools_panel)

	# View controls
	_create_view_controls(tools_panel)

	# Info bar
	var info_bar := _create_info_bar()
	main_vbox.add_child(info_bar)

	# Footer buttons
	var footer := _create_footer()
	main_vbox.add_child(footer)


func _create_header() -> Control:
	var hbox := HBoxContainer.new()

	var title := Label.new()
	title.text = "Campaign Map Editor"
	title.add_theme_font_size_override("font_size", 16)
	hbox.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var fit_btn := Button.new()
	fit_btn.text = "Fit View"
	fit_btn.pressed.connect(_on_fit_view_pressed)
	hbox.add_child(fit_btn)

	var center_btn := Button.new()
	center_btn.text = "Center"
	center_btn.pressed.connect(_on_center_pressed)
	hbox.add_child(center_btn)

	return hbox


func _create_region_list_section(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var label := Label.new()
	label.text = "Regions"
	section.add_child(label)

	# Region list
	region_list = ItemList.new()
	region_list.custom_minimum_size.y = 150
	region_list.max_columns = 1
	region_list.item_selected.connect(_on_region_list_selected)
	section.add_child(region_list)

	# New region row
	var new_row := HBoxContainer.new()
	new_region_edit = LineEdit.new()
	new_region_edit.placeholder_text = "region_id"
	new_region_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_row.add_child(new_region_edit)

	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.tooltip_text = "Add new region"
	add_btn.pressed.connect(_on_add_region_pressed)
	new_row.add_child(add_btn)

	section.add_child(new_row)


func _create_region_properties_section(parent: Control) -> void:
	selected_region_panel = VBoxContainer.new()
	selected_region_panel.visible = false
	parent.add_child(selected_region_panel)

	var sep := HSeparator.new()
	selected_region_panel.add_child(sep)

	var header := Label.new()
	header.text = "Region Properties"
	selected_region_panel.add_child(header)

	# Name
	var name_row := HBoxContainer.new()
	name_row.add_child(_make_label("Name:"))
	region_name_edit = LineEdit.new()
	region_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_name_edit.text_changed.connect(_on_region_name_changed)
	name_row.add_child(region_name_edit)
	selected_region_panel.add_child(name_row)

	# Terrain
	var terrain_row := HBoxContainer.new()
	terrain_row.add_child(_make_label("Terrain:"))
	terrain_option = OptionButton.new()
	terrain_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for terrain: String in CampaignMapEditorData.TERRAIN_VALUES:
		terrain_option.add_item(terrain.capitalize())
	terrain_option.item_selected.connect(_on_terrain_changed)
	terrain_row.add_child(terrain_option)
	selected_region_panel.add_child(terrain_row)

	# Owner
	var owner_row := HBoxContainer.new()
	owner_row.add_child(_make_label("Owner:"))
	owner_option = OptionButton.new()
	owner_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owner_option.add_item("Neutral")
	for faction: String in CampaignMapEditorData.FACTION_COLORS:
		if faction != "":
			owner_option.add_item(faction.capitalize())
	owner_option.item_selected.connect(_on_owner_changed)
	owner_row.add_child(owner_option)
	selected_region_panel.add_child(owner_row)

	# Passable
	var passable_row := HBoxContainer.new()
	passable_row.add_child(_make_label("Passable:"))
	passable_check = CheckButton.new()
	passable_check.button_pressed = true
	passable_check.toggled.connect(_on_passable_changed)
	passable_row.add_child(passable_check)
	selected_region_panel.add_child(passable_row)

	# Delete button
	var delete_btn := Button.new()
	delete_btn.text = "Delete Region"
	delete_btn.pressed.connect(_on_delete_region_pressed)
	selected_region_panel.add_child(delete_btn)


func _create_settlement_section(parent: Control) -> void:
	settlement_panel = VBoxContainer.new()
	settlement_panel.visible = false
	parent.add_child(settlement_panel)

	var sep := HSeparator.new()
	settlement_panel.add_child(sep)

	var header := Label.new()
	header.text = "Settlements (Capital + Minor)"
	settlement_panel.add_child(header)

	# Capital settlement
	var capital_header := Label.new()
	capital_header.text = "Regional Capital:"
	capital_header.add_theme_font_size_override("font_size", 12)
	settlement_panel.add_child(capital_header)

	var capital_row := HBoxContainer.new()
	capital_name_edit = LineEdit.new()
	capital_name_edit.placeholder_text = "Capital name..."
	capital_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	capital_name_edit.text_changed.connect(_on_capital_name_changed)
	capital_row.add_child(capital_name_edit)

	capital_place_btn = Button.new()
	capital_place_btn.text = "Place"
	capital_place_btn.tooltip_text = "Click on map to place capital"
	capital_place_btn.toggle_mode = true
	capital_place_btn.toggled.connect(_on_capital_place_toggled)
	capital_row.add_child(capital_place_btn)
	settlement_panel.add_child(capital_row)

	# Minor settlements header
	var minor_header := Label.new()
	minor_header.text = "Minor Settlements (0-3):"
	minor_header.add_theme_font_size_override("font_size", 12)
	settlement_panel.add_child(minor_header)

	# Minor settlements list
	minor_list = ItemList.new()
	minor_list.custom_minimum_size.y = 80
	minor_list.max_columns = 1
	minor_list.item_selected.connect(_on_minor_selected)
	settlement_panel.add_child(minor_list)

	# Add minor settlement row
	var minor_row := HBoxContainer.new()
	minor_name_edit = LineEdit.new()
	minor_name_edit.placeholder_text = "Minor settlement..."
	minor_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minor_row.add_child(minor_name_edit)

	var add_minor_btn := Button.new()
	add_minor_btn.text = "+"
	add_minor_btn.tooltip_text = "Add minor settlement (click map to place)"
	add_minor_btn.pressed.connect(_on_add_minor_pressed)
	minor_row.add_child(add_minor_btn)

	var del_minor_btn := Button.new()
	del_minor_btn.text = "-"
	del_minor_btn.tooltip_text = "Remove selected minor settlement"
	del_minor_btn.pressed.connect(_on_delete_minor_pressed)
	minor_row.add_child(del_minor_btn)
	settlement_panel.add_child(minor_row)

	# Auto-generate button
	var auto_btn := Button.new()
	auto_btn.text = "Auto-Generate Settlements"
	auto_btn.tooltip_text = "Auto-place capital at region center, generate names"
	auto_btn.pressed.connect(_on_auto_generate_settlements)
	settlement_panel.add_child(auto_btn)


func _create_brush_controls(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var label := Label.new()
	label.text = "Brush"
	section.add_child(label)

	# Brush size
	var size_row := HBoxContainer.new()
	size_row.add_child(_make_label("Size:"))

	brush_size_group = ButtonGroup.new()
	for size_val: int in [1, 3, 5]:
		var btn := Button.new()
		btn.text = "%dx%d" % [size_val, size_val]
		btn.toggle_mode = true
		btn.button_group = brush_size_group
		btn.button_pressed = (size_val == 1)
		btn.pressed.connect(_on_brush_size_changed.bind(size_val))
		size_row.add_child(btn)

	section.add_child(size_row)


func _create_view_controls(parent: Control) -> void:
	var section := VBoxContainer.new()
	parent.add_child(section)

	var sep := HSeparator.new()
	section.add_child(sep)

	var label := Label.new()
	label.text = "View Options"
	section.add_child(label)

	# Color by
	var color_row := HBoxContainer.new()
	color_row.add_child(_make_label("Color by:"))
	color_by_option = OptionButton.new()
	color_by_option.add_item("Terrain")
	color_by_option.add_item("Owner")
	color_by_option.add_item("Region")
	color_by_option.item_selected.connect(_on_color_by_changed)
	color_row.add_child(color_by_option)
	section.add_child(color_row)

	# Toggles
	show_grid_check = CheckButton.new()
	show_grid_check.text = "Show Grid"
	show_grid_check.button_pressed = true
	show_grid_check.toggled.connect(_on_show_grid_changed)
	section.add_child(show_grid_check)

	show_labels_check = CheckButton.new()
	show_labels_check.text = "Show Labels"
	show_labels_check.button_pressed = true
	show_labels_check.toggled.connect(_on_show_labels_changed)
	section.add_child(show_labels_check)

	show_pois_check = CheckButton.new()
	show_pois_check.text = "Show POIs"
	show_pois_check.button_pressed = true
	show_pois_check.toggled.connect(_on_show_pois_changed)
	section.add_child(show_pois_check)


func _create_info_bar() -> Control:
	var hbox := HBoxContainer.new()

	coords_label = Label.new()
	coords_label.text = "Cell: --"
	hbox.add_child(coords_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	zoom_label = Label.new()
	zoom_label.text = "Zoom: 50%"
	hbox.add_child(zoom_label)

	return hbox


func _create_footer() -> Control:
	var vbox := VBoxContainer.new()

	var row1 := HBoxContainer.new()

	var export_btn := Button.new()
	export_btn.text = "Export JSON"
	export_btn.pressed.connect(_on_export_pressed)
	row1.add_child(export_btn)

	var import_btn := Button.new()
	import_btn.text = "Import JSON"
	import_btn.pressed.connect(_on_import_pressed)
	row1.add_child(import_btn)

	var save_tres_btn := Button.new()
	save_tres_btn.text = "Save to .tres"
	save_tres_btn.tooltip_text = "Save regions as .tres resource files"
	save_tres_btn.pressed.connect(_on_save_tres_pressed)
	row1.add_child(save_tres_btn)

	vbox.add_child(row1)

	var row2 := HBoxContainer.new()

	var reload_btn := Button.new()
	reload_btn.text = "Reload from .tres"
	reload_btn.pressed.connect(_on_reload_tres_pressed)
	row2.add_child(reload_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear All"
	clear_btn.pressed.connect(_on_clear_pressed)
	row2.add_child(clear_btn)

	vbox.add_child(row2)

	status_label = Label.new()
	status_label.text = "Ready"
	vbox.add_child(status_label)

	return vbox


func _connect_signals() -> void:
	canvas.cell_painted.connect(_on_cell_painted)
	canvas.cell_erased.connect(_on_cell_erased)
	canvas.cell_selected.connect(_on_cell_selected)
	canvas.poi_selected.connect(_on_poi_selected)
	canvas.canvas_zoomed.connect(_on_canvas_zoomed)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 60
	return label


# --- Region list ---

func _update_region_list() -> void:
	region_list.clear()

	var region_ids: Array[String] = map_state.get_all_region_ids()
	for region_id: String in region_ids:
		var info: CampaignMapEditorData.RegionInfo = map_state.get_region(region_id)
		var display: String = info.region_name if info else region_id
		var idx: int = region_list.add_item(display)
		region_list.set_item_metadata(idx, region_id)

		# Highlight selected
		if region_id == editor_state.current_region_id:
			region_list.select(idx)


func _on_region_list_selected(index: int) -> void:
	if index >= 0 and index < region_list.item_count:
		var region_id: String = region_list.get_item_metadata(index)
		editor_state.current_region_id = region_id
		_update_region_properties_panel()
		canvas.queue_redraw()


func _on_add_region_pressed() -> void:
	var region_id: String = new_region_edit.text.strip_edges().to_snake_case()
	if region_id.is_empty():
		_set_status("Enter a region ID")
		return

	if map_state.regions.has(region_id):
		_set_status("Region already exists: %s" % region_id)
		return

	map_state.add_region(region_id)
	editor_state.current_region_id = region_id
	new_region_edit.text = ""
	_update_region_list()
	_update_region_properties_panel()
	_set_status("Added region: %s" % region_id)


func _on_delete_region_pressed() -> void:
	if editor_state.current_region_id.is_empty():
		return

	# Clear cells assigned to this region
	for i: int in range(map_state.cell_regions.size()):
		if map_state.cell_regions[i] == editor_state.current_region_id:
			map_state.cell_regions[i] = ""

	map_state.regions.erase(editor_state.current_region_id)
	_set_status("Deleted region: %s" % editor_state.current_region_id)
	editor_state.current_region_id = ""
	_update_region_list()
	_update_region_properties_panel()
	canvas.queue_redraw()


# --- Region properties ---

func _update_region_properties_panel() -> void:
	if editor_state.current_region_id.is_empty():
		selected_region_panel.visible = false
		_update_settlement_panel()
		return

	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if not info:
		selected_region_panel.visible = false
		_update_settlement_panel()
		return

	selected_region_panel.visible = true

	region_name_edit.text = info.region_name

	var terrain_idx: int = CampaignMapEditorData.TERRAIN_VALUES.find(info.terrain_type)
	terrain_option.selected = terrain_idx if terrain_idx >= 0 else 0

	# Owner - find index
	if info.owner_faction == "":
		owner_option.selected = 0
	else:
		for i: int in range(owner_option.item_count):
			if owner_option.get_item_text(i).to_lower() == info.owner_faction:
				owner_option.selected = i
				break

	passable_check.button_pressed = info.is_passable

	# Also update settlement panel
	_update_settlement_panel()


func _on_region_name_changed(new_text: String) -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if info:
		info.region_name = new_text
		_update_region_list()
		canvas.queue_redraw()


func _on_terrain_changed(index: int) -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if info and index >= 0 and index < CampaignMapEditorData.TERRAIN_VALUES.size():
		info.terrain_type = CampaignMapEditorData.TERRAIN_VALUES[index]
		info.region_color = CampaignMapEditorData.TERRAIN_COLORS.get(info.terrain_type, Color(0.5, 0.5, 0.5, 0.3))
		canvas.queue_redraw()


func _on_owner_changed(index: int) -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if info:
		if index == 0:
			info.owner_faction = ""
		else:
			info.owner_faction = owner_option.get_item_text(index).to_lower()
		canvas.queue_redraw()


func _on_passable_changed(pressed: bool) -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if info:
		info.is_passable = pressed


# --- Settlement handling ---

func _update_settlement_panel() -> void:
	if editor_state.current_region_id.is_empty():
		settlement_panel.visible = false
		return

	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if not info:
		settlement_panel.visible = false
		return

	settlement_panel.visible = true

	# Update capital name
	var capital_data: Dictionary = map_state.poi_data.get(info.capital_settlement_id, {})
	capital_name_edit.text = capital_data.get("name", "")

	# Update minor settlements list
	minor_list.clear()
	for minor_id: String in info.minor_settlement_ids:
		var minor_data: Dictionary = map_state.poi_data.get(minor_id, {})
		var display_name: String = minor_data.get("name", minor_id)
		var idx: int = minor_list.add_item(display_name)
		minor_list.set_item_metadata(idx, minor_id)


func _on_capital_name_changed(new_text: String) -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if not info or info.capital_settlement_id.is_empty():
		return

	if not map_state.poi_data.has(info.capital_settlement_id):
		map_state.poi_data[info.capital_settlement_id] = {}
	map_state.poi_data[info.capital_settlement_id]["name"] = new_text
	canvas.queue_redraw()


func _on_capital_place_toggled(pressed: bool) -> void:
	settlement_tool_active = pressed
	if pressed:
		_set_status("Click on map to place capital...")
	else:
		_set_status("Ready")


func _on_add_minor_pressed() -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if not info:
		return

	if info.minor_settlement_ids.size() >= 3:
		_set_status("Maximum 3 minor settlements per region")
		return

	# Generate unique ID
	var minor_id := "%s_minor_%d" % [editor_state.current_region_id, info.minor_settlement_ids.size() + 1]
	var minor_name: String = minor_name_edit.text.strip_edges()
	if minor_name.is_empty():
		minor_name = _generate_settlement_name(editor_state.current_region_id, "minor")

	# Create POI data
	map_state.poi_data[minor_id] = {
		"name": minor_name,
		"type": "settlement",
		"settlement_type": "town",
		"region_id": editor_state.current_region_id,
		"x": -1,
		"y": -1,
		"is_capital": false
	}

	info.minor_settlement_ids.append(minor_id)
	minor_name_edit.text = ""
	_update_settlement_panel()
	_set_status("Added minor settlement - click map to place")
	canvas.queue_redraw()


func _on_delete_minor_pressed() -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if not info:
		return

	var selected: PackedInt32Array = minor_list.get_selected_items()
	if selected.is_empty():
		return

	var minor_id: String = minor_list.get_item_metadata(selected[0])
	info.minor_settlement_ids.erase(minor_id)
	map_state.poi_data.erase(minor_id)
	_update_settlement_panel()
	canvas.queue_redraw()
	_set_status("Removed minor settlement")


func _on_minor_selected(_index: int) -> void:
	pass  # Could add editing functionality here


func _on_auto_generate_settlements() -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if not info:
		return

	# Find cells belonging to this region
	var region_cells: Array[Vector2i] = []
	for i: int in range(map_state.cell_regions.size()):
		if map_state.cell_regions[i] == editor_state.current_region_id:
			region_cells.append(map_state.get_cell_coords(i))

	if region_cells.is_empty():
		_set_status("No cells assigned to this region")
		return

	# Calculate region center
	var center := Vector2.ZERO
	for cell: Vector2i in region_cells:
		center += Vector2(cell.x, cell.y)
	center /= float(region_cells.size())
	var center_cell := Vector2i(int(center.x), int(center.y))

	# Create capital if not exists
	if info.capital_settlement_id.is_empty():
		info.capital_settlement_id = "%s_capital" % editor_state.current_region_id
		var capital_name := _generate_settlement_name(editor_state.current_region_id, "capital")
		map_state.poi_data[info.capital_settlement_id] = {
			"name": capital_name,
			"type": "settlement",
			"settlement_type": "capital",
			"region_id": editor_state.current_region_id,
			"x": center_cell.x,
			"y": center_cell.y,
			"is_capital": true
		}

	# Auto-place capital at center
	map_state.poi_data[info.capital_settlement_id]["x"] = center_cell.x
	map_state.poi_data[info.capital_settlement_id]["y"] = center_cell.y

	# Auto-place existing minors around region
	for i: int in range(info.minor_settlement_ids.size()):
		var minor_id: String = info.minor_settlement_ids[i]
		if map_state.poi_data.has(minor_id):
			# Place at offset from center
			var offset := Vector2i(0, 0)
			match i:
				0: offset = Vector2i(-2, -1)
				1: offset = Vector2i(2, 1)
				2: offset = Vector2i(0, 2)
			var minor_cell := center_cell + offset
			# Clamp to grid
			minor_cell.x = clampi(minor_cell.x, 0, map_state.grid_width - 1)
			minor_cell.y = clampi(minor_cell.y, 0, map_state.grid_height - 1)
			map_state.poi_data[minor_id]["x"] = minor_cell.x
			map_state.poi_data[minor_id]["y"] = minor_cell.y

	_update_settlement_panel()
	canvas.queue_redraw()
	_set_status("Auto-generated settlements for %s" % info.region_name)


func _generate_settlement_name(region_id: String, settlement_type: String) -> String:
	# Generate thematic names based on region
	var region_name: String = region_id.replace("_", " ").capitalize()

	var capital_suffixes: Array[String] = ["Keep", "Hold", "Fortress", "Citadel", "Castle"]
	var minor_suffixes: Array[String] = ["Village", "Hamlet", "Crossing", "Mill", "Ford", "Watch"]

	if settlement_type == "capital":
		return region_name + " " + capital_suffixes[randi() % capital_suffixes.size()]
	else:
		return region_name + " " + minor_suffixes[randi() % minor_suffixes.size()]


func _place_settlement_at_cell(x: int, y: int) -> void:
	if editor_state.current_region_id.is_empty():
		return
	var info: CampaignMapEditorData.RegionInfo = map_state.get_region(editor_state.current_region_id)
	if not info:
		return

	# Check if placing capital
	if capital_place_btn and capital_place_btn.button_pressed:
		if info.capital_settlement_id.is_empty():
			# Create new capital
			info.capital_settlement_id = "%s_capital" % editor_state.current_region_id
			var capital_name := capital_name_edit.text.strip_edges()
			if capital_name.is_empty():
				capital_name = _generate_settlement_name(editor_state.current_region_id, "capital")

			map_state.poi_data[info.capital_settlement_id] = {
				"name": capital_name,
				"type": "settlement",
				"settlement_type": "capital",
				"region_id": editor_state.current_region_id,
				"x": x,
				"y": y,
				"is_capital": true
			}
		else:
			# Move existing capital
			map_state.poi_data[info.capital_settlement_id]["x"] = x
			map_state.poi_data[info.capital_settlement_id]["y"] = y

		capital_place_btn.button_pressed = false
		settlement_tool_active = false
		_update_settlement_panel()
		canvas.queue_redraw()
		_set_status("Capital placed at (%d, %d)" % [x, y])
		return

	# Check for unplaced minor settlements
	for minor_id: String in info.minor_settlement_ids:
		if map_state.poi_data.has(minor_id):
			var data: Dictionary = map_state.poi_data[minor_id]
			if data.get("x", -1) < 0:
				data["x"] = x
				data["y"] = y
				canvas.queue_redraw()
				_set_status("Minor settlement placed at (%d, %d)" % [x, y])
				return


# --- Canvas events ---

func _on_cell_painted(x: int, y: int, region_id: String) -> void:
	map_state.set_cell_region(x, y, region_id)
	canvas.queue_redraw()
	_update_coords_label(x, y)


func _on_cell_erased(x: int, y: int) -> void:
	map_state.set_cell_region(x, y, "")
	canvas.queue_redraw()
	_update_coords_label(x, y)


func _on_cell_selected(x: int, y: int) -> void:
	_update_coords_label(x, y)

	# Handle settlement placement if tool is active
	if settlement_tool_active:
		_place_settlement_at_cell(x, y)
		return

	# Show region at this cell
	var region_id: String = map_state.get_cell_region(x, y)
	if not region_id.is_empty() and region_id != editor_state.current_region_id:
		editor_state.current_region_id = region_id
		_update_region_list()
		_update_region_properties_panel()


func _on_poi_selected(index: int) -> void:
	editor_state.selected_poi_index = index
	canvas.queue_redraw()


func _on_canvas_zoomed(zoom: float) -> void:
	zoom_label.text = "Zoom: %d%%" % int(zoom * 100)


func _update_coords_label(x: int, y: int) -> void:
	var region_id: String = map_state.get_cell_region(x, y)
	var region_str: String = region_id if not region_id.is_empty() else "none"
	coords_label.text = "Cell: (%d, %d) | Region: %s" % [x, y, region_str]


# --- Brush ---

func _on_brush_size_changed(size_val: int) -> void:
	editor_state.brush_size = size_val


# --- View ---

func _on_color_by_changed(index: int) -> void:
	match index:
		0: editor_state.color_by = "terrain"
		1: editor_state.color_by = "owner"
		2: editor_state.color_by = "region"
	canvas.queue_redraw()


func _on_show_grid_changed(pressed: bool) -> void:
	editor_state.show_grid = pressed
	canvas.queue_redraw()


func _on_show_labels_changed(pressed: bool) -> void:
	editor_state.show_labels = pressed
	canvas.queue_redraw()


func _on_show_pois_changed(pressed: bool) -> void:
	editor_state.show_pois = pressed
	canvas.queue_redraw()


func _on_fit_view_pressed() -> void:
	canvas.fit_to_view()


func _on_center_pressed() -> void:
	canvas.center_on_map()


# --- Export/Import ---

func _on_export_pressed() -> void:
	var data: Dictionary = map_state.to_dict()
	var json_str: String = JSON.stringify(data, "  ")

	var file := FileAccess.open(EXPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(json_str)
		file.close()
		_set_status("Exported to: %s" % EXPORT_PATH)
	else:
		_set_status("Failed to export!")


func _on_import_pressed() -> void:
	if not FileAccess.file_exists(EXPORT_PATH):
		_set_status("No file at: %s" % EXPORT_PATH)
		return

	var file := FileAccess.open(EXPORT_PATH, FileAccess.READ)
	if not file:
		_set_status("Failed to open file!")
		return

	var json_str: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_str)
	if error != OK:
		_set_status("JSON parse error: %s" % json.get_error_message())
		return

	if not json.data is Dictionary:
		_set_status("Invalid JSON format!")
		return

	map_state.from_dict(json.data)
	_update_region_list()
	_update_region_properties_panel()
	canvas.queue_redraw()
	_set_status("Imported from: %s" % EXPORT_PATH)


func _on_save_tres_pressed() -> void:
	# Generate RegionData and SettlementData resources from current state
	var region_dir := "res://campaign_system/data/regions/"
	var settlement_dir := "res://campaign_system/data/settlements/"
	var saved_regions: int = 0
	var saved_settlements: int = 0

	# Ensure settlement directory exists
	if not DirAccess.dir_exists_absolute(settlement_dir):
		DirAccess.make_dir_recursive_absolute(settlement_dir)

	for region_id: String in map_state.regions:
		var info: CampaignMapEditorData.RegionInfo = map_state.get_region(region_id)
		if not info:
			continue

		# Generate polygon from cells
		var cells: Array[Vector2i] = []
		for i: int in range(map_state.cell_regions.size()):
			if map_state.cell_regions[i] == region_id:
				cells.append(map_state.get_cell_coords(i))

		if cells.is_empty():
			continue

		# Create RegionData
		var region := RegionData.new()
		region.region_id = region_id
		region.region_name = info.region_name
		region.owner_faction = info.owner_faction
		region.is_passable = info.is_passable
		region.region_color = info.region_color

		# Set terrain type
		match info.terrain_type:
			"plains": region.terrain_type = RegionData.TerrainType.PLAINS
			"forest": region.terrain_type = RegionData.TerrainType.FOREST
			"hills": region.terrain_type = RegionData.TerrainType.HILLS
			"mountains": region.terrain_type = RegionData.TerrainType.MOUNTAINS
			"desert": region.terrain_type = RegionData.TerrainType.DESERT
			"swamp": region.terrain_type = RegionData.TerrainType.SWAMP
			"coast": region.terrain_type = RegionData.TerrainType.COAST

		# Set settlement references
		region.capital_settlement_id = info.capital_settlement_id
		region.minor_settlement_ids = info.minor_settlement_ids.duplicate()

		# Calculate center and polygon
		var cell_size: Vector2 = map_state.get_cell_size()
		var center := Vector2.ZERO
		for cell: Vector2i in cells:
			center += Vector2((cell.x + 0.5) * cell_size.x, (cell.y + 0.5) * cell_size.y)
		center /= float(cells.size())
		region.map_center = center

		# Generate outline polygon
		region.map_polygon = _generate_outline(cells, cell_size)

		# Apply terrain defaults
		region.apply_terrain_defaults()

		# Save RegionData
		var region_path := region_dir + region_id + ".tres"
		var err := ResourceSaver.save(region, region_path)
		if err == OK:
			saved_regions += 1
		else:
			push_error("Failed to save region: %s" % region_id)

		# Save capital settlement if exists
		if not info.capital_settlement_id.is_empty() and map_state.poi_data.has(info.capital_settlement_id):
			var capital_data: Dictionary = map_state.poi_data[info.capital_settlement_id]
			var settlement := _create_settlement_resource(info.capital_settlement_id, capital_data, region_id, true, cell_size)
			if settlement:
				var settlement_path := settlement_dir + info.capital_settlement_id + ".tres"
				err = ResourceSaver.save(settlement, settlement_path)
				if err == OK:
					saved_settlements += 1

		# Save minor settlements
		for minor_id: String in info.minor_settlement_ids:
			if map_state.poi_data.has(minor_id):
				var minor_data: Dictionary = map_state.poi_data[minor_id]
				var settlement := _create_settlement_resource(minor_id, minor_data, region_id, false, cell_size)
				if settlement:
					var settlement_path := settlement_dir + minor_id + ".tres"
					err = ResourceSaver.save(settlement, settlement_path)
					if err == OK:
						saved_settlements += 1

	_set_status("Saved %d regions, %d settlements to .tres files" % [saved_regions, saved_settlements])


func _create_settlement_resource(settlement_id: String, data: Dictionary, region_id: String, is_capital: bool, cell_size: Vector2) -> SettlementData:
	var settlement := SettlementData.new()
	settlement.settlement_id = settlement_id
	settlement.settlement_name = data.get("name", settlement_id.capitalize().replace("_", " "))
	settlement.region_id = region_id
	settlement.is_regional_capital = is_capital

	# Set settlement type
	if is_capital:
		settlement.settlement_type = SettlementData.SettlementType.CAPITAL
	else:
		var stype: String = data.get("settlement_type", "town")
		match stype:
			"capital": settlement.settlement_type = SettlementData.SettlementType.CAPITAL
			"town": settlement.settlement_type = SettlementData.SettlementType.TOWN
			"village": settlement.settlement_type = SettlementData.SettlementType.VILLAGE
			"fortress": settlement.settlement_type = SettlementData.SettlementType.FORTRESS
			"city": settlement.settlement_type = SettlementData.SettlementType.CITY
			_: settlement.settlement_type = SettlementData.SettlementType.TOWN

	# Calculate map position from grid cell
	var x: int = data.get("x", 0)
	var y: int = data.get("y", 0)
	settlement.map_position = Vector2((x + 0.5) * cell_size.x, (y + 0.5) * cell_size.y)

	# Apply type defaults
	settlement.apply_type_defaults()

	return settlement


func _on_reload_tres_pressed() -> void:
	_load_from_tres_files()
	_set_status("Reloaded from .tres files")


func _load_from_tres_files() -> void:
	map_state.clear_all()

	var region_dir := "res://campaign_system/data/regions/"
	var settlement_dir := "res://campaign_system/data/settlements/"
	var cell_size: Vector2 = map_state.get_cell_size()

	# Load regions
	var dir := DirAccess.open(region_dir)
	if not dir:
		_set_status("Cannot open regions directory")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := region_dir + file_name
			var resource := load(path)
			if resource is RegionData:
				var region: RegionData = resource

				# Create RegionInfo
				var info := CampaignMapEditorData.RegionInfo.new(region.region_id)
				info.region_name = region.region_name
				info.owner_faction = region.owner_faction
				info.is_passable = region.is_passable
				info.region_color = region.region_color
				info.capital_settlement_id = region.capital_settlement_id
				info.minor_settlement_ids = region.minor_settlement_ids.duplicate()

				match region.terrain_type:
					RegionData.TerrainType.PLAINS: info.terrain_type = "plains"
					RegionData.TerrainType.FOREST: info.terrain_type = "forest"
					RegionData.TerrainType.HILLS: info.terrain_type = "hills"
					RegionData.TerrainType.MOUNTAINS: info.terrain_type = "mountains"
					RegionData.TerrainType.DESERT: info.terrain_type = "desert"
					RegionData.TerrainType.SWAMP: info.terrain_type = "swamp"
					RegionData.TerrainType.COAST: info.terrain_type = "coast"

				map_state.regions[region.region_id] = info

				# Assign cells based on map_center
				if region.map_center != Vector2.ZERO:
					var center_cell := Vector2i(
						int(region.map_center.x / cell_size.x),
						int(region.map_center.y / cell_size.y)
					)
					if center_cell.x >= 0 and center_cell.x < map_state.grid_width:
						if center_cell.y >= 0 and center_cell.y < map_state.grid_height:
							map_state.set_cell_region(center_cell.x, center_cell.y, region.region_id)

		file_name = dir.get_next()
	dir.list_dir_end()

	# Load settlements
	var settlement_dir_access := DirAccess.open(settlement_dir)
	if settlement_dir_access:
		settlement_dir_access.list_dir_begin()
		file_name = settlement_dir_access.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var path := settlement_dir + file_name
				var resource := load(path)
				if resource is SettlementData:
					var settlement: SettlementData = resource

					# Convert map position back to grid cell
					var grid_x: int = int(settlement.map_position.x / cell_size.x)
					var grid_y: int = int(settlement.map_position.y / cell_size.y)

					# Create POI data for this settlement
					map_state.poi_data[settlement.settlement_id] = {
						"name": settlement.settlement_name,
						"type": "settlement",
						"settlement_type": _settlement_type_to_string(settlement.settlement_type),
						"region_id": settlement.region_id,
						"x": grid_x,
						"y": grid_y,
						"is_capital": settlement.is_regional_capital
					}

			file_name = settlement_dir_access.get_next()
		settlement_dir_access.list_dir_end()

	_update_region_list()
	canvas.queue_redraw()


func _settlement_type_to_string(stype: SettlementData.SettlementType) -> String:
	match stype:
		SettlementData.SettlementType.VILLAGE: return "village"
		SettlementData.SettlementType.TOWN: return "town"
		SettlementData.SettlementType.CITY: return "city"
		SettlementData.SettlementType.FORTRESS: return "fortress"
		SettlementData.SettlementType.CAPITAL: return "capital"
	return "town"


func _on_clear_pressed() -> void:
	map_state.clear_all()
	editor_state.current_region_id = ""
	_update_region_list()
	_update_region_properties_panel()
	canvas.queue_redraw()
	_set_status("Cleared all data")


func _set_status(text: String) -> void:
	if status_label:
		status_label.text = text
	print("[CampaignMapEditor] %s" % text)


# --- Polygon generation ---

func _generate_outline(cells: Array[Vector2i], cell_size: Vector2) -> PackedVector2Array:
	if cells.is_empty():
		return PackedVector2Array()

	# Convert to set for fast lookup
	var cell_set: Dictionary = {}
	for cell: Vector2i in cells:
		cell_set[cell] = true

	# Find all boundary edges
	var edges: Array = []

	for cell: Vector2i in cells:
		var corners: Array[Vector2] = _cell_corners(cell, cell_size)

		var neighbors: Array[Vector2i] = [
			Vector2i(cell.x, cell.y - 1),  # Top
			Vector2i(cell.x + 1, cell.y),  # Right
			Vector2i(cell.x, cell.y + 1),  # Bottom
			Vector2i(cell.x - 1, cell.y),  # Left
		]

		var edge_indices: Array = [
			[0, 1],  # Top
			[1, 2],  # Right
			[2, 3],  # Bottom
			[3, 0],  # Left
		]

		for i: int in range(4):
			if not cell_set.has(neighbors[i]):
				var idx: Array = edge_indices[i]
				edges.append([corners[idx[0]], corners[idx[1]]])

	return _edges_to_polygon(edges)


func _cell_corners(cell: Vector2i, cell_size: Vector2) -> Array[Vector2]:
	var x: float = cell.x * cell_size.x
	var y: float = cell.y * cell_size.y
	return [
		Vector2(x, y),                           # Top-left
		Vector2(x + cell_size.x, y),             # Top-right
		Vector2(x + cell_size.x, y + cell_size.y), # Bottom-right
		Vector2(x, y + cell_size.y)              # Bottom-left
	]


func _edges_to_polygon(edges: Array) -> PackedVector2Array:
	if edges.is_empty():
		return PackedVector2Array()

	var polygon: Array[Vector2] = []
	var remaining := edges.duplicate()

	var current_edge: Array = remaining.pop_front()
	polygon.append(current_edge[0])
	polygon.append(current_edge[1])

	var max_iterations: int = remaining.size() + 1
	var iterations: int = 0

	while not remaining.is_empty() and iterations < max_iterations:
		iterations += 1
		var found: bool = false
		var last_point: Vector2 = polygon[polygon.size() - 1]

		for i: int in range(remaining.size()):
			var edge: Array = remaining[i]

			if last_point.distance_to(edge[0]) < 0.1:
				polygon.append(edge[1])
				remaining.remove_at(i)
				found = true
				break
			elif last_point.distance_to(edge[1]) < 0.1:
				polygon.append(edge[0])
				remaining.remove_at(i)
				found = true
				break

		if not found:
			break

	# Remove duplicate last point
	if polygon.size() > 1 and polygon[0].distance_to(polygon[polygon.size() - 1]) < 0.1:
		polygon.pop_back()

	return PackedVector2Array(polygon)
