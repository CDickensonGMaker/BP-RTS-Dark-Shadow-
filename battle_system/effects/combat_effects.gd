extends Node

## Combat visual effects manager with pooled GPUParticles3D.
## Uses object pooling for performance - pre-spawns particles and reuses them.
##
## Effect Types:
## - MELEE_HIT: Orange spark burst (8 particles, 0.3s)
## - RANGED_HIT: Brown dust puff (4 particles, 0.2s)
## - DEATH: Red mist burst (12 particles, 0.5s)
## - BLOCK: Blue spark deflection (6 particles, 0.2s)

# =============================================================================
# CONSTANTS
# =============================================================================

# Pool sizes
const POOL_SIZE_MELEE: int = 20
const POOL_SIZE_RANGED: int = 20
const POOL_SIZE_DEATH: int = 10
const POOL_SIZE_BLOCK: int = 10
const POOL_SIZE_BLOOD: int = 50  # Blood pools persist longer

# Effect durations
const DURATION_MELEE: float = 0.3
const DURATION_RANGED: float = 0.2
const DURATION_DEATH: float = 0.5
const DURATION_BLOCK: float = 0.2
const DURATION_BLOOD: float = 30.0  # Blood pools last 30 seconds

# Particle counts
const PARTICLES_MELEE: int = 8
const PARTICLES_RANGED: int = 4
const PARTICLES_DEATH: int = 12
const PARTICLES_BLOCK: int = 6
const PARTICLES_BLOOD: int = 3  # Simple blood splatter

# Colors
const COLOR_MELEE_START: Color = Color(1.0, 0.6, 0.1, 1.0)   # Bright orange
const COLOR_MELEE_END: Color = Color(1.0, 0.3, 0.0, 0.0)     # Fade orange

const COLOR_RANGED_START: Color = Color(0.6, 0.45, 0.25, 0.9)  # Brown dust
const COLOR_RANGED_END: Color = Color(0.5, 0.4, 0.2, 0.0)      # Fade brown

const COLOR_DEATH_START: Color = Color(0.8, 0.1, 0.1, 1.0)   # Bright red
const COLOR_DEATH_END: Color = Color(0.4, 0.0, 0.0, 0.0)     # Fade dark red

const COLOR_BLOCK_START: Color = Color(0.3, 0.6, 1.0, 1.0)   # Bright blue
const COLOR_BLOCK_END: Color = Color(0.1, 0.3, 0.8, 0.0)     # Fade blue

const COLOR_BLOOD_START: Color = Color(0.5, 0.05, 0.05, 0.9)  # Dark red blood
const COLOR_BLOOD_END: Color = Color(0.3, 0.02, 0.02, 0.6)    # Darker, stays visible

# =============================================================================
# EFFECT POOLS
# =============================================================================

enum EffectType {
	MELEE_HIT,
	RANGED_HIT,
	DEATH,
	BLOCK,
	BLOOD_POOL
}

# Pools organized by effect type
var _pools: Dictionary = {
	EffectType.MELEE_HIT: [],
	EffectType.RANGED_HIT: [],
	EffectType.DEATH: [],
	EffectType.BLOCK: [],
	EffectType.BLOOD_POOL: []
}

# Container node for pooled particles (keeps scene tree clean)
var _pool_container: Node3D


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	# Create container for particle pools
	_pool_container = Node3D.new()
	_pool_container.name = "CombatEffectsPool"
	add_child(_pool_container)

	# Pre-spawn particle pools
	_init_pool(EffectType.MELEE_HIT, POOL_SIZE_MELEE)
	_init_pool(EffectType.RANGED_HIT, POOL_SIZE_RANGED)
	_init_pool(EffectType.DEATH, POOL_SIZE_DEATH)
	_init_pool(EffectType.BLOCK, POOL_SIZE_BLOCK)
	_init_pool(EffectType.BLOOD_POOL, POOL_SIZE_BLOOD)


# =============================================================================
# POOL INITIALIZATION
# =============================================================================

func _init_pool(effect_type: EffectType, size: int) -> void:
	## Pre-spawn particles for the given effect type.
	for i in size:
		var particles := _create_particles(effect_type)
		particles.visible = false
		particles.emitting = false
		_pool_container.add_child(particles)
		_pools[effect_type].append(particles)


func _create_particles(effect_type: EffectType) -> GPUParticles3D:
	## Create a GPUParticles3D configured for the given effect type.
	var particles := GPUParticles3D.new()

	match effect_type:
		EffectType.MELEE_HIT:
			_configure_melee_particles(particles)
		EffectType.RANGED_HIT:
			_configure_ranged_particles(particles)
		EffectType.DEATH:
			_configure_death_particles(particles)
		EffectType.BLOCK:
			_configure_block_particles(particles)
		EffectType.BLOOD_POOL:
			_configure_blood_particles(particles)

	return particles


