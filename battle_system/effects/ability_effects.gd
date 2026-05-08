extends Node3D

## Visual effects manager for unit abilities.
## Uses GPUParticles3D with pooling for performance.
##
## Effects:
## - CHARGE: Speed lines trailing behind unit during charge
## - BRACE: Blue shield aura around regiment (persistent while braced)
## - WAR_CRY: Expanding golden ring from caster
## - RALLY: Vertical golden beam at rally point
## - INSPIRE: Glowing gold particles on affected units

# =============================================================================
# CONSTANTS
# =============================================================================

# Pool sizes
const POOL_SIZE_PARTICLES: int = 20
const POOL_SIZE_MESHES: int = 10

# Effect durations
const CHARGE_EFFECT_DURATION: float = 0.5  # Per burst, loops while charging
const WAR_CRY_RING_DURATION: float = 1.5
const RALLY_BEAM_DURATION: float = 2.5
const INSPIRE_PARTICLE_DURATION: float = 3.0

# Colors
const COLOR_CHARGE_LINES: Color = Color(1.0, 1.0, 1.0, 0.7)  # White speed lines
const COLOR_BRACE_SHIELD: Color = Color(0.3, 0.5, 1.0, 0.5)  # Blue shield
const COLOR_WAR_CRY_RING: Color = Color(1.0, 0.85, 0.3, 0.9)  # Golden
const COLOR_RALLY_BEAM: Color = Color(1.0, 0.9, 0.4, 0.8)  # Golden
const COLOR_INSPIRE_PARTICLES: Color = Color(1.0, 0.85, 0.3, 1.0)  # Golden

# Effect parameters
const WAR_CRY_RING_MAX_RADIUS: float = 25.0
const RALLY_BEAM_HEIGHT: float = 15.0
const BRACE_SHIELD_RADIUS: float = 4.0

# =============================================================================
# POOLING
# =============================================================================

## Pool of available GPUParticles3D nodes
var _particle_pool: Array[GPUParticles3D] = []

## Pool of available MeshInstance3D nodes
var _mesh_pool: Array[MeshInstance3D] = []

## Active effects per regiment
var _active_effects: Dictionary = {}  # Regiment -> Dictionary of effect nodes

## Charge effects that need continuous updates
var _active_charge_effects: Dictionary = {}  # Regiment -> { particles: GPUParticles3D, timer: float }

## Brace effects (persistent)
var _brace_effects: Dictionary = {}  # Regiment -> MeshInstance3D


func _ready() -> void:
	_initialize_pools()


func _process(delta: float) -> void:
	_update_charge_effects(delta)
	_update_brace_effects(delta)


# =============================================================================
# POOL MANAGEMENT
# =============================================================================

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
	## Return a particle system to the pool.
	if not is_instance_valid(particles):
		return
	particles.emitting = false
	particles.visible = false
	# Reset parent to this node if it was reparented
	if particles.get_parent() != self:
		particles.get_parent().remove_child(particles)
		add_child(particles)


func _return_mesh_to_pool(mesh: MeshInstance3D) -> void:
	## Return a mesh to the pool.
	if not is_instance_valid(mesh):
		return
	mesh.visible = false
	# Reset parent to this node if it was reparented
	if mesh.get_parent() != self:
		mesh.get_parent().remove_child(mesh)
		add_child(mesh)


# =============================================================================
# CHARGE EFFECT - Speed lines trailing behind unit
# =============================================================================

func spawn_charge_effect(regiment: Node) -> void:
	## Create speed lines trailing behind unit during charge.
	if not is_instance_valid(regiment):
		return

	# Don't duplicate if already active
	if regiment in _active_charge_effects:
		return

	var particles := _get_pooled_particles()
	_configure_charge_particles(particles)

	# Reparent to regiment for position tracking
	if particles.get_parent() != regiment:
		particles.get_parent().remove_child(particles)
		regiment.add_child(particles)

	particles.position = Vector3(0, 1.0, 0)
	particles.visible = true
	particles.emitting = true

	_active_charge_effects[regiment] = {
		"particles": particles,
		"timer": 0.0
	}


func stop_charge_effect(regiment: Node) -> void:
	## Stop the charge effect for a regiment.
	if regiment not in _active_charge_effects:
		return

	var data: Dictionary = _active_charge_effects[regiment]
	var particles: GPUParticles3D = data["particles"]
	_return_particles_to_pool(particles)
	_active_charge_effects.erase(regiment)


