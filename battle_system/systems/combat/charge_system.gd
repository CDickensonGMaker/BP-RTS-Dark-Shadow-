class_name ChargeSystem
extends RefCounted

## Handles charge impact, bracing, and charge bonus decay.
## Extracted from CombatManager for single responsibility.

# Preload FlankingCalculator to avoid class_name parse order issues
const FlankingCalculatorScript = preload("res://battle_system/systems/combat/flanking_calculator.gd")

# Charge constants
const CHARGE_BONUS_DURATION: float = 3.0
const CHARGE_DECAY_DURATION: float = 10.0  # Charge bonus decays linearly over 10 seconds
const CHARGE_KNOCKBACK_FORCE: float = 2.0  # Units pushed back on charge impact
const CHARGE_AP_RATIO: float = 0.7  # 70% of impact damage is armor-piercing

# Reference to flanking calculator for frontal attack check
var flanking  # FlankingCalculator


func _init() -> void:
	flanking = FlankingCalculatorScript.new()


## Process charge impact when melee begins.
## Returns Dictionary with charge results:
## - "valid_charge": bool - whether charge bonus applies
## - "charge_negated": bool - whether defender's brace negated the charge
## - "impact_damage": int - damage dealt by charge impact
## - "impact_casualties": int - casualties from impact
func process_charge_impact(attacker: Node, defender: Node) -> Dictionary:
	var result: Dictionary = {
		"valid_charge": false,
		"charge_negated": false,
		"impact_damage": 0,
		"impact_casualties": 0,
		"was_braced": false,
		"is_frontal": false
	}

	# Check if this is actually a charge order
	if attacker.current_order != OrderType.Type.CHARGE:
		return result

	# Check if charge traveled minimum distance
	if not attacker.has_valid_charge():
		return result

	result.valid_charge = true
	result.was_braced = defender.is_braced
	result.is_frontal = flanking.is_frontal_attack(attacker, defender)

	# Check if bracing applies (frontal charges only)
	if result.was_braced and result.is_frontal:
		# Defender braced against frontal charge - negate bonus
		result.charge_negated = true
		return result

	# Successful charge impact - calculate impact damage
	var impact_damage: int = _get_charge_impact_damage(attacker)
	if impact_damage > 0:
		result.impact_damage = impact_damage
		# Impact causes instant casualties (1 per 3 damage, min 1)
		result.impact_casualties = maxi(1, impact_damage / 3)

	return result


## Calculate charge impact damage based on regiment stats.
func _get_charge_impact_damage(attacker: Node) -> int:
	if not attacker.has_method("get_charge_impact_damage"):
		# Fallback calculation
		if attacker.data:
			var mass: float = attacker.data.mass if "mass" in attacker.data else 1.0
			var speed: float = attacker.data.charge_speed if "charge_speed" in attacker.data else 1.5
			return int(mass * speed * 2.0)
		return 0
	return attacker.get_charge_impact_damage()


## Get the current charge bonus multiplier based on time since impact.
## Returns value between 1.0 (full bonus) and 0.0 (no bonus).
func get_charge_bonus_decay(time_since_charge: float) -> float:
	if time_since_charge >= CHARGE_DECAY_DURATION:
		return 0.0
	return 1.0 - (time_since_charge / CHARGE_DECAY_DURATION)


## Calculate total charge bonus for damage.
func get_charge_damage_bonus(attacker: Node, time_since_charge: float) -> int:
	if not attacker.data:
		return 0

	var base_bonus: int = attacker.data.charge_bonus if "charge_bonus" in attacker.data else 0
	var decay: float = get_charge_bonus_decay(time_since_charge)
	return int(float(base_bonus) * decay)


## Check if a unit can brace against a charge.
func can_brace_against(defender: Node, attacker: Node) -> bool:
	# Must be braced
	if not defender.is_braced:
		return false

	# Must be a frontal attack
	if not flanking.is_frontal_attack(attacker, defender):
		return false

	return true
