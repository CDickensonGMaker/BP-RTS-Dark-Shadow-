class_name RangedResolver
extends RefCounted

## Handles ranged damage calculations.
## Total War style: arrows hit formations easily, armor saves block damage.
## Includes terrain modifiers for height, cover, and concealment.
## Includes weather modifiers for accuracy and range.
## Extracted from CombatManager for single responsibility.

# Preload terrain modifiers
const TerrainCombatModifiersScript = preload("res://battle_system/terrain/terrain_combat_modifiers.gd")
const MatchupCalculatorScript = preload("res://battle_system/systems/combat/matchup_calculator.gd")

# Weather system reference (autoload)
var _weather_system: Node

# Ranged combat constants - Total War style
# Arrows land on formations easily, armor determines if damage is blocked
const RANGED_ACCURACY_PER_SKILL: float = 0.01  # +1% per ballistic skill point
const BASE_RANGED_ACCURACY: float = 0.80  # 80% base - arrows hit standing formations
const MIN_RANGED_ACCURACY: float = 0.40  # Minimum 40% even at max range
const MAX_RANGED_ACCURACY: float = 0.95  # Maximum 95%

# Armor save constants
# Armor 0 = 0% save, Armor 5 = 25% save, Armor 10 = 50% save
const ARMOR_SAVE_PER_POINT: float = 0.05  # 5% save chance per armor point
const MAX_ARMOR_SAVE: float = 0.65  # Cap at 65% save chance

# Range falloff (less harsh than before)
const EFFECTIVE_RANGE_RATIO: float = 0.5  # Full accuracy within 50% of max range
const MAX_RANGE_PENALTY: float = 0.6  # 60% accuracy at max range (was 50%)

# Damage scaling
const RANGED_STRENGTH_MULTIPLIER: float = 0.8  # Ranged strength slightly less than melee


## Get weather system reference (cached).
func _get_weather_system() -> Node:
	if not _weather_system:
		if Engine.has_singleton("WeatherSystem"):
			_weather_system = Engine.get_singleton("WeatherSystem")
		elif Engine.get_main_loop().root.has_node("/root/WeatherSystem"):
			_weather_system = Engine.get_main_loop().root.get_node("/root/WeatherSystem")
	return _weather_system


## Get weather accuracy modifier (1.0 = no change).
func _get_weather_accuracy_mod() -> float:
	var ws := _get_weather_system()
	if ws and ws.has_method("get_ranged_accuracy_modifier"):
		return ws.get_ranged_accuracy_modifier()
	return 1.0


## Get weather range modifier (1.0 = no change).
func _get_weather_range_mod() -> float:
	var ws := _get_weather_system()
	if ws and ws.has_method("get_ranged_range_modifier"):
		return ws.get_ranged_range_modifier()
	return 1.0


## Check if weather blocks LOS at distance.
func _weather_blocks_los(distance: float) -> bool:
	var ws := _get_weather_system()
	if ws and ws.has_method("blocks_los"):
		return ws.blocks_los(distance)
	return false


## Calculate ranged hit chance (arrows landing on formation).
func calculate_accuracy(attacker: Node, defender: Node) -> float:
	var ballistic_skill: int = attacker.data.ballistic_skill if attacker.data else 10
	var base_acc: float = BASE_RANGED_ACCURACY + (float(ballistic_skill) * RANGED_ACCURACY_PER_SKILL)

	# Range falloff
	var distance: float = attacker.global_position.distance_to(defender.global_position)
	var max_range: float = attacker.data.range_distance if attacker.data else 50.0
	var effective_range: float = max_range * EFFECTIVE_RANGE_RATIO

	var range_mod: float = 1.0
	if distance > effective_range and max_range > effective_range:
		# Linear falloff from effective range to max range
		var falloff_ratio: float = (distance - effective_range) / (max_range - effective_range)
		range_mod = lerpf(1.0, MAX_RANGE_PENALTY, clampf(falloff_ratio, 0.0, 1.0))

	# Target size modifier (larger targets easier to hit)
	var size_mod: float = 1.0
	if defender.data and defender.data.unit_type == UnitType.Type.CAVALRY:
		size_mod = 1.1  # Cavalry slightly bigger target
	elif defender.data and defender.data.unit_type == UnitType.Type.ARTILLERY:
		size_mod = 1.15  # Artillery largest

	# Moving target penalty
	var movement_mod: float = 1.0
	if defender.state == Regiment.State.MARCHING:
		movement_mod = 0.90  # Moving targets slightly harder to hit
	elif defender.state == Regiment.State.ROUTING:
		movement_mod = 0.85  # Routing units are fleeing/erratic

	# Apply unit type matchup modifier (ranged units vs target types)
	var matchup_mod: float = 1.0
	if attacker.data:
		var target_type: UnitType.Type = defender.data.unit_type if defender.data else UnitType.Type.INFANTRY
		matchup_mod = MatchupCalculatorScript.get_ranged_matchup(attacker.data.unit_type, target_type)

	# Apply weather modifier (rain/storm reduce accuracy)
	var weather_mod: float = _get_weather_accuracy_mod()

	var final_acc: float = base_acc * range_mod * size_mod * movement_mod * matchup_mod * weather_mod
	return clampf(final_acc, MIN_RANGED_ACCURACY, MAX_RANGED_ACCURACY)


