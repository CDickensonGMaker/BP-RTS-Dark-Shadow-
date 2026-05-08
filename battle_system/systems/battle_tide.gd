extends Node

## BattleTide - Tracks the overall momentum of the battle.
##
## The tide ranges from -100 (enemy winning) to +100 (player winning).
## Various battle events affect the tide, and the tide in turn affects:
## - Morale floors/ceilings
## - AI play scoring
## - Charge damage bonuses
##
## Add as autoload: BattleTide

# =============================================================================
# SIGNALS
# =============================================================================

signal tide_changed(old_value: float, new_value: float)
signal tide_threshold_crossed(is_player_winning: bool)

# =============================================================================
# CONSTANTS
# =============================================================================

# Tide range
const TIDE_MIN: float = -100.0
const TIDE_MAX: float = 100.0

# Decay rate toward neutral (per second)
const DECAY_RATE: float = 1.0

# Event impact values
const IMPACT_REGIMENT_KILLED: float = 15.0    # Regiment wiped out
const IMPACT_REGIMENT_ROUTED: float = 8.0     # Regiment routed
const IMPACT_FLANK_ATTACK: float = 3.0        # Successful flank
const IMPACT_REAR_ATTACK: float = 5.0         # Successful rear attack
const IMPACT_GENERAL_KILLED: float = 30.0     # General/hero died
const IMPACT_CHARGE_SUCCESS: float = 4.0      # Successful charge impact
const IMPACT_RALLY_SUCCESS: float = 10.0      # Units rallied

# Threshold for "winning" effects
const WINNING_THRESHOLD: float = 30.0
const LOSING_THRESHOLD: float = -30.0

# Modifier scales
const MORALE_MODIFIER_MAX: float = 5.0       # ±5 morale based on tide
const CHARGE_MODIFIER_MAX: float = 0.15      # ±15% charge damage

# =============================================================================
# STATE
# =============================================================================

## Current tide value (-100 to +100, positive = player winning)
var current_tide: float = 0.0

## Was the player winning last check (for threshold crossing detection)
var _was_player_winning: bool = false
var _was_enemy_winning: bool = false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	# Connect to battle signals
	if BattleSignals:
		BattleSignals.regiment_dead.connect(_on_regiment_dead)
		BattleSignals.regiment_routing.connect(_on_regiment_routing)
		BattleSignals.unit_flanked.connect(_on_unit_flanked)
		BattleSignals.charge_impact.connect(_on_charge_impact)
		BattleSignals.rally_used.connect(_on_rally_used)
		BattleSignals.battle_started.connect(_on_battle_started)
		BattleSignals.battle_ended.connect(_on_battle_ended)


func _on_battle_started() -> void:
	reset()


func _on_battle_ended(_result: Dictionary) -> void:
	# Optional: could record final tide in result
	pass

# =============================================================================
# PROCESSING
# =============================================================================

func _process(delta: float) -> void:
	# Decay tide toward neutral
	if current_tide > 0.0:
		current_tide = maxf(0.0, current_tide - DECAY_RATE * delta)
	elif current_tide < 0.0:
		current_tide = minf(0.0, current_tide + DECAY_RATE * delta)

	# Check threshold crossings
	_check_thresholds()

# =============================================================================
# EVENT HANDLERS
# =============================================================================

func _on_regiment_dead(regiment: Regiment) -> void:
	if not is_instance_valid(regiment):
		return

	var impact: float = IMPACT_REGIMENT_KILLED
	if regiment.data and regiment.data.has_aura:
		# General/hero died - extra impact
		impact = IMPACT_GENERAL_KILLED

	if regiment.is_player_controlled:
		shift_tide(-impact)  # Player loss
	else:
		shift_tide(impact)   # Enemy loss


func _on_regiment_routing(regiment: Regiment) -> void:
	if not is_instance_valid(regiment):
		return

	if regiment.is_player_controlled:
		shift_tide(-IMPACT_REGIMENT_ROUTED)  # Player routing = bad
	else:
		shift_tide(IMPACT_REGIMENT_ROUTED)   # Enemy routing = good


func _on_unit_flanked(flanked: Regiment, flanker: Regiment, is_rear: bool) -> void:
	if not is_instance_valid(flanked) or not is_instance_valid(flanker):
		return

	var impact: float = IMPACT_REAR_ATTACK if is_rear else IMPACT_FLANK_ATTACK

	if flanker.is_player_controlled:
		shift_tide(impact)   # Player flanked enemy
	else:
		shift_tide(-impact)  # Enemy flanked player