func _configure_melee_particles(particles: GPUParticles3D) -> void:
	## Orange spark burst for melee impacts.
	particles.name = "MeleeHitParticles"
	particles.amount = PARTICLES_MELEE
	particles.lifetime = DURATION_MELEE
	particles.one_shot = true
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()

	# Outward burst in all directions
	material.direction = Vector3(0, 0.5, 0)
	material.spread = 180.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0

	# Slight downward gravity for sparks
	material.gravity = Vector3(0, -4.0, 0)

	# Angular velocity for spark tumbling
	material.angular_velocity_min = -360.0
	material.angular_velocity_max = 360.0

	# Scale
	material.scale_min = 0.05
	material.scale_max = 0.12

	# Color gradient: bright orange to fade
	var gradient := Gradient.new()
	gradient.set_color(0, COLOR_MELEE_START)
	gradient.set_color(1, COLOR_MELEE_END)
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Simple spark mesh (small diamond)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_MELEE_START
	mesh_material.emission_enabled = true
	mesh_material.emission = COLOR_MELEE_START
	mesh_material.emission_energy_multiplier = 2.0
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh


func _configure_ranged_particles(particles: GPUParticles3D) -> void:
	## Brown dust puff for ranged impacts.
	particles.name = "RangedHitParticles"
	particles.amount = PARTICLES_RANGED
	particles.lifetime = DURATION_RANGED
	particles.one_shot = true
	particles.explosiveness = 0.9

	var material := ParticleProcessMaterial.new()

	# Soft upward puff
	material.direction = Vector3(0, 1, 0)
	material.spread = 60.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 2.5

	# Slight gravity
	material.gravity = Vector3(0, -2.0, 0)

	# Scale grows slightly (dust expanding)
	material.scale_min = 0.15
	material.scale_max = 0.3

	# Emission from small sphere
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.2

	# Color gradient: brown dust fading
	var gradient := Gradient.new()
	gradient.set_color(0, COLOR_RANGED_START)
	gradient.set_color(1, COLOR_RANGED_END)
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Dust puff mesh (sphere)
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_RANGED_START
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh


func _configure_death_particles(particles: GPUParticles3D) -> void:
	## Red mist burst for unit deaths.
	particles.name = "DeathParticles"
	particles.amount = PARTICLES_DEATH
	particles.lifetime = DURATION_DEATH
	particles.one_shot = true
	particles.explosiveness = 0.95

	var material := ParticleProcessMaterial.new()

	# Outward mist burst
	material.direction = Vector3(0, 0.3, 0)
	material.spread = 180.0
	material.initial_velocity_min = 1.5
	material.initial_velocity_max = 4.0

	# Slight upward drift (mist rises)
	material.gravity = Vector3(0, 0.5, 0)

	# Scale grows as mist disperses
	material.scale_min = 0.2
	material.scale_max = 0.5

	# Emission from ring (outward spray)
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.5

	# Color gradient: red mist fading
	var gradient := Gradient.new()
	gradient.set_color(0, COLOR_DEATH_START)
	gradient.add_point(0.3, Color(0.7, 0.1, 0.05, 0.8))
	gradient.set_color(1, COLOR_DEATH_END)
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Mist mesh (larger sphere)
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_DEATH_START
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh


func _configure_block_particles(particles: GPUParticles3D) -> void:
	## Blue spark deflection for blocked attacks.
	particles.name = "BlockParticles"
	particles.amount = PARTICLES_BLOCK
	particles.lifetime = DURATION_BLOCK
	particles.one_shot = true
	particles.explosiveness = 1.0

	var material := ParticleProcessMaterial.new()

	# Upward deflection arc
	material.direction = Vector3(0, 1, 0)
	material.spread = 90.0
	material.initial_velocity_min = 4.0
	material.initial_velocity_max = 7.0

	# Gravity pulls sparks down in arc
	material.gravity = Vector3(0, -8.0, 0)

	# Angular tumbling
	material.angular_velocity_min = -540.0
	material.angular_velocity_max = 540.0

	# Small sparks
	material.scale_min = 0.04
	material.scale_max = 0.08

	# Color gradient: bright blue to fade
	var gradient := Gradient.new()
	gradient.set_color(0, COLOR_BLOCK_START)
	gradient.set_color(1, COLOR_BLOCK_END)
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Spark mesh (small box)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 0.06)
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_BLOCK_START
	mesh_material.emission_enabled = true
	mesh_material.emission = COLOR_BLOCK_START
	mesh_material.emission_energy_multiplier = 3.0
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh


func _configure_blood_particles(particles: GPUParticles3D) -> void:
	## Dark red blood pool that spreads on the ground.
	particles.name = "BloodPoolParticles"
	particles.amount = PARTICLES_BLOOD
	particles.lifetime = DURATION_BLOOD
	particles.one_shot = true
	particles.explosiveness = 0.8

	var material := ParticleProcessMaterial.new()

	# Blood spreads outward on ground plane
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 0.3
	material.initial_velocity_max = 0.8

	# No gravity - stays on ground
	material.gravity = Vector3(0, -0.1, 0)

	# Blood pools grow as they spread
	material.scale_min = 0.8
	material.scale_max = 1.5

	# Emission from small area at ground level
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.3

	# Color gradient: dark red, stays visible for long time
	var gradient := Gradient.new()
	gradient.set_color(0, COLOR_BLOOD_START)
	gradient.add_point(0.1, COLOR_BLOOD_START)  # Stay bright initially
	gradient.add_point(0.7, COLOR_BLOOD_END)    # Start fading late
	gradient.set_color(1, Color(0.2, 0.01, 0.01, 0.0))  # Fade out
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Flat disk mesh for blood pool on ground
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	mesh.orientation = PlaneMesh.FACE_Y  # Horizontal on ground
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_BLOOD_START
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh


