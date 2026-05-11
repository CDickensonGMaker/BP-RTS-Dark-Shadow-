# Unit card UI element - displays regiment info like Total War
# Enhanced with: card states, rank chevrons, unit type icons, status indicators,
# improved morale display, and ability cooldown badges
class_name UnitCard
extends PanelContainer


signal card_clicked(regiment: Regiment)
signal card_right_clicked(regiment: Regiment)
signal card_shift_clicked(regiment: Regiment)  # Multi-select support (add to selection)
signal card_ctrl_clicked(regiment: Regiment)   # Toggle selection support

var regiment: Regiment
var is_selected: bool = false

# === PHASE 2: Simplified background ===
# State communicated via border color only, not background
# Removed STATE_BG_COLORS - was competing with morale bar for attention
const COLOR_BG_NEUTRAL = Color(0.12, 0.11, 0.10, 0.95)  # Neutral dark

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
const COLOR_STATUS_RUNNING = Color(0.3, 0.9, 0.5, 1.0)  # Green - running mode
const COLOR_STATUS_SHAKEN = Color(0.7, 0.5, 0.9, 1.0)   # Purple - hasn't fully recovered
const COLOR_STATUS_AIMING = Color(0.95, 0.6, 0.2, 1.0)  # Orange - artillery aiming
const COLOR_STATUS_RELOADING = Color(0.6, 0.6, 0.6, 1.0)  # Gray - artillery reloading

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
var chevron_container: HBoxContainer  # Phase 2: Hidden, will move to selected panel
var unit_type_edge: ColorRect  # Phase 2: 4px edge indicator for unit type
var status_container: HBoxContainer
var morale_bar_container: Control
var morale_threshold_markers: Array[ColorRect] = []
var morale_cap_marker: ColorRect  # Vertical notch showing morale cap
var morale_cap_shade: ColorRect   # Shaded region above cap
var ability_cooldown_container: HBoxContainer

# Artillery reload UI
var artillery_reload_container: VBoxContainer
var artillery_reload_bar: ProgressBar
var artillery_state_label: Label
var _cached_reload_style: StyleBoxFlat = null

# Ammo warning state
var _ammo_warning_active: bool = false
var _ammo_warning_timer: float = 0.0
var _ammo_empty_warning_played: bool = false
var _ammo_low_warning_played: bool = false
const AMMO_LOW_THRESHOLD: float = 0.25  # 25%
const AMMO_WARNING_FLASH_SPEED: float = 4.0  # Flashes per second

# === CACHED STYLEBOXES (Performance Optimization) ===
# These are created once and reused to avoid per-frame allocations
var _cached_morale_style: StyleBoxFlat = null
var _cached_health_style: StyleBoxFlat = null
var _cached_ammo_style: StyleBoxFlat = null
var _cached_panel_style: StyleBoxFlat = null

# === STATE HASHES FOR DIRTY CHECKING ===
# Only rebuild UI elements when underlying state actually changes
var _last_chevron_level: int = -1
var _last_status_hash: int = -1  # Bitmask: braced|charging|inspired|hold_fire
var _last_morale_band: int = -1  # 0=broken, 1=shaken, 2=wavering, 3=steady
var _last_health_band: int = -1  # 0=critical, 1=low, 2=healthy
var _last_ammo_band: int = -1    # 0=empty, 1=low, 2=normal
var _last_card_state: CardState = CardState.NORMAL
var _last_ability_hash: int = -1

# === THROTTLED UPDATE TIMER ===
var _slow_update_timer: float = 0.0
const SLOW_UPDATE_INTERVAL: float = 0.25  # 4Hz instead of 60Hz for non-critical updates


func _ready():
	_setup_ui()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	# Connect to battle signals for card state updates
	if BattleSignals:
		BattleSignals.regiment_attacked.connect(_on_regiment_attacked)
		BattleSignals.regiment_routing.connect(_on_regiment_routing)
		BattleSignals.regiment_rallied.connect(_on_regiment_rallied)
		BattleSignals.stance_changed.connect(_on_stance_changed)
		BattleSignals.formation_type_changed.connect(_on_formation_changed)
		BattleSignals.ability_ready.connect(_on_ability_ready)


