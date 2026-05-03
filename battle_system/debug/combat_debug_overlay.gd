## CombatDebugOverlay - Visual debug overlay for battle system.
## Toggle with F3 key to show combat information for all regiments.
##
## Displays:
## - Morale bars (colored by value)
## - Soldier count (current/max)
## - Facing direction arrow
## - "FLANKED!" indicator when being flanked
## - AI state text for AI-controlled units
## - Lines from regiments to their current targets
class_name CombatDebugOverlay
extends CanvasLayer


## Reference to the draw control node
var draw_control: Control

## Camera reference for 3D to 2D projection
var camera: Camera3D

## Toggle state
var is_enabled: bool = false

## Track flanked regiments (cleared when no longer being flanked)
var flanked_regiments: Dictionary = {}  # Regiment -> { flanker: Regiment, is_rear: bool, timer: float }

## Flank indicator duration
const FLANK_INDICATOR_DURATION: float = 2.0

## Colors
const COLOR_MORALE_HIGH: Color = Color(0.2, 0.9, 0.2, 1.0)      # Green - above 60%
const COLOR_MORALE_MED: Color = Color(0.9, 0.9, 0.2, 1.0)       # Yellow - 30-60%
const COLOR_MORALE_LOW: Color = Color(0.9, 0.2, 0.2, 1.0)       # Red - below 30%
const COLOR_MORALE_BG: Color = Color(0.1, 0.1, 0.1, 0.8)        # Background
const COLOR_SOLDIER_TEXT: Color = Color(1.0, 1.0, 1.0, 1.0)     # White
const COLOR_FLANKED: Color = Color(1.0, 0.3, 0.0, 1.0)          # Orange-red
const COLOR_AI_STATE: Color = Color(0.6, 0.8, 1.0, 1.0)         # Light blue
const COLOR_FACING_ARROW: Color = Color(0.8, 0.8, 0.2, 0.9)     # Yellow
const COLOR_TARGET_LINE: Color = Color(1.0, 0.4, 0.4, 0.6)      # Red (semi-transparent)
const COLOR_TARGET_LINE_PLAYER: Color = Color(0.4, 0.8, 1.0, 0.6)  # Blue for player units

## UI sizing
const MORALE_BAR_WIDTH: float = 60.0
const MORALE_BAR_HEIGHT: float = 8.0
const MORALE_BAR_OFFSET_Y: float = -40.0
const SOLDIER_COUNT_OFFSET_Y: float = -28.0
const ARROW_LENGTH: float = 25.0
const ARROW_HEAD_SIZE: float = 8.0
const FLANKED_OFFSET_Y: float = -55.0
const AI_STATE_OFFSET_Y: float = -70.0


func _ready() -> void:
	layer = 100  # Render on top of everything

	# Create the Control node for drawing
	draw_control = Control.new()
	draw_control.name = "DrawControl"
	draw_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(draw_control)

	# Connect draw function
	draw_control.draw.connect(_on_draw)

	# Connect to BattleSignals for flank detection
	if BattleSignals:
		BattleSignals.unit_flanked.connect(_on_unit_flanked)

	# Start disabled
	draw_control.visible = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			toggle_overlay()


func toggle_overlay() -> void:
	is_enabled = not is_enabled
	draw_control.visible = is_enabled

	if is_enabled:
		print("CombatDebugOverlay: ENABLED (F3 to toggle)")
	else:
		print("CombatDebugOverlay: DISABLED")


func _process(delta: float) -> void:
	if not is_enabled:
		return

	# Find camera if not cached
	if not camera or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()

	# Update flank timers
	_update_flank_timers(delta)

	# Request redraw
	draw_control.queue_redraw()


func _update_flank_timers(delta: float) -> void:
	## Update flank indicator timers and remove expired ones.
	var to_remove: Array = []

	for regiment in flanked_regiments:
		if not is_instance_valid(regiment):
			to_remove.append(regiment)
			continue

		flanked_regiments[regiment]["timer"] -= delta
		if flanked_regiments[regiment]["timer"] <= 0:
			to_remove.append(regiment)

	for regiment in to_remove:
		flanked_regiments.erase(regiment)


func _on_unit_flanked(flanked: Regiment, flanker: Regiment, is_rear: bool) -> void:
	## Called when a unit is flanked - track for display.
	flanked_regiments[flanked] = {
		"flanker": flanker,
		"is_rear": is_rear,
		"timer": FLANK_INDICATOR_DURATION
	}


func _on_draw() -> void:
	## Main draw callback - renders all debug info.
	if not is_enabled or not camera:
		return

	# Get all regiments
	var all_regiments: Array = get_tree().get_nodes_in_group("all_regiments")

	for regiment in all_regiments:
		if not regiment is Regiment:
			continue
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD:
			continue

		_draw_regiment_debug(regiment)


