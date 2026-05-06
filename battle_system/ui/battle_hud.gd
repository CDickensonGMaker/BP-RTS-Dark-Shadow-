# Battle HUD - Total War style layout
# Top center: timer | Top right: minimap
# Bottom left: selected unit panel | Bottom center: unit cards | Bottom right: speed controls
class_name BattleHUD
extends CanvasLayer


const UnitCardScript = preload("res://battle_system/ui/unit_card.gd")

# UI Elements
var unit_card_container: HBoxContainer
var battle_timer_label: Label
var speed_label: Label
var minimap: BattleMinimap
var control_group_bar: ControlGroupBar
var selected_unit_panel: Panel
var selected_unit_portrait: TextureRect
var selected_unit_name: Label
var selected_unit_stats: VBoxContainer
var ability_container: HBoxContainer
var stance_container: HBoxContainer
var formation_container: HBoxContainer

# Deployment Phase UI (unified clickable box)
var deployment_panel: Button  # Single clickable button styled as panel
var start_battle_button: Button  # Alias for deployment_panel

var unit_cards: Dictionary = {}  # Regiment -> UnitCard
var current_selected_regiment: Regiment = null
var stance_buttons: Dictionary = {}  # StanceType.Type -> Button
var formation_buttons: Dictionary = {}  # FormationType.Type -> Button
var ability_buttons: Array[Button] = []
var ability_overlays: Array[Control] = []  # Cooldown overlay controls
var ability_types: Array = []  # Track which ability each button represents


# === ABILITY COOLDOWN OVERLAY ===
# Draws a radial sweep to show cooldown progress
class AbilityCooldownOverlay extends Control:
	var cooldown_ratio: float = 0.0  # 0 = ready, 1 = full cooldown
	var remaining_seconds: float = 0.0

	const COLOR_COOLDOWN = Color(0.0, 0.0, 0.0, 0.7)
	const COLOR_TEXT = Color(1.0, 1.0, 1.0, 0.9)

	func _init():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw():
		if cooldown_ratio <= 0.0:
			return

		var center = size / 2.0
		var radius = min(size.x, size.y) / 2.0

		# Draw radial sweep (pie slice showing cooldown)
		var start_angle = -PI / 2.0  # Start from top
		var end_angle = start_angle + (cooldown_ratio * TAU)

		# Draw filled arc for cooldown
		var points: PackedVector2Array = PackedVector2Array()
		points.append(center)

		var segments = int(32 * cooldown_ratio) + 4
		for i in range(segments + 1):
			var angle = start_angle + (float(i) / segments) * (end_angle - start_angle)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)

		if points.size() >= 3:
			draw_colored_polygon(points, COLOR_COOLDOWN)

		# Draw remaining seconds in center
		if remaining_seconds > 0.5:
			var font = ThemeDB.fallback_font
			var font_size = 11
			var text = "%.0f" % remaining_seconds
			var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos = center - text_size / 2.0 + Vector2(0, text_size.y * 0.35)
			draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_TEXT)

	func set_cooldown(ratio: float, seconds: float):
		cooldown_ratio = clampf(ratio, 0.0, 1.0)
		remaining_seconds = seconds
		queue_redraw()

# Colors matching dark fantasy theme
const COLOR_PANEL_BG = Color(0.08, 0.06, 0.05, 0.92)
const COLOR_PANEL_BORDER = Color(0.6, 0.5, 0.3, 1.0)
const COLOR_GOLD = Color(0.85, 0.7, 0.4, 1.0)
const COLOR_TEXT = Color(0.95, 0.92, 0.85, 1.0)
const COLOR_TEXT_DIM = Color(0.7, 0.65, 0.55, 1.0)


func _ready():
	_setup_ui()
	_connect_signals()
	call_deferred("_populate_unit_cards")


