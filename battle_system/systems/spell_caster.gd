class_name SpellCaster
extends RefCounted

## Handles spell casting for regiments.
## Manages cast flow, spawns effects, and applies damage.
## Based on Catacombs of Gore spell casting patterns.
##
## Usage:
##   var caster = SpellCaster.new()
##   caster.cast_spell(spell_data, regiment, target_position)

const SpellProjectileClass = preload("res://battle_system/effects/spell_projectile.gd")
const SpellBeamClass = preload("res://battle_system/effects/spell_beam.gd")
const HazardZoneClass = preload("res://battle_system/effects/hazard_zone.gd")

# Projectile type mapping from spell damage type to Projectile.ProjectileType enum
const SPELL_DAMAGE_TO_PROJECTILE_TYPE: Dictionary = {
	SpellData.DamageType.FIRE: 4,      # FLAME
	SpellData.DamageType.ICE: 2,       # MAGIC
	SpellData.DamageType.LIGHTNING: 2, # MAGIC
	SpellData.DamageType.HOLY: 2,      # MAGIC
	SpellData.DamageType.DARK: 2,      # MAGIC
	SpellData.DamageType.PHYSICAL: 3,  # SHELL
}

# === SIGNALS ===

signal spell_cast_started(spell: SpellData, caster: Regiment)
signal spell_cast_completed(spell: SpellData, caster: Regiment, target: Vector3)
signal spell_hit(spell: SpellData, target: Regiment, damage: int)
signal spell_projectile_spawned(projectile: Node3D)


# === CONSTANTS ===

## Maximum targets for AOE spells (performance limit)
const MAX_AOE_TARGETS: int = 20

## Beam update interval (seconds)
const BEAM_TICK_INTERVAL: float = 0.1

## Cone segment resolution for hit detection
const CONE_SEGMENTS: int = 8


# === INTERNAL STATE ===

## Active spell projectiles (for cleanup)
var _active_projectiles: Array[Node3D] = []

## Active beam effects
var _active_beams: Dictionary = {}  # Regiment -> { beam_node, target, spell, timer }

## Reference to shared projectile pool (from CombatManager)
var _projectile_pool: ProjectilePool = null

## Cached autoload references
var _spell_effects: Node = null
var _ability_effects: Node = null
var _combat_effects: Node = null
var _audio_manager: Node = null


func _get_spell_effects(caster: Regiment) -> Node:
	if _spell_effects and is_instance_valid(_spell_effects):
		return _spell_effects
	if caster and caster.is_inside_tree():
		_spell_effects = caster.get_node_or_null("/root/SpellEffects")
	return _spell_effects


func _get_ability_effects(caster: Regiment) -> Node:
	if _ability_effects and is_instance_valid(_ability_effects):
		return _ability_effects
	if caster and caster.is_inside_tree():
		_ability_effects = caster.get_node_or_null("/root/AbilityEffects")
	return _ability_effects


func _get_combat_effects(caster: Regiment) -> Node:
	if _combat_effects and is_instance_valid(_combat_effects):
		return _combat_effects
	if caster and caster.is_inside_tree():
		_combat_effects = caster.get_node_or_null("/root/CombatEffects")
	return _combat_effects


func _get_audio_manager(caster: Regiment) -> Node:
	if _audio_manager and is_instance_valid(_audio_manager):
		return _audio_manager
	if caster and caster.is_inside_tree():
		_audio_manager = caster.get_node_or_null("/root/AudioManager")
	return _audio_manager


func _get_projectile_pool(_caster: Regiment) -> ProjectilePool:
	## Get reference to shared ProjectilePool from CombatManager.
	## Caches the reference for subsequent calls.
	if _projectile_pool and is_instance_valid(_projectile_pool):
		return _projectile_pool
	# Try to get from CombatManager autoload
	if CombatManager and CombatManager._projectile_pool:
		_projectile_pool = CombatManager._projectile_pool
	return _projectile_pool


