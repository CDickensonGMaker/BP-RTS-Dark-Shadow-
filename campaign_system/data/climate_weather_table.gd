class_name ClimateWeatherTable
extends RefCounted

## Weather probability tables per (climate x season).
## Used by WeatherScheduler for deterministic weather rolls.
## Probabilities are cumulative thresholds (0.0 - 1.0).

# Import enums
const RegionDataScript = preload("res://campaign_system/data/region_data.gd")
const WeatherTypeScript = preload("res://battle_system/data/weather_type.gd")

# Alias enums for readability
const ClimateBiome = RegionDataScript.ClimateBiome
const Season = preload("res://campaign_system/systems/campaign_calendar.gd").Season

# Weather type indices (matching WeatherType enum)
const CLEAR = 0
const RAIN = 1
const FOG = 2
const STORM = 3
const SNOW = 4      # Phase 4 - will be added to WeatherType
const BLIZZARD = 5  # Phase 4 - will be added to WeatherType


## Weather probability tables.
## Format: { climate: { season: { weather_type: cumulative_probability } } }
## Example: TEMPERATE Spring - 60% clear, 25% rain, 10% fog, 5% storm
## Cumulative: clear < 0.60, rain < 0.85, fog < 0.95, storm <= 1.0
static var WEATHER_TABLES: Dictionary = {
	ClimateBiome.TEMPERATE: {
		Season.SPRING: { CLEAR: 0.55, RAIN: 0.80, FOG: 0.92, STORM: 1.0 },
		Season.SUMMER: { CLEAR: 0.70, RAIN: 0.88, FOG: 0.94, STORM: 1.0 },
		Season.AUTUMN: { CLEAR: 0.50, RAIN: 0.78, FOG: 0.93, STORM: 1.0 },
		Season.WINTER: { CLEAR: 0.45, RAIN: 0.60, FOG: 0.75, SNOW: 0.92, BLIZZARD: 1.0 },
	},
	ClimateBiome.ARID: {
		Season.SPRING: { CLEAR: 0.85, RAIN: 0.92, FOG: 0.97, STORM: 1.0 },
		Season.SUMMER: { CLEAR: 0.95, RAIN: 0.98, FOG: 0.99, STORM: 1.0 },
		Season.AUTUMN: { CLEAR: 0.88, RAIN: 0.95, FOG: 0.98, STORM: 1.0 },
		Season.WINTER: { CLEAR: 0.80, RAIN: 0.90, FOG: 0.97, STORM: 1.0 },  # No snow in arid
	},
	ClimateBiome.HIGHLAND: {
		Season.SPRING: { CLEAR: 0.45, RAIN: 0.65, FOG: 0.85, STORM: 1.0 },
		Season.SUMMER: { CLEAR: 0.60, RAIN: 0.80, FOG: 0.92, STORM: 1.0 },
		Season.AUTUMN: { CLEAR: 0.40, RAIN: 0.60, FOG: 0.82, STORM: 0.92, SNOW: 1.0 },
		Season.WINTER: { CLEAR: 0.30, FOG: 0.50, SNOW: 0.80, BLIZZARD: 1.0 },  # Harsh winters
	},
	ClimateBiome.SWAMPLAND: {
		Season.SPRING: { CLEAR: 0.30, RAIN: 0.60, FOG: 0.90, STORM: 1.0 },
		Season.SUMMER: { CLEAR: 0.40, RAIN: 0.70, FOG: 0.92, STORM: 1.0 },
		Season.AUTUMN: { CLEAR: 0.25, RAIN: 0.55, FOG: 0.90, STORM: 1.0 },
		Season.WINTER: { CLEAR: 0.35, RAIN: 0.50, FOG: 0.80, SNOW: 0.95, BLIZZARD: 1.0 },
	},
	ClimateBiome.NORTHERN: {
		Season.SPRING: { CLEAR: 0.40, RAIN: 0.55, FOG: 0.70, SNOW: 0.90, BLIZZARD: 1.0 },
		Season.SUMMER: { CLEAR: 0.55, RAIN: 0.75, FOG: 0.88, STORM: 1.0 },
		Season.AUTUMN: { CLEAR: 0.35, RAIN: 0.50, FOG: 0.65, SNOW: 0.88, BLIZZARD: 1.0 },
		Season.WINTER: { CLEAR: 0.20, FOG: 0.35, SNOW: 0.70, BLIZZARD: 1.0 },  # Brutal winters
	},
}


## Roll weather for a given climate and season using provided RNG.
## Returns weather type int (matches WeatherType enum).
static func roll_weather(rng: RandomNumberGenerator, climate: int, season: int) -> int:
	var table: Dictionary = WEATHER_TABLES.get(climate, WEATHER_TABLES[ClimateBiome.TEMPERATE])
	var season_probs: Dictionary = table.get(season, table[Season.SUMMER])

	var roll: float = rng.randf()

	# Check cumulative probabilities in order
	# Sort by probability threshold to ensure correct order
	var sorted_weather: Array = season_probs.keys()
	sorted_weather.sort_custom(func(a, b): return season_probs[a] < season_probs[b])

	for weather_type in sorted_weather:
		if roll < season_probs[weather_type]:
			return weather_type

	# Fallback to clear if something goes wrong
	return CLEAR


## Get the most likely weather for a climate/season (for UI previews).
static func get_dominant_weather(climate: int, season: int) -> int:
	var table: Dictionary = WEATHER_TABLES.get(climate, WEATHER_TABLES[ClimateBiome.TEMPERATE])
	var season_probs: Dictionary = table.get(season, table[Season.SUMMER])

	# Find weather with highest individual probability
	var best_weather: int = CLEAR
	var best_prob: float = 0.0
	var prev_threshold: float = 0.0

	var sorted_weather: Array = season_probs.keys()
	sorted_weather.sort_custom(func(a, b): return season_probs[a] < season_probs[b])

	for weather_type in sorted_weather:
		var individual_prob: float = season_probs[weather_type] - prev_threshold
		if individual_prob > best_prob:
			best_prob = individual_prob
			best_weather = weather_type
		prev_threshold = season_probs[weather_type]

	return best_weather


## Get weather name string (for debugging/UI).
static func get_weather_name(weather_type: int) -> String:
	match weather_type:
		CLEAR: return "Clear"
		RAIN: return "Rain"
		FOG: return "Fog"
		STORM: return "Storm"
		SNOW: return "Snow"
		BLIZZARD: return "Blizzard"
	return "Unknown"
