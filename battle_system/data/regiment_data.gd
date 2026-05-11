# Pure data resource. No Node dependencies. Fully serializable.
class_name RegimentData
extends Resource


## Unit personality affects combat behavior (inspired by Stainless Steel mod)
enum Personality {
	NORMAL,      # Standard behavior
	DISCIPLINED, # Never breaks formation, slower to rout, won't pursue
	IMPETUOUS,   # May charge without orders, +10% attack, -10% defense
	FANATIC,     # Locked morale (cannot rout), +10% attack, -20% defense
}

## Ranged fire mode for missile units
enum FireMode {
	VOLLEY,  # Area effect, less accurate, high rate - default for archers
	DIRECT,  # Accurate single target, lower rate - for skirmishers/crossbows
}

## Hero trait-based weaknesses (flexible system for any hero)
enum HeroTrait {
	NONE,
	ARROGANT,       # Weak vs INFANTRY (underestimates common soldiers)
	IMPATIENT,      # Weak vs RANGED (charges into arrows)
	GROUNDED,       # Weak vs CAVALRY (can't handle mounted foes)
	FEARLESS,       # Weak vs MONSTER (overconfident, doesn't retreat)
	DUELIST,        # Weak vs ARTILLERY (focused on single combat)
}

## Weapon class — defines reload, fire pattern, projectile base, line-of-sight rules.
## This replaces the implicit weapon-from-unit-name detection in CombatManager.
enum WeaponClass {
	NONE,            # Melee-only unit, no ranged weapon
	BOW,             # Volley fire, short-medium range, indirect arc OK
	CROSSBOW,        # Stagger fire, flat trajectory, requires LOS
	HANDGUN,         # Stagger fire, flat trajectory, slow but punchy, requires LOS
	THROWN,          # Volley fire, very short range, javelins/axes
	CANNON,          # Single shot per crew, direct fire, pierces ranks, requires LOS
	MORTAR,          # Single shot per crew, indirect fire (high arc), AOE on landing
	WAR_MACHINE,     # Catch-all for special weapons (warpfire, volley gun, doom diver)
	BREATH_FIRE,     # Dragon/monster fire breath - cone attack with cooldown
	BREATH_POISON,   # Wyvern/creature poison breath
	MAGIC_MISSILE,   # Hero/wizard ranged magic attack with cooldown
}


@export var regiment_name: String = "Unnamed Regiment"
@export var unit_type: UnitType.Type = UnitType.Type.INFANTRY
@export var faction: String = "neutral"  # empire, dwarf, greenskin, undead, skaven, woodelf, neutral

# Unit personality and behavior
@export var personality: Personality = Personality.NORMAL
@export var fire_mode: FireMode = FireMode.VOLLEY  # Only matters for ranged units

# Elite and discipline
@export var is_elite: bool = false      # Elite units have delayed casualty reactions
@export var discipline: int = 10        # Used for disengage rolls (vs enemy weapon_skill)

# Combat stats
@export var attack: int = 10
@export var defense: int = 10
@export var weapon_skill: int = 10      # melee accuracy
@export var ballistic_skill: int = 0    # ranged accuracy (0 = no ranged)
@export var strength: int = 3           # damage per hit
@export var armor: int = 0              # armor value (affects fatigue drain: 0=light, 5=medium, 10+=heavy)

# Regiment composition
@export var max_soldiers: int = 40      # visual/HP representation
@export var current_soldiers: int = 40

# Morale
@export var base_morale: float = 60.0   # starting morale 0-100
@export var morale_save: int = 5        # resistance to morale damage

# Movement speeds (infantry: walk=1.75, run=2.0, charge=3.5)
# Walk is 50% of old speed, run is slightly faster than walk, charge is old speed (short burst)
@export var walk_speed: float = 1.75    # Normal marching pace (50% of old infantry speed)
@export var run_speed: float = 2.0      # Slightly faster than walk (running)
@export var charge_speed: float = 3.5   # Fast burst for charges (old infantry speed)
@export var charge_speed_distance: float = 15.0  # Distance charge speed lasts before slowing
@export var charge_bonus: int = 6       # attack bonus on charge tick
@export var mass: float = 1.0           # unit mass for charge impact (cavalry=2.0-3.0, infantry=1.0)
@export var turn_rate: float = 3.0      # radians/sec (infantry=3.0, cavalry=1.5, artillery=0.5)

# Ranged (optional)
@export var weapon_class: WeaponClass = WeaponClass.NONE
@export var max_ammo: int = 0           # 0 = melee only
@export var current_ammo: int = 0
@export var range_distance: float = 0.0
@export var breath_cooldown: float = 8.0  # Cooldown for breath/magic attacks (dragons, heroes)
@export var default_round_type: int = 0  # WeaponClassData.RoundType.STANDARD

