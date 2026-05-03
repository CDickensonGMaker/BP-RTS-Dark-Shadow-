extends Node3D

## Visual effects manager for spell casting.
## Uses GPUParticles3D with pooling for performance.
## Provides effects based on damage type (fire, ice, lightning, etc.)
##
## Effect Types:
## - Cast flash: Brief glow at caster position
## - Impact burst: Explosion at target based on damage type
## - Expanding ring: AOE indicator
## - Beam core: Particles flowing along beam
## - Hazard ambient: Persistent particles for hazard zones

# =============================================================================
# CONSTANTS
# =============================================================================

# Pool sizes
const POOL_SIZE_PARTICLES: int = 30
const POOL_SIZE_MESHES: int = 15

# Effect durations
const CAST_FLASH_DURATION: float = 0.3
const IMPACT_BURST_DURATION: float = 0.5
const AOE_RING_DURATION: float = 1.0

# Colors by damage type
const COLORS := {
	"fire": {
		"primary": Color(1.0, 0.4, 0.1, 1.0),
		"secondary": Color(1.0, 0.2, 0.0, 0.7),
		"emission": 3.0
	},
	"ice": {
		"primary": Color(0.4, 0.7, 1.0, 1.0),
		"secondary": Color(0.2, 0.5, 0.9, 0.7),
		"emission": 2.0
	},
	"lightning": {
		"primary": Color(0.8, 0.9, 1.0, 1.0),
		"secondary": Color(0.3, 0.6, 1.0, 0.8),
		"emission": 4.0
	},
	"holy": {
		"primary": Color(1.0, 0.95, 0.7, 1.0),
		"secondary": Color(1.0, 0.9, 0.5, 0.7),
		"emission": 3.5
	},
	"dark": {
		"primary": Color(0.3, 0.1, 0.4, 1.0),
		"secondary": Color(0.5, 0.2, 0.6, 0.7),
		"emission": 2.0
	},
	"physical": {
		"primary": Color(0.7, 0.7, 0.7, 1.0),
		"secondary": Color(0.5, 0.5, 0.5, 0.7),
		"emission": 1.5
	}
}

# =============================================================================
# POOLING
# =============================================================================

var _particle_pool: Array[GPUParticles3D] = []
var _mesh_pool: Array[MeshInstance3D] = []


func _ready() -> void:
	_initialize_pools()


func _initialize_pools() -> void:
	## Pre-create particle and mesh nodes for pooling.
	for i in range(POOL_SIZE_PARTICLES):
		var particles := GPUParticles3D.new()
		particles.emitting = false
		particles.one_shot = true
		particles.visible = false
		add_child(particles)
		_particle_pool.append(particles)

	for i in range(POOL_SIZE_MESHES):
		var mesh := MeshInstance3D.new()
		mesh.visible = false
		add_child(mesh)
		_mesh_pool.append(mesh)


func _get_pooled_particles() -> GPUParticles3D:
	## Get an available particle system from the pool.
	for particles in _particle_pool:
		if not particles.emitting and not particles.visible:
			return particles

	# Pool exhausted, create new one
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.visible = false
	add_child(particles)
	_particle_pool.append(particles)
	return particles


func _get_pooled_mesh() -> MeshInstance3D:
	## Get an available mesh from the pool.
	for mesh in _mesh_pool:
		if not mesh.visible:
			return mesh

	# Pool exhausted, create new one
	var mesh := MeshInstance3D.new()
	mesh.visible = false
	add_child(mesh)
	_mesh_pool.append(mesh)
	return mesh


func _return_particles_to_pool(particles: GPUParticles3D) -> void:
	if not is_instance_valid(particles):
		return
	particles.emitting = false
	particles.visible = false
	if particles.get_parent() != self:
		particles.get_parent().remove_child(particles)
		add_child(particles)


func _return_mesh_to_pool(mesh: MeshInstance3D) -> void:
	if not is_instance_valid(mesh):
		return
	mesh.visible = false
	if mesh.get_parent() != self:
		mesh.get_parent().remove_child(mesh)
		add_child(mesh)


# =============================================================================
# CAST FLASH - Brief glow at caster when casting
# =============================================================================

func spawn_cast_flash(position: Vector3, damage_type: SpellData.DamageType) -> void:
	## Create brief flash at caster position.
	var type_key: String = _damage_type_to_key(damage_type)
	var colors: Dictionary = COLORS.get(type_key, COLORS["physical"])

	var mesh := _get_pooled_mesh()
	_configure_flash_mesh(mesh, colors)

	mesh.global_position = position + Vector3(0, 1.5, 0)
	mesh.visible = true
	mesh.scale = Vector3(0.1, 0.1, 0.1)

	# Animate flash
	var tween := create_tween()
	tween.tween_property(mesh, "scale", Vector3(3.0, 3.0, 3.0), CAST_FLASH_DURATION * 0.3)
	tween.parallel().tween_property(mesh.material_override, "albedo_color:a", 0.0, CAST_FLASH_DURATION)
	tween.tween_callback(func(): _return_mesh_to_pool(mesh))


func _configure_flash_mesh(mesh: MeshInstance3D, colors: Dictionary) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh.mesh = sphere

	var material := StandardMaterial3D.new()
	material.albedo_color = colors["primary"]
	material.emission_enabled = true
	material.emission = colors["primary"]
	material.emission_energy_multiplier = colors["emission"]
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material_override = material


# =============================================================================
# IMPACT BURST - Explosion at target
# =============================================================================

