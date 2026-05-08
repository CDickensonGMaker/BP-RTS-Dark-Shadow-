# Region/territory data for campaign map.
# Defines territorial boundaries, terrain, and settlement references.
class_name RegionData
extends Resource


enum TerrainType { PLAINS, FOREST, HILLS, MOUNTAINS, DESERT, SWAMP, COAST }

## Climate biome - affects what weather is likely in this region.
## Decoupled from terrain_type (terrain affects movement/attrition; climate affects weather).
## Default mapping is sensible per terrain but can be overridden per-region.
enum ClimateBiome {
	TEMPERATE,   # Default - balanced rainfall, mild winters. Most plains/forests/coast.
	ARID,        # Hot, dry. Deserts, badlands. Rare rain, never snow.
	HIGHLAND,    # Cold, frequent fog/snow in winter. Mountains, high hills.
	SWAMPLAND,   # Humid, frequent fog and rain. Swamps, marshlands.
	NORTHERN,    # Cold year-round, snowy winters dominate. Far north regions.
}


@export var region_id: String = ""
@export var region_name: String = "Unnamed Region"

# Ownership
@export var owner_faction: String = ""  # "" = neutral/contested

# Map geometry
@export var map_polygon: PackedVector2Array = PackedVector2Array()  # Click detection boundary
@export var map_center: Vector2 = Vector2.ZERO  # For labels/icons

# Terrain
@export var terrain_type: TerrainType = TerrainType.PLAINS
@export var is_passable: bool = true

# Climate (affects weather - defaults from terrain but can be overridden)
@export var climate: ClimateBiome = ClimateBiome.TEMPERATE

# Movement costs (DEI/Napoleon style)
@export var movement_cost_modifier: float = 1.0  # 1.0 = normal, 2.0 = difficult

# Settlements in this region (Capital + Minor Settlements model)
@export var capital_settlement_id: String = ""  # The regional capital - controlling this controls the region
@export var minor_settlement_ids: Array[String] = []  # Optional minor settlements (provide bonuses)

# Supply and attrition (DEI/Napoleon style)
@export var supplies_friendly_armies: bool = true  # Only supplies if owned
@export var has_attrition_risk: bool = false       # Desert/swamp can cause attrition
@export var attrition_type: String = ""            # "heat", "cold", "swamp"
@export var attrition_damage: float = 0.05         # 5% losses per turn

# Morale modifier (DEI - fighting in homeland)
@export var homeland_morale_bonus: float = 10.0

# Visual
@export var region_color: Color = Color(0.5, 0.5, 0.5, 0.3)
@export var border_color: Color = Color(0.3, 0.3, 0.3, 1.0)


# Terrain constants
const TERRAIN_MOVEMENT_COST: Dictionary = {
	TerrainType.PLAINS: 1.0,
	TerrainType.FOREST: 1.3,
	TerrainType.HILLS: 1.5,
	TerrainType.MOUNTAINS: 2.5,
	TerrainType.DESERT: 1.2,
	TerrainType.SWAMP: 1.8,
	TerrainType.COAST: 1.0
}

const TERRAIN_ATTRITION: Dictionary = {
	TerrainType.DESERT: {"has_risk": true, "type": "heat", "damage": 0.05},
	TerrainType.SWAMP: {"has_risk": true, "type": "swamp", "damage": 0.03},
	TerrainType.MOUNTAINS: {"has_risk": true, "type": "cold", "damage": 0.04}
}

# Default climate biome based on terrain type
const TERRAIN_CLIMATE_DEFAULTS: Dictionary = {
	TerrainType.PLAINS: ClimateBiome.TEMPERATE,
	TerrainType.FOREST: ClimateBiome.TEMPERATE,
	TerrainType.HILLS: ClimateBiome.TEMPERATE,
	TerrainType.MOUNTAINS: ClimateBiome.HIGHLAND,
	TerrainType.DESERT: ClimateBiome.ARID,
	TerrainType.SWAMP: ClimateBiome.SWAMPLAND,
	TerrainType.COAST: ClimateBiome.TEMPERATE,
}


