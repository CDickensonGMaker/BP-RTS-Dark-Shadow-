extends Node


var battle_start_time: float = 0.0
var is_battle_active: bool = false

# Reference to CombatManager for signal connections
var combat_manager: Node = null

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


func start_battle():
	is_battle_active = true
	battle_start_time = Time.get_unix_time_from_system()

	# Initialize battle stats tracking
	battle_stats = BattleStats.new()
	_connect_stat_signals()

	BattleSignals.battle_started.emit()
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


## Handle damage_dealt signal from CombatManager
func _on_damage_dealt(target: Regiment, amount: int, source: Regiment, _damage_type: String) -> void:
	if not battle_stats or not is_battle_active:
		return
	var source_name: String = source.data.regiment_name if source and source.data else "Unknown"
	var target_name: String = target.data.regiment_name if target and target.data else "Unknown"
	battle_stats.record_damage(source_name, amount)
	battle_stats.record_casualties(target_name, amount)


## Handle regiment_attacked signal (backup if damage_dealt not available)
func _on_regiment_attacked(attacker: Regiment, defender: Regiment, damage: int) -> void:
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
	pass


func _check_battle_end():
	var player_alive = get_tree().get_nodes_in_group("player_regiments").filter(
		func(r): return r.state != Regiment.State.DEAD and r.state != Regiment.State.ROUTING
	)
	var enemy_alive = get_tree().get_nodes_in_group("enemy_regiments").filter(
		func(r): return r.state != Regiment.State.DEAD and r.state != Regiment.State.ROUTING
	)
	if player_alive.is_empty():
		_end_battle("enemy")
	elif enemy_alive.is_empty():
		_end_battle("player")


func _end_battle(winner: String):
	is_battle_active = false
	var duration = Time.get_unix_time_from_system() - battle_start_time

	# Finalize battle stats
	if battle_stats:
		battle_stats.duration = duration
		battle_stats.winner = winner
		battle_stats.print_summary()
		_export_battle_stats_to_json()

	# Disconnect stat signals
	_disconnect_stat_signals()

	var result = {
		"winner": winner,
		"duration": duration,
		"casualties": _gather_casualty_report(),
		"stats": battle_stats.to_dict() if battle_stats else {}
	}
	BattleSignals.battle_ended.emit(result)

	# Return to campaign if this was a campaign battle
	if BattleTransition and BattleTransition.is_campaign_battle():
		# Small delay so player can see the result
		await get_tree().create_timer(2.0).timeout
		BattleTransition.return_to_campaign(result)


func _gather_casualty_report() -> Dictionary:
	var report = {
		"player_unit_stats": {},
		"enemy_unit_stats": {}
	}

	# Gather player regiment stats
	for regiment in get_tree().get_nodes_in_group("player_regiments"):
		if regiment and regiment.data:
			var unit_name: String = regiment.data.regiment_name
			var starting: int = regiment.data.max_soldiers
			var survived: int = regiment.current_soldiers
			var losses: int = starting - survived
			var kills: int = battle_stats.damage_dealt.get(unit_name, 0) if battle_stats else 0

			report["player_unit_stats"][unit_name] = {
				"display_name": unit_name,
				"starting": starting,
				"losses": losses,
				"kills": kills
			}

	# Gather enemy regiment stats
	for regiment in get_tree().get_nodes_in_group("enemy_regiments"):
		if regiment and regiment.data:
			var unit_name: String = regiment.data.regiment_name
			var starting: int = regiment.data.max_soldiers
			var survived: int = regiment.current_soldiers
			var losses: int = starting - survived
			var kills: int = battle_stats.damage_dealt.get(unit_name, 0) if battle_stats else 0

			report["enemy_unit_stats"][unit_name] = {
				"display_name": unit_name,
				"starting": starting,
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
		print("BattleManager: Stats exported to %s" % filepath)
	else:
		push_warning("BattleManager: Failed to export stats to %s" % filepath)
