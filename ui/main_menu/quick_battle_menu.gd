# Quick Battle Menu - Full army builder with faction selection and upgrades
extends Control


signal back_pressed

# Budget per side
const STARTING_GOLD: int = 10000

# Upgrade costs
const VETERAN_UPGRADE_COST: int = 150  # Per level (3 levels max)
const ARMS_UPGRADE_COST: int = 100     # +2 attack
const ARMOR_UPGRADE_COST: int = 100    # +2 defense/armor

# Unit base costs (calculated from stats if not defined)
const UNIT_COSTS: Dictionary = {
	# Empire
	"halb": 400,
	"mcsword": 500,
	"empsword": 600,
	"grtsword": 900,
	"xbow": 550,
	"reik": 1200,
	"impcanon": 1500,
	# Dwarf
	"dwwar": 500,
	"iron": 700,
	"ironbrks": 1000,
	"engr": 600,
	"grtcanon": 1400,
	"gyrocopt": 1100,
	# Orc
	"gob1": 200,
	"orcboyz": 450,
	"blackorc": 850,
	"gobarch": 300,
	"wolfride": 550,
	"boarboyz": 800,
	# Undead
	"vanheims": 300,
	"graveguard": 650,
	"gravearch": 400,
	"graveknight": 900,
}

# Faction display names
const FACTION_NAMES: Dictionary = {
	"empire": "The Empire",
	"dwarf": "Dwarven Holds",
	"orc": "Orc Warband",
	"undead": "Undead Legion",
}

# Faction colors
const FACTION_COLORS: Dictionary = {
	"empire": Color(0.3, 0.5, 0.8),
	"dwarf": Color(0.6, 0.5, 0.3),
	"orc": Color(0.4, 0.6, 0.3),
	"undead": Color(0.5, 0.3, 0.5),
}

# UI Colors
const COLOR_BG := Color(0.05, 0.04, 0.03, 0.98)
const COLOR_PANEL := Color(0.08, 0.07, 0.06, 0.95)
const COLOR_BORDER := Color(0.35, 0.28, 0.18, 1.0)
const COLOR_GOLD := Color(0.9, 0.7, 0.2, 1.0)
const COLOR_TEXT := Color(0.9, 0.85, 0.75, 1.0)
const COLOR_TEXT_DIM := Color(0.6, 0.55, 0.5, 1.0)

# Army data
var player_faction: String = "empire"
var enemy_faction: String = "orc"
var player_gold: int = STARTING_GOLD
var enemy_gold: int = STARTING_GOLD
var player_army: Array = []  # Array of {unit_id, veteran_level, arms_upgrade, armor_upgrade}
var enemy_army: Array = []

# UI References
var player_faction_btn: OptionButton
var enemy_faction_btn: OptionButton
var player_gold_label: Label
var enemy_gold_label: Label
var player_roster_list: VBoxContainer
var enemy_roster_list: VBoxContainer
var player_army_list: VBoxContainer
var enemy_army_list: VBoxContainer
var terrain_option: OptionButton
var start_button: Button

const TERRAIN_TYPES := ["plains", "hills", "forest", "village"]


func _ready() -> void:
	_create_ui()
	_refresh_all()


