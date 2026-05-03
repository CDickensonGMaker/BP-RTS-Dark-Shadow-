class_name BattleLog
extends Control

## Scrolling battle log showing recent combat events.
## Displays routing, rallying, kills, flanking, charges, and abilities.
## Toggle visibility with Tab key.

# Configuration
const MAX_LINES: int = 50  # Total lines stored
const VISIBLE_LINES: int = 10  # Lines visible at once
const LINE_HEIGHT: int = 16
const PANEL_WIDTH: int = 320
const PANEL_HEIGHT: int = 170

# Colors matching dark fantasy theme
const COLOR_PANEL_BG = Color(0.06, 0.05, 0.04, 0.85)
const COLOR_PANEL_BORDER = Color(0.5, 0.4, 0.3, 0.8)
const COLOR_GOLD = Color(0.85, 0.7, 0.4, 1.0)

# Event colors (BBCode hex format)
const COLOR_ROUTING = "ff4444"      # Red
const COLOR_RALLIED = "44ff66"      # Green
const COLOR_KILLS = "dddddd"        # White
const COLOR_FLANKED = "ff9944"      # Orange
const COLOR_CHARGE = "ffdd44"       # Yellow
const COLOR_ABILITY = "4499ff"      # Blue
const COLOR_TIMESTAMP = "888877"    # Dim gold

# UI elements
var panel: Panel
var scroll_container: ScrollContainer
var rich_text: RichTextLabel
var title_label: Label

# State
var log_entries: Array[String] = []
var battle_start_time: float = 0.0
var is_visible: bool = true


func _ready():
	_setup_ui()
	_connect_signals()


func _setup_ui():
	# Main panel - bottom left, above selected unit panel
	panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 10
	panel.offset_right = 10 + PANEL_WIDTH
	panel.offset_top = -285 - PANEL_HEIGHT  # Above the selected unit panel
	panel.offset_bottom = -280

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_PANEL_BG
	panel_style.border_color = COLOR_PANEL_BORDER
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	# Title bar
	title_label = Label.new()
	title_label.text = "Battle Log [Tab]"
	title_label.offset_left = 8
	title_label.offset_top = 4
	title_label.offset_right = PANEL_WIDTH - 8
	title_label.offset_bottom = 22
	title_label.add_theme_font_size_override("font_size", 12)
	title_label.add_theme_color_override("font_color", COLOR_GOLD)
	panel.add_child(title_label)

	# Separator line
	var separator = ColorRect.new()
	separator.color = COLOR_PANEL_BORDER
	separator.offset_left = 4
	separator.offset_top = 24
	separator.offset_right = PANEL_WIDTH - 4
	separator.offset_bottom = 25
	panel.add_child(separator)

	# Scroll container
	scroll_container = ScrollContainer.new()
	scroll_container.offset_left = 4
	scroll_container.offset_top = 28
	scroll_container.offset_right = PANEL_WIDTH - 4
	scroll_container.offset_bottom = PANEL_HEIGHT - 4
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll_container)

	# Rich text label for colored messages
	rich_text = RichTextLabel.new()
	rich_text.bbcode_enabled = true
	rich_text.fit_content = true
	rich_text.scroll_following = true
	rich_text.custom_minimum_size = Vector2(PANEL_WIDTH - 20, 0)
	rich_text.add_theme_font_size_override("normal_font_size", 11)
	rich_text.add_theme_color_override("default_color", Color(0.8, 0.78, 0.7, 1.0))
	scroll_container.add_child(rich_text)


func _connect_signals():
	if not BattleSignals:
		push_warning("BattleLog: BattleSignals autoload not found")
		return

	# Morale events
	BattleSignals.regiment_routing.connect(_on_regiment_routing)
	BattleSignals.regiment_rallied.connect(_on_regiment_rallied)

	# Combat events
	BattleSignals.regiment_attacked.connect(_on_regiment_attacked)
	BattleSignals.unit_flanked.connect(_on_unit_flanked)
	BattleSignals.charge_impact.connect(_on_charge_impact)

	# Abilities
	BattleSignals.ability_used.connect(_on_ability_used)

	# Battle state
	BattleSignals.battle_started.connect(_on_battle_started)
	BattleSignals.battle_ended.connect(_on_battle_ended)
	BattleSignals.regiment_dead.connect(_on_regiment_dead)
	BattleSignals.general_died.connect(_on_general_died)


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			toggle_visibility()
			get_viewport().set_input_as_handled()


