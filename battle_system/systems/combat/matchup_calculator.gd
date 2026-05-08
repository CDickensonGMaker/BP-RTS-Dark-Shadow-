class_name MatchupCalculator
extends RefCounted

## Rock-paper-scissors unit type matchup system.
## Provides damage multipliers based on attacker vs defender unit types.
## Inspired by Total War unit counter mechanics.

# Spear units get bonus vs cavalry (historical pike/lance effectiveness)
const SPEAR_VS_CAVALRY_BONUS: float = 1.25

# Melee matchup table: attacker type -> defender type -> damage multiplier
# Values > 1.0 = attacker has advantage, < 1.0 = defender has advantage
const MELEE_MATCHUPS: Dictionary = {
	UnitType.Type.INFANTRY: {
		UnitType.Type.INFANTRY: 1.0,
		UnitType.Type.CAVALRY: 0.9,  # Infantry struggles vs cavalry unless spears
		UnitType.Type.RANGED: 1.15,
		UnitType.Type.ARTILLERY: 1.25,
		UnitType.Type.GENERAL: 0.75,  # Heroes are elite fighters
		UnitType.Type.MONSTER: 0.85
	},
	UnitType.Type.CAVALRY: {
		UnitType.Type.INFANTRY: 1.35,  # Cavalry dominates infantry without spears
		UnitType.Type.CAVALRY: 1.0,
		UnitType.Type.RANGED: 1.4,  # Cavalry devastates archers
		UnitType.Type.ARTILLERY: 1.25,
		UnitType.Type.GENERAL: 0.8,  # Heroes resist cavalry charges
		UnitType.Type.MONSTER: 0.7
	},
	UnitType.Type.RANGED: {
		UnitType.Type.INFANTRY: 0.85,
		UnitType.Type.CAVALRY: 0.75,
		UnitType.Type.RANGED: 0.9,
		UnitType.Type.ARTILLERY: 0.8,
		UnitType.Type.GENERAL: 0.6,  # Heroes close distance quickly
		UnitType.Type.MONSTER: 0.6
	},
	UnitType.Type.ARTILLERY: {
		UnitType.Type.INFANTRY: 0.5,
		UnitType.Type.CAVALRY: 0.4,
		UnitType.Type.RANGED: 0.6,
		UnitType.Type.ARTILLERY: 0.7,
		UnitType.Type.GENERAL: 0.5,
		UnitType.Type.MONSTER: 0.3
	},
	UnitType.Type.GENERAL: {
		UnitType.Type.INFANTRY: 1.5,   # Heroes are elite fighters vs common soldiers
		UnitType.Type.CAVALRY: 1.3,    # Heroes can unhorse riders
		UnitType.Type.RANGED: 1.4,     # Heroes close and destroy archers
		UnitType.Type.ARTILLERY: 1.3,
		UnitType.Type.GENERAL: 1.0,
		UnitType.Type.MONSTER: 1.0     # Heroes can fight monsters on equal terms
	},
	UnitType.Type.MONSTER: {
		UnitType.Type.INFANTRY: 1.5,
		UnitType.Type.CAVALRY: 1.7,
		UnitType.Type.RANGED: 1.5,
		UnitType.Type.ARTILLERY: 1.25,
		UnitType.Type.GENERAL: 0.95,  # Heroes can challenge monsters
		UnitType.Type.MONSTER: 1.0
	}
}

# Ranged matchup table: shooter type -> target type -> accuracy multiplier
# Only RANGED and ARTILLERY can shoot, other types default to 1.0
const RANGED_MATCHUPS: Dictionary = {
	UnitType.Type.RANGED: {
		UnitType.Type.INFANTRY: 1.0,
		UnitType.Type.CAVALRY: 1.1,
		UnitType.Type.RANGED: 1.0,
		UnitType.Type.ARTILLERY: 1.15,
		UnitType.Type.GENERAL: 0.85,
		UnitType.Type.MONSTER: 1.2
	},
	UnitType.Type.ARTILLERY: {
		UnitType.Type.INFANTRY: 1.3,
		UnitType.Type.CAVALRY: 1.15,
		UnitType.Type.RANGED: 1.2,
		UnitType.Type.ARTILLERY: 1.0,
		UnitType.Type.GENERAL: 0.8,
		UnitType.Type.MONSTER: 1.4
	}
}


## Get melee damage multiplier based on attacker and defender unit types.
## Returns 1.0 if either type is not found in the matchup table.
static func get_melee_matchup(attacker_type: UnitType.Type, defender_type: UnitType.Type) -> float:
	if not MELEE_MATCHUPS.has(attacker_type):
		return 1.0
	var attacker_matchups: Dictionary = MELEE_MATCHUPS[attacker_type]
	if not attacker_matchups.has(defender_type):
		return 1.0
	return attacker_matchups[defender_type]


## Get ranged accuracy multiplier based on shooter and target unit types.
## Returns 1.0 if the shooter type has no ranged matchups defined.
static func get_ranged_matchup(shooter_type: UnitType.Type, target_type: UnitType.Type) -> float:
	if not RANGED_MATCHUPS.has(shooter_type):
		return 1.0
	var shooter_matchups: Dictionary = RANGED_MATCHUPS[shooter_type]
	if not shooter_matchups.has(target_type):
		return 1.0
	return shooter_matchups[target_type]


## Check if a regiment is a spear-type unit (halberd, pike, spear, lance).
## These units receive bonus damage against cavalry.
static func is_spear_unit(data: RegimentData) -> bool:
	if data == null or data.regiment_name.is_empty():
		return false
	var name_lower: String = data.regiment_name.to_lower()
	return (
		name_lower.contains("halb") or
		name_lower.contains("pike") or
		name_lower.contains("spear") or
		name_lower.contains("lance")
	)
