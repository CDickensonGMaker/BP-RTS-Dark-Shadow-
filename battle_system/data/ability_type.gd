class_name AbilityType
extends RefCounted

## Active abilities that units can use.
## Each ability has a cooldown, targeting mode, and effect.

enum Type {
	NONE,
	# Cavalry
	CHARGE,           # Speed boost + damage spike
	WEDGE_CHARGE,     # Devastating wedge formation charge

	# Infantry
	BRACE,            # Plant against incoming charge
	SHIELD_WALL,      # Form defensive wall

	# Ranged
	VOLLEY_FIRE,      # Synchronized volley (more morale damage)
	FIRE_AT_WILL,     # Toggle automatic firing
	HOLD_FIRE,        # Stop firing (conserve ammo)

	# General/Hero
	WAR_CRY,          # +morale to nearby units
	RALLY,            # Recover routing units
	INSPIRE,          # Temporary combat boost
}

enum TargetMode {
	NONE,             # No targeting needed
	SELF,             # Affects this unit only
	ALLY,             # Target friendly unit
	ENEMY,            # Target enemy unit
	POSITION,         # Target ground position
	DIRECTION,        # Target direction (for charges)
}

# Ability definitions
const ABILITIES := {
	Type.CHARGE: {
		"name": "Charge",
		"description": "Gallop at full speed into the enemy. +50% damage on impact.",
		"cooldown": 30.0,
		"duration": 5.0,
		"target_mode": TargetMode.DIRECTION,
		"hotkey": KEY_Q,
		"unit_types": [UnitType.Type.CAVALRY],
		"stamina_cost": 30.0,
		"icon": "res://assets/ui/ability_charge.png",
	},
	Type.WEDGE_CHARGE: {
		"name": "Wedge Charge",
		"description": "Form wedge and charge through enemy lines.",
		"cooldown": 45.0,
		"duration": 6.0,
		"target_mode": TargetMode.DIRECTION,
		"hotkey": KEY_E,
		"unit_types": [UnitType.Type.CAVALRY],
		"stamina_cost": 40.0,
		"icon": "res://assets/ui/ability_wedge.png",
	},
	Type.BRACE: {
		"name": "Brace",
		"description": "Plant spears against incoming charge. +200% vs cavalry.",
		"cooldown": 15.0,
		"duration": 10.0,
		"target_mode": TargetMode.SELF,
		"hotkey": KEY_Q,
		"unit_types": [UnitType.Type.INFANTRY],
		"stamina_cost": 0.0,
		"icon": "res://assets/ui/ability_brace.png",
	},
	Type.SHIELD_WALL: {
		"name": "Shield Wall",
		"description": "Lock shields for maximum frontal defense. -50% speed.",
		"cooldown": 10.0,
		"duration": 0.0,  # Toggle
		"target_mode": TargetMode.SELF,
		"hotkey": KEY_E,
		"unit_types": [UnitType.Type.INFANTRY],
		"stamina_cost": 0.0,
		"icon": "res://assets/ui/ability_shieldwall.png",
	},
	Type.VOLLEY_FIRE: {
		"name": "Volley Fire",
		"description": "Synchronized volley. +50% morale damage.",
		"cooldown": 20.0,
		"duration": 0.0,  # Instant
		"target_mode": TargetMode.ENEMY,
		"hotkey": KEY_Q,
		"unit_types": [UnitType.Type.RANGED],
		"stamina_cost": 0.0,
		"ammo_cost": 5,  # Uses 5 ammo at once
		"icon": "res://assets/ui/ability_volley.png",
	},
	Type.HOLD_FIRE: {
		"name": "Hold Fire",
		"description": "Stop firing to conserve ammunition.",
		"cooldown": 0.0,
		"duration": 0.0,  # Toggle
		"target_mode": TargetMode.SELF,
		"hotkey": KEY_E,
		"unit_types": [UnitType.Type.RANGED],
		"stamina_cost": 0.0,
		"icon": "res://assets/ui/ability_holdfire.png",
	},
	Type.WAR_CRY: {
		"name": "War Cry",
		"description": "Inspire nearby troops. +10 morale for 30s.",
		"cooldown": 60.0,
		"duration": 30.0,
		"target_mode": TargetMode.SELF,
		"hotkey": KEY_Q,
		"unit_types": [UnitType.Type.GENERAL],
		"stamina_cost": 0.0,
		"effect_radius": 25.0,
		"icon": "res://assets/ui/ability_warcry.png",
	},
	Type.RALLY: {
		"name": "Rally",
		"description": "Attempt to rally routing units nearby.",
		"cooldown": 45.0,
		"duration": 5.0,
		"target_mode": TargetMode.SELF,
		"hotkey": KEY_E,
		"unit_types": [UnitType.Type.GENERAL],
		"stamina_cost": 0.0,
		"effect_radius": 30.0,
		"icon": "res://assets/ui/ability_rally.png",
	},
	Type.INSPIRE: {
		"name": "Inspire",
		"description": "Boost combat effectiveness of nearby troops.",
		"cooldown": 90.0,
		"duration": 20.0,
		"target_mode": TargetMode.SELF,
		"hotkey": KEY_F,
		"unit_types": [UnitType.Type.GENERAL],
		"stamina_cost": 0.0,
		"effect_radius": 20.0,
		"icon": "res://assets/ui/ability_inspire.png",
	},
}

static func get_ability_data(ability: Type) -> Dictionary:
	return ABILITIES.get(ability, {})

static func get_name(ability: Type) -> String:
	var data: Dictionary = ABILITIES.get(ability, {})
	return data.get("name", "Unknown")

static func get_cooldown(ability: Type) -> float:
	var data: Dictionary = ABILITIES.get(ability, {})
	return data.get("cooldown", 0.0)

static func get_abilities_for_unit_type(unit_type: UnitType.Type) -> Array[Type]:
	var result: Array[Type] = []
	for ability_type in ABILITIES.keys():
		var data: Dictionary = ABILITIES[ability_type]
		var unit_types: Array = data.get("unit_types", [])
		if unit_type in unit_types:
			result.append(ability_type)
	return result
