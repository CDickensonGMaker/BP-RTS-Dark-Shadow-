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

	# DEBUG: Show all ranged units attempting to fire
	var unit_name: String = regiment.data.regiment_name if regiment.data else regiment.name
	var has_firing_component: bool = regiment.firing != null

	# DEBUG: Extra verbose for crossbow units to diagnose firing issues
	var is_crossbow: bool = regiment.data and regiment.data.weapon_class == RegimentData.WeaponClass.CROSSBOW
	if is_crossbow and Engine.get_process_frames() % 30 == 0:
		print("[CROSSBOW DEBUG] %s: tick() called, target=%s, ammo=%d, firing_comp=%s" % [
			unit_name,
			target.data.regiment_name if target and is_instance_valid(target) and target.data else "NONE",
			regiment.current_ammo,
			"YES" if has_firing_component else "NO"
		])

	# Check preconditions
	if not target or not is_instance_valid(target):
		if is_crossbow:
			print("[CROSSBOW DEBUG] %s: FAILURE - no valid target" % unit_name)
		return Status.FAILURE

	if target.state == Regiment.State.DEAD:
		commander.clear_target()
		return Status.FAILURE

	if regiment.current_ammo <= 0:
		print("[RANGED DEBUG] %s: No ammo (current_ammo=%d)" % [unit_name, regiment.current_ammo])
		return Status.FAILURE

	if regiment.data.ballistic_skill == 0:
		print("[RANGED DEBUG] %s: No ballistic_skill" % unit_name)
		return Status.FAILURE

	# Update kite cooldown
	_kite_cooldown -= delta

	# Check if this is artillery (stationary weapon - never moves to engage)
	var is_artillery: bool = regiment.data and regiment.data.unit_type == UnitType.Type.ARTILLERY

	# DEBUG: Track artillery behavior
	if is_artillery:
		var state_name := str(regiment.state)
		if regiment.state == Regiment.State.IDLE: state_name = "IDLE"
		elif regiment.state == Regiment.State.MARCHING: state_name = "MARCHING"
		elif regiment.state == Regiment.State.ENGAGING: state_name = "ENGAGING"
		print("[ARTILLERY DEBUG] %s: state=%s, target=%s, distance=%.1f, range=%.1f" % [
			regiment.data.regiment_name if regiment.data else "?",
			state_name,
			target.data.regiment_name if target and target.data else "?",
			regiment.global_position.distance_to(target.global_position) if target else -1,
			regiment.data.range_distance if regiment.data else 0
		])

	# ARTILLERY FIX: Artillery should NEVER move. If it's marching (e.g. from ATTACK_MOVE order), stop it immediately.
	if is_artillery and regiment.state == Regiment.State.MARCHING:
		print("[ARTILLERY DEBUG] %s: STOPPING - was marching, now idle" % (regiment.data.regiment_name if regiment.data else "?"))
		regiment.leader.stop_movement()
		regiment.set_state(Regiment.State.IDLE)

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
		# ARTILLERY STAYS PUT: Artillery never moves to engage - waits for targets to enter range
		if is_artillery:
			# Face target even when out of range (important for crew sprite direction)
			var aim_direction: Vector3 = (target.global_position - regiment.global_position).normalized()
			aim_direction.y = 0
			if aim_direction.length_squared() > 0.01:
				regiment.set_facing_direction(aim_direction)
			# Stay in place and wait - target is out of range
			return Status.RUNNING

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
		# DEBUG: Log ALL ranged units firing
		print("[RANGED FIRE] %s: FIRING %d shots at %s (ammo=%d, firing_comp=%s)" % [
			regiment.data.regiment_name if regiment.data else regiment.name,
			shots_ready,
			target.data.regiment_name if target and target.data else target.name,
			regiment.current_ammo,
			"yes" if regiment.firing else "LEGACY"
		])
		_fire_volley(target, shots_ready)

	# Success but keep attacking
	return Status.RUNNING


func _tick_firing(regiment: Node, delta: float) -> int:
	## Tick the firing component and return shots ready to fire.
	## Falls back to legacy cooldown for regiments without firing component.
	var unit_name: String = regiment.data.regiment_name if regiment.data else regiment.name

	# Use RegimentFiring if available
	if regiment.firing and regiment.firing.has_method("tick"):
		var shots: int = regiment.firing.tick(delta)
		# DEBUG: Track firing component state for ALL ranged units (every 60 frames to reduce spam)
		if Engine.get_process_frames() % 60 == 0:
			var progress: float = regiment.firing.get_reload_progress() if regiment.firing.has_method("get_reload_progress") else -1.0
			var pattern: String = regiment.firing.get_fire_pattern_name() if regiment.firing.has_method("get_fire_pattern_name") else "?"
			print("[FIRING TICK] %s: pattern=%s, progress=%.2f, shots=%d" % [
				unit_name, pattern, progress, shots
			])
		return shots

	# Legacy fallback - single cooldown for entire regiment
	# DEBUG: Log legacy fallback usage
	if Engine.get_process_frames() % 120 == 0:
		print("[FIRING TICK] %s: LEGACY mode (no firing component), cooldown=%.2f" % [
			unit_name, _legacy_fire_cooldown
		])

	_legacy_fire_cooldown -= delta
	if _legacy_fire_cooldown <= 0:
		_legacy_fire_cooldown = _get_legacy_reload_time(regiment)
		# Legacy fires all soldiers at once
		print("[FIRING TICK] %s: LEGACY volley ready, firing %d shots" % [unit_name, regiment.current_soldiers])
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

	# Mark that we've fired (for AIMING/RELOADING state tracking)
	if regiment.firing and regiment.firing.has_method("mark_shot_fired"):
		regiment.firing.mark_shot_fired()


func reset() -> void:
	super.reset()
	_legacy_fire_cooldown = 0.0
	_kite_cooldown = 0.0
	# Reset firing component if available
	if commander and commander.regiment and commander.regiment.firing:
		if commander.regiment.firing.has_method("reset"):
			commander.regiment.firing.reset()
