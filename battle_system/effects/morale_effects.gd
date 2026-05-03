class_name MoraleEffects
extends Node3D

## Visual effects manager for morale-related events.
## Connects to BattleSignals and spawns effects on Regiment nodes.
##
## Effects:
## - ROUTING: Particle effect showing soldiers scattering/dropping weapons
## - RALLYING: Pulsing golden glow effect around the regiment
## - WAVERING: Subtle soldier jitter/shake (when morale < 40%)
## - ELITE: Glowing badge/chevron above elite veterancy units

# =============================================================================
# CONSTANTS
# =============================================================================
const WAVERING_THRESHOLD: float = 40.0
const ELITE_LEVEL: int = 3  # VeterancySystem.Level.ELITE

# Effect durations
const ROUTING_PARTICLE_DURATION: float = 3.0
const RALLY_GLOW_DURATION: float = 2.5
const JITTER_AMPLITUDE: float = 0.05
const JITTER_FREQUENCY: float = 15.0

# Colors
const COLOR_RALLY_GLOW: Color = Color(1.0, 0.85, 0.3, 0.8)  # Golden
const COLOR_ROUTING_PARTICLES: Color = Color(0.6, 0.4, 0.3, 1.0)  # Brown/dirt
const COLOR_ELITE_BADGE: Color = Color(1.0, 0.9, 0.4, 1.0)  # Gold
const COLOR_ELITE_BADGE_OUTLINE: Color = Color(0.8, 0.6, 0.1, 1.0)  # Dark gold

# =============================================================================
# TRACKING
# =============================================================================
## Active effects per regiment
var _active_effects: Dictionary = {}  # Regiment -> Dictionary of effect nodes

## Regiments currently wavering (for jitter effect)
var _wavering_regiments: Dictionary = {}  # Regiment -> { original_positions: Array, timer: float }

## Elite badges attached to regiments
var _elite_badges: Dictionary = {}  # Regiment -> MeshInstance3D


func _ready() -> void:
	# Connect to BattleSignals
	if BattleSignals:
		BattleSignals.regiment_routing.connect(_on_regiment_routing)
		BattleSignals.regiment_rallied.connect(_on_regiment_rallied)
		BattleSignals.morale_changed.connect(_on_morale_changed)
		BattleSignals.unit_leveled_up.connect(_on_unit_leveled_up)
		BattleSignals.regiment_dead.connect(_on_regiment_dead)


func _process(delta: float) -> void:
	# Update wavering jitter effect for affected regiments
	_update_wavering_effects(delta)


# =============================================================================
# SIGNAL HANDLERS
# =============================================================================

func _on_regiment_routing(regiment: Regiment) -> void:
	## Spawn routing particle effect showing soldiers scattering.
	if not is_instance_valid(regiment):
		return

	# Remove any existing rally effect
	_cleanup_effect(regiment, "rally")

	# Spawn routing particles
	var particles := _create_routing_particles(regiment)
	_register_effect(regiment, "routing", particles)

	# Auto-cleanup after duration
	get_tree().create_timer(ROUTING_PARTICLE_DURATION).timeout.connect(
		func(): _cleanup_effect(regiment, "routing")
	)


func _on_regiment_rallied(regiment: Regiment) -> void:
	## Spawn rallying glow effect around the regiment.
	if not is_instance_valid(regiment):
		return

	# Remove routing effect and wavering
	_cleanup_effect(regiment, "routing")
	_stop_wavering(regiment)

	# Spawn rally glow
	var glow := _create_rally_glow(regiment)
	_register_effect(regiment, "rally", glow)

	# Animate and cleanup
	_animate_rally_glow(glow, RALLY_GLOW_DURATION)


func _on_morale_changed(regiment: Regiment, new_value: float, _delta: float) -> void:
	## Check for wavering threshold and apply jitter effect.
	if not is_instance_valid(regiment):
		return

	# Check wavering state
	if new_value < WAVERING_THRESHOLD and regiment.state != Regiment.State.ROUTING:
		_start_wavering(regiment)
	else:
		_stop_wavering(regiment)


func _on_unit_leveled_up(regiment: Regiment, _old_level: int, new_level: int) -> void:
	## Add elite badge if unit reaches level 3.
	if not is_instance_valid(regiment):
		return

	if new_level >= ELITE_LEVEL:
		_add_elite_badge(regiment)


func _on_regiment_dead(regiment: Regiment) -> void:
	## Cleanup all effects when regiment dies.
	_cleanup_all_effects(regiment)


# =============================================================================
# ROUTING EFFECT
# =============================================================================

