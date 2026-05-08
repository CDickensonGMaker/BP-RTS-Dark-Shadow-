class_name WeaponClassData
extends RefCounted

## Defines behavior for each WeaponClass.
## Single source of truth for reload times, fire patterns, projectile base configs.
## DamageType is unified with SpellData.DamageType for consistent damage effects.

# Reference SpellData's DamageType enum for unified damage typing
const SpellDataScript = preload("res://battle_system/data/spell_data.gd")

## Fire pattern determines how soldiers in a regiment release shots over time.
enum FirePattern {
	VOLLEY,     # All soldiers fire on the same tick, then all reload together
	STAGGER,    # Soldiers fire continuously, each on their own reload cycle
	SINGLE,     # One projectile per regiment per reload (crewed weapons)
}

## Trajectory determines arc and LOS rules.
enum Trajectory {
	FLAT,       # Direct fire, requires LOS, can't shoot over allies
	ARCING,     # Mild arc, can clear short obstacles, soft LOS
	HIGH_ARC,   # Indirect fire, ignores LOS over units, lobs over walls
	CONE,       # Breath weapon cone (short range, wide spread)
}

## Round type determines ammo behavior for artillery/siege weapons.
## Infantry weapons (bow, crossbow, handgun) use STANDARD only.
enum RoundType {
	STANDARD,    # Default ammo - uses weapon's base behavior
	GRAPESHOT,   # Anti-infantry - spawns spread of small projectiles (shotgun)
	SHRAPNEL,    # Anti-infantry - explodes in air above target, rains fragments
	SOLID_SHOT,  # Anti-armor - heavy ball that penetrates multiple ranks
	EXPLOSIVE,   # AOE - impact detonation with blast radius
	CHAIN_SHOT,  # Anti-large - spinning chain between two balls, anti-cavalry/monster
	INCENDIARY,  # Fire damage - leaves burning hazard zone on impact
}

## Per-round-type behavior modifiers.
## These override or augment the base WeaponDef properties.
class RoundDef extends RefCounted:
	var damage_modifier: float = 1.0         # Multiplier to base damage
	var range_modifier: float = 1.0          # Multiplier to base range
	var accuracy_modifier: float = 1.0       # Multiplier to hit chance
	var reload_modifier: float = 1.0         # Multiplier to reload time

	# Spread behavior (grapeshot, shrapnel)
	var sub_projectile_count: int = 1        # 1 = single projectile, >1 = spread
	var spread_angle: float = 0.0            # Cone angle for spread (degrees)
	var spread_random: bool = false          # Random vs uniform spread pattern

	# Pierce behavior (solid shot, chain shot)
	var pierce_override: int = -1            # -1 = use weapon default, >=0 = override
	var anti_large_bonus: float = 0.0        # Extra damage vs cavalry/monsters

	# AOE behavior (explosive, shrapnel, incendiary)
	var aoe_override: float = -1.0           # -1 = use weapon default, >=0 = override radius
	var airburst_height: float = 0.0         # 0 = ground impact, >0 = airburst above target
	var leaves_hazard: bool = false          # Creates lingering damage zone
	var hazard_duration: float = 0.0         # How long hazard lasts
	var hazard_damage_per_sec: float = 0.0   # Damage per second in hazard

	# Visual overrides
	var visual_type_override: String = ""    # "" = use weapon default
	var trail_color_override: Color = Color(-1, -1, -1, -1)  # Invalid = use default

	# Damage type override (for incendiary rounds changing PHYSICAL to FIRE)
	var damage_type_override: int = -1       # -1 = use weapon default, >=0 = override (SpellData.DamageType)


