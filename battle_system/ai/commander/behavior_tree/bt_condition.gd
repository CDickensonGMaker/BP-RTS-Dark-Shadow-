class_name BTCondition
extends BTNode

## Condition node for checking state.
## Returns SUCCESS if condition is true, FAILURE otherwise.
## Never returns RUNNING.

# =============================================================================
# PROPERTIES
# =============================================================================

var condition_func: Callable
var invert: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_name: String = "Condition", p_condition: Callable = Callable(), p_invert: bool = false) -> void:
	super._init(p_name)
	condition_func = p_condition
	invert = p_invert

# =============================================================================
# EXECUTION
# =============================================================================

func tick(_delta: float) -> Status:
	## Evaluate the condition.
	if not condition_func.is_valid():
		return Status.FAILURE

	var result: bool = condition_func.call()

	if invert:
		result = not result

	return Status.SUCCESS if result else Status.FAILURE

# =============================================================================
# FACTORY METHODS
# =============================================================================

static func has_target() -> BTCondition:
	## Create condition that checks if target exists.
	var cond: BTCondition = BTCondition.new("HasTarget")
	cond.condition_func = func():
		var target = cond.get_blackboard("target")
		return target != null and is_instance_valid(target)
	return cond


static func unit_is_routing() -> BTCondition:
	## Create condition that checks if unit is routing.
	var cond: BTCondition = BTCondition.new("IsRouting")
	cond.condition_func = func():
		return cond.get_blackboard("is_routing", false)
	return cond


static func unit_is_not_routing() -> BTCondition:
	## Create condition that checks if unit is NOT routing.
	var cond: BTCondition = BTCondition.new("IsNotRouting")
	cond.condition_func = func():
		return not cond.get_blackboard("is_routing", false)
	return cond


static func has_ammo() -> BTCondition:
	## Create condition that checks if unit has ammo.
	var cond: BTCondition = BTCondition.new("HasAmmo")
	cond.condition_func = func():
		var regiment = cond.get_regiment()
		return regiment and regiment.current_ammo > 0
	return cond


static func target_in_range(max_range: float) -> BTCondition:
	## Create condition that checks if target is in range.
	var cond: BTCondition = BTCondition.new("TargetInRange")
	cond.condition_func = func():
		var regiment = cond.get_regiment()
		var target = cond.get_target()
		if not regiment or not target or not is_instance_valid(target):
			return false
		var dist = regiment.global_position.distance_to(target.global_position)
		return dist <= max_range
	return cond


static func target_in_melee_range() -> BTCondition:
	## Create condition for melee range (3 units).
	return target_in_range(3.0)


static func is_engaging() -> BTCondition:
	## Create condition that checks if currently in melee.
	var cond: BTCondition = BTCondition.new("IsEngaging")
	cond.condition_func = func():
		var regiment = cond.get_regiment()
		return regiment and regiment.state == Regiment.State.ENGAGING
	return cond


static func custom(p_name: String, p_callable: Callable) -> BTCondition:
	## Create a custom condition.
	return BTCondition.new(p_name, p_callable)

# =============================================================================
# UTILITY
# =============================================================================

func get_debug_string() -> String:
	return "Cond:%s" % name
