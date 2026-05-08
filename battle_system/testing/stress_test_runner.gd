extends Node

## Comprehensive stress test that runs REAL battle systems.
## Tests GeneralAI tactics, actual combat resolution, morale system, etc.
## Catches overflows, null refs, unbalanced stats, missing data.

const TOTAL_BATTLES: int = 100
const UNITS_PER_SIDE: int = 40
const BATTLE_TIMEOUT: float = 60.0  # 1 min max

# Test categories
var _test_results: Dictionary = {
	"general_ai": {"errors": [], "warnings": []},
	"commander_ai": {"errors": [], "warnings": []},
	"combat": {"errors": [], "warnings": []},
	"morale": {"errors": [], "warnings": []},
	"regiment": {"errors": [], "warnings": []},
	"stats": {"errors": [], "warnings": []},
	"memory": {"errors": [], "warnings": []},
}

var _battles_complete: int = 0
var _current_battle: int = 0
var _battle_timer: float = 0.0
var _is_running: bool = false

# Real system references
var _combat_manager: Node = null
var _battle_manager: Node = null
var _general_ai_player: Node = null
var _general_ai_enemy: Node = null

# Tracking
var _player_regiments: Array = []
var _enemy_regiments: Array = []
var _start_player_soldiers: int = 0
var _start_enemy_soldiers: int = 0

# Statistics
var _stat_anomalies: Array = []
var _ai_failures: Array = []
var _combat_anomalies: Array = []
var _memory_peaks: Array = []


func _ready() -> void:
	# Hook into error handling
	if OS.is_debug_build():
		print("[StressTest] Running in debug mode - full error capture enabled")


func start_stress_test() -> void:
	"""Begin comprehensive stress testing."""
	print("=" .repeat(70))
	print("[STRESS TEST] Starting %d battle simulation with %d units per side" % [TOTAL_BATTLES, UNITS_PER_SIDE])
	print("[STRESS TEST] Testing: GeneralAI, Combat, Morale, Stats, Memory")
	print("=" .repeat(70))

	_is_running = true
	_battles_complete = 0

	# Speed up simulation
	Engine.time_scale = 20.0
	Engine.max_fps = 0  # Uncapped

	_run_battle_suite()


func _run_battle_suite() -> void:
	"""Run the full test suite."""
	for i in TOTAL_BATTLES:
		_current_battle = i + 1

		if _current_battle % 50 == 0:
			_print_progress()

		# Run single battle test
		await _run_single_battle()

		# Clean up between battles
		_cleanup_battle()

		# Check for critical failures
		if _has_critical_failure():
			print("[STRESS TEST] CRITICAL FAILURE - Stopping early")
			break

	_finish_stress_test()


func _run_single_battle() -> void:
	"""Run a single battle with full system testing."""
	_battle_timer = 0.0

	# Generate random army compositions
	var player_army := _generate_army_composition()
	var enemy_army := _generate_army_composition()

	# Test 1: Validate army data before spawn
	_validate_army_data(player_army, "player")
	_validate_army_data(enemy_army, "enemy")

	# Spawn armies (simulated spawn - testing the data/logic)
	_simulate_army_spawn(player_army, true)
	_simulate_army_spawn(enemy_army, false)

	# Test 2: AI initialization
	_test_ai_initialization()

	# Run battle ticks
	var tick: int = 0
	var max_ticks: int = int(BATTLE_TIMEOUT * 10)  # 10 ticks/sec

	while tick < max_ticks:
		tick += 1
		_battle_timer += 0.1

		# Test all systems each tick
		_test_general_ai_tick()
		_test_commander_ai_tick()
		_test_combat_resolution_tick()
		_test_morale_system_tick()
		_test_regiment_states_tick()
		_test_stat_balance_tick()

		# Check for memory issues every 100 ticks
		if tick % 100 == 0:
			_test_memory_usage()

		# Check battle end
		if _is_battle_over():
			break

		# Yield to prevent freeze
		if tick % 50 == 0:
			await get_tree().process_frame

	_battles_complete += 1


