class_name PlayDefensiveLine
extends StrategicPlay

# Preload BattleObjective class
const BattleObjectiveClass = preload("res://battle_system/ai/data/battle_objective.gd")

## Defensive Line strategy.
## Form a solid defensive line and let the enemy come to us.
## Good when outnumbered or on favorable terrain.

const ROLE_LINE: String = "line"
const ROLE_RANGED: String = "ranged_support"
const ROLE_RESERVE: String = "reserve"

var _line_position: Vector3 = Vector3.ZERO
var _line_facing: Vector3 = Vector3.FORWARD
var _line_units: Array = []
var _ranged_units: Array = []
var _reserve_units: Array = []

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "Defensive Line")
	intent = "Form solid defensive line and let enemy come to us; conserve strength and wear them down"


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score this play. Good when defensive posture is advantageous.
	var score: float = 0.0

	# Good when outnumbered
	if analysis.strength_ratio < 1.0:
		score += (1.0 - analysis.strength_ratio) * 40.0

	# Good when we have ranged units
	if analysis.friendly_ranged > 0:
		score += analysis.friendly_ranged * 10.0

	# Good when enemy has lots of cavalry (defense counters charges)
	if analysis.enemy_cavalry > analysis.friendly_cavalry:
		score += 15.0

	# Less good when we're winning (should be aggressive)
	if analysis.strength_ratio > 1.3:
		score -= 20.0

	# Good when morale is low (conserve strength)
	if analysis.average_friendly_morale < 60.0:
		score += 15.0

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_line_units.clear()
	_ranged_units.clear()
	_reserve_units.clear()

	# Calculate defensive line position
	_calculate_line_position(analysis)

	# Assign units to roles
	_assign_units(analysis)

	# Issue formation orders
	_form_line()


func tick() -> Status:
	if not _is_active:
		return status

	# Refresh analysis
	if general_ai:
		_analysis = general_ai.analysis
		_analysis.update()

	# Check completion
	if _check_completion():
		return status

	# Maintain formation
	_maintain_line()

	# Manage ranged fire
	_manage_ranged()

	# Commit reserves if needed
	_manage_reserves()

	return Status.RUNNING


func _calculate_line_position(analysis: BattlefieldAnalysis) -> void:
	## Calculate where to form the defensive line.
	## OBJECTIVE FIX: HOLD_GROUND defenders form line at hold_position from
	## their objective, instead of advancing 30% toward the enemy.

	# Read objective from the parent GeneralAI
	var objective: BattleObjectiveClass = null
	if general_ai and general_ai.objective:
		objective = general_ai.objective

	if objective and objective.type == BattleObjectiveClass.Type.HOLD_GROUND:
		# Defender: hold the line at the designated position. Don't advance.
		_line_position = objective.hold_position
		_line_position.y = 0.0

		# Still face the enemy — just don't move toward them.
		var to_enemy: Vector3 = (analysis.enemy_center - _line_position)
		to_enemy.y = 0.0
		if to_enemy.length_squared() < 0.01:
			to_enemy = Vector3(0, 0, -1)  # safe default if enemy_center coincides
		_line_facing = to_enemy.normalized()
	else:
		# Original behavior for ANNIHILATE objective: form line 30% of the way
		# toward the enemy (defending is just a tactical choice, not a goal).
		_line_position = analysis.friendly_center.lerp(analysis.enemy_center, 0.3)
		_line_position.y = 0.0
		var to_enemy: Vector3 = (analysis.enemy_center - _line_position).normalized()
		to_enemy.y = 0.0
		_line_facing = to_enemy


func _assign_units(analysis: BattlefieldAnalysis) -> void:
	## Assign units to defensive roles.

	# Infantry forms the main line
	for regiment in analysis.friendly_regiments:
		if regiment.data.unit_type == UnitType.Type.INFANTRY:
			_line_units.append(regiment)
			assign_role(regiment, ROLE_LINE)

	# Ranged units support from behind
	for regiment in analysis.friendly_regiments:
		if regiment.data.unit_type == UnitType.Type.RANGED:
			_ranged_units.append(regiment)
			assign_role(regiment, ROLE_RANGED)

	# Cavalry as mobile reserve
	for regiment in analysis.friendly_regiments:
		if regiment.data.unit_type == UnitType.Type.CAVALRY:
			_reserve_units.append(regiment)
			assign_role(regiment, ROLE_RESERVE)


