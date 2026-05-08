class_name PlayHoldHighGround
extends StrategicPlay

## Hold High Ground - Defensive play that secures and defends elevated terrain.
##
## Finds high ground positions and moves defensive units there,
## using the terrain advantage for both combat bonuses and morale.
##
## Triggers when:
## - High ground is available on the battlefield
## - We have defensive capability (infantry/ranged)
## - We want to force enemy to attack uphill

const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")

const HIGH_GROUND_THRESHOLD: float = 2.0  # Height advantage in meters
const POSITION_SPREAD: float = 8.0  # Spread between defending units
const HOLD_DISTANCE: float = 15.0  # Stay within this distance of position

var _high_ground_position: Vector3 = Vector3.ZERO
var _defending_units: Array = []
var _ranged_units: Array = []

func _init(p_general_ai: GeneralAI = null) -> void:
	super._init(p_general_ai, "Hold High Ground")
	intent = "Secure elevated terrain for defensive advantage and force enemy to attack uphill"


func evaluate(analysis: BattlefieldAnalysis) -> float:
	## Score based on terrain opportunity and defensive needs.
	var score: float = 0.0

	# Find best high ground position
	var high_ground: Vector3 = _find_best_high_ground(analysis)
	if high_ground == Vector3.ZERO:
		return -100.0  # No high ground available

	# Base score for having high ground
	score += 25.0

	# Bonus for having ranged units (maximize height advantage)
	if analysis.friendly_ranged > 0:
		score += 15.0 + analysis.friendly_ranged * 3.0

	# Bonus when we want to defend (losing or conservative)
	if analysis.strength_ratio < 1.0:
		score += (1.0 - analysis.strength_ratio) * 25.0

	# Bonus if enemy has to approach us (we're closer to high ground)
	var our_dist: float = analysis.friendly_center.distance_to(high_ground)
	var enemy_dist: float = analysis.enemy_center.distance_to(high_ground)
	if our_dist < enemy_dist:
		score += 15.0

	# Bonus for unit preservation personality
	if general_ai and general_ai.personality:
		score += general_ai.personality.unit_preservation * 15.0
		score += (1.0 - general_ai.personality.aggression) * 10.0

	return score


func start(analysis: BattlefieldAnalysis) -> void:
	super.start(analysis)

	_defending_units.clear()
	_ranged_units.clear()

	# Find high ground
	_high_ground_position = _find_best_high_ground(analysis)
	if _high_ground_position == Vector3.ZERO:
		status = Status.FAILURE
		return

	# Assign units
	_assign_defenders(analysis)

	if _defending_units.is_empty() and _ranged_units.is_empty():
		status = Status.FAILURE
		return

	# Issue orders
	_issue_position_orders()

	print("[AI] Securing high ground at %s with %d infantry, %d ranged" % [
		_high_ground_position, _defending_units.size(), _ranged_units.size()
	])


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

	# Update defenders
	_update_defenders()

	return Status.RUNNING


func _find_best_high_ground(analysis: BattlefieldAnalysis) -> Vector3:
	## Find the best high ground position on the battlefield.
	## Samples terrain and finds elevated areas.

	var best_pos: Vector3 = Vector3.ZERO
	var best_height: float = 0.0

	# Sample positions across the battlefield
	var center: Vector3 = analysis.battle_center
	var sample_range: float = 50.0

	for x in range(-5, 6):
		for z in range(-5, 6):
			var sample_pos: Vector3 = center + Vector3(x * 10.0, 0, z * 10.0)
			var height: float = _get_terrain_height(sample_pos)

			# Check this is higher than surrounding area
			var avg_surrounding: float = 0.0
			var samples: int = 0
			for ox in range(-1, 2):
				for oz in range(-1, 2):
					if ox == 0 and oz == 0:
						continue
					var check_pos: Vector3 = sample_pos + Vector3(ox * 8.0, 0, oz * 8.0)
					avg_surrounding += _get_terrain_height(check_pos)
					samples += 1

			if samples > 0:
				avg_surrounding /= float(samples)

			var elevation_advantage: float = height - avg_surrounding
			if elevation_advantage > HIGH_GROUND_THRESHOLD and height > best_height:
				# Prefer positions closer to our forces
				var dist_factor: float = 1.0 - (sample_pos.distance_to(analysis.friendly_center) / sample_range) * 0.3
				var score: float = elevation_advantage * dist_factor

				if score > best_height:
					best_height = score
					best_pos = sample_pos
					best_pos.y = height

	return best_pos


