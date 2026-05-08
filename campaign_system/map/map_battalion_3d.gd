# Player battalion token on the 3D campaign map.
# Handles selection, movement, and visual representation in 3D space.
extends Node3D


signal selected(battalion: Node3D)
signal deselected()
signal move_completed(new_position: Vector3)

@export var battalion_data: Resource  # BattalionData

# Visual components
var army_sprite: Sprite3D
var base_mesh: MeshInstance3D
var selection_ring: MeshInstance3D
var banner_label: Label3D
var hover_highlight: MeshInstance3D

# Army banner texture
const PLAYER_BANNER_PATH := "res://assets/icons/army_banner_player.png"

# Movement
var target_position: Vector3 = Vector3.ZERO
var is_moving: bool = false
var move_speed: float = 20.0  # World units per second

# Selection
var is_selected: bool = false
var is_hovered: bool = false

# Reference to terrain for height queries
var campaign_terrain: Node3D = null

# Colors
const COLOR_SELECTED := Color(0.85, 0.7, 0.4, 1.0)
const COLOR_HOVER := Color(0.6, 0.5, 0.3, 0.8)
const COLOR_PLAYER := Color(0.2, 0.5, 0.8)
const COLOR_ENEMY := Color(0.8, 0.2, 0.2)

# Scale from pixels to world units
const PIXELS_TO_UNITS: float = 0.1


func _ready() -> void:
	# Find terrain for height queries
	campaign_terrain = get_tree().get_first_node_in_group("campaign_terrain")

	# Create visual representation
	_create_visuals()

	# Initialize from battalion data
	if battalion_data:
		var pixel_pos: Vector2 = battalion_data.map_position
		position = Vector3(
			pixel_pos.x * PIXELS_TO_UNITS,
			0,
			pixel_pos.y * PIXELS_TO_UNITS
		)
		_snap_to_terrain()
		_update_display()


func _create_visuals() -> void:
	## Create the 3D visual representation of the battalion

	# Army billboard sprite (main visual)
	army_sprite = Sprite3D.new()
	var banner_tex := _load_banner_texture()
	if banner_tex:
		army_sprite.texture = banner_tex
		# Scale sprite to ~10 world units tall (prominent on map)
		# pixel_size determines how big each pixel appears in world units
		army_sprite.pixel_size = 0.04  # Adjust based on texture size
	army_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	army_sprite.transparent = true
	army_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	army_sprite.position.y = 2.5  # Position near terrain
	army_sprite.no_depth_test = false
	army_sprite.render_priority = 1
	add_child(army_sprite)

	# Small ground shadow/marker
	base_mesh = MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 2.5
	base.bottom_radius = 3.0
	base.height = 0.3
	base_mesh.mesh = base
	base_mesh.position.y = 0.15

	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.1, 0.08, 0.05, 0.7)
	base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base_mesh.material_override = base_mat
	add_child(base_mesh)

	# Selection ring (hidden by default)
	selection_ring = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 3.5
	ring.outer_radius = 4.2
	selection_ring.mesh = ring
	selection_ring.rotation.x = -PI / 2  # Lay flat
	selection_ring.position.y = 0.2

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = COLOR_SELECTED
	ring_mat.emission_enabled = true
	ring_mat.emission = COLOR_SELECTED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	selection_ring.material_override = ring_mat
	selection_ring.visible = false
	add_child(selection_ring)

	# Hover highlight (hidden by default)
	hover_highlight = MeshInstance3D.new()
	var hover_ring := TorusMesh.new()
	hover_ring.inner_radius = 3.2
	hover_ring.outer_radius = 3.8
	hover_highlight.mesh = hover_ring
	hover_highlight.rotation.x = -PI / 2
	hover_highlight.position.y = 0.2

	var hover_mat := StandardMaterial3D.new()
	hover_mat.albedo_color = COLOR_HOVER
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_highlight.material_override = hover_mat
	hover_highlight.visible = false
	add_child(hover_highlight)

	# Name label (above the sprite)
	banner_label = Label3D.new()
	banner_label.text = "Battalion"
	banner_label.position.y = 8.0  # Above the sprite
	banner_label.font_size = 64
	banner_label.outline_size = 8
	banner_label.modulate = Color(1.0, 0.95, 0.85)
	banner_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(banner_label)

	# Create click detection area (larger for billboard)
	var click_area := Area3D.new()
	click_area.name = "ClickArea"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 10.0, 6.0)  # Box around sprite
	collision.shape = shape
	collision.position.y = 5.0
	click_area.add_child(collision)
	click_area.input_ray_pickable = true
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	add_child(click_area)


