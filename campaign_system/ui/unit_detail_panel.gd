# Popup panel showing detailed unit stats when right-clicking a unit card.
# Displays veterancy, equipment bonuses, abilities, and battle history.
class_name UnitDetailPanel
extends Control


# Panel styling
const PANEL_WIDTH := 320
const PANEL_PADDING := 12
const BG_COLOR := Color(0.08, 0.06, 0.05, 0.95)
const BORDER_COLOR := Color(0.6, 0.5, 0.3, 1.0)
const TEXT_COLOR := Color(0.95, 0.92, 0.85, 1.0)
const STAT_COLOR := Color(0.7, 0.8, 0.6, 1.0)
const BONUS_COLOR := Color(0.4, 0.8, 0.4, 1.0)
const PENALTY_COLOR := Color(0.8, 0.4, 0.4, 1.0)

var current_regiment: Resource = null
var panel_container: PanelContainer = null
var content_vbox: VBoxContainer = null


func _ready() -> void:
	_setup_panel()
	visible = false


func _setup_panel() -> void:
	# Create panel container
	panel_container = PanelContainer.new()
	panel_container.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(PANEL_PADDING)
	panel_container.add_theme_stylebox_override("panel", style)

	add_child(panel_container)

	# Content container
	content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 6)
	panel_container.add_child(content_vbox)


func show_for_regiment(regiment: Resource, screen_position: Vector2) -> void:
	current_regiment = regiment
	_populate_content()
	_position_panel(screen_position)
	visible = true


func _position_panel(screen_position: Vector2) -> void:
	# Position panel near click, but keep on screen
	var viewport_size := get_viewport_rect().size
	var panel_size := panel_container.size

	var pos := screen_position + Vector2(20, 0)

	# Keep on screen horizontally
	if pos.x + panel_size.x > viewport_size.x:
		pos.x = screen_position.x - panel_size.x - 20

	# Keep on screen vertically
	if pos.y + panel_size.y > viewport_size.y:
		pos.y = viewport_size.y - panel_size.y - 10

	pos.x = maxf(10, pos.x)
	pos.y = maxf(10, pos.y)

	global_position = pos


func _populate_content() -> void:
	# Clear existing content
	for child in content_vbox.get_children():
		child.queue_free()

	if not current_regiment:
		return

	# Unit name and type
	_add_header()

	# Separator
	_add_separator()

	# Strength
	_add_strength_section()

	# Separator
	_add_separator()

	# Combat stats
	_add_stats_section()

	# Equipment bonuses
	if _has_equipment_bonuses():
		_add_separator()
		_add_equipment_section()

	# Veterancy
	_add_separator()
	_add_veterancy_section()

	# Abilities
	if _has_abilities():
		_add_separator()
		_add_abilities_section()

	# Battle history
	_add_separator()
	_add_history_section()

	# Upkeep
	_add_separator()
	_add_upkeep_section()


func _add_header() -> void:
	var name_label := Label.new()
	name_label.text = current_regiment.regiment_name
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	name_label.add_theme_font_size_override("font_size", 18)
	content_vbox.add_child(name_label)

	var type_label := Label.new()
	var category: String = _get_unit_category()
	type_label.text = category.capitalize()
	type_label.add_theme_color_override("font_color", STAT_COLOR)
	content_vbox.add_child(type_label)


func _get_unit_category() -> String:
	# Check meta first, then unit_type enum
	if current_regiment.has_meta("unit_category"):
		return current_regiment.get_meta("unit_category")
	if "unit_type" in current_regiment:
		match current_regiment.unit_type:
			UnitType.Type.INFANTRY:
				return "infantry"
			UnitType.Type.RANGED:
				return "ranged"
			UnitType.Type.CAVALRY:
				return "cavalry"
			_:
				return "special"
	return "infantry"


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.modulate = BORDER_COLOR
	content_vbox.add_child(sep)


