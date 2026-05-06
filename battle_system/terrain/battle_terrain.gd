# Battle Terrain - combines procedural terrain with prop/building spawning
# Uses assets from Catacombs of Gore project
class_name BattleTerrain
extends Node3D

const DaggerfallTerrainScript = preload("res://battle_system/terrain/daggerfall_terrain.gd")

@export var terrain_size: Vector2 = Vector2(200, 200)
@export var terrain_resolution: int = 64
@export var height_scale: float = 12.0
@export var tree_count: int = 30
@export var building_count: int = 5
@export var prop_count: int = 20
@export var rock_count: int = 15
@export var bush_count: int = 25
@export var spawn_seed: int = -1  # -1 for random

var terrain: Node3D  # DaggerfallTerrain instance
var spawned_objects: Array[Node3D] = []
var cover_objects: Array[Node3D] = []  # Tracked for cover system

# Unit spawn exclusion zones - buildings won't spawn here
var unit_exclusion_zones: Array[Vector3] = [
	Vector3(-15, 0, 10),   # Player spawn area
	Vector3(15, 0, -10),   # Enemy spawn area
]
const UNIT_EXCLUSION_RADIUS: float = 20.0  # Keep buildings away from unit spawns

# Asset paths (local to project)
const ASSETS_PATH = "res://assets/models/"

const TREE_MODELS = [
	"props/kenney_tree_large.glb",
	"props/kenney_tree_shrub.glb",
]

const BUILDING_MODELS = [
	"buildings/cottage.glb",
	"buildings/house_small.glb",
	"buildings/house_medium.glb",
	"buildings/farm.glb",
	"buildings/shop.glb",
	"buildings/blacksmith.glb",
	"buildings/windmill.glb",
	"buildings/guard_tower.glb",
	"buildings/wooden_outpost_tower.glb",
]

const PROP_MODELS = [
	"props/kenney_detail_barrel.glb",
	"props/kenney_detail_crate.glb",
	"props/kenney_fence.glb",
	"props/kenney_fence_wood.glb",
	"props/barrel.glb",
	"props/crate.glb",
]


func _ready():
	if spawn_seed >= 0:
		seed(spawn_seed)
	else:
		randomize()

	_create_terrain()
	_create_boundary_walls()

	# Configure AI map bounds based on terrain size
	if AIAutoload:
		AIAutoload.set_map_bounds(terrain_size, 10.0)  # 10 unit margin from edge

	# Wait for terrain to generate before spawning objects
	await get_tree().create_timer(0.5).timeout
	_spawn_objects()


func _create_terrain():
	var terrain_node = Node3D.new()
	terrain_node.set_script(DaggerfallTerrainScript)
	terrain_node.terrain_size = terrain_size
	terrain_node.terrain_resolution = terrain_resolution
	terrain_node.height_scale = height_scale
	add_child(terrain_node)
	terrain = terrain_node


func _create_boundary_walls():
	## Create invisible collision walls around the map perimeter to prevent units from leaving
	var map_half_x = terrain_size.x / 2.0
	var map_half_z = terrain_size.y / 2.0
	var wall_height = 50.0
	var wall_thickness = 2.0

	# Wall definitions: position and size for each wall
	# North wall (negative Z edge)
	# South wall (positive Z edge)
	# West wall (negative X edge)
	# East wall (positive X edge)
	var walls = [
		{"pos": Vector3(0, wall_height / 2.0, -map_half_z - wall_thickness / 2.0),
		 "size": Vector3(terrain_size.x + wall_thickness * 2, wall_height, wall_thickness)},  # North
		{"pos": Vector3(0, wall_height / 2.0, map_half_z + wall_thickness / 2.0),
		 "size": Vector3(terrain_size.x + wall_thickness * 2, wall_height, wall_thickness)},  # South
		{"pos": Vector3(-map_half_x - wall_thickness / 2.0, wall_height / 2.0, 0),
		 "size": Vector3(wall_thickness, wall_height, terrain_size.y + wall_thickness * 2)},  # West
		{"pos": Vector3(map_half_x + wall_thickness / 2.0, wall_height / 2.0, 0),
		 "size": Vector3(wall_thickness, wall_height, terrain_size.y + wall_thickness * 2)},  # East
	]

	for wall_data in walls:
		var wall = StaticBody3D.new()
		wall.name = "BoundaryWall"
		var collision = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape.size = wall_data.size
		collision.shape = shape
		wall.add_child(collision)
		wall.position = wall_data.pos
		wall.collision_layer = 1  # Terrain layer
		wall.collision_mask = 0   # Walls don't need to detect anything
		add_child(wall)


