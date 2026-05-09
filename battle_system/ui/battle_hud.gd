# Battle HUD - Total War style layout
# Top center: timer | Top right: minimap
# Bottom left: selected unit panel | Bottom center: unit cards | Bottom right: speed controls
class_name BattleHUD
extends CanvasLayer


const UnitCardScript = preload("res://battle_system/ui/unit_card.gd")
const BattleCompassScript = preload("res://battle_system/ui/battle_compass.gd")

# UI Elements
var unit_card_container: HBoxContainer
var battle_timer_label: Label
var speed_label: Label
var minimap: BattleMinimap
var compass: Control  # BattleCompass
var control_group_bar: ControlGroupBar
var tide_bar_container: Control
var tide_bar_fill: ColorRect
var tide_bar_marker: ColorRect
var pause_label: Label  # QOL Phase 2 - PAUSED overlay
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

# QOL Phase 5: Hover preview
var hover_preview_panel: Panel = null
var hover_preview_name: Label = null
var hover_preview_stats: Label = null
var _hovered_regiment: Regiment = null

# Phase 6.6: Trait Status Panel
var trait_panel: Panel = null
var trait_panel_header: Button = null
var trait_panel_content: VBoxContainer = null
var _trait_panel_expanded: bool = false

# QOL Phase 8: After-action report
var after_action_panel: Panel = null
var after_action_content: VBoxContainer = null


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

# Button styling colors
const COLOR_BTN_BG = Color(0.12, 0.11, 0.10, 0.95)
const COLOR_BTN_HOVER = Color(0.18, 0.16, 0.14, 0.95)
const COLOR_BTN_PRESSED = Color(0.08, 0.07, 0.06, 0.95)
const COLOR_BTN_ACTIVE = Color(0.15, 0.25, 0.15, 0.95)  # Green tint for active


## Apply consistent dark theme styling to HUD buttons
func _apply_hud_button_style(btn: Button) -> void:
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = COLOR_BTN_BG
	normal_style.border_color = COLOR_PANEL_BORDER
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = COLOR_BTN_HOVER
	hover_style.border_color = COLOR_GOLD
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = COLOR_BTN_PRESSED
	pressed_style.border_color = COLOR_GOLD
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style = normal_style.duplicate()
	disabled_style.bg_color = Color(0.08, 0.08, 0.08, 0.6)
	disabled_style.border_color = Color(0.3, 0.3, 0.3, 0.6)
	btn.add_theme_stylebox_override("disabled", disabled_style)

	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_GOLD)
	btn.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_DIM)


func _ready():
	_setup_ui()
	_connect_signals()
	# Delay card population to ensure regiments are spawned (battle_scene waits 0.6s)
	get_tree().create_timer(0.8).timeout.connect(_populate_unit_cards)


func _setup_ui():
	# === TOP LEFT - Control Group Bar ===
	_create_control_group_bar()

	# === TOP CENTER - Battle Timer ===
	_create_timer_display()

	# === BELOW TIMER - Battle Tide Bar ===
	_create_tide_bar()

	# === PAUSED OVERLAY (QOL Phase 2) ===
	_create_pause_overlay()

	# === TOP RIGHT - Minimap ===
	_create_minimap()

	# === BELOW MINIMAP - Compass ===
	_create_compass()

	# === TOP LEFT - Deployment Panel (visible during deployment phase) ===
	_create_deployment_panel()

	# === BOTTOM LEFT - Selected Unit Panel ===
	_create_selected_unit_panel()

	# === BOTTOM HUD (Phase 1: Unified container) ===
	# Creates selected_unit_panel + unit cards + speed controls in one HBoxContainer
	_create_bottom_hud()

	# Legacy calls (now no-ops, content in _create_bottom_hud)
	_create_unit_card_bar()
	_create_speed_controls()

	# === HOVER PREVIEW (QOL Phase 5) ===
	_create_hover_preview()

	# === TRAIT STATUS PANEL (Phase 6.6) ===
	_create_trait_panel()


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


func _create_tide_bar():
	# Battle Tide indicator - horizontal bar showing momentum
	# Center = even, left = enemy winning, right = player winning
	tide_bar_container = Control.new()
	tide_bar_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tide_bar_container.offset_left = -100
	tide_bar_container.offset_right = 100
	tide_bar_container.offset_top = 54  # Below timer
	tide_bar_container.offset_bottom = 66
	tide_bar_container.tooltip_text = "Battle Tide: Even"
	add_child(tide_bar_container)

	# Background bar
	var bg = Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_style.border_color = COLOR_PANEL_BORDER
	bg_style.set_border_width_all(1)
	bg_style.set_corner_radius_all(4)
	bg.add_theme_stylebox_override("panel", bg_style)
	tide_bar_container.add_child(bg)

	# Fill bar (slides left/right)
	tide_bar_fill = ColorRect.new()
	tide_bar_fill.size = Vector2(0, 8)
	tide_bar_fill.position = Vector2(100, 2)  # Start at center
	tide_bar_fill.color = Color(0.3, 0.7, 0.4, 0.9)  # Green for player
	tide_bar_container.add_child(tide_bar_fill)

	# Center marker (neutral point)
	tide_bar_marker = ColorRect.new()
	tide_bar_marker.size = Vector2(2, 12)
	tide_bar_marker.position = Vector2(99, 0)  # Center of 200px bar
	tide_bar_marker.color = Color(1.0, 1.0, 1.0, 0.6)
	tide_bar_container.add_child(tide_bar_marker)

	# Connect to BattleTide signal if available
	if has_node("/root/BattleTide"):
		var battle_tide = get_node("/root/BattleTide")
		if battle_tide.has_signal("tide_changed"):
			battle_tide.tide_changed.connect(_on_tide_changed)


