class_name RegimentFiring
extends RefCounted

## Tracks per-soldier firing state for a regiment.
## Each soldier has an independent reload timer in STAGGER pattern.
## In VOLLEY pattern, all soldiers share a single timer.
## In SINGLE pattern, one timer for the whole regiment (crewed weapons).

const WeaponClassDataScript = preload("res://battle_system/data/weapon_class_data.gd")

var regiment: Node = null
var weapon_def: WeaponClassDataScript.WeaponDef = null
var weapon_class: int = 0

# Per-soldier reload timers (STAGGER mode only). Index matches soldier index.
var _soldier_timers: Array[float] = []

# Single shared timer (VOLLEY/SINGLE modes)
var _shared_timer: float = 0.0

# Track if we're ready to fire (for VOLLEY - all at once)
var _volley_ready: bool = false

# How many shots have been fired this firing cycle (for animation/sfx pacing)
var _shots_fired_this_cycle: int = 0

# Cooldown for breath/magic weapons (uses regiment.data.breath_cooldown)
var _breath_cooldown_timer: float = 0.0
var _breath_on_cooldown: bool = false


func _init(p_regiment: Node) -> void:
	regiment = p_regiment
	if regiment and regiment.data:
		weapon_class = regiment.data.weapon_class
		weapon_def = WeaponClassDataScript.get_def(weapon_class)
	_initialize_timers()


func _initialize_timers() -> void:
	## Initialize timers based on fire pattern.
	if not weapon_def:
		return

	var reload_time: float = _get_reload_time()

	if weapon_def.fire_pattern == WeaponClassDataScript.FirePattern.STAGGER:
		# One timer per soldier, randomized initial offset for natural staggering
		_soldier_timers.clear()
		var soldier_count: int = _get_soldier_count()
		for i in soldier_count:
			# Random initial offset 0..reload_time so soldiers fire desynced
			_soldier_timers.append(randf() * reload_time)
	elif weapon_def.fire_pattern == WeaponClassDataScript.FirePattern.SINGLE:
		# Artillery/crewed weapons start 80% loaded - first shot within 2-5 seconds
		# This represents the gun being pre-loaded before battle
		_shared_timer = reload_time * 0.8
		_volley_ready = false
	else:
		# VOLLEY starts at 50% - quicker first volley but not instant
		_shared_timer = reload_time * 0.5
		_volley_ready = false


func _get_soldier_count() -> int:
	## Returns the current number of soldiers that can fire.
	if not regiment:
		return 0
	return regiment.current_soldiers


func _get_reload_time() -> float:
	## Returns the reload time, accounting for breath_cooldown if applicable.
	if not weapon_def:
		return 3.0

	if weapon_def.has_cooldown and regiment and regiment.data:
		return regiment.data.breath_cooldown

	return weapon_def.reload_time


func _get_soldiers_per_shot() -> int:
	## Returns how many soldiers needed to fire one shot (for crewed weapons).
	if weapon_def:
		return weapon_def.soldiers_per_shot
	return 1


## Called every frame. Returns the number of shots ready to fire this frame.
## Caller is responsible for actually spawning projectiles via CombatManager.
func tick(delta: float) -> int:
	if not weapon_def or not regiment:
		return 0

	# Check if regiment has ammo
	if regiment.current_ammo <= 0:
		return 0

	# Handle breath/magic cooldown
	if _breath_on_cooldown:
		_breath_cooldown_timer -= delta
		if _breath_cooldown_timer <= 0:
			_breath_on_cooldown = false
		else:
			return 0

	_shots_fired_this_cycle = 0

	match weapon_def.fire_pattern:
		WeaponClassDataScript.FirePattern.VOLLEY:
			return _tick_volley(delta)
		WeaponClassDataScript.FirePattern.STAGGER:
			return _tick_stagger(delta)
		WeaponClassDataScript.FirePattern.SINGLE:
			return _tick_single(delta)

	return 0


func _tick_volley(delta: float) -> int:
	## All soldiers fire together when shared timer reaches reload_time.
	var reload_time: float = _get_reload_time()

	_shared_timer += delta
	if _shared_timer >= reload_time:
		_shared_timer = 0.0
		# Fire one shot per living soldier
		var shots: int = _get_soldier_count()

		# For breath weapons, start cooldown after firing
		if weapon_def.has_cooldown:
			_breath_on_cooldown = true
			_breath_cooldown_timer = reload_time

		_shots_fired_this_cycle = shots
		return shots

	return 0


