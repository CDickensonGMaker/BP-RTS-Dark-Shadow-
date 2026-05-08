class_name CasualtyTracker
extends RefCounted

## Tracks casualties over a rolling window to trigger behavior thresholds.
## Based on Stainless Steel's casualty-based morale and behavior system.
##
## Thresholds:
## - 15% loss: CAUTION - drop to DEFENSIVE stance
## - 50% loss: WITHDRAW - begin fighting withdrawal
## - 75% loss: ROUT - force immediate rout
##
## Elite units have an 8-second delay before behavior changes.
## Cascade pressure from nearby units can inflate perceived losses.

# =============================================================================
# SIGNALS
# =============================================================================

signal threshold_reached(threshold_name: String, loss_percent: float)

# =============================================================================
# CONSTANTS
# =============================================================================

const WINDOW_DURATION: float = 30.0  # Rolling window in seconds
const SAMPLE_INTERVAL: float = 1.0   # How often to sample soldier count

const CAUTION_THRESHOLD: float = 0.15   # 15% loss
const WITHDRAW_THRESHOLD: float = 0.50  # 50% loss
const ROUT_THRESHOLD: float = 0.75      # 75% loss

const ELITE_DELAY: float = 8.0  # Seconds before elite units react

# =============================================================================
# PROPERTIES
# =============================================================================

## Reference to the regiment being tracked
var regiment: Node = null

## Is this an elite unit (delayed reactions)
var is_elite: bool = false

## Rolling window of soldier counts: Array of {time: float, count: int}
var _soldier_samples: Array = []

## Initial soldier count at start of tracking (for percentage calculation)
var _starting_soldiers: int = 0

## One-way flags - once tripped, stay tripped
var _caution_triggered: bool = false
var _withdraw_triggered: bool = false
var _rout_triggered: bool = false

## Elite delay timers
var _caution_delay_timer: float = 0.0
var _withdraw_delay_timer: float = 0.0
var _rout_delay_timer: float = 0.0

## Pending thresholds waiting for elite delay
var _pending_caution: bool = false
var _pending_withdraw: bool = false
var _pending_rout: bool = false

## Cascade pressure from nearby units (inflates perceived loss)
## Decays at 0.02/sec
var cascade_pressure: float = 0.0

## Ranged damage tracking for UNDER_FIRE morale modifier
var _last_ranged_damage_time: float = 0.0
const UNDER_FIRE_DURATION: float = 3.0  # Consider "under fire" for 3 seconds after hit

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_regiment: Node = null, p_is_elite: bool = false) -> void:
	regiment = p_regiment
	is_elite = p_is_elite
	if regiment:
		_starting_soldiers = regiment.current_soldiers
		_soldier_samples.append({
			"time": Time.get_ticks_msec() / 1000.0,
			"count": _starting_soldiers
		})


func set_starting_soldiers(count: int) -> void:
	## Set the starting soldier count for percentage calculation.
	_starting_soldiers = count


func reset() -> void:
	## Reset the tracker for a new battle.
	_soldier_samples.clear()
	_caution_triggered = false
	_withdraw_triggered = false
	_rout_triggered = false
	_caution_delay_timer = 0.0
	_withdraw_delay_timer = 0.0
	_rout_delay_timer = 0.0
	_pending_caution = false
	_pending_withdraw = false
	_pending_rout = false
	cascade_pressure = 0.0
	if regiment:
		_starting_soldiers = regiment.current_soldiers

# =============================================================================
# SAMPLING
# =============================================================================

func sample(current_time: float) -> void:
	## Record current soldier count and remove old samples.
	if not regiment:
		return

	# Add new sample
	_soldier_samples.append({
		"time": current_time,
		"count": regiment.current_soldiers
	})

	# Remove samples older than the window
	var cutoff: float = current_time - WINDOW_DURATION
	while _soldier_samples.size() > 1 and _soldier_samples[0].time < cutoff:
		_soldier_samples.pop_front()


func tick(delta: float) -> void:
	## Update timers and decay cascade pressure.

	# Decay cascade pressure
	cascade_pressure = maxf(0.0, cascade_pressure - 0.02 * delta)

	# Update elite delay timers
	if is_elite:
		if _pending_caution and not _caution_triggered:
			_caution_delay_timer += delta
			if _caution_delay_timer >= ELITE_DELAY:
				_caution_triggered = true
				threshold_reached.emit("caution", get_loss_pct_in_window())

		if _pending_withdraw and not _withdraw_triggered:
			_withdraw_delay_timer += delta
			if _withdraw_delay_timer >= ELITE_DELAY:
				_withdraw_triggered = true
				threshold_reached.emit("withdraw", get_loss_pct_in_window())

		if _pending_rout and not _rout_triggered:
			_rout_delay_timer += delta
			if _rout_delay_timer >= ELITE_DELAY:
				_rout_triggered = true
				threshold_reached.emit("rout", get_loss_pct_in_window())