func spawn_impact_burst(position: Vector3, damage_type: SpellData.DamageType, radius: float = 5.0) -> void:
	## Create impact explosion particles.
	var type_key: String = _damage_type_to_key(damage_type)
	var colors: Dictionary = COLORS.get(type_key, COLORS["physical"])

	var particles := _get_pooled_particles()
	_configure_impact_particles(particles, colors, radius)

	particles.global_position = position
	particles.visible = true
	particles.emitting = true

	# Auto-cleanup
	get_tree().create_timer(IMPACT_BURST_DURATION + 0.5).timeout.connect(
		func(): _return_particles_to_pool(particles)
	)


func _configure_impact_particles(particles: GPUParticles3D, colors: Dictionary, radius: float) -> void:
	particles.amount = 30
	particles.lifetime = IMPACT_BURST_DURATION
	particles.one_shot = true
	particles.explosiveness = 0.95

	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 0.5, 0)
	material.spread = 180.0
	material.initial_velocity_min = radius * 2.0
	material.initial_velocity_max = radius * 4.0
	material.gravity = Vector3(0, -3.0, 0)

	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = radius * 0.3

	material.scale_min = 0.2
	material.scale_max = 0.6

	var gradient := Gradient.new()
	gradient.set_color(0, colors["primary"])
	gradient.add_point(0.3, Color(colors["primary"].r, colors["primary"].g, colors["primary"].b, 0.8))
	gradient.set_color(1, Color(colors["secondary"].r, colors["secondary"].g, colors["secondary"].b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = colors["primary"]
	mesh_mat.emission_enabled = true
	mesh_mat.emission = colors["primary"]
	mesh_mat.emission_energy_multiplier = colors["emission"]
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh


# =============================================================================
# AOE RING - Expanding indicator ring
# =============================================================================

func spawn_aoe_ring(position: Vector3, damage_type: SpellData.DamageType, max_radius: float) -> void:
	## Create expanding ring showing AOE area.
	var type_key: String = _damage_type_to_key(damage_type)
	var colors: Dictionary = COLORS.get(type_key, COLORS["physical"])

	var ring := _get_pooled_mesh()
	_configure_ring_mesh(ring, colors)

	ring.global_position = position + Vector3(0, 0.5, 0)
	ring.visible = true
	ring.scale = Vector3(0.1, 1.0, 0.1)

	# Animate expansion
	var final_scale: float = max_radius / 1.0  # Based on torus outer_radius
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(final_scale, 1.0, final_scale), AOE_RING_DURATION)

	var mat := ring.material_override as StandardMaterial3D
	if mat:
		tween.tween_property(mat, "albedo_color:a", 0.0, AOE_RING_DURATION)

	tween.set_parallel(false)
	tween.tween_callback(func(): _return_mesh_to_pool(ring))


func _configure_ring_mesh(ring: MeshInstance3D, colors: Dictionary) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.8
	torus.outer_radius = 1.0
	torus.rings = 16
	torus.ring_segments = 32
	ring.mesh = torus

	var material := StandardMaterial3D.new()
	material.albedo_color = colors["primary"]
	material.emission_enabled = true
	material.emission = colors["primary"]
	material.emission_energy_multiplier = colors["emission"]
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material


# =============================================================================
# CONE EFFECT - Frontal cone visual
# =============================================================================

func spawn_cone_effect(position: Vector3, direction: Vector3, angle: float, length: float, damage_type: SpellData.DamageType) -> void:
	## Create cone-shaped particle burst.
	var type_key: String = _damage_type_to_key(damage_type)
	var colors: Dictionary = COLORS.get(type_key, COLORS["physical"])

	var particles := _get_pooled_particles()
	_configure_cone_particles(particles, colors, direction, angle, length)

	particles.global_position = position + Vector3(0, 1.0, 0)
	particles.visible = true
	particles.emitting = true

	# Auto-cleanup
	get_tree().create_timer(0.8).timeout.connect(
		func(): _return_particles_to_pool(particles)
	)


func _configure_cone_particles(particles: GPUParticles3D, colors: Dictionary, direction: Vector3, angle: float, length: float) -> void:
	particles.amount = 40
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 0.9

	var material := ParticleProcessMaterial.new()
	material.direction = direction
	material.spread = angle / 2.0
	material.initial_velocity_min = length * 1.5
	material.initial_velocity_max = length * 2.5
	material.gravity = Vector3.ZERO

	material.scale_min = 0.2
	material.scale_max = 0.8

	var gradient := Gradient.new()
	gradient.set_color(0, colors["primary"])
	gradient.set_color(1, Color(colors["secondary"].r, colors["secondary"].g, colors["secondary"].b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	particles.process_material = material

	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = colors["primary"]
	mesh_mat.emission_enabled = true
	mesh_mat.emission = colors["primary"]
	mesh_mat.emission_energy_multiplier = colors["emission"]
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh


# =============================================================================
# UTILITY
# =============================================================================

func _damage_type_to_key(damage_type: SpellData.DamageType) -> String:
	## Convert damage type enum to color key.
	match damage_type:
		SpellData.DamageType.FIRE:
			return "fire"
		SpellData.DamageType.ICE:
			return "ice"
		SpellData.DamageType.LIGHTNING:
			return "lightning"
		SpellData.DamageType.HOLY:
			return "holy"
		SpellData.DamageType.DARK:
			return "dark"
		_:
			return "physical"


func clear_all_effects() -> void:
	## Clear all active effects. Call when battle ends.
	for particles in _particle_pool:
		if is_instance_valid(particles):
			particles.emitting = false
			particles.visible = false

	for mesh in _mesh_pool:
		if is_instance_valid(mesh):
			mesh.visible = false