func _create_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.add_child(main_vbox)
	add_child(margin)

	# Title
	var title := Label.new()
	title.text = "QUICK BATTLE - ARMY BUILDER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", COLOR_GOLD)
	main_vbox.add_child(title)

	# Two-column layout for armies
	var armies_hbox := HBoxContainer.new()
	armies_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	armies_hbox.add_theme_constant_override("separation", 30)
	main_vbox.add_child(armies_hbox)

	# Player side
	var player_panel := _create_army_panel("YOUR ARMY", true)
	player_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armies_hbox.add_child(player_panel)

	# VS divider
	var vs_label := Label.new()
	vs_label.text = "VS"
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs_label.add_theme_font_size_override("font_size", 48)
	vs_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	armies_hbox.add_child(vs_label)

	# Enemy side
	var enemy_panel := _create_army_panel("ENEMY ARMY", false)
	enemy_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	armies_hbox.add_child(enemy_panel)

	# Bottom controls
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(bottom_hbox)

	# Terrain selection
	var terrain_label := Label.new()
	terrain_label.text = "Terrain:"
	terrain_label.add_theme_color_override("font_color", COLOR_TEXT)
	bottom_hbox.add_child(terrain_label)

	terrain_option = OptionButton.new()
	terrain_option.custom_minimum_size = Vector2(150, 40)
	for terrain in TERRAIN_TYPES:
		terrain_option.add_item(terrain.capitalize())
	bottom_hbox.add_child(terrain_option)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(50, 0)
	bottom_hbox.add_child(spacer)

	# Back button
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(150, 50)
	back_btn.pressed.connect(_on_back_pressed)
	bottom_hbox.add_child(back_btn)

	# Start button
	start_button = Button.new()
	start_button.text = "START BATTLE"
	start_button.custom_minimum_size = Vector2(200, 50)
	start_button.pressed.connect(_on_start_pressed)
	bottom_hbox.add_child(start_button)


func _create_army_panel(title_text: String, is_player: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# Header with title and faction
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 15)
	vbox.add_child(header)

	var title_label := Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", COLOR_GOLD)
	header.add_child(title_label)

	var faction_btn := OptionButton.new()
	faction_btn.custom_minimum_size = Vector2(180, 35)
	for faction_id in FACTION_NAMES.keys():
		faction_btn.add_item(FACTION_NAMES[faction_id])
	if is_player:
		player_faction_btn = faction_btn
		faction_btn.selected = 0  # Empire
		faction_btn.item_selected.connect(_on_player_faction_changed)
	else:
		enemy_faction_btn = faction_btn
		faction_btn.selected = 2  # Orc
		faction_btn.item_selected.connect(_on_enemy_faction_changed)
	header.add_child(faction_btn)

	# Gold display
	var gold_hbox := HBoxContainer.new()
	vbox.add_child(gold_hbox)
	var gold_icon := Label.new()
	gold_icon.text = "Gold: "
	gold_icon.add_theme_color_override("font_color", COLOR_TEXT)
	gold_hbox.add_child(gold_icon)
	var gold_label := Label.new()
	gold_label.text = str(STARTING_GOLD)
	gold_label.add_theme_color_override("font_color", COLOR_GOLD)
	gold_label.add_theme_font_size_override("font_size", 18)
	if is_player:
		player_gold_label = gold_label
	else:
		enemy_gold_label = gold_label
	gold_hbox.add_child(gold_label)

	# Available units section
	var roster_label := Label.new()
	roster_label.text = "Available Units:"
	roster_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(roster_label)

	var roster_scroll := ScrollContainer.new()
	roster_scroll.custom_minimum_size = Vector2(0, 180)
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(roster_scroll)

	var roster_list := VBoxContainer.new()
	roster_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_list.add_theme_constant_override("separation", 5)
	if is_player:
		player_roster_list = roster_list
	else:
		enemy_roster_list = roster_list
	roster_scroll.add_child(roster_list)

	# Selected army section
	var army_label := Label.new()
	army_label.text = "Your Army:"
	army_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	vbox.add_child(army_label)

	var army_scroll := ScrollContainer.new()
	army_scroll.custom_minimum_size = Vector2(0, 200)
	army_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(army_scroll)

	var army_list := VBoxContainer.new()
	army_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	army_list.add_theme_constant_override("separation", 5)
	if is_player:
		player_army_list = army_list
	else:
		enemy_army_list = army_list
	army_scroll.add_child(army_list)

	return panel


func _refresh_all() -> void:
	_refresh_roster(true)
	_refresh_roster(false)
	_refresh_army_list(true)
	_refresh_army_list(false)
	_update_gold_display()
	_update_start_button()


