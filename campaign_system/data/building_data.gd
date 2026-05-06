# Building data for settlements.
# Represents structures that provide economic, military, and strategic bonuses.
class_name BuildingData
extends Resource


enum BuildingCategory {
	RESOURCE,      # Farms, mines, markets - income and supply
	RESEARCH,      # Libraries, academies - tech points
	PRODUCTION,    # Barracks, stables - unit recruitment
	ARMORY,        # Equipment upgrades - armor bonus
	BLACKSMITH,    # Weapon upgrades - attack bonus
	BESTIARY,      # Monster pens - special units
	WORKSHOP,      # Siege equipment - siege weapons
	SUPPLY         # Supply posts - replenishment (Napoleon TW style)
}


@export var building_id: String = ""
@export var building_name: String = "Unnamed Building"
@export var description: String = ""
@export var category: BuildingCategory = BuildingCategory.RESOURCE
@export var tier: int = 1  # 1-3 tiers for upgradeable buildings

# Requirements
@export var prerequisite_building: String = ""  # Required to build this
@export var required_settlement_type: int = 0   # Min SettlementType ordinal
@export var required_tech: String = ""          # Tech unlock requirement

# Costs
@export var gold_cost: int = 200
@export var turns_to_build: int = 1
@export var upkeep: int = 10

# Economic effects
@export var income_bonus: int = 0
@export var supply_bonus: int = 0

# Replenishment effects (Napoleon TW supply posts)
@export var replenishment_bonus: float = 0.0
@export var global_replenishment: bool = false  # Affects all regions

# Recruitment effects
@export var recruitment_bonus: Dictionary = {}  # {pool_type: amount}
@export var unlocks_units: Array[String] = []   # Unit IDs that can be recruited

# Equipment upgrades (Armory/Blacksmith)
@export var armor_upgrade: int = 0   # +armor for local recruits
@export var attack_upgrade: int = 0  # +attack for local recruits

# Research
@export var tech_points_per_turn: int = 0

# Visual
@export var icon: Texture2D


func get_category_name() -> String:
	match category:
		BuildingCategory.RESOURCE:
			return "Resource"
		BuildingCategory.RESEARCH:
			return "Research"
		BuildingCategory.PRODUCTION:
			return "Production"
		BuildingCategory.ARMORY:
			return "Armory"
		BuildingCategory.BLACKSMITH:
			return "Blacksmith"
		BuildingCategory.BESTIARY:
			return "Bestiary"
		BuildingCategory.WORKSHOP:
			return "Workshop"
		BuildingCategory.SUPPLY:
			return "Supply"
	return "Unknown"


func get_tier_name() -> String:
	match tier:
		1:
			return "Basic"
		2:
			return "Improved"
		3:
			return "Advanced"
	return "Tier %d" % tier


func get_full_name() -> String:
	if tier > 1:
		return "%s (%s)" % [building_name, get_tier_name()]
	return building_name


func can_build_in(settlement: Resource) -> Dictionary:
	# Returns {can_build: bool, reason: String}

	# Check settlement type requirement
	if settlement.settlement_type < required_settlement_type:
		return {
			"can_build": false,
			"reason": "Requires %s or higher" % _settlement_type_name(required_settlement_type)
		}

	# Check available slots
	if not settlement.can_build():
		return {
			"can_build": false,
			"reason": "No building slots available"
		}

	# Check prerequisite
	if prerequisite_building != "" and not settlement.has_building(prerequisite_building):
		return {
			"can_build": false,
			"reason": "Requires %s" % prerequisite_building
		}

	# Check if already has this exact building
	if settlement.has_building(building_id):
		return {
			"can_build": false,
			"reason": "Already built"
		}

	return {"can_build": true, "reason": ""}


func _settlement_type_name(type_value: int) -> String:
	match type_value:
		0:
			return "Village"
		1:
			return "Town"
		2:
			return "City"
		3:
			return "Fortress"
		4:
			return "Capital"
	return "Unknown"


func get_effects_summary() -> String:
	var effects := []

	if income_bonus > 0:
		effects.append("+%d Income" % income_bonus)
	if supply_bonus > 0:
		effects.append("+%d Supply" % supply_bonus)
	if replenishment_bonus > 0:
		var percent := int(replenishment_bonus * 100)
		if global_replenishment:
			effects.append("+%d%% Global Replenishment" % percent)
		else:
			effects.append("+%d%% Local Replenishment" % percent)
	if armor_upgrade > 0:
		effects.append("+%d Armor (recruits)" % armor_upgrade)
	if attack_upgrade > 0:
		effects.append("+%d Attack (recruits)" % attack_upgrade)
	if tech_points_per_turn > 0:
		effects.append("+%d Tech/turn" % tech_points_per_turn)

	for unit_id in unlocks_units:
		effects.append("Unlocks: %s" % unit_id)

	for pool_type in recruitment_bonus:
		effects.append("+%d %s recruitment" % [recruitment_bonus[pool_type], pool_type])

	if effects.is_empty():
		return "No effects"

	return "\n".join(effects)