func _form_line() -> void:
	## Order units into defensive line formation.

	if _line_units.is_empty():
		return

	# Calculate spacing
	var total_width: float = _line_units.size() * 8.0
	var start_x: float = -total_width / 2.0

	# Line perpendicular to facing
	var line_right: Vector3 = _line_facing.cross(Vector3.UP).normalized()

	for i in _line_units.size():
		var regiment = _line_units[i]
		var offset: float = start_x + i * 8.0

		var position: Vector3 = _line_position + line_right * offset
		issue_defend(regiment, position)

	# Position ranged behind the line
	for i in _ranged_units.size():
		var regiment = _ranged_units[i]
		var offset: float = start_x + i * 10.0

		var position: Vector3 = _line_position - _line_facing * 10.0 + line_right * offset
		issue_defend(regiment, position)

	# Reserves behind ranged
	for regiment in _reserve_units:
		var _position: Vector3 = _line_position - _line_facing * 20.0  # Reserved for reserve positioning
		issue_hold(regiment)


func _maintain_line() -> void:
	## Keep line units in position and engaged.

	for regiment in _line_units:
		if not is_instance_valid(regiment):
			continue

		# Skip if already engaged in melee
		if regiment.state == Regiment.State.ENGAGING:
			continue

		# If enemy is within engagement range, engage them
		# Use larger radius (30m) so defensive line actually engages approaching enemies
		var nearest_enemy: Node = AIAutoload.query_nearest_enemy(
			regiment.global_position, 30.0,
			0 if regiment.is_player_controlled else 1
		)

		if nearest_enemy:
			var commander: CommanderAI = general_ai.get_commander(regiment)
			if commander:
				var dist: float = regiment.global_position.distance_to(nearest_enemy.global_position)
				# If enemy is close (within 20m), actively attack them
				# This ensures defensive units actually engage instead of just watching
				if dist < 20.0:
					commander.set_target(nearest_enemy)
					commander.issue_attack_order(nearest_enemy)
				else:
					# Beyond 20m, just set target and let them hold position
					# They'll engage when enemy gets closer
					commander.set_stance(CommanderAI.Stance.DEFENSIVE)
					commander.set_target(nearest_enemy)


func _manage_ranged() -> void:
	## Direct ranged fire at priority targets.

	for regiment in _ranged_units:
		if not is_instance_valid(regiment):
			continue

		var commander: CommanderAI = general_ai.get_commander(regiment)
		if not commander:
			continue

		# Find best target for ranged fire
		var targets: Array = AIAutoload.get_enemy_regiments(
			0 if regiment.is_player_controlled else 1
		)

		if targets.is_empty():
			continue

		# Prioritize units engaging our line
		var best_target: Node = null
		var best_score: float = -INF

		for target in targets:
			var score: float = 0.0

			# Closer is better (for ranged)
			var dist: float = regiment.global_position.distance_to(target.global_position)
			if dist <= regiment.data.range_distance:
				score += 20.0 - dist * 0.2

			# Engaged targets are priority
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
	## Commit reserves to reinforce weak points.

	# Find if any line unit is routing or heavily engaged
	var crisis_point: Node = null

	for regiment in _line_units:
		if not is_instance_valid(regiment):
			continue

		if regiment.state == Regiment.State.ROUTING:
			crisis_point = regiment
			break

		# Check if severely outnumbered locally
		var nearby_enemies: int = AIAutoload.count_enemies(
			regiment.global_position, 15.0,
			0 if regiment.is_player_controlled else 1
		)
		var nearby_allies: int = AIAutoload.count_allies(
			regiment.global_position, 15.0,
			0 if regiment.is_player_controlled else 1
		)

		if nearby_enemies > nearby_allies * 2:
			crisis_point = regiment
			break

	if crisis_point and not _reserve_units.is_empty():
		# Commit reserves
		var reserve = _reserve_units.pop_front()
		if is_instance_valid(reserve):
			# Find enemy threatening the crisis point
			var threat: Node = AIAutoload.query_nearest_enemy(
				crisis_point.global_position, 20.0,
				0 if reserve.is_player_controlled else 1
			)

			if threat:
				issue_attack(reserve, threat)
			else:
				issue_defend(reserve, crisis_point.global_position)


func _check_completion() -> bool:
	## Check if play should end.

	# Enemy destroyed/routed = success
	if _analysis.enemy_regiments.is_empty():
		status = Status.SUCCESS
		_is_active = false
		return true

	if _analysis.routing_enemy >= _analysis.enemy_regiments.size() * 0.7:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Our line collapsed = failure
	var active_line: int = 0
	for regiment in _line_units:
		if is_instance_valid(regiment) and regiment.state != Regiment.State.DEAD:
			active_line += 1

	if active_line == 0:
		status = Status.FAILURE
		_is_active = false
		return true

	return false


func abort() -> void:
	super.abort()
	_line_units.clear()
	_ranged_units.clear()
	_reserve_units.clear()
