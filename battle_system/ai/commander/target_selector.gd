class_name TargetSelector
extends RefCounted

## Universal target selection algorithm.
## Works identically for player and enemy units.
## Scores potential targets based on multiple factors.
##
## Usage:
##   var selector = TargetSelector.new()
##   var best_target = selector.select_best_target(my_regiment, candidates)

# =============================================================================
# SCORING WEIGHTS
# =============================================================================

const WEIGHT_DISTANCE: float = 0.5          # Per unit of distance (lower = better)
const WEIGHT_WEAKNESS: float = 25.0         # HP ratio bonus
const WEIGHT_LOW_MORALE: float = 20.0       # Morale ratio bonus
const WEIGHT_ROUTING: float = 15.0          # Bonus for routing targets
const WEIGHT_THREAT: float = 10.0           # High attack value
const WEIGHT_FLANK: float = 20.0            # Flanking opportunity
const WEIGHT_REAR: float = 30.0             # Rear attack opportunity

# Unit type matchup bonuses
const MATCHUP_BONUS: Dictionary = {
	# attacker_type -> { defender_type -> bonus }
	UnitType.Type.CAVALRY: {
		UnitType.Type.RANGED: 15.0,
		UnitType.Type.INFANTRY: 5.0,
		UnitType.Type.CAVALRY: 0.0,
		UnitType.Type.ARTILLERY: 20.0,
	},
	UnitType.Type.INFANTRY: {
		UnitType.Type.RANGED: 10.0,
		UnitType.Type.INFANTRY: 0.0,
		UnitType.Type.CAVALRY: -10.0,
		UnitType.Type.ARTILLERY: 15.0,
	},
	UnitType.Type.RANGED: {
		UnitType.Type.RANGED: 0.0,
		UnitType.Type.INFANTRY: 5.0,
		UnitType.Type.CAVALRY: -5.0,
		UnitType.Type.ARTILLERY: 10.0,
	},
	UnitType.Type.ARTILLERY: {
		UnitType.Type.RANGED: 5.0,
		UnitType.Type.INFANTRY: 10.0,
		UnitType.Type.CAVALRY: -15.0,
		UnitType.Type.ARTILLERY: 0.0,
	},
}

# Maximum engagement distances by unit type
const MAX_ENGAGEMENT_DISTANCE: Dictionary = {
	UnitType.Type.INFANTRY: 30.0,
	UnitType.Type.CAVALRY: 50.0,
	UnitType.Type.RANGED: 80.0,
	UnitType.Type.ARTILLERY: 120.0,
}

# =============================================================================
# PROPERTIES
# =============================================================================

var _cached_scores: Dictionary = {}
var _cache_valid_time: float = 0.0
const CACHE_DURATION: float = 0.25  # Cache scores for 250ms

# =============================================================================
# MAIN SELECTION
# =============================================================================

func select_best_target(regiment: Node, candidates: Array, max_distance: float = -1.0) -> Node:
	## Select the best target from a list of candidates.
	## Returns null if no valid target found.
	return select_best_target_with_accuracy(regiment, candidates, max_distance, 1.0)


func select_best_target_with_accuracy(regiment: Node, candidates: Array, max_distance: float = -1.0, accuracy: float = 1.0) -> Node:
	## Select the best target with accuracy modifier applied.
	## accuracy < 1.0 adds randomness to scores, making targeting worse.
	## accuracy = 0.0 means completely random targeting.
	## accuracy = 1.0 means perfect targeting (default behavior).
	if candidates.is_empty():
		return null

	if max_distance < 0:
		max_distance = _get_max_engagement_distance(regiment)

	var best_target: Node = null
	var best_score: float = -INF

	for candidate in candidates:
		if not _is_valid_target(candidate):
			continue

		var distance: float = regiment.global_position.distance_to(candidate.global_position)
		if distance > max_distance:
			continue

		var score: float = calculate_target_score(regiment, candidate, distance)

		# Apply accuracy modifier - lower accuracy adds randomness
		if accuracy < 1.0:
			# Add noise inversely proportional to accuracy
			# At accuracy 0.5, add up to 50% noise
			# At accuracy 0.0, add up to 100% noise (essentially random)
			var noise_factor: float = 1.0 - accuracy
			var noise: float = randf_range(-noise_factor, noise_factor) * abs(score)
			score = score * accuracy + noise

		if score > best_score:
			best_score = score
			best_target = candidate

	return best_target


func select_targets_ranked(regiment: Node, candidates: Array, count: int = 3, max_distance: float = -1.0) -> Array:
	## Select top N targets, ranked by score.
	if candidates.is_empty():
		return []

	if max_distance < 0:
		max_distance = _get_max_engagement_distance(regiment)

	var scored_targets: Array = []

	for candidate in candidates:
		if not _is_valid_target(candidate):
			continue

		var distance: float = regiment.global_position.distance_to(candidate.global_position)
		if distance > max_distance:
			continue

		var score: float = calculate_target_score(regiment, candidate, distance)
		scored_targets.append({ "target": candidate, "score": score })

	# Sort by score descending
	scored_targets.sort_custom(func(a, b): return a["score"] > b["score"])

	# Return top N
	var results: Array = []
	for i in mini(count, scored_targets.size()):
		results.append(scored_targets[i]["target"])

	return results

