class_name PlayPunishOvercommit
extends StrategicPlay

## Punish Overcommit - Reactive play that exploits isolated enemy units.
##
## Detects enemy units that have advanced too far from support and
## coordinates a concentrated attack to destroy them before reinforcements arrive.
##
## Triggers when:
## - Enemy unit is isolated (far from other enemies)
## - We have numerical advantage locally
## - Enemy unit is engaged or vulnerable

const ISOLATION_DISTANCE: float = 30.0  # Distance from nearest ally to be "isolated"
const LOCAL_SUPERIORITY_RATIO: float = 1.5  # We need 1.5x soldiers locally
const CONVERGENCE_RADIUS: float = 15.0  # Units within this radius attack together

var _target_unit: Node = null
var _attacking_units: Array = []
var _target_acquired_time: float = 0.0

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "Punish Overcommit")
	intent = "Concentrate forces to destroy an isolated enemy unit that has overextended"


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score based on whether there's an exploitable isolated enemy.
	var score: float = 0.0

	# Find the most isolated enemy
	var isolated_target: Node = _find_isolated_enemy(analysis)
	if not isolated_target:
		return -100.0  # No opportunity

	# Calculate local superiority
	var local_ratio: float = _calculate_local_superiority(isolated_target, analysis)
	if local_ratio < LOCAL_SUPERIORITY_RATIO:
		return -50.0  # Not enough local advantage

	# Base score for having a target
	score += 40.0

	# Bonus for higher local superiority
	score += (local_ratio - LOCAL_SUPERIORITY_RATIO) * 15.0

	# Bonus if target is already engaged (vulnerable)
	if isolated_target.state == isolated_target.State.ENGAGING:
		score += 15.0

	# Bonus if target has low morale
	if isolated_target.current_morale < 50.0:
		score += 10.0

	# Bonus for opportunistic personality
	if general_ai and general_ai.personality:
		score += general_ai.personality.opportunism * 15.0
		score += general_ai.personality.tactical_flexibility * 5.0

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_attacking_units.clear()
	_target_acquired_time = Time.get_ticks_msec() / 1000.0

	# Find and lock onto isolated target
	_target_unit = _find_isolated_enemy(analysis)
	if not _target_unit:
		status = Status.FAILURE
		return

	# Assign nearby units to attack
	_assign_attackers(analysis)

	if _attacking_units.is_empty():
		status = Status.FAILURE
		return

	# Issue initial orders
	_issue_converge_orders()

	print("[AI] Punishing overcommitted %s with %d units" % [_target_unit.name, _attacking_units.size()])


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

	# Keep attackers focused on target
	_update_attackers()

	return Status.RUNNING


func _find_isolated_enemy(analysis: BattlefieldAnalysis) -> Node:
	## Find the most isolated enemy unit.
	var best_target: Node = null
	var best_isolation: float = 0.0

	for enemy in analysis.enemy_regiments:
		if not is_instance_valid(enemy):
			continue
		if enemy.state == enemy.State.DEAD or enemy.state == enemy.State.ROUTING:
			continue

		var isolation: float = _get_isolation_score(enemy, analysis)
		if isolation > best_isolation and isolation > ISOLATION_DISTANCE:
			best_isolation = isolation
			best_target = enemy

	return best_target


func _get_isolation_score(regiment: Node, analysis: BattlefieldAnalysis) -> float:
	## Calculate how isolated this unit is from its allies.
	var min_ally_dist: float = INF

	for ally in analysis.enemy_regiments:
		if ally == regiment:
			continue
		if not is_instance_valid(ally):
			continue
		if ally.state == ally.State.DEAD:
			continue

		var dist: float = regiment.global_position.distance_to(ally.global_position)
		if dist < min_ally_dist:
			min_ally_dist = dist

	return min_ally_dist


func _calculate_local_superiority(target: Node, analysis: BattlefieldAnalysis) -> float:
	## Calculate our numerical advantage near the target.
	var our_soldiers: int = 0
	var their_soldiers: int = target.current_soldiers

	for regiment in analysis.friendly_regiments:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == regiment.State.DEAD or regiment.state == regiment.State.ROUTING:
			continue

		var dist: float = regiment.global_position.distance_to(target.global_position)
		if dist <= CONVERGENCE_RADIUS * 2:  # Units that could reach quickly
			our_soldiers += regiment.current_soldiers

	if their_soldiers <= 0:
		return 10.0  # Target has no soldiers

	return float(our_soldiers) / float(their_soldiers)


func _assign_attackers(analysis: BattlefieldAnalysis) -> void:
	## Assign nearby units to the attack.
	if not _target_unit:
		return

	# Get units within convergence range
	for regiment in analysis.friendly_regiments:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == regiment.State.DEAD or regiment.state == regiment.State.ROUTING:
			continue

		var dist: float = regiment.global_position.distance_to(_target_unit.global_position)
		if dist <= CONVERGENCE_RADIUS * 2:
			_attacking_units.append(regiment)
			assign_role(regiment, "punish")


func _issue_converge_orders() -> void:
	## Order all attackers to converge on target.
	for regiment in _attacking_units:
		if is_instance_valid(regiment):
			issue_attack(regiment, _target_unit)


func _update_attackers() -> void:
	## Keep attackers focused on the target.
	if not _target_unit or not is_instance_valid(_target_unit):
		return

	for regiment in _attacking_units:
		if not is_instance_valid(regiment):
			continue

		# Re-engage if not currently attacking
		if regiment.state != regiment.State.ENGAGING:
			issue_attack(regiment, _target_unit)


func _check_completion() -> bool:
	## Check if play is complete.

	# Target destroyed = success
	if not _target_unit or not is_instance_valid(_target_unit):
		status = Status.SUCCESS
		_is_active = false
		return true

	if _target_unit.state == _target_unit.State.DEAD:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Target routing = success
	if _target_unit.state == _target_unit.State.ROUTING:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Lost all attackers = failure
	var active: int = 0
	for regiment in _attacking_units:
		if is_instance_valid(regiment) and regiment.state != regiment.State.DEAD:
			active += 1

	if active == 0:
		status = Status.FAILURE
		_is_active = false
		return true

	# Timeout after 30 seconds (target got reinforced)
	var elapsed: float = Time.get_ticks_msec() / 1000.0 - _target_acquired_time
	if elapsed > 30.0:
		status = Status.FAILURE
		_is_active = false
		return true

	return false


func abort() -> void:
	super.abort()
	_attacking_units.clear()
	_target_unit = null