func _setup_ui():
	# Unit cards: 85px wide, 145px tall for better readability
	custom_minimum_size = Vector2(85, 145)
	# Ensure this card captures mouse clicks
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Phase 2: Main layout is HBox with [type edge | content]
	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 0)
	main_hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(main_hbox)

	# Unit type edge (4px left border colored by type)
	unit_type_edge = ColorRect.new()
	unit_type_edge.custom_minimum_size = Vector2(4, 0)
	unit_type_edge.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_type_edge.color = Color(0.4, 0.5, 0.7, 1.0)  # Default infantry
	unit_type_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_hbox.add_child(unit_type_edge)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Children should pass mouse events to parent (this card)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	main_hbox.add_child(vbox)

	# Portrait area with faction color background
	var portrait_container = Control.new()
	portrait_container.custom_minimum_size = Vector2(75, 55)  # Taller portrait
	portrait_container.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(portrait_container)

	portrait_rect = TextureRect.new()
	portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	portrait_container.add_child(portrait_rect)

	# Phase 1: Overlay surface for badges (anchored instead of absolute position)
	var overlay_surface = Control.new()
	overlay_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_container.add_child(overlay_surface)

	# === CHEVRON BADGES - Phase 2: Hidden (moved to selected unit panel) ===
	chevron_container = HBoxContainer.new()
	chevron_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	chevron_container.offset_left = 2
	chevron_container.offset_top = 2
	chevron_container.add_theme_constant_override("separation", 1)
	chevron_container.mouse_filter = Control.MOUSE_FILTER_PASS
	chevron_container.visible = false  # Phase 2: Hidden, chevrons shown in selected panel
	overlay_surface.add_child(chevron_container)

	# === UNIT TYPE EDGE (Phase 2) - 4px left edge colored by unit type ===
	# Replaces the corner badge with a subtle peripheral indicator
	unit_type_edge = ColorRect.new()
	unit_type_edge.custom_minimum_size = Vector2(4, 0)
	unit_type_edge.color = Color(0.4, 0.5, 0.7, 1.0)  # Default infantry blue
	unit_type_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Note: Added to card layout in setup(), not overlay

	# Unit name - readable size
	name_label = Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.clip_text = true  # Clip if too long
	name_label.custom_minimum_size.x = 76
	vbox.add_child(name_label)

	# === STATUS ICONS (Task 3) - compact row ===
	status_container = HBoxContainer.new()
	status_container.custom_minimum_size = Vector2(0, 10)
	status_container.add_theme_constant_override("separation", 1)
	status_container.alignment = BoxContainer.ALIGNMENT_CENTER
	status_container.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(status_container)

	# Soldier count - smaller
	soldier_count_label = Label.new()
	soldier_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soldier_count_label.add_theme_font_size_override("font_size", 8)
	vbox.add_child(soldier_count_label)

	# Health bar - visible
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(74, 6)
	health_bar.show_percentage = false
	health_bar.max_value = 100
	vbox.add_child(health_bar)

	# === MORALE BAR WITH THRESHOLDS (Task 4) ===
	morale_bar_container = Control.new()
	morale_bar_container.custom_minimum_size = Vector2(74, 6)
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

	# Morale cap shade (region above cap where recovery is diminished)
	morale_cap_shade = ColorRect.new()
	morale_cap_shade.custom_minimum_size = Vector2(0, 6)
	morale_cap_shade.color = Color(0.0, 0.0, 0.0, 0.4)  # Semi-transparent dark overlay
	morale_cap_shade.position = Vector2(74, 0)  # Start off-screen, will be positioned in update
	morale_cap_shade.size = Vector2(0, 6)
	morale_cap_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	morale_bar_container.add_child(morale_cap_shade)

	# Morale cap marker (vertical notch showing current cap)
	morale_cap_marker = ColorRect.new()
	morale_cap_marker.custom_minimum_size = Vector2(2, 6)
	morale_cap_marker.color = Color(1.0, 1.0, 1.0, 0.8)  # White notch
	morale_cap_marker.position = Vector2(74, 0)  # Will be positioned in update
	morale_cap_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	morale_bar_container.add_child(morale_cap_marker)

	# Ammo container (for ranged units) - compact
	ammo_container = VBoxContainer.new()
	ammo_container.add_theme_constant_override("separation", 0)
	ammo_container.visible = false
	vbox.add_child(ammo_container)

	# Ammo bar - visible
	ammo_bar = ProgressBar.new()
	ammo_bar.custom_minimum_size = Vector2(74, 5)
	ammo_bar.show_percentage = false
	ammo_bar.max_value = 100
	var ammo_bar_style = StyleBoxFlat.new()
	ammo_bar_style.bg_color = Color(0.3, 0.7, 0.9)
	ammo_bar.add_theme_stylebox_override("fill", ammo_bar_style)
	var ammo_bg_style = StyleBoxFlat.new()
	ammo_bg_style.bg_color = Color(0.15, 0.15, 0.2)
	ammo_bar.add_theme_stylebox_override("background", ammo_bg_style)
	ammo_container.add_child(ammo_bar)

	# Ammo count label - hide text, just use bar
	ammo_label = Label.new()
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_label.add_theme_font_size_override("font_size", 7)
	ammo_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	ammo_label.visible = false  # Hide text for skinnier look
	ammo_container.add_child(ammo_label)

	# OUT OF AMMO warning label - abbreviated
	ammo_warning_label = Label.new()
	ammo_warning_label.text = "NO AMMO"
	ammo_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_warning_label.add_theme_font_size_override("font_size", 6)
	ammo_warning_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	ammo_warning_label.visible = false
	ammo_container.add_child(ammo_warning_label)

	# === ARTILLERY RELOAD STATUS (prominent visual feedback) ===
	artillery_reload_container = VBoxContainer.new()
	artillery_reload_container.add_theme_constant_override("separation", 1)
	artillery_reload_container.visible = false  # Hidden for non-artillery
	vbox.add_child(artillery_reload_container)

	# Artillery state label (AIMING / RELOADING)
	artillery_state_label = Label.new()
	artillery_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	artillery_state_label.add_theme_font_size_override("font_size", 8)
	artillery_state_label.add_theme_color_override("font_color", COLOR_STATUS_AIMING)
	artillery_state_label.text = "AIMING"
	artillery_reload_container.add_child(artillery_state_label)

	# Artillery reload progress bar
	artillery_reload_bar = ProgressBar.new()
	artillery_reload_bar.custom_minimum_size = Vector2(74, 6)
	artillery_reload_bar.show_percentage = false
	artillery_reload_bar.min_value = 0
	artillery_reload_bar.max_value = 100
	artillery_reload_bar.value = 80  # Artillery starts 80% loaded
	var reload_bar_style = StyleBoxFlat.new()
	reload_bar_style.bg_color = COLOR_STATUS_AIMING  # Orange when reloading
	artillery_reload_bar.add_theme_stylebox_override("fill", reload_bar_style)
	var reload_bg_style = StyleBoxFlat.new()
	reload_bg_style.bg_color = Color(0.15, 0.15, 0.2)
	artillery_reload_bar.add_theme_stylebox_override("background", reload_bg_style)
	artillery_reload_container.add_child(artillery_reload_bar)

	# Cache the reload bar style for updates
	_cached_reload_style = reload_bar_style

	# === ABILITY COOLDOWN BADGES (Task 5) - bottom-right of card ===
	ability_cooldown_container = HBoxContainer.new()
	ability_cooldown_container.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ability_cooldown_container.offset_left = -32
	ability_cooldown_container.offset_right = -2
	ability_cooldown_container.offset_top = -14
	ability_cooldown_container.offset_bottom = -2
	ability_cooldown_container.add_theme_constant_override("separation", 1)
	ability_cooldown_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(ability_cooldown_container)  # Add to card, not portrait overlay

	# === CREATE CACHED STYLEBOXES (Performance Optimization) ===
	_cached_morale_style = StyleBoxFlat.new()
	_cached_morale_style.bg_color = COLOR_MORALE_STEADY

	_cached_health_style = StyleBoxFlat.new()
	_cached_health_style.bg_color = Color(0.2, 0.8, 0.2)

	_cached_ammo_style = StyleBoxFlat.new()
	_cached_ammo_style.bg_color = Color(0.3, 0.7, 0.9)

	# Panel style will be set in setup() from regiment faction color
	_cached_panel_style = null


