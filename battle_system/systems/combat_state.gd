extends Node

## CombatState - Centralized manager for combat state flags.
## Handles is_braced, has_charged, inspire_active, and other transient combat states.
## All combat state changes should go through this system for centralized tracking.

# =============================================================================
# COMBAT STATE FLAGS
# =============================================================================

enum Flag {
	BRACED,        # Unit is braced against charge
	CHARGED,       # Unit has applied charge bonus this engagement
	INSPIRED,      # Unit is inspired by general or ability
	HOLD_FIRE,     # Unit is holding fire (ranged only)
}

# Flag names for debug output
const FLAG_NAMES := {
	Flag.BRACED: "braced",
	Flag.CHARGED: "charged",
	Flag.INSPIRED: "inspired",
	Flag.HOLD_FIRE: "hold_fire",
}

# =============================================================================
# SETTERS - Route all combat state changes through here
# =============================================================================

## Set the braced flag on a regiment.
## Bracing negates frontal charge bonuses.
func set_braced(regiment: Node, value: bool, source: String = "") -> void:
	if not is_instance_valid(regiment):
		return

	var old_value: bool = regiment.is_braced
	if old_value == value:
		return

	regiment.is_braced = value
	_emit_change(regiment, Flag.BRACED, value, source)


## Set the charged flag on a regiment.
## Indicates the unit has applied its charge bonus this engagement.
func set_charged(regiment: Node, value: bool, source: String = "") -> void:
	if not is_instance_valid(regiment):
		return

	var old_value: bool = regiment.has_charged
	if old_value == value:
		return

	regiment.has_charged = value
	_emit_change(regiment, Flag.CHARGED, value, source)


## Set the inspired flag on a regiment.
## Inspired units get attack/morale bonuses from general or ability.
func set_inspired(regiment: Node, value: bool, source: String = "") -> void:
	if not is_instance_valid(regiment):
		return

	var old_value: bool = regiment.inspire_active
	if old_value == value:
		return

	regiment.inspire_active = value
	_emit_change(regiment, Flag.INSPIRED, value, source)


## Set the hold fire flag on a regiment.
func set_hold_fire(regiment: Node, value: bool, source: String = "") -> void:
	if not is_instance_valid(regiment):
		return

	var old_value: bool = regiment.hold_fire
	if old_value == value:
		return

	regiment.hold_fire = value
	_emit_change(regiment, Flag.HOLD_FIRE, value, source)


# =============================================================================
# GETTERS - Query combat state
# =============================================================================

## Check if a regiment is braced.
func is_braced(regiment: Node) -> bool:
	if not is_instance_valid(regiment):
		return false
	return regiment.is_braced


## Check if a regiment has charged this engagement.
func has_charged(regiment: Node) -> bool:
	if not is_instance_valid(regiment):
		return false
	return regiment.has_charged


## Check if a regiment is inspired.
func is_inspired(regiment: Node) -> bool:
	if not is_instance_valid(regiment):
		return false
	return regiment.inspire_active


## Check if a regiment is holding fire.
func is_holding_fire(regiment: Node) -> bool:
	if not is_instance_valid(regiment):
		return false
	return regiment.hold_fire


## Get a flag value by enum.
func get_flag(regiment: Node, flag: Flag) -> bool:
	if not is_instance_valid(regiment):
		return false

	match flag:
		Flag.BRACED:
			return regiment.is_braced
		Flag.CHARGED:
			return regiment.has_charged
		Flag.INSPIRED:
			return regiment.inspire_active
		Flag.HOLD_FIRE:
			return regiment.hold_fire

	return false


# =============================================================================
# BULK OPERATIONS
# =============================================================================

## Reset all combat state flags for a regiment (e.g., at engagement end).
func reset_combat_state(regiment: Node, source: String = "") -> void:
	if not is_instance_valid(regiment):
		return

	set_braced(regiment, false, source)
	set_charged(regiment, false, source)
	# Note: inspired and hold_fire are often persistent, so don't reset here


## Reset engagement-specific flags (called when melee engagement ends).
func reset_engagement_flags(regiment: Node, source: String = "") -> void:
	if not is_instance_valid(regiment):
		return

	set_charged(regiment, false, source)


# =============================================================================
# SIGNAL EMISSION
# =============================================================================

func _emit_change(regiment: Node, flag: Flag, value: bool, source: String) -> void:
	BattleSignals.combat_state_changed.emit(regiment, flag, value)

	# Debug output
	if source != "" and OS.is_debug_build():
		var flag_name: String = FLAG_NAMES.get(flag, "unknown")
		var state_str: String = "ON" if value else "OFF"
		print("[COMBAT_STATE] %s: %s %s (from %s)" % [regiment.name, flag_name, state_str, source])
