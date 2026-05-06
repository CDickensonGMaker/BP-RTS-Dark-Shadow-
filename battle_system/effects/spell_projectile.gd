class_name SpellProjectile
extends Node3D

## Spell projectile that travels toward a target.
## Supports homing, arc, and various visual styles.
## Based on Catacombs of Gore projectile patterns.

# === SIGNALS ===

signal hit_target(position: Vector3, target: Regiment)
signal projectile_expired()

# === CONFIGURATION ===

## Movement speed (units per second)
var speed: float = 30.0

## Arc height at midpoint
var arc_height: float = 5.0

## Whether projectile homes toward nearest enemy
var is_homing: bool = false

## Homing turn rate (degrees per second)
var homing_turn_rate: float = 180.0

## Maximum lifetime before auto-expire
var lifetime: float = 10.0

## Impact AOE radius (0 = single target)
var impact_radius: float = 0.0

## Effect color
var effect_color: Color = Color(1.0, 0.5, 0.1, 1.0)

## Damage type for effects
var damage_type: SpellData.DamageType = SpellData.DamageType.FIRE

## Reference to caster
var caster: Regiment = null

## Target position
var target_position: Vector3 = Vector3.ZERO

## Target regiment (for homing)
var target_regiment: Regiment = null

## Visual scale
var visual_scale: float = 1.0

# === INTERNAL STATE ===

var _start_position: Vector3 = Vector3.ZERO
var _time_alive: float = 0.0
var _total_distance: float = 0.0
var _distance_traveled: float = 0.0
var _direction: Vector3 = Vector3.FORWARD
var _particles: GPUParticles3D = null
var _mesh: MeshInstance3D = null
var _trail: GPUParticles3D = null


func _ready() -> void:
	_setup_visuals()


func _process(delta: float) -> void:
	_time_alive += delta

	# Check lifetime
	if _time_alive >= lifetime:
		_expire()
		return

	# Update movement
	if is_homing:
		_update_homing(delta)
	else:
		_update_arc_movement(delta)

	# Check for impact
	_check_impact()


## Setup projectile from spell data.
func setup(spell: SpellData, source: Regiment, target_pos: Vector3) -> void:
	caster = source
	target_position = target_pos
	_start_position = source.global_position + Vector3(0, 2.0, 0)
	global_position = _start_position

	# Copy spell parameters
	speed = spell.projectile_speed
	arc_height = spell.projectile_arc
	is_homing = spell.is_homing
	homing_turn_rate = spell.homing_turn_rate
	impact_radius = spell.aoe_radius
	effect_color = spell.effect_color
	damage_type = spell.damage_type
	visual_scale = spell.projectile_scale

	# Calculate direction and distance
	var to_target: Vector3 = target_position - _start_position
	_total_distance = to_target.length()
	_direction = to_target.normalized()

	# Find target regiment for homing
	if is_homing:
		_find_target_regiment()