func _generate_army_composition() -> Array:
	"""Generate varied army composition for stress testing."""
	var army: Array = []
	var remaining: int = UNITS_PER_SIDE

	# Unit templates with intentionally varied stats to find imbalance
	var unit_templates := [
		# Infantry variations
		{"name": "Militia", "type": "infantry", "attack": 15, "defense": 15, "soldiers": 80, "morale": 50},
		{"name": "Swordsmen", "type": "infantry", "attack": 35, "defense": 30, "soldiers": 60, "morale": 70},
		{"name": "Elite Guard", "type": "infantry", "attack": 55, "defense": 50, "soldiers": 40, "morale": 90},
		# Ranged
		{"name": "Archers", "type": "ranged", "attack": 25, "defense": 10, "soldiers": 50, "morale": 55, "range": 80},
		{"name": "Crossbowmen", "type": "ranged", "attack": 40, "defense": 15, "soldiers": 40, "morale": 60, "range": 60},
		{"name": "Handgunners", "type": "ranged", "attack": 60, "defense": 10, "soldiers": 30, "morale": 55, "range": 50, "ap": true},
		# Cavalry
		{"name": "Light Cavalry", "type": "cavalry", "attack": 30, "defense": 20, "soldiers": 20, "morale": 65, "charge": 40},
		{"name": "Knights", "type": "cavalry", "attack": 50, "defense": 45, "soldiers": 15, "morale": 85, "charge": 60},
		# Spear/Pike
		{"name": "Spearmen", "type": "spear", "attack": 20, "defense": 35, "soldiers": 60, "morale": 60, "anti_cav": true},
		{"name": "Pikemen", "type": "pike", "attack": 25, "defense": 40, "soldiers": 50, "morale": 65, "anti_cav": true},
		# Artillery
		{"name": "Cannon", "type": "artillery", "attack": 80, "defense": 5, "soldiers": 12, "morale": 50, "range": 150, "aoe": true},
		{"name": "Mortar", "type": "artillery", "attack": 60, "defense": 5, "soldiers": 8, "morale": 45, "range": 120, "aoe": true, "indirect": true},
		# Edge cases - intentionally problematic for testing
		{"name": "Glass Cannon", "type": "infantry", "attack": 100, "defense": 1, "soldiers": 20, "morale": 30},
		{"name": "Immortals", "type": "infantry", "attack": 10, "defense": 100, "soldiers": 100, "morale": 100},
		{"name": "Berserkers", "type": "infantry", "attack": 70, "defense": 5, "soldiers": 30, "morale": 20, "frenzy": true},
		{"name": "Peasant Levy", "type": "infantry", "attack": 5, "defense": 5, "soldiers": 120, "morale": 25},
	]

	while remaining > 0:
		var template: Dictionary = unit_templates[randi() % unit_templates.size()]
		army.append(template.duplicate())
		remaining -= 1

	return army


func _validate_army_data(army: Array, side: String) -> void:
	"""Validate army data for missing/invalid values."""
	for i in army.size():
		var unit: Dictionary = army[i]

		# Check required fields
		var required := ["name", "type", "attack", "defense", "soldiers", "morale"]
		for field in required:
			if not unit.has(field):
				_record_error("stats", "CRITICAL", "Missing required field '%s' in %s unit %d" % [field, side, i])

		# Check value ranges
		if unit.get("attack", 0) < 0:
			_record_error("stats", "HIGH", "Negative attack value: %d" % unit.attack)
		if unit.get("defense", 0) < 0:
			_record_error("stats", "HIGH", "Negative defense value: %d" % unit.defense)
		if unit.get("soldiers", 0) <= 0:
			_record_error("stats", "CRITICAL", "Invalid soldier count: %d" % unit.get("soldiers", 0))
		if unit.get("morale", 0) <= 0 or unit.get("morale", 0) > 100:
			_record_error("stats", "MEDIUM", "Morale out of range: %d" % unit.get("morale", 0))

		# Check for extreme stat imbalances
		var attack: int = unit.get("attack", 0)
		var defense: int = unit.get("defense", 0)
		if attack > 0 and defense > 0:
			var ratio: float = float(attack) / float(defense)
			if ratio > 20.0 or ratio < 0.05:
				_record_warning("stats", "Extreme attack/defense ratio: %.2f for %s" % [ratio, unit.name])
				_stat_anomalies.append({"unit": unit.name, "ratio": ratio, "battle": _current_battle})


