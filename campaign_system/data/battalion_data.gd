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

# Regiments in this battalion
@export var regiments: Array = []  # Array of RegimentData
@export var max_regiments: int = 6  # Upgradeable to 10

# Supply wagons (max 2 per army stack)
@export var supply_wagons: int = 0
const MAX_SUPPLY_WAGONS: int = 2

# Supply status (DEI/Napoleon style)
@export var supply_status: float = 100.0  # 0-100%
@export var in_friendly_territory: bool = true
@export var replenishment_cooldown: int = 0  # Turns since last battle

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


# =============================================================================
# Supply System (DEI/Napoleon style)
# =============================================================================

const SUPPLY_INFANTRY := 1.0
const SUPPLY_CAVALRY := 2.0
const SUPPLY_MONSTER := 4.0

func get_supply_consumption() -> float:
	var total := 0.0
	for regiment in regiments:
		# Check unit category for supply cost multiplier
		var multiplier := SUPPLY_INFANTRY
		if regiment.has_meta("supply_cost"):
			multiplier = regiment.get_meta("supply_cost")
		elif _is_cavalry_type(regiment):
			multiplier = SUPPLY_CAVALRY
		elif regiment.has_meta("unit_category") and regiment.get_meta("unit_category") == "monster":
			multiplier = SUPPLY_MONSTER
		total += multiplier
	return total


func _is_cavalry_type(regiment: Resource) -> bool:
	# Check meta first, then unit_type enum
	if regiment.has_meta("unit_category"):
		return regiment.get_meta("unit_category") == "cavalry"
	# UnitType.Type.CAVALRY = 2 in the enum
	if "unit_type" in regiment:
		return regiment.unit_type == UnitType.Type.CAVALRY
	return false


func apply_replenishment(rate: float) -> void:
	# Napoleon TW style - free replenishment based on location
	for regiment in regiments:
		if regiment.current_soldiers >= regiment.max_soldiers:
			continue

		var max_replenish := int(regiment.max_soldiers * rate)
		var actual := mini(max_replenish, regiment.max_soldiers - regiment.current_soldiers)

		if actual > 0:
			regiment.current_soldiers += actual

			# Experience loss for replenished units (Napoleon TW)
			# Fresh recruits replacing veterans
			var replenish_ratio: float = float(actual) / float(regiment.max_soldiers)
			if replenish_ratio > 0.3 and regiment.has_meta("veterancy_level"):
				var vet_level: int = regiment.get_meta("veterancy_level")
				if vet_level > 0:
					regiment.set_meta("veterancy_level", vet_level - 1)


func apply_attrition(damage_percent: float) -> int:
	# Apply attrition losses to all regiments
	var total_losses := 0
	for regiment in regiments:
		var losses := int(regiment.current_soldiers * damage_percent)
		losses = mini(losses, regiment.current_soldiers - 1)  # Keep at least 1
		regiment.current_soldiers -= losses
		total_losses += losses
	return total_losses


func can_add_regiment() -> bool:
	return regiments.size() < max_regiments


# =============================================================================
# Supply Wagon Management (Max 2 per army stack)
# =============================================================================

func can_add_supply_wagon() -> bool:
	return supply_wagons < MAX_SUPPLY_WAGONS


func add_supply_wagon() -> bool:
	if can_add_supply_wagon():
		supply_wagons += 1
		return true
	return false


func remove_supply_wagon() -> bool:
	if supply_wagons > 0:
		supply_wagons -= 1
		return true
	return false


func get_supply_wagon_count() -> int:
	return supply_wagons


func get_strength_summary() -> Dictionary:
	var infantry := 0
	var ranged := 0
	var cavalry := 0
	var special := 0

	for regiment in regiments:
		var category := _get_regiment_category(regiment)
		match category:
			"infantry":
				infantry += regiment.current_soldiers
			"ranged":
				ranged += regiment.current_soldiers
			"cavalry":
				cavalry += regiment.current_soldiers
			_:
				special += regiment.current_soldiers

	return {
		"total": get_total_soldiers(),
		"infantry": infantry,
		"ranged": ranged,
		"cavalry": cavalry,
		"special": special,
		"regiments": regiments.size()
	}


func _get_regiment_category(regiment: Resource) -> String:
	# Check meta first
	if regiment.has_meta("unit_category"):
		return regiment.get_meta("unit_category")
	# Fall back to unit_type enum
	if "unit_type" in regiment:
		match regiment.unit_type:
			UnitType.Type.INFANTRY:
				return "infantry"
			UnitType.Type.RANGED:
				return "ranged"
			UnitType.Type.CAVALRY:
				return "cavalry"
			_:
				return "special"
	return "infantry"