func _add_morale_marker(threshold: float, color: Color):
	var marker = ColorRect.new()
	marker.custom_minimum_size = Vector2(1, 6)
	marker.color = color
	marker.color.a = 0.6
	# Scale threshold position for 74px wide bar
	marker.position = Vector2((threshold / 100.0) * 74 - 0.5, 0)
	morale_bar_container.add_child(marker)
	morale_threshold_markers.append(marker)


func setup(reg: Regiment):
	regiment = reg
	if not regiment:
		return

	# Abbreviate long names for skinnier cards
	var display_name: String = regiment.data.regiment_name
	if display_name.length() > 10:
		display_name = display_name.substr(0, 9) + "."
	name_label.text = display_name
	_setup_unit_type_badge()

	# Initialize cached panel style - will update color based on state
	_cached_panel_style = StyleBoxFlat.new()
	_cached_panel_style.bg_color = Color(0.25, 0.25, 0.25, 0.9)  # Neutral gray for all states
	_cached_panel_style.corner_radius_top_left = 3
	_cached_panel_style.corner_radius_top_right = 3
	_cached_panel_style.corner_radius_bottom_left = 3
	_cached_panel_style.corner_radius_bottom_right = 3
	_cached_panel_style.border_width_left = 1
	_cached_panel_style.border_width_right = 1
	_cached_panel_style.border_width_top = 1
	_cached_panel_style.border_width_bottom = 1
	_cached_panel_style.border_color = COLOR_BORDER_NORMAL
	add_theme_stylebox_override("panel", _cached_panel_style)

	# Reset dirty-check state for fresh regiment
	_last_chevron_level = -1
	_last_status_hash = -1
	_last_morale_band = -1
	_last_health_band = -1
	_last_ammo_band = -1
	_last_card_state = CardState.NORMAL
	_last_ability_hash = -1

	# Force initial update
	_update_display_throttled()

	# Show ammo container for ranged units
	if regiment.data.max_ammo > 0:
		ammo_container.visible = true
		ammo_bar.max_value = regiment.data.max_ammo
		_ammo_empty_warning_played = false
		_ammo_low_warning_played = false

	# Show artillery reload container for artillery units
	if regiment.data.unit_type == UnitType.Type.ARTILLERY:
		artillery_reload_container.visible = true

	# Build card tooltip with hatred info if applicable
	_update_card_tooltip()


