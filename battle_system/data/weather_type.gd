class_name WeatherType
extends RefCounted

## Weather types for battles.
## Different weather conditions apply combat modifiers and visibility effects.

enum Type {
	CLEAR,    # Default - no modifiers
	RAIN,     # Reduced ranged accuracy, reduced charge effectiveness
	FOG,      # Severely limited ranged range, blocks LOS beyond threshold
	STORM,    # Reduced ranged accuracy, increased morale damage from routing
}

# Display names
const NAMES := {
	Type.CLEAR: "Clear",
	Type.RAIN: "Rain",
	Type.FOG: "Fog",
	Type.STORM: "Storm",
}

# Descriptions for UI tooltips
const DESCRIPTIONS := {
	Type.CLEAR: "Clear skies. No combat modifiers.",
	Type.RAIN: "Heavy rain. Ranged accuracy -20%, charge bonus -10%.",
	Type.FOG: "Dense fog. Ranged range -50%, blocks LOS beyond 30m.",
	Type.STORM: "Violent storm. Ranged accuracy -30%, routing morale damage +10%.",
}

# Icons (placeholder paths)
const ICONS := {
	Type.CLEAR: "res://assets/ui/weather_clear.png",
	Type.RAIN: "res://assets/ui/weather_rain.png",
	Type.FOG: "res://assets/ui/weather_fog.png",
	Type.STORM: "res://assets/ui/weather_storm.png",
}

# =====================
# RANGED ACCURACY MODIFIERS
# Multiplier applied to ranged hit chance (1.0 = no change)
# =====================
const RANGED_ACCURACY_MODIFIERS := {
	Type.CLEAR: 1.0,
	Type.RAIN: 0.8,     # -20% accuracy
	Type.FOG: 1.0,      # Fog affects range, not accuracy
	Type.STORM: 0.7,    # -30% accuracy
}

# =====================
# RANGED RANGE MODIFIERS
# Multiplier applied to maximum ranged distance (1.0 = no change)
# =====================
const RANGED_RANGE_MODIFIERS := {
	Type.CLEAR: 1.0,
	Type.RAIN: 1.0,
	Type.FOG: 0.5,      # -50% range
	Type.STORM: 1.0,
}

# =====================
# CHARGE BONUS MODIFIERS
# Multiplier applied to charge bonus damage (1.0 = no change)
# =====================
const CHARGE_BONUS_MODIFIERS := {
	Type.CLEAR: 1.0,
	Type.RAIN: 0.9,     # -10% charge bonus (slippery ground)
	Type.FOG: 1.0,
	Type.STORM: 1.0,
}

# =====================
# ROUTING MORALE DAMAGE MODIFIERS
# Multiplier applied to morale damage when units are routing (1.0 = no change)
# =====================
const ROUTING_MORALE_MODIFIERS := {
	Type.CLEAR: 1.0,
	Type.RAIN: 1.0,
	Type.FOG: 1.0,
	Type.STORM: 1.1,    # +10% morale damage from routing (fear in storm)
}

# =====================
# LINE OF SIGHT DISTANCE
# Maximum distance (meters) for LOS checks in fog. -1 = unlimited.
# =====================
const LOS_DISTANCE := {
	Type.CLEAR: -1.0,   # Unlimited
	Type.RAIN: -1.0,    # Unlimited
	Type.FOG: 30.0,     # Blocks LOS beyond 30m
	Type.STORM: -1.0,   # Unlimited (but lightning could reveal)
}

# =====================
# STATIC GETTER FUNCTIONS
# =====================

static func get_weather_name(weather: Type) -> String:
	return NAMES.get(weather, "Unknown")


static func get_description(weather: Type) -> String:
	return DESCRIPTIONS.get(weather, "")


static func get_ranged_accuracy_modifier(weather: Type) -> float:
	return RANGED_ACCURACY_MODIFIERS.get(weather, 1.0)


static func get_ranged_range_modifier(weather: Type) -> float:
	return RANGED_RANGE_MODIFIERS.get(weather, 1.0)


static func get_charge_bonus_modifier(weather: Type) -> float:
	return CHARGE_BONUS_MODIFIERS.get(weather, 1.0)


static func get_routing_morale_modifier(weather: Type) -> float:
	return ROUTING_MORALE_MODIFIERS.get(weather, 1.0)


static func get_los_distance(weather: Type) -> float:
	return LOS_DISTANCE.get(weather, -1.0)


static func has_los_restriction(weather: Type) -> bool:
	var dist: float = LOS_DISTANCE.get(weather, -1.0)
	return dist > 0.0


static func blocks_los_at_distance(weather: Type, distance: float) -> bool:
	var max_los: float = LOS_DISTANCE.get(weather, -1.0)
	if max_los < 0.0:
		return false  # No LOS restriction
	return distance > max_los
