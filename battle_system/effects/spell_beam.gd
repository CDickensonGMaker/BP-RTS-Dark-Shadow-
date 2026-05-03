class_name SpellBeam
extends Node3D

## Continuous beam spell effect.
## Deals damage over time while active.
## Based on Catacombs of Gore beam patterns with jitter effects.

# === SIGNALS ===

signal beam_tick(target: Regiment)
signal beam_ended()

# === CONFIGURATION ===

## Beam width
var beam_width: float = 2.0

## Maximum beam distance
var beam_distance: float = 40.0

## Beam duration
var duration: float = 3.0

## Damage tick interval
var tick_interval: float = 0.1

## Effect color
var effect_color: Color = Color(0.3, 0.6, 1.0, 0.9)

## Secondary color for effects
var secondary_color: Color = Color(0.1, 0.3, 0.8, 0.5)

## Damage type
var damage_type: SpellData.DamageType = SpellData.DamageType.LIGHTNING

## Jitter amount for beam wobble
var jitter_amount: float = 0.3

## Reference to caster
var caster: Regiment = null

## Target position (or direction)
var target_position: Vector3 = Vector3.ZERO

# === INTERNAL STATE ===

var _time_alive: float = 0.0
var _tick_timer: float = 0.0
var _beam_mesh: MeshInstance3D = null
var _beam_particles: GPUParticles3D = null
var _impact_particles: GPUParticles3D = null
var _current_hit_point: Vector3 = Vector3.ZERO
var _jitter_phase: float = 0.0


func _ready() -> void:
	_setup_visuals()


func _process(delta: float) -> void:
	_time_alive += delta
	_tick_timer += delta
	_jitter_phase += delta * 20.0  # Fast jitter

	# Check duration
	if _time_alive >= duration:
		_end_beam()
		return

	# Update beam endpoint and visuals
	_update_beam()

	# Damage tick
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		_apply_beam_tick()


## Setup beam from spell data.
func setup(spell: SpellData, source: Regiment, target_pos: Vector3) -> void:
	caster = source
	target_position = target_pos
	global_position = source.global_position + Vector3(0, 1.5, 0)

	# Copy spell parameters
	beam_width = spell.beam_width
	beam_distance = spell.beam_distance
	duration = spell.effect_duration if spell.effect_duration > 0 else 3.0
	tick_interval = 0.1
	effect_color = spell.effect_color
	secondary_color = spell.secondary_color
	damage_type = spell.damage_type


func _setup_visuals() -> void:
	## Create beam visual components.
	# Main beam cylinder mesh
	_beam_mesh = MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = beam_width * 0.3
	cylinder.bottom_radius = beam_width * 0.5
	cylinder.height = 1.0  # Will be scaled dynamically
	cylinder.radial_segments = 8

	var material := StandardMaterial3D.new()
	material.albedo_color = effect_color
	material.emission_enabled = true
	material.emission = effect_color
	material.emission_energy_multiplier = 4.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cylinder.material = material

	_beam_mesh.mesh = cylinder
	add_child(_beam_mesh)

	# Beam core particles (energy flowing along beam)
	_beam_particles = GPUParticles3D.new()
	_beam_particles.amount = 30
	_beam_particles.lifetime = 0.3
	_beam_particles.one_shot = false
	_beam_particles.explosiveness = 0.0

	var beam_mat := ParticleProcessMaterial.new()
	beam_mat.direction = Vector3(0, 1, 0)
	beam_mat.spread = 5.0
	beam_mat.initial_velocity_min = 30.0
	beam_mat.initial_velocity_max = 50.0
	beam_mat.gravity = Vector3.ZERO
	beam_mat.scale_min = 0.1
	beam_mat.scale_max = 0.3

	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(effect_color.r, effect_color.g, effect_color.b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	beam_mat.color_ramp = gradient_texture

	_beam_particles.process_material = beam_mat

	var part_mesh := SphereMesh.new()
	part_mesh.radius = 0.08
	part_mesh.height = 0.16
	var part_mat := StandardMaterial3D.new()
	part_mat.albedo_color = Color.WHITE
	part_mat.emission_enabled = true
	part_mat.emission = Color.WHITE
	part_mat.emission_energy_multiplier = 3.0
	part_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	part_mesh.material = part_mat
	_beam_particles.draw_pass_1 = part_mesh

	add_child(_beam_particles)
	_beam_particles.emitting = true

	# Impact point particles
	_impact_particles = GPUParticles3D.new()
	_impact_particles.amount = 20
	_impact_particles.lifetime = 0.4
	_impact_particles.one_shot = false
	_impact_particles.explosiveness = 0.8

	var impact_mat := ParticleProcessMaterial.new()
	impact_mat.direction = Vector3(0, 1, 0)
	impact_mat.spread = 180.0
	impact_mat.initial_velocity_min = 2.0
	impact_mat.initial_velocity_max = 5.0
	impact_mat.gravity = Vector3(0, -5.0, 0)
	impact_mat.scale_min = 0.1
	impact_mat.scale_max = 0.25
	impact_mat.color_ramp = gradient_texture

	_impact_particles.process_material = impact_mat
	_impact_particles.draw_pass_1 = part_mesh.duplicate()

	add_child(_impact_particles)
	_impact_particles.emitting = true


func _update_beam() -> void:
	## Update beam endpoint and orientation.
	if not is_instance_valid(caster):
		_end_beam()
		return

	# Update start position to follow caster
	global_position = caster.global_position + Vector3(0, 1.5, 0)

	# Calculate beam direction and endpoint
	var direction: Vector3 = (target_position - global_position).normalized()
	direction.y = direction.y * 0.3  # Flatten beam slightly

	# Raycast to find actual hit point
	_current_hit_point = _raycast_beam(global_position, direction)

	# Calculate beam length
	var beam_length: float = global_position.distance_to(_current_hit_point)

	# Apply jitter to beam mesh
	var jitter_x: float = sin(_jitter_phase) * jitter_amount
	var jitter_z: float = cos(_jitter_phase * 1.3) * jitter_amount

	# Update beam mesh transform
	var mid_point: Vector3 = (global_position + _current_hit_point) / 2.0
	_beam_mesh.global_position = mid_point + Vector3(jitter_x, 0, jitter_z)
	_beam_mesh.scale = Vector3(1.0, beam_length, 1.0)

	# Orient beam toward target
	_beam_mesh.look_at(_current_hit_point, Vector3.UP)
	_beam_mesh.rotation.x += PI / 2  # Cylinder points along Y, rotate to Z

	# Update impact particles position
	_impact_particles.global_position = _current_hit_point

	# Pulse effect
	var pulse: float = 0.8 + 0.2 * sin(_time_alive * 15.0)
	_beam_mesh.scale.x = pulse
	_beam_mesh.scale.z = pulse


func _raycast_beam(origin: Vector3, direction: Vector3) -> Vector3:
	## Raycast to find where beam hits.
	# Start with max distance
	var end_point: Vector3 = origin + direction * beam_distance

	# Physics raycast for terrain/obstacles
	var space: PhysicsDirectSpaceState3D = caster.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, end_point)
	query.collision_mask = 1  # World layer
	query.exclude = [caster]

	var result: Dictionary = space.intersect_ray(query)
	if not result.is_empty():
		return result.position

	# Check for unit hits
	var hit_regiment := _find_regiment_along_beam(origin, direction, beam_distance)
	if hit_regiment:
		return hit_regiment.global_position + Vector3(0, 1.0, 0)

	return end_point


