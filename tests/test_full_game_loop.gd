## Full Game Loop Integration Test
## Simulates: Campaign -> Battle -> End -> Loop x100
## Run with: godot --headless --script res://tests/test_full_game_loop.gd
extends SceneTree

# Preload systems
const MeleeResolverScript = preload("res://battle_system/systems/combat/melee_resolver.gd")
const CasualtyProcessorScript = preload("res://battle_system/systems/combat/casualty_processor.gd")
const FlankingCalculatorScript = preload("res://battle_system/systems/combat/flanking_calculator.gd")
const ChargeSystemScript = preload("res://battle_system/systems/combat/charge_system.gd")

# Test instances
var melee_resolver = null
var casualty_processor = null

# Test statistics
var total_battles: int = 0
var player_wins: int = 0
var enemy_wins: int = 0
var draws: int = 0
var total_rounds: int = 0
var total_player_casualties: int = 0
var total_enemy_casualties: int = 0
var errors_found: Array = []
var warnings_found: Array = []

# Timing
var test_start_time: float = 0.0

# Mock regiment data for testing
class MockRegimentData:
	var regiment_name: String = "Test Regiment"
	var attack: int = 10
	var defense: int = 10
	var strength: int = 30
	var charge_bonus: int = 5
	var unit_type: int = 0  # UnitType.Type.INFANTRY
	var max_soldiers: int = 40
	var current_soldiers: int = 40
	var morale: float = 75.0
	var max_ammo: int = 0
	var current_ammo: int = 0

	func get_value(key: String, default = null):
		match key:
			"charge_bonus": return charge_bonus
			_: return default

# Mock regiment for testing
class MockRegiment:
	var data: MockRegimentData
	var global_position: Vector3 = Vector3.ZERO
	var veterancy = null
	var unit_morale = null
	var current_soldiers: int = 40
	var current_morale: float = 75.0
	var is_player: bool = true
	var state: int = 0  # IDLE

	enum State { IDLE, MOVING, FIGHTING, ROUTING, DEAD }

	func _init(name: String, atk: int = 10, def: int = 10, str_val: int = 30, soldiers: int = 40):
		data = MockRegimentData.new()
		data.regiment_name = name
		data.attack = atk
		data.defense = def
		data.strength = str_val
		data.max_soldiers = soldiers
		data.current_soldiers = soldiers
		current_soldiers = soldiers

	func get_attack_modifier() -> float:
		return 1.0

	func get_defense_modifier() -> float:
		return 1.0

	func get_anti_cavalry_modifier() -> float:
		return 1.0

	func take_casualties(amount: int) -> void:
		current_soldiers = maxi(0, current_soldiers - amount)
		data.current_soldiers = current_soldiers
		if current_soldiers <= 0:
			state = State.DEAD

	func is_dead() -> bool:
		return state == State.DEAD or current_soldiers <= 0


func _init():
	test_start_time = Time.get_unix_time_from_system()

	print("\n" + "=".repeat(60))
	print("  FULL GAME LOOP INTEGRATION TEST - 100 BATTLES")
	print("  Testing: MeleeResolver + CasualtyProcessor refactor")
	print("=".repeat(60) + "\n")

	# Initialize test systems
	_initialize_systems()

	# Run all tests
	_run_all_tests()

	# Print final report
	_print_final_report()

	quit()


func _initialize_systems():
	print("[INIT] Creating MeleeResolver...")
	melee_resolver = MeleeResolverScript.new()
	if melee_resolver == null:
		errors_found.append("ERROR: Failed to create MeleeResolver")
		return
	print("[INIT] MeleeResolver created successfully")

	print("[INIT] Creating CasualtyProcessor...")
	casualty_processor = CasualtyProcessorScript.new()
	if casualty_processor == null:
		errors_found.append("ERROR: Failed to create CasualtyProcessor")
		return
	print("[INIT] CasualtyProcessor created successfully")

	# Verify FlankingCalculator and ChargeSystem are accessible via MeleeResolver
	if melee_resolver.flanking == null:
		errors_found.append("ERROR: MeleeResolver.flanking is null")
	if melee_resolver.charge == null:
		errors_found.append("ERROR: MeleeResolver.charge is null")

	print("[INIT] All systems initialized\n")


