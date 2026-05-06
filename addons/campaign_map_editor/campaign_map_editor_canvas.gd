@tool
extends Control
class_name CampaignMapEditorCanvas
## Custom Control for the campaign map grid painting canvas

signal cell_painted(x: int, y: int, region_id: String)
signal cell_erased(x: int, y: int)
signal cell_selected(x: int, y: int)
signal poi_selected(index: int)
signal poi_moved(index: int, new_x: int, new_y: int)
signal canvas_panned(offset: Vector2)
signal canvas_zoomed(zoom: float)

const MIN_ZOOM := 0.1
const MAX_ZOOM := 2.0
const ZOOM_STEP := 0.1

var map_state: CampaignMapEditorData.MapState
var editor_state: CampaignMapEditorData.EditorState
var map_texture: Texture2D

var _is_painting: bool = false
var _is_panning: bool = false
var _pan_start: Vector2 = Vector2.ZERO
var _last_painted_cell: Vector2i = Vector2i(-1, -1)
var _hovered_cell: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(400, 400)

	# Try to load map texture
	var map_path := "res://assets/textures/campaign_map.png"
	if ResourceLoader.exists(map_path):
		map_texture = load(map_path)


func set_map_texture(tex: Texture2D) -> void:
	map_texture = tex
	if map_texture and map_state:
		map_state.map_size = Vector2(map_texture.get_width(), map_texture.get_height())
	queue_redraw()


func _draw() -> void:
	if not map_state or not editor_state:
		return

	var cell_size: Vector2 = map_state.get_cell_size() * editor_state.zoom
	var offset: Vector2 = editor_state.pan_offset

	# Draw background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.12, 0.15))

	# Draw map texture if available
	if map_texture:
		var tex_size := Vector2(map_texture.get_width(), map_texture.get_height()) * editor_state.zoom
		draw_texture_rect(map_texture, Rect2(offset, tex_size), false)

	# Draw region overlays
	if editor_state.show_regions:
		_draw_regions(cell_size, offset)

	# Draw grid
	if editor_state.show_grid:
		_draw_grid(cell_size, offset)

	# Draw region labels
	if editor_state.show_labels:
		_draw_region_labels(cell_size, offset)

	# Draw POIs
	if editor_state.show_pois:
		_draw_pois(cell_size, offset)

	# Draw hovered cell highlight
	if _hovered_cell.x >= 0 and _hovered_cell.y >= 0:
		_draw_cell_highlight(_hovered_cell, cell_size, offset, Color(1, 1, 1, 0.4))

	# Draw selected cell
	if editor_state.selected_cell.x >= 0 and editor_state.selected_cell.y >= 0:
		_draw_cell_highlight(editor_state.selected_cell, cell_size, offset, Color(1, 0.8, 0, 0.6))

	# Draw brush preview
	if _hovered_cell.x >= 0 and editor_state.current_brush in ["region", "erase"]:
		_draw_brush_preview(cell_size, offset)


func _draw_regions(cell_size: Vector2, offset: Vector2) -> void:
	for y: int in range(map_state.grid_height):
		for x: int in range(map_state.grid_width):
			var region_id: String = map_state.get_cell_region(x, y)
			if region_id.is_empty():
				continue

			var info: CampaignMapEditorData.RegionInfo = map_state.get_region(region_id)
			if not info:
				continue

			var color: Color
			match editor_state.color_by:
				"terrain":
					color = CampaignMapEditorData.TERRAIN_COLORS.get(info.terrain_type, Color(0.5, 0.5, 0.5, 0.3))
					color.a = 0.5
				"owner":
					color = CampaignMapEditorData.FACTION_COLORS.get(info.owner_faction, Color(0.5, 0.5, 0.5, 0.5))
				"region":
					color = info.region_color
				_:
					color = Color(0.5, 0.5, 0.5, 0.3)

			var rect := Rect2(
				Vector2(x * cell_size.x, y * cell_size.y) + offset,
				cell_size
			)
			draw_rect(rect, color)

			# Draw subtle border for each cell in region
			draw_rect(rect, color.darkened(0.3), false, 1.0)


func _draw_grid(cell_size: Vector2, offset: Vector2) -> void:
	var grid_color := Color(0.4, 0.4, 0.4, 0.4)
	var major_color := Color(0.6, 0.6, 0.6, 0.5)

	# Vertical lines
	for x: int in range(map_state.grid_width + 1):
		var x_pos: float = x * cell_size.x + offset.x
		var color: Color = major_color if x % 4 == 0 else grid_color
		var width: float = 2.0 if x % 4 == 0 else 1.0
		draw_line(
			Vector2(x_pos, offset.y),
			Vector2(x_pos, map_state.grid_height * cell_size.y + offset.y),
			color, width
		)

	# Horizontal lines
	for y: int in range(map_state.grid_height + 1):
		var y_pos: float = y * cell_size.y + offset.y
		var color: Color = major_color if y % 3 == 0 else grid_color
		var width: float = 2.0 if y % 3 == 0 else 1.0
		draw_line(
			Vector2(offset.x, y_pos),
			Vector2(map_state.grid_width * cell_size.x + offset.x, y_pos),
			color, width
		)


