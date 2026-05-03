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

const EXHAUSTED_THRESHOLD: float = 10.0    # Below this = exhausted
const EXHAUSTED_SPEED_PENALTY: float = 0.5 # 50% speed when exhausted
const EXHAUSTED_COMBAT_PENALTY: float = 0.8 # 80% combat effectiveness

enum MovementMode {
	IDLE,
	WALKING,
	RUNNING,
	CHARGING,
}

var current_stamina: float = MAX_STAMINA
var movement_mode: MovementMode = MovementMode.IDLE
var is_exhausted: bool = false

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
			current_stamina = maxf(current_stamina - RUN_DRAIN_RATE * delta, 0.0)
		MovementMode.CHARGING:
			current_stamina = maxf(current_stamina - CHARGE_DRAIN_RATE * delta, 0.0)

	# Check for exhaustion state change
	var was_exhausted: bool = is_exhausted
	is_exhausted = current_stamina < EXHAUSTED_THRESHOLD

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
	if is_exhausted:
		return EXHAUSTED_SPEED_PENALTY
	return 1.0


func get_combat_modifier() -> float:
	if is_exhausted:
		return EXHAUSTED_COMBAT_PENALTY
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