# =============================================================================
# POOL MANAGEMENT
# =============================================================================

func _get_from_pool(effect_type: EffectType) -> GPUParticles3D:
	## Get an available particle system from the pool, or create new if needed.
	var pool: Array = _pools[effect_type]

	# Find inactive particle system
	for particles in pool:
		if is_instance_valid(particles) and not particles.emitting:
			return particles

	# Pool exhausted - create new (will be added to pool)
	var new_particles := _create_particles(effect_type)
	new_particles.visible = false
	new_particles.emitting = false
	_pool_container.add_child(new_particles)
	pool.append(new_particles)

	return new_particles


func _spawn_effect(effect_type: EffectType, position: Vector3) -> void:
	## Spawn a particle effect at the given world position.
	var particles := _get_from_pool(effect_type)

	if not is_instance_valid(particles):
		return

	# Position in world space
	particles.global_position = position
	particles.visible = true
	particles.emitting = true

	# Get duration for auto-hide
	var duration: float
	match effect_type:
		EffectType.MELEE_HIT:
			duration = DURATION_MELEE
		EffectType.RANGED_HIT:
			duration = DURATION_RANGED
		EffectType.DEATH:
			duration = DURATION_DEATH
		EffectType.BLOCK:
			duration = DURATION_BLOCK
		EffectType.BLOOD_POOL:
			duration = DURATION_BLOOD

	# Hide after emission completes (add small buffer)
	get_tree().create_timer(duration + 0.1).timeout.connect(
		func():
			if is_instance_valid(particles):
				particles.visible = false
				particles.emitting = false
	)


# =============================================================================
# PUBLIC API
# =============================================================================

func spawn_melee_hit(position: Vector3) -> void:
	## Spawn orange spark burst at melee impact location.
	## 8 particles, 0.3s duration.
	_spawn_effect(EffectType.MELEE_HIT, position)


func spawn_ranged_hit(position: Vector3) -> void:
	## Spawn brown dust puff at ranged impact location.
	## 4 particles, 0.2s duration.
	_spawn_effect(EffectType.RANGED_HIT, position)


func spawn_death(position: Vector3) -> void:
	## Spawn red mist burst at death location.
	## 12 particles, 0.5s duration.
	_spawn_effect(EffectType.DEATH, position)


func spawn_block(position: Vector3) -> void:
	## Spawn blue spark deflection at block location.
	## 6 particles, 0.2s duration.
	_spawn_effect(EffectType.BLOCK, position)


func spawn_blood_pool(position: Vector3) -> void:
	## Spawn dark red blood pool at corpse location.
	## Blood spreads on ground and persists for 30 seconds.
	## Position should be at ground level (y near 0).
	var ground_pos := Vector3(position.x, 0.05, position.z)  # Slightly above ground to avoid z-fighting
	_spawn_effect(EffectType.BLOOD_POOL, ground_pos)


# =============================================================================
# UTILITY
# =============================================================================

func clear_all_effects() -> void:
	## Stop all active particle effects. Call when battle ends.
	for effect_type in _pools:
		var pool: Array = _pools[effect_type]
		for particles in pool:
			if is_instance_valid(particles):
				particles.emitting = false
				particles.visible = false


func get_pool_stats() -> Dictionary:
	## Get statistics about pool usage for debugging.
	var stats := {}
	for effect_type in _pools:
		var pool: Array = _pools[effect_type]
		var active: int = 0
		for particles in pool:
			if is_instance_valid(particles) and particles.emitting:
				active += 1
		stats[EffectType.keys()[effect_type]] = {
			"pool_size": pool.size(),
			"active": active
		}
	return stats


# =============================================================================
# EXPLOSION EFFECTS (Sprite-based via SpriteEffectPool)
# =============================================================================

func spawn_explosion(position: Vector3, radius: float = 3.0, context_node: Node = null) -> void:
	## Spawn explosion effect at position.
	## Uses sprite-based effect if SpriteEffectPool is available,
	## otherwise falls back to particle-based DEATH effect.
	## Large explosions (radius >= 4) use artillery explosion with fire and smoke.
	## @param context_node: Source unit for viewport detection (SubViewport support)
	var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
	if sprite_pool:
		if radius >= 4.0 and sprite_pool.has_method("spawn_artillery_explosion"):
			sprite_pool.spawn_artillery_explosion(position, radius, context_node)
		elif sprite_pool.has_method("spawn_explosion"):
			sprite_pool.spawn_explosion(position, radius, context_node)
		else:
			_spawn_effect(EffectType.DEATH, position)
	else:
		# Fallback to particle effect
		_spawn_effect(EffectType.DEATH, position)
