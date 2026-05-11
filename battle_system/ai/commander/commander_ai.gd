class_name CommanderAI
extends RefCounted

## Regiment-level tactical AI.
## Uses behavior trees to make decisions.
## Manages stance, targeting, and movement orders.
##
## Usage:
##   var commander = CommanderAI.new(regiment, general_ai)
##   # Called by AIAutoload at 0.5s intervals
##   commander.tick()

# =============================================================================
# ENUMS
# =============================================================================

enum Stance {
	DEFENSIVE,    # Default. Hold position, engage in range only
	AGGRESSIVE,   # Pursue target, pursue routing up to 50m
	WITHDRAWING,  # Moving away, no engagement
}

# Auto-engagement constants
const AUTO_ENGAGE_RADIUS_AGGRESSIVE: float = 100.0  # Aggressive units engage within 100m (covers 120m spawn gap)
const AUTO_ENGAGE_RADIUS_DEFENSIVE: float = 15.0   # Defensive units only engage close threats
const AUTO_ENGAGE_CHECK_INTERVAL: float = 1.0      # Check every 1 second

# =============================================================================
# SIGNALS
# =============================================================================

signal target_changed(old_target: Node, new_target: Node)
signal stance_changed(old_stance: Stance, new_stance: Stance)
signal order_issued(order_type: int, target)

# =============================================================================
# PROPERTIES
# =============================================================================

var regiment: Node = null
var general_ai = null  # Optional GeneralAI for strategic coordination

var current_stance: Stance = Stance.DEFENSIVE
var current_target: Node = null
var current_order: Dictionary = {}

var behavior_tree: BTNode = null
var blackboard: Dictionary = {}

var target_selector: TargetSelector
var auto_assist_enabled: bool = false  # For player unit assist mode

# State
var _is_active: bool = true
var _last_target_check: float = 0.0  # Reserved for target check throttling
var _faction: int = 0

# Personality-driven state
var _reaction_delay_timer: float = 0.0  # Delay before responding to new threats
var _pending_threat: Node = null  # Threat waiting for reaction delay
var _last_hp_ratio: float = 1.0  # Track HP for preservation check
var _cached_personality: AIPersonality = null  # Cache to avoid repeated lookups

# =============================================================================
# PERSONALITY ACCESS
# =============================================================================

var personality: AIPersonality:
	get:
		# Return cached personality if available
		if _cached_personality:
			return _cached_personality
		# Get personality from GeneralAI if available
		if general_ai and general_ai.personality:
			_cached_personality = general_ai.personality
			return _cached_personality
		# Try to get from AIAutoload's GeneralAI for this faction
		if AIAutoload:
			var faction_general = AIAutoload.get_general_ai(_faction)
			if faction_general and faction_general.personality:
				_cached_personality = faction_general.personality
				return _cached_personality
		# Create default personality as fallback
		_cached_personality = AIPersonality.new()
		return _cached_personality

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_regiment: Node, p_general_ai = null) -> void:
	regiment = p_regiment
	general_ai = p_general_ai
	_faction = 0 if regiment.is_player_controlled else 1

	target_selector = TargetSelector.new()

	_init_blackboard()
	_build_behavior_tree()

	# Register with AIAutoload
	if AIAutoload:
		AIAutoload.register_commander_ai(self)

	# Connect to regiment's UnitMorale if available
	_connect_morale_signals()


func _init_blackboard() -> void:
	## Initialize shared data for behavior tree.
	blackboard = {
		"regiment": regiment,
		"target": null,
		"stance": current_stance,
		"is_routing": false,
		"is_engaged": false,
		"destination": Vector3.ZERO,
		"faction": _faction,
	}


func _connect_morale_signals() -> void:
	## Connect to UnitMorale signals for routing behavior.
	if regiment and regiment.has_method("get") and regiment.get("unit_morale"):
		var unit_morale = regiment.unit_morale
		if unit_morale:
			unit_morale.unit_routed.connect(_on_unit_routed)
			unit_morale.unit_rallied.connect(_on_unit_rallied)

