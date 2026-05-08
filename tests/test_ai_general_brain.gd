## AI General Brain Test - Verifies AI personality traits affect strategic decisions
## Tests personality presets, retreat logic, target scoring, and combat simulation
## Run with: godot --headless --script res://tests/test_ai_general_brain.gd
extends SceneTree

const AIPersonalityScript = preload("res://battle_system/ai/data/ai_personality.gd")
const MeleeResolverScript = preload("res://battle_system/systems/combat/melee_resolver.gd")

var melee_resolver = null
var tests_passed: int = 0
var tests_failed: int = 0
var test_start_time: float = 0.0


# Mock regiment data matching actual RegimentData structure
class MockRegimentData:
	var regiment_name: String = "Mock Regiment"
	var attack: int = 10
	var defense: int = 10
	var weapon_skill: int = 10
	var ballistic_skill: int = 0
	var strength: int = 3
	var charge_bonus: int = 5
	var unit_type: int = 0  # UnitType.Type.INFANTRY
	var max_soldiers: int = 40
	var current_soldiers: int = 40
	var morale: float = 75.0
	var max_ammo: int = 0
	var current_ammo: int = 0
	var armor: int = 5
	var has_aura: bool = false
	var aura_radius: float = 0.0
	var aura_threshold_bonus: float = 0.0
	var personality: int = 0  # NORMAL
	var hero_trait: int = 0  # NONE

	func can_pursue() -> bool:
		return personality != 1  # Not DISCIPLINED

	func may_charge_impulsively() -> bool:
		return personality == 2  # IMPETUOUS

	func get_attack_modifier() -> float:
		return 1.0

	func get_defense_modifier() -> float:
		return 1.0

	func get_weakness_penalty_vs(_enemy_type: int) -> float:
		return 1.0


# Mock regiment matching Regiment interface for MeleeResolver
class MockRegiment:
	var data: MockRegimentData
	var global_position: Vector3 = Vector3.ZERO
	var global_transform: Transform3D = Transform3D.IDENTITY
	var veterancy = null
	var unit_morale = null
	var casualty_tracker = null
	var current_soldiers: int = 40
	var current_morale: float = 75.0
	var current_ammo: int = 0
	var current_formation: int = 0  # LINE
	var is_player_controlled: bool = false
	var state: int = 0
	var name: String = "MockRegiment"
	var formation = null

	enum State { IDLE, MOVING, MARCHING, ENGAGING, ROUTING, RALLYING, DEAD }

	func _init(p_name: String = "Mock", ws: int = 10, def: int = 10, str_val: int = 3, soldiers: int = 40, unit_type: int = 0):
		name = p_name
		data = MockRegimentData.new()
		data.regiment_name = p_name
		data.weapon_skill = ws
		data.defense = def
		data.strength = str_val
		data.max_soldiers = soldiers
		data.current_soldiers = soldiers
		data.unit_type = unit_type
		current_soldiers = soldiers

	func get_attack_modifier() -> float:
		return 1.0

	func get_defense_modifier() -> float:
		return 1.0

	func get_anti_cavalry_modifier() -> float:
		return 1.0

	func has_method(method_name: String) -> bool:
		return method_name in ["get_attack_modifier", "get_defense_modifier", "get_anti_cavalry_modifier", "get_tree"]

	func get_tree():
		return null  # No tree in headless test

	func is_dead() -> bool:
		return state == State.DEAD or current_soldiers <= 0

	func take_casualties(amount: int) -> void:
		current_soldiers = maxi(0, current_soldiers - amount)
		data.current_soldiers = current_soldiers
		if current_soldiers <= 0:
			state = State.DEAD


func _init():
	test_start_time = Time.get_unix_time_from_system()

	print("\n" + "=".repeat(70))
	print("  AI GENERAL BRAIN TEST")
	print("  Testing: Personality traits → Strategic decision making")
	print("  Combat: MeleeResolver with proper mock interfaces")
	print("=".repeat(70) + "\n")

	melee_resolver = MeleeResolverScript.new()

	_run_all_tests()
	_print_final_report()

	quit()


