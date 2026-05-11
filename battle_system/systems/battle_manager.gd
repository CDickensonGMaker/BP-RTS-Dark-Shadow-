extends Node

# Preload BattleObjective to ensure class is available
const BattleObjectiveClass = preload("res://battle_system/ai/data/battle_objective.gd")

var battle_start_time: float = 0.0
var is_battle_active: bool = false

# Reference to CombatManager for signal connections
var combat_manager: Node = null

# Reference to enemy GeneralAI instance
var _enemy_general_ai = null

# Combat tracking for battle end logic (prevents premature victory)
var _any_combat_started: bool = false  # True once any melee/combat occurs
var _victory_pending_timer: float = 0.0  # Timer for delayed victory check
const VICTORY_DELAY: float = 2.0  # Require 2 seconds of one side eliminated

# Player's rally ability (requires a general unit)
var player_rally: RallyAbility = null
var _player_general: Node = null

## BattleStats - Tracks combat metrics for balance analysis
class BattleStats:
	## Per-regiment damage dealt
	var damage_dealt: Dictionary = {}  # regiment_name -> int
	## Per-regiment casualties taken
	var casualties: Dictionary = {}  # regiment_name -> int
	## Morale history per regiment: Array of {time: float, value: float}
	var morale_history: Dictionary = {}  # regiment_name -> Array
	## Flank attack counts per regiment (as attacker)
	var flank_attacks: Dictionary = {}  # regiment_name -> int
	## Rear attack counts per regiment (as attacker)
	var rear_attacks: Dictionary = {}  # regiment_name -> int
	## Times regiment was flanked
	var times_flanked: Dictionary = {}  # regiment_name -> int
	## Routing events
	var routing_events: Array = []  # Array of {regiment: String, time: float}
	## Combat duration in seconds
	var duration: float = 0.0
	## Winner faction
	var winner: String = ""

	func record_damage(attacker_name: String, amount: int) -> void:
		if not damage_dealt.has(attacker_name):
			damage_dealt[attacker_name] = 0
		damage_dealt[attacker_name] += amount

	func record_casualties(regiment_name: String, amount: int) -> void:
		if not casualties.has(regiment_name):
			casualties[regiment_name] = 0
		casualties[regiment_name] += amount

	func record_morale(regiment_name: String, time: float, value: float) -> void:
		if not morale_history.has(regiment_name):
			morale_history[regiment_name] = []
		morale_history[regiment_name].append({"time": time, "value": value})

	func record_flank(attacker_name: String, is_rear: bool) -> void:
		if is_rear:
			if not rear_attacks.has(attacker_name):
				rear_attacks[attacker_name] = 0
			rear_attacks[attacker_name] += 1
		else:
			if not flank_attacks.has(attacker_name):
				flank_attacks[attacker_name] = 0
			flank_attacks[attacker_name] += 1

	func record_was_flanked(regiment_name: String) -> void:
		if not times_flanked.has(regiment_name):
			times_flanked[regiment_name] = 0
		times_flanked[regiment_name] += 1

	func record_routing(regiment_name: String, time: float) -> void:
		routing_events.append({"regiment": regiment_name, "time": time})

	func to_dict() -> Dictionary:
		return {
			"duration": duration,
			"winner": winner,
			"damage_dealt": damage_dealt,
			"casualties": casualties,
			"morale_history": morale_history,
			"flank_attacks": flank_attacks,
			"rear_attacks": rear_attacks,
			"times_flanked": times_flanked,
			"routing_events": routing_events
		}

	func print_summary() -> void:
		if not DebugFlags.battle_setup:
			return
		print("\n========== BATTLE STATS SUMMARY ==========")
		print("Duration: %.1f seconds" % duration)
		print("Winner: %s" % winner)
		print("\n--- Damage Dealt ---")
		for regiment_name in damage_dealt:
			print("  %s: %d damage" % [regiment_name, damage_dealt[regiment_name]])
		print("\n--- Casualties Taken ---")
		for regiment_name in casualties:
			print("  %s: %d casualties" % [regiment_name, casualties[regiment_name]])
		print("\n--- Flank/Rear Attacks (as attacker) ---")
		for regiment_name in flank_attacks:
			print("  %s: %d flank attacks" % [regiment_name, flank_attacks[regiment_name]])
		for regiment_name in rear_attacks:
			print("  %s: %d rear attacks" % [regiment_name, rear_attacks[regiment_name]])
		print("\n--- Times Flanked ---")
		for regiment_name in times_flanked:
			print("  %s: flanked %d times" % [regiment_name, times_flanked[regiment_name]])
		print("\n--- Routing Events ---")
		for event in routing_events:
			print("  %s routed at %.1fs" % [event["regiment"], event["time"]])
		print("==========================================\n")

