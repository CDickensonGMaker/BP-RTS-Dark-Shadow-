# Bridge between campaign map and battle scenes.
# Handles scene switching and data passing.
# Now supports pre-battle screen routing.
# Weather is inherited from campaign via WeatherScheduler.
extends Node

# Import weather table for weather name lookup
const ClimateWeatherTableScript = preload("res://campaign_system/data/climate_weather_table.gd")
# Import BattleObjective for objective types
const BattleObjectiveClass = preload("res://battle_system/ai/data/battle_objective.gd")

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
#   "weather": int (WeatherType enum value),
#   "weather_name": String (for display),
#   "region_id": String (for weather lookup),
#   "player_objective_type": int (BattleObjectiveClass.Type, optional - default ANNIHILATE),
#   "enemy_objective_type": int (BattleObjectiveClass.Type, optional - default HOLD_GROUND),
#   "battle_time_limit_sec": float (optional - for BREAKTHROUGH attackers),
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


func start_battle_from_campaign(player_battalion, enemy_regiments: Array, terrain: String = "plains", region_id: String = "") -> void:
	from_campaign = true

	# Get weather from campaign scheduler
	var weather_data := _get_weather_for_battle(region_id)

	battle_data = {
		"player_regiments": player_battalion.regiments.duplicate(),
		"enemy_regiments": enemy_regiments,
		"terrain_type": terrain,
		"is_contract": false,
		"battalion_id": player_battalion.battalion_id,
		"region_id": region_id,
		"weather": weather_data.weather,
		"weather_name": weather_data.name,
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

	# Get weather from campaign scheduler
	var region_id: String = pending_enemy_data.get("region_id", "")
	var weather_data := _get_weather_for_battle(region_id)

	battle_data = {
		"player_regiments": pending_battalion.regiments.duplicate(),
		"enemy_regiments": pending_enemy_data.get("regiments", []),
		"terrain_type": pending_enemy_data.get("terrain", "plains"),
		"is_contract": pending_contract != null,
		"contract_data": pending_contract,
		"battalion_id": pending_battalion.battalion_id,
		"core_regiments": deployment.get("core", pending_battalion.regiments),
		"reinforcement_regiments": deployment.get("reinforcements", []),
		"region_id": region_id,
		"weather": weather_data.weather,
		"weather_name": weather_data.name,
	}

	# Set objectives based on territorial context.
	# pending_friendly_territory means the battle is happening on the player's
	# home turf — they're the defender, the enemy is breaking through.
	if pending_friendly_territory:
		battle_data["player_objective_type"] = BattleObjectiveClass.Type.HOLD_GROUND
		battle_data["enemy_objective_type"] = BattleObjectiveClass.Type.BREAKTHROUGH
		battle_data["battle_time_limit_sec"] = 600.0  # 10-min attacker timer
	else:
		# Player is the attacker (raiding, contract, marching out)
		battle_data["player_objective_type"] = BattleObjectiveClass.Type.BREAKTHROUGH
		battle_data["enemy_objective_type"] = BattleObjectiveClass.Type.HOLD_GROUND
		battle_data["battle_time_limit_sec"] = 600.0

	# Clean up pre-battle screen
	if pre_battle_screen and pre_battle_screen.get_parent():
		pre_battle_screen.get_parent().remove_child(pre_battle_screen)

	_transition_to_battle()

	# Clear pending state to avoid stale data (Bug 7 fix)
	pending_battalion = null
	pending_enemy_data.clear()
	pending_contract = null
	pending_friendly_territory = false


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

	# Get region from contract or battalion location
	var region_id: String = ""
	if "region_id" in contract:
		region_id = contract.region_id

	# Get weather from campaign scheduler
	var weather_data := _get_weather_for_battle(region_id)

	battle_data = {
		"player_regiments": player_battalion.regiments.duplicate(),
		"enemy_regiments": enemy_regiments,
		"terrain_type": terrain,
		"is_contract": true,
		"contract_data": contract,
		"battalion_id": player_battalion.battalion_id,
		"region_id": region_id,
		"weather": weather_data.weather,
		"weather_name": weather_data.name,
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

	# Set up BattleModifiers with general profiles before battle starts
	_setup_battle_modifiers()

	var err := get_tree().change_scene_to_file(battle_scene)
	if err != OK:
		push_error("Failed to change to battle scene: %s (error %d)" % [battle_scene, err])
		from_campaign = false
		battle_data.clear()


## Set up BattleModifiers autoload with general profiles for this battle.
func _setup_battle_modifiers() -> void:
	var battle_mods = get_node_or_null("/root/BattleModifiers")
	if not battle_mods:
		return

	# Get player's general profile from CampaignManager
	var player_profile = null  # GeneralProfile - dynamic to avoid load order issues
	if CampaignManager and CampaignManager.player_general_profile:
		player_profile = CampaignManager.player_general_profile

	# Enemy general profile - check contract data first, then generate if needed
	var enemy_profile = null  # GeneralProfile - dynamic to avoid load order issues
	var contract = battle_data.get("contract_data", null)

	if contract and "enemy_general" in contract and contract.enemy_general:
		# Use contract's specified enemy general
		enemy_profile = contract.enemy_general
		print("[BattleTransition] Using contract enemy general: %s" % enemy_profile.general_name)
	elif battle_data.get("generate_enemy_general", true):
		# Generate a random enemy general for this battle
		enemy_profile = _generate_enemy_general()

	battle_mods.setup_battle(player_profile, enemy_profile)
	print("[BattleTransition] BattleModifiers set up - Player: %s, Enemy: %s" % [
		player_profile.general_name if player_profile else "None",
		enemy_profile.general_name if enemy_profile else "None"
	])


## Generate a random enemy general profile for battles.
## Scales difficulty based on player's progress.
func _generate_enemy_general():
	if not CampaignManager or not CampaignManager.trait_manager:
		return null

	# Create enemy general with random traits
	var enemy_names: Array[String] = [
		"Warlord Grimjaw", "Commander Blackwood", "Captain Ironfist",
		"Marshal Duskbane", "General Stormhelm", "Lord Ashcroft",
		"Chief Bloodaxe", "Warmaster Draven", "Baron Nightfall"
	]
	var enemy_name: String = enemy_names[randi() % enemy_names.size()]

	var enemy_profile = CampaignManager.trait_manager.create_general(enemy_name)

	# Scale enemy rank based on player's progress
	if CampaignManager.player_general_profile:
		var player_battles: int = CampaignManager.player_general_profile.battles_fought
		var player_kills: int = CampaignManager.player_general_profile.total_kills
		var player_victories: int = CampaignManager.player_general_profile.victories

		# Enemy gets similar progression (slightly behind player)
		enemy_profile.battles_fought = maxi(0, player_battles - randi() % 3)
		enemy_profile.victories = maxi(0, player_victories - randi() % 2)
		enemy_profile.total_kills = maxi(0, player_kills - randi() % 20)

		# Update rank based on fake progression
		enemy_profile._update_commander_rank()

	print("[BattleTransition] Generated enemy general: %s (Rank: %s)" % [
		enemy_profile.general_name, enemy_profile.get_rank_name()
	])

	return enemy_profile


func return_to_campaign(result: Dictionary) -> void:
	battle_result = result

	# Clear BattleModifiers when battle ends
	_clear_battle_modifiers()

	# Record battle results on the general profile
	_record_general_battle_results(result)

	# Check if this was a quick battle - return to main menu instead
	if battle_data.get("is_quick_battle", false):
		from_campaign = false
		battle_data.clear()
		get_tree().change_scene_to_file("res://ui/main_menu/main_menu.tscn")
		return

	if not from_campaign:
		# Not from campaign and not quick battle - just clear and return to main menu
		battle_data.clear()
		get_tree().change_scene_to_file("res://ui/main_menu/main_menu.tscn")
		return

	from_campaign = false

	# Emit signal before scene change (safely check for autoload)
	var campaign_signals = get_node_or_null("/root/CampaignSignals")
	if campaign_signals:
		campaign_signals.battle_returning.emit(result)

	# Clear battle data
	battle_data.clear()

	# Return to campaign map
	get_tree().change_scene_to_file(campaign_scene_path)


## Clear BattleModifiers when battle ends.
func _clear_battle_modifiers() -> void:
	var battle_mods = get_node_or_null("/root/BattleModifiers")
	if battle_mods:
		battle_mods.clear_battle()


## Record battle results on the player's general profile.
func _record_general_battle_results(result: Dictionary) -> void:
	if not CampaignManager:
		return

	var won: bool = result.get("winner", "") == "player"
	var kills: int = result.get("enemy_casualties", 0)

	CampaignManager.record_general_battle(won, kills)


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


## Get weather for a battle, using WeatherScheduler if available.
## Returns { weather: int, name: String }
func _get_weather_for_battle(region_id: String) -> Dictionary:
	var weather: int = 0  # CLEAR default
	var weather_name: String = "Clear"

	# Try to get weather from WeatherScheduler
	var scheduler = get_node_or_null("/root/WeatherScheduler")
	if scheduler and region_id != "":
		weather = scheduler.get_weather_for_region(region_id)
		weather_name = ClimateWeatherTableScript.get_weather_name(weather)
		print("[BattleTransition] Weather for region '%s': %s" % [region_id, weather_name])
	elif region_id == "":
		# No region specified - use random weather based on current season
		var season: int = 0
		if CampaignCalendar:
			season = CampaignCalendar.get_season()
		# Default to TEMPERATE climate for random battles
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		weather = ClimateWeatherTableScript.roll_weather(rng, 0, season)
		weather_name = ClimateWeatherTableScript.get_weather_name(weather)
		print("[BattleTransition] Random weather (no region): %s" % weather_name)

	return { "weather": weather, "name": weather_name }
