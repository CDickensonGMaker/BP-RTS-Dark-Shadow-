class_name BTSequence
extends BTNode

## Sequence node (AND logic).
## Executes children in order until one fails.
## Returns SUCCESS only if all children succeed.
## Returns FAILURE if any child fails.
## Returns RUNNING if a child is still running.

# =============================================================================
# PROPERTIES
# =============================================================================

var _current_child_index: int = 0
var _is_running: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_name: String = "Sequence") -> void:
	super._init(p_name)

# =============================================================================
# EXECUTION
# =============================================================================

func tick(delta: float) -> Status:
	## Execute children in sequence.

	# If we were running, continue from where we left off
	if not _is_running:
		_current_child_index = 0

	while _current_child_index < children.size():
		var child: BTNode = children[_current_child_index]
		var status: Status = child.tick(delta)

		match status:
			Status.FAILURE:
				_is_running = false
				_current_child_index = 0
				return Status.FAILURE

			Status.RUNNING:
				_is_running = true
				return Status.RUNNING

			Status.SUCCESS:
				# Move to next child
				_current_child_index += 1

	# All children succeeded
	_is_running = false
	_current_child_index = 0
	return Status.SUCCESS


func reset() -> void:
	## Reset state.
	super.reset()
	_current_child_index = 0
	_is_running = false

# =============================================================================
# UTILITY
# =============================================================================

func get_debug_string() -> String:
	return "Sequence[%d/%d]" % [_current_child_index, children.size()]
