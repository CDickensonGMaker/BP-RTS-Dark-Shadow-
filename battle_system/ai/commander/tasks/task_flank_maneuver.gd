class_name TaskFlankManeuver
extends BTNode

## Behavior tree task for flanking maneuvers.
## Uses waypoint-based wide arc for proper flanking approach.
## Waypoints are recalculated if target moves significantly (dynamic flanking).

var commander: CommanderAI
var _flank_waypoints: Array = []
var _current_waypoint: int = 0
var _has_reached_flank: bool = false
var _last_target_position: Vector3 = Vector3.ZERO  # Track target movement

const FLANK_DISTANCE: float = 12.0
const ARRIVAL_THRESHOLD: float = 5.0
const ARC_DISTANCE: float = 20.0  # Reduced from 25 - tighter arc for less rubber-banding
const TARGET_MOVE_THRESHOLD: float = 8.0  # Recalculate waypoints if target moves this far

func _init(p_commander: CommanderAI) -> void:
	super._init("FlankManeuver")
	commander = p_commander


func tick(_delta: float) -> Status:
	## Execute flanking maneuver using wide arc approach.

	# Validate target - check for freed instances before accessing
	var target_ref: Variant = blackboard.get("target")
	if target_ref == null or not is_instance_valid(target_ref):
		reset()
		return Status.FAILURE

	var target: Node = target_ref as Node
	if not target:
		reset()
		return Status.FAILURE

	if target.state == Regiment.State.DEAD:
		commander.clear_target()
		reset()
		return Status.FAILURE

	var regiment: Node = commander.regiment
	if not regiment or not is_instance_valid(regiment):
		reset()
		return Status.FAILURE

	# Calculate waypoints if we don't have any
	if _flank_waypoints.is_empty():
		_flank_waypoints = commander.target_selector.calculate_wide_flank_waypoints(
			regiment, target, ARC_DISTANCE
		)
		_current_waypoint = 0
		_last_target_position = target.global_position
	else:
		# DYNAMIC WAYPOINTS: Recalculate if target has moved significantly
		var target_moved: float = target.global_position.distance_to(_last_target_position)
		if target_moved > TARGET_MOVE_THRESHOLD and not _has_reached_flank:
			# Target moved - recalculate waypoints from current position
			_flank_waypoints = commander.target_selector.calculate_wide_flank_waypoints(
				regiment, target, ARC_DISTANCE
			)
			# Keep current waypoint index but ensure it's valid
			_current_waypoint = mini(_current_waypoint, _flank_waypoints.size() - 1)
			_last_target_position = target.global_position

	# Follow waypoints
	if _current_waypoint < _flank_waypoints.size():
		var target_wp: Vector3 = _flank_waypoints[_current_waypoint]
		var dist: float = regiment.global_position.distance_to(target_wp)

		if dist <= ARRIVAL_THRESHOLD:
			_current_waypoint += 1
		else:
			# Move toward waypoint
			commander.issue_move_order(target_wp)
			return Status.RUNNING

	# Reached final position - check angle and attack
	_has_reached_flank = true
	var distance_to_target: float = regiment.global_position.distance_to(target.global_position)

	if distance_to_target <= 5.0:
		# Apply flank attack morale damage
		_apply_flank_morale(target)

		# Engage
		regiment.set_state(Regiment.State.ENGAGING)
		reset()
		return Status.SUCCESS

	# Move to engage with charge
	commander.issue_charge_order(target)
	return Status.RUNNING


func _calculate_flank_position(target: Node) -> Vector3:
	## Calculate best position to attack from flank (fallback).
	return commander.target_selector.get_best_flank_position(
		commander.regiment, target, FLANK_DISTANCE
	)


func _apply_flank_morale(target: Node) -> void:
	## Apply flank attack morale damage.
	if not is_instance_valid(target):
		return
	if not is_instance_valid(commander) or not is_instance_valid(commander.regiment):
		return

	if target.has_method("get") and target.get("unit_morale"):
		var angle: float = commander.target_selector._calculate_attack_angle(
			commander.regiment, target
		)

		if angle > 135.0:
			# Rear attack
			var event: MoraleEvent = MoraleEvent.rear_attack(commander.regiment.global_position)
			target.unit_morale.apply_event_to_all(event)
		elif angle > 90.0:
			# Flank attack
			var event: MoraleEvent = MoraleEvent.flank_attack(commander.regiment.global_position)
			target.unit_morale.apply_event_to_all(event)


func reset() -> void:
	super.reset()
	_flank_waypoints.clear()
	_current_waypoint = 0
	_has_reached_flank = false
	_last_target_position = Vector3.ZERO
