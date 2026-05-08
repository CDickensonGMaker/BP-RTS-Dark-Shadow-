class_name GeneralAI
extends RefCounted

## Strategic-level AI for army command.

# Preload siege plays (ensure script is loaded before use)
const PlayChokepointDefenseScript = preload("res://battle_system/ai/general/plays/play_chokepoint_defense.gd")
const PlayDefendCapturePointsScript = preload("res://battle_system/ai/general/plays/play_defend_capture_points.gd")
const BattleObjectiveClass = preload("res://battle_system/ai/data/battle_objective.gd")
## Evaluates battlefield state and selects strategic plays.
## Coordinates regiment-level CommanderAIs.
##
## Usage:
##   var general = GeneralAI.new(faction, personality)
##   AIAutoload.register_general_ai(general, faction)

# =============================================================================
# SIGNALS
# =============================================================================

signal play_started(play_name: String)
signal play_completed(play_name: String, success: bool)
signal order_issued(regiment: Node, order: Dictionary)

# =============================================================================
# PROPERTIES
# =============================================================================

var faction: int = 0
var personality: AIPersonality

## Per-side objective (attacker/defender/etc). Drives play selection in Phase 5+.
## Defaults to ANNIHILATE (skirmish behavior) so battles without an explicit
## objective work exactly as before.
var objective: BattleObjectiveClass = BattleObjectiveClass.default_skirmish()

var analysis: BattlefieldAnalysis
var current_play: StrategicPlay = null
var available_plays: Array[StrategicPlay] = []

# Regiment assignments
var regiment_roles: Dictionary = {}  # Regiment -> role string

# Hysteresis to prevent dithering between plays
var _play_switch_cooldown: float = 0.0
const PLAY_SWITCH_COOLDOWN: float = 5.0

# Registered commander AIs
var _commander_ais: Dictionary = {}  # Regiment -> CommanderAI

# Debug verbosity - reads from DebugFlags autoload
var debug_verbose: bool:
	get: return DebugFlags.ai_general if DebugFlags else false

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_faction: int = 0, p_personality: AIPersonality = null) -> void:
	faction = p_faction
	personality = p_personality if p_personality else AIPersonality.new()

	analysis = BattlefieldAnalysis.new(faction)
	_init_plays()

	# Stamp the objective start time so time-pressure calculations work.
	objective.start_time_sec = Time.get_ticks_msec() / 1000.0


func _init_plays() -> void:
	## Initialize available strategic plays.
	available_plays = [
		# Siege plays (check first - high priority when applicable)
		PlayChokepointDefenseScript.new(self),  # Forward defense at chokepoints
		PlayDefendCapturePointsScript.new(self),
		# Core plays
		PlayPinAndFlank.new(self),
		PlayDefensiveLine.new(self),
		PlayAllOutAssault.new(self),
		PlayTacticalRetreat.new(self),
		PlayRallyPoint.new(self),
		# Reactive plays
		PlayPunishOvercommit.new(self),
		PlayExploitLowMorale.new(self),
		PlayHoldHighGround.new(self),
	]

# =============================================================================
# COMMANDER REGISTRATION
# =============================================================================

func register_commander(regiment: Node, commander_ai: CommanderAI) -> void:
	## Register a CommanderAI for a regiment.
	_commander_ais[regiment] = commander_ai


func unregister_commander(regiment: Node) -> void:
	## Remove a CommanderAI.
	_commander_ais.erase(regiment)
	regiment_roles.erase(regiment)


func get_commander(regiment: Node) -> CommanderAI:
	## Get the CommanderAI for a regiment.
	return _commander_ais.get(regiment)

# =============================================================================
# MAIN TICK
# =============================================================================

func tick() -> void:
	## Called by AIAutoload at 3s intervals.

	# Update battlefield analysis
	analysis.update()

	# Update cooldown
	if _play_switch_cooldown > 0:
		_play_switch_cooldown -= 3.0  # Tick interval

	# Evaluate current play
	if current_play:
		var status: StrategicPlay.Status = current_play.tick()
		if status != StrategicPlay.Status.RUNNING:
			_on_play_completed(status == StrategicPlay.Status.SUCCESS)

	# Consider switching plays
	if _play_switch_cooldown <= 0:
		_evaluate_plays()

	# Issue orders to unassigned regiments
	_manage_unassigned_regiments()


