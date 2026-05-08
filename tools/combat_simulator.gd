## Combat Simulator - Tests 1v1 unit matchups
## Run from editor: Tools > Execute Script or via command line
## Results are printed to console and saved to tools/combat_results.txt

extends SceneTree

# Combat constants (matching melee_resolver.gd)
const TO_HIT_MUCH_HIGHER: float = 0.83  # WS diff +4 or more
const TO_HIT_HIGHER: float = 0.66       # WS diff +1 to +3
const TO_HIT_EQUAL: float = 0.50        # WS equal
const TO_HIT_LOWER: float = 0.33        # WS diff -1 to -3
const TO_HIT_MUCH_LOWER: float = 0.17   # WS diff -4 or less

const TO_WOUND_MUCH_HIGHER: float = 0.83  # Str diff +3 or more
const TO_WOUND_HIGHER: float = 0.66       # Str diff +1 to +2
const TO_WOUND_EQUAL: float = 0.50        # Str equal
const TO_WOUND_LOWER: float = 0.33        # Str diff -1 to -2
const TO_WOUND_MUCH_LOWER: float = 0.17   # Str diff -3 or less

const ARMOR_SAVE_PER_POINT: float = 0.033
const MAX_ARMOR_SAVE: float = 0.66

const FILES_PER_RANK: int = 8
const SUPPORT_RANK_MULTIPLIER: float = 0.5
const GENERAL_EFFECTIVE_SOLDIERS: int = 10
const MONSTER_EFFECTIVE_MULTIPLIER: float = 3.0  # Each monster fights as 3 soldiers

const MELEE_TICK_RATE: float = 1.875
const MAX_COMBAT_ROUNDS: int = 50  # ~94 seconds max combat

# Veterancy bonuses
const VET_LEVELS = {
	0: {"name": "Fresh", "attack": 0, "defense": 0, "morale": 0},
	1: {"name": "Trained", "attack": 2, "defense": 1, "morale": 5},
	2: {"name": "Veteran", "attack": 4, "defense": 2, "morale": 10},
	3: {"name": "Elite", "attack": 6, "defense": 4, "morale": 15},
}

# Upgrade levels (blacksmith/armory)
const UPGRADE_LEVELS = {
	0: {"name": "Basic", "armor": 0, "weapon": 0},
	1: {"name": "Improved", "armor": 2, "weapon": 2},
	2: {"name": "Superior", "armor": 4, "weapon": 4},
	3: {"name": "Masterwork", "armor": 6, "weapon": 6},
}

# Unit type enum
enum UnitType { INFANTRY = 0, CAVALRY = 1, RANGED = 2, ARTILLERY = 3, GENERAL = 4, MONSTER = 5 }

# Simulated unit data
class UnitData:
	var name: String
	var unit_type: int
	var attack: int
	var defense: int
	var weapon_skill: int
	var strength: int
	var armor: int
	var max_soldiers: int
	var base_morale: float
	var morale_save: int
	var mass: float
	var charge_bonus: int

	func _init(dict: Dictionary) -> void:
		name = dict.get("name", "Unknown")
		unit_type = dict.get("unit_type", 0)
		attack = dict.get("attack", 10)
		defense = dict.get("defense", 10)
		weapon_skill = dict.get("weapon_skill", 10)
		strength = dict.get("strength", 5)
		armor = dict.get("armor", 0)
		max_soldiers = dict.get("max_soldiers", 20)
		base_morale = dict.get("base_morale", 70.0)
		morale_save = dict.get("morale_save", 5)
		mass = dict.get("mass", 1.0)
		charge_bonus = dict.get("charge_bonus", 6)