func _draw_region_labels(cell_size: Vector2, offset: Vector2) -> void:
	var font: Font = ThemeDB.fallback_font
	var font_size: int = int(mini(cell_size.x, cell_size.y) * 0.15)
	font_size = clampi(font_size, 8, 24)

	# Group cells by region to find center
	var region_cells: Dictionary = {}  # region_id -> Array[Vector2i]
	for y: int in range(map_state.grid_height):
		for x: int in range(map_state.grid_width):
			var region_id: String = map_state.get_cell_region(x, y)
			if region_id.is_empty():
				continue
			if not region_cells.has(region_id):
				region_cells[region_id] = []
			region_cells[region_id].append(Vector2i(x, y))

	# Draw label at center of each region
	for region_id: String in region_cells:
		var cells: Array = region_cells[region_id]
		var center := Vector2.ZERO
		for cell: Vector2i in cells:
			center += Vector2(cell.x + 0.5, cell.y + 0.5)
		center /= float(cells.size())

		var screen_pos := Vector2(center.x * cell_size.x, center.y * cell_size.y) + offset

		var info: CampaignMapEditorData.RegionInfo = map_state.get_region(region_id)
		var label: String = info.region_name if info else region_id.capitalize()

		var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)

		# Draw text shadow
		draw_string(font, screen_pos - text_size / 2 + Vector2(1, 1 + text_size.y * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.BLACK)
		# Draw text
		draw_string(font, screen_pos - text_size / 2 + Vector2(0, text_size.y * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _draw_pois(cell_size: Vector2, offset: Vector2) -> void:
	for key: String in map_state.poi_data:
		var poi: Dictionary = map_state.poi_data[key]
		var x: int = poi.get("x", -1)
		var y: int = poi.get("y", -1)

		# Skip unplaced settlements
		if x < 0 or y < 0:
			continue

		var poi_type: String = poi.get("type", "landmark")
		var settlement_type: String = poi.get("settlement_type", "")
		var is_capital: bool = poi.get("is_capital", false)

		var center := Vector2((x + 0.5) * cell_size.x, (y + 0.5) * cell_size.y) + offset
		var radius: float = mini(cell_size.x, cell_size.y) * 0.35

		# Determine color and icon
		var color: Color
		var icon: String

		if poi_type == "settlement":
			# Settlement-specific rendering
			if is_capital:
				color = Color(1.0, 0.85, 0.2)  # Gold for capital
				icon = "★"
				radius *= 1.3  # Capitals are larger
			else:
				color = Color(0.9, 0.7, 0.4)  # Tan for minor settlements
				match settlement_type:
					"town": icon = "▲"
					"village": icon = "●"
					"fortress": icon = "■"
					_: icon = "●"
		else:
			# Legacy POI rendering
			color = CampaignMapEditorData.POI_COLORS.get(poi_type, Color.WHITE)
			icon = CampaignMapEditorData.POI_ICONS.get(poi_type, "?")

		# Draw POI marker background
		draw_circle(center, radius, color)
		draw_arc(center, radius, 0, TAU, 32, Color.BLACK, 2.0)

		# Draw icon
		var font: Font = ThemeDB.fallback_font
		var font_size: int = int(radius * 1.4)
		var text_size: Vector2 = font.get_string_size(icon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(font, center - text_size / 2 + Vector2(0, text_size.y * 0.35), icon, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.BLACK)

		# Draw selection highlight for selected POI
		if key == str(editor_state.selected_poi_index):
			draw_arc(center, radius + 4, 0, TAU, 32, Color.WHITE, 3.0)

		# Draw name if zoomed in enough
		if editor_state.zoom >= 0.3:
			var name_str: String = poi.get("name", "")
			if not name_str.is_empty():
				var name_font_size: int = 12 if is_capital else 10
				var name_size: Vector2 = font.get_string_size(name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, name_font_size)
				var name_pos := Vector2(center.x - name_size.x / 2, center.y + radius + 14)
				# Shadow
				draw_string(font, name_pos + Vector2(1, 1), name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, name_font_size, Color.BLACK)
				# Text
				var text_color: Color = Color(1.0, 0.95, 0.7) if is_capital else Color.WHITE
				draw_string(font, name_pos, name_str, HORIZONTAL_ALIGNMENT_CENTER, -1, name_font_size, text_color)


func _draw_cell_highlight(cell: Vector2i, cell_size: Vector2, offset: Vector2, color: Color) -> void:
	var rect := Rect2(
		Vector2(cell.x * cell_size.x, cell.y * cell_size.y) + offset,
		cell_size
	)
	draw_rect(rect, color, false, 3.0)


func _draw_brush_preview(cell_size: Vector2, offset: Vector2) -> void:
	var brush_color: Color = Color(1, 1, 1, 0.2) if not editor_state.is_eraser else Color(1, 0, 0, 0.3)
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
				if editor_state.current_brush == "poi":
					# Select POI or place new one
					var poi_index: int = _get_poi_at_cell(cell)
					if poi_index >= 0:
						editor_state.selected_poi_index = poi_index
						poi_selected.emit(poi_index)
					else:
						editor_state.selected_poi_index = -1
				else:
					# Paint region
					_is_painting = true
					editor_state.selected_cell = cell
					cell_selected.emit(cell.x, cell.y)
					_paint_at_cell(cell)
			else:
				_is_painting = false
				_last_painted_cell = Vector2i(-1, -1)
			queue_redraw()

		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if editor_state.current_brush == "region":
					# Erase
					_is_painting = true
					_erase_at_cell(cell)
				else:
					# Deselect
					editor_state.selected_poi_index = -1
					poi_selected.emit(-1)
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
		canvas_panned.emit(editor_state.pan_offset)
		queue_redraw()
	elif _is_painting and cell != _last_painted_cell:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_paint_at_cell(cell)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			_erase_at_cell(cell)
		queue_redraw()
	else:
		queue_redraw()


func _screen_to_cell(screen_pos: Vector2) -> Vector2i:
	var cell_size: Vector2 = map_state.get_cell_size() * editor_state.zoom
	var adjusted := screen_pos - editor_state.pan_offset
	return Vector2i(int(adjusted.x / cell_size.x), int(adjusted.y / cell_size.y))


func _paint_at_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= map_state.grid_width or cell.y < 0 or cell.y >= map_state.grid_height:
		return

	if editor_state.current_region_id.is_empty():
		return

	var half_size: int = editor_state.brush_size / 2

	for dy: int in range(-half_size, half_size + 1):
		for dx: int in range(-half_size, half_size + 1):
			var target := Vector2i(cell.x + dx, cell.y + dy)
			if target.x >= 0 and target.x < map_state.grid_width and target.y >= 0 and target.y < map_state.grid_height:
				cell_painted.emit(target.x, target.y, editor_state.current_region_id)

	_last_painted_cell = cell


func _erase_at_cell(cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= map_state.grid_width or cell.y < 0 or cell.y >= map_state.grid_height:
		return

	var half_size: int = editor_state.brush_size / 2

	for dy: int in range(-half_size, half_size + 1):
		for dx: int in range(-half_size, half_size + 1):
			var target := Vector2i(cell.x + dx, cell.y + dy)
			if target.x >= 0 and target.x < map_state.grid_width and target.y >= 0 and target.y < map_state.grid_height:
				cell_erased.emit(target.x, target.y)

	_last_painted_cell = cell


func _get_poi_at_cell(cell: Vector2i) -> int:
	for key: String in map_state.poi_data:
		var poi: Dictionary = map_state.poi_data[key]
		if poi.get("x", -1) == cell.x and poi.get("y", -1) == cell.y:
			return int(key)
	return -1


func _zoom_at_point(point: Vector2, delta: float) -> void:
	var old_zoom: float = editor_state.zoom
	editor_state.zoom = clampf(editor_state.zoom + delta, MIN_ZOOM, MAX_ZOOM)

	if old_zoom != editor_state.zoom:
		# Adjust pan to zoom towards mouse position
		var zoom_factor: float = editor_state.zoom / old_zoom
		var point_before := (point - editor_state.pan_offset)
		var point_after := point_before * zoom_factor
		editor_state.pan_offset -= (point_after - point_before)

		canvas_zoomed.emit(editor_state.zoom)
		queue_redraw()


func center_on_map() -> void:
	if not map_state or not editor_state:
		return

	var map_size_zoomed := map_state.map_size * editor_state.zoom
	editor_state.pan_offset = (size - map_size_zoomed) / 2
	queue_redraw()


func fit_to_view() -> void:
	if not map_state or not editor_state:
		return

	# Calculate zoom to fit map in view
	var zoom_x: float = size.x / map_state.map_size.x
	var zoom_y: float = size.y / map_state.map_size.y
	editor_state.zoom = clampf(minf(zoom_x, zoom_y) * 0.95, MIN_ZOOM, MAX_ZOOM)

	center_on_map()
	canvas_zoomed.emit(editor_state.zoom)