## Calculate armor save chance (chance to block arrow damage).
func calculate_armor_save(defender: Node) -> float:
	var armor: int = defender.data.armor if defender.data else 0
	# Shield wall and similar formations boost armor save
	var formation_bonus: float = 0.0
	if defender.current_formation == FormationType.Type.SHIELD_WALL:
		formation_bonus = 0.15  # +15% save in shield wall
	elif defender.current_formation == FormationType.Type.SQUARE:
		formation_bonus = 0.10  # +10% save in square

	var save_chance: float = (float(armor) * ARMOR_SAVE_PER_POINT) + formation_bonus
	return clampf(save_chance, 0.0, MAX_ARMOR_SAVE)


## Calculate ranged damage when armor save fails.
func calculate_damage(attacker: Node, _defender: Node) -> int:
	var strength: int = attacker.data.strength if attacker.data else 3
	# Base damage from strength, ranged does slightly less than melee
	var base_damage: int = maxi(1, int(float(strength) * RANGED_STRENGTH_MULTIPLIER))
	return base_damage


## Resolve a ranged attack.
## Total War style: hit roll, then armor save roll.
## Includes terrain modifiers: height accuracy, forest defense, concealment.
## Includes weather modifiers: fog blocks LOS, rain/storm reduce accuracy.
## Returns Dictionary with hit/damage info.
func resolve_ranged_attack(attacker: Node, defender: Node) -> Dictionary:
	var result: Dictionary = {
		"hit": false,
		"damage": 0,
		"blocked": false,
		"concealed": false,
		"weather_blocked": false,
		"accuracy": 0.0,
		"armor_save": 0.0,
		"terrain_defense_mod": 1.0,
		"height_accuracy_mod": 1.0,
		"height_damage_mod": 1.0,
		"weather_accuracy_mod": 1.0,
		"debug_info": {}
	}

	# Check weather LOS blocking (fog limits visibility)
	var distance: float = attacker.global_position.distance_to(defender.global_position)
	if _weather_blocks_los(distance):
		result.weather_blocked = true
		result.debug_info = {"outcome": "weather_blocked", "distance": distance}
		return result  # Can't see through fog

	# Get terrain modifiers
	var tree: SceneTree = attacker.get_tree() if attacker.has_method("get_tree") else null
	var terrain_ranged_defense: float = 1.0
	var height_accuracy_mod: float = 1.0
	var height_damage_mod: float = 1.0

	if tree:
		# Check if target is concealed (hidden in forest)
		if TerrainCombatModifiersScript.is_unit_concealed(tree, defender):
			result.concealed = true
			result.debug_info = {"outcome": "concealed"}
			return result  # Can't shoot what you can't see

		# Height modifiers (shooting downhill = easier)
		height_accuracy_mod = TerrainCombatModifiersScript.get_ranged_accuracy_height_mod(attacker, defender)
		height_damage_mod = TerrainCombatModifiersScript.get_ranged_damage_height_mod(attacker, defender)

		# Terrain defense (forest blocks arrows, cover)
		terrain_ranged_defense = TerrainCombatModifiersScript.get_ranged_defense_at(tree, defender.global_position)

	result.height_accuracy_mod = height_accuracy_mod
	result.height_damage_mod = height_damage_mod
	result.terrain_defense_mod = terrain_ranged_defense
	result.weather_accuracy_mod = _get_weather_accuracy_mod()

	# Step 1: Did the arrow land on the formation?
	# Note: weather modifier already applied in calculate_accuracy()
	var accuracy: float = calculate_accuracy(attacker, defender) * height_accuracy_mod
	result.accuracy = accuracy

	if randf() > accuracy:
		result.debug_info = {"accuracy": accuracy, "outcome": "miss", "height_mod": height_accuracy_mod}
		return result

	# Step 2: Arrow hit - does armor + terrain block it?
	# Terrain adds to effective armor save (forest, cover)
	var base_armor_save: float = calculate_armor_save(defender)
	# Terrain ranged defense converts to additional save chance
	# defense 1.35 (forest) = +17.5% extra save
	var terrain_save_bonus: float = (terrain_ranged_defense - 1.0) * 0.5
	var armor_save: float = clampf(base_armor_save + terrain_save_bonus, 0.0, MAX_ARMOR_SAVE)
	result.armor_save = armor_save

	if randf() < armor_save:
		# Armor/terrain blocked the hit
		result.blocked = true
		result.debug_info = {"accuracy": accuracy, "armor_save": armor_save, "terrain_bonus": terrain_save_bonus, "outcome": "blocked"}
		return result

	# Step 3: Hit connected and penetrated armor
	result.hit = true
	var base_damage: int = calculate_damage(attacker, defender)
	result.damage = maxi(1, int(float(base_damage) * height_damage_mod))
	result.debug_info = {
		"accuracy": accuracy,
		"armor_save": armor_save,
		"height_damage": height_damage_mod,
		"outcome": "hit",
		"damage": result.damage
	}

	return result


## Check if target is in range (includes weather range modifier).
func is_in_range(attacker: Node, target: Node) -> bool:
	if not attacker.data:
		return false
	# Apply weather range modifier (fog reduces effective range)
	var max_range: float = attacker.data.range_distance * _get_weather_range_mod()
	var distance: float = attacker.global_position.distance_to(target.global_position)
	return distance <= max_range


## Get effective range after weather modifier.
func get_effective_range(attacker: Node) -> float:
	if not attacker.data:
		return 0.0
	return attacker.data.range_distance * _get_weather_range_mod()


## Check if attacker has ammunition.
func has_ammunition(attacker: Node) -> bool:
	return attacker.current_ammo > 0
