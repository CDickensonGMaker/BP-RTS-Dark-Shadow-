extends Node

## WeatherScheduler - Deterministic weather per region per turn.
## Uses campaign_seed + turn_number + region_id to generate consistent weather.
## Caches results per turn to avoid recomputation.

const ClimateWeatherTableScript = preload("res://campaign_system/data/climate_weather_table.gd")

# Cache: { turn_number: { region_id: weather_type } }
var _weather_cache: Dictionary = {}
var _current_turn: int = 0


func _ready() -> void:
	if CampaignSignals:
		CampaignSignals.turn_started.connect(_on_turn_started)


func _on_turn_started(turn: int) -> void:
	# Clear cache when turn changes
	if turn != _current_turn:
		_weather_cache.clear()
		_current_turn = turn


## Get deterministic weather for a region on current turn.
## Returns weather type int (matches WeatherType enum).
func get_weather_for_region(region_id: String) -> int:
	# Check cache first
	if _weather_cache.has(_current_turn):
		var turn_cache: Dictionary = _weather_cache[_current_turn]
		if turn_cache.has(region_id):
			return turn_cache[region_id]

	# Get campaign seed and turn from CampaignManager
	var campaign_seed: int = 0
	var turn: int = 1
	if CampaignManager:
		campaign_seed = CampaignManager.campaign_seed
		turn = CampaignManager.turn_number

	# Get region data for climate
	var climate: int = ClimateWeatherTableScript.ClimateBiome.TEMPERATE
	var region_data = _get_region_data(region_id)
	if region_data:
		climate = region_data.climate

	# Get current season from calendar
	var season: int = 0  # Spring default
	if CampaignCalendar:
		season = CampaignCalendar.get_season()

	# Create deterministic RNG from seed + turn + region hash
	var rng := RandomNumberGenerator.new()
	var region_hash: int = region_id.hash()
	rng.seed = campaign_seed + (turn * 1000) + region_hash

	# Roll weather
	var weather: int = ClimateWeatherTableScript.roll_weather(rng, climate, season)

	# Cache result
	if not _weather_cache.has(_current_turn):
		_weather_cache[_current_turn] = {}
	_weather_cache[_current_turn][region_id] = weather

	return weather


## Get weather name string for a region (for UI).
func get_weather_name_for_region(region_id: String) -> String:
	var weather: int = get_weather_for_region(region_id)
	return ClimateWeatherTableScript.get_weather_name(weather)


## Force recalculate weather (e.g., after loading save).
func invalidate_cache() -> void:
	_weather_cache.clear()


## Sync with a specific turn number (called on save load).
func sync_with_turn(turn: int) -> void:
	if turn != _current_turn:
		_weather_cache.clear()
		_current_turn = turn


## Preview weather for a future turn (for planning UI).
func preview_weather_for_turn(region_id: String, future_turn: int) -> int:
	var campaign_seed: int = 0
	if CampaignManager:
		campaign_seed = CampaignManager.campaign_seed

	# Get region climate
	var climate: int = ClimateWeatherTableScript.ClimateBiome.TEMPERATE
	var region_data = _get_region_data(region_id)
	if region_data:
		climate = region_data.climate

	# Calculate future season
	var future_season: int = _get_season_for_turn(future_turn)

	# Deterministic roll
	var rng := RandomNumberGenerator.new()
	var region_hash: int = region_id.hash()
	rng.seed = campaign_seed + (future_turn * 1000) + region_hash

	return ClimateWeatherTableScript.roll_weather(rng, climate, future_season)


## Get region data from CampaignManager or MapManager.
func _get_region_data(region_id: String):
	# Try MapManager first (has all region data)
	var map_manager = Engine.get_main_loop().root.get_node_or_null("/root/MapManager")
	if map_manager and map_manager.has_method("get_region"):
		return map_manager.get_region(region_id)

	# Fallback: try CampaignManager's region lookup
	if CampaignManager and CampaignManager.has_method("get_region_data"):
		return CampaignManager.get_region_data(region_id)

	return null


## Calculate season for a given turn number.
func _get_season_for_turn(turn: int) -> int:
	const WEEKS_PER_SEASON: int = 13
	const WEEKS_PER_YEAR: int = 52
	var week_index: int = (turn - 1) % WEEKS_PER_YEAR
	return week_index / WEEKS_PER_SEASON