func _setup_ui():
	# === TOP LEFT - Control Group Bar ===
	_create_control_group_bar()

	# === TOP CENTER - Battle Timer ===
	_create_timer_display()

	# === TOP RIGHT - Minimap ===
	_create_minimap()

	# === TOP LEFT - Deployment Panel (visible during deployment phase) ===
	_create_deployment_panel()

	# === BOTTOM LEFT - Selected Unit Panel ===
	_create_selected_unit_panel()

	# === BOTTOM CENTER - Unit Cards ===
	_create_unit_card_bar()

	# === BOTTOM RIGHT - Speed Controls ===
	_create_speed_controls()


func _create_control_group_bar():
	control_group_bar = ControlGroupBar.new()
	control_group_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control_group_bar.offset_left = 10
	control_group_bar.offset_top = 60
	add_child(control_group_bar)


func _create_timer_display():
	var timer_container = Control.new()
	timer_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	timer_container.offset_left = -80
	timer_container.offset_right = 80
	timer_container.offset_top = 8
	timer_container.offset_bottom = 50
	add_child(timer_container)

	# Ornate frame background
	var frame = Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var frame_style = StyleBoxFlat.new()
	frame_style.bg_color = COLOR_PANEL_BG
	frame_style.border_color = COLOR_GOLD
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(6)
	frame_style.corner_radius_top_left = 12
	frame_style.corner_radius_top_right = 12
	frame.add_theme_stylebox_override("panel", frame_style)
	timer_container.add_child(frame)

	# Timer label
	battle_timer_label = Label.new()
	battle_timer_label.text = "12:00"
	battle_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	battle_timer_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	battle_timer_label.add_theme_font_size_override("font_size", 22)
	battle_timer_label.add_theme_color_override("font_color", COLOR_GOLD)
	timer_container.add_child(battle_timer_label)


func _create_minimap():
	var minimap_panel: Panel = Panel.new()
	minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap_panel.offset_left = -180
	minimap_panel.offset_right = -10
	minimap_panel.offset_top = 10
	minimap_panel.offset_bottom = 165

	var mini_style: StyleBoxFlat = StyleBoxFlat.new()
	mini_style.bg_color = Color(0.1, 0.08, 0.06, 0.95)
	mini_style.border_color = COLOR_PANEL_BORDER
	mini_style.set_border_width_all(2)
	minimap_panel.add_theme_stylebox_override("panel", mini_style)
	add_child(minimap_panel)

	# Use actual minimap component
	minimap = BattleMinimap.new()
	minimap.offset_left = 5
	minimap.offset_right = -5
	minimap.offset_top = 5
	minimap.offset_bottom = -5
	minimap_panel.add_child(minimap)


func _create_deployment_panel():
	# Unified clickable deployment box - click anywhere to start battle
	deployment_panel = Button.new()
	deployment_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	deployment_panel.offset_left = 10
	deployment_panel.offset_right = 290  # 280px width
	deployment_panel.offset_top = 10
	deployment_panel.offset_bottom = 70  # 60px height

	deployment_panel.text = "DEPLOYMENT PHASE\nCLICK TO START"
	deployment_panel.add_theme_font_size_override("font_size", 16)
	deployment_panel.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5, 1.0))

	# Style as panel-like button
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = COLOR_PANEL_BG
	btn_style.border_color = Color(0.3, 0.7, 0.4, 1.0)  # Green deployment color
	btn_style.set_border_width_all(3)
	btn_style.set_corner_radius_all(6)
	deployment_panel.add_theme_stylebox_override("normal", btn_style)

	var btn_hover = btn_style.duplicate()
	btn_hover.border_color = Color(0.4, 0.9, 0.5, 1.0)  # Brighter on hover
	btn_hover.bg_color = Color(0.1, 0.12, 0.08, 0.95)
	deployment_panel.add_theme_stylebox_override("hover", btn_hover)

	var btn_pressed = btn_style.duplicate()
	btn_pressed.bg_color = Color(0.06, 0.1, 0.06, 0.95)
	deployment_panel.add_theme_stylebox_override("pressed", btn_pressed)

	deployment_panel.pressed.connect(_on_start_battle_pressed)
	add_child(deployment_panel)

	# Alias for backward compatibility
	start_battle_button = deployment_panel


