# Battle Terrain using Blender-exported maps
# Drop-in replacement for BattleTerrain that uses pre-made maps
class_name BlenderBattleTerrain
extends Node3D

const BlenderMapTerrainScript = preload("res://battle_system/terrain/blender_map_terrain.gd")

## Path to the complete battle map scene (.tscn with terrain + rocks)
@export_file("*.tscn") var map_scene_path: String = "res://assets/maps/battle_map_01.tscn"

@export var terrain_size: Vector2 = Vector2(600, 600)
@export var tree_count: int = 30
@export var building_count: int = 5
@export var prop_count: int = 20
@export var bush_count: int = 25
@export var spawn_seed: int = -1

var terrain: Node3D  # BlenderMapTerrain instance
var map_root: Node3D  # The loaded map scene
var spawned_objects: Array[Node3D] = []
var cover_objects: Array[Node3D] = []

# Unit spawn exclusion zones
var unit_exclusion_zones: Array[Vector3] = [
	Vector3(-15, 0, 10),
	Vector3(15, 0, -10),
]
const UNIT_EXCLUSION_RADIUS: float = 20.0

# Asset paths
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

	_load_map()
	_create_boundary_walls()

	# Configure AI map bounds
	if AIAutoload:
		AIAutoload.set_map_bounds(terrain_size, 10.0)

	# Wait for terrain to load before spawning objects
	await get_tree().create_timer(0.5).timeout

	# Setup cover from pre-placed rocks in the map
	_setup_rock_cover()

	# Spawn additional objects
	_spawn_objects()


func _load_map():
	if not ResourceLoader.exists(map_scene_path):
		push_error("BlenderBattleTerrain: Map scene not found: " + map_scene_path)
		return

	var map_scene = load(map_scene_path) as PackedScene
	if not map_scene:
		push_error("BlenderBattleTerrain: Failed to load map scene")
		return

	map_root = map_scene.instantiate()
	add_child(map_root)

	# Find the terrain node
	for child in map_root.get_children():
		if child.has_method("get_height_at"):
			terrain = child
			break

	if not terrain:
		push_warning("BlenderBattleTerrain: No terrain node found in map")


