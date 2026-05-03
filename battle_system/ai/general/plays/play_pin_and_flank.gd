class_name PlayPinAndFlank
extends StrategicPlay

## Pin & Flank strategy.
## Uses infantry to pin enemy frontally while cavalry flanks.
## Classic Total War hammer-and-anvil tactic.
##
## Improved flanking calculates a wide arc path that goes AROUND
## enemy positions rather than directly to the flank.

const ROLE_PIN: String = "pin"
const ROLE_FLANK: String = "flank"
const ROLE_RESERVE: String = "reserve"

# Flanking parameters
const FLANK_ARC_DISTANCE: float = 40.0     # How wide the arc sweeps
const FLANK_APPROACH_DISTANCE: float = 20.0 # Final approach distance
const ENEMY_AVOIDANCE_RADIUS: float = 15.0  # Stay this far from enemies
const WAYPOINT_ARRIVAL_THRESHOLD: float = 5.0

var _primary_target: Node = null
var _pin_units: Array = []
var _flank_units: Array = []
var _flank_engaged: bool = false

# Waypoint-based flanking for each unit
var _flank_waypoints: Dictionary = {}  # Regiment -> Array[Vector3]
var _current_waypoint_index: Dictionary = {}  # Regiment -> int
var _flank_direction: int = 1  # 1 = right, -1 = left

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "Pin and Flank")


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score this play. Good when we have cavalry and aren't losing.
	var score: float = 0.0

	# Need cavalry for flanking
	if analysis.friendly_cavalry == 0:
		return -100.0  # Can't execute without cavalry

	# Need infantry to pin
	if analysis.friendly_infantry == 0:
		return -50.0

	# Good strength ratio (not desperate)
	if analysis.strength_ratio >= 0.8:
		score += 30.0

	# More effective with cavalry advantage
	if analysis.friendly_cavalry > analysis.enemy_cavalry:
		score += 20.0

	# Bonus if enemy has exposed flanks
	if analysis.flank_vulnerability_left > 5.0 or analysis.flank_vulnerability_right > 5.0:
		score += 15.0

	# Less effective if already heavily engaged
	if analysis.active_engagements > analysis.friendly_regiments.size() / 2:
		score -= 20.0

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_pin_units.clear()
	_flank_units.clear()
	_flank_waypoints.clear()
	_current_waypoint_index.clear()
	_flank_engaged = false

	# Select primary target (strongest or most central enemy)
	_primary_target = _select_primary_target(analysis)
	if not _primary_target:
		status = Status.FAILURE
		return

	# Determine best flank direction based on battlefield geometry
	_flank_direction = _choose_flank_direction(analysis)

	# Assign roles
	_assign_units(analysis)

	# Calculate wide arc waypoints for each flank unit
	_calculate_all_flank_paths(analysis)

	# Issue initial orders
	_issue_initial_orders()


func tick() -> Status:
	if not _is_active:
		return status

	# Refresh analysis
	if general_ai:
		_analysis = general_ai.analysis
		_analysis.update()

	# Check win/lose conditions
	if _check_completion():
		return status

	# Update unit orders
	_update_pin_units()
	_update_flank_units()

	return Status.RUNNING


func _select_primary_target(analysis: BattlefieldAnalysis) -> Node:
	## Select the main target to pin.
	# Prefer center-most enemy infantry
	var best_target: Node = null
	var best_score: float = -INF

	for regiment in analysis.enemy_regiments:
		var score: float = 0.0

		# Prefer infantry (can be pinned)
		if regiment.data.unit_type == UnitType.Type.INFANTRY:
			score += 20.0

		# Prefer central units
		var distance_from_center: float = absf(regiment.global_position.x - analysis.enemy_center.x)
		score -= distance_from_center * 0.5

		# Prefer stronger units (worth flanking)
		score += regiment.current_soldiers * 0.1

		if score > best_score:
			best_score = score
			best_target = regiment

	return best_target


func _assign_units(analysis: BattlefieldAnalysis) -> void:
	## Assign units to pin and flank roles.

	# Cavalry goes to flank
	for regiment in analysis.get_available_cavalry():
		_flank_units.append(regiment)
		assign_role(regiment, ROLE_FLANK)

	# Infantry goes to pin
	for regiment in analysis.get_available_infantry():
		_pin_units.append(regiment)
		assign_role(regiment, ROLE_PIN)

	# Ranged stays in reserve/support
	for regiment in analysis.friendly_regiments:
		if regiment.data.unit_type == UnitType.Type.RANGED:
			assign_role(regiment, ROLE_RESERVE)


