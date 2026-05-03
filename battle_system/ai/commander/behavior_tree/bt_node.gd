class_name BTNode
extends RefCounted

## Base class for behavior tree nodes.
## Provides common structure for all BT node types.

# =============================================================================
# ENUMS
# =============================================================================

enum Status {
	SUCCESS,    # Task completed successfully
	FAILURE,    # Task failed
	RUNNING,    # Task still in progress
}

# =============================================================================
# PROPERTIES
# =============================================================================

var name: String = "BTNode"
var blackboard: Dictionary = {}  # Shared data between nodes
var parent: BTNode = null
var children: Array[BTNode] = []

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_name: String = "BTNode") -> void:
	name = p_name


func setup(p_blackboard: Dictionary) -> void:
	## Initialize with shared blackboard.
	blackboard = p_blackboard
	for child in children:
		child.setup(blackboard)

# =============================================================================
# TREE BUILDING
# =============================================================================

func add_child(child: BTNode) -> BTNode:
	## Add a child node. Returns self for chaining.
	child.parent = self
	child.blackboard = blackboard
	children.append(child)
	return self


func add_children(new_children: Array) -> BTNode:
	## Add multiple children. Returns self for chaining.
	for child in new_children:
		add_child(child)
	return self


func remove_child(child: BTNode) -> void:
	## Remove a child node.
	var idx: int = children.find(child)
	if idx >= 0:
		children[idx].parent = null
		children.remove_at(idx)


func clear_children() -> void:
	## Remove all children.
	for child in children:
		child.parent = null
	children.clear()

# =============================================================================
# EXECUTION
# =============================================================================

func tick(delta: float) -> Status:
	## Execute this node. Override in subclasses.
	return Status.SUCCESS


func reset() -> void:
	## Reset node state. Override in subclasses if needed.
	for child in children:
		child.reset()

# =============================================================================
# BLACKBOARD ACCESS
# =============================================================================

func get_blackboard(key: String, default = null):
	## Get a value from the blackboard.
	return blackboard.get(key, default)


func set_blackboard(key: String, value) -> void:
	## Set a value in the blackboard.
	blackboard[key] = value


func has_blackboard(key: String) -> bool:
	## Check if blackboard has a key.
	return blackboard.has(key)


func clear_blackboard(key: String) -> void:
	## Remove a key from blackboard.
	blackboard.erase(key)

# =============================================================================
# UTILITY
# =============================================================================

func get_regiment() -> Node:
	## Get the regiment from blackboard.
	return get_blackboard("regiment")


func get_target() -> Node:
	## Get current target from blackboard.
	return get_blackboard("target")


func is_routing() -> bool:
	## Check if unit is routing.
	return get_blackboard("is_routing", false)


func get_debug_string() -> String:
	## Get debug info string.
	return name