# =============================================================================
# BEHAVIOR TREE CONSTRUCTION
# =============================================================================

func _build_behavior_tree() -> void:
	## Build the behavior tree for this commander.

	# Root selector - try behaviors in priority order
	var root: BTSelector = BTSelector.new("Root")

	# 1. Routing behavior (highest priority)
	var routing_sequence: BTSequence = BTSequence.new("RoutingBehavior")
	routing_sequence.add_child(_create_is_routing_condition())
	routing_sequence.add_child(_create_flee_task())

	# 2. Engage current target
	var engage_sequence: BTSequence = BTSequence.new("EngageBehavior")
	engage_sequence.add_child(_create_has_target_condition())
	engage_sequence.add_child(_create_engage_selector())

	# 3. Acquire new target
	var acquire_sequence: BTSequence = BTSequence.new("AcquireBehavior")
	acquire_sequence.add_child(_create_acquire_target_task())
	acquire_sequence.add_child(_create_engage_selector())

	# 4. Idle/hold position
	var idle_task: BTNode = _create_idle_task()

	root.add_children([routing_sequence, engage_sequence, acquire_sequence, idle_task])
	root.setup(blackboard)

	behavior_tree = root


func _create_engage_selector() -> BTNode:
	## Create selector for engagement options.
	var selector: BTSelector = BTSelector.new("EngageOptions")

	# Try ranged first if we have ammo and range
	var ranged_sequence: BTSequence = BTSequence.new("RangedAttack")
	ranged_sequence.add_child(_create_has_ammo_condition())
	ranged_sequence.add_child(_create_ranged_task())

	# Otherwise move to engage in melee
	var melee_sequence: BTSequence = BTSequence.new("MeleeAttack")
	melee_sequence.add_child(_create_move_to_target_task())
	melee_sequence.add_child(_create_melee_task())

	selector.add_children([ranged_sequence, melee_sequence])
	return selector


func _create_is_routing_condition() -> BTNode:
	var cond: BTCondition = BTCondition.new("IsRouting")
	cond.condition_func = func(): return blackboard.get("is_routing", false)
	cond.blackboard = blackboard
	return cond


func _create_has_target_condition() -> BTNode:
	var cond: BTCondition = BTCondition.new("HasTarget")
	cond.condition_func = func():
		var target = blackboard.get("target")
		var has_target: bool = target != null and is_instance_valid(target)
		# DEBUG: Trace target check for artillery
		if regiment and regiment.data and regiment.data.unit_type == UnitType.Type.ARTILLERY:
			print("[COMMANDER DEBUG] %s: HasTarget check - target=%s, result=%s" % [
				regiment.data.regiment_name if regiment.data else "?",
				target.data.regiment_name if target and is_instance_valid(target) and target.data else "none",
				str(has_target)
			])
		return has_target
	cond.blackboard = blackboard
	return cond


func _create_has_ammo_condition() -> BTNode:
	var cond: BTCondition = BTCondition.new("HasAmmo")
	cond.condition_func = func():
		var has_ammo: bool = regiment and regiment.current_ammo > 0 and regiment.data.ballistic_skill > 0
		# DEBUG: Trace ammo check for artillery
		if regiment and regiment.data and regiment.data.unit_type == UnitType.Type.ARTILLERY:
			print("[COMMANDER DEBUG] %s: HasAmmo check - ammo=%d, bs=%d, result=%s" % [
				regiment.data.regiment_name if regiment.data else "?",
				regiment.current_ammo if regiment else -1,
				regiment.data.ballistic_skill if regiment and regiment.data else -1,
				str(has_ammo)
			])
		return has_ammo
	cond.blackboard = blackboard
	return cond


func _create_acquire_target_task() -> BTNode:
	return TaskAcquireTarget.new(self)