func _evaluate_plays() -> void:
	## Score all plays and potentially switch to a better one.
	var best_play: StrategicPlay = null
	var best_score: float = -INF
	var play_scores: Dictionary = {}  # For logging

	for play in available_plays:
		var score: float = play.evaluate(analysis)

		# Apply personality modifiers
		score = _apply_personality_modifiers(play, score)

		# Apply battle tide modifier (losing AI prefers defensive, winning prefers aggressive)
		score = _apply_tide_modifier(play, score)

		# Apply objective modifiers (attacker/defender asymmetry)
		score = _apply_objective_modifiers(play, score)

		# Hysteresis: current play gets bonus to prevent dithering
		if play == current_play:
			score += 15.0

		play_scores[play.name] = score

		if score > best_score:
			best_score = score
			best_play = play

	# Log play evaluation with reasoning (only if verbose or play is changing)
	var current_name: String = current_play.name if current_play else "None"
	var will_switch: bool = best_play and best_play != current_play and best_score > 20.0

	if debug_verbose or will_switch:
		print("[AI] GeneralAI evaluating plays (strength=%.2f, morale=%.0f%%, current=%s):" % [
			analysis.strength_ratio,
			analysis.average_friendly_morale,
			current_name
		])
		for play in available_plays:
			var score: float = play_scores.get(play.name, 0.0)
			var marker: String = " <-- BEST" if play == best_play else ""
			print("  %s: %.1f%s" % [play.name, score, marker])

	# Switch if significantly better
	if best_play and best_play != current_play:
		if best_score > 20.0:  # Minimum threshold
			print("[AI] Switching to %s: %s" % [best_play.name, best_play.intent])
			_start_play(best_play)


func _apply_personality_modifiers(play: StrategicPlay, base_score: float) -> float:
	## Apply AI personality modifiers to play scores.
	## Also applies strength ratio checks (Stainless Steel pattern).
	var score: float = base_score

	# === STRENGTH RATIO MODIFIERS (Stainless Steel) ===
	# AI should avoid attacking when significantly outnumbered
	# and prefer defensive plays when at a disadvantage.
	var strength_ratio: float = analysis.strength_ratio

	if play is PlayAllOutAssault:
		score += personality.aggression * 20.0
		# Heavily penalize attacking when outnumbered
		# At 0.8 ratio (SS "strength comparison"): no penalty
		# Below 0.8: increasingly penalized
		# Below 0.5: almost never attack
		if strength_ratio < 0.8:
			score -= (0.8 - strength_ratio) * 100.0  # Strong penalty when weak
		elif strength_ratio > 1.5:
			score += 15.0  # Bonus for attacking when strong

	elif play is PlayDefensiveLine:
		score += (1.0 - personality.aggression) * 15.0
		# Boost defensive play when outnumbered
		if strength_ratio < 1.0:
			score += (1.0 - strength_ratio) * 30.0

	elif play is PlayPinAndFlank:
		score += personality.tactical_flexibility * 10.0
		# Flanking requires some strength - penalize when weak
		if strength_ratio < 0.7:
			score -= 20.0
		elif strength_ratio > 1.2:
			score += 10.0  # Good flanking opportunity

	elif play is PlayTacticalRetreat:
		# Cautious AIs retreat earlier, aggressive AIs fight longer
		score += (1.0 - personality.aggression) * 15.0
		score += personality.unit_preservation * 20.0
		score -= personality.risk_tolerance * 10.0
		# Boost retreat when severely outnumbered (below 0.6 ratio)
		if strength_ratio < 0.6:
			score += (0.6 - strength_ratio) * 50.0

	elif play is PlayRallyPoint:
		# Leaders who care about troops rally more
		score += personality.unit_preservation * 15.0
		score += personality.tactical_flexibility * 8.0
		score -= personality.pursuit_aggression * 5.0

	return score


func _apply_tide_modifier(play: StrategicPlay, base_score: float) -> float:
	## Apply battle tide modifier to play scores.
	## When AI is winning (negative tide), prefer aggressive plays.
	## When AI is losing (positive tide), prefer defensive plays.
	if not BattleTide:
		return base_score

	var score: float = base_score
	var tide_mod: float = BattleTide.get_ai_play_modifier()  # -1 to +1 (positive = AI should be defensive)

	if play is PlayAllOutAssault:
		# Aggressive play: boost when winning, penalize when losing
		score -= tide_mod * 20.0  # Negative tide_mod = AI winning = boost

	elif play is PlayDefensiveLine:
		# Defensive play: boost when losing
		score += tide_mod * 15.0

	elif play is PlayTacticalRetreat:
		# Retreat play: strongly boost when losing badly
		if tide_mod > 0.5:  # AI is losing
			score += tide_mod * 25.0

	elif play is PlayRallyPoint:
		# Rally: boost when losing (need to rally troops)
		score += tide_mod * 10.0

	return score


