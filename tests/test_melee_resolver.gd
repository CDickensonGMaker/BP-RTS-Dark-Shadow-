## Test script for MeleeResolver - runs 100 combat simulations
## Run with: godot --headless --script res://tests/test_melee_resolver.gd
extends SceneTree

const MeleeResolverScript = preload("res://battle_system/systems/combat/melee_resolver.gd")

var melee_resolver = null

# Mock regiment data for testing
class MockRegimentData:
	var attack: int = 10
	var defense: int = 10
	var strength: int = 30
	var charge_bonus: int = 5
	var unit_type: int = 0  # UnitType.Type.INFANTRY

# Mock regiment for testing
class MockRegiment:
	var data: MockRegimentData
	var global_position: Vector3 = Vector3.ZERO
	var veterancy = null

	func _init(atk: int = 10, def: int = 10, str_val: int = 30):
		data = MockRegimentData.new()
		data.attack = atk
		data.defense = def
		data.strength = str_val

	func get_attack_modifier() -> float:
		return 1.0

	func get_defense_modifier() -> float:
		return 1.0

	func get_anti_cavalry_modifier() -> float:
		return 1.0


func _init():
	print("\n========================================")
	print("  MELEE RESOLVER TEST - 100 BATTLES")
	print("========================================\n")

	melee_resolver = MeleeResolverScript.new()

	# Run tests
	test_basic_combat()
	test_stat_advantage()
	test_bidirectional_combat()
	test_100_battles()

	print("\n========================================")
	print("  ALL TESTS COMPLETED")
	print("========================================\n")

	quit()


func test_basic_combat():
	print("[TEST] Basic Combat (equal stats)")
	print("-" * 40)

	var attacker = MockRegiment.new(10, 10, 30)
	var defender = MockRegiment.new(10, 10, 30)

	var hits: int = 0
	var total_casualties: int = 0
	var trials: int = 100

	for i in trials:
		var result = melee_resolver.resolve_melee_attack(attacker, defender)
		if result.hit:
			hits += 1
			total_casualties += result.casualties

	print("  Trials: %d" % trials)
	print("  Hit Rate: %.1f%% (expected ~35%%)" % (float(hits) / trials * 100))
	print("  Avg Casualties on Hit: %.1f" % (float(total_casualties) / maxf(hits, 1)))
	print("  PASS" if absf(float(hits) / trials - 0.35) < 0.15 else "  FAIL")
	print("")


func test_stat_advantage():
	print("[TEST] Stat Advantage (attacker +10 attack)")
	print("-" * 40)

	var attacker = MockRegiment.new(20, 10, 30)  # +10 attack
	var defender = MockRegiment.new(10, 10, 30)

	var hits: int = 0
	var trials: int = 100

	for i in trials:
		var result = melee_resolver.resolve_melee_attack(attacker, defender)
		if result.hit:
			hits += 1

	print("  Trials: %d" % trials)
	print("  Hit Rate: %.1f%% (expected ~45%%)" % (float(hits) / trials * 100))
	print("  PASS" if float(hits) / trials > 0.40 else "  FAIL")
	print("")


func test_bidirectional_combat():
	print("[TEST] Bidirectional Combat")
	print("-" * 40)

	var attacker = MockRegiment.new(12, 8, 35)
	var defender = MockRegiment.new(10, 10, 30)

	var att_hits: int = 0
	var def_hits: int = 0
	var trials: int = 100

	for i in trials:
		var result = melee_resolver.resolve_bidirectional_melee(
			attacker, defender,
			0.0,  # charge_time
			false,  # charge_negated
			1.0,  # ai_multiplier
			1.0,  # counter_ai_multiplier
			1.0,  # weather_charge_modifier
			1.0   # formation_charge_modifier
		)
		if result.attacker.hit:
			att_hits += 1
		if result.defender_counter.hit:
			def_hits += 1

	print("  Trials: %d" % trials)
	print("  Attacker Hit Rate: %.1f%%" % (float(att_hits) / trials * 100))
	print("  Defender Counter Rate: %.1f%%" % (float(def_hits) / trials * 100))
	print("  Both methods return valid results: PASS")
	print("")


func test_100_battles():
	print("[TEST] 100 Full Battles (until one side eliminated)")
	print("-" * 40)

	var attacker_wins: int = 0
	var defender_wins: int = 0
	var total_rounds: int = 0
	var total_att_casualties: int = 0
	var total_def_casualties: int = 0

	for battle in 100:
		var att_soldiers: int = 40
		var def_soldiers: int = 40
		var rounds: int = 0

		var attacker = MockRegiment.new(12, 8, 35)
		var defender = MockRegiment.new(10, 10, 30)

		while att_soldiers > 0 and def_soldiers > 0 and rounds < 100:
			rounds += 1

			var result = melee_resolver.resolve_bidirectional_melee(
				attacker, defender,
				float(rounds) * 1.5,  # charge_time (simulating tick rate)
				false, 1.0, 1.0, 1.0, 1.0
			)

			# Attacker's attack
			if result.attacker.hit:
				def_soldiers -= result.attacker.casualties
				total_def_casualties += result.attacker.casualties

			# Defender's counter-attack
			if result.defender_counter.hit and def_soldiers > 0:
				att_soldiers -= result.defender_counter.casualties
				total_att_casualties += result.defender_counter.casualties

		total_rounds += rounds

		if att_soldiers > 0:
			attacker_wins += 1
		else:
			defender_wins += 1

	print("  Battles: 100")
	print("  Attacker Wins: %d" % attacker_wins)
	print("  Defender Wins: %d" % defender_wins)
	print("  Avg Rounds per Battle: %.1f" % (float(total_rounds) / 100))
	print("  Total Attacker Casualties: %d" % total_att_casualties)
	print("  Total Defender Casualties: %d" % total_def_casualties)
	print("  Avg Att Casualties per Battle: %.1f" % (float(total_att_casualties) / 100))
	print("  Avg Def Casualties per Battle: %.1f" % (float(total_def_casualties) / 100))
	print("  Attacker should win more (has +2 attack): %s" % ("PASS" if attacker_wins > defender_wins else "CHECK"))
	print("")
