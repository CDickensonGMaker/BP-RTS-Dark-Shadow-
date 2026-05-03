class_name MoraleComponent
extends RefCounted

## Per-soldier morale component.
## Tracks individual morale, applies events and continuous modifiers,
## and reports state changes.
##
## Usage:
##   var morale = MoraleComponent.new(soldier_node)
##   morale.apply_event(MoraleEvent.friend_killed(position))
##   morale.set_continuous_modifier(MoraleEvent.Source.FLANKED, -1.5)
##   morale.tick(delta)

# =============================================================================
# SIGNALS
# =============================================================================

signal state_changed(old_state: MoraleEvent.State, new_state: MoraleEvent.State)
signal soldier_broke(soldier: Node)
signal morale_changed(new_value: float, delta: float)

# =============================================================================
# PROPERTIES
# =============================================================================

var owner: Node = null  # The soldier this component belongs to
var faction: int = 0    # 0 = player, 1 = enemy (for spatial queries)

var current_morale: float = 80.0
var base_morale: float = 80.0
var current_state: MoraleEvent.State = MoraleEvent.State.STEADY

# Continuous modifiers: Source -> per-second value
var _continuous_modifiers: Dictionary = {}

# Safety tracking for rally
var _time_since_last_hit: float = 0.0
var _is_rallying: bool = false

# State tracking
var _previous_state: MoraleEvent.State = MoraleEvent.State.STEADY
var _is_alive: bool = true

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_owner: Node = null, p_base_morale: float = 80.0, p_faction: int = 0) -> void:
	owner = p_owner
	base_morale = p_base_morale
	current_morale = p_base_morale
	faction = p_faction
	_update_state()


func setup(p_owner: Node, p_base_morale: float, p_faction: int) -> void:
	## Late initialization if not using constructor.
	owner = p_owner
	base_morale = p_base_morale
	current_morale = p_base_morale
	faction = p_faction
	_update_state()

# =============================================================================
# EVENT APPLICATION
# =============================================================================

func apply_event(event: MoraleEvent) -> void:
	## Apply a one-time morale event.
	if not _is_alive:
		return

	var old_morale: float = current_morale
	current_morale = clampf(current_morale + event.magnitude, 0.0, 100.0)

	# Reset safety timer on negative events
	if event.is_negative():
		_time_since_last_hit = 0.0

	morale_changed.emit(current_morale, event.magnitude)
	_update_state()


func apply_damage(amount: float) -> void:
	## Direct morale damage (negative amount).
	if not _is_alive:
		return

	var old_morale: float = current_morale
	current_morale = clampf(current_morale - absf(amount), 0.0, 100.0)
	_time_since_last_hit = 0.0

	morale_changed.emit(current_morale, -absf(amount))
	_update_state()


func apply_bonus(amount: float) -> void:
	## Direct morale bonus (positive amount).
	if not _is_alive:
		return

	var old_morale: float = current_morale
	current_morale = clampf(current_morale + absf(amount), 0.0, 100.0)

	morale_changed.emit(current_morale, absf(amount))
	_update_state()

# =============================================================================
# CONTINUOUS MODIFIERS
# =============================================================================

func set_continuous_modifier(source: MoraleEvent.Source, per_second: float) -> void:
	## Set a continuous modifier. Replaces any existing modifier from this source.
	_continuous_modifiers[source] = per_second


func clear_continuous_modifier(source: MoraleEvent.Source) -> void:
	## Remove a continuous modifier.
	_continuous_modifiers.erase(source)


func has_continuous_modifier(source: MoraleEvent.Source) -> bool:
	## Check if a modifier is active.
	return _continuous_modifiers.has(source)


func get_continuous_modifier(source: MoraleEvent.Source) -> float:
	## Get current value of a modifier (0 if not present).
	return _continuous_modifiers.get(source, 0.0)


func clear_all_continuous_modifiers() -> void:
	## Remove all continuous modifiers.
	_continuous_modifiers.clear()

# =============================================================================
# TICK UPDATE
# =============================================================================