func _create_pause_overlay():
	# QOL Phase 2 - PAUSED text overlay
	pause_label = Label.new()
	pause_label.text = "⏸ PAUSED"
	pause_label.add_theme_font_size_override("font_size", 32)
	pause_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	pause_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	pause_label.offset_top = 75
	pause_label.offset_left = -80
	pause_label.offset_right = 80
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.process_mode = Node.PROCESS_MODE_ALWAYS  # Visible while paused
	pause_label.visible = false
	add_child(pause_label)

	# Connect to pause signal
	if BattleSignals:
		BattleSignals.battle_paused.connect(_on_battle_paused)


func _on_battle_paused(is_paused: bool):
	if pause_label:
		pause_label.visible = is_paused


func _create_minimap():
	var minimap_panel: Panel = Panel.new()
	minimap_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap_panel.offset_left = -200  # Wider for better visibility
	minimap_panel.offset_right = -10
	minimap_panel.offset_top = 10
	minimap_panel.offset_bottom = 180  # Taller for better visibility

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


func _create_compass():
	# Compass showing direction system: N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7
	var compass_container: Panel = Panel.new()
	compass_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	compass_container.offset_left = -100  # 90px wide
	compass_container.offset_right = -10
	compass_container.offset_top = 185  # Below minimap (which ends at ~180)
	compass_container.offset_bottom = 280  # 95px tall

	var compass_style: StyleBoxFlat = StyleBoxFlat.new()
	compass_style.bg_color = Color(0.1, 0.08, 0.06, 0.95)
	compass_style.border_color = COLOR_PANEL_BORDER
	compass_style.set_border_width_all(2)
	compass_container.add_theme_stylebox_override("panel", compass_style)
	add_child(compass_container)

	# Compass widget
	compass = BattleCompassScript.new()
	compass.set_anchors_preset(Control.PRESET_CENTER)
	compass.offset_left = -40
	compass.offset_right = 40
	compass.offset_top = -40
	compass.offset_bottom = 40
	compass_container.add_child(compass)


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
	# Phase 2: Info-only panel (commands moved to command bar)
	selected_unit_panel = Panel.new()
	selected_unit_panel.custom_minimum_size = Vector2(200, 0)  # Slimmer, info only
	selected_unit_panel.visible = false  # Hidden until unit selected

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	selected_unit_panel.add_theme_stylebox_override("panel", panel_style)

	# Main margin container
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	selected_unit_panel.add_child(margin)

	# Main vertical layout
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(main_vbox)

	# === HEADER ROW: Portrait + Name/Stats ===
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(header_hbox)

	# Portrait panel (fixed size)
	var portrait_panel = Panel.new()
	portrait_panel.custom_minimum_size = Vector2(70, 70)
	var portrait_style = StyleBoxFlat.new()
	portrait_style.bg_color = Color(0.15, 0.12, 0.1, 1.0)
	portrait_style.border_color = COLOR_GOLD
	portrait_style.set_border_width_all(2)
	portrait_panel.add_theme_stylebox_override("panel", portrait_style)
	header_hbox.add_child(portrait_panel)

	selected_unit_portrait = TextureRect.new()
	selected_unit_portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	selected_unit_portrait.offset_left = 2
	selected_unit_portrait.offset_top = 2
	selected_unit_portrait.offset_right = -2
	selected_unit_portrait.offset_bottom = -2
	selected_unit_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_panel.add_child(selected_unit_portrait)

	# Stats column (expands to fill)
	var stats_vbox = VBoxContainer.new()
	stats_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_vbox.add_theme_constant_override("separation", 2)
	header_hbox.add_child(stats_vbox)

	# Unit name
	selected_unit_name = Label.new()
	selected_unit_name.text = "Unit Name"
	selected_unit_name.add_theme_font_size_override("font_size", 16)
	selected_unit_name.add_theme_color_override("font_color", COLOR_GOLD)
	stats_vbox.add_child(selected_unit_name)

	# Stats container (dynamic stat lines)
	selected_unit_stats = VBoxContainer.new()
	selected_unit_stats.add_theme_constant_override("separation", 2)
	selected_unit_stats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_vbox.add_child(selected_unit_stats)

	# Phase 2: Stance/Formation/Ability buttons moved to command bar
	# This panel is now purely informational


func _create_unit_card_bar():
	# Phase 1: This now creates just the card panel content, added to unified bottom HUD
	pass  # Content moved to _create_bottom_hud()