func _add_strength_section() -> void:
	var current: int = current_regiment.current_soldiers
	var max_soldiers: int = current_regiment.max_soldiers
	var percent := (float(current) / max_soldiers) * 100.0

	var strength_label := Label.new()
	strength_label.text = "Strength: %d / %d (%d%%)" % [current, max_soldiers, int(percent)]

	if percent < 50:
		strength_label.add_theme_color_override("font_color", PENALTY_COLOR)
	elif percent < 75:
		strength_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	else:
		strength_label.add_theme_color_override("font_color", TEXT_COLOR)

	content_vbox.add_child(strength_label)

	# Health bar
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max_soldiers
	bar.value = current
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	content_vbox.add_child(bar)


func _add_stats_section() -> void:
	var header := Label.new()
	header.text = "Combat Stats"
	header.add_theme_color_override("font_color", TEXT_COLOR)
	content_vbox.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	content_vbox.add_child(grid)

	# Get stats - use actual RegimentData properties when available
	var attack: int = current_regiment.attack if "attack" in current_regiment else current_regiment.get_meta("melee_attack", 10)
	var defense: int = current_regiment.defense if "defense" in current_regiment else current_regiment.get_meta("melee_defense", 10)
	var armor: int = current_regiment.armor if "armor" in current_regiment else current_regiment.get_meta("armor", 5)
	var morale: int = int(current_regiment.base_morale) if "base_morale" in current_regiment else current_regiment.get_meta("base_morale", 70)

	# Equipment bonuses
	var attack_bonus: int = current_regiment.get_meta("attack_bonus", 0)
	var armor_bonus: int = current_regiment.get_meta("armor_bonus", 0)

	_add_stat_row(grid, "Attack", attack, attack_bonus)
	_add_stat_row(grid, "Defense", defense, 0)
	_add_stat_row(grid, "Armor", armor, armor_bonus)
	_add_stat_row(grid, "Morale", morale, 0)

	# Ranged stats if applicable - check actual RegimentData properties
	var has_ranged: bool = false
	if "ballistic_skill" in current_regiment and current_regiment.ballistic_skill > 0:
		has_ranged = true
	elif current_regiment.has_meta("ranged_attack"):
		has_ranged = true

	if has_ranged:
		var ranged: int = current_regiment.ballistic_skill if "ballistic_skill" in current_regiment else current_regiment.get_meta("ranged_attack", 0)
		var range_dist: float = current_regiment.range_distance if "range_distance" in current_regiment else current_regiment.get_meta("range", 100)
		_add_stat_row(grid, "Ranged", ranged, 0)
		_add_stat_row(grid, "Range", int(range_dist), 0)


func _add_stat_row(grid: GridContainer, stat_name: String, value: int, bonus: int) -> void:
	var name_label := Label.new()
	name_label.text = "%s:" % stat_name
	name_label.add_theme_color_override("font_color", STAT_COLOR)
	grid.add_child(name_label)

	var value_label := Label.new()
	if bonus > 0:
		value_label.text = "%d (+%d)" % [value + bonus, bonus]
		value_label.add_theme_color_override("font_color", BONUS_COLOR)
	elif bonus < 0:
		value_label.text = "%d (%d)" % [value + bonus, bonus]
		value_label.add_theme_color_override("font_color", PENALTY_COLOR)
	else:
		value_label.text = "%d" % value
		value_label.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(value_label)


func _has_equipment_bonuses() -> bool:
	var attack_bonus: int = current_regiment.get_meta("attack_bonus", 0)
	var armor_bonus: int = current_regiment.get_meta("armor_bonus", 0)
	return attack_bonus > 0 or armor_bonus > 0


func _add_equipment_section() -> void:
	var header := Label.new()
	header.text = "Equipment"
	header.add_theme_color_override("font_color", TEXT_COLOR)
	content_vbox.add_child(header)

	var attack_bonus: int = current_regiment.get_meta("attack_bonus", 0)
	var armor_bonus: int = current_regiment.get_meta("armor_bonus", 0)

	if attack_bonus > 0:
		var label := Label.new()
		label.text = "  Improved Weapons (+%d Attack)" % attack_bonus
		label.add_theme_color_override("font_color", BONUS_COLOR)
		content_vbox.add_child(label)

	if armor_bonus > 0:
		var label := Label.new()
		label.text = "  Reinforced Armor (+%d Armor)" % armor_bonus
		label.add_theme_color_override("font_color", BONUS_COLOR)
		content_vbox.add_child(label)