# =============================================================================
# THRESHOLD CHECKING
# =============================================================================

func check_thresholds(aura_bonus: float = 0.0) -> String:
	## Check if any threshold has been crossed.
	## aura_bonus: Threshold tolerance boost from nearby general/hero aura.
	## Returns: "caution", "withdraw", "rout", or "" if no new threshold.

	var loss_pct: float = get_loss_pct_in_window()

	# Apply aura bonus to thresholds (makes unit more resilient)
	var effective_caution: float = CAUTION_THRESHOLD + aura_bonus
	var effective_withdraw: float = WITHDRAW_THRESHOLD + aura_bonus
	var effective_rout: float = ROUT_THRESHOLD + aura_bonus

	# Check rout first (highest priority)
	if loss_pct >= effective_rout and not _rout_triggered:
		if is_elite:
			_pending_rout = true
			return ""  # Wait for delay
		else:
			_rout_triggered = true
			threshold_reached.emit("rout", loss_pct)
			return "rout"

	# Check withdraw
	if loss_pct >= effective_withdraw and not _withdraw_triggered:
		if is_elite:
			_pending_withdraw = true
			return ""  # Wait for delay
		else:
			_withdraw_triggered = true
			threshold_reached.emit("withdraw", loss_pct)
			return "withdraw"

	# Check caution
	if loss_pct >= effective_caution and not _caution_triggered:
		if is_elite:
			_pending_caution = true
			return ""  # Wait for delay
		else:
			_caution_triggered = true
			threshold_reached.emit("caution", loss_pct)
			return "caution"

	return ""

# =============================================================================
# QUERIES
# =============================================================================

func get_loss_pct_in_window() -> float:
	## Get percentage of soldiers lost within the rolling window.
	## Includes cascade pressure inflation.
	if _soldier_samples.size() < 2 or _starting_soldiers <= 0:
		return 0.0

	var oldest_count: int = _soldier_samples[0].count
	var newest_count: int = _soldier_samples[-1].count

	var raw_loss: int = oldest_count - newest_count
	if raw_loss <= 0:
		return cascade_pressure  # No actual loss, just cascade pressure

	# Edge case: oldest_count is 0 (shouldn't happen, but defensive)
	if oldest_count <= 0:
		return cascade_pressure

	# Calculate percentage based on window-start count (not battle-start)
	# This ensures threshold triggers correctly as unit shrinks
	var loss_pct: float = float(raw_loss) / float(oldest_count)

	# Add cascade pressure
	loss_pct += cascade_pressure

	return loss_pct


func get_total_loss_pct() -> float:
	## Get total percentage of soldiers lost since battle start.
	if _starting_soldiers <= 0 or not regiment:
		return 0.0

	var lost: int = _starting_soldiers - regiment.current_soldiers
	return float(lost) / float(_starting_soldiers)


func is_caution() -> bool:
	return _caution_triggered


func is_withdrawing() -> bool:
	return _withdraw_triggered


func is_routed() -> bool:
	return _rout_triggered


func add_cascade_pressure(amount: float) -> void:
	## Add cascade pressure from nearby unit failures.
	cascade_pressure += amount


func record_ranged_damage() -> void:
	## Called when regiment takes ranged damage - sets under fire timer.
	_last_ranged_damage_time = Time.get_ticks_msec() / 1000.0


func took_ranged_damage_recently() -> bool:
	## Returns true if regiment took ranged damage within UNDER_FIRE_DURATION.
	var now: float = Time.get_ticks_msec() / 1000.0
	return (now - _last_ranged_damage_time) < UNDER_FIRE_DURATION

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"samples": _soldier_samples.size(),
		"starting_soldiers": _starting_soldiers,
		"loss_pct_window": get_loss_pct_in_window(),
		"loss_pct_total": get_total_loss_pct(),
		"cascade_pressure": cascade_pressure,
		"caution": _caution_triggered,
		"withdraw": _withdraw_triggered,
		"rout": _rout_triggered,
		"is_elite": is_elite,
	}