func _apply_objective_modifiers(play: StrategicPlay, base_score: float) -> float:
	## Apply battle objective modifiers to play scores.
	## This is what makes attackers behave like attackers and defenders like defenders.
	## Personality and tide already applied — this adjusts on top of those.
	var score: float = base_score

	match objective.type:
		BattleObjectiveClass.Type.HOLD_GROUND:
			# Defender: heavily reward holding the line, penalize unprovoked aggression.
			# Counter-attacks (PlayPunishOvercommit) are bread-and-butter, not pacifism.
			if play is PlayChokepointDefenseScript:
				score += 45.0  # Highest priority for forward chokepoint defense
			elif play is PlayDefensiveLine:
				score += 35.0
			elif play is PlayHoldHighGround:
				score += 25.0
			elif play is PlayAllOutAssault:
				score -= 40.0
			elif play is PlayPinAndFlank:
				# Defender flanking is a counter-attack — only if enemy is committed.
				# Approximate "enemy committed" as analysis.active_engagements >= 2.
				if analysis.active_engagements >= 2:
					score += 5.0
				else:
					score -= 15.0
			elif play is PlayPunishOvercommit:
				score += 20.0

		BattleObjectiveClass.Type.BREAKTHROUGH:
			# Attacker with time pressure: aggression scales with time elapsed.
			# Early battle = normal play. Late battle = throw caution out.
			var time_pressure: float = objective.get_time_pressure(
				Time.get_ticks_msec() / 1000.0
			)
			if play is PlayAllOutAssault:
				score += 15.0 + time_pressure * 30.0
			elif play is PlayPinAndFlank:
				score += 10.0
			elif play is PlayDefensiveLine:
				score -= 20.0 + time_pressure * 30.0
			elif play is PlayTacticalRetreat:
				# Attackers retreating waste time; heavy penalty late.
				score -= time_pressure * 25.0

		BattleObjectiveClass.Type.RAID:
			# Hit-and-run: prefer plays that target weak units, avoid attrition.
			if play is PlayExploitLowMorale:
				score += 25.0
			elif play is PlayPunishOvercommit:
				score += 15.0
			elif play is PlayAllOutAssault:
				score -= 15.0
			elif play is PlayTacticalRetreat:
				score += 10.0  # retreating IS the plan

		BattleObjectiveClass.Type.CAPTURE_POINTS:
			# Siege defense: chokepoint defense is ideal.
			if play is PlayChokepointDefenseScript:
				score += 40.0  # High priority for chokepoint defense
			elif play is PlayDefendCapturePointsScript:
				score += 30.0
			elif play is PlayDefensiveLine:
				score += 20.0
			elif play is PlayAllOutAssault:
				score -= 30.0

		BattleObjectiveClass.Type.ANNIHILATE, _:
			# Default: no objective modifier. Personality + tide alone govern.
			pass

	return score

# =============================================================================
# PLAY MANAGEMENT
# =============================================================================

func _start_play(play: StrategicPlay) -> void:
	## Start a new strategic play.
	if current_play:
		current_play.abort()

	current_play = play
	current_play.start(analysis)
	_play_switch_cooldown = PLAY_SWITCH_COOLDOWN

	play_started.emit(play.name)
	BattleSignals.ai_play_started.emit(self, play.name)


func _on_play_completed(success: bool) -> void:
	## Called when current play completes.
	if current_play:
		play_completed.emit(current_play.name, success)
		current_play = null

	# Clear regiment roles
	regiment_roles.clear()


func assign_role(regiment: Node, role: String) -> void:
	## Assign a role to a regiment for the current play.
	regiment_roles[regiment] = role


func get_role(regiment: Node) -> String:
	## Get a regiment's current role.
	return regiment_roles.get(regiment, "")

# =============================================================================
# ORDER ISSUING
# =============================================================================

func issue_order_to_regiment(regiment: Node, order: Dictionary) -> void:
	## Issue an order to a specific regiment.
	var commander: CommanderAI = _commander_ais.get(regiment)
	if commander:
		commander.receive_strategic_order(order)
		order_issued.emit(regiment, order)


func issue_attack_order(regiment: Node, target: Node) -> void:
	## Order regiment to attack a target.
	issue_order_to_regiment(regiment, {
		"type": "ATTACK",
		"target": target,
	})