# === MAIN CAST FUNCTION ===

## Cast a spell from a regiment at a target position.
## Returns true if cast succeeded, false otherwise.
func cast_spell(spell: SpellData, caster: Regiment, target_pos: Vector3) -> bool:
	if not _validate_cast(spell, caster, target_pos):
		return false

	# Consume resources
	_consume_resources(spell, caster)

	# Emit start signal
	spell_cast_started.emit(spell, caster)

	# Spawn cast visual effect
	_spawn_cast_effect(spell, caster)

	# Execute based on target type
	match spell.target_type:
		SpellData.TargetType.PROJECTILE:
			_cast_projectile(spell, caster, target_pos)
		SpellData.TargetType.AOE_POINT:
			_cast_aoe_point(spell, caster, target_pos)
		SpellData.TargetType.AOE_SELF:
			_cast_aoe_self(spell, caster)
		SpellData.TargetType.CONE:
			_cast_cone(spell, caster, target_pos)
		SpellData.TargetType.BEAM:
			_cast_beam(spell, caster, target_pos)

	# Play cast sound
	_play_cast_sound(spell, caster.global_position, caster)

	spell_cast_completed.emit(spell, caster, target_pos)
	return true


func _spawn_cast_effect(spell: SpellData, caster: Regiment) -> void:
	## Spawn visual effect at caster when casting spell.
	var sfx = _get_spell_effects(caster)
	if not sfx:
		return

	var cast_pos: Vector3 = caster.global_position + Vector3(0, 1.5, 0)

	# Try sprite-based cast effect first
	if sfx.has_method("spawn_sprite_cast"):
		sfx.spawn_sprite_cast(cast_pos, spell.damage_type)
	else:
		sfx.spawn_cast_flash(cast_pos, spell.damage_type)


## Validate that the cast can proceed.
func _validate_cast(spell: SpellData, caster: Regiment, target_pos: Vector3) -> bool:
	if not spell or not caster:
		return false

	# Check unit can use this spell
	if not spell.can_unit_use(caster):
		return false

	# Check range
	var dist: float = caster.global_position.distance_to(target_pos)
	if dist > spell.range_distance:
		return false

	# Check stamina cost
	if spell.stamina_cost > 0.0 and caster.stamina:
		if caster.stamina.current_stamina < spell.stamina_cost:
			return false

	# Check ammo cost
	if spell.ammo_cost > 0:
		if caster.current_ammo < spell.ammo_cost:
			return false

	return true


## Consume resources for casting.
func _consume_resources(spell: SpellData, caster: Regiment) -> void:
	if spell.stamina_cost > 0.0 and caster.stamina:
		caster.stamina.consume_stamina(spell.stamina_cost)

	if spell.ammo_cost > 0:
		caster.current_ammo -= spell.ammo_cost


# === PROJECTILE SPELL ===

func _spell_to_projectile_config(spell: SpellData) -> Dictionary:
	## Maps SpellData properties to the projectile config format used by ProjectilePool.
	## Similar to WeaponClassData.get_projectile_config() but for spells.
	## Ensures all fields needed by projectile.apply_config() are present.
	var config: Dictionary = {
		# === MOVEMENT ===
		"speed": spell.projectile_speed,
		"arc_height": spell.projectile_arc,
		"lifetime": spell.range_distance / spell.projectile_speed + 2.0,  # Estimate from range

		# === HOMING ===
		"is_homing": spell.is_homing,
		"homing_strength": spell.homing_turn_rate / 60.0,  # Convert degrees/sec to lerp rate
		"homing_turn_rate": spell.homing_turn_rate,  # Direct pass for projectile

		# === PIERCING ===
		"max_pierces": 0,  # Spells don't pierce by default
		"pierce_damage_falloff": 0.25,

		# === AOE ===
		"aoe_radius": spell.aoe_radius,
		"aoe_damage_falloff": true,
		"aoe_min_damage_mult": spell.edge_damage_mult,

		# === COLLISION ===
		"collision_mask": 2,  # Units layer

		# === VISUAL TYPE ===
		"projectile_type": SPELL_DAMAGE_TO_PROJECTILE_TYPE.get(spell.damage_type, 2),  # Default MAGIC

		# === DAMAGE TYPE (for trail/impact coloring) ===
		"damage_type": spell.damage_type,

		# === TRAIL VISUALS ===
		"trail_color": spell.effect_color,
		"trail_particles": 30,
		"trail_lifetime": 0.35,

		# === IMPACT EFFECT ===
		"impact_effect": _get_impact_effect_for_damage_type(spell.damage_type),
	}

	# Add hazard info if spell creates one
	if spell.creates_hazard:
		config["leaves_hazard"] = true
		config["hazard_duration"] = spell.hazard_duration
		config["hazard_damage_per_sec"] = float(spell.hazard_tick_damage) / spell.hazard_tick_interval
		config["hazard_radius"] = spell.get_hazard_radius()

	return config


