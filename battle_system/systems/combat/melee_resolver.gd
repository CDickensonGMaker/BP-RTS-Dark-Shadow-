class_name MeleeResolver
extends RefCounted

## Handles melee damage calculations - Warhammer Tabletop Style.
## 1. To Hit: Weapon Skill vs Weapon Skill
## 2. To Wound: Strength vs Defense (Toughness)
## 3. Armor Save: Roll to block wound
## Includes terrain modifiers for height, cover, and terrain type.

# Preload helper systems
const FlankingCalculatorScript = preload("res://battle_system/systems/combat/flanking_calculator.gd")
const ChargeSystemScript = preload("res://battle_system/systems/combat/charge_system.gd")
const TerrainCombatModifiersScript = preload("res://battle_system/terrain/terrain_combat_modifiers.gd")

# To Hit table (attacker WS vs defender WS)
# Difference -> hit chance
const TO_HIT_EQUAL: float = 0.50       # WS equal: 4+ (50%)
const TO_HIT_HIGHER: float = 0.66      # WS 1-3 higher: 3+ (66%)
const TO_HIT_MUCH_HIGHER: float = 0.83 # WS 4+ higher: 2+ (83%)
const TO_HIT_LOWER: float = 0.33       # WS 1-3 lower: 5+ (33%)
const TO_HIT_MUCH_LOWER: float = 0.17  # WS 4+ lower: 6+ (17%)

# To Wound table (Strength vs Defense/Toughness)
const TO_WOUND_EQUAL: float = 0.50       # S = D: 4+ (50%)
const TO_WOUND_HIGHER: float = 0.66      # S > D by 1-2: 3+ (66%)
const TO_WOUND_MUCH_HIGHER: float = 0.83 # S > D by 3+: 2+ (83%)
const TO_WOUND_LOWER: float = 0.33       # S < D by 1-2: 5+ (33%)
const TO_WOUND_MUCH_LOWER: float = 0.17  # S < D by 3+: 6+ (17%)

# Armor Save table
const ARMOR_SAVE_PER_POINT: float = 0.033  # ~3.3% per armor point
const ARMOR_SAVE_BASE: float = 0.0         # Armor 0 = no save
const MAX_ARMOR_SAVE: float = 0.66         # Max 66% save (3+)

# Height modifiers
const MELEE_HEIGHT_BONUS: float = 0.15
const MELEE_HEIGHT_PENALTY: float = 0.15
const HEIGHT_ADVANTAGE_THRESHOLD: float = 1.5
const SLOPE_WS_BONUS: int = 2  # +2 effective WS when defending uphill

# === FRONT RANK COMBAT LIMITING (Historical melee realism) ===
# Only soldiers who can physically reach the enemy can fight.
# This dramatically slows combat and creates tactical depth.
const DEFAULT_FILES_PER_RANK: int = 8  # Default front rank width
const SUPPORT_RANK_MULTIPLIER: float = 0.5  # Second rank fights at 50% effectiveness

# References to helper systems
var flanking  # FlankingCalculator
var charge    # ChargeSystem


func _init() -> void:
	flanking = FlankingCalculatorScript.new()
	charge = ChargeSystemScript.new()


## Get the number of soldiers that can fight in the front rank.
## Uses formation width if available, otherwise defaults to 8.
func get_front_rank_size(regiment: Node) -> int:
	# Try to get formation width from regiment
	if "formation" in regiment and regiment.formation:
		var formation = regiment.formation
		# SoldierFormation stores 'rows' which is ranks deep
		# Files = soldiers / ranks
		var alive_count: int = regiment.current_soldiers if "current_soldiers" in regiment else 20
		if "alive_count" in formation:
			alive_count = formation.alive_count
		var ranks: int = 3  # Default
		if "rows" in formation:
			ranks = formation.rows
		return ceili(float(alive_count) / float(maxi(ranks, 1)))

	# Fallback to default
	return DEFAULT_FILES_PER_RANK


