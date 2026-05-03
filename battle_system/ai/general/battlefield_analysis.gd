class_name BattlefieldAnalysis
extends RefCounted

## Analyzes battlefield state for strategic decision-making.
## Provides metrics like strength ratio, centers of mass, and unit counts.
##
## Usage:
##   var analysis = BattlefieldAnalysis.new(faction)
##   analysis.update()
##   print(analysis.strength_ratio)

# =============================================================================
# PROPERTIES
# =============================================================================

var faction: int = 0

# Army composition
var friendly_regiments: Array = []
var enemy_regiments: Array = []

# Strength metrics
var friendly_strength: float = 0.0
var enemy_strength: float = 0.0
var strength_ratio: float = 1.0  # > 1 = we're stronger

# Centers of mass
var friendly_center: Vector3 = Vector3.ZERO
var enemy_center: Vector3 = Vector3.ZERO
var battle_center: Vector3 = Vector3.ZERO

# Unit type counts
var friendly_infantry: int = 0
var friendly_cavalry: int = 0
var friendly_ranged: int = 0
var friendly_artillery: int = 0

var enemy_infantry: int = 0
var enemy_cavalry: int = 0
var enemy_ranged: int = 0
var enemy_artillery: int = 0

# Combat state
var active_engagements: int = 0
var routing_friendly: int = 0
var routing_enemy: int = 0

# Morale
var average_friendly_morale: float = 100.0
var average_enemy_morale: float = 100.0

# Battlefield geometry
var frontline_position: Vector3 = Vector3.ZERO
var flank_vulnerability_left: float = 0.0
var flank_vulnerability_right: float = 0.0

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_faction: int = 0) -> void:
	faction = p_faction

# =============================================================================
# UPDATE
# =============================================================================

func update() -> void:
	## Refresh all battlefield analysis data.
	_gather_regiments()
	_calculate_strengths()
	_calculate_centers()
	_count_unit_types()
	_analyze_combat_state()
	_calculate_morale()
	_analyze_geometry()


func _gather_regiments() -> void:
	## Collect all regiments by faction.
	friendly_regiments = AIAutoload.get_all_regiments(faction)
	var enemy_faction: int = 1 if faction == 0 else 0
	enemy_regiments = AIAutoload.get_all_regiments(enemy_faction)

	# Filter out dead units
	friendly_regiments = friendly_regiments.filter(func(r): return r.state != Regiment.State.DEAD)
	enemy_regiments = enemy_regiments.filter(func(r): return r.state != Regiment.State.DEAD)


func _calculate_strengths() -> void:
	## Calculate total combat strength for each side.
	friendly_strength = 0.0
	for regiment in friendly_regiments:
		friendly_strength += _calculate_regiment_strength(regiment)

	enemy_strength = 0.0
	for regiment in enemy_regiments:
		enemy_strength += _calculate_regiment_strength(regiment)

	# Calculate ratio (avoid division by zero)
	if enemy_strength > 0:
		strength_ratio = friendly_strength / enemy_strength
	else:
		strength_ratio = 10.0 if friendly_strength > 0 else 1.0


func _calculate_regiment_strength(regiment: Node) -> float:
	## Calculate combat strength of a single regiment.
	var soldiers: float = float(regiment.current_soldiers)
	var attack: float = float(regiment.data.attack)
	var defense: float = float(regiment.data.defense)
	var morale_mult: float = regiment.current_morale / 100.0

	# Base strength
	var strength: float = soldiers * (attack + defense) / 20.0

	# Morale modifier
	strength *= 0.5 + morale_mult * 0.5

	# Unit type bonus
	match regiment.data.unit_type:
		UnitType.Type.CAVALRY:
			strength *= 1.3  # Cavalry is mobile and dangerous
		UnitType.Type.ARTILLERY:
			strength *= 0.8  # Artillery is vulnerable but powerful at range

	# Routing units are much weaker
	if regiment.state == Regiment.State.ROUTING:
		strength *= 0.1

	return strength


func _calculate_centers() -> void:
	## Calculate centers of mass for each army.
	friendly_center = _calculate_center_of_mass(friendly_regiments)
	enemy_center = _calculate_center_of_mass(enemy_regiments)

	# Battle center is midpoint
	if friendly_center != Vector3.ZERO and enemy_center != Vector3.ZERO:
		battle_center = (friendly_center + enemy_center) / 2.0
	else:
		battle_center = friendly_center if friendly_center != Vector3.ZERO else enemy_center


func _calculate_center_of_mass(regiments: Array) -> Vector3:
	## Calculate weighted center of mass (weighted by soldiers).
	if regiments.is_empty():
		return Vector3.ZERO

	var total_weight: float = 0.0
	var weighted_pos: Vector3 = Vector3.ZERO

	for regiment in regiments:
		var weight: float = float(regiment.current_soldiers)
		weighted_pos += regiment.global_position * weight
		total_weight += weight

	if total_weight > 0:
		return weighted_pos / total_weight
	return Vector3.ZERO


