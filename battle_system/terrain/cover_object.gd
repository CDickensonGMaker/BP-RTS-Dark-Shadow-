# Cover object - trees, rocks, buildings that provide defensive bonus
class_name CoverObject
extends Node3D


enum CoverType { LIGHT, MEDIUM, HEAVY }

@export var cover_type: CoverType = CoverType.LIGHT
@export var cover_radius: float = 3.0  # Range at which units get cover bonus
@export var blocks_line_of_sight: bool = false

# Cover bonuses by type
const COVER_BONUSES = {
	CoverType.LIGHT: 0.15,   # 15% damage reduction (bushes, small trees)
	CoverType.MEDIUM: 0.30,  # 30% damage reduction (trees, large rocks)
	CoverType.HEAVY: 0.50,   # 50% damage reduction (buildings, walls)
}

var visual_mesh: Node3D


func _ready():
	add_to_group("cover_objects")


func get_cover_bonus() -> float:
	return COVER_BONUSES[cover_type]


func is_position_in_cover(pos: Vector3) -> bool:
	return global_position.distance_to(pos) <= cover_radius


func get_cover_direction() -> Vector3:
	"""Returns the direction from which cover is provided (facing away from cover)"""
	return Vector3.ZERO  # Override in subclasses for directional cover


# Static factory for creating procedural cover
static func spawn_tree(parent: Node, pos: Vector3) -> CoverObject:
	var cover = CoverObject.new()
	cover.cover_type = CoverType.MEDIUM
	cover.cover_radius = 4.0
	cover.blocks_line_of_sight = true
	cover.position = pos
	parent.add_child(cover)

	# Create simple tree visual (green cone)
	var mesh = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 2.0
	cone.height = 5.0
	mesh.mesh = cone
	mesh.position.y = 3.5

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.5, 0.15)
	mesh.material_override = mat
	cover.add_child(mesh)

	# Trunk
	var trunk = MeshInstance3D.new()
	var trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.2
	trunk_mesh.bottom_radius = 0.3
	trunk_mesh.height = 2.0
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.0

	var trunk_mat = StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.25, 0.1)
	trunk.material_override = trunk_mat
	cover.add_child(trunk)

	cover.visual_mesh = mesh
	return cover


static func spawn_rock(parent: Node, pos: Vector3, size: float = 1.0) -> CoverObject:
	var cover = CoverObject.new()
	cover.cover_type = CoverType.MEDIUM if size > 1.5 else CoverType.LIGHT
	cover.cover_radius = size * 2.0
	cover.blocks_line_of_sight = size > 2.0
	cover.position = pos
	parent.add_child(cover)

	# Create simple rock visual (irregular box)
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(size * 1.2, size * 0.8, size * 1.0)
	mesh.mesh = box
	mesh.position.y = size * 0.4
	mesh.rotation = Vector3(randf() * 0.2, randf() * TAU, randf() * 0.1)

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.4, 0.35)
	mat.roughness = 1.0
	mesh.material_override = mat
	cover.add_child(mesh)

	cover.visual_mesh = mesh
	return cover


static func spawn_bush(parent: Node, pos: Vector3) -> CoverObject:
	var cover = CoverObject.new()
	cover.cover_type = CoverType.LIGHT
	cover.cover_radius = 2.0
	cover.blocks_line_of_sight = false
	cover.position = pos
	parent.add_child(cover)

	# Create simple bush visual (sphere)
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 1.5
	mesh.mesh = sphere
	mesh.position.y = 0.75

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.45, 0.2)
	mesh.material_override = mat
	cover.add_child(mesh)

	cover.visual_mesh = mesh
	return cover
