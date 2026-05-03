# Unit card UI element - displays regiment info like Total War
# Enhanced with: card states, rank chevrons, unit type icons, status indicators,
# improved morale display, and ability cooldown badges
class_name UnitCard
extends PanelContainer


signal card_clicked(regiment: Regiment)
signal card_right_clicked(regiment: Regiment)

var regiment: Regiment
var is_selected: bool = false

# === CARD STATE SYSTEM (Task 1) ===
enum CardState {
	NORMAL,
	SELECTED,
	HOVER,
	TAKING_DAMAGE,
	WAVERING,
	ROUTING,
	DEAD
}

var card_state: CardState = CardState.NORMAL
var _damage_flash_timer: float = 0.0
var _wavering_pulse_timer: float = 0.0
const DAMAGE_FLASH_DURATION: float = 0.8
const DAMAGE_FLASH_SPEED: float = 25.0  # ~4 Hz
const WAVERING_PULSE_SPEED: float = 6.28  # 1 Hz

# State colors
const COLOR_BORDER_NORMAL = Color(0.3, 0.3, 0.3, 1.0)
const COLOR_BORDER_SELECTED = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_BORDER_DAMAGE = Color(0.9, 0.2, 0.1, 1.0)
const COLOR_BORDER_WAVERING = Color(0.9, 0.6, 0.1, 1.0)
const COLOR_BORDER_ROUTING = Color(0.5, 0.5, 0.5, 1.0)
const COLOR_MODULATE_ROUTING = Color(0.5, 0.5, 0.5, 1.0)
const COLOR_MODULATE_DEAD = Color(0.3, 0.3, 0.3, 0.5)

# === CHEVRON BADGES (Task 2) ===
const CHEVRON_COLORS = {
	0: Color(0.0, 0.0, 0.0, 0.0),  # FRESH - invisible
	1: Color(0.6, 0.5, 0.3, 1.0),  # BLOODED - bronze
	2: Color(0.75, 0.65, 0.4, 1.0),  # VETERAN - silver-gold
	3: Color(0.85, 0.7, 0.4, 1.0),  # ELITE - gold
}

# === UNIT TYPE ICONS (Task 3) ===
const UNIT_TYPE_COLORS = {
	UnitType.Type.INFANTRY: Color(0.4, 0.5, 0.7, 1.0),  # Blue-gray
	UnitType.Type.CAVALRY: Color(0.6, 0.4, 0.3, 1.0),   # Brown
	UnitType.Type.RANGED: Color(0.3, 0.6, 0.4, 1.0),    # Green
	UnitType.Type.ARTILLERY: Color(0.5, 0.5, 0.5, 1.0), # Gray
}

const UNIT_TYPE_LETTERS = {
	UnitType.Type.INFANTRY: "I",
	UnitType.Type.CAVALRY: "C",
	UnitType.Type.RANGED: "R",
	UnitType.Type.ARTILLERY: "A",
}

# Status icon colors
const COLOR_STATUS_BRACED = Color(0.4, 0.6, 0.9, 1.0)  # Blue
const COLOR_STATUS_CHARGING = Color(0.9, 0.7, 0.2, 1.0)  # Yellow
const COLOR_STATUS_INSPIRED = Color(0.85, 0.7, 0.4, 1.0)  # Gold
const COLOR_STATUS_HOLD_FIRE = Color(0.8, 0.3, 0.3, 1.0)  # Red

# === MORALE THRESHOLDS (Task 4) ===
const MORALE_STEADY_THRESHOLD: float = 70.0
const MORALE_WAVERING_THRESHOLD: float = 40.0
const MORALE_SHAKEN_THRESHOLD: float = 20.0

const COLOR_MORALE_STEADY = Color(0.2, 0.7, 0.2, 1.0)    # Green
const COLOR_MORALE_WAVERING = Color(0.9, 0.7, 0.2, 1.0)  # Yellow
const COLOR_MORALE_SHAKEN = Color(0.9, 0.4, 0.1, 1.0)    # Orange
const COLOR_MORALE_BROKEN = Color(0.9, 0.2, 0.1, 1.0)    # Red

