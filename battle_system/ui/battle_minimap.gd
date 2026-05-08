class_name BattleMinimap
extends Control

## Renders a tactical minimap showing:
## - Terrain (simplified)
## - Unit positions (color-coded by faction)
## - Camera viewport indicator
## - Click to move camera

@export var map_size: Vector2 = Vector2(200, 200)  # World units
@export var minimap_size: Vector2 = Vector2(180, 160)  # Pixels - slightly larger for better clicking

var _terrain: Node3D = null
var _camera: Camera3D = null
var _viewport_rect: Rect2 = Rect2()

# Colors
const COLOR_TERRAIN = Color(0.2, 0.25, 0.15, 1.0)
const COLOR_TERRAIN_HILL = Color(0.35, 0.4, 0.25, 1.0)
const COLOR_PLAYER = Color(0.2, 0.5, 0.9, 1.0)
const COLOR_ENEMY = Color(0.9, 0.2, 0.2, 1.0)
const COLOR_SELECTED = Color(1.0, 1.0, 0.3, 1.0)
const COLOR_VIEWPORT = Color(1.0, 1.0, 1.0, 0.5)
const COLOR_DEPLOYMENT_ZONE = Color(0.3, 0.7, 0.4, 0.3)

# Cached data
var _terrain_image: Image = null
var _terrain_texture: ImageTexture = null
var _needs_terrain_update: bool = true


func _ready():
	custom_minimum_size = minimap_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS  # Crosshair for tactical map
	call_deferred("_find_references")
	call_deferred("_generate_terrain_texture")


func _find_references():
	# Find terrain
	var terrains: Array[Node] = get_tree().get_nodes_in_group("terrain")
	if terrains.size() > 0:
		_terrain = terrains[0]
		if _terrain.has_method("get") and _terrain.get("terrain_size"):
			map_size = _terrain.terrain_size

	# Find camera
	_camera = get_viewport().get_camera_3d()


func _generate_terrain_texture():
	if not _terrain or not _terrain.has_method("get_height_at"):
		_create_flat_terrain_texture()
		return

	# Create terrain heightmap texture
	var img_size: int = 64
	_terrain_image = Image.create(img_size, img_size, false, Image.FORMAT_RGB8)

	var half_x: float = map_size.x / 2.0
	var half_z: float = map_size.y / 2.0

	var min_h: float = INF
	var max_h: float = -INF

	# First pass: find height range
	for y in range(img_size):
		for x in range(img_size):
			var world_x: float = (float(x) / img_size) * map_size.x - half_x
			var world_z: float = (float(y) / img_size) * map_size.y - half_z
			var h: float = _terrain.get_height_at(Vector3(world_x, 0, world_z))
			min_h = minf(min_h, h)
			max_h = maxf(max_h, h)

	# Second pass: generate colors
	var height_range: float = maxf(max_h - min_h, 0.1)
	for y in range(img_size):
		for x in range(img_size):
			var world_x: float = (float(x) / img_size) * map_size.x - half_x
			var world_z: float = (float(y) / img_size) * map_size.y - half_z
			var h: float = _terrain.get_height_at(Vector3(world_x, 0, world_z))
			var t: float = (h - min_h) / height_range
			var color: Color = COLOR_TERRAIN.lerp(COLOR_TERRAIN_HILL, t)
			_terrain_image.set_pixel(x, y, color)

	_terrain_texture = ImageTexture.create_from_image(_terrain_image)
	_needs_terrain_update = false


func _create_flat_terrain_texture():
	_terrain_image = Image.create(4, 4, false, Image.FORMAT_RGB8)
	_terrain_image.fill(COLOR_TERRAIN)
	_terrain_texture = ImageTexture.create_from_image(_terrain_image)
	_needs_terrain_update = false


func _draw():
	# Draw background
	draw_rect(Rect2(Vector2.ZERO, minimap_size), Color(0.1, 0.08, 0.06, 1.0))

	# Draw terrain texture
	if _terrain_texture:
		draw_texture_rect(_terrain_texture, Rect2(Vector2.ZERO, minimap_size), false)

	# Draw deployment zone during deployment
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		var deploy_rect: Rect2 = Rect2(
			Vector2(0, minimap_size.y / 2),
			Vector2(minimap_size.x, minimap_size.y / 2)
		)
		draw_rect(deploy_rect, COLOR_DEPLOYMENT_ZONE)

	# Draw units
	_draw_units()

	# Draw camera viewport
	_draw_viewport()

	# Draw border
	draw_rect(Rect2(Vector2.ZERO, minimap_size), Color(0.6, 0.5, 0.3, 1.0), false, 2.0)


