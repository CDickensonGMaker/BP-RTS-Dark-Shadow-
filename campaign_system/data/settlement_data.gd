# Settlement data for campaign map.
# Represents villages, towns, cities, fortresses, and capitals with building slots.
class_name SettlementData
extends Resource


enum SettlementType { VILLAGE, TOWN, CITY, FORTRESS, CAPITAL }


@export var settlement_id: String = ""
@export var settlement_name: String = "Unnamed Settlement"
@export var settlement_type: SettlementType = SettlementType.VILLAGE

# Parent region (for capital + minor settlement system)
@export var region_id: String = ""
@export var is_regional_capital: bool = false  # True = controlling this controls the region

# Ownership
@export var owner_faction: String = ""  # "" = neutral/unowned

# Position on campaign map
@export var map_position: Vector2 = Vector2.ZERO

# Building system - slots determined by settlement type
@export var buildings: Array = []  # Array of BuildingData

# Economy (base values, modified by buildings)
@export var base_income: int = 50
@export var current_income: int = 50

# Supply generation (DEI style)
@export var base_supply: int = 5
@export var current_supply: int = 5

# Replenishment (Napoleon TW style - percentage per turn)
@export var base_replenishment: float = 0.03
@export var replenishment_bonus: float = 0.0

# Population for recruitment (DEI style, simplified)
@export var population: int = 1000
@export var population_growth_rate: float = 0.02  # 2% per turn
@export var recruitment_pools: Dictionary = {
	"infantry": 20,
	"ranged": 10,
	"cavalry": 5,
	"special": 2
}

# Defense (for sieges)
@export var has_walls: bool = false
@export var wall_level: int = 0  # 0 = none, 1-3 = strength

# Garrison
@export var garrison_regiments: Array = []  # Auto-defense units


# Settlement type constants
const TYPE_BUILDING_SLOTS: Dictionary = {
	SettlementType.VILLAGE: 2,
	SettlementType.TOWN: 4,
	SettlementType.CITY: 6,
	SettlementType.FORTRESS: 4,
	SettlementType.CAPITAL: 8
}

const TYPE_BASE_INCOME: Dictionary = {
	SettlementType.VILLAGE: 50,
	SettlementType.TOWN: 150,
	SettlementType.CITY: 300,
	SettlementType.FORTRESS: 100,
	SettlementType.CAPITAL: 500
}

const TYPE_BASE_SUPPLY: Dictionary = {
	SettlementType.VILLAGE: 5,
	SettlementType.TOWN: 15,
	SettlementType.CITY: 25,
	SettlementType.FORTRESS: 30,
	SettlementType.CAPITAL: 40
}

const TYPE_BASE_REPLENISHMENT: Dictionary = {
	SettlementType.VILLAGE: 0.03,
	SettlementType.TOWN: 0.07,
	SettlementType.CITY: 0.12,
	SettlementType.FORTRESS: 0.08,
	SettlementType.CAPITAL: 0.15
}

const TYPE_HAS_WALLS: Dictionary = {
	SettlementType.VILLAGE: false,
	SettlementType.TOWN: false,  # Can build walls
	SettlementType.CITY: true,
	SettlementType.FORTRESS: true,
	SettlementType.CAPITAL: true
}


func _init() -> void:
	# Apply type defaults when created
	apply_type_defaults()


func apply_type_defaults() -> void:
	base_income = TYPE_BASE_INCOME.get(settlement_type, 50)
	current_income = base_income
	base_supply = TYPE_BASE_SUPPLY.get(settlement_type, 5)
	current_supply = base_supply
	base_replenishment = TYPE_BASE_REPLENISHMENT.get(settlement_type, 0.03)
	has_walls = TYPE_HAS_WALLS.get(settlement_type, false)


func get_building_slots() -> int:
	return TYPE_BUILDING_SLOTS.get(settlement_type, 2)


func get_available_slots() -> int:
	return get_building_slots() - buildings.size()


func can_build() -> bool:
	return get_available_slots() > 0


func has_building(building_id: String) -> bool:
	for building in buildings:
		if building.building_id == building_id:
			return true
	return false


func get_building(building_id: String) -> Resource:
	for building in buildings:
		if building.building_id == building_id:
			return building
	return null


func get_building_tier(building_category: String) -> int:
	# Find highest tier building of a category
	var highest_tier := 0
	for building in buildings:
		if building.get_category_name() == building_category:
			highest_tier = maxi(highest_tier, building.tier)
	return highest_tier


func get_total_replenishment() -> float:
	return base_replenishment + replenishment_bonus


func recalculate_bonuses() -> void:
	# Reset to base values
	current_income = base_income
	current_supply = base_supply
	replenishment_bonus = 0.0

	# Apply building bonuses
	for building in buildings:
		current_income += building.income_bonus
		current_supply += building.supply_bonus
		replenishment_bonus += building.replenishment_bonus


func get_recruitment_pool(pool_type: String) -> int:
	return recruitment_pools.get(pool_type, 0)


func consume_recruitment(pool_type: String, amount: int) -> bool:
	if recruitment_pools.has(pool_type):
		if recruitment_pools[pool_type] >= amount:
			recruitment_pools[pool_type] -= amount
			return true
	return false


func regenerate_population() -> void:
	# Called each turn
	var growth := int(population * population_growth_rate)
	population += growth

	# Regenerate recruitment pools based on population
	recruitment_pools["infantry"] = mini(recruitment_pools["infantry"] + 2, population / 50)
	recruitment_pools["ranged"] = mini(recruitment_pools["ranged"] + 1, population / 100)
	recruitment_pools["cavalry"] = mini(recruitment_pools["cavalry"] + 1, population / 200)


func get_type_name() -> String:
	match settlement_type:
		SettlementType.VILLAGE:
			return "Village"
		SettlementType.TOWN:
			return "Town"
		SettlementType.CITY:
			return "City"
		SettlementType.FORTRESS:
			return "Fortress"
		SettlementType.CAPITAL:
			return "Capital"
	return "Unknown"
