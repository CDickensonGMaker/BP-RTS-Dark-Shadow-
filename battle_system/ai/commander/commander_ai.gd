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
	PASSIVE,      # Hold position, don't attack unless attacked
	DEFENSIVE,    # Hold position, attack threats in range
	AGGRESSIVE,   # Seek and destroy enemies
	FLANKING,     # Attempt to flank current target
	SKIRMISH,     # Maintain distance, use ranged if available
}

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

var current_stance: Stance = Stance.AGGRESSIVE
var current_target: Node = null
var current_order: Dictionary = {}

var behavior_tree: BTNode = null
var blackboard: Dictionary = {}

var target_selector: TargetSelector
var auto_assist_enabled: bool = false  # For player unit assist mode

# State
var _is_active: bool = true
var _last_target_check: float = 0.0
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
		return target != null and is_instance_valid(target)
	cond.blackboard = blackboard
	return cond


func _create_has_ammo_condition() -> BTNode:
	var cond: BTCondition = BTCondition.new("HasAmmo")
	cond.condition_func = func():
		var has_ammo = regiment and regiment.current_ammo > 0 and regiment.data.ballistic_skill > 0
		if regiment and regiment.data.ballistic_skill > 0:
			print("[AI DEBUG] %s HasAmmo check: ammo=%d, bs=%d, result=%s" % [
				regiment.name, regiment.current_ammo, regiment.data.ballistic_skill, has_ammo])
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

	# Check pursuit aggression for routing enemies
	_check_pursuit_behavior()

	# Update blackboard state
	_update_blackboard()

	# If already engaged in melee, don't run behavior tree - let combat resolve naturally
	# This prevents the AI from issuing conflicting move orders during melee
	if regiment.state == Regiment.State.ENGAGING:
		return

	# Run behavior tree
	if behavior_tree:
		var _bt_result = behavior_tree.tick(tick_delta)


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

	# Ammo depletion fallback - if out of ammo and in skirmish stance, switch to aggressive
	if regiment and regiment.current_ammo <= 0 and current_stance == Stance.SKIRMISH:
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


func _check_pursuit_behavior() -> void:
	## Check pursuit aggression for routing enemies.
	## When enemy is routing, chase if pursuit_aggression > 0.5, otherwise hold.
	if not current_target or not is_instance_valid(current_target):
		return

	# Check if current target is routing
	if current_target.state == Regiment.State.ROUTING:
		if personality.pursuit_aggression > 0.5:
			# Chase the routing enemy
			if current_stance != Stance.AGGRESSIVE:
				set_stance(Stance.AGGRESSIVE)
			# Issue attack order to pursue
			issue_attack_order(current_target)
		else:
			# Hold position, don't pursue
			clear_target()
			issue_hold_order()

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
	regiment.give_order(OrderType.Type.ATTACK_MOVE, target.global_position)
	order_issued.emit(OrderType.Type.ATTACK_MOVE, target)


func issue_charge_order(target: Node) -> void:
	## Issue a charge command.
	set_target(target)
	current_order = { "type": OrderType.Type.CHARGE, "target": target }
	regiment.give_order(OrderType.Type.CHARGE, target.global_position)
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

	# Use threat heatmap for intelligent safe position
	if AIAutoload and AIAutoload.threat_heatmap:
		return AIAutoload.get_safest_retreat_position(regiment.global_position, _faction)

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
	return regiment.global_position + flee_direction * 30.0

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
			set_stance(Stance.FLANKING)
			if order.has("target"):
				set_target(order["target"])

		"HOLD":
			issue_hold_order()

# =============================================================================
# CLEANUP
# =============================================================================

func destroy() -> void:
	## Clean up the commander AI.
	_is_active = false

	if AIAutoload:
		AIAutoload.unregister_commander_ai(self)

	regiment = null
	general_ai = null
	behavior_tree = null

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