# UI elements - existing
var portrait_rect: TextureRect
var name_label: Label
var soldier_count_label: Label
var health_bar: ProgressBar
var morale_bar: ProgressBar
var ammo_label: Label
var ammo_bar: ProgressBar
var ammo_warning_label: Label
var ammo_container: VBoxContainer

# UI elements - new
var chevron_container: HBoxContainer
var unit_type_badge: Panel
var unit_type_label: Label
var status_container: HBoxContainer
var morale_bar_container: Control
var morale_threshold_markers: Array[ColorRect] = []
var ability_cooldown_container: HBoxContainer

# Ammo warning state
var _ammo_warning_active: bool = false
var _ammo_warning_timer: float = 0.0
var _ammo_empty_warning_played: bool = false
var _ammo_low_warning_played: bool = false
const AMMO_LOW_THRESHOLD: float = 0.25  # 25%
const AMMO_WARNING_FLASH_SPEED: float = 4.0  # Flashes per second


func _ready():
	_setup_ui()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Connect to battle signals for card state updates
	if BattleSignals:
		BattleSignals.regiment_attacked.connect(_on_regiment_attacked)
		BattleSignals.regiment_routing.connect(_on_regiment_routing)
		BattleSignals.regiment_rallied.connect(_on_regiment_rallied)


func _setup_ui():
	custom_minimum_size = Vector2(120, 150)
	# Ensure this card captures mouse clicks
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	# Children should pass mouse events to parent (this card)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(vbox)

	# Portrait area with faction color background
	var portrait_container = Control.new()
	portrait_container.custom_minimum_size = Vector2(100, 60)
	portrait_container.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(portrait_container)

	portrait_rect = TextureRect.new()
	portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	portrait_container.add_child(portrait_rect)

	# === CHEVRON BADGES (Task 2) ===
	chevron_container = HBoxContainer.new()
	chevron_container.position = Vector2(4, 4)
	chevron_container.add_theme_constant_override("separation", 2)
	portrait_container.add_child(chevron_container)

	# === UNIT TYPE BADGE (Task 3) ===
	unit_type_badge = Panel.new()
	unit_type_badge.custom_minimum_size = Vector2(16, 16)
	unit_type_badge.position = Vector2(80, 4)  # Top-right of portrait
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.4, 0.5, 0.7)
	badge_style.set_corner_radius_all(3)
	unit_type_badge.add_theme_stylebox_override("panel", badge_style)
	portrait_container.add_child(unit_type_badge)

	unit_type_label = Label.new()
	unit_type_label.text = "I"
	unit_type_label.add_theme_font_size_override("font_size", 10)
	unit_type_label.add_theme_color_override("font_color", Color.WHITE)
	unit_type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unit_type_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	unit_type_badge.add_child(unit_type_label)

	# Unit name
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(name_label)

	# === STATUS ICONS (Task 3) ===
	status_container = HBoxContainer.new()
	status_container.custom_minimum_size = Vector2(0, 14)
	status_container.add_theme_constant_override("separation", 2)
	status_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(status_container)

	# Soldier count
	soldier_count_label = Label.new()
	soldier_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soldier_count_label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(soldier_count_label)

	# Health bar
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(100, 8)
	health_bar.show_percentage = false
	health_bar.max_value = 100
	vbox.add_child(health_bar)

	# === MORALE BAR WITH THRESHOLDS (Task 4) ===
	morale_bar_container = Control.new()
	morale_bar_container.custom_minimum_size = Vector2(100, 8)
	vbox.add_child(morale_bar_container)

	morale_bar = ProgressBar.new()
	morale_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	morale_bar.show_percentage = false
	morale_bar.max_value = 100
	var morale_style = StyleBoxFlat.new()
	morale_style.bg_color = COLOR_MORALE_STEADY
	morale_bar.add_theme_stylebox_override("fill", morale_style)
	morale_bar_container.add_child(morale_bar)

	# Add threshold markers
	_add_morale_marker(MORALE_STEADY_THRESHOLD, COLOR_MORALE_STEADY)
	_add_morale_marker(MORALE_WAVERING_THRESHOLD, COLOR_MORALE_WAVERING)
	_add_morale_marker(MORALE_SHAKEN_THRESHOLD, COLOR_MORALE_BROKEN)

	# Ammo container (for ranged units)
	ammo_container = VBoxContainer.new()
	ammo_container.add_theme_constant_override("separation", 1)
	ammo_container.visible = false
	vbox.add_child(ammo_container)

	# Ammo bar
	ammo_bar = ProgressBar.new()
	ammo_bar.custom_minimum_size = Vector2(100, 6)
	ammo_bar.show_percentage = false
	ammo_bar.max_value = 100
	var ammo_bar_style = StyleBoxFlat.new()
	ammo_bar_style.bg_color = Color(0.3, 0.7, 0.9)
	ammo_bar.add_theme_stylebox_override("fill", ammo_bar_style)
	var ammo_bg_style = StyleBoxFlat.new()
	ammo_bg_style.bg_color = Color(0.15, 0.15, 0.2)
	ammo_bar.add_theme_stylebox_override("background", ammo_bg_style)
	ammo_container.add_child(ammo_bar)

	# Ammo count label
	ammo_label = Label.new()
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_label.add_theme_font_size_override("font_size", 9)
	ammo_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	ammo_container.add_child(ammo_label)

	# OUT OF AMMO warning label
	ammo_warning_label = Label.new()
	ammo_warning_label.text = "OUT OF AMMO"
	ammo_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_warning_label.add_theme_font_size_override("font_size", 8)
	ammo_warning_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	ammo_warning_label.visible = false
	ammo_container.add_child(ammo_warning_label)

	# === ABILITY COOLDOWN BADGES (Task 5) ===
	ability_cooldown_container = HBoxContainer.new()
	ability_cooldown_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ability_cooldown_container.position = Vector2(-52, -16)
	ability_cooldown_container.add_theme_constant_override("separation", 2)
	add_child(ability_cooldown_container)