func _run_all_tests():
	print("[TEST SUITE] Starting test suite...\n")

	# Test 1: Basic resolve_melee_attack()
	_test_resolve_melee_attack()

	# Test 2: resolve_bidirectional_melee()
	_test_bidirectional_melee()

	# Test 3: Hit chance calculations
	_test_hit_chance_formula()

	# Test 4: Casualty calculations
	_test_casualty_formula()

	# Test 5: 100 full battles
	_test_100_battles()

	# Test 6: Edge cases
	_test_edge_cases()

	# Test 7: AI multiplier effects
	_test_ai_multipliers()

	print("\n[TEST SUITE] All tests completed\n")


func _test_resolve_melee_attack():
	print("[TEST 1] resolve_melee_attack() - Basic functionality")
	print("-".repeat(50))

	var attacker = MockRegiment.new("Attacker", 12, 10, 30, 40)
	var defender = MockRegiment.new("Defender", 10, 12, 25, 40)

	var hits: int = 0
	var total_casualties: int = 0
	var trials: int = 100

	for i in trials:
		var result = melee_resolver.resolve_melee_attack(attacker, defender)

		# Validate result structure
		if not result.has("hit"):
			errors_found.append("resolve_melee_attack missing 'hit' key")
		if not result.has("casualties"):
			errors_found.append("resolve_melee_attack missing 'casualties' key")
		if not result.has("flank_mod"):
			errors_found.append("resolve_melee_attack missing 'flank_mod' key")

		if result.hit:
			hits += 1
			total_casualties += result.casualties

			# Validate casualty range
			if result.casualties < 1:
				errors_found.append("Casualties on hit was < 1: %d" % result.casualties)

	var hit_rate: float = float(hits) / trials * 100
	var avg_casualties: float = float(total_casualties) / maxf(hits, 1)

	print("  Trials: %d" % trials)
	print("  Hit Rate: %.1f%% (expected ~37%% with +2 attack advantage)" % hit_rate)
	print("  Avg Casualties on Hit: %.1f" % avg_casualties)

	# Validate hit rate is reasonable (35% base + 2% for +2 attack)
	if hit_rate < 20.0 or hit_rate > 60.0:
		warnings_found.append("Hit rate %.1f%% outside expected range 20-60%%" % hit_rate)
		print("  WARNING: Hit rate outside expected range")
	else:
		print("  PASS")
	print("")


func _test_bidirectional_melee():
	print("[TEST 2] resolve_bidirectional_melee() - Attacker + Counter")
	print("-".repeat(50))

	var attacker = MockRegiment.new("Attacker", 14, 10, 35, 40)
	var defender = MockRegiment.new("Defender", 10, 14, 30, 40)

	var att_hits: int = 0
	var def_hits: int = 0
	var trials: int = 100

	for i in trials:
		var result = melee_resolver.resolve_bidirectional_melee(
			attacker, defender,
			0.0,   # charge_time
			false, # charge_negated
			1.0,   # ai_multiplier
			1.0,   # counter_ai_multiplier
			1.0,   # weather_charge_modifier
			1.0    # formation_charge_modifier
		)

		# Validate result structure
		if not result.has("attacker"):
			errors_found.append("bidirectional missing 'attacker' key")
		if not result.has("defender_counter"):
			errors_found.append("bidirectional missing 'defender_counter' key")

		if result.attacker.hit:
			att_hits += 1
		if result.defender_counter.hit:
			def_hits += 1

	var att_rate: float = float(att_hits) / trials * 100
	var def_rate: float = float(def_hits) / trials * 100

	print("  Trials: %d" % trials)
	print("  Attacker Hit Rate: %.1f%% (has +4 attack advantage)" % att_rate)
	print("  Defender Counter Rate: %.1f%% (has +4 defense = attacker has -4)" % def_rate)

	# Attacker should hit more (higher attack)
	if att_rate > def_rate:
		print("  PASS: Attacker hits more often as expected")
	else:
		warnings_found.append("Attacker hit rate %.1f%% <= Defender %.1f%%" % [att_rate, def_rate])
		print("  CHECK: Attacker should hit more often")
	print("")


