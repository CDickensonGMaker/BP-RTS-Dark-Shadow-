# Faction Selection Screen - Choose your warband
# Orcs or Human Mercenaries
extends Control


signal back_pressed
signal faction_selected(faction_id: String)

@onready var faction_list: VBoxContainer = $Panel/MarginContainer/VBoxContainer/FactionList
@onready var description_label: Label = $Panel/MarginContainer/VBoxContainer/DescriptionPanel/DescriptionLabel
@onready var start_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/StartButton
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/BackButton

var factions: Array[Dictionary] = [
	{
		"id": "human_mercs",
		"name": "The Black Company",
		"subtitle": "Human Mercenaries",
		"description": "A hardened band of sellswords, veterans of a hundred campaigns. Flexible tactics, balanced units, and gold is their creed. Start with professional infantry and archers.",
		"color": Color(0.7, 0.55, 0.35),  # Bronze
		"starting_gold": 2000,
		"starting_region": "westervale",
	},
	{
		"id": "orcs",
		"name": "Da Bloodfang Boyz",
		"subtitle": "Orc Warband",
		"description": "Brutal and savage, the Bloodfang horde sweeps across the land. Heavy infantry, devastating charges, and raw aggression. Start with orc warriors and goblin skirmishers.",
		"color": Color(0.4, 0.6, 0.3),  # Orc green
		"starting_gold": 1500,
		"starting_region": "karthmoor",
	},
]

var selected_faction: Dictionary = {}


func _ready() -> void:
	_setup_ui()
	_connect_signals()

	# Select first faction by default
	if factions.size() > 0:
		_select_faction(factions[0])


func _setup_ui() -> void:
	# Create faction buttons
	for child in faction_list.get_children():
		child.queue_free()

	for faction in factions:
		var button := Button.new()
		button.custom_minimum_size = Vector2(400, 80)
		button.text = "%s\n%s" % [faction.name, faction.subtitle]
		button.pressed.connect(_on_faction_button_pressed.bind(faction))
		faction_list.add_child(button)

	# Disable start until faction selected
	start_button.disabled = true


func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _select_faction(faction: Dictionary) -> void:
	selected_faction = faction
	description_label.text = faction.description
	start_button.disabled = false

	# Highlight selected button
	var index := factions.find(faction)
	for i in range(faction_list.get_child_count()):
		var button: Button = faction_list.get_child(i)
		if i == index:
			button.add_theme_color_override("font_color", faction.color)
		else:
			button.remove_theme_color_override("font_color")


func _on_faction_button_pressed(faction: Dictionary) -> void:
	_select_faction(faction)


func _on_start_pressed() -> void:
	if selected_faction.is_empty():
		return

	faction_selected.emit(selected_faction.id)
	_start_campaign_with_faction(selected_faction)


func _on_back_pressed() -> void:
	back_pressed.emit()


func _start_campaign_with_faction(faction: Dictionary) -> void:
	# Configure CampaignManager with selected faction
	CampaignManager.company_name = faction.name
	CampaignManager.current_gold = faction.starting_gold
	CampaignManager.turn_number = 1
	CampaignManager.battalions.clear()
	CampaignManager.completed_contracts.clear()
	CampaignManager.active_contract = null
	CampaignManager.is_campaign_active = true

	# Create starting battalion based on faction
	var battalion = _create_faction_battalion(faction)
	CampaignManager.battalions.append(battalion)

	# Transition to campaign map
	get_tree().change_scene_to_file("res://campaign_system/scenes/campaign_map.tscn")


func _create_faction_battalion(faction: Dictionary):
	var BattalionDataScript = load("res://campaign_system/data/battalion_data.gd")
	var battalion = BattalionDataScript.new()
	battalion.battalion_id = "battalion_1"
	battalion.battalion_name = faction.name
	battalion.movement_points = 100.0
	battalion.max_movement_points = 100.0

	# Set starting position based on faction's region
	var spawn_pos := _get_spawn_position(faction.starting_region)
	battalion.map_position = spawn_pos

	# Create faction-specific regiments
	match faction.id:
		"human_mercs":
			battalion.regiments = _create_human_regiments()
		"orcs":
			battalion.regiments = _create_orc_regiments()

	return battalion