func _on_start_battle_pressed():
	if DeploymentManager:
		DeploymentManager.start_battle()
		deployment_panel.visible = false


func _create_selected_unit_panel():
	selected_unit_panel = Panel.new()
	selected_unit_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	selected_unit_panel.offset_left = 10
	selected_unit_panel.offset_right = 280
	selected_unit_panel.offset_top = -275
	selected_unit_panel.offset_bottom = -50
	selected_unit_panel.visible = false  # Hidden until unit selected

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	selected_unit_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(selected_unit_panel)

	# Portrait area (left side)
	var portrait_panel = Panel.new()
	portrait_panel.offset_left = 8
	portrait_panel.offset_top = 8
	portrait_panel.offset_right = 78
	portrait_panel.offset_bottom = 78
	var portrait_style = StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.15, 0.12, 0.1, 1.0)
	portrait_style.border_color = COLOR_GOLD
	portrait_style.set_border_width_all(2)
	portrait_panel.add_theme_stylebox_override("panel", portrait_style)
	selected_unit_panel.add_child(portrait_panel)

	selected_unit_portrait = TextureRect.new()
	selected_unit_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	selected_unit_portrait.offset_left = 2
	selected_unit_portrait.offset_top = 2
	selected_unit_portrait.offset_right = -2
	selected_unit_portrait.offset_bottom = -2
	selected_unit_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_panel.add_child(selected_unit_portrait)

	# Unit name
	selected_unit_name = Label.new()
	selected_unit_name.offset_left = 85
	selected_unit_name.offset_top = 8
	selected_unit_name.offset_right = 265
	selected_unit_name.offset_bottom = 30
	selected_unit_name.text = "Unit Name"
	selected_unit_name.add_theme_font_size_override("font_size", 16)
	selected_unit_name.add_theme_color_override("font_color", COLOR_GOLD)
	selected_unit_panel.add_child(selected_unit_name)

	# Stats container
	selected_unit_stats = VBoxContainer.new()
	selected_unit_stats.offset_left = 85
	selected_unit_stats.offset_top = 32
	selected_unit_stats.offset_right = 265
	selected_unit_stats.offset_bottom = 85
	selected_unit_stats.add_theme_constant_override("separation", 2)
	selected_unit_panel.add_child(selected_unit_stats)

	# Stance buttons
	var stance_label: Label = Label.new()
	stance_label.text = "Stance"
	stance_label.offset_left = 8
	stance_label.offset_top = 85
	stance_label.offset_right = 60
	stance_label.offset_bottom = 100
	stance_label.add_theme_font_size_override("font_size", 10)
	stance_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	selected_unit_panel.add_child(stance_label)

	stance_container = HBoxContainer.new()
	stance_container.offset_left = 8
	stance_container.offset_top = 100
	stance_container.offset_right = 265
	stance_container.offset_bottom = 125
	stance_container.add_theme_constant_override("separation", 3)
	selected_unit_panel.add_child(stance_container)
	_create_stance_buttons()

	# Formation buttons
	var formation_label: Label = Label.new()
	formation_label.text = "Formation"
	formation_label.offset_left = 8
	formation_label.offset_top = 128
	formation_label.offset_right = 80
	formation_label.offset_bottom = 143
	formation_label.add_theme_font_size_override("font_size", 10)
	formation_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	selected_unit_panel.add_child(formation_label)

	formation_container = HBoxContainer.new()
	formation_container.offset_left = 8
	formation_container.offset_top = 143
	formation_container.offset_right = 265
	formation_container.offset_bottom = 168
	formation_container.add_theme_constant_override("separation", 3)
	selected_unit_panel.add_child(formation_container)
	_create_formation_buttons()

	# Ability buttons
	var ability_label: Label = Label.new()
	ability_label.text = "Abilities (Q/E/R)"
	ability_label.offset_left = 8
	ability_label.offset_top = 171
	ability_label.offset_right = 120
	ability_label.offset_bottom = 186
	ability_label.add_theme_font_size_override("font_size", 10)
	ability_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	selected_unit_panel.add_child(ability_label)

	ability_container = HBoxContainer.new()
	ability_container.offset_left = 8
	ability_container.offset_top = 186
	ability_container.offset_right = 265
	ability_container.offset_bottom = 220
	ability_container.add_theme_constant_override("separation", 5)
	selected_unit_panel.add_child(ability_container)


