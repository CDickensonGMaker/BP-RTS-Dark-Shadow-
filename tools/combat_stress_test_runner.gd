@tool
extends Node

## Combat Stress Test Runner (Editor-friendly version)
## Attach to a Node in the editor and run via the "_run_test" checkbox.
## Or run the scene directly from the editor.

# =============================================================================
# CONFIGURATION
# =============================================================================

@export var runs_per_matchup: int = 20
@export var combat_rounds_per_fight: int = 50
@export_group("Actions")
@export var _run_test: bool = false:
	set(value):
		if value and Engine.is_editor_hint():
			_run_stress_test()
		_run_test = false

const REGIMENT_DATA_PATH: String = "res://battle_system/data/regiments/"
const OUTPUT_FILE: String = "res://tools/stress_test_results.txt"

# Imbalance thresholds
const IMBALANCE_HIGH: float = 0.70
const IMBALANCE_LOW: float = 0.30

# =============================================================================
# COMBAT FORMULAS (FROM melee_resolver.gd)
# =============================================================================

const TO_HIT_EQUAL: float = 0.50
const TO_HIT_HIGHER: float = 0.66
const TO_HIT_MUCH_HIGHER: float = 0.83
const TO_HIT_LOWER: float = 0.33
const TO_HIT_MUCH_LOWER: float = 0.17

const TO_WOUND_EQUAL: float = 0.50
const TO_WOUND_HIGHER: float = 0.66
const TO_WOUND_MUCH_HIGHER: float = 0.83
const TO_WOUND_LOWER: float = 0.33
const TO_WOUND_MUCH_LOWER: float = 0.17

const ARMOR_SAVE_PER_POINT: float = 0.033
const MAX_ARMOR_SAVE: float = 0.66

const DEFAULT_FILES_PER_RANK: int = 8
const SUPPORT_RANK_MULTIPLIER: float = 0.5
const GENERAL_EFFECTIVE_SOLDIERS: int = 10

# =============================================================================
# VETERANCY / UPGRADE BONUSES
# =============================================================================

const VETERANCY_MELEE_BONUS: Array = [0.0, 0.05, 0.10, 0.15]
const VETERANCY_GENERAL_HP_BONUS: Array = [0, 2, 5, 8]

const UPGRADE_ATTACK_BONUS: Array = [0, 2, 4, 6]
const UPGRADE_DEFENSE_BONUS: Array = [0, 1, 2, 3]
const UPGRADE_ARMOR_BONUS: Array = [0, 1, 2, 3]
const UPGRADE_SOLDIER_BONUS: Array = [0, 2, 4, 6]

# =============================================================================
# UNIT TYPES
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

const SPEAR_VS_CAVALRY_BONUS: float = 1.25

const MELEE_MATCHUPS: Dictionary = {
	0: {0: 1.0, 1: 1.1, 2: 1.15, 3: 1.25, 4: 0.9, 5: 0.85},
	1: {0: 1.1, 1: 1.0, 2: 1.2, 3: 1.25, 4: 0.95, 5: 0.7},
	2: {0: 0.85, 1: 0.75, 2: 0.9, 3: 0.8, 4: 0.75, 5: 0.6},
	3: {0: 0.5, 1: 0.4, 2: 0.6, 3: 0.7, 4: 0.5, 5: 0.3},
	4: {0: 1.2, 1: 1.15, 2: 1.25, 3: 1.3, 4: 1.0, 5: 0.9},
	5: {0: 1.3, 1: 1.5, 2: 1.35, 3: 1.25, 4: 1.1, 5: 1.0}
}

# =============================================================================
# DATA CLASSES
# =============================================================================

class SimUnit:
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

	func reset() -> void:
		current_soldiers = max_soldiers

	func is_dead() -> bool:
		return current_soldiers <= 0

	func apply_casualties(count: int) -> void:
		current_soldiers = maxi(0, current_soldiers - count)

	func duplicate_unit() -> SimUnit:
		var copy := SimUnit.new()
		copy.name = name
		copy.unit_type = unit_type
		copy.faction = faction
		copy.attack = attack
		copy.defense = defense
		copy.weapon_skill = weapon_skill
		copy.strength = strength
		copy.armor = armor
		copy.max_soldiers = max_soldiers
		copy.current_soldiers = current_soldiers
		copy.charge_bonus = charge_bonus
		copy.is_spear = is_spear
		return copy


