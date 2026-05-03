# Procedural terrain generator inspired by Daggerfall's outdoor terrain
# Generates heightmap-based terrain with hills and valleys for RTS battles
class_name DaggerfallTerrain
extends Node3D


@export var terrain_size: Vector2 = Vector2(200, 200)
@export var terrain_resolution: int = 64  # Vertices per side
@export var height_scale: float = 15.0
@export var noise_scale: float = 0.02
@export var octaves: int = 4
@export var persistence: float = 0.5
@export var lacunarity: float = 2.0

var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var static_body: StaticBody3D
var nav_region: NavigationRegion3D
var noise: FastNoiseLite
var heightmap: Array = []


func _ready():
	add_to_group("terrain")
	_setup_noise()
	_generate_terrain()


func _setup_noise():
	noise = FastNoiseLite.new()
	noise.seed = randi()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = noise_scale
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = persistence
	noise.fractal_lacunarity = lacunarity


func _generate_terrain():
	# Generate heightmap
	_generate_heightmap()

	# Create mesh
	var mesh = _create_terrain_mesh()

	# Setup mesh instance
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh_instance)

	# Setup collision
	_setup_collision(mesh)

	# Setup navigation
	_setup_navigation()

	# Apply material
	_apply_material()


func _generate_heightmap():
	heightmap.clear()
	for z in range(terrain_resolution):
		var row = []
		for x in range(terrain_resolution):
			var world_x = (float(x) / terrain_resolution) * terrain_size.x - terrain_size.x / 2
			var world_z = (float(z) / terrain_resolution) * terrain_size.y - terrain_size.y / 2
			var height = noise.get_noise_2d(world_x, world_z) * height_scale
			row.append(height)
		heightmap.append(row)


func _create_terrain_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cell_size_x = terrain_size.x / (terrain_resolution - 1)
	var cell_size_z = terrain_size.y / (terrain_resolution - 1)

	# Generate vertices and triangles
	for z in range(terrain_resolution - 1):
		for x in range(terrain_resolution - 1):
			var x0 = x * cell_size_x - terrain_size.x / 2
			var x1 = (x + 1) * cell_size_x - terrain_size.x / 2
			var z0 = z * cell_size_z - terrain_size.y / 2
			var z1 = (z + 1) * cell_size_z - terrain_size.y / 2

			var h00 = heightmap[z][x]
			var h10 = heightmap[z][x + 1]
			var h01 = heightmap[z + 1][x]
			var h11 = heightmap[z + 1][x + 1]

			var v0 = Vector3(x0, h00, z0)
			var v1 = Vector3(x1, h10, z0)
			var v2 = Vector3(x0, h01, z1)
			var v3 = Vector3(x1, h11, z1)

			# Calculate normals
			var n1 = (v1 - v0).cross(v2 - v0).normalized()
			var n2 = (v2 - v3).cross(v1 - v3).normalized()

			# Calculate UVs
			var uv0 = Vector2(float(x) / terrain_resolution, float(z) / terrain_resolution)
			var uv1 = Vector2(float(x + 1) / terrain_resolution, float(z) / terrain_resolution)
			var uv2 = Vector2(float(x) / terrain_resolution, float(z + 1) / terrain_resolution)
			var uv3 = Vector2(float(x + 1) / terrain_resolution, float(z + 1) / terrain_resolution)

			# Triangle 1
			st.set_normal(n1)
			st.set_uv(uv0)
			st.add_vertex(v0)
			st.set_uv(uv1)
			st.add_vertex(v1)
			st.set_uv(uv2)
			st.add_vertex(v2)

			# Triangle 2
			st.set_normal(n2)
			st.set_uv(uv1)
			st.add_vertex(v1)
			st.set_uv(uv3)
			st.add_vertex(v3)
			st.set_uv(uv2)
			st.add_vertex(v2)

	st.generate_tangents()
	return st.commit()


func _setup_collision(mesh: ArrayMesh):
	static_body = StaticBody3D.new()
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)

	collision_shape = CollisionShape3D.new()
	var shape = mesh.create_trimesh_shape()
	collision_shape.shape = shape
	static_body.add_child(collision_shape)