func _create_unit_card_bar():
	var bottom_panel = Panel.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_left = 290  # Leave room for selected unit panel
	bottom_panel.offset_right = -200  # Leave room for speed controls
	bottom_panel.offset_top = -170
	bottom_panel.offset_bottom = -50

	var bottom_style = StyleBoxFlat.new()
	bottom_style.bg_color = COLOR_PANEL_BG
	bottom_style.border_color = COLOR_PANEL_BORDER
	bottom_style.set_border_width_all(2)
	bottom_style.set_corner_radius_all(4)
	bottom_panel.add_theme_stylebox_override("panel", bottom_style)
	add_child(bottom_panel)

	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 8
	scroll.offset_right = -8
	scroll.offset_top = 8
	scroll.offset_bottom = -8
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS  # Always show scrollbar for many units
	scroll.follow_focus = true  # Auto-scroll to selected unit
	bottom_panel.add_child(scroll)

	unit_card_container = HBoxContainer.new()
	unit_card_container.add_theme_constant_override("separation", 4)  # Smaller spacing for more units
	unit_card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(unit_card_container)


func _create_speed_controls():
	var speed_panel = Panel.new()
	speed_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	speed_panel.offset_left = -190
	speed_panel.offset_right = -10
	speed_panel.offset_top = -170
	speed_panel.offset_bottom = -50

	var speed_style = StyleBoxFlat.new()
	speed_style.bg_color = COLOR_PANEL_BG
	speed_style.border_color = COLOR_PANEL_BORDER
	speed_style.set_border_width_all(2)
	speed_style.set_corner_radius_all(4)
	speed_panel.add_theme_stylebox_override("panel", speed_style)
	add_child(speed_panel)

	# Speed label
	speed_label = Label.new()
	speed_label.text = "1.0x"
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	speed_label.offset_top = 10
	speed_label.offset_bottom = 35
	speed_label.offset_left = -40
	speed_label.offset_right = 40
	speed_label.add_theme_font_size_override("font_size", 18)
	speed_label.add_theme_color_override("font_color", COLOR_GOLD)
	speed_panel.add_child(speed_label)

	# Speed buttons
	var button_container = HBoxContainer.new()
	button_container.set_anchors_preset(Control.PRESET_CENTER)
	button_container.offset_top = 10
	button_container.offset_left = -75
	button_container.offset_right = 75
	button_container.add_theme_constant_override("separation", 10)
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_panel.add_child(button_container)

	var slow_btn = _create_speed_button("<<", 0.5)
	var pause_btn = _create_speed_button("||", 0.0)
	var normal_btn = _create_speed_button(">", 1.0)
	var fast_btn = _create_speed_button(">>", 2.0)

	button_container.add_child(slow_btn)
	button_container.add_child(pause_btn)
	button_container.add_child(normal_btn)
	button_container.add_child(fast_btn)


func _create_speed_button(text: String, speed: float) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(35, 35)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func(): _set_game_speed(speed))
	return btn


func _set_game_speed(speed: float):
	if speed == 0.0:
		Engine.time_scale = 0.001  # Near-pause
	else:
		Engine.time_scale = speed
	speed_label.text = "%.1fx" % speed


func _connect_signals():
	if BattleSignals:
		if not BattleSignals.regiment_selected.is_connected(_on_regiment_selected):
			BattleSignals.regiment_selected.connect(_on_regiment_selected)
		if not BattleSignals.regiment_dead.is_connected(_on_regiment_dead):
			BattleSignals.regiment_dead.connect(_on_regiment_dead)
		if not BattleSignals.deployment_ended.is_connected(_on_deployment_ended):
			BattleSignals.deployment_ended.connect(_on_deployment_ended)
		if not BattleSignals.battle_started.is_connected(_on_battle_started):
			BattleSignals.battle_started.connect(_on_battle_started)