# =============================================================================
# SCORING
# =============================================================================

func calculate_target_score(attacker: Node, defender: Node, distance: float = -1.0) -> float:
	## Calculate a score for attacking this target.
	## Higher score = better target.

	if distance < 0:
		distance = attacker.global_position.distance_to(defender.global_position)

	var score: float = 30.0  # Base score

	# Distance penalty (closer = better)
	score -= distance * WEIGHT_DISTANCE

	# HP weakness bonus
	var hp_ratio: float = _get_hp_ratio(defender)
	score += (1.0 - hp_ratio) * WEIGHT_WEAKNESS

	# Morale weakness bonus
	var morale_ratio: float = _get_morale_ratio(defender)
	score += (1.0 - morale_ratio) * WEIGHT_LOW_MORALE

	# Routing bonus
	if _is_routing(defender):
		score += WEIGHT_ROUTING

	# Threat level (attack stat)
	var threat: float = _get_threat_level(defender)
	score += threat * WEIGHT_THREAT

	# Flank/rear attack opportunity
	var angle: float = _calculate_attack_angle(attacker, defender)
	if angle > 135.0:  # Rear
		score += WEIGHT_REAR
	elif angle > 90.0:  # Flank
		score += WEIGHT_FLANK

	# Unit type matchup
	var matchup: float = _get_matchup_bonus(attacker, defender)
	score += matchup

	return score

# =============================================================================
# ANGLE CALCULATIONS
# =============================================================================

func _calculate_attack_angle(attacker: Node, defender: Node) -> float:
	## Calculate angle of attack relative to defender's facing.
	## 0 = frontal, 90 = flank, 180 = rear

	# Get defender's facing direction (forward is -Z in Godot)
	var defender_forward: Vector3 = -defender.global_transform.basis.z.normalized()
	defender_forward.y = 0
	defender_forward = defender_forward.normalized()

	# Direction from defender to attacker
	var to_attacker: Vector3 = (attacker.global_position - defender.global_position).normalized()
	to_attacker.y = 0
	to_attacker = to_attacker.normalized()

	# Calculate angle (dot product gives cosine of angle)
	var dot: float = defender_forward.dot(to_attacker)
	var angle_rad: float = rad_to_deg(acos(clampf(dot, -1.0, 1.0)))

	return angle_rad


func is_flanking(attacker: Node, defender: Node) -> bool:
	## Check if attacker is in flanking position.
	var angle: float = _calculate_attack_angle(attacker, defender)
	return angle > 90.0


func is_rear_attacking(attacker: Node, defender: Node) -> bool:
	## Check if attacker is attacking from rear.
	var angle: float = _calculate_attack_angle(attacker, defender)
	return angle > 135.0


func get_best_flank_position(attacker: Node, defender: Node, distance: float = 8.0) -> Vector3:
	## Calculate best position to flank the defender.
	## Now considers attacker's approach angle for better positioning.

	# Get defender's right side (perpendicular to facing)
	var defender_right: Vector3 = defender.global_transform.basis.x.normalized()
	defender_right.y = 0
	defender_right = defender_right.normalized()

	var defender_back: Vector3 = defender.global_transform.basis.z.normalized()
	defender_back.y = 0
	defender_back = defender_back.normalized()

	# Choose side based on attacker's current position
	var to_defender: Vector3 = defender.global_position - attacker.global_position
	var side: float = sign(defender_right.dot(to_defender.normalized()))
	if side == 0:
		side = 1.0

	# Combine flank and rear for a diagonal approach (better angle of attack)
	var flank_pos: Vector3 = defender.global_position
	flank_pos += defender_right * side * distance * 0.7  # Side component
	flank_pos += defender_back * distance * 0.5          # Rear component

	return flank_pos


func get_rear_attack_position(attacker: Node, defender: Node, distance: float = 8.0) -> Vector3:
	## Calculate position to attack from rear.

	var defender_back: Vector3 = defender.global_transform.basis.z.normalized()
	defender_back.y = 0
	defender_back = defender_back.normalized()

	return defender.global_position + defender_back * distance


