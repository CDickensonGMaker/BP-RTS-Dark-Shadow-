class_name TaskFireRanged
extends BTNode

## Behavior tree task for ranged combat.
## Uses RegimentFiring component for per-soldier firing (24 archers = 24 arrows).
## Each soldier reloads independently (STAGGER) or together (VOLLEY) based on weapon.
## Includes kiting behavior - retreats when enemies approach.

const WeaponClassDataScript = preload("res://battle_system/data/weapon_class_data.gd")

var commander: CommanderAI

# Legacy fallback for regiments without firing component
var _legacy_fire_cooldown: float = 0.0
const LEGACY_FIRE_INTERVAL: float = 3.0

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
	## Per-soldier firing: each soldier's shot fires when their reload completes.

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

	# Check for approaching enemies - ranged units kite away if too close
	var is_ranged_unit: bool = regiment.data and regiment.data.unit_type == UnitType.Type.RANGED
	if is_ranged_unit and regiment.state != Regiment.State.ENGAGING:
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

	# If out of range, move to just within max range (fire ASAP from max distance)
	if distance > range_dist:
		# Fire from near max range (95%) - prioritize shooting over closing distance
		var optimal_range: float = range_dist * 0.95
		var dir_to_target: Vector3 = (target.global_position - regiment.global_position).normalized()
		var fire_position: Vector3 = target.global_position - dir_to_target * optimal_range

		# ALL ranged units should move to fire position, not melee range
		# This overrides any ATTACK_MOVE order that would take them past firing range
		var current_dest: Vector3 = regiment.leader.target_position if regiment.leader else Vector3.ZERO
		var dest_is_wrong: bool = current_dest.distance_to(fire_position) > 5.0

		# Issue move order if not marching OR if marching to wrong destination (toward melee)
		if regiment.state != Regiment.State.MARCHING or dest_is_wrong:
			regiment.give_order(OrderType.Type.MOVE, fire_position)

		return Status.RUNNING

	# IN RANGE - stop moving and fire immediately!
	# If unit is marching (e.g. from ATTACK_MOVE order), stop them so they can shoot
	if regiment.state == Regiment.State.MARCHING:
		regiment.leader.stop_movement()
		regiment.set_state(Regiment.State.IDLE)

	# Face toward target when firing (critical for LOS cone and sprite direction)
	var fire_direction: Vector3 = (target.global_position - regiment.global_position).normalized()
	fire_direction.y = 0
	if fire_direction.length_squared() > 0.01:
		regiment.set_facing_direction(fire_direction)

	# Tick firing system and fire ready shots
	var shots_ready: int = _tick_firing(regiment, delta)

	if shots_ready > 0:
		_fire_volley(target, shots_ready)

	# Success but keep attacking
	return Status.RUNNING


func _tick_firing(regiment: Node, delta: float) -> int:
	## Tick the firing component and return shots ready to fire.
	## Falls back to legacy cooldown for regiments without firing component.

	# Use RegimentFiring if available
	if regiment.firing and regiment.firing.has_method("tick"):
		return regiment.firing.tick(delta)

	# Legacy fallback - single cooldown for entire regiment
	_legacy_fire_cooldown -= delta
	if _legacy_fire_cooldown <= 0:
		_legacy_fire_cooldown = _get_legacy_reload_time(regiment)
		# Legacy fires all soldiers at once
		return regiment.current_soldiers

	return 0


func _get_legacy_reload_time(regiment: Node) -> float:
	## Returns the reload time for legacy regiments without firing component.
	if not regiment.data:
		return LEGACY_FIRE_INTERVAL

	var weapon_class: int = regiment.data.weapon_class
	if weapon_class != RegimentData.WeaponClass.NONE:
		return WeaponClassDataScript.get_reload_time(weapon_class, regiment.data)

	return LEGACY_FIRE_INTERVAL


func _fire_volley(target: Node, shot_count: int) -> void:
	## Fire projectiles at the target.
	## Uses fire_ranged_multi for per-soldier firing.
	if not is_instance_valid(target) or not is_instance_valid(commander.regiment):
		return

	var regiment = commander.regiment

	# Use multi-shot function for per-soldier firing
	CombatManager.fire_ranged_multi(regiment, target, shot_count)


func reset() -> void:
	super.reset()
	_legacy_fire_cooldown = 0.0
	_kite_cooldown = 0.0
	# Reset firing component if available
	if commander and commander.regiment and commander.regiment.firing:
		if commander.regiment.firing.has_method("reset"):
			commander.regiment.firing.reset()