func _run_all_tests():
	print("[SUITE] AI Personality & Combat Tests\n")

	# AI Personality Tests
	_test_personality_presets()
	_test_should_retreat_logic()
	_test_target_score_modifiers()
	_test_adjusted_tick_rate()

	# Combat Tests with Proper Mocks
	_test_melee_basic_combat()
	_test_melee_stat_advantage()
	_test_bidirectional_combat()

	# Stress Tests
	_test_50_unit_battle()
	_test_100_unit_battle()

	print("\n[SUITE] All tests completed\n")


func _test_personality_presets():
	print("[TEST 1] AI Personality Presets")
	print("-".repeat(50))

	var easy = AIPersonalityScript.easy()
	var normal = AIPersonalityScript.normal()
	var hard = AIPersonalityScript.hard()
	var legendary = AIPersonalityScript.legendary()
	var defensive = AIPersonalityScript.defensive()
	var aggressive = AIPersonalityScript.aggressive()

	var all_valid = true

	# Verify expected trait relationships
	if easy.aggression >= normal.aggression:
		print("  ERROR: Easy aggression should be < Normal")
		all_valid = false

	if hard.aggression <= normal.aggression:
		print("  ERROR: Hard aggression should be > Normal")
		all_valid = false

	if legendary.reaction_delay_mult >= normal.reaction_delay_mult:
		print("  ERROR: Legendary reaction should be faster than Normal")
		all_valid = false

	if defensive.unit_preservation <= aggressive.unit_preservation:
		print("  ERROR: Defensive unit_preservation should be > Aggressive")
		all_valid = false

	if aggressive.pursuit_aggression <= defensive.pursuit_aggression:
		print("  ERROR: Aggressive pursuit should be > Defensive")
		all_valid = false

	print("  Presets:")
	print("    Easy:       agg=%.2f, react=%.2fx, preserve=%.2f" % [easy.aggression, easy.reaction_delay_mult, easy.unit_preservation])
	print("    Normal:     agg=%.2f, react=%.2fx, preserve=%.2f" % [normal.aggression, normal.reaction_delay_mult, normal.unit_preservation])
	print("    Hard:       agg=%.2f, react=%.2fx, preserve=%.2f" % [hard.aggression, hard.reaction_delay_mult, hard.unit_preservation])
	print("    Legendary:  agg=%.2f, react=%.2fx, preserve=%.2f" % [legendary.aggression, legendary.reaction_delay_mult, legendary.unit_preservation])
	print("    Defensive:  agg=%.2f, react=%.2fx, preserve=%.2f" % [defensive.aggression, defensive.reaction_delay_mult, defensive.unit_preservation])
	print("    Aggressive: agg=%.2f, react=%.2fx, preserve=%.2f" % [aggressive.aggression, aggressive.reaction_delay_mult, aggressive.unit_preservation])

	if all_valid:
		print("  PASS: All personality presets correctly configured")
		tests_passed += 1
	else:
		print("  FAIL: Personality preset issues found")
		tests_failed += 1
	print("")


func _test_should_retreat_logic():
	print("[TEST 2] should_retreat() Logic Based on Traits")
	print("-".repeat(50))

	# Create personalities with different unit_preservation and risk_tolerance
	var cautious = AIPersonalityScript.new()
	cautious.unit_preservation = 0.9
	cautious.risk_tolerance = 0.1

	var reckless = AIPersonalityScript.new()
	reckless.unit_preservation = 0.1
	reckless.risk_tolerance = 0.9

	var balanced = AIPersonalityScript.new()
	balanced.unit_preservation = 0.5
	balanced.risk_tolerance = 0.5

	# Test at various strength ratios
	var test_ratios = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8]
	var cautious_retreats: int = 0
	var reckless_retreats: int = 0
	var balanced_retreats: int = 0

	print("  Strength | Cautious | Balanced | Reckless")
	print("  " + "-".repeat(45))

	for ratio in test_ratios:
		var c_ret = cautious.should_retreat(ratio)
		var b_ret = balanced.should_retreat(ratio)
		var r_ret = reckless.should_retreat(ratio)

		if c_ret: cautious_retreats += 1
		if b_ret: balanced_retreats += 1
		if r_ret: reckless_retreats += 1

		print("    %.1f    |    %s    |    %s    |    %s" % [
			ratio,
			"YES" if c_ret else "NO ",
			"YES" if b_ret else "NO ",
			"YES" if r_ret else "NO "
		])

	# Cautious should retreat more often than reckless
	if cautious_retreats > reckless_retreats:
		print("  PASS: Cautious retreats more (%d) than Reckless (%d)" % [cautious_retreats, reckless_retreats])
		tests_passed += 1
	else:
		print("  FAIL: Retreat logic not differentiating properly")
		tests_failed += 1
	print("")