func _add_morale_marker(threshold: float, color: Color):
	var marker = ColorRect.new()
	marker.custom_minimum_size = Vector2(2, 8)
	marker.color = color
	marker.color.a = 0.6
	marker.position = Vector2(threshold - 1, 0)
	morale_bar_container.add_child(marker)
	morale_threshold_markers.append(marker)


func setup(reg: Regiment):
	regiment = reg
	if not regiment:
		return

	name_label.text = regiment.data.regiment_name
	_setup_unit_type_badge()
	_update_display()

	# Set faction color as background
	var style = StyleBoxFlat.new()
	style.bg_color = regiment.data.faction_color
	style.bg_color.a = 0.3
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

	# Show ammo container for ranged units
	if regiment.data.max_ammo > 0:
		ammo_container.visible = true
		ammo_bar.max_value = regiment.data.max_ammo
		_ammo_empty_warning_played = false
		_ammo_low_warning_played = false


func _setup_unit_type_badge():
	if not regiment or not regiment.data:
		return

	var unit_type = regiment.data.unit_type
	var color = UNIT_TYPE_COLORS.get(unit_type, Color(0.5, 0.5, 0.5))
	var letter = UNIT_TYPE_LETTERS.get(unit_type, "?")

	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = color
	badge_style.set_corner_radius_all(3)
	unit_type_badge.add_theme_stylebox_override("panel", badge_style)
	unit_type_label.text = letter


func _process(delta: float):
	if regiment:
		_update_card_state(delta)
		_update_display()
		_update_chevrons()
		_update_status_icons()
		_update_morale_display()
		_update_ammo_warning(delta)
		_update_ability_cooldowns()
		_apply_card_state_visuals()


# === CARD STATE SYSTEM (Task 1) ===