## Current battle stats instance
var battle_stats: BattleStats = null


func _ready() -> void:
	# Find CombatManager in the scene tree
	call_deferred("_find_combat_manager")


func _find_combat_manager() -> void:
	var managers = get_tree().get_nodes_in_group("combat_manager")
	if managers.size() > 0:
		combat_manager = managers[0]
	else:
		# Try finding by name in parent or siblings
		combat_manager = get_node_or_null("../CombatManager")
		if not combat_manager:
			combat_manager = get_node_or_null("/root/CombatManager")


func _setup_enemy_general() -> void:
	## Setup GeneralAI for enemy faction (faction 1).
	## Links all enemy regiments to the GeneralAI.

	# Get enemy regiments
	var enemy_regiments := get_tree().get_nodes_in_group("enemy_regiments")

	if enemy_regiments.is_empty():
		if DebugFlags.battle_setup:
			print("[AI] No enemy regiments found, skipping GeneralAI setup")
		return

	# Create GeneralAI for enemy faction (1)
	_enemy_general_ai = GeneralAI.new(1)  # faction 1 = enemy

	# Read objective from battle_data; default to defender for skirmish.
	var enemy_obj_type: int = BattleObjectiveClass.Type.HOLD_GROUND
	var time_limit: float = -1.0
	if BattleTransition and BattleTransition.battle_data.has("enemy_objective_type"):
		enemy_obj_type = BattleTransition.battle_data["enemy_objective_type"]
		time_limit = BattleTransition.battle_data.get("battle_time_limit_sec", -1.0)

	var enemy_obj := BattleObjectiveClass.new()
	enemy_obj.type = enemy_obj_type
	enemy_obj.time_limit_sec = time_limit
	enemy_obj.start_time_sec = Time.get_ticks_msec() / 1000.0

	# Set hold_position to enemy center of mass at battle start
	if not enemy_regiments.is_empty():
		var center := Vector3.ZERO
		var valid_count: int = 0
		for r in enemy_regiments:
			if is_instance_valid(r):
				center += r.global_position
				valid_count += 1
		if valid_count > 0:
			center /= float(valid_count)
			enemy_obj.hold_position = center
			enemy_obj.hold_position.y = 0.0

	_enemy_general_ai.objective = enemy_obj

	if DebugFlags and DebugFlags.battle_setup:
		print("[AI] Enemy objective: %s (time_limit=%.0fs, hold=%s)" % [
			BattleObjectiveClass.Type.keys()[enemy_obj_type],
			time_limit,
			str(enemy_obj.hold_position)
		])

	# Register with AIAutoload
	AIAutoload.register_general_ai(_enemy_general_ai, 1)

	# Link all enemy regiments to the GeneralAI
	var linked_count: int = 0
	var no_ai_count: int = 0
	for regiment in enemy_regiments:
		# Regiment uses ai_controller property (not commander_ai)
		if regiment and "ai_controller" in regiment and regiment.ai_controller:
			_enemy_general_ai.register_commander(regiment, regiment.ai_controller)
			linked_count += 1
		else:
			no_ai_count += 1

	if DebugFlags.battle_setup:
		print("[AI] Enemy GeneralAI activated: %d/%d regiments linked" % [linked_count, enemy_regiments.size()])
		if no_ai_count > 0:
			print("[AI] Warning: %d regiments missing ai_controller" % no_ai_count)

	# Force immediate AI tick to start acting right away
	if linked_count > 0:
		_enemy_general_ai.tick()


