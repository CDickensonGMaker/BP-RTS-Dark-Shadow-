class_name UnitZooController
extends Node

## Unit Zoo Controller
## Debug scene for testing individual units: formations, pathfinding, combat,
## morale, stamina, and ammo systems.

const REGIMENT_SCENE: PackedScene = preload("res://battle_system/nodes/regiment.tscn")
const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")
const MeleeDuelRunnerScript = preload("res://battle_system/testing/melee_duel_runner.gd")
const BattleObjectiveClass = preload("res://battle_system/ai/data/battle_objective.gd")
const CapturePointScript = preload("res://battle_system/objectives/capture_point.gd")

# Building GLB models for stress test scenery
const BUILDING_MODELS: Array[String] = [
	"res://assets/models/buildings/house_small.glb",
	"res://assets/models/buildings/house_medium.glb",
	"res://assets/models/buildings/cottage.glb",
	"res://assets/models/buildings/shop.glb",
	"res://assets/models/buildings/blacksmith.glb",
	"res://assets/models/buildings/watch_tower.glb",
]

# UI References - Left side controls (VBox is now inside ScrollContainer)
@onready var player_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/PlayerColumn/PlayerUnitSelector
@onready var enemy_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/EnemyColumn/EnemyUnitSelector
@onready var formation_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/PlayerColumn/FormationSelector
@onready var stance_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/PlayerColumn/StanceSelector
@onready var enemy_formation_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/EnemyColumn/EnemyFormationSelector
@onready var enemy_stance_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/EnemyColumn/EnemyStanceSelector
@onready var player_info: Label = $ZooDebugUI/MainLayout/LeftSide/InfoPanel/InfoContainer/PlayerInfo
@onready var enemy_info: Label = $ZooDebugUI/MainLayout/LeftSide/InfoPanel/InfoContainer/EnemyInfo
@onready var lock_enemy_toggle: CheckButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/LockEnemyToggle

# Stat adjustment UI references
@onready var player_vet_value: Label = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/PlayerColumn/VeterancyRow/VetValue
@onready var player_armor_value: Label = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/PlayerColumn/ArmorRow/ArmorValue
@onready var player_attack_value: Label = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/PlayerColumn/AttackRow/AttackValue
@onready var enemy_vet_value: Label = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/EnemyColumn/EnemyVeterancyRow/VetValue
@onready var enemy_armor_value: Label = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/EnemyColumn/EnemyArmorRow/ArmorValue
@onready var enemy_attack_value: Label = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/SideBySide/EnemyColumn/EnemyAttackRow/AttackValue

# Filter UI references
@onready var faction_filter: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/FilterRow/FactionFilter
@onready var type_filter: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/FilterRow/TypeFilter

# Weather UI references
@onready var weather_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/WeatherRow/WeatherSelector
@onready var weather_info: Label = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/WeatherRow/WeatherInfo

# Battle control UI
@onready var start_battle_button: Button = $ZooDebugUI/MainLayout/LeftSide/BattleControlPanel/StartBattleButton

# 3D viewport references
@onready var battle_viewport: SubViewport = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport
@onready var unit_container: Node3D = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport/BattleWorld/Units
@onready var battle_camera: Camera3D = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport/BattleWorld/BattleCamera
@onready var camera_lock_toggle: CheckButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox/CameraLockToggle
@onready var selection_overlay: CanvasLayer = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport/SelectionBoxOverlay
@onready var viewport_container: SubViewportContainer = $ZooDebugUI/MainLayout/ViewportContainer
@onready var battle_hud: BattleHUD = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport/BattleHUD

# Multi-unit support
var player_regiment: Node = null  # Primary player regiment (for backwards compatibility)
var enemy_regiment: Node = null   # Primary enemy regiment (for backwards compatibility)
var player_regiments: Array[Node] = []
var enemy_regiments: Array[Node] = []
const MAX_UNITS_PER_SIDE: int = 6
var all_unit_ids: Array = []

# Selection tracking for battle controls
var _selected_regiments: Array[Node] = []
var _is_dragging_formation: bool = false
var _formation_drag_start: Vector3 = Vector3.ZERO

# AI controller initialization retry tracking
var _aggressive_retry_counts: Dictionary = {}  # regiment -> int
const MAX_AGGRESSIVE_RETRIES: int = 10

# Default starting units
const DEFAULT_PLAYER_UNIT: String = "grtcanon"  # Changed for testing artillery melee
const DEFAULT_ENEMY_UNIT: String = "orcboyz"

# Auto-test state
var _auto_test_running: bool = false
var _auto_test_index: int = 0
var _auto_test_errors: Array = []
var _auto_test_delay: float = 0.3  # seconds between each unit

# Melee duel test state
var _melee_duel_runner: Node = null

# Stress test UI counter (upper right)
var _stress_test_counter_label: Label = null

# Set to true to auto-start testing on scene load (for MCP automation)
# Disabled by default - press T to manually start auto-test
@export var auto_start_test: bool = false

# Auto-start battle stress test on load (for automated testing while away)
@export var auto_start_battle_stress: bool = false
@export var battle_stress_rounds: int = 5
@export var battle_stress_duration: float = 60.0  # 1 min per battle - faster iteration for daemon

# Debug: Melee position tracking
var _melee_debug_timer: float = 0.0
const MELEE_DEBUG_INTERVAL: float = 2.0
@export var battle_stress_units_per_side: int = 6
@export var stress_test_basic_infantry_only: bool = false  # Only use melee infantry for core loop testing
@export var stress_test_faction_based: bool = true  # Use faction-specific unit pools
@export var stress_test_headless: bool = false  # Enable sprites so you can see the battles
@export var stress_test_exclude_artillery: bool = false  # Exclude artillery/siege units
@export var stress_test_weather_variation: bool = false  # Change weather every 2 battles
@export var stress_test_attacker_defender_objectives: bool = false  # Use BattleObjective asymmetry
@export var stress_test_always_include_general: bool = false  # Always include a general/hero for player side
@export var stress_test_include_capture_point: bool = false  # Add a siege capture point in the center
@export var stress_test_include_buildings: bool = false  # Spawn buildings around the battlefield
@export var stress_test_siege_mode: bool = false  # Use full town layout with chokepoints
@export var stress_test_3x_map: bool = false  # Use 3x larger map for siege battles
@export var stress_test_quit_when_done: bool = false  # Quit Godot after stress tests (for daemon/headless)

# Siege mode spawn positions (3x larger map)
const SIEGE_PLAYER_SPAWN_X: float = -75.0  # Attacker spawn (west)
const SIEGE_ENEMY_SPAWN_X: float = 75.0    # Defender spawn (east)
const SIEGE_TOWN_CENTER: Vector3 = Vector3(40, 0, 0)  # Capture point location

# Extended building models for town layout
const TOWN_BUILDING_MODELS: Dictionary = {
	# Defensive structures
	"gate_house": "res://assets/models/buildings/gate_house.glb",
	"guard_tower": "res://assets/models/buildings/guard_tower.glb",
	"watch_tower": "res://assets/models/buildings/watch_tower.glb",
	"wooden_outpost_tower": "res://assets/models/buildings/wooden_outpost_tower.glb",
	"wall_small": "res://assets/models/buildings/wall_small.glb",
	"wall_medium": "res://assets/models/buildings/wall_medium.glb",
	"wall_large": "res://assets/models/buildings/wall_large.glb",
	# Residential
	"house_small": "res://assets/models/buildings/house_small.glb",
	"house_medium": "res://assets/models/buildings/house_medium.glb",
	"house_large": "res://assets/models/buildings/house_large.glb",
	"cottage": "res://assets/models/buildings/cottage.glb",
	"hovel": "res://assets/models/buildings/hovel.glb",
	# Commercial
	"shop": "res://assets/models/buildings/shop.glb",
	"blacksmith": "res://assets/models/buildings/blacksmith.glb",
	"warehouse": "res://assets/models/buildings/warehouse.glb",
	"market_stall": "res://assets/models/buildings/market_stall.glb",
	# Civic
	"town_hall": "res://assets/models/buildings/town_hall.glb",
}

# Faction to general mapping for stress tests
const FACTION_GENERALS: Dictionary = {
	"Empire": "empire_general",
	"Dwarfs": "dwarf_general",
	"Orcs": "orc_general",
	"Undead": "undead_general",
	"Skaven": "seer",  # Skaven use Grey Seer as general
}

# Melee duel torture test (isolated 1v1 fights with invariant checking)
@export var auto_start_melee_duel_test: bool = false
@export var melee_duel_test_rounds: int = 1000
@export var melee_duel_rally_cycles: int = 3

# Basic infantry unit IDs for focused combat loop testing (no ranged, artillery, monsters)
const BASIC_INFANTRY_IDS: Array[String] = [
	"mcsword", "grtsword", "hammers", "halberd", "spears", "swords",
	"orcboyz", "blorc", "goblin", "clanrats", "stmverm",
	"skeletons", "graveguard", "bandit"
]

# Faction-based unit pools for more realistic battle compositions
const FACTION_POOLS: Dictionary = {
	"Empire": [
		# Melee Infantry
		"grtsword", "mcsword", "empsword", "carlgrd", "bodygrd", "peasant", "avengers", "hammers",
		# Spear/Halberd
		"halb", "nlnhlb",
		# Cavalry
		"reik", "brdhrs", "keelers", "mtdrks",
		# Ranged
		"xbow", "mercxbow",
		# Artillery
		"mortar", "grtcanon", "voleygun", "impcanon",
	],
	"Dwarfs": [
		# Melee Infantry
		"dwwar", "iron", "ironbrks", "dwslay", "ragnar", "engrol",
		# Ranged
		"dwxbow",
		# Artillery/Machines
		"dwheel", "gyrocopt",
	],
	"Orcs": [
		# Goblin Infantry
		"gob1", "ntgoblin", "fanatic", "squigs",
		# Orc Infantry
		"orcboyz", "biguns", "blackorc",
		# Cavalry
		"wolfride", "boarboyz",
		# Ranged
		"gobarch", "arraboyz",
		# Artillery
		"rocklob",
		# Monsters
		"troll", "giant",
	],
	"Undead": [
		# Melee Infantry
		"vanheims", "graveguard",
		# Cavalry
		"graveknight",
		# Ranged
		"gravearch",
	],
	"Skaven": [
		# Melee Infantry
		"clanrats", "stmverm", "ratslave", "eshin", "plagmonk", "packmast",
		# Artillery/Weapons Teams
		"warpfire", "doomdivr",
		# Monsters
		"ratogre",
	],
}

# Factions list for random selection
const FACTION_LIST: Array[String] = ["Empire", "Dwarfs", "Orcs", "Undead", "Skaven"]

# === PROJECTILE SYSTEM DEBUG ===

# Projectile debug UI (created programmatically)
var _projectile_debug_label: Label = null
var _round_type_selector: OptionButton = null
var _ranged_presets_container: HBoxContainer = null

# WorldCompass debug UI
var _compass_debug_label: Label = null

# Spell testing UI
var _spell_buttons_container: HBoxContainer = null
var _spell_debug_label: Label = null
var _spell_buttons: Array[Button] = []

# Ranged unit presets for quick testing
const RANGED_PRESETS: Dictionary = {
	"Archers": "gobarch",      # Goblin Archers (VOLLEY pattern)
	"Crossbow": "xbow",        # Crossbowmen (STAGGER pattern)
	"Handgun": "engr",         # Engineers/Handgunners
	"Cannon": "grtcanon",      # Great Cannon (SINGLE, artillery)
	"Mortar": "mortar",        # Mortar (HIGH_ARC, indirect)
}

# Hero/wizard presets for spell testing
const HERO_PRESETS: Dictionary = {
	"Empire": "empire_general",   # Empire General (Hold the Line, Healing Light, Fireball)
	"Dwarf": "dwarf_general",     # Dwarf Thane (Ancestral Might, Fireball)
	"Orc": "orc_general",         # Orc Warboss (WAAAGH!, Fireball)
	"Undead": "undead_general",   # Vampire Lord (Dread Aura, Fireball)
	"Bright": "briwiz",           # Bright Wizard
	"Celestial": "celwiz",        # Celestial Wizard
}

const ENEMY_RANGED_PRESETS: Dictionary = {
	"Infantry": "orcboyz",     # Orc Boyz (melee target)
	"Archers": "arraboyz",     # Arrer Boyz (ranged)
	"Cavalry": "wolfride",     # Wolf Riders (fast target)
	"Monster": "troll",        # Troll (large target)
}


func _ready() -> void:
	# Detect headless mode (daemon/automated testing)
	var is_headless: bool = DisplayServer.get_name() == "headless"
	if is_headless:
		print("[UnitZoo] Running in HEADLESS mode - skipping UI initialization")
		# In headless mode, skip UI setup and go straight to stress tests
		# Enable combat debugging
		if CombatManager:
			CombatManager.debug_combat = true
		# Auto-start stress tests immediately in headless mode
		if auto_start_battle_stress:
			call_deferred("_auto_start_battle_stress_after_delay")
		return  # Skip all UI initialization

	_populate_filters()
	_populate_unit_dropdowns()
	_populate_formation_dropdown()
	_populate_stance_dropdown()
	_populate_weather_dropdown()
	_connect_signals()

	# Create projectile system debug UI
	_create_projectile_debug_ui()

	# Create stress test counter label (upper right corner)
	_create_stress_test_counter()

	# Enable combat debugging by default in Unit Zoo
	if CombatManager:
		CombatManager.debug_combat = true
		print("[UnitZoo] Combat debug enabled (press D to toggle)")

	# Spawn initial units after a frame to ensure autoloads are ready
	call_deferred("_spawn_initial_units")

	# Auto-start test if enabled (for MCP automation)
	if auto_start_test:
		call_deferred("_auto_start_after_delay")

	# Auto-start battle stress test if enabled (for automated testing)
	if auto_start_battle_stress:
		call_deferred("_auto_start_battle_stress_after_delay")

	# Auto-start melee duel torture test if enabled
	if auto_start_melee_duel_test:
		call_deferred("_auto_start_melee_duel_after_delay")


func _populate_filters() -> void:
	if not faction_filter or not type_filter:
		return

	# Populate faction filter
	faction_filter.clear()
	for faction_name in UnitCatalog.get_available_factions():
		faction_filter.add_item(faction_name)

	# Populate type filter
	type_filter.clear()
	for type_name in UnitCatalog.get_available_types():
		type_filter.add_item(type_name)


func _populate_unit_dropdowns() -> void:
	# Get current filter values
	var faction_val: String = "All"
	var type_val: String = "All"
	if faction_filter and faction_filter.selected >= 0:
		faction_val = faction_filter.get_item_text(faction_filter.selected)
	if type_filter and type_filter.selected >= 0:
		type_val = type_filter.get_item_text(type_filter.selected)

	# Use filtered ZOO units
	all_unit_ids = UnitCatalog.get_filtered_zoo_units(faction_val, type_val)

	player_selector.clear()
	enemy_selector.clear()

	var player_default_idx: int = 0
	var enemy_default_idx: int = 0
	var valid_idx: int = 0

	for i in range(all_unit_ids.size()):
		var unit_id: String = all_unit_ids[i]
		var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
		if not data:
			continue  # Skip missing units

		var display_name: String = data.regiment_name

		player_selector.add_item(display_name)
		player_selector.set_item_metadata(valid_idx, unit_id)

		enemy_selector.add_item(display_name)
		enemy_selector.set_item_metadata(valid_idx, unit_id)

		if unit_id == DEFAULT_PLAYER_UNIT:
			player_default_idx = valid_idx
		if unit_id == DEFAULT_ENEMY_UNIT:
			enemy_default_idx = valid_idx

		valid_idx += 1

	# Select defaults if available, otherwise first item
	if player_selector.item_count > 0:
		player_selector.select(mini(player_default_idx, player_selector.item_count - 1))
	if enemy_selector.item_count > 0:
		enemy_selector.select(mini(enemy_default_idx, enemy_selector.item_count - 1))


func _populate_formation_dropdown() -> void:
	var formations: Array[String] = ["Line", "Column", "Wedge", "Square", "Loose", "Shield Wall", "Schiltron"]

	formation_selector.clear()
	enemy_formation_selector.clear()

	for formation in formations:
		formation_selector.add_item(formation)
		enemy_formation_selector.add_item(formation)


func _populate_stance_dropdown() -> void:
	# Match actual CommanderAI.Stance enum order: DEFENSIVE=0, AGGRESSIVE=1, WITHDRAWING=2
	var stances: Array[String] = ["Defensive", "Aggressive", "Withdrawing"]

	stance_selector.clear()
	enemy_stance_selector.clear()

	for stance in stances:
		stance_selector.add_item(stance)
		enemy_stance_selector.add_item(stance)


func _populate_weather_dropdown() -> void:
	if not weather_selector:
		return

	weather_selector.clear()

	# Match WeatherType.Type enum order
	var weathers: Array[String] = ["Clear", "Rain", "Fog", "Storm", "Snow", "Blizzard"]

	for i in range(weathers.size()):
		weather_selector.add_item(weathers[i])
		weather_selector.set_item_metadata(i, i)  # Store enum value

	# Default to clear
	weather_selector.select(0)