func _create_move_to_target_task() -> BTNode:
	return TaskMoveToPosition.new(self)


func _create_melee_task() -> BTNode:
	return TaskEngageMelee.new(self)


func _create_ranged_task() -> BTNode:
	return TaskFireRanged.new(self)


func _create_flee_task() -> BTNode:
	return TaskFlee.new(self)


func _create_idle_task() -> BTNode:
	return TaskIdle.new(self)

# =============================================================================
# MAIN TICK
# =============================================================================

func tick() -> void:
	## Called by AIAutoload at 0.5s intervals.
	if not _is_active or not regiment:
		return

	if regiment.state == Regiment.State.DEAD:
		_is_active = false
		return

	# Don't run AI during deployment phase
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		return

	# Apply reaction delay from personality (reduced for faster engagement)
	var tick_delta: float = 0.5
	if _reaction_delay_timer > 0:
		_reaction_delay_timer -= tick_delta
		if _reaction_delay_timer <= 0 and _pending_threat:
			# Reaction delay expired, now respond to threat
			set_target(_pending_threat)
			_pending_threat = null

	# Check unit preservation - request retreat if HP low and trait is high
	_check_unit_preservation()

	# Check casualty thresholds for stance/behavior changes
	_check_casualty_thresholds()

	# Check pursuit aggression for routing enemies
	_check_pursuit_behavior()

	# Check if impetuous unit wants to charge without orders
	_check_impetuous_charge()

	# Check for auto-engagement based on stance
	_check_auto_engagement()

	# Update blackboard state
	_update_blackboard()

	# Ensure target is set in blackboard BEFORE running tree (fixes ranged not firing)
	blackboard["target"] = current_target

	# If already engaged in melee, don't run behavior tree - let combat resolve naturally
	# This prevents the AI from issuing conflicting move orders during melee
	if regiment.state == Regiment.State.ENGAGING:
		return

	# DEBUG: Trace behavior tree for artillery
	var is_artillery: bool = regiment.data and regiment.data.unit_type == UnitType.Type.ARTILLERY
	if is_artillery:
		print("[COMMANDER DEBUG] %s: tick() - target=%s, ammo=%d, bs=%d" % [
			regiment.data.regiment_name if regiment.data else "?",
			current_target.data.regiment_name if current_target and is_instance_valid(current_target) and current_target.data else "none",
			regiment.current_ammo,
			regiment.data.ballistic_skill if regiment.data else 0
		])

	# Run behavior tree
	if behavior_tree:
		var _bt_result = behavior_tree.tick(tick_delta)
		if is_artillery:
			print("[COMMANDER DEBUG] %s: behavior_tree result=%s" % [
				regiment.data.regiment_name if regiment.data else "?",
				str(_bt_result)
			])


func _update_blackboard() -> void:
	## Sync blackboard with current state.
	blackboard["regiment"] = regiment
	blackboard["stance"] = current_stance
	blackboard["target"] = current_target
	blackboard["is_engaged"] = regiment.state == Regiment.State.ENGAGING

	# Check target validity - clear stale targets
	if current_target:
		if not is_instance_valid(current_target):
			set_target(null)
		elif current_target.state == Regiment.State.DEAD:
			set_target(null)
		elif current_target.has_method("is_queued_for_deletion") and current_target.is_queued_for_deletion():
			set_target(null)

	# Ammo depletion fallback - ranged units out of ammo become aggressive for melee
	if regiment and regiment.current_ammo <= 0 and regiment.data and regiment.data.ballistic_skill > 0:
		if current_stance == Stance.DEFENSIVE:
			set_stance(Stance.AGGRESSIVE)