func _issue_initial_orders() -> void:
	## Send initial orders to all units.

	# Pin units engage the target
	for regiment in _pin_units:
		issue_attack(regiment, _primary_target)

	# Flank units start moving along their waypoint path
	for regiment in _flank_units:
		var waypoints: Array = _flank_waypoints.get(regiment, [])
		if waypoints.is_empty():
			# Fallback to direct flank position
			var flank_pos: Vector3 = _calculate_flank_position(regiment)
			issue_defend(regiment, flank_pos)
		else:
			# Move to first waypoint of the arc
			issue_defend(regiment, waypoints[0])


func _choose_flank_direction(analysis: BattlefieldAnalysis) -> int:
	## Choose best flank direction (1 = right, -1 = left).
	## Considers enemy unit density on each side.

	if not _primary_target:
		return 1

	# Count enemies on each side of the target
	var target_pos: Vector3 = _primary_target.global_position
	var target_right: Vector3 = _primary_target.global_transform.basis.x.normalized()

	var enemies_left: int = 0
	var enemies_right: int = 0

	for enemy in analysis.enemy_regiments:
		if enemy == _primary_target:
			continue
		var to_enemy: Vector3 = enemy.global_position - target_pos
		to_enemy.y = 0
		var side: float = target_right.dot(to_enemy.normalized())
		if side > 0.2:
			enemies_right += 1
		elif side < -0.2:
			enemies_left += 1

	# Also consider battlefield geometry (flank vulnerabilities)
	var left_score: float = float(enemies_right) * 2.0  # Fewer enemies on left = go left
	var right_score: float = float(enemies_left) * 2.0  # Fewer enemies on right = go right

	# Add vulnerability bonus (higher vulnerability = more exposed = easier to flank)
	left_score += analysis.flank_vulnerability_left * 0.5
	right_score += analysis.flank_vulnerability_right * 0.5

	return 1 if right_score >= left_score else -1


func _calculate_all_flank_paths(analysis: BattlefieldAnalysis) -> void:
	## Calculate wide arc waypoint paths for all flank units.
	for regiment in _flank_units:
		if not is_instance_valid(regiment):
			continue
		var waypoints: Array = _calculate_wide_arc_path(regiment, analysis)
		_flank_waypoints[regiment] = waypoints
		_current_waypoint_index[regiment] = 0


func _calculate_wide_arc_path(regiment: Node, analysis: BattlefieldAnalysis) -> Array:
	## Calculate waypoints for a wide flanking arc that avoids enemies.
	## Returns Array[Vector3] of waypoints.

	if not _primary_target:
		return []

	var waypoints: Array = []
	var start_pos: Vector3 = regiment.global_position
	var target_pos: Vector3 = _primary_target.global_position

	# Get direction vectors
	var to_target: Vector3 = (target_pos - start_pos)
	to_target.y = 0
	var distance: float = to_target.length()
	to_target = to_target.normalized()

	# Perpendicular direction for the arc (left or right based on _flank_direction)
	var arc_dir: Vector3 = Vector3(-to_target.z, 0, to_target.x) * _flank_direction

	# Calculate enemy center to know which way is "behind" enemy lines
	var enemy_center: Vector3 = analysis.enemy_center
	var to_enemy_center: Vector3 = (enemy_center - start_pos).normalized()

	# WAYPOINT 1: Move away from center to start wide swing
	# Go perpendicular to engagement direction
	var waypoint1: Vector3 = start_pos + arc_dir * FLANK_ARC_DISTANCE
	waypoint1 = _adjust_for_enemies(waypoint1, analysis)
	waypoints.append(waypoint1)

	# WAYPOINT 2: Continue arc, moving forward but staying wide
	var halfway: Vector3 = start_pos + to_target * (distance * 0.5)
	var waypoint2: Vector3 = halfway + arc_dir * FLANK_ARC_DISTANCE
	waypoint2 = _adjust_for_enemies(waypoint2, analysis)
	waypoints.append(waypoint2)

	# WAYPOINT 3: Arc around to the flank/rear of target
	var target_back: Vector3 = _primary_target.global_transform.basis.z.normalized()
	target_back.y = 0
	var target_side: Vector3 = _primary_target.global_transform.basis.x.normalized() * _flank_direction
	target_side.y = 0

	# Position behind and to the side of the target
	var waypoint3: Vector3 = target_pos + target_back * 15.0 + target_side * 12.0
	waypoint3 = _adjust_for_enemies(waypoint3, analysis)
	waypoints.append(waypoint3)

	# WAYPOINT 4: Final attack position (flank/rear)
	var final_pos: Vector3 = target_pos + target_side * FLANK_APPROACH_DISTANCE
	waypoints.append(final_pos)

	return waypoints