## Per-class definition.
class WeaponDef extends RefCounted:
	var fire_pattern: int = FirePattern.VOLLEY
	var trajectory: int = Trajectory.FLAT
	var reload_time: float = 3.0           # Seconds per shooter to reload
	var soldiers_per_shot: int = 1         # 1 = each soldier fires; 2-3 = crew weapons
	var requires_los: bool = true          # If false, can fire through/over things
	var projectile_speed: float = 35.0
	var arc_height: float = 8.0
	var lifetime: float = 4.0
	var hit_radius: float = 1.5            # Direct-hit proximity check
	var aoe_radius: float = 0.0            # 0 = single-target, >0 = explodes
	var aoe_damage_falloff: bool = true
	var max_pierces: int = 0
	var pierce_falloff: float = 0.25
	var visual_type: String = "arrow"      # "arrow", "bolt", "bullet", "shell", "flame", "magic"
	var has_cooldown: bool = false         # For breath/magic - uses breath_cooldown from RegimentData
	var cone_angle: float = 0.0            # For breath weapons - cone spread in degrees
	var cone_length: float = 0.0           # For breath weapons - cone range

	# Damage type for special effects (FIRE = panic, POISON = DoT, ICE = slow)
	# Uses SpellData.DamageType enum values for unified damage system
	var damage_type: int = 0               # Default PHYSICAL (SpellData.DamageType.PHYSICAL)

	# Homing properties (for spell-style projectiles like MAGIC_MISSILE)
	var is_homing: bool = false            # Whether projectile homes toward target
	var homing_turn_rate: float = 0.0      # Degrees per second for slerp turning

	# Particle effect settings
	var trail_enabled: bool = true
	var trail_color: Color = Color(0.4, 0.25, 0.1, 0.8)
	var trail_particles: int = 20
	var trail_lifetime: float = 0.3
	var impact_effect: String = ""         # "explosion", "fire_burst", "ice_shatter", etc.


# All weapon class definitions, keyed by RegimentData.WeaponClass enum value.
static var DEFINITIONS: Dictionary = {}
# All round type definitions, keyed by RoundType enum value.
static var ROUND_DEFINITIONS: Dictionary = {}
static var _initialized: bool = false