func _check_unit_preservation() -> void:
	## Check if unit should retreat based on HP, personality, and threat assessment.
	## Uses threat heatmap for smarter retreat decisions (spring1944-style).
	if not regiment:
		return

	var hp_ratio: float = float(regiment.current_soldiers) / float(regiment.data.max_soldiers)
	_last_hp_ratio = hp_ratio

	# Only check if we're not already routing
	if blackboard.get("is_routing", false):
		return

	# Calculate our firepower for threat comparison
	var my_firepower := float(regiment.data.weapon_skill * regiment.data.strength * regiment.current_soldiers)

	# Use threat heatmap for intelligent retreat decision
	var should_retreat_threat := false
	if AIAutoload and AIAutoload.threat_heatmap:
		should_retreat_threat = AIAutoload.should_retreat(
			regiment.global_position, _faction, my_firepower, hp_ratio
		)

	# Traditional unit preservation threshold check
	var should_retreat_hp := hp_ratio < 0.3 and personality.unit_preservation > 0.5

	# Retreat if either condition is met
	if should_retreat_threat or should_retreat_hp:
		# Request tactical retreat from GeneralAI
		if general_ai and general_ai.has_method("request_retreat"):
			general_ai.request_retreat(regiment)
		else:
			# If no general, switch to defensive and move to safer position
			set_stance(Stance.DEFENSIVE)
			var flee_pos: Vector3 = _find_flee_position()
			issue_move_order(flee_pos)


func _check_casualty_thresholds() -> void:
	## Check casualty tracker thresholds for behavior changes.
	## 15% loss -> CAUTION (DEFENSIVE), 50% -> WITHDRAW, 75% -> ROUT
	if not regiment or not regiment.casualty_tracker:
		return

	# Skip if already routing
	if blackboard.get("is_routing", false):
		return

	var tracker: CasualtyTracker = regiment.casualty_tracker

	# Calculate aura bonus from nearby heroes/generals
	var aura_bonus: float = _calculate_nearby_aura_bonus()

	var threshold: String = tracker.check_thresholds(aura_bonus)

	if threshold == "rout":
		# Force immediate rout
		print("[AI] %s reached ROUT threshold (75%% casualties)" % regiment.name)
		if regiment.unit_morale:
			regiment.unit_morale.force_rout()
		blackboard["is_routing"] = true

	elif threshold == "withdraw":
		# Begin fighting withdrawal
		print("[AI] %s entered FIGHTING WITHDRAWAL (50%% casualties)" % regiment.name)
		set_stance(Stance.WITHDRAWING)
		BattleSignals.unit_withdrawing.emit(regiment)
		# Move away from enemy
		var flee_pos: Vector3 = _find_flee_position()
		issue_move_order(flee_pos)

	elif threshold == "caution":
		# Drop to defensive stance
		print("[AI] %s entered CAUTION mode (15%% casualties)" % regiment.name)
		set_stance(Stance.DEFENSIVE)
		BattleSignals.unit_entered_caution.emit(regiment)


func _calculate_nearby_aura_bonus() -> float:
	## Calculate threshold bonus from nearby heroes/generals with auras.
	## Returns the best aura_threshold_bonus from any nearby allied aura source.
	if not AIAutoload or not AIAutoload.spatial_hash:
		return 0.0

	var my_faction: int = 0 if regiment.is_player_controlled else 1
	var best_bonus: float = 0.0

	# Query nearby allied units within a reasonable radius
	var nearby_allies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		regiment.global_position,
		30.0,  # Check within 30m for aura sources
		my_faction
	)

	for ally in nearby_allies:
		if ally == regiment:
			continue
		if not is_instance_valid(ally) or not ally.data:
			continue
		if not ally.data.has_aura:
			continue
		if ally.state == Regiment.State.DEAD:
			continue

		# Check if we're within this unit's aura radius
		var dist: float = regiment.global_position.distance_to(ally.global_position)
		if dist <= ally.data.aura_radius:
			# Take the best bonus
			if ally.data.aura_threshold_bonus > best_bonus:
				best_bonus = ally.data.aura_threshold_bonus

	return best_bonus