func _adjust_for_enemies(position: Vector3, analysis: BattlefieldAnalysis) -> Vector3:
	## Adjust a position to avoid getting too close to enemies.
	var adjusted: Vector3 = position

	for enemy in analysis.enemy_regiments:
		if enemy == _primary_target:
			continue

		var to_enemy: Vector3 = enemy.global_position - position
		to_enemy.y = 0
		var dist: float = to_enemy.length()

		if dist < ENEMY_AVOIDANCE_RADIUS:
			# Push away from this enemy
			var push: Vector3 = -to_enemy.normalized() * (ENEMY_AVOIDANCE_RADIUS - dist)
			adjusted += push

	return adjusted


func _calculate_flank_position(regiment: Node) -> Vector3:
	## Get the final flank position for a regiment.
	## Used as fallback and for the charge phase.
	if not _primary_target:
		return regiment.global_position

	var target_side: Vector3 = _primary_target.global_transform.basis.x.normalized() * _flank_direction
	target_side.y = 0

	return _primary_target.global_position + target_side * FLANK_APPROACH_DISTANCE


func _update_pin_units() -> void:
	## Keep pin units engaged with target.
	if not _primary_target or not is_instance_valid(_primary_target):
		return

	for regiment in _pin_units:
		if not is_instance_valid(regiment):
			continue

		# Re-engage if not currently engaging
		if regiment.state != Regiment.State.ENGAGING:
			issue_attack(regiment, _primary_target)


func _update_flank_units() -> void:
	## Manage flanking cavalry using waypoint-based wide arc maneuver.
	if not _primary_target or not is_instance_valid(_primary_target):
		return

	for regiment in _flank_units:
		if not is_instance_valid(regiment):
			continue

		# If already engaged, keep fighting
		if regiment.state == Regiment.State.ENGAGING:
			continue

		# Get this unit's waypoints
		var waypoints: Array = _flank_waypoints.get(regiment, [])
		var current_idx: int = _current_waypoint_index.get(regiment, 0)

		# If no waypoints, use fallback
		if waypoints.is_empty():
			var angle: float = _calculate_flank_angle(regiment)
			if angle > 60.0:
				_flank_engaged = true
				issue_flank(regiment, _primary_target)
			continue

		# Check if we've reached all waypoints
		if current_idx >= waypoints.size():
			# At final position - charge!
			var angle: float = _calculate_flank_angle(regiment)
			if angle > 45.0:
				_flank_engaged = true
				issue_flank(regiment, _primary_target)
			else:
				# Not quite in position, attack anyway
				issue_attack(regiment, _primary_target)
			continue

		# Move to current waypoint
		var target_waypoint: Vector3 = waypoints[current_idx]
		var dist: float = regiment.global_position.distance_to(target_waypoint)

		if dist <= WAYPOINT_ARRIVAL_THRESHOLD:
			# Reached waypoint, advance to next
			_current_waypoint_index[regiment] = current_idx + 1
		else:
			# Move toward current waypoint
			# Use charge for final waypoint, defend for earlier ones
			if current_idx == waypoints.size() - 1:
				# Final approach - prepare for charge
				issue_attack(regiment, _primary_target)
			else:
				# Still maneuvering - move carefully
				issue_defend(regiment, target_waypoint)


func _calculate_flank_angle(regiment: Node) -> float:
	## Calculate angle of attack (0 = frontal, 90 = flank, 180 = rear).
	if not _primary_target:
		return 0.0

	var target_forward: Vector3 = -_primary_target.global_transform.basis.z.normalized()
	target_forward.y = 0

	var to_attacker: Vector3 = (regiment.global_position - _primary_target.global_position).normalized()
	to_attacker.y = 0

	var dot: float = target_forward.dot(to_attacker)
	return rad_to_deg(acos(clampf(dot, -1.0, 1.0)))


func _check_completion() -> bool:
	## Check if play is complete.

	# Target destroyed = success
	if not _primary_target or not is_instance_valid(_primary_target):
		status = Status.SUCCESS
		_is_active = false
		return true

	if _primary_target.state == Regiment.State.DEAD:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Target routing = success
	if _primary_target.state == Regiment.State.ROUTING:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Lost all units = failure
	var active_units: int = 0
	for regiment in _pin_units + _flank_units:
		if is_instance_valid(regiment) and regiment.state != Regiment.State.DEAD:
			active_units += 1

	if active_units == 0:
		status = Status.FAILURE
		_is_active = false
		return true

	return false


func abort() -> void:
	super.abort()
	_pin_units.clear()
	_flank_units.clear()
	_flank_waypoints.clear()
	_current_waypoint_index.clear()
	_primary_target = null
