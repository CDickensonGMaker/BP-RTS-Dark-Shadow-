# Capture Point - Siege objective that must be controlled to win
# Shows a gold circle on the ground and a floating star above
class_name CapturePoint
extends Node3D


signal capture_progress_changed(faction: String, progress: float)
signal point_captured(faction: String)
signal point_contested()

## Capture settings
@export var capture_radius: float = 15.0
@export var capture_time: float = 30.0  # Seconds to capture at full strength
@export var point_name: String = "Stronghold"

## Visual settings
@export var circle_color: Color = Color(1.0, 0.85, 0.2, 0.8)  # Gold
@export var star_color: Color = Color(1.0, 0.9, 0.3, 1.0)  # Bright gold
@export var star_height: float = 8.0
@export var star_size: float = 2.0

## State
var current_owner: String = "neutral"  # "neutral", "player", "enemy"
var capture_progress: float = 0.0  # -1.0 to 1.0 (-1 = enemy, 1 = player)
var is_contested: bool = false

## Visual nodes
var ground_circle: MeshInstance3D
var ground_glow: MeshInstance3D
var floating_star: Node3D
var star_mesh: MeshInstance3D
var capture_bar: Node3D

## Pulse animation
var pulse_time: float = 0.0
const PULSE_SPEED := 2.0


func _ready() -> void:
	add_to_group("capture_points")
	_create_visuals()
	_create_capture_bar()


func _process(delta: float) -> void:
	_update_capture(delta)
	_animate_visuals(delta)


func _create_visuals() -> void:
	# === GROUND CIRCLE ===
	ground_circle = MeshInstance3D.new()
	var circle_mesh := TorusMesh.new()
	circle_mesh.inner_radius = capture_radius - 0.5
	circle_mesh.outer_radius = capture_radius + 0.5
	circle_mesh.rings = 64
	circle_mesh.ring_segments = 3
	ground_circle.mesh = circle_mesh

	var circle_mat := StandardMaterial3D.new()
	circle_mat.albedo_color = circle_color
	circle_mat.emission_enabled = true
	circle_mat.emission = circle_color
	circle_mat.emission_energy_multiplier = 2.0
	circle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	circle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_circle.material_override = circle_mat
	ground_circle.rotation.x = -PI / 2  # Lay flat
	ground_circle.position.y = 0.1  # Slightly above ground
	add_child(ground_circle)

	# === INNER GLOW ===
	ground_glow = MeshInstance3D.new()
	var glow_mesh := CylinderMesh.new()
	glow_mesh.top_radius = capture_radius
	glow_mesh.bottom_radius = capture_radius
	glow_mesh.height = 0.05
	glow_mesh.radial_segments = 64
	ground_glow.mesh = glow_mesh

	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(circle_color.r, circle_color.g, circle_color.b, 0.15)
	glow_mat.emission_enabled = true
	glow_mat.emission = circle_color
	glow_mat.emission_energy_multiplier = 0.5
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ground_glow.material_override = glow_mat
	ground_glow.position.y = 0.05
	add_child(ground_glow)

	# === FLOATING STAR ===
	floating_star = Node3D.new()
	floating_star.position.y = star_height
	add_child(floating_star)

	# Create star shape using prisms
	star_mesh = MeshInstance3D.new()
	var star_shape := _create_star_mesh()
	star_mesh.mesh = star_shape

	var star_mat := StandardMaterial3D.new()
	star_mat.albedo_color = star_color
	star_mat.emission_enabled = true
	star_mat.emission = star_color
	star_mat.emission_energy_multiplier = 3.0
	star_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_mesh.material_override = star_mat
	floating_star.add_child(star_mesh)

	# Add point light for glow
	var light := OmniLight3D.new()
	light.light_color = star_color
	light.light_energy = 2.0
	light.omni_range = 10.0
	light.omni_attenuation = 2.0
	floating_star.add_child(light)


func _create_star_mesh() -> ArrayMesh:
	# Create a 4-pointed star using SurfaceTool
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var s := star_size
	var t := star_size * 0.3  # Thickness

	# 4 triangular points extending outward
	var points := [
		Vector3(s, 0, 0),   # Right
		Vector3(-s, 0, 0),  # Left
		Vector3(0, s, 0),   # Up
		Vector3(0, -s, 0),  # Down
		Vector3(0, 0, s),   # Front
		Vector3(0, 0, -s),  # Back
	]

	# Center octahedron
	for i in range(0, 6, 2):
		var p1 := points[i]
		var p2 := points[(i + 2) % 6]
		var p3 := points[(i + 4) % 6]

		# Front face
		st.add_vertex(p1 * 0.5)
		st.add_vertex(p2 * 0.5)
		st.add_vertex(Vector3.ZERO + Vector3(0, 0, t))

		# Back face
		st.add_vertex(p2 * 0.5)
		st.add_vertex(p1 * 0.5)
		st.add_vertex(Vector3.ZERO - Vector3(0, 0, t))

	# Create the 6 pointed spikes
	for point in points:
		var perp1 := point.cross(Vector3.UP).normalized() * t * 0.5
		var perp2 := point.cross(perp1).normalized() * t * 0.5
		if perp1.length() < 0.01:
			perp1 = Vector3(t * 0.5, 0, 0)
			perp2 = Vector3(0, 0, t * 0.5)

		var base := point * 0.3
		# 4 triangular faces per spike
		st.add_vertex(base + perp1)
		st.add_vertex(base + perp2)
		st.add_vertex(point)

		st.add_vertex(base + perp2)
		st.add_vertex(base - perp1)
		st.add_vertex(point)

		st.add_vertex(base - perp1)
		st.add_vertex(base - perp2)
		st.add_vertex(point)

		st.add_vertex(base - perp2)
		st.add_vertex(base + perp1)
		st.add_vertex(point)

	st.generate_normals()
	return st.commit()


