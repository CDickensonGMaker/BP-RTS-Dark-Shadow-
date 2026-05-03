extends Node3D


@onready var player_regiment: Regiment = $PlayerRegiment
@onready var enemy_regiment: Regiment = $EnemyRegiment


func _ready():
	# Initialize regiments
	player_regiment.is_player_controlled = true
	enemy_regiment.is_player_controlled = false

	# Start the battle
	BattleManager.start_battle()

	# Set initial camera position (higher for siege overview)
	var camera = $RTSCamera
	camera.position = Vector3(0, 0, 30)