func _count_unit_types() -> void:
	## Count units by type for each faction.
	friendly_infantry = 0
	friendly_cavalry = 0
	friendly_ranged = 0
	friendly_artillery = 0

	for regiment in friendly_regiments:
		match regiment.data.unit_type:
			UnitType.Type.INFANTRY:
				friendly_infantry += 1
			UnitType.Type.CAVALRY:
				friendly_cavalry += 1
			UnitType.Type.RANGED:
				friendly_ranged += 1
			UnitType.Type.ARTILLERY:
				friendly_artillery += 1

	enemy_infantry = 0
	enemy_cavalry = 0
	enemy_ranged = 0
	enemy_artillery = 0

	for regiment in enemy_regiments:
		match regiment.data.unit_type:
			UnitType.Type.INFANTRY:
				enemy_infantry += 1
			UnitType.Type.CAVALRY:
				enemy_cavalry += 1
			UnitType.Type.RANGED:
				enemy_ranged += 1
			UnitType.Type.ARTILLERY:
				enemy_artillery += 1


func _analyze_combat_state() -> void:
	## Count engagements and routing units.
	active_engagements = 0
	routing_friendly = 0
	routing_enemy = 0

	for regiment in friendly_regiments:
		if regiment.state == Regiment.State.ENGAGING:
			active_engagements += 1
		elif regiment.state == Regiment.State.ROUTING:
			routing_friendly += 1

	for regiment in enemy_regiments:
		if regiment.state == Regiment.State.ROUTING:
			routing_enemy += 1


func _calculate_morale() -> void:
	## Calculate average morale for each side.
	if friendly_regiments.is_empty():
		average_friendly_morale = 0.0
	else:
		var total: float = 0.0
		for regiment in friendly_regiments:
			total += regiment.current_morale
		average_friendly_morale = total / float(friendly_regiments.size())

	if enemy_regiments.is_empty():
		average_enemy_morale = 0.0
	else:
		var total: float = 0.0
		for regiment in enemy_regiments:
			total += regiment.current_morale
		average_enemy_morale = total / float(enemy_regiments.size())


func _analyze_geometry() -> void:
	## Analyze battlefield geometry for tactical opportunities.
	if friendly_regiments.is_empty() or enemy_regiments.is_empty():
		return

	# Calculate frontline (average contact point)
	frontline_position = (friendly_center + enemy_center) / 2.0

	# Analyze flank vulnerability
	# Find leftmost and rightmost friendly units
	var friendly_left: float = INF
	var friendly_right: float = -INF

	for regiment in friendly_regiments:
		var x: float = regiment.global_position.x
		friendly_left = minf(friendly_left, x)
		friendly_right = maxf(friendly_right, x)

	# Find leftmost and rightmost enemy units
	var enemy_left: float = INF
	var enemy_right: float = -INF

	for regiment in enemy_regiments:
		var x: float = regiment.global_position.x
		enemy_left = minf(enemy_left, x)
		enemy_right = maxf(enemy_right, x)

	# Flank vulnerability: positive means enemy extends beyond our flank
	flank_vulnerability_left = friendly_left - enemy_left
	flank_vulnerability_right = enemy_right - friendly_right

# =============================================================================
# QUERIES
# =============================================================================

func get_available_cavalry() -> Array:
	## Get cavalry units not currently engaged.
	return friendly_regiments.filter(func(r):
		return r.data.unit_type == UnitType.Type.CAVALRY and r.state != Regiment.State.ENGAGING
	)


func get_available_infantry() -> Array:
	## Get infantry units not currently engaged.
	return friendly_regiments.filter(func(r):
		return r.data.unit_type == UnitType.Type.INFANTRY and r.state != Regiment.State.ENGAGING
	)


func get_weakest_enemy() -> Node:
	## Find the weakest enemy regiment.
	var weakest: Node = null
	var lowest_strength: float = INF

	for regiment in enemy_regiments:
		var strength: float = _calculate_regiment_strength(regiment)
		if strength < lowest_strength:
			lowest_strength = strength
			weakest = regiment

	return weakest


func get_most_isolated_enemy() -> Node:
	## Find enemy regiment furthest from its allies.
	var most_isolated: Node = null
	var max_isolation: float = 0.0

	for regiment in enemy_regiments:
		var isolation: float = _calculate_isolation(regiment, enemy_regiments)
		if isolation > max_isolation:
			max_isolation = isolation
			most_isolated = regiment

	return most_isolated


func _calculate_isolation(regiment: Node, allies: Array) -> float:
	## Calculate how isolated a regiment is from its allies.
	var min_dist: float = INF

	for ally in allies:
		if ally == regiment:
			continue
		var dist: float = regiment.global_position.distance_to(ally.global_position)
		min_dist = minf(min_dist, dist)

	return min_dist


func is_winning() -> bool:
	## Are we winning the battle?
	return strength_ratio > 1.2 and routing_enemy > routing_friendly


func is_losing() -> bool:
	## Are we losing the battle?
	return strength_ratio < 0.8 or routing_friendly > enemy_regiments.size() / 2

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"strength_ratio": strength_ratio,
		"friendly_strength": friendly_strength,
		"enemy_strength": enemy_strength,
		"friendly_regiments": friendly_regiments.size(),
		"enemy_regiments": enemy_regiments.size(),
		"active_engagements": active_engagements,
		"routing_friendly": routing_friendly,
		"routing_enemy": routing_enemy,
		"average_friendly_morale": average_friendly_morale,
		"average_enemy_morale": average_enemy_morale,
	}
