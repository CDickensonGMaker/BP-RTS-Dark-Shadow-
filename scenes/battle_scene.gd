extends Node3D


@onready var battle_terrain: Node3D = $BattleTerrain

var player_regiments: Array[Regiment] = []
var enemy_regiments: Array[Regiment] = []


func _ready():
	# Wait for terrain to generate
	await get_tree().create_timer(0.6).timeout

	# Check if coming from campaign with pre-defined regiments
	if BattleTransition and BattleTransition.has_battle_data():
		_setup_from_campaign()
	else:
		# Find all regiments (standalone mode)
		_gather_regiments()

	# Position regiments on terrain
	for regiment in player_regiments + enemy_regiments:
		_position_regiment_on_terrain(regiment)

	# Set initial camera position
	var camera = get_node_or_null("RTSCamera")
	if camera:
		camera.position = Vector3(0, 0, 30)

	# Start the battle
	BattleManager.start_battle()


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
