# Panel for managing reinforcement waves in pre-battle.
# Shows which units deploy first vs held as reinforcements.
class_name ReinforcementPanel
extends Control


signal deployment_order_changed(core_units: Array, reinforcements: Array)


const MAX_CORE_UNITS := 8  # First wave deployment limit
const TEXT_COLOR := Color(0.95, 0.92, 0.85, 1.0)
const CORE_COLOR := Color(0.4, 0.8, 0.4, 1.0)
const RESERVE_COLOR := Color(0.8, 0.7, 0.4, 1.0)

var battalion: Resource = null
var core_units: Array = []
var reserve_units: Array = []

var core_list: ItemList = null
var reserve_list: ItemList = null
var info_label: Label = null


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 10)
	add_child(main_vbox)

	# Header
	var header := Label.new()
	header.text = "Deployment Order"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", TEXT_COLOR)
	main_vbox.add_child(header)

	# Info text
	info_label = Label.new()
	info_label.text = "First %d units deploy at battle start. Others arrive as reinforcements." % MAX_CORE_UNITS
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_label.add_theme_font_size_override("font_size", 12)
	main_vbox.add_child(info_label)

	# Two-column layout
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)
	main_vbox.add_child(hbox)

	# Core units (left side)
	var core_panel := _create_list_panel("CORE DEPLOYMENT", CORE_COLOR, true)
	core_list = core_panel.get_node("VBox/List")
	hbox.add_child(core_panel)

	# Transfer buttons (center)
	var button_vbox := VBoxContainer.new()
	button_vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button_vbox.add_theme_constant_override("separation", 5)
	hbox.add_child(button_vbox)

	var to_reserve_btn := Button.new()
	to_reserve_btn.text = ">>"
	to_reserve_btn.tooltip_text = "Move to Reserves"
	to_reserve_btn.pressed.connect(_on_move_to_reserve)
	button_vbox.add_child(to_reserve_btn)

	var to_core_btn := Button.new()
	to_core_btn.text = "<<"
	to_core_btn.tooltip_text = "Move to Core"
	to_core_btn.pressed.connect(_on_move_to_core)
	button_vbox.add_child(to_core_btn)

	var up_btn := Button.new()
	up_btn.text = "Up"
	up_btn.tooltip_text = "Move Up in Order"
	up_btn.pressed.connect(_on_move_up)
	button_vbox.add_child(up_btn)

	var down_btn := Button.new()
	down_btn.text = "Down"
	down_btn.tooltip_text = "Move Down in Order"
	down_btn.pressed.connect(_on_move_down)
	button_vbox.add_child(down_btn)

	# Reserve units (right side)
	var reserve_panel := _create_list_panel("REINFORCEMENTS", RESERVE_COLOR, false)
	reserve_list = reserve_panel.get_node("VBox/List")
	hbox.add_child(reserve_panel)

	# Reinforcement info
	var reinforce_info := Label.new()
	reinforce_info.text = "Reinforcements arrive when:\n- 40% of core units are casualties\n- Every 90 seconds during battle\n- Player manually requests (costs morale)"
	reinforce_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	reinforce_info.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	reinforce_info.add_theme_font_size_override("font_size", 11)
	main_vbox.add_child(reinforce_info)