func _create_capture_bar() -> void:
	# Create a capture progress indicator above the point
	capture_bar = Node3D.new()
	capture_bar.position.y = star_height + 3.0
	add_child(capture_bar)

	# Background bar
	var bg := MeshInstance3D.new()
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(6.0, 0.5, 0.2)
	bg.mesh = bg_mesh

	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.8)
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.material_override = bg_mat
	capture_bar.add_child(bg)

	# Progress bar (will be scaled)
	var progress := MeshInstance3D.new()
	progress.name = "ProgressFill"
	var prog_mesh := BoxMesh.new()
	prog_mesh.size = Vector3(5.8, 0.4, 0.25)
	progress.mesh = prog_mesh
	progress.position.z = 0.01

	var prog_mat := StandardMaterial3D.new()
	prog_mat.albedo_color = Color(0.5, 0.5, 0.5)
	prog_mat.emission_enabled = true
	prog_mat.emission_energy_multiplier = 1.0
	progress.material_override = prog_mat
	capture_bar.add_child(progress)


func _update_capture(delta: float) -> void:
	# Count units in capture zone
	var player_strength := 0
	var enemy_strength := 0

	for regiment in get_tree().get_nodes_in_group("all_regiments"):
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD or regiment.state == Regiment.State.ROUTING:
			continue

		var dist := global_position.distance_to(regiment.global_position)
		if dist <= capture_radius:
			var strength: int = regiment.current_soldiers
			if regiment.is_player_controlled:
				player_strength += strength
			else:
				enemy_strength += strength

	# Determine capture rate
	var net_strength := player_strength - enemy_strength
	is_contested = (player_strength > 0 and enemy_strength > 0)

	if is_contested:
		point_contested.emit()
		# Contested - slower capture
		net_strength = int(net_strength * 0.5)

	# Update progress
	var rate := float(net_strength) / 100.0  # 100 soldiers = 1x capture rate
	var progress_delta := (delta / capture_time) * rate

	var old_progress := capture_progress
	capture_progress = clampf(capture_progress + progress_delta, -1.0, 1.0)

	if capture_progress != old_progress:
		var faction := "neutral"
		if capture_progress > 0:
			faction = "player"
		elif capture_progress < 0:
			faction = "enemy"
		capture_progress_changed.emit(faction, abs(capture_progress))

	# Check for capture
	var old_owner := current_owner
	if capture_progress >= 1.0:
		current_owner = "player"
	elif capture_progress <= -1.0:
		current_owner = "enemy"
	elif abs(capture_progress) < 0.1:
		current_owner = "neutral"

	if current_owner != old_owner and current_owner != "neutral":
		point_captured.emit(current_owner)

	_update_capture_bar()


func _update_capture_bar() -> void:
	var fill: MeshInstance3D = capture_bar.get_node_or_null("ProgressFill")
	if not fill:
		return

	# Scale and color based on progress
	var abs_progress := abs(capture_progress)
	fill.scale.x = maxf(abs_progress, 0.01)

	var mat: StandardMaterial3D = fill.material_override
	if capture_progress > 0:
		mat.albedo_color = Color(0.2, 0.6, 1.0)  # Blue for player
		mat.emission = Color(0.2, 0.6, 1.0)
	elif capture_progress < 0:
		mat.albedo_color = Color(1.0, 0.2, 0.2)  # Red for enemy
		mat.emission = Color(1.0, 0.2, 0.2)
	else:
		mat.albedo_color = Color(0.5, 0.5, 0.5)
		mat.emission = Color(0.3, 0.3, 0.3)


func _animate_visuals(delta: float) -> void:
	pulse_time += delta * PULSE_SPEED

	# Rotate star
	floating_star.rotation.y += delta * 0.5

	# Bob star up and down
	floating_star.position.y = star_height + sin(pulse_time) * 0.5

	# Pulse ground circle
	var pulse := 0.9 + sin(pulse_time * 2.0) * 0.1
	ground_circle.scale = Vector3(pulse, pulse, pulse)

	# Billboard capture bar to camera
	var camera := get_viewport().get_camera_3d()
	if camera:
		capture_bar.look_at(camera.global_position)
		capture_bar.rotation.x = 0
		capture_bar.rotation.z = 0


func get_owner_faction() -> String:
	return current_owner


func is_captured_by_player() -> bool:
	return current_owner == "player"


func is_captured_by_enemy() -> bool:
	return current_owner == "enemy"