## Calculate effective number of attacks based on front rank limiting.
## Only front rank attacks at full strength, support rank at 50%.
func calculate_effective_attacks(regiment: Node) -> int:
	var total_soldiers: int = 20
	if "current_soldiers" in regiment:
		total_soldiers = regiment.current_soldiers

	var front_rank_size: int = get_front_rank_size(regiment)

	# Front rank: min(files, soldiers) at full effectiveness
	var front_attacks: int = mini(front_rank_size, total_soldiers)

	# Support rank: min(files, remaining) at half effectiveness
	var remaining: int = maxi(total_soldiers - front_attacks, 0)
	var support_soldiers: int = mini(front_rank_size, remaining)
	var support_attacks: int = int(float(support_soldiers) * SUPPORT_RANK_MULTIPLIER)

	return front_attacks + support_attacks


## Calculate To Hit chance based on Weapon Skill comparison.
func calculate_to_hit(attacker_ws: int, defender_ws: int) -> float:
	var diff: int = attacker_ws - defender_ws

	if diff >= 4:
		return TO_HIT_MUCH_HIGHER
	elif diff >= 1:
		return TO_HIT_HIGHER
	elif diff >= -3:
		if diff == 0:
			return TO_HIT_EQUAL
		else:
			return TO_HIT_LOWER
	else:
		return TO_HIT_MUCH_LOWER


## Calculate To Wound chance based on Strength vs Defense.
func calculate_to_wound(strength: int, defense: int) -> float:
	var diff: int = strength - defense

	if diff >= 3:
		return TO_WOUND_MUCH_HIGHER
	elif diff >= 1:
		return TO_WOUND_HIGHER
	elif diff >= -2:
		if diff == 0:
			return TO_WOUND_EQUAL
		else:
			return TO_WOUND_LOWER
	else:
		return TO_WOUND_MUCH_LOWER


## Calculate Armor Save chance.
func calculate_armor_save(armor: int, formation_bonus: float = 0.0) -> float:
	# Armor 0 = 0%, Armor 10 = 33%, Armor 15 = 50%, Armor 20 = 66%
	var save: float = ARMOR_SAVE_BASE + (float(armor) * ARMOR_SAVE_PER_POINT) + formation_bonus
	return clampf(save, 0.0, MAX_ARMOR_SAVE)


## Get formation armor bonus.
func get_formation_armor_bonus(defender: Node) -> float:
	if not defender.has_method("get") or not "current_formation" in defender:
		return 0.0

	match defender.current_formation:
		FormationType.Type.SHIELD_WALL:
			return 0.15  # +15% save
		FormationType.Type.SQUARE:
			return 0.10  # +10% save
		FormationType.Type.SCHILTRON:
			return 0.12  # +12% save
		_:
			return 0.0


## Calculate height modifier for melee combat.
func get_height_modifier(attacker: Node, defender: Node) -> float:
	var height_diff: float = attacker.global_position.y - defender.global_position.y

	if height_diff > HEIGHT_ADVANTAGE_THRESHOLD:
		return 1.0 + MELEE_HEIGHT_BONUS
	elif height_diff < -HEIGHT_ADVANTAGE_THRESHOLD:
		return 1.0 - MELEE_HEIGHT_PENALTY
	return 1.0


## Calculate slope WS bonus for defender on high ground.
func get_slope_ws_bonus(defender: Node, attacker: Node) -> int:
	var height_diff: float = defender.global_position.y - attacker.global_position.y
	if height_diff > HEIGHT_ADVANTAGE_THRESHOLD:
		return SLOPE_WS_BONUS
	return 0