func toggle_visibility():
	is_visible = not is_visible
	panel.visible = is_visible


func _get_timestamp() -> String:
	var elapsed: float = Time.get_unix_time_from_system() - battle_start_time
	if elapsed < 0:
		elapsed = 0.0
	var minutes: int = int(elapsed) / 60
	var seconds: int = int(elapsed) % 60
	return "[color=#%s][%02d:%02d][/color] " % [COLOR_TIMESTAMP, minutes, seconds]


func _get_regiment_name(regiment: Regiment) -> String:
	if regiment and regiment.data:
		return regiment.data.regiment_name
	return "Unknown Unit"


func _add_log_entry(message: String):
	var timestamped: String = _get_timestamp() + message
	log_entries.append(timestamped)

	# Trim old entries
	while log_entries.size() > MAX_LINES:
		log_entries.pop_front()

	# Rebuild text
	rich_text.clear()
	for entry in log_entries:
		rich_text.append_text(entry + "\n")

	# Auto-scroll to bottom
	await get_tree().process_frame
	scroll_container.scroll_vertical = scroll_container.get_v_scroll_bar().max_value


# === Signal Handlers ===

func _on_battle_started():
	battle_start_time = Time.get_unix_time_from_system()
	log_entries.clear()
	rich_text.clear()
	_add_log_entry("[color=#%s]Battle has begun![/color]" % COLOR_GOLD)


func _on_battle_ended(result: Dictionary):
	var winner: String = result.get("winner", "Unknown")
	_add_log_entry("[color=#%s]Battle ended! Victor: %s[/color]" % [COLOR_GOLD, winner])


func _on_regiment_routing(regiment: Regiment):
	var name: String = _get_regiment_name(regiment)
	_add_log_entry("[color=#%s]%s is routing![/color]" % [COLOR_ROUTING, name])


func _on_regiment_rallied(regiment: Regiment):
	var name: String = _get_regiment_name(regiment)
	_add_log_entry("[color=#%s]%s has rallied![/color]" % [COLOR_RALLIED, name])


func _on_regiment_attacked(attacker: Regiment, defender: Regiment, damage: int):
	# Only log significant kills (not every hit)
	if damage >= 3:
		var attacker_name: String = _get_regiment_name(attacker)
		_add_log_entry("[color=#%s]%s killed %d enemies[/color]" % [COLOR_KILLS, attacker_name, damage])


func _on_unit_flanked(flanked: Regiment, flanker: Regiment, is_rear: bool):
	var flanker_name: String = _get_regiment_name(flanker)
	var flanked_name: String = _get_regiment_name(flanked)
	var flank_type: String = "rear-flanked" if is_rear else "flanked"
	_add_log_entry("[color=#%s]%s %s %s![/color]" % [COLOR_FLANKED, flanker_name, flank_type, flanked_name])


func _on_charge_impact(charger: Regiment, target: Regiment, was_braced: bool):
	var charger_name: String = _get_regiment_name(charger)
	var target_name: String = _get_regiment_name(target)
	if was_braced:
		_add_log_entry("[color=#%s]%s charged into %s (BRACED!)[/color]" % [COLOR_CHARGE, charger_name, target_name])
	else:
		_add_log_entry("[color=#%s]%s charged into %s![/color]" % [COLOR_CHARGE, charger_name, target_name])


func _on_ability_used(regiment: Regiment, ability: int):
	var name: String = _get_regiment_name(regiment)
	var ability_name: String = AbilityType.get_name(ability as AbilityType.Type)
	_add_log_entry("[color=#%s]%s used %s![/color]" % [COLOR_ABILITY, name, ability_name])


func _on_regiment_dead(regiment: Regiment):
	var name: String = _get_regiment_name(regiment)
	_add_log_entry("[color=#%s]%s has been destroyed![/color]" % [COLOR_ROUTING, name])


func _on_general_died(general):
	var general_name: String = "The General"
	if general and general.has_method("get_name"):
		general_name = general.get_name()
	elif general and "name" in general:
		general_name = general.name
	_add_log_entry("[color=#%s]%s has fallen![/color]" % [COLOR_ROUTING, general_name])