func _create_bottom_hud():
	# Phase 2: Unified bottom HUD with command bar
	var bottom_hud = HBoxContainer.new()
	bottom_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_hud.offset_left = 10
	bottom_hud.offset_right = -10
	bottom_hud.offset_top = -180  # Taller for command bar
	bottom_hud.offset_bottom = -10
	bottom_hud.add_theme_constant_override("separation", 8)
	add_child(bottom_hud)

	# === LEFT: Selected Unit Panel (fixed width, info only) ===
	bottom_hud.add_child(selected_unit_panel)

	# === CENTER: Command Bar + Unit Cards (expands to fill) ===
	var center_panel = Panel.new()
	center_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_panel.custom_minimum_size = Vector2(200, 0)

	var center_style = StyleBoxFlat.new()
	center_style.bg_color = COLOR_PANEL_BG
	center_style.border_color = COLOR_PANEL_BORDER
	center_style.set_border_width_all(2)
	center_style.set_corner_radius_all(4)
	center_panel.add_theme_stylebox_override("panel", center_style)
	bottom_hud.add_child(center_panel)

	# VBox for [command bar | unit cards]
	var center_vbox = VBoxContainer.new()
	center_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	center_vbox.offset_left = 4
	center_vbox.offset_right = -4
	center_vbox.offset_top = 4
	center_vbox.offset_bottom = -4
	center_vbox.add_theme_constant_override("separation", 4)
	center_panel.add_child(center_vbox)

	# === COMMAND BAR (Phase 2) ===
	_create_command_bar(center_vbox)

	# === UNIT CARDS SCROLL ===
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.follow_focus = true
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	center_vbox.add_child(scroll)

	unit_card_container = HBoxContainer.new()
	unit_card_container.add_theme_constant_override("separation", 4)
	unit_card_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unit_card_container.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(unit_card_container)

	# === RIGHT: Speed Controls (fixed width) ===
	var speed_panel = Panel.new()
	speed_panel.custom_minimum_size = Vector2(140, 0)  # Slimmer

	var speed_style = StyleBoxFlat.new()
	speed_style.bg_color = COLOR_PANEL_BG
	speed_style.border_color = COLOR_PANEL_BORDER
	speed_style.set_border_width_all(2)
	speed_style.set_corner_radius_all(4)
	speed_panel.add_theme_stylebox_override("panel", speed_style)
	bottom_hud.add_child(speed_panel)

	# Speed panel content
	var speed_vbox = VBoxContainer.new()
	speed_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_vbox.offset_left = 8
	speed_vbox.offset_right = -8
	speed_vbox.offset_top = 8
	speed_vbox.offset_bottom = -8
	speed_vbox.add_theme_constant_override("separation", 8)
	speed_panel.add_child(speed_vbox)

	# Speed label
	speed_label = Label.new()
	speed_label.text = "1.0x"
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_label.add_theme_font_size_override("font_size", 18)
	speed_label.add_theme_color_override("font_color", COLOR_GOLD)
	speed_vbox.add_child(speed_label)

	# Speed buttons
	var button_container = HBoxContainer.new()
	button_container.add_theme_constant_override("separation", 4)
	button_container.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_vbox.add_child(button_container)

	var slow_btn = _create_speed_button("<<", 0.5)
	var pause_btn = _create_speed_button("||", 0.0)
	var normal_btn = _create_speed_button(">", 1.0)
	var fast_btn = _create_speed_button(">>", 2.0)

	button_container.add_child(slow_btn)
	button_container.add_child(pause_btn)
	button_container.add_child(normal_btn)
	button_container.add_child(fast_btn)


# Phase 2: Command bar with unified controls
var command_bar: HBoxContainer

func _create_command_bar(parent: Control):
	command_bar = HBoxContainer.new()
	command_bar.custom_minimum_size = Vector2(0, 40)
	command_bar.add_theme_constant_override("separation", 8)
	parent.add_child(command_bar)

	# === ORDERS SECTION ===
	var orders_section = HBoxContainer.new()
	orders_section.add_theme_constant_override("separation", 4)
	command_bar.add_child(orders_section)

	# Halt button
	var halt_btn = _create_command_button("H", "Halt [H]", func(): _issue_halt_command())
	orders_section.add_child(halt_btn)

	# Run toggle button
	var run_btn = _create_command_button("R", "Run/Walk [R]", func(): _toggle_run_command())
	orders_section.add_child(run_btn)

	# Divider
	command_bar.add_child(_create_divider())

	# === STANCE SECTION ===
	stance_container = HBoxContainer.new()
	stance_container.add_theme_constant_override("separation", 3)
	command_bar.add_child(stance_container)
	_create_stance_buttons()

	# Divider
	command_bar.add_child(_create_divider())

	# === FORMATION SECTION ===
	formation_container = HBoxContainer.new()
	formation_container.add_theme_constant_override("separation", 3)
	command_bar.add_child(formation_container)
	_create_formation_buttons()

	# Divider
	command_bar.add_child(_create_divider())

	# === ABILITIES SECTION ===
	ability_container = HBoxContainer.new()
	ability_container.add_theme_constant_override("separation", 4)
	command_bar.add_child(ability_container)
	# Abilities populated dynamically based on selection


func _create_divider() -> ColorRect:
	var divider = ColorRect.new()
	divider.custom_minimum_size = Vector2(2, 32)
	divider.color = Color(0.4, 0.35, 0.3, 0.6)
	return divider


func _create_command_button(text: String, tooltip: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = Vector2(36, 32)
	btn.add_theme_font_size_override("font_size", 12)
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_apply_hud_button_style(btn)
	btn.pressed.connect(callback)
	return btn


func _issue_halt_command():
	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment):
			regiment.give_order(OrderType.Type.HOLD_POSITION)


