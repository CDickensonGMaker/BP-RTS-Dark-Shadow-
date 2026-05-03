# Persistent battalion state for campaign map.
# Tracks position, movement, and regiment roster.
class_name BattalionData
extends Resource


@export var battalion_id: String = ""
@export var battalion_name: String = "Unnamed Battalion"

# Position on campaign map
@export var map_position: Vector2 = Vector2.ZERO

# Movement
@export var movement_points: float = 100.0
@export var max_movement_points: float = 100.0
@export var queued_path: Array = []  # Waypoints to final destination

# Regiments in this battalion (max 6 per the plan)
@export var regiments: Array = []  # Array of RegimentData

# Visual
@export var banner_texture: Texture2D
@export var battalion_color: Color = Color.BLUE


func get_total_soldiers() -> int:
	var total := 0
	for regiment in regiments:
		total += regiment.current_soldiers
	return total


func get_total_upkeep() -> int:
	var total := 0
	for regiment in regiments:
		# Use meta or default value
		var upkeep: int = regiment.get_meta("upkeep_cost", 10)
		total += upkeep
	return total


func can_move(distance: float) -> bool:
	return movement_points >= distance


func spend_movement(amount: float) -> void:
	movement_points = maxf(0.0, movement_points - amount)


func refresh_movement() -> void:
	movement_points = max_movement_points


func apply_battle_casualties(casualty_report: Dictionary) -> void:
	for regiment in regiments:
		if casualty_report.has(regiment.regiment_name):
			var report = casualty_report[regiment.regiment_name]
			regiment.current_soldiers = report.survived


# Path queue methods for multi-turn movement
func has_queued_path() -> bool:
	return queued_path.size() > 0


func clear_queued_path() -> void:
	queued_path.clear()


func set_queued_path(path: Array) -> void:
	queued_path = path.duplicate()


func get_next_waypoint() -> Vector2:
	if queued_path.size() > 0:
		return queued_path[0]
	return Vector2.ZERO


func consume_waypoint() -> void:
	if queued_path.size() > 0:
		queued_path.remove_at(0)
