# Campaign World Terrain - Procedural 3D terrain for the campaign map
# Generates a continent-scale terrain with mountains, forests, and settlements
class_name CampaignTerrain3D
extends Node3D


# =============================================================================
# CONFIGURATION
# =============================================================================

## Terrain dimensions (matches campaign map pixels scaled down)
## 3053 x 2160 pixels at 0.1 scale = 305.3 x 216.0 world units
@export var terrain_size: Vector2 = Vector2(305.3, 216.0)

## Mesh resolution (vertices per side)
@export var terrain_resolution: int = 128

## Maximum terrain height
@export var height_scale: float = 25.0

## Base noise scale
@export var noise_scale: float = 0.008

## Noise settings
@export var octaves: int = 5
@export var persistence: float = 0.45
@export var lacunarity: float = 2.2

## Water level (as percentage of height_scale)
@export var water_level: float = 0.15

## Spawn trees as 3D objects
@export var spawn_forests: bool = true
@export var max_forest_trees: int = 500

## Spawn settlement markers
@export var spawn_settlements: bool = true

# =============================================================================
# INTERNAL STATE
# =============================================================================

var mesh_instance: MeshInstance3D
var water_mesh: MeshInstance3D
var collision_body: StaticBody3D
var noise: FastNoiseLite
var heightmap: Array = []
var forest_trees: Array[Node3D] = []
var settlement_markers: Array[Node3D] = []

# Region data for terrain coloring
var region_data: Array = []

# Scale factor from original pixels to 3D world units
const PIXELS_TO_UNITS: float = 0.1


# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	add_to_group("campaign_terrain")
	_setup_noise()
	_generate_terrain()
	_create_water_plane()

	if spawn_forests:
		call_deferred("_spawn_forests")

	if spawn_settlements:
		call_deferred("_spawn_settlement_markers")


func set_region_data(regions: Array) -> void:
	## Set region data for terrain coloring
	region_data = regions
	_apply_material()


func _setup_noise() -> void:
	noise = FastNoiseLite.new()
	noise.seed = 42  # Consistent seed for campaign map
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = noise_scale
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_gain = persistence
	noise.fractal_lacunarity = lacunarity


func _generate_terrain() -> void:
	# Generate heightmap
	_generate_heightmap()

	# Create mesh
	var mesh := _create_terrain_mesh()

	# Setup mesh instance
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # Campaign view doesn't need shadows
	add_child(mesh_instance)

	# NOTE: Don't offset mesh position - keep at origin so coordinates match battalion/settlement positions
	# Terrain spans (0, 0) to (terrain_size.x, terrain_size.y) in world space

	# Setup collision for raycasting
	_setup_collision(mesh)

	# Apply material
	_apply_material()


func _generate_heightmap() -> void:
	heightmap.clear()

	for z in range(terrain_resolution):
		var row := []
		for x in range(terrain_resolution):
			var world_x := (float(x) / terrain_resolution) * terrain_size.x
			var world_z := (float(z) / terrain_resolution) * terrain_size.y

			# Sample noise
			var height := noise.get_noise_2d(world_x, world_z)

			# Add continent shaping - lower heights at edges for ocean
			var edge_falloff := _get_edge_falloff(x, z)
			height = (height * 0.5 + 0.5) * edge_falloff  # Normalize to 0-1 range

			# Apply height scale
			height *= height_scale

			row.append(height)
		heightmap.append(row)


func _get_edge_falloff(x: int, z: int) -> float:
	## Create edge falloff to make water borders
	var fx: float = float(x) / terrain_resolution
	var fz: float = float(z) / terrain_resolution

	# Distance from edges (0 at edge, 1 in center)
	var edge_x: float = 1.0 - absf(fx - 0.5) * 2.0
	var edge_z: float = 1.0 - absf(fz - 0.5) * 2.0

	# Apply soft falloff
	edge_x = smoothstep(0.0, 0.3, edge_x)
	edge_z = smoothstep(0.0, 0.3, edge_z)

	return edge_x * edge_z


