@tool
extends Control
class_name BattleSceneEditorCanvas
## Canvas for battle scene editor with terrain and object painting

signal terrain_painted(x: int, y: int, terrain: String)
signal terrain_erased(x: int, y: int)
signal object_placed(x: int, y: int, obj_type: String)
signal object_removed(x: int, y: int)
signal object_selected(index: int)
signal cell_selected(x: int, y: int)
signal canvas_zoomed(zoom: float)

const CELL_SIZE := 16  # Base pixel size per cell
const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const ZOOM_STEP := 0.15

var map_state: BattleSceneEditorData.BattleMapState
var editor_state: BattleSceneEditorData.EditorState

var _is_painting: bool = false
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _last_painted_cell: Vector2i = Vector2i(-1, -1)
var _hovered_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(400, 400)


func _draw() -> void:
	if not map_state or not editor_state:
		return

	var cell_size: float = CELL_SIZE * editor_state.zoom
	var offset: Vector2 = editor_state.pan_offset

	# Background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.12))

	# Calculate visible range
	var start_x: int = maxi(0, int(-offset.x / cell_size))
	var start_y: int = maxi(0, int(-offset.y / cell_size))
	var end_x: int = mini(map_state.grid_width, int((-offset.x + size.x) / cell_size) + 1)
	var end_y: int = mini(map_state.grid_height, int((-offset.y + size.y) / cell_size) + 1)

	# Draw terrain
	_draw_terrain(start_x, start_y, end_x, end_y, cell_size, offset)

	# Draw deployment zones
	if editor_state.show_deployment:
		_draw_deployment_zones(cell_size, offset)

	# Draw grid
	if editor_state.show_grid:
		_draw_grid(start_x, start_y, end_x, end_y, cell_size, offset)

	# Draw objects
	if editor_state.show_objects:
		_draw_objects(cell_size, offset)

	# Draw hover highlight
	if _hovered_cell.x >= 0 and _hovered_cell.y >= 0:
		_draw_cell_highlight(_hovered_cell, cell_size, offset, Color(1, 1, 1, 0.3))

	# Draw brush preview
	if editor_state.current_tool in ["terrain", "erase"]:
		_draw_brush_preview(cell_size, offset)


func _draw_terrain(start_x: int, start_y: int, end_x: int, end_y: int, cell_size: float, offset: Vector2) -> void:
	for y: int in range(start_y, end_y):
		for x: int in range(start_x, end_x):
			var terrain: String = map_state.get_terrain(x, y)
			if terrain.is_empty():
				continue

			var color: Color = BattleSceneEditorData.TERRAIN_COLORS.get(terrain, Color(0.5, 0.5, 0.5))
			var rect := Rect2(
				Vector2(x * cell_size, y * cell_size) + offset,
				Vector2(cell_size, cell_size)
			)
			draw_rect(rect, color)


