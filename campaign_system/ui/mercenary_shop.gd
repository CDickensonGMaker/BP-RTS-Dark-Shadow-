# Mercenary hiring panel for pre-battle screen.
# Shows available mercenaries based on region and completed contracts.
# Inspired by Shadow of the Horned Rat's paymaster system.
class_name MercenaryShop
extends Control


signal mercenary_selected(regiment: Resource)
signal hire_requested(regiment: Resource, cost: int)


# Dark color palette (Catacombs style)
const BG_COLOR := Color(0.05, 0.04, 0.03, 0.98)
const BG_CARD_COLOR := Color(0.07, 0.06, 0.05, 0.96)
const BORDER_COLOR := Color(0.35, 0.28, 0.18, 1.0)
const TEXT_COLOR := Color(0.9, 0.85, 0.75, 1.0)
const TEXT_DIM_COLOR := Color(0.6, 0.55, 0.5, 1.0)
const GOLD_COLOR := Color(0.9, 0.7, 0.2, 1.0)
const DISABLED_COLOR := Color(0.4, 0.4, 0.4, 0.7)

# Available mercenaries
var available_mercenaries: Array = []
var selected_mercenary: Resource = null

# UI elements
var mercenary_list: ItemList = null
var detail_panel: VBoxContainer = null
var hire_button: Button = null
var gold_label: Label = null

# Current region for filtering
var current_region: Resource = null


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# Main layout
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	# Left side - mercenary list
	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 0.4
	hbox.add_child(list_panel)

	var list_vbox := VBoxContainer.new()
	list_panel.add_child(list_vbox)

	var list_header := Label.new()
	list_header.text = "Available Mercenaries"
	list_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_vbox.add_child(list_header)

	mercenary_list = ItemList.new()
	mercenary_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mercenary_list.item_selected.connect(_on_mercenary_selected)
	list_vbox.add_child(mercenary_list)

	# Right side - detail panel
	var detail_container := PanelContainer.new()
	detail_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_container.size_flags_stretch_ratio = 0.6
	hbox.add_child(detail_container)

	detail_panel = VBoxContainer.new()
	detail_panel.add_theme_constant_override("separation", 8)
	detail_container.add_child(detail_panel)

	# Placeholder content
	var placeholder := Label.new()
	placeholder.text = "Select a mercenary to view details"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(placeholder)

	# Bottom bar
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 20)
	detail_panel.add_child(bottom_bar)

	gold_label = Label.new()
	gold_label.text = "Gold: 0"
	gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(gold_label)

	hire_button = Button.new()
	hire_button.text = "Hire Mercenary"
	hire_button.disabled = true
	hire_button.pressed.connect(_on_hire_pressed)
	bottom_bar.add_child(hire_button)


func set_region(region: Resource) -> void:
	current_region = region
	refresh_available()


func refresh_available() -> void:
	available_mercenaries.clear()
	mercenary_list.clear()

	# Get base mercenaries (always available)
	_add_base_mercenaries()

	# Get region-specific mercenaries
	if current_region:
		_add_region_mercenaries(current_region)

	# Get contract-unlocked mercenaries
	_add_contract_mercenaries()

	# Update gold display
	_update_gold_display()


func _add_base_mercenaries() -> void:
	# Always available generic mercenaries
	var base_mercs := [
		_create_mercenary_data("Sellswords", "infantry", 60, 150, 15),
		_create_mercenary_data("Free Company Archers", "ranged", 40, 120, 12),
		_create_mercenary_data("Hedge Knights", "cavalry", 20, 300, 25),
	]

	for merc in base_mercs:
		_add_mercenary_to_list(merc)


func _add_region_mercenaries(region: Resource) -> void:
	# Region-specific mercenaries based on terrain/culture
	if not region:
		return

	var terrain_type: int = region.terrain_type

	match terrain_type:
		0:  # PLAINS
			_add_mercenary_to_list(_create_mercenary_data("Plains Riders", "cavalry", 30, 250, 20))
		1:  # FOREST
			_add_mercenary_to_list(_create_mercenary_data("Forest Rangers", "ranged", 35, 180, 18))
			_add_mercenary_to_list(_create_mercenary_data("Woodsmen", "infantry", 50, 100, 10))
		2:  # HILLS
			_add_mercenary_to_list(_create_mercenary_data("Hill Clansmen", "infantry", 55, 130, 14))
		3:  # MOUNTAINS
			_add_mercenary_to_list(_create_mercenary_data("Mountain Guard", "infantry", 45, 200, 20))
		4:  # DESERT
			_add_mercenary_to_list(_create_mercenary_data("Desert Skirmishers", "ranged", 40, 160, 16))
		5:  # SWAMP
			_add_mercenary_to_list(_create_mercenary_data("Swamp Stalkers", "infantry", 40, 140, 15))


func _add_contract_mercenaries() -> void:
	# Mercenaries unlocked by completing specific contracts
	# Check CampaignManager for completed contracts
	if not CampaignManager:
		return

	# This would check completed_contracts array
	# For now, add some examples
	pass


func _create_mercenary_data(unit_name: String, category: String, soldiers: int, cost: int, upkeep: int) -> Dictionary:
	return {
		"name": unit_name,
		"category": category,
		"soldiers": soldiers,
		"max_soldiers": soldiers,
		"cost": cost,
		"upkeep": upkeep,
		"melee_attack": 12 if category == "infantry" else 8,
		"melee_defense": 10 if category == "infantry" else 6,
		"armor": 8 if category == "infantry" else 5,
		"base_morale": 65,
		"description": "Experienced %s mercenaries for hire." % category
	}