func _setup_unit_type_edge():
	# Phase 2: Set edge color based on unit type (peripheral type indicator)
	if not regiment or not regiment.data:
		return

	var unit_type = regiment.data.unit_type
	var color = UNIT_TYPE_COLORS.get(unit_type, Color(0.5, 0.5, 0.5))
	unit_type_edge.color = color


# Legacy compatibility alias
func _setup_unit_type_badge():
	_setup_unit_type_edge()


func _process(delta: float):
	if not regiment:
		return

	# === 60Hz UPDATES (animations that need smooth playback) ===
	_update_card_state(delta)
	_update_ammo_warning(delta)

	# Apply card state visuals only when state actually changes
	if card_state != _last_card_state:
		_apply_card_state_visuals_cached()
		_last_card_state = card_state

	# === 4Hz THROTTLED UPDATES (non-critical visual updates) ===
	_slow_update_timer += delta
	if _slow_update_timer >= SLOW_UPDATE_INTERVAL:
		_slow_update_timer = 0.0
		_update_display_throttled()
		_update_chevrons_throttled()
		_update_status_icons_throttled()
		_update_morale_display_throttled()
		_update_ability_cooldowns_throttled()
		_update_artillery_reload_throttled()
		_update_state_background_color()


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


func _apply_card_state_visuals_cached():
	# Uses cached panel style - no duplicate() per frame
	if not _cached_panel_style:
		return

	match card_state:
		CardState.NORMAL:
			_cached_panel_style.border_width_left = 1
			_cached_panel_style.border_width_right = 1
			_cached_panel_style.border_width_top = 1
			_cached_panel_style.border_width_bottom = 1
			_cached_panel_style.border_color = COLOR_BORDER_NORMAL
			modulate = Color.WHITE

		CardState.SELECTED:
			_cached_panel_style.border_width_left = 3
			_cached_panel_style.border_width_right = 3
			_cached_panel_style.border_width_top = 3
			_cached_panel_style.border_width_bottom = 3
			_cached_panel_style.border_color = COLOR_BORDER_SELECTED
			modulate = Color.WHITE

		CardState.TAKING_DAMAGE:
			var flash_intensity = sin(_damage_flash_timer * DAMAGE_FLASH_SPEED) * 0.5 + 0.5
			_cached_panel_style.border_width_left = 4
			_cached_panel_style.border_width_right = 4
			_cached_panel_style.border_width_top = 4
			_cached_panel_style.border_width_bottom = 4
			var border_color = COLOR_BORDER_DAMAGE
			border_color.a = 0.7 + flash_intensity * 0.3
			_cached_panel_style.border_color = border_color
			modulate = Color(1.0 + flash_intensity * 0.2, 1.0, 1.0)

		CardState.WAVERING:
			var pulse = sin(_wavering_pulse_timer) * 0.5 + 0.5
			_cached_panel_style.border_width_left = 2
			_cached_panel_style.border_width_right = 2
			_cached_panel_style.border_width_top = 2
			_cached_panel_style.border_width_bottom = 2
			var border_color = COLOR_BORDER_WAVERING
			border_color.a = 0.6 + pulse * 0.4
			_cached_panel_style.border_color = border_color
			modulate = Color.WHITE

		CardState.ROUTING:
			_cached_panel_style.border_width_left = 2
			_cached_panel_style.border_width_right = 2
			_cached_panel_style.border_width_top = 2
			_cached_panel_style.border_width_bottom = 2
			_cached_panel_style.border_color = COLOR_BORDER_ROUTING
			modulate = COLOR_MODULATE_ROUTING

		CardState.DEAD:
			_cached_panel_style.border_width_left = 1
			_cached_panel_style.border_width_right = 1
			_cached_panel_style.border_width_top = 1
			_cached_panel_style.border_width_bottom = 1
			_cached_panel_style.border_color = Color(0.2, 0.2, 0.2, 0.5)
			modulate = COLOR_MODULATE_DEAD

	# Style is already applied - Godot will detect property changes automatically
	# No need to call add_theme_stylebox_override again


