extends Node3D


@onready var battle_terrain: Node3D = $BattleTerrain

var player_regiments: Array[Regiment] = []
var enemy_regiments: Array[Regiment] = []

# =============================================================================
# STRESS TEST CONFIGURATION
# =============================================================================
# Set to true to spawn 80 units on each side for performance testing
@export var stress_test_mode: bool = false
@export var stress_test_units_per_side: int = 80

# Regiment data for stress testing - mix of unit types
const STRESS_TEST_PLAYER_REGIMENTS: Array[String] = [
	"res://battle_system/data/regiments/grtsword_regiment.tres",  # Infantry
	"res://battle_system/data/regiments/halb_regiment.tres",      # Infantry
	"res://battle_system/data/regiments/reik_regiment.tres",      # Infantry
	"res://battle_system/data/regiments/dwwar_regiment.tres",     # Infantry
	"res://battle_system/data/regiments/ironbrks_regiment.tres",  # Infantry
	"res://battle_system/data/regiments/dwxbow_regiment.tres",    # Ranged
	"res://battle_system/data/regiments/mercxbow_regiment.tres",  # Ranged
	"res://battle_system/data/regiments/brdhrs_regiment.tres",    # Cavalry
]

const STRESS_TEST_ENEMY_REGIMENTS: Array[String] = [
	"res://battle_system/data/regiments/blackorc_regiment.tres",  # Infantry
	"res://battle_system/data/regiments/orcboyz_regiment.tres",   # Infantry
	"res://battle_system/data/regiments/ntgoblin_regiment.tres",  # Infantry
	"res://battle_system/data/regiments/orc2_regiment.tres",      # Infantry
	"res://battle_system/data/regiments/clanrats_regiment.tres",  # Infantry
	"res://battle_system/data/regiments/arraboyz_regiment.tres",  # Ranged
	"res://battle_system/data/regiments/gobarch_regiment.tres",   # Ranged
	"res://battle_system/data/regiments/wolfride_regiment.tres",  # Cavalry
]


func _ready():
	# Wait for terrain to generate
	await get_tree().create_timer(0.6).timeout

	# Safety check - scene might be freed during await
	if not is_instance_valid(self):
		return

	# STRESS TEST MODE: Spawn 80 units on each side
	if stress_test_mode:
		print("[STRESS TEST] Spawning %d units per side..." % stress_test_units_per_side)
		_setup_stress_test()
	# Check if coming from campaign with pre-defined regiments
	# Use has_node to safely check for autoload
	elif get_node_or_null("/root/BattleTransition") and get_node_or_null("/root/BattleTransition").has_battle_data():
		_setup_from_campaign()
	else:
		# Find all regiments (standalone mode)
		_gather_regiments()

	# Position regiments on terrain
	for regiment in player_regiments + enemy_regiments:
		_position_regiment_on_terrain(regiment)

	# Set initial camera position
	var camera = get_node_or_null("BattleCamera")
	if camera:
		camera.position = Vector3(0, 50, 50)  # Higher up for stress test view

	# Don't auto-start battle - let deployment phase run first
	# Player clicks "CLICK TO START" button in BattleHUD to begin combat
	# The deployment_panel in battle_hud.gd handles this via _on_start_battle_pressed()

	if stress_test_mode:
		print("[STRESS TEST] Setup complete. %d player + %d enemy = %d total regiments" % [
			player_regiments.size(), enemy_regiments.size(),
			player_regiments.size() + enemy_regiments.size()
		])


func _setup_from_campaign() -> void:
	# Get regiment data from campaign
	var player_data: Array = BattleTransition.get_player_regiments()
	var enemy_data: Array = BattleTransition.get_enemy_regiments()

	# Spawn player regiments
	var player_spawn_x := -20.0
	for i in range(player_data.size()):
		var regiment_data: RegimentData = player_data[i]
		var regiment := _spawn_regiment_from_data(regiment_data, true)
		regiment.position = Vector3(player_spawn_x, 0, -10 + i * 8)
		player_regiments.append(regiment)

	# Spawn enemy regiments
	var enemy_spawn_x := 20.0
	for i in range(enemy_data.size()):
		var regiment_data: RegimentData = enemy_data[i]
		var regiment := _spawn_regiment_from_data(regiment_data, false)
		regiment.position = Vector3(enemy_spawn_x, 0, -10 + i * 8)
		enemy_regiments.append(regiment)