func _connect_signals() -> void:
	player_selector.item_selected.connect(_on_player_unit_changed)
	enemy_selector.item_selected.connect(_on_enemy_unit_changed)
	formation_selector.item_selected.connect(_on_formation_changed)
	stance_selector.item_selected.connect(_on_stance_changed)
	enemy_formation_selector.item_selected.connect(_on_enemy_formation_changed)
	enemy_stance_selector.item_selected.connect(_on_enemy_stance_changed)

	# Filter dropdowns
	if faction_filter:
		faction_filter.item_selected.connect(_on_filter_changed)
	if type_filter:
		type_filter.item_selected.connect(_on_filter_changed)

	# Weather selector
	if weather_selector:
		weather_selector.item_selected.connect(_on_weather_changed)

	# Camera lock toggle
	camera_lock_toggle.toggled.connect(_on_camera_lock_toggled)

	# Start battle button
	if start_battle_button:
		start_battle_button.pressed.connect(_on_start_battle_pressed)

	# Connect player action button signals
	var vbox: VBoxContainer = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox
	vbox.get_node("ActionButtons/MoveButton").pressed.connect(_on_move_button_pressed)
	vbox.get_node("ActionButtons/AttackButton").pressed.connect(_on_attack_button_pressed)
	vbox.get_node("ActionButtons/ChargeButton").pressed.connect(_on_charge_button_pressed)
	vbox.get_node("ActionButtons/DisengageButton").pressed.connect(_on_disengage_button_pressed)
	vbox.get_node("ResetButton").pressed.connect(_on_reset_button_pressed)

	# Connect enemy action button signals
	vbox.get_node("EnemyActionButtons/EnemyMoveButton").pressed.connect(_on_enemy_move_button_pressed)
	vbox.get_node("EnemyActionButtons/EnemyAttackButton").pressed.connect(_on_enemy_attack_button_pressed)
	vbox.get_node("EnemyActionButtons/EnemyChargeButton").pressed.connect(_on_enemy_charge_button_pressed)
	vbox.get_node("EnemyActionButtons/EnemyDisengageButton").pressed.connect(_on_enemy_disengage_button_pressed)

	# Connect add/clear unit buttons (if they exist)
	var player_col = vbox.get_node("SideBySide/PlayerColumn")
	var enemy_col = vbox.get_node("SideBySide/EnemyColumn")
	if player_col.has_node("AddPlayerButton"):
		player_col.get_node("AddPlayerButton").pressed.connect(_on_add_player_unit_pressed)
	if player_col.has_node("ClearPlayerButton"):
		player_col.get_node("ClearPlayerButton").pressed.connect(_on_clear_player_units_pressed)
	if enemy_col.has_node("AddEnemyButton"):
		enemy_col.get_node("AddEnemyButton").pressed.connect(_on_add_enemy_unit_pressed)
	if enemy_col.has_node("ClearEnemyButton"):
		enemy_col.get_node("ClearEnemyButton").pressed.connect(_on_clear_enemy_units_pressed)

	# Lock enemy toggle
	lock_enemy_toggle.toggled.connect(_on_lock_enemy_toggled)

	# Connect stat adjustment buttons
	if player_col.has_node("VeterancyRow/VetUp"):
		player_col.get_node("VeterancyRow/VetUp").pressed.connect(_on_player_vet_up_pressed)
	if player_col.has_node("VeterancyRow/VetDown"):
		player_col.get_node("VeterancyRow/VetDown").pressed.connect(_on_player_vet_down_pressed)
	if player_col.has_node("ArmorRow/ArmorUp"):
		player_col.get_node("ArmorRow/ArmorUp").pressed.connect(_on_player_armor_up_pressed)
	if player_col.has_node("ArmorRow/ArmorDown"):
		player_col.get_node("ArmorRow/ArmorDown").pressed.connect(_on_player_armor_down_pressed)
	if player_col.has_node("AttackRow/AttackUp"):
		player_col.get_node("AttackRow/AttackUp").pressed.connect(_on_player_attack_up_pressed)
	if player_col.has_node("AttackRow/AttackDown"):
		player_col.get_node("AttackRow/AttackDown").pressed.connect(_on_player_attack_down_pressed)

	if enemy_col.has_node("EnemyVeterancyRow/VetUp"):
		enemy_col.get_node("EnemyVeterancyRow/VetUp").pressed.connect(_on_enemy_vet_up_pressed)
	if enemy_col.has_node("EnemyVeterancyRow/VetDown"):
		enemy_col.get_node("EnemyVeterancyRow/VetDown").pressed.connect(_on_enemy_vet_down_pressed)
	if enemy_col.has_node("EnemyArmorRow/ArmorUp"):
		enemy_col.get_node("EnemyArmorRow/ArmorUp").pressed.connect(_on_enemy_armor_up_pressed)
	if enemy_col.has_node("EnemyArmorRow/ArmorDown"):
		enemy_col.get_node("EnemyArmorRow/ArmorDown").pressed.connect(_on_enemy_armor_down_pressed)
	if enemy_col.has_node("EnemyAttackRow/AttackUp"):
		enemy_col.get_node("EnemyAttackRow/AttackUp").pressed.connect(_on_enemy_attack_up_pressed)
	if enemy_col.has_node("EnemyAttackRow/AttackDown"):
		enemy_col.get_node("EnemyAttackRow/AttackDown").pressed.connect(_on_enemy_attack_down_pressed)


# =============================================================================
# PROJECTILE SYSTEM DEBUG UI
# =============================================================================

func _create_projectile_debug_ui() -> void:
	"""Create projectile debug panel with presets and round type selector."""
	var vbox: VBoxContainer = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/ScrollContainer/VBox
	if not vbox:
		return

	# === RANGED PRESETS ROW ===
	var presets_label := Label.new()
	presets_label.text = "-- Quick Ranged Presets --"
	presets_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Insert before the SideBySide container (after weather row)
	var weather_row_idx: int = -1
	for i in vbox.get_child_count():
		if vbox.get_child(i).name == "WeatherRow":
			weather_row_idx = i
			break
	if weather_row_idx >= 0:
		vbox.add_child(presets_label)
		vbox.move_child(presets_label, weather_row_idx + 1)

	# Player ranged presets
	_ranged_presets_container = HBoxContainer.new()
	_ranged_presets_container.name = "RangedPresetsRow"
	_ranged_presets_container.set("theme_override_constants/separation", 5)
	if weather_row_idx >= 0:
		vbox.add_child(_ranged_presets_container)
		vbox.move_child(_ranged_presets_container, weather_row_idx + 2)

	var player_label := Label.new()
	player_label.text = "Player:"
	_ranged_presets_container.add_child(player_label)

	for preset_name in RANGED_PRESETS:
		var btn := Button.new()
		btn.text = preset_name
		btn.custom_minimum_size = Vector2(55, 0)
		btn.pressed.connect(_on_ranged_preset_pressed.bind(RANGED_PRESETS[preset_name], true))
		_ranged_presets_container.add_child(btn)

	# Enemy target presets
	var enemy_presets_row := HBoxContainer.new()
	enemy_presets_row.name = "EnemyPresetsRow"
	enemy_presets_row.set("theme_override_constants/separation", 5)
	if weather_row_idx >= 0:
		vbox.add_child(enemy_presets_row)
		vbox.move_child(enemy_presets_row, weather_row_idx + 3)

	var enemy_label := Label.new()
	enemy_label.text = "Enemy:"
	enemy_presets_row.add_child(enemy_label)

	for preset_name in ENEMY_RANGED_PRESETS:
		var btn := Button.new()
		btn.text = preset_name
		btn.custom_minimum_size = Vector2(55, 0)
		btn.pressed.connect(_on_ranged_preset_pressed.bind(ENEMY_RANGED_PRESETS[preset_name], false))
		enemy_presets_row.add_child(btn)

	# === ROUND TYPE SELECTOR (for artillery) ===
	var round_row := HBoxContainer.new()
	round_row.name = "RoundTypeRow"
	round_row.set("theme_override_constants/separation", 10)
	if weather_row_idx >= 0:
		vbox.add_child(round_row)
		vbox.move_child(round_row, weather_row_idx + 4)

	var round_label := Label.new()
	round_label.text = "Ammo Type:"
	round_row.add_child(round_label)

	_round_type_selector = OptionButton.new()
	_round_type_selector.name = "RoundTypeSelector"
	_round_type_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Populate round types
	for round_type in WeaponClassData.RoundType.values():
		_round_type_selector.add_item(WeaponClassData.get_round_type_name(round_type))
		_round_type_selector.set_item_metadata(_round_type_selector.item_count - 1, round_type)
	_round_type_selector.item_selected.connect(_on_round_type_changed)
	round_row.add_child(_round_type_selector)

	# === PROJECTILE DEBUG LABEL ===
	_projectile_debug_label = Label.new()
	_projectile_debug_label.name = "ProjectileDebugLabel"
	_projectile_debug_label.text = "Projectiles: 0 active | Pool: 100 | Hits: 0"
	_projectile_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_projectile_debug_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	if weather_row_idx >= 0:
		vbox.add_child(_projectile_debug_label)
		vbox.move_child(_projectile_debug_label, weather_row_idx + 5)

	print("[UnitZoo] Projectile debug UI created (press P to toggle stats)")

	# === WORLDCOMPASS DEBUG LABEL ===
	_compass_debug_label = Label.new()
	_compass_debug_label.name = "CompassDebugLabel"
	_compass_debug_label.text = "Compass: -- | Camera: --"
	_compass_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_debug_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	if weather_row_idx >= 0:
		vbox.add_child(_compass_debug_label)
		vbox.move_child(_compass_debug_label, weather_row_idx + 6)

	print("[UnitZoo] WorldCompass debug enabled (shows unit facing)")

	# === SPELL TESTING UI ===
	_create_spell_test_ui(vbox, weather_row_idx + 7)


func _create_spell_test_ui(vbox: VBoxContainer, insert_idx: int) -> void:
	"""Create spell testing UI with hero presets and spell buttons."""

	# === HERO PRESETS LABEL ===
	var hero_label := Label.new()
	hero_label.text = "-- Hero/Wizard Presets (Spells) --"
	hero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hero_label)
	vbox.move_child(hero_label, insert_idx)

	# === HERO PRESET BUTTONS ===
	var hero_row := HBoxContainer.new()
	hero_row.name = "HeroPresetsRow"
	hero_row.set("theme_override_constants/separation", 5)
	vbox.add_child(hero_row)
	vbox.move_child(hero_row, insert_idx + 1)

	for preset_name in HERO_PRESETS:
		var btn := Button.new()
		btn.text = preset_name
		btn.custom_minimum_size = Vector2(55, 0)
		btn.pressed.connect(_on_hero_preset_pressed.bind(HERO_PRESETS[preset_name]))
		hero_row.add_child(btn)

	# === SPELL BUTTONS CONTAINER ===
	var spell_label := Label.new()
	spell_label.text = "Spells (1/2/3 to cast at enemy):"
	vbox.add_child(spell_label)
	vbox.move_child(spell_label, insert_idx + 2)

	_spell_buttons_container = HBoxContainer.new()
	_spell_buttons_container.name = "SpellButtonsRow"
	_spell_buttons_container.set("theme_override_constants/separation", 5)
	vbox.add_child(_spell_buttons_container)
	vbox.move_child(_spell_buttons_container, insert_idx + 3)

	# Create placeholder spell buttons (will be updated when hero is spawned)
	for i in range(4):
		var btn := Button.new()
		btn.text = "[%d] --" % (i + 1)
		btn.custom_minimum_size = Vector2(80, 0)
		btn.disabled = true
		btn.pressed.connect(_on_spell_button_pressed.bind(i))
		_spell_buttons_container.add_child(btn)
		_spell_buttons.append(btn)

	# === SPELL DEBUG LABEL ===
	_spell_debug_label = Label.new()
	_spell_debug_label.name = "SpellDebugLabel"
	_spell_debug_label.text = "Spells: No hero selected"
	_spell_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spell_debug_label.add_theme_color_override("font_color", Color(0.9, 0.7, 1.0))
	vbox.add_child(_spell_debug_label)
	vbox.move_child(_spell_debug_label, insert_idx + 4)

	print("[UnitZoo] Spell testing UI created (press 1/2/3 to cast spells)")


func _create_stress_test_counter() -> void:
	"""Create stress test counter label in upper right corner."""
	_stress_test_counter_label = Label.new()
	_stress_test_counter_label.name = "StressTestCounter"
	_stress_test_counter_label.text = ""
	_stress_test_counter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stress_test_counter_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_stress_test_counter_label.add_theme_font_size_override("font_size", 32)
	_stress_test_counter_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_stress_test_counter_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_stress_test_counter_label.add_theme_constant_override("outline_size", 4)

	# Position in upper right corner
	_stress_test_counter_label.anchors_preset = Control.PRESET_TOP_RIGHT
	_stress_test_counter_label.anchor_left = 1.0
	_stress_test_counter_label.anchor_right = 1.0
	_stress_test_counter_label.anchor_top = 0.0
	_stress_test_counter_label.anchor_bottom = 0.0
	_stress_test_counter_label.offset_left = -200
	_stress_test_counter_label.offset_right = -20
	_stress_test_counter_label.offset_top = 20
	_stress_test_counter_label.offset_bottom = 60

	# Add to viewport container so it overlays the battle view
	if viewport_container:
		viewport_container.add_child(_stress_test_counter_label)
	else:
		add_child(_stress_test_counter_label)

	_stress_test_counter_label.visible = false  # Hidden until stress test starts


func _update_stress_test_counter() -> void:
	"""Update the stress test counter display."""
	if _stress_test_counter_label:
		_stress_test_counter_label.text = "%d / %d" % [_battle_stress_round, _battle_stress_max_rounds]
		_stress_test_counter_label.visible = _battle_stress_running


func _on_hero_preset_pressed(unit_id: String) -> void:
	"""Quick spawn a hero preset unit with spells."""
	_spawn_player_unit(unit_id)
	# Update dropdown to match
	for i in player_selector.item_count:
		if player_selector.get_item_metadata(i) == unit_id:
			player_selector.select(i)
			break
	print("[UnitZoo] Spawned hero preset: %s" % unit_id)
	# Update spell buttons after a frame (regiment needs to initialize)
	call_deferred("_update_spell_buttons")


func _update_spell_buttons() -> void:
	"""Update spell buttons to show available spells for current player unit."""
	if not _spell_buttons_container:
		return

	# Reset all buttons
	for i in range(_spell_buttons.size()):
		_spell_buttons[i].text = "[%d] --" % (i + 1)
		_spell_buttons[i].disabled = true
		_spell_buttons[i].tooltip_text = ""

	if not player_regiment or not is_instance_valid(player_regiment):
		if _spell_debug_label:
			_spell_debug_label.text = "Spells: No unit selected"
		return

	# Get available spells
	var spells: Array[SpellData] = player_regiment.get_available_spells()

	if spells.size() == 0:
		if _spell_debug_label:
			_spell_debug_label.text = "Spells: %s has no spells" % player_regiment.data.regiment_name
		return

	# Update buttons with spell info
	for i in range(mini(spells.size(), _spell_buttons.size())):
		var spell: SpellData = spells[i]
		_spell_buttons[i].text = "[%d] %s" % [i + 1, spell.display_name]
		_spell_buttons[i].disabled = false
		_spell_buttons[i].tooltip_text = spell.description

	if _spell_debug_label:
		_spell_debug_label.text = "Spells: %s has %d spells (CD: %.0fs)" % [
			player_regiment.data.regiment_name,
			spells.size(),
			spells[0].cooldown if spells.size() > 0 else 0
		]


func _on_spell_button_pressed(spell_index: int) -> void:
	"""Cast the spell at the given index at enemy position."""
	_cast_spell_at_enemy(spell_index)


func _cast_spell_at_enemy(spell_index: int) -> void:
	"""Cast spell at spell_index toward enemy regiment."""
	if not player_regiment or not is_instance_valid(player_regiment):
		print("[UnitZoo] No player unit to cast spell")
		return

	var spells: Array[SpellData] = player_regiment.get_available_spells()
	if spell_index >= spells.size():
		print("[UnitZoo] No spell at index %d" % spell_index)
		return

	var spell: SpellData = spells[spell_index]

	# Get target position (enemy or center)
	var target_pos: Vector3 = Vector3(15, 0, 0)  # Default to enemy spawn
	if enemy_regiment and is_instance_valid(enemy_regiment):
		target_pos = enemy_regiment.global_position

	# Check if can cast
	if not player_regiment.can_cast_spell(spell, target_pos):
		print("[UnitZoo] Cannot cast %s (cooldown or out of range)" % spell.display_name)
		return

	# Cast the spell
	var success: bool = player_regiment.cast_spell(spell, target_pos)
	if success:
		print("[UnitZoo] Cast %s at (%.1f, %.1f, %.1f)" % [spell.display_name, target_pos.x, target_pos.y, target_pos.z])
	else:
		print("[UnitZoo] Failed to cast %s" % spell.display_name)


