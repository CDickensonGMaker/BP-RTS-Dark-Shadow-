# Core campaign state management.
# Handles turns, battalions, contracts, and save data.
extends Node

# Preload to ensure class is available
const BattalionDataScript = preload("res://campaign_system/data/battalion_data.gd")

# Campaign state
var company_name: String = "The Black Company"
var current_gold: int = 2000
var turn_number: int = 1

# Battalions (1-5 player battalions)
var battalions: Array = []  # Array of BattalionData
var selected_battalion = null  # BattalionData

# Contracts
var active_contract = null  # ContractData when implemented
var completed_contracts: Array[String] = []

# Scene reference
var campaign_map_scene_path: String = "res://campaign_system/scenes/campaign_map.tscn"

# Is campaign mode active
var is_campaign_active: bool = false


func _ready() -> void:
	# Connect to relevant signals
	if CampaignSignals:
		CampaignSignals.battalion_selected.connect(_on_battalion_selected)
		CampaignSignals.turn_ended.connect(_on_turn_ended)
		CampaignSignals.battle_returning.connect(_on_battle_returning)


func start_new_campaign() -> void:
	company_name = "The Black Company"
	current_gold = 2000
	turn_number = 1
	battalions.clear()
	completed_contracts.clear()
	active_contract = null
	is_campaign_active = true

	# Create starting battalion with test regiments
	var starting_battalion = _create_starting_battalion()
	battalions.append(starting_battalion)

	CampaignSignals.turn_started.emit(turn_number)


func _create_starting_battalion():
	var battalion = BattalionDataScript.new()
	battalion.battalion_id = "battalion_1"
	battalion.battalion_name = "Iron Wolves"
	battalion.map_position = Vector2(400, 300)
	battalion.movement_points = 100.0
	battalion.max_movement_points = 100.0

	# Create test regiments
	var swordsmen := RegimentData.new()
	swordsmen.regiment_name = "Iron Wolf Swordsmen"
	swordsmen.unit_type = UnitType.Type.INFANTRY
	swordsmen.max_soldiers = 40
	swordsmen.current_soldiers = 40
	swordsmen.attack = 12
	swordsmen.defense = 12
	swordsmen.set_meta("upkeep_cost", 15)

	var spearmen := RegimentData.new()
	spearmen.regiment_name = "Iron Wolf Spearmen"
	spearmen.unit_type = UnitType.Type.INFANTRY
	spearmen.max_soldiers = 40
	spearmen.current_soldiers = 40
	spearmen.attack = 10
	spearmen.defense = 14
	spearmen.charge_bonus = 8
	spearmen.set_meta("upkeep_cost", 12)

	var archers := RegimentData.new()
	archers.regiment_name = "Iron Wolf Archers"
	archers.unit_type = UnitType.Type.RANGED
	archers.max_soldiers = 30
	archers.current_soldiers = 30
	archers.attack = 6
	archers.defense = 6
	archers.ballistic_skill = 14
	archers.max_ammo = 24
	archers.current_ammo = 24
	archers.range_distance = 40.0
	archers.set_meta("upkeep_cost", 18)

	battalion.regiments = [swordsmen, spearmen, archers]
	return battalion


func end_turn() -> void:
	# Pay upkeep
	var total_upkeep := get_total_upkeep()
	if current_gold >= total_upkeep:
		current_gold -= total_upkeep
		CampaignSignals.upkeep_paid.emit(total_upkeep)
		CampaignSignals.gold_changed.emit(current_gold, -total_upkeep)
	else:
		CampaignSignals.insufficient_funds.emit(total_upkeep, current_gold)
		# Still deduct what we can
		current_gold = 0
		CampaignSignals.gold_changed.emit(current_gold, -current_gold)

	# Refresh all battalion movement
	for battalion in battalions:
		battalion.refresh_movement()

	turn_number += 1
	CampaignSignals.turn_ended.emit(turn_number - 1)
	CampaignSignals.turn_started.emit(turn_number)


func get_total_upkeep() -> int:
	var total := 0
	for battalion in battalions:
		total += battalion.get_total_upkeep()
	return total


func add_gold(amount: int, source: String = "reward") -> void:
	current_gold += amount
	CampaignSignals.reward_received.emit(amount, source)
	CampaignSignals.gold_changed.emit(current_gold, amount)


func _on_battalion_selected(battalion_node: Node2D) -> void:
	# Find matching BattalionData
	for battalion in battalions:
		if battalion.battalion_id == battalion_node.battalion_data.battalion_id:
			selected_battalion = battalion
			return


func _on_turn_ended(_turn: int) -> void:
	pass  # Additional turn end logic


func _on_battle_returning(result: Dictionary) -> void:
	is_campaign_active = true

	# Apply casualties to battalion
	if selected_battalion and result.has("casualties"):
		selected_battalion.apply_battle_casualties(result.casualties)

	# Award gold for victory
	if result.get("winner") == "player" and active_contract:
		var reward: int = 500
		if active_contract.has_method("get") or "gold_reward" in active_contract:
			reward = active_contract.gold_reward
		add_gold(reward, "contract")
		var contract_id = ""
		if "contract_id" in active_contract:
			contract_id = active_contract.contract_id
		completed_contracts.append(contract_id)
		active_contract = null


func get_save_data() -> Dictionary:
	var battalion_saves := []
	for battalion in battalions:
		battalion_saves.append({
			"id": battalion.battalion_id,
			"name": battalion.battalion_name,
			"position": {"x": battalion.map_position.x, "y": battalion.map_position.y},
			"movement": battalion.movement_points,
			# Regiment data would need separate serialization
		})

	return {
		"company_name": company_name,
		"gold": current_gold,
		"turn": turn_number,
		"battalions": battalion_saves,
		"completed_contracts": completed_contracts,
	}


func load_save_data(data: Dictionary) -> void:
	company_name = data.get("company_name", "The Black Company")
	current_gold = data.get("gold", 2000)
	turn_number = data.get("turn", 1)
	completed_contracts = data.get("completed_contracts", [])
	# Battalion loading would need full implementation
	is_campaign_active = true
