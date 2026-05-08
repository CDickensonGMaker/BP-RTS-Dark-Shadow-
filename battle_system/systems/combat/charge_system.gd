class_name ChargeSystem
extends RefCounted

## Handles charge impact, bracing, and charge bonus decay.
## Includes weather modifiers for charge effectiveness.
## Extracted from CombatManager for single responsibility.

# Preload FlankingCalculator to avoid class_name parse order issues
const FlankingCalculatorScript = preload("res://battle_system/systems/combat/flanking_calculator.gd")

# Weather system reference (autoload)
var _weather_system: Node

# Charge constants
const CHARGE_BONUS_DURATION: float = 3.0
const CHARGE_DECAY_DURATION: float = 10.0  # Charge bonus decays linearly over 10 seconds
const CHARGE_KNOCKBACK_FORCE: float = 2.0  # Units pushed back on charge impact
const CHARGE_AP_RATIO: float = 0.7  # 70% of impact damage is armor-piercing

# Large unit knockback constants (rock-paper-scissors Part 2)
const KNOCKBACK_MASS_THRESHOLD: float = 1.5
const KNOCKBACK_BASE_DISTANCE: float = 5.0
const KNOCKBACK_CASUALTY_THRESHOLD: int = 3
const KNOCKBACK_SCATTER_MULTIPLIER: float = 1.5

# Reference to flanking calculator for frontal attack check
var flanking  # FlankingCalculator


func _init() -> void:
	flanking = FlankingCalculatorScript.new()


## Get weather system reference (cached).
func _get_weather_system() -> Node:
	if not _weather_system:
		if Engine.has_singleton("WeatherSystem"):
			_weather_system = Engine.get_singleton("WeatherSystem")
		elif Engine.get_main_loop().root.has_node("/root/WeatherSystem"):
			_weather_system = Engine.get_main_loop().root.get_node("/root/WeatherSystem")
	return _weather_system


## Get weather charge bonus modifier (1.0 = no change, <1.0 = reduced in rain).
func _get_weather_charge_mod() -> float:
	var ws := _get_weather_system()
	if ws and ws.has_method("get_charge_bonus_modifier"):
		return ws.get_charge_bonus_modifier()
	return 1.0


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
		"is_frontal": false,
		"knockback_distance": 0.0,
		"knockback_direction": Vector3.ZERO,
		"triggered_knockback": false,
		"is_monster_impact": false
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

	# Check for large unit knockback (rock-paper-scissors Part 2)
	var mass_ratio: float = attacker.data.mass / defender.data.mass
	if mass_ratio >= KNOCKBACK_MASS_THRESHOLD and result.impact_casualties >= KNOCKBACK_CASUALTY_THRESHOLD:
		result.knockback_distance = KNOCKBACK_BASE_DISTANCE * mass_ratio
		result.knockback_direction = (defender.global_position - attacker.global_position).normalized()
		result.triggered_knockback = true
		if attacker.data.unit_type == UnitType.Type.MONSTER:
			result.knockback_distance *= 1.5
			result.is_monster_impact = true

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
## Includes weather modifier (rain reduces charge effectiveness due to slippery ground).
func get_charge_damage_bonus(attacker: Node, time_since_charge: float) -> int:
	if not attacker.data:
		return 0

	var base_bonus: int = attacker.data.charge_bonus if "charge_bonus" in attacker.data else 0
	var decay: float = get_charge_bonus_decay(time_since_charge)
	var weather_mod: float = _get_weather_charge_mod()
	return int(float(base_bonus) * decay * weather_mod)


## Check if a unit can brace against a charge.
func can_brace_against(defender: Node, attacker: Node) -> bool:
	# Must be braced
	if not defender.is_braced:
		return false

	# Must be a frontal attack
	if not flanking.is_frontal_attack(attacker, defender):
		return false

	return true