func _toggle_run_command():
	if SelectionManager.selected_regiments.is_empty():
		return
	# Check if any selected regiment is walking
	var any_walking: bool = false
	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment) and regiment.leader:
			if regiment.leader.move_mode == RegimentLeader.MoveMode.WALK:
				any_walking = true
				break
	# Toggle
	var new_mode = RegimentLeader.MoveMode.RUN if any_walking else RegimentLeader.MoveMode.WALK
	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment) and regiment.leader:
			if regiment.leader.move_mode != RegimentLeader.MoveMode.CHARGE:
				regiment.leader.set_move_mode(new_mode)


func _create_speed_controls():
	# Phase 1: Content moved to _create_bottom_hud()
	pass


func _create_speed_button(text: String, speed: float) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(44, 44)  # Larger click target
	btn.add_theme_font_size_override("font_size", 16)
	btn.focus_mode = Control.FOCUS_NONE  # Prevent focus stealing
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Apply consistent dark theme styling
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.11, 0.10, 0.95)
	normal_style.border_color = COLOR_PANEL_BORDER
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.18, 0.16, 0.14, 0.95)
	hover_style.border_color = COLOR_GOLD
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0.08, 0.07, 0.06, 0.95)
	pressed_style.border_color = COLOR_GOLD
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_color_override("font_color", COLOR_TEXT)
	btn.add_theme_color_override("font_hover_color", COLOR_GOLD)
	btn.add_theme_color_override("font_pressed_color", COLOR_GOLD)

	btn.pressed.connect(func(): _set_game_speed(speed))
	return btn


func _set_game_speed(speed: float):
	if speed == 0.0:
		Engine.time_scale = 0.001  # Near-pause
	else:
		Engine.time_scale = speed
	speed_label.text = "%.1fx" % speed


# === HOVER PREVIEW (QOL Phase 5) ===

func _create_hover_preview():
	"""Create floating panel that shows unit info on mouse hover."""
	hover_preview_panel = Panel.new()
	hover_preview_panel.visible = false
	hover_preview_panel.custom_minimum_size = Vector2(200, 80)
	hover_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block input

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	style.border_color = Color(0.8, 0.3, 0.3, 1.0)  # Red-ish for enemies
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	hover_preview_panel.add_theme_stylebox_override("panel", style)
	add_child(hover_preview_panel)

	# Unit name label
	hover_preview_name = Label.new()
	hover_preview_name.add_theme_font_size_override("font_size", 14)
	hover_preview_name.add_theme_color_override("font_color", COLOR_GOLD)
	hover_preview_name.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hover_preview_name.offset_left = 8
	hover_preview_name.offset_top = 6
	hover_preview_panel.add_child(hover_preview_name)

	# Stats label (morale, soldiers, etc.)
	hover_preview_stats = Label.new()
	hover_preview_stats.add_theme_font_size_override("font_size", 12)
	hover_preview_stats.add_theme_color_override("font_color", COLOR_TEXT)
	hover_preview_stats.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hover_preview_stats.offset_left = 8
	hover_preview_stats.offset_top = 28
	hover_preview_panel.add_child(hover_preview_stats)


func _create_trait_panel():
	"""Create collapsible panel showing active general traits (Phase 6.6)."""
	trait_panel = Panel.new()
	trait_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	trait_panel.offset_left = 10
	trait_panel.offset_top = 90  # Below control group bar
	trait_panel.offset_right = 180
	trait_panel.offset_bottom = 115  # Collapsed height

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.05, 0.85)
	style.border_color = COLOR_GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	trait_panel.add_theme_stylebox_override("panel", style)
	add_child(trait_panel)

	# Header button (click to expand/collapse)
	trait_panel_header = Button.new()
	trait_panel_header.text = "▶ General Traits"
	trait_panel_header.add_theme_font_size_override("font_size", 11)
	trait_panel_header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	trait_panel_header.offset_top = 2
	trait_panel_header.offset_bottom = 22
	trait_panel_header.offset_left = 4
	trait_panel_header.offset_right = -4
	trait_panel_header.flat = true
	trait_panel_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	trait_panel_header.pressed.connect(_on_trait_panel_toggle)
	trait_panel.add_child(trait_panel_header)

	# Content container (hidden by default)
	trait_panel_content = VBoxContainer.new()
	trait_panel_content.set_anchors_preset(Control.PRESET_TOP_WIDE)
	trait_panel_content.offset_top = 24
	trait_panel_content.offset_left = 8
	trait_panel_content.offset_right = -8
	trait_panel_content.visible = false
	trait_panel.add_child(trait_panel_content)

	# Hide initially if no traits
	_update_trait_panel()


func _on_trait_panel_toggle():
	"""Toggle trait panel expanded/collapsed state."""
	_trait_panel_expanded = not _trait_panel_expanded
	trait_panel_content.visible = _trait_panel_expanded
	trait_panel_header.text = "▼ General Traits" if _trait_panel_expanded else "▶ General Traits"

	# Resize panel
	if _trait_panel_expanded:
		var content_height: int = trait_panel_content.get_children().size() * 18 + 30
		trait_panel.offset_bottom = trait_panel.offset_top + content_height
	else:
		trait_panel.offset_bottom = trait_panel.offset_top + 25