# Legacy function for compatibility - redirects to cached version
func _apply_card_state_visuals():
	_apply_card_state_visuals_cached()


func _on_regiment_attacked(attacker: Regiment, defender: Regiment, damage: int):
	if defender == regiment:
		_damage_flash_timer = DAMAGE_FLASH_DURATION


func _on_regiment_routing(reg: Regiment):
	if reg == regiment:
		card_state = CardState.ROUTING


func _on_regiment_rallied(reg: Regiment):
	if reg == regiment:
		card_state = CardState.NORMAL


func _on_stance_changed(reg: Node, _old_stance: int, new_stance: int) -> void:
	if reg != regiment:
		return
	_update_stance_indicator(new_stance)


func _on_formation_changed(reg: Node, _old_formation: int, new_formation: int) -> void:
	if reg != regiment:
		return
	_update_formation_indicator(new_formation)


func _on_ability_ready(reg: Node, ability_id: int) -> void:
	if reg != regiment:
		return
	_flash_ability_ready(ability_id)


func _update_stance_indicator(_stance: int) -> void:
	# Stance is already shown via status icons (braced, etc.)
	# This could be enhanced to show a stance badge
	pass


func _update_formation_indicator(_formation: int) -> void:
	# Formation changes trigger visual update in next _process tick
	# Could add a formation badge similar to unit type badge
	pass


func _flash_ability_ready(_ability_id: int) -> void:
	# Flash the ability cooldown badge to indicate ready
	# Create a brief visual pulse effect
	var tween := create_tween()
	tween.tween_property(ability_cooldown_container, "modulate", Color(1.5, 1.5, 0.5), 0.2)
	tween.tween_property(ability_cooldown_container, "modulate", Color.WHITE, 0.3)


# === CHEVRON BADGES (Task 2) ===

func _update_chevrons_throttled():
	if not regiment or not regiment.veterancy:
		return

	var level: int = regiment.veterancy.current_level

	# Skip if unchanged - dirty check
	if level == _last_chevron_level:
		return
	_last_chevron_level = level

	# Only now do we clear and rebuild
	for child in chevron_container.get_children():
		child.queue_free()

	if level == 0:
		return  # FRESH - no chevrons

	var color: Color = CHEVRON_COLORS.get(level, Color.GOLD)

	for i in range(level):
		var chevron = _create_chevron(color)
		chevron_container.add_child(chevron)


# Legacy function for compatibility
func _update_chevrons():
	_update_chevrons_throttled()


func _create_chevron(color: Color) -> Control:
	# Create a simple chevron/triangle badge - smaller for compact cards
	var badge = Panel.new()
	badge.custom_minimum_size = Vector2(8, 8)
	badge.mouse_filter = Control.MOUSE_FILTER_PASS

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(1)
	badge.add_theme_stylebox_override("panel", style)

	# Add a "^" symbol for chevron look
	var lbl = Label.new()
	lbl.text = "^"
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)

	return badge


# === STATUS ICONS (Task 3) ===