func _create_terrain_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var cell_size_x := terrain_size.x / (terrain_resolution - 1)
	var cell_size_z := terrain_size.y / (terrain_resolution - 1)

	# Generate vertices and triangles
	for z in range(terrain_resolution - 1):
		for x in range(terrain_resolution - 1):
			var x0 := x * cell_size_x
			var x1 := (x + 1) * cell_size_x
			var z0 := z * cell_size_z
			var z1 := (z + 1) * cell_size_z

			var h00: float = heightmap[z][x]
			var h10: float = heightmap[z][x + 1]
			var h01: float = heightmap[z + 1][x]
			var h11: float = heightmap[z + 1][x + 1]

			var v0 := Vector3(x0, h00, z0)
			var v1 := Vector3(x1, h10, z0)
			var v2 := Vector3(x0, h01, z1)
			var v3 := Vector3(x1, h11, z1)

			# Calculate normals
			var n1 := (v1 - v0).cross(v2 - v0).normalized()
			var n2 := (v2 - v3).cross(v1 - v3).normalized()

			# Calculate UVs
			var uv0 := Vector2(float(x) / terrain_resolution, float(z) / terrain_resolution)
			var uv1 := Vector2(float(x + 1) / terrain_resolution, float(z) / terrain_resolution)
			var uv2 := Vector2(float(x) / terrain_resolution, float(z + 1) / terrain_resolution)
			var uv3 := Vector2(float(x + 1) / terrain_resolution, float(z + 1) / terrain_resolution)

			# Height-based color (vertex color)
			var c0 := _get_terrain_color(h00)
			var c1 := _get_terrain_color(h10)
			var c2 := _get_terrain_color(h01)
			var c3 := _get_terrain_color(h11)

			# Triangle 1
			st.set_normal(n1)
			st.set_color(c0)
			st.set_uv(uv0)
			st.add_vertex(v0)
			st.set_color(c1)
			st.set_uv(uv1)
			st.add_vertex(v1)
			st.set_color(c2)
			st.set_uv(uv2)
			st.add_vertex(v2)

			# Triangle 2
			st.set_normal(n2)
			st.set_color(c1)
			st.set_uv(uv1)
			st.add_vertex(v1)
			st.set_color(c3)
			st.set_uv(uv3)
			st.add_vertex(v3)
			st.set_color(c2)
			st.set_uv(uv2)
			st.add_vertex(v2)

	st.generate_tangents()
	return st.commit()


func _get_terrain_color(height: float) -> Color:
	## Get terrain color based on height
	var water_height := water_level * height_scale
	var normalized := (height - water_height) / (height_scale - water_height)

	if height < water_height:
		# Underwater - sand/shallow
		return Color(0.76, 0.70, 0.50)  # Sandy beach
	elif normalized < 0.1:
		# Lowlands - grass
		return Color(0.35, 0.55, 0.25)
	elif normalized < 0.3:
		# Hills - darker grass
		return Color(0.30, 0.50, 0.20)
	elif normalized < 0.5:
		# Highlands - brown grass
		return Color(0.45, 0.40, 0.25)
	elif normalized < 0.7:
		# Mountains - rock
		return Color(0.50, 0.45, 0.40)
	else:
		# Peaks - snow
		return Color(0.90, 0.90, 0.95)


func _setup_collision(mesh: ArrayMesh) -> void:
	collision_body = StaticBody3D.new()
	collision_body.collision_layer = 1
	collision_body.collision_mask = 0
	add_child(collision_body)

	var collision_shape := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	collision_shape.shape = shape
	collision_body.add_child(collision_shape)

	# Collision stays at origin to match terrain mesh


func _create_water_plane() -> void:
	## Create a water plane at water level (invisible - just for height reference)
	var water_height := water_level * height_scale

	var plane := PlaneMesh.new()
	plane.size = Vector2(terrain_size.x * 1.2, terrain_size.y * 1.2)

	water_mesh = MeshInstance3D.new()
	water_mesh.mesh = plane
	water_mesh.position = Vector3(terrain_size.x / 2, water_height - 0.5, terrain_size.y / 2)

	# Water is invisible - just exists for collision/reference
	water_mesh.visible = false

	add_child(water_mesh)


func _apply_material() -> void:
	if not mesh_instance:
		return

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true  # Use vertex colors for terrain
	material.roughness = 0.9
	material.metallic = 0.0

	# Try to load parchment-style texture overlay
	var overlay_path := "res://assets/textures/campaign_map.png"
	if ResourceLoader.exists(overlay_path):
		var tex := load(overlay_path) as Texture2D
		if tex:
			material.detail_enabled = true
			material.detail_albedo = tex
			material.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			material.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1

	mesh_instance.material_override = material


# =============================================================================
# FOREST SPAWNING
# =============================================================================

func _spawn_forests() -> void:
	## Spawn trees in forested areas
	var tree_count := 0
	var water_height := water_level * height_scale

	for _i in range(max_forest_trees):
		# Random position
		var pos := Vector3(
			randf() * terrain_size.x,
			0,
			randf() * terrain_size.y
		)

		# Get height at position
		var height := get_height_at(pos)

		# Only spawn trees above water and below mountains
		var normalized := (height - water_height) / (height_scale - water_height)
		if height < water_height + 1.0 or normalized > 0.6:
			continue

		# Weight towards lower elevations
		if randf() > (1.0 - normalized * 0.8):
			continue

		pos.y = height

		# Create simple tree representation
		var tree := _create_tree_marker(pos)
		forest_trees.append(tree)
		tree_count += 1

	print("[CampaignTerrain3D] Spawned %d forest trees" % tree_count)