func _get_impact_effect_for_damage_type(damage_type: int) -> String:
	## Returns the impact effect name for the given damage type.
	match damage_type:
		SpellData.DamageType.FIRE:
			return "fire_burst"
		SpellData.DamageType.ICE:
			return "ice_shatter"
		SpellData.DamageType.LIGHTNING:
			return "lightning_strike"
		SpellData.DamageType.HOLY:
			return "magic_burst"
		SpellData.DamageType.DARK:
			return "magic_burst"
		_:
			return "explosion"


func _cast_projectile(spell: SpellData, caster: Regiment, target_pos: Vector3) -> void:
	## Cast a projectile spell toward target.
	## Uses shared ProjectilePool if available, falls back to SpellProjectile.

	var pool := _get_projectile_pool(caster)

	if pool:
		# Use shared ProjectilePool for better performance
		var config := _spell_to_projectile_config(spell)
		var spawn_pos: Vector3 = caster.global_position + Vector3(0, 1.5, 0)

		# Add scatter based on distance (6% scatter at max range)
		var distance := spawn_pos.distance_to(target_pos)
		var scatter_radius := distance * 0.06
		var scattered_target := target_pos
		scattered_target.x += randf_range(-scatter_radius, scatter_radius)
		scattered_target.z += randf_range(-scatter_radius, scatter_radius)

		var direction: Vector3 = (scattered_target - spawn_pos).normalized()

		var projectile = pool.spawn_configured(
			caster,
			spawn_pos,
			direction,
			null,  # No Regiment target, using position
			config
		)

		if projectile:
			# Store spell data on projectile for impact handling
			projectile.set_meta("spell_data", spell)
			projectile.set_meta("caster", caster)
			projectile.set_meta("target_pos", target_pos)

			# Connect signals for impact handling
			if projectile.has_signal("hit_target") and not projectile.hit_target.is_connected(_on_pool_projectile_hit):
				projectile.hit_target.connect(_on_pool_projectile_hit.bind(projectile))
			if projectile.has_signal("aoe_triggered") and not projectile.aoe_triggered.is_connected(_on_pool_projectile_aoe):
				projectile.aoe_triggered.connect(_on_pool_projectile_aoe.bind(projectile))

			if projectile.has_method("start_flight"):
				projectile.start_flight()

			_active_projectiles.append(projectile)
			spell_projectile_spawned.emit(projectile)
			return

	# Fallback to SpellProjectile if pool unavailable or exhausted
	var projectile := SpellProjectileClass.new()
	projectile.setup(spell, caster, target_pos)

	# Connect hit callback
	projectile.hit_target.connect(_on_projectile_hit.bind(spell, caster))

	# Add to scene
	var tree := caster.get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(projectile)
	else:
		projectile.queue_free()
		return
	_active_projectiles.append(projectile)

	spell_projectile_spawned.emit(projectile)


