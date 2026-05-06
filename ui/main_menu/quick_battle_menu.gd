# Quick Battle Menu - Skirmish mode without campaign
extends Control


signal back_pressed

@onready var terrain_option: OptionButton = $Panel/MarginContainer/VBoxContainer/SettingsGrid/TerrainOption
@onready var army_size_option: OptionButton = $Panel/MarginContainer/VBoxContainer/SettingsGrid/ArmySizeOption
@onready var difficulty_option: OptionButton = $Panel/MarginContainer/VBoxContainer/SettingsGrid/DifficultyOption
@onready var start_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/StartButton
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/BackButton

const TERRAIN_TYPES := ["plains", "hills", "forest", "village"]
const ARMY_SIZES := ["Small (3 regiments)", "Medium (5 regiments)", "Large (8 regiments)"]
const DIFFICULTIES := ["Easy", "Normal", "Hard", "Brutal"]


func _ready() -> void:
	_setup_options()
	_connect_signals()


func _setup_options() -> void:
	# Terrain
	terrain_option.clear()
	for terrain in TERRAIN_TYPES:
		terrain_option.add_item(terrain.capitalize())

	# Army size
	army_size_option.clear()
	for size in ARMY_SIZES:
		army_size_option.add_item(size)
	army_size_option.selected = 1  # Default: Medium

	# Difficulty
	difficulty_option.clear()
	for diff in DIFFICULTIES:
		difficulty_option.add_item(diff)
	difficulty_option.selected = 1  # Default: Normal


func _connect_signals() -> void:
	start_button.pressed.connect(_on_start_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _on_start_pressed() -> void:
	var terrain: String = TERRAIN_TYPES[terrain_option.selected]
	var army_size: int = army_size_option.selected
	var difficulty: int = difficulty_option.selected

	# Create player regiments based on army size
	var player_regiments := _create_player_army(army_size)
	var enemy_regiments := _create_enemy_army(army_size, difficulty)

	# Set up battle data directly (skip campaign)
	BattleTransition.from_campaign = false
	BattleTransition.battle_data = {
		"player_regiments": player_regiments,
		"enemy_regiments": enemy_regiments,
		"terrain_type": terrain,
		"is_contract": false,
		"is_quick_battle": true,
	}

	# Go directly to battle scene
	get_tree().change_scene_to_file("res://scenes/battle_scene.tscn")


func _on_back_pressed() -> void:
	back_pressed.emit()


func _create_player_army(size_index: int) -> Array:
	var regiments: Array = []
	var regiment_counts: Array[int] = [3, 5, 8]
	var count: int = regiment_counts[size_index]

	# Always have at least 1 of each type
	regiments.append(_create_regiment("Swordsmen", UnitType.Type.INFANTRY, 40, 12, 12))
	regiments.append(_create_regiment("Spearmen", UnitType.Type.INFANTRY, 40, 10, 14))
	regiments.append(_create_regiment("Archers", UnitType.Type.RANGED, 30, 6, 6, true))

	# Add more based on size
	while regiments.size() < count:
		var roll := randi() % 4
		match roll:
			0: regiments.append(_create_regiment("Militia", UnitType.Type.INFANTRY, 50, 8, 8))
			1: regiments.append(_create_regiment("Knights", UnitType.Type.CAVALRY, 20, 16, 14))
			2: regiments.append(_create_regiment("Crossbowmen", UnitType.Type.RANGED, 25, 5, 7, true))
			3: regiments.append(_create_regiment("Men-at-Arms", UnitType.Type.INFANTRY, 35, 14, 14))

	return regiments


func _create_enemy_army(size_index: int, difficulty: int) -> Array:
	var regiments: Array = []
	var regiment_counts: Array[int] = [3, 5, 8]
	var count: int = regiment_counts[size_index]

	# Difficulty multiplier for stats
	var mult := 0.8 + (difficulty * 0.15)  # 0.8, 0.95, 1.1, 1.25

	# Basic enemy army
	regiments.append(_create_enemy_regiment("Enemy Warriors", UnitType.Type.INFANTRY, int(45 * mult), int(11 * mult), int(11 * mult)))
	regiments.append(_create_enemy_regiment("Enemy Spears", UnitType.Type.INFANTRY, int(40 * mult), int(9 * mult), int(13 * mult)))
	regiments.append(_create_enemy_regiment("Enemy Archers", UnitType.Type.RANGED, int(30 * mult), int(6 * mult), int(6 * mult), true))

	while regiments.size() < count:
		var roll := randi() % 3
		match roll:
			0: regiments.append(_create_enemy_regiment("Marauders", UnitType.Type.INFANTRY, int(50 * mult), int(10 * mult), int(8 * mult)))
			1: regiments.append(_create_enemy_regiment("Raiders", UnitType.Type.CAVALRY, int(18 * mult), int(14 * mult), int(12 * mult)))
			2: regiments.append(_create_enemy_regiment("Skirmishers", UnitType.Type.RANGED, int(25 * mult), int(5 * mult), int(5 * mult), true))

	return regiments


func _create_regiment(reg_name: String, unit_type: int, soldiers: int, attack: int, defense: int, is_ranged: bool = false) -> RegimentData:
	var reg := RegimentData.new()
	reg.regiment_name = reg_name
	reg.unit_type = unit_type
	reg.max_soldiers = soldiers
	reg.current_soldiers = soldiers
	reg.attack = attack
	reg.defense = defense
	reg.weapon_skill = attack  # Use attack as weapon skill
	reg.strength = 3 + (attack / 5)  # Scale strength with attack
	reg.armor = defense / 2  # Scale armor with defense
	reg.base_morale = 75.0
	reg.faction_color = Color(0.3, 0.5, 0.8)  # Blue for player
	# Set speeds based on unit type
	if unit_type == UnitType.Type.CAVALRY:
		reg.walk_speed = 2.5
		reg.run_speed = 3.0
		reg.charge_speed = 5.0
		reg.charge_bonus = 10
		reg.mass = 2.5
	if is_ranged:
		reg.ballistic_skill = 12
		reg.max_ammo = 24
		reg.current_ammo = 24
		reg.range_distance = 40.0
	return reg


func _create_enemy_regiment(reg_name: String, unit_type: int, soldiers: int, attack: int, defense: int, is_ranged: bool = false) -> RegimentData:
	var reg := _create_regiment(reg_name, unit_type, soldiers, attack, defense, is_ranged)
	reg.faction_color = Color(0.8, 0.2, 0.2)  # Red for enemy
	return reg
