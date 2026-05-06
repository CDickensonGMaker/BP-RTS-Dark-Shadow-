# Refit panel for upgrading unit equipment in controlled territory.
# Requires Armory for armor upgrades, Blacksmith for weapon upgrades.
class_name RefitPanel
extends Control


signal unit_upgraded(regiment: Resource, upgrade_type: String, cost: int)


# UI styling
const BG_COLOR := Color(0.08, 0.06, 0.05, 0.92)
const BORDER_COLOR := Color(0.6, 0.5, 0.3, 1.0)
const TEXT_COLOR := Color(0.95, 0.92, 0.85, 1.0)
const GOLD_COLOR := Color(0.85, 0.7, 0.4, 1.0)
const BONUS_COLOR := Color(0.4, 0.8, 0.4, 1.0)
const DISABLED_COLOR := Color(0.5, 0.5, 0.5, 0.7)

# Current settlement and battalion
var current_settlement: Resource = null
var current_battalion: Resource = null
var selected_regiment: Resource = null

# Available upgrade tiers from buildings
var available_armor_tier: int = 0
var available_weapon_tier: int = 0

# UI elements
var unit_list: ItemList = null
var upgrade_panel: VBoxContainer = null
var armor_button: Button = null
var weapon_button: Button = null
var gold_label: Label = null
var no_upgrades_label: Label = null


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	# Left side - unit list
	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 0.4
	hbox.add_child(list_panel)

	var list_vbox := VBoxContainer.new()
	list_panel.add_child(list_vbox)

	var list_header := Label.new()
	list_header.text = "Select Unit to Upgrade"
	list_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list_vbox.add_child(list_header)

	unit_list = ItemList.new()
	unit_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_list.item_selected.connect(_on_unit_selected)
	list_vbox.add_child(unit_list)

	# Right side - upgrade options
	var upgrade_container := PanelContainer.new()
	upgrade_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_container.size_flags_stretch_ratio = 0.6
	hbox.add_child(upgrade_container)

	upgrade_panel = VBoxContainer.new()
	upgrade_panel.add_theme_constant_override("separation", 12)
	upgrade_container.add_child(upgrade_panel)

	# Placeholder
	no_upgrades_label = Label.new()
	no_upgrades_label.text = "Select a unit to view available upgrades"
	no_upgrades_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_upgrades_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	no_upgrades_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upgrade_panel.add_child(no_upgrades_label)

	# Gold display at bottom
	gold_label = Label.new()
	gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	upgrade_panel.add_child(gold_label)


func setup(settlement: Resource, battalion: Resource) -> void:
	current_settlement = settlement
	current_battalion = battalion

	# Determine available upgrade tiers from settlement buildings
	_calculate_available_upgrades()

	# Populate unit list
	_populate_unit_list()

	_update_gold_display()


func _calculate_available_upgrades() -> void:
	available_armor_tier = 0
	available_weapon_tier = 0

	if not current_settlement:
		return

	# Check for armory buildings
	for building in current_settlement.buildings:
		if building.category == 3:  # ARMORY
			available_armor_tier = maxi(available_armor_tier, building.tier)
		elif building.category == 4:  # BLACKSMITH
			available_weapon_tier = maxi(available_weapon_tier, building.tier)


func _populate_unit_list() -> void:
	unit_list.clear()

	if not current_battalion:
		return

	for regiment in current_battalion.regiments:
		var name: String = regiment.regiment_name if regiment.get("regiment_name") else regiment.get_meta("regiment_name", "Unknown")
		var current_armor: int = regiment.get_meta("armor_bonus", 0)
		var current_weapon: int = regiment.get_meta("attack_bonus", 0)

		var display := name
		if current_armor > 0 or current_weapon > 0:
			display += " [+"
			if current_armor > 0:
				display += "A%d" % current_armor
			if current_weapon > 0:
				if current_armor > 0:
					display += "/"
				display += "W%d" % current_weapon
			display += "]"

		unit_list.add_item(display)


func _on_unit_selected(index: int) -> void:
	if index < 0 or index >= current_battalion.regiments.size():
		return

	selected_regiment = current_battalion.regiments[index]
	_display_upgrade_options()