func _check_pursuit_behavior() -> void:
	## Check pursuit aggression for routing enemies.
	## When enemy is routing, chase if pursuit_aggression > 0.5, otherwise hold.
	## Disciplined units never pursue regardless of aggression setting.
	if not current_target or not is_instance_valid(current_target):
		return

	# Check if current target is routing
	if current_target.state == Regiment.State.ROUTING:
		# Disciplined units never pursue (from RegimentData personality)
		var can_pursue: bool = true
		if regiment.data and not regiment.data.can_pursue():
			can_pursue = false

		if can_pursue and personality.pursuit_aggression > 0.5:
			# Chase the routing enemy
			if current_stance != Stance.AGGRESSIVE:
				set_stance(Stance.AGGRESSIVE)
			# Issue attack order to pursue
			issue_attack_order(current_target)
		else:
			# Hold position, don't pursue
			clear_target()
			issue_hold_order()


func _check_impetuous_charge() -> void:
	## Check if impetuous unit charges without orders.
	## Impetuous units may charge when enemies are nearby, ignoring orders.
	if not regiment or not regiment.data:
		return

	# Only impetuous units can charge without orders
	if not regiment.data.may_charge_impulsively():
		return

	# Don't interrupt if already engaged or marching to target
	if regiment.state == Regiment.State.ENGAGING or regiment.state == Regiment.State.MARCHING:
		return

	# Don't charge while routing
	if blackboard.get("is_routing", false):
		return

	# Check for nearby enemies within charge range (40 units)
	const IMPETUOUS_CHARGE_RANGE: float = 40.0
	var nearest_enemy: Node = AIAutoload.query_nearest_enemy(
		regiment.global_position, IMPETUOUS_CHARGE_RANGE, _faction
	)

	if not nearest_enemy or not is_instance_valid(nearest_enemy):
		return

	# Random chance to charge (30% per tick when enemy is in range)
	# This creates the "may charge without orders" behavior
	if randf() < 0.30:
		# CHARGE!
		set_target(nearest_enemy)
		issue_charge_order(nearest_enemy)


func _check_auto_engagement() -> void:
	## Check if unit should auto-engage nearby enemies based on stance.
	if not regiment or regiment.state == Regiment.State.ENGAGING:
		return  # Already in combat
	if regiment.state == Regiment.State.ROUTING:
		return  # Can't engage while routing
	if current_stance == Stance.WITHDRAWING:
		return  # Withdrawing units don't engage

	# Determine engagement radius based on stance
	var engage_radius: float = 0.0
	match current_stance:
		Stance.AGGRESSIVE:
			engage_radius = AUTO_ENGAGE_RADIUS_AGGRESSIVE
		Stance.DEFENSIVE:
			engage_radius = AUTO_ENGAGE_RADIUS_DEFENSIVE

	if engage_radius <= 0:
		return

	# Find nearest enemy within radius
	var nearest_enemy: Node = AIAutoload.query_nearest_enemy(
		regiment.global_position, engage_radius, _faction
	)

	if not nearest_enemy or not is_instance_valid(nearest_enemy):
		return
	if nearest_enemy.state == Regiment.State.DEAD:
		return

	# Set target and issue appropriate order
	set_target(nearest_enemy)

	if current_stance == Stance.AGGRESSIVE:
		# Aggressive: move to attack
		issue_attack_order(nearest_enemy)
	else:
		# Defensive: engage if within reasonable melee range (15m)
		# This ensures units actually fight nearby enemies instead of watching
		var dist: float = regiment.global_position.distance_to(nearest_enemy.global_position)
		if dist < 15.0:
			issue_attack_order(nearest_enemy)

# =============================================================================
# TARGET MANAGEMENT
# =============================================================================

func set_target(new_target: Node) -> void:
	## Set current attack target.
	if new_target == current_target:
		return

	var old_target: Node = current_target
	current_target = new_target
	blackboard["target"] = new_target

	target_changed.emit(old_target, new_target)

	if new_target:
		BattleSignals.ai_target_acquired.emit(regiment, new_target)


