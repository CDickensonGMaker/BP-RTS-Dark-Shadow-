class_name PlayChokepointDefense
extends StrategicPlay

## Chokepoint Defense - Advanced siege defense strategy.
##
## Positions forward units at chokepoints to intercept attackers BEFORE
## they reach the capture point. Keeps reserves at the capture point.
##
## Priority order:
## 1. Cut enemies off at chokepoints (forward interception)
## 2. Hold reserves at capture point (final defense)
## 3. Fight to the last man (high morale, no easy routing)

# Preload BattleObjective class
const BattleObjectiveClass = preload("res://battle_system/ai/data/battle_objective.gd")

# =============================================================================
# CONSTANTS
# =============================================================================

const ROLE_CHOKEPOINT_DEFENDER: String = "chokepoint_defender"
const ROLE_CAPTURE_POINT_GUARD: String = "capture_point_guard"
const ROLE_MOBILE_RESERVE: String = "mobile_reserve"
const ROLE_RANGED_SUPPORT: String = "ranged_support"

# Morale boost for siege defenders - fight to the last man
const SIEGE_DEFENDER_MORALE_BOOST: float = 15.0

# Engagement distances
const CHOKEPOINT_ENGAGE_RADIUS: float = 25.0
const CAPTURE_POINT_THREAT_RADIUS: float = 30.0

# Default chokepoint positions for siege town layout
# These are positions where attackers must pass through
const DEFAULT_CHOKEPOINTS: Array[Vector3] = [
	Vector3(0, 0, 0),    # Town gate - furthest forward
	Vector3(20, 0, 0),   # Market square - middle
	Vector3(30, 0, 0),   # Inner plaza - closest to capture point
]

# =============================================================================
# STATE
# =============================================================================

var _chokepoints: Array[Vector3] = []
var _chokepoint_defenders: Dictionary = {}  # Vector3 -> Array of regiments
var _capture_point_guards: Array = []
var _ranged_units: Array = []
var _reserve_units: Array = []
var _capture_point: Node = null
var _morale_boost_applied: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_general_ai = null) -> void:
	super._init(p_general_ai, "Chokepoint Defense")
	intent = "Intercept attackers at chokepoints; hold reserves at capture point; fight to the last"


# =============================================================================
# EVALUATION
# =============================================================================

func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score this play. High priority when defending siege with chokepoints.
	var score: float = 0.0

	# Find capture points in scene
	var capture_points := _find_capture_points()
	if capture_points.is_empty():
		return -100.0  # No capture points, not applicable

	# Check if we're the defender (HOLD_GROUND or CAPTURE_POINTS objective)
	var objective: BattleObjectiveClass = null
	if general_ai and general_ai.objective:
		objective = general_ai.objective

	if objective:
		if objective.type != BattleObjectiveClass.Type.HOLD_GROUND and \
		   objective.type != BattleObjectiveClass.Type.CAPTURE_POINTS:
			return -50.0  # Only for defenders

	# BASE SCORE: High when we have capture points to defend
	score = 90.0  # Higher than PlayDefendCapturePoints (80)

	# Bonus for having multiple units (need enough to split between positions)
	if analysis.friendly_regiments.size() >= 4:
		score += 10.0

	# Bonus when enemy is still approaching (not yet at capture point)
	var enemy_dist_to_capture := INF
	for enemy in analysis.enemy_regiments:
		if is_instance_valid(enemy):
			var dist: float = enemy.global_position.distance_to(capture_points[0].global_position)
			enemy_dist_to_capture = minf(enemy_dist_to_capture, dist)

	if enemy_dist_to_capture > 50.0:  # Enemy still far from capture point
		score += 25.0  # Excellent time for forward defense
	elif enemy_dist_to_capture > 30.0:
		score += 15.0  # Good time for forward defense

	# Bonus when we have ranged units (can support chokepoints)
	if analysis.friendly_ranged > 0:
		score += analysis.friendly_ranged * 5.0

	# Good when outnumbered (chokepoints equalize odds)
	if analysis.strength_ratio < 1.0:
		score += (1.0 - analysis.strength_ratio) * 20.0

	return score