func _on_projectile_hit(hit_pos: Vector3, hit_regiment: Regiment, spell: SpellData, caster: Regiment) -> void:
	## Handle projectile impact (SpellProjectile fallback).
	# Apply damage to hit target
	if hit_regiment:
		_apply_spell_damage(spell, caster, hit_regiment)

	# Create AOE if spell has radius
	if spell.aoe_radius > 0.0:
		_apply_aoe_damage(spell, caster, hit_pos)

	# Create hazard if configured
	if spell.creates_hazard:
		_spawn_hazard_zone(spell, caster, hit_pos)

	# Play impact sound and visual
	_play_impact_sound(spell, hit_pos, caster)
	_spawn_impact_effect(spell, hit_pos, caster)


func _on_pool_projectile_hit(target: Node, damage_multiplier: float, projectile: Node) -> void:
	## Handle hit from ProjectilePool projectile.
	## Retrieves spell data from projectile metadata.
	if not is_instance_valid(projectile):
		return

	var spell: SpellData = projectile.get_meta("spell_data", null)
	var caster: Regiment = projectile.get_meta("caster", null)

	if not spell or not caster:
		return

	# Apply damage to hit target if it's a Regiment
	if target is Regiment and is_instance_valid(target):
		var hit_regiment: Regiment = target
		# Apply damage scaled by multiplier (for piercing falloff)
		var scaled_damage: int = maxi(1, int(float(spell.base_damage) * damage_multiplier))
		_apply_spell_damage_amount(spell, caster, hit_regiment, scaled_damage)

	# Get hit position from projectile
	var hit_pos: Vector3 = projectile.global_position

	# Create hazard if configured (mark as spawned to prevent double-spawn in AOE handler)
	if spell.creates_hazard and not projectile.get_meta("hazard_spawned", false):
		projectile.set_meta("hazard_spawned", true)
		_spawn_hazard_zone(spell, caster, hit_pos)

	# Play impact sound and visual
	_play_impact_sound(spell, hit_pos, caster)
	_spawn_impact_effect(spell, hit_pos, caster)


func _on_pool_projectile_aoe(impact_pos: Vector3, _radius: float, projectile: Node) -> void:
	## Handle AOE trigger from ProjectilePool projectile.
	## Applies area damage using spell data from projectile metadata.
	## Also spawns hazard zones for fire spells, incendiary rounds, etc.
	if not is_instance_valid(projectile):
		return

	var spell: SpellData = projectile.get_meta("spell_data", null)
	var caster: Regiment = projectile.get_meta("caster", null)

	if not spell or not caster:
		return

	# Apply AOE damage using spell's radius (may differ from projectile's)
	_apply_aoe_damage(spell, caster, impact_pos)

	# Spawn AOE visual effect
	_spawn_aoe_effect(spell, impact_pos, caster)

	# Create hazard if spell creates one (for AOE-only hits that bypass _on_pool_projectile_hit)
	# Check projectile meta flag to avoid double-spawning if hit was also called
	if spell.creates_hazard and not projectile.get_meta("hazard_spawned", false):
		projectile.set_meta("hazard_spawned", true)
		_spawn_hazard_zone(spell, caster, impact_pos)


# === AOE POINT SPELL ===

func _cast_aoe_point(spell: SpellData, caster: Regiment, target_pos: Vector3) -> void:
	## Cast area effect at target position.
	# Spawn visual effect immediately
	_spawn_aoe_effect(spell, target_pos, caster)

	# Apply damage to units in area
	_apply_aoe_damage(spell, caster, target_pos)

	# Create hazard if configured
	if spell.creates_hazard:
		_spawn_hazard_zone(spell, caster, target_pos)

	# Play impact sound
	_play_impact_sound(spell, target_pos, caster)


# === AOE SELF SPELL ===

