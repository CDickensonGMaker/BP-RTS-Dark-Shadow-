class_name PlayRallyPoint
extends StrategicPlay

## Rally Point strategy.
## Designate a safe rally position and gather routing units there.
## Used to recover broken units and reform the army.

const ROLE_RALLYING: String = "rallying"
const ROLE_SCREENING: String = "screening"

const RALLY_SAFE_DISTANCE: float = 40.0  # Distance from battle for rally point
const RALLY_RADIUS: float = 15.0  # Units within this radius are "rallied"
const MIN_ROUTING_TO_ACTIVATE: int = 1  # Minimum routing units to trigger

var _rally_position: Vector3 = Vector3.ZERO
var _rallying_units: Array = []
var _screening_units: Array = []
var _units_rallied: Dictionary = {}  # Regiment -> bool (has reached rally point)

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "Rally Point")


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score this play. High when multiple units are routing.
	var score: float = 0.0

	# Primary trigger: routing units
	if analysis.routing_friendly >= MIN_ROUTING_TO_ACTIVATE:
		score += analysis.routing_friendly * 25.0
	else:
		return -50.0  # No routing units = don't use this play

	# More routing = more important to rally
	var routing_ratio: float = float(analysis.routing_friendly) / maxf(1.0, float(analysis.friendly_regiments.size()))
	score += routing_ratio * 30.0

	# Good when we still have non-routing units to screen
	var non_routing: int = analysis.friendly_regiments.size() - analysis.routing_friendly
	if non_routing > 0:
		score += 15.0  # Can provide screening force

	# Less effective if army is completely broken
	if routing_ratio > 0.8:
		score -= 20.0  # Too many routing, retreat might be better

	# Good when morale isn't completely destroyed (can recover)
	if analysis.average_friendly_morale > 20.0:
		score += 10.0
	else:
		score -= 15.0  # Morale too low to rally effectively

	# Better when not all units are engaged (some can screen)
	if analysis.active_engagements < analysis.friendly_regiments.size():
		score += 10.0

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_rallying_units.clear()
	_screening_units.clear()
	_units_rallied.clear()

	# Calculate safe rally position
	_calculate_rally_position(analysis)

	# Assign units to roles
	_assign_units(analysis)

	# Issue initial orders
	_issue_rally_orders()


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

	# Check for new routing units
	_check_new_routing_units()

	# Update rallying units
	_update_rallying_units()

	# Update screening units
	_update_screening_units()

	return Status.RUNNING


func _calculate_rally_position(analysis: BattlefieldAnalysis) -> void:
	## Find a safe position for units to rally.

	# Rally point is behind friendly center, away from enemy
	var retreat_dir: Vector3 = Vector3.ZERO

	if analysis.enemy_center != Vector3.ZERO and analysis.friendly_center != Vector3.ZERO:
		retreat_dir = (analysis.friendly_center - analysis.enemy_center).normalized()
	else:
		retreat_dir = Vector3.BACK

	retreat_dir.y = 0

	# Place rally point behind our lines
	_rally_position = analysis.friendly_center + retreat_dir * RALLY_SAFE_DISTANCE

	# Ensure rally point is away from active engagements
	# Check for enemies near the rally point and adjust if needed
	var nearest_enemy_dist: float = INF
	for enemy in analysis.enemy_regiments:
		var dist: float = _rally_position.distance_to(enemy.global_position)
		nearest_enemy_dist = minf(nearest_enemy_dist, dist)

	# If enemies too close, push rally point further back
	while nearest_enemy_dist < RALLY_SAFE_DISTANCE / 2.0:
		_rally_position += retreat_dir * 10.0
		nearest_enemy_dist = INF
		for enemy in analysis.enemy_regiments:
			var dist: float = _rally_position.distance_to(enemy.global_position)
			nearest_enemy_dist = minf(nearest_enemy_dist, dist)

		# Safety limit
		if _rally_position.distance_to(analysis.friendly_center) > 200.0:
			break


func _assign_units(analysis: BattlefieldAnalysis) -> void:
	## Assign routing units to rally, others to screen.

	for regiment in analysis.friendly_regiments:
		if regiment.state == Regiment.State.ROUTING:
			_rallying_units.append(regiment)
			assign_role(regiment, ROLE_RALLYING)
			_units_rallied[regiment] = false
		elif regiment.state != Regiment.State.DEAD:
			# Non-routing units provide screening
			_screening_units.append(regiment)
			assign_role(regiment, ROLE_SCREENING)


func _issue_rally_orders() -> void:
	## Issue orders to start the rally.

	# Send routing units to rally point
	for regiment in _rallying_units:
		if not is_instance_valid(regiment):
			continue

		# Direct routing units to rally position
		_send_to_rally_point(regiment)

	# Screening units hold position or defend approaches
	for regiment in _screening_units:
		if not is_instance_valid(regiment):
			continue

		# Position between enemy and rally point
		var screen_pos: Vector3 = _rally_position.lerp(
			_analysis.enemy_center if _analysis.enemy_center != Vector3.ZERO else regiment.global_position,
			0.4  # 40% toward enemy from rally point
		)

		issue_defend(regiment, screen_pos)

		var commander: CommanderAI = general_ai.get_commander(regiment)
		if commander:
			commander.set_stance(CommanderAI.Stance.DEFENSIVE)


