extends Node3D

# Preload for initial facing setup (Bug C fix)
const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")

@onready var battle_terrain: Node3D = $BattleTerrain

var player_regiments: Array[Regiment] = []
var enemy_regiments: Array[Regiment] = []

# =============================================================================
# STRESS TEST CONFIGURATION
# =============================================================================
# Set to true to spawn units on each side for performance testing
@export var stress_test_mode: bool = true
@export var stress_test_units_per_side: int = 20
@export var enable_dynamic_weather: bool = true
@export var auto_start_battle: bool = true  # Auto-start battle after 2s for AI testing
@export var siege_defense_mode: bool = false  # Spawn defenders at capture points

# Regiment data for stress testing - Player: Melee front, Ranged middle, Artillery back
# ORDER MATTERS: First units spawn in FRONT row, last units spawn in BACK
const STRESS_TEST_PLAYER_REGIMENTS: Array[String] = [
	# === FRONT LINE: Melee Infantry (10 units) ===
	"res://battle_system/data/regiments/grtsword_regiment.tres",  # Greatswords
	"res://battle_system/data/regiments/empsword_regiment.tres",  # Empire Swords
	"res://battle_system/data/regiments/mcsword_regiment.tres",   # Merc Swords
	"res://battle_system/data/regiments/bodygrd_regiment.tres",   # Bodyguard
	"res://battle_system/data/regiments/carlgrd_regiment.tres",   # Carls Guard
	"res://battle_system/data/regiments/nlnhlb_regiment.tres",    # Halberdiers
	"res://battle_system/data/regiments/ironbrks_regiment.tres",  # Ironbreakers
	"res://battle_system/data/regiments/dwwar_regiment.tres",     # Dwarf Warriors
	"res://battle_system/data/regiments/hammers_regiment.tres",   # Hammerers
	"res://battle_system/data/regiments/avengers_regiment.tres",  # Avengers
	# === SECOND LINE: Ranged Infantry (6 units) ===
	"res://battle_system/data/regiments/dwxbow_regiment.tres",    # Dwarf Crossbows
	"res://battle_system/data/regiments/mercxbow_regiment.tres",  # Merc Crossbows
	"res://battle_system/data/regiments/xbow_regiment.tres",      # Crossbowmen
	"res://battle_system/data/regiments/engr_regiment.tres",      # Engineers
	"res://battle_system/data/regiments/mercxbow_regiment.tres",  # Merc Crossbows 2
	"res://battle_system/data/regiments/dwxbow_regiment.tres",    # Dwarf Crossbows 2
	# === BACK LINE: Cavalry & Artillery (4 units) ===
	"res://battle_system/data/regiments/reik_regiment.tres",      # Reiksguard Cavalry
	"res://battle_system/data/regiments/keelers_regiment.tres",   # Keelers Cavalry
	"res://battle_system/data/regiments/impcanon_regiment.tres",  # Imperial Cannon
	"res://battle_system/data/regiments/grtcanon_regiment.tres",  # Great Cannon
]