static func _init_round_definitions() -> void:
	## Initialize round type definitions.

	# === STANDARD ===
	# Default ammo - no modifications, uses base weapon stats
	var standard := RoundDef.new()
	ROUND_DEFINITIONS[RoundType.STANDARD] = standard

	# === GRAPESHOT ===
	# Anti-infantry shotgun blast - many small projectiles in cone
	# Short range, devastating to massed infantry, useless vs armor
	var grapeshot := RoundDef.new()
	grapeshot.damage_modifier = 0.3           # Each pellet does 30% damage
	grapeshot.range_modifier = 0.5            # Half range (close quarters)
	grapeshot.accuracy_modifier = 1.5         # Easier to hit something with spread
	grapeshot.reload_modifier = 0.8           # Faster to load loose shot
	grapeshot.sub_projectile_count = 12       # 12 pellets per shot
	grapeshot.spread_angle = 30.0             # 30-degree cone
	grapeshot.spread_random = true            # Random scatter pattern
	grapeshot.pierce_override = 0             # Pellets don't pierce
	grapeshot.visual_type_override = "pellet"
	grapeshot.trail_color_override = Color(0.4, 0.4, 0.4, 0.6)
	ROUND_DEFINITIONS[RoundType.GRAPESHOT] = grapeshot

	# === SHRAPNEL ===
	# Airburst fragmentation - explodes above target, rains metal
	# Excellent vs infantry in the open, less effective vs armored
	var shrapnel := RoundDef.new()
	shrapnel.damage_modifier = 0.6            # Less damage per fragment
	shrapnel.range_modifier = 0.9             # Slightly reduced range
	shrapnel.accuracy_modifier = 0.8          # Airburst timing is tricky
	shrapnel.reload_modifier = 1.2            # Fuse setting takes time
	shrapnel.sub_projectile_count = 8         # 8 fragments rain down
	shrapnel.spread_angle = 45.0              # Wide coverage
	shrapnel.spread_random = true
	shrapnel.airburst_height = 6.0            # Explodes 6 units above ground
	shrapnel.aoe_override = 6.0               # Large effect radius
	shrapnel.visual_type_override = "shell"
	shrapnel.trail_color_override = Color(0.3, 0.3, 0.3, 0.8)
	ROUND_DEFINITIONS[RoundType.SHRAPNEL] = shrapnel

	# === SOLID_SHOT ===
	# Heavy iron ball - maximum armor penetration and rank pierce
	# Best vs armored targets and dense formations
	var solid_shot := RoundDef.new()
	solid_shot.damage_modifier = 1.2          # Heavy impact
	solid_shot.range_modifier = 1.1           # Better ballistics
	solid_shot.accuracy_modifier = 1.0        # Standard accuracy
	solid_shot.reload_modifier = 1.0          # Standard reload
	solid_shot.pierce_override = 5            # Bowls through 5 ranks
	solid_shot.anti_large_bonus = 0.3         # +30% vs large targets
	solid_shot.visual_type_override = "shell"
	solid_shot.trail_color_override = Color(0.15, 0.15, 0.15, 0.9)  # Dark iron
	ROUND_DEFINITIONS[RoundType.SOLID_SHOT] = solid_shot

	# === EXPLOSIVE ===
	# Impact-detonating shell - AOE blast damage on hit
	# Good all-rounder, effective vs all target types
	var explosive := RoundDef.new()
	explosive.damage_modifier = 0.8           # Direct hit does less
	explosive.range_modifier = 1.0            # Standard range
	explosive.accuracy_modifier = 0.9         # Slightly harder to hit
	explosive.reload_modifier = 1.3           # Careful handling required
	explosive.aoe_override = 5.0              # 5-unit blast radius
	explosive.pierce_override = 0             # Explodes on first contact
	explosive.visual_type_override = "shell"
	explosive.trail_color_override = Color(0.5, 0.3, 0.1, 0.8)  # Powder smoke
	ROUND_DEFINITIONS[RoundType.EXPLOSIVE] = explosive

	# === CHAIN_SHOT ===
	# Two balls connected by chain - anti-cavalry/monster specialist
	# Devastating vs large targets, poor vs infantry
	var chain_shot := RoundDef.new()
	chain_shot.damage_modifier = 0.7          # Less raw damage
	chain_shot.range_modifier = 0.7           # Poor aerodynamics
	chain_shot.accuracy_modifier = 0.6        # Hard to aim spinning shot
	chain_shot.reload_modifier = 1.1          # Slightly slower to load
	chain_shot.anti_large_bonus = 1.5         # +150% vs cavalry/monsters!
	chain_shot.pierce_override = 2            # Can hit 2 large targets
	chain_shot.visual_type_override = "chain"
	chain_shot.trail_color_override = Color(0.2, 0.2, 0.25, 0.8)
	ROUND_DEFINITIONS[RoundType.CHAIN_SHOT] = chain_shot

	# === INCENDIARY ===
	# Fire shell - leaves burning hazard zone on impact
	# Good for area denial and morale damage
	var incendiary := RoundDef.new()
	incendiary.damage_modifier = 0.6          # Impact damage is low
	incendiary.range_modifier = 0.9           # Slightly reduced range
	incendiary.accuracy_modifier = 0.9        # Standard accuracy
	incendiary.reload_modifier = 1.4          # Dangerous to load
	incendiary.aoe_override = 4.0             # Fire spreads
	incendiary.leaves_hazard = true           # Creates fire zone
	incendiary.hazard_duration = 8.0          # Burns for 8 seconds
	incendiary.hazard_damage_per_sec = 3.0    # 3 damage per second in fire
	incendiary.visual_type_override = "flame"
	incendiary.trail_color_override = Color(1.0, 0.4, 0.1, 0.9)  # Fire trail
	incendiary.damage_type_override = SpellDataScript.DamageType.FIRE  # Override to FIRE damage
	ROUND_DEFINITIONS[RoundType.INCENDIARY] = incendiary


