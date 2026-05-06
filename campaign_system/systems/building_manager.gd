# Manages building construction across all settlements.
# Handles construction queues, prerequisites, and applying building effects.
extends Node


# Construction queue: settlement_id -> {building: BuildingData, turns_remaining: int}
var construction_queues: Dictionary = {}

# Cache of all settlements for quick lookup
var settlements_cache: Dictionary = {}  # settlement_id -> SettlementData

# Global replenishment bonus from supply posts (Napoleon TW style)
var global_replenishment_bonus: float = 0.0


func _ready() -> void:
	# Connect to turn signals
	if CampaignSignals:
		CampaignSignals.turn_ended.connect(_on_turn_ended)


func register_settlement(settlement: Resource) -> void:
	settlements_cache[settlement.settlement_id] = settlement


func unregister_settlement(settlement_id: String) -> void:
	settlements_cache.erase(settlement_id)
	construction_queues.erase(settlement_id)


func get_settlement(settlement_id: String) -> Resource:
	return settlements_cache.get(settlement_id, null)


func get_all_settlements() -> Array:
	return settlements_cache.values()


func get_settlements_by_faction(faction: String) -> Array:
	var result := []
	for settlement in settlements_cache.values():
		if settlement.owner_faction == faction:
			result.append(settlement)
	return result


# =============================================================================
# Construction
# =============================================================================

func can_build(settlement: Resource, building: Resource, current_gold: int) -> Dictionary:
	# Returns {can_build: bool, reason: String}

	# Check building's own requirements
	var building_check: Dictionary = building.can_build_in(settlement)
	if not building_check.can_build:
		return building_check

	# Check gold
	if current_gold < building.gold_cost:
		return {
			"can_build": false,
			"reason": "Insufficient gold (need %d, have %d)" % [building.gold_cost, current_gold]
		}

	# Check if already constructing something
	if is_constructing(settlement.settlement_id):
		return {
			"can_build": false,
			"reason": "Already constructing a building"
		}

	return {"can_build": true, "reason": ""}


func start_construction(settlement: Resource, building: Resource) -> bool:
	var gold_check := can_build(settlement, building, CampaignManager.current_gold)
	if not gold_check.can_build:
		push_warning("Cannot build: %s" % gold_check.reason)
		return false

	# Deduct gold
	CampaignManager.current_gold -= building.gold_cost

	# Add to construction queue
	construction_queues[settlement.settlement_id] = {
		"building": building,
		"turns_remaining": building.turns_to_build
	}

	CampaignSignals.building_started.emit(settlement, building)
	return true


func is_constructing(settlement_id: String) -> bool:
	return construction_queues.has(settlement_id)


func get_construction_progress(settlement_id: String) -> Dictionary:
	if not construction_queues.has(settlement_id):
		return {}

	var queue: Dictionary = construction_queues[settlement_id]
	return {
		"building": queue.building,
		"turns_remaining": queue.turns_remaining,
		"total_turns": queue.building.turns_to_build,
		"progress": 1.0 - (float(queue.turns_remaining) / queue.building.turns_to_build)
	}


func cancel_construction(settlement_id: String) -> bool:
	if not construction_queues.has(settlement_id):
		return false

	var queue: Dictionary = construction_queues[settlement_id]

	# Refund half the gold
	var refund: int = queue.building.gold_cost / 2
	CampaignManager.current_gold += refund

	construction_queues.erase(settlement_id)
	return true


# =============================================================================
# Turn Processing
# =============================================================================

func _on_turn_ended(_turn_number: int) -> void:
	process_construction()


func process_construction() -> void:
	var completed_settlements := []

	for settlement_id in construction_queues.keys():
		var queue: Dictionary = construction_queues[settlement_id]
		queue.turns_remaining -= 1

		if queue.turns_remaining <= 0:
			completed_settlements.append(settlement_id)

	# Complete construction
	for settlement_id in completed_settlements:
		_complete_construction(settlement_id)


func _complete_construction(settlement_id: String) -> void:
	if not construction_queues.has(settlement_id):
		return

	var queue: Dictionary = construction_queues[settlement_id]
	var settlement: Resource = settlements_cache.get(settlement_id)

	if not settlement:
		push_error("Settlement not found: %s" % settlement_id)
		construction_queues.erase(settlement_id)
		return

	var building: Resource = queue.building

	# Add building to settlement
	settlement.buildings.append(building)

	# Apply effects
	_apply_building_effects(settlement, building)

	# Remove from queue
	construction_queues.erase(settlement_id)

	CampaignSignals.building_completed.emit(settlement, building)


func _apply_building_effects(settlement: Resource, building: Resource) -> void:
	# Recalculate settlement bonuses
	settlement.recalculate_bonuses()

	# Handle global effects (supply posts)
	if building.global_replenishment:
		global_replenishment_bonus += building.replenishment_bonus


# =============================================================================
# Building Destruction
# =============================================================================

func destroy_building(settlement: Resource, building: Resource) -> bool:
	var index: int = settlement.buildings.find(building)
	if index == -1:
		return false

	settlement.buildings.remove_at(index)

	# Remove effects
	_remove_building_effects(settlement, building)

	settlement.recalculate_bonuses()

	CampaignSignals.building_destroyed.emit(settlement, building)
	return true


func _remove_building_effects(_settlement: Resource, building: Resource) -> void:
	# Remove global effects
	if building.global_replenishment:
		global_replenishment_bonus -= building.replenishment_bonus
		global_replenishment_bonus = maxf(0.0, global_replenishment_bonus)


# =============================================================================
# Queries
# =============================================================================

func get_available_buildings(settlement: Resource) -> Array:
	# Returns all buildings that can be built in this settlement
	var available := []

	# Load all building resources
	var building_dir := "res://campaign_system/data/buildings/"
	var dir := DirAccess.open(building_dir)

	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".tres"):
				var building := load(building_dir + file_name) as Resource
				if building:
					var check: Dictionary = building.can_build_in(settlement)
					if check.can_build:
						available.append(building)
			file_name = dir.get_next()
		dir.list_dir_end()

	return available


func get_buildings_by_category(settlement: Resource, category: int) -> Array:
	var result := []
	for building in settlement.buildings:
		if building.category == category:
			result.append(building)
	return result


func get_highest_tier_building(settlement: Resource, category: int) -> Resource:
	var highest: Resource = null
	var highest_tier := 0

	for building in settlement.buildings:
		if building.category == category and building.tier > highest_tier:
			highest = building
			highest_tier = building.tier

	return highest


func get_total_income_from_buildings(faction: String) -> int:
	var total := 0
	for settlement in get_settlements_by_faction(faction):
		for building in settlement.buildings:
			total += building.income_bonus
	return total


func get_total_upkeep_from_buildings(faction: String) -> int:
	var total := 0
	for settlement in get_settlements_by_faction(faction):
		for building in settlement.buildings:
			total += building.upkeep
	return total


func get_unlocked_units(settlement: Resource) -> Array[String]:
	var unlocked: Array[String] = []
	for building in settlement.buildings:
		for unit_id in building.unlocks_units:
			if not unlocked.has(unit_id):
				unlocked.append(unit_id)
	return unlocked


func get_equipment_bonuses(settlement: Resource) -> Dictionary:
	# Returns armor/attack bonuses from armory/blacksmith
	var armor_bonus := 0
	var attack_bonus := 0

	for building in settlement.buildings:
		armor_bonus += building.armor_upgrade
		attack_bonus += building.attack_upgrade

	return {
		"armor": armor_bonus,
		"attack": attack_bonus
	}
