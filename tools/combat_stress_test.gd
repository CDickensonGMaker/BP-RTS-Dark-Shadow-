@tool
class_name CombatStressTest
extends SceneTree

## Combat Stress Test Tool
## Runs automated 1v1 battles between all unit types to identify balance issues.
##
## Run from Godot editor:
##   godot --headless --script res://tools/combat_stress_test.gd
##
## Or run directly in editor via @tool annotation.

# =============================================================================
# CONFIGURATION
# =============================================================================

const RUNS_PER_MATCHUP: int = 20
const COMBAT_ROUNDS_PER_FIGHT: int = 50  # Simulate 50 combat rounds
const REGIMENT_DATA_PATH: String = "res://battle_system/data/regiments/"
const OUTPUT_FILE: String = "res://tools/stress_test_results.txt"

# Imbalance thresholds
const IMBALANCE_HIGH: float = 0.70  # >70% win rate = favored
const IMBALANCE_LOW: float = 0.30   # <30% win rate = weak

# =============================================================================
# COMBAT FORMULAS (FROM melee_resolver.gd)
# =============================================================================

# To Hit table (attacker WS vs defender WS)
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

# Armor Save
const ARMOR_SAVE_PER_POINT: float = 0.033  # ~3.3% per armor point
const MAX_ARMOR_SAVE: float = 0.66         # Max 66% save (3+)

# Front rank combat limiting
const DEFAULT_FILES_PER_RANK: int = 8
const SUPPORT_RANK_MULTIPLIER: float = 0.5
const GENERAL_EFFECTIVE_SOLDIERS: int = 10

# Charge bonus decay per round (full on round 0, diminishing thereafter)
const CHARGE_BONUS_DECAY: Array[float] = [1.0, 0.75, 0.5, 0.25, 0.0]  # Per round

# =============================================================================
# VETERANCY BONUSES (FROM veterancy_system.gd)
# =============================================================================

const VETERANCY_MELEE_BONUS: Array[float] = [0.0, 0.05, 0.10, 0.15]
const VETERANCY_MORALE_BONUS: Array[float] = [0.0, 5.0, 10.0, 15.0]
const VETERANCY_GENERAL_HP_BONUS: Array[int] = [0, 2, 5, 8]

# =============================================================================
# UPGRADE BONUSES (Hypothetical - per level)
# =============================================================================

const UPGRADE_ATTACK_BONUS: Array[int] = [0, 2, 4, 6]
const UPGRADE_DEFENSE_BONUS: Array[int] = [0, 1, 2, 3]
const UPGRADE_ARMOR_BONUS: Array[int] = [0, 1, 2, 3]
const UPGRADE_SOLDIER_BONUS: Array[int] = [0, 2, 4, 6]

# =============================================================================
# UNIT TYPE ENUM (FROM unit_type.gd)
# =============================================================================

enum UnitTypeEnum {
	INFANTRY = 0,
	CAVALRY = 1,
	RANGED = 2,
	ARTILLERY = 3,
	GENERAL = 4,
	MONSTER = 5
}

const UNIT_TYPE_NAMES: Dictionary = {
	0: "Infantry",
	1: "Cavalry",
	2: "Ranged",
	3: "Artillery",
	4: "General",
	5: "Monster"
}

# =============================================================================
# MATCHUP BONUSES (FROM matchup_calculator.gd)
# =============================================================================

const SPEAR_VS_CAVALRY_BONUS: float = 1.25

const MELEE_MATCHUPS: Dictionary = {
	0: {0: 1.0, 1: 1.1, 2: 1.15, 3: 1.25, 4: 0.9, 5: 0.85},  # INFANTRY
	1: {0: 1.1, 1: 1.0, 2: 1.2, 3: 1.25, 4: 0.95, 5: 0.7},   # CAVALRY
	2: {0: 0.85, 1: 0.75, 2: 0.9, 3: 0.8, 4: 0.75, 5: 0.6},  # RANGED
	3: {0: 0.5, 1: 0.4, 2: 0.6, 3: 0.7, 4: 0.5, 5: 0.3},     # ARTILLERY
	4: {0: 1.2, 1: 1.15, 2: 1.25, 3: 1.3, 4: 1.0, 5: 0.9},   # GENERAL
	5: {0: 1.3, 1: 1.5, 2: 1.35, 3: 1.25, 4: 1.1, 5: 1.0}    # MONSTER
}