func _draw_regiment_debug(regiment: Regiment) -> void:
	## Draw all debug info for a single regiment.

	# Get screen position
	var screen_pos: Vector2 = _world_to_screen(regiment.global_position)
	if screen_pos == Vector2.ZERO:
		return  # Behind camera or off-screen

	# Draw morale bar
	_draw_morale_bar(regiment, screen_pos)

	# Draw soldier count
	_draw_soldier_count(regiment, screen_pos)

	# Draw facing arrow
	_draw_facing_arrow(regiment, screen_pos)

	# Draw flanked indicator
	if regiment in flanked_regiments:
		_draw_flanked_indicator(regiment, screen_pos)

	# Draw AI state (only for AI-controlled units)
	if not regiment.is_player_controlled and regiment.ai_controller:
		_draw_ai_state(regiment, screen_pos)

	# Draw target line
	_draw_target_line(regiment)


func _draw_morale_bar(regiment: Regiment, screen_pos: Vector2) -> void:
	## Draw morale bar above the regiment.
	var bar_pos: Vector2 = screen_pos + Vector2(-MORALE_BAR_WIDTH / 2, MORALE_BAR_OFFSET_Y)

	# Background
	var bg_rect: Rect2 = Rect2(bar_pos, Vector2(MORALE_BAR_WIDTH, MORALE_BAR_HEIGHT))
	draw_control.draw_rect(bg_rect, COLOR_MORALE_BG)

	# Morale fill
	var morale_ratio: float = clampf(regiment.current_morale / 100.0, 0.0, 1.0)
	var fill_width: float = MORALE_BAR_WIDTH * morale_ratio

	# Color based on morale level
	var morale_color: Color
	if regiment.current_morale >= 60.0:
		morale_color = COLOR_MORALE_HIGH
	elif regiment.current_morale >= 30.0:
		morale_color = COLOR_MORALE_MED
	else:
		morale_color = COLOR_MORALE_LOW

	var fill_rect: Rect2 = Rect2(bar_pos + Vector2(1, 1), Vector2(fill_width - 2, MORALE_BAR_HEIGHT - 2))
	draw_control.draw_rect(fill_rect, morale_color)

	# Border
	draw_control.draw_rect(bg_rect, Color.WHITE, false, 1.0)


func _draw_soldier_count(regiment: Regiment, screen_pos: Vector2) -> void:
	## Draw soldier count text.
	var text: String = "%d/%d" % [regiment.current_soldiers, regiment.data.max_soldiers]
	var text_pos: Vector2 = screen_pos + Vector2(0, SOLDIER_COUNT_OFFSET_Y)

	# Get default font
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 12

	# Center the text
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	text_pos.x -= text_size.x / 2

	# Draw shadow
	draw_control.draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	# Draw text
	draw_control.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_SOLDIER_TEXT)


func _draw_facing_arrow(regiment: Regiment, screen_pos: Vector2) -> void:
	## Draw an arrow showing the regiment's facing direction.
	var facing_3d: Vector3 = regiment.get_facing_direction()

	# Convert 3D facing to 2D direction (ignore Y, invert Z for screen coordinates)
	var facing_2d: Vector2 = Vector2(facing_3d.x, -facing_3d.z).normalized()

	# Arrow start point (slightly below the unit position)
	var arrow_start: Vector2 = screen_pos + Vector2(0, 5)
	var arrow_end: Vector2 = arrow_start + facing_2d * ARROW_LENGTH

	# Draw arrow line
	draw_control.draw_line(arrow_start, arrow_end, COLOR_FACING_ARROW, 2.0)

	# Draw arrow head
	var perpendicular: Vector2 = Vector2(-facing_2d.y, facing_2d.x)
	var head_base: Vector2 = arrow_end - facing_2d * ARROW_HEAD_SIZE
	var head_left: Vector2 = head_base + perpendicular * (ARROW_HEAD_SIZE / 2)
	var head_right: Vector2 = head_base - perpendicular * (ARROW_HEAD_SIZE / 2)

	draw_control.draw_polygon(
		PackedVector2Array([arrow_end, head_left, head_right]),
		PackedColorArray([COLOR_FACING_ARROW, COLOR_FACING_ARROW, COLOR_FACING_ARROW])
	)