func _get_terrain_height(position: Vector3) -> float:
	## Get terrain height at position.
	# GeneralAI is RefCounted, so get tree through a regiment node
	if general_ai and general_ai.analysis:
		for regiment in general_ai.analysis.friendly_regiments:
			if is_instance_valid(regiment) and regiment.is_inside_tree():
				return TerrainHelperScript.get_height_at(regiment.get_tree(), position)
	return position.y


func _assign_defenders(analysis: BattlefieldAnalysis) -> void:
	## Assign units to defend the high ground.

	# Infantry defends the position
	for regiment in analysis.friendly_regiments:
		if not is_instance_valid(regiment):
			continue
		if regiment.state == regiment.State.DEAD or regiment.state == regiment.State.ROUTING:
			continue

		if regiment.data.unit_type == UnitType.Type.INFANTRY:
			_defending_units.append(regiment)
			assign_role(regiment, "hold_ground")
		elif regiment.data.unit_type == UnitType.Type.RANGED:
			_ranged_units.append(regiment)
			assign_role(regiment, "ranged_support")


func _issue_position_orders() -> void:
	## Order units to their positions on the high ground.
	var infantry_index: int = 0

	# Spread infantry across the high ground
	for regiment in _defending_units:
		if not is_instance_valid(regiment):
			continue

		var offset: Vector3 = Vector3(
			(infantry_index - _defending_units.size() / 2) * POSITION_SPREAD,
			0,
			0
		)
		var pos: Vector3 = _high_ground_position + offset
		pos.y = _get_terrain_height(pos)

		issue_defend(regiment, pos)
		infantry_index += 1

	# Place ranged units behind infantry
	var ranged_index: int = 0
	for regiment in _ranged_units:
		if not is_instance_valid(regiment):
			continue

		var offset: Vector3 = Vector3(
			(ranged_index - _ranged_units.size() / 2) * POSITION_SPREAD,
			0,
			-POSITION_SPREAD  # Behind the infantry line
		)
		var pos: Vector3 = _high_ground_position + offset
		pos.y = _get_terrain_height(pos)

		issue_defend(regiment, pos)
		ranged_index += 1


func _update_defenders() -> void:
	## Keep defenders on the high ground, engage enemies that approach.

	for regiment in _defending_units + _ranged_units:
		if not is_instance_valid(regiment):
			continue

		# If engaged, let them fight
		if regiment.state == regiment.State.ENGAGING:
			continue

		# Check if drifted too far from position
		var dist: float = regiment.global_position.distance_to(_high_ground_position)
		if dist > HOLD_DISTANCE:
			# Return to position
			var target_pos: Vector3 = _high_ground_position
			if regiment in _ranged_units:
				target_pos += Vector3(0, 0, -POSITION_SPREAD)
			issue_defend(regiment, target_pos)


func _check_completion() -> bool:
	## Check if play is complete.

	# All enemies routed/destroyed = success
	if _analysis.enemy_regiments.is_empty():
		status = Status.SUCCESS
		_is_active = false
		return true

	var active_enemies: int = 0
	for enemy in _analysis.enemy_regiments:
		if is_instance_valid(enemy) and enemy.state != enemy.State.DEAD and enemy.state != enemy.State.ROUTING:
			active_enemies += 1

	if active_enemies == 0:
		status = Status.SUCCESS
		_is_active = false
		return true

	# Lost all defenders = failure
	var active_defenders: int = 0
	for regiment in _defending_units + _ranged_units:
		if is_instance_valid(regiment) and regiment.state != regiment.State.DEAD:
			active_defenders += 1

	if active_defenders == 0:
		status = Status.FAILURE
		_is_active = false
		return true

	return false


func abort() -> void:
	super.abort()
	_defending_units.clear()
	_ranged_units.clear()
	_high_ground_position = Vector3.ZERO