class MatchResult:
	var unit_a_name: String
	var unit_b_name: String
	var unit_a_wins: int = 0
	var unit_b_wins: int = 0
	var draws: int = 0
	var total_runs: int = 0
	var unit_a_avg_remaining: float = 0.0
	var unit_b_avg_remaining: float = 0.0

	func get_unit_a_winrate() -> float:
		if total_runs == 0:
			return 0.0
		return float(unit_a_wins) / float(total_runs)

	func is_imbalanced() -> bool:
		var wr := get_unit_a_winrate()
		return wr > 0.70 or wr < 0.30


# =============================================================================
# STATE
# =============================================================================

var all_units: Array = []
var results: Array = []
var output_lines: Array = []
var _vet_results: Array = []
var _upgrade_results: Array = []


# =============================================================================
# LIFECYCLE
# =============================================================================

func _ready() -> void:
	if not Engine.is_editor_hint():
		# Auto-run when scene is played
		call_deferred("_run_stress_test")


func _run_stress_test() -> void:
	print("=" .repeat(60))
	print("COMBAT STRESS TEST - Starting...")
	print("=" .repeat(60))
	print("")

	_load_all_regiment_data()

	if all_units.is_empty():
		print("ERROR: No regiment data files found!")
		return

	print("Loaded %d unit types" % all_units.size())
	print("")

	_run_all_tests()
	_generate_report()
	_save_results()

	print("")
	print("=" .repeat(60))
	print("STRESS TEST COMPLETE")
	print("Results saved to: %s" % OUTPUT_FILE)
	print("=" .repeat(60))


# =============================================================================
# DATA LOADING
# =============================================================================

