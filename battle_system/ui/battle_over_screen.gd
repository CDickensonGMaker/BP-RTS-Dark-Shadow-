# Battle Over Screen - Shows victory/defeat summary after battle ends
# Displays casualties, kills/losses per unit, and battle duration
class_name BattleOverScreen
extends CanvasLayer


# Colors matching BattleHUD dark fantasy theme
const COLOR_PANEL_BG = Color(0.08, 0.06, 0.05, 0.96)
const COLOR_PANEL_BORDER = Color(0.6, 0.5, 0.3, 1.0)
const COLOR_GOLD = Color(0.85, 0.7, 0.4, 1.0)
const COLOR_TEXT = Color(0.95, 0.92, 0.85, 1.0)
const COLOR_TEXT_DIM = Color(0.7, 0.65, 0.55, 1.0)
const COLOR_VICTORY = Color(0.95, 0.85, 0.3, 1.0)  # Bright gold
const COLOR_DEFEAT = Color(0.9, 0.25, 0.2, 1.0)    # Blood red

# UI Elements
var main_panel: PanelContainer
var title_label: Label
var subtitle_label: Label
var duration_label: Label
var player_forces_panel: PanelContainer
var enemy_forces_panel: PanelContainer
var continue_button: Button

# Cached result data
var battle_result: Dictionary = {}


func _ready() -> void:
	# Must process while paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100  # Render on top of everything

	_setup_ui()
	_connect_signals()

	# Start hidden
	visible = false


func _connect_signals() -> void:
	if BattleSignals:
		BattleSignals.battle_ended.connect(_on_battle_ended)


func _on_battle_ended(result: Dictionary) -> void:
	battle_result = result
	_populate_data(result)
	_show()


func _show() -> void:
	visible = true
	get_tree().paused = true


func _hide() -> void:
	visible = false
	get_tree().paused = false


func _setup_ui() -> void:
	# === FULL SCREEN DARKENER ===
	var darkener := ColorRect.new()
	darkener.set_anchors_preset(Control.PRESET_FULL_RECT)
	darkener.color = Color(0.0, 0.0, 0.0, 0.6)
	darkener.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks
	add_child(darkener)

	# === MAIN PANEL (centered) ===
	main_panel = PanelContainer.new()
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.offset_left = -380
	main_panel.offset_right = 380
	main_panel.offset_top = -280
	main_panel.offset_bottom = 280

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_GOLD
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	panel_style.shadow_size = 10
	main_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(main_panel)

	# === CONTENT VBOX ===
	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 15)
	main_panel.add_child(content_vbox)

	# Padding margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	content_vbox.add_child(margin)

	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(inner_vbox)

	# === TITLE ===
	title_label = Label.new()
	title_label.text = "VICTORY"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 42)
	title_label.add_theme_color_override("font_color", COLOR_VICTORY)
	inner_vbox.add_child(title_label)

	# === SUBTITLE ===
	subtitle_label = Label.new()
	subtitle_label.text = "The enemy has been vanquished!"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 16)
	subtitle_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	inner_vbox.add_child(subtitle_label)

	# === SEPARATOR ===
	var sep1 := HSeparator.new()
	sep1.add_theme_stylebox_override("separator", _create_separator_style())
	inner_vbox.add_child(sep1)

	# === DURATION ===
	duration_label = Label.new()
	duration_label.text = "Battle Duration: 0:00"
	duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	duration_label.add_theme_font_size_override("font_size", 18)
	duration_label.add_theme_color_override("font_color", COLOR_GOLD)
	inner_vbox.add_child(duration_label)

	# === FORCES COLUMNS ===
	var forces_hbox := HBoxContainer.new()
	forces_hbox.add_theme_constant_override("separation", 20)
	forces_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	inner_vbox.add_child(forces_hbox)

	# Player forces column
	player_forces_panel = _create_forces_panel("YOUR FORCES", true)
	forces_hbox.add_child(player_forces_panel)

	# Enemy forces column
	enemy_forces_panel = _create_forces_panel("ENEMY FORCES", false)
	forces_hbox.add_child(enemy_forces_panel)

	# === CONTINUE BUTTON ===
	var button_container := CenterContainer.new()
	inner_vbox.add_child(button_container)

	continue_button = Button.new()
	continue_button.text = "  Continue  "
	continue_button.custom_minimum_size = Vector2(180, 45)
	continue_button.add_theme_font_size_override("font_size", 18)

	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.15, 0.12, 0.1, 1.0)
	btn_normal.border_color = COLOR_GOLD
	btn_normal.set_border_width_all(2)
	btn_normal.set_corner_radius_all(6)
	continue_button.add_theme_stylebox_override("normal", btn_normal)

	var btn_hover := btn_normal.duplicate()
	btn_hover.bg_color = Color(0.25, 0.2, 0.15, 1.0)
	btn_hover.border_color = COLOR_VICTORY
	continue_button.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed := btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.1, 0.08, 0.06, 1.0)
	continue_button.add_theme_stylebox_override("pressed", btn_pressed)

	continue_button.add_theme_color_override("font_color", COLOR_GOLD)
	continue_button.add_theme_color_override("font_hover_color", COLOR_VICTORY)
	continue_button.pressed.connect(_on_continue_pressed)
	button_container.add_child(continue_button)