func _setup_navigation():
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)

	var nav_mesh = NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 0.5
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_height = 2.0
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_max_climb = 1.0
	nav_mesh.agent_max_slope = 45.0

	nav_region.navigation_mesh = nav_mesh
	# Bake after a frame to ensure collision is ready
	call_deferred("_bake_navigation")


func _bake_navigation():
	nav_region.bake_navigation_mesh()


func _apply_material():
	var material = StandardMaterial3D.new()

	# Try to load grass texture from Catacombs of Gore
	var grass_texture_path = "res://assets/textures/terrain/plains_floor1.png"
	if ResourceLoader.exists(grass_texture_path):
		var grass_tex = load(grass_texture_path) as Texture2D
		if grass_tex:
			material.albedo_texture = grass_tex
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # PS1 style
			material.uv1_scale = Vector3(15, 15, 1)  # Tile the texture
	else:
		# Fallback to solid color
		material.albedo_color = Color(0.3, 0.5, 0.2)

	material.roughness = 0.9
	material.metallic = 0.0

	mesh_instance.material_override = material


# Get height at world position
func get_height_at(world_pos: Vector3) -> float:
	var local_x = (world_pos.x + terrain_size.x / 2) / terrain_size.x * (terrain_resolution - 1)
	var local_z = (world_pos.z + terrain_size.y / 2) / terrain_size.y * (terrain_resolution - 1)

	local_x = clamp(local_x, 0, terrain_resolution - 2)
	local_z = clamp(local_z, 0, terrain_resolution - 2)

	var x0 = int(local_x)
	var z0 = int(local_z)
	var x1 = min(x0 + 1, terrain_resolution - 1)
	var z1 = min(z0 + 1, terrain_resolution - 1)

	var fx = local_x - x0
	var fz = local_z - z0

	# Bilinear interpolation
	var h00 = heightmap[z0][x0]
	var h10 = heightmap[z0][x1]
	var h01 = heightmap[z1][x0]
	var h11 = heightmap[z1][x1]

	var h0 = lerp(h00, h10, fx)
	var h1 = lerp(h01, h11, fx)
	return lerp(h0, h1, fz)


## Returns slope angle in degrees at position
func get_slope_at(world_pos: Vector3) -> float:
	var sample_dist: float = 1.0
	var h_center: float = get_height_at(world_pos)
	var h_forward: float = get_height_at(world_pos + Vector3(0, 0, sample_dist))
	var h_right: float = get_height_at(world_pos + Vector3(sample_dist, 0, 0))
	var slope_z: float = (h_forward - h_center) / sample_dist
	var slope_x: float = (h_right - h_center) / sample_dist
	return rad_to_deg(atan(maxf(absf(slope_z), absf(slope_x))))


## Returns the uphill direction at position (normalized)
func get_height_direction_at(world_pos: Vector3) -> Vector3:
	var sample_dist: float = 1.0
	var h_forward: float = get_height_at(world_pos + Vector3(0, 0, sample_dist))
	var h_back: float = get_height_at(world_pos + Vector3(0, 0, -sample_dist))
	var h_right: float = get_height_at(world_pos + Vector3(sample_dist, 0, 0))
	var h_left: float = get_height_at(world_pos + Vector3(-sample_dist, 0, 0))
	var dir: Vector3 = Vector3(h_left - h_right, 0, h_back - h_forward)
	if dir.length_squared() < 0.0001:
		return Vector3.ZERO
	return dir.normalized()


# Regenerate with new seed
func regenerate(new_seed: int = -1):
	if new_seed >= 0:
		noise.seed = new_seed
	else:
		noise.seed = randi()

	# Clean up old
	if mesh_instance:
		mesh_instance.queue_free()
	if static_body:
		static_body.queue_free()
	if nav_region:
		nav_region.queue_free()

	# Wait a frame then regenerate
	await get_tree().process_frame
	_generate_terrain()
