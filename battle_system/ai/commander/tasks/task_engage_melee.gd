class_name TaskEngageMelee
extends BTNode

## Behavior tree task for melee combat.
## Handles charging and sustained melee engagement.

var commander: CommanderAI
const MELEE_RANGE: float = 7.0  # Slightly larger than MeleeArea radius (6.0) to stop before collision
const CHARGE_RANGE: float = 15.0
const DEFENSIVE_ENGAGE_RANGE: float = 18.0  # Auto-engage enemies within this range when DEFENSIVE

func _init(p_commander: CommanderAI) -> void:
	super._init("EngageMelee")
	commander = p_commander


func tick(_delta: float) -> Status:
	## Engage target in melee combat.

	# Validate target - check for freed instances before accessing properties
	var target_ref: Variant = blackboard.get("target")
	if target_ref == null or not is_instance_valid(target_ref):
		return Status.FAILURE

	var target: Node = target_ref as Node
	if not target:
		return Status.FAILURE

	if target.state == Regiment.State.DEAD:
		commander.clear_target()
		return Status.FAILURE

	var regiment: Node = commander.regiment
	if not regiment or not is_instance_valid(regiment):
		return Status.FAILURE

	var distance: float = regiment.global_position.distance_to(target.global_position)

	# Already engaged? Don't issue any new orders - let combat resolve
	if regiment.state == Regiment.State.ENGAGING:
		return Status.RUNNING

	# In melee range - stop movement and engage
	if distance <= MELEE_RANGE:
		# Stop movement immediately before engaging
		regiment.leader.stop_movement()
		regiment.set_state(Regiment.State.ENGAGING)
		# Also stop the target if they're an enemy
		if target.is_player_controlled != regiment.is_player_controlled:
			target.leader.stop_movement()
			if target.state != Regiment.State.ENGAGING:
				target.set_state(Regiment.State.ENGAGING)
		# Begin melee combat
		CombatManager.begin_melee(regiment, target)
		return Status.RUNNING

	# DEFENSIVE STANCE - hold position, only engage if enemy comes close
	# Per game bible: "Holds position, will attack threats approaching"
	if commander.current_stance == CommanderAI.Stance.DEFENSIVE:
		if distance <= DEFENSIVE_ENGAGE_RANGE:
			# Enemy close enough - short move to engage
			if regiment.state != Regiment.State.MARCHING:
				commander.issue_move_order(target.global_position)
			return Status.RUNNING
		else:
			# Enemy too far - hold position, clear target, wait for them to approach
			commander.clear_target()
			return Status.FAILURE

	# In charge range - charge! (only for non-DEFENSIVE stances)
	if distance <= CHARGE_RANGE and regiment.data.charge_bonus > 0:
		_initiate_charge(target)
		return Status.RUNNING

	# Need to get closer - but only if not already marching toward target
	if regiment.state != Regiment.State.MARCHING:
		commander.issue_move_order(target.global_position)
	return Status.RUNNING


func _initiate_charge(target: Node) -> void:
	## Begin a charge towards the target.
	if not is_instance_valid(target):
		return

	var regiment: Node = commander.regiment
	if not regiment or not is_instance_valid(regiment):
		return

	# Apply charge morale effect to enemy
	if target.has_method("get") and target.get("unit_morale"):
		var is_cavalry: bool = regiment.data.unit_type == UnitType.Type.CAVALRY
		if is_cavalry:
			var event: MoraleEvent = MoraleEvent.cavalry_charge(regiment.global_position)
			target.unit_morale.apply_event_to_all(event)
		else:
			var event: MoraleEvent = MoraleEvent.infantry_charge(regiment.global_position)
			target.unit_morale.apply_event_to_all(event)

	# Issue charge order
	commander.issue_charge_order(target)