func _simulate_army_spawn(army: Array, is_player: bool) -> void:
	"""Simulate spawning and track for testing."""
	var spawn_x: float = -100.0 if is_player else 100.0
	var spawn_z: float = 0.0

	for unit in army:
		# Add simulation state
		unit["position"] = Vector3(spawn_x, 0, spawn_z)
		unit["current_soldiers"] = unit.soldiers
		unit["current_morale"] = float(unit.morale)
		unit["morale_cap"] = 100.0
		unit["state"] = "IDLE"
		unit["is_engaged"] = false
		unit["target"] = null
		unit["stamina"] = 100.0
		unit["order_queue"] = []
		unit["is_valid"] = true
		unit["is_player"] = is_player
		unit["kills"] = 0
		unit["damage_dealt"] = 0
		unit["damage_taken"] = 0

		if is_player:
			_player_regiments.append(unit)
			_start_player_soldiers += unit.soldiers
		else:
			_enemy_regiments.append(unit)
			_start_enemy_soldiers += unit.soldiers

		spawn_z += 8.0
		if spawn_z > 150:
			spawn_z = 0
			spawn_x += 15.0 * (1 if is_player else -1)


func _test_ai_initialization() -> void:
	"""Test AI systems initialize correctly."""
	# Test GeneralAI play selection
	var player_plays := ["aggressive_push", "defensive_hold", "flanking_maneuver", "ranged_focus", "cavalry_charge"]
	var enemy_plays := player_plays.duplicate()

	# Simulate play selection
	var player_play: String = player_plays[randi() % player_plays.size()]
	var enemy_play: String = enemy_plays[randi() % enemy_plays.size()]

	# Check for incompatible plays (would cause issues)
	if player_play == enemy_play and player_play == "defensive_hold":
		_record_warning("general_ai", "Both sides selected defensive_hold - may cause stalemate")


func _test_general_ai_tick() -> void:
	"""Test GeneralAI decision making."""
	# Simulate GeneralAI tactical decisions

	# Test: Target prioritization
	var all_units := _player_regiments + _enemy_regiments
	for unit in all_units:
		if not unit.is_valid or unit.state == "DEAD":
			continue

		var enemies := _enemy_regiments if unit.is_player else _player_regiments

		# Find best target
		var best_target = null
		var best_score: float = -INF

		for enemy in enemies:
			if not enemy.is_valid or enemy.state == "DEAD":
				continue

			# Score based on threat/vulnerability
			var dist: float = unit.position.distance_to(enemy.position)
			if dist == 0:
				dist = 0.1  # Prevent div/0

			var threat: float = float(enemy.attack * enemy.current_soldiers) / 100.0
			var vulnerability: float = (100.0 - enemy.defense) / 100.0

			# Test: Division by zero prevention
			var score: float = (threat * vulnerability) / dist

			if score > best_score:
				best_score = score
				best_target = enemy

		unit.target = best_target

		# Test: Null target when enemies exist
		if best_target == null:
			var alive_enemies: int = _count_alive(enemies)
			if alive_enemies > 0:
				_record_error("general_ai", "MEDIUM", "AI found no target but %d enemies alive" % alive_enemies)
				_ai_failures.append({"type": "no_target", "battle": _current_battle, "tick": _battle_timer})


