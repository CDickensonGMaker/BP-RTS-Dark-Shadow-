class_name RTSCamera
extends Node3D


@export var pan_speed: float = 25.0
@export var zoom_min: float = 3.0  # Very close to units
@export var zoom_max: float = 50.0  # Far out for overview
@export var zoom_speed: float = 4.0
@export var rotate_speed: float = 2.0
@export var tilt_speed: float = 1.5
@export var min_tilt: float = -85.0  # Look almost straight down
@export var max_tilt: float = -10.0  # Very shallow angle for action view
@export var edge_scroll_margin: int = 30   # px from screen edge (wider margin)
@export var edge_scroll_enabled: bool = true  # Toggle edge scrolling
@export var battlefield_bounds: Rect2 = Rect2(-100, -100, 200, 200)


@onready var spring_arm: SpringArm3D = $SpringArm3D
var zoom_target: float = 20.0
var is_rotating: bool = false
var last_mouse_pos: Vector2
var current_tilt: float = -45.0  # Starting pitch angle

# Camera shake variables
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _shake_frequency: float = 25.0  # Hz - impact feel
var _base_position: Vector3 = Vector3.ZERO
var _is_shaking: bool = false


func _ready():
	# Apply initial tilt to spring arm
	spring_arm.rotation_degrees.x = current_tilt
	_base_position = position
	_connect_battle_signals()


func _input(event):
	# Zoom with mouse wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_target = max(zoom_min, zoom_target - zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_target = min(zoom_max, zoom_target + zoom_speed)
		# Middle mouse rotate
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			is_rotating = event.pressed
			last_mouse_pos = event.position

	if event is InputEventMouseMotion and is_rotating:
		var delta = event.position - last_mouse_pos
		# Horizontal rotation (yaw) - rotate the whole camera rig
		rotate_y(-delta.x * rotate_speed * 0.005)
		# Vertical rotation (pitch) - tilt the spring arm up/down
		current_tilt += delta.y * tilt_speed * 0.005
		current_tilt = clamp(current_tilt, min_tilt, max_tilt)
		spring_arm.rotation_degrees.x = current_tilt
		last_mouse_pos = event.position


func _process(delta):
	spring_arm.spring_length = lerp(spring_arm.spring_length, zoom_target, delta * 8.0)
	_handle_pan(delta)
	_handle_shake(delta)


func _handle_pan(delta):
	var move = Vector3.ZERO
	var vp = get_viewport().get_visible_rect()
	var mouse = get_viewport().get_mouse_position()

	# Edge scroll - with acceleration based on how far into the margin
	if edge_scroll_enabled:
		# Left edge
		if mouse.x < edge_scroll_margin:
			var strength = 1.0 - (mouse.x / edge_scroll_margin)
			move.x -= strength
		# Right edge
		if mouse.x > vp.size.x - edge_scroll_margin:
			var strength = (mouse.x - (vp.size.x - edge_scroll_margin)) / edge_scroll_margin
			move.x += strength
		# Top edge
		if mouse.y < edge_scroll_margin:
			var strength = 1.0 - (mouse.y / edge_scroll_margin)
			move.z -= strength
		# Bottom edge
		if mouse.y > vp.size.y - edge_scroll_margin:
			var strength = (mouse.y - (vp.size.y - edge_scroll_margin)) / edge_scroll_margin
			move.z += strength

	# WASD
	if Input.is_action_pressed("ui_left"):  move.x -= 1
	if Input.is_action_pressed("ui_right"): move.x += 1
	if Input.is_action_pressed("ui_up"):    move.z -= 1
	if Input.is_action_pressed("ui_down"):  move.z += 1

	if move != Vector3.ZERO:
		# Constant pan speed regardless of zoom level
		var pan = (basis * move).normalized() * pan_speed * delta
		pan.y = 0
		position += pan
		# Clamp to battlefield
		position.x = clamp(position.x, battlefield_bounds.position.x, battlefield_bounds.end.x)
		position.z = clamp(position.z, battlefield_bounds.position.y, battlefield_bounds.end.y)

	# Update base position for shake calculations (after panning)
	if not _is_shaking:
		_base_position = position


## Camera Shake System

func shake(intensity: float, duration: float) -> void:
	"""
	Trigger a camera shake effect.
	intensity: Shake strength (0.1 = subtle, 0.5 = heavy impact)
	duration: How long the shake lasts in seconds
	"""
	# Allow stronger shakes to override weaker ones
	if intensity > _shake_intensity or not _is_shaking:
		_shake_intensity = intensity
		_shake_duration = duration
		_shake_timer = 0.0
		_is_shaking = true
		_base_position = position


func _handle_shake(delta: float) -> void:
	if not _is_shaking:
		return

	_shake_timer += delta

	if _shake_timer >= _shake_duration:
		# Shake finished - reset to base position
		_is_shaking = false
		_shake_intensity = 0.0
		position = _base_position
		return

	# Calculate decay (1.0 at start, 0.0 at end)
	var decay: float = 1.0 - (_shake_timer / _shake_duration)

	# Calculate shake offset using sine wave with decay
	var time_scaled: float = _shake_timer * _shake_frequency * TAU
	var offset_x: float = sin(time_scaled) * _shake_intensity * decay
	var offset_z: float = sin(time_scaled * 1.3) * _shake_intensity * decay * 0.7  # Slightly offset frequency for Z

	# Apply offset to camera position
	position = _base_position + Vector3(offset_x, 0, offset_z)


func _connect_battle_signals() -> void:
	# Connect to BattleSignals autoload for automatic shake triggers
	if not BattleSignals:
		push_warning("RTSCamera: BattleSignals autoload not found, shake triggers disabled")
		return

	# Cavalry charge impact - medium shake
	BattleSignals.charge_impact.connect(_on_charge_impact)

	# Projectile fired (artillery) - heavy shake
	BattleSignals.projectile_fired.connect(_on_projectile_fired)

	# Regiment destroyed - medium-heavy shake
	BattleSignals.regiment_dead.connect(_on_regiment_dead)


func _on_charge_impact(_charger: Regiment, _target: Regiment, _was_braced: bool) -> void:
	# Cavalry charge impact: intensity 0.3, duration 0.4s
	shake(0.3, 0.4)


func _on_projectile_fired(_from: Regiment, _target: Regiment) -> void:
	# Artillery explosion: intensity 0.5, duration 0.6s
	shake(0.5, 0.6)


func _on_regiment_dead(_regiment: Regiment) -> void:
	# Building/regiment destroyed: intensity 0.4, duration 0.5s
	shake(0.4, 0.5)