func _update_card_state(delta: float):
	if not regiment:
		return

	# Update damage flash timer
	if _damage_flash_timer > 0:
		_damage_flash_timer -= delta
		if _damage_flash_timer <= 0:
			_damage_flash_timer = 0.0

	# Update wavering pulse
	_wavering_pulse_timer += delta * WAVERING_PULSE_SPEED

	# Determine card state based on regiment state
	if regiment.state == Regiment.State.DEAD:
		card_state = CardState.DEAD
	elif regiment.state == Regiment.State.ROUTING:
		card_state = CardState.ROUTING
	elif _damage_flash_timer > 0:
		card_state = CardState.TAKING_DAMAGE
	elif regiment.current_morale < MORALE_STEADY_THRESHOLD and regiment.current_morale >= MORALE_WAVERING_THRESHOLD:
		card_state = CardState.WAVERING
	elif is_selected:
		card_state = CardState.SELECTED
	else:
		card_state = CardState.NORMAL


func _apply_card_state_visuals():
	var style = get_theme_stylebox("panel")
	if not style or not style is StyleBoxFlat:
		return

	style = style.duplicate() as StyleBoxFlat

	match card_state:
		CardState.NORMAL:
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = COLOR_BORDER_NORMAL
			modulate = Color.WHITE

		CardState.SELECTED:
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
			style.border_color = COLOR_BORDER_SELECTED
			modulate = Color.WHITE

		CardState.TAKING_DAMAGE:
			var flash_intensity = sin(_damage_flash_timer * DAMAGE_FLASH_SPEED) * 0.5 + 0.5
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4
			var border_color = COLOR_BORDER_DAMAGE
			border_color.a = 0.7 + flash_intensity * 0.3
			style.border_color = border_color
			modulate = Color(1.0 + flash_intensity * 0.2, 1.0, 1.0)

		CardState.WAVERING:
			var pulse = sin(_wavering_pulse_timer) * 0.5 + 0.5
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			var border_color = COLOR_BORDER_WAVERING
			border_color.a = 0.6 + pulse * 0.4
			style.border_color = border_color
			modulate = Color.WHITE

		CardState.ROUTING:
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			style.border_color = COLOR_BORDER_ROUTING
			modulate = COLOR_MODULATE_ROUTING

		CardState.DEAD:
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.2, 0.2, 0.2, 0.5)
			modulate = COLOR_MODULATE_DEAD

	add_theme_stylebox_override("panel", style)


func _on_regiment_attacked(attacker: Regiment, defender: Regiment, damage: int):
	if defender == regiment:
		_damage_flash_timer = DAMAGE_FLASH_DURATION


func _on_regiment_routing(reg: Regiment):
	if reg == regiment:
		card_state = CardState.ROUTING


func _on_regiment_rallied(reg: Regiment):
	if reg == regiment:
		card_state = CardState.NORMAL


# === CHEVRON BADGES (Task 2) ===

func _update_chevrons():
	# Clear existing chevrons
	for child in chevron_container.get_children():
		child.queue_free()

	if not regiment or not regiment.veterancy:
		return

	var level: int = regiment.veterancy.current_level
	if level == 0:
		return  # FRESH - no chevrons

	var color: Color = CHEVRON_COLORS.get(level, Color.GOLD)

	for i in range(level):
		var chevron = _create_chevron(color)
		chevron_container.add_child(chevron)


func _create_chevron(color: Color) -> Control:
	# Create a simple chevron/triangle badge
	var badge = Panel.new()
	badge.custom_minimum_size = Vector2(10, 10)

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	badge.add_theme_stylebox_override("panel", style)

	# Add a "^" symbol for chevron look
	var lbl = Label.new()
	lbl.text = "^"
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(lbl)

	return badge


# === STATUS ICONS (Task 3) ===