func _cast_aoe_self(spell: SpellData, caster: Regiment) -> void:
	## Cast self-centered area effect (buffs/auras).
	var center_pos: Vector3 = caster.global_position

	# Spawn visual effect
	_spawn_aoe_effect(spell, center_pos, caster)

	# For buff spells, apply to friendly units
	if spell.effect_type == SpellData.EffectType.BUFF:
		_apply_buff_to_allies(spell, caster)
	elif spell.effect_type == SpellData.EffectType.DAMAGE:
		# Damage AOE (explosion centered on self)
		_apply_aoe_damage(spell, caster, center_pos)

	# Create hazard if configured
	if spell.creates_hazard:
		_spawn_hazard_zone(spell, caster, center_pos)


# === CONE SPELL ===

func _cast_cone(spell: SpellData, caster: Regiment, target_pos: Vector3) -> void:
	## Cast cone-shaped attack in direction of target.
	var origin: Vector3 = caster.global_position
	var direction: Vector3 = (target_pos - origin).normalized()
	direction.y = 0  # Flatten to horizontal

	# Spawn cone visual effect
	_spawn_cone_effect(spell, origin, direction, caster)

	# Find units in cone
	var targets := _get_units_in_cone(
		origin,
		direction,
		spell.cone_length,
		spell.cone_angle,
		caster
	)

	# Apply damage to all targets in cone
	for target in targets:
		_apply_spell_damage(spell, caster, target)

	# Play impact sound
	_play_impact_sound(spell, origin, caster)


# === BEAM SPELL ===

func _cast_beam(spell: SpellData, caster: Regiment, target_pos: Vector3) -> void:
	## Cast continuous beam toward target.
	var beam := SpellBeamClass.new()
	beam.setup(spell, caster, target_pos)

	# Connect tick callback
	beam.beam_tick.connect(_on_beam_tick.bind(spell, caster))
	beam.beam_ended.connect(_on_beam_ended.bind(caster))

	# Add to scene
	var tree := caster.get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(beam)
	else:
		beam.queue_free()
		return

	# Track active beam
	_active_beams[caster] = {
		"beam": beam,
		"spell": spell
	}


func _on_beam_tick(hit_regiment: Regiment, spell: SpellData, caster: Regiment) -> void:
	## Handle beam damage tick.
	if hit_regiment:
		# Reduced damage per tick for beams
		var tick_damage: int = maxi(1, spell.base_damage / 5)
		_apply_spell_damage_amount(spell, caster, hit_regiment, tick_damage)


func _on_beam_ended(caster: Regiment) -> void:
	## Clean up beam reference.
	_active_beams.erase(caster)


# === DAMAGE APPLICATION ===

func _apply_spell_damage(spell: SpellData, caster: Regiment, target: Regiment) -> void:
	## Apply full spell damage to a single target.
	_apply_spell_damage_amount(spell, caster, target, spell.base_damage)


func _apply_spell_damage_amount(spell: SpellData, caster: Regiment, target: Regiment, damage: int) -> void:
	## Apply specified damage amount with spell effects.
	if not is_instance_valid(target):
		return
	if target.state == Regiment.State.DEAD:
		return

	# Apply damage
	target.take_casualties(damage)

	# Apply morale damage
	var morale_damage: float = damage * spell.morale_damage_mult
	MoraleSystem.apply_morale_damage(target, morale_damage)

	# Visual feedback
	var cfx = _get_combat_effects(caster)
	if cfx:
		var hit_pos: Vector3 = target.global_position + Vector3(0, 1.0, 0)
		match spell.damage_type:
			SpellData.DamageType.FIRE:
				cfx.spawn_melee_hit(hit_pos)
			SpellData.DamageType.ICE:
				cfx.spawn_block(hit_pos)
			_:
				cfx.spawn_ranged_hit(hit_pos)

	# Track kills for veterancy
	if caster.veterancy and damage > 0:
		caster.veterancy.add_kill()

	# Emit signal
	spell_hit.emit(spell, target, damage)
	CombatManager.damage_dealt.emit(target, damage, caster, "spell_%s" % spell.id)