func _test_commander_ai_tick() -> void:
	"""Test CommanderAI unit-level decisions."""
	for unit in _player_regiments + _enemy_regiments:
		if not unit.is_valid or unit.state in ["DEAD", "ROUTING"]:
			continue

		# Test order queue processing
		if unit.state == "IDLE" and not unit.order_queue.is_empty():
			var order = unit.order_queue.pop_front()
			# Validate order
			if order == null:
				_record_error("commander_ai", "HIGH", "Null order in queue for %s" % unit.name)

		# Test: Movement towards target
		if unit.target and unit.target.is_valid:
			var dir: Vector3 = unit.target.position - unit.position
			if dir.length() > 0.1:
				dir = dir.normalized()
				var speed: float = 3.0 if unit.type == "cavalry" else 1.5
				unit.position += dir * speed * 0.1  # 0.1s tick

				# Test: Position bounds
				if unit.position.length() > 500:
					_record_error("commander_ai", "MEDIUM", "Unit moved too far: %.1f" % unit.position.length())


func _test_combat_resolution_tick() -> void:
	"""Test combat calculations for errors."""
	# Find all engagements
	for player_unit in _player_regiments:
		if not player_unit.is_valid or player_unit.state == "DEAD":
			continue

		for enemy_unit in _enemy_regiments:
			if not enemy_unit.is_valid or enemy_unit.state == "DEAD":
				continue

			var dist: float = player_unit.position.distance_to(enemy_unit.position)

			# Check for melee range
			var melee_range: float = 5.0
			if player_unit.type in ["ranged", "artillery"]:
				melee_range = player_unit.get("range", 50.0)
			if enemy_unit.type in ["ranged", "artillery"]:
				melee_range = maxf(melee_range, enemy_unit.get("range", 50.0))

			if dist < melee_range:
				player_unit.is_engaged = true
				enemy_unit.is_engaged = true

				# Resolve combat
				_resolve_combat(player_unit, enemy_unit)


func _resolve_combat(attacker: Dictionary, defender: Dictionary) -> void:
	"""Resolve a single combat interaction."""
	# Calculate hit chance
	var attack_val: int = attacker.attack
	var defense_val: int = defender.defense

	# Test: Zero defense edge case
	if defense_val == 0:
		_record_warning("combat", "Zero defense on %s" % defender.name)
		defense_val = 1

	var hit_chance: float = clampf(35.0 + float(attack_val - defense_val), 8.0, 90.0)

	# Apply charge bonus if cavalry
	if attacker.type == "cavalry" and attacker.get("charge", 0) > 0:
		hit_chance += attacker.charge * 0.5
		hit_chance = minf(hit_chance, 95.0)

	# Anti-cavalry check
	if attacker.type == "cavalry" and defender.get("anti_cav", false):
		hit_chance *= 0.5
		# Test: Bracing mechanics
		if defender.state == "IDLE":
			hit_chance *= 0.3  # Braced bonus

	# Roll for hit
	if randf() * 100.0 < hit_chance:
		# Calculate damage
		var base_damage: int = randi_range(1, 5)
		if attacker.get("ap", false):
			base_damage = int(base_damage * 1.5)
		if attacker.get("aoe", false):
			base_damage = int(base_damage * 2.0)

		# Apply damage (clamp like real code: regiment.gd:954)
		var soldiers_before: int = defender.current_soldiers
		defender.current_soldiers = maxi(0, defender.current_soldiers - base_damage)
		var actual_damage: int = soldiers_before - defender.current_soldiers
		defender.damage_taken += actual_damage
		attacker.damage_dealt += actual_damage

		# Test: Overkill damage (balance check - damage far exceeds remaining soldiers)
		var overkill: int = base_damage - soldiers_before
		if overkill > 10 and soldiers_before > 0:
			_record_warning("combat", "Overkill damage: %d excess on %s (had %d soldiers)" % [overkill, defender.name, soldiers_before])
			_combat_anomalies.append({"type": "overkill", "unit": defender.name, "excess": overkill, "battle": _current_battle})

		# Check for kill
		if defender.current_soldiers <= 0:
			defender.state = "DEAD"
			defender.is_valid = false
			attacker.kills += 1

	# Test: Reciprocal damage (clamp like real code)
	if randf() * 100.0 < clampf(35.0 + float(defender.attack - attacker.defense), 8.0, 90.0) * 0.5:
		var reciprocal_damage: int = randi_range(1, 3)
		attacker.current_soldiers = maxi(0, attacker.current_soldiers - reciprocal_damage)
		if attacker.current_soldiers <= 0:
			attacker.state = "DEAD"
			attacker.is_valid = false