func issue_defend_order(regiment: Node, position: Vector3) -> void:
	## Order regiment to defend a position.
	issue_order_to_regiment(regiment, {
		"type": "DEFEND",
		"position": position,
	})


func issue_flank_order(regiment: Node, target: Node) -> void:
	## Order regiment to flank a target.
	issue_order_to_regiment(regiment, {
		"type": "FLANK",
		"target": target,
	})


func issue_hold_order(regiment: Node) -> void:
	## Order regiment to hold position.
	issue_order_to_regiment(regiment, {
		"type": "HOLD",
	})

# =============================================================================
# UNASSIGNED REGIMENT MANAGEMENT
# =============================================================================

func _manage_unassigned_regiments() -> void:
	## Give basic orders to regiments without roles.
	for regiment in analysis.friendly_regiments:
		if not regiment_roles.has(regiment) or regiment_roles[regiment] == "":
			_assign_default_behavior(regiment)


func _assign_default_behavior(regiment: Node) -> void:
	## Assign default behavior to unassigned regiment.
	## Does NOT auto-switch stance to prevent dithering. Stance comes from orders only.
	var commander: CommanderAI = _commander_ais.get(regiment)
	if not commander:
		return

	# Find target if no current target (regardless of stance)
	if not commander.current_target:
		commander.acquire_target()

# =============================================================================
# RETREAT MANAGEMENT
# =============================================================================

func request_retreat(regiment: Node) -> void:
	## Handle retreat request from a CommanderAI.
	## Called when unit_preservation trait triggers due to low HP.
	var commander: CommanderAI = _commander_ais.get(regiment)
	if not commander:
		return

	# Assign retreat role
	regiment_roles[regiment] = "retreating"

	# Set defensive stance and move to safe position
	commander.set_stance(CommanderAI.Stance.DEFENSIVE)
	commander.clear_target()

	# Find a safe retreat position (away from enemies, towards map edge)
	var retreat_pos: Vector3 = _find_retreat_position(regiment)
	issue_order_to_regiment(regiment, {
		"type": "DEFEND",
		"position": retreat_pos,
	})


func _find_retreat_position(regiment: Node) -> Vector3:
	## Find a safe position for the regiment to retreat to.
	var retreat_dir: Vector3 = Vector3.ZERO

	# Get direction away from nearest enemy
	if AIAutoload:
		var enemy_faction: int = 1 if faction == 0 else 0
		var enemies: Array = AIAutoload.get_all_regiments(enemy_faction)
		if enemies.size() > 0:
			# Find centroid of enemies (count valid enemies)
			var enemy_center: Vector3 = Vector3.ZERO
			var valid_count: int = 0
			for enemy in enemies:
				if is_instance_valid(enemy):
					enemy_center += enemy.global_position
					valid_count += 1
			if valid_count > 0:
				enemy_center /= float(valid_count)
				# Move away from enemy center
				retreat_dir = (regiment.global_position - enemy_center).normalized()
		else:
			# No enemies, retreat towards own edge
			retreat_dir = Vector3(0, 0, 1) if faction == 0 else Vector3(0, 0, -1)
	else:
		retreat_dir = Vector3(0, 0, 1) if faction == 0 else Vector3(0, 0, -1)

	retreat_dir.y = 0
	return regiment.global_position + retreat_dir * 25.0


# =============================================================================
# QUERIES
# =============================================================================

func get_regiments_with_role(role: String) -> Array:
	## Get all regiments assigned to a specific role.
	var result: Array = []
	for regiment in regiment_roles:
		if regiment_roles[regiment] == role:
			result.append(regiment)
	return result


func get_available_regiments() -> Array:
	## Get regiments not currently assigned or engaged.
	return analysis.friendly_regiments.filter(func(r):
		return not regiment_roles.has(r) and r.state != Regiment.State.ENGAGING
	)

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	return {
		"faction": faction,
		"current_play": current_play.name if current_play else "None",
		"play_cooldown": _play_switch_cooldown,
		"regiment_roles": regiment_roles.size(),
		"analysis": analysis.get_debug_info(),
	}

# =============================================================================
# CLEANUP
# =============================================================================

func destroy() -> void:
	## Clean up the general AI.
	if current_play:
		current_play.abort()
		current_play = null

	# Unregister from AIAutoload
	if AIAutoload:
		AIAutoload.unregister_general_ai(faction)

	# Clear references
	_commander_ais.clear()
	regiment_roles.clear()
	available_plays.clear()
	analysis = null
	personality = null
