# Terrain system for Blender-exported battle maps
# Compatible with existing BattleTerrain and TerrainCombatModifiers
class_name BlenderMapTerrain
extends Node3D

## Path to the terrain GLB file
@export_file("*.glb") var terrain_glb_path: String = ""
## Path to terrain metadata JSON (optional)
@export_file("*.json") var metadata_path: String = ""
## Terrain size (should match Blender export)
@export var terrain_size: Vector2 = Vector2(600, 600)

var mesh_instance: MeshInstance3D
var static_body: StaticBody3D
var collision_shape: CollisionShape3D
var nav_region: NavigationRegion3D
var terrain_mesh: Mesh

# Cached raycast for height queries
var _space_state: PhysicsDirectSpaceState3D

# Metadata from JSON
var mud_zones: Array = []
var rock_data: Array = []


func _ready():
	add_to_group("terrain")
	_load_terrain()
	_load_metadata()

	# Wait for physics space to be ready
	await get_tree().process_frame
	_space_state = get_world_3d().direct_space_state


func _load_terrain():
	if terrain_glb_path.is_empty():
		push_error("BlenderMapTerrain: No terrain GLB path specified")
		return

	if not ResourceLoader.exists(terrain_glb_path):
		push_error("BlenderMapTerrain: Terrain file not found: " + terrain_glb_path)
		return

	var scene = load(terrain_glb_path) as PackedScene
	if not scene:
		push_error("BlenderMapTerrain: Failed to load terrain scene")
		return

	var terrain_root = scene.instantiate()
	add_child(terrain_root)

	# Find the mesh instance in the loaded scene
	_find_and_setup_mesh(terrain_root)

	# Setup collision from mesh
	_setup_collision()

	# Setup navigation
	_setup_navigation()


func _find_and_setup_mesh(node: Node):
	if node is MeshInstance3D:
		mesh_instance = node as MeshInstance3D
		terrain_mesh = mesh_instance.mesh
		return

	for child in node.get_children():
		_find_and_setup_mesh(child)
		if mesh_instance:
			return


func _setup_collision():
	if not terrain_mesh:
		push_error("BlenderMapTerrain: No mesh found for collision")
		return

	# Create StaticBody3D for terrain collision
	static_body = StaticBody3D.new()
	static_body.collision_layer = 1  # Terrain layer
	static_body.collision_mask = 0   # Terrain doesn't need to detect anything
	add_child(static_body)

	# Create trimesh collision from the terrain mesh
	collision_shape = CollisionShape3D.new()
	var shape = terrain_mesh.create_trimesh_shape()
	collision_shape.shape = shape
	static_body.add_child(collision_shape)


func _setup_navigation():
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)

	var nav_mesh = NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 1.0
	nav_mesh.cell_height = 0.5
	nav_mesh.agent_height = 3.0
	nav_mesh.agent_radius = 5.0
	nav_mesh.agent_max_climb = 2.0
	nav_mesh.agent_max_slope = 45.0
	# Filter bounds for 600x600 map with margin
	nav_mesh.filter_baking_aabb = AABB(
		Vector3(-350, -50, -350),
		Vector3(700, 100, 700)
	)

	nav_region.navigation_mesh = nav_mesh
	call_deferred("_bake_navigation")


func _bake_navigation():
	nav_region.bake_navigation_mesh()
	# Phase 4B: Wait for nav mesh bake completion before combat starts
	await nav_region.bake_finished
	print("[TERRAIN] Navigation mesh baked successfully")


func rebake_navigation() -> void:
	if nav_region and nav_region.navigation_mesh:
		nav_region.bake_navigation_mesh()


func _load_metadata():
	if metadata_path.is_empty():
		return

	if not FileAccess.file_exists(metadata_path):
		push_warning("BlenderMapTerrain: Metadata file not found: " + metadata_path)
		return

	var file = FileAccess.open(metadata_path, FileAccess.READ)
	if not file:
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_warning("BlenderMapTerrain: Failed to parse metadata JSON")
		return

	var data = json.data
	if data.has("mud_zones"):
		mud_zones = data.mud_zones
	if data.has("rock_clusters"):
		rock_data = data.rock_clusters


## Get height at world position using raycast
func get_height_at(world_pos: Vector3) -> float:
	if not _space_state:
		_space_state = get_world_3d().direct_space_state
		if not _space_state:
			return 0.0

	# Raycast from above the terrain down
	var query = PhysicsRayQueryParameters3D.create(
		Vector3(world_pos.x, 100.0, world_pos.z),
		Vector3(world_pos.x, -50.0, world_pos.z)
	)
	query.collision_mask = 1  # Terrain layer only

	var result = _space_state.intersect_ray(query)
	if result:
		return result.position.y

	return 0.0


## Returns slope angle in degrees at position
func get_slope_at(world_pos: Vector3) -> float:
	var sample_dist: float = 2.0
	var h_center: float = get_height_at(world_pos)
	var h_forward: float = get_height_at(world_pos + Vector3(0, 0, sample_dist))
	var h_right: float = get_height_at(world_pos + Vector3(sample_dist, 0, 0))
	var slope_z: float = (h_forward - h_center) / sample_dist
	var slope_x: float = (h_right - h_center) / sample_dist
	return rad_to_deg(atan(maxf(absf(slope_z), absf(slope_x))))


## Returns the uphill direction at position (normalized)
func get_height_direction_at(world_pos: Vector3) -> Vector3:
	var sample_dist: float = 2.0
	var h_forward: float = get_height_at(world_pos + Vector3(0, 0, sample_dist))
	var h_back: float = get_height_at(world_pos + Vector3(0, 0, -sample_dist))
	var h_right: float = get_height_at(world_pos + Vector3(sample_dist, 0, 0))
	var h_left: float = get_height_at(world_pos + Vector3(-sample_dist, 0, 0))
	var dir: Vector3 = Vector3(h_left - h_right, 0, h_back - h_forward)
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()


## Check if position is in a mud zone
func is_in_mud_zone(world_pos: Vector3) -> bool:
	for zone in mud_zones:
		var zone_pos = Vector3(zone.position[0], 0, zone.position[1])
		var flat_pos = Vector3(world_pos.x, 0, world_pos.z)
		if flat_pos.distance_to(zone_pos) <= zone.radius:
			return true
	return false


## Get all mud zone Area3D nodes (create if needed)
func get_mud_zone_areas() -> Array[Area3D]:
	var areas: Array[Area3D] = []
	for child in get_children():
		if child is Area3D and child.name.begins_with("MudZone"):
			areas.append(child)
	return areas


## Create Area3D nodes for mud zones (call after terrain is ready)
func create_mud_zone_areas() -> void:
	for i in range(mud_zones.size()):
		var zone = mud_zones[i]
		var area = Area3D.new()
		area.name = "MudZone_%d" % i

		var collision = CollisionShape3D.new()
		var shape = CylinderShape3D.new()
		shape.radius = zone.radius
		shape.height = 10.0  # Tall enough to catch all units
		collision.shape = shape
		area.add_child(collision)

		# Position at zone center, at ground level
		var height = get_height_at(Vector3(zone.position[0], 0, zone.position[1]))
		area.position = Vector3(zone.position[0], height + 5.0, zone.position[1])

		# Add to mud zone group for TerrainCombatModifiers
		area.add_to_group("mud_zones")

		add_child(area)
