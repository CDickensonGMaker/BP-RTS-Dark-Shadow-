# Grid-based region definition system.
# Regions are defined by grid cells, ensuring perfect alignment.
# Use this to generate RegionData polygons that tile properly.
class_name RegionGrid
extends RefCounted


## Grid configuration (32x18 for finer detail)
var grid_width: int = 32   # Number of columns
var grid_height: int = 18  # Number of rows
var cell_width: float = 120.0   # Pixels per cell (3840 / 32 = 120)
var cell_height: float = 120.0  # Pixels per cell (2160 / 18 = 120)
var map_offset: Vector2 = Vector2.ZERO

## Grid cell assignments: Vector2i -> region_id
var cell_assignments: Dictionary = {}

## Generated regions
var regions: Dictionary = {}  # region_id -> RegionData


func _init(width: int = 32, height: int = 18, map_size: Vector2 = Vector2(3840, 2160)) -> void:
	grid_width = width
	grid_height = height
	cell_width = map_size.x / float(width)
	cell_height = map_size.y / float(height)


## Assign a grid cell to a region
func assign_cell(x: int, y: int, region_id: String) -> void:
	cell_assignments[Vector2i(x, y)] = region_id


## Assign multiple cells to a region (convenience)
func assign_cells(cells: Array, region_id: String) -> void:
	for cell in cells:
		if cell is Vector2i:
			cell_assignments[cell] = region_id
		elif cell is Array and cell.size() == 2:
			cell_assignments[Vector2i(cell[0], cell[1])] = region_id


## Assign a rectangular block of cells
func assign_rect(start_x: int, start_y: int, width: int, height: int, region_id: String) -> void:
	for y in range(start_y, start_y + height):
		for x in range(start_x, start_x + width):
			cell_assignments[Vector2i(x, y)] = region_id


## Generate RegionData for all assigned regions
func generate_regions() -> Array[RegionData]:
	regions.clear()

	# Group cells by region
	var region_cells: Dictionary = {}  # region_id -> Array[Vector2i]
	for cell in cell_assignments:
		var region_id: String = cell_assignments[cell]
		if not region_cells.has(region_id):
			region_cells[region_id] = []
		region_cells[region_id].append(cell)

	# Generate polygon for each region
	var result: Array[RegionData] = []
	for region_id in region_cells:
		var cells: Array = region_cells[region_id]
		var region := _create_region_from_cells(region_id, cells)
		regions[region_id] = region
		result.append(region)

	return result


## Create a RegionData from a set of cells
func _create_region_from_cells(region_id: String, cells: Array) -> RegionData:
	var region := RegionData.new()
	region.region_id = region_id
	region.region_name = region_id.capitalize().replace("_", " ")

	# Calculate center
	var center := Vector2.ZERO
	for cell in cells:
		center += _cell_center(cell)
	center /= float(cells.size())
	region.map_center = center

	# Generate outline polygon using marching squares
	region.map_polygon = _generate_outline(cells)

	return region


## Get the center point of a cell in world coordinates
func _cell_center(cell: Vector2i) -> Vector2:
	return map_offset + Vector2(
		(cell.x + 0.5) * cell_width,
		(cell.y + 0.5) * cell_height
	)


## Get corner points of a cell
func _cell_corners(cell: Vector2i) -> Array[Vector2]:
	var x := map_offset.x + cell.x * cell_width
	var y := map_offset.y + cell.y * cell_height
	return [
		Vector2(x, y),                           # Top-left
		Vector2(x + cell_width, y),              # Top-right
		Vector2(x + cell_width, y + cell_height), # Bottom-right
		Vector2(x, y + cell_height)              # Bottom-left
	]


## Generate outline polygon for a group of cells
func _generate_outline(cells: Array) -> PackedVector2Array:
	# Convert to set for fast lookup
	var cell_set: Dictionary = {}
	for cell in cells:
		cell_set[cell] = true

	# Find all edges on the boundary
	var edges: Array = []  # Array of [Vector2, Vector2]

	for cell in cells:
		var corners := _cell_corners(cell)

		# Check each edge (top, right, bottom, left)
		var neighbors := [
			Vector2i(cell.x, cell.y - 1),  # Top
			Vector2i(cell.x + 1, cell.y),  # Right
			Vector2i(cell.x, cell.y + 1),  # Bottom
			Vector2i(cell.x - 1, cell.y),  # Left
		]

		var edge_indices := [
			[0, 1],  # Top edge
			[1, 2],  # Right edge
			[2, 3],  # Bottom edge
			[3, 0],  # Left edge
		]

		for i in range(4):
			if not cell_set.has(neighbors[i]):
				# This edge is on the boundary
				var idx := edge_indices[i]
				edges.append([corners[idx[0]], corners[idx[1]]])

	# Sort edges into a continuous path
	return _edges_to_polygon(edges)


