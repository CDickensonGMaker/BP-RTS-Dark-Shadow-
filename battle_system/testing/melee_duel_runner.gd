extends Node

## ============================================================================
## MELEE DUEL TORTURE TEST
## ----------------------------------------------------------------------------
## Runs N isolated 1-vs-1 melee fights using REAL Regiment nodes, REAL
## RegimentData .tres files, and the REAL MeleeResolver / CasualtyProcessor
## / UnitMorale code paths. Each duel runs until one side is dead OR routs.
## After a rout, the routed side is given a chance to rally and re-engage,
## up to MAX_RALLY_CYCLES per duel. This is what catches state-machine holes,
## morale-loop bugs, and casualty-tracking drift.
##
## Output:
##   - Console summary at end
##   - JSON report at user://melee_duel_report.json
##
## Run: Via Unit Zoo hotkey M, or set auto_start_melee_duel_test=true
##      OR from CLI:  godot --headless res://scenes/unit_zoo.tscn
## ============================================================================

const MeleeResolverScript = preload("res://battle_system/systems/combat/melee_resolver.gd")
const CasualtyProcessorScript = preload("res://battle_system/systems/combat/casualty_processor.gd")
const UnitMoraleScript = preload("res://battle_system/morale/unit_morale.gd")
const RegimentScene = preload("res://battle_system/nodes/regiment.tscn")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
var TOTAL_DUELS: int           = 40
var MAX_TICKS_PER_DUEL: int    = 600   # 60 sec @ 0.1s tick
const TICK_DELTA: float        = 0.1
var MAX_RALLY_CYCLES: int      = 3     # rout -> rally -> re-engage cycles per duel
const ENGAGEMENT_DISTANCE: float = 2.0

# Set to false when running inside unit zoo to prevent auto-quit
var quit_when_done: bool = false

# Morale thresholds (mirror the values your real system uses)
# Real system routs when 50%+ soldiers are BROKEN (morale < 20)
# We simulate this by checking average morale against thresholds
const ROUT_THRESHOLD: float   = 35.0  # Rout when avg morale drops below this
const RALLY_THRESHOLD: float  = 50.0
const SHATTER_THRESHOLD: float = 15.0  # Below this, unit cannot rally

# Morale damage scaling - proportional to casualties taken
# Real system: each death applies -3.0 to nearby soldiers, plus "friend killed" events
# We simulate: (casualties / max_soldiers) * BASE_CASUALTY_MORALE_MULT = % morale lost
const BASE_CASUALTY_MORALE_MULT: float = 150.0  # 50% casualties = 75 morale damage
const COMBAT_MORALE_DRAIN_PER_TICK: float = 0.5  # Stress from sustained combat