func _on_deployment_ended():
	deployment_panel.visible = false


func _on_battle_started():
	deployment_panel.visible = false
	battle_timer_label.text = "00:00"


func _populate_unit_cards():
	for card in unit_cards.values():
		card.queue_free()
	unit_cards.clear()

	await get_tree().process_frame
	await get_tree().process_frame

	# Safety check after await in case scene changed
	if not is_instance_valid(self) or not is_instance_valid(unit_card_container):
		return

	var regiments = get_tree().get_nodes_in_group("player_regiments")
	for regiment in regiments:
		if regiment is Regiment:
			_add_unit_card(regiment)


func _add_unit_card(regiment: Regiment):
	var card = UnitCardScript.new()
	unit_card_container.add_child(card)
	card.setup(regiment)
	card.card_clicked.connect(_on_card_clicked)
	unit_cards[regiment] = card


func _remove_unit_card(regiment: Regiment):
	if regiment in unit_cards:
		unit_cards[regiment].queue_free()
		unit_cards.erase(regiment)


func _on_card_clicked(regiment: Regiment):
	if SelectionManager:
		SelectionManager.select_regiment(regiment)


func _on_regiment_selected(regiment: Regiment):
	current_selected_regiment = regiment
	_update_selected_unit_panel(regiment)

	for reg in unit_cards:
		unit_cards[reg].set_selected(reg == regiment)


func _update_selected_unit_panel(regiment: Regiment):
	if regiment == null:
		selected_unit_panel.visible = false
		return

	selected_unit_panel.visible = true
	selected_unit_name.text = regiment.data.regiment_name if regiment.data else "Unknown Unit"

	# Clear old stats
	for child in selected_unit_stats.get_children():
		child.queue_free()

	# Add stats
	if regiment.data:
		var type_name: String = UnitType.Type.keys()[regiment.data.unit_type].capitalize()
		_add_stat_line("Type:", type_name)
		_add_stat_line("Men:", "%d / %d" % [regiment.current_soldiers, regiment.data.max_soldiers])
		_add_stat_line("Morale:", "%d%%" % int(regiment.current_morale))
		if regiment.stamina:
			_add_stat_line("Stamina:", "%d%%" % int(regiment.stamina.get_ratio() * 100))
		if regiment.veterancy:
			_add_stat_line("Rank:", regiment.veterancy.get_level_name())
		# Add ammo display for ranged units
		if regiment.data.max_ammo > 0:
			var ammo_ratio: float = float(regiment.current_ammo) / float(regiment.data.max_ammo)
			var ammo_text: String = "%d / %d" % [regiment.current_ammo, regiment.data.max_ammo]
			var ammo_color: Color = COLOR_TEXT
			if regiment.current_ammo <= 0:
				ammo_text = "EMPTY"
				ammo_color = Color(1.0, 0.3, 0.3)  # Red
			elif ammo_ratio <= 0.25:
				ammo_color = Color(1.0, 0.7, 0.2)  # Orange/yellow warning
			_add_stat_line_colored("Ammo:", ammo_text, ammo_color)

	# Update stance and formation buttons
	_update_stance_buttons()
	_update_formation_buttons()

	# Update ability buttons
	_update_ability_buttons(regiment)


func _add_stat_line(label_text: String, value_text: String):
	var hbox: HBoxContainer = HBoxContainer.new()

	var label: Label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	label.custom_minimum_size.x = 50
	hbox.add_child(label)

	var value: Label = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", COLOR_TEXT)
	hbox.add_child(value)

	selected_unit_stats.add_child(hbox)


