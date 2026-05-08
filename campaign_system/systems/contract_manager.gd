# Manages contract lifecycle, generation, and objective tracking.
# Handles both contracts (missions) and open battles (map encounters).
extends Node

# =============================================================================
# CONSTANTS
# =============================================================================

## Maximum number of available contracts at once
const MAX_AVAILABLE_CONTRACTS := 3

## Open battle reward multiplier (contracts pay more)
const OPEN_BATTLE_REWARD_MULT := 0.5

# =============================================================================
# STATE
# =============================================================================

## Contract templates loaded from .tres files
var contract_templates: Array = []

## Currently available contracts to choose from
var available_contracts: Array = []

## The active contract being worked on (only one at a time)
var active_contract: ContractData = null

## Occupied settlements providing ongoing income
var occupied_settlements: Dictionary = {}  # settlement_id -> ContractData

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	_load_contract_templates()

	if CampaignSignals:
		CampaignSignals.turn_started.connect(_on_turn_started)
		CampaignSignals.battle_returning.connect(_on_battle_returning)
		CampaignSignals.settlement_captured.connect(_on_settlement_captured)


func _load_contract_templates() -> void:
	## Load all contract .tres files from the contracts directory
	var dir_path := "res://campaign_system/data/contracts/"
	var dir := DirAccess.open(dir_path)

	if not dir:
		push_warning("ContractManager: Could not open contracts directory at %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres"):
			var template := load(dir_path + file_name)
			if template is ContractData:
				contract_templates.append(template)
				print("[ContractManager] Loaded contract template: %s" % template.contract_name)
		file_name = dir.get_next()

	dir.list_dir_end()
	print("[ContractManager] Loaded %d contract templates" % contract_templates.size())

# =============================================================================
# CONTRACT GENERATION
# =============================================================================

func generate_contracts() -> void:
	## Generate new contracts at turn start.
	## Story contracts persist, random contracts are replaced.

	# Keep story contracts only
	available_contracts = available_contracts.filter(func(c): return c.is_story_contract)

	# Generate random contracts to fill slots
	var to_generate := MAX_AVAILABLE_CONTRACTS - available_contracts.size()

	for i in range(to_generate):
		var contract := _create_random_contract()
		if contract:
			available_contracts.append(contract)

	CampaignSignals.contracts_refreshed.emit(available_contracts)
	print("[ContractManager] Generated %d contracts, total available: %d" % [
		to_generate, available_contracts.size()])


func _create_random_contract() -> ContractData:
	## Create a new contract instance from templates
	if contract_templates.is_empty():
		return null

	var template: ContractData = contract_templates.pick_random()
	var contract := template.duplicate_contract()

	# Generate unique ID
	var turn := 1
	if CampaignManager:
		turn = CampaignManager.turn_number
	contract.contract_id = "contract_%d_%d" % [turn, randi() % 1000]

	return contract

# =============================================================================
# CONTRACT ACCEPTANCE
# =============================================================================

func accept_contract(contract: ContractData) -> bool:
	## Accept a contract and make it active.
	## Returns false if already have an active contract.

	if active_contract != null:
		push_warning("ContractManager: Already have an active contract")
		return false

	if not contract in available_contracts:
		push_warning("ContractManager: Contract not in available list")
		return false

	active_contract = contract
	available_contracts.erase(contract)

	CampaignSignals.contract_accepted.emit(contract)
	print("[ContractManager] Accepted contract: %s" % contract.contract_name)

	return true


func abandon_contract() -> void:
	## Abandon the current active contract
	if active_contract:
		CampaignSignals.contract_declined.emit(active_contract)
		print("[ContractManager] Abandoned contract: %s" % active_contract.contract_name)
		active_contract = null

# =============================================================================
# BATTLE INITIATION
# =============================================================================

func start_contract_battle(player_battalion) -> void:
	## Start a battle for the active contract
	if not active_contract:
		push_warning("ContractManager: No active contract to battle")
		return

	if not player_battalion:
		push_warning("ContractManager: No battalion provided")
		return

	BattleTransition.start_contract_battle(player_battalion, active_contract)


