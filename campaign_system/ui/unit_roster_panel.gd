# Panel displaying the army's unit roster with clickable cards.
# Supports right-click for detailed inspection.
class_name UnitRosterPanel
extends Control


signal unit_clicked(regiment: Resource)
signal unit_right_clicked(regiment: Resource, position: Vector2)


# UI styling
const CARD_SIZE := Vector2(100, 130)
const CARD_SPACING := 8
const BG_COLOR := Color(0.1, 0.08, 0.06, 0.9)
const BORDER_COLOR := Color(0.6, 0.5, 0.3, 1.0)
const SELECTED_COLOR := Color(0.8, 0.7, 0.4, 1.0)

var regiments: Array = []
var selected_index: int = -1
var card_container: HBoxContainer = null
var scroll_container: ScrollContainer = null


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# Header
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	var header := Label.new()
	header.text = "YOUR ARMY ROSTER"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	vbox.add_child(header)

	var hint := Label.new()
	hint.text = "Right-click any unit for detailed stats"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)

	# Scrollable container for cards
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll_container)

	card_container = HBoxContainer.new()
	card_container.add_theme_constant_override("separation", CARD_SPACING)
	scroll_container.add_child(card_container)


func display_roster(regiment_list: Array) -> void:
	regiments = regiment_list
	_rebuild_cards()


func _rebuild_cards() -> void:
	# Clear existing cards
	for child in card_container.get_children():
		child.queue_free()

	# Create new cards
	for i in range(regiments.size()):
		var card := _create_unit_card(regiments[i], i)
		card_container.add_child(card)


func _create_unit_card(regiment: Resource, index: int) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE

	# Style
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", style)

	# Content
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Unit name
	var name_label := Label.new()
	var unit_name: String = regiment.regiment_name if regiment.get("regiment_name") else regiment.get_meta("regiment_name", "Unknown")
	name_label.text = _truncate(unit_name, 12)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(name_label)

	# Unit type icon/category
	var type_label := Label.new()
	var category: String = regiment.get_meta("unit_category", "infantry")
	type_label.text = "[%s]" % category.substr(0, 3).to_upper()
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_color_override("font_color", _get_category_color(category))
	type_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(type_label)

	# Strength bar
	var strength_container := VBoxContainer.new()
	vbox.add_child(strength_container)

	var current: int = regiment.current_soldiers if regiment.get("current_soldiers") else regiment.get_meta("current_soldiers", 60)
	var max_soldiers: int = regiment.max_soldiers if regiment.get("max_soldiers") else regiment.get_meta("max_soldiers", 60)

	var strength_bar := ProgressBar.new()
	strength_bar.min_value = 0
	strength_bar.max_value = max_soldiers
	strength_bar.value = current
	strength_bar.show_percentage = false
	strength_bar.custom_minimum_size = Vector2(0, 8)
	strength_container.add_child(strength_bar)

	var strength_label := Label.new()
	strength_label.text = "%d/%d" % [current, max_soldiers]
	strength_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strength_label.add_theme_font_size_override("font_size", 10)
	strength_container.add_child(strength_label)

	# Veterancy indicator
	var vet_level: int = regiment.get_meta("veterancy_level", 0)
	if vet_level > 0:
		var vet_label := Label.new()
		vet_label.text = "*".repeat(vet_level)
		vet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vet_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
		vbox.add_child(vet_label)

	# Equipment indicators
	var armor_bonus: int = regiment.get_meta("armor_bonus", 0)
	var attack_bonus: int = regiment.get_meta("attack_bonus", 0)
	if armor_bonus > 0 or attack_bonus > 0:
		var equip_label := Label.new()
		var parts := []
		if armor_bonus > 0:
			parts.append("+%dA" % armor_bonus)
		if attack_bonus > 0:
			parts.append("+%dW" % attack_bonus)
		equip_label.text = " ".join(parts)
		equip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		equip_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4))
		equip_label.add_theme_font_size_override("font_size", 10)
		vbox.add_child(equip_label)

	# Make interactive
	card.gui_input.connect(_on_card_input.bind(index))
	card.mouse_entered.connect(_on_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_card_hover.bind(card, false))

	return card


func _truncate(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 2) + ".."


func _get_category_color(category: String) -> Color:
	match category.to_lower():
		"infantry":
			return Color(0.6, 0.6, 0.8)
		"ranged":
			return Color(0.6, 0.8, 0.6)
		"cavalry":
			return Color(0.8, 0.6, 0.6)
		"monster", "special":
			return Color(0.8, 0.6, 0.8)
		_:
			return Color(0.7, 0.7, 0.7)


func _on_card_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_select_card(index)
			unit_clicked.emit(regiments[index])
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			unit_right_clicked.emit(regiments[index], get_global_mouse_position())


func _on_card_hover(card: Control, hovering: bool) -> void:
	var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate()
	if hovering:
		style.border_color = SELECTED_COLOR
	else:
		style.border_color = BORDER_COLOR
	card.add_theme_stylebox_override("panel", style)


func _select_card(index: int) -> void:
	selected_index = index
	# Visual feedback handled by hover for now


func get_selected_regiment() -> Resource:
	if selected_index >= 0 and selected_index < regiments.size():
		return regiments[selected_index]
	return null