func _add_veterancy_section() -> void:
	var vet_level: int = current_regiment.get_meta("veterancy_level", 0)
	var vet_xp: int = current_regiment.get_meta("veterancy_xp", 0)
	var xp_for_next: int = _get_xp_for_level(vet_level + 1)

	var vet_names := ["Fresh", "Blooded", "Veteran", "Elite"]
	var vet_name: String = vet_names[mini(vet_level, 3)]

	var header := Label.new()
	header.text = "Veterancy: %s" % vet_name
	header.add_theme_color_override("font_color", TEXT_COLOR)
	content_vbox.add_child(header)

	if vet_level < 3:
		var xp_label := Label.new()
		xp_label.text = "  XP: %d / %d" % [vet_xp, xp_for_next]
		xp_label.add_theme_color_override("font_color", STAT_COLOR)
		content_vbox.add_child(xp_label)

		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = xp_for_next
		bar.value = vet_xp
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		content_vbox.add_child(bar)

	# Veterancy bonuses
	if vet_level > 0:
		var bonus_label := Label.new()
		var bonuses := _get_vet_bonuses(vet_level)
		bonus_label.text = "  %s" % bonuses
		bonus_label.add_theme_color_override("font_color", BONUS_COLOR)
		content_vbox.add_child(bonus_label)


func _get_xp_for_level(level: int) -> int:
	match level:
		1: return 100
		2: return 300
		3: return 600
		_: return 999


func _get_vet_bonuses(level: int) -> String:
	match level:
		1: return "+5% Melee, +5 Morale"
		2: return "+10% Melee, +10 Morale, +5% Ranged"
		3: return "+15% Melee, +15 Morale, +10% Ranged"
		_: return ""


func _has_abilities() -> bool:
	return current_regiment.has_meta("abilities") and current_regiment.get_meta("abilities").size() > 0


func _add_abilities_section() -> void:
	var header := Label.new()
	header.text = "Abilities"
	header.add_theme_color_override("font_color", TEXT_COLOR)
	content_vbox.add_child(header)

	var abilities: Array = current_regiment.get_meta("abilities", [])
	for ability in abilities:
		var label := Label.new()
		label.text = "  - %s" % ability
		label.add_theme_color_override("font_color", STAT_COLOR)
		content_vbox.add_child(label)


func _add_history_section() -> void:
	var battles: int = current_regiment.get_meta("battles_fought", 0)
	var kills: int = current_regiment.get_meta("total_kills", 0)

	var header := Label.new()
	header.text = "Battle History"
	header.add_theme_color_override("font_color", TEXT_COLOR)
	content_vbox.add_child(header)

	var battles_label := Label.new()
	battles_label.text = "  Battles: %d" % battles
	battles_label.add_theme_color_override("font_color", STAT_COLOR)
	content_vbox.add_child(battles_label)

	var kills_label := Label.new()
	kills_label.text = "  Kills: %d" % kills
	kills_label.add_theme_color_override("font_color", STAT_COLOR)
	content_vbox.add_child(kills_label)


func _add_upkeep_section() -> void:
	var upkeep: int = current_regiment.get_meta("upkeep_cost", 10)

	var label := Label.new()
	label.text = "Upkeep: %d gold/turn" % upkeep
	label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	content_vbox.add_child(label)


func _input(event: InputEvent) -> void:
	# Close on click outside or right-click
	if visible and event is InputEventMouseButton:
		if event.pressed:
			var local_pos := panel_container.get_local_mouse_position()
			var rect := Rect2(Vector2.ZERO, panel_container.size)
			if not rect.has_point(local_pos):
				visible = false