func _refresh_roster(is_player: bool) -> void:
	var roster_list: VBoxContainer = player_roster_list if is_player else enemy_roster_list
	var faction: String = player_faction if is_player else enemy_faction
	var gold: int = player_gold if is_player else enemy_gold

	# Clear existing
	for child in roster_list.get_children():
		child.queue_free()

	# Get faction units
	var unit_ids: Array = UnitCatalog.get_faction_units(faction)

	for unit_id in unit_ids:
		var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
		if not data:
			continue

		var cost: int = _get_unit_cost(unit_id)
		var can_afford: bool = gold >= cost

		var row := _create_roster_row(unit_id, data, cost, can_afford, is_player)
		roster_list.add_child(row)


func _create_roster_row(unit_id: String, data: RegimentData, cost: int, can_afford: bool, is_player: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Unit name
	var name_label := Label.new()
	name_label.text = data.regiment_name
	name_label.custom_minimum_size = Vector2(150, 0)
	name_label.add_theme_color_override("font_color", COLOR_TEXT if can_afford else COLOR_TEXT_DIM)
	row.add_child(name_label)

	# Unit type icon
	var type_label := Label.new()
	type_label.text = _get_unit_type_icon(data.unit_type)
	type_label.custom_minimum_size = Vector2(30, 0)
	type_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	row.add_child(type_label)

	# Cost
	var cost_label := Label.new()
	cost_label.text = str(cost) + "g"
	cost_label.custom_minimum_size = Vector2(60, 0)
	cost_label.add_theme_color_override("font_color", COLOR_GOLD if can_afford else COLOR_TEXT_DIM)
	row.add_child(cost_label)

	# Add button
	var add_btn := Button.new()
	add_btn.text = "+"
	add_btn.custom_minimum_size = Vector2(35, 30)
	add_btn.disabled = not can_afford
	add_btn.pressed.connect(_on_add_unit.bind(unit_id, is_player))
	row.add_child(add_btn)

	return row


func _refresh_army_list(is_player: bool) -> void:
	var army_list: VBoxContainer = player_army_list if is_player else enemy_army_list
	var army: Array = player_army if is_player else enemy_army

	# Clear existing
	for child in army_list.get_children():
		child.queue_free()

	if army.is_empty():
		var empty_label := Label.new()
		empty_label.text = "(No units selected)"
		empty_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
		army_list.add_child(empty_label)
		return

	for i in range(army.size()):
		var unit_entry: Dictionary = army[i]
		var row := _create_army_row(i, unit_entry, is_player)
		army_list.add_child(row)


func _create_army_row(index: int, unit_entry: Dictionary, is_player: bool) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 3)

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_entry.unit_id)
	if not data:
		return container

	# Main row
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	container.add_child(row)

	# Unit name with upgrades indicator
	var name_text: String = data.regiment_name
	if unit_entry.veteran_level > 0:
		name_text += " ★".repeat(unit_entry.veteran_level)
	var name_label := Label.new()
	name_label.text = name_text
	name_label.custom_minimum_size = Vector2(180, 0)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(name_label)

	# Remove button
	var remove_btn := Button.new()
	remove_btn.text = "X"
	remove_btn.custom_minimum_size = Vector2(30, 28)
	remove_btn.pressed.connect(_on_remove_unit.bind(index, is_player))
	row.add_child(remove_btn)

	# Upgrade row
	var upgrade_row := HBoxContainer.new()
	upgrade_row.add_theme_constant_override("separation", 5)
	container.add_child(upgrade_row)

	var gold: int = player_gold if is_player else enemy_gold

	# Veteran upgrade (max 3 levels)
	if unit_entry.veteran_level < 3:
		var vet_btn := Button.new()
		vet_btn.text = "+Vet (%dg)" % VETERAN_UPGRADE_COST
		vet_btn.custom_minimum_size = Vector2(90, 26)
		vet_btn.disabled = gold < VETERAN_UPGRADE_COST
		vet_btn.pressed.connect(_on_upgrade_veteran.bind(index, is_player))
		upgrade_row.add_child(vet_btn)

	# Arms upgrade (max 1)
	if not unit_entry.arms_upgrade:
		var arms_btn := Button.new()
		arms_btn.text = "+Arms (%dg)" % ARMS_UPGRADE_COST
		arms_btn.custom_minimum_size = Vector2(100, 26)
		arms_btn.disabled = gold < ARMS_UPGRADE_COST
		arms_btn.pressed.connect(_on_upgrade_arms.bind(index, is_player))
		upgrade_row.add_child(arms_btn)
	else:
		var arms_label := Label.new()
		arms_label.text = "[Arms+]"
		arms_label.add_theme_color_override("font_color", COLOR_GOLD)
		arms_label.add_theme_font_size_override("font_size", 12)
		upgrade_row.add_child(arms_label)

	# Armor upgrade (max 1)
	if not unit_entry.armor_upgrade:
		var armor_btn := Button.new()
		armor_btn.text = "+Armor (%dg)" % ARMOR_UPGRADE_COST
		armor_btn.custom_minimum_size = Vector2(110, 26)
		armor_btn.disabled = gold < ARMOR_UPGRADE_COST
		armor_btn.pressed.connect(_on_upgrade_armor.bind(index, is_player))
		upgrade_row.add_child(armor_btn)
	else:
		var armor_label := Label.new()
		armor_label.text = "[Armor+]"
		armor_label.add_theme_color_override("font_color", COLOR_GOLD)
		armor_label.add_theme_font_size_override("font_size", 12)
		upgrade_row.add_child(armor_label)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 3)
	container.add_child(sep)

	return container