class CombatUnit:
	var data: UnitData
	var current_soldiers: int
	var current_morale: float
	var is_routing: bool = false
	var vet_level: int = 0
	var upgrade_level: int = 0

	func _init(unit_data: UnitData, vet: int = 0, upgrade: int = 0) -> void:
		data = unit_data
		current_soldiers = data.max_soldiers
		current_morale = data.base_morale
		vet_level = vet
		upgrade_level = upgrade

	func get_effective_ws() -> int:
		return data.weapon_skill + VET_LEVELS[vet_level]["attack"] + UPGRADE_LEVELS[upgrade_level]["weapon"]

	func get_effective_strength() -> int:
		return data.strength + UPGRADE_LEVELS[upgrade_level]["weapon"]

	func get_effective_defense() -> int:
		return data.defense + VET_LEVELS[vet_level]["defense"]

	func get_effective_armor() -> int:
		return data.armor + UPGRADE_LEVELS[upgrade_level]["armor"]

	func get_effective_morale() -> float:
		return data.base_morale + VET_LEVELS[vet_level]["morale"]

	func is_alive() -> bool:
		return current_soldiers > 0 and not is_routing


# All unit definitions loaded from regiment files
var units: Array[UnitData] = []
var results: Array[Dictionary] = []


func _init() -> void:
	print("\n========================================")
	print("  BP RTS COMBAT SIMULATOR")
	print("========================================\n")

	load_units()
	run_all_matchups()
	analyze_results()
	save_results()

	quit()