func _draw_flanked_indicator(regiment: Regiment, screen_pos: Vector2) -> void:
	## Draw "FLANKED!" or "REAR!" indicator.
	var flank_data: Dictionary = flanked_regiments[regiment]
	var is_rear: bool = flank_data["is_rear"]
	var timer: float = flank_data["timer"]

	# Pulse effect based on timer
	var alpha: float = 0.5 + 0.5 * sin(timer * 10.0)
	var color: Color = COLOR_FLANKED
	color.a = alpha

	var text: String = "REAR!" if is_rear else "FLANKED!"
	var text_pos: Vector2 = screen_pos + Vector2(0, FLANKED_OFFSET_Y)

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14

	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	text_pos.x -= text_size.x / 2

	# Draw with shadow
	draw_control.draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, alpha))
	draw_control.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_ai_state(regiment: Regiment, screen_pos: Vector2) -> void:
	## Draw AI state for AI-controlled units.
	var ai: CommanderAI = regiment.ai_controller
	if not ai:
		return

	# Build state text
	var state_text: String = ""

	# Current stance
	var stance_names: Array[String] = ["PASSIVE", "DEFENSIVE", "AGGRESSIVE", "FLANKING", "SKIRMISH"]
	if ai.current_stance >= 0 and ai.current_stance < stance_names.size():
		state_text = stance_names[ai.current_stance]

	# Current target
	if ai.current_target and is_instance_valid(ai.current_target):
		state_text += " -> " + ai.current_target.name

	# Check for routing
	if ai.blackboard.get("is_routing", false):
		state_text = "ROUTING!"

	# Regiment state
	match regiment.state:
		Regiment.State.IDLE:
			if state_text.is_empty():
				state_text = "IDLE"
		Regiment.State.MARCHING:
			state_text = "MARCH: " + state_text
		Regiment.State.ENGAGING:
			state_text = "ENGAGE: " + state_text
		Regiment.State.ROUTING:
			state_text = "ROUTING!"
		Regiment.State.RALLYING:
			state_text = "RALLYING..."

	var text_pos: Vector2 = screen_pos + Vector2(0, AI_STATE_OFFSET_Y)

	var font: Font = ThemeDB.fallback_font
	var font_size: int = 11

	var text_size: Vector2 = font.get_string_size(state_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	text_pos.x -= text_size.x / 2

	# Draw with shadow
	draw_control.draw_string(font, text_pos + Vector2(1, 1), state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	draw_control.draw_string(font, text_pos, state_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_AI_STATE)


func _draw_target_line(regiment: Regiment) -> void:
	## Draw a line from this regiment to its current target.
	var target: Regiment = null

	# Get target from AI controller if available
	if regiment.ai_controller and regiment.ai_controller.current_target:
		target = regiment.ai_controller.current_target

	# Also check if in active melee (CombatManager)
	if not target and CombatManager:
		for melee in CombatManager.active_melees:
			if melee.get("attacker") == regiment:
				target = melee.get("defender")
				break
			elif melee.get("defender") == regiment:
				target = melee.get("attacker")
				break

	if not target or not is_instance_valid(target):
		return

	# Get screen positions
	var from_pos: Vector2 = _world_to_screen(regiment.global_position)
	var to_pos: Vector2 = _world_to_screen(target.global_position)

	if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
		return

	# Choose color based on player/enemy
	var line_color: Color = COLOR_TARGET_LINE_PLAYER if regiment.is_player_controlled else COLOR_TARGET_LINE

	# Draw dashed line
	_draw_dashed_line(from_pos, to_pos, line_color, 2.0, 8.0, 4.0)

	# Draw small circle at target end
	draw_control.draw_circle(to_pos, 4.0, line_color)


func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash_length: float, gap_length: float) -> void:
	## Draw a dashed line between two points.
	var direction: Vector2 = (to - from).normalized()
	var total_length: float = from.distance_to(to)
	var current_pos: float = 0.0
	var drawing: bool = true

	while current_pos < total_length:
		var segment_length: float = dash_length if drawing else gap_length
		segment_length = minf(segment_length, total_length - current_pos)

		if drawing:
			var start: Vector2 = from + direction * current_pos
			var end: Vector2 = from + direction * (current_pos + segment_length)
			draw_control.draw_line(start, end, color, width)

		current_pos += segment_length
		drawing = not drawing


func _world_to_screen(world_pos: Vector3) -> Vector2:
	## Convert 3D world position to 2D screen position.
	if not camera:
		return Vector2.ZERO

	# Check if point is in front of camera
	var camera_transform: Transform3D = camera.global_transform
	var local_pos: Vector3 = camera_transform.affine_inverse() * world_pos

	if local_pos.z > 0:
		return Vector2.ZERO  # Behind camera

	# Check if point is on screen
	if not camera.is_position_in_frustum(world_pos):
		return Vector2.ZERO

	return camera.unproject_position(world_pos)
