# Bridge between campaign map and battle scenes.
# Handles scene switching and data passing.
# Now supports pre-battle screen routing.
extends Node


# Battle configuration passed to battle scene
var battle_data: Dictionary = {}
# {
#   "player_regiments": Array[RegimentData],
#   "enemy_regiments": Array[RegimentData],
#   "terrain_type": String,
#   "is_contract": bool,
#   "contract_data": Resource (optional),
#   "core_regiments": Array (from pre-battle),
#   "reinforcement_regiments": Array (from pre-battle),
# }

# Result from completed battle
var battle_result: Dictionary = {}

# Scene paths
var campaign_scene_path: String = "res://campaign_system/scenes/campaign_map.tscn"
var default_battle_scene: String = "res://scenes/battle_scene.tscn"

# Track if we came from campaign
var from_campaign: bool = false

# Pre-battle screen instance (created when needed)
var pre_battle_screen: Control = null

# Current battalion for pre-battle
var pending_battalion = null
var pending_enemy_data: Dictionary = {}
var pending_contract = null
var pending_friendly_territory: bool = false


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


func start_battle_with_pre_battle(player_battalion, enemy_data: Dictionary, contract = null, friendly_territory: bool = false) -> void:
	# Show pre-battle screen before transitioning to battle
	from_campaign = true

	pending_battalion = player_battalion
	pending_enemy_data = enemy_data
	pending_contract = contract
	pending_friendly_territory = friendly_territory

	_show_pre_battle_screen()


func _show_pre_battle_screen() -> void:
	# Create pre-battle screen if needed
	if not pre_battle_screen:
		var script := load("res://campaign_system/ui/pre_battle_screen.gd")
		if script:
			pre_battle_screen = Control.new()
			pre_battle_screen.set_script(script)
			pre_battle_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

			# Connect signals (only if not already connected)
			if pre_battle_screen.has_signal("battle_started") and not pre_battle_screen.battle_started.is_connected(_on_pre_battle_started):
				pre_battle_screen.battle_started.connect(_on_pre_battle_started)
			if pre_battle_screen.has_signal("battle_cancelled") and not pre_battle_screen.battle_cancelled.is_connected(_on_pre_battle_cancelled):
				pre_battle_screen.battle_cancelled.connect(_on_pre_battle_cancelled)

	if pre_battle_screen:
		# Add to scene tree if not already
		if not pre_battle_screen.get_parent():
			get_tree().root.add_child(pre_battle_screen)

		# Show the pre-battle screen
		pre_battle_screen.show_pre_battle(
			pending_battalion,
			pending_enemy_data,
			pending_contract,
			pending_friendly_territory
		)


func _on_pre_battle_started() -> void:
	# Player confirmed battle - set up battle data with deployment order
	var deployment := {}
	if pre_battle_screen and pre_battle_screen.has_method("get_deployment_order"):
		deployment = pre_battle_screen.get_deployment_order()

	battle_data = {
		"player_regiments": pending_battalion.regiments.duplicate(),
		"enemy_regiments": pending_enemy_data.get("regiments", []),
		"terrain_type": pending_enemy_data.get("terrain", "plains"),
		"is_contract": pending_contract != null,
		"contract_data": pending_contract,
		"battalion_id": pending_battalion.battalion_id,
		"core_regiments": deployment.get("core", pending_battalion.regiments),
		"reinforcement_regiments": deployment.get("reinforcements", []),
	}

	# Clean up pre-battle screen
	if pre_battle_screen and pre_battle_screen.get_parent():
		pre_battle_screen.get_parent().remove_child(pre_battle_screen)

	_transition_to_battle()


func _on_pre_battle_cancelled() -> void:
	# Player cancelled - return to campaign
	from_campaign = false
	pending_battalion = null
	pending_enemy_data.clear()
	pending_contract = null

	# Clean up pre-battle screen
	if pre_battle_screen and pre_battle_screen.get_parent():
		pre_battle_screen.get_parent().remove_child(pre_battle_screen)


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
	var terrain_type: String = battle_data.get("terrain_type", "plains")

	# Map terrain types to specific scenes if they exist
	var scene_map := {
		"city": "res://scenes/battle_maps/city_siege_01.tscn",
		"village": "res://scenes/battle_maps/village_01.tscn",
		"siege": "res://scenes/battle_maps/siege_large_01.tscn",
		"swamp": "res://scenes/battle_maps/swamp_hills_01.tscn",
		"coastal": "res://scenes/battle_maps/coastal_01.tscn",
		"mountains": "res://scenes/battle_maps/mountain_pass_01.tscn",
	}

	if terrain_type in scene_map:
		var scene_path: String = scene_map[terrain_type]
		if ResourceLoader.exists(scene_path):
			battle_scene = scene_path
		else:
			push_warning("Battle scene not found: %s, using default" % scene_path)

	# Verify the scene exists before transitioning
	if not ResourceLoader.exists(battle_scene):
		push_error("Default battle scene not found: %s" % battle_scene)
		from_campaign = false
		battle_data.clear()
		return

	var err := get_tree().change_scene_to_file(battle_scene)
	if err != OK:
		push_error("Failed to change to battle scene: %s (error %d)" % [battle_scene, err])
		from_campaign = false
		battle_data.clear()


func return_to_campaign(result: Dictionary) -> void:
	if not from_campaign:
		return

	battle_result = result
	from_campaign = false

	# Emit signal before scene change (safely check for autoload)
	var campaign_signals = get_node_or_null("/root/CampaignSignals")
	if campaign_signals:
		campaign_signals.battle_returning.emit(result)

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