func start_open_battle(player_battalion, enemy_army) -> void:
	## Start an open battle from a map encounter (not a contract)
	## enemy_army should have: regiments, faction_name, and position

	if not player_battalion or not enemy_army:
		push_warning("ContractManager: Invalid battle participants")
		return

	# Build enemy regiments array
	var enemy_regiments: Array = []
	if enemy_army.has_method("get") and "regiments" in enemy_army:
		enemy_regiments = enemy_army.regiments
	elif enemy_army is Array:
		enemy_regiments = enemy_army

	# Calculate base reward for open battle
	var base_reward := _calculate_open_battle_reward(enemy_regiments)

	# Store open battle data in BattleTransition
	BattleTransition.battle_data = {
		"player_regiments": player_battalion.regiments.duplicate(),
		"enemy_regiments": enemy_regiments,
		"terrain_type": "plains",  # Default terrain for open battles
		"is_contract": false,
		"is_open_battle": true,
		"base_reward": base_reward,
		"battalion_id": player_battalion.battalion_id,
	}

	BattleTransition.from_campaign = true
	BattleTransition._transition_to_battle()


func _calculate_open_battle_reward(enemy_regiments: Array) -> int:
	## Calculate reward for open battle based on enemy strength
	## Returns 50% of what a contract would pay
	var strength := 0

	for regiment in enemy_regiments:
		if not regiment:
			continue

		var soldiers := 0
		var attack := 1

		if regiment.get("current_soldiers"):
			soldiers = regiment.current_soldiers
		elif regiment.get("max_soldiers"):
			soldiers = regiment.max_soldiers

		if regiment.get("attack"):
			attack = regiment.attack

		strength += soldiers * attack

	# Base reward scaled by strength, multiplied by open battle factor
	return int(strength * 0.5 * OPEN_BATTLE_REWARD_MULT)

# =============================================================================
# BATTLE COMPLETION
# =============================================================================

func _on_battle_returning(result: Dictionary) -> void:
	## Handle battle completion
	var is_victory: bool = result.get("winner", "") == "player"

	# Check if this was a contract battle
	if active_contract:
		_complete_contract(is_victory, result)
	elif result.get("is_open_battle", false):
		_complete_open_battle(is_victory, result)


func _complete_contract(victory: bool, result: Dictionary) -> void:
	## Process contract completion based on objective type
	if not active_contract:
		return

	var contract := active_contract

	if victory:
		match contract.objective_type:
			ContractData.ObjectiveType.DEFEAT_ARMY:
				_reward_defeat_army(contract)

			ContractData.ObjectiveType.SACK_CITY:
				_reward_sack_city(contract)

			ContractData.ObjectiveType.OCCUPY_CITY:
				_reward_occupy_city(contract)

			ContractData.ObjectiveType.CAPTURE_TERRITORY:
				_process_territory_battle(contract, result)
				# Don't complete yet if more settlements remain
				if not contract.is_territory_complete():
					return
				_reward_capture_territory(contract)

	# Complete or fail the contract
	CampaignSignals.contract_completed.emit(contract, victory)

	if victory:
		if CampaignManager:
			CampaignManager.completed_contracts.append(contract.contract_id)
		print("[ContractManager] Contract completed: %s" % contract.contract_name)
	else:
		print("[ContractManager] Contract failed: %s" % contract.contract_name)

	active_contract = null


func _complete_open_battle(victory: bool, result: Dictionary) -> void:
	## Process open battle completion
	if victory:
		var reward: int = result.get("base_reward", 200)
		if CampaignManager:
			CampaignManager.add_gold(reward, "open_battle")
		print("[ContractManager] Open battle won! Reward: %d gold" % reward)

# =============================================================================
# OBJECTIVE REWARDS
# =============================================================================

func _reward_defeat_army(contract: ContractData) -> void:
	## Simple defeat army - just pay the reward
	if CampaignManager:
		CampaignManager.add_gold(contract.gold_reward, "contract")
		if contract.bonus_gold > 0:
			# TODO: Check for low casualties bonus
			pass
	print("[ContractManager] DEFEAT_ARMY complete - %d gold" % contract.gold_reward)