func _add_stat_line_colored(label_text: String, value_text: String, value_color: Color):
	## Add a stat line with custom color for the value (used for ammo warnings).
	var hbox: HBoxContainer = HBoxContainer.new()

	var label: Label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	label.custom_minimum_size.x = 50
	hbox.add_child(label)

	var value: Label = Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 11)
	value.add_theme_color_override("font_color", value_color)
	hbox.add_child(value)

	selected_unit_stats.add_child(hbox)


func _create_stance_buttons():
	var stances: Array = [
		StanceType.Type.AGGRESSIVE,
		StanceType.Type.DEFENSIVE,
		StanceType.Type.HOLD_GROUND,
		StanceType.Type.SKIRMISH,
	]

	for stance in stances:
		var btn: Button = Button.new()
		btn.text = StanceType.get_stance_name(stance).substr(0, 1)  # First letter
		btn.tooltip_text = "%s (%s)" % [StanceType.get_stance_name(stance), OS.get_keycode_string(StanceType.get_hotkey(stance))]
		btn.custom_minimum_size = Vector2(25, 22)
		btn.add_theme_font_size_override("font_size", 11)
		btn.pressed.connect(_on_stance_button_pressed.bind(stance))
		stance_container.add_child(btn)
		stance_buttons[stance] = btn


func _create_formation_buttons():
	var formations: Array = [
		FormationType.Type.LINE,
		FormationType.Type.COLUMN,
		FormationType.Type.WEDGE,
		FormationType.Type.SQUARE,
	]

	for formation in formations:
		var btn: Button = Button.new()
		btn.text = FormationType.get_formation_name(formation).substr(0, 3)  # First 3 letters
		btn.tooltip_text = "%s (F%d)" % [FormationType.get_formation_name(formation), formations.find(formation) + 1]
		btn.custom_minimum_size = Vector2(35, 22)
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(_on_formation_button_pressed.bind(formation))
		formation_container.add_child(btn)
		formation_buttons[formation] = btn


func _on_stance_button_pressed(stance: StanceType.Type):
	if current_selected_regiment and is_instance_valid(current_selected_regiment):
		current_selected_regiment.set_stance(stance)
		_update_stance_buttons()


func _on_formation_button_pressed(formation: FormationType.Type):
	if current_selected_regiment and is_instance_valid(current_selected_regiment):
		current_selected_regiment.set_formation(formation)
		_update_formation_buttons()


func _update_stance_buttons():
	if not current_selected_regiment:
		return

	var current: StanceType.Type = current_selected_regiment.current_stance
	for stance in stance_buttons:
		var btn: Button = stance_buttons[stance]
		btn.disabled = false
		if stance == current:
			btn.modulate = Color(0.5, 1.0, 0.5, 1.0)  # Highlight active
		else:
			btn.modulate = Color.WHITE


func _update_formation_buttons():
	if not current_selected_regiment:
		return

	var current: FormationType.Type = current_selected_regiment.current_formation
	var unit_type: UnitType.Type = current_selected_regiment.data.unit_type

	for formation in formation_buttons:
		var btn: Button = formation_buttons[formation]
		# Disable formations that this unit can't use
		btn.disabled = not FormationType.can_unit_use(formation, unit_type)
		if formation == current:
			btn.modulate = Color(0.5, 1.0, 0.5, 1.0)  # Highlight active
		else:
			btn.modulate = Color.WHITE