func _find_regiment_along_beam(origin: Vector3, direction: Vector3, length: float) -> Regiment:
	## Find closest enemy regiment along beam path.
	if not caster or not AIAutoload:
		return null

	var my_faction: int = 0 if caster.is_player_controlled else 1
	var enemy_faction: int = 1 - my_faction

	# Get regiments in beam area
	var center: Vector3 = origin + direction * (length / 2.0)
	var regiments: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		center,
		length / 2.0 + 5.0,
		enemy_faction
	)

	var closest: Regiment = null
	var closest_dist: float = INF

	for node in regiments:
		if not node is Regiment:
			continue
		if node.state == Regiment.State.DEAD:
			continue

		var regiment: Regiment = node
		var to_reg: Vector3 = regiment.global_position - origin

		# Project onto beam direction
		var proj_length: float = to_reg.dot(direction)
		if proj_length < 0 or proj_length > length:
			continue  # Behind or past beam

		# Calculate perpendicular distance from beam line
		var proj_point: Vector3 = origin + direction * proj_length
		var perp_dist: float = regiment.global_position.distance_to(proj_point)

		if perp_dist < beam_width * 2.0:  # Within beam width
			if proj_length < closest_dist:
				closest = regiment
				closest_dist = proj_length

	return closest


func _apply_beam_tick() -> void:
	## Apply damage tick to regiment at beam endpoint.
	var hit_regiment := _find_regiment_along_beam(
		global_position,
		(target_position - global_position).normalized(),
		beam_distance
	)

	if hit_regiment:
		beam_tick.emit(hit_regiment)

		# Visual feedback at hit point
		if CombatEffects:
			CombatEffects.spawn_block(_current_hit_point)


func _end_beam() -> void:
	## Clean up and end beam effect.
	# Fade out
	if _beam_particles:
		_beam_particles.emitting = false
	if _impact_particles:
		_impact_particles.emitting = false

	# Fade mesh
	var tween := create_tween()
	if _beam_mesh and _beam_mesh.mesh and _beam_mesh.mesh.material:
		var mat := _beam_mesh.mesh.material as StandardMaterial3D
		if mat:
			tween.tween_property(mat, "albedo_color:a", 0.0, 0.2)

	beam_ended.emit()

	tween.tween_callback(queue_free)


## Get current beam hit position.
func get_hit_point() -> Vector3:
	return _current_hit_point


## Get remaining duration.
func get_remaining_duration() -> float:
	return maxf(0.0, duration - _time_alive)