func _update_projectile_debug() -> void:
	"""Update projectile debug display with current pool stats."""
	if not _projectile_debug_label:
		return

	# Get projectile pool stats via CombatManager's public method
	var stats: Dictionary = {}
	if CombatManager:
		stats = CombatManager.get_projectile_stats()

	if stats.size() > 0:
		var active: int = stats.get("active_count", 0)
		var available: int = stats.get("pool_size", 0)
		var spawned: int = stats.get("spawned_total", 0)
		var hit_rate: float = stats.get("pool_hit_rate", 100.0)
		var max_reached: int = stats.get("max_active_reached", 0)

		_projectile_debug_label.text = "Projectiles: %d active | Pool: %d | Spawned: %d | Hit%%: %.1f%%" % [
			active, available, spawned, hit_rate
		]

		# Color code based on pool health
		if active > 150:
			_projectile_debug_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))  # Orange warning
		elif max_reached > 0:
			_projectile_debug_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))  # Red critical
		else:
			_projectile_debug_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))  # Green healthy
	else:
		_projectile_debug_label.text = "Projectile pool not available"


func _on_ranged_preset_pressed(unit_id: String, is_player: bool) -> void:
	"""Quick spawn a ranged preset unit."""
	if is_player:
		_spawn_player_unit(unit_id)
		# Update dropdown to match
		for i in player_selector.item_count:
			if player_selector.get_item_metadata(i) == unit_id:
				player_selector.select(i)
				break
		print("[UnitZoo] Spawned player ranged preset: %s" % unit_id)
	else:
		_spawn_enemy_unit(unit_id)
		# Update dropdown to match
		for i in enemy_selector.item_count:
			if enemy_selector.get_item_metadata(i) == unit_id:
				enemy_selector.select(i)
				break
		print("[UnitZoo] Spawned enemy target preset: %s" % unit_id)


func _on_round_type_changed(index: int) -> void:
	"""Change artillery round type for player regiment."""
	if not player_regiment or not is_instance_valid(player_regiment):
		return

	var round_type: int = _round_type_selector.get_item_metadata(index)

	# Check if player unit is artillery
	if not WeaponClassData.is_artillery_weapon(player_regiment.data.weapon_class):
		print("[UnitZoo] Round type only applies to artillery units")
		return

	# Apply round type to regiment
	if "current_round_type" in player_regiment:
		player_regiment.current_round_type = round_type
	elif player_regiment.data:
		# Store on data for combat system to use
		player_regiment.data.set_meta("round_type", round_type)

	print("[UnitZoo] Changed ammo to: %s" % WeaponClassData.get_round_type_name(round_type))

	# Emit signal if available
	if BattleSignals:
		BattleSignals.round_type_changed.emit(player_regiment, round_type)


func _cycle_round_type() -> void:
	"""Cycle through artillery round types (R hotkey)."""
	if not _round_type_selector:
		return

	if not player_regiment or not is_instance_valid(player_regiment):
		print("[UnitZoo] No player unit to change ammo")
		return

	if not WeaponClassData.is_artillery_weapon(player_regiment.data.weapon_class):
		print("[UnitZoo] Current unit is not artillery - spawn Cannon/Mortar first")
		return

	var current: int = _round_type_selector.selected
	var next_idx: int = (current + 1) % _round_type_selector.item_count
	_round_type_selector.select(next_idx)
	_on_round_type_changed(next_idx)


func _input(event: InputEvent) -> void:
	# Handle keyboard hotkeys
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			camera_lock_toggle.button_pressed = not camera_lock_toggle.button_pressed
		elif event.keycode == KEY_T:
			if not _auto_test_running:
				start_auto_test()
			else:
				stop_auto_test()
		# Battle stress test (B)
		elif event.keycode == KEY_B:
			if not _battle_stress_running:
				start_battle_stress_test(40, 60.0, 3)  # 40 rounds, 60s each, 3 units/side
			else:
				stop_battle_stress_test()
		# Melee duel torture test (M)
		elif event.keycode == KEY_M:
			if _melee_duel_runner == null or not is_instance_valid(_melee_duel_runner):
				start_melee_duel_test()
			else:
				stop_melee_duel_test()
		# Weather hotkey (G to cycle - "Ground conditions")
		elif event.keycode == KEY_G:
			_cycle_weather()
		# Debug toggle (D)
		elif event.keycode == KEY_D:
			if CombatManager:
				CombatManager.debug_combat = not CombatManager.debug_combat
				print("[UnitZoo] Combat debug %s" % ("ENABLED" if CombatManager.debug_combat else "DISABLED"))
		# Projectile debug toggle (P)
		elif event.keycode == KEY_P:
			if _projectile_debug_label:
				_projectile_debug_label.visible = not _projectile_debug_label.visible
				print("[UnitZoo] Projectile debug %s" % ("shown" if _projectile_debug_label.visible else "hidden"))
		# Cycle round type for artillery (R)
		elif event.keycode == KEY_R:
			_cycle_round_type()
		# Stance hotkeys (Z/X/C)
		elif event.keycode == KEY_Z:
			_set_selected_stance(CommanderAI.Stance.AGGRESSIVE)
		elif event.keycode == KEY_X:
			_set_selected_stance(CommanderAI.Stance.DEFENSIVE)
		elif event.keycode == KEY_C:
			_set_selected_stance(CommanderAI.Stance.WITHDRAWING)
		# Formation hotkeys (F1-F4)
		elif event.keycode == KEY_F1:
			_set_selected_formation(FormationType.Type.LINE)
		elif event.keycode == KEY_F2:
			_set_selected_formation(FormationType.Type.COLUMN)
		elif event.keycode == KEY_F3:
			_set_selected_formation(FormationType.Type.WEDGE)
		elif event.keycode == KEY_F4:
			_set_selected_formation(FormationType.Type.SQUARE)
		# Spell hotkeys (1/2/3/4)
		elif event.keycode == KEY_1:
			_cast_spell_at_enemy(0)
		elif event.keycode == KEY_2:
			_cast_spell_at_enemy(1)
		elif event.keycode == KEY_3:
			_cast_spell_at_enemy(2)
		elif event.keycode == KEY_4:
			_cast_spell_at_enemy(3)

	# Only handle mouse input if within the viewport
	if not _is_mouse_over_viewport():
		return

	# Handle mouse clicks for selection and movement
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(event.position)


func _is_mouse_over_viewport() -> bool:
	"""Check if mouse is over the battle viewport (not the control panel)."""
	if not viewport_container:
		return false
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var container_rect: Rect2 = viewport_container.get_global_rect()
	return container_rect.has_point(mouse_pos)


func _handle_left_click(screen_pos: Vector2) -> void:
	"""Handle left click for unit selection."""
	var world_pos: Vector3 = _screen_to_world(screen_pos)
	if world_pos == Vector3.INF:
		return

	# Find closest unit to click
	var closest_unit: Node = null
	var closest_dist: float = 10.0  # Max selection distance

	for reg in player_regiments:
		if not is_instance_valid(reg):
			continue
		var dist: float = reg.global_position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest_unit = reg

	# Clear previous selection
	for reg in _selected_regiments:
		if is_instance_valid(reg) and reg.has_method("set_selected"):
			reg.set_selected(false)
	_selected_regiments.clear()

	# Select new unit
	if closest_unit:
		_selected_regiments.append(closest_unit)
		if closest_unit.has_method("set_selected"):
			closest_unit.set_selected(true)
		print("[UnitZoo] Selected: %s" % closest_unit.data.regiment_name)


func _handle_right_click(screen_pos: Vector2) -> void:
	"""Handle right click for move/attack orders."""
	if _selected_regiments.is_empty():
		return

	var world_pos: Vector3 = _screen_to_world(screen_pos)
	if world_pos == Vector3.INF:
		return

	# Check if clicking on an enemy
	var target_enemy: Node = null
	for reg in enemy_regiments:
		if not is_instance_valid(reg):
			continue
		var dist: float = reg.global_position.distance_to(world_pos)
		if dist < 8.0:  # Click near enemy = attack
			target_enemy = reg
			break

	# Issue orders to selected units
	for reg in _selected_regiments:
		if not is_instance_valid(reg):
			continue
		if target_enemy:
			# Set AI target so ranged units know what to shoot at
			if reg.ai_controller:
				reg.ai_controller.set_target(target_enemy)
			reg.give_order(OrderType.Type.ATTACK_MOVE, target_enemy.global_position)
			print("[UnitZoo] Attack order: %s -> %s" % [reg.data.regiment_name, target_enemy.data.regiment_name])
		else:
			reg.give_order(OrderType.Type.MOVE, world_pos)
			print("[UnitZoo] Move order: %s -> %.1f, %.1f" % [reg.data.regiment_name, world_pos.x, world_pos.z])


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	"""Convert screen position to world position on terrain."""
	if not battle_camera:
		return Vector3.INF

	# Adjust screen pos relative to viewport container
	var container_rect: Rect2 = viewport_container.get_global_rect()
	var local_pos: Vector2 = screen_pos - container_rect.position
	# Scale to viewport size
	var scale: Vector2 = Vector2(battle_viewport.size) / container_rect.size
	local_pos *= scale

	# Ray from camera
	var from: Vector3 = battle_camera.project_ray_origin(local_pos)
	var dir: Vector3 = battle_camera.project_ray_normal(local_pos)

	# Intersect with ground plane (Y=0)
	if abs(dir.y) > 0.001:
		var t: float = -from.y / dir.y
		if t > 0:
			return from + dir * t

	return Vector3.INF


func _set_selected_stance(stance: CommanderAI.Stance) -> void:
	"""Set stance for all selected regiments."""
	for reg in _selected_regiments:
		if is_instance_valid(reg) and reg.ai_controller:
			reg.ai_controller.current_stance = stance
	if not _selected_regiments.is_empty():
		print("[UnitZoo] Stance changed to: %s" % CommanderAI.Stance.keys()[stance])


func _set_selected_formation(formation: FormationType.Type) -> void:
	"""Set formation for all selected regiments."""
	for reg in _selected_regiments:
		if is_instance_valid(reg):
			reg.set_formation(formation)
	if not _selected_regiments.is_empty():
		print("[UnitZoo] Formation changed to: %s" % FormationType.Type.keys()[formation])


func _cycle_weather() -> void:
	"""Cycle through weather types."""
	if not weather_selector:
		return

	var current: int = weather_selector.selected
	var next_idx: int = (current + 1) % weather_selector.item_count
	weather_selector.select(next_idx)
	_on_weather_changed(next_idx)


func _on_camera_lock_toggled(pressed: bool) -> void:
	if battle_camera:
		battle_camera.camera_locked = pressed
		print("[UnitZoo] Camera %s" % ("locked" if pressed else "unlocked"))


func _spawn_initial_units() -> void:
	_spawn_player_unit(DEFAULT_PLAYER_UNIT)
	_spawn_enemy_unit(DEFAULT_ENEMY_UNIT)

	# Auto-target player ranged units at the enemy (for artillery/ranged testing)
	call_deferred("_setup_player_ranged_targeting")

	# Combat phase is now started manually via the Start Battle button
	# This allows positioning units before combat begins
	_update_battle_button_state()


func _setup_player_ranged_targeting() -> void:
	"""Auto-target player ranged/artillery at enemy for fire testing."""
	if not player_regiment or not is_instance_valid(player_regiment):
		return
	if not enemy_regiment or not is_instance_valid(enemy_regiment):
		return
	# Only auto-target if player has ranged capability
	if player_regiment.data and player_regiment.data.ballistic_skill > 0:
		# Wait for AI to initialize
		await get_tree().create_timer(0.2).timeout
		if player_regiment.ai_controller:
			player_regiment.ai_controller.set_target(enemy_regiment)
			print("[UnitZoo] Auto-targeted player %s at enemy %s (ranged unit)" % [
				player_regiment.data.regiment_name if player_regiment.data else player_regiment.name,
				enemy_regiment.data.regiment_name if enemy_regiment.data else enemy_regiment.name
			])


func _ensure_combat_phase() -> void:
	## Ensures the game is in combat phase so damage can be dealt.
	## Unit Zoo bypasses the normal deployment flow, so we need to manually
	## transition to combat phase for CombatManager to process damage.
	if DeploymentManager:
		if DeploymentManager.is_deployment_phase():
			print("[UnitZoo] Transitioning from deployment to combat phase")
			DeploymentManager.start_battle()
		else:
			print("[UnitZoo] Already in combat phase")
	else:
		push_warning("[UnitZoo] DeploymentManager not found - combat may not work")
	_update_battle_button_state()


func _on_start_battle_pressed() -> void:
	## Handler for Start Battle button press.
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		_ensure_combat_phase()
		print("[UnitZoo] Battle started via button!")
	else:
		print("[UnitZoo] Already in combat phase")


func _update_battle_button_state() -> void:
	## Updates the Start Battle button text based on current phase.
	if not start_battle_button:
		return
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		start_battle_button.text = "START BATTLE"
		start_battle_button.disabled = false
	else:
		start_battle_button.text = "BATTLE IN PROGRESS"
		start_battle_button.disabled = true


func _auto_start_after_delay() -> void:
	# Wait for initial units to spawn and settle
	await get_tree().create_timer(1.0).timeout
	start_auto_test()


func _auto_start_battle_stress_after_delay() -> void:
	"""Auto-start battle stress test after scene settles."""
	# Wait for initial setup to complete
	await get_tree().create_timer(2.0).timeout
	print("[UnitZoo] Auto-starting battle stress test...")
	start_battle_stress_test(battle_stress_rounds, battle_stress_duration, battle_stress_units_per_side)


func _on_player_unit_changed(_index: int) -> void:
	# Dropdown only selects unit type for Add button - no auto-spawn
	# This fixes the bug where changing dropdown cleared previously placed units
	pass


func _on_enemy_unit_changed(_index: int) -> void:
	# Dropdown only selects unit type for Add button - no auto-spawn
	# This fixes the bug where changing dropdown cleared previously placed units
	pass


func _spawn_player_unit(unit_id: String) -> void:
	# Clean up all existing player units
	_clear_player_units()
	await get_tree().process_frame

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		push_error("UnitZoo: Could not load regiment data for " + unit_id)
		return

	player_regiment = REGIMENT_SCENE.instantiate()
	player_regiment.name = "PlayerRegiment"
	# Set data BEFORE adding to tree (Regiment._ready() checks for data)
	player_regiment.data = data.duplicate()
	player_regiment.is_player_controlled = true
	# Use sprites only (no 3D soldiers) to match battle scene
	player_regiment.use_3d_soldiers = false
	player_regiment.use_sprite_soldiers = true
	# Override scene's default atlas with the unit's actual atlas
	player_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(player_regiment)

	# Sync all positions after added to tree (prevents rubber-banding)
	# Use wider separation (120 units total) to give ranged units time to fire
	player_regiment.sync_all_positions(Vector3(-60, 0, 0))
	# Set initial facing toward the enemy (East) - uses immediate facing to avoid spin
	var facing_toward_enemy := Vector3(1, 0, 0)  # East (+X)
	player_regiment.set_initial_facing(facing_toward_enemy)

	# Note: AIAutoload registration happens in Regiment._ready(), no need to duplicate

	# Enable AI assist so stance changes work in Unit Zoo
	player_regiment.enable_ai_assist(true)

	# Add to group for selection manager
	player_regiment.add_to_group("player_regiments")

	# Track in array
	player_regiments.append(player_regiment)

	print("[UnitZoo] Spawned player unit: %s (%s)" % [data.regiment_name, unit_id])

	# Update stat labels to reflect new unit
	_update_stat_labels()

	# Refresh unit cards in HUD
	_refresh_hud_unit_cards()

	# Update spell buttons for new unit
	call_deferred("_update_spell_buttons")


func _add_player_unit(unit_id: String, spawn_offset: Vector3) -> void:
	"""Add an additional player unit without clearing existing ones."""
	if player_regiments.size() >= MAX_UNITS_PER_SIDE:
		print("[UnitZoo] Max player units reached (%d)" % MAX_UNITS_PER_SIDE)
		return

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		push_error("UnitZoo: Could not load regiment data for " + unit_id)
		return

	var new_regiment: Node = REGIMENT_SCENE.instantiate()
	new_regiment.name = "PlayerRegiment_%d" % player_regiments.size()
	new_regiment.data = data.duplicate()
	new_regiment.is_player_controlled = true
	new_regiment.use_3d_soldiers = false
	new_regiment.use_sprite_soldiers = true
	new_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(new_regiment)

	# Position with offset
	var base_pos: Vector3 = Vector3(-15, 0, 0) + spawn_offset
	new_regiment.sync_all_positions(base_pos)
	new_regiment.set_initial_facing(Vector3(1, 0, 0))  # Face east toward enemy

	new_regiment.enable_ai_assist(true)
	new_regiment.add_to_group("player_regiments")

	player_regiments.append(new_regiment)

	print("[UnitZoo] Added player unit: %s (%d/%d)" % [data.regiment_name, player_regiments.size(), MAX_UNITS_PER_SIDE])

	# Refresh unit cards in HUD
	_refresh_hud_unit_cards()


func _clear_player_units() -> void:
	"""Clear all player units."""
	for reg in player_regiments:
		if is_instance_valid(reg):
			if AIAutoload and AIAutoload.spatial_hash:
				AIAutoload.spatial_hash.unregister(reg)
			reg.queue_free()
	player_regiments.clear()
	player_regiment = null
	_selected_regiments.clear()

	# Refresh unit cards in HUD
	_refresh_hud_unit_cards()


