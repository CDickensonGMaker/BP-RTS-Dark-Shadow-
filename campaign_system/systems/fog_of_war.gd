# Fog of War system for the campaign map.
# Tracks explored regions and provides visual fog overlay.
# Uses a grid-based approach for efficient visibility calculations.
class_name FogOfWar
extends Node2D


# =============================================================================
# CONFIGURATION
# =============================================================================

## Size of each fog grid cell in pixels
@export var cell_size: float = 50.0

## Base visibility radius around battalions
@export var battalion_sight_range: float = 200.0

## How much of the map is revealed initially (0.0 = all hidden, 1.0 = all visible)
@export var initial_revealed: float = 0.0

## Fog color for unexplored areas
@export var fog_color: Color = Color(0.08, 0.06, 0.04, 0.95)

## Fog color for explored but not visible areas (shroud)
@export var shroud_color: Color = Color(0.08, 0.06, 0.04, 0.6)

## Map bounds (should match campaign map)
@export var map_bounds: Rect2 = Rect2(0, 0, 1920, 1080)

# =============================================================================
# STATE
# =============================================================================

## Grid tracking fog state: 0 = unexplored, 1 = explored, 2 = visible
var fog_grid: Array = []

## Grid dimensions
var grid_width: int = 0
var grid_height: int = 0

## Fog texture for rendering
var fog_image: Image = null
var fog_texture: ImageTexture = null
var fog_sprite: Sprite2D = null

## Is fog of war enabled?
var is_enabled: bool = true

# =============================================================================
# CONSTANTS
# =============================================================================

const STATE_UNEXPLORED := 0
const STATE_EXPLORED := 1
const STATE_VISIBLE := 2

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	# Calculate grid dimensions
	grid_width = int(ceil(map_bounds.size.x / cell_size))
	grid_height = int(ceil(map_bounds.size.y / cell_size))

	# Initialize fog grid
	_initialize_grid()

	# Create fog visual
	_create_fog_visual()

	# Connect signals
	if CampaignSignals:
		CampaignSignals.battalion_moved.connect(_on_battalion_moved)
		CampaignSignals.turn_started.connect(_on_turn_started)


func _initialize_grid() -> void:
	## Initialize the fog grid with default state
	fog_grid.clear()
	fog_grid.resize(grid_width * grid_height)

	var initial_state := STATE_UNEXPLORED
	if initial_revealed >= 1.0:
		initial_state = STATE_VISIBLE
	elif initial_revealed > 0.0:
		initial_state = STATE_EXPLORED

	for i in range(fog_grid.size()):
		fog_grid[i] = initial_state


func _create_fog_visual() -> void:
	## Create the fog overlay sprite
	fog_image = Image.create(grid_width, grid_height, false, Image.FORMAT_RGBA8)
	fog_texture = ImageTexture.create_from_image(fog_image)

	fog_sprite = Sprite2D.new()
	fog_sprite.texture = fog_texture
	fog_sprite.centered = false
	fog_sprite.position = map_bounds.position
	fog_sprite.scale = Vector2(cell_size, cell_size)
	fog_sprite.z_index = 50  # Above map but below armies (z=200)
	fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR  # Smooth edges, hide grid
	add_child(fog_sprite)

	_update_fog_texture()

# =============================================================================
# FOG UPDATES
# =============================================================================

func reveal_area(center: Vector2, radius: float) -> void:
	## Reveal an area around a point
	if not is_enabled:
		return

	var cells_radius := int(ceil(radius / cell_size))
	var center_cell := _world_to_grid(center)

	for dx in range(-cells_radius, cells_radius + 1):
		for dy in range(-cells_radius, cells_radius + 1):
			var gx := center_cell.x + dx
			var gy := center_cell.y + dy

			if gx < 0 or gx >= grid_width or gy < 0 or gy >= grid_height:
				continue

			# Check if within circular radius
			var cell_center := _grid_to_world(Vector2i(gx, gy))
			if center.distance_to(cell_center) <= radius:
				var idx := gy * grid_width + gx
				fog_grid[idx] = STATE_VISIBLE