func _process(delta: float) -> void:
	if is_moving:
		var direction := (target_position - position)
		direction.y = 0  # Keep movement horizontal
		var distance := direction.length()

		if distance < 0.5:
			position = Vector3(target_position.x, position.y, target_position.z)
			_snap_to_terrain()
			is_moving = false

			# Update battalion data
			if battalion_data:
				battalion_data.map_position = Vector2(
					position.x / PIXELS_TO_UNITS,
					position.z / PIXELS_TO_UNITS
				)

			move_completed.emit(position)
			CampaignSignals.battalion_moved.emit(self, battalion_data.map_position)
		else:
			var move_dir := direction.normalized()
			position += move_dir * move_speed * delta
			_snap_to_terrain()

	# Subtle bob animation for the army sprite
	if army_sprite:
		army_sprite.position.y = 2.5 + sin(Time.get_ticks_msec() * 0.002) * 0.2


func _snap_to_terrain() -> void:
	## Snap position to terrain height
	if campaign_terrain and campaign_terrain.has_method("get_height_at"):
		position.y = campaign_terrain.get_height_at(position) + 0.1


func _update_display() -> void:
	if banner_label and battalion_data:
		banner_label.text = battalion_data.battalion_name

	# Tint selection ring based on battalion color
	if battalion_data and selection_ring:
		var color: Color = battalion_data.battalion_color if "battalion_color" in battalion_data else COLOR_PLAYER
		var ring_mat := selection_ring.material_override as StandardMaterial3D
		if ring_mat:
			ring_mat.albedo_color = color
			ring_mat.emission = color


func select() -> void:
	is_selected = true
	if selection_ring:
		selection_ring.visible = true
	if hover_highlight:
		hover_highlight.visible = false
	selected.emit(self)
	CampaignSignals.battalion_selected.emit(self)


func deselect() -> void:
	is_selected = false
	if selection_ring:
		selection_ring.visible = false
	deselected.emit()
	CampaignSignals.battalion_deselected.emit()


func move_to(target_pixel_pos: Vector2) -> void:
	## Move to target position (in pixel coordinates)
	var world_target := Vector3(
		target_pixel_pos.x * PIXELS_TO_UNITS,
		0,
		target_pixel_pos.y * PIXELS_TO_UNITS
	)

	var distance := Vector2(position.x, position.z).distance_to(Vector2(world_target.x, world_target.z))
	var pixel_distance := distance / PIXELS_TO_UNITS

	# Check movement points
	if battalion_data and not battalion_data.can_move(pixel_distance * 0.1):
		return

	target_position = world_target
	is_moving = true

	# Deduct movement points
	if battalion_data:
		battalion_data.spend_movement(pixel_distance * 0.1)
		CampaignSignals.movement_points_changed.emit(self, battalion_data.movement_points)

	CampaignSignals.battalion_move_requested.emit(self, target_pixel_pos)


func _on_mouse_entered() -> void:
	is_hovered = true
	if not is_selected and hover_highlight:
		hover_highlight.visible = true


func _on_mouse_exited() -> void:
	is_hovered = false
	if not is_selected and hover_highlight:
		hover_highlight.visible = false


func get_regiment_count() -> int:
	if battalion_data:
		return battalion_data.regiments.size()
	return 0


func get_soldier_count() -> int:
	if battalion_data:
		return battalion_data.get_total_soldiers()
	return 0


func get_pixel_position() -> Vector2:
	## Get position in original pixel coordinates
	return Vector2(position.x / PIXELS_TO_UNITS, position.z / PIXELS_TO_UNITS)


func _load_banner_texture() -> ImageTexture:
	## Load banner texture at runtime (bypasses import system)
	# Try resource path first (if imported)
	if ResourceLoader.exists(PLAYER_BANNER_PATH):
		var tex := load(PLAYER_BANNER_PATH)
		if tex is Texture2D:
			return tex as ImageTexture

	# Fall back to loading from absolute path
	var abs_path := ProjectSettings.globalize_path(PLAYER_BANNER_PATH)
	if FileAccess.file_exists(abs_path):
		var image := Image.new()
		var err := image.load(abs_path)
		if err == OK:
			var texture := ImageTexture.create_from_image(image)
			return texture

	# Return null if texture couldn't be loaded
	push_warning("[MapBattalion3D] Could not load banner texture: " + PLAYER_BANNER_PATH)
	return null
