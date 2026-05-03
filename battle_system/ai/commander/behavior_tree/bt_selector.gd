class_name BTSelector
extends BTNode

## Selector node (OR logic).
## Tries children in order until one succeeds.
## Returns SUCCESS if any child succeeds.
## Returns FAILURE only if all children fail.
## Returns RUNNING if a child is still running.

# =============================================================================
# PROPERTIES
# =============================================================================

var _current_child_index: int = 0
var _is_running: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_name: String = "Selector") -> void:
	super._init(p_name)

# =============================================================================
# EXECUTION
# =============================================================================

func tick(delta: float) -> Status:
	## Try children until one succeeds or returns RUNNING.

	# If we were running, continue from where we left off
	if not _is_running:
		_current_child_index = 0

	while _current_child_index < children.size():
		var child: BTNode = children[_current_child_index]
		var status: Status = child.tick(delta)

		match status:
			Status.SUCCESS:
				_is_running = false
				_current_child_index = 0
				return Status.SUCCESS

			Status.RUNNING:
				_is_running = true
				return Status.RUNNING

			Status.FAILURE:
				# Try next child
				_current_child_index += 1

	# All children failed
	_is_running = false
	_current_child_index = 0
	return Status.FAILURE


func reset() -> void:
	## Reset state.
	super.reset()
	_current_child_index = 0
	_is_running = false

# =============================================================================
# UTILITY
# =============================================================================

func get_debug_string() -> String:
	return "Selector[%d/%d]" % [_current_child_index, children.size()]