static func _init_definitions() -> void:
	if _initialized:
		return
	_initialized = true

	_init_round_definitions()

	# === BOW ===
	var bow := WeaponDef.new()
	bow.fire_pattern = FirePattern.VOLLEY
	bow.trajectory = Trajectory.ARCING
	bow.reload_time = 3.0
	bow.soldiers_per_shot = 1
	bow.requires_los = false  # Soft LOS - can arc over short obstacles
	bow.projectile_speed = 35.0
	bow.arc_height = 8.0
	bow.lifetime = 4.0
	bow.visual_type = "arrow"
	bow.trail_color = Color(0.4, 0.25, 0.1, 0.8)  # Brown
	DEFINITIONS[RegimentData.WeaponClass.BOW] = bow

	# === CROSSBOW ===
	var crossbow := WeaponDef.new()
	crossbow.fire_pattern = FirePattern.STAGGER
	crossbow.trajectory = Trajectory.FLAT
	crossbow.reload_time = 5.0
	crossbow.soldiers_per_shot = 1
	crossbow.requires_los = true
	crossbow.projectile_speed = 50.0
	crossbow.arc_height = 3.0
	crossbow.lifetime = 3.0
	crossbow.max_pierces = 1
	crossbow.pierce_falloff = 0.3
	crossbow.visual_type = "bolt"
	crossbow.trail_color = Color(0.3, 0.3, 0.35, 0.8)  # Gray
	DEFINITIONS[RegimentData.WeaponClass.CROSSBOW] = crossbow

	# === HANDGUN ===
	var handgun := WeaponDef.new()
	handgun.fire_pattern = FirePattern.STAGGER
	handgun.trajectory = Trajectory.FLAT
	handgun.reload_time = 7.0
	handgun.soldiers_per_shot = 1
	handgun.requires_los = true
	handgun.projectile_speed = 80.0  # Bullets are fast, near-instant feel
	handgun.arc_height = 1.0
	handgun.lifetime = 2.0
	handgun.max_pierces = 1  # Heavy slug pierces light armor
	handgun.pierce_falloff = 0.5
	handgun.visual_type = "bullet"
	handgun.trail_color = Color(0.6, 0.6, 0.6, 0.5)  # Light gray smoke
	handgun.trail_particles = 10
	handgun.trail_lifetime = 0.15
	DEFINITIONS[RegimentData.WeaponClass.HANDGUN] = handgun

	# === THROWN ===
	var thrown := WeaponDef.new()
	thrown.fire_pattern = FirePattern.VOLLEY
	thrown.trajectory = Trajectory.ARCING
	thrown.reload_time = 4.0
	thrown.soldiers_per_shot = 1
	thrown.requires_los = false
	thrown.projectile_speed = 28.0
	thrown.arc_height = 6.0
	thrown.lifetime = 3.5
	thrown.visual_type = "arrow"  # Reuse arrow until we have javelin sprite
	thrown.trail_color = Color(0.5, 0.35, 0.2, 0.8)  # Darker brown
	DEFINITIONS[RegimentData.WeaponClass.THROWN] = thrown

	# === CANNON ===
	# Historical: ~60-90 seconds per shot. Game compression ~6x for 7-25 min battles.
	# First shot fires fast (80% pre-loaded in RegimentFiring) = ~3s first shot.
	var cannon := WeaponDef.new()
	cannon.fire_pattern = FirePattern.SINGLE
	cannon.trajectory = Trajectory.FLAT
	cannon.reload_time = 15.0  # Subsequent shots: 15 seconds
	cannon.soldiers_per_shot = 2  # 2-crew minimum; 0 crew = can't fire
	cannon.requires_los = true
	cannon.projectile_speed = 70.0
	cannon.arc_height = 4.0  # Slight arc, mostly direct
	cannon.lifetime = 4.0
	cannon.aoe_radius = 4.0  # Cannonball explosion - hits nearby soldiers
	cannon.aoe_damage_falloff = true
	cannon.max_pierces = 2  # Punches through 2 ranks before exploding
	cannon.pierce_falloff = 0.20
	cannon.visual_type = "shell"  # Dark sphere
	cannon.trail_color = Color(0.2, 0.2, 0.2, 0.9)  # Dark smoke
	cannon.trail_particles = 30
	cannon.trail_lifetime = 0.5
	cannon.impact_effect = "explosion"
	DEFINITIONS[RegimentData.WeaponClass.CANNON] = cannon

	# === MORTAR ===
	# Slower than cannon due to high-arc loading complexity.
	# First shot: ~4s (80% pre-loaded), subsequent: 20s
	var mortar := WeaponDef.new()
	mortar.fire_pattern = FirePattern.SINGLE
	mortar.trajectory = Trajectory.HIGH_ARC
	mortar.reload_time = 20.0
	mortar.soldiers_per_shot = 2  # Mortars often 2-3 crew
	mortar.requires_los = false  # Indirect fire - main differentiator
	mortar.projectile_speed = 25.0
	mortar.arc_height = 25.0  # High lob
	mortar.lifetime = 6.0
	mortar.aoe_radius = 5.0
	mortar.aoe_damage_falloff = true
	mortar.hit_radius = 3.0
	mortar.visual_type = "shell"
	mortar.trail_color = Color(0.3, 0.3, 0.3, 0.8)  # Gray smoke
	mortar.trail_particles = 25
	mortar.trail_lifetime = 0.6
	mortar.impact_effect = "explosion"
	DEFINITIONS[RegimentData.WeaponClass.MORTAR] = mortar

	# === WAR_MACHINE ===
	var war_machine := WeaponDef.new()
	war_machine.fire_pattern = FirePattern.SINGLE
	war_machine.trajectory = Trajectory.FLAT  # Default; overridden per-unit
	war_machine.reload_time = 8.0
	war_machine.soldiers_per_shot = 2
	war_machine.requires_los = true
	war_machine.projectile_speed = 40.0
	war_machine.arc_height = 5.0
	war_machine.lifetime = 4.0
	war_machine.aoe_radius = 3.0
	war_machine.visual_type = "magic"  # Will be overridden per-unit
	war_machine.trail_color = Color(0.2, 0.8, 0.2, 0.8)  # Green warpstone
	war_machine.impact_effect = "explosion"
	DEFINITIONS[RegimentData.WeaponClass.WAR_MACHINE] = war_machine

	# === BREATH_FIRE ===
	var breath_fire := WeaponDef.new()
	breath_fire.fire_pattern = FirePattern.SINGLE
	breath_fire.trajectory = Trajectory.CONE
	breath_fire.reload_time = 8.0  # Base; uses breath_cooldown from RegimentData
	breath_fire.soldiers_per_shot = 1
	breath_fire.requires_los = true
	breath_fire.projectile_speed = 45.0
	breath_fire.arc_height = 2.0
	breath_fire.lifetime = 1.5
	breath_fire.aoe_radius = 4.0
	breath_fire.aoe_damage_falloff = true
	breath_fire.visual_type = "flame"
	breath_fire.has_cooldown = true  # Uses breath_cooldown from RegimentData
	breath_fire.cone_angle = 45.0  # 45-degree cone
	breath_fire.cone_length = 20.0  # 20 unit range
	breath_fire.damage_type = SpellDataScript.DamageType.FIRE  # Fire damage - causes morale panic
	breath_fire.trail_enabled = true
	breath_fire.trail_color = Color(1.0, 0.5, 0.1, 0.9)  # Orange fire
	breath_fire.trail_particles = 40
	breath_fire.trail_lifetime = 0.4
	breath_fire.impact_effect = "fire_burst"
	DEFINITIONS[RegimentData.WeaponClass.BREATH_FIRE] = breath_fire

	# === BREATH_POISON ===
	var breath_poison := WeaponDef.new()
	breath_poison.fire_pattern = FirePattern.SINGLE
	breath_poison.trajectory = Trajectory.CONE
	breath_poison.reload_time = 10.0
	breath_poison.soldiers_per_shot = 1
	breath_poison.requires_los = true
	breath_poison.projectile_speed = 35.0
	breath_poison.arc_height = 3.0
	breath_poison.lifetime = 2.0
	breath_poison.aoe_radius = 5.0
	breath_poison.aoe_damage_falloff = true
	breath_poison.visual_type = "magic"  # Green cloud
	breath_poison.has_cooldown = true
	breath_poison.cone_angle = 60.0  # Wider cone
	breath_poison.cone_length = 15.0
	breath_poison.damage_type = SpellDataScript.DamageType.POISON  # Poison damage - DoT effect
	breath_poison.trail_color = Color(0.2, 0.8, 0.2, 0.8)  # Green poison
	breath_poison.trail_particles = 35
	breath_poison.trail_lifetime = 0.5
	breath_poison.impact_effect = "poison_cloud"
	DEFINITIONS[RegimentData.WeaponClass.BREATH_POISON] = breath_poison

	# === MAGIC_MISSILE ===
	var magic_missile := WeaponDef.new()
	magic_missile.fire_pattern = FirePattern.SINGLE
	magic_missile.trajectory = Trajectory.FLAT
	magic_missile.reload_time = 6.0
	magic_missile.soldiers_per_shot = 1
	magic_missile.requires_los = true
	magic_missile.projectile_speed = 50.0
	magic_missile.arc_height = 2.0
	magic_missile.lifetime = 3.0
	magic_missile.aoe_radius = 2.0
	magic_missile.aoe_damage_falloff = true
	magic_missile.visual_type = "magic"
	magic_missile.has_cooldown = true
	magic_missile.damage_type = SpellDataScript.DamageType.FIRE  # Default FIRE (wizard type may vary)
	magic_missile.is_homing = true                     # Homes toward target
	magic_missile.homing_turn_rate = 90.0              # 90 degrees per second
	magic_missile.trail_color = Color(0.3, 0.5, 1.0, 0.9)  # Blue magic
	magic_missile.trail_particles = 30
	magic_missile.trail_lifetime = 0.35
	magic_missile.impact_effect = "magic_burst"
	DEFINITIONS[RegimentData.WeaponClass.MAGIC_MISSILE] = magic_missile