func _setup_player_rally() -> void:
	## Setup Rally ability for player's general (if one exists).
	## Looks for a player-controlled regiment with has_aura (typically a general/hero).

	var player_regiments := get_tree().get_nodes_in_group("player_regiments")

	for regiment in player_regiments:
		if not is_instance_valid(regiment):
			continue
		if not regiment.data:
			continue

		# Find a general/hero (has_aura indicates a leadership unit)
		if regiment.data.has_aura:
			_player_general = regiment
			player_rally = RallyAbility.new(regiment)
			if DebugFlags.battle_setup:
				print("[RALLY] Player rally initialized: %s" % regiment.name)

			# Connect to general death signal
			if regiment.has_signal("state_changed"):
				regiment.state_changed.connect(_on_player_general_state_changed)
			return


func _on_player_general_state_changed(_old_state: int, new_state: int) -> void:
	## Handle player general death - disable rally.
	if new_state == Regiment.State.DEAD:
		if player_rally:
			player_rally.deactivate()


func start_battle():
	if DebugFlags.battle_setup:
		print("[BattleManager] ===== BATTLE STARTING =====")
	is_battle_active = true
	battle_start_time = Time.get_unix_time_from_system()

	# Initialize battle stats tracking
	battle_stats = BattleStats.new()
	_connect_stat_signals()

	# Apply weather from campaign (if coming from campaign)
	_apply_campaign_weather()

	# Set difficulty profile on CombatManager (BattleDebug agent calibration)
	_apply_difficulty_profile()

	# Setup enemy GeneralAI if strategic AI is enabled
	# Delay to allow regiments time to initialize their AI controllers (after terrain snap)
	if AIAutoload and AIAutoload.strategic_ai_enabled:
		get_tree().create_timer(1.0).timeout.connect(_setup_enemy_general)

	# Setup player rally ability (also delayed to wait for regiment init)
	get_tree().create_timer(1.0).timeout.connect(_setup_player_rally)

	BattleSignals.battle_started.emit()
	# Only connect if not already connected (prevents duplicate connections across battles)
	if not BattleSignals.regiment_dead.is_connected(_on_regiment_dead):
		BattleSignals.regiment_dead.connect(_on_regiment_dead)


func _on_regiment_dead(_regiment: Regiment):
	_check_battle_end()


## Connect to combat signals for stats tracking
func _connect_stat_signals() -> void:
	# Connect to CombatManager.damage_dealt if available
	if combat_manager and combat_manager.has_signal("damage_dealt"):
		if not combat_manager.damage_dealt.is_connected(_on_damage_dealt):
			combat_manager.damage_dealt.connect(_on_damage_dealt)

	# Connect to BattleSignals
	if not BattleSignals.regiment_attacked.is_connected(_on_regiment_attacked):
		BattleSignals.regiment_attacked.connect(_on_regiment_attacked)
	if not BattleSignals.unit_flanked.is_connected(_on_unit_flanked):
		BattleSignals.unit_flanked.connect(_on_unit_flanked)
	if not BattleSignals.regiment_routing.is_connected(_on_regiment_routing):
		BattleSignals.regiment_routing.connect(_on_regiment_routing)
	if not BattleSignals.morale_changed.is_connected(_on_morale_changed):
		BattleSignals.morale_changed.connect(_on_morale_changed)


## Disconnect stat signals to prevent duplicates
func _disconnect_stat_signals() -> void:
	if combat_manager and combat_manager.has_signal("damage_dealt"):
		if combat_manager.damage_dealt.is_connected(_on_damage_dealt):
			combat_manager.damage_dealt.disconnect(_on_damage_dealt)
	if BattleSignals.regiment_attacked.is_connected(_on_regiment_attacked):
		BattleSignals.regiment_attacked.disconnect(_on_regiment_attacked)
	if BattleSignals.unit_flanked.is_connected(_on_unit_flanked):
		BattleSignals.unit_flanked.disconnect(_on_unit_flanked)
	if BattleSignals.regiment_routing.is_connected(_on_regiment_routing):
		BattleSignals.regiment_routing.disconnect(_on_regiment_routing)
	if BattleSignals.morale_changed.is_connected(_on_morale_changed):
		BattleSignals.morale_changed.disconnect(_on_morale_changed)
	# Also disconnect regiment_dead to prevent duplicate connections
	if BattleSignals.regiment_dead.is_connected(_on_regiment_dead):
		BattleSignals.regiment_dead.disconnect(_on_regiment_dead)