# =============================================================================
# DATA STRUCTURES
# =============================================================================

class SimulatedUnit:
	var name: String
	var unit_type: int
	var faction: String
	var attack: int
	var defense: int
	var weapon_skill: int
	var strength: int
	var armor: int
	var max_soldiers: int
	var current_soldiers: int
	var charge_bonus: int
	var is_spear: bool

	# HP pool for Generals and single-model Monsters
	var hp_pool: int = 0
	var current_hp: int = 0
	var uses_hp_pool: bool = false

	func reset() -> void:
		current_soldiers = max_soldiers
		current_hp = hp_pool

	func setup_hp_pool() -> void:
		# Generals use HP pool (GENERAL_BASE_HP=15 + veterancy bonus)
		if unit_type == UnitTypeEnum.GENERAL:
			hp_pool = 15  # GENERAL_BASE_HP
			current_hp = hp_pool
			uses_hp_pool = true
		# Single-model Monsters use HP pool (MONSTER_BASE_HP=20 + defense*1.0)
		elif unit_type == UnitTypeEnum.MONSTER and max_soldiers == 1:
			hp_pool = 20 + defense  # MONSTER_BASE_HP + defense * MONSTER_HP_PER_DEFENSE
			current_hp = hp_pool
			uses_hp_pool = true

	func is_dead() -> bool:
		if uses_hp_pool:
			return current_hp <= 0
		return current_soldiers <= 0

	func apply_casualties(count: int) -> void:
		if uses_hp_pool:
			# For HP pool units, each "casualty" is 1 damage
			# Apply armor saves (4% per armor point for generals, 3.5% for monsters)
			var save_chance: float = float(armor) * 0.04
			var actual_damage: int = 0
			for i in count:
				if randf() >= save_chance:
					actual_damage += 1
			current_hp = maxi(0, current_hp - actual_damage)
		else:
			current_soldiers = maxi(0, current_soldiers - count)


class MatchupResult:
	var unit_a_name: String
	var unit_b_name: String
	var unit_a_wins: int = 0
	var unit_b_wins: int = 0
	var draws: int = 0
	var total_runs: int = 0
	var unit_a_avg_remaining: float = 0.0
	var unit_b_avg_remaining: float = 0.0
	var unit_a_total_remaining: int = 0
	var unit_b_total_remaining: int = 0

	func get_unit_a_winrate() -> float:
		if total_runs == 0:
			return 0.0
		return float(unit_a_wins) / float(total_runs)

	func is_imbalanced() -> bool:
		var winrate := get_unit_a_winrate()
		return winrate > IMBALANCE_HIGH or winrate < IMBALANCE_LOW


class TestConfig:
	var veterancy_a: int = 0
	var veterancy_b: int = 0
	var upgrade_a: int = 0
	var upgrade_b: int = 0


# =============================================================================
# STATE
# =============================================================================

var all_units: Array[SimulatedUnit] = []
var results: Array[MatchupResult] = []
var output_lines: Array[String] = []


# =============================================================================
# ENTRY POINT
# =============================================================================

func _init() -> void:
	print("=".repeat(60))
	print("COMBAT STRESS TEST - Starting...")
	print("=".repeat(60))
	print("")

	load_all_regiment_data()

	if all_units.is_empty():
		print("ERROR: No regiment data files found!")
		quit(1)
		return

	print("Loaded %d unit types" % all_units.size())
	print("")

	run_all_tests()
	generate_report()
	save_results()

	print("")
	print("=".repeat(60))
	print("STRESS TEST COMPLETE")
	print("Results saved to: %s" % OUTPUT_FILE)
	print("=".repeat(60))

	quit(0)


# =============================================================================
# LOADING REGIMENT DATA
# =============================================================================

