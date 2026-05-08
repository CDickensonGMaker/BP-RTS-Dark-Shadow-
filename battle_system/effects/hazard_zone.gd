class_name HazardZone
extends Area3D

## Persistent damage zone that ticks damage to units inside.
## Based on Catacombs of Gore hazard system.
##
## Usage:
##   var hazard = HazardZone.new()
##   hazard.setup(spell_data, position, caster_faction)
##   add_child(hazard)

# === CONFIGURATION ===

## Radius of the hazard zone
var radius: float = 5.0

## Damage per tick
var tick_damage: int = 10

## Time between damage ticks
var tick_interval: float = 0.5

## How long the hazard persists
var duration: float = 10.0

## Damage type for effects
var damage_type: SpellData.DamageType = SpellData.DamageType.FIRE

## Faction that created this hazard (immune to damage)
var source_faction: int = -1  # -1 = damages everyone, 0 = player, 1 = AI

## Reference to caster regiment for kill tracking
var caster: Regiment = null

## Primary visual color
var effect_color: Color = Color(1.0, 0.5, 0.1, 0.8)

## Secondary color for gradients
var secondary_color: Color = Color(1.0, 0.2, 0.0, 0.5)

# === INTERNAL STATE ===

var _time_alive: float = 0.0
var _tick_timer: float = 0.0
var _units_in_zone: Array[Regiment] = []
var _particles: GPUParticles3D = null
var _ground_decal: MeshInstance3D = null
var _collision_shape: CollisionShape3D = null


func _ready() -> void:
	# Setup collision
	collision_layer = 0  # Don't collide with anything
	collision_mask = 2   # Detect units (layer 2)
	monitoring = true
	monitorable = false

	# Create collision shape
	_collision_shape = CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 4.0  # Tall enough to catch units
	_collision_shape.shape = shape
	add_child(_collision_shape)

	# Setup visual effects
	_setup_particles()
	_setup_ground_decal()

	# Connect area signals
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


func _process(delta: float) -> void:
	_time_alive += delta
	_tick_timer += delta

	# Check expiration
	if _time_alive >= duration:
		_expire()
		return

	# Damage tick
	if _tick_timer >= tick_interval:
		_tick_timer = 0.0
		_apply_tick_damage()

	# Update visuals based on remaining time
	_update_visuals()


## Setup hazard from spell data
func setup(spell: SpellData, world_position: Vector3, caster_regiment: Regiment = null) -> void:
	radius = spell.get_hazard_radius()
	tick_damage = spell.hazard_tick_damage
	tick_interval = spell.hazard_tick_interval
	duration = spell.hazard_duration
	damage_type = spell.damage_type
	effect_color = spell.effect_color
	secondary_color = spell.secondary_color
	caster = caster_regiment

	if caster_regiment:
		source_faction = 0 if caster_regiment.is_player_controlled else 1

	global_position = world_position
	global_position.y += 0.1  # Slightly above ground

	# Update collision shape radius
	if _collision_shape:
		var shape := _collision_shape.shape as CylinderShape3D
		if shape:
			shape.radius = radius


## Setup hazard with raw parameters
func setup_raw(
	p_radius: float,
	p_tick_damage: int,
	p_tick_interval: float,
	p_duration: float,
	p_damage_type: SpellData.DamageType,
	p_color: Color,
	p_faction: int = -1
) -> void:
	radius = p_radius
	tick_damage = p_tick_damage
	tick_interval = p_tick_interval
	duration = p_duration
	damage_type = p_damage_type
	effect_color = p_color
	source_faction = p_faction

	if _collision_shape:
		var shape := _collision_shape.shape as CylinderShape3D
		if shape:
			shape.radius = radius


