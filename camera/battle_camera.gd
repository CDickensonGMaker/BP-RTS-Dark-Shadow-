# Simple battle camera - WASD pan, mouse wheel zoom, middle-drag rotate/tilt
extends Camera3D

@export var pan_speed: float = 30.0
@export var zoom_speed: float = 2.0
@export var rotate_speed: float = 0.005
@export var tilt_speed: float = 0.003
@export var min_zoom: float = 10.0
@export var max_zoom: float = 80.0
@export var min_tilt: float = -85.0  # Almost straight down
@export var max_tilt: float = -15.0  # Shallow angle
@export var center_lerp_speed: float = 5.0  # Speed for centering on units

## Camera boundary limits - prevents camera from going too far outside playable area
## Values include some margin beyond map edge for better viewing angles
@export var map_bounds_min: Vector3 = Vector3(-100, 0, -100)
@export var map_bounds_max: Vector3 = Vector3(100, 100, 100)

var target_position: Vector3
var current_zoom: float = 30.0  # Starting zoom height
var current_tilt: float = -45.0  # Shallower angle to see behind units
var is_rotating: bool = false
var last_mouse_pos: Vector2
var _centering_on_target: bool = false
var camera_locked: bool = false  # When true, disables edge scrolling and WASD


func _ready():
	add_to_group("battle_camera")
	target_position = global_position
	current_zoom = clampf(global_position.y, min_zoom, max_zoom)
	rotation_degrees.x = current_tilt


func _input(event):
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom = max(min_zoom, current_zoom - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom = min(max_zoom, current_zoom + zoom_speed)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_rotating = event.pressed
			last_mouse_pos = event.position

	# Middle mouse drag to rotate (X) and tilt (Y)
	if event is InputEventMouseMotion and is_rotating:
		var delta = event.position - last_mouse_pos
		# Horizontal drag = rotate around Y axis
		rotate_y(-delta.x * rotate_speed)
		# Vertical drag = tilt camera angle (inverted: drag up = camera up)
		current_tilt -= delta.y * tilt_speed * 50.0
		current_tilt = clamp(current_tilt, min_tilt, max_tilt)
		rotation_degrees.x = current_tilt
		last_mouse_pos = event.position


func _process(delta):
	var input_dir = Vector3.ZERO

	# Only process movement input if camera is not locked
	if not camera_locked:
		# WASD movement
		if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
			input_dir.x -= 1
		if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
			input_dir.x += 1
		if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
			input_dir.z -= 1
		if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
			input_dir.z += 1

		# Edge scrolling
		var viewport = get_viewport()
		var mouse_pos = viewport.get_mouse_position()
		var screen_size = viewport.get_visible_rect().size
		var edge_margin = 20

		if mouse_pos.x < edge_margin:
			input_dir.x -= 1
		elif mouse_pos.x > screen_size.x - edge_margin:
			input_dir.x += 1
		if mouse_pos.y < edge_margin:
			input_dir.z -= 1
		elif mouse_pos.y > screen_size.y - edge_margin:
			input_dir.z += 1

		# Apply movement relative to camera rotation
		if input_dir != Vector3.ZERO:
			var move_dir = (global_transform.basis * input_dir).normalized()
			move_dir.y = 0
			target_position += move_dir * pan_speed * delta

	# Apply zoom (always works even when locked)
	target_position.y = current_zoom

	# Clamp camera position to map bounds
	target_position.x = clampf(target_position.x, map_bounds_min.x, map_bounds_max.x)
	target_position.z = clampf(target_position.z, map_bounds_min.z, map_bounds_max.z)

	# Smooth movement
	global_position = global_position.lerp(target_position, delta * 8.0)


func center_on(world_position: Vector3):
	"""Center the camera on a world position (e.g., a regiment)."""
	# Keep XZ from target, Y stays as zoom height
	target_position.x = world_position.x
	target_position.z = world_position.z + current_zoom * 0.7  # Offset back so unit is visible
	_centering_on_target = true


func center_on_regiment(regiment: Node3D):
	"""Center the camera on a regiment's position."""
	if regiment and is_instance_valid(regiment):
		center_on(regiment.global_position)
