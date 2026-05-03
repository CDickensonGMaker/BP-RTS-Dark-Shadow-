extends Node

## MoraleSystem - Handles morale changes, routing contagion, and leadership bonuses.
## Uses AIAutoload's spatial hash for efficient O(1) proximity queries.

# =============================================================================
# CONSTANTS
# =============================================================================

# Morale modifier constants
const CASUALTY_MORALE_LOSS: float = 0.5     # per soldier lost
const FLANK_PENALTY: float = 15.0
const REAR_PENALTY: float = 25.0
const FRIENDLY_ROUTING_NEARBY: float = 10.0
const OUTNUMBERED_PENALTY: float = 8.0
const GENERAL_NEARBY_BONUS: float = 20.0
const HIGH_GROUND_BONUS: float = 5.0
const ROUTE_THRESHOLD: float = 20.0
const RALLY_THRESHOLD: float = 40.0
const PASSIVE_RECOVERY: float = 0.5         # per second when not in combat

# Spatial query radii
const ROUTING_CONTAGION_RADIUS: float = 15.0
const LEADERSHIP_BONUS_RADIUS: float = 25.0

# Tick rate for morale checks (avoid per-frame overhead)
const MORALE_CHECK_INTERVAL: float = 0.5
const PASSIVE_RECOVERY_INTERVAL: float = 0.25  # Throttle passive recovery

# =============================================================================
# STATE
# =============================================================================

var _morale_check_timer: float = 0.0
var _passive_recovery_timer: float = 0.0
var _cached_regiments: Array = []
var _cache_timer: float = 0.0
const CACHE_REFRESH_INTERVAL: float = 1.0  # Refresh cache every second

# =============================================================================
# MORALE MODIFIERS
# =============================================================================

func apply_morale_damage(regiment: Regiment, amount: float) -> void:
	# Morale save roll (d10 style)
	var save_roll: int = randi() % 10
	if save_roll < regiment.data.morale_save:
		amount *= 0.5
	regiment.current_morale = maxf(0.0, regiment.current_morale - amount)
	BattleSignals.morale_changed.emit(regiment, regiment.current_morale, -amount)
	if regiment.current_morale <= ROUTE_THRESHOLD:
		regiment.set_state(Regiment.State.ROUTING)
		BattleSignals.regiment_routing.emit(regiment)


func apply_morale_bonus(regiment: Regiment, amount: float) -> void:
	regiment.current_morale = minf(100.0, regiment.current_morale + amount)
	BattleSignals.morale_changed.emit(regiment, regiment.current_morale, amount)
	if regiment.state == Regiment.State.ROUTING and regiment.current_morale >= RALLY_THRESHOLD:
		regiment.set_state(Regiment.State.RALLYING)
		BattleSignals.regiment_rallied.emit(regiment)

# =============================================================================
# PROCESSING
# =============================================================================

func _process(delta: float) -> void:
	# Refresh cached regiment list periodically (not every frame)
	_cache_timer += delta
	if _cache_timer >= CACHE_REFRESH_INTERVAL:
		_cache_timer = 0.0
		_cached_regiments = get_tree().get_nodes_in_group("all_regiments")

	# Throttle passive morale recovery (not every frame!)
	_passive_recovery_timer += delta
	if _passive_recovery_timer >= PASSIVE_RECOVERY_INTERVAL:
		var recovery_delta := _passive_recovery_timer
		_passive_recovery_timer = 0.0
		for regiment in _cached_regiments:
			if not is_instance_valid(regiment):
				continue
			if regiment.state == Regiment.State.IDLE or regiment.state == Regiment.State.MARCHING:
				# Apply recovery without emitting signal every time (batch update)
				regiment.current_morale = minf(100.0, regiment.current_morale + PASSIVE_RECOVERY * recovery_delta)

	# Throttle spatial morale checks to avoid per-frame overhead
	_morale_check_timer += delta
	if _morale_check_timer >= MORALE_CHECK_INTERVAL:
		_morale_check_timer -= MORALE_CHECK_INTERVAL
		_tick_morale_checks()


func _tick_morale_checks() -> void:
	## Perform spatial morale checks using AIAutoload's spatial hash.
	for regiment in _cached_regiments:
		if not is_instance_valid(regiment):
			continue
		_check_routing_contagion(regiment)
		_check_leadership_bonus(regiment)

# =============================================================================
# ROUTING CONTAGION (Spatial Hash Query)
# =============================================================================

func _check_routing_contagion(regiment: Regiment) -> void:
	## Query nearby allied regiments using spatial hash.
	## If any are routing, apply morale penalty.
	if regiment.state == Regiment.State.ROUTING or regiment.state == Regiment.State.DEAD:
		return  # Already routing or dead, no need to check

	var my_faction: int = 0 if regiment.is_player_controlled else 1

	# Use spatial hash for O(1) query instead of O(n) iteration
	var nearby_allies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		regiment.global_position,
		ROUTING_CONTAGION_RADIUS,
		my_faction
	)

	for ally in nearby_allies:
		if ally == regiment:
			continue
		if not is_instance_valid(ally):
			continue
		if ally.state == Regiment.State.ROUTING:
			# Scale penalty by how many routing allies are nearby
			apply_morale_damage(regiment, FRIENDLY_ROUTING_NEARBY * MORALE_CHECK_INTERVAL * 0.2)
			break  # Only apply once per tick

# =============================================================================
# LEADERSHIP BONUS (Spatial Hash Query)
# =============================================================================

func _check_leadership_bonus(regiment: Regiment) -> void:
	## Query for nearby generals/commanders using spatial hash.
	## If a commander is nearby, apply morale bonus.
	if regiment.state == Regiment.State.ROUTING or regiment.state == Regiment.State.DEAD:
		return  # Routing/dead units don't benefit from leadership

	var my_faction: int = 0 if regiment.is_player_controlled else 1

	# Query for generals within leadership radius
	var nearby_generals: Array[Node] = AIAutoload.spatial_hash.query_radius(
		regiment.global_position,
		LEADERSHIP_BONUS_RADIUS,
		my_faction,
		SpatialHash.EntityType.GENERAL
	)

	if nearby_generals.size() > 0:
		# Apply leadership bonus (scaled by tick interval)
		var bonus: float = GENERAL_NEARBY_BONUS * MORALE_CHECK_INTERVAL * 0.1
		apply_morale_bonus(regiment, bonus)
		return

	# Fallback: Check for nearby regiment leaders (commanders) if no general
	# Regiment leaders boost nearby regiments even without a general
	var nearby_regiments: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		regiment.global_position,
		LEADERSHIP_BONUS_RADIUS,
		my_faction
	)

	# Count nearby friendly regiments for mutual support bonus
	var ally_count: int = 0
	for ally in nearby_regiments:
		if ally != regiment and is_instance_valid(ally):
			if ally.state != Regiment.State.ROUTING and ally.state != Regiment.State.DEAD:
				ally_count += 1

	# Mutual support: having nearby non-routing allies gives a small morale boost
	if ally_count >= 2:
		var support_bonus: float = 2.0 * MORALE_CHECK_INTERVAL * 0.1  # Small mutual support bonus
		apply_morale_bonus(regiment, support_bonus)
