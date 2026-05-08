class_name PlayDefendCapturePoints
extends StrategicPlay

## Defend Capture Points - Primary siege defense strategy.
##
## The MAIN GOAL of any defending AI is to hold capture points.
## This play takes precedence over personality traits in siege battles.
##
## Assigns units to defend capture points based on:
## - Point value (larger/more valuable points get more defenders)
## - Threat level (contested points get reinforcements)
## - Unit type (infantry holds, ranged supports, cavalry counter-attacks)

const ROLE_POINT_DEFENDER: String = "point_defender"
const ROLE_POINT_SUPPORT: String = "point_support"
const ROLE_MOBILE_RESERVE: String = "mobile_reserve"

var _capture_points: Array = []
var _point_assignments: Dictionary = {}  # CapturePoint -> Array[Regiment]
var _reserve_units: Array = []

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "Defend Capture Points")
	intent = "Hold strategic capture points at all costs; primary objective in siege defense"


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score this play. ALWAYS high priority in siege battles for defenders.
	var score: float = 0.0

	# Find capture points
	_capture_points = _get_capture_points()
	if _capture_points.is_empty():
		return -100.0  # No capture points, not a siege battle

	# Check if we're defending (AI is typically the defender)
	var siege_manager: Node = _get_siege_manager()
	if siege_manager and not siege_manager.attacker_is_player:
		# AI is attacker, different strategy needed
		return -50.0

	# BASE SCORE: Very high when defending siege
	score = 80.0  # Start high - defending points is THE priority

	# Bonus for each point we control
	var controlled_points: int = 0
	var contested_points: int = 0
	var total_value: int = 0

	for point in _capture_points:
		total_value += point.get_point_value()
		if point.get_owner_faction() == "enemy":  # AI controls
			controlled_points += 1
			score += 5.0
		if point.is_contested:
			contested_points += 1
			score += 10.0  # Urgent - need to reinforce

	# Massive bonus when points are threatened
	if contested_points > 0:
		score += contested_points * 15.0

	# Bonus when we're the defender and losing ground
	var enemy_points: int = 0
	for point in _capture_points:
		if point.get_owner_faction() == "player":
			enemy_points += 1

	if enemy_points > 0:
		score += enemy_points * 20.0  # Must retake!

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_point_assignments.clear()
	_reserve_units.clear()
	_capture_points = _get_capture_points()

	if _capture_points.is_empty():
		status = Status.FAILURE
		return

	# Sort points by value (defend high-value points first)
	_capture_points.sort_custom(func(a, b): return a.get_point_value() > b.get_point_value())

	# Initialize assignments
	for point in _capture_points:
		_point_assignments[point] = []

	# Assign defenders
	_assign_defenders(analysis)
	_issue_defense_orders()

	print("[AI] Defending %d capture points with %d units" % [
		_capture_points.size(),
		analysis.friendly_regiments.size() - _reserve_units.size()
	])


func tick() -> Status:
	if not _is_active:
		return status

	# Refresh analysis
	if general_ai:
		_analysis = general_ai.analysis
		_analysis.update()

	if _check_completion():
		return status

	# Check for contested points - reallocate if needed
	_handle_contested_points()

	# Manage reserves for counter-attacks
	_manage_reserves()

	return Status.RUNNING


func _get_capture_points() -> Array:
	## Find all capture points in the scene.
	var points: Array = []
	# Access scene tree through a valid regiment
	if general_ai and general_ai.analysis:
		for regiment in general_ai.analysis.friendly_regiments:
			if is_instance_valid(regiment) and regiment.is_inside_tree():
				for node in regiment.get_tree().get_nodes_in_group("capture_points"):
					if node is CapturePoint:
						points.append(node)
				break
	return points


func _get_siege_manager() -> Node:
	## Find the SiegeManager in the scene.
	if general_ai and general_ai.analysis:
		for regiment in general_ai.analysis.friendly_regiments:
			if is_instance_valid(regiment) and regiment.is_inside_tree():
				var managers = regiment.get_tree().get_nodes_in_group("siege_managers")
				if managers.size() > 0:
					return managers[0]
				# Also check direct lookup
				var parent = regiment.get_tree().current_scene
				if parent:
					var manager = parent.get_node_or_null("SiegeManager")
					if manager:
						return manager
				break
	return null