# Enemy: Monsters and foot troops - Melee front, ranged back
# ORDER MATTERS: First units spawn in FRONT row, last units spawn in BACK
const STRESS_TEST_ENEMY_REGIMENTS: Array[String] = [
	# === FRONT LINE: Elite Infantry & Monsters (10 units) ===
	"res://battle_system/data/regiments/blackorc_regiment.tres",  # Black Orcs
	"res://battle_system/data/regiments/biguns_regiment.tres",    # Big'Uns
	"res://battle_system/data/regiments/giant_regiment.tres",     # Giant
	"res://battle_system/data/regiments/troll_regiment.tres",     # Trolls
	"res://battle_system/data/regiments/ratogre_regiment.tres",   # Rat Ogres
	"res://battle_system/data/regiments/stmverm_regiment.tres",   # Stormvermin
	"res://battle_system/data/regiments/plagmonk_regiment.tres",  # Plague Monks
	"res://battle_system/data/regiments/orcboyz_regiment.tres",   # Orc Boyz
	"res://battle_system/data/regiments/orcboyz_regiment.tres",   # Orc Boyz 2
	"res://battle_system/data/regiments/clanrats_regiment.tres",  # Clanrats
	# === SECOND LINE: Light Infantry (6 units) ===
	"res://battle_system/data/regiments/ntgoblin_regiment.tres",  # Night Goblins
	"res://battle_system/data/regiments/ntgoblin_regiment.tres",  # Night Goblins 2
	"res://battle_system/data/regiments/ratslave_regiment.tres",  # Rat Slaves
	"res://battle_system/data/regiments/fanatic_regiment.tres",   # Fanatics
	"res://battle_system/data/regiments/orcboyz_regiment.tres",   # Orc Boyz 3
	"res://battle_system/data/regiments/clanrats_regiment.tres",  # Clanrats 2
	# === BACK LINE: Cavalry & Ranged (4 units) ===
	"res://battle_system/data/regiments/boarboyz_regiment.tres",  # Boar Boyz
	"res://battle_system/data/regiments/wolfride_regiment.tres",  # Wolf Riders
	"res://battle_system/data/regiments/arraboyz_regiment.tres",  # Arrer Boyz
	"res://battle_system/data/regiments/gobarch_regiment.tres",   # Goblin Archers
]


func _ready():
	# Enable combat debug for stress testing
	if CombatManager:
		CombatManager.debug_combat = true
		print("[BattleScene] Combat debug ENABLED")

	# Add freeze debugger for stress testing
	if stress_test_mode:
		var freeze_debugger_script = load("res://battle_system/debug/freeze_debugger.gd")
		if freeze_debugger_script:
			var debugger = Node.new()
			debugger.set_script(freeze_debugger_script)
			debugger.name = "FreezeDebugger"
			add_child(debugger)
			print("[BattleScene] Freeze debugger ENABLED")

	# Wait for terrain to generate
	await get_tree().create_timer(0.6).timeout

	# Safety check - scene might be freed during await
	if not is_instance_valid(self):
		return

	# STRESS TEST MODE: Spawn units on each side
	if stress_test_mode:
		print("[STRESS TEST] Spawning %d units per side..." % stress_test_units_per_side)
		_setup_stress_test()
		# Enable dynamic weather for stress test
		if enable_dynamic_weather:
			_enable_dynamic_weather()
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
		_print_army_composition()

		# Auto-start battle for AI testing
		if auto_start_battle:
			print("[STRESS TEST] Auto-starting battle in 2 seconds...")
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(self) and DeploymentManager:
				print("[STRESS TEST] Calling DeploymentManager.start_battle()")
				DeploymentManager.start_battle()


func _setup_from_campaign() -> void:
	# Get regiment data from campaign
	var player_data: Array = BattleTransition.get_player_regiments()
	var enemy_data: Array = BattleTransition.get_enemy_regiments()

	# Spawn player regiments (facing East toward enemy)
	var player_spawn_x := -20.0
	for i in range(player_data.size()):
		var regiment_data: RegimentData = player_data[i]
		var regiment := _spawn_regiment_from_data(regiment_data, true)
		regiment.position = Vector3(player_spawn_x, 0, -10 + i * 8)
		regiment.set_initial_facing(WorldCompassScript.EAST)  # Bug C fix: face enemy
		player_regiments.append(regiment)

	# Spawn enemy regiments (facing West toward player)
	var enemy_spawn_x := 20.0
	for i in range(enemy_data.size()):
		var regiment_data: RegimentData = enemy_data[i]
		var regiment := _spawn_regiment_from_data(regiment_data, false)
		regiment.position = Vector3(enemy_spawn_x, 0, -10 + i * 8)
		regiment.set_initial_facing(WorldCompassScript.WEST)  # Bug C fix: face player
		enemy_regiments.append(regiment)

	# Wire up reinforcement system (Bug 3 fix)
	_setup_reinforcements()