# =============================================================================
# START
# =============================================================================

func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	# Clear previous state
	_chokepoint_defenders.clear()
	_capture_point_guards.clear()
	_ranged_units.clear()
	_reserve_units.clear()
	_morale_boost_applied = false

	# Find capture point
	var capture_points := _find_capture_points()
	if capture_points.is_empty():
		status = Status.FAILURE
		_is_active = false
		print("[AI] Chokepoint Defense: No capture points found, aborting")
		return
	_capture_point = capture_points[0]

	# Setup chokepoints (use defaults or detect from buildings)
	_chokepoints = DEFAULT_CHOKEPOINTS.duplicate()

	# Initialize defender arrays for each chokepoint
	for cp in _chokepoints:
		_chokepoint_defenders[cp] = []

	# Assign units to positions
	_assign_defenders(analysis)

	# Apply morale boost for "fight to the last man" behavior
	_apply_siege_morale_boost()

	# Issue initial defense orders
	_issue_defense_orders()

	print("[AI] Chokepoint Defense started: %d chokepoints, %d guards, %d ranged, %d reserves" % [
		_chokepoints.size(),
		_capture_point_guards.size(),
		_ranged_units.size(),
		_reserve_units.size()
	])


# =============================================================================
# TICK
# =============================================================================

func tick() -> Status:
	if not _is_active:
		return status

	# Refresh analysis
	if general_ai:
		_analysis = general_ai.analysis
		_analysis.update()

	# Check victory/defeat conditions
	if _check_completion():
		return status

	# Manage chokepoint defenders - engage enemies, fall back if overwhelmed
	_manage_chokepoint_defense()

	# Manage ranged support - fire at priority targets
	_manage_ranged_support()

	# Commit reserves when needed
	_manage_reserves()

	return Status.RUNNING


# =============================================================================
# UNIT ASSIGNMENT
# =============================================================================

func _assign_defenders(analysis: BattlefieldAnalysis) -> void:
	## Assign units to chokepoints and capture point based on type.
	var available_infantry: Array = []
	var available_ranged: Array = []
	var available_cavalry: Array = []

	# Sort units by type
	for regiment in analysis.friendly_regiments:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD or regiment.state == Regiment.State.ROUTING:
			continue

		match regiment.data.unit_type:
			UnitType.Type.INFANTRY:
				available_infantry.append(regiment)
			UnitType.Type.RANGED:
				available_ranged.append(regiment)
			UnitType.Type.CAVALRY:
				available_cavalry.append(regiment)

	# Strategy:
	# - Chokepoint 1 (furthest forward): 40% of infantry
	# - Chokepoint 2 (middle): 20% of infantry
	# - Capture point guard: 40% of infantry
	# - Ranged: Support chokepoints from behind
	# - Cavalry: Mobile reserve

	var total_infantry := available_infantry.size()
	var infantry_idx := 0

	# Assign to forward chokepoints (60% of infantry goes forward)
	if _chokepoints.size() >= 1 and total_infantry > 0:
		# First chokepoint - 40% of infantry
		var cp1: Vector3 = _chokepoints[0]
		var count1: int = ceili(total_infantry * 0.4)
		for i in range(count1):
			if infantry_idx >= available_infantry.size():
				break
			var regiment = available_infantry[infantry_idx]
			_chokepoint_defenders[cp1].append(regiment)
			assign_role(regiment, ROLE_CHOKEPOINT_DEFENDER)
			infantry_idx += 1

	if _chokepoints.size() >= 2 and infantry_idx < total_infantry:
		# Second chokepoint - 20% of infantry
		var cp2: Vector3 = _chokepoints[1]
		var count2: int = ceili(total_infantry * 0.2)
		for i in range(count2):
			if infantry_idx >= available_infantry.size():
				break
			var regiment = available_infantry[infantry_idx]
			_chokepoint_defenders[cp2].append(regiment)
			assign_role(regiment, ROLE_CHOKEPOINT_DEFENDER)
			infantry_idx += 1

	# Remaining infantry guards capture point (40%)
	while infantry_idx < available_infantry.size():
		var regiment = available_infantry[infantry_idx]
		_capture_point_guards.append(regiment)
		assign_role(regiment, ROLE_CAPTURE_POINT_GUARD)
		infantry_idx += 1

	# Ranged units support chokepoints from behind
	for regiment in available_ranged:
		_ranged_units.append(regiment)
		assign_role(regiment, ROLE_RANGED_SUPPORT)

	# Cavalry as mobile reserve
	for regiment in available_cavalry:
		_reserve_units.append(regiment)
		assign_role(regiment, ROLE_MOBILE_RESERVE)