func _spawn_enemy_unit(unit_id: String) -> void:
	# Clean up all existing enemy units
	_clear_enemy_units()
	await get_tree().process_frame

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		push_error("UnitZoo: Could not load regiment data for " + unit_id)
		return

	enemy_regiment = REGIMENT_SCENE.instantiate()
	enemy_regiment.name = "EnemyRegiment"
	# Set data BEFORE adding to tree (Regiment._ready() checks for data)
	enemy_regiment.data = data.duplicate()
	enemy_regiment.is_player_controlled = false
	# Use sprites only (no 3D soldiers) to match battle scene
	enemy_regiment.use_3d_soldiers = false
	enemy_regiment.use_sprite_soldiers = true
	# Override scene's default atlas with the unit's actual atlas
	enemy_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(enemy_regiment)

	# Sync all positions after added to tree (prevents rubber-banding)
	# Use wider separation (120 units total) to give ranged units time to fire
	enemy_regiment.sync_all_positions(Vector3(60, 0, 0))
	# Set initial facing toward the player (West) - uses immediate facing to avoid spin
	var facing_toward_player := Vector3(-1, 0, 0)  # West (-X)
	enemy_regiment.set_initial_facing(facing_toward_player)

	# Note: AIAutoload registration happens in Regiment._ready(), no need to duplicate

	# Add to group for selection manager
	enemy_regiment.add_to_group("enemy_regiments")

	# Apply lock state if toggle is on
	if lock_enemy_toggle and lock_enemy_toggle.button_pressed:
		enemy_regiment.is_position_locked = true
		# Locked enemies stay defensive and don't attack - useful for testing ranged
		call_deferred("_set_enemy_defensive_locked", enemy_regiment)
	else:
		# Set enemy to aggressive stance so they auto-engage (40 unit radius vs 15 for defensive)
		call_deferred("_set_enemy_aggressive", enemy_regiment)

	# Track in array
	enemy_regiments.append(enemy_regiment)

	print("[UnitZoo] Spawned enemy unit: %s (%s)" % [data.regiment_name, unit_id])

	# Update stat labels to reflect new unit
	_update_stat_labels()


func _set_enemy_aggressive(reg: Node) -> void:
	"""Set enemy unit to aggressive stance so they auto-engage (called deferred after AI init)."""
	if not is_instance_valid(reg):
		print("[UnitZoo] _set_enemy_aggressive: regiment invalid")
		_aggressive_retry_counts.erase(reg)
		return
	if not reg.ai_controller:
		# Track retry count
		var reg_id: int = reg.get_instance_id()
		var retries: int = _aggressive_retry_counts.get(reg_id, 0)
		if retries >= MAX_AGGRESSIVE_RETRIES:
			push_warning("[UnitZoo] _set_enemy_aggressive: gave up after %d retries for %s" % [retries, reg.name])
			_aggressive_retry_counts.erase(reg_id)
			return
		_aggressive_retry_counts[reg_id] = retries + 1
		# Use timer instead of call_deferred for better spacing
		get_tree().create_timer(0.1).timeout.connect(func(): _set_enemy_aggressive(reg))
		return
	# Clear retry tracking
	_aggressive_retry_counts.erase(reg.get_instance_id())
	# Set to AGGRESSIVE stance (index 1) for 120m acquisition range
	reg.ai_controller.set_stance(CommanderAI.Stance.AGGRESSIVE)
	print("[UnitZoo] Set enemy %s to AGGRESSIVE stance" % (reg.data.regiment_name if reg.data else reg.name))
	# Also issue an attack order to ensure they start moving
	if player_regiment and is_instance_valid(player_regiment):
		reg.ai_controller.set_target(player_regiment)
		reg.ai_controller.issue_attack_order(player_regiment)
		print("[UnitZoo] Issued attack order to %s targeting %s" % [reg.data.regiment_name if reg.data else reg.name, player_regiment.data.regiment_name if player_regiment.data else player_regiment.name])


func _set_enemy_defensive_locked(reg: Node) -> void:
	"""Set locked enemy to defensive stance - they won't move or attack (for ranged testing)."""
	if not is_instance_valid(reg):
		return
	if not reg.ai_controller:
		# Retry if AI not ready yet
		get_tree().create_timer(0.1).timeout.connect(func(): _set_enemy_defensive_locked(reg))
		return
	# Set to DEFENSIVE stance (index 0 = DEFENSIVE in CommanderAI.Stance)
	reg.ai_controller.set_stance(CommanderAI.Stance.DEFENSIVE)
	# Clear any target so they don't try to engage
	reg.ai_controller.set_target(null)
	print("[UnitZoo] Set enemy %s to DEFENSIVE stance (LOCKED - won't attack)" % (reg.data.regiment_name if reg.data else reg.name))


func _add_enemy_unit(unit_id: String, spawn_offset: Vector3) -> void:
	"""Add an additional enemy unit without clearing existing ones."""
	if enemy_regiments.size() >= MAX_UNITS_PER_SIDE:
		print("[UnitZoo] Max enemy units reached (%d)" % MAX_UNITS_PER_SIDE)
		return

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		push_error("UnitZoo: Could not load regiment data for " + unit_id)
		return

	var new_regiment: Node = REGIMENT_SCENE.instantiate()
	new_regiment.name = "EnemyRegiment_%d" % enemy_regiments.size()
	new_regiment.data = data.duplicate()
	new_regiment.is_player_controlled = false
	new_regiment.use_3d_soldiers = false
	new_regiment.use_sprite_soldiers = true
	new_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(new_regiment)

	# Position with offset
	var base_pos: Vector3 = Vector3(15, 0, 0) + spawn_offset
	new_regiment.sync_all_positions(base_pos)
	new_regiment.set_initial_facing(Vector3(-1, 0, 0))  # Face west toward player

	new_regiment.add_to_group("enemy_regiments")

	# Apply lock state if toggle is on
	if lock_enemy_toggle and lock_enemy_toggle.button_pressed:
		new_regiment.is_position_locked = true

	enemy_regiments.append(new_regiment)

	print("[UnitZoo] Added enemy unit: %s (%d/%d)" % [data.regiment_name, enemy_regiments.size(), MAX_UNITS_PER_SIDE])


func _clear_enemy_units() -> void:
	"""Clear all enemy units."""
	for reg in enemy_regiments:
		if is_instance_valid(reg):
			if AIAutoload and AIAutoload.spatial_hash:
				AIAutoload.spatial_hash.unregister(reg)
			reg.queue_free()
	enemy_regiments.clear()
	enemy_regiment = null


func _on_formation_changed(index: int) -> void:
	if not player_regiment or not is_instance_valid(player_regiment):
		return

	# Use set_formation() to properly trigger formation change with visuals
	player_regiment.set_formation(index as FormationType.Type)
	print("[UnitZoo] Player formation changed to: %s" % FormationType.Type.keys()[index])


func _on_stance_changed(index: int) -> void:
	if not player_regiment or not is_instance_valid(player_regiment):
		return

	if player_regiment.ai_controller:
		player_regiment.ai_controller.current_stance = index as CommanderAI.Stance
		print("[UnitZoo] Player stance changed to: %s" % CommanderAI.Stance.keys()[index])


func _on_enemy_formation_changed(index: int) -> void:
	if not enemy_regiment or not is_instance_valid(enemy_regiment):
		return

	# Use set_formation() to properly trigger formation change with visuals
	enemy_regiment.set_formation(index as FormationType.Type)
	print("[UnitZoo] Enemy formation changed to: %s" % FormationType.Type.keys()[index])


func _on_enemy_stance_changed(index: int) -> void:
	if not enemy_regiment or not is_instance_valid(enemy_regiment):
		return

	if enemy_regiment.ai_controller:
		enemy_regiment.ai_controller.current_stance = index as CommanderAI.Stance
		print("[UnitZoo] Enemy stance changed to: %s" % CommanderAI.Stance.keys()[index])


func _on_filter_changed(_index: int) -> void:
	# Repopulate dropdowns with filtered units
	_populate_unit_dropdowns()
	var faction_val: String = "All"
	var type_val: String = "All"
	if faction_filter and faction_filter.selected >= 0:
		faction_val = faction_filter.get_item_text(faction_filter.selected)
	if type_filter and type_filter.selected >= 0:
		type_val = type_filter.get_item_text(type_filter.selected)
	print("[UnitZoo] Filter changed: Faction=%s, Type=%s (%d units)" % [faction_val, type_val, all_unit_ids.size()])


func _on_weather_changed(index: int) -> void:
	if not WeatherSystem:
		push_warning("[UnitZoo] WeatherSystem autoload not available")
		return

	# Get weather type from metadata (enum value)
	var weather_type: int = weather_selector.get_item_metadata(index) if weather_selector.get_item_metadata(index) != null else index

	# Apply to WeatherSystem
	WeatherSystem.debug_set_weather(weather_type)

	# Update weather info display
	_update_weather_info()

	print("[UnitZoo] Weather changed to: %s" % WeatherSystem.get_weather_name())


func _process(_delta: float) -> void:
	_update_info_panels()
	_update_weather_info()
	_update_projectile_debug()
	_update_compass_debug()
	_debug_melee_positions(_delta)


func _update_compass_debug() -> void:
	"""Update WorldCompass debug display showing unit facing and camera rotation."""
	if not _compass_debug_label:
		return

	# Get camera rotation
	var camera_rot_deg: float = 0.0
	var camera_rot_rad: float = 0.0
	if battle_camera:
		camera_rot_rad = battle_camera.global_rotation.y
		camera_rot_deg = rad_to_deg(camera_rot_rad)

	# Get selected unit facing (or primary player regiment)
	var selected_reg: Node = null
	if not _selected_regiments.is_empty():
		selected_reg = _selected_regiments[0]
	elif player_regiment and is_instance_valid(player_regiment):
		selected_reg = player_regiment

	if selected_reg and is_instance_valid(selected_reg):
		# Get world-space facing direction
		var facing_dir: Vector3 = selected_reg.get_facing_direction() if selected_reg.has_method("get_facing_direction") else Vector3.FORWARD

		# Calculate raw angle for debugging
		var raw_angle := atan2(facing_dir.x, facing_dir.z)
		var raw_angle_deg := rad_to_deg(raw_angle)

		var world_dir_idx := WorldCompassScript.direction_from_vector(facing_dir)
		var world_dir_name := WorldCompassScript.direction_name(world_dir_idx, false)  # Full name

		# Get screen-space direction (what sprite is shown)
		var screen_dir_idx := WorldCompassScript.world_to_screen_direction(world_dir_idx, camera_rot_rad)
		var screen_dir_name := WorldCompassScript.direction_name(screen_dir_idx, true)

		# Get sprite row info if sprite formation available
		var sprite_row_info := ""
		if selected_reg.has_node("SpriteFormation"):
			var sprite_form = selected_reg.get_node("SpriteFormation")
			if sprite_form.has_method("get_current_direction_index"):
				var current_dir: int = sprite_form.get_current_direction_index()
				var current_dir_name := WorldCompassScript.direction_name(current_dir, true)
				sprite_row_info = " | SpriteRow: %d (%s)" % [current_dir, current_dir_name]

		# Multi-line debug with full details
		_compass_debug_label.text = "Vec: (%.2f, %.2f) Angle: %.0f° -> World: %s (%d) | Screen: %s (%d) | Cam: %.0f°%s" % [
			facing_dir.x, facing_dir.z, raw_angle_deg,
			world_dir_name, world_dir_idx,
			screen_dir_name, screen_dir_idx,
			camera_rot_deg, sprite_row_info
		]
	else:
		_compass_debug_label.text = "No unit selected | Cam: %.0f°" % camera_rot_deg


func _debug_melee_positions(delta: float) -> void:
	"""Debug: Print MeleeArea positions every 2 seconds to diagnose collision detection."""
	_melee_debug_timer += delta
	if _melee_debug_timer < MELEE_DEBUG_INTERVAL:
		return
	_melee_debug_timer = 0.0

	if not player_regiment or not is_instance_valid(player_regiment):
		return
	if not enemy_regiment or not is_instance_valid(enemy_regiment):
		return

	# Get melee areas
	var player_melee: Area3D = player_regiment.melee_area if "melee_area" in player_regiment else null
	var enemy_melee: Area3D = enemy_regiment.melee_area if "melee_area" in enemy_regiment else null

	if not player_melee or not enemy_melee:
		print("[MELEE POS] MeleeArea not found on regiments")
		return

	var player_pos: Vector3 = player_melee.global_position
	var enemy_pos: Vector3 = enemy_melee.global_position
	var distance: float = player_pos.distance_to(enemy_pos)
	var xz_distance: float = Vector2(player_pos.x, player_pos.z).distance_to(Vector2(enemy_pos.x, enemy_pos.z))
	var y_diff: float = abs(player_pos.y - enemy_pos.y)

	# Check monitoring state
	var p_monitoring: bool = player_melee.monitoring
	var p_monitorable: bool = player_melee.monitorable
	var e_monitoring: bool = enemy_melee.monitoring
	var e_monitorable: bool = enemy_melee.monitorable

	# Get collision layer/mask
	var p_layer: int = player_melee.collision_layer
	var p_mask: int = player_melee.collision_mask
	var e_layer: int = enemy_melee.collision_layer
	var e_mask: int = enemy_melee.collision_mask

	# Get states
	var p_state: String = player_regiment.state_name() if player_regiment.has_method("state_name") else str(player_regiment.state)
	var e_state: String = enemy_regiment.state_name() if enemy_regiment.has_method("state_name") else str(enemy_regiment.state)

	print("[MELEE POS] Player: pos=%s, state=%s, layer=%d, mask=%d, monitoring=%s, monitorable=%s" % [
		player_pos, p_state, p_layer, p_mask, p_monitoring, p_monitorable])
	print("[MELEE POS] Enemy:  pos=%s, state=%s, layer=%d, mask=%d, monitoring=%s, monitorable=%s" % [
		enemy_pos, e_state, e_layer, e_mask, e_monitoring, e_monitorable])
	print("[MELEE POS] Distance: %.2f (XZ: %.2f, Y diff: %.2f) - Capsule radius=8, should overlap if XZ < 16" % [
		distance, xz_distance, y_diff])


func _update_info_panels() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		player_info.text = _format_regiment_info(player_regiment, "PLAYER")
	else:
		player_info.text = "=== PLAYER ===\n(No unit)"

	if enemy_regiment and is_instance_valid(enemy_regiment):
		enemy_info.text = _format_regiment_info(enemy_regiment, "ENEMY")
	else:
		enemy_info.text = "=== ENEMY ===\n(No unit)"


func _update_weather_info() -> void:
	if not weather_info or not WeatherSystem:
		return

	var acc: float = WeatherSystem.get_ranged_accuracy_modifier() * 100.0
	var rng: float = WeatherSystem.get_ranged_range_modifier() * 100.0
	var chg: float = WeatherSystem.get_charge_bonus_modifier() * 100.0
	var spd: float = WeatherSystem.get_movement_speed_modifier() * 100.0

	weather_info.text = "Acc: %.0f%% | Rng: %.0f%% | Chg: %.0f%% | Spd: %.0f%%" % [acc, rng, chg, spd]

	# Color code based on penalties
	if acc < 100.0 or rng < 100.0 or chg < 100.0 or spd < 100.0:
		weather_info.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))  # Yellow for penalties
	else:
		weather_info.remove_theme_color_override("font_color")


func _format_regiment_info(reg: Node, label: String) -> String:
	var info: String = "=== %s ===\n" % label

	if not reg.data:
		return info + "(No data)"

	info += "Name: %s\n" % reg.data.regiment_name
	info += "Type: %s\n" % UnitType.Type.keys()[reg.data.unit_type]
	info += "State: %s\n" % Regiment.State.keys()[reg.state]
	info += "Soldiers: %d/%d\n" % [reg.current_soldiers, reg.data.max_soldiers]
	info += "Morale: %.1f\n" % reg.current_morale

	if reg.stamina:
		var stamina_pct: float = (reg.stamina.current_stamina / StaminaSystem.MAX_STAMINA) * 100.0
		info += "Stamina: %.1f%%\n" % stamina_pct

	if reg.data.max_ammo > 0:
		info += "Ammo: %d/%d\n" % [reg.current_ammo, reg.data.max_ammo]

	info += "Formation: %s\n" % FormationType.Type.keys()[reg.current_formation]

	# Combat stats
	info += "\n--- Stats ---\n"
	info += "Attack: %d\n" % reg.data.attack
	info += "Defense: %d\n" % reg.data.defense
	info += "Speed: Walk=%.2f Run=%.2f Charge=%.2f\n" % [reg.data.walk_speed, reg.data.run_speed, reg.data.charge_speed]

	if reg.data.ballistic_skill > 0:
		info += "BS: %d\n" % reg.data.ballistic_skill
		info += "Range: %.0f\n" % reg.data.range_distance

	return info


# === ACTION BUTTONS ===

func _on_move_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		player_regiment.give_order(OrderType.Type.MOVE, Vector3(0, 0, 0))
		print("[UnitZoo] Player ordered to move to center")


func _on_attack_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		if enemy_regiment and is_instance_valid(enemy_regiment):
			# Set AI target so ranged units know what to shoot at
			if player_regiment.ai_controller:
				player_regiment.ai_controller.set_target(enemy_regiment)
			player_regiment.give_order(OrderType.Type.ATTACK_MOVE, enemy_regiment.global_position)
			print("[UnitZoo] Player ordered to attack enemy")