func _setup_reinforcements() -> void:
	# Set up reinforcement manager from campaign data
	if not ReinforcementManager:
		return

	var battle_data: Dictionary = BattleTransition.battle_data

	# Check if pre-battle screen provided explicit deployment order
	var core_data: Array = battle_data.get("core_regiments", [])
	var reinforcement_data: Array = battle_data.get("reinforcement_regiments", [])

	if core_data.size() > 0 or reinforcement_data.size() > 0:
		# Use pre-battle deployment - create a setup resource
		var setup := Resource.new()
		setup.set_meta("core_regiments", core_data)
		setup.set_meta("reinforcement_regiments", reinforcement_data)
		# ReinforcementManager expects these as properties, so set them
		if setup.has_method("set"):
			setup.set("core_regiments", core_data)
			setup.set("reinforcement_regiments", reinforcement_data)
		# Fallback: set up from regiment arrays directly
		ReinforcementManager.core_regiments = core_data.duplicate()
		ReinforcementManager.reinforcement_queue = reinforcement_data.duplicate()
		ReinforcementManager.all_regiments = core_data + reinforcement_data
		ReinforcementManager.original_core_strength = ReinforcementManager._calculate_strength(core_data)
		ReinforcementManager.current_wave = 0
		ReinforcementManager.reinforcements_spawned = 0
		ReinforcementManager.time_since_last_wave = 0.0
		print("[BattleScene] Reinforcements wired: %d core, %d in reserve" % [core_data.size(), reinforcement_data.size()])
	else:
		# No pre-battle screen - check for battalion data to use auto-split
		# This happens when using start_battle_from_campaign() directly
		var battalion_id: String = battle_data.get("battalion_id", "")
		if not battalion_id.is_empty() and CampaignManager:
			for battalion in CampaignManager.battalions:
				if battalion.battalion_id == battalion_id:
					ReinforcementManager.setup_from_battalion(battalion)
					print("[BattleScene] Reinforcements wired from battalion: %d core, %d reserve" % [
						ReinforcementManager.core_regiments.size(),
						ReinforcementManager.reinforcement_queue.size()
					])
					return

		# Final fallback: use player_regiments directly (first 8 core, rest reserve)
		var player_data: Array = battle_data.get("player_regiments", [])
		if player_data.size() > 0:
			ReinforcementManager.core_regiments.clear()
			ReinforcementManager.reinforcement_queue.clear()
			for i in range(player_data.size()):
				if i < ReinforcementManager.MAX_CORE_UNITS:
					ReinforcementManager.core_regiments.append(player_data[i])
				else:
					ReinforcementManager.reinforcement_queue.append(player_data[i])
			ReinforcementManager.all_regiments = player_data.duplicate()
			ReinforcementManager.original_core_strength = ReinforcementManager._calculate_strength(ReinforcementManager.core_regiments)
			print("[BattleScene] Reinforcements wired from player data: %d core, %d reserve" % [
				ReinforcementManager.core_regiments.size(),
				ReinforcementManager.reinforcement_queue.size()
			])