func explore_area(center: Vector2, radius: float) -> void:
	## Mark an area as explored (but not necessarily visible)
	if not is_enabled:
		return

	var cells_radius := int(ceil(radius / cell_size))
	var center_cell := _world_to_grid(center)

	for dx in range(-cells_radius, cells_radius + 1):
		for dy in range(-cells_radius, cells_radius + 1):
			var gx := center_cell.x + dx
			var gy := center_cell.y + dy

			if gx < 0 or gx >= grid_width or gy < 0 or gy >= grid_height:
				continue

			var cell_center := _grid_to_world(Vector2i(gx, gy))
			if center.distance_to(cell_center) <= radius:
				var idx := gy * grid_width + gx
				# Only upgrade from unexplored
				if fog_grid[idx] == STATE_UNEXPLORED:
					fog_grid[idx] = STATE_EXPLORED


func update_visibility() -> void:
	## Update visibility based on current battalion positions
	if not is_enabled:
		return

	# First, downgrade all visible to explored
	for i in range(fog_grid.size()):
		if fog_grid[i] == STATE_VISIBLE:
			fog_grid[i] = STATE_EXPLORED

	# Then reveal around each player battalion
	if CampaignManager:
		for battalion_data in CampaignManager.battalions:
			reveal_area(battalion_data.map_position, battalion_sight_range)

	_update_fog_texture()


func _update_fog_texture() -> void:
	## Update the fog image based on grid state
	if not fog_image:
		return

	for y in range(grid_height):
		for x in range(grid_width):
			var idx := y * grid_width + x
			var state: int = fog_grid[idx]

			var color: Color
			match state:
				STATE_UNEXPLORED:
					color = fog_color
				STATE_EXPLORED:
					color = shroud_color
				STATE_VISIBLE:
					color = Color(0, 0, 0, 0)  # Fully transparent
				_:
					color = fog_color

			fog_image.set_pixel(x, y, color)

	fog_texture.update(fog_image)

# =============================================================================
# COORDINATE CONVERSION
# =============================================================================

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	## Convert world position to grid coordinates
	var local := world_pos - map_bounds.position
	var gx := int(local.x / cell_size)
	var gy := int(local.y / cell_size)
	return Vector2i(clampi(gx, 0, grid_width - 1), clampi(gy, 0, grid_height - 1))


func _grid_to_world(grid_pos: Vector2i) -> Vector2:
	## Convert grid coordinates to world position (center of cell)
	return map_bounds.position + Vector2(
		(grid_pos.x + 0.5) * cell_size,
		(grid_pos.y + 0.5) * cell_size
	)

# =============================================================================
# QUERIES
# =============================================================================

func is_position_visible(world_pos: Vector2) -> bool:
	## Check if a world position is currently visible
	if not is_enabled:
		return true

	var grid_pos := _world_to_grid(world_pos)
	var idx := grid_pos.y * grid_width + grid_pos.x
	return fog_grid[idx] == STATE_VISIBLE


func is_position_explored(world_pos: Vector2) -> bool:
	## Check if a world position has been explored
	if not is_enabled:
		return true

	var grid_pos := _world_to_grid(world_pos)
	var idx := grid_pos.y * grid_width + grid_pos.x
	return fog_grid[idx] >= STATE_EXPLORED


func get_visibility_state(world_pos: Vector2) -> int:
	## Get the visibility state at a world position
	var grid_pos := _world_to_grid(world_pos)
	var idx := grid_pos.y * grid_width + grid_pos.x
	return fog_grid[idx]

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_battalion_moved(battalion: Node2D, new_position: Vector2) -> void:
	## Reveal fog around moved battalion
	reveal_area(new_position, battalion_sight_range)
	_update_fog_texture()


func _on_turn_started(_turn: int) -> void:
	## Refresh visibility at turn start
	update_visibility()

# =============================================================================
# CONTROL
# =============================================================================

func set_enabled(enabled: bool) -> void:
	## Enable or disable fog of war
	is_enabled = enabled
	if fog_sprite:
		fog_sprite.visible = enabled


func reveal_all() -> void:
	## Reveal the entire map (debug/cheat)
	for i in range(fog_grid.size()):
		fog_grid[i] = STATE_VISIBLE
	_update_fog_texture()


func hide_all() -> void:
	## Hide the entire map (reset)
	for i in range(fog_grid.size()):
		fog_grid[i] = STATE_UNEXPLORED
	_update_fog_texture()


func get_save_data() -> Dictionary:
	## Get fog state for saving
	return {
		"grid": fog_grid.duplicate(),
		"enabled": is_enabled,
	}


func load_save_data(data: Dictionary) -> void:
	## Load fog state from save
	if data.has("grid"):
		fog_grid = data.grid
		_update_fog_texture()
	if data.has("enabled"):
		is_enabled = data.enabled
		if fog_sprite:
			fog_sprite.visible = is_enabled