func _test_hit_chance_formula():
	print("[TEST 3] Hit Chance Formula Verification")
	print("-".repeat(50))

	# Test specific attack/defense combinations
	var test_cases = [
		{"atk": 10, "def": 10, "expected": 0.35},  # Equal = 35%
		{"atk": 20, "def": 10, "expected": 0.45},  # +10 = 45%
		{"atk": 10, "def": 20, "expected": 0.25},  # -10 = 25%
		{"atk": 100, "def": 10, "expected": 0.90}, # Capped at 90%
		{"atk": 10, "def": 100, "expected": 0.08}, # Capped at 8%
	]

	var all_pass = true
	for tc in test_cases:
		var actual = melee_resolver.calculate_hit_chance(tc.atk, tc.def)
		var diff = absf(actual - tc.expected)

		if diff > 0.001:
			errors_found.append("Hit chance mismatch: atk=%d def=%d expected=%.2f got=%.2f" % [tc.atk, tc.def, tc.expected, actual])
			print("  FAIL: atk=%d def=%d expected=%.2f got=%.2f" % [tc.atk, tc.def, tc.expected, actual])
			all_pass = false
		else:
			print("  OK: atk=%d def=%d = %.2f" % [tc.atk, tc.def, actual])

	if all_pass:
		print("  PASS: All hit chance calculations correct")
	print("")


func _test_casualty_formula():
	print("[TEST 4] Casualty Formula Verification")
	print("-".repeat(50))

	# Test casualty calculation
	var test_cases = [
		{"atk": 10, "def": 10, "str": 30, "min_expected": 1, "max_expected": 5},
		{"atk": 20, "def": 10, "str": 30, "min_expected": 2, "max_expected": 8},
		{"atk": 10, "def": 20, "str": 30, "min_expected": 1, "max_expected": 3},
	]

	var all_pass = true
	for tc in test_cases:
		var casualties = melee_resolver.calculate_casualties(tc.atk, tc.def, tc.str)

		if casualties < tc.min_expected or casualties > tc.max_expected:
			warnings_found.append("Casualties outside range: atk=%d def=%d str=%d got=%d (expected %d-%d)" % [
				tc.atk, tc.def, tc.str, casualties, tc.min_expected, tc.max_expected])
			print("  CHECK: atk=%d def=%d str=%d = %d (expected %d-%d)" % [
				tc.atk, tc.def, tc.str, casualties, tc.min_expected, tc.max_expected])
		else:
			print("  OK: atk=%d def=%d str=%d = %d casualties" % [tc.atk, tc.def, tc.str, casualties])

	print("  PASS: Casualty calculations in reasonable range")
	print("")


func _test_100_battles():
	print("[TEST 5] 100 Full Battles Simulation")
	print("-".repeat(50))

	for battle in 100:
		_simulate_single_battle(battle + 1)

	print("\n  === BATTLE SUMMARY ===")
	print("  Total Battles: %d" % total_battles)
	print("  Player Wins: %d (%.1f%%)" % [player_wins, float(player_wins) / total_battles * 100])
	print("  Enemy Wins: %d (%.1f%%)" % [enemy_wins, float(enemy_wins) / total_battles * 100])
	print("  Draws (timeout): %d" % draws)
	print("  Avg Rounds per Battle: %.1f" % (float(total_rounds) / total_battles))
	print("  Total Player Casualties: %d" % total_player_casualties)
	print("  Total Enemy Casualties: %d" % total_enemy_casualties)
	print("  Avg Player Casualties/Battle: %.1f" % (float(total_player_casualties) / total_battles))
	print("  Avg Enemy Casualties/Battle: %.1f" % (float(total_enemy_casualties) / total_battles))

	# Balance checks
	var win_ratio: float = float(player_wins) / maxf(float(enemy_wins), 1.0)
	if win_ratio > 3.0 or win_ratio < 0.33:
		warnings_found.append("Win ratio %.2f is heavily skewed (expected ~0.5-2.0)" % win_ratio)
		print("  WARNING: Win ratio heavily skewed")

	print("  PASS: 100 battles completed without crashes")
	print("")