func _spawn_regiment_from_data(data: RegimentData, is_player: bool) -> Regiment:
	# Load regiment scene
	var regiment_scene := preload("res://battle_system/nodes/regiment.tscn")
	var regiment: Regiment = regiment_scene.instantiate()

	# Apply data
	regiment.data = data.duplicate()
	regiment.is_player_controlled = is_player
	regiment.current_soldiers = data.current_soldiers

	# Force sprite-based soldiers only (no 3D models)
	regiment.use_sprite_soldiers = true
	regiment.use_3d_soldiers = false

	# Add to scene and groups
	add_child(regiment)
	regiment.add_to_group("all_regiments")
	if is_player:
		regiment.add_to_group("player_regiments")
	else:
		regiment.add_to_group("enemy_regiments")

	return regiment


func _gather_regiments():
	player_regiments.clear()
	enemy_regiments.clear()

	# Find all children that are regiments
	for child in get_children():
		if child is Regiment:
			# Check if player or enemy by naming convention or explicit setting
			if child.name.begins_with("Player") or child.is_player_controlled:
				child.is_player_controlled = true
				player_regiments.append(child)
			elif child.name.begins_with("Enemy") or not child.is_player_controlled:
				child.is_player_controlled = false
				enemy_regiments.append(child)

	# Also check nested regiments
	for regiment in get_tree().get_nodes_in_group("player_regiments"):
		if regiment is Regiment and regiment not in player_regiments:
			player_regiments.append(regiment)

	for regiment in get_tree().get_nodes_in_group("enemy_regiments"):
		if regiment is Regiment and regiment not in enemy_regiments:
			enemy_regiments.append(regiment)


func _position_regiment_on_terrain(regiment: Regiment):
	if battle_terrain and battle_terrain.terrain:
		var height = battle_terrain.terrain.get_height_at(regiment.global_position)
		regiment.global_position.y = height + 0.5


# =============================================================================
# STRESS TEST SPAWNING
# =============================================================================

func _setup_stress_test() -> void:
	## Spawn many units for performance stress testing.
	## Removes existing scene regiments and spawns fresh ones in grid formation.

	# First, remove existing regiments from scene (the ones defined in .tscn)
	for child in get_children():
		if child is Regiment:
			child.queue_free()

	player_regiments.clear()
	enemy_regiments.clear()

	# Load regiment data resources
	var player_regiment_resources: Array = []
	for path in STRESS_TEST_PLAYER_REGIMENTS:
		var res = load(path)
		if res:
			player_regiment_resources.append(res)

	var enemy_regiment_resources: Array = []
	for path in STRESS_TEST_ENEMY_REGIMENTS:
		var res = load(path)
		if res:
			enemy_regiment_resources.append(res)

	if player_regiment_resources.is_empty() or enemy_regiment_resources.is_empty():
		push_error("[STRESS TEST] Failed to load regiment resources!")
		return

	# Calculate grid layout - aim for roughly 10 rows x 8 columns
	var units_per_row: int = 8
	var row_spacing: float = 12.0  # Z spacing between rows
	var col_spacing: float = 15.0  # X spacing between units in row (wider for formations)

	# Spawn player units on LEFT side (negative X)
	var player_start_x: float = -80.0
	var player_start_z: float = -50.0

	for i in range(stress_test_units_per_side):
		var row: int = i / units_per_row
		var col: int = i % units_per_row

		var pos := Vector3(
			player_start_x + col * col_spacing,
			10.0,
			player_start_z + row * row_spacing
		)

		# Cycle through regiment types
		var regiment_data: RegimentData = player_regiment_resources[i % player_regiment_resources.size()]
		var regiment := _spawn_regiment_from_data(regiment_data.duplicate(), true)
		regiment.name = "PlayerUnit_%d" % i
		regiment.global_position = pos
		player_regiments.append(regiment)

	# Spawn enemy units on RIGHT side (positive X)
	var enemy_start_x: float = 80.0
	var enemy_start_z: float = -50.0

	for i in range(stress_test_units_per_side):
		var row: int = i / units_per_row
		var col: int = i % units_per_row

		var pos := Vector3(
			enemy_start_x - col * col_spacing,  # Mirror the column placement
			10.0,
			enemy_start_z + row * row_spacing
		)

		# Cycle through regiment types
		var regiment_data: RegimentData = enemy_regiment_resources[i % enemy_regiment_resources.size()]
		var regiment := _spawn_regiment_from_data(regiment_data.duplicate(), false)
		regiment.name = "EnemyUnit_%d" % i
		regiment.global_position = pos
		enemy_regiments.append(regiment)

	print("[STRESS TEST] Spawned %d player units and %d enemy units" % [
		player_regiments.size(), enemy_regiments.size()
	])