func _draw_units():
	# Draw enemy units first
	for regiment in get_tree().get_nodes_in_group("enemy_regiments"):
		if regiment is Regiment and regiment.state != Regiment.State.DEAD:
			var pos: Vector2 = _world_to_minimap(regiment.global_position)
			# Draw with outline for visibility
			draw_circle(pos, 6.0, Color(0.0, 0.0, 0.0, 0.5))  # Shadow
			draw_circle(pos, 5.0, COLOR_ENEMY)

	# Draw player units on top
	var selected: Array = []
	if SelectionManager:
		selected = SelectionManager.selected_regiments

	for regiment in get_tree().get_nodes_in_group("player_regiments"):
		if regiment is Regiment and regiment.state != Regiment.State.DEAD:
			var pos: Vector2 = _world_to_minimap(regiment.global_position)
			var color: Color = COLOR_SELECTED if regiment in selected else COLOR_PLAYER
			# Draw with outline for visibility
			draw_circle(pos, 6.0, Color(0.0, 0.0, 0.0, 0.5))  # Shadow
			draw_circle(pos, 5.0, color)


func _draw_viewport():
	if not _camera:
		return

	# Calculate camera frustum on ground plane
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	# Get corners of the visible area on ground
	var corners: Array[Vector2] = []
	for screen_pos in [Vector2(0, 0), Vector2(viewport_size.x, 0),
					   Vector2(viewport_size.x, viewport_size.y), Vector2(0, viewport_size.y)]:
		var world_pos: Vector3 = _screen_to_ground(screen_pos)
		if world_pos != Vector3.INF:
			corners.append(_world_to_minimap(world_pos))

	if corners.size() >= 4:
		# Draw viewport rectangle
		var packed_corners: PackedVector2Array = PackedVector2Array(corners)
		packed_corners.append(corners[0])  # Close the shape
		draw_polyline(packed_corners, COLOR_VIEWPORT, 1.5)


func _world_to_minimap(world_pos: Vector3) -> Vector2:
	var half_x: float = map_size.x / 2.0
	var half_z: float = map_size.y / 2.0

	var normalized_x: float = (world_pos.x + half_x) / map_size.x
	var normalized_z: float = (world_pos.z + half_z) / map_size.y

	return Vector2(
		clampf(normalized_x * minimap_size.x, 0, minimap_size.x),
		clampf(normalized_z * minimap_size.y, 0, minimap_size.y)
	)


func _minimap_to_world(minimap_pos: Vector2) -> Vector3:
	var half_x: float = map_size.x / 2.0
	var half_z: float = map_size.y / 2.0

	var normalized_x: float = minimap_pos.x / minimap_size.x
	var normalized_z: float = minimap_pos.y / minimap_size.y

	var world_x: float = normalized_x * map_size.x - half_x
	var world_z: float = normalized_z * map_size.y - half_z

	return Vector3(world_x, 0, world_z)


func _screen_to_ground(screen_pos: Vector2) -> Vector3:
	if not _camera:
		return Vector3.INF

	var ray_origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = _camera.project_ray_normal(screen_pos)

	# Intersect with y=0 plane
	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# Move camera to clicked position
			var world_pos: Vector3 = _minimap_to_world(event.position)
			_move_camera_to(world_pos)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# Move selected units to clicked position
			var world_pos: Vector3 = _minimap_to_world(event.position)
			_move_units_to(world_pos)


func _move_camera_to(world_pos: Vector3):
	if not _camera:
		return

	# If using RTSCamera, move the parent
	var camera_parent: Node3D = _camera.get_parent()
	if camera_parent:
		camera_parent.global_position.x = world_pos.x
		camera_parent.global_position.z = world_pos.z


func _move_units_to(world_pos: Vector3):
	if not SelectionManager or SelectionManager.selected_regiments.is_empty():
		return

	for regiment in SelectionManager.selected_regiments:
		if is_instance_valid(regiment):
			regiment.give_order(OrderType.Type.MOVE, world_pos)


func _process(_delta):
	# Redraw every frame for unit movement
	queue_redraw()

	# Update camera reference
	if not _camera:
		_camera = get_viewport().get_camera_3d()