func _reward_sack_city(contract: ContractData) -> void:
	## Sack settlement - one-time loot reward
	if CampaignManager:
		CampaignManager.add_gold(contract.gold_reward, "contract_sack")

	# Mark settlement as sacked/hostile
	var settlement = BuildingManager.get_settlement(contract.target_settlement_id) if BuildingManager else null
	if settlement:
		CampaignSignals.settlement_captured.emit(settlement, "hostile")
	else:
		push_warning("[ContractManager] Could not find settlement: %s" % contract.target_settlement_id)

	print("[ContractManager] SACK_CITY complete - %d gold loot" % contract.gold_reward)


func _reward_occupy_city(contract: ContractData) -> void:
	## Occupy settlement - base reward + ongoing income
	if CampaignManager:
		CampaignManager.add_gold(contract.gold_reward, "contract")

	# Register for ongoing income
	if contract.ongoing_income > 0:
		occupied_settlements[contract.target_settlement_id] = contract
		print("[ContractManager] Settlement occupied - %d gold/turn" % contract.ongoing_income)

	# Mark settlement as captured
	CampaignSignals.settlement_captured.emit(
		contract.target_settlement_id, "player")

	print("[ContractManager] OCCUPY_CITY complete - %d gold + %d/turn" % [
		contract.gold_reward, contract.ongoing_income])


func _process_territory_battle(contract: ContractData, result: Dictionary) -> void:
	## Track settlement capture for CAPTURE_TERRITORY contracts
	var settlement_id: String = result.get("settlement_id", "")
	if settlement_id and settlement_id in contract.settlements_to_capture:
		contract.mark_settlement_captured(settlement_id)
		CampaignSignals.settlement_captured.emit(settlement_id, "player")

		var progress := contract.get_territory_progress()
		print("[ContractManager] Territory progress: %d/%d settlements" % [
			progress.captured, progress.total])


func _reward_capture_territory(contract: ContractData) -> void:
	## Capture entire territory - big reward
	if CampaignManager:
		CampaignManager.add_gold(contract.gold_reward, "contract_territory")

	print("[ContractManager] CAPTURE_TERRITORY complete - %d gold" % contract.gold_reward)

# =============================================================================
# TURN PROCESSING
# =============================================================================

func _on_turn_started(turn: int) -> void:
	## Process turn start - generate contracts and collect income

	# Generate new contracts on turns after the first
	if turn > 1:
		generate_contracts()

	# Collect income from occupied settlements
	_collect_ongoing_income()


func _on_settlement_captured(settlement_id, new_owner: String) -> void:
	## Handle settlement ownership change
	# If we lose an occupied settlement, remove it from income
	if new_owner != "player" and occupied_settlements.has(settlement_id):
		var contract = occupied_settlements[settlement_id]
		print("[ContractManager] Lost occupied settlement: %s (-%d gold/turn)" % [
			settlement_id, contract.ongoing_income])
		occupied_settlements.erase(settlement_id)


func _collect_ongoing_income() -> void:
	## Collect per-turn income from occupied settlements
	var total_income := 0

	for settlement_id in occupied_settlements:
		var contract: ContractData = occupied_settlements[settlement_id]
		total_income += contract.ongoing_income

	if total_income > 0 and CampaignManager:
		CampaignManager.add_gold(total_income, "settlement_income")
		print("[ContractManager] Collected %d gold from %d occupied settlements" % [
			total_income, occupied_settlements.size()])

# =============================================================================
# QUERIES
# =============================================================================

func has_active_contract() -> bool:
	return active_contract != null


func get_active_contract() -> ContractData:
	return active_contract


func get_available_contracts() -> Array:
	return available_contracts


func get_occupied_settlements() -> Dictionary:
	return occupied_settlements


func get_total_ongoing_income() -> int:
	var total := 0
	for settlement_id in occupied_settlements:
		var contract: ContractData = occupied_settlements[settlement_id]
		total += contract.ongoing_income
	return total


func get_contract_by_id(contract_id: String) -> ContractData:
	## Find a contract by ID in available or active
	if active_contract and active_contract.contract_id == contract_id:
		return active_contract

	for contract in available_contracts:
		if contract.contract_id == contract_id:
			return contract

	return null
