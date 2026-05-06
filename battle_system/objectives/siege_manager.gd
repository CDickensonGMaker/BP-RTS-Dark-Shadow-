# Siege Manager - Handles capture point victory conditions
# Add to siege battle scenes to enable objective-based victory
class_name SiegeManager
extends Node


signal siege_won(winner: String)
signal capture_point_taken(point: CapturePoint, faction: String)

## Victory conditions
@export var require_all_points: bool = true  # Must capture ALL points
@export var hold_time: float = 0.0  # Seconds to hold after capture (0 = instant win)
@export var attacker_is_player: bool = true  # Player is attacking the settlement

var capture_points: Array[CapturePoint] = []
var hold_timer: float = 0.0
var holding_faction: String = ""
var victory_declared: bool = false


func _ready() -> void:
	# Find all capture points in scene
	await get_tree().process_frame
	_find_capture_points()

	# Connect to BattleManager
	if BattleSignals:
		BattleSignals.battle_started.connect(_on_battle_started)


func _find_capture_points() -> void:
	capture_points.clear()
	for point in get_tree().get_nodes_in_group("capture_points"):
		if point is CapturePoint:
			capture_points.append(point)
			point.point_captured.connect(_on_point_captured.bind(point))

	print("[SiegeManager] Found %d capture points" % capture_points.size())


func _process(delta: float) -> void:
	if victory_declared:
		return

	_check_victory_conditions(delta)


func _check_victory_conditions(delta: float) -> void:
	if capture_points.is_empty():
		return

	# Count captured points
	var player_points := 0
	var enemy_points := 0

	for point in capture_points:
		match point.get_owner_faction():
			"player":
				player_points += 1
			"enemy":
				enemy_points += 1

	# Check win condition
	var total := capture_points.size()
	var winning_faction := ""

	if require_all_points:
		if player_points == total:
			winning_faction = "player"
		elif enemy_points == total:
			winning_faction = "enemy"
	else:
		# Majority control
		if player_points > total / 2:
			winning_faction = "player"
		elif enemy_points > total / 2:
			winning_faction = "enemy"

	# Handle hold timer
	if winning_faction != "":
		if winning_faction == holding_faction:
			hold_timer += delta
			if hold_timer >= hold_time:
				_declare_victory(winning_faction)
		else:
			holding_faction = winning_faction
			hold_timer = 0.0
	else:
		holding_faction = ""
		hold_timer = 0.0


func _declare_victory(winner: String) -> void:
	if victory_declared:
		return

	victory_declared = true
	print("[SiegeManager] Siege victory: %s" % winner)
	siege_won.emit(winner)

	# End battle through BattleManager
	if BattleManager:
		# Create result dict
		var result := {
			"winner": winner,
			"is_siege": true,
			"points_captured": _count_faction_points(winner),
			"total_points": capture_points.size(),
		}
		BattleSignals.battle_ended.emit(result)


func _count_faction_points(faction: String) -> int:
	var count := 0
	for point in capture_points:
		if point.get_owner_faction() == faction:
			count += 1
	return count


func _on_point_captured(faction: String, point: CapturePoint) -> void:
	capture_point_taken.emit(point, faction)
	print("[SiegeManager] %s captured by %s" % [point.point_name, faction])


func _on_battle_started() -> void:
	victory_declared = false
	hold_timer = 0.0
	holding_faction = ""


## Get current siege status for UI
func get_status() -> Dictionary:
	var player_points := 0
	var enemy_points := 0
	var neutral_points := 0

	for point in capture_points:
		match point.get_owner_faction():
			"player":
				player_points += 1
			"enemy":
				enemy_points += 1
			_:
				neutral_points += 1

	return {
		"player_points": player_points,
		"enemy_points": enemy_points,
		"neutral_points": neutral_points,
		"total_points": capture_points.size(),
		"holding_faction": holding_faction,
		"hold_progress": hold_timer / maxf(hold_time, 0.01) if hold_time > 0 else 1.0,
	}