func _on_charge_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		if enemy_regiment and is_instance_valid(enemy_regiment):
			# Set AI target for charge
			if player_regiment.ai_controller:
				player_regiment.ai_controller.set_target(enemy_regiment)
			player_regiment.give_order(OrderType.Type.CHARGE, enemy_regiment.global_position)
			print("[UnitZoo] Player ordered to charge enemy")


func _on_disengage_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		# Order unit to retreat away from enemy
		var retreat_dir: Vector3 = Vector3(-1, 0, 0)  # Default retreat left
		if enemy_regiment and is_instance_valid(enemy_regiment):
			retreat_dir = (player_regiment.global_position - enemy_regiment.global_position).normalized()
		var retreat_pos: Vector3 = player_regiment.global_position + retreat_dir * 20.0
		player_regiment.give_order(OrderType.Type.WITHDRAW, retreat_pos)
		print("[UnitZoo] Player ordered to disengage/retreat")


func _on_reset_button_pressed() -> void:
	_spawn_initial_units()
	formation_selector.select(0)
	stance_selector.select(0)
	enemy_formation_selector.select(0)
	enemy_stance_selector.select(0)
	lock_enemy_toggle.button_pressed = false

	# Reset weather to clear
	if weather_selector:
		weather_selector.select(0)
		_on_weather_changed(0)

	print("[UnitZoo] Reset to initial state")


# === ENEMY ACTION BUTTONS ===

func _on_enemy_move_button_pressed() -> void:
	if enemy_regiment and is_instance_valid(enemy_regiment):
		enemy_regiment.give_order(OrderType.Type.MOVE, Vector3(0, 0, 0))
		print("[UnitZoo] Enemy ordered to move to center")


func _on_enemy_attack_button_pressed() -> void:
	if enemy_regiment and is_instance_valid(enemy_regiment):
		if player_regiment and is_instance_valid(player_regiment):
			# Set AI target so ranged units know what to shoot at
			if enemy_regiment.ai_controller:
				enemy_regiment.ai_controller.set_target(player_regiment)
			enemy_regiment.give_order(OrderType.Type.ATTACK_MOVE, player_regiment.global_position)
			print("[UnitZoo] Enemy ordered to attack player")


func _on_enemy_charge_button_pressed() -> void:
	if enemy_regiment and is_instance_valid(enemy_regiment):
		if player_regiment and is_instance_valid(player_regiment):
			# Set AI target for charge
			if enemy_regiment.ai_controller:
				enemy_regiment.ai_controller.set_target(player_regiment)
			enemy_regiment.give_order(OrderType.Type.CHARGE, player_regiment.global_position)
			print("[UnitZoo] Enemy ordered to charge player")


func _on_enemy_disengage_button_pressed() -> void:
	if enemy_regiment and is_instance_valid(enemy_regiment):
		# Order unit to retreat away from player
		var retreat_dir: Vector3 = Vector3(1, 0, 0)  # Default retreat right
		if player_regiment and is_instance_valid(player_regiment):
			retreat_dir = (enemy_regiment.global_position - player_regiment.global_position).normalized()
		var retreat_pos: Vector3 = enemy_regiment.global_position + retreat_dir * 20.0
		enemy_regiment.give_order(OrderType.Type.WITHDRAW, retreat_pos)
		print("[UnitZoo] Enemy ordered to disengage/retreat")


func _on_lock_enemy_toggled(pressed: bool) -> void:
	# Apply to all enemy regiments
	for reg in enemy_regiments:
		if is_instance_valid(reg):
			reg.is_position_locked = pressed
			if pressed:
				# IMMEDIATELY stop movement and set defensive
				if reg.leader:
					reg.leader.stop_movement()
				reg.set_state(Regiment.State.IDLE)
				if reg.ai_controller:
					reg.ai_controller.set_stance(CommanderAI.Stance.DEFENSIVE)
					reg.ai_controller.clear_target()
				print("[UnitZoo] Locked %s - stopped movement, set DEFENSIVE" % (reg.data.regiment_name if reg.data else reg.name))
	print("[UnitZoo] All enemies position %s (can still route/flee)" % ("LOCKED" if pressed else "UNLOCKED"))


# === ADD UNIT BUTTONS ===

func _on_add_player_unit_pressed() -> void:
	"""Add another player unit using currently selected type."""
	if player_selector.selected < 0:
		return
	var unit_id: String = player_selector.get_item_metadata(player_selector.selected)
	if not unit_id:
		return

	# Calculate spawn offset based on current unit count
	var idx: int = player_regiments.size()
	var offset: Vector3 = Vector3(0, 0, -10 + idx * 8)  # Spread along Z
	_add_player_unit(unit_id, offset)


func _on_add_enemy_unit_pressed() -> void:
	"""Add another enemy unit using currently selected type."""
	if enemy_selector.selected < 0:
		return
	var unit_id: String = enemy_selector.get_item_metadata(enemy_selector.selected)
	if not unit_id:
		return

	# Calculate spawn offset based on current unit count
	var idx: int = enemy_regiments.size()
	var offset: Vector3 = Vector3(0, 0, -10 + idx * 8)  # Spread along Z
	_add_enemy_unit(unit_id, offset)


func _on_clear_player_units_pressed() -> void:
	"""Clear all player units."""
	_clear_player_units()
	print("[UnitZoo] Cleared all player units")


func _on_clear_enemy_units_pressed() -> void:
	"""Clear all enemy units."""
	_clear_enemy_units()
	print("[UnitZoo] Cleared all enemy units")


# === STAT ADJUSTMENT BUTTONS ===

func _on_player_vet_up_pressed() -> void:
	if player_regiment and player_regiment.veterancy:
		var current: int = player_regiment.veterancy.current_level
		if current < VeterancySystem.Level.ELITE:
			player_regiment.veterancy.current_level = (current + 1) as VeterancySystem.Level
			player_regiment.veterancy.current_xp = VeterancySystem.XP_THRESHOLDS[player_regiment.veterancy.current_level]
			_update_stat_labels()


func _on_player_vet_down_pressed() -> void:
	if player_regiment and player_regiment.veterancy:
		var current: int = player_regiment.veterancy.current_level
		if current > VeterancySystem.Level.FRESH:
			player_regiment.veterancy.current_level = (current - 1) as VeterancySystem.Level
			player_regiment.veterancy.current_xp = VeterancySystem.XP_THRESHOLDS[player_regiment.veterancy.current_level]
			_update_stat_labels()


func _on_player_armor_up_pressed() -> void:
	if player_regiment and player_regiment.data:
		player_regiment.data.armor = mini(player_regiment.data.armor + 2, 20)
		_update_stat_labels()


func _on_player_armor_down_pressed() -> void:
	if player_regiment and player_regiment.data:
		player_regiment.data.armor = maxi(player_regiment.data.armor - 2, 0)
		_update_stat_labels()


func _on_player_attack_up_pressed() -> void:
	if player_regiment and player_regiment.data:
		player_regiment.data.attack = mini(player_regiment.data.attack + 2, 30)
		_update_stat_labels()


func _on_player_attack_down_pressed() -> void:
	if player_regiment and player_regiment.data:
		player_regiment.data.attack = maxi(player_regiment.data.attack - 2, 1)
		_update_stat_labels()


func _on_enemy_vet_up_pressed() -> void:
	if enemy_regiment and enemy_regiment.veterancy:
		var current: int = enemy_regiment.veterancy.current_level
		if current < VeterancySystem.Level.ELITE:
			enemy_regiment.veterancy.current_level = (current + 1) as VeterancySystem.Level
			enemy_regiment.veterancy.current_xp = VeterancySystem.XP_THRESHOLDS[enemy_regiment.veterancy.current_level]
			_update_stat_labels()


func _on_enemy_vet_down_pressed() -> void:
	if enemy_regiment and enemy_regiment.veterancy:
		var current: int = enemy_regiment.veterancy.current_level
		if current > VeterancySystem.Level.FRESH:
			enemy_regiment.veterancy.current_level = (current - 1) as VeterancySystem.Level
			enemy_regiment.veterancy.current_xp = VeterancySystem.XP_THRESHOLDS[enemy_regiment.veterancy.current_level]
			_update_stat_labels()


func _on_enemy_armor_up_pressed() -> void:
	if enemy_regiment and enemy_regiment.data:
		enemy_regiment.data.armor = mini(enemy_regiment.data.armor + 2, 20)
		_update_stat_labels()


func _on_enemy_armor_down_pressed() -> void:
	if enemy_regiment and enemy_regiment.data:
		enemy_regiment.data.armor = maxi(enemy_regiment.data.armor - 2, 0)
		_update_stat_labels()


func _on_enemy_attack_up_pressed() -> void:
	if enemy_regiment and enemy_regiment.data:
		enemy_regiment.data.attack = mini(enemy_regiment.data.attack + 2, 30)
		_update_stat_labels()


func _on_enemy_attack_down_pressed() -> void:
	if enemy_regiment and enemy_regiment.data:
		enemy_regiment.data.attack = maxi(enemy_regiment.data.attack - 2, 1)
		_update_stat_labels()


func _update_stat_labels() -> void:
	if player_regiment and player_vet_value:
		if player_regiment.veterancy:
			player_vet_value.text = player_regiment.veterancy.get_level_name()
		if player_regiment.data:
			player_armor_value.text = str(player_regiment.data.armor)
			player_attack_value.text = str(player_regiment.data.attack)
	if enemy_regiment and enemy_vet_value:
		if enemy_regiment.veterancy:
			enemy_vet_value.text = enemy_regiment.veterancy.get_level_name()
		if enemy_regiment.data:
			enemy_armor_value.text = str(enemy_regiment.data.armor)
			enemy_attack_value.text = str(enemy_regiment.data.attack)


func _refresh_hud_unit_cards() -> void:
	"""Refresh unit cards in the BattleHUD to reflect current player regiments."""
	if battle_hud and is_instance_valid(battle_hud):
		# Small delay to ensure regiment is fully initialized
		await get_tree().process_frame
		battle_hud.refresh_unit_cards()


# === AUTO-TEST SYSTEM ===

func start_auto_test() -> void:
	"""Start automatic testing of all units in the zoo."""
	if _auto_test_running:
		print("[UnitZoo] Auto-test already running")
		return

	_auto_test_running = true
	_auto_test_index = 0
	_auto_test_errors.clear()

	print("\n========================================")
	print("[UnitZoo] STARTING AUTO-TEST")
	print("[UnitZoo] Testing %d units..." % all_unit_ids.size())
	print("========================================\n")

	_auto_test_next_unit()


func _auto_test_next_unit() -> void:
	"""Test the next unit in the sequence."""
	if not _auto_test_running:
		return

	if _auto_test_index >= all_unit_ids.size():
		_auto_test_complete()
		return

	var unit_id: String = all_unit_ids[_auto_test_index]
	print("\n[AutoTest] Testing unit %d/%d: %s" % [_auto_test_index + 1, all_unit_ids.size(), unit_id])

	# Spawn the unit as player
	_spawn_player_unit(unit_id)

	# Wait for the unit to fully spawn then check for errors
	await get_tree().create_timer(_auto_test_delay).timeout

	if not _auto_test_running:
		return

	# Check if the unit spawned correctly
	if not player_regiment or not is_instance_valid(player_regiment):
		var error_msg: String = "[AutoTest] FAILED: %s - Regiment did not spawn" % unit_id
		print(error_msg)
		_auto_test_errors.append({"unit_id": unit_id, "error": "Regiment did not spawn"})
	elif not player_regiment.data:
		var error_msg: String = "[AutoTest] FAILED: %s - No regiment data" % unit_id
		print(error_msg)
		_auto_test_errors.append({"unit_id": unit_id, "error": "No regiment data"})
	else:
		print("[AutoTest] OK: %s (%s)" % [player_regiment.data.regiment_name, unit_id])

	_auto_test_index += 1
	_auto_test_next_unit()


func _auto_test_complete() -> void:
	"""Complete the auto-test and report results."""
	_auto_test_running = false

	print("\n========================================")
	print("[UnitZoo] AUTO-TEST COMPLETE")
	print("[UnitZoo] Tested %d units" % all_unit_ids.size())
	print("[UnitZoo] Errors: %d" % _auto_test_errors.size())

	if _auto_test_errors.size() > 0:
		print("\n--- FAILED UNITS ---")
		for error in _auto_test_errors:
			print("  %s: %s" % [error.unit_id, error.error])
	else:
		print("\n[UnitZoo] All units passed!")

	print("========================================\n")


func stop_auto_test() -> void:
	"""Stop the auto-test if running."""
	if _auto_test_running:
		_auto_test_running = false
		print("[UnitZoo] Auto-test stopped")


# === RANDOM BATTLE STRESS TEST ===
# Tests random unit combinations in combat to find bugs

var _battle_stress_running: bool = false
var _battle_stress_round: int = 0
var _battle_stress_max_rounds: int = 40
var _battle_stress_duration: float = 60.0  # seconds per battle
var _battle_stress_timer: float = 0.0
var _battle_stress_errors: Array = []
var _battle_stress_units_per_side: int = 6  # How many units per side
var _battle_stress_player_start_soldiers: int = 0  # Track starting soldiers
var _battle_stress_enemy_start_soldiers: int = 0
var _battle_stress_player_unit_names: Array = []  # Track unit names for summary
var _battle_stress_enemy_unit_names: Array = []
var _battle_stress_player_faction: String = ""  # Track faction for summary
var _battle_stress_enemy_faction: String = ""
var _battle_stress_faction_wins: Dictionary = {}  # Track wins per faction
var _battle_stress_current_weather: int = 0  # Current weather index for variation
var _battle_stress_routing_count: int = 0  # Track routing events
var _battle_stress_flank_count: int = 0  # Track flank attacks
var _battle_stress_rear_count: int = 0  # Track rear attacks
var _stress_capture_point: Node3D = null  # Siege capture point
var _stress_buildings: Array[Node3D] = []  # Scenery buildings

# Weather names for logging
const WEATHER_TYPE_NAMES: Array[String] = ["Clear", "Rain", "Fog", "Storm", "Snow", "Blizzard"]

# === AGENT JSON EXPORT ===
# Structured data for BattleDebug agent consumption
var _agent_run_data: Dictionary = {}      # Full run data for JSON export
var _agent_battles: Array = []             # Array of battle results
var _agent_battle_events: Array = []       # Events for current battle
var _agent_battle_start_time: float = 0.0  # When current battle started (in game time)
var _agent_ai_plays: Array = []            # AI plays for current battle
@export var agent_json_export_enabled: bool = true  # Enable JSON export for agent


func start_battle_stress_test(rounds: int = 40, duration: float = 60.0, units_per_side: int = 6) -> void:
	"""Start random battle stress testing."""
	if _battle_stress_running:
		print("[BattleStress] Already running!")
		return

	_battle_stress_running = true
	_battle_stress_round = 0
	_battle_stress_max_rounds = rounds
	_update_stress_test_counter()  # Show counter
	_battle_stress_duration = duration
	_battle_stress_units_per_side = units_per_side
	_battle_stress_errors.clear()
	_battle_stress_faction_wins.clear()
	_battle_stress_routing_count = 0
	_battle_stress_flank_count = 0
	_battle_stress_rear_count = 0
	_battle_stress_current_weather = 0
	_clear_stress_scenery()  # Clear any existing scenery from previous run
	for faction in FACTION_LIST:
		_battle_stress_faction_wins[faction] = 0

	# Initialize agent JSON export data
	if agent_json_export_enabled:
		_agent_run_data = {
			"run_id": Time.get_datetime_string_from_system().replace(":", "-"),
			"spec": {
				"experiment_name": "stress_test_run",
				"rounds": rounds,
				"duration_per_battle_sec": duration,
				"units_per_side": units_per_side,
				"difficulty_profile": "default",
				"faction_based": stress_test_faction_based,
				"weather_variation": stress_test_weather_variation,
				"siege_mode": stress_test_siege_mode,
			},
			"totals": {
				"battles_run": 0,
				"battles_decisive": 0,
				"total_routs": 0,
				"total_flank_events": 0,
				"total_rear_events": 0,
				"total_charge_impacts": 0,
			},
			"by_faction": {},
		}
		_agent_battles.clear()

	# Connect to BattleSignals for tracking
	_connect_stress_test_signals()

	var sep: String = "======================================================================"
	print("\n" + sep)
	print("[BATTLE STRESS TEST] Starting %d random battle rounds" % rounds)
	print("[BATTLE STRESS TEST] Duration per battle: %.0fs, Units per side: %d" % [duration, units_per_side])
	if stress_test_faction_based:
		print("[BATTLE STRESS TEST] MODE: Faction-Based (each side from single faction)")
		print("[BATTLE STRESS TEST] Factions: %s" % str(FACTION_LIST))
	elif stress_test_basic_infantry_only:
		print("[BATTLE STRESS TEST] MODE: Basic Infantry Only (melee combat loop focus)")
	if stress_test_headless:
		print("[BATTLE STRESS TEST] HEADLESS: Sprite rendering disabled for performance")
		# Speed up simulation in headless mode
		Engine.time_scale = 20.0
	else:
		# Observable mode - normal speed so camera works properly
		Engine.time_scale = 1.0
		print("[BATTLE STRESS TEST] VISIBLE MODE: 1x speed, sprites enabled")
	print(sep + "\n")

	_start_next_stress_battle()