func _send_to_rally_point(regiment: Node) -> void:
	## Send a unit to the rally point.
	if not is_instance_valid(regiment):
		return

	# Use general_ai to issue order through CommanderAI
	var commander: CommanderAI = general_ai.get_commander(regiment)
	if commander:
		# Set rallying state
		commander.receive_strategic_order({
			"type": "RALLY",
			"position": _rally_position,
		})

	# Also direct the regiment
	issue_defend(regiment, _rally_position)


func _check_new_routing_units() -> void:
	## Check for any new units that started routing and add them to rally.

	for regiment in _analysis.friendly_regiments:
		if regiment.state == Regiment.State.ROUTING:
			if regiment not in _rallying_units:
				_rallying_units.append(regiment)
				assign_role(regiment, ROLE_RALLYING)
				_units_rallied[regiment] = false
				_send_to_rally_point(regiment)

				# Remove from screening if it was there
				if regiment in _screening_units:
					_screening_units.erase(regiment)


func _update_rallying_units() -> void:
	## Update routing units moving to rally point.

	for regiment in _rallying_units:
		if not is_instance_valid(regiment):
			continue

		if regiment.state == Regiment.State.DEAD:
			continue

		# Check if unit has reached rally point
		var dist: float = regiment.global_position.distance_to(_rally_position)

		if dist <= RALLY_RADIUS:
			# Unit has reached rally point
			if not _units_rallied.get(regiment, false):
				_units_rallied[regiment] = true

				# Try to set unit to RALLYING state
				if regiment.state == Regiment.State.ROUTING:
					regiment.set_state(Regiment.State.RALLYING)

				# Apply morale recovery boost
				_boost_morale(regiment)
		else:
			# Still moving to rally point
			if regiment.state == Regiment.State.IDLE:
				_send_to_rally_point(regiment)


func _boost_morale(regiment: Node) -> void:
	## Boost morale of a unit that reached the rally point.
	if not is_instance_valid(regiment):
		return

	# Apply morale bonus for successful rally
	var morale_boost: float = 20.0

	# Use morale system if available
	if regiment.unit_morale:
		regiment.unit_morale.apply_morale_modifier(morale_boost)
	else:
		regiment.current_morale = minf(100.0, regiment.current_morale + morale_boost)


func _update_screening_units() -> void:
	## Keep screening units between enemy and rally point.

	for regiment in _screening_units:
		if not is_instance_valid(regiment):
			continue

		if regiment.state == Regiment.State.DEAD:
			continue

		# If unit started routing, move to rallying
		if regiment.state == Regiment.State.ROUTING:
			_rallying_units.append(regiment)
			_screening_units.erase(regiment)
			assign_role(regiment, ROLE_RALLYING)
			_units_rallied[regiment] = false
			_send_to_rally_point(regiment)
			continue

		var commander: CommanderAI = general_ai.get_commander(regiment)
		if not commander:
			continue

		# Find nearby enemies approaching rally point
		var nearest_enemy: Node = AIAutoload.query_nearest_enemy(
			regiment.global_position, 25.0,
			0 if regiment.is_player_controlled else 1
		)

		if nearest_enemy:
			# Engage to slow enemy advance
			commander.set_stance(CommanderAI.Stance.DEFENSIVE)
			commander.set_target(nearest_enemy)
		elif regiment.state == Regiment.State.IDLE:
			# Hold screening position
			issue_hold(regiment)


func _check_completion() -> bool:
	## Check if rally is complete.

	# Count rallied vs total
	var rallied_count: int = 0
	var total_routing: int = 0

	for regiment in _rallying_units:
		if not is_instance_valid(regiment) or regiment.state == Regiment.State.DEAD:
			rallied_count += 1
			total_routing += 1
			continue

		total_routing += 1

		# Unit is rallied if at rally point and no longer routing
		if _units_rallied.get(regiment, false) and regiment.state != Regiment.State.ROUTING:
			rallied_count += 1

	# Success: all routing units rallied
	if total_routing > 0 and rallied_count >= total_routing:
		status = Status.SUCCESS
		_is_active = false
		return true

	# No more routing units in analysis = success
	if _analysis.routing_friendly == 0 and get_elapsed_time() > 5.0:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Failure: all units dead
	var all_dead: bool = true
	for regiment in _rallying_units:
		if is_instance_valid(regiment) and regiment.state != Regiment.State.DEAD:
			all_dead = false
			break
	for regiment in _screening_units:
		if is_instance_valid(regiment) and regiment.state != Regiment.State.DEAD:
			all_dead = false
			break

	if all_dead:
		status = Status.FAILURE
		_is_active = false
		return true

	# Timeout after 45 seconds
	if get_elapsed_time() > 45.0:
		# Partial success if some rallied
		if rallied_count > 0:
			status = Status.SUCCESS
		else:
			status = Status.FAILURE
		_is_active = false
		return true

	return false


func abort() -> void:
	super.abort()
	_rallying_units.clear()
	_screening_units.clear()
	_units_rallied.clear()