func _display_upgrade_options() -> void:
	# Clear existing
	for child in upgrade_panel.get_children():
		child.queue_free()

	if not selected_regiment:
		return

	var name: String = selected_regiment.regiment_name if selected_regiment.get("regiment_name") else selected_regiment.get_meta("regiment_name", "Unknown")

	# Unit header
	var header := Label.new()
	header.text = "Upgrades for %s" % name
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", TEXT_COLOR)
	upgrade_panel.add_child(header)

	upgrade_panel.add_child(HSeparator.new())

	# Current equipment status
	var current_armor: int = selected_regiment.get_meta("armor_bonus", 0)
	var current_weapon: int = selected_regiment.get_meta("attack_bonus", 0)

	var status := Label.new()
	status.text = "Current Equipment:"
	status.add_theme_color_override("font_color", TEXT_COLOR)
	upgrade_panel.add_child(status)

	var armor_status := Label.new()
	armor_status.text = "  Armor Tier: %d / %d" % [current_armor, available_armor_tier]
	armor_status.add_theme_color_override("font_color", BONUS_COLOR if current_armor > 0 else TEXT_COLOR)
	upgrade_panel.add_child(armor_status)

	var weapon_status := Label.new()
	weapon_status.text = "  Weapon Tier: %d / %d" % [current_weapon, available_weapon_tier]
	weapon_status.add_theme_color_override("font_color", BONUS_COLOR if current_weapon > 0 else TEXT_COLOR)
	upgrade_panel.add_child(weapon_status)

	upgrade_panel.add_child(HSeparator.new())

	# Available upgrades section
	var upgrades_header := Label.new()
	upgrades_header.text = "Available Upgrades:"
	upgrades_header.add_theme_color_override("font_color", TEXT_COLOR)
	upgrade_panel.add_child(upgrades_header)

	var has_upgrades := false

	# Armor upgrade
	if current_armor < available_armor_tier:
		has_upgrades = true
		var armor_cost := _get_upgrade_cost("armor", current_armor + 1)

		var armor_box := HBoxContainer.new()
		upgrade_panel.add_child(armor_box)

		var armor_desc := Label.new()
		armor_desc.text = "Reinforced Armor (+1 Armor)"
		armor_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		armor_box.add_child(armor_desc)

		armor_button = Button.new()
		armor_button.text = "%d Gold" % armor_cost
		armor_button.disabled = CampaignManager.current_gold < armor_cost
		armor_button.pressed.connect(_on_armor_upgrade_pressed.bind(armor_cost))
		armor_box.add_child(armor_button)
	else:
		var no_armor := Label.new()
		if available_armor_tier == 0:
			no_armor.text = "  No Armory available (build one)"
		else:
			no_armor.text = "  Armor at maximum tier"
		no_armor.add_theme_color_override("font_color", DISABLED_COLOR)
		upgrade_panel.add_child(no_armor)

	# Weapon upgrade
	if current_weapon < available_weapon_tier:
		has_upgrades = true
		var weapon_cost := _get_upgrade_cost("weapon", current_weapon + 1)

		var weapon_box := HBoxContainer.new()
		upgrade_panel.add_child(weapon_box)

		var weapon_desc := Label.new()
		weapon_desc.text = "Improved Weapons (+1 Attack)"
		weapon_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		weapon_box.add_child(weapon_desc)

		weapon_button = Button.new()
		weapon_button.text = "%d Gold" % weapon_cost
		weapon_button.disabled = CampaignManager.current_gold < weapon_cost
		weapon_button.pressed.connect(_on_weapon_upgrade_pressed.bind(weapon_cost))
		weapon_box.add_child(weapon_button)
	else:
		var no_weapon := Label.new()
		if available_weapon_tier == 0:
			no_weapon.text = "  No Blacksmith available (build one)"
		else:
			no_weapon.text = "  Weapons at maximum tier"
		no_weapon.add_theme_color_override("font_color", DISABLED_COLOR)
		upgrade_panel.add_child(no_weapon)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	upgrade_panel.add_child(spacer)

	# Info about upgrades
	upgrade_panel.add_child(HSeparator.new())

	var info := Label.new()
	info.text = "Upgrades are permanent and affect unit stats in all future battles."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	upgrade_panel.add_child(info)

	# Gold display
	gold_label = Label.new()
	gold_label.add_theme_color_override("font_color", GOLD_COLOR)
	upgrade_panel.add_child(gold_label)
	_update_gold_display()


func _get_upgrade_cost(upgrade_type: String, tier: int) -> int:
	# Cost increases with tier
	var base_cost := 50 if upgrade_type == "armor" else 60
	return base_cost * tier


func _on_armor_upgrade_pressed(cost: int) -> void:
	if not selected_regiment:
		return

	if CampaignManager.current_gold < cost:
		return

	CampaignManager.current_gold -= cost

	var current: int = selected_regiment.get_meta("armor_bonus", 0)
	selected_regiment.set_meta("armor_bonus", current + 1)

	unit_upgraded.emit(selected_regiment, "armor", cost)

	# Refresh displays
	_populate_unit_list()
	_display_upgrade_options()


func _on_weapon_upgrade_pressed(cost: int) -> void:
	if not selected_regiment:
		return

	if CampaignManager.current_gold < cost:
		return

	CampaignManager.current_gold -= cost

	var current: int = selected_regiment.get_meta("attack_bonus", 0)
	selected_regiment.set_meta("attack_bonus", current + 1)

	unit_upgraded.emit(selected_regiment, "weapon", cost)

	# Refresh displays
	_populate_unit_list()
	_display_upgrade_options()


func _update_gold_display() -> void:
	if gold_label and CampaignManager:
		gold_label.text = "Your Gold: %d" % CampaignManager.current_gold


func is_available() -> bool:
	# Refit is only available with armory or blacksmith
	return available_armor_tier > 0 or available_weapon_tier > 0


func get_status_text() -> String:
	if not current_settlement:
		return "Not in controlled territory"

	if not is_available():
		return "No Armory or Blacksmith available"

	var parts := []
	if available_armor_tier > 0:
		parts.append("Armor T%d" % available_armor_tier)
	if available_weapon_tier > 0:
		parts.append("Weapons T%d" % available_weapon_tier)

	return "Available: %s" % ", ".join(parts)