func _configure_charge_particles(particles: GPUParticles3D) -> void:
	## Configure particle system for speed lines effect.
	particles.amount = 30
	particles.lifetime = CHARGE_EFFECT_DURATION
	particles.one_shot = false  # Continuous while charging
	particles.explosiveness = 0.0

	var material := ParticleProcessMaterial.new()

	# Emit from behind the unit
	material.direction = Vector3(0, 0.2, 1)  # Trail behind
	material.spread = 15.0
	material.initial_velocity_min = 3.0
	material.initial_velocity_max = 6.0
	material.gravity = Vector3.ZERO

	# Radial emission for scattered lines
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(2.0, 0.5, 0.5)

	# Scale for line appearance
	material.scale_min = 0.5
	material.scale_max = 1.5

	# Color gradient (white fading out)
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, COLOR_CHARGE_LINES)
	color_ramp.set_color(1, Color(COLOR_CHARGE_LINES.r, COLOR_CHARGE_LINES.g, COLOR_CHARGE_LINES.b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = color_ramp
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Create elongated mesh for speed lines
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.05, 0.05, 0.5)  # Long thin lines
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_CHARGE_LINES
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh


func _update_charge_effects(_delta: float) -> void:
	## Update active charge effects.
	var to_remove: Array = []

	for regiment in _active_charge_effects:
		if not is_instance_valid(regiment):
			to_remove.append(regiment)
			continue

		# Check if regiment is still charging
		if not _is_regiment_charging(regiment):
			to_remove.append(regiment)

	for regiment in to_remove:
		stop_charge_effect(regiment)


func _is_regiment_charging(regiment: Node) -> bool:
	## Check if regiment is currently in a charge state.
	# Check for has_charged property (indicates active charge)
	if "has_charged" in regiment:
		return regiment.has_charged
	return false


# =============================================================================
# BRACE EFFECT - Blue shield aura around regiment
# =============================================================================

func spawn_brace_effect(regiment: Node) -> void:
	## Create blue shield aura around regiment (persistent while braced).
	if not is_instance_valid(regiment):
		return

	# Don't duplicate if already active
	if regiment in _brace_effects:
		return

	var shield := _get_pooled_mesh()
	_configure_brace_shield(shield)

	# Reparent to regiment
	if shield.get_parent() != regiment:
		shield.get_parent().remove_child(shield)
		regiment.add_child(shield)

	shield.position = Vector3(0, 0.1, 0)
	shield.visible = true

	_brace_effects[regiment] = shield

	# Start pulse animation
	_animate_brace_shield(shield)


func stop_brace_effect(regiment: Node) -> void:
	## Stop the brace effect for a regiment.
	if regiment not in _brace_effects:
		return

	var shield: MeshInstance3D = _brace_effects[regiment]
	_return_mesh_to_pool(shield)
	_brace_effects.erase(regiment)


func _configure_brace_shield(shield: MeshInstance3D) -> void:
	## Configure mesh for shield aura effect.
	# Create dome/hemisphere mesh
	var mesh := SphereMesh.new()
	mesh.radius = BRACE_SHIELD_RADIUS
	mesh.height = BRACE_SHIELD_RADIUS * 1.5
	mesh.radial_segments = 16
	mesh.rings = 8
	shield.mesh = mesh

	# Semi-transparent blue glowing material
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_BRACE_SHIELD
	material.emission_enabled = true
	material.emission = Color(0.3, 0.5, 1.0, 1.0)
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_FRONT  # Render inside of dome
	shield.material_override = material


func _animate_brace_shield(shield: MeshInstance3D) -> void:
	## Animate the shield with subtle pulsing.
	if not is_instance_valid(shield):
		return

	var tween := create_tween()
	tween.set_loops()

	# Subtle scale pulse
	tween.tween_property(shield, "scale", Vector3(1.05, 1.05, 1.05), 0.8).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(shield, "scale", Vector3(1.0, 1.0, 1.0), 0.8).set_ease(Tween.EASE_IN_OUT)


func _update_brace_effects(_delta: float) -> void:
	## Check if braced regiments are still braced.
	var to_remove: Array = []

	for regiment in _brace_effects:
		if not is_instance_valid(regiment):
			to_remove.append(regiment)
			continue

		# Check if regiment is still braced
		if regiment.has_method("get") and regiment.get("is_braced") != null:
			if not regiment.is_braced:
				to_remove.append(regiment)

	for regiment in to_remove:
		stop_brace_effect(regiment)


# =============================================================================
# WAR CRY EFFECT - Expanding golden ring from caster
# =============================================================================

func spawn_war_cry_effect(position: Vector3) -> void:
	## Create expanding golden ring from caster position.
	var ring := _get_pooled_mesh()
	_configure_war_cry_ring(ring)

	# Position at world location (not attached to regiment)
	if ring.get_parent() != self:
		ring.get_parent().remove_child(ring)
		add_child(ring)

	ring.global_position = position + Vector3(0, 0.5, 0)
	ring.visible = true
	ring.scale = Vector3(0.1, 1.0, 0.1)  # Start small

	# Animate expanding ring
	_animate_war_cry_ring(ring)


func _configure_war_cry_ring(ring: MeshInstance3D) -> void:
	## Configure mesh for expanding ring effect.
	# Create torus/ring mesh
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.8
	mesh.outer_radius = 1.0
	mesh.rings = 16
	mesh.ring_segments = 32
	ring.mesh = mesh

	# Glowing golden material
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_WAR_CRY_RING
	material.emission_enabled = true
	material.emission = COLOR_WAR_CRY_RING
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = material


func _animate_war_cry_ring(ring: MeshInstance3D) -> void:
	## Animate the ring expanding outward and fading.
	if not is_instance_valid(ring):
		return

	var tween := create_tween()
	tween.set_parallel(true)

	# Expand ring
	var final_scale := WAR_CRY_RING_MAX_RADIUS / 1.0  # Based on torus outer_radius
	tween.tween_property(ring, "scale", Vector3(final_scale, 1.0, final_scale), WAR_CRY_RING_DURATION).set_ease(Tween.EASE_OUT)

	# Fade out
	var mat := ring.material_override as StandardMaterial3D
	if mat:
		tween.tween_property(mat, "albedo_color:a", 0.0, WAR_CRY_RING_DURATION)

	# Return to pool after animation
	tween.set_parallel(false)
	tween.tween_callback(func():
		_return_mesh_to_pool(ring)
	)


# =============================================================================
# RALLY EFFECT - Vertical golden beam at rally point
# =============================================================================

func spawn_rally_effect(position: Vector3) -> void:
	## Create vertical golden beam at rally point.
	var beam := _get_pooled_mesh()
	_configure_rally_beam(beam)

	# Position at world location
	if beam.get_parent() != self:
		beam.get_parent().remove_child(beam)
		add_child(beam)

	beam.global_position = position + Vector3(0, RALLY_BEAM_HEIGHT / 2.0, 0)
	beam.visible = true
	beam.scale = Vector3(1.0, 0.0, 1.0)  # Start with no height

	# Animate beam appearing and fading
	_animate_rally_beam(beam)


func _configure_rally_beam(beam: MeshInstance3D) -> void:
	## Configure mesh for vertical beam effect.
	# Create cylinder for beam
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.5
	mesh.height = RALLY_BEAM_HEIGHT
	mesh.radial_segments = 12
	beam.mesh = mesh

	# Glowing golden material
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_RALLY_BEAM
	material.emission_enabled = true
	material.emission = COLOR_RALLY_BEAM
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam.material_override = material


func _animate_rally_beam(beam: MeshInstance3D) -> void:
	## Animate the beam appearing, pulsing, and fading.
	if not is_instance_valid(beam):
		return

	var tween := create_tween()

	# Grow beam upward
	tween.tween_property(beam, "scale:y", 1.0, 0.3).set_ease(Tween.EASE_OUT)

	# Pulse for a moment
	tween.tween_property(beam, "scale:x", 1.3, 0.3)
	tween.parallel().tween_property(beam, "scale:z", 1.3, 0.3)
	tween.tween_property(beam, "scale:x", 1.0, 0.3)
	tween.parallel().tween_property(beam, "scale:z", 1.0, 0.3)

	# Hold visible
	tween.tween_interval(RALLY_BEAM_DURATION - 1.4)

	# Fade out
	var mat := beam.material_override as StandardMaterial3D
	if mat:
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)

	# Return to pool
	tween.tween_callback(func():
		_return_mesh_to_pool(beam)
	)