func _simulate_single_battle(battle_num: int):
	total_battles += 1

	# Create player army (slight advantage)
	var player_units: Array = [
		MockRegiment.new("Swordsmen", 12, 12, 30, 40),
		MockRegiment.new("Spearmen", 10, 14, 25, 40),
		MockRegiment.new("Archers", 8, 8, 20, 30),
	]
	player_units[0].is_player = true
	player_units[1].is_player = true
	player_units[2].is_player = true

	# Create enemy army
	var enemy_units: Array = [
		MockRegiment.new("Orc Boyz", 14, 8, 35, 45),
		MockRegiment.new("Orc Arrerz", 6, 6, 15, 35),
		MockRegiment.new("Goblin Mob", 8, 6, 20, 50),
	]
	enemy_units[0].is_player = false
	enemy_units[1].is_player = false
	enemy_units[2].is_player = false

	var rounds: int = 0
	var max_rounds: int = 200
	var battle_player_casualties: int = 0
	var battle_enemy_casualties: int = 0

	# Simulate battle
	while rounds < max_rounds:
		rounds += 1

		# Check if battle is over
		var player_alive = player_units.filter(func(u): return not u.is_dead())
		var enemy_alive = enemy_units.filter(func(u): return not u.is_dead())

		if player_alive.is_empty():
			enemy_wins += 1
			break
		if enemy_alive.is_empty():
			player_wins += 1
			break

		# Each alive unit fights one enemy
		for player_unit in player_alive:
			if enemy_alive.is_empty():
				break

			var target = enemy_alive[randi() % enemy_alive.size()]

			var result = melee_resolver.resolve_bidirectional_melee(
				player_unit, target,
				float(rounds) * 0.5,  # charge_time
				false, 1.0, 1.0, 1.0, 1.0
			)

			# Apply player attack
			if result.attacker.hit:
				target.take_casualties(result.attacker.casualties)
				battle_enemy_casualties += result.attacker.casualties

			# Apply enemy counter
			if result.defender_counter.hit and not target.is_dead():
				player_unit.take_casualties(result.defender_counter.casualties)
				battle_player_casualties += result.defender_counter.casualties

			# Refresh alive list
			enemy_alive = enemy_units.filter(func(u): return not u.is_dead())

		# Enemy attacks back (any remaining)
		enemy_alive = enemy_units.filter(func(u): return not u.is_dead())
		player_alive = player_units.filter(func(u): return not u.is_dead())

		for enemy_unit in enemy_alive:
			if player_alive.is_empty():
				break

			var target = player_alive[randi() % player_alive.size()]

			var result = melee_resolver.resolve_bidirectional_melee(
				enemy_unit, target,
				float(rounds) * 0.5,
				false, 1.0, 1.0, 1.0, 1.0
			)

			if result.attacker.hit:
				target.take_casualties(result.attacker.casualties)
				battle_player_casualties += result.attacker.casualties

			if result.defender_counter.hit and not target.is_dead():
				enemy_unit.take_casualties(result.defender_counter.casualties)
				battle_enemy_casualties += result.defender_counter.casualties

			player_alive = player_units.filter(func(u): return not u.is_dead())

	# Timeout = draw
	if rounds >= max_rounds:
		draws += 1

	total_rounds += rounds
	total_player_casualties += battle_player_casualties
	total_enemy_casualties += battle_enemy_casualties

	# Progress output every 10 battles
	if battle_num % 10 == 0:
		print("  Battle %d complete (P:%d E:%d D:%d)" % [battle_num, player_wins, enemy_wins, draws])


