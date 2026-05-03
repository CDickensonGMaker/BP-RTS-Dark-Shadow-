# 2D camera with pan and zoom for the campaign map.
extends Camera2D


@export var pan_speed: float = 800.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0

# Map boundaries (set based on map size)
@export var map_bounds: Rect2 = Rect2(0, 0, 1920, 1080)

var is_panning: bool = false
var pan_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Start at reasonable zoom
	zoom = Vector2(1.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(-zoom_speed)

		# Middle mouse pan
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
			if is_panning:
				pan_start = event.position

	# Pan with middle mouse drag
	if event is InputEventMouseMotion and is_panning:
		var pan_delta: Vector2 = (pan_start - event.position) / zoom
		position += pan_delta
		pan_start = event.position
		_clamp_position()


func _process(delta: float) -> void:
	# WASD/Arrow key panning
	var pan_direction := Vector2.ZERO

	if Input.is_action_pressed("ui_left"):
		pan_direction.x -= 1
	if Input.is_action_pressed("ui_right"):
		pan_direction.x += 1
	if Input.is_action_pressed("ui_up"):
		pan_direction.y -= 1
	if Input.is_action_pressed("ui_down"):
		pan_direction.y += 1

	if pan_direction != Vector2.ZERO:
		position += pan_direction.normalized() * pan_speed * delta / zoom.x
		_clamp_position()


func _zoom_camera(delta: float) -> void:
	var new_zoom := clampf(zoom.x + delta, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	_clamp_position()


func _clamp_position() -> void:
	# Keep camera within map bounds
	var view_size := get_viewport_rect().size / zoom
	var half_view := view_size / 2

	position.x = clampf(position.x, map_bounds.position.x + half_view.x, map_bounds.end.x - half_view.x)
	position.y = clampf(position.y, map_bounds.position.y + half_view.y, map_bounds.end.y - half_view.y)


func focus_on(target_position: Vector2, smooth: bool = true) -> void:
	if smooth:
		var tween := create_tween()
		tween.tween_property(self, "position", target_position, 0.3).set_ease(Tween.EASE_OUT)
	else:
		position = target_position
	_clamp_position()