func _spawn_regiment_from_data(data: RegimentData, is_player: bool) -> Regiment:
	# Load regiment scene
	var regiment_scene := preload("res://battle_system/nodes/regiment.tscn")
	var regiment: Regiment = regiment_scene.instantiate()

	# Apply data
	regiment.data = data.duplicate()
	regiment.is_player_controlled = is_player

	# Use campaign's current_soldiers (may be wounded from previous battle)
	# Fall back to max_soldiers if not set
	var starting_soldiers: int = data.current_soldiers if data.current_soldiers > 0 else data.max_soldiers
	regiment.current_soldiers = starting_soldiers

	# Store starting count for casualty reporting (Bug 2 fix)
	regiment.set_meta("starting_soldiers", starting_soldiers)

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

	# Calculate grid layout - ROWS go across (Z direction), units side by side (X direction)
	# 10 units per row = front line of melee, then archers, then cavalry/artillery
	# Scaled 4x for 1200x1200 map (was 300x300)
	var units_per_row: int = 10
	var row_spacing: float = 40.0  # X spacing between rows (depth from front to back)
	var col_spacing: float = 20.0  # Z spacing between units in same row (side by side)

	# Spawn player units on LEFT side - scaled for 1200x1200 map
	var player_start_x: float = -320.0   # Was -80 (4x scale)
	var player_start_z: float = -90.0    # Centered vertically (10 units * 20 spacing = 180 wide)

	for i in range(stress_test_units_per_side):
		var row: int = i / units_per_row   # 0 = front line, 1 = second line, etc.
		var col: int = i % units_per_row   # Position within the row (side by side)

		# ROWS layout: X = depth (row pushes back), Z = width (col spreads sideways)
		var pos := Vector3(
			player_start_x - row * row_spacing,  # Front row at start_x, back rows behind
			10.0,
			player_start_z + col * col_spacing   # Units spread across Z axis
		)

		# Cycle through regiment types
		var regiment_data: RegimentData = player_regiment_resources[i % player_regiment_resources.size()]
		var regiment := _spawn_regiment_from_data(regiment_data.duplicate(), true)
		regiment.name = "PlayerUnit_%d" % i
		regiment.global_position = pos
		regiment.set_initial_facing(WorldCompassScript.EAST)  # Face enemy (to the right)
		player_regiments.append(regiment)

	# Spawn enemy units
	if siege_defense_mode:
		# SIEGE MODE: Spawn defenders at capture points
		var capture_points: Array = get_tree().get_nodes_in_group("capture_points")
		if capture_points.is_empty():
			push_warning("[STRESS TEST] Siege mode but no capture points found, using normal spawn")
			_spawn_enemy_units_normal(enemy_regiment_resources, units_per_row, col_spacing, row_spacing)
		else:
			_spawn_enemy_units_at_capture_points(enemy_regiment_resources, capture_points)
	else:
		# Normal mode: Spawn on RIGHT side
		_spawn_enemy_units_normal(enemy_regiment_resources, units_per_row, col_spacing, row_spacing)

	print("[STRESS TEST] Spawned %d player units and %d enemy units" % [
		player_regiments.size(), enemy_regiments.size()
	])


func _spawn_enemy_units_normal(regiment_resources: Array, units_per_row: int, col_spacing: float, row_spacing: float) -> void:
	## Spawn enemy units on the right side (normal battle layout)
	## Scaled for 1200x1200 map
	var enemy_start_x: float = 320.0   # Was 80 (4x scale)
	var enemy_start_z: float = -90.0   # Centered vertically (matches player)

	for i in range(stress_test_units_per_side):
		var row: int = i / units_per_row   # 0 = front line, 1 = second line, etc.
		var col: int = i % units_per_row   # Position within the row (side by side)

		# ROWS layout: X = depth (row pushes back), Z = width (col spreads sideways)
		var pos := Vector3(
			enemy_start_x + row * row_spacing,  # Front row at start_x, back rows behind
			10.0,
			enemy_start_z + col * col_spacing   # Units spread across Z axis
		)

		# Cycle through regiment types
		var regiment_data: RegimentData = regiment_resources[i % regiment_resources.size()]
		var regiment := _spawn_regiment_from_data(regiment_data.duplicate(), false)
		regiment.name = "EnemyUnit_%d" % i
		regiment.global_position = pos
		regiment.set_initial_facing(WorldCompassScript.WEST)  # Face player (to the left)
		enemy_regiments.append(regiment)


