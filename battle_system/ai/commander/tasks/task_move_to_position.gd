class_name TaskMoveToPosition
extends BTNode

## Behavior tree task for moving to a position.
## Can move towards target, waypoint, or flee position.

var commander: CommanderAI
var _arrival_threshold: float = 3.0

func _init(p_commander: CommanderAI) -> void:
	super._init("MoveToPosition")
	commander = p_commander


func tick(_delta: float) -> Status:
	## Move towards the target or destination.

	var regiment: Node = commander.regiment
	if not regiment:
		return Status.FAILURE

	# If already in melee combat, don't issue new move orders
	if regiment.state == Regiment.State.ENGAGING:
		return Status.SUCCESS

	# Determine destination
	var destination: Vector3 = _get_destination()
	if destination == Vector3.ZERO:
		return Status.FAILURE

	# Check if we've arrived
	var distance: float = regiment.global_position.distance_to(destination)
	if distance <= _arrival_threshold:
		return Status.SUCCESS

	# Issue move order if not already moving there
	if regiment.state != Regiment.State.MARCHING:
		commander.issue_move_order(destination)

	return Status.RUNNING


func _get_destination() -> Vector3:
	## Determine where to move.

	# If we have a target, move towards it
	# NOTE: blackboard may return a freed instance - check validity BEFORE accessing
	var target: Variant = blackboard.get("target")
	if target != null and is_instance_valid(target) and target is Node:
		# Verify regiment is also valid before calculating
		if not commander.regiment or not is_instance_valid(commander.regiment):
			return Vector3.ZERO

		# Get engagement distance based on unit type
		var engage_dist: float = _get_engagement_distance()

		# Move to engagement range
		var dir: Vector3 = (target.global_position - commander.regiment.global_position).normalized()
		var target_dist: float = commander.regiment.global_position.distance_to(target.global_position)

		if target_dist > engage_dist:
			return target.global_position - dir * engage_dist
		else:
			return target.global_position
	elif target != null and not is_instance_valid(target):
		# Target was freed - clear it from blackboard to prevent future errors
		blackboard.set("target", null)
		commander.clear_target()

	# Check for explicit destination
	var dest: Variant = blackboard.get("destination")
	if dest is Vector3 and dest != Vector3.ZERO:
		return dest

	return Vector3.ZERO


func _get_engagement_distance() -> float:
	## Get optimal engagement distance based on unit type and stance.
	## Ranged units prioritize firing from max range ASAP.
	var regiment: Node = commander.regiment

	# Ranged/Artillery units stay at max range (fire ASAP, don't close distance)
	if regiment.data.ballistic_skill > 0 and regiment.current_ammo > 0:
		var is_ranged_type: bool = regiment.data.unit_type == UnitType.Type.RANGED
		var is_artillery_type: bool = regiment.data.unit_type == UnitType.Type.ARTILLERY
		if is_ranged_type or is_artillery_type:
			return regiment.data.range_distance * 0.95  # Fire from near max range
		else:
			return regiment.data.range_distance * 0.8  # Hybrid units slightly closer

	# Melee units close in - must be INSIDE TaskEngageMelee.MELEE_RANGE (7.0)
	# to prevent deadlock where infantry stops outside engagement distance
	return 5.0
