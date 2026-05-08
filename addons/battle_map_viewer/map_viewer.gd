extends Node3D

## Standalone map viewer with RTS camera controls

@onready var camera_arm: SpringArm3D = $CameraArm
@onready var camera: Camera3D = $CameraArm/Camera3D
@onready var map_container: Node3D = $MapContainer
@onready var ui: CanvasLayer = $UI
@onready var map_label: Label = $UI/MapLabel
@onready var controls_label: Label = $UI/ControlsLabel
@onready var time_label: Label = $UI/TimeLabel

# Camera settings
@export var pan_speed: float = 50.0
@export var zoom_speed: float = 5.0
@export var rotate_speed: float = 2.0
@export var min_zoom: float = 10.0
@export var max_zoom: float = 200.0
@export var edge_scroll_margin: int = 20
@export var edge_scroll_enabled: bool = true

var current_zoom: float = 80.0
var current_rotation: float = 0.0
var current_tilt: float = -60.0
var loaded_map: Node = null
var map_path: String = ""

func _ready() -> void:
	# Get map path from project settings
	if ProjectSettings.has_setting("battle_map_viewer/current_map"):
		map_path = ProjectSettings.get_setting("battle_map_viewer/current_map")
		_load_map(map_path)

	# Setup camera
	_update_camera()

	# Setup UI
	controls_label.text = "WASD: Pan | Scroll: Zoom | Q/E: Rotate | R/F: Tilt | ESC: Exit"

	# Try to find Sky3D for time display
	_setup_time_display()

func _load_map(path: String) -> void:
	# Clear existing map
	if loaded_map:
		loaded_map.queue_free()
		loaded_map = null

	# Load new map
	var scene = load(path)
	if scene:
		loaded_map = scene.instantiate()
		map_container.add_child(loaded_map)

		# Update label
		var map_name = path.get_file().get_basename().capitalize()
		map_label.text = "Map: " + map_name

		# Disable any game logic nodes
		_disable_game_logic(loaded_map)

		# Find good starting position
		_center_camera_on_map()

func _disable_game_logic(node: Node) -> void:
	# Disable scripts that might cause issues in viewer mode
	var nodes_to_disable = ["BattleManager", "AIAutoload", "CombatManager", "DeploymentManager"]

	for child in node.get_children():
		if child.name in nodes_to_disable:
			child.set_process(false)
			child.set_physics_process(false)
		_disable_game_logic(child)

func _center_camera_on_map() -> void:
	if not loaded_map:
		return

	# Try to find terrain bounds
	var terrain = loaded_map.get_node_or_null("BattleTerrain")
	if terrain:
		# Center on terrain
		camera_arm.position = terrain.global_position
	else:
		# Just use origin
		camera_arm.position = Vector3.ZERO

func _setup_time_display() -> void:
	# Find Sky3D if present
	var sky = get_tree().get_first_node_in_group("sky3d")
	if sky and sky.has_method("get_current_time"):
		time_label.visible = true
	else:
		time_label.visible = false

func _process(delta: float) -> void:
	_handle_input(delta)
	_handle_edge_scroll(delta)
	_update_time_display()

func _handle_input(delta: float) -> void:
	var move_dir := Vector3.ZERO

	# WASD pan
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		move_dir.z -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		move_dir.z += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		move_dir.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		move_dir.x += 1

	# Apply rotation to movement
	move_dir = move_dir.rotated(Vector3.UP, deg_to_rad(current_rotation))
	camera_arm.position += move_dir * pan_speed * delta

	# Q/E rotate
	if Input.is_key_pressed(KEY_Q):
		current_rotation += rotate_speed * delta * 60
	if Input.is_key_pressed(KEY_E):
		current_rotation -= rotate_speed * delta * 60

	# R/F tilt
	if Input.is_key_pressed(KEY_R):
		current_tilt = clamp(current_tilt + rotate_speed * delta * 30, -80, -30)
	if Input.is_key_pressed(KEY_F):
		current_tilt = clamp(current_tilt - rotate_speed * delta * 30, -80, -30)

	# ESC to exit
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()

	_update_camera()

func _handle_edge_scroll(delta: float) -> void:
	if not edge_scroll_enabled:
		return

	var viewport = get_viewport()
	var mouse_pos = viewport.get_mouse_position()
	var viewport_size = viewport.get_visible_rect().size

	var edge_dir := Vector3.ZERO

	if mouse_pos.x < edge_scroll_margin:
		edge_dir.x -= 1
	elif mouse_pos.x > viewport_size.x - edge_scroll_margin:
		edge_dir.x += 1

	if mouse_pos.y < edge_scroll_margin:
		edge_dir.z -= 1
	elif mouse_pos.y > viewport_size.y - edge_scroll_margin:
		edge_dir.z += 1

	edge_dir = edge_dir.rotated(Vector3.UP, deg_to_rad(current_rotation))
	camera_arm.position += edge_dir * pan_speed * delta * 0.5

func _input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom = clamp(current_zoom - zoom_speed, min_zoom, max_zoom)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom = clamp(current_zoom + zoom_speed, min_zoom, max_zoom)
			_update_camera()

func _update_camera() -> void:
	camera_arm.spring_length = current_zoom
	camera_arm.rotation_degrees = Vector3(current_tilt, current_rotation, 0)

func _update_time_display() -> void:
	var sky = get_tree().get_first_node_in_group("sky3d")
	if sky and sky.has_method("get_current_time"):
		var time = sky.get_current_time()
		var hours = int(time)
		var minutes = int((time - hours) * 60)
		time_label.text = "Time: %02d:%02d" % [hours, minutes]