func _update_trait_panel():
	"""Update trait panel with current general traits."""
	if not trait_panel or not trait_panel_content:
		return

	# Clear old labels
	for child in trait_panel_content.get_children():
		child.queue_free()

	# Get trait names from BattleModifiers
	if not BattleModifiers or not BattleModifiers.is_active():
		trait_panel.visible = false
		return

	var player_traits: Array[String] = BattleModifiers.get_trait_names(true)
	if player_traits.is_empty():
		trait_panel.visible = false
		return

	trait_panel.visible = true

	# Add trait labels
	for trait_name in player_traits:
		var lbl = Label.new()
		lbl.text = "• " + trait_name
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7, 1.0))
		trait_panel_content.add_child(lbl)


func _on_regiment_hover_entered(regiment: Regiment) -> void:
	"""Show hover preview for regiment under mouse."""
	if not is_instance_valid(regiment) or not regiment.data:
		return

	_hovered_regiment = regiment
	hover_preview_panel.visible = true

	# Update content
	hover_preview_name.text = regiment.data.regiment_name
	hover_preview_stats.text = "Soldiers: %d/%d\nMorale: %d%%" % [
		regiment.current_soldiers,
		regiment.data.max_soldiers,
		int(regiment.current_morale)
	]

	# Add threat info for enemies
	if not regiment.is_player_controlled:
		hover_preview_stats.text += "\nAtk: %d | Def: %d" % [
			regiment.data.attack,
			regiment.data.defense
		]

	# Position near mouse (offset to not obscure)
	_update_hover_position()


func _on_regiment_hover_exited(_regiment: Regiment) -> void:
	"""Hide hover preview."""
	_hovered_regiment = null
	hover_preview_panel.visible = false


# === AUTO-PAUSE (QOL Phase 7) ===
var _auto_pause_enabled: bool = false  # Disabled - was causing unwanted pauses during battle

func _on_regiment_routing_autopause(regiment: Regiment) -> void:
	"""Auto-pause when a player unit starts routing."""
	if not _auto_pause_enabled:
		return
	if not regiment or not regiment.is_player_controlled:
		return
	# Auto-pause the game
	if not get_tree().paused:
		get_tree().paused = true
		BattleSignals.battle_paused.emit(true)


func _on_battle_ended_autopause(result: Dictionary) -> void:
	"""Auto-pause when battle ends and show after-action report."""
	# Skip during stress tests - check for Unit Zoo stress test running
	var unit_zoo = get_node_or_null("/root/UnitZoo")
	if unit_zoo and unit_zoo.has_method("is_stress_test_running") and unit_zoo.is_stress_test_running():
		return  # Don't show after-action report during stress tests

	if not get_tree().paused:
		get_tree().paused = true
		BattleSignals.battle_paused.emit(true)
	# Show after-action report
	_show_after_action_report(result)


# === AFTER-ACTION REPORT (QOL Phase 8) ===

func _show_after_action_report(result: Dictionary) -> void:
	"""Display battle summary after victory/defeat."""
	if not result.has("winner"):
		return

	# Create panel if it doesn't exist
	if not after_action_panel:
		_create_after_action_panel()

	# Clear previous content
	for child in after_action_content.get_children():
		child.queue_free()

	# Victory/Defeat header
	var header := Label.new()
	var is_victory: bool = result.get("player_victory", false)
	header.text = "VICTORY!" if is_victory else "DEFEAT"
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3) if is_victory else Color(0.8, 0.3, 0.3))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	after_action_content.add_child(header)

	# Duration
	var duration: float = result.get("duration", 0.0)
	var duration_label := Label.new()
	duration_label.text = "Battle Duration: %d:%02d" % [int(duration) / 60, int(duration) % 60]
	duration_label.add_theme_font_size_override("font_size", 14)
	duration_label.add_theme_color_override("font_color", COLOR_TEXT)
	duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	after_action_content.add_child(duration_label)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 20
	after_action_content.add_child(spacer)

	# Casualties summary
	var casualties: Dictionary = result.get("casualties", {})
	var player_kills: int = casualties.get("player_kills", 0)
	var player_losses: int = casualties.get("player_losses", 0)
	var enemy_kills: int = casualties.get("enemy_kills", 0)
	var enemy_losses: int = casualties.get("enemy_losses", 0)

	# Your Army section
	var your_header := Label.new()
	your_header.text = "YOUR FORCES"
	your_header.add_theme_font_size_override("font_size", 16)
	your_header.add_theme_color_override("font_color", COLOR_GOLD)
	after_action_content.add_child(your_header)

	var your_stats := Label.new()
	your_stats.text = "Kills: %d | Losses: %d" % [player_kills, player_losses]
	your_stats.add_theme_font_size_override("font_size", 14)
	your_stats.add_theme_color_override("font_color", COLOR_TEXT)
	after_action_content.add_child(your_stats)

	# Per-unit breakdown (player)
	var player_unit_stats: Dictionary = casualties.get("player_unit_stats", {})
	for unit_name in player_unit_stats:
		var s: Dictionary = player_unit_stats[unit_name]
		var unit_label := Label.new()
		var remaining: int = s.get("starting", 0) - s.get("losses", 0)
		unit_label.text = "  %s: %d/%d (K:%d)" % [s.get("display_name", unit_name), remaining, s.get("starting", 0), s.get("kills", 0)]
		unit_label.add_theme_font_size_override("font_size", 12)
		unit_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		after_action_content.add_child(unit_label)

	# Spacer
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 10
	after_action_content.add_child(spacer2)

	# Enemy Forces section
	var enemy_header := Label.new()
	enemy_header.text = "ENEMY FORCES"
	enemy_header.add_theme_font_size_override("font_size", 16)
	enemy_header.add_theme_color_override("font_color", Color(0.8, 0.4, 0.4))
	after_action_content.add_child(enemy_header)

	var enemy_stats := Label.new()
	enemy_stats.text = "Kills: %d | Losses: %d" % [enemy_kills, enemy_losses]
	enemy_stats.add_theme_font_size_override("font_size", 14)
	enemy_stats.add_theme_color_override("font_color", COLOR_TEXT)
	after_action_content.add_child(enemy_stats)

	# Continue button
	var spacer3 := Control.new()
	spacer3.custom_minimum_size.y = 20
	after_action_content.add_child(spacer3)

	var continue_btn := Button.new()
	continue_btn.text = "CONTINUE"
	continue_btn.custom_minimum_size = Vector2(120, 40)
	_apply_hud_button_style(continue_btn)
	continue_btn.pressed.connect(_on_after_action_continue)
	after_action_content.add_child(continue_btn)

	after_action_panel.visible = true