func tick(delta: float) -> void:
	## Called by UnitMorale at 4 Hz. Applies continuous modifiers and updates state.
	if not _is_alive:
		return

	# Update safety timer
	_time_since_last_hit += delta

	# Calculate total continuous effect
	var total_per_second: float = 0.0
	for source in _continuous_modifiers:
		total_per_second += _continuous_modifiers[source]

	# Apply natural recovery if safe
	if _is_safe_for_recovery():
		total_per_second += MoraleConstants.CONTINUOUS_NATURAL_RECOVERY

	# Apply rally recovery if rallying
	if _is_rallying:
		total_per_second += MoraleConstants.CONTINUOUS_RALLY_RECOVERY

	# Apply total change
	if total_per_second != 0.0:
		var change: float = total_per_second * delta
		var old_morale: float = current_morale
		current_morale = clampf(current_morale + change, 0.0, 100.0)

		if change < 0.0:
			_time_since_last_hit = 0.0

		morale_changed.emit(current_morale, change)

	_update_state()
	_check_rally_conditions()

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

func _update_state() -> void:
	## Update state based on current morale and emit signals if changed.
	var new_state: MoraleEvent.State = _calculate_state()

	if new_state != current_state:
		_previous_state = current_state
		current_state = new_state
		state_changed.emit(_previous_state, new_state)

		# Check for breaking
		if new_state == MoraleEvent.State.BROKEN and _previous_state != MoraleEvent.State.BROKEN:
			soldier_broke.emit(owner)


func _calculate_state() -> MoraleEvent.State:
	## Determine state from morale value.
	if current_morale >= MoraleConstants.STATE_STEADY_MIN:
		return MoraleEvent.State.STEADY
	elif current_morale >= MoraleConstants.STATE_WAVERING_MIN:
		return MoraleEvent.State.WAVERING
	elif current_morale >= MoraleConstants.STATE_SHAKEN_MIN:
		return MoraleEvent.State.SHAKEN
	else:
		return MoraleEvent.State.BROKEN


func _is_safe_for_recovery() -> bool:
	## Check if soldier has been safe long enough for natural recovery.
	# Only recover if not under negative continuous effects
	var negative_continuous: bool = false
	for source in _continuous_modifiers:
		if _continuous_modifiers[source] < 0.0:
			negative_continuous = true
			break

	return not negative_continuous and _time_since_last_hit >= 2.0


func _check_rally_conditions() -> void:
	## Check if soldier can begin or complete rallying.
	if current_state == MoraleEvent.State.BROKEN:
		# Can we start rallying?
		if not _is_rallying:
			if _time_since_last_hit >= MoraleConstants.RALLY_SAFETY_TIME:
				if current_morale >= MoraleConstants.RALLY_MORALE_THRESHOLD:
					_is_rallying = true
		# Have we recovered enough to stop being broken?
		elif current_morale >= MoraleConstants.RALLY_SUCCESS_THRESHOLD:
			_is_rallying = false
			# State will update on next tick
	else:
		_is_rallying = false

# =============================================================================
# QUERIES
# =============================================================================

func get_effectiveness() -> float:
	## Returns combat effectiveness multiplier based on current state.
	return MoraleConstants.get_effectiveness_for_state(current_state)


func get_morale() -> float:
	## Returns current morale value (0-100).
	return current_morale


func get_morale_ratio() -> float:
	## Returns morale as ratio (0.0-1.0).
	return current_morale / 100.0


func get_state() -> MoraleEvent.State:
	## Returns current morale state.
	return current_state


func is_broken() -> bool:
	## Returns true if soldier has broken.
	return current_state == MoraleEvent.State.BROKEN


func is_steady() -> bool:
	## Returns true if morale is high.
	return current_state == MoraleEvent.State.STEADY


func is_rallying() -> bool:
	## Returns true if actively rallying.
	return _is_rallying

# =============================================================================
# LIFECYCLE
# =============================================================================

func kill() -> void:
	## Called when the soldier dies.
	_is_alive = false
	clear_all_continuous_modifiers()


func revive(starting_morale: float = 50.0) -> void:
	## Reset for respawn/reuse.
	_is_alive = true
	current_morale = starting_morale
	_time_since_last_hit = 0.0
	_is_rallying = false
	clear_all_continuous_modifiers()
	_update_state()


func is_alive() -> bool:
	## Returns true if soldier is alive.
	return _is_alive

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	## Returns debug information for visualization.
	return {
		"morale": current_morale,
		"state": MoraleEvent.State.keys()[current_state],
		"effectiveness": get_effectiveness(),
		"is_rallying": _is_rallying,
		"time_safe": _time_since_last_hit,
		"continuous_modifiers": _continuous_modifiers.duplicate(),
	}