static func get_def(weapon_class: int) -> WeaponDef:
	## Returns the WeaponDef for the given weapon class, or null if not found.
	if not _initialized:
		_init_definitions()
	return DEFINITIONS.get(weapon_class, null)


static func get_reload_time(weapon_class: int, regiment_data: RegimentData = null) -> float:
	## Returns the reload time for a weapon class.
	## For breath/magic weapons, uses regiment_data.breath_cooldown if available.
	var def := get_def(weapon_class)
	if not def:
		return 3.0  # Fallback

	if def.has_cooldown and regiment_data:
		return regiment_data.breath_cooldown

	return def.reload_time


static func get_projectile_config(weapon_class: int) -> Dictionary:
	## Returns a projectile configuration dictionary for CombatManager.
	var def := get_def(weapon_class)
	if not def:
		return {}

	return {
		"speed": def.projectile_speed,
		"arc_height": def.arc_height,
		"is_homing": def.is_homing,
		"homing_turn_rate": def.homing_turn_rate,
		"max_pierces": def.max_pierces,
		"pierce_damage_falloff": def.pierce_falloff,
		"aoe_radius": def.aoe_radius,
		"aoe_damage_falloff": def.aoe_damage_falloff,
		"lifetime": def.lifetime,
		"collision_mask": 2,
		"hit_radius": def.hit_radius,
		"trajectory": def.trajectory,
		"visual_type": def.visual_type,
		"trail_color": def.trail_color,
		"trail_particles": def.trail_particles,
		"trail_lifetime": def.trail_lifetime,
		"impact_effect": def.impact_effect,
		"cone_angle": def.cone_angle,
		"cone_length": def.cone_length,
		"damage_type": def.damage_type,
	}