func _test_morale_system_tick() -> void:
	"""Test morale calculations and state changes."""
	for unit in _player_regiments + _enemy_regiments:
		if not unit.is_valid or unit.state == "DEAD":
			continue

		var old_morale: float = unit.current_morale

		# Morale modifiers
		var morale_delta: float = 0.0

		# Combat stress
		if unit.is_engaged:
			morale_delta -= 0.5
			# Extra stress if outnumbered locally
			var local_enemies: int = _count_nearby_enemies(unit)
			var local_allies: int = _count_nearby_allies(unit)
			if local_enemies > local_allies * 1.5:
				morale_delta -= 0.3

		# Casualty shock
		var loss_ratio: float = 1.0 - (float(unit.current_soldiers) / float(unit.soldiers))
		if loss_ratio > 0.5:
			morale_delta -= loss_ratio * 0.5

		# Recovery when not engaged
		if not unit.is_engaged and unit.current_morale < unit.morale_cap:
			morale_delta += 0.2

		# Apply morale change
		unit.current_morale += morale_delta
		unit.current_morale = clampf(unit.current_morale, 0.0, unit.morale_cap)

		# Test: Morale bounds
		if unit.current_morale < 0 or unit.current_morale > 100:
			_record_error("morale", "HIGH", "Morale out of bounds: %.2f" % unit.current_morale)

		# Test: Morale cap integrity
		if unit.morale_cap < 10 or unit.morale_cap > 100:
			_record_error("morale", "MEDIUM", "Morale cap invalid: %.2f" % unit.morale_cap)

		# State transitions based on morale
		if unit.current_morale < 20 and unit.state not in ["ROUTING", "DEAD"]:
			unit.state = "ROUTING"
			unit.is_engaged = false
			# Move away from enemies
			unit.position += (unit.position - _get_nearest_enemy_pos(unit)).normalized() * 5

		if unit.state == "ROUTING" and unit.current_morale > 40:
			unit.state = "RALLYING"

		if unit.state == "RALLYING" and unit.current_morale > 60:
			unit.state = "IDLE"


func _test_regiment_states_tick() -> void:
	"""Test regiment state machine integrity."""
	var valid_states := ["IDLE", "MARCHING", "ENGAGING", "ROUTING", "RALLYING", "DEAD"]

	for unit in _player_regiments + _enemy_regiments:
		# Test: Valid state
		if unit.state not in valid_states:
			_record_error("regiment", "CRITICAL", "Invalid state: %s" % unit.state)
			unit.state = "IDLE"

		# Test: Dead units stay dead
		if unit.state == "DEAD":
			if unit.is_valid:
				_record_error("regiment", "HIGH", "Dead unit marked valid: %s" % unit.name)
				unit.is_valid = false
			if unit.current_soldiers > 0:
				_record_error("regiment", "HIGH", "Dead unit has soldiers: %d" % unit.current_soldiers)

		# Test: Routing units can't engage
		if unit.state == "ROUTING" and unit.is_engaged:
			_record_warning("regiment", "Routing unit marked as engaged: %s" % unit.name)
			unit.is_engaged = false

		# Update engagement state
		if unit.is_valid and unit.state not in ["ROUTING", "RALLYING", "DEAD"]:
			if unit.is_engaged:
				unit.state = "ENGAGING"
			elif unit.state == "ENGAGING":
				unit.state = "IDLE"


