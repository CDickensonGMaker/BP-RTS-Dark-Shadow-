# Settlement interaction panel - shows settlement info and Enter/Attack buttons.
# Dark theme following Catacombs of Gore UI style.
extends PanelContainer


signal enter_settlement(settlement: Resource)
signal attack_settlement(settlement: Resource)
signal panel_closed()


# Dark color palette (Catacombs style)
const COLOR_BG := Color(0.05, 0.04, 0.03, 0.98)
const COLOR_BG_CARD := Color(0.07, 0.06, 0.05, 0.96)
const COLOR_BORDER := Color(0.35, 0.28, 0.18, 1.0)
const COLOR_GOLD := Color(0.9, 0.7, 0.2, 1.0)
const COLOR_TEXT := Color(0.9, 0.85, 0.75, 1.0)
const COLOR_TEXT_DIM := Color(0.6, 0.55, 0.5, 1.0)
const COLOR_HOSTILE := Color(0.8, 0.25, 0.2, 1.0)
const COLOR_FRIENDLY := Color(0.4, 0.7, 0.4, 1.0)

# Panel size (standard large popup)
const PANEL_SIZE := Vector2(480, 600)

# Current settlement
var current_settlement: Resource = null

# UI elements
var title_label: Label
var type_label: Label
var owner_label: Label
var income_label: Label
var supply_label: Label
var garrison_label: Label
var buildings_container: VBoxContainer
var enter_button: Button
var attack_button: Button
var close_button: Button


func _ready() -> void:
	_setup_style()
	_create_ui()
	visible = false


func _setup_style() -> void:
	# Dark panel background
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_BORDER
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", style)

	# Set size
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE


func _create_ui() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	title_label = Label.new()
	title_label.text = "Settlement Name"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", COLOR_GOLD)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Type & Owner
	var header_row := HBoxContainer.new()
	vbox.add_child(header_row)

	type_label = Label.new()
	type_label.text = "Village"
	type_label.add_theme_font_size_override("font_size", 18)
	type_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	header_row.add_child(type_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)

	owner_label = Label.new()
	owner_label.text = "Neutral"
	owner_label.add_theme_font_size_override("font_size", 18)
	owner_label.add_theme_color_override("font_color", COLOR_TEXT)
	header_row.add_child(owner_label)

	# Separator
	var sep1 := HSeparator.new()
	sep1.add_theme_stylebox_override("separator", _create_separator_style())
	vbox.add_child(sep1)

	# Economy stats
	var stats_container := VBoxContainer.new()
	stats_container.add_theme_constant_override("separation", 8)
	vbox.add_child(stats_container)

	income_label = _create_stat_row(stats_container, "Income:", "0 gold/turn")
	supply_label = _create_stat_row(stats_container, "Supply:", "0")
	garrison_label = _create_stat_row(stats_container, "Garrison:", "None")

	# Separator
	var sep2 := HSeparator.new()
	sep2.add_theme_stylebox_override("separator", _create_separator_style())
	vbox.add_child(sep2)

	# Buildings section
	var buildings_header := Label.new()
	buildings_header.text = "Buildings"
	buildings_header.add_theme_font_size_override("font_size", 20)
	buildings_header.add_theme_color_override("font_color", COLOR_GOLD)
	vbox.add_child(buildings_header)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 180
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	buildings_container = VBoxContainer.new()
	buildings_container.add_theme_constant_override("separation", 6)
	scroll.add_child(buildings_container)

	# Action buttons
	var button_container := HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 12)
	vbox.add_child(button_container)

	enter_button = _create_button("Enter Settlement", COLOR_FRIENDLY)
	enter_button.pressed.connect(_on_enter_pressed)
	button_container.add_child(enter_button)

	attack_button = _create_button("Attack", COLOR_HOSTILE)
	attack_button.pressed.connect(_on_attack_pressed)
	button_container.add_child(attack_button)

	# Close button
	close_button = _create_button("Close", COLOR_TEXT_DIM)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)


func _create_stat_row(parent: Control, label_text: String, value_text: String) -> Label:
	var row := HBoxContainer.new()
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	row.add_child(label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 18)
	value.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(value)

	return value


func _create_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 18)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = COLOR_BG_CARD
	style_normal.border_color = color
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", style_normal)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = color.darkened(0.7)
	style_hover.border_color = color
	style_hover.set_border_width_all(2)
	style_hover.set_corner_radius_all(3)
	button.add_theme_stylebox_override("hover", style_hover)

	var style_pressed := StyleBoxFlat.new()
	style_pressed.bg_color = color.darkened(0.5)
	style_pressed.border_color = color
	style_pressed.set_border_width_all(2)
	style_pressed.set_corner_radius_all(3)
	button.add_theme_stylebox_override("pressed", style_pressed)

	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", color.lightened(0.2))

	return button


func _create_separator_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BORDER
	style.set_content_margin_all(1)
	return style


func show_settlement(settlement: Resource) -> void:
	current_settlement = settlement
	if not settlement:
		visible = false
		return

	# Update UI
	title_label.text = settlement.settlement_name
	type_label.text = settlement.get_type_name() if settlement.has_method("get_type_name") else "Settlement"

	# Owner display
	var owner_text: String = settlement.owner_faction if settlement.owner_faction != "" else "Neutral"
	owner_label.text = owner_text

	# Check if friendly or hostile
	var is_player_owned := (settlement.owner_faction == "player" or settlement.owner_faction == "")
	if is_player_owned:
		owner_label.add_theme_color_override("font_color", COLOR_FRIENDLY)
		enter_button.visible = true
		attack_button.visible = false
	else:
		owner_label.add_theme_color_override("font_color", COLOR_HOSTILE)
		enter_button.visible = false
		attack_button.visible = true

	# Economy stats
	income_label.text = "%d gold/turn" % settlement.current_income
	supply_label.text = "%d" % settlement.current_supply

	# Garrison
	if settlement.garrison_regiments.size() > 0:
		garrison_label.text = "%d regiment(s)" % settlement.garrison_regiments.size()
	else:
		garrison_label.text = "None"

	# Buildings
	_populate_buildings(settlement)

	visible = true


func _populate_buildings(settlement: Resource) -> void:
	# Clear existing
	for child in buildings_container.get_children():
		child.queue_free()

	if settlement.buildings.size() == 0:
		var empty_label := Label.new()
		empty_label.text = "No buildings constructed"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		buildings_container.add_child(empty_label)
		return

	for building in settlement.buildings:
		var building_row := HBoxContainer.new()
		buildings_container.add_child(building_row)

		var name_label := Label.new()
		name_label.text = building.display_name if "display_name" in building else building.building_id
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", COLOR_TEXT)
		building_row.add_child(name_label)

		if "income_bonus" in building and building.income_bonus > 0:
			var bonus := Label.new()
			bonus.text = " (+%d gold)" % building.income_bonus
			bonus.add_theme_font_size_override("font_size", 14)
			bonus.add_theme_color_override("font_color", COLOR_GOLD)
			building_row.add_child(bonus)


func _on_enter_pressed() -> void:
	if current_settlement:
		enter_settlement.emit(current_settlement)
	hide_panel()


func _on_attack_pressed() -> void:
	if current_settlement:
		attack_settlement.emit(current_settlement)
	hide_panel()


func _on_close_pressed() -> void:
	hide_panel()


func hide_panel() -> void:
	visible = false
	panel_closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_panel()
		get_viewport().set_input_as_handled()
