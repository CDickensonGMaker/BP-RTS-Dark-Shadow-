class_name StaminaSystem
extends RefCounted

## Manages unit stamina for movement and abilities.
## Stamina drains during running/charging and recovers when walking/idle.

# Constants per bible §6.3
const MAX_STAMINA: float = 100.0
const WALK_RECOVERY_RATE: float = 5.0      # Per second while walking
const IDLE_RECOVERY_RATE: float = 10.0     # Per second while idle
const RUN_DRAIN_RATE: float = 8.0          # Per second while running
const CHARGE_DRAIN_RATE: float = 15.0      # Per second while charging

# TotalWarSimulator fatigue thresholds
const WINDED_THRESHOLD: float = 70.0       # Below this = winded
const TIRED_THRESHOLD: float = 40.0        # Below this = tired
const EXHAUSTED_THRESHOLD: float = 10.0    # Below this = exhausted

# TotalWarSimulator fatigue penalties (attack/speed)
const WINDED_COMBAT_PENALTY: float = 0.95  # 5% penalty when winded
const TIRED_COMBAT_PENALTY: float = 0.90   # 10% penalty when tired
const EXHAUSTED_ATTACK_PENALTY: float = 0.80   # 20% attack penalty when exhausted
const EXHAUSTED_DEFENSE_PENALTY: float = 0.85  # 15% defense penalty when exhausted

const WINDED_SPEED_PENALTY: float = 0.95   # 5% slower
const TIRED_SPEED_PENALTY: float = 0.85    # 15% slower
const EXHAUSTED_SPEED_PENALTY: float = 0.5 # 50% speed when exhausted

enum MovementMode {
	IDLE,
	WALKING,
	RUNNING,
	CHARGING,
}

enum FatigueState {
	FRESH,      # > WINDED_THRESHOLD
	WINDED,     # TIRED_THRESHOLD to WINDED_THRESHOLD
	TIRED,      # EXHAUSTED_THRESHOLD to TIRED_THRESHOLD
	EXHAUSTED,  # < EXHAUSTED_THRESHOLD
}

var current_stamina: float = MAX_STAMINA
var movement_mode: MovementMode = MovementMode.IDLE
var is_exhausted: bool = false
var fatigue_state: FatigueState = FatigueState.FRESH

# Armor weight multiplier (heavy armor = faster fatigue drain)
# Light (0-3): 1.0x, Medium (4-7): 1.25x, Heavy (8+): 1.5x
var armor_fatigue_multiplier: float = 1.0

signal stamina_changed(new_value: float, max_value: float)
signal exhausted()
signal recovered()


func update(delta: float) -> void:
	var old_stamina: float = current_stamina

	match movement_mode:
		MovementMode.IDLE:
			current_stamina = minf(current_stamina + IDLE_RECOVERY_RATE * delta, MAX_STAMINA)
		MovementMode.WALKING:
			current_stamina = minf(current_stamina + WALK_RECOVERY_RATE * delta, MAX_STAMINA)
		MovementMode.RUNNING:
			# Heavy armor drains stamina faster (Stainless Steel pattern)
			current_stamina = maxf(current_stamina - RUN_DRAIN_RATE * armor_fatigue_multiplier * delta, 0.0)
		MovementMode.CHARGING:
			# Heavy armor drains stamina faster during charges
			current_stamina = maxf(current_stamina - CHARGE_DRAIN_RATE * armor_fatigue_multiplier * delta, 0.0)

	# Check for fatigue state change (TotalWarSimulator)
	var _old_state: FatigueState = fatigue_state
	var was_exhausted: bool = is_exhausted

	if current_stamina < EXHAUSTED_THRESHOLD:
		fatigue_state = FatigueState.EXHAUSTED
	elif current_stamina < TIRED_THRESHOLD:
		fatigue_state = FatigueState.TIRED
	elif current_stamina < WINDED_THRESHOLD:
		fatigue_state = FatigueState.WINDED
	else:
		fatigue_state = FatigueState.FRESH

	is_exhausted = fatigue_state == FatigueState.EXHAUSTED

	if is_exhausted and not was_exhausted:
		exhausted.emit()
	elif not is_exhausted and was_exhausted:
		recovered.emit()

	# Emit change signal
	if absf(current_stamina - old_stamina) > 0.1:
		stamina_changed.emit(current_stamina, MAX_STAMINA)


func set_movement_mode(mode: MovementMode) -> void:
	# Can't run/charge if exhausted
	if is_exhausted and mode in [MovementMode.RUNNING, MovementMode.CHARGING]:
		movement_mode = MovementMode.WALKING
		return
	movement_mode = mode


func can_run() -> bool:
	return not is_exhausted


func can_charge() -> bool:
	return current_stamina >= 20.0  # Need at least 20% to start a charge


func get_speed_modifier() -> float:
	## Returns speed multiplier based on fatigue state (TotalWarSimulator).
	match fatigue_state:
		FatigueState.WINDED:
			return WINDED_SPEED_PENALTY
		FatigueState.TIRED:
			return TIRED_SPEED_PENALTY
		FatigueState.EXHAUSTED:
			return EXHAUSTED_SPEED_PENALTY
	return 1.0


func get_combat_modifier() -> float:
	## Returns attack modifier based on fatigue state (TotalWarSimulator).
	## Note: For exhausted state, this returns attack penalty (0.80).
	## Use get_defense_modifier() for separate defense penalty.
	match fatigue_state:
		FatigueState.WINDED:
			return WINDED_COMBAT_PENALTY
		FatigueState.TIRED:
			return TIRED_COMBAT_PENALTY
		FatigueState.EXHAUSTED:
			return EXHAUSTED_ATTACK_PENALTY
	return 1.0


func get_defense_modifier() -> float:
	## Returns defense modifier based on fatigue state (TotalWarSimulator).
	## Only exhausted state has different defense penalty.
	match fatigue_state:
		FatigueState.WINDED:
			return WINDED_COMBAT_PENALTY  # Same as attack for winded/tired
		FatigueState.TIRED:
			return TIRED_COMBAT_PENALTY
		FatigueState.EXHAUSTED:
			return EXHAUSTED_DEFENSE_PENALTY
	return 1.0


func consume_stamina(amount: float) -> bool:
	## Consume stamina for an ability. Returns true if successful.
	if current_stamina >= amount:
		current_stamina -= amount
		stamina_changed.emit(current_stamina, MAX_STAMINA)
		return true
	return false


func get_ratio() -> float:
	return current_stamina / MAX_STAMINA


func reset() -> void:
	current_stamina = MAX_STAMINA
	is_exhausted = false
	movement_mode = MovementMode.IDLE


func setup_from_regiment_data(regiment_data: RegimentData) -> void:
	## Configure stamina system based on regiment data.
	## Applies armor weight fatigue penalty (Stainless Steel pattern).
	if regiment_data:
		armor_fatigue_multiplier = regiment_data.get_armor_fatigue_multiplier()