func _create_boundary_walls():
	var map_half_x = terrain_size.x / 2.0
	var map_half_z = terrain_size.y / 2.0
	var wall_height = 50.0
	var wall_thickness = 2.0

	var walls = [
		{"pos": Vector3(0, wall_height / 2.0, -map_half_z - wall_thickness / 2.0),
		 "size": Vector3(terrain_size.x + wall_thickness * 2, wall_height, wall_thickness)},
		{"pos": Vector3(0, wall_height / 2.0, map_half_z + wall_thickness / 2.0),
		 "size": Vector3(terrain_size.x + wall_thickness * 2, wall_height, wall_thickness)},
		{"pos": Vector3(-map_half_x - wall_thickness / 2.0, wall_height / 2.0, 0),
		 "size": Vector3(wall_thickness, wall_height, terrain_size.y + wall_thickness * 2)},
		{"pos": Vector3(map_half_x + wall_thickness / 2.0, wall_height / 2.0, 0),
		 "size": Vector3(wall_thickness, wall_height, terrain_size.y + wall_thickness * 2)},
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
		wall.collision_layer = 1
		wall.collision_mask = 0
		add_child(wall)


func _setup_rock_cover():
	# Find all rock meshes from the imported map and add cover components
	if not map_root:
		return

	var rocks_node = map_root.get_node_or_null("Rocks")
	if not rocks_node:
		return

	_add_cover_to_rocks(rocks_node)


func _add_cover_to_rocks(node: Node):
	if node is MeshInstance3D:
		var mesh_inst = node as MeshInstance3D
		# Calculate cover radius from mesh size
		if mesh_inst.mesh:
			var aabb = mesh_inst.mesh.get_aabb()
			var size = max(aabb.size.x, aabb.size.z)
			var cover_type = CoverObject.CoverType.LIGHT if size < 2 else CoverObject.CoverType.MEDIUM

			var cover = CoverObject.new()
			cover.cover_type = cover_type
			cover.cover_radius = size
			cover.blocks_line_of_sight = cover_type == CoverObject.CoverType.MEDIUM
			mesh_inst.add_child(cover)
			cover_objects.append(cover)

	for child in node.get_children():
		_add_cover_to_rocks(child)


func _spawn_objects():
	_spawn_trees()
	_spawn_buildings()
	_spawn_props()
	_spawn_bushes()

	# Rebake navigation to include spawned buildings
	if terrain and terrain.has_method("rebake_navigation"):
		await get_tree().process_frame
		terrain.rebake_navigation()


func _spawn_trees():
	for i in range(tree_count):
		var model_path = ASSETS_PATH + TREE_MODELS[randi() % TREE_MODELS.size()]
		var pos = _get_random_terrain_position()
		var tree = _spawn_model(model_path, pos, randf_range(0.8, 1.5))
		if tree:
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

			for other_pos in building_positions:
				if pos.distance_to(other_pos) < min_building_distance:
					valid = false
					break

			if valid:
				for exclusion_pos in unit_exclusion_zones:
					var flat_pos = Vector3(pos.x, 0, pos.z)
					var flat_exclusion = Vector3(exclusion_pos.x, 0, exclusion_pos.z)
					if flat_pos.distance_to(flat_exclusion) < UNIT_EXCLUSION_RADIUS:
						valid = false
						break

			if valid and terrain and terrain.has_method("get_slope_at"):
				var slope = terrain.get_slope_at(pos)
				if slope > 15.0:  # Avoid steep slopes for buildings
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


func _spawn_bushes():
	for i in range(bush_count):
		var pos = _get_random_terrain_position()
		var bush = CoverObject.spawn_bush(self, pos)
		cover_objects.append(bush)
		spawned_objects.append(bush)


func _get_random_terrain_position() -> Vector3:
	var margin = 20.0
	var x = randf_range(-terrain_size.x / 2 + margin, terrain_size.x / 2 - margin)
	var z = randf_range(-terrain_size.y / 2 + margin, terrain_size.y / 2 - margin)
	var y = 0.0

	if terrain and terrain.has_method("get_height_at"):
		y = terrain.get_height_at(Vector3(x, 0, z))

	return Vector3(x, y, z)


func _spawn_model(path: String, pos: Vector3, scale_factor: float = 1.0, is_building: bool = false) -> Node3D:
	if not ResourceLoader.exists(path):
		return null

	var packed_scene = load(path) as PackedScene
	if not packed_scene:
		return null

	var scene = packed_scene.instantiate()
	if not scene:
		return null

	scene.scale = Vector3.ONE * scale_factor
	scene.rotation.y = randf() * TAU

	_hide_collision_shapes(scene)

	if is_building:
		_add_to_navigation_group(scene)

	add_child(scene)

	var aabb = _get_combined_aabb(scene)
	var bottom_offset = aabb.position.y * scale_factor
	scene.position = Vector3(pos.x, pos.y - bottom_offset, pos.z)

	spawned_objects.append(scene)
	return scene


func _add_to_navigation_group(node: Node) -> void:
	if node is StaticBody3D:
		node.add_to_group("navigation_geometry")
	for child in node.get_children():
		_add_to_navigation_group(child)


func _get_combined_aabb(node: Node) -> AABB:
	var combined_aabb = AABB()
	var first = true

	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			if mesh_inst.mesh:
				var child_aabb = mesh_inst.mesh.get_aabb()
				child_aabb = Transform3D(Basis(), mesh_inst.position) * child_aabb
				if first:
					combined_aabb = child_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(child_aabb)

		var child_combined = _get_combined_aabb(child)
		if child_combined.size != Vector3.ZERO:
			if first:
				combined_aabb = child_combined
				first = false
			else:
				combined_aabb = combined_aabb.merge(child_combined)

	return combined_aabb


func _add_cover_to_object(obj: Node3D, cover_type: CoverObject.CoverType, radius: float, blocks_los: bool):
	var cover = CoverObject.new()
	cover.cover_type = cover_type
	cover.cover_radius = radius
	cover.blocks_line_of_sight = blocks_los
	obj.add_child(cover)
	cover_objects.append(cover)


func _hide_collision_shapes(node: Node):
	for child in node.get_children():
		if child is StaticBody3D:
			var body = child as StaticBody3D
			body.collision_layer = 1
			body.collision_mask = 0
		elif child is RigidBody3D or child is CharacterBody3D:
			var body = child as PhysicsBody3D
			body.collision_layer = 1
			body.collision_mask = 0
		elif child is MeshInstance3D:
			var mesh_inst = child as MeshInstance3D
			if mesh_inst.name.to_lower().contains("collision") or mesh_inst.name.to_lower().contains("col_"):
				mesh_inst.visible = false

		if child.get_child_count() > 0:
			_hide_collision_shapes(child)


func get_cover_objects() -> Array[Node3D]:
	return cover_objects


func get_height_at(world_pos: Vector3) -> float:
	if terrain and terrain.has_method("get_height_at"):
		return terrain.get_height_at(world_pos)
	return 0.0


func regenerate():
	# Clear spawned objects
	for obj in spawned_objects:
		if is_instance_valid(obj):
			obj.queue_free()
	spawned_objects.clear()
	cover_objects.clear()

	# Reload map and respawn
	if map_root:
		map_root.queue_free()

	await get_tree().create_timer(0.3).timeout
	_load_map()
	await get_tree().create_timer(0.3).timeout
	_setup_rock_cover()
	_spawn_objects()