func _start_next_stress_battle() -> void:
	"""Set up and start the next random battle."""
	if not _battle_stress_running:
		return

	if _battle_stress_round >= _battle_stress_max_rounds:
		_complete_battle_stress_test()
		return

	_battle_stress_round += 1
	_update_stress_test_counter()
	_battle_stress_timer = 0.0
	_battle_stress_player_start_soldiers = 0
	_battle_stress_enemy_start_soldiers = 0
	_battle_stress_player_unit_names.clear()
	_battle_stress_enemy_unit_names.clear()

	# Initialize agent battle tracking
	if agent_json_export_enabled:
		_agent_battle_events.clear()
		_agent_ai_plays.clear()
		_agent_battle_start_time = Time.get_ticks_msec() / 1000.0
		_agent_first_contact_recorded = false

	# Cleanup AIs and clear existing units
	_cleanup_stress_ais()
	_clear_player_units()
	_clear_enemy_units()
	await get_tree().process_frame

	# Spawn battlefield scenery (capture point and buildings) on first round only
	await _spawn_stress_scenery()

	# Get random units for each side (faction-based or random)
	var player_unit_ids: Array
	var enemy_unit_ids: Array

	if stress_test_faction_based:
		# Pick two different factions
		var factions: Array = FACTION_LIST.duplicate()
		factions.shuffle()
		_battle_stress_player_faction = factions[0]
		_battle_stress_enemy_faction = factions[1]

		player_unit_ids = _get_faction_unit_ids(_battle_stress_player_faction, _battle_stress_units_per_side)
		enemy_unit_ids = _get_faction_unit_ids(_battle_stress_enemy_faction, _battle_stress_units_per_side)
	else:
		_battle_stress_player_faction = ""
		_battle_stress_enemy_faction = ""
		player_unit_ids = _get_random_unit_ids(_battle_stress_units_per_side)
		enemy_unit_ids = _get_random_unit_ids(_battle_stress_units_per_side)

	_battle_stress_player_unit_names = player_unit_ids.duplicate()
	_battle_stress_enemy_unit_names = enemy_unit_ids.duplicate()

	# Weather variation - change every 2 battles
	if stress_test_weather_variation and _battle_stress_round % 2 == 1:
		_battle_stress_current_weather = (_battle_stress_current_weather + 1) % WEATHER_TYPE_NAMES.size()
		_apply_stress_test_weather(_battle_stress_current_weather)

	print("\n[BattleStress] === Round %d/%d ===" % [_battle_stress_round, _battle_stress_max_rounds])
	if stress_test_weather_variation:
		print("[BattleStress] Weather: %s" % WEATHER_TYPE_NAMES[_battle_stress_current_weather])
	if stress_test_faction_based:
		print("[BattleStress] %s vs %s" % [_battle_stress_player_faction, _battle_stress_enemy_faction])
	print("[BattleStress] Player units: %s" % str(player_unit_ids))
	print("[BattleStress] Enemy units: %s" % str(enemy_unit_ids))

	# Spawn player units
	var player_z_offset: float = -10.0
	for i in player_unit_ids.size():
		var unit_id: String = player_unit_ids[i]
		var spawn_offset: Vector3 = Vector3(0, 0, player_z_offset + i * 8.0)
		await _spawn_stress_player_unit(unit_id, spawn_offset)

	# Spawn enemy units
	var enemy_z_offset: float = -10.0
	for i in enemy_unit_ids.size():
		var unit_id: String = enemy_unit_ids[i]
		var spawn_offset: Vector3 = Vector3(0, 0, enemy_z_offset + i * 8.0)
		await _spawn_stress_enemy_unit(unit_id, spawn_offset)

	# Record starting soldiers for summary
	await get_tree().process_frame
	for reg in player_regiments:
		if is_instance_valid(reg):
			_battle_stress_player_start_soldiers += reg.current_soldiers
	for reg in enemy_regiments:
		if is_instance_valid(reg):
			_battle_stress_enemy_start_soldiers += reg.current_soldiers

	print("[BattleStress] Starting: Player %d soldiers vs Enemy %d soldiers" % [
		_battle_stress_player_start_soldiers, _battle_stress_enemy_start_soldiers])

	# Start the battle
	await get_tree().process_frame
	if DeploymentManager:
		DeploymentManager.start_battle()

	# Setup GeneralAI for BOTH sides in stress test (normal battles only have enemy AI)
	# Wait for terrain snap and regiment init to complete (same delay as BattleManager)
	await get_tree().create_timer(1.2).timeout
	_setup_stress_test_ais()

	# Start the battle timer
	_run_stress_battle_timer()


func _get_random_unit_ids(count: int) -> Array:
	"""Get random unit IDs from the catalog."""
	var result: Array = []
	var available: Array

	# Use basic infantry only for focused combat loop testing
	if stress_test_basic_infantry_only:
		available = []
		for unit_id in BASIC_INFANTRY_IDS:
			if UnitCatalog.get_regiment_data(unit_id) != null:
				available.append(unit_id)
	else:
		available = all_unit_ids.duplicate()

	available.shuffle()

	for i in mini(count, available.size()):
		result.append(available[i])

	return result


# Artillery/siege units to exclude when stress_test_exclude_artillery is true
const ARTILLERY_IDS: Array[String] = [
	"mortar", "grtcanon", "voleygun", "impcanon", "rocklob", "dwheel",
	"gyrocopt", "warpfire", "doomdivr", "cannon",
]


func _get_faction_unit_ids(faction: String, count: int, force_include_general: bool = false) -> Array:
	"""Get random unit IDs from a specific faction's pool."""
	var result: Array = []
	var remaining_count: int = count

	# Add general first if enabled
	if force_include_general or stress_test_always_include_general:
		if FACTION_GENERALS.has(faction):
			var general_id: String = FACTION_GENERALS[faction]
			if UnitCatalog.get_regiment_data(general_id) != null:
				result.append(general_id)
				remaining_count -= 1
				print("[BattleStress] Including general: %s" % general_id)

	if not FACTION_POOLS.has(faction):
		push_warning("[BattleStress] Unknown faction: %s, falling back to random" % faction)
		return _get_random_unit_ids(count)

	var available: Array = []
	for unit_id in FACTION_POOLS[faction]:
		# Skip artillery if excluded
		if stress_test_exclude_artillery and unit_id in ARTILLERY_IDS:
			continue
		# Skip generals (we already added one if needed)
		if unit_id in FACTION_GENERALS.values():
			continue
		if UnitCatalog.get_regiment_data(unit_id) != null:
			available.append(unit_id)

	if available.is_empty():
		push_warning("[BattleStress] No valid units for faction: %s" % faction)
		return result  # Return with just general if we have one

	available.shuffle()

	# Allow duplicates if we need more units than available
	for i in remaining_count:
		result.append(available[i % available.size()])

	return result


func _apply_stress_test_weather(weather_idx: int) -> void:
	"""Apply weather and combat modifiers for stress test."""
	# Set weather via BattleModifiers if available
	var battle_mods = get_node_or_null("/root/BattleModifiers")
	if battle_mods and battle_mods.has_method("set_weather"):
		battle_mods.set_weather(weather_idx)

	# Also try weather selector if present
	if weather_selector:
		weather_selector.select(weather_idx)
		_on_weather_changed(weather_idx)


func _spawn_stress_scenery() -> void:
	"""Spawn capture point and buildings for stress test battlefield."""
	# Only spawn scenery on first round
	if _battle_stress_round > 1:
		return

	# Use siege town layout if enabled (full town with chokepoints)
	if stress_test_siege_mode:
		await _spawn_town_layout()
		return

	# Otherwise use simple layout
	# Spawn capture point in center of battlefield
	if stress_test_include_capture_point and _stress_capture_point == null:
		_spawn_stress_capture_point()

	# Spawn buildings around the edges
	if stress_test_include_buildings and _stress_buildings.is_empty():
		await _spawn_stress_buildings()


func _spawn_stress_capture_point() -> void:
	"""Spawn a siege capture point in the center of the battlefield."""
	_stress_capture_point = Node3D.new()
	_stress_capture_point.name = "StressCapturePoint"
	_stress_capture_point.set_script(CapturePointScript)
	_stress_capture_point.capture_radius = 12.0
	_stress_capture_point.capture_time = 20.0
	_stress_capture_point.point_name = "Center Point"
	_stress_capture_point.initial_owner = "enemy"  # Defender starts with it
	unit_container.add_child(_stress_capture_point)
	_stress_capture_point.global_position = Vector3(0, 0, 10)  # Center, slightly forward
	print("[BattleStress] Spawned siege capture point at center")


func _spawn_stress_buildings() -> void:
	"""Spawn buildings around the edges of the battlefield for scenery."""
	# Building placement positions (avoid center combat area)
	var building_positions: Array[Vector3] = [
		Vector3(-40, 0, -25),   # Far left rear
		Vector3(-40, 0, 25),    # Far left front
		Vector3(40, 0, -25),    # Far right rear
		Vector3(40, 0, 25),     # Far right front
		Vector3(0, 0, -35),     # Center rear
		Vector3(0, 0, 40),      # Center front
	]

	for i in mini(building_positions.size(), BUILDING_MODELS.size()):
		var model_path: String = BUILDING_MODELS[i]
		var building: Node3D = _load_building_model(model_path)
		if building:
			unit_container.add_child(building)
			building.global_position = building_positions[i]
			building.rotation.y = randf() * TAU  # Random rotation
			_stress_buildings.append(building)
			print("[BattleStress] Spawned building: %s at %s" % [model_path.get_file(), building_positions[i]])

	# Rebake navigation mesh to carve out building colliders
	await _rebake_navigation_mesh()


func _load_building_model(path: String) -> Node3D:
	"""Load a GLB building model and return it as a StaticBody3D with collision."""
	var glb = load(path)
	if glb == null:
		push_warning("[BattleStress] Failed to load building: %s" % path)
		return null

	var mesh_instance: Node3D = glb.instantiate()

	# Create a StaticBody3D wrapper for collision
	var static_body := StaticBody3D.new()
	static_body.name = "Building_" + path.get_file().get_basename()
	static_body.collision_layer = 1  # Terrain layer
	static_body.collision_mask = 0   # Doesn't need to detect anything

	# Add the mesh as a child
	static_body.add_child(mesh_instance)

	# Calculate AABB from all MeshInstance3D children and create collision shape
	var aabb := AABB()
	var found_mesh := false
	for child in mesh_instance.get_children():
		if child is MeshInstance3D and child.mesh:
			var child_aabb: AABB = child.mesh.get_aabb()
			# Transform AABB by the child's local transform
			child_aabb = child.transform * child_aabb
			if not found_mesh:
				aabb = child_aabb
				found_mesh = true
			else:
				aabb = aabb.merge(child_aabb)

	# Also check if the root itself is a MeshInstance3D
	if mesh_instance is MeshInstance3D and mesh_instance.mesh:
		var root_aabb: AABB = mesh_instance.mesh.get_aabb()
		if not found_mesh:
			aabb = root_aabb
			found_mesh = true
		else:
			aabb = aabb.merge(root_aabb)

	# Create collision shape and navigation obstacle from AABB
	var obstacle_vertices: PackedVector3Array
	if found_mesh and aabb.size.length() > 0.1:
		var collision_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = aabb.size
		collision_shape.shape = box_shape
		# Position collision shape at AABB center
		collision_shape.position = aabb.get_center()
		static_body.add_child(collision_shape)

		# Create obstacle vertices (rectangle on XZ plane with padding)
		var half_size := aabb.size * 0.5
		var center := aabb.get_center()
		var pad := 1.0  # Extra padding for navigation
		obstacle_vertices = PackedVector3Array([
			Vector3(center.x - half_size.x - pad, 0, center.z - half_size.z - pad),
			Vector3(center.x + half_size.x + pad, 0, center.z - half_size.z - pad),
			Vector3(center.x + half_size.x + pad, 0, center.z + half_size.z + pad),
			Vector3(center.x - half_size.x - pad, 0, center.z + half_size.z + pad),
		])
	else:
		# Fallback: create a default box collision
		push_warning("[BattleStress] No mesh found for collision on %s, using default box" % path)
		var collision_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(4.0, 4.0, 4.0)
		collision_shape.shape = box_shape
		collision_shape.position = Vector3(0, 2, 0)
		static_body.add_child(collision_shape)

		# Default obstacle vertices
		obstacle_vertices = PackedVector3Array([
			Vector3(-3, 0, -3),
			Vector3(3, 0, -3),
			Vector3(3, 0, 3),
			Vector3(-3, 0, 3),
		])

	# Add NavigationObstacle3D so units path around the building
	var nav_obstacle := NavigationObstacle3D.new()
	nav_obstacle.name = "NavObstacle"
	nav_obstacle.avoidance_enabled = true
	nav_obstacle.use_3d_avoidance = false  # 2D avoidance is faster for ground units
	nav_obstacle.vertices = obstacle_vertices
	nav_obstacle.affect_navigation_mesh = true  # Carve out of nav mesh
	static_body.add_child(nav_obstacle)

	return static_body


func _spawn_town_layout() -> void:
	"""Spawn a full town layout with chokepoints for siege defense stress test.

	Layout (attacker approaches from west/left, defender holds east/right):
	- Chokepoint 1 (X=0): Town gate with flanking walls and guard towers
	- Chokepoint 2 (X=20): Market street with houses lining both sides
	- Chokepoint 3 (X=30): Inner plaza with shops creating narrow passage
	- Town Center (X=40): Capture point with town_hall and market stalls
	- Perimeter: Walls and cottages along Z=+-60
	"""
	print("[BattleStress] Spawning siege town layout (3x map)")

	# === SPAWN CAPTURE POINT AT TOWN CENTER ===
	_stress_capture_point = Node3D.new()
	_stress_capture_point.name = "TownCenterCapturePoint"
	_stress_capture_point.set_script(CapturePointScript)
	_stress_capture_point.capture_radius = 15.0  # Larger for town center
	_stress_capture_point.capture_time = 30.0    # Longer capture time
	_stress_capture_point.point_name = "Town Center"
	_stress_capture_point.initial_owner = "enemy"  # Defender starts with it
	unit_container.add_child(_stress_capture_point)
	_stress_capture_point.global_position = SIEGE_TOWN_CENTER
	_stress_capture_point.add_to_group("capture_points")

	# === CHOKEPOINT 1: TOWN GATE (X=0) ===
	# Gate house at center
	_spawn_town_building("gate_house", Vector3(0, 0, 0), PI/2)

	# Flanking walls to force units through gate
	_spawn_town_building("wall_large", Vector3(0, 0, -25), 0.0)
	_spawn_town_building("wall_large", Vector3(0, 0, 25), 0.0)
	_spawn_town_building("wall_medium", Vector3(0, 0, -40), 0.0)
	_spawn_town_building("wall_medium", Vector3(0, 0, 40), 0.0)

	# Guard towers at corners
	_spawn_town_building("guard_tower", Vector3(-5, 0, -50), PI/4)
	_spawn_town_building("guard_tower", Vector3(-5, 0, 50), -PI/4)

	# === CHOKEPOINT 2: MARKET STREET (X=20) ===
	# Houses lining the street (street width ~15 units)
	for z_offset in [-3, -2, -1, 1, 2, 3]:
		var z: float = z_offset * 12.0
		var house_type: String = _pick_random_house()
		var rotation: float = PI/2 if z_offset > 0 else -PI/2
		_spawn_town_building(house_type, Vector3(20, 0, z), rotation)

	# Additional houses further from center
	_spawn_town_building("cottage", Vector3(18, 0, -50), randf() * TAU)
	_spawn_town_building("cottage", Vector3(22, 0, 50), randf() * TAU)

	# === CHOKEPOINT 3: INNER PLAZA (X=30) ===
	# Shops creating narrower passage
	for z_offset in [-2, -1, 1, 2]:
		var z: float = z_offset * 10.0
		var shop_type: String = _pick_random_commercial()
		_spawn_town_building(shop_type, Vector3(30, 0, z), randf() * TAU)

	# === TOWN CENTER (X=40) ===
	# Town hall behind capture point
	_spawn_town_building("town_hall", SIEGE_TOWN_CENTER + Vector3(15, 0, 0), PI)

	# Market stalls around plaza (not blocking capture point)
	_spawn_town_building("market_stall", SIEGE_TOWN_CENTER + Vector3(0, 0, -18), PI)
	_spawn_town_building("market_stall", SIEGE_TOWN_CENTER + Vector3(0, 0, 18), 0.0)
	_spawn_town_building("shop", SIEGE_TOWN_CENTER + Vector3(-12, 0, -12), PI/4)
	_spawn_town_building("shop", SIEGE_TOWN_CENTER + Vector3(-12, 0, 12), -PI/4)

	# === PERIMETER BUILDINGS (Z=+-55) ===
	# Northern wall line
	for x in range(-4, 6):
		var pos := Vector3(x * 18.0, 0, -55)
		if x % 2 == 0:
			_spawn_town_building("wall_medium", pos, 0.0)
		else:
			_spawn_town_building("cottage", pos, 0.0)

	# Southern wall line
	for x in range(-4, 6):
		var pos := Vector3(x * 18.0, 0, 55)
		if x % 2 == 0:
			_spawn_town_building("wall_medium", pos, PI)
		else:
			_spawn_town_building("hovel", pos, PI)

	# === CORNER TOWERS ===
	_spawn_town_building("wooden_outpost_tower", Vector3(-70, 0, -55), 0.0)
	_spawn_town_building("wooden_outpost_tower", Vector3(-70, 0, 55), 0.0)
	_spawn_town_building("watch_tower", Vector3(70, 0, -55), 0.0)
	_spawn_town_building("watch_tower", Vector3(70, 0, 55), 0.0)

	# === SCATTERED BUILDINGS FOR FLANKING COVER ===
	# West side (attacker approach area)
	_spawn_town_building("cottage", Vector3(-35, 0, -30), randf() * TAU)
	_spawn_town_building("hovel", Vector3(-35, 0, 30), randf() * TAU)
	_spawn_town_building("house_small", Vector3(-50, 0, 0), randf() * TAU)

	# East side (defender staging area)
	_spawn_town_building("blacksmith", Vector3(55, 0, -20), randf() * TAU)
	_spawn_town_building("warehouse", Vector3(55, 0, 20), randf() * TAU)
	_spawn_town_building("house_large", Vector3(60, 0, 0), randf() * TAU)

	print("[BattleStress] Town layout complete: %d buildings, capture point at %s" % [
		_stress_buildings.size(), SIEGE_TOWN_CENTER
	])

	# Rebake navigation mesh to carve out building colliders
	await _rebake_navigation_mesh()