func load_all_regiment_data() -> void:
	var dir := DirAccess.open(REGIMENT_DATA_PATH)
	if dir == null:
		print("ERROR: Cannot open directory: %s" % REGIMENT_DATA_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := REGIMENT_DATA_PATH + file_name
			var unit := load_regiment_file(path)
			if unit != null:
				all_units.append(unit)
		file_name = dir.get_next()

	dir.list_dir_end()

	# Sort by unit type, then by name
	all_units.sort_custom(func(a: SimulatedUnit, b: SimulatedUnit) -> bool:
		if a.unit_type != b.unit_type:
			return a.unit_type < b.unit_type
		return a.name < b.name
	)


func load_regiment_file(path: String) -> SimulatedUnit:
	var resource := ResourceLoader.load(path)
	if resource == null:
		print("WARNING: Failed to load: %s" % path)
		return null

	var unit := SimulatedUnit.new()

	# Read properties - RegimentData is a Resource
	unit.name = resource.get("regiment_name") if resource.get("regiment_name") else path.get_file()
	unit.unit_type = resource.get("unit_type") if resource.get("unit_type") != null else 0
	unit.faction = resource.get("faction") if resource.get("faction") else "unknown"
	unit.attack = resource.get("attack") if resource.get("attack") != null else 10
	unit.defense = resource.get("defense") if resource.get("defense") != null else 10
	unit.weapon_skill = resource.get("weapon_skill") if resource.get("weapon_skill") != null else 10
	unit.strength = resource.get("strength") if resource.get("strength") != null else 3
	unit.armor = resource.get("armor") if resource.get("armor") != null else 0
	unit.max_soldiers = resource.get("max_soldiers") if resource.get("max_soldiers") != null else 20
	unit.current_soldiers = unit.max_soldiers
	unit.charge_bonus = resource.get("charge_bonus") if resource.get("charge_bonus") != null else 0

	# Check if spear unit
	var name_lower: String = unit.name.to_lower()
	unit.is_spear = (
		name_lower.contains("halb") or
		name_lower.contains("pike") or
		name_lower.contains("spear") or
		name_lower.contains("lance")
	)

	# Setup HP pool for Generals and single-model Monsters
	unit.setup_hp_pool()

	return unit


# =============================================================================
# COMBAT SIMULATION
# =============================================================================

func calculate_to_hit(attacker_ws: int, defender_ws: int) -> float:
	var diff := attacker_ws - defender_ws
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


func calculate_to_wound(strength: int, defense: int) -> float:
	var diff := strength - defense
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


func calculate_armor_save(armor_val: int) -> float:
	var save := float(armor_val) * ARMOR_SAVE_PER_POINT
	return clampf(save, 0.0, MAX_ARMOR_SAVE)


func calculate_effective_attacks(unit: SimulatedUnit) -> int:
	# Generals fight like GENERAL_EFFECTIVE_SOLDIERS
	if unit.unit_type == UnitTypeEnum.GENERAL:
		return GENERAL_EFFECTIVE_SOLDIERS

	var total := unit.current_soldiers
	var front_rank := mini(DEFAULT_FILES_PER_RANK, total)
	var remaining := maxi(total - front_rank, 0)
	var support := mini(DEFAULT_FILES_PER_RANK, remaining)
	var support_attacks := int(float(support) * SUPPORT_RANK_MULTIPLIER)

	return front_rank + support_attacks


func get_melee_matchup(attacker_type: int, defender_type: int) -> float:
	if not MELEE_MATCHUPS.has(attacker_type):
		return 1.0
	var matchups: Dictionary = MELEE_MATCHUPS[attacker_type]
	if not matchups.has(defender_type):
		return 1.0
	return matchups[defender_type]


func apply_veterancy(unit: SimulatedUnit, level: int) -> SimulatedUnit:
	## Returns a copy with veterancy bonuses applied
	var modified := SimulatedUnit.new()
	modified.name = unit.name
	modified.unit_type = unit.unit_type
	modified.faction = unit.faction
	modified.is_spear = unit.is_spear
	modified.charge_bonus = unit.charge_bonus

	var melee_mult := 1.0 + VETERANCY_MELEE_BONUS[level]
	modified.attack = int(float(unit.attack) * melee_mult)
	modified.defense = unit.defense
	modified.weapon_skill = int(float(unit.weapon_skill) * melee_mult)
	modified.strength = unit.strength
	modified.armor = unit.armor

	# Generals get HP bonus
	if unit.unit_type == UnitTypeEnum.GENERAL:
		modified.max_soldiers = unit.max_soldiers + VETERANCY_GENERAL_HP_BONUS[level]
	else:
		modified.max_soldiers = unit.max_soldiers

	modified.current_soldiers = modified.max_soldiers

	# Setup HP pool for Generals and single-model Monsters
	modified.setup_hp_pool()

	return modified


func apply_upgrades(unit: SimulatedUnit, level: int) -> SimulatedUnit:
	## Returns a copy with upgrade bonuses applied
	var modified := SimulatedUnit.new()
	modified.name = unit.name
	modified.unit_type = unit.unit_type
	modified.faction = unit.faction
	modified.is_spear = unit.is_spear
	modified.charge_bonus = unit.charge_bonus

	modified.attack = unit.attack + UPGRADE_ATTACK_BONUS[level]
	modified.defense = unit.defense + UPGRADE_DEFENSE_BONUS[level]
	modified.weapon_skill = unit.weapon_skill
	modified.strength = unit.strength
	modified.armor = unit.armor + UPGRADE_ARMOR_BONUS[level]
	modified.max_soldiers = unit.max_soldiers + UPGRADE_SOLDIER_BONUS[level]
	modified.current_soldiers = modified.max_soldiers

	# Setup HP pool for Generals and single-model Monsters
	modified.setup_hp_pool()

	return modified


func simulate_combat_round(attacker: SimulatedUnit, defender: SimulatedUnit, round_num: int = 0) -> int:
	## Simulate one round of combat, return casualties inflicted on defender
	var att_attacks := calculate_effective_attacks(attacker)

	# Get weapon skill with matchup bonus
	var att_ws := attacker.weapon_skill
	var matchup := get_melee_matchup(attacker.unit_type, defender.unit_type)
	if attacker.is_spear and defender.unit_type == UnitTypeEnum.CAVALRY:
		matchup *= SPEAR_VS_CAVALRY_BONUS
	att_ws = int(float(att_ws) * matchup)

	var att_strength := attacker.strength

	# Apply charge bonus for cavalry on early rounds
	if attacker.unit_type == UnitTypeEnum.CAVALRY and round_num < CHARGE_BONUS_DECAY.size():
		var charge_mult: float = CHARGE_BONUS_DECAY[round_num]
		att_ws += int(float(attacker.charge_bonus) * charge_mult * 0.5)
		att_strength += int(float(attacker.charge_bonus) * charge_mult * 0.5)

	var def_ws := defender.weapon_skill
	var def_defense := defender.defense
	var def_armor := defender.armor

	var to_hit := calculate_to_hit(att_ws, def_ws)
	var to_wound := calculate_to_wound(att_strength, def_defense)
	var armor_save := calculate_armor_save(def_armor)

	var damage_per_wound := maxi(1, att_strength / 3)
	var total_casualties := 0

	for i in att_attacks:
		# To Hit
		if randf() > to_hit:
			continue
		# To Wound
		if randf() > to_wound:
			continue
		# Armor Save
		if randf() < armor_save:
			continue
		# Wound got through
		total_casualties += damage_per_wound

	return total_casualties


func simulate_battle(unit_a: SimulatedUnit, unit_b: SimulatedUnit) -> int:
	## Returns: 1 if unit_a wins, -1 if unit_b wins, 0 if draw
	unit_a.reset()
	unit_b.reset()

	# Simulate all combat rounds with decaying charge bonus
	for round_num in range(COMBAT_ROUNDS_PER_FIGHT):
		if unit_a.is_dead() or unit_b.is_dead():
			break

		# Both sides attack simultaneously, passing round number for charge bonus calculation
		var a_casualties := simulate_combat_round(unit_b, unit_a, round_num)
		var b_casualties := simulate_combat_round(unit_a, unit_b, round_num)
		unit_a.apply_casualties(a_casualties)
		unit_b.apply_casualties(b_casualties)

	# Determine winner
	if unit_a.is_dead() and unit_b.is_dead():
		return 0
	elif unit_b.is_dead():
		return 1
	elif unit_a.is_dead():
		return -1
	elif unit_a.current_soldiers > unit_b.current_soldiers:
		return 1
	elif unit_b.current_soldiers > unit_a.current_soldiers:
		return -1
	else:
		return 0


# =============================================================================
# TEST EXECUTION
# =============================================================================

func run_all_tests() -> void:
	var total_matchups := all_units.size() * all_units.size()
	var current := 0

	print("Running matchup tests...")
	print("Total matchups to test: %d" % total_matchups)
	print("Runs per matchup: %d" % RUNS_PER_MATCHUP)
	print("Veterancy levels: 0-3")
	print("Upgrade levels: 0-3")
	print("")

	# Test baseline (vet 0, upgrade 0)
	print("--- Testing Baseline (Vet 0, Upgrade 0) ---")
	var baseline_results: Array[MatchupResult] = []

	for i in all_units.size():
		for j in all_units.size():
			current += 1
			if current % 100 == 0:
				print("  Progress: %d/%d matchups" % [current, total_matchups])

			var unit_a := all_units[i]
			var unit_b := all_units[j]
			var result := run_matchup(unit_a, unit_b, 0, 0, 0, 0)
			baseline_results.append(result)

	results = baseline_results

	# Test veterancy impact (comparing vet 0 vs vet 3)
	print("")
	print("--- Testing Veterancy Impact (Vet 3 vs Vet 0) ---")
	var vet_advantage_results: Array[Dictionary] = []

	# Sample subset of units for veterancy testing
	var sample_units: Array[SimulatedUnit] = []
	var types_sampled: Dictionary = {}
	for unit in all_units:
		if not types_sampled.has(unit.unit_type) or types_sampled[unit.unit_type] < 3:
			sample_units.append(unit)
			types_sampled[unit.unit_type] = types_sampled.get(unit.unit_type, 0) + 1

	for unit_a in sample_units:
		for unit_b in sample_units:
			# Vet 3 attacker vs Vet 0 defender
			var vet3_result := run_matchup(unit_a, unit_b, 3, 0, 0, 0)
			# Vet 0 attacker vs Vet 0 defender (baseline)
			var vet0_result := run_matchup(unit_a, unit_b, 0, 0, 0, 0)

			var advantage := vet3_result.get_unit_a_winrate() - vet0_result.get_unit_a_winrate()
			vet_advantage_results.append({
				"unit_a": unit_a.name,
				"unit_b": unit_b.name,
				"vet0_winrate": vet0_result.get_unit_a_winrate(),
				"vet3_winrate": vet3_result.get_unit_a_winrate(),
				"advantage": advantage
			})

	# Test upgrade impact (comparing upgrade 0 vs upgrade 3)
	print("")
	print("--- Testing Upgrade Impact (Upgrade 3 vs Upgrade 0) ---")
	var upgrade_advantage_results: Array[Dictionary] = []

	for unit_a in sample_units:
		for unit_b in sample_units:
			# Upgrade 3 attacker vs Upgrade 0 defender
			var upg3_result := run_matchup(unit_a, unit_b, 0, 0, 3, 0)
			# Upgrade 0 attacker vs Upgrade 0 defender (baseline)
			var upg0_result := run_matchup(unit_a, unit_b, 0, 0, 0, 0)

			var advantage := upg3_result.get_unit_a_winrate() - upg0_result.get_unit_a_winrate()
			upgrade_advantage_results.append({
				"unit_a": unit_a.name,
				"unit_b": unit_b.name,
				"upg0_winrate": upg0_result.get_unit_a_winrate(),
				"upg3_winrate": upg3_result.get_unit_a_winrate(),
				"advantage": advantage
			})

	# Store extra results for report
	_vet_results = vet_advantage_results
	_upgrade_results = upgrade_advantage_results


var _vet_results: Array[Dictionary] = []
var _upgrade_results: Array[Dictionary] = []


func run_matchup(
	unit_a: SimulatedUnit,
	unit_b: SimulatedUnit,
	vet_a: int,
	vet_b: int,
	upg_a: int,
	upg_b: int
) -> MatchupResult:
	var result := MatchupResult.new()
	result.unit_a_name = unit_a.name
	result.unit_b_name = unit_b.name
	result.total_runs = RUNS_PER_MATCHUP

	# Apply veterancy and upgrades
	var modified_a := apply_upgrades(apply_veterancy(unit_a, vet_a), upg_a)
	var modified_b := apply_upgrades(apply_veterancy(unit_b, vet_b), upg_b)

	for run_idx in RUNS_PER_MATCHUP:
		var outcome := simulate_battle(modified_a, modified_b)

		if outcome > 0:
			result.unit_a_wins += 1
		elif outcome < 0:
			result.unit_b_wins += 1
		else:
			result.draws += 1

		result.unit_a_total_remaining += modified_a.current_soldiers
		result.unit_b_total_remaining += modified_b.current_soldiers

	result.unit_a_avg_remaining = float(result.unit_a_total_remaining) / float(RUNS_PER_MATCHUP)
	result.unit_b_avg_remaining = float(result.unit_b_total_remaining) / float(RUNS_PER_MATCHUP)

	return result


# =============================================================================
# REPORT GENERATION
# =============================================================================

func generate_report() -> void:
	output_lines.clear()

	_add_line("=" .repeat(80))
	_add_line("COMBAT STRESS TEST REPORT")
	_add_line("Generated: %s" % Time.get_datetime_string_from_system())
	_add_line("=" .repeat(80))
	_add_line("")

	# Summary statistics
	_add_line("CONFIGURATION")
	_add_line("-" .repeat(40))
	_add_line("Units tested: %d" % all_units.size())
	_add_line("Total matchups: %d" % results.size())
	_add_line("Runs per matchup: %d" % RUNS_PER_MATCHUP)
	_add_line("Combat rounds per fight: %d" % COMBAT_ROUNDS_PER_FIGHT)
	_add_line("")

	# Unit roster
	_add_line("UNIT ROSTER")
	_add_line("-" .repeat(40))
	_add_line("%-30s %-12s %-8s" % ["Name", "Type", "Faction"])
	_add_line("-" .repeat(50))
	for unit in all_units:
		var type_name: String = UNIT_TYPE_NAMES.get(unit.unit_type, "Unknown")
		_add_line("%-30s %-12s %-8s" % [unit.name.left(30), type_name, unit.faction])
	_add_line("")

	# Imbalanced matchups
	var imbalanced: Array[MatchupResult] = []
	for result in results:
		if result.is_imbalanced() and result.unit_a_name != result.unit_b_name:
			imbalanced.append(result)

	_add_line("IMBALANCED MATCHUPS (>70%% or <30%% win rate)")
	_add_line("-" .repeat(40))
	_add_line("Found %d imbalanced matchups" % imbalanced.size())
	_add_line("")

	# Sort by most imbalanced
	imbalanced.sort_custom(func(a: MatchupResult, b: MatchupResult) -> bool:
		return absf(a.get_unit_a_winrate() - 0.5) > absf(b.get_unit_a_winrate() - 0.5)
	)

	if imbalanced.size() > 0:
		_add_line("%-25s vs %-25s | Win%% | Verdict" % ["Unit A", "Unit B"])
		_add_line("-" .repeat(75))

		var shown := 0
		for result in imbalanced:
			if shown >= 50:  # Limit to top 50
				break
			var winrate := result.get_unit_a_winrate()
			var verdict: String
			if winrate > IMBALANCE_HIGH:
				verdict = "A FAVORED"
			else:
				verdict = "B FAVORED"
			_add_line("%-25s vs %-25s | %5.1f%% | %s" % [
				result.unit_a_name.left(25),
				result.unit_b_name.left(25),
				winrate * 100.0,
				verdict
			])
			shown += 1
	_add_line("")

	# Unit type matchup matrix
	_add_line("UNIT TYPE WIN RATE MATRIX (Row vs Column)")
	_add_line("-" .repeat(40))
	_add_line("Shows average win rate when row type attacks column type")
	_add_line("")

	# Calculate type vs type averages
	var type_matrix: Dictionary = {}
	for att_type in UNIT_TYPE_NAMES.keys():
		type_matrix[att_type] = {}
		for def_type in UNIT_TYPE_NAMES.keys():
			type_matrix[att_type][def_type] = {"wins": 0, "total": 0}

	for result in results:
		var att_type := -1
		var def_type := -1
		for unit in all_units:
			if unit.name == result.unit_a_name:
				att_type = unit.unit_type
			if unit.name == result.unit_b_name:
				def_type = unit.unit_type

		if att_type >= 0 and def_type >= 0:
			type_matrix[att_type][def_type]["wins"] += result.unit_a_wins
			type_matrix[att_type][def_type]["total"] += result.total_runs

	# Print matrix header
	var header := "%-10s" % ["Attacker"]
	for def_type in UNIT_TYPE_NAMES.keys():
		header += " | %-8s" % [UNIT_TYPE_NAMES[def_type].left(8)]
	_add_line(header)
	_add_line("-" .repeat(10 + 11 * UNIT_TYPE_NAMES.size()))

	for att_type in UNIT_TYPE_NAMES.keys():
		var row := "%-10s" % [UNIT_TYPE_NAMES[att_type].left(10)]
		for def_type in UNIT_TYPE_NAMES.keys():
			var data: Dictionary = type_matrix[att_type][def_type]
			if data["total"] > 0:
				var rate := float(data["wins"]) / float(data["total"]) * 100.0
				row += " | %6.1f%%" % [rate]
			else:
				row += " |   N/A  "
		_add_line(row)
	_add_line("")

	# Per-faction analysis
	_add_line("FACTION PERFORMANCE")
	_add_line("-" .repeat(40))

	var faction_stats: Dictionary = {}
	for result in results:
		var att_faction := ""
		var def_faction := ""
		for unit in all_units:
			if unit.name == result.unit_a_name:
				att_faction = unit.faction
			if unit.name == result.unit_b_name:
				def_faction = unit.faction

		if att_faction != "":
			if not faction_stats.has(att_faction):
				faction_stats[att_faction] = {"wins": 0, "losses": 0, "draws": 0}
			faction_stats[att_faction]["wins"] += result.unit_a_wins
			faction_stats[att_faction]["losses"] += result.unit_b_wins
			faction_stats[att_faction]["draws"] += result.draws

	_add_line("%-12s | %8s | %8s | %8s | %8s" % ["Faction", "Wins", "Losses", "Draws", "Win%"])
	_add_line("-" .repeat(55))

	for faction in faction_stats.keys():
		var stats: Dictionary = faction_stats[faction]
		var total: int = int(stats["wins"]) + int(stats["losses"]) + int(stats["draws"])
		var winrate: float = 0.0
		if total > 0:
			winrate = float(stats["wins"]) / float(total) * 100.0
		_add_line("%-12s | %8d | %8d | %8d | %7.1f%%" % [
			faction.left(12),
			stats["wins"],
			stats["losses"],
			stats["draws"],
			winrate
		])
	_add_line("")

	# Veterancy impact analysis
	_add_line("VETERANCY IMPACT (Level 3 vs Level 0)")
	_add_line("-" .repeat(40))
	_add_line("Average win rate advantage when Vet 3 unit fights Vet 0 unit")
	_add_line("")

	if _vet_results.size() > 0:
		var total_advantage := 0.0
		var max_advantage := {"unit": "", "opponent": "", "value": 0.0}
		var min_advantage := {"unit": "", "opponent": "", "value": 1.0}

		for entry in _vet_results:
			var adv: float = entry["advantage"]
			total_advantage += adv
			if adv > max_advantage["value"]:
				max_advantage = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}
			if adv < min_advantage["value"]:
				min_advantage = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}

		var avg_advantage := total_advantage / float(_vet_results.size())
		_add_line("Average veterancy advantage: +%.1f%% win rate" % [avg_advantage * 100.0])
		_add_line("Maximum benefit: %s vs %s (+%.1f%%)" % [
			max_advantage["unit"],
			max_advantage["opponent"],
			max_advantage["value"] * 100.0
		])
		_add_line("Minimum benefit: %s vs %s (%+.1f%%)" % [
			min_advantage["unit"],
			min_advantage["opponent"],
			min_advantage["value"] * 100.0
		])
	_add_line("")

	# Upgrade impact analysis
	_add_line("UPGRADE IMPACT (Level 3 vs Level 0)")
	_add_line("-" .repeat(40))
	_add_line("Average win rate advantage when Upgrade 3 unit fights Upgrade 0 unit")
	_add_line("")

	if _upgrade_results.size() > 0:
		var total_advantage := 0.0
		var max_advantage := {"unit": "", "opponent": "", "value": 0.0}
		var min_advantage := {"unit": "", "opponent": "", "value": 1.0}

		for entry in _upgrade_results:
			var adv: float = entry["advantage"]
			total_advantage += adv
			if adv > max_advantage["value"]:
				max_advantage = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}
			if adv < min_advantage["value"]:
				min_advantage = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}

		var avg_advantage := total_advantage / float(_upgrade_results.size())
		_add_line("Average upgrade advantage: +%.1f%% win rate" % [avg_advantage * 100.0])
		_add_line("Maximum benefit: %s vs %s (+%.1f%%)" % [
			max_advantage["unit"],
			max_advantage["opponent"],
			max_advantage["value"] * 100.0
		])
		_add_line("Minimum benefit: %s vs %s (%+.1f%%)" % [
			min_advantage["unit"],
			min_advantage["opponent"],
			min_advantage["value"] * 100.0
		])
	_add_line("")

	# Full matchup table
	_add_line("FULL MATCHUP RESULTS (Baseline - Vet 0, Upgrade 0)")
	_add_line("-" .repeat(40))
	_add_line("%-25s vs %-25s | A-Win | B-Win | Draw | A-Rem | B-Rem" % ["Unit A", "Unit B"])
	_add_line("-" .repeat(95))

	for result in results:
		if result.unit_a_name == result.unit_b_name:
			continue  # Skip mirror matches
		_add_line("%-25s vs %-25s | %5d | %5d | %4d | %5.1f | %5.1f" % [
			result.unit_a_name.left(25),
			result.unit_b_name.left(25),
			result.unit_a_wins,
			result.unit_b_wins,
			result.draws,
			result.unit_a_avg_remaining,
			result.unit_b_avg_remaining
		])

	_add_line("")
	_add_line("=" .repeat(80))
	_add_line("END OF REPORT")
	_add_line("=" .repeat(80))

	# Print summary to console
	print("")
	print("SUMMARY:")
	print("  Total units: %d" % all_units.size())
	print("  Total matchups tested: %d" % results.size())
	print("  Imbalanced matchups found: %d" % imbalanced.size())

	if imbalanced.size() > 0:
		print("")
		print("TOP 10 MOST IMBALANCED:")
		var count := 0
		for result in imbalanced:
			if count >= 10:
				break
			var winrate := result.get_unit_a_winrate()
			var winner: String
			var loser: String
			if winrate > 0.5:
				winner = result.unit_a_name
				loser = result.unit_b_name
			else:
				winner = result.unit_b_name
				loser = result.unit_a_name
				winrate = 1.0 - winrate
			print("  %s beats %s %.0f%% of the time" % [winner, loser, winrate * 100.0])
			count += 1


func _add_line(line: String) -> void:
	output_lines.append(line)


# =============================================================================
# FILE OUTPUT
# =============================================================================

func save_results() -> void:
	var file := FileAccess.open(OUTPUT_FILE, FileAccess.WRITE)
	if file == null:
		print("ERROR: Failed to open output file: %s" % OUTPUT_FILE)
		return

	for line in output_lines:
		file.store_line(line)

	file.close()
	print("Results saved to: %s" % OUTPUT_FILE)