func _load_all_regiment_data() -> void:
	all_units.clear()

	var dir := DirAccess.open(REGIMENT_DATA_PATH)
	if dir == null:
		print("ERROR: Cannot open directory: %s" % REGIMENT_DATA_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := REGIMENT_DATA_PATH + file_name
			var unit := _load_regiment_file(path)
			if unit != null:
				all_units.append(unit)
		file_name = dir.get_next()

	dir.list_dir_end()

	all_units.sort_custom(func(a, b) -> bool:
		if a.unit_type != b.unit_type:
			return a.unit_type < b.unit_type
		return a.name < b.name
	)


func _load_regiment_file(path: String) -> SimUnit:
	var resource := ResourceLoader.load(path)
	if resource == null:
		print("WARNING: Failed to load: %s" % path)
		return null

	var unit := SimUnit.new()
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

	var name_lower: String = unit.name.to_lower()
	unit.is_spear = (
		name_lower.contains("halb") or
		name_lower.contains("pike") or
		name_lower.contains("spear") or
		name_lower.contains("lance")
	)

	return unit


# =============================================================================
# COMBAT FORMULAS
# =============================================================================

func _calculate_to_hit(attacker_ws: int, defender_ws: int) -> float:
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


func _calculate_to_wound(str_val: int, def_val: int) -> float:
	var diff := str_val - def_val
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


func _calculate_armor_save(armor_val: int) -> float:
	var save := float(armor_val) * ARMOR_SAVE_PER_POINT
	return clampf(save, 0.0, MAX_ARMOR_SAVE)


func _calculate_effective_attacks(unit: SimUnit) -> int:
	if unit.unit_type == UnitTypeEnum.GENERAL:
		return GENERAL_EFFECTIVE_SOLDIERS

	var total := unit.current_soldiers
	var front_rank := mini(DEFAULT_FILES_PER_RANK, total)
	var remaining := maxi(total - front_rank, 0)
	var support := mini(DEFAULT_FILES_PER_RANK, remaining)
	var support_attacks := int(float(support) * SUPPORT_RANK_MULTIPLIER)

	return front_rank + support_attacks


func _get_melee_matchup(att_type: int, def_type: int) -> float:
	if not MELEE_MATCHUPS.has(att_type):
		return 1.0
	var matchups: Dictionary = MELEE_MATCHUPS[att_type]
	if not matchups.has(def_type):
		return 1.0
	return matchups[def_type]


func _apply_veterancy(unit: SimUnit, level: int) -> SimUnit:
	var modified := unit.duplicate_unit()
	var melee_mult := 1.0 + VETERANCY_MELEE_BONUS[level]
	modified.attack = int(float(unit.attack) * melee_mult)
	modified.weapon_skill = int(float(unit.weapon_skill) * melee_mult)

	if unit.unit_type == UnitTypeEnum.GENERAL:
		modified.max_soldiers = unit.max_soldiers + VETERANCY_GENERAL_HP_BONUS[level]

	modified.current_soldiers = modified.max_soldiers
	return modified


func _apply_upgrades(unit: SimUnit, level: int) -> SimUnit:
	var modified := unit.duplicate_unit()
	modified.attack = unit.attack + UPGRADE_ATTACK_BONUS[level]
	modified.defense = unit.defense + UPGRADE_DEFENSE_BONUS[level]
	modified.armor = unit.armor + UPGRADE_ARMOR_BONUS[level]
	modified.max_soldiers = unit.max_soldiers + UPGRADE_SOLDIER_BONUS[level]
	modified.current_soldiers = modified.max_soldiers
	return modified


func _simulate_combat_round(attacker: SimUnit, defender: SimUnit, is_charging: bool = false) -> int:
	var att_attacks := _calculate_effective_attacks(attacker)

	var att_ws := attacker.weapon_skill
	var matchup := _get_melee_matchup(attacker.unit_type, defender.unit_type)
	if attacker.is_spear and defender.unit_type == UnitTypeEnum.CAVALRY:
		matchup *= SPEAR_VS_CAVALRY_BONUS
	att_ws = int(float(att_ws) * matchup)

	var att_strength := attacker.strength

	if is_charging and attacker.charge_bonus > 0:
		att_ws += attacker.charge_bonus / 2
		att_strength += attacker.charge_bonus / 2

	var def_ws := defender.weapon_skill
	var def_defense := defender.defense
	var def_armor := defender.armor

	var to_hit := _calculate_to_hit(att_ws, def_ws)
	var to_wound := _calculate_to_wound(att_strength, def_defense)
	var armor_save := _calculate_armor_save(def_armor)

	var damage_per_wound := maxi(1, att_strength / 3)
	var total_casualties := 0

	for i in att_attacks:
		if randf() > to_hit:
			continue
		if randf() > to_wound:
			continue
		if randf() < armor_save:
			continue
		total_casualties += damage_per_wound

	return total_casualties


func _simulate_battle(unit_a: SimUnit, unit_b: SimUnit) -> int:
	unit_a.reset()
	unit_b.reset()

	var a_casualties := _simulate_combat_round(unit_b, unit_a, true)
	var b_casualties := _simulate_combat_round(unit_a, unit_b, true)
	unit_a.apply_casualties(a_casualties)
	unit_b.apply_casualties(b_casualties)

	for round_num in range(1, combat_rounds_per_fight):
		if unit_a.is_dead() or unit_b.is_dead():
			break

		a_casualties = _simulate_combat_round(unit_b, unit_a, false)
		b_casualties = _simulate_combat_round(unit_a, unit_b, false)
		unit_a.apply_casualties(a_casualties)
		unit_b.apply_casualties(b_casualties)

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

func _run_all_tests() -> void:
	results.clear()
	_vet_results.clear()
	_upgrade_results.clear()

	var total_matchups := all_units.size() * all_units.size()
	var current := 0

	print("Running matchup tests...")
	print("Total matchups: %d" % total_matchups)
	print("Runs per matchup: %d" % runs_per_matchup)
	print("")

	print("--- Testing Baseline (Vet 0, Upgrade 0) ---")

	for i in all_units.size():
		for j in all_units.size():
			current += 1
			if current % 100 == 0:
				print("  Progress: %d/%d" % [current, total_matchups])

			var result := _run_matchup(all_units[i], all_units[j], 0, 0, 0, 0)
			results.append(result)

	print("")
	print("--- Testing Veterancy Impact ---")

	var sample_units: Array = []
	var types_sampled: Dictionary = {}
	for unit in all_units:
		if not types_sampled.has(unit.unit_type) or types_sampled[unit.unit_type] < 3:
			sample_units.append(unit)
			types_sampled[unit.unit_type] = types_sampled.get(unit.unit_type, 0) + 1

	for unit_a in sample_units:
		for unit_b in sample_units:
			var vet3 := _run_matchup(unit_a, unit_b, 3, 0, 0, 0)
			var vet0 := _run_matchup(unit_a, unit_b, 0, 0, 0, 0)
			var advantage := vet3.get_unit_a_winrate() - vet0.get_unit_a_winrate()
			_vet_results.append({
				"unit_a": unit_a.name,
				"unit_b": unit_b.name,
				"vet0_winrate": vet0.get_unit_a_winrate(),
				"vet3_winrate": vet3.get_unit_a_winrate(),
				"advantage": advantage
			})

	print("")
	print("--- Testing Upgrade Impact ---")

	for unit_a in sample_units:
		for unit_b in sample_units:
			var upg3 := _run_matchup(unit_a, unit_b, 0, 0, 3, 0)
			var upg0 := _run_matchup(unit_a, unit_b, 0, 0, 0, 0)
			var advantage := upg3.get_unit_a_winrate() - upg0.get_unit_a_winrate()
			_upgrade_results.append({
				"unit_a": unit_a.name,
				"unit_b": unit_b.name,
				"upg0_winrate": upg0.get_unit_a_winrate(),
				"upg3_winrate": upg3.get_unit_a_winrate(),
				"advantage": advantage
			})


func _run_matchup(
	unit_a: SimUnit,
	unit_b: SimUnit,
	vet_a: int, vet_b: int,
	upg_a: int, upg_b: int
) -> MatchResult:
	var result := MatchResult.new()
	result.unit_a_name = unit_a.name
	result.unit_b_name = unit_b.name
	result.total_runs = runs_per_matchup

	var mod_a := _apply_upgrades(_apply_veterancy(unit_a, vet_a), upg_a)
	var mod_b := _apply_upgrades(_apply_veterancy(unit_b, vet_b), upg_b)

	var a_total_remaining := 0
	var b_total_remaining := 0

	for run_idx in runs_per_matchup:
		var outcome := _simulate_battle(mod_a, mod_b)

		if outcome > 0:
			result.unit_a_wins += 1
		elif outcome < 0:
			result.unit_b_wins += 1
		else:
			result.draws += 1

		a_total_remaining += mod_a.current_soldiers
		b_total_remaining += mod_b.current_soldiers

	result.unit_a_avg_remaining = float(a_total_remaining) / float(runs_per_matchup)
	result.unit_b_avg_remaining = float(b_total_remaining) / float(runs_per_matchup)

	return result


# =============================================================================
# REPORT GENERATION
# =============================================================================

func _generate_report() -> void:
	output_lines.clear()

	_add("=" .repeat(80))
	_add("COMBAT STRESS TEST REPORT")
	_add("Generated: %s" % Time.get_datetime_string_from_system())
	_add("=" .repeat(80))
	_add("")

	_add("CONFIGURATION")
	_add("-" .repeat(40))
	_add("Units tested: %d" % all_units.size())
	_add("Total matchups: %d" % results.size())
	_add("Runs per matchup: %d" % runs_per_matchup)
	_add("Combat rounds per fight: %d" % combat_rounds_per_fight)
	_add("")

	_add("UNIT ROSTER")
	_add("-" .repeat(40))
	_add("%-30s %-12s %-8s" % ["Name", "Type", "Faction"])
	_add("-" .repeat(50))
	for unit in all_units:
		var type_name: String = UNIT_TYPE_NAMES.get(unit.unit_type, "Unknown")
		_add("%-30s %-12s %-8s" % [unit.name.left(30), type_name, unit.faction])
	_add("")

	var imbalanced: Array = []
	for result in results:
		if result.is_imbalanced() and result.unit_a_name != result.unit_b_name:
			imbalanced.append(result)

	_add("IMBALANCED MATCHUPS (>70%% or <30%% win rate)")
	_add("-" .repeat(40))
	_add("Found %d imbalanced matchups" % imbalanced.size())
	_add("")

	imbalanced.sort_custom(func(a, b) -> bool:
		return absf(a.get_unit_a_winrate() - 0.5) > absf(b.get_unit_a_winrate() - 0.5)
	)

	if imbalanced.size() > 0:
		_add("%-25s vs %-25s | Win%% | Verdict" % ["Unit A", "Unit B"])
		_add("-" .repeat(75))

		var shown := 0
		for result in imbalanced:
			if shown >= 50:
				break
			var winrate := result.get_unit_a_winrate()
			var verdict: String
			if winrate > 0.70:
				verdict = "A FAVORED"
			else:
				verdict = "B FAVORED"
			_add("%-25s vs %-25s | %5.1f%% | %s" % [
				result.unit_a_name.left(25),
				result.unit_b_name.left(25),
				winrate * 100.0,
				verdict
			])
			shown += 1
	_add("")

	_add("UNIT TYPE WIN RATE MATRIX")
	_add("-" .repeat(40))
	_add("")

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

	var header := "%-10s" % ["Attacker"]
	for def_type in UNIT_TYPE_NAMES.keys():
		header += " | %-8s" % [UNIT_TYPE_NAMES[def_type].left(8)]
	_add(header)
	_add("-" .repeat(10 + 11 * UNIT_TYPE_NAMES.size()))

	for att_type in UNIT_TYPE_NAMES.keys():
		var row := "%-10s" % [UNIT_TYPE_NAMES[att_type].left(10)]
		for def_type in UNIT_TYPE_NAMES.keys():
			var data: Dictionary = type_matrix[att_type][def_type]
			if data["total"] > 0:
				var rate := float(data["wins"]) / float(data["total"]) * 100.0
				row += " | %6.1f%%" % [rate]
			else:
				row += " |   N/A  "
		_add(row)
	_add("")

	_add("FACTION PERFORMANCE")
	_add("-" .repeat(40))

	var faction_stats: Dictionary = {}
	for result in results:
		var att_faction := ""
		for unit in all_units:
			if unit.name == result.unit_a_name:
				att_faction = unit.faction
				break

		if att_faction != "":
			if not faction_stats.has(att_faction):
				faction_stats[att_faction] = {"wins": 0, "losses": 0, "draws": 0}
			faction_stats[att_faction]["wins"] += result.unit_a_wins
			faction_stats[att_faction]["losses"] += result.unit_b_wins
			faction_stats[att_faction]["draws"] += result.draws

	_add("%-12s | %8s | %8s | %8s | %8s" % ["Faction", "Wins", "Losses", "Draws", "Win%"])
	_add("-" .repeat(55))

	for faction in faction_stats.keys():
		var stats: Dictionary = faction_stats[faction]
		var total := stats["wins"] + stats["losses"] + stats["draws"]
		var winrate := 0.0
		if total > 0:
			winrate = float(stats["wins"]) / float(total) * 100.0
		_add("%-12s | %8d | %8d | %8d | %7.1f%%" % [
			str(faction).left(12),
			stats["wins"],
			stats["losses"],
			stats["draws"],
			winrate
		])
	_add("")

	_add("VETERANCY IMPACT (Level 3 vs Level 0)")
	_add("-" .repeat(40))

	if _vet_results.size() > 0:
		var total_adv := 0.0
		var max_adv := {"unit": "", "opponent": "", "value": 0.0}
		var min_adv := {"unit": "", "opponent": "", "value": 1.0}

		for entry in _vet_results:
			var adv: float = entry["advantage"]
			total_adv += adv
			if adv > max_adv["value"]:
				max_adv = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}
			if adv < min_adv["value"]:
				min_adv = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}

		var avg_adv := total_adv / float(_vet_results.size())
		_add("Average veterancy advantage: +%.1f%% win rate" % [avg_adv * 100.0])
		_add("Maximum benefit: %s vs %s (+%.1f%%)" % [
			max_adv["unit"], max_adv["opponent"], max_adv["value"] * 100.0
		])
		_add("Minimum benefit: %s vs %s (%+.1f%%)" % [
			min_adv["unit"], min_adv["opponent"], min_adv["value"] * 100.0
		])
	_add("")

	_add("UPGRADE IMPACT (Level 3 vs Level 0)")
	_add("-" .repeat(40))

	if _upgrade_results.size() > 0:
		var total_adv := 0.0
		var max_adv := {"unit": "", "opponent": "", "value": 0.0}
		var min_adv := {"unit": "", "opponent": "", "value": 1.0}

		for entry in _upgrade_results:
			var adv: float = entry["advantage"]
			total_adv += adv
			if adv > max_adv["value"]:
				max_adv = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}
			if adv < min_adv["value"]:
				min_adv = {"unit": entry["unit_a"], "opponent": entry["unit_b"], "value": adv}

		var avg_adv := total_adv / float(_upgrade_results.size())
		_add("Average upgrade advantage: +%.1f%% win rate" % [avg_adv * 100.0])
		_add("Maximum benefit: %s vs %s (+%.1f%%)" % [
			max_adv["unit"], max_adv["opponent"], max_adv["value"] * 100.0
		])
		_add("Minimum benefit: %s vs %s (%+.1f%%)" % [
			min_adv["unit"], min_adv["opponent"], min_adv["value"] * 100.0
		])
	_add("")

	_add("FULL MATCHUP RESULTS")
	_add("-" .repeat(40))
	_add("%-25s vs %-25s | A-Win | B-Win | Draw | A-Rem | B-Rem" % ["Unit A", "Unit B"])
	_add("-" .repeat(95))

	for result in results:
		if result.unit_a_name == result.unit_b_name:
			continue
		_add("%-25s vs %-25s | %5d | %5d | %4d | %5.1f | %5.1f" % [
			result.unit_a_name.left(25),
			result.unit_b_name.left(25),
			result.unit_a_wins,
			result.unit_b_wins,
			result.draws,
			result.unit_a_avg_remaining,
			result.unit_b_avg_remaining
		])

	_add("")
	_add("=" .repeat(80))
	_add("END OF REPORT")
	_add("=" .repeat(80))

	print("")
	print("SUMMARY:")
	print("  Total units: %d" % all_units.size())
	print("  Total matchups tested: %d" % results.size())
	print("  Imbalanced matchups: %d" % imbalanced.size())

	if imbalanced.size() > 0:
		print("")
		print("TOP 10 MOST IMBALANCED:")
		var count := 0
		for result in imbalanced:
			if count >= 10:
				break
			var wr := result.get_unit_a_winrate()
			var winner: String
			var loser: String
			if wr > 0.5:
				winner = result.unit_a_name
				loser = result.unit_b_name
			else:
				winner = result.unit_b_name
				loser = result.unit_a_name
				wr = 1.0 - wr
			print("  %s beats %s %.0f%% of the time" % [winner, loser, wr * 100.0])
			count += 1


func _add(line: String) -> void:
	output_lines.append(line)


# =============================================================================
# FILE OUTPUT
# =============================================================================

func _save_results() -> void:
	var file := FileAccess.open(OUTPUT_FILE, FileAccess.WRITE)
	if file == null:
		print("ERROR: Failed to open output file: %s" % OUTPUT_FILE)
		return

	for line in output_lines:
		file.store_line(line)

	file.close()
	print("Results saved to: %s" % OUTPUT_FILE)