func _apply_aoe_damage(spell: SpellData, caster: Regiment, center: Vector3) -> void:
	## Apply AOE damage to all enemy units in radius.
	var targets := _get_enemy_regiments_in_radius(center, spell.aoe_radius, caster)

	for target in targets:
		# Calculate distance falloff
		var dist: float = target.global_position.distance_to(center)
		var falloff: float = 1.0 - (dist / spell.aoe_radius) * (1.0 - spell.edge_damage_mult)
		falloff = clampf(falloff, spell.edge_damage_mult, 1.0)

		var damage: int = maxi(1, int(float(spell.base_damage) * falloff))
		_apply_spell_damage_amount(spell, caster, target, damage)


func _apply_buff_to_allies(spell: SpellData, caster: Regiment) -> void:
	## Apply buff effects to friendly units in radius.
	var allies := _get_friendly_regiments_in_radius(
		caster.global_position,
		spell.aoe_radius,
		caster
	)

	# Include self
	allies.append(caster)

	for ally in allies:
		_apply_buff_effect(spell, ally)


func _apply_buff_effect(spell: SpellData, target: Regiment) -> void:
	## Apply a buff effect to a regiment.
	# This would integrate with a buff system if one exists
	# For now, emit signals and apply immediate effects

	# Apply inspire-like effect if attack modifier > 1
	if spell.attack_modifier > 1.0:
		CombatState.set_inspired(target, true, "spell_buff")

	# Apply morale boost
	if spell.morale_per_second > 0.0 and target.unit_morale:
		var event := MoraleEvent.create(
			MoraleEvent.Source.VICTORY_CHEER,
			spell.morale_per_second * spell.effect_duration,
			target.global_position
		)
		target.unit_morale.apply_event_to_all(event)

	# Visual feedback
	var afx = _get_ability_effects(target)
	if afx:
		afx.spawn_inspire_effect(target)


# === SPATIAL QUERIES ===

func _get_enemy_regiments_in_radius(center: Vector3, radius: float, caster: Regiment) -> Array[Regiment]:
	## Get enemy regiments within radius.
	var result: Array[Regiment] = []
	if not AIAutoload or not AIAutoload.spatial_hash:
		return result
	var my_faction: int = 0 if caster.is_player_controlled else 1
	var enemy_faction: int = 1 if my_faction == 0 else 0

	var regiments: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		center,
		radius,
		enemy_faction
	)

	var count: int = 0
	for node in regiments:
		if count >= MAX_AOE_TARGETS:
			break
		if node is Regiment and node.state != Regiment.State.DEAD:
			result.append(node)
			count += 1

	return result


func _get_friendly_regiments_in_radius(center: Vector3, radius: float, caster: Regiment) -> Array[Regiment]:
	## Get friendly regiments within radius.
	var result: Array[Regiment] = []
	if not AIAutoload or not AIAutoload.spatial_hash:
		return result
	var my_faction: int = 0 if caster.is_player_controlled else 1

	var regiments: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		center,
		radius,
		my_faction
	)

	var count: int = 0
	for node in regiments:
		if count >= MAX_AOE_TARGETS:
			break
		if node is Regiment and node != caster and node.state != Regiment.State.DEAD:
			result.append(node)
			count += 1

	return result


func _get_units_in_cone(origin: Vector3, direction: Vector3, length: float, angle_deg: float, caster: Regiment) -> Array[Regiment]:
	## Get enemy units within cone area.
	var result: Array[Regiment] = []
	if not AIAutoload or not AIAutoload.spatial_hash:
		return result
	var my_faction: int = 0 if caster.is_player_controlled else 1
	var enemy_faction: int = 1 if my_faction == 0 else 0

	# Get all regiments in bounding radius
	var regiments: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		origin,
		length,
		enemy_faction
	)

	var half_angle: float = deg_to_rad(angle_deg / 2.0)

	for node in regiments:
		if result.size() >= MAX_AOE_TARGETS:
			break
		if not node is Regiment:
			continue
		if node.state == Regiment.State.DEAD:
			continue

		var regiment: Regiment = node
		var to_target: Vector3 = regiment.global_position - origin
		to_target.y = 0

		# Check distance
		if to_target.length() > length:
			continue

		# Check angle
		var angle: float = to_target.normalized().angle_to(direction)
		if angle <= half_angle:
			result.append(regiment)

	return result


