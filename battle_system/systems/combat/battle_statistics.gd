class_name BattleStatistics
extends RefCounted

## Tracks battle statistics: kills, losses, per-unit stats.
## Extracted from CombatManager for single responsibility.

var debug_combat: bool = false

# Statistics dictionary
var stats: Dictionary = {
	"player_kills": 0,
	"player_losses": 0,
	"enemy_kills": 0,
	"enemy_losses": 0,
	"player_unit_stats": {},  # unit_name -> {kills, losses, starting, display_name}
	"enemy_unit_stats": {},   # unit_name -> {kills, losses, starting, display_name}
	"battle_start_time": 0.0,
	"battle_ended": false
}

# Reference to scene tree for queries
var _scene_tree: SceneTree = null


func setup(scene_tree: SceneTree) -> void:
	_scene_tree = scene_tree
	_init_battle_stats()


## Initialize battle statistics at start
func _init_battle_stats() -> void:
	stats.battle_start_time = Time.get_ticks_msec() / 1000.0
	stats.battle_ended = false
	stats.player_kills = 0
	stats.player_losses = 0
	stats.enemy_kills = 0
	stats.enemy_losses = 0
	stats.player_unit_stats = {}
	stats.enemy_unit_stats = {}

	if not _scene_tree:
		return

	# Record starting strength of all regiments
	for regiment in _scene_tree.get_nodes_in_group("all_regiments"):
		if not is_instance_valid(regiment):
			continue
		var stats_dict: Dictionary = stats.player_unit_stats if regiment.is_player_controlled else stats.enemy_unit_stats
		stats_dict[regiment.name] = {
			"display_name": regiment.data.regiment_name if regiment.data else regiment.name,
			"starting": regiment.current_soldiers,
			"kills": 0,
			"losses": 0
		}

	if debug_combat:
		print("[COMBAT] Battle stats initialized - Player units: %d, Enemy units: %d" % [
			stats.player_unit_stats.size(),
			stats.enemy_unit_stats.size()
		])


## Track a kill for statistics
func track_kill(attacker: Node, defender: Node, casualties: int) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	# Track kills for attacker
	var attacker_stats: Dictionary = stats.player_unit_stats if attacker.is_player_controlled else stats.enemy_unit_stats
	if attacker.name in attacker_stats:
		attacker_stats[attacker.name].kills += casualties

	# Track losses for defender
	var defender_stats: Dictionary = stats.player_unit_stats if defender.is_player_controlled else stats.enemy_unit_stats
	if defender.name in defender_stats:
		defender_stats[defender.name].losses += casualties

	# Track global totals
	if attacker.is_player_controlled:
		stats.player_kills += casualties
	else:
		stats.enemy_kills += casualties

	if defender.is_player_controlled:
		stats.player_losses += casualties
	else:
		stats.enemy_losses += casualties

	if debug_combat:
		print("[COMBAT] %s killed %d from %s (Total: P:%d/%d E:%d/%d)" % [
			attacker.name, casualties, defender.name,
			stats.player_kills, stats.player_losses,
			stats.enemy_kills, stats.enemy_losses
		])


## Check if battle has ended and return result if so
func check_battle_end() -> Dictionary:
	if stats.battle_ended:
		return {}

	if not _scene_tree:
		return {}

	var player_alive := 0
	var enemy_alive := 0

	for regiment in _scene_tree.get_nodes_in_group("all_regiments"):
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD:
			continue
		if regiment.current_soldiers <= 0:
			continue
		if regiment.is_player_controlled:
			player_alive += 1
		else:
			enemy_alive += 1

	if player_alive == 0 or enemy_alive == 0:
		stats.battle_ended = true
		var start_time: float = stats.battle_start_time
		var duration: float = (Time.get_ticks_msec() / 1000.0) - start_time
		var winner: String = "PLAYER" if enemy_alive == 0 else "ENEMY"

		_print_battle_summary(winner, duration)

		# Return result dictionary
		return {
			"winner": winner,
			"player_victory": winner == "PLAYER",
			"casualties": {
				"player_kills": stats.player_kills,
				"player_losses": stats.player_losses,
				"enemy_kills": stats.enemy_kills,
				"enemy_losses": stats.enemy_losses,
				"player_unit_stats": stats.player_unit_stats,
				"enemy_unit_stats": stats.enemy_unit_stats
			},
			"duration": duration
		}

	return {}


func _print_battle_summary(winner: String, duration: float) -> void:
	var separator: String = "=".repeat(60)
	print("\n" + separator)
	print("[BATTLE OVER] %s VICTORY!" % winner)
	print(separator)
	print("Duration: %.1f seconds" % duration)
	print("\n--- PLAYER FORCES ---")
	print("Total Kills: %d | Total Losses: %d" % [stats.player_kills, stats.player_losses])
	for unit_name in stats.player_unit_stats:
		var s: Dictionary = stats.player_unit_stats[unit_name]
		var remaining: int = s.starting - s.losses
		print("  %s: %d/%d remaining (K:%d L:%d)" % [s.display_name, remaining, s.starting, s.kills, s.losses])

	print("\n--- ENEMY FORCES ---")
	print("Total Kills: %d | Total Losses: %d" % [stats.enemy_kills, stats.enemy_losses])
	for unit_name in stats.enemy_unit_stats:
		var s: Dictionary = stats.enemy_unit_stats[unit_name]
		var remaining: int = s.starting - s.losses
		print("  %s: %d/%d remaining (K:%d L:%d)" % [s.display_name, remaining, s.starting, s.kills, s.losses])
	print(separator + "\n")


func is_battle_ended() -> bool:
	return stats.battle_ended


func get_stats() -> Dictionary:
	return stats.duplicate(true)