## Handle damage_dealt signal from CombatManager
func _on_damage_dealt(target: Regiment, amount: int, source: Regiment, _damage_type: String) -> void:
	if not battle_stats or not is_battle_active:
		return
	var source_name: String = source.data.regiment_name if source and source.data else "Unknown"
	var target_name: String = target.data.regiment_name if target and target.data else "Unknown"
	battle_stats.record_damage(source_name, amount)
	battle_stats.record_casualties(target_name, amount)


## Handle regiment_attacked signal (backup if damage_dealt not available)
func _on_regiment_attacked(_attacker: Regiment, _defender: Regiment, _damage: int) -> void:
	# Only use this if we didn't get the damage_dealt signal
	if not battle_stats or not is_battle_active:
		return
	# This signal is for logging purposes - damage_dealt handles actual tracking
	pass


## Handle unit_flanked signal
func _on_unit_flanked(flanked: Regiment, flanker: Regiment, is_rear: bool) -> void:
	if not battle_stats or not is_battle_active:
		return
	var flanker_name: String = flanker.data.regiment_name if flanker and flanker.data else "Unknown"
	var flanked_name: String = flanked.data.regiment_name if flanked and flanked.data else "Unknown"
	battle_stats.record_flank(flanker_name, is_rear)
	battle_stats.record_was_flanked(flanked_name)


## Handle regiment_routing signal
func _on_regiment_routing(regiment: Regiment) -> void:
	if not battle_stats or not is_battle_active:
		return
	var regiment_name: String = regiment.data.regiment_name if regiment and regiment.data else "Unknown"
	var elapsed: float = Time.get_unix_time_from_system() - battle_start_time
	battle_stats.record_routing(regiment_name, elapsed)


## Handle morale_changed signal
func _on_morale_changed(regiment: Regiment, new_value: float, _delta: float) -> void:
	if not battle_stats or not is_battle_active:
		return
	var regiment_name: String = regiment.data.regiment_name if regiment and regiment.data else "Unknown"
	var elapsed: float = Time.get_unix_time_from_system() - battle_start_time
	battle_stats.record_morale(regiment_name, elapsed, new_value)


func _process(delta):
	# Handle battle speed via Engine.time_scale
	# This is managed separately via input

	# Tick player rally ability cooldown
	if player_rally:
		player_rally.tick(delta)

	# Track combat started via CombatManager active melees (more reliable than signal)
	if not _any_combat_started and is_battle_active:
		if combat_manager and "active_melees" in combat_manager:
			if combat_manager.active_melees.size() > 0:
				_any_combat_started = true
				if DebugFlags.battle_setup:
					print("[BattleManager] Combat started - melee engagement detected")


func _check_battle_end():
	# Phase 2A: Don't end battle before any fighting has occurred
	if not _any_combat_started:
		if DebugFlags.battle_setup:
			print("[BattleManager] Battle end check skipped - no combat started yet")
		return

	var player_alive = get_tree().get_nodes_in_group("player_regiments").filter(
		func(r): return r.state != Regiment.State.DEAD and r.state != Regiment.State.ROUTING
	)
	var enemy_alive = get_tree().get_nodes_in_group("enemy_regiments").filter(
		func(r): return r.state != Regiment.State.DEAD and r.state != Regiment.State.ROUTING
	)

	# Phase 2B: Victory delay - require sustained 0 units for VICTORY_DELAY seconds
	# This prevents instant victory from single deaths and allows rally/reinforcement
	var pending_winner: String = ""
	if player_alive.is_empty():
		pending_winner = "enemy"
	elif enemy_alive.is_empty():
		pending_winner = "player"

	if pending_winner != "":
		_victory_pending_timer += get_process_delta_time()
		if DebugFlags.battle_setup and int(_victory_pending_timer * 10) % 10 == 0:
			print("[BattleManager] Victory pending for %s... (%.1fs / %.1fs)" % [
				pending_winner, _victory_pending_timer, VICTORY_DELAY
			])
		if _victory_pending_timer >= VICTORY_DELAY:
			_end_battle(pending_winner)
	else:
		# Reset timer if units respawn/rally/rejoin
		if _victory_pending_timer > 0.0:
			if DebugFlags.battle_setup:
				print("[BattleManager] Victory pending reset - units still fighting")
		_victory_pending_timer = 0.0