# === VISUAL EFFECTS ===

func _spawn_aoe_effect(spell: SpellData, position: Vector3, caster: Regiment) -> void:
	## Spawn expanding ring effect for AOE.
	# Use SpellEffects if available, fallback to AbilityEffects
	var sfx = _get_spell_effects(caster)
	if sfx:
		sfx.spawn_aoe_ring(position, spell.damage_type, spell.aoe_radius)
		sfx.spawn_impact_burst(position, spell.damage_type, spell.aoe_radius)
	else:
		var afx = _get_ability_effects(caster)
		if afx:
			afx.spawn_war_cry_effect(position)


func _spawn_cone_effect(spell: SpellData, origin: Vector3, direction: Vector3, caster: Regiment) -> void:
	## Spawn cone-shaped particle effect using SpellEffects autoload.
	var sfx = _get_spell_effects(caster)
	if sfx:
		sfx.spawn_cone_effect(origin, direction, spell.cone_angle, spell.cone_length, spell.damage_type)


func _spawn_impact_effect(spell: SpellData, position: Vector3, caster: Regiment) -> void:
	## Spawn impact visual at position.
	# Try sprite-based impact first
	var sfx = _get_spell_effects(caster)
	if sfx and sfx.has_method("spawn_sprite_impact"):
		sfx.spawn_sprite_impact(position, spell.damage_type, max(spell.aoe_radius, 3.0))
		return

	# Fallback to particle effects
	var cfx = _get_combat_effects(caster)
	if cfx:
		match spell.damage_type:
			SpellData.DamageType.FIRE:
				cfx.spawn_melee_hit(position)
			SpellData.DamageType.ICE:
				cfx.spawn_block(position)
			SpellData.DamageType.LIGHTNING:
				cfx.spawn_block(position)
			_:
				cfx.spawn_death(position)


func _spawn_hazard_zone(spell: SpellData, caster: Regiment, position: Vector3) -> void:
	## Create persistent hazard zone at position using unified factory method.
	var config: Dictionary = {
		"radius": spell.get_hazard_radius(),
		"damage_per_tick": spell.hazard_tick_damage,
		"tick_interval": spell.hazard_tick_interval,
		"duration": spell.hazard_duration,
		"damage_type": spell.damage_type,
		"color": spell.effect_color,
		"secondary_color": spell.secondary_color,
	}

	var hazard := HazardZoneClass.create_from_config(config, position, caster)

	var tree := caster.get_tree()
	if tree and tree.current_scene:
		tree.current_scene.add_child(hazard)
	else:
		hazard.queue_free()


# === AUDIO ===

func _play_cast_sound(spell: SpellData, position: Vector3, caster: Regiment) -> void:
	## Play spell cast sound effect.
	var audio = _get_audio_manager(caster)
	if audio and spell.cast_sound:
		audio.play_sfx(spell.cast_sound, position)


func _play_impact_sound(spell: SpellData, position: Vector3, caster: Regiment) -> void:
	## Play spell impact sound effect.
	var audio = _get_audio_manager(caster)
	if audio and spell.impact_sound:
		audio.play_sfx(spell.impact_sound, position)


# === CLEANUP ===

func cleanup() -> void:
	## Clean up all active spell effects.
	for projectile in _active_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_active_projectiles.clear()

	for caster in _active_beams:
		var data: Dictionary = _active_beams[caster]
		if is_instance_valid(data["beam"]):
			data["beam"].queue_free()
	_active_beams.clear()