func _update_status_icons():
	# Clear existing status icons
	for child in status_container.get_children():
		child.queue_free()

	if not regiment:
		return

	# Check each status and add icons
	if regiment.is_braced:
		_add_status_icon("B", COLOR_STATUS_BRACED, "Braced")

	if regiment.has_charged and regiment.state == Regiment.State.MARCHING:
		_add_status_icon("!", COLOR_STATUS_CHARGING, "Charging")

	if regiment.inspire_active:
		_add_status_icon("*", COLOR_STATUS_INSPIRED, "Inspired")

	if regiment.hold_fire:
		_add_status_icon("X", COLOR_STATUS_HOLD_FIRE, "Hold Fire")


func _add_status_icon(letter: String, color: Color, tooltip: String):
	var icon = Panel.new()
	icon.custom_minimum_size = Vector2(12, 12)
	icon.tooltip_text = tooltip

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	icon.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.text = letter
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.add_child(lbl)

	status_container.add_child(icon)


# === MORALE DISPLAY (Task 4) ===

func _update_morale_display():
	if not regiment:
		return

	var morale = regiment.current_morale
	morale_bar.value = morale

	# Update color based on morale state
	var morale_style = StyleBoxFlat.new()
	if morale >= MORALE_STEADY_THRESHOLD:
		morale_style.bg_color = COLOR_MORALE_STEADY
	elif morale >= MORALE_WAVERING_THRESHOLD:
		morale_style.bg_color = COLOR_MORALE_WAVERING
	elif morale >= MORALE_SHAKEN_THRESHOLD:
		morale_style.bg_color = COLOR_MORALE_SHAKEN
	else:
		morale_style.bg_color = COLOR_MORALE_BROKEN

	morale_bar.add_theme_stylebox_override("fill", morale_style)

	# Update tooltip with morale breakdown
	var state_name = "Unknown"
	if morale >= MORALE_STEADY_THRESHOLD:
		state_name = "Steady"
	elif morale >= MORALE_WAVERING_THRESHOLD:
		state_name = "Wavering"
	elif morale >= MORALE_SHAKEN_THRESHOLD:
		state_name = "Shaken"
	else:
		state_name = "Broken"

	morale_bar.tooltip_text = "Morale: %.0f%% (%s)" % [morale, state_name]


# === ABILITY COOLDOWNS (Task 5) ===

func _update_ability_cooldowns():
	# Clear existing badges
	for child in ability_cooldown_container.get_children():
		child.queue_free()

	if not regiment or not regiment.abilities:
		return

	# Check each ability for cooldown
	for ability in regiment.abilities.available_abilities:
		var ratio = regiment.abilities.get_cooldown_ratio(ability)
		if ratio > 0:
			var data = AbilityType.get_ability_data(ability)
			var remaining = ratio * data.get("cooldown", 0.0)
			var badge = _create_cooldown_badge(remaining)
			ability_cooldown_container.add_child(badge)


func _create_cooldown_badge(seconds: float) -> Control:
	var badge = Panel.new()
	badge.custom_minimum_size = Vector2(14, 14)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	style.set_corner_radius_all(7)  # Circular
	badge.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.text = "%.0f" % seconds
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(lbl)

	return badge


# === EXISTING FUNCTIONALITY ===

