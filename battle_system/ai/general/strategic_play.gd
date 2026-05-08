class_name StrategicPlay
extends RefCounted

## Base class for strategic plays.
## A play is a high-level battle strategy executed by the GeneralAI.
##
## Subclasses must implement:
##   - evaluate(analysis) -> float: Score this play given battlefield state
##   - start(analysis): Begin executing the play
##   - tick() -> Status: Continue execution, return status
##   - abort(): Cancel the play

# =============================================================================
# ENUMS
# =============================================================================

enum Status {
	RUNNING,    # Play is still executing
	SUCCESS,    # Play completed successfully
	FAILURE,    # Play failed
	ABORTED,    # Play was cancelled
}

# =============================================================================
# PROPERTIES
# =============================================================================

var name: String = "StrategicPlay"
var intent: String = ""  # Human-readable description of what this play aims to achieve
var general_ai  # Untyped to avoid cyclic dependency with GeneralAI preloading plays
var status: Status = Status.RUNNING

# Play state
var _is_active: bool = false
var _start_time: float = 0.0
var _analysis: BattlefieldAnalysis = null

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_general_ai = null, p_name: String = "StrategicPlay") -> void:
	general_ai = p_general_ai
	name = p_name

# =============================================================================
# ABSTRACT METHODS
# =============================================================================

func evaluate(_analysis: BattlefieldAnalysis) -> float:
	## Score this play given current battlefield state.
	## Higher scores = better play for this situation.
	## Override in subclasses.
	return 0.0


func start(analysis: BattlefieldAnalysis) -> void:
	## Begin executing the play.
	## Override in subclasses.
	_is_active = true
	_start_time = Time.get_ticks_msec() / 1000.0
	_analysis = analysis
	status = Status.RUNNING


func tick() -> Status:
	## Continue execution of the play.
	## Returns current status.
	## Override in subclasses.
	return status


func abort() -> void:
	## Cancel the play.
	_is_active = false
	status = Status.ABORTED

# =============================================================================
# UTILITY
# =============================================================================

func is_active() -> bool:
	## Check if play is currently executing.
	return _is_active


func get_elapsed_time() -> float:
	## Get time since play started.
	return Time.get_ticks_msec() / 1000.0 - _start_time


func assign_role(regiment: Node, role: String) -> void:
	## Assign a role to a regiment.
	if general_ai:
		general_ai.assign_role(regiment, role)


func issue_attack(regiment: Node, target: Node) -> void:
	## Issue attack order.
	if general_ai:
		general_ai.issue_attack_order(regiment, target)


func issue_defend(regiment: Node, position: Vector3) -> void:
	## Issue defend order.
	if general_ai:
		general_ai.issue_defend_order(regiment, position)


func issue_flank(regiment: Node, target: Node) -> void:
	## Issue flank order.
	if general_ai:
		general_ai.issue_flank_order(regiment, target)


func issue_hold(regiment: Node) -> void:
	## Issue hold order.
	if general_ai:
		general_ai.issue_hold_order(regiment)


func get_regiments_by_role(role: String) -> Array:
	## Get regiments assigned to a role.
	if general_ai:
		return general_ai.get_regiments_with_role(role)
	return []

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"name": name,
		"status": Status.keys()[status],
		"is_active": _is_active,
		"elapsed_time": get_elapsed_time() if _is_active else 0.0,
	}