func _on_charge_impact(charger: Regiment, _target: Regiment, was_braced: bool) -> void:
	if was_braced:
		return  # Braced charge = no momentum swing

	if not is_instance_valid(charger):
		return

	if charger.is_player_controlled:
		shift_tide(IMPACT_CHARGE_SUCCESS)
	else:
		shift_tide(-IMPACT_CHARGE_SUCCESS)


func _on_rally_used(general: Node, units_rallied: int) -> void:
	if not is_instance_valid(general):
		return
	if units_rallied <= 0:
		return

	# Scale impact by number of units rallied (cap at 3)
	var impact: float = IMPACT_RALLY_SUCCESS * minf(float(units_rallied), 3.0) / 3.0

	if general.is_player_controlled:
		shift_tide(impact)
	else:
		shift_tide(-impact)

# =============================================================================
# TIDE MODIFICATION
# =============================================================================

func shift_tide(amount: float) -> void:
	## Shift the tide by the given amount.
	## Positive = player advantage, Negative = enemy advantage.
	var old_tide: float = current_tide
	current_tide = clampf(current_tide + amount, TIDE_MIN, TIDE_MAX)

	if current_tide != old_tide:
		tide_changed.emit(old_tide, current_tide)
		if DebugFlags and DebugFlags.tide:
			print("[TIDE] %.1f -> %.1f (shift: %+.1f)" % [old_tide, current_tide, amount])


func reset() -> void:
	## Reset tide to neutral.
	current_tide = 0.0
	_was_player_winning = false
	_was_enemy_winning = false


func _check_thresholds() -> void:
	## Check if tide crossed winning/losing thresholds.
	var player_winning: bool = current_tide >= WINNING_THRESHOLD
	var enemy_winning: bool = current_tide <= LOSING_THRESHOLD

	if player_winning and not _was_player_winning:
		tide_threshold_crossed.emit(true)
		if DebugFlags and DebugFlags.tide:
			print("[TIDE] Player gaining the upper hand!")
	elif enemy_winning and not _was_enemy_winning:
		tide_threshold_crossed.emit(false)
		if DebugFlags and DebugFlags.tide:
			print("[TIDE] Enemy gaining the upper hand!")

	_was_player_winning = player_winning
	_was_enemy_winning = enemy_winning

# =============================================================================
# QUERIES
# =============================================================================

func get_tide() -> float:
	## Returns current tide value (-100 to +100).
	return current_tide


func get_tide_ratio() -> float:
	## Returns tide as -1.0 to +1.0.
	return current_tide / 100.0


func is_player_winning() -> bool:
	## Returns true if player has significant advantage.
	return current_tide >= WINNING_THRESHOLD


func is_enemy_winning() -> bool:
	## Returns true if enemy has significant advantage.
	return current_tide <= LOSING_THRESHOLD


func is_contested() -> bool:
	## Returns true if battle is evenly matched.
	return current_tide > LOSING_THRESHOLD and current_tide < WINNING_THRESHOLD

# =============================================================================
# MODIFIER GETTERS
# =============================================================================

func get_morale_modifier(is_player: bool) -> float:
	## Get morale modifier based on tide.
	## Returns +/- up to MORALE_MODIFIER_MAX.
	var ratio: float = current_tide / 100.0

	if is_player:
		return ratio * MORALE_MODIFIER_MAX  # Positive tide = morale boost
	else:
		return -ratio * MORALE_MODIFIER_MAX  # Positive tide = enemy morale penalty


func get_charge_modifier(is_player: bool) -> float:
	## Get charge damage modifier based on tide.
	## Returns 1.0 +/- CHARGE_MODIFIER_MAX.
	var ratio: float = current_tide / 100.0

	if is_player:
		return 1.0 + (ratio * CHARGE_MODIFIER_MAX)  # 0.85 to 1.15
	else:
		return 1.0 - (ratio * CHARGE_MODIFIER_MAX)  # 1.15 to 0.85


func get_ai_play_modifier() -> float:
	## Get modifier for AI play scoring.
	## Positive = AI should prefer aggressive plays.
	## Negative = AI should prefer defensive plays.
	return -get_tide_ratio()  # Invert: positive tide = AI should be defensive