func _update_status_icons_throttled():
	if not regiment:
		return

	# Compute status bitmask for dirty checking
	var status_hash: int = 0
	if regiment.is_braced:
		status_hash |= 1
	if regiment.has_charged and regiment.state == Regiment.State.MARCHING:
		status_hash |= 2
	if regiment.inspire_active:
		status_hash |= 4
	if regiment.hold_fire:
		status_hash |= 8
	# Movement mode: bit 16 = running
	if regiment.leader and regiment.leader.move_mode == RegimentLeader.MoveMode.RUN:
		status_hash |= 16
	# Shaken: bit 32 = morale cap below 100 (hasn't fully recovered)
	if regiment.unit_morale and regiment.unit_morale.get_morale_cap() < 99.5:
		status_hash |= 32

	# Artillery firing state: bits 64 = AIMING, 128 = RELOADING
	if regiment.data and regiment.data.unit_type == UnitType.Type.ARTILLERY and regiment.firing:
		# Access the FiringState enum from RegimentFiring class
		var RegimentFiringClass = load("res://battle_system/ai/commander/regiment_firing.gd")
		if RegimentFiringClass and regiment.firing.has_method("get_firing_state"):
			var firing_state = regiment.firing.get_firing_state()
			if firing_state == RegimentFiringClass.FiringState.AIMING:
				status_hash |= 64
			elif firing_state == RegimentFiringClass.FiringState.RELOADING:
				status_hash |= 128

	# Skip if unchanged
	if status_hash == _last_status_hash:
		return
	_last_status_hash = status_hash

	# Only now do we clear and rebuild
	for child in status_container.get_children():
		child.queue_free()

	# Check each status and add icons
	if status_hash & 1:
		_add_status_icon("B", COLOR_STATUS_BRACED, "Braced")

	if status_hash & 2:
		_add_status_icon("!", COLOR_STATUS_CHARGING, "Charging")

	if status_hash & 4:
		_add_status_icon("*", COLOR_STATUS_INSPIRED, "Inspired")

	if status_hash & 8:
		_add_status_icon("X", COLOR_STATUS_HOLD_FIRE, "Hold Fire")

	if status_hash & 16:
		_add_status_icon("R", COLOR_STATUS_RUNNING, "Running (press R to toggle)")

	if status_hash & 32:
		var cap: float = regiment.unit_morale.get_morale_cap() if regiment.unit_morale else 100.0
		_add_status_icon("~", COLOR_STATUS_SHAKEN, "Shaken (cap: %.0f%% - hasn't fully recovered)" % cap)

	# Artillery firing states
	if status_hash & 64:
		_add_status_icon("A", COLOR_STATUS_AIMING, "AIMING - Ready to fire")

	if status_hash & 128:
		_add_status_icon("R", COLOR_STATUS_RELOADING, "RELOADING")


# Legacy function for compatibility
func _update_status_icons():
	_update_status_icons_throttled()


func _add_status_icon(letter: String, color: Color, tooltip: String):
	var icon = Panel.new()
	icon.custom_minimum_size = Vector2(10, 10)  # Smaller for skinnier cards
	icon.tooltip_text = tooltip
	icon.mouse_filter = Control.MOUSE_FILTER_PASS

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	icon.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.text = letter
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(lbl)

	status_container.add_child(icon)


# === MORALE DISPLAY (Task 4) ===

func _update_morale_display_throttled():
	if not regiment:
		return

	var morale = regiment.current_morale
	morale_bar.value = morale

	# Get morale cap from unit_morale component
	var cap: float = 100.0
	if regiment.unit_morale:
		cap = regiment.unit_morale.get_morale_cap()

	# Update cap marker position (74px bar width)
	if morale_cap_marker:
		var cap_x: float = (cap / 100.0) * 74.0 - 1.0  # -1 to center the 2px marker
		morale_cap_marker.position.x = cap_x
		# Only show cap marker if cap < 100
		morale_cap_marker.visible = cap < 99.5

	# Update cap shade (region above cap)
	if morale_cap_shade:
		var cap_x: float = (cap / 100.0) * 74.0
		morale_cap_shade.position.x = cap_x
		morale_cap_shade.size.x = 74.0 - cap_x
		morale_cap_shade.visible = cap < 99.5

	# Determine morale band (0-3) for dirty checking
	var morale_band: int
	var state_name: String
	if morale >= MORALE_STEADY_THRESHOLD:
		morale_band = 3
		state_name = "Steady"
	elif morale >= MORALE_WAVERING_THRESHOLD:
		morale_band = 2
		state_name = "Wavering"
	elif morale >= MORALE_SHAKEN_THRESHOLD:
		morale_band = 1
		state_name = "Shaken"
	else:
		morale_band = 0
		state_name = "Broken"

	# Only update style if band changed
	if morale_band != _last_morale_band:
		_last_morale_band = morale_band
		match morale_band:
			3: _cached_morale_style.bg_color = COLOR_MORALE_STEADY
			2: _cached_morale_style.bg_color = COLOR_MORALE_WAVERING
			1: _cached_morale_style.bg_color = COLOR_MORALE_SHAKEN
			0: _cached_morale_style.bg_color = COLOR_MORALE_BROKEN
		morale_bar.add_theme_stylebox_override("fill", _cached_morale_style)

	# Tooltip shows current morale and cap
	if cap < 99.5:
		morale_bar.tooltip_text = "Morale: %.0f / %.0f (cap) - %s" % [morale, cap, state_name]
	else:
		morale_bar.tooltip_text = "Morale: %.0f%% (%s)" % [morale, state_name]