func _create_after_action_panel() -> void:
	"""Create the after-action report panel."""
	after_action_panel = Panel.new()
	after_action_panel.set_anchors_preset(Control.PRESET_CENTER)
	after_action_panel.offset_left = -200
	after_action_panel.offset_right = 200
	after_action_panel.offset_top = -200
	after_action_panel.offset_bottom = 200
	after_action_panel.visible = false
	after_action_panel.process_mode = Node.PROCESS_MODE_ALWAYS  # Works when paused

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.03, 0.98)
	style.border_color = COLOR_GOLD
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	after_action_panel.add_theme_stylebox_override("panel", style)
	add_child(after_action_panel)

	# Scrollable content
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.set_anchor_and_offset(SIDE_LEFT, 0, 15)
	scroll.set_anchor_and_offset(SIDE_RIGHT, 1, -15)
	scroll.set_anchor_and_offset(SIDE_TOP, 0, 15)
	scroll.set_anchor_and_offset(SIDE_BOTTOM, 1, -15)
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	after_action_panel.add_child(scroll)

	after_action_content = VBoxContainer.new()
	after_action_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	after_action_content.add_theme_constant_override("separation", 4)
	after_action_content.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.add_child(after_action_content)


func _on_after_action_continue() -> void:
	"""Close after-action report and return to campaign or main menu."""
	after_action_panel.visible = false
	# Unpause so the game can transition
	get_tree().paused = false
	BattleSignals.battle_paused.emit(false)


func _update_hover_position() -> void:
	"""Position hover panel near mouse cursor."""
	if not hover_preview_panel.visible:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_size: Vector2 = hover_preview_panel.size

	# Offset to right of cursor, flip if near edge
	var offset := Vector2(20, -20)
	if mouse_pos.x + panel_size.x + 20 > screen_size.x:
		offset.x = -panel_size.x - 20

	hover_preview_panel.global_position = mouse_pos + offset


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
		if not BattleSignals.unit_disengage_failed.is_connected(_on_unit_disengage_failed):
			BattleSignals.unit_disengage_failed.connect(_on_unit_disengage_failed)
		if not BattleSignals.unit_disengage_success.is_connected(_on_unit_disengage_success):
			BattleSignals.unit_disengage_success.connect(_on_unit_disengage_success)
		# QOL Phase 5: Hover preview
		if not BattleSignals.regiment_hover_entered.is_connected(_on_regiment_hover_entered):
			BattleSignals.regiment_hover_entered.connect(_on_regiment_hover_entered)
		if not BattleSignals.regiment_hover_exited.is_connected(_on_regiment_hover_exited):
			BattleSignals.regiment_hover_exited.connect(_on_regiment_hover_exited)
		# QOL Phase 7: Auto-pause on important events
		if not BattleSignals.regiment_routing.is_connected(_on_regiment_routing_autopause):
			BattleSignals.regiment_routing.connect(_on_regiment_routing_autopause)
		if not BattleSignals.battle_ended.is_connected(_on_battle_ended_autopause):
			BattleSignals.battle_ended.connect(_on_battle_ended_autopause)
		# Phase 3: Re-bucket cards when control groups change
		if not BattleSignals.group_saved.is_connected(_on_group_saved):
			BattleSignals.group_saved.connect(_on_group_saved)


func _on_deployment_ended():
	deployment_panel.visible = false
	# Repopulate cards in case any were missed during initial load
	_populate_unit_cards()


# Phase 3: Re-bucket unit cards when control groups change
func _on_group_saved(_group_id: int, _regiments: Array):
	_populate_unit_cards()


func _on_battle_started():
	deployment_panel.visible = false
	battle_timer_label.text = "00:00"


