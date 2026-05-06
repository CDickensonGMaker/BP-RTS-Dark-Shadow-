class_name GeneralAI
extends RefCounted

## Strategic-level AI for army command.
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

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_faction: int = 0, p_personality: AIPersonality = null) -> void:
	faction = p_faction
	personality = p_personality if p_personality else AIPersonality.new()

	analysis = BattlefieldAnalysis.new(faction)
	_init_plays()


func _init_plays() -> void:
	## Initialize available strategic plays.
	available_plays = [
		PlayPinAndFlank.new(self),
		PlayDefensiveLine.new(self),
		PlayAllOutAssault.new(self),
		PlayTacticalRetreat.new(self),
		PlayRallyPoint.new(self),
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

	for play in available_plays:
		var score: float = play.evaluate(analysis)

		# Apply personality modifiers
		score = _apply_personality_modifiers(play, score)

		# Hysteresis: current play gets bonus to prevent dithering
		if play == current_play:
			score += 15.0

		if score > best_score:
			best_score = score
			best_play = play

	# Switch if significantly better
	if best_play and best_play != current_play:
		if best_score > 20.0:  # Minimum threshold
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
	## Uses strength ratio to decide between aggressive and defensive (Stainless Steel).
	var commander: CommanderAI = _commander_ais.get(regiment)
	if not commander:
		return

	# Check strength ratio before deciding stance
	var strength_ratio: float = analysis.strength_ratio

	if strength_ratio >= 0.8:
		# We're strong enough - be aggressive
		commander.set_stance(CommanderAI.Stance.AGGRESSIVE)
		# Find nearest enemy if no target
		if not commander.current_target:
			commander.acquire_target()
	else:
		# We're outnumbered - be defensive
		commander.set_stance(CommanderAI.Stance.DEFENSIVE)
		# Don't actively seek targets when weak - let enemies come to us

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