static func get_round_def(round_type: int) -> RoundDef:
	## Returns the RoundDef for the given round type, or null if not found.
	if not _initialized:
		_init_definitions()
	return ROUND_DEFINITIONS.get(round_type, null)


static func is_artillery_weapon(weapon_class: int) -> bool:
	## Returns true if the weapon class is an artillery/siege weapon that supports ammo types.
	return weapon_class in [
		RegimentData.WeaponClass.CANNON,
		RegimentData.WeaponClass.MORTAR,
		RegimentData.WeaponClass.WAR_MACHINE,
	]


static func get_available_rounds(weapon_class: int) -> Array[int]:
	## Returns the valid round types for a given weapon class.
	## Infantry weapons only use STANDARD. Artillery can use all round types.
	if not is_artillery_weapon(weapon_class):
		return [RoundType.STANDARD]

	# Artillery weapons can use all round types
	return [
		RoundType.STANDARD,
		RoundType.GRAPESHOT,
		RoundType.SHRAPNEL,
		RoundType.SOLID_SHOT,
		RoundType.EXPLOSIVE,
		RoundType.CHAIN_SHOT,
		RoundType.INCENDIARY,
	]


static func get_round_type_name(round_type: int) -> String:
	## Returns a human-readable name for the round type.
	match round_type:
		RoundType.STANDARD:
			return "Standard"
		RoundType.GRAPESHOT:
			return "Grapeshot"
		RoundType.SHRAPNEL:
			return "Shrapnel"
		RoundType.SOLID_SHOT:
			return "Solid Shot"
		RoundType.EXPLOSIVE:
			return "Explosive"
		RoundType.CHAIN_SHOT:
			return "Chain Shot"
		RoundType.INCENDIARY:
			return "Incendiary"
		_:
			return "Unknown"