func _spawn_objects():
	_spawn_trees()
	_spawn_buildings()
	_spawn_props()
	_spawn_rocks()
	_spawn_bushes()


func _spawn_trees():
	for i in range(tree_count):
		var model_path = ASSETS_PATH + TREE_MODELS[randi() % TREE_MODELS.size()]
		var pos = _get_random_terrain_position()
		var tree = _spawn_model(model_path, pos, randf_range(0.8, 1.5))
		if tree:
			# Add cover component to tree
			_add_cover_to_object(tree, CoverObject.CoverType.MEDIUM, 4.0, true)


func _spawn_buildings():
	var building_positions: Array[Vector3] = []
	var min_building_distance = 25.0

	for i in range(building_count):
		var attempts = 0
		var pos = Vector3.ZERO
		var valid = false

		while not valid and attempts < 50:
			pos = _get_random_terrain_position()
			valid = true

			# Check distance from other buildings
			for other_pos in building_positions:
				if pos.distance_to(other_pos) < min_building_distance:
					valid = false
					break

			# Avoid unit spawn zones - don't place buildings on top of units
			if valid:
				for exclusion_pos in unit_exclusion_zones:
					var flat_pos = Vector3(pos.x, 0, pos.z)
					var flat_exclusion = Vector3(exclusion_pos.x, 0, exclusion_pos.z)
					if flat_pos.distance_to(flat_exclusion) < UNIT_EXCLUSION_RADIUS:
						valid = false
						break

			# Avoid steep slopes
			if valid and terrain:
				var slope = _get_terrain_slope(pos)
				if slope > 0.3:
					valid = false

			attempts += 1

		if valid:
			building_positions.append(pos)
			var model_path = ASSETS_PATH + BUILDING_MODELS[randi() % BUILDING_MODELS.size()]
			_spawn_model(model_path, pos, randf_range(0.8, 1.2), true)


func _spawn_props():
	for i in range(prop_count):
		var model_path = ASSETS_PATH + PROP_MODELS[randi() % PROP_MODELS.size()]
		var pos = _get_random_terrain_position()
		_spawn_model(model_path, pos, randf_range(0.7, 1.3))


func _get_random_terrain_position() -> Vector3:
	var margin = 20.0
	var x = randf_range(-terrain_size.x / 2 + margin, terrain_size.x / 2 - margin)
	var z = randf_range(-terrain_size.y / 2 + margin, terrain_size.y / 2 - margin)
	var y = 0.0

	if terrain:
		y = terrain.get_height_at(Vector3(x, 0, z))

	return Vector3(x, y, z)


func _get_terrain_slope(pos: Vector3) -> float:
	if not terrain:
		return 0.0

	var sample_dist = 2.0
	var h_center = terrain.get_height_at(pos)
	var h_left = terrain.get_height_at(pos + Vector3(-sample_dist, 0, 0))
	var h_right = terrain.get_height_at(pos + Vector3(sample_dist, 0, 0))
	var h_front = terrain.get_height_at(pos + Vector3(0, 0, -sample_dist))
	var h_back = terrain.get_height_at(pos + Vector3(0, 0, sample_dist))

	var slope_x = abs(h_right - h_left) / (sample_dist * 2)
	var slope_z = abs(h_back - h_front) / (sample_dist * 2)

	return max(slope_x, slope_z)