func _populate_unit_cards():
	# Phase 3: Clear all children including dividers
	for child in unit_card_container.get_children():
		child.queue_free()
	unit_cards.clear()

	await get_tree().process_frame
	await get_tree().process_frame

	# Safety check after await in case scene changed
	if not is_instance_valid(self) or not is_instance_valid(unit_card_container):
		return

	# Phase 3: Get regiments bucketed by control group
	var grouped: Dictionary = SelectionManager.get_regiments_by_group()
	var total_count: int = 0

	# Render in order: groups 1-9, group 0, ungrouped (-1)
	var group_order: Array = []
	for g_id in range(1, 10):
		if grouped.has(g_id):
			group_order.append(g_id)
	if grouped.has(0):
		group_order.append(0)
	if grouped.has(-1):
		group_order.append(-1)

	for g_idx in range(group_order.size()):
		var group_id: int = group_order[g_idx]
		var members: Array = grouped[group_id]

		# Add group divider (except before first group)
		if g_idx > 0:
			_add_group_divider(group_id)
		elif group_id >= 0:
			# First group - show label without divider line
			_add_group_label(group_id)

		for regiment in members:
			if regiment is Regiment and regiment not in unit_cards:
				_add_unit_card(regiment)
				total_count += 1

	print("[BattleHUD] Created %d unit cards in %d groups" % [total_count, group_order.size()])


## Public method to refresh unit cards (for unit zoo and dynamic spawning)
func refresh_unit_cards() -> void:
	_populate_unit_cards()


# Phase 3: Add a visual divider with group label between card groups
func _add_group_divider(group_id: int) -> void:
	var divider = VBoxContainer.new()
	divider.custom_minimum_size = Vector2(24, 0)
	divider.alignment = BoxContainer.ALIGNMENT_CENTER

	# Vertical line
	var line = ColorRect.new()
	line.custom_minimum_size = Vector2(2, 60)
	line.color = Color(0.5, 0.45, 0.35, 0.5)
	divider.add_child(line)

	# Group label below line
	if group_id >= 0:
		var lbl = Label.new()
		lbl.text = str(group_id)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		divider.add_child(lbl)

	unit_card_container.add_child(divider)


# Phase 3: Add just a group label (no divider line) for first group
func _add_group_label(group_id: int) -> void:
	var container = VBoxContainer.new()
	container.custom_minimum_size = Vector2(20, 0)
	container.alignment = BoxContainer.ALIGNMENT_END

	var lbl = Label.new()
	lbl.text = str(group_id)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", COLOR_GOLD)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(lbl)

	unit_card_container.add_child(container)


func _add_unit_card(regiment: Regiment):
	var card = UnitCardScript.new()
	unit_card_container.add_child(card)
	card.setup(regiment)
	card.card_clicked.connect(_on_card_clicked)
	card.card_shift_clicked.connect(_on_card_shift_clicked)  # Multi-select (add)
	card.card_ctrl_clicked.connect(_on_card_ctrl_clicked)    # Toggle selection
	unit_cards[regiment] = card


func _remove_unit_card(regiment: Regiment):
	if regiment in unit_cards:
		unit_cards[regiment].queue_free()
		unit_cards.erase(regiment)


func _on_card_clicked(regiment: Regiment):
	if SelectionManager:
		SelectionManager.select_regiment(regiment)


func _on_card_shift_clicked(regiment: Regiment):
	# Add to selection without clearing existing selection
	if SelectionManager:
		SelectionManager.add_to_selection(regiment)


func _on_card_ctrl_clicked(regiment: Regiment):
	# Toggle regiment in selection (add if not selected, remove if selected)
	if SelectionManager:
		if regiment in SelectionManager.selected_regiments:
			SelectionManager._remove_from_selection(regiment)
		else:
			SelectionManager.add_to_selection(regiment)


func _on_tide_changed(_old_value: float, new_value: float):
	# Update tide bar visualization
	# new_value ranges from -100 (enemy winning) to +100 (player winning)
	if not tide_bar_fill or not tide_bar_container:
		return

	# Calculate bar position and size
	# Bar is 200px wide, center is at x=100
	var bar_width: float = 200.0
	var center: float = bar_width / 2.0
	var normalized: float = new_value / 100.0  # -1 to +1

	if new_value >= 0:
		# Player winning: fill from center to right (green)
		var fill_width: float = normalized * center
		tide_bar_fill.position.x = center
		tide_bar_fill.size.x = fill_width
		tide_bar_fill.color = Color(0.3, 0.7, 0.4, 0.9)  # Green
	else:
		# Enemy winning: fill from center to left (red)
		var fill_width: float = -normalized * center
		tide_bar_fill.position.x = center - fill_width
		tide_bar_fill.size.x = fill_width
		tide_bar_fill.color = Color(0.8, 0.3, 0.3, 0.9)  # Red

	# Update tooltip
	var status: String
	if new_value > 30:
		status = "Winning"
	elif new_value > 10:
		status = "Advantage"
	elif new_value < -30:
		status = "Losing"
	elif new_value < -10:
		status = "Disadvantage"
	else:
		status = "Even"
	tide_bar_container.tooltip_text = "Battle Tide: %s (%.0f)" % [status, new_value]


func _on_regiment_selected(regiment: Regiment):
	current_selected_regiment = regiment
	_update_selected_unit_panel(regiment)

	# Phase 2: Update command bar for current selection
	_update_stance_buttons()
	_update_formation_buttons()
	_update_command_bar_abilities()

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

	# Phase 2: Stance/formation/ability buttons moved to command bar
	# Updated via _on_regiment_selected, not here


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
		btn.custom_minimum_size = Vector2(40, 32)  # Larger click target
		btn.add_theme_font_size_override("font_size", 13)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_hud_button_style(btn)
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
		btn.custom_minimum_size = Vector2(50, 32)  # Larger click target
		btn.add_theme_font_size_override("font_size", 12)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_hud_button_style(btn)
		btn.pressed.connect(_on_formation_button_pressed.bind(formation))
		formation_container.add_child(btn)
		formation_buttons[formation] = btn