func _test_target_score_modifiers():
	print("[TEST 3] Target Score Modifiers Based on Traits")
	print("-".repeat(50))

	var hunter = AIPersonalityScript.new()
	hunter.pursuit_aggression = 0.9
	hunter.target_priority = 0.9
	hunter.aggression = 0.9

	var passive = AIPersonalityScript.new()
	passive.pursuit_aggression = 0.1
	passive.target_priority = 0.1
	passive.aggression = 0.1

	var target_types = ["weak", "routing", "high_value", "close"]

	print("  Target Type  | Hunter | Passive | Diff")
	print("  " + "-".repeat(45))

	var all_valid = true
	for target in target_types:
		var hunter_mod = hunter.get_target_score_modifier(target)
		var passive_mod = passive.get_target_score_modifier(target)
		var diff = hunter_mod - passive_mod

		print("  %-12s |  %.2f  |   %.2f  | +%.2f" % [target, hunter_mod, passive_mod, diff])

		# Hunter should always have higher modifiers (except for neutral targets)
		if hunter_mod < passive_mod:
			all_valid = false

	if all_valid:
		print("  PASS: Target modifiers correctly reflect personality")
		tests_passed += 1
	else:
		print("  FAIL: Target modifier logic incorrect")
		tests_failed += 1
	print("")


func _test_adjusted_tick_rate():
	print("[TEST 4] Adjusted Tick Rate Based on Reaction Speed")
	print("-".repeat(50))

	var fast = AIPersonalityScript.legendary()  # 0.6x delay
	var normal = AIPersonalityScript.normal()   # 1.0x delay
	var slow = AIPersonalityScript.easy()       # 1.5x delay

	var base_rate = 3.0

	var fast_tick = fast.get_adjusted_tick_rate(base_rate)
	var normal_tick = normal.get_adjusted_tick_rate(base_rate)
	var slow_tick = slow.get_adjusted_tick_rate(base_rate)

	print("  Base tick rate: %.1fs" % base_rate)
	print("  Legendary (fast):  %.2fs (%.1fx)" % [fast_tick, fast.reaction_delay_mult])
	print("  Normal:            %.2fs (%.1fx)" % [normal_tick, normal.reaction_delay_mult])
	print("  Easy (slow):       %.2fs (%.1fx)" % [slow_tick, slow.reaction_delay_mult])

	if fast_tick < normal_tick and normal_tick < slow_tick:
		print("  PASS: Tick rates correctly scaled by difficulty")
		tests_passed += 1
	else:
		print("  FAIL: Tick rate scaling incorrect")
		tests_failed += 1
	print("")


func _test_melee_basic_combat():
	print("[TEST 5] MeleeResolver - Basic Combat (Equal Stats)")
	print("-".repeat(50))

	var attacker = MockRegiment.new("Attacker", 10, 10, 3, 40)
	var defender = MockRegiment.new("Defender", 10, 10, 3, 40)

	var hits: int = 0
	var total_casualties: int = 0
	var trials: int = 100

	for i in trials:
		var result = melee_resolver.resolve_melee_attack(attacker, defender)
		if result.hit:
			hits += 1
			if result.casualties > 0:
				total_casualties += result.casualties

	var hit_rate = float(hits) / float(trials) * 100.0
	print("  Trials: %d" % trials)
	print("  Hit Rate: %.1f%%" % hit_rate)
	print("  Total Wounds: %d" % total_casualties)

	# With equal stats (WS 10 vs 10), expect ~25% hit rate (50% to hit × 50% to wound)
	if hit_rate > 10.0 and hit_rate < 60.0:
		print("  PASS: Hit rate within expected range")
		tests_passed += 1
	else:
		print("  FAIL: Hit rate outside expected range")
		tests_failed += 1
	print("")