static func get_projectile_config_with_round(weapon_class: int, round_type: int) -> Dictionary:
	## Returns a projectile config dictionary with round type modifiers applied.
	## Merges round modifiers onto the weapon's base stats.
	var base_config := get_projectile_config(weapon_class)
	if base_config.is_empty():
		return {}

	var weapon_def := get_def(weapon_class)
	var round_def := get_round_def(round_type)
	if not round_def:
		return base_config

	# For non-artillery weapons, ignore round modifiers (always STANDARD behavior)
	if not is_artillery_weapon(weapon_class):
		return base_config

	# Apply round modifiers to base config
	var config := base_config.duplicate()

	# Apply range modifier to speed (affects effective range via travel time)
	config["speed"] = weapon_def.projectile_speed * round_def.range_modifier

	# Apply pierce override if specified
	if round_def.pierce_override >= 0:
		config["max_pierces"] = round_def.pierce_override

	# Apply AOE override if specified
	if round_def.aoe_override >= 0.0:
		config["aoe_radius"] = round_def.aoe_override

	# Apply visual overrides if specified
	if round_def.visual_type_override != "":
		config["visual_type"] = round_def.visual_type_override

	# Check for valid color override (not the invalid sentinel color)
	if round_def.trail_color_override.r >= 0.0:
		config["trail_color"] = round_def.trail_color_override

	# Add round-specific properties for projectile system to use
	config["round_type"] = round_type
	config["damage_modifier"] = round_def.damage_modifier
	config["accuracy_modifier"] = round_def.accuracy_modifier
	config["reload_modifier"] = round_def.reload_modifier
	config["anti_large_bonus"] = round_def.anti_large_bonus

	# Spread behavior (grapeshot, shrapnel)
	config["sub_projectile_count"] = round_def.sub_projectile_count
	config["spread_angle"] = round_def.spread_angle
	config["spread_random"] = round_def.spread_random

	# Airburst and hazard behavior
	config["airburst_height"] = round_def.airburst_height
	config["leaves_hazard"] = round_def.leaves_hazard
	config["hazard_duration"] = round_def.hazard_duration
	config["hazard_damage_per_sec"] = round_def.hazard_damage_per_sec

	# Apply damage type override if specified (e.g., INCENDIARY rounds = FIRE)
	if round_def.damage_type_override >= 0:
		config["damage_type"] = round_def.damage_type_override

	return config
