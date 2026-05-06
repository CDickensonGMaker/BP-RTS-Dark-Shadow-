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


@export var regiment_name: String = "Unnamed Regiment"
@export var unit_type: UnitType.Type = UnitType.Type.INFANTRY

# Unit personality and behavior
@export var personality: Personality = Personality.NORMAL
@export var fire_mode: FireMode = FireMode.VOLLEY  # Only matters for ranged units

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
@export var max_ammo: int = 0           # 0 = melee only
@export var current_ammo: int = 0
@export var range_distance: float = 0.0

# Display
@export var sprite_texture: Texture2D
@export var unit_card_portrait: Texture2D
@export var faction_color: Color = Color.BLUE

# Batched sprite soldiers (for use_sprite_soldiers mode)
@export var sprite_atlas: SpriteUnitAtlas


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