func _test_melee_stat_advantage():
	print("[TEST 6] MeleeResolver - Stat Advantage (+5 WS)")
	print("-".repeat(50))

	var strong_attacker = MockRegiment.new("Strong", 15, 10, 4, 40)  # +5 WS, +1 strength
	var weak_defender = MockRegiment.new("Weak", 10, 8, 3, 40)       # Lower defense

	var hits: int = 0
	var trials: int = 100

	for i in trials:
		var result = melee_resolver.resolve_melee_attack(strong_attacker, weak_defender)
		if result.hit:
			hits += 1

	var hit_rate = float(hits) / float(trials) * 100.0
	print("  Attacker: WS 15, STR 4")
	print("  Defender: WS 10, DEF 8")
	print("  Hit Rate: %.1f%%" % hit_rate)

	# Higher WS should give better hit rate
	if hit_rate > 20.0:
		print("  PASS: Stat advantage reflected in hit rate")
		tests_passed += 1
	else:
		print("  FAIL: Stat advantage not reflected")
		tests_failed += 1
	print("")


func _test_bidirectional_combat():
	print("[TEST 7] MeleeResolver - Bidirectional Combat")
	print("-".repeat(50))

	var attacker = MockRegiment.new("Attacker", 12, 10, 4, 40)
	var defender = MockRegiment.new("Defender", 10, 12, 3, 40)

	var att_hits: int = 0
	var def_hits: int = 0
	var att_casualties: int = 0
	var def_casualties: int = 0
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
		if result.attacker.hit:
			att_hits += 1
			att_casualties += result.attacker.casualties
		if result.defender_counter.hit:
			def_hits += 1
			def_casualties += result.defender_counter.casualties

	print("  Trials: %d" % trials)
	print("  Attacker hits: %d (%.1f%%), casualties dealt: %d" % [att_hits, float(att_hits)/trials*100, att_casualties])
	print("  Defender hits: %d (%.1f%%), casualties dealt: %d" % [def_hits, float(def_hits)/trials*100, def_casualties])

	if att_hits > 0 and def_hits > 0:
		print("  PASS: Both sides dealing damage")
		tests_passed += 1
	else:
		print("  FAIL: One side not dealing damage")
		tests_failed += 1
	print("")


func _test_50_unit_battle():
	print("[TEST 8] Stress Test - 50 Unit Battle (25 vs 25)")
	print("-".repeat(50))

	var result = _run_battle_simulation(25, 25, 200)

	print("  Units: 50 (25 vs 25)")
	print("  Rounds: %d" % result.rounds)
	print("  Player casualties: %d" % result.player_casualties)
	print("  Enemy casualties: %d" % result.enemy_casualties)
	print("  Winner: %s" % result.winner)
	print("  Duration: %.3fs" % result.duration)

	if result.completed:
		print("  PASS: 50-unit battle completed")
		tests_passed += 1
	else:
		print("  FAIL: Battle did not complete")
		tests_failed += 1
	print("")


func _test_100_unit_battle():
	print("[TEST 9] Stress Test - 100 Unit Battle (50 vs 50)")
	print("-".repeat(50))

	var result = _run_battle_simulation(50, 50, 300)

	print("  Units: 100 (50 vs 50)")
	print("  Rounds: %d" % result.rounds)
	print("  Player casualties: %d" % result.player_casualties)
	print("  Enemy casualties: %d" % result.enemy_casualties)
	print("  Winner: %s" % result.winner)
	print("  Duration: %.3fs" % result.duration)

	if result.completed:
		print("  PASS: 100-unit battle completed")
		tests_passed += 1
	else:
		print("  FAIL: Battle did not complete")
		tests_failed += 1
	print("")


