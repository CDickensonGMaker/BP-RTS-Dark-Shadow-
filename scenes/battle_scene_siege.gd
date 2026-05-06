extends Node3D


@onready var player_regiment: Regiment = $PlayerRegiment
@onready var enemy_regiment: Regiment = $EnemyRegiment


func _ready():
	# Initialize regiments
	player_regiment.is_player_controlled = true
	enemy_regiment.is_player_controlled = false

	# Don't auto-start battle - let deployment phase run first
	# Player clicks "CLICK TO START" button in BattleHUD to begin combat

	# Set initial camera position (higher for siege overview)
	var camera = $RTSCamera
	camera.position = Vector3(0, 0, 30)