func load_units() -> void:
	print("Loading unit definitions...")

	# Define all units based on .tres files
	units = [
		# Empire Infantry
		UnitData.new({"name": "Greatswords", "unit_type": UnitType.INFANTRY, "attack": 16, "defense": 14, "weapon_skill": 14, "strength": 5, "armor": 7, "max_soldiers": 24, "base_morale": 85.0, "morale_save": 4, "mass": 1.0, "charge_bonus": 6}),
		UnitData.new({"name": "Empire Swordsmen", "unit_type": UnitType.INFANTRY, "attack": 12, "defense": 12, "weapon_skill": 12, "strength": 4, "armor": 5, "max_soldiers": 30, "base_morale": 75.0, "morale_save": 5, "mass": 1.0, "charge_bonus": 4}),
		UnitData.new({"name": "Halberdiers", "unit_type": UnitType.INFANTRY, "attack": 14, "defense": 12, "weapon_skill": 12, "strength": 5, "armor": 4, "max_soldiers": 28, "base_morale": 75.0, "morale_save": 5, "mass": 1.0, "charge_bonus": 5}),

		# Dwarf Infantry
		UnitData.new({"name": "Dwarf Warriors", "unit_type": UnitType.INFANTRY, "attack": 14, "defense": 16, "weapon_skill": 14, "strength": 5, "armor": 8, "max_soldiers": 20, "base_morale": 90.0, "morale_save": 3, "mass": 1.2, "charge_bonus": 4}),
		UnitData.new({"name": "Ironbreakers", "unit_type": UnitType.INFANTRY, "attack": 16, "defense": 18, "weapon_skill": 16, "strength": 5, "armor": 12, "max_soldiers": 16, "base_morale": 95.0, "morale_save": 2, "mass": 1.3, "charge_bonus": 4}),
		UnitData.new({"name": "Slayers", "unit_type": UnitType.INFANTRY, "attack": 20, "defense": 10, "weapon_skill": 18, "strength": 6, "armor": 0, "max_soldiers": 16, "base_morale": 100.0, "morale_save": 1, "mass": 1.1, "charge_bonus": 8}),

		# Greenskin Infantry
		UnitData.new({"name": "Orc Boyz", "unit_type": UnitType.INFANTRY, "attack": 14, "defense": 12, "weapon_skill": 12, "strength": 5, "armor": 4, "max_soldiers": 30, "base_morale": 70.0, "morale_save": 6, "mass": 1.1, "charge_bonus": 6}),
		UnitData.new({"name": "Big Uns", "unit_type": UnitType.INFANTRY, "attack": 18, "defense": 14, "weapon_skill": 14, "strength": 6, "armor": 6, "max_soldiers": 24, "base_morale": 75.0, "morale_save": 5, "mass": 1.2, "charge_bonus": 7}),
		UnitData.new({"name": "Black Orcs", "unit_type": UnitType.INFANTRY, "attack": 20, "defense": 16, "weapon_skill": 16, "strength": 6, "armor": 8, "max_soldiers": 20, "base_morale": 85.0, "morale_save": 4, "mass": 1.3, "charge_bonus": 6}),
		UnitData.new({"name": "Goblins", "unit_type": UnitType.INFANTRY, "attack": 8, "defense": 8, "weapon_skill": 8, "strength": 3, "armor": 2, "max_soldiers": 40, "base_morale": 50.0, "morale_save": 7, "mass": 0.7, "charge_bonus": 2}),

		# Cavalry
		UnitData.new({"name": "Empire Knights", "unit_type": UnitType.CAVALRY, "attack": 18, "defense": 14, "weapon_skill": 14, "strength": 6, "armor": 10, "max_soldiers": 12, "base_morale": 85.0, "morale_save": 4, "mass": 2.5, "charge_bonus": 12}),
		UnitData.new({"name": "Boar Boyz", "unit_type": UnitType.CAVALRY, "attack": 16, "defense": 12, "weapon_skill": 12, "strength": 6, "armor": 6, "max_soldiers": 10, "base_morale": 75.0, "morale_save": 5, "mass": 2.8, "charge_bonus": 14}),
		UnitData.new({"name": "Wolf Riders", "unit_type": UnitType.CAVALRY, "attack": 10, "defense": 8, "weapon_skill": 10, "strength": 4, "armor": 3, "max_soldiers": 15, "base_morale": 55.0, "morale_save": 7, "mass": 1.8, "charge_bonus": 8}),

		# Ranged
		UnitData.new({"name": "Empire Crossbows", "unit_type": UnitType.RANGED, "attack": 8, "defense": 10, "weapon_skill": 10, "strength": 4, "armor": 3, "max_soldiers": 20, "base_morale": 70.0, "morale_save": 6, "mass": 1.0, "charge_bonus": 2}),
		UnitData.new({"name": "Dwarf Crossbows", "unit_type": UnitType.RANGED, "attack": 10, "defense": 14, "weapon_skill": 12, "strength": 5, "armor": 6, "max_soldiers": 16, "base_morale": 85.0, "morale_save": 4, "mass": 1.2, "charge_bonus": 2}),
		UnitData.new({"name": "Goblin Archers", "unit_type": UnitType.RANGED, "attack": 6, "defense": 6, "weapon_skill": 6, "strength": 2, "armor": 1, "max_soldiers": 30, "base_morale": 45.0, "morale_save": 8, "mass": 0.7, "charge_bonus": 1}),

		# Monsters (updated stats)
		UnitData.new({"name": "Trolls", "unit_type": UnitType.MONSTER, "attack": 32, "defense": 22, "weapon_skill": 10, "strength": 14, "armor": 2, "max_soldiers": 4, "base_morale": 55.0, "morale_save": 4, "mass": 4.0, "charge_bonus": 14}),
		UnitData.new({"name": "Giant", "unit_type": UnitType.MONSTER, "attack": 40, "defense": 28, "weapon_skill": 8, "strength": 18, "armor": 0, "max_soldiers": 1, "base_morale": 60.0, "morale_save": 3, "mass": 8.0, "charge_bonus": 20}),
		UnitData.new({"name": "Rat Ogres", "unit_type": UnitType.MONSTER, "attack": 28, "defense": 20, "weapon_skill": 10, "strength": 14, "armor": 1, "max_soldiers": 4, "base_morale": 50.0, "morale_save": 5, "mass": 3.5, "charge_bonus": 10}),
		UnitData.new({"name": "Treeman", "unit_type": UnitType.MONSTER, "attack": 38, "defense": 30, "weapon_skill": 16, "strength": 18, "armor": 5, "max_soldiers": 1, "base_morale": 85.0, "morale_save": 2, "mass": 7.0, "charge_bonus": 15}),
		UnitData.new({"name": "Dragon", "unit_type": UnitType.MONSTER, "attack": 45, "defense": 32, "weapon_skill": 18, "strength": 20, "armor": 6, "max_soldiers": 1, "base_morale": 75.0, "morale_save": 2, "mass": 10.0, "charge_bonus": 18}),
		UnitData.new({"name": "Wyvern", "unit_type": UnitType.MONSTER, "attack": 30, "defense": 26, "weapon_skill": 14, "strength": 14, "armor": 3, "max_soldiers": 2, "base_morale": 55.0, "morale_save": 5, "mass": 5.0, "charge_bonus": 12}),

		# Generals/Heroes
		UnitData.new({"name": "Empire General", "unit_type": UnitType.GENERAL, "attack": 22, "defense": 20, "weapon_skill": 20, "strength": 8, "armor": 12, "max_soldiers": 1, "base_morale": 100.0, "morale_save": 1, "mass": 1.5, "charge_bonus": 10}),
		UnitData.new({"name": "Dwarf Thane", "unit_type": UnitType.GENERAL, "attack": 22, "defense": 28, "weapon_skill": 24, "strength": 14, "armor": 15, "max_soldiers": 1, "base_morale": 100.0, "morale_save": 1, "mass": 2.5, "charge_bonus": 12}),
		UnitData.new({"name": "Orc Warboss", "unit_type": UnitType.GENERAL, "attack": 24, "defense": 18, "weapon_skill": 18, "strength": 10, "armor": 8, "max_soldiers": 1, "base_morale": 90.0, "morale_save": 2, "mass": 1.8, "charge_bonus": 14}),
	]

	print("Loaded %d unit types\n" % units.size())


