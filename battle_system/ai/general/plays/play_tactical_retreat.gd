class_name PlayTacticalRetreat
extends StrategicPlay

## Tactical Retreat strategy.
## Pull damaged units back while maintaining ranged cover.
## Used when the army is losing and needs to disengage.

const ROLE_RETREAT: String = "retreat"
const ROLE_COVER: String = "cover"

const HP_THRESHOLD: float = 0.4  # Units below 40% HP retreat
const RETREAT_DISTANCE: float = 50.0  # How far to pull back
const COVER_FIRE_RANGE: float = 30.0  # Ranged units stay within this range

var _retreat_units: Array = []
var _cover_units: Array = []
var _retreat_positions: Dictionary = {}  # Regiment -> Vector3 target position
var _retreat_direction: Vector3 = Vector3.BACK

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "Tactical Retreat")
	intent = "Pull damaged units back while ranged units provide covering fire; disengage safely"


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score this play. High when army is losing and needs to retreat.
	var score: float = 0.0

	# Very good when losing badly
	if analysis.strength_ratio < 0.6:
		score += (0.6 - analysis.strength_ratio) * 80.0

	# Good when many units are routing
	if analysis.routing_friendly > 0 and analysis.friendly_regiments.size() > 0:
		var routing_ratio: float = float(analysis.routing_friendly) / float(analysis.friendly_regiments.size())
		score += routing_ratio * 50.0

	# Good when morale is low
	if analysis.average_friendly_morale < 40.0:
		score += (40.0 - analysis.average_friendly_morale) * 0.8

	# Count damaged units (HP < 40%)
	var damaged_count: int = 0
	var total_hp_ratio: float = 0.0

	for regiment in analysis.friendly_regiments:
		if not regiment.data or regiment.data.max_soldiers <= 0:
			continue
		var hp_ratio: float = float(regiment.current_soldiers) / float(regiment.data.max_soldiers)
		total_hp_ratio += hp_ratio
		if hp_ratio < HP_THRESHOLD:
			damaged_count += 1

	# Average HP ratio
	if analysis.friendly_regiments.size() > 0:
		var avg_hp: float = total_hp_ratio / float(analysis.friendly_regiments.size())
		if avg_hp < 0.5:
			score += (0.5 - avg_hp) * 40.0

	# Many damaged units = retreat needed
	if damaged_count > 0:
		score += damaged_count * 15.0

	# Negative score when winning - don't retreat if ahead
	if analysis.strength_ratio > 1.2:
		score -= 50.0

	# Negative when enemy is routing more than us
	if analysis.routing_enemy > analysis.routing_friendly:
		score -= 30.0

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_retreat_units.clear()
	_cover_units.clear()
	_retreat_positions.clear()

	# Calculate retreat direction (away from enemy center)
	_calculate_retreat_direction(analysis)

	# Assign units to roles
	_assign_units(analysis)

	# Calculate retreat positions
	_calculate_retreat_positions(analysis)

	# Issue initial orders
	_issue_retreat_orders()


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

	# Update retreat movement
	_update_retreat_units()

	# Update cover fire
	_update_cover_units()

	return Status.RUNNING


func _calculate_retreat_direction(analysis: BattlefieldAnalysis) -> void:
	## Calculate the direction to retreat (away from enemies).
	if analysis.enemy_center != Vector3.ZERO and analysis.friendly_center != Vector3.ZERO:
		_retreat_direction = (analysis.friendly_center - analysis.enemy_center).normalized()
		_retreat_direction.y = 0
	else:
		# Default to retreating "backward" (negative Z)
		_retreat_direction = Vector3.BACK


func _assign_units(analysis: BattlefieldAnalysis) -> void:
	## Assign units to retreat or cover roles.

	for regiment in analysis.friendly_regiments:
		if not regiment.data or regiment.data.max_soldiers <= 0:
			continue
		var hp_ratio: float = float(regiment.current_soldiers) / float(regiment.data.max_soldiers)

		# Damaged units or routing units retreat
		if hp_ratio < HP_THRESHOLD or regiment.state == Regiment.State.ROUTING:
			_retreat_units.append(regiment)
			assign_role(regiment, ROLE_RETREAT)
		# Ranged units with decent HP provide cover
		elif regiment.data.unit_type == UnitType.Type.RANGED and hp_ratio >= HP_THRESHOLD:
			_cover_units.append(regiment)
			assign_role(regiment, ROLE_COVER)
		# Healthy melee units also retreat but more slowly (screening)
		else:
			_retreat_units.append(regiment)
			assign_role(regiment, ROLE_RETREAT)