func _create_separator_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BORDER
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _create_forces_panel(header_text: String, is_player: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 280)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.04, 0.8)
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.name = "MarginContainer"
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.name = "ForceContent"  # For later lookup
	margin.add_child(vbox)

	# Header
	var header := Label.new()
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", COLOR_GOLD)
	vbox.add_child(header)

	# Remaining count placeholder
	var remaining := Label.new()
	remaining.name = "RemainingLabel"
	remaining.text = "Remaining: 0 / 0"
	remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	remaining.add_theme_font_size_override("font_size", 14)
	remaining.add_theme_color_override("font_color", COLOR_TEXT)
	vbox.add_child(remaining)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", _create_separator_style())
	vbox.add_child(sep)

	# Table header
	var table_header := _create_table_row("Unit", "K", "L", true)
	vbox.add_child(table_header)

	# Scroll container for unit rows
	var scroll := ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var unit_list := VBoxContainer.new()
	unit_list.name = "UnitList"
	unit_list.add_theme_constant_override("separation", 4)
	scroll.add_child(unit_list)

	return panel


func _create_table_row(unit_name: String, kills: String, losses: String, is_header: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var font_size := 13 if is_header else 12
	var font_color := COLOR_GOLD if is_header else COLOR_TEXT

	# Unit name (flexible width)
	var name_label := Label.new()
	name_label.text = unit_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", font_size)
	name_label.add_theme_color_override("font_color", font_color)
	name_label.clip_text = true
	row.add_child(name_label)

	# Kills column
	var kills_label := Label.new()
	kills_label.text = kills
	kills_label.custom_minimum_size = Vector2(35, 0)
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_font_size_override("font_size", font_size)
	kills_label.add_theme_color_override("font_color", font_color)
	row.add_child(kills_label)

	# Losses column
	var losses_label := Label.new()
	losses_label.text = losses
	losses_label.custom_minimum_size = Vector2(35, 0)
	losses_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	losses_label.add_theme_font_size_override("font_size", font_size)
	losses_label.add_theme_color_override("font_color", font_color)
	row.add_child(losses_label)

	return row


func _populate_data(result: Dictionary) -> void:
	# Handle both formats: "player_victory" (bool) or "winner" (String)
	var is_victory: bool
	if result.has("player_victory"):
		is_victory = result.get("player_victory", false)
	else:
		is_victory = result.get("winner", "") == "player"

	var casualties: Dictionary = result.get("casualties", {})
	var duration: float = result.get("duration", 0.0)

	# Title and subtitle
	if is_victory:
		title_label.text = "VICTORY"
		title_label.add_theme_color_override("font_color", COLOR_VICTORY)
		subtitle_label.text = "The enemy has been vanquished!"
	else:
		title_label.text = "DEFEAT"
		title_label.add_theme_color_override("font_color", COLOR_DEFEAT)
		subtitle_label.text = "Your forces have been routed..."

	# Duration
	var minutes := int(duration) / 60
	var seconds := int(duration) % 60
	duration_label.text = "Battle Duration: %d:%02d" % [minutes, seconds]

	# Player forces
	var player_stats: Dictionary = casualties.get("player_unit_stats", {})
	var player_remaining := _calculate_remaining(player_stats)
	var player_starting := _calculate_starting(player_stats)
	_populate_forces_panel(player_forces_panel, player_stats, player_remaining, player_starting)

	# Enemy forces
	var enemy_stats: Dictionary = casualties.get("enemy_unit_stats", {})
	var enemy_remaining := _calculate_remaining(enemy_stats)
	var enemy_starting := _calculate_starting(enemy_stats)
	_populate_forces_panel(enemy_forces_panel, enemy_stats, enemy_remaining, enemy_starting)


func _calculate_remaining(unit_stats: Dictionary) -> int:
	var total := 0
	for unit_name in unit_stats:
		var stats: Dictionary = unit_stats[unit_name]
		var starting: int = stats.get("starting", 0)
		var losses: int = stats.get("losses", 0)
		total += maxi(0, starting - losses)
	return total


func _calculate_starting(unit_stats: Dictionary) -> int:
	var total := 0
	for unit_name in unit_stats:
		var stats: Dictionary = unit_stats[unit_name]
		total += stats.get("starting", 0)
	return total


func _populate_forces_panel(panel: PanelContainer, unit_stats: Dictionary, remaining: int, starting: int) -> void:
	# Find the content nodes
	var content: VBoxContainer = panel.get_node("MarginContainer/ForceContent")
	if not content:
		return

	# Update remaining label
	var remaining_label: Label = content.get_node("RemainingLabel")
	if remaining_label:
		remaining_label.text = "Remaining: %d / %d" % [remaining, starting]

	# Clear and populate unit list
	var unit_list: VBoxContainer = content.get_node("ScrollContainer/UnitList")
	if not unit_list:
		return

	for child in unit_list.get_children():
		child.queue_free()

	# Add rows sorted by display name
	var sorted_units := unit_stats.keys()
	sorted_units.sort_custom(func(a, b):
		var name_a: String = unit_stats[a].get("display_name", a)
		var name_b: String = unit_stats[b].get("display_name", b)
		return name_a < name_b
	)

	for unit_name in sorted_units:
		var stats: Dictionary = unit_stats[unit_name]
		var display_name: String = stats.get("display_name", unit_name)
		var kills: int = stats.get("kills", 0)
		var losses: int = stats.get("losses", 0)

		var row := _create_table_row(display_name, str(kills), str(losses), false)

		# Color losses red if high
		if losses > 0:
			var starting_count: int = stats.get("starting", 1)
			var loss_ratio: float = float(losses) / float(starting_count)
			if loss_ratio >= 0.5:
				var losses_label: Label = row.get_child(2)
				losses_label.add_theme_color_override("font_color", COLOR_DEFEAT)

		unit_list.add_child(row)

	# If no units, show placeholder
	if sorted_units.is_empty():
		var placeholder := Label.new()
		placeholder.text = "No units"
		placeholder.add_theme_font_size_override("font_size", 12)
		placeholder.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unit_list.add_child(placeholder)


func _on_continue_pressed() -> void:
	_hide()