func _apply_siege_morale_boost() -> void:
	## Apply morale boost to all defenders for "fight to the last man" behavior.
	if _morale_boost_applied:
		return

	for regiment in _analysis.friendly_regiments:
		if is_instance_valid(regiment):
			# Boost current morale
			regiment.current_morale = minf(regiment.current_morale + SIEGE_DEFENDER_MORALE_BOOST, 100.0)

			# If unit has morale component, boost its base as well
			if regiment.has_node("UnitMorale"):
				var morale_node = regiment.get_node("UnitMorale")
				if morale_node.has_method("apply_bonus"):
					morale_node.apply_bonus(SIEGE_DEFENDER_MORALE_BOOST)

	_morale_boost_applied = true
	print("[AI] Chokepoint Defense: Applied +%.0f morale boost to defenders" % SIEGE_DEFENDER_MORALE_BOOST)


# =============================================================================
# DEFENSE ORDERS
# =============================================================================

func _issue_defense_orders() -> void:
	## Order units to their assigned positions.

	# Chokepoint defenders - spread across chokepoint width
	for cp in _chokepoint_defenders:
		var defenders: Array = _chokepoint_defenders[cp]
		var cp_pos: Vector3 = cp

		for i in defenders.size():
			var regiment = defenders[i]
			if not is_instance_valid(regiment):
				continue

			# Spread defenders across the chokepoint width (Z axis)
			var offset: float = (float(i) - float(defenders.size() - 1) / 2.0) * 8.0
			var defend_pos: Vector3 = cp_pos + Vector3(0, 0, offset)

			issue_defend(regiment, defend_pos)

			# Set defensive stance for holding position
			var commander = general_ai.get_commander(regiment) if general_ai else null
			if commander:
				commander.set_stance(commander.Stance.DEFENSIVE)

	# Ranged units - position behind first two chokepoints
	for i in _ranged_units.size():
		var regiment = _ranged_units[i]
		if not is_instance_valid(regiment):
			continue

		# Position ranged behind chokepoints, alternating
		var cp_idx: int = i % mini(_chokepoints.size(), 2)
		var cp_pos: Vector3 = _chokepoints[cp_idx]

		# 15 units behind the chokepoint
		var offset_z: float = (float(i / 2) - 1.0) * 10.0
		var ranged_pos: Vector3 = cp_pos + Vector3(10, 0, offset_z)  # Behind (+X is toward defender spawn)

		issue_defend(regiment, ranged_pos)

	# Capture point guards - spread around capture point
	if _capture_point and is_instance_valid(_capture_point):
		var cp_pos: Vector3 = _capture_point.global_position

		for i in _capture_point_guards.size():
			var regiment = _capture_point_guards[i]
			if not is_instance_valid(regiment):
				continue

			# Spread around capture point in a circle
			var angle: float = (float(i) / float(maxf(_capture_point_guards.size(), 1))) * TAU
			var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * 12.0

			issue_defend(regiment, cp_pos + offset)

			# Defensive stance
			var commander = general_ai.get_commander(regiment) if general_ai else null
			if commander:
				commander.set_stance(commander.Stance.DEFENSIVE)

	# Reserves - hold near capture point but ready to move
	for regiment in _reserve_units:
		if not is_instance_valid(regiment):
			continue
		issue_hold(regiment)