func _spawn_model(path: String, pos: Vector3, scale_factor: float = 1.0, _is_building: bool = false) -> Node3D:
	# Check if resource exists
	if not ResourceLoader.exists(path):
		push_warning("Model not found: " + path)
		return null

	# Load the GLB as a PackedScene (Godot imports .glb as scenes)
	var packed_scene = load(path) as PackedScene
	if not packed_scene:
		push_warning("Could not load model: " + path)
		return null

	var scene = packed_scene.instantiate()
	if not scene:
		push_warning("Failed to instantiate scene from: " + path)
		return null

	# Scale first
	scene.scale = Vector3.ONE * scale_factor
	scene.rotation.y = randf() * TAU  # Random rotation

	# Hide any collision shapes that came with the model
	_hide_collision_shapes(scene)

	# Add to tree temporarily to calculate AABB
	add_child(scene)

	# Calculate model's bounding box to fix floating objects
	var aabb = _get_combined_aabb(scene)
	var bottom_offset = aabb.position.y * scale_factor  # Bottom of model relative to origin

	# Adjust position so bottom of model sits on terrain
	scene.position = Vector3(pos.x, pos.y - bottom_offset, pos.z)

	spawned_objects.append(scene)
	return scene


func _get_combined_aabb(node: Node) -> AABB:
	var combined_aabb = AABB()
	var first = true

	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			if mesh_inst.mesh:
				var child_aabb = mesh_inst.mesh.get_aabb()
				# Transform to parent space
				child_aabb = Transform3D(Basis(), mesh_inst.position) * child_aabb
				if first:
					combined_aabb = child_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(child_aabb)

		# Recurse into children
		var child_combined = _get_combined_aabb(child)
		if child_combined.size != Vector3.ZERO:
			if first:
				combined_aabb = child_combined
				first = false
			else:
				combined_aabb = combined_aabb.merge(child_combined)

	return combined_aabb


func _add_cover_to_object(obj: Node3D, cover_type: CoverObject.CoverType, radius: float, blocks_los: bool):
	# Create a CoverObject as a child so it tracks with the visual
	var cover = CoverObject.new()
	cover.cover_type = cover_type
	cover.cover_radius = radius
	cover.blocks_line_of_sight = blocks_los
	obj.add_child(cover)
	cover_objects.append(cover)


func _hide_collision_shapes(node: Node):
	# Remove or hide collision shapes and static bodies that came with GLB imports
	var to_remove: Array[Node] = []

	for child in node.get_children():
		# Remove collision-related nodes that might be visible
		if child is CollisionShape3D or child is CollisionPolygon3D:
			to_remove.append(child)
		elif child is StaticBody3D or child is RigidBody3D or child is CharacterBody3D:
			to_remove.append(child)
		# Also check for mesh instances that might be collision visualizations
		elif child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			# Hide meshes that look like collision boxes (small, white, or named "collision")
			if mesh_inst.name.to_lower().contains("collision") or mesh_inst.name.to_lower().contains("col_"):
				mesh_inst.visible = false

		# Recurse into children
		if child.get_child_count() > 0:
			_hide_collision_shapes(child)

	# Remove collected nodes
	for n in to_remove:
		n.queue_free()


func _spawn_rocks():
	for i in range(rock_count):
		var pos = _get_random_terrain_position()
		var size = randf_range(1.0, 3.0)
		var rock = CoverObject.spawn_rock(self, pos, size)
		cover_objects.append(rock)
		spawned_objects.append(rock)


func _spawn_bushes():
	for i in range(bush_count):
		var pos = _get_random_terrain_position()
		var bush = CoverObject.spawn_bush(self, pos)
		cover_objects.append(bush)
		spawned_objects.append(bush)


func get_cover_objects() -> Array[Node3D]:
	return cover_objects


func regenerate():
	# Clear existing spawned objects
	for obj in spawned_objects:
		if is_instance_valid(obj):
			obj.queue_free()
	spawned_objects.clear()
	cover_objects.clear()

	# Regenerate terrain
	if terrain:
		terrain.regenerate()

	# Wait then respawn objects
	await get_tree().create_timer(0.5).timeout
	_spawn_objects()