func _create_list_panel(title: String, color: Color, is_core: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	panel.add_child(vbox)

	var header := Label.new()
	header.text = title
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", color)
	vbox.add_child(header)

	var count_label := Label.new()
	count_label.name = "Count"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(count_label)

	var list := ItemList.new()
	list.name = "List"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_SINGLE
	vbox.add_child(list)

	return panel


func update_reinforcements(batt: Resource) -> void:
	battalion = batt

	if not battalion:
		return

	# Split regiments into core and reserve based on current order
	core_units.clear()
	reserve_units.clear()

	for i in range(battalion.regiments.size()):
		if i < MAX_CORE_UNITS:
			core_units.append(battalion.regiments[i])
		else:
			reserve_units.append(battalion.regiments[i])

	_refresh_lists()


func _refresh_lists() -> void:
	core_list.clear()
	reserve_list.clear()

	for regiment in core_units:
		var name: String = regiment.regiment_name if regiment.get("regiment_name") else regiment.get_meta("regiment_name", "Unknown")
		var soldiers: int = regiment.current_soldiers if regiment.get("current_soldiers") else regiment.get_meta("current_soldiers", 60)
		core_list.add_item("%s (%d)" % [name, soldiers])

	for regiment in reserve_units:
		var name: String = regiment.regiment_name if regiment.get("regiment_name") else regiment.get_meta("regiment_name", "Unknown")
		var soldiers: int = regiment.current_soldiers if regiment.get("current_soldiers") else regiment.get_meta("current_soldiers", 60)
		reserve_list.add_item("%s (%d)" % [name, soldiers])

	# Update count labels
	var core_panel: Control = core_list.get_parent().get_parent()
	var core_count: Label = core_panel.get_node("VBox/Count")
	if core_count:
		core_count.text = "(%d / %d)" % [core_units.size(), MAX_CORE_UNITS]

	var reserve_panel: Control = reserve_list.get_parent().get_parent()
	var reserve_count: Label = reserve_panel.get_node("VBox/Count")
	if reserve_count:
		reserve_count.text = "(%d units)" % reserve_units.size()


func _on_move_to_reserve() -> void:
	var selected := core_list.get_selected_items()
	if selected.is_empty():
		return

	var idx: int = selected[0]
	if idx < 0 or idx >= core_units.size():
		return

	var regiment := core_units[idx]
	core_units.remove_at(idx)
	reserve_units.push_front(regiment)

	_refresh_lists()
	_emit_change()


func _on_move_to_core() -> void:
	if core_units.size() >= MAX_CORE_UNITS:
		return

	var selected := reserve_list.get_selected_items()
	if selected.is_empty():
		return

	var idx: int = selected[0]
	if idx < 0 or idx >= reserve_units.size():
		return

	var regiment := reserve_units[idx]
	reserve_units.remove_at(idx)
	core_units.append(regiment)

	_refresh_lists()
	_emit_change()


func _on_move_up() -> void:
	# Check which list has selection
	var core_selected := core_list.get_selected_items()
	var reserve_selected := reserve_list.get_selected_items()

	if not core_selected.is_empty():
		var idx: int = core_selected[0]
		if idx > 0:
			var temp := core_units[idx]
			core_units[idx] = core_units[idx - 1]
			core_units[idx - 1] = temp
			_refresh_lists()
			core_list.select(idx - 1)
			_emit_change()
	elif not reserve_selected.is_empty():
		var idx: int = reserve_selected[0]
		if idx > 0:
			var temp := reserve_units[idx]
			reserve_units[idx] = reserve_units[idx - 1]
			reserve_units[idx - 1] = temp
			_refresh_lists()
			reserve_list.select(idx - 1)
			_emit_change()


func _on_move_down() -> void:
	var core_selected := core_list.get_selected_items()
	var reserve_selected := reserve_list.get_selected_items()

	if not core_selected.is_empty():
		var idx: int = core_selected[0]
		if idx < core_units.size() - 1:
			var temp := core_units[idx]
			core_units[idx] = core_units[idx + 1]
			core_units[idx + 1] = temp
			_refresh_lists()
			core_list.select(idx + 1)
			_emit_change()
	elif not reserve_selected.is_empty():
		var idx: int = reserve_selected[0]
		if idx < reserve_units.size() - 1:
			var temp := reserve_units[idx]
			reserve_units[idx] = reserve_units[idx + 1]
			reserve_units[idx + 1] = temp
			_refresh_lists()
			reserve_list.select(idx + 1)
			_emit_change()


func _emit_change() -> void:
	deployment_order_changed.emit(core_units, reserve_units)


func get_deployment_order() -> Dictionary:
	return {
		"core": core_units.duplicate(),
		"reinforcements": reserve_units.duplicate()
	}


func get_core_strength() -> int:
	var total := 0
	for regiment in core_units:
		var soldiers: int = regiment.current_soldiers if regiment.get("current_soldiers") else regiment.get_meta("current_soldiers", 0)
		total += soldiers
	return total


func get_reserve_strength() -> int:
	var total := 0
	for regiment in reserve_units:
		var soldiers: int = regiment.current_soldiers if regiment.get("current_soldiers") else regiment.get_meta("current_soldiers", 0)
		total += soldiers
	return total
