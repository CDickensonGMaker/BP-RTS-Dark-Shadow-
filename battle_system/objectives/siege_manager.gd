# Siege Manager - Handles capture point victory conditions
# Add to siege battle scenes to enable objective-based victory
class_name SiegeManager
extends Node


signal siege_won(winner: String)
signal capture_point_taken(point: CapturePoint, faction: String)
signal victory_points_changed(player_pts: float, enemy_pts: float, required: int)

## Victory conditions
@export var require_all_points: bool = true  # Must capture ALL points
@export var hold_time: float = 0.0  # Seconds to hold after capture (0 = instant win)
@export var attacker_is_player: bool = true  # Player is attacking the settlement

## Victory points system (alternative to require_all_points)
@export var use_victory_points: bool = false  # Enable weighted point system
@export var victory_points_required: int = 150
@export var points_per_second: float = 1.0  # Multiplier for points per second

var capture_points: Array[CapturePoint] = []
var hold_timer: float = 0.0
var holding_faction: String = ""
var victory_declared: bool = false

## Victory points tracking
var player_victory_points: float = 0.0
var enemy_victory_points: float = 0.0  # Kept for UI display, but not used for victory
var _battle_active: bool = false  # Prevent point accumulation before battle starts


func _ready() -> void:
	add_to_group("siege_managers")

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

	# Use victory points system if enabled
	if use_victory_points:
		_update_victory_points(delta)
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


func _update_victory_points(delta: float) -> void:
	# Don't accumulate points until battle starts
	if not _battle_active:
		return

	# Only the ATTACKER accumulates victory points
	# The defender wins by preventing the attacker from reaching the threshold
	# or by destroying all attacker units
	var attacker_faction: String = "player" if attacker_is_player else "enemy"

	for point in capture_points:
		if point.get_owner_faction() == attacker_faction:
			var value: float = float(point.get_point_value()) * points_per_second * delta
			if attacker_is_player:
				player_victory_points += value
			else:
				enemy_victory_points += value

	victory_points_changed.emit(player_victory_points, enemy_victory_points, victory_points_required)

	# Check for attacker victory (reached point threshold)
	var attacker_points: float = player_victory_points if attacker_is_player else enemy_victory_points
	if attacker_points >= victory_points_required:
		print("[SiegeManager] Attacker reached %d victory points!" % victory_points_required)
		_declare_victory(attacker_faction)


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
	player_victory_points = 0.0
	enemy_victory_points = 0.0
	_battle_active = true  # Now start accumulating victory points


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
		"player_victory_points": player_victory_points,
		"enemy_victory_points": enemy_victory_points,
		"victory_points_required": victory_points_required,
		"use_victory_points": use_victory_points,
	}