func _draw_deployment_zones(cell_size: float, offset: Vector2) -> void:
	# Player deployment (blue)
	var player_rect := Rect2(
		Vector2(map_state.player_deployment.position.x * cell_size, map_state.player_deployment.position.y * cell_size) + offset,
		Vector2(map_state.player_deployment.size.x * cell_size, map_state.player_deployment.size.y * cell_size)
	)
	draw_rect(player_rect, Color(0.2, 0.4, 0.8, 0.3))
	draw_rect(player_rect, Color(0.3, 0.5, 0.9, 0.8), false, 2.0)

	# Label
	var font: Font = ThemeDB.fallback_font
	draw_string(font, player_rect.position + Vector2(4, 14), "Player Deploy", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

	# Enemy deployment (red)
	var enemy_rect := Rect2(
		Vector2(map_state.enemy_deployment.position.x * cell_size, map_state.enemy_deployment.position.y * cell_size) + offset,
		Vector2(map_state.enemy_deployment.size.x * cell_size, map_state.enemy_deployment.size.y * cell_size)
	)
	draw_rect(enemy_rect, Color(0.8, 0.2, 0.2, 0.3))
	draw_rect(enemy_rect, Color(0.9, 0.3, 0.3, 0.8), false, 2.0)

	draw_string(font, enemy_rect.position + Vector2(4, 14), "Enemy Deploy", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _draw_grid(start_x: int, start_y: int, end_x: int, end_y: int, cell_size: float, offset: Vector2) -> void:
	var grid_color := Color(0.3, 0.3, 0.3, 0.4)
	var major_color := Color(0.5, 0.5, 0.5, 0.5)

	# Vertical lines
	for x: int in range(start_x, end_x + 1):
		var x_pos: float = x * cell_size + offset.x
		var color: Color = major_color if x % 8 == 0 else grid_color
		var width: float = 2.0 if x % 8 == 0 else 1.0
		draw_line(
			Vector2(x_pos, start_y * cell_size + offset.y),
			Vector2(x_pos, end_y * cell_size + offset.y),
			color, width
		)

	# Horizontal lines
	for y: int in range(start_y, end_y + 1):
		var y_pos: float = y * cell_size + offset.y
		var color: Color = major_color if y % 8 == 0 else grid_color
		var width: float = 2.0 if y % 8 == 0 else 1.0
		draw_line(
			Vector2(start_x * cell_size + offset.x, y_pos),
			Vector2(end_x * cell_size + offset.x, y_pos),
			color, width
		)


func _draw_objects(cell_size: float, offset: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(cell_size * 0.7)
	font_size = clampi(font_size, 8, 20)

	for i: int in range(map_state.objects.size()):
		var obj: Dictionary = map_state.objects[i]
		var obj_type: String = obj.get("type", "")
		var x: int = obj.get("x", 0)
		var y: int = obj.get("y", 0)

		var center := Vector2((x + 0.5) * cell_size, (y + 0.5) * cell_size) + offset
		var color: Color = BattleSceneEditorData.OBJECT_COLORS.get(obj_type, Color.WHITE)
		var icon: String = BattleSceneEditorData.OBJECT_ICONS.get(obj_type, "?")

		# Draw background circle
		var radius: float = cell_size * 0.4
		draw_circle(center, radius, color)
		draw_arc(center, radius, 0, TAU, 24, Color.BLACK, 1.5)

		# Draw icon
		var text_size: Vector2 = font.get_string_size(icon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, center - text_size / 2 + Vector2(0, text_size.y * 0.35), icon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

		# Selection highlight
		if i == editor_state.selected_object_index:
			draw_arc(center, radius + 3, 0, TAU, 24, Color.YELLOW, 2.0)


func _draw_cell_highlight(cell: Vector2i, cell_size: float, offset: Vector2, color: Color) -> void:
	var rect := Rect2(
		Vector2(cell.x * cell_size, cell.y * cell_size) + offset,
		Vector2(cell_size, cell_size)
	)
	draw_rect(rect, color, false, 2.0)


func _draw_brush_preview(cell_size: float, offset: Vector2) -> void:
	var is_erase: bool = editor_state.current_tool == "erase"
	var brush_color: Color = Color(1, 0, 0, 0.3) if is_erase else Color(1, 1, 1, 0.2)
	var half_size: int = editor_state.brush_size / 2

	for dy: int in range(-half_size, half_size + 1):
		for dx: int in range(-half_size, half_size + 1):
			var cell := Vector2i(_hovered_cell.x + dx, _hovered_cell.y + dy)
			if cell.x >= 0 and cell.x < map_state.grid_width and cell.y >= 0 and cell.y < map_state.grid_height:
				_draw_cell_highlight(cell, cell_size, offset, brush_color)


func _gui_input(event: InputEvent) -> void:
	if not map_state or not editor_state:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	var cell := _screen_to_cell(event.position)

	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				match editor_state.current_tool:
					"terrain":
						_is_painting = true
						_paint_terrain(cell)
					"object":
						_place_object(cell)
					"erase":
						_is_painting = true
						_erase_at_cell(cell)
					"deployment":
						cell_selected.emit(cell.x, cell.y)
			else:
				_is_painting = false
				_last_painted_cell = Vector2i(-1, -1)
			queue_redraw()

		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if editor_state.current_tool == "object":
					_remove_object(cell)
				else:
					_is_painting = true
					_erase_at_cell(cell)
			else:
				_is_painting = false
				_last_painted_cell = Vector2i(-1, -1)
			queue_redraw()

		MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_is_panning = true
				_pan_start = event.position
			else:
				_is_panning = false

		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_at_point(event.position, ZOOM_STEP)

		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_at_point(event.position, -ZOOM_STEP)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var cell := _screen_to_cell(event.position)
	_hovered_cell = cell

	if _is_panning:
		editor_state.pan_offset += event.relative
		queue_redraw()
	elif _is_painting and cell != _last_painted_cell:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			if editor_state.current_tool == "terrain":
				_paint_terrain(cell)
			elif editor_state.current_tool == "erase":
				_erase_at_cell(cell)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_erase_at_cell(cell)
		queue_redraw()
	else:
		queue_redraw()


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var cell_size: float = CELL_SIZE * editor_state.zoom
	var adjusted := screen_pos - editor_state.pan_offset
	return Vector2i(int(adjusted.x / cell_size), int(adjusted.y / cell_size))


func _paint_terrain(cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= map_state.grid_width or cell.y < 0 or cell.y >= map_state.grid_height:
		return

	var half_size: int = editor_state.brush_size / 2
	for dy: int in range(-half_size, half_size + 1):
		for dx: int in range(-half_size, half_size + 1):
			var target := Vector2i(cell.x + dx, cell.y + dy)
			if target.x >= 0 and target.x < map_state.grid_width and target.y >= 0 and target.y < map_state.grid_height:
				terrain_painted.emit(target.x, target.y, editor_state.current_terrain)

	_last_painted_cell = cell


func _erase_at_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= map_state.grid_width or cell.y < 0 or cell.y >= map_state.grid_height:
		return

	var half_size: int = editor_state.brush_size / 2
	for dy: int in range(-half_size, half_size + 1):
		for dx: int in range(-half_size, half_size + 1):
			var target := Vector2i(cell.x + dx, cell.y + dy)
			if target.x >= 0 and target.x < map_state.grid_width and target.y >= 0 and target.y < map_state.grid_height:
				terrain_erased.emit(target.x, target.y)

	_last_painted_cell = cell


func _place_object(cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= map_state.grid_width or cell.y < 0 or cell.y >= map_state.grid_height:
		return
	object_placed.emit(cell.x, cell.y, editor_state.current_object)


func _remove_object(cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= map_state.grid_width or cell.y < 0 or cell.y >= map_state.grid_height:
		return
	object_removed.emit(cell.x, cell.y)


func _zoom_at_point(point: Vector2, delta: float) -> void:
	var old_zoom: float = editor_state.zoom
	editor_state.zoom = clampf(editor_state.zoom + delta, MIN_ZOOM, MAX_ZOOM)

	if old_zoom != editor_state.zoom:
		var zoom_factor: float = editor_state.zoom / old_zoom
		var point_before := (point - editor_state.pan_offset)
		var point_after := point_before * zoom_factor
		editor_state.pan_offset -= (point_after - point_before)

		canvas_zoomed.emit(editor_state.zoom)
		queue_redraw()


func center_on_map() -> void:
	if not map_state or not editor_state:
		return

	var cell_size: float = CELL_SIZE * editor_state.zoom
	var map_pixel_size := Vector2(map_state.grid_width * cell_size, map_state.grid_height * cell_size)
	editor_state.pan_offset = (size - map_pixel_size) / 2
	queue_redraw()


func fit_to_view() -> void:
	if not map_state or not editor_state:
		return

	var map_pixel_size := Vector2(map_state.grid_width * CELL_SIZE, map_state.grid_height * CELL_SIZE)
	var zoom_x: float = size.x / map_pixel_size.x
	var zoom_y: float = size.y / map_pixel_size.y
	editor_state.zoom = clampf(minf(zoom_x, zoom_y) * 0.9, MIN_ZOOM, MAX_ZOOM)

	center_on_map()
	canvas_zoomed.emit(editor_state.zoom)