func _update_ability_buttons(regiment: Regiment):
	# Clear old abilities
	for child in ability_container.get_children():
		child.queue_free()
	ability_buttons.clear()
	ability_overlays.clear()
	ability_types.clear()

	if not regiment.abilities:
		return

	var hotkeys: Array[String] = ["Q", "E", "R", "T"]
	var idx: int = 0

	for ability in regiment.abilities.available_abilities:
		var data: Dictionary = AbilityType.get_ability_data(ability)

		# Create container to hold button and overlay
		var container: Control = Control.new()
		container.custom_minimum_size = Vector2(45, 30)

		var btn: Button = Button.new()
		btn.text = data.get("name", "?").substr(0, 3)
		btn.tooltip_text = "%s\n%s\nCooldown: %.0fs" % [
			data.get("name", "Unknown"),
			data.get("description", ""),
			data.get("cooldown", 0.0)
		]
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_theme_font_size_override("font_size", 10)

		# Show hotkey
		if idx < hotkeys.size():
			btn.text = "[%s] %s" % [hotkeys[idx], btn.text]

		# Check if on cooldown
		var cooldown_ratio: float = regiment.abilities.get_cooldown_ratio(ability)
		if not regiment.abilities.can_use(ability):
			btn.disabled = true
			if cooldown_ratio > 0:
				btn.tooltip_text += "\n(%.1fs remaining)" % (data.get("cooldown", 0.0) * cooldown_ratio)

		# Check if active - green glowing border
		if regiment.abilities.is_ability_active(ability):
			btn.modulate = Color(0.5, 1.0, 0.5, 1.0)

		btn.pressed.connect(_on_ability_button_pressed.bind(ability))
		container.add_child(btn)

		# Create cooldown overlay on top of button
		var overlay: AbilityCooldownOverlay = AbilityCooldownOverlay.new()
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.set_cooldown(cooldown_ratio, data.get("cooldown", 0.0) * cooldown_ratio)
		container.add_child(overlay)

		ability_container.add_child(container)
		ability_buttons.append(btn)
		ability_overlays.append(overlay)
		ability_types.append(ability)
		idx += 1


func _on_ability_button_pressed(ability: AbilityType.Type):
	if current_selected_regiment and is_instance_valid(current_selected_regiment):
		var data: Dictionary = AbilityType.get_ability_data(ability)
		if data.get("duration", 1.0) == 0.0:
			# Toggle ability
			current_selected_regiment.toggle_ability(ability)
		else:
			# Instant or duration ability
			current_selected_regiment.use_ability(ability)


func _on_regiment_dead(regiment: Regiment):
	_remove_unit_card(regiment)
	if current_selected_regiment == regiment:
		selected_unit_panel.visible = false
		current_selected_regiment = null


func _process(_delta):
	# Check deployment phase
	var is_deployment = DeploymentManager and DeploymentManager.is_deployment_phase()

	# Update battle timer
	if is_deployment:
		battle_timer_label.text = "DEPLOY"
	elif BattleManager and BattleManager.is_battle_active:
		var elapsed = Time.get_unix_time_from_system() - BattleManager.battle_start_time
		var minutes = int(elapsed) / 60
		var seconds = int(elapsed) % 60
		battle_timer_label.text = "%02d:%02d" % [minutes, seconds]

	# Update speed label
	var current_speed = Engine.time_scale
	if current_speed < 0.01:
		speed_label.text = "PAUSED"
	else:
		speed_label.text = "%.1fx" % current_speed

	# Update selected unit stats if visible
	if selected_unit_panel.visible and current_selected_regiment:
		_update_selected_unit_panel(current_selected_regiment)
		_update_ability_cooldowns()


func _update_ability_cooldowns():
	## Update cooldown overlays for ability buttons.
	if not current_selected_regiment or not current_selected_regiment.abilities:
		return

	for i in range(ability_overlays.size()):
		if i >= ability_types.size():
			break

		var overlay: AbilityCooldownOverlay = ability_overlays[i]
		var ability = ability_types[i]
		var data: Dictionary = AbilityType.get_ability_data(ability)

		var ratio: float = current_selected_regiment.abilities.get_cooldown_ratio(ability)
		var total_cooldown: float = data.get("cooldown", 0.0)
		var remaining: float = total_cooldown * ratio

		overlay.set_cooldown(ratio, remaining)

		# Update button disabled state based on cooldown
		if i < ability_buttons.size():
			var btn: Button = ability_buttons[i]
			btn.disabled = not current_selected_regiment.abilities.can_use(ability)

			# Active abilities get green glow
			if current_selected_regiment.abilities.is_ability_active(ability):
				btn.modulate = Color(0.5, 1.0, 0.5, 1.0)
			else:
				btn.modulate = Color.WHITE
