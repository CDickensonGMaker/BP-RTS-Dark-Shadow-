class_name SpellData
extends Resource

## Spell data resource defining magic abilities for regiments.
## Based on Catacombs of Gore spell system patterns.
##
## Target Types:
## - PROJECTILE: Fires a projectile at target (can be homing)
## - AOE_POINT: Area damage at target location
## - AOE_SELF: Area effect centered on caster
## - CONE: Cone-shaped damage in front of caster
## - BEAM: Continuous beam to target

enum TargetType {
	PROJECTILE,  ## Single-target projectile (optionally homing)
	AOE_POINT,   ## Ground-targeted area of effect
	AOE_SELF,    ## Self-centered area of effect (buffs/auras)
	CONE,        ## Frontal cone attack
	BEAM,        ## Continuous beam to target
}

enum DamageType {
	FIRE,        ## Fire damage - leaves burning hazard
	ICE,         ## Ice damage - slows targets
	LIGHTNING,   ## Lightning damage - chains to nearby
	HOLY,        ## Holy damage - extra vs undead
	DARK,        ## Dark damage - drains morale
	PHYSICAL,    ## Physical damage - no special effects
}

enum EffectType {
	DAMAGE,      ## Deals damage
	BUFF,        ## Positive effect on allies
	DEBUFF,      ## Negative effect on enemies
	HEAL,        ## Restores health
	SUMMON,      ## Summons units
}

## Unique identifier for this spell
@export var id: String = "spell_name"

## Display name shown in UI
@export var display_name: String = "Spell Name"

## Description shown in UI
@export_multiline var description: String = "Spell description."

## Icon for UI display
@export var icon: Texture2D = null

## How this spell targets
@export var target_type: TargetType = TargetType.PROJECTILE

## What type of damage this spell deals
@export var damage_type: DamageType = DamageType.FIRE

## What effect category this spell belongs to
@export var effect_type: EffectType = EffectType.DAMAGE

# === DAMAGE PARAMETERS ===

## Base damage dealt on hit
@export var base_damage: int = 50

## Damage falloff at edge of AOE (1.0 = no falloff)
@export_range(0.0, 1.0) var edge_damage_mult: float = 0.5

## Morale damage multiplier (base_damage * morale_mult)
@export var morale_damage_mult: float = 0.5

# === TARGETING PARAMETERS ===

## Maximum cast range from caster
@export var range_distance: float = 50.0

## Radius for AOE effects
@export var aoe_radius: float = 8.0

## Angle for cone attacks (degrees)
@export_range(15.0, 180.0) var cone_angle: float = 45.0

## Cone length (distance from caster)
@export var cone_length: float = 20.0

## Beam width for beam attacks
@export var beam_width: float = 2.0

## Beam max distance
@export var beam_distance: float = 40.0

# === PROJECTILE PARAMETERS ===

## Speed of projectile (units per second)
@export var projectile_speed: float = 30.0

## Whether projectile homes toward target
@export var is_homing: bool = false

## Homing turn rate (degrees per second)
@export var homing_turn_rate: float = 180.0

## Projectile arc height (0 = straight line)
@export var projectile_arc: float = 5.0

## Projectile size scale
@export var projectile_scale: float = 1.0

# === HAZARD PARAMETERS ===

## Whether spell creates a persistent hazard zone
@export var creates_hazard: bool = false

## How long hazard persists
@export var hazard_duration: float = 10.0

## Damage per tick while in hazard
@export var hazard_tick_damage: int = 5

## Time between hazard damage ticks
@export var hazard_tick_interval: float = 0.5

## Hazard radius (uses aoe_radius if 0)
@export var hazard_radius: float = 0.0

# === BUFF/DEBUFF PARAMETERS ===

## Duration of buff/debuff effect
@export var effect_duration: float = 10.0

## Attack modifier (1.0 = no change, 1.2 = +20%)
@export var attack_modifier: float = 1.0

## Defense modifier
@export var defense_modifier: float = 1.0

## Speed modifier
@export var speed_modifier: float = 1.0

## Morale modifier per second
@export var morale_per_second: float = 0.0

# === COOLDOWN AND COST ===

## Cooldown in seconds
@export var cooldown: float = 30.0

## Stamina cost to cast
@export var stamina_cost: float = 20.0

## Ammo cost (for artillery-style spells)
@export var ammo_cost: int = 0

# === VISUAL PARAMETERS ===

## Primary color for spell effects
@export var effect_color: Color = Color(1.0, 0.5, 0.1, 1.0)

## Secondary color for gradients/accents
@export var secondary_color: Color = Color(1.0, 0.2, 0.0, 0.5)

## Particle texture (optional)
@export var particle_texture: Texture2D = null

## Sound effect to play on cast
@export var cast_sound: String = "spell_fire"

## Sound effect to play on impact
@export var impact_sound: String = "explosion_fire"

# === REQUIREMENTS ===

## Unit types that can use this spell
@export var allowed_unit_types: Array[UnitType.Type] = []

## Minimum veterancy level required
@export var min_veterancy_level: int = 0


# === HELPER METHODS ===

func get_hazard_radius() -> float:
	## Returns hazard radius, defaulting to aoe_radius if not set.
	return hazard_radius if hazard_radius > 0.0 else aoe_radius


func get_display_range() -> String:
	## Returns formatted range string for UI.
	return "%d units" % int(range_distance)


func get_display_damage() -> String:
	## Returns formatted damage string for UI.
	if effect_type == EffectType.DAMAGE:
		return "%d %s" % [base_damage, DamageType.keys()[damage_type].to_lower()]
	elif effect_type == EffectType.HEAL:
		return "Heals %d" % base_damage
	return ""


func get_display_cooldown() -> String:
	## Returns formatted cooldown string for UI.
	if cooldown >= 60.0:
		return "%dm %ds" % [int(cooldown / 60.0), int(fmod(cooldown, 60.0))]
	return "%ds" % int(cooldown)


func can_unit_use(regiment: Regiment) -> bool:
	## Check if a regiment can use this spell.
	if not regiment or not regiment.data:
		return false

	# Check unit type restriction
	if allowed_unit_types.size() > 0:
		if regiment.data.unit_type not in allowed_unit_types:
			return false

	# Check veterancy requirement
	if regiment.veterancy and min_veterancy_level > 0:
		if regiment.veterancy.current_level < min_veterancy_level:
			return false

	return true
