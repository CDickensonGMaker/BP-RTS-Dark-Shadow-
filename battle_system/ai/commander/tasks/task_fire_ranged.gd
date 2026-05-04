class_name TaskFireRanged
extends BTNode

## Behavior tree task for ranged combat.
## Fires at target if in range with ammo and LOS.

var commander: CommanderAI
var _fire_cooldown: float = 0.0
const FIRE_INTERVAL: float = 2.0  # Seconds between volleys

func _init(p_commander: CommanderAI) -> void:
	super._init("FireRanged")
	commander = p_commander


func tick(delta: float) -> Status:
	## Fire at target if conditions are met.

	var regiment: Node = commander.regiment
	var target = blackboard.get("target")  # Untyped to handle freed instances

	print("[RANGED AI] %s: TaskFireRanged.tick() target=%s" % [
		regiment.name if regiment else "nil",
		target.name if target else "nil"])

	# Check preconditions
	if not target or not is_instance_valid(target):
		print("[RANGED AI] %s: No valid target!" % (regiment.name if regiment else "nil"))
		return Status.FAILURE

	if target.state == Regiment.State.DEAD:
		commander.clear_target()
		return Status.FAILURE

	if regiment.current_ammo <= 0:
		print("[RANGED AI] %s: No ammo left!" % regiment.name)
		return Status.FAILURE

	if regiment.data.ballistic_skill == 0:
		return Status.FAILURE

	# Check range
	var distance: float = regiment.global_position.distance_to(target.global_position)
	var range_dist: float = regiment.data.range_distance

	# If out of range, move closer to firing position (NOT melee range)
	if distance > range_dist:
		# Calculate position at optimal firing range (80% of max range for safety)
		var optimal_range: float = range_dist * 0.8
		var dir_to_target: Vector3 = (target.global_position - regiment.global_position).normalized()
		var fire_position: Vector3 = target.global_position - dir_to_target * optimal_range

		# Issue move order if not already moving there
		if regiment.state != Regiment.State.MARCHING:
			print("[RANGED AI] %s: Out of range (%.1f > %.1f), moving to fire position" % [
				regiment.name, distance, range_dist])
			regiment.give_order(OrderType.Type.MOVE, fire_position)

		return Status.RUNNING

	# In range - fire!
	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return Status.RUNNING

	# Fire!
	print("[RANGED AI] %s: FIRING at %s (range: %.1f, ammo: %d)" % [
		regiment.name, target.name, distance, regiment.current_ammo])
	_fire_volley(target)
	_fire_cooldown = FIRE_INTERVAL

	# Success but keep attacking
	return Status.RUNNING


func _fire_volley(target: Node) -> void:
	## Fire a ranged volley at the target.
	CombatManager.fire_ranged(commander.regiment, target)
	print("[RANGED AI] %s: Volley fired!" % commander.regiment.name)

	# Apply "under fire" morale effect
	if target.has_method("get") and target.get("unit_morale"):
		target.unit_morale.set_continuous_modifier_all(
			MoraleEvent.Source.UNDER_FIRE,
			MoraleConstants.CONTINUOUS_UNDER_FIRE
		)


func reset() -> void:
	super.reset()
	_fire_cooldown = 0.0