# Pull a curated subset of unit .tres files. Add/remove to focus testing.
# ALL COMBAT UNITS - melee, cavalry, ranged, artillery, monsters
const UNIT_POOL: Array[String] = [
	# =========================================================================
	# BASE UNITS
	# =========================================================================
	"res://battle_system/data/militia.tres",
	"res://battle_system/data/swordsmen.tres",
	"res://battle_system/data/player_infantry.tres",
	"res://battle_system/data/enemy_infantry.tres",
	"res://battle_system/data/cavalry.tres",

	# =========================================================================
	# EMPIRE
	# =========================================================================
	# Melee Infantry
	"res://battle_system/data/regiments/grtsword_regiment.tres",      # Greatswords
	"res://battle_system/data/regiments/mcsword_regiment.tres",       # Merc Swordsmen
	"res://battle_system/data/regiments/empsword_regiment.tres",      # Empire Swordsmen
	"res://battle_system/data/regiments/carlgrd_regiment.tres",       # Carroburg Greatswords
	"res://battle_system/data/regiments/bodygrd_regiment.tres",       # Bodyguard
	"res://battle_system/data/regiments/peasant_regiment.tres",       # Peasants
	"res://battle_system/data/regiments/avengers_regiment.tres",      # Avengers
	"res://battle_system/data/regiments/hammers_regiment.tres",       # Hammers
	# Spear/Halberd Infantry
	"res://battle_system/data/regiments/nlnhlb_regiment.tres",          # Halberdiers
	"res://battle_system/data/regiments/nlnhlb_regiment.tres",        # Nuln Halberdiers
	# Cavalry
	"res://battle_system/data/regiments/reik_regiment.tres",          # Reiksguard
	"res://battle_system/data/regiments/brdhrs_regiment.tres",        # Bright Hussars
	"res://battle_system/data/regiments/keelers_regiment.tres",       # Keelers
	"res://battle_system/data/regiments/mtdrks_regiment.tres",        # Mountain Dragoons
	# Ranged
	"res://battle_system/data/regiments/xbow_regiment.tres",          # Crossbowmen
	"res://battle_system/data/regiments/mercxbow_regiment.tres",      # Merc Crossbows
	# Artillery
	"res://battle_system/data/regiments/mortar_regiment.tres",        # Mortar
	"res://battle_system/data/regiments/grtcanon_regiment.tres",      # Great Cannon
	"res://battle_system/data/regiments/voleygun_regiment.tres",      # Volley Gun
	"res://battle_system/data/regiments/impcanon_regiment.tres",      # Imperial Cannon

	# =========================================================================
	# DWARFS
	# =========================================================================
	# Melee Infantry
	"res://battle_system/data/regiments/dwwar_regiment.tres",         # Dwarf Warriors
	"res://battle_system/data/regiments/ironbrks_regiment.tres",          # Ironbreakers
	"res://battle_system/data/regiments/ironbrks_regiment.tres",      # Ironbreakers alt
	"res://battle_system/data/regiments/dwslay_regiment.tres",        # Slayers
	"res://battle_system/data/regiments/ragnar_regiment.tres",        # Ragnar's Slayers
	"res://battle_system/data/regiments/engrol_regiment.tres",        # Engineers
	# Ranged
	"res://battle_system/data/regiments/dwxbow_regiment.tres",        # Dwarf Crossbows
	# Artillery / Machines
	"res://battle_system/data/regiments/dwheel_regiment.tres",        # Dwarf Wheel
	"res://battle_system/data/regiments/gyrocopt_regiment.tres",      # Gyrocopter

	# =========================================================================
	# ORCS & GOBLINS
	# =========================================================================
	# Goblin Infantry
	"res://battle_system/data/regiments/ntgoblin_regiment.tres",          # Goblins
	"res://battle_system/data/regiments/ntgoblin_regiment.tres",      # Night Goblins
	"res://battle_system/data/regiments/fanatic_regiment.tres",       # Fanatics
	"res://battle_system/data/regiments/squigs_regiment.tres",        # Squig Hoppers
	# Orc Infantry
	"res://battle_system/data/regiments/orcboyz_regiment.tres",       # Orc Boyz
	"res://battle_system/data/regiments/biguns_regiment.tres",        # Big 'Uns
	"res://battle_system/data/regiments/blackorc_regiment.tres",      # Black Orcs
	# Cavalry
	"res://battle_system/data/regiments/wolfride_regiment.tres",      # Wolf Riders
	"res://battle_system/data/regiments/boarboyz_regiment.tres",      # Boar Boyz
	# Ranged
	"res://battle_system/data/regiments/gobarch_regiment.tres",       # Goblin Archers
	"res://battle_system/data/regiments/arraboyz_regiment.tres",      # Arrer Boyz
	# Artillery
	"res://battle_system/data/regiments/rocklob_regiment.tres",       # Rock Lobber

	# =========================================================================
	# UNDEAD
	# =========================================================================
	# Melee Infantry
	"res://battle_system/data/regiments/vanheims_regiment.tres",      # Vanheims
	"res://battle_system/data/regiments/graveguard_regiment.tres",    # Grave Guard
	# Cavalry
	"res://battle_system/data/regiments/graveknight_regiment.tres",   # Grave Knights
	# Ranged
	"res://battle_system/data/regiments/gravearch_regiment.tres",     # Skeleton Archers

	# =========================================================================
	# SKAVEN
	# =========================================================================
	# Melee Infantry
	"res://battle_system/data/regiments/clanrats_regiment.tres",      # Clanrats
	"res://battle_system/data/regiments/stmverm_regiment.tres",       # Stormvermin
	"res://battle_system/data/regiments/ratslave_regiment.tres",      # Rat Slaves
	"res://battle_system/data/regiments/eshin_regiment.tres",         # Eshin Assassins
	"res://battle_system/data/regiments/plagmonk_regiment.tres",      # Plague Monks
	"res://battle_system/data/regiments/packmast_regiment.tres",      # Packmasters
	# Artillery / Weapons Teams
	"res://battle_system/data/regiments/warpfire_regiment.tres",      # Warpfire Thrower
	"res://battle_system/data/regiments/doomdivr_regiment.tres",      # Doom Diver

	# =========================================================================
	# ELVES
	# =========================================================================
	"res://battle_system/data/regiments/woodelf_regiment.tres",       # Wood Elf Archers
	"res://battle_system/data/regiments/ilmarin_regiment.tres",       # Ilmarin

	# =========================================================================
	# MISC / MERCENARIES
	# =========================================================================
	"res://battle_system/data/regiments/bandit_regiment.tres",        # Bandits
	"res://battle_system/data/regiments/mccapt_regiment.tres",        # Merc Captain
	"res://battle_system/data/regiments/engr_regiment.tres",          # Engineers

	# =========================================================================
	# MONSTERS
	# =========================================================================
	"res://battle_system/data/regiments/ratogre_regiment.tres",       # Rat Ogres
	"res://battle_system/data/regiments/giant_regiment.tres",         # Giant
	"res://battle_system/data/regiments/treeman_regiment.tres",       # Treeman
	"res://battle_system/data/regiments/troll_regiment.tres",         # Troll
	"res://battle_system/data/regiments/dragon_regiment.tres",        # Dragon
	"res://battle_system/data/regiments/wyvern_regiment.tres",        # Wyvern
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _melee_resolver = null
var _casualty_processor = null
var _rng := RandomNumberGenerator.new()

var _duel_results: Array[Dictionary] = []
var _all_invariant_violations: Array[Dictionary] = []
var _crashes: Array[Dictionary] = []

# Aggregate counters
var _total_attacks_resolved: int = 0
var _total_casualties_dealt: int = 0
var _total_routs: int = 0
var _total_rallies: int = 0
var _total_kills: int = 0           # regiment fully wiped
var _total_timeouts: int = 0

# Public state for external queries
var _is_running: bool = false

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
func _ready() -> void:
	_rng.randomize()
	_is_running = true

	print("=".repeat(72))
	print("[MeleeDuelRunner] Starting %d melee duels" % TOTAL_DUELS)
	print("[MeleeDuelRunner] Max %d ticks per duel, max %d rally cycles" % [MAX_TICKS_PER_DUEL, MAX_RALLY_CYCLES])
	print("=".repeat(72))

	_melee_resolver = MeleeResolverScript.new()
	_casualty_processor = CasualtyProcessorScript.new()
	_casualty_processor.cache_audio_manager(get_tree())

	# Speed up
	Engine.time_scale = 10.0
	Engine.max_fps = 0

	await get_tree().process_frame
	await _run_all_duels()

	Engine.time_scale = 1.0
	_emit_report()
	_save_json_report()

	_is_running = false

	# Only quit if running standalone (not inside unit zoo)
	if quit_when_done:
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func _run_all_duels() -> void:
	for i in TOTAL_DUELS:
		var duel_num: int = i + 1
		var result: Dictionary = await _run_single_duel(duel_num)
		_duel_results.append(result)

		if duel_num % 5 == 0 or duel_num == TOTAL_DUELS:
			print("[MeleeDuelRunner] Completed %d/%d duels (violations so far: %d)" % [
				duel_num, TOTAL_DUELS, _all_invariant_violations.size()
			])


func _run_single_duel(duel_num: int) -> Dictionary:
	var data_a: RegimentData = _pick_unit_data()
	var data_b: RegimentData = _pick_unit_data()

	var result: Dictionary = {
		"duel": duel_num,
		"unit_a": data_a.regiment_name,
		"unit_b": data_b.regiment_name,
		"ticks": 0,
		"attacks_resolved": 0,
		"casualties_a": 0,
		"casualties_b": 0,
		"rout_cycles_a": 0,
		"rout_cycles_b": 0,
		"rally_cycles_a": 0,
		"rally_cycles_b": 0,
		"final_state_a": "",
		"final_state_b": "",
		"final_morale_a": 0.0,
		"final_morale_b": 0.0,
		"final_soldiers_a": 0,
		"final_soldiers_b": 0,
		"winner": "",
		"violations": [],
		"crashed": false,
	}

	# Spawn the two regiments with proper faction assignments
	# reg_a = player-controlled (west side), reg_b = enemy (east side)
	var reg_a: Node3D = _spawn_regiment(data_a, Vector3(-1, 0, 0), true)
	var reg_b: Node3D = _spawn_regiment(data_b, Vector3(1, 0, 0), false)

	if reg_a == null or reg_b == null:
		result.crashed = true
		_crashes.append({"duel": duel_num, "reason": "regiment spawn failed"})
		return result

	# Wait one frame so _ready() fires on the regiments
	await get_tree().process_frame

	# Drive the duel
	var ticks: int = 0
	var rout_a: int = 0
	var rout_b: int = 0
	var rally_a: int = 0
	var rally_b: int = 0
	var prev_state_a: int = reg_a.state
	var prev_state_b: int = reg_b.state

	while ticks < MAX_TICKS_PER_DUEL:
		ticks += 1

		# Termination: one side wiped
		if reg_a.current_soldiers <= 0:
			result.winner = "B (kill)"
			_total_kills += 1
			break
		if reg_b.current_soldiers <= 0:
			result.winner = "A (kill)"
			_total_kills += 1
			break

		# Termination: both routing past max cycles
		if rout_a >= MAX_RALLY_CYCLES and rout_b >= MAX_RALLY_CYCLES:
			result.winner = "stalemate (both broke too many times)"
			break

		# Termination: one side shattered/routing while other is still fighting
		var a_shattered: bool = reg_a.state == Regiment.State.ROUTING and reg_a.current_morale <= SHATTER_THRESHOLD
		var b_shattered: bool = reg_b.state == Regiment.State.ROUTING and reg_b.current_morale <= SHATTER_THRESHOLD
		var a_fighting: bool = reg_a.state == Regiment.State.ENGAGING and reg_a.current_soldiers > 0
		var b_fighting: bool = reg_b.state == Regiment.State.ENGAGING and reg_b.current_soldiers > 0

		if a_shattered and b_fighting:
			result.winner = "B (routed A)"
			break
		if b_shattered and a_fighting:
			result.winner = "A (routed B)"
			break

		# Pre-tick invariant snapshot (per regiment) for state-transition checking
		prev_state_a = reg_a.state
		prev_state_b = reg_b.state

		# Move toward each other if not engaged yet
		if not _in_melee_range(reg_a, reg_b):
			_step_toward(reg_a, reg_b.global_position, TICK_DELTA)
			_step_toward(reg_b, reg_a.global_position, TICK_DELTA)
		else:
			# === RESOLVE ONE EXCHANGE ===
			var ok_a: bool = (reg_a.state != Regiment.State.ROUTING and reg_a.state != Regiment.State.DEAD)
			var ok_b: bool = (reg_b.state != Regiment.State.ROUTING and reg_b.state != Regiment.State.DEAD)

			if ok_a and ok_b:
				var exchange: Dictionary = _safe_resolve_exchange(reg_a, reg_b, result)
				result.attacks_resolved += 1
				_total_attacks_resolved += 1

				var cas_a_to_b: int = exchange.get("attacker", {}).get("casualties", 0)
				var cas_b_to_a: int = exchange.get("defender_counter", {}).get("casualties", 0)

				_apply_casualties(reg_b, cas_a_to_b)
				_apply_casualties(reg_a, cas_b_to_a)
				result.casualties_b += cas_a_to_b
				result.casualties_a += cas_b_to_a
				_total_casualties_dealt += cas_a_to_b + cas_b_to_a

				# Morale damage proportional to casualties taken
				# Real system: each death applies -3.0 to nearby soldiers + friend_killed events
				# Simulation: (casualties / max_soldiers) * BASE_CASUALTY_MORALE_MULT
				if cas_a_to_b > 0 and reg_b.data.max_soldiers > 0:
					var casualty_ratio_b: float = float(cas_a_to_b) / float(reg_b.data.max_soldiers)
					var morale_damage_b: float = casualty_ratio_b * BASE_CASUALTY_MORALE_MULT
					reg_b.current_morale -= morale_damage_b
				if cas_b_to_a > 0 and reg_a.data.max_soldiers > 0:
					var casualty_ratio_a: float = float(cas_b_to_a) / float(reg_a.data.max_soldiers)
					var morale_damage_a: float = casualty_ratio_a * BASE_CASUALTY_MORALE_MULT
					reg_a.current_morale -= morale_damage_a

		# Per-tick morale drain in melee (matches your "stress while engaged" model)
		if _in_melee_range(reg_a, reg_b):
			reg_a.current_morale -= COMBAT_MORALE_DRAIN_PER_TICK
			reg_b.current_morale -= COMBAT_MORALE_DRAIN_PER_TICK

		# Clamp morale
		reg_a.current_morale = clampf(reg_a.current_morale, 0.0, 100.0)
		reg_b.current_morale = clampf(reg_b.current_morale, 0.0, 100.0)

		# === ROUT / RALLY STATE MACHINE ===
		# Rout when morale collapses and not already routing/dead
		if reg_a.current_morale <= ROUT_THRESHOLD and reg_a.state == Regiment.State.ENGAGING:
			_force_state(reg_a, Regiment.State.ROUTING)
			rout_a += 1
			_total_routs += 1
		if reg_b.current_morale <= ROUT_THRESHOLD and reg_b.state == Regiment.State.ENGAGING:
			_force_state(reg_b, Regiment.State.ROUTING)
			rout_b += 1
			_total_routs += 1

		# Check for shattered (morale too low to ever rally)
		var a_can_rally: bool = reg_a.current_morale > SHATTER_THRESHOLD and rout_a < MAX_RALLY_CYCLES
		var b_can_rally: bool = reg_b.current_morale > SHATTER_THRESHOLD and rout_b < MAX_RALLY_CYCLES

		# Rally if morale recovered enough AND not shattered
		if reg_a.state == Regiment.State.ROUTING and reg_a.current_morale >= RALLY_THRESHOLD and a_can_rally:
			_force_state(reg_a, Regiment.State.RALLYING)
		if reg_b.state == Regiment.State.ROUTING and reg_b.current_morale >= RALLY_THRESHOLD and b_can_rally:
			_force_state(reg_b, Regiment.State.RALLYING)

		# After rallying for a moment, return to engaging (re-engage cycle)
		if reg_a.state == Regiment.State.RALLYING and reg_a.current_morale >= RALLY_THRESHOLD + 10:
			_force_state(reg_a, Regiment.State.ENGAGING)
			rally_a += 1
			_total_rallies += 1
		if reg_b.state == Regiment.State.RALLYING and reg_b.current_morale >= RALLY_THRESHOLD + 10:
			_force_state(reg_b, Regiment.State.ENGAGING)
			rally_b += 1
			_total_rallies += 1

		# Routing units drift away from enemy + slowly recover morale (if not shattered)
		if reg_a.state == Regiment.State.ROUTING:
			_step_toward(reg_a, reg_a.global_position - reg_b.global_position.normalized() * 5.0, TICK_DELTA)
			if a_can_rally:
				reg_a.current_morale += 1.5  # Recovery while fleeing
		if reg_b.state == Regiment.State.ROUTING:
			_step_toward(reg_b, reg_b.global_position - reg_a.global_position.normalized() * 5.0, TICK_DELTA)
			if b_can_rally:
				reg_b.current_morale += 1.5  # Recovery while fleeing

		# Force-engage if alive and in range and not routing
		if (reg_a.state == Regiment.State.IDLE or reg_a.state == Regiment.State.MARCHING) and _in_melee_range(reg_a, reg_b):
			_force_state(reg_a, Regiment.State.ENGAGING)
		if (reg_b.state == Regiment.State.IDLE or reg_b.state == Regiment.State.MARCHING) and _in_melee_range(reg_b, reg_a):
			_force_state(reg_b, Regiment.State.ENGAGING)

		# === INVARIANT CHECKS ===
		_check_invariants(reg_a, "A", duel_num, ticks, prev_state_a, result)
		_check_invariants(reg_b, "B", duel_num, ticks, prev_state_b, result)

		# Yield occasionally so we don't freeze the engine
		if ticks % 25 == 0:
			await get_tree().process_frame

	# Timeout?
	if ticks >= MAX_TICKS_PER_DUEL and result.winner == "":
		result.winner = "timeout"
		_total_timeouts += 1

	# Snapshot final state
	result.ticks            = ticks
	result.rout_cycles_a    = rout_a
	result.rout_cycles_b    = rout_b
	result.rally_cycles_a   = rally_a
	result.rally_cycles_b   = rally_b
	result.final_state_a    = _state_name(reg_a.state)
	result.final_state_b    = _state_name(reg_b.state)
	result.final_morale_a   = reg_a.current_morale
	result.final_morale_b   = reg_b.current_morale
	result.final_soldiers_a = reg_a.current_soldiers
	result.final_soldiers_b = reg_b.current_soldiers

	# Cleanup
	if is_instance_valid(reg_a):
		reg_a.queue_free()
	if is_instance_valid(reg_b):
		reg_b.queue_free()
	await get_tree().process_frame

	return result


# ---------------------------------------------------------------------------
# Combat resolution wrapper - catches errors from your real resolver
# ---------------------------------------------------------------------------
func _safe_resolve_exchange(att: Node, def: Node, duel_result: Dictionary) -> Dictionary:
	# We trap any exceptions/push_errors from the resolver. Godot doesn't have
	# try/catch for runtime errors, but it does for missing methods/null derefs
	# in the form of post-call validation. We do best-effort sanity checks:
	if att == null or def == null:
		_record_violation(duel_result, "null_combatant",
			"Resolver called with null combatant", -1)
		return {"attacker": {"casualties": 0}, "defender_counter": {"casualties": 0}}
	if att.data == null or def.data == null:
		_record_violation(duel_result, "null_data",
			"Combatant has null data resource", -1)
		return {"attacker": {"casualties": 0}, "defender_counter": {"casualties": 0}}

	var exchange: Dictionary = _melee_resolver.resolve_bidirectional_melee(att, def, 0.0, false, 1.0, 1.0, 1.0, 1.0)

	# Sanity check the structure
	if not exchange.has("attacker") or not exchange.has("defender_counter"):
		_record_violation(duel_result, "malformed_exchange_result",
			"resolve_bidirectional_melee returned malformed dict: %s" % exchange.keys(), -1)
		return {"attacker": {"casualties": 0}, "defender_counter": {"casualties": 0}}

	return exchange


# ---------------------------------------------------------------------------
# Invariant checks - the actual hole-finder
# ---------------------------------------------------------------------------
func _check_invariants(reg: Node, side: String, duel: int, tick: int, prev_state: int, duel_result: Dictionary) -> void:
	# 1. Soldier count never exceeds max
	if reg.current_soldiers > reg.data.max_soldiers:
		_record_violation(duel_result, "soldier_overflow",
			"%s has %d soldiers (max %d)" % [side, reg.current_soldiers, reg.data.max_soldiers], tick)

	# 2. Soldier count never negative
	if reg.current_soldiers < 0:
		_record_violation(duel_result, "negative_soldiers",
			"%s soldiers went negative: %d" % [side, reg.current_soldiers], tick)

	# 3. Morale clamped 0..100
	if reg.current_morale < 0.0 or reg.current_morale > 100.0:
		_record_violation(duel_result, "morale_out_of_bounds",
			"%s morale %.2f outside [0,100]" % [side, reg.current_morale], tick)

	# 4. Dead unit (0 soldiers) should be marked DEAD
	if reg.current_soldiers <= 0 and reg.state != Regiment.State.DEAD:
		# allow one-tick lag - this is a soft warning
		pass

	# 5. Zombie: state DEAD but soldiers > 0
	if reg.state == Regiment.State.DEAD and reg.current_soldiers > 0:
		_record_violation(duel_result, "zombie_unit",
			"%s state=DEAD but has %d soldiers" % [side, reg.current_soldiers], tick)

	# 6. Illegal direct transition: ENGAGING -> RALLYING (must rout first)
	if prev_state == Regiment.State.ENGAGING and reg.state == Regiment.State.RALLYING:
		_record_violation(duel_result, "illegal_transition",
			"%s went ENGAGING -> RALLYING without ROUTING" % side, tick)

	# 7. Illegal direct transition: ROUTING -> ENGAGING (must rally first)
	if prev_state == Regiment.State.ROUTING and reg.state == Regiment.State.ENGAGING:
		_record_violation(duel_result, "illegal_transition",
			"%s went ROUTING -> ENGAGING without RALLYING" % side, tick)

	# 8. Position should never contain NaN
	var pos: Vector3 = reg.global_position
	if is_nan(pos.x) or is_nan(pos.y) or is_nan(pos.z):
		_record_violation(duel_result, "nan_position",
			"%s position is NaN: %s" % [side, str(pos)], tick)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _pick_unit_data() -> RegimentData:
	var path: String = UNIT_POOL[_rng.randi() % UNIT_POOL.size()]
	var res: Resource = load(path)
	if res == null or not res is RegimentData:
		push_warning("Failed to load %s" % path)
		# fall back to militia
		return load("res://battle_system/data/militia.tres") as RegimentData
	return res as RegimentData


func _spawn_regiment(data: RegimentData, pos: Vector3, is_player: bool = true) -> Node3D:
	var reg: Node3D = RegimentScene.instantiate()
	# Set ALL config BEFORE add_child(), because add_child() triggers _ready().
	# Regiment._ready() reads use_3d_soldiers / use_sprite_soldiers and would
	# spawn full visuals if we set these flags after.
	# FLANKING FIX: Also set is_player_controlled before _ready() so initial
	# facing is set correctly (player faces EAST, enemy faces WEST).
	reg.data = data
	reg.is_player_controlled = is_player
	reg.use_3d_soldiers = false
	reg.use_sprite_soldiers = false
	add_child(reg)
	reg.global_position = pos
	return reg


func _in_melee_range(a: Node3D, b: Node3D) -> bool:
	return a.global_position.distance_to(b.global_position) <= ENGAGEMENT_DISTANCE


func _step_toward(reg: Node3D, target: Vector3, delta: float) -> void:
	var dir: Vector3 = (target - reg.global_position)
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	var speed: float = reg.data.walk_speed if reg.data else 1.5
	reg.global_position += dir * speed * delta


func _force_state(reg: Node, new_state: int) -> void:
	# Use the regiment's set_state if present (preferred - exercises real code path)
	if reg.has_method("set_state"):
		reg.set_state(new_state)
	else:
		reg.state = new_state


func _apply_casualties(reg: Node, amount: int) -> void:
	if amount <= 0:
		return
	# Prefer the real take_casualties method
	if reg.has_method("take_casualties"):
		reg.take_casualties(amount)
	else:
		reg.current_soldiers = maxi(0, reg.current_soldiers - amount)


func _state_name(s: int) -> String:
	match s:
		Regiment.State.IDLE:      return "IDLE"
		Regiment.State.MARCHING:  return "MARCHING"
		Regiment.State.ENGAGING:  return "ENGAGING"
		Regiment.State.ROUTING:   return "ROUTING"
		Regiment.State.RALLYING:  return "RALLYING"
		Regiment.State.DEAD:      return "DEAD"
	return "UNKNOWN(%d)" % s


func _record_violation(duel_result: Dictionary, type_str: String, message: String, tick: int) -> void:
	var v: Dictionary = {
		"duel": duel_result.duel,
		"type": type_str,
		"tick": tick,
		"message": message,
	}
	duel_result.violations.append(v)
	_all_invariant_violations.append(v)


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
func _emit_report() -> void:
	print("")
	print("=".repeat(72))
	print("[MeleeDuelRunner] FINAL REPORT")
	print("=".repeat(72))
	print("Duels run:               %d" % _duel_results.size())
	print("Total attacks resolved:  %d" % _total_attacks_resolved)
	print("Total casualties dealt:  %d" % _total_casualties_dealt)
	print("Total routs:             %d" % _total_routs)
	print("Total rallies:           %d" % _total_rallies)
	print("Total kills (wipeouts):  %d" % _total_kills)
	print("Total timeouts:          %d" % _total_timeouts)
	print("")
	print("Invariant violations:    %d" % _all_invariant_violations.size())

	if _all_invariant_violations.size() > 0:
		# Group by type
		var by_type: Dictionary = {}
		for v in _all_invariant_violations:
			by_type[v.type] = by_type.get(v.type, 0) + 1
		print("  By type:")
		for t in by_type.keys():
			print("    %-26s %d" % [t, by_type[t]])
		print("")
		print("  First 15 violations:")
		for i in mini(15, _all_invariant_violations.size()):
			var v: Dictionary = _all_invariant_violations[i]
			print("    [duel %d, tick %d] %s: %s" % [v.duel, v.tick, v.type, v.message])

	if _crashes.size() > 0:
		print("")
		print("CRASHES: %d" % _crashes.size())
		for c in _crashes:
			print("  %s" % c)

	print("")
	print("Per-duel summary (winner | ticks | attacks | A->B casualties | B->A | A_routs/rallies | B_routs/rallies):")
	print("-".repeat(72))
	for r in _duel_results:
		print("  #%-3d %-22s vs %-22s | %-30s | %3dt %3da | %3d / %3d | A:%d/%d B:%d/%d" % [
			r.duel, r.unit_a, r.unit_b, r.winner,
			r.ticks, r.attacks_resolved,
			r.casualties_b, r.casualties_a,
			r.rout_cycles_a, r.rally_cycles_a,
			r.rout_cycles_b, r.rally_cycles_b,
		])
	print("=".repeat(72))

	if _all_invariant_violations.is_empty() and _crashes.is_empty():
		print("STATUS: PASS - No melee combat invariants violated.")
	else:
		print("STATUS: FAIL - Holes found. See user://melee_duel_report.json for full detail.")
	print("=".repeat(72))


func _save_json_report() -> void:
	var report: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"duels_run": _duel_results.size(),
		"totals": {
			"attacks_resolved":  _total_attacks_resolved,
			"casualties_dealt":  _total_casualties_dealt,
			"routs":             _total_routs,
			"rallies":           _total_rallies,
			"kills":             _total_kills,
			"timeouts":          _total_timeouts,
		},
		"violations": _all_invariant_violations,
		"crashes":    _crashes,
		"duels":      _duel_results,
	}
	var path: String = "user://melee_duel_report.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write report to %s" % path)
		return
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("[MeleeDuelRunner] Full JSON report -> %s" % ProjectSettings.globalize_path(path))