func _create_tree_marker(pos: Vector3) -> Node3D:
	## Create a simple tree visual (cone + cylinder)
	var tree := Node3D.new()
	tree.position = pos

	# Trunk
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.15
	trunk_mesh.bottom_radius = 0.25
	trunk_mesh.height = 1.2
	trunk.mesh = trunk_mesh
	trunk.position.y = 0.6

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.25, 0.15)
	trunk.material_override = trunk_mat
	tree.add_child(trunk)

	# Foliage
	var foliage := MeshInstance3D.new()
	var foliage_mesh := SphereMesh.new()
	foliage_mesh.radius = 0.8
	foliage_mesh.height = 1.6
	foliage.mesh = foliage_mesh
	foliage.position.y = 2.0

	var foliage_mat := StandardMaterial3D.new()
	foliage_mat.albedo_color = Color(0.2 + randf() * 0.15, 0.4 + randf() * 0.15, 0.15)
	foliage.material_override = foliage_mat
	tree.add_child(foliage)

	# Random scale
	tree.scale = Vector3.ONE * randf_range(0.8, 1.5)

	add_child(tree)
	return tree


# =============================================================================
# SETTLEMENT MARKERS
# =============================================================================

func _spawn_settlement_markers() -> void:
	## Load and spawn settlement markers from data
	var settlements := _load_settlement_data()

	for settlement in settlements:
		var pixel_pos: Vector2 = settlement.get("position", Vector2(500, 500))
		var world_pos := Vector3(
			pixel_pos.x * PIXELS_TO_UNITS,
			0,
			pixel_pos.y * PIXELS_TO_UNITS
		)
		world_pos.y = get_height_at(world_pos) + 0.5

		var marker := _create_settlement_marker(settlement, world_pos)
		settlement_markers.append(marker)

	print("[CampaignTerrain3D] Created %d settlement markers" % settlement_markers.size())


func _load_settlement_data() -> Array:
	## Load settlement data from resources
	var settlements := []
	var dir_path := "res://campaign_system/data/settlements/"

	if not DirAccess.dir_exists_absolute(dir_path):
		return settlements

	var dir := DirAccess.open(dir_path)
	if not dir:
		return settlements

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres"):
			var settlement := load(dir_path + file_name)
			if settlement:
				settlements.append({
					"name": settlement.settlement_name if "settlement_name" in settlement else file_name,
					"position": settlement.map_position if "map_position" in settlement else Vector2(500, 500),
					"type": settlement.settlement_type if "settlement_type" in settlement else 0
				})
		file_name = dir.get_next()

	dir.list_dir_end()
	return settlements


func _create_settlement_marker(data: Dictionary, pos: Vector3) -> Node3D:
	## Create a 3D settlement marker
	var marker := Node3D.new()
	marker.position = pos

	# Building base
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(2.0, 1.5, 2.0)
	base.mesh = base_mesh
	base.position.y = 0.75

	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.6, 0.5, 0.4)
	base.material_override = base_mat
	marker.add_child(base)

	# Roof
	var roof := MeshInstance3D.new()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(2.5, 1.0, 2.5)
	roof.mesh = roof_mesh
	roof.position.y = 2.0

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.5, 0.3, 0.2)
	roof.material_override = roof_mat
	marker.add_child(roof)

	# Name label (3D text)
	var label := Label3D.new()
	label.text = data.get("name", "Settlement")
	label.position.y = 4.0
	label.font_size = 32
	label.outline_size = 4
	label.modulate = Color(0.9, 0.85, 0.7)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.add_child(label)

	add_child(marker)
	return marker


# =============================================================================
# QUERIES
# =============================================================================

func get_height_at(world_pos: Vector3) -> float:
	## Get terrain height at world position
	var local_x := world_pos.x / terrain_size.x * (terrain_resolution - 1)
	var local_z := world_pos.z / terrain_size.y * (terrain_resolution - 1)

	local_x = clampf(local_x, 0, terrain_resolution - 2)
	local_z = clampf(local_z, 0, terrain_resolution - 2)

	var x0 := int(local_x)
	var z0 := int(local_z)
	var x1 := mini(x0 + 1, terrain_resolution - 1)
	var z1 := mini(z0 + 1, terrain_resolution - 1)

	var fx := local_x - x0
	var fz := local_z - z0

	# Bilinear interpolation
	var h00: float = heightmap[z0][x0]
	var h10: float = heightmap[z0][x1]
	var h01: float = heightmap[z1][x0]
	var h11: float = heightmap[z1][x1]

	var h0 := lerpf(h00, h10, fx)
	var h1 := lerpf(h01, h11, fx)
	return lerpf(h0, h1, fz)


func pixel_to_world(pixel_pos: Vector2) -> Vector3:
	## Convert pixel coordinates to world position
	return Vector3(pixel_pos.x * PIXELS_TO_UNITS, 0, pixel_pos.y * PIXELS_TO_UNITS)


func world_to_pixel(world_pos: Vector3) -> Vector2:
	## Convert world position to pixel coordinates
	return Vector2(world_pos.x / PIXELS_TO_UNITS, world_pos.z / PIXELS_TO_UNITS)


func is_above_water(world_pos: Vector3) -> bool:
	## Check if position is above water level
	var height := get_height_at(world_pos)
	return height > water_level * height_scale
