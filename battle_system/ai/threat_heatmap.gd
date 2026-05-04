class_name ThreatHeatmap
extends RefCounted

## Grid-based threat assessment system (spring1944-inspired).
## Tracks firepower concentration across the battlefield for AI decisions.
## Enables smarter retreat, flanking, and positioning behavior.

# Grid parameters
var cell_size: float = 20.0  # Each cell is 20x20 world units
var cells: Dictionary = {}    # Vector2i -> {player: float, enemy: float}

# Faction indices
const PLAYER_FACTION: int = 0
const ENEMY_FACTION: int = 1

# Decay rate for threat values (per second)
const THREAT_DECAY_RATE: float = 0.1  # Threats decay 10% per second


func clear() -> void:
	## Clear all threat data.
	cells.clear()


func update_threat(position: Vector3, faction: int, firepower: float) -> void:
	## Add threat at a position. Called when units occupy/shoot from a location.
	var cell := _world_to_cell(position)
	if cell not in cells:
		cells[cell] = {"player": 0.0, "enemy": 0.0}

	var key := "player" if faction == PLAYER_FACTION else "enemy"
	cells[cell][key] += firepower


func set_unit_threat(position: Vector3, faction: int, firepower: float) -> void:
	## Set threat for a unit position (replaces rather than adds).
	var cell := _world_to_cell(position)
	if cell not in cells:
		cells[cell] = {"player": 0.0, "enemy": 0.0}

	var key := "player" if faction == PLAYER_FACTION else "enemy"
	cells[cell][key] = maxf(cells[cell][key], firepower)  # Keep highest threat in cell


func get_threat_at(position: Vector3, my_faction: int) -> float:
	## Get enemy threat level at a position (from perspective of my_faction).
	var cell := _world_to_cell(position)
	if cell not in cells:
		return 0.0

	var enemy_key := "enemy" if my_faction == PLAYER_FACTION else "player"
	return cells[cell][enemy_key]


func get_my_strength_at(position: Vector3, my_faction: int) -> float:
	## Get friendly strength at a position.
	var cell := _world_to_cell(position)
	if cell not in cells:
		return 0.0

	var my_key := "player" if my_faction == PLAYER_FACTION else "enemy"
	return cells[cell][my_key]


func get_threat_gradient(position: Vector3, my_faction: int) -> Vector3:
	## Get direction pointing AWAY from highest threat (for retreat).
	var cell := _world_to_cell(position)
	var gradient := Vector3.ZERO

	# Sample 8 neighboring cells
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue

			var neighbor := cell + Vector2i(dx, dz)
			var threat := _get_cell_threat(neighbor, my_faction)
			# Point AWAY from threat (negative contribution)
			gradient -= Vector3(float(dx), 0, float(dz)) * threat

	return gradient.normalized() if gradient.length() > 0.1 else Vector3.ZERO


func get_flanking_direction(position: Vector3, target_position: Vector3, my_faction: int) -> Vector3:
	## Get a direction for flanking (perpendicular to direct approach, toward lower threat).
	var direct := (target_position - position)
	direct.y = 0
	direct = direct.normalized()

	# Two perpendicular options
	var flank_left := Vector3(-direct.z, 0, direct.x)
	var flank_right := Vector3(direct.z, 0, -direct.x)

	# Check threat in each direction
	var pos_left := position + flank_left * cell_size
	var pos_right := position + flank_right * cell_size

	var threat_left := get_threat_at(pos_left, my_faction)
	var threat_right := get_threat_at(pos_right, my_faction)

	# Go toward lower threat
	if threat_left < threat_right:
		return flank_left
	elif threat_right < threat_left:
		return flank_right
	else:
		# Equal - pick randomly based on position
		return flank_left if fmod(position.x + position.z, 2.0) < 1.0 else flank_right


func should_retreat(position: Vector3, my_faction: int, my_firepower: float, hp_ratio: float) -> bool:
	## Check if a unit should retreat based on threat assessment.
	## Returns true if enemy threat > 2x our firepower AND HP < 50%.
	var threat := get_threat_at(position, my_faction)
	return threat > my_firepower * 2.0 and hp_ratio < 0.5


func get_safest_retreat_position(position: Vector3, my_faction: int, search_radius: float = 60.0) -> Vector3:
	## Find safest nearby position to retreat to.
	var gradient := get_threat_gradient(position, my_faction)
	if gradient.length() > 0.1:
		return position + gradient * search_radius
	else:
		# No threat gradient - retreat backward (toward faction's side)
		var retreat_dir := Vector3.FORWARD if my_faction == ENEMY_FACTION else Vector3.BACK
		return position + retreat_dir * search_radius


func decay_threats(delta: float) -> void:
	## Decay all threat values over time. Call once per frame.
	var decay_factor := 1.0 - (THREAT_DECAY_RATE * delta)
	var cells_to_remove: Array[Vector2i] = []

	for cell in cells:
		cells[cell]["player"] *= decay_factor
		cells[cell]["enemy"] *= decay_factor

		# Remove empty cells to prevent unbounded growth
		if cells[cell]["player"] < 0.1 and cells[cell]["enemy"] < 0.1:
			cells_to_remove.append(cell)

	for cell in cells_to_remove:
		cells.erase(cell)


func update_from_regiments(regiments: Array) -> void:
	## Update heatmap from all active regiments.
	## Call this periodically (e.g., every 0.5s) from AIAutoload.
	for regiment in regiments:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD:
			continue

		# Calculate firepower
		var firepower := _calculate_firepower(regiment)
		var faction: int = PLAYER_FACTION if regiment.is_player_controlled else ENEMY_FACTION

		set_unit_threat(regiment.global_position, faction, firepower)


func _calculate_firepower(regiment: Regiment) -> float:
	## Calculate effective firepower of a regiment.
	var base_power: float = 0.0

	# Melee strength
	base_power += regiment.data.weapon_skill * regiment.data.strength

	# Ranged strength (if has ammo)
	if regiment.current_ammo > 0 and regiment.data.ballistic_skill > 0:
		base_power += regiment.data.ballistic_skill * regiment.data.strength * 1.5

	# Scale by soldier count
	var soldier_ratio := float(regiment.current_soldiers) / float(regiment.data.max_soldiers)
	base_power *= soldier_ratio

	return base_power


func _world_to_cell(position: Vector3) -> Vector2i:
	## Convert world position to cell coordinates.
	return Vector2i(int(position.x / cell_size), int(position.z / cell_size))


func _cell_to_world(cell: Vector2i) -> Vector3:
	## Convert cell to world position (center of cell).
	return Vector3(float(cell.x) * cell_size + cell_size * 0.5, 0, float(cell.y) * cell_size + cell_size * 0.5)


func _get_cell_threat(cell: Vector2i, my_faction: int) -> float:
	## Get threat in a specific cell.
	if cell not in cells:
		return 0.0
	var enemy_key := "enemy" if my_faction == PLAYER_FACTION else "player"
	return cells[cell][enemy_key]


# --- DEBUG ---

func get_debug_info() -> Dictionary:
	## Get debug info about current heatmap state.
	var total_player_threat := 0.0
	var total_enemy_threat := 0.0
	var cell_count := cells.size()

	for cell in cells:
		total_player_threat += cells[cell]["player"]
		total_enemy_threat += cells[cell]["enemy"]

	return {
		"cell_count": cell_count,
		"total_player_threat": total_player_threat,
		"total_enemy_threat": total_enemy_threat,
		"cell_size": cell_size
	}