func _spawn_town_building(building_key: String, position: Vector3, rotation: float) -> void:
	"""Helper to spawn a building from the TOWN_BUILDING_MODELS dictionary."""
	if not TOWN_BUILDING_MODELS.has(building_key):
		push_warning("[BattleStress] Unknown building key: %s" % building_key)
		return

	var model_path: String = TOWN_BUILDING_MODELS[building_key]
	var building: Node3D = _load_building_model(model_path)
	if building:
		unit_container.add_child(building)
		building.global_position = position
		building.rotation.y = rotation
		_stress_buildings.append(building)


func _pick_random_house() -> String:
	"""Pick a random residential building type."""
	var houses: Array[String] = ["house_small", "house_medium", "house_large", "cottage", "hovel"]
	return houses[randi() % houses.size()]


func _pick_random_commercial() -> String:
	"""Pick a random commercial building type."""
	var commercial: Array[String] = ["shop", "blacksmith", "warehouse"]
	return commercial[randi() % commercial.size()]


func _clear_stress_scenery() -> void:
	"""Clear capture point and buildings from previous stress test."""
	if _stress_capture_point and is_instance_valid(_stress_capture_point):
		_stress_capture_point.queue_free()
		_stress_capture_point = null

	for building in _stress_buildings:
		if is_instance_valid(building):
			building.queue_free()
	_stress_buildings.clear()


func _rebake_navigation_mesh() -> void:
	"""Rebake the navigation mesh to include newly placed buildings.

	Buildings with StaticBody3D colliders will be carved out of the nav mesh
	so units pathfind around them instead of walking through.
	"""
	# Find terrain (uses "terrain" group as defined in DaggerfallTerrain)
	var terrain = get_tree().get_first_node_in_group("terrain")
	if not terrain:
		push_warning("[BattleStress] No terrain found for nav mesh rebake")
		return

	# DaggerfallTerrain has nav_region as a member variable
	var nav_region: NavigationRegion3D = terrain.get("nav_region")
	if not nav_region:
		push_warning("[BattleStress] Terrain has no nav_region for rebaking")
		return

	print("[BattleStress] Rebaking navigation mesh with %d buildings..." % _stress_buildings.size())

	# Wait a frame to ensure all StaticBody3D colliders are registered
	await get_tree().process_frame

	# Rebake the navigation mesh (synchronous in Godot 4)
	nav_region.bake_navigation_mesh()

	# Wait a frame for the rebake to be fully applied
	await get_tree().process_frame
	print("[BattleStress] Navigation mesh rebake complete")


func _spawn_stress_player_unit(unit_id: String, spawn_offset: Vector3) -> void:
	"""Spawn a player unit for stress testing."""
	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		_battle_stress_errors.append({
			"round": _battle_stress_round,
			"error": "Failed to load player unit: %s" % unit_id
		})
		return

	var new_regiment: Node = REGIMENT_SCENE.instantiate()
	new_regiment.name = "StressPlayer_%d" % player_regiments.size()
	new_regiment.data = data.duplicate()
	new_regiment.is_player_controlled = true  # Player side but AI will control via ai_assist
	new_regiment.use_3d_soldiers = false
	new_regiment.use_sprite_soldiers = not stress_test_headless  # Disable sprites for faster testing
	new_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(new_regiment)

	# Use siege spawn positions if siege mode enabled
	var spawn_x: float = SIEGE_PLAYER_SPAWN_X if stress_test_siege_mode else -25.0
	var scaled_offset: Vector3 = spawn_offset
	if stress_test_3x_map:
		scaled_offset.z *= 2.0  # Spread units more on larger map

	var base_pos: Vector3 = Vector3(spawn_x, 0, 0) + scaled_offset
	new_regiment.sync_all_positions(base_pos)
	new_regiment.set_initial_facing(Vector3(1, 0, 0))  # Face east
	new_regiment.enable_ai_assist(true)
	new_regiment.add_to_group("player_regiments")

	player_regiments.append(new_regiment)

	if player_regiment == null:
		player_regiment = new_regiment


func _spawn_stress_enemy_unit(unit_id: String, spawn_offset: Vector3) -> void:
	"""Spawn an enemy unit for stress testing."""
	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		_battle_stress_errors.append({
			"round": _battle_stress_round,
			"error": "Failed to load enemy unit: %s" % unit_id
		})
		return

	var new_regiment: Node = REGIMENT_SCENE.instantiate()
	new_regiment.name = "StressEnemy_%d" % enemy_regiments.size()
	new_regiment.data = data.duplicate()
	new_regiment.is_player_controlled = false
	new_regiment.use_3d_soldiers = false
	new_regiment.use_sprite_soldiers = not stress_test_headless  # Disable sprites for faster testing
	new_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(new_regiment)

	# Use siege spawn positions if siege mode enabled
	var spawn_x: float = SIEGE_ENEMY_SPAWN_X if stress_test_siege_mode else 25.0
	var scaled_offset: Vector3 = spawn_offset
	if stress_test_3x_map:
		scaled_offset.z *= 2.0  # Spread units more on larger map

	var base_pos: Vector3 = Vector3(spawn_x, 0, 0) + scaled_offset
	new_regiment.sync_all_positions(base_pos)
	new_regiment.set_initial_facing(Vector3(-1, 0, 0))  # Face west
	new_regiment.enable_ai_assist(true)
	new_regiment.add_to_group("enemy_regiments")

	enemy_regiments.append(new_regiment)

	if enemy_regiment == null:
		enemy_regiment = new_regiment


# Stress test AI state
var _stress_player_general_ai: GeneralAI = null
var _stress_enemy_general_ai: GeneralAI = null


func _setup_stress_test_ais() -> void:
	"""Setup GeneralAIs for BOTH sides during stress testing.
	Normal battles only set up enemy AI, but stress tests need both sides to fight.
	Also sets all units to AGGRESSIVE stance so they actively pursue enemies.
	With attacker/defender objectives enabled, player is BREAKTHROUGH, enemy is HOLD_GROUND."""

	var player_regs := get_tree().get_nodes_in_group("player_regiments")
	var enemy_regs := get_tree().get_nodes_in_group("enemy_regiments")

	# Calculate enemy center for objectives
	var enemy_center := Vector3.ZERO
	for r in enemy_regs:
		if is_instance_valid(r):
			enemy_center += r.global_position
	if enemy_regs.size() > 0:
		enemy_center /= float(enemy_regs.size())
	enemy_center.y = 0.0

	# Setup player GeneralAI (faction 0) - ATTACKER with BREAKTHROUGH
	if player_regs.size() > 0:
		_stress_player_general_ai = GeneralAI.new(0)  # faction 0 = player

		# Set objective if enabled
		if stress_test_attacker_defender_objectives:
			var player_obj := BattleObjectiveClass.new()
			player_obj.type = BattleObjectiveClass.Type.BREAKTHROUGH
			player_obj.time_limit_sec = _battle_stress_duration  # Time pressure
			player_obj.hold_position = enemy_center  # Target for breakthrough
			_stress_player_general_ai.objective = player_obj
			print("[StressTest] Player objective: BREAKTHROUGH (target enemy center)")

		AIAutoload.register_general_ai(_stress_player_general_ai, 0)

		var linked: int = 0
		for reg in player_regs:
			if is_instance_valid(reg) and reg.ai_controller:
				_stress_player_general_ai.register_commander(reg, reg.ai_controller)
				# Set to AGGRESSIVE stance so units pursue enemies (120m acquire vs 25m defensive)
				reg.ai_controller.set_stance(CommanderAI.Stance.AGGRESSIVE)
				linked += 1

		print("[StressTest] Player GeneralAI: %d/%d regiments linked (AGGRESSIVE)" % [linked, player_regs.size()])

	# Calculate player center for enemy objective
	var player_center := Vector3.ZERO
	for r in player_regs:
		if is_instance_valid(r):
			player_center += r.global_position
	if player_regs.size() > 0:
		player_center /= float(player_regs.size())
	player_center.y = 0.0

	# Setup enemy GeneralAI (faction 1) - DEFENDER with HOLD_GROUND
	if enemy_regs.size() > 0:
		_stress_enemy_general_ai = GeneralAI.new(1)  # faction 1 = enemy

		# Set objective if enabled
		if stress_test_attacker_defender_objectives:
			var enemy_obj := BattleObjectiveClass.new()
			enemy_obj.type = BattleObjectiveClass.Type.HOLD_GROUND
			enemy_obj.time_limit_sec = -1.0  # No time pressure for defender
			enemy_obj.hold_position = enemy_center  # Hold their starting position
			enemy_obj.hold_radius = 40.0  # Allow some movement
			_stress_enemy_general_ai.objective = enemy_obj
			print("[StressTest] Enemy objective: HOLD_GROUND (radius %.0fm)" % enemy_obj.hold_radius)

		AIAutoload.register_general_ai(_stress_enemy_general_ai, 1)

		var linked: int = 0
		for reg in enemy_regs:
			if is_instance_valid(reg) and reg.ai_controller:
				_stress_enemy_general_ai.register_commander(reg, reg.ai_controller)
				# Defenders still use AGGRESSIVE to respond to threats
				reg.ai_controller.set_stance(CommanderAI.Stance.AGGRESSIVE)
				linked += 1

		print("[StressTest] Enemy GeneralAI: %d/%d regiments linked (AGGRESSIVE)" % [linked, enemy_regs.size()])

	# Force immediate attack orders - pick a target and move towards it
	# Player units attack nearest enemy
	for reg in player_regs:
		if is_instance_valid(reg) and reg.ai_controller:
			var target := _find_nearest_enemy(reg, enemy_regs)
			if target:
				reg.ai_controller.set_target(target)
				reg.ai_controller.issue_attack_order(target)

	# Enemy units attack nearest player
	for reg in enemy_regs:
		if is_instance_valid(reg) and reg.ai_controller:
			var target := _find_nearest_enemy(reg, player_regs)
			if target:
				reg.ai_controller.set_target(target)
				reg.ai_controller.issue_attack_order(target)

	print("[StressTest] Attack orders issued - combat should begin")


