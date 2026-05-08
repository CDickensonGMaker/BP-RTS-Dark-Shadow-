class_name SelectionRing
extends Node3D

## Selection ring effect - shows a glowing circle on the ground around selected units.
## Uses a mesh ring that pulses gently to indicate selection.

@export var ring_color: Color = Color(0.4, 0.8, 1.0, 0.5)
@export var ring_radius: float = 2.0
@export var ring_thickness: float = 0.15

var _ring_mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	_ring_mesh = MeshInstance3D.new()
	_ring_mesh.mesh = _create_ring_mesh(ring_radius, ring_thickness)

	_material = StandardMaterial3D.new()
	_material.albedo_color = ring_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = true  # Always visible even behind units
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	_ring_mesh.material_override = _material

	add_child(_ring_mesh)


func _process(_delta: float) -> void:
	# Subtle pulse animation
	var t: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = 0.85 + sin(t * 2.0) * 0.15  # 0.7 to 1.0
	if _material:
		var color: Color = ring_color
		color.a = 0.5 * pulse
		_material.albedo_color = color


func _create_ring_mesh(radius: float, thickness: float) -> Mesh:
	## Create a flat ring (annulus) mesh using SurfaceTool.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segments := 32
	for i in segments:
		var a0 := (float(i) / segments) * TAU
		var a1 := (float(i + 1) / segments) * TAU
		var inner := radius - thickness
		var outer := radius

		# 4 corners of this segment
		var p1 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var p2 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var p3 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		var p4 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)

		# Normal up
		st.set_normal(Vector3.UP)

		# Triangle 1
		st.add_vertex(p1)
		st.add_vertex(p2)
		st.add_vertex(p3)

		# Triangle 2
		st.add_vertex(p1)
		st.add_vertex(p3)
		st.add_vertex(p4)

	return st.commit()


func set_size(formation_radius: float) -> void:
	## Resize the ring to match formation extent.
	var scale_factor: float = formation_radius / ring_radius
	_ring_mesh.scale = Vector3.ONE * scale_factor


func set_color(color: Color) -> void:
	## Set the ring color.
	ring_color = color
	if _material:
		_material.albedo_color = color