func _assign_defenders(analysis: BattlefieldAnalysis) -> void:
	## Assign units to defend capture points based on value and unit type.
	var available_infantry: Array = []
	var available_ranged: Array = []
	var available_cavalry: Array = []

	# Sort units by type
	for regiment in analysis.friendly_regiments:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == regiment.State.DEAD or regiment.state == regiment.State.ROUTING:
			continue

		match regiment.data.unit_type:
			UnitType.Type.INFANTRY:
				available_infantry.append(regiment)
			UnitType.Type.RANGED:
				available_ranged.append(regiment)
			UnitType.Type.CAVALRY:
				available_cavalry.append(regiment)

	# Calculate total value for proportional assignment
	var total_value: int = 0
	for point in _capture_points:
		total_value += point.get_point_value()

	if total_value == 0:
		total_value = 1  # Prevent division by zero

	# Assign infantry proportionally to point value
	var infantry_assigned: int = 0
	for point in _capture_points:
		var proportion: float = float(point.get_point_value()) / float(total_value)
		var count: int = maxi(1, int(available_infantry.size() * proportion))

		for i in range(count):
			if infantry_assigned >= available_infantry.size():
				break
			var regiment = available_infantry[infantry_assigned]
			_point_assignments[point].append(regiment)
			assign_role(regiment, ROLE_POINT_DEFENDER)
			infantry_assigned += 1

	# Assign ranged to support highest value points
	var ranged_assigned: int = 0
	for point in _capture_points:
		if ranged_assigned >= available_ranged.size():
			break
		var regiment = available_ranged[ranged_assigned]
		_point_assignments[point].append(regiment)
		assign_role(regiment, ROLE_POINT_SUPPORT)
		ranged_assigned += 1

	# Cavalry become mobile reserve
	for regiment in available_cavalry:
		_reserve_units.append(regiment)
		assign_role(regiment, ROLE_MOBILE_RESERVE)


func _issue_defense_orders() -> void:
	## Order units to their assigned capture points.
	for point in _point_assignments:
		var defenders: Array = _point_assignments[point]
		var point_pos: Vector3 = point.global_position

		for i in defenders.size():
			var regiment = defenders[i]
			if not is_instance_valid(regiment):
				continue

			# Spread defenders around the point
			var angle: float = (float(i) / float(maxf(defenders.size(), 1))) * TAU
			var offset: Vector3 = Vector3(cos(angle), 0, sin(angle)) * (point.capture_radius * 0.5)
			var defend_pos: Vector3 = point_pos + offset

			issue_defend(regiment, defend_pos)

	# Hold reserves near the center
	if _capture_points.size() > 0:
		var center: Vector3 = Vector3.ZERO
		for point in _capture_points:
			center += point.global_position
		center /= float(_capture_points.size())

		for regiment in _reserve_units:
			issue_defend(regiment, center)


func _handle_contested_points() -> void:
	## Reinforce contested capture points.
	for point in _capture_points:
		if not point.is_contested:
			continue

		# Point is contested - send reinforcements
		var defenders: Array = _point_assignments[point]

		# Check if we have enough defenders
		var active_defenders: int = 0
		for regiment in defenders:
			if is_instance_valid(regiment) and regiment.state != regiment.State.DEAD:
				active_defenders += 1

		# If low on defenders, pull from reserves
		if active_defenders < 2 and _reserve_units.size() > 0:
			var reinforcement = _reserve_units.pop_front()
			if is_instance_valid(reinforcement):
				_point_assignments[point].append(reinforcement)
				assign_role(reinforcement, ROLE_POINT_DEFENDER)
				issue_defend(reinforcement, point.global_position)
				print("[AI] Reinforcing contested point: %s" % point.point_name)


func _manage_reserves() -> void:
	## Use reserves for counter-attacks against enemies on points.
	for regiment in _reserve_units:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == regiment.State.ENGAGING:
			continue  # Already fighting

		# Find enemies threatening our capture points
		var best_target: Node = null
		var best_priority: float = 0.0

		for point in _capture_points:
			# Only counter-attack for points we own or are contested
			if point.get_owner_faction() != "enemy" and not point.is_contested:
				continue

			# Find enemies near this point
			var enemies: Array = AIAutoload.get_enemy_regiments(
				0 if regiment.is_player_controlled else 1
			)

			for enemy in enemies:
				if not is_instance_valid(enemy):
					continue

				var dist: float = enemy.global_position.distance_to(point.global_position)
				if dist <= point.capture_radius * 1.5:
					# Enemy is threatening this point
					var priority: float = float(point.get_point_value()) / maxf(dist, 1.0)
					if priority > best_priority:
						best_priority = priority
						best_target = enemy

		if best_target:
			issue_attack(regiment, best_target)


func _check_completion() -> bool:
	## Check if play should end.

	# All enemies destroyed = success
	if _analysis.enemy_regiments.is_empty():
		status = Status.SUCCESS
		_is_active = false
		return true

	# Lost all points = failure (but keep fighting)
	var our_points: int = 0
	for point in _capture_points:
		if point.get_owner_faction() == "enemy":  # AI faction
			our_points += 1

	# Don't end - keep defending even if losing
	return false


func abort() -> void:
	super.abort()
	_point_assignments.clear()
	_reserve_units.clear()
	_capture_points.clear()
