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

	# Don't acquire targets if routing or passive
	if commander.blackboard.get("is_routing", false):
		return Status.FAILURE

	if commander.current_stance == CommanderAI.Stance.PASSIVE:
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
	## Get maximum range for target acquisition based on stance.
	match commander.current_stance:
		CommanderAI.Stance.PASSIVE:
			return 0.0  # Don't acquire targets
		CommanderAI.Stance.DEFENSIVE:
			return 25.0  # Nearby threats only - hold position behavior
		CommanderAI.Stance.AGGRESSIVE:
			return 120.0  # Full engagement range (increased from 80)
		CommanderAI.Stance.FLANKING:
			return 100.0  # Medium range for flanking (increased from 60)
		CommanderAI.Stance.SKIRMISH:
			return 150.0  # Long range for skirmishers (increased from 100)
		_:
			return 80.0