func _on_stance_button_pressed(stance: StanceType.Type):
	# Phase 2: Apply to all selected units
	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment):
			regiment.set_stance(stance)
	_update_stance_buttons()


func _on_formation_button_pressed(formation: FormationType.Type):
	# Phase 2: Apply to all selected units
	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment):
			regiment.set_formation(formation)
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
		container.custom_minimum_size = Vector2(58, 38)  # Larger click target

		var btn: Button = Button.new()
		btn.text = data.get("name", "?").substr(0, 3)
		btn.tooltip_text = "%s\n%s\nCooldown: %.0fs" % [
			data.get("name", "Unknown"),
			data.get("description", ""),
			data.get("cooldown", 0.0)
		]
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_theme_font_size_override("font_size", 11)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_hud_button_style(btn)

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
	# Phase 2: Apply to all selected units that have this ability
	var data: Dictionary = AbilityType.get_ability_data(ability)
	var is_toggle: bool = data.get("duration", 1.0) == 0.0

	for regiment in SelectionManager.selected_regiments:
		if not is_instance_valid(regiment) or not regiment.abilities:
			continue
		if ability not in regiment.abilities.available_abilities:
			continue
		if is_toggle:
			regiment.toggle_ability(ability)
		else:
			regiment.use_ability(ability)


# Phase 2: Get abilities available across the selection
func _abilities_for_selection() -> Array:
	var sel = SelectionManager.selected_regiments
	if sel.is_empty():
		return []

	# Single unit: simple list
	if sel.size() == 1:
		var single = []
		var reg = sel[0]
		if not is_instance_valid(reg) or not reg.abilities:
			return []
		for a in reg.abilities.available_abilities:
			single.append({"ability": a, "available_count": 1, "total": 1})
		return single

	# Multiple units: count how many have each ability
	var counts = {}
	for reg in sel:
		if not is_instance_valid(reg) or not reg.abilities:
			continue
		for a in reg.abilities.available_abilities:
			counts[a] = counts.get(a, 0) + 1

	var result = []
	for a in counts:
		result.append({"ability": a, "available_count": counts[a], "total": sel.size()})
	return result


# Phase 2: Update command bar abilities based on selection
func _update_command_bar_abilities():
	# Clear old abilities
	for child in ability_container.get_children():
		child.queue_free()
	ability_buttons.clear()
	ability_overlays.clear()
	ability_types.clear()

	var abilities = _abilities_for_selection()
	if abilities.is_empty():
		return

	var hotkeys: Array[String] = ["Q", "E", "R", "T"]
	var idx: int = 0

	for ability_info in abilities:
		var ability = ability_info["ability"]
		var available_count: int = ability_info["available_count"]
		var total: int = ability_info["total"]
		var data: Dictionary = AbilityType.get_ability_data(ability)

		var container: Control = Control.new()
		container.custom_minimum_size = Vector2(52, 32)

		var btn: Button = Button.new()
		var btn_text: String = data.get("name", "?").substr(0, 3)
		if idx < hotkeys.size():
			btn_text = "[%s] %s" % [hotkeys[idx], btn_text]

		# Show count badge if not all units have it
		if available_count < total:
			btn_text += " %d/%d" % [available_count, total]

		btn.text = btn_text
		btn.tooltip_text = "%s\n%s\nCooldown: %.0fs\n%d/%d units" % [
			data.get("name", "Unknown"),
			data.get("description", ""),
			data.get("cooldown", 0.0),
			available_count, total
		]
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.add_theme_font_size_override("font_size", 10)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_apply_hud_button_style(btn)
		btn.pressed.connect(_on_ability_button_pressed.bind(ability))
		container.add_child(btn)

		ability_container.add_child(container)
		ability_buttons.append(btn)
		ability_types.append(ability)
		idx += 1


func _on_regiment_dead(regiment: Regiment):
	_remove_unit_card(regiment)
	if current_selected_regiment == regiment:
		selected_unit_panel.visible = false
		current_selected_regiment = null


func _on_unit_disengage_failed(regiment: Regiment) -> void:
	if regiment == current_selected_regiment:
		_show_combat_message("Disengage failed! (%.1fs cooldown)" % regiment._disengage_cooldown)


func _on_unit_disengage_success(regiment: Regiment) -> void:
	if regiment == current_selected_regiment:
		_show_combat_message("Disengaged!")


# Combat message label (created on first use)
var _combat_message_label: Label = null

func _show_combat_message(message: String) -> void:
	## Display a temporary combat feedback message at center-bottom of screen.
	if not _combat_message_label:
		_combat_message_label = Label.new()
		_combat_message_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_combat_message_label.offset_top = -180
		_combat_message_label.offset_bottom = -150
		_combat_message_label.offset_left = -150
		_combat_message_label.offset_right = 150
		_combat_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_combat_message_label.add_theme_font_size_override("font_size", 16)
		_combat_message_label.add_theme_color_override("font_color", COLOR_GOLD)
		add_child(_combat_message_label)

	_combat_message_label.text = message
	_combat_message_label.visible = true
	_combat_message_label.modulate = Color.WHITE

	# Fade out after 2 seconds
	var tween: Tween = create_tween()
	tween.tween_interval(1.5)
	tween.tween_property(_combat_message_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): _combat_message_label.visible = false)


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