func _init() -> void:
	apply_terrain_defaults()


func apply_terrain_defaults() -> void:
	movement_cost_modifier = TERRAIN_MOVEMENT_COST.get(terrain_type, 1.0)

	# Apply default climate if not explicitly set (check if still at default TEMPERATE for non-plains)
	if climate == ClimateBiome.TEMPERATE and terrain_type != TerrainType.PLAINS:
		climate = TERRAIN_CLIMATE_DEFAULTS.get(terrain_type, ClimateBiome.TEMPERATE)

	if TERRAIN_ATTRITION.has(terrain_type):
		var attrition_data: Dictionary = TERRAIN_ATTRITION[terrain_type]
		has_attrition_risk = attrition_data.get("has_risk", false)
		attrition_type = attrition_data.get("type", "")
		attrition_damage = attrition_data.get("damage", 0.05)
	else:
		has_attrition_risk = false
		attrition_type = ""
		attrition_damage = 0.0


func get_terrain_name() -> String:
	match terrain_type:
		TerrainType.PLAINS:
			return "Plains"
		TerrainType.FOREST:
			return "Forest"
		TerrainType.HILLS:
			return "Hills"
		TerrainType.MOUNTAINS:
			return "Mountains"
		TerrainType.DESERT:
			return "Desert"
		TerrainType.SWAMP:
			return "Swamp"
		TerrainType.COAST:
			return "Coast"
	return "Unknown"


func is_owned_by(faction: String) -> bool:
	return owner_faction == faction and owner_faction != ""


func is_neutral() -> bool:
	return owner_faction == ""


func is_hostile_to(faction: String) -> bool:
	return owner_faction != "" and owner_faction != faction


func contains_point(point: Vector2) -> bool:
	if map_polygon.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, map_polygon)


func get_movement_cost(base_cost: float) -> float:
	return base_cost * movement_cost_modifier


func get_supply_for_faction(faction: String) -> int:
	# Returns total supply available in this region for a faction
	if not supplies_friendly_armies:
		return 0
	if not is_owned_by(faction):
		return 0

	# Sum supply from all settlements in region
	# Note: Settlements must be looked up through CampaignManager
	return 0  # Calculated by SupplyManager using settlement_ids


func should_apply_attrition(battalion_in_settlement: bool) -> bool:
	# Napoleon TW style - armies in settlements avoid terrain attrition
	if battalion_in_settlement:
		return false
	return has_attrition_risk


func get_morale_modifier_for_faction(faction: String) -> float:
	# DEI style - fighting in homeland gives morale bonus
	if is_owned_by(faction):
		return homeland_morale_bonus
	elif is_hostile_to(faction):
		return -homeland_morale_bonus * 0.5  # -5% in enemy territory
	return 0.0


func get_region_info() -> Dictionary:
	return {
		"id": region_id,
		"name": region_name,
		"terrain": get_terrain_name(),
		"owner": owner_faction if owner_faction != "" else "Neutral",
		"movement_cost": movement_cost_modifier,
		"attrition_risk": has_attrition_risk,
		"capital": capital_settlement_id,
		"minor_settlements": minor_settlement_ids.size()
	}


func get_all_settlement_ids() -> Array[String]:
	## Returns all settlements in this region (capital + minors)
	var all_ids: Array[String] = []
	if capital_settlement_id != "":
		all_ids.append(capital_settlement_id)
	all_ids.append_array(minor_settlement_ids)
	return all_ids


func has_capital() -> bool:
	return capital_settlement_id != ""


func is_controlled_by(faction: String) -> bool:
	## A region is controlled by whoever holds the capital
	## Must check capital settlement ownership through CampaignManager
	return owner_faction == faction