## Convert unordered edges to an ordered polygon
func _edges_to_polygon(edges: Array) -> PackedVector2Array:
	if edges.is_empty():
		return PackedVector2Array()

	var polygon: Array[Vector2] = []
	var remaining := edges.duplicate()

	# Start with first edge
	var current_edge: Array = remaining.pop_front()
	polygon.append(current_edge[0])
	polygon.append(current_edge[1])

	# Find connecting edges
	var max_iterations := remaining.size() + 1
	var iterations := 0

	while not remaining.is_empty() and iterations < max_iterations:
		iterations += 1
		var found := false
		var last_point: Vector2 = polygon[polygon.size() - 1]

		for i in range(remaining.size()):
			var edge: Array = remaining[i]

			# Check if edge connects (with small tolerance for floating point)
			if last_point.distance_to(edge[0]) < 0.1:
				polygon.append(edge[1])
				remaining.remove_at(i)
				found = true
				break
			elif last_point.distance_to(edge[1]) < 0.1:
				polygon.append(edge[0])
				remaining.remove_at(i)
				found = true
				break

		if not found:
			# Gap in polygon - might have multiple disconnected regions
			break

	# Remove duplicate last point if it matches first
	if polygon.size() > 1 and polygon[0].distance_to(polygon[polygon.size() - 1]) < 0.1:
		polygon.pop_back()

	return PackedVector2Array(polygon)


## Debug: Print the grid layout
func print_grid() -> void:
	print("=== Region Grid (%dx%d) ===" % [grid_width, grid_height])
	for y in range(grid_height):
		var row := ""
		for x in range(grid_width):
			var cell := Vector2i(x, y)
			if cell_assignments.has(cell):
				var region_id: String = cell_assignments[cell]
				row += region_id.substr(0, 2).to_upper() + " "
			else:
				row += ".. "
		print(row)
	print("")


## Create a default campaign layout (32x18 grid, 2x resolution)
## Helper to expand a 16x9 cell to 32x18 (each old cell becomes a 2x2 block)
static func _expand_cells(old_cells: Array) -> Array:
	var new_cells: Array = []
	for cell in old_cells:
		var x: int = cell.x * 2
		var y: int = cell.y * 2
		new_cells.append(Vector2i(x, y))
		new_cells.append(Vector2i(x + 1, y))
		new_cells.append(Vector2i(x, y + 1))
		new_cells.append(Vector2i(x + 1, y + 1))
	return new_cells


static func create_default_layout() -> RegionGrid:
	var grid := RegionGrid.new(32, 18, Vector2(3840, 2160))

	# Iron Hills (player start) - bottom-left
	grid.assign_cells(_expand_cells([
		Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5),
		Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6),
		Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7),
		Vector2i(0, 8), Vector2i(1, 8),
	]), "iron_hills")

	# Borderlands - bottom-center
	grid.assign_cells(_expand_cells([
		Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5),
		Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7),
		Vector2i(2, 8), Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8),
	]), "borderlands")

	# Blackwood Forest - center
	grid.assign_cells(_expand_cells([
		Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3),
		Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4),
		Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5),
		Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6),
	]), "blackwood")

	# Iron Mountains - top-center
	grid.assign_cells(_expand_cells([
		Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
		Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1),
		Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
	]), "iron_mountains")

	# Eastern Marches - right side
	grid.assign_cells(_expand_cells([
		Vector2i(8, 2), Vector2i(9, 2), Vector2i(10, 2),
		Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3),
		Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4), Vector2i(11, 4),
		Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5),
		Vector2i(8, 6), Vector2i(9, 6),
	]), "eastern_marches")

	# Thornwall Territory - bottom-right
	grid.assign_cells(_expand_cells([
		Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7), Vector2i(9, 7),
		Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8), Vector2i(10, 8),
	]), "thornwall_territory")

	# Northern Wastes - top-left
	grid.assign_cells(_expand_cells([
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
		Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4),
	]), "northern_wastes")

	# Darkfen Swamps - right edge
	grid.assign_cells(_expand_cells([
		Vector2i(12, 3), Vector2i(13, 3), Vector2i(14, 3),
		Vector2i(12, 4), Vector2i(13, 4), Vector2i(14, 4), Vector2i(15, 4),
		Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5), Vector2i(14, 5), Vector2i(15, 5),
		Vector2i(10, 6), Vector2i(11, 6), Vector2i(12, 6), Vector2i(13, 6), Vector2i(14, 6), Vector2i(15, 6),
		Vector2i(10, 7), Vector2i(11, 7), Vector2i(12, 7), Vector2i(13, 7), Vector2i(14, 7), Vector2i(15, 7),
		Vector2i(11, 8), Vector2i(12, 8), Vector2i(13, 8), Vector2i(14, 8), Vector2i(15, 8),
	]), "darkfen_swamps")

	# Far North - top-right
	grid.assign_cells(_expand_cells([
		Vector2i(8, 0), Vector2i(9, 0), Vector2i(10, 0), Vector2i(11, 0), Vector2i(12, 0), Vector2i(13, 0), Vector2i(14, 0), Vector2i(15, 0),
		Vector2i(8, 1), Vector2i(9, 1), Vector2i(10, 1), Vector2i(11, 1), Vector2i(12, 1), Vector2i(13, 1), Vector2i(14, 1), Vector2i(15, 1),
		Vector2i(11, 2), Vector2i(12, 2), Vector2i(13, 2), Vector2i(14, 2), Vector2i(15, 2),
		Vector2i(15, 3),
	]), "far_north")

	return grid