func _end_battle(winner: String):
	is_battle_active = false
	var duration = Time.get_unix_time_from_system() - battle_start_time

	# Reset combat tracking flags
	_any_combat_started = false
	_victory_pending_timer = 0.0

	# Finalize battle stats
	if battle_stats:
		battle_stats.duration = duration
		battle_stats.winner = winner
		battle_stats.print_summary()
		_export_battle_stats_to_json()

	# Cleanup enemy GeneralAI
	if _enemy_general_ai:
		_enemy_general_ai.destroy()
		_enemy_general_ai = null

	# Persist morale caps to RegimentData for surviving player regiments
	# This allows campaign to track battle fatigue across multiple engagements
	_persist_morale_caps()

	# Disconnect stat signals
	_disconnect_stat_signals()

	# Get contract and battalion info from BattleTransition for campaign integration
	var transition = get_node_or_null("/root/BattleTransition")
	var contract_ref = null
	var battalion_id := ""
	if transition and transition.has_battle_data():
		contract_ref = transition.battle_data.get("contract_data", null)
		battalion_id = transition.battle_data.get("battalion_id", "")

	var result = {
		"winner": winner,
		"duration": duration,
		"casualties": _gather_casualty_report(),
		"stats": battle_stats.to_dict() if battle_stats else {},
		"contract": contract_ref,       # Carry contract back to campaign
		"battalion_id": battalion_id,   # Identify which battalion fought
	}
	BattleSignals.battle_ended.emit(result)

	# Note: Return to campaign is now handled by BattleOverScreen's Continue button
	# This allows the player to view battle results before transitioning


func _persist_morale_caps() -> void:
	## Save morale caps to RegimentData for surviving player regiments.
	## This persists battle fatigue to campaign for multi-battle continuity.
	for regiment in get_tree().get_nodes_in_group("player_regiments"):
		if not regiment or not regiment.data:
			continue
		if regiment.state == Regiment.State.DEAD:
			continue
		if not regiment.unit_morale:
			continue

		var cap: float = regiment.unit_morale.get_morale_cap()
		regiment.data.set_meta("battle_morale_cap", cap)

		if DebugFlags and DebugFlags.battle_setup:
			print("[BattleManager] Persisted morale cap %.1f for %s" % [cap, regiment.name])


func _gather_casualty_report() -> Dictionary:
	var report = {
		"player_unit_stats": {},
		"enemy_unit_stats": {}
	}

	# Gather player regiment stats
	for regiment in get_tree().get_nodes_in_group("player_regiments"):
		if regiment and regiment.data:
			var unit_name: String = regiment.data.regiment_name
			# Use meta for starting count (set by battle_scene.gd from campaign data)
			var starting: int = regiment.get_meta("starting_soldiers", regiment.data.max_soldiers)
			var survived: int = regiment.current_soldiers
			var losses: int = starting - survived
			var kills: int = battle_stats.damage_dealt.get(unit_name, 0) if battle_stats else 0

			report["player_unit_stats"][unit_name] = {
				"display_name": unit_name,
				"starting": starting,
				"survived": survived,  # Campaign needs this to set current_soldiers
				"losses": losses,
				"kills": kills
			}

	# Gather enemy regiment stats
	for regiment in get_tree().get_nodes_in_group("enemy_regiments"):
		if regiment and regiment.data:
			var unit_name: String = regiment.data.regiment_name
			var starting: int = regiment.get_meta("starting_soldiers", regiment.data.max_soldiers)
			var survived: int = regiment.current_soldiers
			var losses: int = starting - survived
			var kills: int = battle_stats.damage_dealt.get(unit_name, 0) if battle_stats else 0

			report["enemy_unit_stats"][unit_name] = {
				"display_name": unit_name,
				"starting": starting,
				"survived": survived,
				"losses": losses,
				"kills": kills
			}

	return report