func _update_display():
	if not regiment or not regiment.data:
		return

	var health_pct = (float(regiment.current_soldiers) / float(regiment.data.max_soldiers)) * 100
	health_bar.value = health_pct

	soldier_count_label.text = "%d / %d" % [regiment.current_soldiers, regiment.data.max_soldiers]

	# Update ammo display for ranged units
	if regiment.data.max_ammo > 0:
		var ammo_ratio: float = float(regiment.current_ammo) / float(regiment.data.max_ammo)
		ammo_bar.value = regiment.current_ammo
		ammo_label.text = "%d / %d" % [regiment.current_ammo, regiment.data.max_ammo]

		# Update ammo bar color based on ammo level
		var ammo_style = StyleBoxFlat.new()
		if regiment.current_ammo <= 0:
			ammo_style.bg_color = Color(0.8, 0.2, 0.2)
			ammo_warning_label.visible = true
			ammo_label.visible = false
			_ammo_warning_active = true

			if not _ammo_empty_warning_played:
				_ammo_empty_warning_played = true
				_play_ammo_warning_sound("ammo_empty")

		elif ammo_ratio <= AMMO_LOW_THRESHOLD:
			ammo_style.bg_color = Color(0.9, 0.6, 0.1)
			ammo_warning_label.visible = false
			ammo_label.visible = true
			_ammo_warning_active = true

			if not _ammo_low_warning_played:
				_ammo_low_warning_played = true
				_play_ammo_warning_sound("ammo_low")

		else:
			ammo_style.bg_color = Color(0.3, 0.7, 0.9)
			ammo_warning_label.visible = false
			ammo_label.visible = true
			_ammo_warning_active = false

		ammo_bar.add_theme_stylebox_override("fill", ammo_style)

	# Update health bar color based on health
	var health_style = StyleBoxFlat.new()
	if health_pct > 60:
		health_style.bg_color = Color(0.2, 0.8, 0.2)
	elif health_pct > 30:
		health_style.bg_color = Color(0.9, 0.7, 0.2)
	else:
		health_style.bg_color = Color(0.8, 0.2, 0.2)
	health_bar.add_theme_stylebox_override("fill", health_style)


func _update_ammo_warning(delta: float):
	if not _ammo_warning_active or not regiment or regiment.data.max_ammo <= 0:
		ammo_bar.modulate = Color.WHITE
		return

	_ammo_warning_timer += delta * AMMO_WARNING_FLASH_SPEED * TAU
	var flash_intensity: float = (sin(_ammo_warning_timer) + 1.0) * 0.5

	if regiment.current_ammo <= 0:
		ammo_bar.modulate = Color(1.0, 0.5 + flash_intensity * 0.5, 0.5 + flash_intensity * 0.5)
		ammo_warning_label.modulate = Color(1.0, 0.3 + flash_intensity * 0.7, 0.3 + flash_intensity * 0.7)
	else:
		ammo_bar.modulate = Color(1.0 + flash_intensity * 0.3, 1.0, 1.0)


func _play_ammo_warning_sound(event_name: String):
	var audio_manager: Node = _find_audio_manager()
	if audio_manager and audio_manager.has_method("play_morale_event"):
		audio_manager.play_morale_event(event_name)


func _find_audio_manager() -> Node:
	var managers = get_tree().get_nodes_in_group("audio_manager")
	if managers.size() > 0:
		return managers[0]
	for node in get_tree().root.get_children():
		if node is AudioManager:
			return node
		var found = _find_audio_manager_recursive(node)
		if found:
			return found
	return null


func _find_audio_manager_recursive(parent: Node) -> Node:
	for child in parent.get_children():
		if child is AudioManager:
			return child
		var found = _find_audio_manager_recursive(child)
		if found:
			return found
	return null


func set_selected(selected: bool):
	is_selected = selected
	# State update will handle visuals in _process


func _update_selection_visual():
	# Now handled by card state system
	pass


func _on_mouse_entered():
	if card_state == CardState.NORMAL:
		modulate = Color(1.2, 1.2, 1.2)


func _on_mouse_exited():
	if card_state == CardState.NORMAL:
		modulate = Color.WHITE


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				card_clicked.emit(regiment)
				# Center camera on the regiment when card is clicked
				_center_camera_on_regiment()
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				card_right_clicked.emit(regiment)


func _center_camera_on_regiment():
	"""Center the battle camera on this regiment's position."""
	if not regiment or not is_instance_valid(regiment):
		return

	# Find the battle camera
	var camera = _find_battle_camera()
	if camera and camera.has_method("center_on_regiment"):
		camera.center_on_regiment(regiment)


func _find_battle_camera() -> Camera3D:
	"""Find the battle camera in the scene."""
	var cameras = get_tree().get_nodes_in_group("battle_camera")
	if cameras.size() > 0:
		return cameras[0]

	# Fallback: search for Camera3D with the script
	var viewport = get_viewport()
	if viewport:
		var camera = viewport.get_camera_3d()
		if camera:
			return camera

	return null
