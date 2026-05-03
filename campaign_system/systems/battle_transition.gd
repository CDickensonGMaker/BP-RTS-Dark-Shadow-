# Bridge between campaign map and battle scenes.
# Handles scene switching and data passing.
extends Node


# Battle configuration passed to battle scene
var battle_data: Dictionary = {}
# {
#   "player_regiments": Array[RegimentData],
#   "enemy_regiments": Array[RegimentData],
#   "terrain_type": String,
#   "is_contract": bool,
#   "contract_data": Resource (optional),
# }

# Result from completed battle
var battle_result: Dictionary = {}

# Scene paths
var campaign_scene_path: String = "res://campaign_system/scenes/campaign_map.tscn"
var default_battle_scene: String = "res://scenes/battle_scene.tscn"

# Track if we came from campaign
var from_campaign: bool = false


func start_battle_from_campaign(player_battalion, enemy_regiments: Array, terrain: String = "plains") -> void:
	from_campaign = true

	battle_data = {
		"player_regiments": player_battalion.regiments.duplicate(),
		"enemy_regiments": enemy_regiments,
		"terrain_type": terrain,
		"is_contract": false,
		"battalion_id": player_battalion.battalion_id,
	}

	# Transition to battle scene
	_transition_to_battle()


func start_contract_battle(player_battalion, contract) -> void:
	from_campaign = true

	# Contract should have enemy_regiments defined
	var enemy_regiments: Array = []
	if "enemy_regiments" in contract:
		enemy_regiments = contract.enemy_regiments

	var terrain = "plains"
	if "terrain_type" in contract:
		terrain = contract.terrain_type

	battle_data = {
		"player_regiments": player_battalion.regiments.duplicate(),
		"enemy_regiments": enemy_regiments,
		"terrain_type": terrain,
		"is_contract": true,
		"contract_data": contract,
		"battalion_id": player_battalion.battalion_id,
	}

	_transition_to_battle()


func _transition_to_battle() -> void:
	# Select battle scene based on terrain
	var battle_scene := default_battle_scene
	match battle_data.get("terrain_type", "plains"):
		"city":
			battle_scene = "res://scenes/battle_scene_city.tscn"
		"village":
			battle_scene = "res://scenes/battle_scene_village.tscn"
		"siege":
			battle_scene = "res://scenes/battle_scene_siege.tscn"

	get_tree().change_scene_to_file(battle_scene)


func return_to_campaign(result: Dictionary) -> void:
	if not from_campaign:
		return

	battle_result = result
	from_campaign = false

	# Emit signal before scene change
	CampaignSignals.battle_returning.emit(result)

	# Clear battle data
	battle_data.clear()

	# Return to campaign map
	get_tree().change_scene_to_file(campaign_scene_path)


func has_battle_data() -> bool:
	return not battle_data.is_empty()


func get_player_regiments() -> Array:
	return battle_data.get("player_regiments", [])


func get_enemy_regiments() -> Array:
	return battle_data.get("enemy_regiments", [])


func is_campaign_battle() -> bool:
	return from_campaign and has_battle_data()


func clear_battle_data() -> void:
	battle_data.clear()
	battle_result.clear()
	from_campaign = false
