extends Node

## WeatherSystem - Manages battle weather and provides combat modifiers.
## Add as autoload or child of battle scene.
##
## Usage:
##   # Query current weather modifiers
##   var accuracy_mod: float = WeatherSystem.get_ranged_accuracy_modifier()
##   var range_mod: float = WeatherSystem.get_ranged_range_modifier()
##
##   # Check LOS restrictions
##   if WeatherSystem.blocks_los(distance):
##       # Can't see target
##
##   # Change weather manually
##   WeatherSystem.set_weather(WeatherType.Type.STORM)

signal weather_changed(old_weather: WeatherType.Type, new_weather: WeatherType.Type)

# Current weather state
var current_weather: WeatherType.Type = WeatherType.Type.CLEAR

# Random weather change settings
var random_weather_enabled: bool = false
var min_weather_duration: float = 60.0   # Minimum seconds before weather can change
var max_weather_duration: float = 180.0  # Maximum seconds before weather changes
var _weather_timer: float = 0.0
var _next_change_time: float = 0.0

# Weather transition probabilities (from current weather -> possible next weathers)
# Each weather has weighted chances for what it can transition to
const WEATHER_TRANSITIONS := {
	WeatherType.Type.CLEAR: {
		WeatherType.Type.CLEAR: 50,
		WeatherType.Type.RAIN: 25,
		WeatherType.Type.FOG: 20,
		WeatherType.Type.STORM: 5,
	},
	WeatherType.Type.RAIN: {
		WeatherType.Type.CLEAR: 30,
		WeatherType.Type.RAIN: 40,
		WeatherType.Type.FOG: 10,
		WeatherType.Type.STORM: 20,
	},
	WeatherType.Type.FOG: {
		WeatherType.Type.CLEAR: 40,
		WeatherType.Type.RAIN: 20,
		WeatherType.Type.FOG: 35,
		WeatherType.Type.STORM: 5,
	},
	WeatherType.Type.STORM: {
		WeatherType.Type.CLEAR: 20,
		WeatherType.Type.RAIN: 50,
		WeatherType.Type.FOG: 10,
		WeatherType.Type.STORM: 20,
	},
}


func _ready() -> void:
	_reset_weather_timer()


func _process(delta: float) -> void:
	if not random_weather_enabled:
		return

	_weather_timer += delta
	if _weather_timer >= _next_change_time:
		_roll_random_weather()
		_reset_weather_timer()


# =====================
# PUBLIC API - WEATHER CONTROL
# =====================

## Set the current weather type
func set_weather(weather: WeatherType.Type) -> void:
	if weather == current_weather:
		return

	var old_weather: WeatherType.Type = current_weather
	current_weather = weather
	weather_changed.emit(old_weather, current_weather)

	# Reset timer when manually setting weather
	_reset_weather_timer()

	print("WeatherSystem: Weather changed from %s to %s" % [
		WeatherType.get_weather_name(old_weather),
		WeatherType.get_weather_name(current_weather)
	])


## Get the current weather type
func get_weather() -> WeatherType.Type:
	return current_weather


## Enable or disable random weather changes
func set_random_weather(enabled: bool, min_duration: float = 60.0, max_duration: float = 180.0) -> void:
	random_weather_enabled = enabled
	min_weather_duration = min_duration
	max_weather_duration = max_duration
	_reset_weather_timer()


# =====================
# PUBLIC API - MODIFIER GETTERS
# These query the current weather's modifiers
# =====================

## Get ranged accuracy multiplier for current weather (0.0 - 1.0)
func get_ranged_accuracy_modifier() -> float:
	return WeatherType.get_ranged_accuracy_modifier(current_weather)


## Get ranged range multiplier for current weather (0.0 - 1.0)
func get_ranged_range_modifier() -> float:
	return WeatherType.get_ranged_range_modifier(current_weather)


## Get charge bonus multiplier for current weather (0.0 - 1.0)
func get_charge_bonus_modifier() -> float:
	return WeatherType.get_charge_bonus_modifier(current_weather)