func _create_routing_particles(regiment: Regiment) -> GPUParticles3D:
	## Create particle effect showing soldiers scattering/dropping weapons.
	var particles := GPUParticles3D.new()
	particles.name = "RoutingParticles"

	# Configure particle system
	particles.amount = 20
	particles.lifetime = ROUTING_PARTICLE_DURATION
	particles.one_shot = true
	particles.explosiveness = 0.8

	# Create process material
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 45.0
	material.initial_velocity_min = 2.0
	material.initial_velocity_max = 5.0
	material.gravity = Vector3(0, -9.8, 0)
	material.angular_velocity_min = -180.0
	material.angular_velocity_max = 180.0

	# Radial emission for scattering effect
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 3.0

	# Scale down over time
	material.scale_min = 0.1
	material.scale_max = 0.3

	# Color gradient (brown fading out)
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, COLOR_ROUTING_PARTICLES)
	color_ramp.set_color(1, Color(COLOR_ROUTING_PARTICLES.r, COLOR_ROUTING_PARTICLES.g, COLOR_ROUTING_PARTICLES.b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = color_ramp
	material.color_ramp = gradient_texture

	particles.process_material = material

	# Create simple mesh for particles (small boxes representing dropped items)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.2, 0.1, 0.3)
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = COLOR_ROUTING_PARTICLES
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh

	# Position at regiment location
	regiment.add_child(particles)
	particles.position = Vector3(0, 1.0, 0)

	# Start emitting
	particles.emitting = true

	return particles


# =============================================================================
# RALLY EFFECT
# =============================================================================

func _create_rally_glow(regiment: Regiment) -> MeshInstance3D:
	## Create pulsing golden glow effect around the regiment.
	var glow := MeshInstance3D.new()
	glow.name = "RallyGlow"

	# Create cylinder mesh for ring effect
	var mesh := CylinderMesh.new()
	mesh.top_radius = 5.0
	mesh.bottom_radius = 5.0
	mesh.height = 0.2
	mesh.radial_segments = 24
	glow.mesh = mesh

	# Create glowing material
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_RALLY_GLOW
	material.emission_enabled = true
	material.emission = COLOR_RALLY_GLOW
	material.emission_energy_multiplier = 2.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = material

	# Position at regiment base
	regiment.add_child(glow)
	glow.position = Vector3(0, 0.1, 0)

	return glow


func _animate_rally_glow(glow: MeshInstance3D, duration: float) -> void:
	## Animate the rally glow with pulsing and fade out.
	if not is_instance_valid(glow):
		return

	var tween := create_tween()
	tween.set_loops(3)  # Pulse 3 times

	# Scale pulse
	tween.tween_property(glow, "scale", Vector3(1.2, 1.0, 1.2), duration / 6.0)
	tween.tween_property(glow, "scale", Vector3(1.0, 1.0, 1.0), duration / 6.0)

	# Final fade out after pulses complete
	tween.tween_callback(func():
		if is_instance_valid(glow):
			var fade_tween := create_tween()
			var mat := glow.material_override as StandardMaterial3D
			if mat:
				fade_tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
				fade_tween.tween_callback(func():
					if is_instance_valid(glow):
						glow.queue_free()
				)
	)


# =============================================================================
# WAVERING EFFECT
# =============================================================================

func _start_wavering(regiment: Regiment) -> void:
	## Start jitter effect on soldiers when morale is low.
	if regiment in _wavering_regiments:
		return  # Already wavering

	_wavering_regiments[regiment] = {
		"timer": 0.0,
	}


func _stop_wavering(regiment: Regiment) -> void:
	## Stop jitter effect and restore soldier positions.
	if regiment not in _wavering_regiments:
		return

	_wavering_regiments.erase(regiment)


func _update_wavering_effects(delta: float) -> void:
	## Apply jitter to all wavering regiments.
	var to_remove: Array = []

	for regiment in _wavering_regiments:
		if not is_instance_valid(regiment):
			to_remove.append(regiment)
			continue

		# Check if still should be wavering
		if regiment.current_morale >= WAVERING_THRESHOLD or regiment.state == Regiment.State.ROUTING:
			to_remove.append(regiment)
			continue

		# Update timer
		_wavering_regiments[regiment]["timer"] += delta

		# Apply jitter to formation
		_apply_formation_jitter(regiment, _wavering_regiments[regiment]["timer"])

	# Cleanup invalid entries
	for regiment in to_remove:
		_wavering_regiments.erase(regiment)


func _apply_formation_jitter(regiment: Regiment, time: float) -> void:
	## Apply subtle jitter to the regiment's soldiers.
	if not regiment.formation:
		return

	# Access the formation's soldiers if available
	var formation = regiment.formation
	if not formation.has_method("get_soldier_count"):
		# Apply jitter to the whole formation node instead
		var offset_x := sin(time * JITTER_FREQUENCY) * JITTER_AMPLITUDE
		var offset_z := cos(time * JITTER_FREQUENCY * 1.3) * JITTER_AMPLITUDE * 0.7
		formation.position.x = offset_x
		formation.position.z = offset_z
		return

	# If we have individual soldiers, jitter each with slight phase offset
	if formation.has("soldiers"):
		var soldiers: Array = formation.soldiers
		for i in soldiers.size():
			var soldier = soldiers[i]
			if not is_instance_valid(soldier) or not soldier.visible:
				continue

			var phase := float(i) * 0.5
			var offset_x := sin((time + phase) * JITTER_FREQUENCY) * JITTER_AMPLITUDE
			var offset_z := cos((time + phase) * JITTER_FREQUENCY * 1.3) * JITTER_AMPLITUDE * 0.7

			# Store original position if not stored
			if not soldier.has_meta("original_local_pos"):
				soldier.set_meta("original_local_pos", soldier.position)

			var original: Vector3 = soldier.get_meta("original_local_pos")
			soldier.position = original + Vector3(offset_x, 0, offset_z)


# =============================================================================
# ELITE BADGE
# =============================================================================

func _add_elite_badge(regiment: Regiment) -> void:
	## Add glowing chevron badge above elite units.
	if regiment in _elite_badges:
		return  # Already has badge

	var badge := _create_elite_badge()
	regiment.add_child(badge)
	badge.position = Vector3(0, 3.5, 0)  # Above the unit

	_elite_badges[regiment] = badge

	# Start badge animation
	_animate_elite_badge(badge)


func _create_elite_badge() -> MeshInstance3D:
	## Create a glowing chevron mesh for elite units.
	var badge := MeshInstance3D.new()
	badge.name = "EliteBadge"

	# Create chevron shape using PrismMesh (upward pointing)
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.8, 0.4, 0.1)
	badge.mesh = mesh

	# Glowing gold material
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_ELITE_BADGE
	material.emission_enabled = true
	material.emission = COLOR_ELITE_BADGE
	material.emission_energy_multiplier = 3.0
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	badge.material_override = material

	return badge


func _animate_elite_badge(badge: MeshInstance3D) -> void:
	## Animate the elite badge with gentle bobbing and glow pulse.
	if not is_instance_valid(badge):
		return

	var tween := create_tween()
	tween.set_loops()

	# Gentle vertical bob
	var start_y := badge.position.y
	tween.tween_property(badge, "position:y", start_y + 0.15, 1.0).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(badge, "position:y", start_y, 1.0).set_ease(Tween.EASE_IN_OUT)


# =============================================================================
# EFFECT MANAGEMENT
# =============================================================================

func _register_effect(regiment: Regiment, effect_name: String, effect_node: Node) -> void:
	## Register an effect for tracking and cleanup.
	if regiment not in _active_effects:
		_active_effects[regiment] = {}

	# Cleanup existing effect of same type
	if effect_name in _active_effects[regiment]:
		var old_effect = _active_effects[regiment][effect_name]
		if is_instance_valid(old_effect):
			old_effect.queue_free()

	_active_effects[regiment][effect_name] = effect_node


func _cleanup_effect(regiment: Regiment, effect_name: String) -> void:
	## Remove and free a specific effect.
	if regiment not in _active_effects:
		return

	if effect_name in _active_effects[regiment]:
		var effect = _active_effects[regiment][effect_name]
		if is_instance_valid(effect):
			effect.queue_free()
		_active_effects[regiment].erase(effect_name)


func _cleanup_all_effects(regiment: Regiment) -> void:
	## Remove all effects for a regiment.
	# Cleanup tracked effects
	if regiment in _active_effects:
		for effect_name in _active_effects[regiment]:
			var effect = _active_effects[regiment][effect_name]
			if is_instance_valid(effect):
				effect.queue_free()
		_active_effects.erase(regiment)

	# Remove from wavering
	_wavering_regiments.erase(regiment)

	# Remove elite badge
	if regiment in _elite_badges:
		var badge = _elite_badges[regiment]
		if is_instance_valid(badge):
			badge.queue_free()
		_elite_badges.erase(regiment)


# =============================================================================
# PUBLIC API
# =============================================================================

func force_refresh_elite_badges() -> void:
	## Scan all regiments and add elite badges where needed.
	## Call this after loading a save game.
	var regiments: Array = get_tree().get_nodes_in_group("all_regiments")
	for regiment in regiments:
		if regiment is Regiment and regiment.veterancy:
			if regiment.veterancy.is_elite():
				_add_elite_badge(regiment)


func clear_all_effects() -> void:
	## Remove all active effects. Call when battle ends.
	for regiment in _active_effects.keys():
		_cleanup_all_effects(regiment)

	_active_effects.clear()
	_wavering_regiments.clear()

	for regiment in _elite_badges.keys():
		var badge = _elite_badges[regiment]
		if is_instance_valid(badge):
			badge.queue_free()
	_elite_badges.clear()