func _setup_particles() -> void:
	## Create particle system for hazard visual.
	_particles = GPUParticles3D.new()
	_particles.amount = 50
	_particles.lifetime = 1.5
	_particles.one_shot = false
	_particles.explosiveness = 0.0

	var material := ParticleProcessMaterial.new()

	# Particles rise from ground
	material.direction = Vector3(0, 1, 0)
	material.spread = 20.0
	material.initial_velocity_min = 1.0
	material.initial_velocity_max = 3.0
	material.gravity = Vector3(0, 0.5, 0)

	# Emit from disk shape (hazard area)
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = radius * 0.8

	# Scale
	material.scale_min = 0.3
	material.scale_max = 0.8

	# Color gradient based on damage type
	var gradient := Gradient.new()
	gradient.set_color(0, effect_color)
	gradient.add_point(0.5, Color(effect_color.r, effect_color.g, effect_color.b, 0.7))
	gradient.set_color(1, Color(secondary_color.r, secondary_color.g, secondary_color.b, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = gradient
	material.color_ramp = gradient_texture

	_particles.process_material = material

	# Create particle mesh
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.radial_segments = 8
	mesh.rings = 4

	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = effect_color
	mesh_material.emission_enabled = true
	mesh_material.emission = effect_color
	mesh_material.emission_energy_multiplier = 2.0
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_material
	_particles.draw_pass_1 = mesh

	add_child(_particles)
	_particles.emitting = true


func _setup_ground_decal() -> void:
	## Create ground decal showing hazard area.
	_ground_decal = MeshInstance3D.new()

	# Create disk mesh
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.05
	mesh.radial_segments = 32
	mesh.rings = 1

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(effect_color.r, effect_color.g, effect_color.b, 0.3)
	material.emission_enabled = true
	material.emission = effect_color
	material.emission_energy_multiplier = 0.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = material

	_ground_decal.mesh = mesh
	_ground_decal.position = Vector3(0, 0.01, 0)  # Just above ground

	add_child(_ground_decal)


func _update_visuals() -> void:
	## Update visual intensity based on remaining duration.
	var _remaining_ratio: float = 1.0 - (_time_alive / duration)  # Reserved for intensity scaling

	# Fade out in last 2 seconds
	if _time_alive > duration - 2.0:
		var fade_ratio: float = (duration - _time_alive) / 2.0
		if _particles:
			var mat := _particles.draw_pass_1.material as StandardMaterial3D
			if mat:
				mat.albedo_color.a = effect_color.a * fade_ratio
		if _ground_decal:
			var mat := _ground_decal.mesh.material as StandardMaterial3D
			if mat:
				mat.albedo_color.a = 0.3 * fade_ratio

	# Pulse effect
	var pulse: float = 0.9 + 0.1 * sin(_time_alive * 4.0)
	if _ground_decal:
		_ground_decal.scale = Vector3(pulse, 1.0, pulse)


func _apply_tick_damage() -> void:
	## Apply damage to all units in the zone.
	# Clean up invalid references
	_units_in_zone = _units_in_zone.filter(func(r): return is_instance_valid(r))

	for regiment in _units_in_zone:
		# Skip same faction (friendly fire protection)
		if source_faction != -1:
			var reg_faction: int = 0 if regiment.is_player_controlled else 1
			if reg_faction == source_faction:
				continue

		# Skip dead/routing units
		if regiment.state == Regiment.State.DEAD or regiment.state == Regiment.State.ROUTING:
			continue

		# Apply damage
		_apply_damage_to_regiment(regiment)


func _apply_damage_to_regiment(regiment: Regiment) -> void:
	## Apply tick damage and effects to a regiment.
	# Calculate damage falloff based on distance from center
	var dist: float = regiment.global_position.distance_to(global_position)
	var falloff: float = 1.0 - (dist / radius) * 0.5  # 50% damage at edge
	falloff = clampf(falloff, 0.5, 1.0)

	var damage: int = maxi(1, int(float(tick_damage) * falloff))

	# Apply damage
	regiment.take_casualties(damage)

	# Apply morale damage
	var morale_damage: float = damage * 0.3
	MoraleSystem.apply_morale_damage(regiment, morale_damage)

	# Visual feedback
	if CombatEffects:
		var hit_pos: Vector3 = regiment.global_position + Vector3(0, 1.0, 0)
		match damage_type:
			SpellData.DamageType.FIRE:
				CombatEffects.spawn_melee_hit(hit_pos)  # Orange sparks for fire
			SpellData.DamageType.ICE:
				CombatEffects.spawn_block(hit_pos)  # Blue sparks for ice
			_:
				CombatEffects.spawn_ranged_hit(hit_pos)

	# Apply special effects based on damage type
	_apply_damage_type_effects(regiment)

	# Track kills for caster veterancy
	if caster and caster.veterancy and damage > 0:
		caster.veterancy.add_kill()

	# Emit damage signal
	CombatManager.damage_dealt.emit(regiment, damage, caster, "hazard_%s" % SpellData.DamageType.keys()[damage_type].to_lower())


func _apply_damage_type_effects(regiment: Regiment) -> void:
	## Apply special effects based on damage type.
	match damage_type:
		SpellData.DamageType.ICE:
			# Slow effect - reduce speed temporarily
			# This would need a buff system to track
			pass
		SpellData.DamageType.LIGHTNING:
			# Chain damage to nearby units
			# Could be implemented with additional damage pulses
			pass
		SpellData.DamageType.DARK:
			# Extra morale damage
			MoraleSystem.apply_morale_damage(regiment, tick_damage * 0.5)


func _on_area_entered(area: Area3D) -> void:
	## Track units entering the hazard zone.
	var regiment: Regiment = area.get_parent() as Regiment
	if regiment and regiment not in _units_in_zone:
		_units_in_zone.append(regiment)

		# Immediate damage on entry
		_apply_damage_to_regiment(regiment)


func _on_area_exited(area: Area3D) -> void:
	## Remove units from tracking when they leave.
	var regiment: Regiment = area.get_parent() as Regiment
	if regiment:
		_units_in_zone.erase(regiment)


func _expire() -> void:
	## Clean up and remove hazard zone.
	# Stop particles
	if _particles:
		_particles.emitting = false

	# Fade out and free
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)


## Get remaining duration
func get_remaining_duration() -> float:
	return maxf(0.0, duration - _time_alive)


## Get progress (0.0 = just started, 1.0 = about to expire)
func get_progress() -> float:
	return _time_alive / duration


# === STATIC FACTORY METHODS ===

## Create a HazardZone from a configuration dictionary.
## This is the preferred way to create hazards for consistency between spells and weapons.
##
## Config keys:
##   - radius: float (default 5.0)
##   - damage_per_tick: int (default 10)
##   - tick_interval: float (default 0.5)
##   - duration: float (default 10.0)
##   - damage_type: SpellData.DamageType (default FIRE)
##   - color: Color (optional - auto-derived from damage_type if not set)
##   - secondary_color: Color (optional - auto-derived from damage_type if not set)
##   - faction: int (-1 = damages all, 0 = player, 1 = AI)
##
## Usage:
##   var config = { "radius": 6.0, "damage_per_tick": 8, "duration": 12.0, "damage_type": SpellData.DamageType.FIRE }
##   var hazard = HazardZone.create_from_config(config, impact_pos, caster_regiment)
##   get_tree().current_scene.add_child(hazard)
static func create_from_config(config: Dictionary, position: Vector3, source: Regiment = null) -> HazardZone:
	var hazard := HazardZone.new()

	# Extract config values with defaults
	var p_radius: float = config.get("radius", 5.0)
	var p_damage: int = config.get("damage_per_tick", 10)
	var p_interval: float = config.get("tick_interval", 0.5)
	var p_duration: float = config.get("duration", 10.0)
	var p_damage_type: int = config.get("damage_type", SpellData.DamageType.FIRE)

	# Determine faction from source regiment if not explicitly set
	var p_faction: int = config.get("faction", -1)
	if p_faction == -1 and source:
		p_faction = 0 if source.is_player_controlled else 1

	# Get colors - use provided colors or derive from damage type
	var colors: Dictionary = _get_colors_for_damage_type(p_damage_type)
	var p_color: Color = config.get("color", colors.primary)
	var p_secondary: Color = config.get("secondary_color", colors.secondary)

	# Set properties before _ready() runs
	hazard.radius = p_radius
	hazard.tick_damage = p_damage
	hazard.tick_interval = p_interval
	hazard.duration = p_duration
	hazard.damage_type = p_damage_type
	hazard.effect_color = p_color
	hazard.secondary_color = p_secondary
	hazard.source_faction = p_faction
	hazard.caster = source

	# Position will be set after adding to scene tree
	hazard.set_meta("spawn_position", position)

	# Connect to tree_entered to set position after _ready()
	hazard.tree_entered.connect(func():
		hazard.global_position = hazard.get_meta("spawn_position", Vector3.ZERO)
		hazard.global_position.y += 0.1  # Slightly above ground
		# Update collision shape if already created
		if hazard._collision_shape:
			var shape := hazard._collision_shape.shape as CylinderShape3D
			if shape:
				shape.radius = hazard.radius
	, CONNECT_ONE_SHOT)

	return hazard


## Get primary and secondary colors for a damage type.
## Used for consistent visual theming across spells and weapons.
static func _get_colors_for_damage_type(damage_type: int) -> Dictionary:
	match damage_type:
		SpellData.DamageType.FIRE:
			return {
				"primary": Color(1.0, 0.5, 0.1, 0.8),   # Orange fire
				"secondary": Color(1.0, 0.2, 0.0, 0.5)  # Deep red
			}
		SpellData.DamageType.ICE:
			return {
				"primary": Color(0.4, 0.8, 1.0, 0.8),   # Icy blue
				"secondary": Color(0.2, 0.5, 0.9, 0.5)  # Deep blue
			}
		SpellData.DamageType.LIGHTNING:
			return {
				"primary": Color(0.8, 0.8, 1.0, 0.9),   # Electric white-blue
				"secondary": Color(0.5, 0.5, 1.0, 0.5)  # Purple-blue
			}
		SpellData.DamageType.HOLY:
			return {
				"primary": Color(1.0, 1.0, 0.8, 0.9),   # Golden white
				"secondary": Color(1.0, 0.9, 0.5, 0.5)  # Warm gold
			}
		SpellData.DamageType.DARK:
			return {
				"primary": Color(0.4, 0.1, 0.5, 0.8),   # Dark purple
				"secondary": Color(0.2, 0.0, 0.3, 0.5)  # Deep shadow
			}
		SpellData.DamageType.PHYSICAL, _:
			return {
				"primary": Color(0.6, 0.5, 0.4, 0.7),   # Dusty brown
				"secondary": Color(0.4, 0.3, 0.2, 0.4)  # Darker earth
			}
