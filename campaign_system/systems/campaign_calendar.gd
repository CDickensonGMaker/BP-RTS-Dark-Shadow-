extends Node

## CampaignCalendar - Translates turn_number into structured time
## (year/season/week/day). Read-only consumer of CampaignManager.turn_number.
##
## Calendar design (Broken Provinces):
##   - 1 turn = 1 week
##   - 1 year = 52 weeks = 52 turns
##   - 1 year has 4 seasons of 13 weeks each
##   - Season order: Spring (week 1-13), Summer (14-26), Autumn (27-39), Winter (40-52)
##
## In-world month names (12 months x ~4.33 weeks each, approximate mapping):
##   Spring: Greenfall, Bloomtide, Sunsmile
##   Summer: Hightide, Dustwind, Sunfire
##   Autumn: Harvest, Leafall, Frostwake
##   Winter: Coldgrip, Hearthkeep, Frostmoon
##
## Example: turn 1 = Year 1, Greenfall, Week 1.
##          turn 53 = Year 2, Greenfall, Week 1.
##          turn 100 = Year 2, Frostwake, Week 9 of autumn.

signal day_changed(year: int, season: int, week_in_season: int)
signal season_changed(year: int, new_season: int)
signal year_changed(new_year: int)


enum Season {
	SPRING = 0,
	SUMMER = 1,
	AUTUMN = 2,
	WINTER = 3,
}

const SEASONS_PER_YEAR: int = 4
const WEEKS_PER_SEASON: int = 13
const WEEKS_PER_YEAR: int = 52

const SEASON_NAMES: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]

const MONTH_NAMES: Array[String] = [
	"Greenfall", "Bloomtide", "Sunsmile",      # Spring
	"Hightide", "Dustwind", "Sunfire",         # Summer
	"Harvest", "Leafall", "Frostwake",         # Autumn
	"Coldgrip", "Hearthkeep", "Frostmoon",     # Winter
]

# Cached state - recomputed when turn_number changes
var _last_known_turn: int = 0
var _current_year: int = 1
var _current_season: int = Season.SPRING
var _current_week_in_season: int = 1
var _current_month_index: int = 0  # 0..11


func _ready() -> void:
	if CampaignSignals:
		CampaignSignals.turn_started.connect(_on_turn_started)


func _on_turn_started(turn: int) -> void:
	_recompute(turn)


## Force-recompute calendar from current turn_number. Called on save load.
func sync_with_turn(turn: int) -> void:
	_recompute(turn)


func _recompute(turn: int) -> void:
	var prev_year: int = _current_year
	var prev_season: int = _current_season

	# Convert 1-based turn to 0-based week index
	var week_index: int = (turn - 1)
	_current_year = (week_index / WEEKS_PER_YEAR) + 1
	var week_in_year: int = week_index % WEEKS_PER_YEAR
	_current_season = week_in_year / WEEKS_PER_SEASON
	_current_week_in_season = (week_in_year % WEEKS_PER_SEASON) + 1
	# Month: 12 months across 52 weeks = ~4.33 weeks per month
	_current_month_index = clampi(int(float(week_in_year) / (52.0 / 12.0)), 0, 11)
	_last_known_turn = turn

	if _current_year != prev_year:
		year_changed.emit(_current_year)
		print("[CampaignCalendar] New Year: %d" % _current_year)
	if _current_season != prev_season:
		season_changed.emit(_current_year, _current_season)
		print("[CampaignCalendar] Season changed to %s (Year %d)" % [SEASON_NAMES[_current_season], _current_year])
	day_changed.emit(_current_year, _current_season, _current_week_in_season)


# === Public read-only API ===

func get_year() -> int:
	return _current_year


func get_season() -> int:
	return _current_season


func get_season_name() -> String:
	return SEASON_NAMES[_current_season]


func get_week_in_season() -> int:
	return _current_week_in_season


func get_month_index() -> int:
	return _current_month_index


func get_month_name() -> String:
	return MONTH_NAMES[_current_month_index]


func get_date_string() -> String:
	## Returns "Greenfall, Week 2 of Year 1" style string for UI.
	return "%s, Week %d of Year %d" % [get_month_name(), _current_week_in_season, _current_year]


func get_short_date_string() -> String:
	## Returns "Y1 Spring W2" style for compact UI.
	return "Y%d %s W%d" % [_current_year, get_season_name(), _current_week_in_season]


func get_total_weeks() -> int:
	## Total weeks since campaign start.
	return _last_known_turn


func is_winter() -> bool:
	return _current_season == Season.WINTER


func is_summer() -> bool:
	return _current_season == Season.SUMMER