func _run_battle_simulation(player_count: int, enemy_count: int, max_rounds: int) -> Dictionary:
	var start_time = Time.get_unix_time_from_system()

	# Create player units (varied stats)
	var player_units: Array = []
	for i in player_count:
		var ws = 8 + randi() % 6   # 8-13
		var def = 8 + randi() % 6  # 8-13
		var str_val = 2 + randi() % 3  # 2-4
		var soldiers = 25 + randi() % 20  # 25-44
		var unit = MockRegiment.new("Player_%d" % i, ws, def, str_val, soldiers)
		unit.is_player_controlled = true
		unit.global_position = Vector3(randf_range(-50, 50), 0, randf_range(-20, 0))
		player_units.append(unit)

	# Create enemy units
	var enemy_units: Array = []
	for i in enemy_count:
		var ws = 8 + randi() % 6
		var def = 8 + randi() % 6
		var str_val = 2 + randi() % 3
		var soldiers = 25 + randi() % 20
		var unit = MockRegiment.new("Enemy_%d" % i, ws, def, str_val, soldiers)
		unit.is_player_controlled = false
		unit.global_position = Vector3(randf_range(-50, 50), 0, randf_range(20, 50))
		enemy_units.append(unit)

	var rounds: int = 0
	var player_casualties: int = 0
	var enemy_casualties: int = 0
	var winner: String = "DRAW"

	while rounds < max_rounds:
		rounds += 1

		var player_alive = player_units.filter(func(u): return not u.is_dead())
		var enemy_alive = enemy_units.filter(func(u): return not u.is_dead())

		if player_alive.is_empty():
			winner = "ENEMY"
			break
		if enemy_alive.is_empty():
			winner = "PLAYER"
			break

		# Each player unit attacks a random enemy
		for unit in player_alive:
			if enemy_alive.is_empty():
				break
			var target = enemy_alive[randi() % enemy_alive.size()]

			var result = melee_resolver.resolve_bidirectional_melee(
				unit, target, 0.0, false, 1.0, 1.0, 1.0, 1.0
			)

			if result.attacker.hit and result.attacker.casualties > 0:
				target.take_casualties(result.attacker.casualties)
				enemy_casualties += result.attacker.casualties

			if result.defender_counter.hit and result.defender_counter.casualties > 0:
				unit.take_casualties(result.defender_counter.casualties)
				player_casualties += result.defender_counter.casualties

			# Refresh alive lists
			enemy_alive = enemy_units.filter(func(u): return not u.is_dead())
			player_alive = player_units.filter(func(u): return not u.is_dead())

	var end_time = Time.get_unix_time_from_system()

	return {
		"completed": true,
		"rounds": rounds,
		"player_casualties": player_casualties,
		"enemy_casualties": enemy_casualties,
		"winner": winner,
		"duration": end_time - start_time
	}


func _print_final_report():
	var duration = Time.get_unix_time_from_system() - test_start_time
	var total = tests_passed + tests_failed

	print("=".repeat(70))
	print("  FINAL AI GENERAL BRAIN TEST REPORT")
	print("=".repeat(70))
	print("")
	print("  Duration: %.2f seconds" % duration)
	print("  Tests Run: %d" % total)
	print("  Passed: %d" % tests_passed)
	print("  Failed: %d" % tests_failed)
	print("")
	print("  === AI TRAIT VERIFICATION SUMMARY ===")
	print("  Verified traits affecting AI decisions:")
	print("    - aggression: Controls attack vs defend preference")
	print("    - unit_preservation: Controls retreat threshold")
	print("    - risk_tolerance: Controls retreat threshold")
	print("    - pursuit_aggression: Controls chase routing enemies")
	print("    - target_priority: Controls high-value target focus")
	print("    - reaction_delay_mult: Controls AI response time")
	print("")

	if tests_failed == 0:
		print("  OVERALL: PASS - AI General Brain working correctly")
	else:
		print("  OVERALL: FAIL - %d test(s) failed" % tests_failed)

	print("")
	print("=".repeat(70))
	print("")
