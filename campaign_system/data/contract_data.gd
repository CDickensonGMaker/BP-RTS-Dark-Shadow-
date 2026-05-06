class_name ContractData
extends Resource

## Contract data resource for campaign missions.
## Contracts offer higher rewards than open battles and have specific objectives.
##
## Usage:
##   var contract := preload("res://campaign_system/data/contracts/orc_raiders.tres")
##   ContractManager.accept_contract(contract)

# =============================================================================
# OBJECTIVE TYPES
# =============================================================================

## Types of contract objectives
enum ObjectiveType {
	DEFEAT_ARMY,       ## Kill/rout an enemy army - simplest objective
	SACK_CITY,         ## Attack settlement, loot it (one-time gold reward)
	OCCUPY_CITY,       ## Capture settlement, hold it (ongoing income)
	CAPTURE_TERRITORY, ## Control all settlements in a region
}

# =============================================================================
# BASIC INFO
# =============================================================================

@export_group("Basic Info")
## Unique contract identifier (auto-generated for random contracts)
@export var contract_id: String = ""
## Display name for the contract
@export var contract_name: String = "Unnamed Contract"
## Flavor text describing the mission
@export_multiline var description: String = ""
## Region where the contract takes place
@export var region_name: String = ""

# =============================================================================
# OBJECTIVE
# =============================================================================

@export_group("Objective")
## The type of objective to complete
@export var objective_type: ObjectiveType = ObjectiveType.DEFEAT_ARMY
## Target settlement ID for SACK_CITY or OCCUPY_CITY objectives
@export var target_settlement_id: String = ""
## Target region ID for CAPTURE_TERRITORY objectives
@export var target_region_id: String = ""

# =============================================================================
# DIFFICULTY & REWARDS
# =============================================================================

@export_group("Rewards")
## Threat level 1-5 (displayed as stars)
@export_range(1, 5) var threat_level: int = 1
## Gold reward on completion
@export var gold_reward: int = 500
## Bonus gold for low casualties (optional)
@export var bonus_gold: int = 0
## Per-turn income for OCCUPY_CITY contracts
@export var ongoing_income: int = 0

# =============================================================================
# ENEMY COMPOSITION
# =============================================================================

@export_group("Enemies")
## Enemy regiments to fight (Array of RegimentData)
@export var enemy_regiments: Array = []
## Enemy faction name for display
@export var enemy_faction_name: String = "Unknown"

# =============================================================================
# BATTLE SETTINGS
# =============================================================================

@export_group("Battle")
## Terrain type for the battle
@export var terrain_type: String = "plains"
## Time of day (day, dusk, night)
@export var time_of_day: String = "day"

# =============================================================================
# FLAGS
# =============================================================================

@export_group("Flags")
## Story contracts persist and aren't replaced by random generation
@export var is_story_contract: bool = false
## Turns until contract expires (-1 = unlimited)
@export var turns_available: int = -1

# =============================================================================
# MAP POSITION
# =============================================================================

@export_group("Map Position")
## Position on campaign map (for "Show on Map" feature)
@export var map_position: Vector2 = Vector2(500, 500)
## Whether this location is visible through fog of war
@export var always_visible: bool = false

# =============================================================================
# CAPTURE_TERRITORY TRACKING
# =============================================================================

## For CAPTURE_TERRITORY: list of settlement IDs that must be captured
@export var settlements_to_capture: Array[String] = []
## Runtime tracking: settlements already captured
var captured_settlements: Array[String] = []

# =============================================================================
# HELPER METHODS
# =============================================================================

func get_threat_stars() -> String:
	## Returns threat level as star string (e.g., "★★★☆☆")
	return "★".repeat(threat_level) + "☆".repeat(5 - threat_level)


func get_objective_text() -> String:
	## Returns human-readable objective type text
	match objective_type:
		ObjectiveType.DEFEAT_ARMY:
			return "Defeat Enemy Army"
		ObjectiveType.SACK_CITY:
			return "Sack Settlement"
		ObjectiveType.OCCUPY_CITY:
			return "Occupy Settlement"
		ObjectiveType.CAPTURE_TERRITORY:
			return "Capture Territory"
	return "Unknown"


func get_objective_description() -> String:
	## Returns detailed objective description based on type
	match objective_type:
		ObjectiveType.DEFEAT_ARMY:
			return "Defeat the enemy army to complete this contract."
		ObjectiveType.SACK_CITY:
			return "Attack and loot the settlement for a one-time reward."
		ObjectiveType.OCCUPY_CITY:
			return "Capture and hold the settlement for ongoing income."
		ObjectiveType.CAPTURE_TERRITORY:
			var remaining := settlements_to_capture.size() - captured_settlements.size()
			return "Control all %d settlements in the region. (%d remaining)" % [
				settlements_to_capture.size(), remaining]
	return ""


func get_total_enemies() -> int:
	## Returns total enemy soldier count across all regiments
	var total := 0
	for regiment in enemy_regiments:
		if regiment and regiment.get("current_soldiers"):
			total += regiment.current_soldiers
		elif regiment and regiment.get("max_soldiers"):
			total += regiment.max_soldiers
	return total


func get_reward_text() -> String:
	## Returns formatted reward text
	var text := "%d gold" % gold_reward
	if ongoing_income > 0:
		text += " + %d/turn" % ongoing_income
	if bonus_gold > 0:
		text += " (+%d bonus)" % bonus_gold
	return text


func is_territory_complete() -> bool:
	## For CAPTURE_TERRITORY: check if all settlements are captured
	if objective_type != ObjectiveType.CAPTURE_TERRITORY:
		return false
	for settlement_id in settlements_to_capture:
		if settlement_id not in captured_settlements:
			return false
	return true


func mark_settlement_captured(settlement_id: String) -> void:
	## Mark a settlement as captured (for CAPTURE_TERRITORY tracking)
	if settlement_id not in captured_settlements:
		captured_settlements.append(settlement_id)


func get_territory_progress() -> Dictionary:
	## Returns progress for CAPTURE_TERRITORY contracts
	return {
		"total": settlements_to_capture.size(),
		"captured": captured_settlements.size(),
		"remaining": settlements_to_capture.size() - captured_settlements.size(),
	}


func duplicate_contract() -> ContractData:
	## Creates a copy of this contract for instance-specific tracking
	var copy := duplicate(true) as ContractData
	copy.captured_settlements = []
	return copy