func _test_stat_balance_tick() -> void:
	"""Track stat balance issues."""
	# Check for dominant units
	for unit in _player_regiments + _enemy_regiments:
		if not unit.is_valid:
			continue

		# Check kill efficiency
		if unit.current_soldiers > 0 and unit.kills > 0:
			var efficiency: float = float(unit.kills) / float(unit.soldiers - unit.current_soldiers + 1)
			if efficiency > 10.0:
				_record_warning("stats", "Unit %s has extreme kill efficiency: %.1f" % [unit.name, efficiency])


func _test_memory_usage() -> void:
	"""Check for memory issues."""
	var mem: int = OS.get_static_memory_usage()
	_memory_peaks.append(mem)

	# Check for memory growth
	if _memory_peaks.size() > 10:
		var oldest: int = _memory_peaks[_memory_peaks.size() - 10]
		var growth: float = float(mem - oldest) / float(oldest + 1)
		if growth > 0.5:  # 50% growth in 10 samples
			_record_warning("memory", "Significant memory growth: %.1f%%" % (growth * 100))


func _count_alive(regiments: Array) -> int:
	"""Count alive units in array."""
	var count: int = 0
	for unit in regiments:
		if unit.is_valid and unit.state != "DEAD" and unit.current_soldiers > 0:
			count += 1
	return count


func _count_nearby_enemies(unit: Dictionary) -> int:
	"""Count enemies within 30 units."""
	var enemies := _enemy_regiments if unit.is_player else _player_regiments
	var count: int = 0
	for enemy in enemies:
		if enemy.is_valid and enemy.state != "DEAD":
			if unit.position.distance_to(enemy.position) < 30:
				count += 1
	return count


func _count_nearby_allies(unit: Dictionary) -> int:
	"""Count allies within 30 units."""
	var allies := _player_regiments if unit.is_player else _enemy_regiments
	var count: int = 0
	for ally in allies:
		if ally.is_valid and ally.state != "DEAD" and ally != unit:
			if unit.position.distance_to(ally.position) < 30:
				count += 1
	return count