func acquire_target() -> Node:
	## Find and set a new target using the target selector.
	## Applies personality traits: targeting_accuracy and reaction_delay_mult.
	var enemy_faction: int = 1 if _faction == 0 else 0
	var candidates: Array = AIAutoload.get_all_regiments(enemy_faction)

	# Apply targeting_accuracy to target selection
	var best_target: Node = target_selector.select_best_target_with_accuracy(
		regiment, candidates, -1.0, personality.targeting_accuracy
	)

	if best_target:
		# Reduced reaction delay - only apply for non-aggressive stances
		# AGGRESSIVE stance targets immediately for responsive combat
		if current_stance == Stance.AGGRESSIVE:
			set_target(best_target)
		else:
			# Apply reaction delay before responding to new threats (reduced base from 0.5 to 0.2)
			var delay: float = 0.2 * personality.reaction_delay_mult  # Reduced base delay
			if delay > 0.1 and _reaction_delay_timer <= 0:
				# Start reaction delay - don't immediately target
				_reaction_delay_timer = delay
				_pending_threat = best_target
				return null  # Don't set target yet
			else:
				set_target(best_target)

	return best_target


func clear_target() -> void:
	## Clear the current target.
	set_target(null)

# =============================================================================
# STANCE MANAGEMENT
# =============================================================================

func set_stance(new_stance: Stance) -> void:
	## Change tactical stance.
	if new_stance == current_stance:
		return

	var old_stance: Stance = current_stance
	current_stance = new_stance
	blackboard["stance"] = new_stance

	stance_changed.emit(old_stance, new_stance)


func is_stance(stance: Stance) -> bool:
	## Check current stance.
	return current_stance == stance

# =============================================================================
# ORDER ISSUING
# =============================================================================

func issue_move_order(destination: Vector3) -> void:
	## Issue a move command.
	current_order = { "type": OrderType.Type.MOVE, "destination": destination }
	blackboard["destination"] = destination
	regiment.give_order(OrderType.Type.MOVE, destination)
	order_issued.emit(OrderType.Type.MOVE, destination)


func issue_attack_order(target: Node) -> void:
	## Issue an attack command.
	set_target(target)
	current_order = { "type": OrderType.Type.ATTACK_MOVE, "target": target }
	# Use approach position to avoid pathing through enemy
	var approach_pos: Vector3 = Regiment.get_attack_approach_position(regiment.global_position, target.global_position)
	regiment.give_order(OrderType.Type.ATTACK_MOVE, approach_pos)
	order_issued.emit(OrderType.Type.ATTACK_MOVE, target)


func issue_charge_order(target: Node) -> void:
	## Issue a charge command.
	set_target(target)
	current_order = { "type": OrderType.Type.CHARGE, "target": target }
	# Use approach position to avoid pathing through enemy
	var approach_pos: Vector3 = Regiment.get_attack_approach_position(regiment.global_position, target.global_position)
	regiment.give_order(OrderType.Type.CHARGE, approach_pos)
	order_issued.emit(OrderType.Type.CHARGE, target)


func issue_hold_order() -> void:
	## Issue a hold position command.
	current_order = { "type": OrderType.Type.HOLD_POSITION }
	regiment.give_order(OrderType.Type.HOLD_POSITION)
	order_issued.emit(OrderType.Type.HOLD_POSITION, null)

# =============================================================================
# MORALE INTEGRATION
# =============================================================================

func _on_unit_routed() -> void:
	## Called when the unit routs.
	blackboard["is_routing"] = true
	clear_target()

	# Find safe position to flee to
	var flee_pos: Vector3 = _find_flee_position()
	current_order = { "type": "FLEE", "destination": flee_pos }


func _on_unit_rallied() -> void:
	## Called when the unit rallies.
	blackboard["is_routing"] = false
	issue_hold_order()