func _get_unit_cost(unit_id: String) -> int:
	if unit_id in UNIT_COSTS:
		return UNIT_COSTS[unit_id]
	# Calculate from stats if not defined
	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if data:
		var base: int = data.max_soldiers * 10
		base += data.attack * 15
		base += data.defense * 12
		base += data.armor * 20
		if data.unit_type == UnitType.Type.CAVALRY:
			base = int(base * 1.4)
		if data.unit_type == UnitType.Type.ARTILLERY:
			base = int(base * 1.5)
		return base
	return 500


func _get_unit_type_icon(unit_type: int) -> String:
	match unit_type:
		UnitType.Type.INFANTRY: return "⚔"
		UnitType.Type.RANGED: return "🏹"
		UnitType.Type.CAVALRY: return "🐴"
		UnitType.Type.ARTILLERY: return "💣"
		_: return "?"


func _update_gold_display() -> void:
	if player_gold_label:
		player_gold_label.text = str(player_gold)
	if enemy_gold_label:
		enemy_gold_label.text = str(enemy_gold)


func _update_start_button() -> void:
	# Need at least 1 unit per side
	start_button.disabled = player_army.is_empty() or enemy_army.is_empty()


func _on_player_faction_changed(index: int) -> void:
	var factions: Array = FACTION_NAMES.keys()
	player_faction = factions[index]
	# Clear player army when faction changes
	for unit in player_army:
		player_gold += _get_total_unit_cost(unit)
	player_army.clear()
	_refresh_all()


func _on_enemy_faction_changed(index: int) -> void:
	var factions: Array = FACTION_NAMES.keys()
	enemy_faction = factions[index]
	# Clear enemy army when faction changes
	for unit in enemy_army:
		enemy_gold += _get_total_unit_cost(unit)
	enemy_army.clear()
	_refresh_all()


func _get_total_unit_cost(unit_entry: Dictionary) -> int:
	var cost: int = _get_unit_cost(unit_entry.unit_id)
	cost += unit_entry.veteran_level * VETERAN_UPGRADE_COST
	if unit_entry.arms_upgrade:
		cost += ARMS_UPGRADE_COST
	if unit_entry.armor_upgrade:
		cost += ARMOR_UPGRADE_COST
	return cost


func _on_add_unit(unit_id: String, is_player: bool) -> void:
	var cost: int = _get_unit_cost(unit_id)

	if is_player:
		if player_gold >= cost:
			player_gold -= cost
			player_army.append({
				"unit_id": unit_id,
				"veteran_level": 0,
				"arms_upgrade": false,
				"armor_upgrade": false,
			})
	else:
		if enemy_gold >= cost:
			enemy_gold -= cost
			enemy_army.append({
				"unit_id": unit_id,
				"veteran_level": 0,
				"arms_upgrade": false,
				"armor_upgrade": false,
			})

	_refresh_all()


