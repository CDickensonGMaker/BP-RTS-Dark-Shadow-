class_name BattleCompass
extends Control

## Visual compass overlay showing 8 cardinal directions.
## Rotates with the camera to always show correct world directions.
## Direction system: N=0, NE=1, E=2, SE=3, S=4, SW=5, W=6, NW=7 (clockwise from North)

const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")

# Size and styling
const COMPASS_SIZE := Vector2(80, 80)
const CENTER_RADIUS := 8.0
const OUTER_RADIUS := 35.0
const CARDINAL_RADIUS := 32.0
const ORDINAL_RADIUS := 28.0

# Colors
const COLOR_BG = Color(0.08, 0.06, 0.05, 0.85)
const COLOR_BORDER = Color(0.6, 0.5, 0.3, 1.0)
const COLOR_NORTH = Color(0.9, 0.2, 0.2, 1.0)  # Red for North
const COLOR_CARDINAL = Color(0.95, 0.92, 0.85, 1.0)  # White for E/S/W
const COLOR_ORDINAL = Color(0.7, 0.65, 0.55, 1.0)  # Dim for diagonals
const COLOR_CENTER = Color(0.4, 0.35, 0.25, 1.0)
const COLOR_LINES = Color(0.5, 0.45, 0.35, 0.5)

# Direction labels matching our system
const DIRECTION_LABELS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# Base angles for each direction (radians from top, clockwise) - before camera rotation
# Index 0 = North = top = -PI/2 radians in screen space
const BASE_DIRECTION_ANGLES := [
	-PI / 2,           # 0: N (top)
	-PI / 4,           # 1: NE
	0.0,               # 2: E (right)
	PI / 4,            # 3: SE
	PI / 2,            # 4: S (bottom)
	3 * PI / 4,        # 5: SW
	PI,                # 6: W (left)
	-3 * PI / 4,       # 7: NW
]

# Camera tracking
var _camera: Camera3D = null
var _camera_rotation: float = 0.0  # Y-axis rotation in radians


func _ready():
	custom_minimum_size = COMPASS_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "Compass: N=0, clockwise to NW=7\nRotates with camera"
	call_deferred("_find_camera")


func _find_camera():
	# Find camera in battle_camera group or viewport camera
	var cameras := get_tree().get_nodes_in_group("battle_camera")
	if cameras.size() > 0:
		_camera = cameras[0] as Camera3D
	else:
		_camera = get_viewport().get_camera_3d()


func _process(_delta: float):
	if _camera and is_instance_valid(_camera):
		# Get camera's Y rotation (around vertical axis)
		var new_rotation := _camera.global_rotation.y
		if absf(new_rotation - _camera_rotation) > 0.001:
			_camera_rotation = new_rotation
			queue_redraw()


func _get_rotated_angle(base_angle: float) -> float:
	# Rotate compass direction by camera rotation
	# Camera rotation is around Y axis, positive = clockwise when looking down
	# We need to rotate the compass the opposite way so North stays pointing to world North
	return base_angle + _camera_rotation


func _draw():
	var center := size / 2.0

	# Background circle
	draw_circle(center, OUTER_RADIUS + 4, COLOR_BG)

	# Border ring
	_draw_circle_outline(center, OUTER_RADIUS + 4, COLOR_BORDER, 2.0)

	# Direction lines from center
	for i in 8:
		var angle: float = _get_rotated_angle(BASE_DIRECTION_ANGLES[i])
		var line_end := center + Vector2(cos(angle), sin(angle)) * OUTER_RADIUS
		var is_cardinal := (i % 2 == 0)  # N, E, S, W
		var line_color := COLOR_LINES if not is_cardinal else Color(COLOR_LINES.r, COLOR_LINES.g, COLOR_LINES.b, 0.7)
		draw_line(center, line_end, line_color, 1.0 if not is_cardinal else 1.5)

	# Center dot
	draw_circle(center, CENTER_RADIUS, COLOR_CENTER)
	_draw_circle_outline(center, CENTER_RADIUS, COLOR_BORDER, 1.0)

	# Direction labels
	var font := ThemeDB.fallback_font
	for i in 8:
		var angle: float = _get_rotated_angle(BASE_DIRECTION_ANGLES[i])
		var is_cardinal := (i % 2 == 0)  # N, E, S, W
		var radius: float = CARDINAL_RADIUS if is_cardinal else ORDINAL_RADIUS
		var label_pos := center + Vector2(cos(angle), sin(angle)) * radius

		var label: String = DIRECTION_LABELS[i]
		var font_size: int = 12 if is_cardinal else 9
		var color: Color

		if i == 0:  # North is special (red)
			color = COLOR_NORTH
			font_size = 14
		elif is_cardinal:
			color = COLOR_CARDINAL
		else:
			color = COLOR_ORDINAL

		# Draw label centered at position
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := label_pos - text_size / 2.0 + Vector2(0, text_size.y * 0.35)
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, color)

	# Draw direction indices in small text (debug info)
	_draw_direction_indices(center, font)


func _draw_direction_indices(center: Vector2, font: Font):
	# Draw tiny direction index numbers outside the compass for verification
	for i in 8:
		var angle: float = _get_rotated_angle(BASE_DIRECTION_ANGLES[i])
		var label_pos := center + Vector2(cos(angle), sin(angle)) * (OUTER_RADIUS + 12)
		var text := str(i)
		var font_size := 8
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := label_pos - text_size / 2.0 + Vector2(0, text_size.y * 0.35)
		draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, COLOR_ORDINAL)


func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float):
	var points := PackedVector2Array()
	var segments := 32
	for i in segments + 1:
		var angle := float(i) / segments * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	for i in segments:
		draw_line(points[i], points[i + 1], color, width)
