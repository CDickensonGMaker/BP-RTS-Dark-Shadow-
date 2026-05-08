class_name TaskAcquireTarget
extends BTNode

## Behavior tree task for acquiring a target.
## Uses TargetSelector to find the best enemy to attack.

var commander: CommanderAI

func _init(p_commander: CommanderAI) -> void:
	super._init("AcquireTarget")
	commander = p_commander


func tick(_delta: float) -> Status:
	## Try to find a new target.

	# Don't acquire targets if routing or withdrawing
	if commander.blackboard.get("is_routing", false):
		return Status.FAILURE

	if commander.current_stance == CommanderAI.Stance.WITHDRAWING:
		return Status.FAILURE

	# Get enemy candidates
	if not AIAutoload:
		return Status.FAILURE
	var candidates: Array = AIAutoload.get_enemy_regiments(commander._faction)

	if candidates.is_empty():
		return Status.FAILURE

	# Filter by distance based on stance
	var max_range: float = _get_acquisition_range()

	# Use target selector
	var best_target: Node = commander.target_selector.select_best_target(
		commander.regiment, candidates, max_range
	)

	if best_target:
		commander.set_target(best_target)
		blackboard["target"] = best_target
		return Status.SUCCESS

	return Status.FAILURE


func _get_acquisition_range() -> float:
	## Get maximum range for target acquisition based on stance and unit type.
	var base_range: float = 0.0

	match commander.current_stance:
		CommanderAI.Stance.DEFENSIVE:
			base_range = 25.0  # Nearby threats only - hold position behavior
		CommanderAI.Stance.AGGRESSIVE:
			base_range = 120.0  # Full engagement range
		CommanderAI.Stance.WITHDRAWING:
			return 0.0  # Don't acquire targets while withdrawing
		_:
			base_range = 80.0

	# Ranged units get extended range based on their weapon range
	if commander.regiment and commander.regiment.data:
		if commander.regiment.data.ballistic_skill > 0 and commander.regiment.current_ammo > 0:
			var weapon_range: float = commander.regiment.data.range_distance
			base_range = maxf(base_range, weapon_range)

	return base_range