# Legacy function for compatibility
func _update_morale_display():
	_update_morale_display_throttled()


# === ARTILLERY RELOAD DISPLAY ===

func _update_artillery_reload_throttled():
	## Update artillery reload bar and state label.
	## Shows AIMING (ready to fire) or RELOADING with progress bar.
	if not regiment or not regiment.data:
		return

	# Only for artillery units
	if regiment.data.unit_type != UnitType.Type.ARTILLERY:
		return

	if not artillery_reload_container or not artillery_reload_bar or not artillery_state_label:
		return

	# Check if regiment has firing component
	if not regiment.firing:
		artillery_state_label.text = "NO FIRING"
		artillery_state_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		artillery_reload_bar.value = 0
		# DEBUG: Artillery has no firing component
		if Engine.get_process_frames() % 60 == 0:
			print("[UNIT CARD DEBUG] %s: No firing component!" % (regiment.data.regiment_name if regiment.data else "?"))
		return

	# Get firing state and progress
	var RegimentFiringClass = load("res://battle_system/ai/commander/regiment_firing.gd")
	if not RegimentFiringClass or not regiment.firing.has_method("get_firing_state"):
		return

	var firing_state = regiment.firing.get_firing_state()
	var reload_progress: float = regiment.firing.get_reload_progress() * 100.0 if regiment.firing.has_method("get_reload_progress") else 0.0

	# Update bar value
	artillery_reload_bar.value = reload_progress

	# Update label and colors based on state
	if firing_state == RegimentFiringClass.FiringState.AIMING:
		artillery_state_label.text = "⚡ READY"
		artillery_state_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.2))  # Green
		if _cached_reload_style:
			_cached_reload_style.bg_color = Color(0.2, 0.9, 0.2)  # Green fill
			artillery_reload_bar.add_theme_stylebox_override("fill", _cached_reload_style)
	elif firing_state == RegimentFiringClass.FiringState.RELOADING:
		artillery_state_label.text = "⟳ RELOAD"
		artillery_state_label.add_theme_color_override("font_color", COLOR_STATUS_AIMING)  # Orange
		if _cached_reload_style:
			_cached_reload_style.bg_color = COLOR_STATUS_AIMING  # Orange fill
			artillery_reload_bar.add_theme_stylebox_override("fill", _cached_reload_style)
	else:
		# IDLE state
		artillery_state_label.text = "IDLE"
		artillery_state_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		if _cached_reload_style:
			_cached_reload_style.bg_color = Color(0.4, 0.4, 0.4)
			artillery_reload_bar.add_theme_stylebox_override("fill", _cached_reload_style)

	# Update tooltip with detailed info
	artillery_reload_bar.tooltip_text = "%s (%.0f%% loaded)" % [artillery_state_label.text, reload_progress]


# === PHASE 2: Neutral background (state via border only) ===
func _update_state_background_color():
	# Phase 2: Use neutral background - state is communicated via border color
	# This avoids competing with morale bar for attention
	if not _cached_panel_style:
		return
	# Use constant neutral background
	_cached_panel_style.bg_color = COLOR_BG_NEUTRAL


# === ABILITY COOLDOWNS (Task 5) ===

func _update_ability_cooldowns_throttled():
	if not regiment or not regiment.abilities:
		return

	# Compute hash of cooldown states for dirty checking
	var ability_hash: int = 0
	for ability in regiment.abilities.available_abilities:
		var ratio = regiment.abilities.get_cooldown_ratio(ability)
		# Hash: ability ID + quantized ratio (4 levels: 0, 0.33, 0.66, 1.0)
		var quantized: int = int(ratio * 3)
		ability_hash = ability_hash * 17 + ability * 4 + quantized

	# Skip if unchanged
	if ability_hash == _last_ability_hash:
		return
	_last_ability_hash = ability_hash

	# Only now do we clear and rebuild
	for child in ability_cooldown_container.get_children():
		child.queue_free()

	# Check each ability for cooldown
	for ability in regiment.abilities.available_abilities:
		var ratio = regiment.abilities.get_cooldown_ratio(ability)
		if ratio > 0:
			var data = AbilityType.get_ability_data(ability)
			var remaining = ratio * data.get("cooldown", 0.0)
			var badge = _create_cooldown_badge(remaining)
			ability_cooldown_container.add_child(badge)