func run_all_matchups() -> void:
	print("Running combat simulations...")
	print("Each matchup runs 20 times\n")

	var total_matchups: int = units.size() * units.size()
	var current: int = 0

	for unit_a in units:
		for unit_b in units:
			current += 1
			if current % 50 == 0:
				print("Progress: %d/%d matchups..." % [current, total_matchups])

			var matchup_results: Dictionary = run_matchup(unit_a, unit_b, 20, 0, 0)
			results.append(matchup_results)

	print("\nBase matchups complete. Running veterancy tests...\n")

	# Run veterancy tests for key matchups
	var test_pairs: Array = [
		["Greatswords", "Trolls"],
		["Greatswords", "Orc Boyz"],
		["Empire Knights", "Halberdiers"],
		["Dwarf Warriors", "Black Orcs"],
		["Trolls", "Ironbreakers"],
	]

	for pair in test_pairs:
		var unit_a: UnitData = find_unit(pair[0])
		var unit_b: UnitData = find_unit(pair[1])
		if unit_a and unit_b:
			for vet in range(4):
				for upgrade in range(4):
					var result: Dictionary = run_matchup(unit_a, unit_b, 10, vet, upgrade)
					result["vet_level"] = vet
					result["upgrade_level"] = upgrade
					results.append(result)


func find_unit(unit_name: String) -> UnitData:
	for u in units:
		if u.name == unit_name:
			return u
	return null


func run_matchup(unit_a: UnitData, unit_b: UnitData, iterations: int, vet: int = 0, upgrade: int = 0) -> Dictionary:
	var a_wins: int = 0
	var b_wins: int = 0
	var draws: int = 0
	var a_survivors_total: int = 0
	var b_survivors_total: int = 0
	var rounds_total: int = 0

	for i in iterations:
		var combat_a: CombatUnit = CombatUnit.new(unit_a, vet, upgrade)
		var combat_b: CombatUnit = CombatUnit.new(unit_b, vet, upgrade)

		var round_count: int = 0
		while combat_a.is_alive() and combat_b.is_alive() and round_count < MAX_COMBAT_ROUNDS:
			resolve_combat_round(combat_a, combat_b)
			round_count += 1

		rounds_total += round_count

		if combat_a.is_alive() and not combat_b.is_alive():
			a_wins += 1
			a_survivors_total += combat_a.current_soldiers
		elif combat_b.is_alive() and not combat_a.is_alive():
			b_wins += 1
			b_survivors_total += combat_b.current_soldiers
		else:
			draws += 1

	return {
		"unit_a": unit_a.name,
		"unit_b": unit_b.name,
		"unit_a_type": unit_a.unit_type,
		"unit_b_type": unit_b.unit_type,
		"a_wins": a_wins,
		"b_wins": b_wins,
		"draws": draws,
		"a_win_rate": float(a_wins) / float(iterations) * 100.0,
		"b_win_rate": float(b_wins) / float(iterations) * 100.0,
		"a_avg_survivors": float(a_survivors_total) / float(maxi(a_wins, 1)),
		"b_avg_survivors": float(b_survivors_total) / float(maxi(b_wins, 1)),
		"avg_rounds": float(rounds_total) / float(iterations),
		"iterations": iterations,
	}