# Aura (for heroes/generals) - affects nearby allied units
@export var has_aura: bool = false                  # Enable aura effects
@export var aura_radius: float = 25.0               # Radius of aura effect
@export var aura_morale_bonus: float = 5.0          # Per-tick morale bonus to nearby allies
@export var aura_casualty_resistance: float = 0.5   # 0.5 = reduces cascade pressure by 50%
@export var aura_threshold_bonus: float = 0.05      # +5% to casualty thresholds (more resilient)

# Display
@export var sprite_texture: Texture2D
@export var unit_card_portrait: Texture2D
@export var faction_color: Color = Color.BLUE

# Sprite direction mapping - which sprite row (0-7) represents the unit's "front"
# When unit faces formation front, this sprite direction will be displayed
# Default 0 = North sprite row is the front. Set to 4 if South sprite is the front, etc.
@export var sprite_front_direction: int = 0

# Batched sprite soldiers (for use_sprite_soldiers mode)
@export var sprite_atlas: SpriteUnitAtlas

# 3D Artillery model (for ARTILLERY unit type with 3D models instead of sprites)
@export var artillery_model: PackedScene
@export var artillery_model_scale: Vector3 = Vector3(0.5, 0.5, 0.5)
@export var artillery_pieces_count: int = 4  # Number of guns in the battery

## Artillery model front direction (0-7). Controls 3D cannon rotation offset.
## Separate from sprite_front_direction to allow independent control.
## Default 0 = cannon model faces North when regiment faces North.
@export var artillery_model_direction: int = 0

## Spacing between artillery pieces in formation (in world units/meters).
## Cannon: 5.0 (standard), Mortar: 4.0 (compact), Catapult: 7.0 (large footprint)
@export var artillery_spacing: float = 5.0

# Hero trait (for GENERAL units - defines weakness)
@export var hero_trait: HeroTrait = HeroTrait.NONE

# --- HERO TRAIT WEAKNESS CONSTANTS ---
# NOTE: FEARLESS maps to MONSTER (value 5) - requires MONSTER to be added to UnitType.Type
const TRAIT_WEAKNESS_MAP := {
	HeroTrait.ARROGANT: UnitType.Type.INFANTRY,
	HeroTrait.IMPATIENT: UnitType.Type.RANGED,
	HeroTrait.GROUNDED: UnitType.Type.CAVALRY,
	HeroTrait.FEARLESS: 5,  # UnitType.Type.MONSTER (pending addition to UnitType)
	HeroTrait.DUELIST: UnitType.Type.ARTILLERY,
}

const TRAIT_WEAKNESS_PENALTY: float = 0.75  # -25% when fighting weakness


# --- PERSONALITY HELPERS ---

func get_attack_modifier() -> float:
	## Returns attack multiplier based on personality.
	match personality:
		Personality.IMPETUOUS:
			return 1.10  # +10% attack
		Personality.FANATIC:
			return 1.10  # +10% attack
		_:
			return 1.0


func get_defense_modifier() -> float:
	## Returns defense multiplier based on personality.
	match personality:
		Personality.IMPETUOUS:
			return 0.90  # -10% defense
		Personality.FANATIC:
			return 0.80  # -20% defense
		_:
			return 1.0


func can_rout() -> bool:
	## Returns whether this unit can rout. Fanatics fight to the death.
	return personality != Personality.FANATIC


func can_pursue() -> bool:
	## Returns whether this unit will pursue routing enemies.
	## Disciplined units hold formation.
	return personality != Personality.DISCIPLINED


func may_charge_impulsively() -> bool:
	## Returns whether this unit might charge without orders.
	return personality == Personality.IMPETUOUS


func get_morale_resistance_modifier() -> float:
	## Returns morale damage resistance. Disciplined units are steadier.
	match personality:
		Personality.DISCIPLINED:
			return 0.75  # Takes 25% less morale damage
		_:
			return 1.0


func get_armor_fatigue_multiplier() -> float:
	## Returns stamina drain multiplier based on armor weight.
	## Light (0-3): 1.0x, Medium (4-7): 1.25x, Heavy (8+): 1.5x
	if armor >= 8:
		return 1.5
	elif armor >= 4:
		return 1.25
	else:
		return 1.0


func is_skirmisher_type() -> bool:
	## Returns true if this is a skirmisher (direct fire, better melee).
	return ballistic_skill > 0 and fire_mode == FireMode.DIRECT


# --- HERO TRAIT HELPERS ---

func get_weakness_penalty_vs(enemy_type: UnitType.Type) -> float:
	## Returns penalty multiplier if fighting weakness type based on trait.
	if hero_trait == HeroTrait.NONE:
		return 1.0
	var weakness_type = TRAIT_WEAKNESS_MAP.get(hero_trait, -1)
	if weakness_type == enemy_type:
		return TRAIT_WEAKNESS_PENALTY
	return 1.0


func get_trait_name() -> String:
	## Returns the string name of the current hero trait.
	return HeroTrait.keys()[hero_trait]
