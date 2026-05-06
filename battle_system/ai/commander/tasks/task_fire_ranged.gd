class_name TaskFireRanged
extends BTNode

## Behavior tree task for ranged combat.
## Fires at target if in range with ammo and LOS.
## Includes kiting behavior - retreats when enemies approach.

var commander: CommanderAI
var _fire_cooldown: float = 0.0

# Fire intervals based on fire mode (Stainless Steel pattern)
const VOLLEY_FIRE_INTERVAL: float = 1.5  # Archers: faster, less accurate volleys
const DIRECT_FIRE_INTERVAL: float = 3.0  # Skirmishers: slower, accurate shots

# Kiting constants - archers retreat when enemies get too close
const DANGER_DISTANCE: float = 20.0  # Start kiting when enemy this close
const KITE_DISTANCE: float = 15.0    # How far to retreat when kiting
const KITE_COOLDOWN: float = 1.5     # Prevent spam retreating
var _kite_cooldown: float = 0.0

func _init(p_commander: CommanderAI) -> void:
	super._init("FireRanged")
	commander = p_commander


func tick(delta: float) -> Status:
	## Fire at target if conditions are met.

	var regiment: Node = commander.regiment
	var target = blackboard.get("target")  # Untyped to handle freed instances

	# Check preconditions
	if not target or not is_instance_valid(target):
		return Status.FAILURE

	if target.state == Regiment.State.DEAD:
		commander.clear_target()
		return Status.FAILURE

	if regiment.current_ammo <= 0:
		return Status.FAILURE

	if regiment.data.ballistic_skill == 0:
		return Status.FAILURE

	# Update kite cooldown
	_kite_cooldown -= delta

	# Check for approaching enemies - kite away if too close (SKIRMISH behavior)
	if commander.current_stance == CommanderAI.Stance.SKIRMISH and regiment.state != Regiment.State.ENGAGING:
		var nearest_enemy = regiment._find_nearest_enemy()
		if nearest_enemy and is_instance_valid(nearest_enemy):
			var enemy_dist: float = regiment.global_position.distance_to(nearest_enemy.global_position)
			if enemy_dist < DANGER_DISTANCE and _kite_cooldown <= 0:
				# Kite away from enemy
				var retreat_dir: Vector3 = (regiment.global_position - nearest_enemy.global_position).normalized()
				retreat_dir.y = 0  # Keep horizontal
				var kite_pos: Vector3 = regiment.global_position + retreat_dir * KITE_DISTANCE
				# Clamp to map bounds (configurable via AIAutoload)
				if AIAutoload:
					kite_pos = AIAutoload.clamp_to_map(kite_pos)
				regiment.give_order(OrderType.Type.MOVE, kite_pos)
				_kite_cooldown = KITE_COOLDOWN
				return Status.RUNNING

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
			regiment.give_order(OrderType.Type.MOVE, fire_position)

		return Status.RUNNING

	# In range - fire!
	_fire_cooldown -= delta
	if _fire_cooldown > 0.0:
		return Status.RUNNING

	# Fire!
	_fire_volley(target)

	# Set cooldown based on fire mode (Stainless Steel pattern)
	if regiment.data and regiment.data.fire_mode == RegimentData.FireMode.DIRECT:
		_fire_cooldown = DIRECT_FIRE_INTERVAL  # Slower, more accurate
	else:
		_fire_cooldown = VOLLEY_FIRE_INTERVAL  # Faster volley

	# Success but keep attacking
	return Status.RUNNING


func _fire_volley(target: Node) -> void:
	## Fire a ranged volley at the target.
	if not is_instance_valid(target) or not is_instance_valid(commander.regiment):
		return

	CombatManager.fire_ranged(commander.regiment, target)

	# Apply "under fire" morale effect
	if target.has_method("get") and target.get("unit_morale"):
		target.unit_morale.set_continuous_modifier_all(
			MoraleEvent.Source.UNDER_FIRE,
			MoraleConstants.CONTINUOUS_UNDER_FIRE
		)


func reset() -> void:
	super.reset()
	_fire_cooldown = 0.0
	_kite_cooldown = 0.0