func _find_flee_position() -> Vector3:
	## Find a position to flee towards using threat heatmap (spring1944-style).
	## Falls back to simple flee-from-enemy if heatmap unavailable.
	## Clamps result to map bounds to prevent units leaving the battlefield.

	var flee_pos: Vector3

	# Use threat heatmap for intelligent safe position
	if AIAutoload and AIAutoload.threat_heatmap:
		flee_pos = AIAutoload.get_safest_retreat_position(regiment.global_position, _faction)
	else:
		# Fallback: simple flee-from-enemy logic
		var flee_direction: Vector3 = Vector3.ZERO

		# Get direction away from nearest enemy
		var nearest_enemy: Node = AIAutoload.query_nearest_enemy(
			regiment.global_position, 50.0, _faction
		)

		if nearest_enemy:
			flee_direction = (regiment.global_position - nearest_enemy.global_position).normalized()
		else:
			# Flee towards own edge of map
			flee_direction = Vector3(0, 0, 1) if _faction == 0 else Vector3(0, 0, -1)

		flee_direction.y = 0
		flee_pos = regiment.global_position + flee_direction * 30.0

	# Clamp to map bounds (configurable via AIAutoload)
	if AIAutoload:
		flee_pos = AIAutoload.clamp_to_map(flee_pos)

	return flee_pos

# =============================================================================
# GENERAL AI INTEGRATION
# =============================================================================

func receive_strategic_order(order: Dictionary) -> void:
	## Receive orders from GeneralAI.
	match order.get("type", ""):
		"ATTACK":
			if order.has("target"):
				issue_attack_order(order["target"])
			elif order.has("position"):
				issue_move_order(order["position"])

		"DEFEND":
			set_stance(Stance.DEFENSIVE)
			if order.has("position"):
				issue_move_order(order["position"])
			else:
				issue_hold_order()

		"FLANK":
			set_stance(Stance.AGGRESSIVE)  # Flanking is aggressive action
			if order.has("target"):
				set_target(order["target"])
				issue_attack_order(order["target"])

		"HOLD":
			issue_hold_order()

# =============================================================================
# CLEANUP
# =============================================================================

func destroy() -> void:
	## Clean up the commander AI.
	_is_active = false

	# Disconnect morale signals to prevent memory leaks
	if regiment and regiment.get("unit_morale"):
		var unit_morale = regiment.unit_morale
		if unit_morale:
			if unit_morale.unit_routed.is_connected(_on_unit_routed):
				unit_morale.unit_routed.disconnect(_on_unit_routed)
			if unit_morale.unit_rallied.is_connected(_on_unit_rallied):
				unit_morale.unit_rallied.disconnect(_on_unit_rallied)

	if AIAutoload:
		AIAutoload.unregister_commander_ai(self)

	regiment = null
	general_ai = null
	behavior_tree = null
	_cached_personality = null
	_pending_threat = null

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"stance": Stance.keys()[current_stance],
		"target": current_target.name if current_target else "None",
		"is_routing": blackboard.get("is_routing", false),
		"is_engaged": blackboard.get("is_engaged", false),
		"current_order": current_order,
	}


# =============================================================================
# SIMPLE TASK CLASSES (embedded for convenience)
# =============================================================================

class TaskFlee extends BTNode:
	var commander: CommanderAI

	func _init(p_commander: CommanderAI) -> void:
		super._init("Flee")
		commander = p_commander

	func tick(_delta: float) -> Status:
		var flee_pos: Vector3 = commander.current_order.get("destination", commander._find_flee_position())
		commander.regiment.give_order(OrderType.Type.MOVE, flee_pos)
		return Status.RUNNING


class TaskIdle extends BTNode:
	var commander: CommanderAI

	func _init(p_commander: CommanderAI) -> void:
		super._init("Idle")
		commander = p_commander

	func tick(_delta: float) -> Status:
		# Just hold position
		if commander.regiment.state == Regiment.State.IDLE:
			return Status.SUCCESS
		return Status.RUNNING