func _add_mercenary_to_list(merc_data: Dictionary) -> void:
	available_mercenaries.append(merc_data)
	var display := "%s (%d) - %d gold" % [merc_data.name, merc_data.soldiers, merc_data.cost]
	mercenary_list.add_item(display)

	# Check if affordable
	if CampaignManager and CampaignManager.current_gold < merc_data.cost:
		var idx := mercenary_list.item_count - 1
		mercenary_list.set_item_custom_fg_color(idx, DISABLED_COLOR)


func _on_mercenary_selected(index: int) -> void:
	if index < 0 or index >= available_mercenaries.size():
		return

	selected_mercenary = null  # Will create on hire
	var merc_data: Dictionary = available_mercenaries[index]

	_display_mercenary_details(merc_data)

	# Enable hire button if affordable and have room
	var can_afford: bool = CampaignManager.current_gold >= merc_data.cost
	# TODO: Check battalion capacity
	hire_button.disabled = not can_afford

	mercenary_selected.emit(null)  # Would emit actual resource


func _display_mercenary_details(merc_data: Dictionary) -> void:
	# Clear existing content
	for child in detail_panel.get_children():
		child.queue_free()

	# Name header
	var name_label := Label.new()
	name_label.text = merc_data.name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	detail_panel.add_child(name_label)

	# Category
	var cat_label := Label.new()
	cat_label.text = merc_data.category.capitalize()
	cat_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
	detail_panel.add_child(cat_label)

	# Separator
	detail_panel.add_child(HSeparator.new())

	# Description
	var desc_label := Label.new()
	desc_label.text = merc_data.description
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	detail_panel.add_child(desc_label)

	# Stats grid
	var stats_label := Label.new()
	stats_label.text = "Unit Stats"
	stats_label.add_theme_color_override("font_color", TEXT_COLOR)
	detail_panel.add_child(stats_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	detail_panel.add_child(grid)

	_add_stat(grid, "Soldiers", str(merc_data.soldiers))
	_add_stat(grid, "Attack", str(merc_data.melee_attack))
	_add_stat(grid, "Defense", str(merc_data.melee_defense))
	_add_stat(grid, "Armor", str(merc_data.armor))
	_add_stat(grid, "Morale", str(merc_data.base_morale))

	# Separator
	detail_panel.add_child(HSeparator.new())

	# Cost section
	var cost_header := Label.new()
	cost_header.text = "Cost"
	cost_header.add_theme_color_override("font_color", TEXT_COLOR)
	detail_panel.add_child(cost_header)

	var cost_grid := GridContainer.new()
	cost_grid.columns = 2
	cost_grid.add_theme_constant_override("h_separation", 30)
	detail_panel.add_child(cost_grid)

	_add_stat(cost_grid, "Hire Cost", "%d gold" % merc_data.cost)
	_add_stat(cost_grid, "Upkeep", "%d gold/turn" % merc_data.upkeep)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(spacer)

	# Recreate bottom bar
	var bottom_bar := HBoxContainer.new()
	bottom_bar.add_theme_constant_override("separation", 20)
	detail_panel.add_child(bottom_bar)

	gold_label = Label.new()
	gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_bar.add_child(gold_label)
	_update_gold_display()

	hire_button = Button.new()
	hire_button.text = "Hire for %d Gold" % merc_data.cost
	hire_button.disabled = CampaignManager.current_gold < merc_data.cost
	hire_button.pressed.connect(_on_hire_pressed)
	bottom_bar.add_child(hire_button)


func _add_stat(grid: GridContainer, stat_name: String, value: String) -> void:
	var name_label := Label.new()
	name_label.text = "%s:" % stat_name
	name_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.6))
	grid.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_color_override("font_color", TEXT_COLOR)
	grid.add_child(value_label)


func _update_gold_display() -> void:
	if gold_label and CampaignManager:
		gold_label.text = "Your Gold: %d" % CampaignManager.current_gold


func _on_hire_pressed() -> void:
	var selected_idx := mercenary_list.get_selected_items()
	if selected_idx.is_empty():
		return

	var idx: int = selected_idx[0]
	if idx < 0 or idx >= available_mercenaries.size():
		return

	var merc_data: Dictionary = available_mercenaries[idx]

	# Create regiment resource from mercenary data
	var regiment := _create_regiment_from_merc(merc_data)

	hire_requested.emit(regiment, merc_data.cost)


func _create_regiment_from_merc(merc_data: Dictionary) -> Resource:
	# Create a RegimentData resource from mercenary data
	# This would normally load a template and customize it
	var regiment := Resource.new()

	# Set metadata (would be proper exports in real RegimentData)
	regiment.set_meta("regiment_name", merc_data.name)
	regiment.set_meta("unit_category", merc_data.category)
	regiment.set_meta("current_soldiers", merc_data.soldiers)
	regiment.set_meta("max_soldiers", merc_data.max_soldiers)
	regiment.set_meta("melee_attack", merc_data.melee_attack)
	regiment.set_meta("melee_defense", merc_data.melee_defense)
	regiment.set_meta("armor", merc_data.armor)
	regiment.set_meta("base_morale", merc_data.base_morale)
	regiment.set_meta("upkeep_cost", merc_data.upkeep)
	regiment.set_meta("is_mercenary", true)
	regiment.set_meta("veterancy_level", 0)
	regiment.set_meta("veterancy_xp", 0)

	return regiment