func _get_spawn_position(region_id: String) -> Vector2:
	# Try to load region and get capital position
	var region_path := "res://campaign_system/data/regions/%s.tres" % region_id
	if ResourceLoader.exists(region_path):
		var region = load(region_path)
		if region and "center" in region:
			return region.center

	# Fallback: random position on map
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return Vector2(
		rng.randf_range(200, 2800),
		rng.randf_range(200, 1960)
	)


func _create_human_regiments() -> Array:
	var regiments: Array = []

	var swordsmen := RegimentData.new()
	swordsmen.regiment_name = "Company Swordsmen"
	swordsmen.unit_type = UnitType.Type.INFANTRY
	swordsmen.max_soldiers = 40
	swordsmen.current_soldiers = 40
	swordsmen.attack = 12
	swordsmen.defense = 12
	swordsmen.weapon_skill = 12
	swordsmen.strength = 3
	swordsmen.armor = 6
	swordsmen.base_morale = 75.0
	swordsmen.faction_color = Color(0.7, 0.55, 0.35)
	swordsmen.set_meta("upkeep_cost", 15)
	regiments.append(swordsmen)

	var spearmen := RegimentData.new()
	spearmen.regiment_name = "Company Spearmen"
	spearmen.unit_type = UnitType.Type.INFANTRY
	spearmen.max_soldiers = 40
	spearmen.current_soldiers = 40
	spearmen.attack = 10
	spearmen.defense = 14
	spearmen.weapon_skill = 10
	spearmen.strength = 3
	spearmen.armor = 4
	spearmen.charge_bonus = 8
	spearmen.base_morale = 70.0
	spearmen.faction_color = Color(0.7, 0.55, 0.35)
	spearmen.set_meta("upkeep_cost", 12)
	regiments.append(spearmen)

	var archers := RegimentData.new()
	archers.regiment_name = "Company Archers"
	archers.unit_type = UnitType.Type.RANGED
	archers.max_soldiers = 30
	archers.current_soldiers = 30
	archers.attack = 6
	archers.defense = 6
	archers.weapon_skill = 6
	archers.strength = 3
	archers.armor = 2
	archers.ballistic_skill = 14
	archers.max_ammo = 24
	archers.current_ammo = 24
	archers.range_distance = 40.0
	archers.base_morale = 65.0
	archers.faction_color = Color(0.7, 0.55, 0.35)
	archers.set_meta("upkeep_cost", 18)
	regiments.append(archers)

	return regiments


func _create_orc_regiments() -> Array:
	var regiments: Array = []

	var orc_boyz := RegimentData.new()
	orc_boyz.regiment_name = "Orc Boyz"
	orc_boyz.unit_type = UnitType.Type.INFANTRY
	orc_boyz.max_soldiers = 50
	orc_boyz.current_soldiers = 50
	orc_boyz.attack = 14
	orc_boyz.defense = 8
	orc_boyz.weapon_skill = 12
	orc_boyz.strength = 5
	orc_boyz.armor = 4
	orc_boyz.charge_bonus = 6
	orc_boyz.base_morale = 80.0
	orc_boyz.faction_color = Color(0.4, 0.6, 0.3)
	orc_boyz.set_meta("upkeep_cost", 12)
	regiments.append(orc_boyz)

	var big_uns := RegimentData.new()
	big_uns.regiment_name = "Big 'Uns"
	big_uns.unit_type = UnitType.Type.INFANTRY
	big_uns.max_soldiers = 30
	big_uns.current_soldiers = 30
	big_uns.attack = 18
	big_uns.defense = 10
	big_uns.weapon_skill = 14
	big_uns.strength = 6
	big_uns.armor = 6
	big_uns.charge_bonus = 10
	big_uns.base_morale = 90.0
	big_uns.faction_color = Color(0.4, 0.6, 0.3)
	big_uns.set_meta("upkeep_cost", 20)
	regiments.append(big_uns)

	var goblins := RegimentData.new()
	goblins.regiment_name = "Goblin Arrerz"
	goblins.unit_type = UnitType.Type.RANGED
	goblins.max_soldiers = 40
	goblins.current_soldiers = 40
	goblins.attack = 4
	goblins.defense = 4
	goblins.weapon_skill = 4
	goblins.strength = 2
	goblins.armor = 1
	goblins.ballistic_skill = 10
	goblins.max_ammo = 20
	goblins.current_ammo = 20
	goblins.range_distance = 35.0
	goblins.base_morale = 40.0
	goblins.faction_color = Color(0.4, 0.6, 0.3)
	goblins.set_meta("upkeep_cost", 8)
	regiments.append(goblins)

	return regiments