func _on_remove_unit(index: int, is_player: bool) -> void:
	if is_player:
		if index < player_army.size():
			var unit: Dictionary = player_army[index]
			player_gold += _get_total_unit_cost(unit)
			player_army.remove_at(index)
	else:
		if index < enemy_army.size():
			var unit: Dictionary = enemy_army[index]
			enemy_gold += _get_total_unit_cost(unit)
			enemy_army.remove_at(index)

	_refresh_all()


func _on_upgrade_veteran(index: int, is_player: bool) -> void:
	if is_player:
		if player_gold >= VETERAN_UPGRADE_COST and index < player_army.size():
			player_gold -= VETERAN_UPGRADE_COST
			player_army[index].veteran_level += 1
	else:
		if enemy_gold >= VETERAN_UPGRADE_COST and index < enemy_army.size():
			enemy_gold -= VETERAN_UPGRADE_COST
			enemy_army[index].veteran_level += 1

	_refresh_all()


func _on_upgrade_arms(index: int, is_player: bool) -> void:
	if is_player:
		if player_gold >= ARMS_UPGRADE_COST and index < player_army.size():
			player_gold -= ARMS_UPGRADE_COST
			player_army[index].arms_upgrade = true
	else:
		if enemy_gold >= ARMS_UPGRADE_COST and index < enemy_army.size():
			enemy_gold -= ARMS_UPGRADE_COST
			enemy_army[index].arms_upgrade = true

	_refresh_all()


func _on_upgrade_armor(index: int, is_player: bool) -> void:
	if is_player:
		if player_gold >= ARMOR_UPGRADE_COST and index < player_army.size():
			player_gold -= ARMOR_UPGRADE_COST
			player_army[index].armor_upgrade = true
	else:
		if enemy_gold >= ARMOR_UPGRADE_COST and index < enemy_army.size():
			enemy_gold -= ARMOR_UPGRADE_COST
			enemy_army[index].armor_upgrade = true

	_refresh_all()


func _on_back_pressed() -> void:
	back_pressed.emit()


func _on_start_pressed() -> void:
	if player_army.is_empty() or enemy_army.is_empty():
		return

	var terrain: String = TERRAIN_TYPES[terrain_option.selected]

	# Build regiment arrays with upgrades applied
	var player_regiments: Array = _build_regiment_array(player_army, FACTION_COLORS[player_faction])
	var enemy_regiments: Array = _build_regiment_array(enemy_army, FACTION_COLORS[enemy_faction])

	# Set up battle data
	BattleTransition.from_campaign = false
	BattleTransition.battle_data = {
		"player_regiments": player_regiments,
		"enemy_regiments": enemy_regiments,
		"terrain_type": terrain,
		"is_contract": false,
		"is_quick_battle": true,
	}

	get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")


func _build_regiment_array(army: Array, faction_color: Color) -> Array:
	var regiments: Array = []

	for unit_entry in army:
		var base_data: RegimentData = UnitCatalog.get_regiment_data(unit_entry.unit_id)
		if not base_data:
			continue

		# Duplicate to avoid modifying the original
		var reg := base_data.duplicate(true)

		# Apply veteran upgrades (+2 attack, +2 defense, +5 morale per level)
		reg.attack += unit_entry.veteran_level * 2
		reg.defense += unit_entry.veteran_level * 2
		reg.weapon_skill += unit_entry.veteran_level * 2
		reg.base_morale = min(100.0, reg.base_morale + unit_entry.veteran_level * 5)

		# Apply arms upgrade (+3 attack, +1 strength)
		if unit_entry.arms_upgrade:
			reg.attack += 3
			reg.strength += 1

		# Apply armor upgrade (+3 defense, +2 armor)
		if unit_entry.armor_upgrade:
			reg.defense += 3
			reg.armor += 2

		# Set faction color
		reg.faction_color = faction_color

		# Reset soldiers to max
		reg.current_soldiers = reg.max_soldiers
		if reg.max_ammo > 0:
			reg.current_ammo = reg.max_ammo

		regiments.append(reg)

	return regiments