func resolve_combat_round(unit_a: CombatUnit, unit_b: CombatUnit) -> void:
	# Both sides attack simultaneously
	var a_casualties: int = calculate_attacks(unit_a, unit_b)
	var b_casualties: int = calculate_attacks(unit_b, unit_a)

	# Apply casualties
	unit_a.current_soldiers = maxi(0, unit_a.current_soldiers - b_casualties)
	unit_b.current_soldiers = maxi(0, unit_b.current_soldiers - a_casualties)

	# Apply morale damage
	unit_a.current_morale -= float(b_casualties) * 0.5
	unit_b.current_morale -= float(a_casualties) * 0.5

	# Check for routing
	if unit_a.current_morale <= 20.0:
		unit_a.is_routing = true
	if unit_b.current_morale <= 20.0:
		unit_b.is_routing = true


func calculate_attacks(attacker: CombatUnit, defender: CombatUnit) -> int:
	var effective_attacks: int = get_effective_attacks(attacker)
	var total_casualties: int = 0

	var hit_chance: float = calculate_to_hit(attacker.get_effective_ws(), defender.get_effective_ws())
	var wound_chance: float = calculate_to_wound(attacker.get_effective_strength(), defender.get_effective_defense())
	var armor_save: float = calculate_armor_save(defender.get_effective_armor())

	for i in effective_attacks:
		if randf() < hit_chance:
			if randf() < wound_chance:
				if randf() >= armor_save:
					total_casualties += 1

	return total_casualties


func get_effective_attacks(unit: CombatUnit) -> int:
	# Generals fight as 10 elite soldiers
	if unit.data.unit_type == UnitType.GENERAL:
		return GENERAL_EFFECTIVE_SOLDIERS

	# Monsters fight as multiple soldiers each
	if unit.data.unit_type == UnitType.MONSTER:
		return int(float(unit.current_soldiers) * MONSTER_EFFECTIVE_MULTIPLIER)

	# Regular units: front rank + support
	var front_rank: int = mini(FILES_PER_RANK, unit.current_soldiers)
	var remaining: int = maxi(0, unit.current_soldiers - front_rank)
	var support: int = int(float(mini(remaining, FILES_PER_RANK)) * SUPPORT_RANK_MULTIPLIER)

	return front_rank + support


func calculate_to_hit(attacker_ws: int, defender_ws: int) -> float:
	var diff: int = attacker_ws - defender_ws
	if diff >= 4:
		return TO_HIT_MUCH_HIGHER
	elif diff >= 1:
		return TO_HIT_HIGHER
	elif diff == 0:
		return TO_HIT_EQUAL
	elif diff >= -3:
		return TO_HIT_LOWER
	else:
		return TO_HIT_MUCH_LOWER


func calculate_to_wound(strength: int, defense: int) -> float:
	var diff: int = strength - defense
	if diff >= 3:
		return TO_WOUND_MUCH_HIGHER
	elif diff >= 1:
		return TO_WOUND_HIGHER
	elif diff == 0:
		return TO_WOUND_EQUAL
	elif diff >= -2:
		return TO_WOUND_LOWER
	else:
		return TO_WOUND_MUCH_LOWER


func calculate_armor_save(armor: int) -> float:
	return minf(float(armor) * ARMOR_SAVE_PER_POINT, MAX_ARMOR_SAVE)