func _find_nearest_enemy(regiment: Node, candidates: Array) -> Node:
	"""Find the nearest valid enemy regiment."""
	var nearest: Node = null
	var nearest_dist: float = INF
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		if candidate.state == Regiment.State.DEAD:
			continue
		var dist: float = regiment.global_position.distance_to(candidate.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = candidate
	return nearest


func _cleanup_stress_ais() -> void:
	"""Cleanup stress test GeneralAIs."""
	if _stress_player_general_ai:
		AIAutoload.unregister_general_ai(0)
		_stress_player_general_ai = null
	if _stress_enemy_general_ai:
		AIAutoload.unregister_general_ai(1)
		_stress_enemy_general_ai = null


func _connect_stress_test_signals() -> void:
	"""Connect to BattleSignals for tracking routing, flanking, charges, and AI plays."""
	if not BattleSignals:
		return
	if BattleSignals.has_signal("regiment_routing") and not BattleSignals.regiment_routing.is_connected(_on_stress_regiment_routing):
		BattleSignals.regiment_routing.connect(_on_stress_regiment_routing)
	if BattleSignals.has_signal("unit_flanked") and not BattleSignals.unit_flanked.is_connected(_on_stress_unit_flanked):
		BattleSignals.unit_flanked.connect(_on_stress_unit_flanked)
	if BattleSignals.has_signal("charge_impact") and not BattleSignals.charge_impact.is_connected(_on_stress_charge_impact):
		BattleSignals.charge_impact.connect(_on_stress_charge_impact)
	if BattleSignals.has_signal("ai_play_started") and not BattleSignals.ai_play_started.is_connected(_on_stress_ai_play_started):
		BattleSignals.ai_play_started.connect(_on_stress_ai_play_started)
	if BattleSignals.has_signal("regiment_attacked") and not BattleSignals.regiment_attacked.is_connected(_on_stress_regiment_attacked):
		BattleSignals.regiment_attacked.connect(_on_stress_regiment_attacked)


func _disconnect_stress_test_signals() -> void:
	"""Disconnect stress test signal handlers."""
	if not BattleSignals:
		return
	if BattleSignals.has_signal("regiment_routing") and BattleSignals.regiment_routing.is_connected(_on_stress_regiment_routing):
		BattleSignals.regiment_routing.disconnect(_on_stress_regiment_routing)
	if BattleSignals.has_signal("unit_flanked") and BattleSignals.unit_flanked.is_connected(_on_stress_unit_flanked):
		BattleSignals.unit_flanked.disconnect(_on_stress_unit_flanked)
	if BattleSignals.has_signal("charge_impact") and BattleSignals.charge_impact.is_connected(_on_stress_charge_impact):
		BattleSignals.charge_impact.disconnect(_on_stress_charge_impact)
	if BattleSignals.has_signal("ai_play_started") and BattleSignals.ai_play_started.is_connected(_on_stress_ai_play_started):
		BattleSignals.ai_play_started.disconnect(_on_stress_ai_play_started)
	if BattleSignals.has_signal("regiment_attacked") and BattleSignals.regiment_attacked.is_connected(_on_stress_regiment_attacked):
		BattleSignals.regiment_attacked.disconnect(_on_stress_regiment_attacked)


# Track first contact per battle (only record once per battle)
var _agent_first_contact_recorded: bool = false


func _on_stress_regiment_routing(regiment: Node) -> void:
	"""Track routing events during stress test."""
	if _battle_stress_running:
		_battle_stress_routing_count += 1
		# Record agent event
		if agent_json_export_enabled:
			var unit_id: String = regiment.data.id if regiment.data else regiment.name
			_agent_battle_events.append({
				"t": _get_agent_battle_time(),
				"type": "rout",
				"regiment": unit_id
			})


func _on_stress_unit_flanked(attacker: Node, defender: Node, zone: String) -> void:
	"""Track flanking events during stress test."""
	if not _battle_stress_running:
		return
	if zone == "flank":
		_battle_stress_flank_count += 1
	elif zone == "rear":
		_battle_stress_rear_count += 1

	# Record agent event
	if agent_json_export_enabled:
		var flanker_id: String = attacker.data.id if attacker.data else attacker.name
		var flanked_id: String = defender.data.id if defender.data else defender.name
		_agent_battle_events.append({
			"t": _get_agent_battle_time(),
			"type": "flank" if zone == "flank" else "rear",
			"flanker": flanker_id,
			"flanked": flanked_id
		})


func _on_stress_charge_impact(charger: Node, target: Node, was_braced: bool) -> void:
	"""Track charge impact events during stress test."""
	if not _battle_stress_running:
		return

	# Update totals
	if agent_json_export_enabled:
		_agent_run_data.totals.total_charge_impacts += 1

		var charger_id: String = charger.data.id if charger.data else charger.name
		var target_id: String = target.data.id if target.data else target.name
		_agent_battle_events.append({
			"t": _get_agent_battle_time(),
			"type": "charge_impact",
			"charger": charger_id,
			"target": target_id,
			"braced": was_braced
		})


func _on_stress_ai_play_started(general_ai, play_name: String) -> void:
	"""Track AI play events during stress test."""
	if not _battle_stress_running or not agent_json_export_enabled:
		return

	# Determine which side the AI is on
	var side: String = "unknown"
	if general_ai and "is_player_controlled" in general_ai:
		side = "player" if general_ai.is_player_controlled else "enemy"

	_agent_ai_plays.append({
		"t": _get_agent_battle_time(),
		"side": side,
		"play": play_name
	})


func _on_stress_regiment_attacked(attacker: Node, defender: Node, damage: int) -> void:
	"""Track first contact event during stress test."""
	if not _battle_stress_running or not agent_json_export_enabled:
		return

	# Only record first contact once per battle
	if _agent_first_contact_recorded:
		return
	_agent_first_contact_recorded = true

	var attacker_id: String = attacker.data.id if attacker.data else attacker.name
	var defender_id: String = defender.data.id if defender.data else defender.name
	_agent_battle_events.append({
		"t": _get_agent_battle_time(),
		"type": "first_contact",
		"attacker": attacker_id,
		"defender": defender_id
	})


func _get_agent_battle_time() -> float:
	"""Get elapsed time since battle started in seconds."""
	return (Time.get_ticks_msec() / 1000.0) - _agent_battle_start_time


func _run_stress_battle_timer() -> void:
	"""Run the battle for the specified duration."""
	while _battle_stress_running and _battle_stress_timer < _battle_stress_duration:
		await get_tree().create_timer(1.0).timeout
		_battle_stress_timer += 1.0

		# Check for errors every 5 seconds
		if int(_battle_stress_timer) % 5 == 0:
			_check_stress_battle_state()

		# Check if battle ended early (one side wiped)
		if _is_battle_over():
			break

	# Print round summary
	if _battle_stress_running:
		_print_round_summary()
		_start_next_stress_battle()


func _print_round_summary() -> void:
	"""Print summary of the completed round."""
	# Count surviving soldiers
	var player_survivors: int = 0
	var enemy_survivors: int = 0
	var player_alive_units: int = 0
	var enemy_alive_units: int = 0

	for reg in player_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0:
			player_survivors += reg.current_soldiers
			if reg.state != reg.State.DEAD:
				player_alive_units += 1

	for reg in enemy_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0:
			enemy_survivors += reg.current_soldiers
			if reg.state != reg.State.DEAD:
				enemy_alive_units += 1

	# Calculate casualties
	var player_casualties: int = _battle_stress_player_start_soldiers - player_survivors
	var enemy_casualties: int = _battle_stress_enemy_start_soldiers - enemy_survivors

	# Determine winner
	var winner: String = "DRAW"
	if player_alive_units == 0 and enemy_alive_units > 0:
		winner = "ENEMY WIN"
		if stress_test_faction_based and _battle_stress_enemy_faction:
			_battle_stress_faction_wins[_battle_stress_enemy_faction] += 1
	elif enemy_alive_units == 0 and player_alive_units > 0:
		winner = "PLAYER WIN"
		if stress_test_faction_based and _battle_stress_player_faction:
			_battle_stress_faction_wins[_battle_stress_player_faction] += 1
	elif player_casualties < enemy_casualties:
		winner = "Player advantage"
		if stress_test_faction_based and _battle_stress_player_faction:
			_battle_stress_faction_wins[_battle_stress_player_faction] += 1
	elif enemy_casualties < player_casualties:
		winner = "Enemy advantage"
		if stress_test_faction_based and _battle_stress_enemy_faction:
			_battle_stress_faction_wins[_battle_stress_enemy_faction] += 1

	# Print summary
	print("[BattleStress] --- Round %d Result: %s (%.0fs) ---" % [
		_battle_stress_round, winner, _battle_stress_timer])
	if stress_test_faction_based:
		print("[BattleStress]   %s vs %s" % [_battle_stress_player_faction, _battle_stress_enemy_faction])
	print("[BattleStress]   Player: %d/%d survived (%d casualties)" % [
		player_survivors, _battle_stress_player_start_soldiers, player_casualties])
	print("[BattleStress]   Enemy:  %d/%d survived (%d casualties)" % [
		enemy_survivors, _battle_stress_enemy_start_soldiers, enemy_casualties])

	# Count errors this round
	var round_errors: int = 0
	for error in _battle_stress_errors:
		if error.round == _battle_stress_round:
			round_errors += 1
	if round_errors > 0:
		print("[BattleStress]   ⚠ ERRORS THIS ROUND: %d" % round_errors)

	# Collect agent battle data
	if agent_json_export_enabled:
		# Determine outcome type
		var outcome: String = "draw"
		var is_decisive: bool = false
		if player_alive_units == 0 and enemy_alive_units > 0:
			outcome = "decisive_enemy_win"
			is_decisive = true
		elif enemy_alive_units == 0 and player_alive_units > 0:
			outcome = "decisive_player_win"
			is_decisive = true
		elif player_casualties < enemy_casualties:
			outcome = "player_advantage"
		elif enemy_casualties < player_casualties:
			outcome = "enemy_advantage"

		# Collect per-unit stats
		var player_units_stats: Array = []
		for reg in player_regiments:
			if is_instance_valid(reg):
				var unit_id: String = reg.data.id if reg.data else reg.name
				player_units_stats.append({
					"unit_id": unit_id,
					"starting": reg.max_soldiers if "max_soldiers" in reg else 0,
					"remaining": reg.current_soldiers,
					"state": _get_state_name(reg)
				})

		var enemy_units_stats: Array = []
		for reg in enemy_regiments:
			if is_instance_valid(reg):
				var unit_id: String = reg.data.id if reg.data else reg.name
				enemy_units_stats.append({
					"unit_id": unit_id,
					"starting": reg.max_soldiers if "max_soldiers" in reg else 0,
					"remaining": reg.current_soldiers,
					"state": _get_state_name(reg)
				})

		# Build battle record
		var battle_record: Dictionary = {
			"battle_idx": _battle_stress_round,
			"duration_sec": _battle_stress_timer,
			"outcome": outcome,
			"weather": WEATHER_TYPE_NAMES[_battle_stress_current_weather] if stress_test_weather_variation else "Clear",
			"player_faction": _battle_stress_player_faction,
			"enemy_faction": _battle_stress_enemy_faction,
			"player_start_soldiers": _battle_stress_player_start_soldiers,
			"enemy_start_soldiers": _battle_stress_enemy_start_soldiers,
			"player_survivors": player_survivors,
			"enemy_survivors": enemy_survivors,
			"player_casualties": player_casualties,
			"enemy_casualties": enemy_casualties,
			"player_units": player_units_stats,
			"enemy_units": enemy_units_stats,
			"events": _agent_battle_events.duplicate(),
			"ai_plays": _agent_ai_plays.duplicate()
		}
		_agent_battles.append(battle_record)

		# Update run totals
		_agent_run_data.totals.battles_run += 1
		if is_decisive:
			_agent_run_data.totals.battles_decisive += 1


func is_stress_test_running() -> bool:
	"""Return whether stress test is currently running (used to skip battle over screen)."""
	return _battle_stress_running


func _check_stress_battle_state() -> void:
	"""Check battle state and print combat status."""
	# Print combat status every 5 seconds
	_print_combat_status()

	# Check player regiments for anomalies
	for reg in player_regiments:
		if not is_instance_valid(reg):
			continue
		_validate_regiment_state(reg, "Player")

	# Check enemy regiments for anomalies
	for reg in enemy_regiments:
		if not is_instance_valid(reg):
			continue
		_validate_regiment_state(reg, "Enemy")


func _print_combat_status() -> void:
	"""Print current combat status (soldiers, morale, state)."""
	var player_soldiers: int = 0
	var enemy_soldiers: int = 0
	var player_status: Array[String] = []
	var enemy_status: Array[String] = []

	for reg in player_regiments:
		if not is_instance_valid(reg):
			continue
		player_soldiers += reg.current_soldiers
		var morale: float = reg.current_morale if "current_morale" in reg else 100.0
		var state_name: String = _get_state_name(reg)
		player_status.append("%s:%d/M%.0f/%s" % [
			reg.data.regiment_name.substr(0, 6) if reg.data else "???",
			reg.current_soldiers,
			morale,
			state_name
		])

	for reg in enemy_regiments:
		if not is_instance_valid(reg):
			continue
		enemy_soldiers += reg.current_soldiers
		var morale: float = reg.current_morale if "current_morale" in reg else 100.0
		var state_name: String = _get_state_name(reg)
		enemy_status.append("%s:%d/M%.0f/%s" % [
			reg.data.regiment_name.substr(0, 6) if reg.data else "???",
			reg.current_soldiers,
			morale,
			state_name
		])

	var player_casualties: int = _battle_stress_player_start_soldiers - player_soldiers
	var enemy_casualties: int = _battle_stress_enemy_start_soldiers - enemy_soldiers

	print("[Combat@%.0fs] P:%d(-%.0f) vs E:%d(-%.0f) | %s | %s" % [
		_battle_stress_timer,
		player_soldiers, player_casualties,
		enemy_soldiers, enemy_casualties,
		" ".join(player_status),
		" ".join(enemy_status)
	])


func _get_state_name(reg: Node) -> String:
	"""Get short state name for regiment."""
	if not "state" in reg:
		return "?"
	match reg.state:
		0: return "IDLE"  # State.IDLE
		1: return "MOVE"  # State.MOVING
		2: return "FIGHT" # State.FIGHTING
		3: return "ROUT"  # State.ROUTING
		4: return "RALLY" # State.RALLYING
		5: return "DEAD"  # State.DEAD
		_: return "?"


func _validate_regiment_state(reg: Node, side: String) -> void:
	"""Validate a regiment's state for bugs."""
	# Check for invalid morale
	if reg.has_method("get") and "current_morale" in reg:
		var morale: float = reg.current_morale
		if morale < 0.0 or morale > 150.0:
			_battle_stress_errors.append({
				"round": _battle_stress_round,
				"error": "%s %s: Invalid morale %.1f" % [side, reg.name, morale]
			})

	# Check for negative soldiers
	if "current_soldiers" in reg:
		var soldiers: int = reg.current_soldiers
		if soldiers < 0:
			_battle_stress_errors.append({
				"round": _battle_stress_round,
				"error": "%s %s: Negative soldiers %d" % [side, reg.name, soldiers]
			})

	# Skip stuck state check - the State enum access was causing issues


func _is_battle_over() -> bool:
	"""Check if the battle has ended."""
	var player_alive: int = 0
	var enemy_alive: int = 0

	for reg in player_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0 and reg.state != reg.State.DEAD:
			player_alive += 1

	for reg in enemy_regiments:
		if is_instance_valid(reg) and reg.current_soldiers > 0 and reg.state != reg.State.DEAD:
			enemy_alive += 1

	return player_alive == 0 or enemy_alive == 0


func _complete_battle_stress_test() -> void:
	"""Complete the battle stress test and report results."""
	_battle_stress_running = false
	_update_stress_test_counter()  # Hide counter
	_cleanup_stress_ais()
	_disconnect_stress_test_signals()
	_clear_stress_scenery()  # Clean up capture point and buildings

	# Reset time scale
	Engine.time_scale = 1.0

	var sep: String = "======================================================================"
	print("\n" + sep)
	print("[BATTLE STRESS TEST] COMPLETE")
	print("[BATTLE STRESS TEST] Rounds: %d" % _battle_stress_round)
	print("[BATTLE STRESS TEST] Errors found: %d" % _battle_stress_errors.size())

	# Combat tracking stats
	print("\n[BATTLE STRESS TEST] Combat Statistics:")
	print("  Routing events: %d (%.1f per battle)" % [
		_battle_stress_routing_count, float(_battle_stress_routing_count) / maxi(1, _battle_stress_round)])
	print("  Flank attacks: %d (%.1f per battle)" % [
		_battle_stress_flank_count, float(_battle_stress_flank_count) / maxi(1, _battle_stress_round)])
	print("  Rear attacks: %d (%.1f per battle)" % [
		_battle_stress_rear_count, float(_battle_stress_rear_count) / maxi(1, _battle_stress_round)])

	if stress_test_weather_variation:
		print("  Weather cycled through: %s" % str(WEATHER_TYPE_NAMES))

	if stress_test_attacker_defender_objectives:
		print("  Objectives: Player=BREAKTHROUGH, Enemy=HOLD_GROUND")

	# Print faction standings if faction-based
	if stress_test_faction_based and _battle_stress_faction_wins.size() > 0:
		print("\n[BATTLE STRESS TEST] Faction Win Rankings:")
		# Sort factions by wins (descending)
		var faction_standings: Array = []
		for faction in _battle_stress_faction_wins:
			faction_standings.append({"faction": faction, "wins": _battle_stress_faction_wins[faction]})
		faction_standings.sort_custom(func(a, b): return a.wins > b.wins)
		for i in faction_standings.size():
			var s = faction_standings[i]
			print("  %d. %-10s: %d wins" % [i + 1, s.faction, s.wins])

	if _battle_stress_errors.size() > 0:
		print("\n[BATTLE STRESS TEST] Error details:")
		for error in _battle_stress_errors:
			print("  Round %d: %s" % [error.round, error.error])
	else:
		print("\n[BATTLE STRESS TEST] All battles passed!")

	# Write agent JSON export
	if agent_json_export_enabled:
		_write_agent_run_report()

	print(sep + "\n")

	# Auto-quit for daemon/headless mode
	if stress_test_quit_when_done:
		print("[BATTLE STRESS TEST] Quitting Godot (stress_test_quit_when_done=true)")
		await get_tree().create_timer(0.5).timeout  # Brief delay to flush output
		get_tree().quit(0)


func _write_agent_run_report() -> void:
	"""Write the agent JSON report file."""
	# Finalize run totals
	_agent_run_data.totals.total_routs = _battle_stress_routing_count
	_agent_run_data.totals.total_flank_events = _battle_stress_flank_count
	_agent_run_data.totals.total_rear_events = _battle_stress_rear_count

	# Build faction statistics
	if stress_test_faction_based:
		for faction in _battle_stress_faction_wins:
			var wins: int = _battle_stress_faction_wins[faction]
			var total_battles: int = _agent_run_data.totals.battles_run
			# Count battles involving this faction
			var faction_battles: int = 0
			var faction_losses: int = 0
			var faction_draws: int = 0
			for battle in _agent_battles:
				if battle.player_faction == faction or battle.enemy_faction == faction:
					faction_battles += 1
					if battle.outcome == "draw":
						faction_draws += 1
					elif (battle.outcome == "decisive_player_win" or battle.outcome == "player_advantage") and battle.enemy_faction == faction:
						faction_losses += 1
					elif (battle.outcome == "decisive_enemy_win" or battle.outcome == "enemy_advantage") and battle.player_faction == faction:
						faction_losses += 1

			_agent_run_data.by_faction[faction] = {
				"wins": wins,
				"losses": faction_losses,
				"draws": faction_draws,
				"win_rate": float(wins) / maxi(1, faction_battles)
			}

	# Add battles array
	_agent_run_data["battles"] = _agent_battles

	# Add errors array
	_agent_run_data["errors"] = _battle_stress_errors

	# Build file path
	var timestamp: String = Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "T")
	var dir_path: String = "user://agent"
	var file_path: String = "%s/run_%s.json" % [dir_path, timestamp]

	# Ensure directory exists
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("agent"):
			var err := dir.make_dir("agent")
			if err != OK:
				push_error("[BattleDebug] Failed to create agent directory: %d" % err)
				return

	# Write JSON file
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		push_error("[BattleDebug] Failed to open JSON file for writing: %s" % file_path)
		return

	var json_string: String = JSON.stringify(_agent_run_data, "\t")
	file.store_string(json_string)
	file.close()

	print("\n[BATTLE STRESS TEST] Agent JSON exported to: %s" % file_path)

	# Also print the resolved absolute path
	var global_path: String = ProjectSettings.globalize_path(file_path)
	print("[BATTLE STRESS TEST] Absolute path: %s" % global_path)


func stop_battle_stress_test() -> void:
	"""Stop the battle stress test."""
	if _battle_stress_running:
		_battle_stress_running = false
		_cleanup_stress_ais()
		_disconnect_stress_test_signals()
		Engine.time_scale = 1.0
		print("[BattleStress] Test stopped at round %d" % _battle_stress_round)


# =============================================================================
# MELEE DUEL TORTURE TEST
# =============================================================================

func _auto_start_melee_duel_after_delay() -> void:
	"""Auto-start melee duel test after initial setup."""
	await get_tree().create_timer(2.0).timeout
	print("[UnitZoo] Auto-starting melee duel torture test...")
	start_melee_duel_test()


func start_melee_duel_test() -> void:
	"""Start the melee duel torture test (40 isolated 1v1 fights)."""
	if _melee_duel_runner and is_instance_valid(_melee_duel_runner):
		print("[UnitZoo] Melee duel test already running")
		return

	# Stop any running stress test first
	if _battle_stress_running:
		stop_battle_stress_test()

	# Clear existing units
	_clear_player_units()
	_clear_enemy_units()
	await get_tree().process_frame

	# Create and configure runner
	_melee_duel_runner = MeleeDuelRunnerScript.new()
	_melee_duel_runner.TOTAL_DUELS = melee_duel_test_rounds
	_melee_duel_runner.MAX_RALLY_CYCLES = melee_duel_rally_cycles
	_melee_duel_runner.quit_when_done = false  # Don't quit, we're inside unit zoo
	add_child(_melee_duel_runner)

	print("[UnitZoo] Melee duel torture test started (%d rounds, %d rally cycles)" % [
		melee_duel_test_rounds, melee_duel_rally_cycles])


func stop_melee_duel_test() -> void:
	"""Stop the melee duel torture test."""
	if _melee_duel_runner and is_instance_valid(_melee_duel_runner):
		_melee_duel_runner.queue_free()
		_melee_duel_runner = null
		Engine.time_scale = 1.0  # Reset time scale
		print("[UnitZoo] Melee duel test stopped")
