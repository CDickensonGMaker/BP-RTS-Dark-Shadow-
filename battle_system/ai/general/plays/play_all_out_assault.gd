class_name PlayAllOutAssault
extends StrategicPlay

## All-Out Assault strategy.
## Concentrate forces and overwhelm the enemy with numbers.
## High risk, high reward when we have the advantage.

const ROLE_ASSAULT: String = "assault"
const ROLE_SUPPORT: String = "support"

var _primary_target: Node = null
var _assault_units: Array = []
var _support_units: Array = []

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "All-Out Assault")
	intent = "Concentrate all forces and overwhelm the enemy with aggressive attack"


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score this play. Good when we have clear advantage.
	var score: float = 0.0

	# Strong advantage = aggressive play
	if analysis.strength_ratio > 1.3:
		score += (analysis.strength_ratio - 1.0) * 40.0

	# Enemy morale is low = go for the kill
	if analysis.average_enemy_morale < 50.0:
		score += (50.0 - analysis.average_enemy_morale) * 0.5

	# Enemy routing = press the advantage
	if analysis.routing_enemy > 0:
		score += analysis.routing_enemy * 15.0

	# Our morale is high = confident attack
	if analysis.average_friendly_morale > 70.0:
		score += 10.0

	# Lots of cavalry = mobile assault
	if analysis.friendly_cavalry > 2:
		score += 10.0

	# Bad when we're losing
	if analysis.strength_ratio < 0.8:
		score -= 30.0

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_assault_units.clear()
	_support_units.clear()

	# Select primary target
	_primary_target = _select_target(analysis)
	if not _primary_target:
		status = Status.FAILURE
		return

	# Assign all units to assault
	_assign_units(analysis)

	# Launch assault
	_launch_assault()


func tick() -> Status:
	if not _is_active:
		return status

	# Refresh analysis
	if general_ai:
		_analysis = general_ai.analysis
		_analysis.update()

	# Check completion
	if _check_completion():
		return status

	# Maintain assault pressure
	_maintain_assault()

	# Update target if current is destroyed
	_update_target()

	return Status.RUNNING


func _select_target(analysis: BattlefieldAnalysis) -> Node:
	## Select the best target for concentrated assault.

	# Prefer weak or isolated targets
	var best_target: Node = null
	var best_score: float = -INF

	for regiment in analysis.enemy_regiments:
		var score: float = 0.0

		# Low morale = likely to break
		score += (100.0 - regiment.current_morale) * 0.3

		# Few soldiers = easy target
		var soldier_ratio: float = float(regiment.current_soldiers) / float(regiment.data.max_soldiers)
		score += (1.0 - soldier_ratio) * 20.0

		# Already routing = finish them
		if regiment.state == Regiment.State.ROUTING:
			score += 30.0

		# Isolated targets are easier
		var isolation: float = 0.0
		for other in analysis.enemy_regiments:
			if other != regiment:
				var dist: float = regiment.global_position.distance_to(other.global_position)
				if dist > 20.0:
					isolation += 1.0
		score += isolation * 5.0

		if score > best_score:
			best_score = score
			best_target = regiment

	return best_target


func _assign_units(analysis: BattlefieldAnalysis) -> void:
	## Assign all units to the assault.

	# Everyone attacks
	for regiment in analysis.friendly_regiments:
		_assault_units.append(regiment)
		assign_role(regiment, ROLE_ASSAULT)

		# Set aggressive stance
		var commander: CommanderAI = general_ai.get_commander(regiment)
		if commander:
			commander.set_stance(CommanderAI.Stance.AGGRESSIVE)


func _launch_assault() -> void:
	## Issue attack orders to all units.

	for regiment in _assault_units:
		if not is_instance_valid(regiment):
			continue

		if regiment.data.unit_type == UnitType.Type.CAVALRY:
			# Cavalry charges
			issue_flank(regiment, _primary_target)
		else:
			# Everyone else direct assault
			issue_attack(regiment, _primary_target)


func _maintain_assault() -> void:
	## Keep all units pressing the attack.

	for regiment in _assault_units:
		if not is_instance_valid(regiment):
			continue

		if regiment.state == Regiment.State.ROUTING:
			continue

		var commander: CommanderAI = general_ai.get_commander(regiment)
		if not commander:
			continue

		# Keep target updated
		if not commander.current_target or not is_instance_valid(commander.current_target):
			if _primary_target and is_instance_valid(_primary_target):
				commander.set_target(_primary_target)
			else:
				# Find any enemy
				commander.acquire_target()

		# Re-engage if idle
		if regiment.state == Regiment.State.IDLE:
			if commander.current_target:
				issue_attack(regiment, commander.current_target)


func _update_target() -> void:
	## Update primary target if current is destroyed.

	if not _primary_target or not is_instance_valid(_primary_target):
		_primary_target = _select_target(_analysis)
		if _primary_target:
			# Redirect assault
			for regiment in _assault_units:
				if is_instance_valid(regiment) and regiment.state != Regiment.State.ROUTING:
					issue_attack(regiment, _primary_target)
		return

	if _primary_target.state == Regiment.State.DEAD:
		_primary_target = _select_target(_analysis)
		if _primary_target:
			for regiment in _assault_units:
				if is_instance_valid(regiment) and regiment.state != Regiment.State.ROUTING:
					issue_attack(regiment, _primary_target)


func _check_completion() -> bool:
	## Check if assault is complete.

	# All enemies destroyed/routing = success
	if _analysis.enemy_regiments.is_empty():
		status = Status.SUCCESS
		_is_active = false
		return true

	# Check routing ratio
	var active_enemies: int = 0
	for regiment in _analysis.enemy_regiments:
		if regiment.state != Regiment.State.ROUTING and regiment.state != Regiment.State.DEAD:
			active_enemies += 1

	if active_enemies == 0:
		status = Status.SUCCESS
		_is_active = false
		return true

	# We're routing more than enemy = failure
	if _analysis.routing_friendly > _analysis.routing_enemy + 2:
		status = Status.FAILURE
		_is_active = false
		return true

	# Lost too many units = failure
	var active_assault: int = 0
	for regiment in _assault_units:
		if is_instance_valid(regiment) and regiment.state != Regiment.State.DEAD:
			active_assault += 1

	if active_assault < _assault_units.size() / 3:
		status = Status.FAILURE
		_is_active = false
		return true

	return false


func abort() -> void:
	super.abort()
	_assault_units.clear()
	_support_units.clear()
	_primary_target = null
