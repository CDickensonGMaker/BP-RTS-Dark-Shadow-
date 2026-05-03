# SelectionBoxOverlay - draws visual drag selection rectangle
# Integrates with SelectionManager to show selection box during drag
extends CanvasLayer


var draw_control: Control
var box_color: Color = Color(0.2, 0.8, 0.2, 0.15)  # Semi-transparent green fill
var border_color: Color = Color(0.3, 1.0, 0.3, 0.8)  # Brighter green border
var border_width: float = 2.0
var _was_dragging: bool = false  # Track previous drag state for final clear


func _ready():
	# Create a Control node that covers the full screen for drawing
	draw_control = Control.new()
	draw_control.name = "SelectionBoxDrawer"
	draw_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_control.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Don't block mouse events
	add_child(draw_control)

	# Connect our draw method
	draw_control.draw.connect(_on_draw)


func _process(_delta):
	# Trigger redraw every frame when dragging
	if SelectionManager and SelectionManager.is_dragging:
		draw_control.queue_redraw()
		_was_dragging = true
	elif _was_dragging:
		# One more redraw to clear the box when drag ends
		draw_control.queue_redraw()
		_was_dragging = false


func _on_draw():
	if not SelectionManager:
		return

	if not SelectionManager.is_dragging:
		return

	var start = SelectionManager.drag_start
	# Use viewport mouse position for screen-space drawing
	var end = get_viewport().get_mouse_position()

	# Calculate rectangle
	var rect = Rect2(start, end - start).abs()

	# Draw filled rectangle
	draw_control.draw_rect(rect, box_color, true)

	# Draw border
	draw_control.draw_rect(rect, border_color, false, border_width)

	# Draw corner accents (Total War style)
	var corner_size = 8.0
	var corners = [
		rect.position,  # Top-left
		Vector2(rect.end.x, rect.position.y),  # Top-right
		Vector2(rect.position.x, rect.end.y),  # Bottom-left
		rect.end  # Bottom-right
	]

	for corner in corners:
		# Horizontal line
		var h_dir = 1.0 if corner.x == rect.position.x else -1.0
		draw_control.draw_line(
			corner,
			corner + Vector2(corner_size * h_dir, 0),
			border_color,
			border_width + 1
		)
		# Vertical line
		var v_dir = 1.0 if corner.y == rect.position.y else -1.0
		draw_control.draw_line(
			corner,
			corner + Vector2(0, corner_size * v_dir),
			border_color,
			border_width + 1
		)
