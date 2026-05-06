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
	# Connect to relevant signals (only if not already connected)
	if CampaignSignals:
		if not CampaignSignals.battalion_selected.is_connected(_on_battalion_selected):
			CampaignSignals.battalion_selected.connect(_on_battalion_selected)
		if not CampaignSignals.turn_ended.is_connected(_on_turn_ended):
			CampaignSignals.turn_ended.connect(_on_turn_ended)
		if not CampaignSignals.battle_returning.is_connected(_on_battle_returning):
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
	battalion.map_position = Vector2(360, 520)  # Westervale - player starting region
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

	# Load battalions
	battalions.clear()
	var battalion_saves: Array = data.get("battalions", [])
	for bat_data in battalion_saves:
		var battalion = BattalionDataScript.new()
		battalion.battalion_id = bat_data.get("id", "battalion_1")
		battalion.battalion_name = bat_data.get("name", "Unknown Battalion")
		var pos_data: Dictionary = bat_data.get("position", {"x": 500, "y": 500})
		battalion.map_position = Vector2(pos_data.get("x", 500), pos_data.get("y", 500))
		battalion.movement_points = bat_data.get("movement", 100.0)
		battalion.max_movement_points = 100.0

		# Load regiment data if available
		var regiment_saves: Array = bat_data.get("regiments", [])
		for reg_data in regiment_saves:
			var regiment := RegimentData.new()
			regiment.regiment_name = reg_data.get("name", "Unknown")
			regiment.unit_type = reg_data.get("unit_type", UnitType.Type.INFANTRY)
			regiment.max_soldiers = reg_data.get("max_soldiers", 30)
			regiment.current_soldiers = reg_data.get("current_soldiers", 30)
			regiment.attack = reg_data.get("attack", 10)
			regiment.defense = reg_data.get("defense", 10)
			regiment.morale = reg_data.get("morale", 75)
			battalion.regiments.append(regiment)

		# If no regiments saved, create defaults
		if battalion.regiments.is_empty():
			battalion.regiments = _create_default_regiments()

		battalions.append(battalion)

	# If no battalions loaded, create starting one
	if battalions.is_empty():
		battalions.append(_create_starting_battalion())

	is_campaign_active = true


func _create_default_regiments() -> Array:
	var regiments: Array = []

	var swordsmen := RegimentData.new()
	swordsmen.regiment_name = "Swordsmen"
	swordsmen.unit_type = UnitType.Type.INFANTRY
	swordsmen.max_soldiers = 40
	swordsmen.current_soldiers = 40
	swordsmen.attack = 12
	swordsmen.defense = 12
	regiments.append(swordsmen)

	return regiments


func save_campaign(save_name: String = "") -> bool:
	## Save the current campaign to a file
	if save_name.is_empty():
		save_name = "campaign_%d" % Time.get_unix_time_from_system()

	var save_dir := "user://saves/"
	if not DirAccess.dir_exists_absolute(save_dir):
		DirAccess.make_dir_recursive_absolute(save_dir)

	var save_path := save_dir + save_name + ".sav"
	var data := get_save_data()

	# Include full regiment data
	var battalion_saves: Array = []
	for battalion in battalions:
		var reg_saves: Array = []
		for regiment in battalion.regiments:
			reg_saves.append({
				"name": regiment.regiment_name,
				"unit_type": regiment.unit_type,
				"max_soldiers": regiment.max_soldiers,
				"current_soldiers": regiment.current_soldiers,
				"attack": regiment.attack,
				"defense": regiment.defense,
				"morale": regiment.morale,
			})

		battalion_saves.append({
			"id": battalion.battalion_id,
			"name": battalion.battalion_name,
			"position": {"x": battalion.map_position.x, "y": battalion.map_position.y},
			"movement": battalion.movement_points,
			"regiments": reg_saves,
		})

	data["battalions"] = battalion_saves

	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		push_error("Failed to create save file: %s" % save_path)
		return false

	var json_text := JSON.stringify(data, "\t")
	file.store_string(json_text)
	file.close()
	print("Campaign saved to: %s" % save_path)
	return true