# Battle speed controls
func set_battle_speed(speed: float):
	Engine.time_scale = speed


func pause_battle():
	get_tree().paused = true


func resume_battle():
	get_tree().paused = false


func toggle_pause():
	get_tree().paused = not get_tree().paused


## Get current battle stats as Dictionary (for UI access)
func get_battle_stats() -> Dictionary:
	if battle_stats:
		return battle_stats.to_dict()
	return {}


## Export battle stats to JSON file in user://battle_logs/
func _export_battle_stats_to_json() -> void:
	if not battle_stats:
		return

	# Ensure battle_logs directory exists
	var dir := DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("battle_logs"):
			dir.make_dir("battle_logs")

	# Generate filename with timestamp
	var datetime := Time.get_datetime_dict_from_system()
	var filename := "battle_%04d%02d%02d_%02d%02d%02d.json" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"], datetime["second"]
	]
	var filepath := "user://battle_logs/" + filename

	# Write JSON file
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file:
		var json_string := JSON.stringify(battle_stats.to_dict(), "\t")
		file.store_string(json_string)
		file.close()
		if DebugFlags.battle_setup:
			print("BattleManager: Stats exported to %s" % filepath)
	else:
		push_warning("BattleManager: Failed to export stats to %s" % filepath)


## Apply weather from campaign to the battle.
## Reads weather from BattleTransition.battle_data and syncs to WeatherSystem/WeatherController.
func _apply_campaign_weather() -> void:
	var transition = get_node_or_null("/root/BattleTransition")
	if not transition or not transition.has_battle_data():
		return

	var weather: int = transition.battle_data.get("weather", -1)
	var weather_name: String = transition.battle_data.get("weather_name", "")
	var region_id: String = transition.battle_data.get("region_id", "")

	if weather < 0:
		# No weather specified - let WeatherController do its thing
		return

	if DebugFlags.battle_setup:
		print("[BattleManager] Campaign weather: %s (region: %s)" % [weather_name, region_id])

	# Apply to WeatherSystem (combat modifiers)
	if WeatherSystem:
		WeatherSystem.debug_set_weather(weather)

	# Apply to WeatherController (visual effects)
	var weather_controller = get_node_or_null("/root/WeatherController")
	if weather_controller:
		# Disable auto weather cycling during campaign battles
		if "auto_weather_enabled" in weather_controller:
			weather_controller.auto_weather_enabled = false

		# Map weather type to visual preset name
		var preset_name: String = _get_weather_preset_name(weather)
		if weather_controller.has_method("set_weather"):
			weather_controller.set_weather(preset_name, true)  # instant = true


## Map weather type int to WeatherController preset name.
func _get_weather_preset_name(weather_type: int) -> String:
	match weather_type:
		0:  # CLEAR
			return "clear"
		1:  # RAIN
			return "rain"
		2:  # FOG
			return "fog"
		3:  # STORM
			return "storm"
		4:  # SNOW
			return "snow"
		5:  # BLIZZARD
			return "blizzard"
	return "clear"


## Apply difficulty profile to CombatManager.
## Reads difficulty_level from BattleTransition.battle_data if available,
## otherwise defaults to NORMAL. This enables the BattleDebug agent's
## calibration system - without this call, difficulty multipliers stay at 1.0.
const DifficultyProfileScript = preload("res://battle_system/ai/data/difficulty_profile.gd")

func _apply_difficulty_profile() -> void:
	if not combat_manager:
		return

	# Default to NORMAL difficulty
	var profile = DifficultyProfileScript.normal()

	# Check if BattleTransition specifies a difficulty level
	var transition = get_node_or_null("/root/BattleTransition")
	if transition and transition.has_method("has_battle_data") and transition.has_battle_data():
		var level = transition.battle_data.get("difficulty_level", -1)
		if level >= 0:
			profile = DifficultyProfileScript.from_level(level)

	# Apply to CombatManager
	if combat_manager.has_method("set_difficulty_profile"):
		combat_manager.set_difficulty_profile(profile)

	if DebugFlags.battle_setup:
		print("[BattleManager] Difficulty profile set: %s" % profile.display_name)