## Resolve a single melee attack - Warhammer style.
## Returns Dictionary with hit/wound/blocked/casualties info.
func resolve_melee_attack(attacker: Node, defender: Node, charge_time: float = 0.0, charge_negated: bool = false) -> Dictionary:
	var result: Dictionary = {
		"hit": false,
		"wounded": false,
		"blocked": false,
		"casualties": 0,
		"flank_mod": 1.0,
		"flank_morale_mod": 1.0,
		"height_mod": 1.0,
		"is_flank": false,
		"is_rear": false,
		"debug_info": {}
	}

	# Get attacker's weapon skill with modifiers
	var att_ws: int = attacker.data.weapon_skill if attacker.data else 10
	var att_ws_mod: float = attacker.get_attack_modifier() if attacker.has_method("get_attack_modifier") else 1.0
	att_ws = int(float(att_ws) * att_ws_mod)

	# Apply charge bonus to WS if applicable
	if not charge_negated and attacker.data.charge_bonus > 0:
		var charge_bonus: int = charge.get_charge_damage_bonus(attacker, charge_time)
		att_ws += charge_bonus / 2  # Half charge bonus goes to WS

	# Get defender's weapon skill with modifiers and slope bonus
	var def_ws: int = defender.data.weapon_skill if defender.data else 10
	var def_ws_mod: float = defender.get_defense_modifier() if defender.has_method("get_defense_modifier") else 1.0
	def_ws = int(float(def_ws) * def_ws_mod) + get_slope_ws_bonus(defender, attacker)

	# Step 1: To Hit roll
	var to_hit_chance: float = calculate_to_hit(att_ws, def_ws)
	if randf() > to_hit_chance:
		result.debug_info = {"step": "miss", "to_hit": to_hit_chance, "att_ws": att_ws, "def_ws": def_ws}
		return result

	result.hit = true

	# Get strength with charge bonus
	var att_strength: int = attacker.data.strength if attacker.data else 3
	if not charge_negated and attacker.data.charge_bonus > 0:
		var charge_bonus: int = charge.get_charge_damage_bonus(attacker, charge_time)
		att_strength += charge_bonus / 2  # Half charge bonus goes to strength

	# Get defender's defense (toughness equivalent)
	var def_defense: int = defender.data.defense if defender.data else 10

	# Step 2: To Wound roll
	var to_wound_chance: float = calculate_to_wound(att_strength, def_defense)
	if randf() > to_wound_chance:
		result.debug_info = {"step": "no_wound", "to_hit": to_hit_chance, "to_wound": to_wound_chance}
		return result

	result.wounded = true

	# Get armor with formation bonus
	var def_armor: int = defender.data.armor if defender.data else 0
	var formation_bonus: float = get_formation_armor_bonus(defender)

	# Step 3: Armor Save roll
	var armor_save: float = calculate_armor_save(def_armor, formation_bonus)
	if randf() < armor_save:
		result.blocked = true
		result.debug_info = {"step": "blocked", "to_hit": to_hit_chance, "to_wound": to_wound_chance, "armor_save": armor_save}
		return result

	# Wound got through! Calculate casualties
	result.height_mod = get_height_modifier(attacker, defender)
	result.flank_mod = flanking.get_damage_modifier(attacker, defender)
	result.flank_morale_mod = flanking.get_morale_modifier(attacker, defender)
	result.is_flank = flanking.is_flank_attack(attacker, defender)
	result.is_rear = flanking.is_rear_attack(attacker, defender)

	# Base casualties = 1 per wound, modified by flanking/height
	var base_casualties: int = 1
	result.casualties = maxi(1, int(float(base_casualties) * result.height_mod * result.flank_mod))

	result.debug_info = {
		"step": "wound",
		"to_hit": to_hit_chance,
		"to_wound": to_wound_chance,
		"armor_save": armor_save,
		"casualties": result.casualties
	}

	return result