# =============================================================================
# COMBAT MANAGEMENT
# =============================================================================

func _manage_chokepoint_defense() -> void:
	## Monitor chokepoints, engage enemies, reinforce as needed.

	for cp in _chokepoints:
		var defenders: Array = _chokepoint_defenders[cp]
		var cp_pos: Vector3 = cp

		# Count active defenders at this chokepoint
		var active_defenders: Array = []
		for regiment in defenders:
			if is_instance_valid(regiment) and regiment.state != Regiment.State.DEAD and regiment.state != Regiment.State.ROUTING:
				active_defenders.append(regiment)

		# Find enemies near this chokepoint
		var nearest_enemy: Node = AIAutoload.query_nearest_enemy(
			cp_pos, CHOKEPOINT_ENGAGE_RADIUS,
			0 if _get_faction() == 1 else 1  # Query opposite faction
		)

		if nearest_enemy and not active_defenders.is_empty():
			# Enemies at chokepoint - engage them!
			for regiment in active_defenders:
				if regiment.state == Regiment.State.ENGAGING:
					continue  # Already fighting

				var dist: float = regiment.global_position.distance_to(nearest_enemy.global_position)
				if dist < 20.0:
					# Close enough - attack
					var commander = general_ai.get_commander(regiment) if general_ai else null
					if commander:
						commander.set_target(nearest_enemy)
						commander.issue_attack_order(nearest_enemy)
				else:
					# Set as target, wait for them to come closer
					var commander = general_ai.get_commander(regiment) if general_ai else null
					if commander:
						commander.set_target(nearest_enemy)

		# Check if chokepoint is breached (no defenders, enemies present)
		var enemies_at_cp: int = AIAutoload.count_enemies(
			cp_pos, CHOKEPOINT_ENGAGE_RADIUS,
			0 if _get_faction() == 1 else 1
		)

		if active_defenders.is_empty() and enemies_at_cp > 0:
			# Chokepoint breached - commit reserves!
			_commit_reserves_to_position(cp_pos)


func _manage_ranged_support() -> void:
	## Direct ranged fire at priority targets.

	for regiment in _ranged_units:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD or regiment.state == Regiment.State.ROUTING:
			continue

		var commander = general_ai.get_commander(regiment) if general_ai else null
		if not commander:
			continue

		# Find best target for ranged support
		var targets: Array = AIAutoload.get_enemy_regiments(
			0 if _get_faction() == 1 else 1
		)

		if targets.is_empty():
			continue

		# Prioritize enemies at chokepoints
		var best_target: Node = null
		var best_score: float = -INF

		for target in targets:
			if not is_instance_valid(target):
				continue

			var score: float = 0.0

			# Check distance to any chokepoint
			for cp in _chokepoints:
				var dist_to_cp: float = target.global_position.distance_to(cp)
				if dist_to_cp < 30.0:
					score += 30.0 - dist_to_cp  # Closer to chokepoint = higher priority

			# Distance from ranged unit (closer = better, but within range)
			var dist: float = regiment.global_position.distance_to(target.global_position)
			if dist <= regiment.data.range_distance:
				score += 20.0 - dist * 0.2
			else:
				score -= 20.0  # Out of range penalty

			# Engaged targets are high priority (supporting melee)
			if target.state == Regiment.State.ENGAGING:
				score += 15.0

			# Low morale targets might break
			score += (100.0 - target.current_morale) * 0.2

			if score > best_score:
				best_score = score
				best_target = target

		if best_target:
			commander.set_target(best_target)