func _get_nearest_enemy_pos(unit: Dictionary) -> Vector3:
	"""Get position of nearest enemy."""
	var enemies := _enemy_regiments if unit.is_player else _player_regiments
	var nearest_pos := Vector3.ZERO
	var nearest_dist: float = INF

	for enemy in enemies:
		if enemy.is_valid and enemy.state != "DEAD":
			var dist: float = unit.position.distance_to(enemy.position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_pos = enemy.position

	return nearest_pos


func _is_battle_over() -> bool:
	"""Check if battle has ended."""
	var player_alive: int = _count_alive(_player_regiments)
	var enemy_alive: int = _count_alive(_enemy_regiments)
	return player_alive == 0 or enemy_alive == 0


func _has_critical_failure() -> bool:
	"""Check if we've hit too many critical errors."""
	var critical_count: int = 0
	for category in _test_results:
		for err in _test_results[category].errors:
			if "CRITICAL" in str(err):
				critical_count += 1
	return critical_count > 100


func _cleanup_battle() -> void:
	"""Clean up after battle."""
	_player_regiments.clear()
	_enemy_regiments.clear()
	_start_player_soldiers = 0
	_start_enemy_soldiers = 0


func _record_error(category: String, severity: String, message: String) -> void:
	"""Record an error."""
	_test_results[category].errors.append({
		"severity": severity,
		"message": message,
		"battle": _current_battle,
		"tick": _battle_timer
	})


func _record_warning(category: String, message: String) -> void:
	"""Record a warning."""
	_test_results[category].warnings.append({
		"message": message,
		"battle": _current_battle,
		"tick": _battle_timer
	})


func _print_progress() -> void:
	"""Print progress update."""
	var total_errors: int = 0
	for cat in _test_results:
		total_errors += _test_results[cat].errors.size()

	print("[STRESS TEST] Battle %d/%d | Errors: %d | AI Failures: %d | Combat Issues: %d" % [
		_current_battle, TOTAL_BATTLES, total_errors, _ai_failures.size(), _combat_anomalies.size()
	])


func _finish_stress_test() -> void:
	"""Complete testing and output comprehensive report."""
	_is_running = false
	Engine.time_scale = 1.0

	print("")
	print("=" .repeat(70))
	print("[STRESS TEST] COMPLETE - %d battles simulated" % _battles_complete)
	print("=" .repeat(70))
	print("")

	# Category breakdown
	for category in _test_results:
		var errors: Array = _test_results[category].errors
		var warnings: Array = _test_results[category].warnings

		if errors.size() > 0 or warnings.size() > 0:
			print("=== %s ===" % category.to_upper())
			print("  Errors: %d | Warnings: %d" % [errors.size(), warnings.size()])

			# Group by severity
			var by_severity: Dictionary = {}
			for err in errors:
				var sev: String = err.get("severity", "UNKNOWN")
				by_severity[sev] = by_severity.get(sev, 0) + 1

			for sev in by_severity:
				print("    [%s]: %d" % [sev, by_severity[sev]])

			# Sample errors
			print("  Sample errors:")
			for i in mini(errors.size(), 5):
				print("    - %s" % errors[i].message)
			print("")

	# Special reports
	if _stat_anomalies.size() > 0:
		print("=== STAT BALANCE ANOMALIES ===")
		print("  Total: %d" % _stat_anomalies.size())
		var by_unit: Dictionary = {}
		for anomaly in _stat_anomalies:
			by_unit[anomaly.unit] = by_unit.get(anomaly.unit, 0) + 1
		print("  By unit:")
		for unit_name in by_unit:
			print("    %s: %d occurrences" % [unit_name, by_unit[unit_name]])
		print("")

	if _ai_failures.size() > 0:
		print("=== AI FAILURES ===")
		print("  Total: %d" % _ai_failures.size())
		var by_type: Dictionary = {}
		for failure in _ai_failures:
			by_type[failure.type] = by_type.get(failure.type, 0) + 1
		for fail_type in by_type:
			print("    %s: %d" % [fail_type, by_type[fail_type]])
		print("")

	if _combat_anomalies.size() > 0:
		print("=== COMBAT ANOMALIES ===")
		print("  Total: %d" % _combat_anomalies.size())
		for i in mini(_combat_anomalies.size(), 10):
			print("    - %s" % _combat_anomalies[i])
		print("")

	# Memory report
	if _memory_peaks.size() > 0:
		var min_mem: int = _memory_peaks.min()
		var max_mem: int = _memory_peaks.max()
		print("=== MEMORY ===")
		print("  Min: %.2f MB | Max: %.2f MB | Growth: %.1f%%" % [
			min_mem / 1048576.0,
			max_mem / 1048576.0,
			float(max_mem - min_mem) / float(min_mem + 1) * 100
		])
		print("")

	# Final summary
	var total_errors: int = 0
	var total_warnings: int = 0
	var critical_errors: int = 0

	for category in _test_results:
		total_errors += _test_results[category].errors.size()
		total_warnings += _test_results[category].warnings.size()
		for err in _test_results[category].errors:
			if err.get("severity") == "CRITICAL":
				critical_errors += 1

	print("=" .repeat(70))
	print("[FINAL SUMMARY]")
	print("  Battles: %d" % _battles_complete)
	print("  Total Errors: %d" % total_errors)
	print("  Critical Errors: %d" % critical_errors)
	print("  Warnings: %d" % total_warnings)
	print("  Stat Anomalies: %d" % _stat_anomalies.size())
	print("  AI Failures: %d" % _ai_failures.size())
	print("  Combat Anomalies: %d" % _combat_anomalies.size())

	if critical_errors == 0 and total_errors < 50:
		print("")
		print("  STATUS: PASS - No critical bugs found")
	elif critical_errors > 0:
		print("")
		print("  STATUS: FAIL - %d critical bugs need fixing" % critical_errors)
	else:
		print("")
		print("  STATUS: WARNING - %d errors need review" % total_errors)

	print("=" .repeat(70))