## Resolve bidirectional melee combat (attacker AND defender counter-attack).
## Warhammer style with multiple attack rolls based on unit size.
## Includes terrain modifiers for defense, cover, and charge blocking.
func resolve_bidirectional_melee(
	attacker: Node,
	defender: Node,
	charge_time: float = 0.0,
	charge_negated: bool = false,
	ai_multiplier: float = 1.0,
	counter_ai_multiplier: float = 1.0,
	weather_charge_modifier: float = 1.0,
	formation_charge_modifier: float = 1.0
) -> Dictionary:
	var result: Dictionary = {
		"attacker": _empty_combat_result(),
		"defender_counter": _empty_combat_result(),
		"charge_blocked_by_terrain": false,
		"debug_info": {}
	}

	# Get terrain modifiers for defender's position
	var tree: SceneTree = attacker.get_tree() if attacker.has_method("get_tree") else null
	var terrain_defense_mod: float = 1.0
	var terrain_can_charge: bool = true

	if tree:
		terrain_defense_mod = TerrainCombatModifiersScript.get_total_defense_modifier(tree, attacker, defender, false)
		terrain_can_charge = TerrainCombatModifiersScript.can_charge_at(tree, defender.global_position)

	# Check if charge is blocked by terrain (forest, mud, water, rocky)
	if not terrain_can_charge and charge_time < 1.0:
		# Charge bonus negated by terrain
		charge_negated = true
		result.charge_blocked_by_terrain = true

	# Number of attacks LIMITED BY FRONT RANK (historical melee realism)
	# Only soldiers who can physically reach the enemy can fight.
	# Front rank attacks at full strength, support rank at 50%.
	var att_attacks: int = calculate_effective_attacks(attacker)
	var def_attacks: int = calculate_effective_attacks(defender)

	# === ATTACKER'S ATTACKS ===
	var att_total_casualties: int = 0
	var att_any_hit: bool = false

	# Get attacker stats
	var att_ws: int = attacker.data.weapon_skill if attacker.data else 10
	var att_ws_mod: float = attacker.get_attack_modifier() if attacker.has_method("get_attack_modifier") else 1.0
	att_ws = int(float(att_ws) * att_ws_mod)

	# Apply terrain attack modifier (uphill penalty)
	if tree:
		var terrain_attack_mod: float = TerrainCombatModifiersScript.get_total_attack_modifier(tree, attacker, defender, false)
		att_ws = int(float(att_ws) * terrain_attack_mod)

	var att_strength: int = attacker.data.strength if attacker.data else 3

	# Apply charge bonus
	var effective_charge_bonus: int = 0
	if not charge_negated and attacker.data.charge_bonus > 0:
		var charge_decay: float = charge.get_charge_bonus_decay(charge_time)
		if charge_decay > 0.0:
			effective_charge_bonus = int(
				float(attacker.data.charge_bonus) *
				weather_charge_modifier *
				formation_charge_modifier *
				charge_decay
			)
			att_ws += effective_charge_bonus / 2
			att_strength += effective_charge_bonus / 2

	# Get defender stats with terrain defense bonus
	var def_ws: int = defender.data.weapon_skill if defender.data else 10
	var def_ws_mod: float = defender.get_defense_modifier() if defender.has_method("get_defense_modifier") else 1.0
	def_ws = int(float(def_ws) * def_ws_mod * terrain_defense_mod) + get_slope_ws_bonus(defender, attacker)
	var def_defense: int = defender.data.defense if defender.data else 10
	# Terrain adds effective defense (forest, cover, etc.)
	def_defense = int(float(def_defense) * terrain_defense_mod)
	var def_armor: int = defender.data.armor if defender.data else 0
	var def_formation_bonus: float = get_formation_armor_bonus(defender)

	# Roll each attack
	var to_hit_chance: float = calculate_to_hit(att_ws, def_ws)
	var to_wound_chance: float = calculate_to_wound(att_strength, def_defense)
	var armor_save: float = calculate_armor_save(def_armor, def_formation_bonus)

	# Damage per wound based on strength (strength 3 = 1, strength 6 = 2, etc.)
	var att_damage_per_wound: int = maxi(1, att_strength / 3)

	for i in att_attacks:
		# To Hit
		if randf() > to_hit_chance:
			continue
		att_any_hit = true

		# To Wound
		if randf() > to_wound_chance:
			continue

		# Armor Save
		if randf() < armor_save:
			continue

		# Wound got through - deal strength-based damage
		att_total_casualties += att_damage_per_wound

	if att_any_hit:
		result.attacker.hit = true
		result.attacker.height_mod = get_height_modifier(attacker, defender)
		result.attacker.flank_mod = flanking.get_damage_modifier(attacker, defender)
		result.attacker.flank_morale_mod = flanking.get_morale_modifier(attacker, defender)
		result.attacker.is_flank = flanking.is_flank_attack(attacker, defender)
		result.attacker.is_rear = flanking.is_rear_attack(attacker, defender)

		# Apply modifiers to total casualties
		result.attacker.casualties = maxi(0, int(
			float(att_total_casualties) *
			result.attacker.height_mod *
			result.attacker.flank_mod *
			ai_multiplier
		))

	result.debug_info["attacker"] = {
		"attacks": att_attacks,
		"to_hit": to_hit_chance,
		"to_wound": to_wound_chance,
		"armor_save": armor_save,
		"wounds": att_total_casualties
	}

	# === DEFENDER'S COUNTER-ATTACKS ===
	var def_total_casualties: int = 0
	var def_any_hit: bool = false

	# Get defender attack stats (they attack back)
	var def_att_ws: int = defender.data.weapon_skill if defender.data else 10
	var def_att_mod: float = defender.get_attack_modifier() if defender.has_method("get_attack_modifier") else 1.0
	def_att_ws = int(float(def_att_ws) * def_att_mod)

	var def_strength: int = defender.data.strength if defender.data else 3

	# Get attacker's defensive stats (as counter-attack target)
	var att_def_ws: int = attacker.data.weapon_skill if attacker.data else 10
	var att_def_mod: float = attacker.get_defense_modifier() if attacker.has_method("get_defense_modifier") else 1.0
	att_def_ws = int(float(att_def_ws) * att_def_mod) + get_slope_ws_bonus(attacker, defender)
	var att_defense: int = attacker.data.defense if attacker.data else 10
	var att_armor: int = attacker.data.armor if attacker.data else 0
	var att_formation_bonus: float = get_formation_armor_bonus(attacker)

	# Roll each counter-attack
	var counter_hit_chance: float = calculate_to_hit(def_att_ws, att_def_ws)
	var counter_wound_chance: float = calculate_to_wound(def_strength, att_defense)
	var counter_armor_save: float = calculate_armor_save(att_armor, att_formation_bonus)

	# Damage per wound based on defender strength
	var def_damage_per_wound: int = maxi(1, def_strength / 3)

	for i in def_attacks:
		# To Hit
		if randf() > counter_hit_chance:
			continue
		def_any_hit = true

		# To Wound
		if randf() > counter_wound_chance:
			continue

		# Armor Save
		if randf() < counter_armor_save:
			continue

		# Wound got through - deal strength-based damage
		def_total_casualties += def_damage_per_wound

	if def_any_hit:
		result.defender_counter.hit = true
		result.defender_counter.height_mod = get_height_modifier(defender, attacker)
		result.defender_counter.flank_mod = flanking.get_damage_modifier(defender, attacker)
		result.defender_counter.flank_morale_mod = flanking.get_morale_modifier(defender, attacker)
		result.defender_counter.is_flank = flanking.is_flank_attack(defender, attacker)
		result.defender_counter.is_rear = flanking.is_rear_attack(defender, attacker)

		# Apply modifiers to total casualties
		result.defender_counter.casualties = maxi(0, int(
			float(def_total_casualties) *
			result.defender_counter.height_mod *
			result.defender_counter.flank_mod *
			counter_ai_multiplier
		))

	result.debug_info["defender_counter"] = {
		"attacks": def_attacks,
		"to_hit": counter_hit_chance,
		"to_wound": counter_wound_chance,
		"armor_save": counter_armor_save,
		"wounds": def_total_casualties
	}

	return result


## Create an empty combat result structure.
func _empty_combat_result() -> Dictionary:
	return {
		"hit": false,
		"wounded": false,
		"blocked": false,
		"casualties": 0,
		"flank_mod": 1.0,
		"flank_morale_mod": 1.0,
		"height_mod": 1.0,
		"is_flank": false,
		"is_rear": false
	}