## Get routing morale damage multiplier for current weather (1.0+)
func get_routing_morale_modifier() -> float:
	return WeatherType.get_routing_morale_modifier(current_weather)


## Get maximum LOS distance for current weather (-1 = unlimited)
func get_los_distance() -> float:
	return WeatherType.get_los_distance(current_weather)


## Check if current weather has LOS restrictions
func has_los_restriction() -> bool:
	return WeatherType.has_los_restriction(current_weather)


## Check if current weather blocks LOS at given distance
func blocks_los(distance: float) -> bool:
	return WeatherType.blocks_los_at_distance(current_weather, distance)


## Get current weather display name
func get_weather_name() -> String:
	return WeatherType.get_weather_name(current_weather)


## Get current weather description
func get_weather_description() -> String:
	return WeatherType.get_description(current_weather)


# =====================
# HELPER FUNCTIONS FOR COMBAT MANAGER INTEGRATION
# =====================

## Apply weather modifier to a ranged hit chance
## Usage: final_hit_chance = WeatherSystem.apply_accuracy_modifier(base_hit_chance)
func apply_accuracy_modifier(base_accuracy: float) -> float:
	return base_accuracy * get_ranged_accuracy_modifier()


## Apply weather modifier to ranged attack range
## Usage: final_range = WeatherSystem.apply_range_modifier(base_range)
func apply_range_modifier(base_range: float) -> float:
	return base_range * get_ranged_range_modifier()


## Apply weather modifier to charge bonus damage
## Usage: final_charge_bonus = WeatherSystem.apply_charge_modifier(base_charge_bonus)
func apply_charge_modifier(base_charge_bonus: int) -> int:
	return int(float(base_charge_bonus) * get_charge_bonus_modifier())


## Check if LOS is valid between two positions under current weather
func check_los_valid(from_pos: Vector3, to_pos: Vector3) -> bool:
	if not has_los_restriction():
		return true

	var distance: float = from_pos.distance_to(to_pos)
	return not blocks_los(distance)


# =====================
# INTERNAL FUNCTIONS
# =====================

func _reset_weather_timer() -> void:
	_weather_timer = 0.0
	_next_change_time = randf_range(min_weather_duration, max_weather_duration)


func _roll_random_weather() -> void:
	var transitions: Dictionary = WEATHER_TRANSITIONS.get(current_weather, {})
	if transitions.is_empty():
		return

	# Calculate total weight
	var total_weight: int = 0
	for weight: int in transitions.values():
		total_weight += weight

	# Roll random number
	var roll: int = randi() % total_weight

	# Find which weather we landed on
	var cumulative: int = 0
	for weather_type: WeatherType.Type in transitions.keys():
		cumulative += transitions[weather_type]
		if roll < cumulative:
			set_weather(weather_type)
			return


# =====================
# DEBUG FUNCTIONS
# =====================

## Force weather for testing
func debug_set_weather(weather_name: String) -> void:
	match weather_name.to_lower():
		"clear":
			set_weather(WeatherType.Type.CLEAR)
		"rain":
			set_weather(WeatherType.Type.RAIN)
		"fog":
			set_weather(WeatherType.Type.FOG)
		"storm":
			set_weather(WeatherType.Type.STORM)
		_:
			push_warning("WeatherSystem: Unknown weather type '%s'" % weather_name)


## Get debug info string
func get_debug_info() -> String:
	var info: String = "Weather: %s\n" % get_weather_name()
	info += "  Ranged Accuracy: %.0f%%\n" % (get_ranged_accuracy_modifier() * 100.0)
	info += "  Ranged Range: %.0f%%\n" % (get_ranged_range_modifier() * 100.0)
	info += "  Charge Bonus: %.0f%%\n" % (get_charge_bonus_modifier() * 100.0)
	info += "  Routing Morale: %.0f%%\n" % (get_routing_morale_modifier() * 100.0)

	var los: float = get_los_distance()
	if los < 0:
		info += "  LOS: Unlimited\n"
	else:
		info += "  LOS: %.0fm\n" % los

	if random_weather_enabled:
		info += "  Next change in: %.0fs\n" % (_next_change_time - _weather_timer)

	return info