func calculate_wide_flank_waypoints(attacker: Node, defender: Node, arc_distance: float = 30.0) -> Array:
	## Calculate waypoints for a wide flanking maneuver.
	## Returns Array[Vector3] forming an arc around the defender.
	var waypoints: Array = []

	# Validate both nodes before accessing positions
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return waypoints

	var start_pos: Vector3 = attacker.global_position
	var target_pos: Vector3 = defender.global_position

	# Direction from attacker to defender
	var to_target: Vector3 = (target_pos - start_pos)
	to_target.y = 0
	var distance: float = to_target.length()
	to_target = to_target.normalized()

	# Choose flank side based on current position
	var defender_right: Vector3 = defender.global_transform.basis.x.normalized()
	defender_right.y = 0
	var side: float = sign(defender_right.dot((start_pos - target_pos).normalized()))
	if side == 0:
		side = 1.0

	# Perpendicular direction for the arc
	var arc_dir: Vector3 = Vector3(-to_target.z, 0, to_target.x) * side

	# WAYPOINT 1: Swing wide perpendicular
	var wp1: Vector3 = start_pos + arc_dir * arc_distance
	waypoints.append(wp1)

	# WAYPOINT 2: Advance while staying wide
	var halfway: Vector3 = start_pos + to_target * (distance * 0.5)
	var wp2: Vector3 = halfway + arc_dir * arc_distance
	waypoints.append(wp2)

	# WAYPOINT 3: Come around behind target
	var defender_back: Vector3 = defender.global_transform.basis.z.normalized()
	defender_back.y = 0
	var wp3: Vector3 = target_pos + defender_back * 15.0 + defender_right * side * 10.0
	waypoints.append(wp3)

	# WAYPOINT 4: Final attack position
	var wp4: Vector3 = get_best_flank_position(attacker, defender, 10.0)
	waypoints.append(wp4)

	return waypoints

# =============================================================================
# HELPER QUERIES
# =============================================================================

func _is_valid_target(target: Node) -> bool:
	## Check if target can be attacked.
	if not is_instance_valid(target):
		return false

	if target is Regiment:
		return target.state != Regiment.State.DEAD

	return true


func _get_hp_ratio(regiment: Node) -> float:
	## Get HP ratio (0-1).
	if regiment is Regiment and regiment.data and regiment.data.max_soldiers > 0:
		return float(regiment.current_soldiers) / float(regiment.data.max_soldiers)
	return 1.0


func _get_morale_ratio(regiment: Node) -> float:
	## Get morale ratio (0-1).
	if regiment is Regiment:
		return regiment.current_morale / 100.0
	return 1.0


func _is_routing(regiment: Node) -> bool:
	## Check if regiment is routing.
	if regiment is Regiment:
		return regiment.state == Regiment.State.ROUTING
	return false


func _get_threat_level(regiment: Node) -> float:
	## Get threat level (0-1 based on attack stat).
	if regiment is Regiment:
		return clampf(float(regiment.data.attack) / 20.0, 0.0, 1.0)
	return 0.5


func _get_matchup_bonus(attacker: Node, defender: Node) -> float:
	## Get unit type matchup bonus.
	if not (attacker is Regiment and defender is Regiment):
		return 0.0

	var att_type: UnitType.Type = attacker.data.unit_type
	var def_type: UnitType.Type = defender.data.unit_type

	if MATCHUP_BONUS.has(att_type):
		var matchups: Dictionary = MATCHUP_BONUS[att_type]
		if matchups.has(def_type):
			return matchups[def_type]

	return 0.0


func _get_max_engagement_distance(regiment: Node) -> float:
	## Get maximum engagement distance for this regiment type.
	if regiment is Regiment:
		var unit_type: UnitType.Type = regiment.data.unit_type
		if MAX_ENGAGEMENT_DISTANCE.has(unit_type):
			return MAX_ENGAGEMENT_DISTANCE[unit_type]
	return 30.0

# =============================================================================
# SPECIAL TARGETING
# =============================================================================

func find_weakest_target(regiment: Node, candidates: Array) -> Node:
	## Find the weakest (lowest HP) valid target.
	var weakest: Node = null
	var lowest_hp: float = INF

	for candidate in candidates:
		if not _is_valid_target(candidate):
			continue

		var hp: float = _get_hp_ratio(candidate)
		if hp < lowest_hp:
			lowest_hp = hp
			weakest = candidate

	return weakest


func find_closest_target(regiment: Node, candidates: Array) -> Node:
	## Find the closest valid target.
	var closest: Node = null
	var min_dist: float = INF

	for candidate in candidates:
		if not _is_valid_target(candidate):
			continue

		var dist: float = regiment.global_position.distance_to(candidate.global_position)
		if dist < min_dist:
			min_dist = dist
			closest = candidate

	return closest


func find_routing_target(regiment: Node, candidates: Array) -> Node:
	## Find a routing target to finish off.
	for candidate in candidates:
		if _is_valid_target(candidate) and _is_routing(candidate):
			return candidate
	return null


func find_flankable_target(regiment: Node, candidates: Array) -> Node:
	## Find a target that can be flanked.
	for candidate in candidates:
		if not _is_valid_target(candidate):
			continue

		# Check if we can reach a flank position
		var check_angle: float = _calculate_attack_angle(regiment, candidate)
		if check_angle > 60.0:  # Already somewhat flanking
			return candidate

	# Otherwise find the best flank opportunity
	var best: Node = null
	var best_angle: float = 0.0

	for candidate in candidates:
		if not _is_valid_target(candidate):
			continue

		var candidate_angle: float = _calculate_attack_angle(regiment, candidate)
		if candidate_angle > best_angle:
			best_angle = candidate_angle
			best = candidate

	return best