func _manage_reserves() -> void:
	## Commit reserves to threatened positions.

	if _reserve_units.is_empty():
		return

	# Check if capture point is directly threatened
	if _capture_point and is_instance_valid(_capture_point):
		var cp_pos: Vector3 = _capture_point.global_position

		var enemies_near_cp: int = AIAutoload.count_enemies(
			cp_pos, CAPTURE_POINT_THREAT_RADIUS,
			0 if _get_faction() == 1 else 1
		)

		if enemies_near_cp > 0:
			# Capture point threatened - commit reserves!
			print("[AI] Chokepoint Defense: Capture point threatened! Committing %d reserves" % _reserve_units.size())

			for regiment in _reserve_units.duplicate():
				if is_instance_valid(regiment):
					# Find nearest enemy at capture point
					var threat: Node = AIAutoload.query_nearest_enemy(
						cp_pos, CAPTURE_POINT_THREAT_RADIUS,
						0 if _get_faction() == 1 else 1
					)
					if threat:
						issue_attack(regiment, threat)
					_reserve_units.erase(regiment)


func _commit_reserves_to_position(position: Vector3) -> void:
	## Send reserve units to reinforce a breached position.

	if _reserve_units.is_empty():
		return

	var reserve = _reserve_units.pop_front()
	if is_instance_valid(reserve):
		print("[AI] Chokepoint Defense: Committing reserve to reinforce position %s" % position)

		var threat: Node = AIAutoload.query_nearest_enemy(
			position, CHOKEPOINT_ENGAGE_RADIUS,
			0 if _get_faction() == 1 else 1
		)
		if threat:
			issue_attack(reserve, threat)
		else:
			issue_defend(reserve, position)


# =============================================================================
# UTILITY
# =============================================================================

func _find_capture_points() -> Array:
	## Find all capture points in the scene.
	var points: Array = []

	# Search through the tree for capture points
	if general_ai and general_ai.analysis:
		for regiment in general_ai.analysis.friendly_regiments:
			if is_instance_valid(regiment) and regiment.is_inside_tree():
				for node in regiment.get_tree().get_nodes_in_group("capture_points"):
					if not points.has(node):
						points.append(node)
				break  # Only need to search once

	return points


func _get_faction() -> int:
	## Get our faction ID from regiments (0 = player, 1 = enemy).
	if _analysis and not _analysis.friendly_regiments.is_empty():
		var regiment = _analysis.friendly_regiments[0]
		return 0 if regiment.is_player_controlled else 1
	return 1  # Default to enemy/defender


func _check_completion() -> bool:
	## Check if play should end.

	# All enemies destroyed = victory!
	if _analysis.enemy_regiments.is_empty():
		status = Status.SUCCESS
		_is_active = false
		print("[AI] Chokepoint Defense: Victory! All enemies eliminated")
		return true

	# Check if most enemies are routing
	if _analysis.routing_enemy >= _analysis.enemy_regiments.size() * 0.7:
		status = Status.SUCCESS
		_is_active = false
		print("[AI] Chokepoint Defense: Victory! Enemy forces routing")
		return true

	# Check if we've lost all defenders (failure)
	var active_friendlies: int = 0
	for regiment in _analysis.friendly_regiments:
		if is_instance_valid(regiment) and regiment.state != Regiment.State.DEAD:
			active_friendlies += 1

	if active_friendlies == 0:
		status = Status.FAILURE
		_is_active = false
		print("[AI] Chokepoint Defense: Defeat! All defenders eliminated")
		return true

	# Keep fighting - siege defenders don't give up easily
	return false


func abort() -> void:
	super.abort()
	_chokepoint_defenders.clear()
	_capture_point_guards.clear()
	_ranged_units.clear()
	_reserve_units.clear()
	print("[AI] Chokepoint Defense: Aborted")