func _spawn_enemy_units_at_capture_points(regiment_resources: Array, capture_points: Array) -> void:
	## Spawn enemy units distributed across capture points for siege defense.
	## More units at higher-value points.

	# Sort capture points by value (highest first)
	capture_points.sort_custom(func(a, b): return a.get_point_value() > b.get_point_value())

	# Calculate total value for proportional distribution
	var total_value: int = 0
	for point in capture_points:
		total_value += point.get_point_value()

	if total_value == 0:
		total_value = capture_points.size()  # Fallback to equal distribution

	# Assign units proportionally to each capture point
	var unit_index: int = 0
	var point_assignments: Dictionary = {}  # CapturePoint -> count

	for point in capture_points:
		var proportion: float = float(point.get_point_value()) / float(total_value)
		var count: int = maxi(1, int(stress_test_units_per_side * proportion))
		point_assignments[point] = count

	# Spawn units at each capture point
	for point in capture_points:
		var count: int = point_assignments[point]
		var point_pos: Vector3 = point.global_position
		var radius: float = point.capture_radius * 0.6  # Spawn inside the capture radius

		for i in range(count):
			if unit_index >= stress_test_units_per_side:
				break

			# Position in a circle around the capture point
			var angle: float = (float(i) / float(count)) * TAU
			var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * radius * (0.5 + randf() * 0.5)
			var pos: Vector3 = point_pos + offset
			pos.y = 10.0  # Will be snapped to terrain later

			# Cycle through regiment types
			var regiment_data: RegimentData = regiment_resources[unit_index % regiment_resources.size()]
			var regiment := _spawn_regiment_from_data(regiment_data.duplicate(), false)
			regiment.name = "EnemyUnit_%d" % unit_index
			regiment.global_position = pos
			regiment.set_initial_facing(WorldCompassScript.WEST)  # Bug C fix: face player
			enemy_regiments.append(regiment)
			unit_index += 1

		print("[STRESS TEST] Assigned %d defenders to %s (value=%d)" % [
			count, point.point_name, point.get_point_value()
		])


func _enable_dynamic_weather() -> void:
	## Enable dynamic weather cycling for stress test.
	var weather_controller := get_node_or_null("/root/WeatherController")
	if weather_controller:
		weather_controller.auto_weather_enabled = true
		weather_controller.auto_weather_min_interval = 45.0  # Change every 45-90 seconds
		weather_controller.auto_weather_max_interval = 90.0
		# Auto weather will cycle through presets automatically
		print("[STRESS TEST] Dynamic weather ENABLED")
		print("[STRESS TEST] Weather will cycle every 45-90 seconds")
	else:
		push_warning("[STRESS TEST] WeatherController not found - weather disabled")


func _print_army_composition() -> void:
	## Print detailed army composition for debugging.
	print("\n========== ARMY COMPOSITION ==========")
	print("--- PLAYER ARMY (%d units) ---" % player_regiments.size())
	var player_total_soldiers: int = 0
	for reg in player_regiments:
		if is_instance_valid(reg) and reg.data:
			print("  %s: %d soldiers (BS=%d, STR=%d, range=%d)" % [
				reg.data.regiment_name, reg.current_soldiers,
				reg.data.ballistic_skill, reg.data.strength,
				reg.data.range_distance
			])
			player_total_soldiers += reg.current_soldiers

	print("\n--- ENEMY ARMY (%d units) ---" % enemy_regiments.size())
	var enemy_total_soldiers: int = 0
	for reg in enemy_regiments:
		if is_instance_valid(reg) and reg.data:
			print("  %s: %d soldiers (ATK=%d, DEF=%d, STR=%d)" % [
				reg.data.regiment_name, reg.current_soldiers,
				reg.data.attack, reg.data.defense,
				reg.data.strength
			])
			enemy_total_soldiers += reg.current_soldiers

	print("\n--- TOTALS ---")
	print("Player: %d regiments, %d total soldiers" % [player_regiments.size(), player_total_soldiers])
	print("Enemy:  %d regiments, %d total soldiers" % [enemy_regiments.size(), enemy_total_soldiers])
	print("========================================\n")