# =============================================================================
# INSPIRE EFFECT - Glowing gold particles on affected units
# =============================================================================

func spawn_inspire_effect(regiment: Node) -> void:
	## Create glowing gold particles on affected units.
	if not is_instance_valid(regiment):
		return

	# Clean up existing inspire effect
	_cleanup_effect(regiment, "inspire")

	var particles := _get_pooled_particles()
	_configure_inspire_particles(particles)

	# Reparent to regiment
	if particles.get_parent() != regiment:
		particles.get_parent().remove_child(particles)
		regiment.add_child(particles)

	particles.position = Vector3(0, 1.5, 0)
	particles.visible = true
	particles.emitting = true

	_register_effect(regiment, "inspire", particles)

	# Auto-cleanup after duration
	get_tree().create_timer(INSPIRE_PARTICLE_DURATION).timeout.connect(
		func():
			stop_inspire_effect(regiment)
	)


func stop_inspire_effect(regiment: Node) -> void:
	## Stop the inspire effect for a regiment.
	_cleanup_effect(regiment, "inspire")


func _configure_inspire_particles(particles: GPUParticles3D) -> void:
	## Configure particle system for inspire glow effect.
	particles.amount = 40
	particles.lifetime = 1.5
	particles.one_shot = false  # Continuous while inspired
	particles.explosiveness = 0.0

	var material := ParticleProcessMaterial.new()

	# Float upward gently
	material.direction = Vector3(0, 1, 0)
	material.spread = 30.0
	material.initial_velocity_min = 0.5
	material.initial_velocity_max = 1.5
	material.gravity = Vector3(0, 0.5, 0)  # Slight upward drift

	# Emit from around the regiment
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(3.0, 0.5, 2.0)

	# Small glowing particles
	material.scale_min = 0.1
	material.scale_max = 0.25

	# Color gradient (gold glowing and fading)
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(COLOR_INSPIRE_PARTICLES.r, COLOR_INSPIRE_PARTICLES.g, COLOR_INSPIRE_PARTICLES.b, 0.0))
	color_ramp.add_point(0.2, COLOR_INSPIRE_PARTICLES)
	color_ramp.set_color(2, Color(COLOR_INSPIRE_PARTICLES.r, COLOR_INSPIRE_PARTICLES.g, COLOR_INSPIRE_PARTICLES.b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = color_ramp
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Create small sphere mesh for particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 8
	mesh.rings = 4
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_INSPIRE_PARTICLES
	mesh_material.emission_enabled = true
	mesh_material.emission = COLOR_INSPIRE_PARTICLES
	mesh_material.emission_energy_multiplier = 2.0
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh


# =============================================================================
# EFFECT MANAGEMENT
# =============================================================================

func _register_effect(regiment: Node, effect_name: String, effect_node: Node) -> void:
	## Register an effect for tracking and cleanup.
	if regiment not in _active_effects:
		_active_effects[regiment] = {}

	# Cleanup existing effect of same type
	if effect_name in _active_effects[regiment]:
		var old_effect = _active_effects[regiment][effect_name]
		if old_effect is GPUParticles3D:
			_return_particles_to_pool(old_effect)
		elif old_effect is MeshInstance3D:
			_return_mesh_to_pool(old_effect)

	_active_effects[regiment][effect_name] = effect_node


func _cleanup_effect(regiment: Node, effect_name: String) -> void:
	## Remove and return a specific effect to pool.
	if regiment not in _active_effects:
		return

	if effect_name in _active_effects[regiment]:
		var effect = _active_effects[regiment][effect_name]
		if effect is GPUParticles3D:
			_return_particles_to_pool(effect)
		elif effect is MeshInstance3D:
			_return_mesh_to_pool(effect)
		_active_effects[regiment].erase(effect_name)


func _cleanup_all_effects(regiment: Node) -> void:
	## Remove all effects for a regiment.
	# Cleanup tracked effects
	if regiment in _active_effects:
		for effect_name in _active_effects[regiment]:
			var effect = _active_effects[regiment][effect_name]
			if effect is GPUParticles3D:
				_return_particles_to_pool(effect)
			elif effect is MeshInstance3D:
				_return_mesh_to_pool(effect)
		_active_effects.erase(regiment)

	# Cleanup charge effect
	if regiment in _active_charge_effects:
		stop_charge_effect(regiment)

	# Cleanup brace effect
	if regiment in _brace_effects:
		stop_brace_effect(regiment)


# =============================================================================
# PUBLIC API
# =============================================================================

func clear_all_effects() -> void:
	## Remove all active effects. Call when battle ends.
	for regiment in _active_effects.keys():
		_cleanup_all_effects(regiment)

	_active_effects.clear()

	# Clear charge effects
	for regiment in _active_charge_effects.keys():
		stop_charge_effect(regiment)
	_active_charge_effects.clear()

	# Clear brace effects
	for regiment in _brace_effects.keys():
		stop_brace_effect(regiment)
	_brace_effects.clear()


func on_regiment_dead(regiment: Node) -> void:
	## Call when a regiment dies to clean up effects.
	_cleanup_all_effects(regiment)