func _calculate_retreat_positions(analysis: BattlefieldAnalysis) -> void:
	## Calculate retreat target positions for each unit.
	## Clamps all positions to map bounds (configurable via AIAutoload).

	# Find the map edge in retreat direction
	# For now, use a fixed retreat distance
	var retreat_base: Vector3 = analysis.friendly_center + _retreat_direction * RETREAT_DISTANCE
	if AIAutoload:
		retreat_base = AIAutoload.clamp_to_map(retreat_base)

	# Spread units along a line perpendicular to retreat direction
	var line_dir: Vector3 = _retreat_direction.cross(Vector3.UP).normalized()
	var unit_spacing: float = 10.0

	var retreat_count: int = _retreat_units.size()
	var start_offset: float = -float(retreat_count - 1) * unit_spacing / 2.0

	for i in retreat_count:
		var regiment = _retreat_units[i]
		var offset: float = start_offset + i * unit_spacing
		var retreat_pos: Vector3 = retreat_base + line_dir * offset
		# Clamp to map bounds (configurable via AIAutoload)
		if AIAutoload:
			retreat_pos = AIAutoload.clamp_to_map(retreat_pos)
		_retreat_positions[regiment] = retreat_pos

	# Cover units position slightly behind retreating units
	var cover_base: Vector3 = retreat_base - _retreat_direction * 15.0  # Behind retreating units
	if AIAutoload:
		cover_base = AIAutoload.clamp_to_map(cover_base)

	var cover_count: int = _cover_units.size()
	start_offset = -float(cover_count - 1) * unit_spacing / 2.0

	for i in cover_count:
		var regiment = _cover_units[i]
		var offset: float = start_offset + i * unit_spacing
		var cover_pos: Vector3 = cover_base + line_dir * offset
		# Clamp to map bounds (configurable via AIAutoload)
		if AIAutoload:
			cover_pos = AIAutoload.clamp_to_map(cover_pos)
		_retreat_positions[regiment] = cover_pos


func _issue_retreat_orders() -> void:
	## Issue initial retreat orders to all units.

	# Order retreat units to move to retreat positions
	for regiment in _retreat_units:
		if not is_instance_valid(regiment):
			continue

		var retreat_pos: Vector3 = _retreat_positions.get(regiment, regiment.global_position)
		issue_defend(regiment, retreat_pos)

		# Set defensive stance
		var commander: CommanderAI = general_ai.get_commander(regiment)
		if commander:
			commander.set_stance(CommanderAI.Stance.DEFENSIVE)

	# Order cover units to their positions
	for regiment in _cover_units:
		if not is_instance_valid(regiment):
			continue

		var cover_pos: Vector3 = _retreat_positions.get(regiment, regiment.global_position)
		issue_defend(regiment, cover_pos)


func _update_retreat_units() -> void:
	## Continue guiding retreat units to safety.

	for regiment in _retreat_units:
		if not is_instance_valid(regiment):
			continue

		# Skip if dead
		if regiment.state == Regiment.State.DEAD:
			continue

		# If still engaged, try to break contact
		if regiment.state == Regiment.State.ENGAGING:
			# Can't issue retreat order while engaged, wait for combat to end
			continue

		# Check if at retreat position
		var retreat_pos: Vector3 = _retreat_positions.get(regiment, regiment.global_position)
		var dist: float = regiment.global_position.distance_to(retreat_pos)

		if dist > 5.0:
			# Still retreating - ensure order is active
			if regiment.state == Regiment.State.IDLE:
				issue_defend(regiment, retreat_pos)


func _update_cover_units() -> void:
	## Manage ranged units providing cover fire.

	for regiment in _cover_units:
		if not is_instance_valid(regiment):
			continue

		if regiment.state == Regiment.State.DEAD:
			continue

		var commander: CommanderAI = general_ai.get_commander(regiment)
		if not commander:
			continue

		# Find best target to cover fire
		var targets: Array = AIAutoload.get_enemy_regiments(
			0 if regiment.is_player_controlled else 1
		)

		if targets.is_empty():
			continue

		# Prioritize enemies chasing our retreating units
		var best_target: Node = null
		var best_score: float = -INF

		for target in targets:
			var score: float = 0.0

			# Distance from target to our retreating units
			var min_dist_to_retreat: float = INF
			for retreating in _retreat_units:
				if is_instance_valid(retreating) and retreating.state != Regiment.State.DEAD:
					var d: float = target.global_position.distance_to(retreating.global_position)
					min_dist_to_retreat = minf(min_dist_to_retreat, d)

			# Closer to our retreating units = higher priority
			if min_dist_to_retreat < 30.0:
				score += (30.0 - min_dist_to_retreat)

			# Pursuing units are priority
			if target.state == Regiment.State.MARCHING:
				score += 10.0

			# Within range is better
			var dist: float = regiment.global_position.distance_to(target.global_position)
			if dist <= regiment.data.range_distance:
				score += 20.0

			if score > best_score:
				best_score = score
				best_target = target

		if best_target:
			commander.set_target(best_target)


func _check_completion() -> bool:
	## Check if retreat is complete or should end.

	# All retreat units reached safety or dead
	var retreated_count: int = 0
	var total_retreat: int = 0

	for regiment in _retreat_units:
		if not is_instance_valid(regiment) or regiment.state == Regiment.State.DEAD:
			retreated_count += 1
			total_retreat += 1
			continue

		total_retreat += 1

		var retreat_pos: Vector3 = _retreat_positions.get(regiment, regiment.global_position)
		var dist: float = regiment.global_position.distance_to(retreat_pos)

		if dist < 8.0:
			retreated_count += 1

	# Success: all units retreated or dead
	if total_retreat > 0 and retreated_count >= total_retreat:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Failure: no more units to retreat
	if _retreat_units.is_empty() and _cover_units.is_empty():
		status = Status.FAILURE
		_is_active = false
		return true

	# Battle state changed significantly - enemy routed
	if _analysis.enemy_regiments.size() > 0 and _analysis.routing_enemy >= _analysis.enemy_regiments.size() / 2:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Timeout after 60 seconds
	if get_elapsed_time() > 60.0:
		status = Status.SUCCESS
		_is_active = false
		return true

	return false


func abort() -> void:
	super.abort()
	_retreat_units.clear()
	_cover_units.clear()
	_retreat_positions.clear()