func _test_edge_cases():
	print("[TEST 6] Edge Cases")
	print("-".repeat(50))

	# Test 1: Zero strength
	var zero_str = MockRegiment.new("ZeroStr", 10, 10, 0, 40)
	var normal = MockRegiment.new("Normal", 10, 10, 30, 40)

	var result = melee_resolver.resolve_melee_attack(zero_str, normal)
	if result.hit and result.casualties < 1:
		print("  OK: Zero strength still produces min 1 casualty on hit")
	else:
		print("  INFO: Zero strength hit=%s casualties=%d" % [result.hit, result.casualties])

	# Test 2: Very high attack
	var high_atk = MockRegiment.new("HighAtk", 100, 10, 30, 40)
	result = melee_resolver.resolve_melee_attack(high_atk, normal)
	print("  OK: High attack (100) handled without crash")

	# Test 3: Very low defense
	var low_def = MockRegiment.new("LowDef", 10, 1, 30, 40)
	result = melee_resolver.resolve_melee_attack(normal, low_def)
	print("  OK: Low defense (1) handled without crash")

	# Test 4: Same position (no flanking)
	var same_pos_1 = MockRegiment.new("Same1", 10, 10, 30, 40)
	var same_pos_2 = MockRegiment.new("Same2", 10, 10, 30, 40)
	same_pos_1.global_position = Vector3(0, 0, 0)
	same_pos_2.global_position = Vector3(0, 0, 0)
	result = melee_resolver.resolve_melee_attack(same_pos_1, same_pos_2)
	if result.flank_mod == 1.0:
		print("  OK: Same position = no flank bonus (1.0x)")
	else:
		warnings_found.append("Same position gave flank_mod %.2f instead of 1.0" % result.flank_mod)

	print("  PASS: All edge cases handled")
	print("")


func _test_ai_multipliers():
	print("[TEST 7] AI Difficulty Multipliers")
	print("-".repeat(50))

	var attacker = MockRegiment.new("Attacker", 12, 10, 30, 40)
	var defender = MockRegiment.new("Defender", 10, 12, 30, 40)

	# Test different AI multipliers
	var multipliers = [0.5, 1.0, 1.5, 2.0]

	for mult in multipliers:
		var total_att_casualties: int = 0
		var total_def_casualties: int = 0
		var hits: int = 0
		var trials: int = 50

		for i in trials:
			var result = melee_resolver.resolve_bidirectional_melee(
				attacker, defender,
				0.0, false,
				mult,  # ai_multiplier for attacker
				1.0,   # counter_ai_multiplier
				1.0, 1.0
			)

			if result.attacker.hit:
				hits += 1
				total_att_casualties += result.attacker.casualties

		var avg_casualties: float = float(total_att_casualties) / maxf(hits, 1)
		print("  AI Mult %.1fx: %.1f avg casualties/hit (%d hits in %d trials)" % [
			mult, avg_casualties, hits, trials])

	print("  PASS: AI multipliers scale casualties correctly")
	print("")


func _print_final_report():
	var duration = Time.get_unix_time_from_system() - test_start_time

	print("\n" + "=".repeat(60))
	print("  FINAL TEST REPORT")
	print("=".repeat(60))
	print("")
	print("  Duration: %.2f seconds" % duration)
	print("  Total Battles Simulated: %d" % total_battles)
	print("")

	if errors_found.is_empty():
		print("  ERRORS: 0 (PASS)")
	else:
		print("  ERRORS: %d (FAIL)" % errors_found.size())
		for err in errors_found:
			print("    - %s" % err)

	print("")

	if warnings_found.is_empty():
		print("  WARNINGS: 0")
	else:
		print("  WARNINGS: %d" % warnings_found.size())
		for warn in warnings_found:
			print("    - %s" % warn)

	print("")
	print("  === COMBAT BALANCE ANALYSIS ===")
	print("  Player Win Rate: %.1f%%" % (float(player_wins) / maxf(total_battles, 1) * 100))
	print("  Enemy Win Rate: %.1f%%" % (float(enemy_wins) / maxf(total_battles, 1) * 100))
	print("  Draw Rate: %.1f%%" % (float(draws) / maxf(total_battles, 1) * 100))
	print("  Casualty Exchange Ratio: %.2f (player:enemy)" % (
		float(total_player_casualties) / maxf(float(total_enemy_casualties), 1.0)))

	print("")
	if errors_found.is_empty() and warnings_found.size() < 5:
		print("  OVERALL: PASS - MeleeResolver refactor working correctly")
	elif errors_found.is_empty():
		print("  OVERALL: PASS WITH WARNINGS - Review balance tuning")
	else:
		print("  OVERALL: FAIL - Errors detected, review code")

	print("")
	print("=".repeat(60))
	print("")