# Legacy function for compatibility
func _update_ability_cooldowns():
	_update_ability_cooldowns_throttled()


func _create_cooldown_badge(seconds: float) -> Control:
	var badge = Panel.new()
	badge.custom_minimum_size = Vector2(12, 12)  # Smaller for compact cards

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	style.set_corner_radius_all(6)  # Circular
	badge.add_theme_stylebox_override("panel", style)

	var lbl = Label.new()
	lbl.text = "%.0f" % seconds
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	badge.add_child(lbl)

	return badge


# === EXISTING FUNCTIONALITY ===

func _update_display_throttled():
	if not regiment or not regiment.data:
		return

	var health_pct = (float(regiment.current_soldiers) / float(regiment.data.max_soldiers)) * 100
	health_bar.value = health_pct

	soldier_count_label.text = "%d / %d" % [regiment.current_soldiers, regiment.data.max_soldiers]

	# Determine health band for dirty checking
	var health_band: int
	if health_pct > 60:
		health_band = 2
	elif health_pct > 30:
		health_band = 1
	else:
		health_band = 0

	# Only update health style if band changed
	if health_band != _last_health_band:
		_last_health_band = health_band
		match health_band:
			2: _cached_health_style.bg_color = Color(0.2, 0.8, 0.2)
			1: _cached_health_style.bg_color = Color(0.9, 0.7, 0.2)
			0: _cached_health_style.bg_color = Color(0.8, 0.2, 0.2)
		health_bar.add_theme_stylebox_override("fill", _cached_health_style)

	# Update ammo display for ranged units
	if regiment.data.max_ammo > 0:
		var ammo_ratio: float = float(regiment.current_ammo) / float(regiment.data.max_ammo)
		ammo_bar.value = regiment.current_ammo
		ammo_label.text = "%d / %d" % [regiment.current_ammo, regiment.data.max_ammo]

		# Determine ammo band for dirty checking
		var ammo_band: int
		if regiment.current_ammo <= 0:
			ammo_band = 0
		elif ammo_ratio <= AMMO_LOW_THRESHOLD:
			ammo_band = 1
		else:
			ammo_band = 2

		# Only update ammo style if band changed
		if ammo_band != _last_ammo_band:
			_last_ammo_band = ammo_band
			match ammo_band:
				0:
					_cached_ammo_style.bg_color = Color(0.8, 0.2, 0.2)
					ammo_warning_label.visible = true
					ammo_label.visible = false
					_ammo_warning_active = true
					if not _ammo_empty_warning_played:
						_ammo_empty_warning_played = true
						_play_ammo_warning_sound("ammo_empty")
				1:
					_cached_ammo_style.bg_color = Color(0.9, 0.6, 0.1)
					ammo_warning_label.visible = false
					ammo_label.visible = true
					_ammo_warning_active = true
					if not _ammo_low_warning_played:
						_ammo_low_warning_played = true
						_play_ammo_warning_sound("ammo_low")
				2:
					_cached_ammo_style.bg_color = Color(0.3, 0.7, 0.9)
					ammo_warning_label.visible = false
					ammo_label.visible = true
					_ammo_warning_active = false
			ammo_bar.add_theme_stylebox_override("fill", _cached_ammo_style)


# Legacy function for compatibility
func _update_display():
	_update_display_throttled()


func _update_card_tooltip():
	## Build the main card tooltip including hatred info for enemy units.
	if not regiment or not regiment.data:
		return

	var tooltip_lines: PackedStringArray = []
	tooltip_lines.append(regiment.data.regiment_name)

	# Add unit type (convert enum to string)
	var unit_type_name: String = UnitType.Type.keys()[regiment.data.unit_type]
	tooltip_lines.append("Type: %s" % unit_type_name.capitalize())

	# Add hatred tooltip for enemy regiments (player looking at enemy unit)
	if not regiment.is_player_controlled and CombatManager and CombatManager.hatred_calculator:
		var hatred_tip: String = CombatManager.hatred_calculator.get_hatred_tooltip(true, regiment)
		if not hatred_tip.is_empty():
			tooltip_lines.append(hatred_tip)

	tooltip_text = "\n".join(tooltip_lines)


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
				# Ctrl+click for toggle selection
				if Input.is_key_pressed(KEY_CTRL):
					card_ctrl_clicked.emit(regiment)
				# Shift+click for add to selection
				elif Input.is_key_pressed(KEY_SHIFT):
					card_shift_clicked.emit(regiment)
				else:
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
