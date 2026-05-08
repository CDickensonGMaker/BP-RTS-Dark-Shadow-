# 3D campaign camera with pan, zoom, and angled view.
# Provides a Total War-style isometric perspective on the campaign map.
extends Camera3D


## Camera angle in degrees from vertical (0 = top-down, 90 = side view)
@export var camera_angle: float = 55.0

## Camera height range
@export var min_height: float = 45.0
@export var max_height: float = 800.0
@export var default_height: float = 200.0

## Pan speed (units per second)
@export var pan_speed: float = 400.0

## Zoom speed (height change per scroll)
@export var zoom_speed: float = 50.0

## Map boundaries in world units (X = width, Z = depth)
## Default matches campaign_map.png scaled: 3053 x 2160 pixels
@export var map_bounds: Rect2 = Rect2(0, 0, 305.3, 216.0)

## Smoothing for camera movement
@export var movement_smoothing: float = 8.0

# Internal state
var target_position: Vector3 = Vector3.ZERO
var target_height: float = 400.0
var is_panning: bool = false
var pan_start: Vector2 = Vector2.ZERO
var last_mouse_world_pos: Vector3 = Vector3.ZERO

# Map scale factor (pixels to world units)
const PIXELS_TO_UNITS: float = 0.1  # 1 pixel = 0.1 units


func _ready() -> void:
	target_height = default_height

	# Position at center of map (must set BEFORE updating transform)
	target_position = Vector3(
		map_bounds.position.x + map_bounds.size.x / 2,
		0,
		map_bounds.position.y + map_bounds.size.y / 2
	)

	# Set initial camera position directly (no lerp on first frame)
	var angle_rad := deg_to_rad(camera_angle)
	var horizontal_offset := target_height * tan(angle_rad)
	global_position = Vector3(
		target_position.x,
		target_height,
		target_position.z + horizontal_offset
	)
	look_at(target_position, Vector3.UP)


func _process(delta: float) -> void:
	# WASD/Arrow key panning
	var pan_direction := Vector2.ZERO

	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		pan_direction.x -= 1
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		pan_direction.x += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		pan_direction.y -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		pan_direction.y += 1

	if pan_direction != Vector2.ZERO:
		pan_direction = pan_direction.normalized()
		# Scale pan speed with height (faster when zoomed out)
		var height_factor := target_height / default_height
		target_position.x += pan_direction.x * pan_speed * height_factor * delta
		target_position.z += pan_direction.y * pan_speed * height_factor * delta

	# Clamp to map bounds
	_clamp_target_position()

	# Smooth camera movement
	_update_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_height = maxf(target_height - zoom_speed, min_height)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_height = minf(target_height + zoom_speed, max_height)

		# Middle mouse pan start
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			if is_panning:
				pan_start = event.position
				last_mouse_world_pos = screen_to_world(event.position)

	# Middle mouse drag pan
	if event is InputEventMouseMotion and is_panning:
		var current_world := screen_to_world(event.position)
		var world_delta := last_mouse_world_pos - current_world
		target_position.x += world_delta.x
		target_position.z += world_delta.z
		last_mouse_world_pos = screen_to_world(event.position)
		_clamp_target_position()


func _update_camera_transform() -> void:
	# Calculate camera position based on angle and height
	var angle_rad := deg_to_rad(camera_angle)
	var horizontal_offset := target_height * tan(angle_rad)

	# Position camera behind and above the target point
	var cam_pos := Vector3(
		target_position.x,
		target_height,
		target_position.z + horizontal_offset
	)

	# Smoothly interpolate to target
	global_position = global_position.lerp(cam_pos, get_process_delta_time() * movement_smoothing)

	# Look at the target point on the map
	look_at(target_position, Vector3.UP)


func _clamp_target_position() -> void:
	# Keep target within map bounds
	var margin := 20.0  # Small margin at edges
	target_position.x = clampf(target_position.x, map_bounds.position.x + margin, map_bounds.position.x + map_bounds.size.x - margin)
	target_position.z = clampf(target_position.z, map_bounds.position.y + margin, map_bounds.position.y + map_bounds.size.y - margin)


func screen_to_world(screen_pos: Vector2) -> Vector3:
	## Convert screen position to world position on the map plane (Y=0)
	var from := project_ray_origin(screen_pos)
	var dir := project_ray_normal(screen_pos)

	# Intersect with Y=0 plane
	if abs(dir.y) < 0.001:
		return Vector3.ZERO

	var t := -from.y / dir.y
	if t < 0:
		return Vector3.ZERO

	return from + dir * t


func world_to_pixel(world_pos: Vector3) -> Vector2:
	## Convert world position to original pixel coordinates
	return Vector2(world_pos.x / PIXELS_TO_UNITS, world_pos.z / PIXELS_TO_UNITS)


func pixel_to_world(pixel_pos: Vector2) -> Vector3:
	## Convert pixel coordinates to world position
	return Vector3(pixel_pos.x * PIXELS_TO_UNITS, 0, pixel_pos.y * PIXELS_TO_UNITS)


func focus_on(target_pixel_position: Vector2, smooth: bool = true) -> void:
	## Focus camera on a position (in original pixel coordinates)
	var world_pos := pixel_to_world(target_pixel_position)

	if smooth:
		var tween := create_tween()
		tween.tween_property(self, "target_position", world_pos, 0.4).set_ease(Tween.EASE_OUT)
	else:
		target_position = world_pos


func get_look_at_position() -> Vector3:
	## Get the current point the camera is looking at
	return target_position


func get_zoom_level() -> float:
	## Returns normalized zoom (0 = closest, 1 = farthest)
	return (target_height - min_height) / (max_height - min_height)
