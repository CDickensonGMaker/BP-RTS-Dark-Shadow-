class_name FormationType
extends RefCounted

## Formation types for units.
## Different formations have different combat modifiers and movement characteristics.

enum Type {
	LINE,         # Default - wide, 2-3 ranks deep (all infantry/archers)
	COLUMN,       # Narrow, deep - fast travel, weak combat (all units)
	WEDGE,        # Triangle - breakthrough bonus (cavalry only)
	SQUARE,       # Hollow square - all-around defense (infantry, spearmen)
	LOOSE,        # Spread out - reduced missile casualties (skirmishers, archers)
	SHIELD_WALL,  # Tight, slow, frontal defense (heavy infantry only)
	SCHILTRON,    # Anti-cavalry braced position (pikemen only)
}

# Hotkey mappings (F1-F4 for common formations)
const HOTKEYS := {
	Type.LINE: KEY_F1,
	Type.COLUMN: KEY_F2,
	Type.WEDGE: KEY_F3,
	Type.SQUARE: KEY_F4,
}

# Display names
const NAMES := {
	Type.LINE: "Line",
	Type.COLUMN: "Column",
	Type.WEDGE: "Wedge",
	Type.SQUARE: "Square",
	Type.LOOSE: "Loose",
	Type.SHIELD_WALL: "Shield Wall",
	Type.SCHILTRON: "Schiltron",
}

# Movement speed multipliers
const SPEED_MODIFIERS := {
	Type.LINE: 1.0,
	Type.COLUMN: 1.2,      # Faster marching
	Type.WEDGE: 1.1,       # Slightly faster for charge
	Type.SQUARE: 0.7,      # Slow defensive formation
	Type.LOOSE: 1.15,      # Mobile
	Type.SHIELD_WALL: 0.5, # Very slow
	Type.SCHILTRON: 0.0,   # Cannot move when braced
}

# Combat modifiers (attack multiplier)
const ATTACK_MODIFIERS := {
	Type.LINE: 1.0,
	Type.COLUMN: 0.6,      # Weak combat
	Type.WEDGE: 1.3,       # Breakthrough power
	Type.SQUARE: 0.8,      # Spread thin
	Type.LOOSE: 0.7,       # Spread out
	Type.SHIELD_WALL: 0.8, # Defensive focus
	Type.SCHILTRON: 0.6,   # Anti-cav specialist
}

# Defense modifiers (defense multiplier)
const DEFENSE_MODIFIERS := {
	Type.LINE: 1.0,
	Type.COLUMN: 0.7,        # Vulnerable
	Type.WEDGE: 0.8,         # Offense focus
	Type.SQUARE: 1.3,        # All-around defense
	Type.LOOSE: 0.6,         # Spread thin
	Type.SHIELD_WALL: 1.5,   # Frontal fortress
	Type.SCHILTRON: 1.4,     # Anti-charge
}

# Anti-cavalry bonus (multiplier vs cavalry charge)
const ANTI_CAVALRY := {
	Type.LINE: 1.0,
	Type.COLUMN: 0.5,
	Type.WEDGE: 1.0,
	Type.SQUARE: 1.5,
	Type.LOOSE: 0.8,
	Type.SHIELD_WALL: 1.3,
	Type.SCHILTRON: 2.5,  # Pike wall devastates cavalry
}

# Charge damage modifiers (multiplier to charge bonus)
const CHARGE_MODIFIERS := {
	Type.LINE: 0.9,        # Line not ideal for charging
	Type.COLUMN: 1.3,      # Good for charges
	Type.WEDGE: 1.5,       # Best for breakthrough charges
	Type.SQUARE: 0.3,      # Cannot charge effectively
	Type.LOOSE: 0.4,       # Spread out, weak charge
	Type.SHIELD_WALL: 0.2, # Defensive, no charge
	Type.SCHILTRON: 0.0,   # Braced, cannot charge
}

# Ranged combat modifiers (accuracy/damage multiplier)
const RANGED_MODIFIERS := {
	Type.LINE: 1.2,        # Good firing line
	Type.COLUMN: 0.5,      # Only front ranks can fire
	Type.WEDGE: 0.4,       # Poor for ranged
	Type.SQUARE: 0.8,      # Can fire in all directions but spread thin
	Type.LOOSE: 1.3,       # Best for skirmishing
	Type.SHIELD_WALL: 0.6, # Shields up, hard to fire
	Type.SCHILTRON: 0.4,   # Pikes up, hard to fire
}

# Which unit types can use which formations
const ALLOWED_UNITS := {
	Type.LINE: [UnitType.Type.INFANTRY, UnitType.Type.RANGED, UnitType.Type.CAVALRY],
	Type.COLUMN: [UnitType.Type.INFANTRY, UnitType.Type.RANGED, UnitType.Type.CAVALRY, UnitType.Type.ARTILLERY],
	Type.WEDGE: [UnitType.Type.CAVALRY],
	Type.SQUARE: [UnitType.Type.INFANTRY],
	Type.LOOSE: [UnitType.Type.RANGED],
	Type.SHIELD_WALL: [UnitType.Type.INFANTRY],
	Type.SCHILTRON: [UnitType.Type.INFANTRY],  # Specifically pikemen
}

# Ranks deep for each formation
const RANKS := {
	Type.LINE: 3,
	Type.COLUMN: 8,
	Type.WEDGE: 0,  # Special triangular
	Type.SQUARE: 0, # Special hollow square
	Type.LOOSE: 2,
	Type.SHIELD_WALL: 2,
	Type.SCHILTRON: 0, # Circular
}

static func get_formation_name(formation: Type) -> String:
	return NAMES.get(formation, "Unknown")

static func get_speed_modifier(formation: Type) -> float:
	return SPEED_MODIFIERS.get(formation, 1.0)

static func get_attack_modifier(formation: Type) -> float:
	return ATTACK_MODIFIERS.get(formation, 1.0)

static func get_defense_modifier(formation: Type) -> float:
	return DEFENSE_MODIFIERS.get(formation, 1.0)

static func get_anti_cavalry_modifier(formation: Type) -> float:
	return ANTI_CAVALRY.get(formation, 1.0)

static func get_charge_modifier(formation: Type) -> float:
	return CHARGE_MODIFIERS.get(formation, 1.0)

static func get_ranged_modifier(formation: Type) -> float:
	return RANGED_MODIFIERS.get(formation, 1.0)

static func can_unit_use(formation: Type, unit_type: UnitType.Type) -> bool:
	var allowed: Array = ALLOWED_UNITS.get(formation, [])
	return unit_type in allowed

static func get_hotkey(formation: Type) -> int:
	return HOTKEYS.get(formation, 0)