func analyze_results() -> void:
	print("\n========================================")
	print("  COMBAT ANALYSIS RESULTS")
	print("========================================\n")

	# Find imbalanced matchups
	print("=== IMBALANCED MATCHUPS (>70% or <30% win rate) ===\n")

	var imbalanced: Array[Dictionary] = []
	for r in results:
		if r.get("vet_level", 0) == 0 and r.get("upgrade_level", 0) == 0:
			if r["a_win_rate"] > 70.0 or r["a_win_rate"] < 30.0:
				if r["unit_a"] != r["unit_b"]:  # Skip mirror matches
					imbalanced.append(r)

	# Sort by most imbalanced
	imbalanced.sort_custom(func(a, b): return absf(a["a_win_rate"] - 50.0) > absf(b["a_win_rate"] - 50.0))

	for i in mini(30, imbalanced.size()):
		var r: Dictionary = imbalanced[i]
		var winner: String = r["unit_a"] if r["a_win_rate"] > 50.0 else r["unit_b"]
		var loser: String = r["unit_b"] if r["a_win_rate"] > 50.0 else r["unit_a"]
		var win_rate: float = maxf(r["a_win_rate"], r["b_win_rate"])
		print("%s vs %s: %s wins %.0f%%" % [r["unit_a"], r["unit_b"], winner, win_rate])

	# Monster vs Infantry analysis
	print("\n=== MONSTER VS INFANTRY MATCHUPS ===\n")
	for r in results:
		if r.get("vet_level", 0) == 0 and r.get("upgrade_level", 0) == 0:
			if r["unit_a_type"] == UnitType.MONSTER and r["unit_b_type"] == UnitType.INFANTRY:
				print("%s vs %s: Monster wins %.0f%% (avg survivors: %.1f)" % [
					r["unit_a"], r["unit_b"], r["a_win_rate"], r["a_avg_survivors"]
				])

	# Infantry vs Infantry baseline
	print("\n=== INFANTRY VS INFANTRY MATCHUPS ===\n")
	for r in results:
		if r.get("vet_level", 0) == 0 and r.get("upgrade_level", 0) == 0:
			if r["unit_a_type"] == UnitType.INFANTRY and r["unit_b_type"] == UnitType.INFANTRY:
				if r["unit_a"] != r["unit_b"]:
					print("%s vs %s: %.0f%% / %.0f%%" % [
						r["unit_a"], r["unit_b"], r["a_win_rate"], r["b_win_rate"]
					])

	# Cavalry vs Infantry
	print("\n=== CAVALRY VS INFANTRY MATCHUPS ===\n")
	for r in results:
		if r.get("vet_level", 0) == 0 and r.get("upgrade_level", 0) == 0:
			if r["unit_a_type"] == UnitType.CAVALRY and r["unit_b_type"] == UnitType.INFANTRY:
				print("%s vs %s: Cavalry wins %.0f%%" % [
					r["unit_a"], r["unit_b"], r["a_win_rate"]
				])

	# General vs various
	print("\n=== GENERAL/HERO MATCHUPS ===\n")
	for r in results:
		if r.get("vet_level", 0) == 0 and r.get("upgrade_level", 0) == 0:
			if r["unit_a_type"] == UnitType.GENERAL:
				print("%s vs %s: Hero wins %.0f%%" % [
					r["unit_a"], r["unit_b"], r["a_win_rate"]
				])

	# Veterancy impact
	print("\n=== VETERANCY IMPACT (Greatswords vs Trolls) ===\n")
	for r in results:
		if r["unit_a"] == "Greatswords" and r["unit_b"] == "Trolls":
			if r.get("vet_level", -1) >= 0:
				print("Vet %d, Upgrade %d: Greatswords win %.0f%%" % [
					r.get("vet_level", 0), r.get("upgrade_level", 0), r["a_win_rate"]
				])


func save_results() -> void:
	var file_path: String = "res://tools/combat_results.txt"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("Failed to save results to file")
		return

	file.store_line("BP RTS Combat Simulation Results")
	file.store_line("================================\n")

	for r in results:
		var line: String = "%s vs %s: %.0f%% / %.0f%% (avg rounds: %.1f)" % [
			r["unit_a"], r["unit_b"], r["a_win_rate"], r["b_win_rate"], r["avg_rounds"]
		]
		if r.get("vet_level", 0) > 0 or r.get("upgrade_level", 0) > 0:
			line += " [Vet:%d Upg:%d]" % [r.get("vet_level", 0), r.get("upgrade_level", 0)]
		file.store_line(line)

	file.close()
	print("\nResults saved to: %s" % file_path)