func _setup_visuals() -> void:
	## Create visual representation.
	# Create glowing sphere mesh
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3 * visual_scale
	sphere.height = 0.6 * visual_scale
	sphere.radial_segments = 16
	sphere.rings = 8

	var material := StandardMaterial3D.new()
	material.albedo_color = effect_color
	material.emission_enabled = true
	material.emission = effect_color
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = material

	_mesh.mesh = sphere
	add_child(_mesh)

	# Create particle trail
	_trail = GPUParticles3D.new()
	_trail.amount = 20
	_trail.lifetime = 0.4
	_trail.one_shot = false
	_trail.explosiveness = 0.0

	var trail_mat := ParticleProcessMaterial.new()
	trail_mat.direction = Vector3(0, 0, -1)  # Trail behind
	trail_mat.spread = 10.0
	trail_mat.initial_velocity_min = 0.5
	trail_mat.initial_velocity_max = 1.5
	trail_mat.gravity = Vector3.ZERO
	trail_mat.scale_min = 0.1
	trail_mat.scale_max = 0.3

	# Color gradient
	var gradient := Gradient.new()
	gradient.set_color(0, effect_color)
	gradient.set_color(1, Color(effect_color.r, effect_color.g, effect_color.b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	trail_mat.color_ramp = gradient_texture

	_trail.process_material = trail_mat

	# Trail particle mesh
	var trail_mesh := SphereMesh.new()
	trail_mesh.radius = 0.08
	trail_mesh.height = 0.16
	var trail_mesh_mat := StandardMaterial3D.new()
	trail_mesh_mat.albedo_color = effect_color
	trail_mesh_mat.emission_enabled = true
	trail_mesh_mat.emission = effect_color
	trail_mesh_mat.emission_energy_multiplier = 2.0
	trail_mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mesh.material = trail_mesh_mat
	_trail.draw_pass_1 = trail_mesh

	add_child(_trail)
	_trail.emitting = true


func _update_arc_movement(delta: float) -> void:
	## Move projectile along arc toward target.
	# Move forward
	var move_dist: float = speed * delta
	_distance_traveled += move_dist

	# Calculate progress (0-1)
	var progress: float = _distance_traveled / _total_distance
	progress = clampf(progress, 0.0, 1.0)

	# Linear interpolation for XZ
	var flat_pos: Vector3 = _start_position.lerp(target_position, progress)

	# Parabolic arc for Y
	var arc_offset: float = 4.0 * arc_height * progress * (1.0 - progress)
	var base_height: float = lerpf(_start_position.y, target_position.y, progress)

	global_position = Vector3(flat_pos.x, base_height + arc_offset, flat_pos.z)

	# Face direction of travel
	if _direction.length_squared() > 0.001:
		look_at(global_position + _direction, Vector3.UP)


func _update_homing(delta: float) -> void:
	## Move projectile with homing toward target regiment.
	# Update target position if tracking regiment
	if is_instance_valid(target_regiment):
		target_position = target_regiment.global_position + Vector3(0, 1.0, 0)
	elif _time_alive > 0.5:
		# Try to find new target if we lost ours
		_find_target_regiment()

	# Calculate desired direction
	var to_target: Vector3 = target_position - global_position
	var desired_direction: Vector3 = to_target.normalized()

	# Smoothly turn toward target
	var max_turn: float = deg_to_rad(homing_turn_rate) * delta
	_direction = _direction.slerp(desired_direction, max_turn / PI)
	_direction = _direction.normalized()

	# Move forward
	global_position += _direction * speed * delta

	# Face direction
	if _direction.length_squared() > 0.001:
		look_at(global_position + _direction, Vector3.UP)


func _find_target_regiment() -> void:
	## Find nearest enemy regiment for homing.
	if not caster or not AIAutoload or not AIAutoload.spatial_hash:
		return

	var my_faction: int = 0 if caster.is_player_controlled else 1
	var nearest: Node = AIAutoload.spatial_hash.query_nearest_enemy(
		global_position,
		100.0,  # Search radius
		my_faction
	)

	if nearest is Regiment:
		target_regiment = nearest
		target_position = target_regiment.global_position + Vector3(0, 1.0, 0)


func _check_impact() -> void:
	## Check if projectile has reached target area.
	var dist_to_target: float = global_position.distance_to(target_position)

	# Impact threshold
	var impact_threshold: float = 1.5

	if dist_to_target < impact_threshold:
		_on_impact()
		return

	# Also check if we've traveled past the target (overshot)
	if _distance_traveled > _total_distance + 5.0:
		_on_impact()
		return

	# Ground collision check
	if global_position.y < 0.0:
		global_position.y = 0.0
		_on_impact()


func _on_impact() -> void:
	## Handle projectile impact.
	# Find regiment at impact location
	var hit_regiment: Regiment = null

	if impact_radius > 0.0:
		# AOE - emit position for area damage
		hit_target.emit(global_position, null)
	else:
		# Single target - find nearest enemy at impact
		hit_regiment = _find_regiment_at_position(global_position, 2.0)
		hit_target.emit(global_position, hit_regiment)

	# Spawn impact visual
	_spawn_impact_effect()

	# Clean up
	_expire()


func _find_regiment_at_position(pos: Vector3, radius: float) -> Regiment:
	## Find a regiment near the given position.
	if not caster or not AIAutoload or not AIAutoload.spatial_hash:
		return null

	var my_faction: int = 0 if caster.is_player_controlled else 1

	var regiments: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		pos,
		radius,
		1 - my_faction  # Enemy faction
	)

	for node in regiments:
		if node is Regiment and node.state != Regiment.State.DEAD:
			return node

	return null


func _spawn_impact_effect() -> void:
	## Create impact visual effect.
	if CombatEffects:
		match damage_type:
			SpellData.DamageType.FIRE:
				CombatEffects.spawn_melee_hit(global_position)
			SpellData.DamageType.ICE:
				CombatEffects.spawn_block(global_position)
			_:
				CombatEffects.spawn_ranged_hit(global_position)

	# Spawn expanding ring for AOE
	if impact_radius > 0.0 and AbilityEffects:
		AbilityEffects.spawn_war_cry_effect(global_position)


func _expire() -> void:
	## Clean up and remove projectile.
	if _trail:
		_trail.emitting = false

	projectile_expired.emit()
	queue_free()