func _tick_stagger(delta: float) -> int:
	## Each soldier fires independently when their personal timer expires.
	## Returns number of shots ready this frame.
	var shots: int = 0
	var soldier_count: int = mini(_soldier_timers.size(), _get_soldier_count())
	var reload_time: float = _get_reload_time()

	for i in soldier_count:
		_soldier_timers[i] += delta
		if _soldier_timers[i] >= reload_time:
			_soldier_timers[i] = 0.0
			shots += 1

	_shots_fired_this_cycle = shots
	return shots


func _tick_single(delta: float) -> int:
	## Crewed weapon: one shot per regiment per reload, requires soldiers_per_shot crew.
	var soldiers_needed: int = _get_soldiers_per_shot()
	if _get_soldier_count() < soldiers_needed:
		return 0  # Not enough crew to fire

	var reload_time: float = _get_reload_time()

	_shared_timer += delta
	if _shared_timer >= reload_time:
		_shared_timer = 0.0

		# For breath weapons, start cooldown after firing
		if weapon_def.has_cooldown:
			_breath_on_cooldown = true
			_breath_cooldown_timer = reload_time

		_shots_fired_this_cycle = 1
		return 1

	return 0


func resync_after_casualty() -> void:
	## Called when regiment loses soldiers — trim per-soldier timers.
	if weapon_def and weapon_def.fire_pattern == WeaponClassDataScript.FirePattern.STAGGER:
		var current: int = _get_soldier_count()
		while _soldier_timers.size() > current:
			_soldier_timers.pop_back()


func reset() -> void:
	## Reset all timers (e.g., when retreating and re-engaging).
	_shared_timer = 0.0
	_breath_on_cooldown = false
	_breath_cooldown_timer = 0.0
	_initialize_timers()


func get_reload_progress() -> float:
	## Returns 0.0-1.0 progress toward next volley (for UI).
	if not weapon_def:
		return 0.0

	var reload_time: float = _get_reload_time()
	if reload_time <= 0:
		return 1.0

	if _breath_on_cooldown:
		return 1.0 - (_breath_cooldown_timer / reload_time)

	match weapon_def.fire_pattern:
		WeaponClassDataScript.FirePattern.VOLLEY, WeaponClassDataScript.FirePattern.SINGLE:
			return _shared_timer / reload_time
		WeaponClassDataScript.FirePattern.STAGGER:
			# Average progress across all soldiers
			if _soldier_timers.is_empty():
				return 0.0
			var total: float = 0.0
			for t in _soldier_timers:
				total += t
			return (total / _soldier_timers.size()) / reload_time

	return 0.0


func is_on_cooldown() -> bool:
	## Returns true if breath/magic weapon is on cooldown.
	return _breath_on_cooldown


func get_cooldown_remaining() -> float:
	## Returns remaining cooldown time in seconds.
	if _breath_on_cooldown:
		return _breath_cooldown_timer
	return 0.0


func get_fire_pattern_name() -> String:
	## Returns the name of the current fire pattern (for debug).
	if not weapon_def:
		return "NONE"
	match weapon_def.fire_pattern:
		WeaponClassDataScript.FirePattern.VOLLEY:
			return "VOLLEY"
		WeaponClassDataScript.FirePattern.STAGGER:
			return "STAGGER"
		WeaponClassDataScript.FirePattern.SINGLE:
			return "SINGLE"
	return "UNKNOWN"


## Firing state for artillery units (AIMING when ready to fire, RELOADING after shot)
enum FiringState { IDLE, AIMING, RELOADING }

var _has_fired_first_shot: bool = false

func get_firing_state() -> FiringState:
	## Returns current firing state for artillery display.
	## AIMING = ready to fire, waiting for target or final aim
	## RELOADING = weapon discharged, loading next round
	if not weapon_def:
		return FiringState.IDLE

	# Only applies to SINGLE pattern (artillery)
	if weapon_def.fire_pattern != WeaponClassDataScript.FirePattern.SINGLE:
		return FiringState.IDLE

	var reload_time: float = _get_reload_time()
	var progress: float = _shared_timer / reload_time if reload_time > 0 else 0.0

	# Before first shot: timer is at 80%+ so we're AIMING
	# After firing: timer resets to 0 and counts up = RELOADING until ~80%
	if progress >= 0.8:
		return FiringState.AIMING
	else:
		# After first shot, we're reloading
		if _has_fired_first_shot:
			return FiringState.RELOADING
		else:
			# Still pre-battle loading
			return FiringState.AIMING


func get_firing_state_name() -> String:
	## Returns human-readable firing state for UI.
	match get_firing_state():
		FiringState.AIMING:
			return "AIMING"
		FiringState.RELOADING:
			return "RELOADING"
		_:
			return ""


func mark_shot_fired() -> void:
	## Called when a shot is actually fired - tracks that we've fired at least once.
	_has_fired_first_shot = true
