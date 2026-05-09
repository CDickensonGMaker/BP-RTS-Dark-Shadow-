extends Node

## MoraleSystem - Handles morale changes, routing contagion, and leadership bonuses.
## Uses AIAutoload's spatial hash for efficient O(1) proximity queries.
## Weather affects routing morale damage (storms increase fear).

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

# Cascade morale system - nearby units affected by one unit's state change
# REDUCED from original values to prevent mass-routing of large armies
const CASCADE_CAUTION_RADIUS: float = 15.0    # Radius for caution cascade (reduced)
const CASCADE_CAUTION_PENALTY: float = 3.0    # Morale penalty for caution cascade (reduced)
const CASCADE_WITHDRAW_RADIUS: float = 20.0   # Radius for withdraw cascade (reduced)
const CASCADE_WITHDRAW_PENALTY: float = 5.0   # Morale penalty for withdraw cascade (reduced)
const CASCADE_ROUT_RADIUS: float = 20.0       # Radius for rout cascade (reduced)
const CASCADE_ROUT_PENALTY: float = 10.0      # Morale penalty for rout cascade (reduced from 20)
const CASCADE_PRESSURE_DECAY: float = 0.03    # Per-second decay of cascade pressure (faster decay)

# Tick rate for morale checks (avoid per-frame overhead)
const MORALE_CHECK_INTERVAL: float = 0.5
const PASSIVE_RECOVERY_INTERVAL: float = 0.25  # Throttle passive recovery
const AURA_TICK_INTERVAL: float = 1.0  # Tick auras every 1 second

# =============================================================================
# STATE
# =============================================================================

var _morale_check_timer: float = 0.0
var _passive_recovery_timer: float = 0.0
var _aura_tick_timer: float = 0.0
var _cached_regiments: Array = []
var _cache_timer: float = 0.0
const CACHE_REFRESH_INTERVAL: float = 1.0  # Refresh cache every second

# Weather system reference
var _weather_system: Node

# =============================================================================
# INITIALIZATION
# =============================================================================

func _ready() -> void:
	# Cache weather system reference
	_weather_system = get_node_or_null("/root/WeatherSystem")

	# Connect to cascade morale signals
	if BattleSignals:
		BattleSignals.unit_entered_caution.connect(_on_unit_entered_caution)
		BattleSignals.unit_withdrawing.connect(_on_unit_withdrawing)
		BattleSignals.regiment_routing.connect(_on_regiment_routing)


## Get weather routing morale modifier (storms increase fear).
func _get_weather_routing_modifier() -> float:
	if _weather_system and _weather_system.has_method("get_routing_morale_modifier"):
		return _weather_system.get_routing_morale_modifier()
	return 1.0

# =============================================================================
# MORALE MODIFIERS
# =============================================================================

## Apply morale damage to a regiment.
## All morale damage should go through this method for centralized tracking.
## @param regiment: The regiment taking morale damage
## @param amount: Base morale damage amount (may be reduced by morale save)
## @param source: Optional source identifier for debugging (e.g., "combat", "flanking", "casualties")
func apply_morale_damage(regiment: Regiment, amount: float, source: String = "") -> void:
	if not is_instance_valid(regiment) or regiment.state == Regiment.State.DEAD:
		return

	var old_morale: float = regiment.current_morale

	# Morale save roll (d10 style)
	var save_roll: int = randi() % 10
	if save_roll < regiment.data.morale_save:
		amount *= 0.5

	regiment.current_morale = maxf(0.0, regiment.current_morale - amount)
	BattleSignals.morale_changed.emit(regiment, regiment.current_morale, -amount)

	# Slow drift: a fraction of morale damage permanently lowers the recovery cap
	if regiment.unit_morale:
		var cap_drift: float = amount * UnitMorale.CAP_DRIFT_RATIO
		regiment.unit_morale.drop_cap(cap_drift, source)

	# Debug output
	if source != "" and DebugFlags and DebugFlags.morale:
		print("[MORALE] %s: %.1f -> %.1f (-%0.1f from %s)" % [
			regiment.name, old_morale, regiment.current_morale, amount, source
		])

	# Calculate effective rout threshold with trait modifiers
	var effective_rout_threshold: float = ROUTE_THRESHOLD
	if BattleModifiers and BattleModifiers.is_active():
		var trait_rout_mod: float = BattleModifiers.get_rout_threshold_mod(regiment.is_player_controlled)
		# Negative modifier = lower threshold (harder to rout)
		effective_rout_threshold = ROUTE_THRESHOLD * (1.0 - trait_rout_mod)

	if regiment.current_morale <= effective_rout_threshold and regiment.state != Regiment.State.ROUTING:
		regiment.set_state(Regiment.State.ROUTING)
		BattleSignals.regiment_routing.emit(regiment)


## Apply morale bonus to a regiment.
## All morale bonuses should go through this method for centralized tracking.
## Applies diminishing returns for bonuses that push morale above the cap.
## @param regiment: The regiment receiving morale bonus
## @param amount: Morale bonus amount
## @param source: Optional source identifier for debugging (e.g., "rally", "leadership", "victory")
func apply_morale_bonus(regiment: Regiment, amount: float, source: String = "") -> void:
	if not is_instance_valid(regiment) or regiment.state == Regiment.State.DEAD:
		return
	if not regiment.unit_morale:
		# Fallback if no unit_morale - use simple add
		regiment.current_morale = minf(100.0, regiment.current_morale + amount)
		return

	var old_morale: float = regiment.current_morale
	var cap: float = regiment.unit_morale.get_morale_cap()

	if regiment.current_morale + amount <= cap:
		# Below cap - full bonus applies
		regiment.current_morale = minf(100.0, regiment.current_morale + amount)
	else:
		# Above cap - diminishing returns
		# First fill up to the cap with full effect, then diminish the remainder
		var to_cap: float = maxf(0.0, cap - regiment.current_morale)
		var overflow: float = amount - to_cap
		regiment.current_morale = minf(cap, regiment.current_morale + to_cap)

		# Diminishing: bonus / (1 + (over_cap_amount / divisor))
		var over_cap: float = regiment.current_morale - cap
		var diminished: float = overflow / (1.0 + over_cap / UnitMorale.CAP_DIMINISHING_DIVISOR)
		regiment.current_morale = minf(100.0, regiment.current_morale + diminished)

	BattleSignals.morale_changed.emit(regiment, regiment.current_morale, regiment.current_morale - old_morale)

	# Debug output
	if source != "" and DebugFlags and DebugFlags.morale:
		print("[MORALE+] %s: %.1f -> %.1f (+%0.1f from %s, cap=%.1f)" % [
			regiment.name, old_morale, regiment.current_morale,
			regiment.current_morale - old_morale, source, cap
		])

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

	# Throttle aura effects (heroes/generals boosting nearby allies)
	_aura_tick_timer += delta
	if _aura_tick_timer >= AURA_TICK_INTERVAL:
		_aura_tick_timer -= AURA_TICK_INTERVAL
		_tick_auras()


func _tick_auras() -> void:
	## Apply aura effects from heroes/generals to nearby allied units.
	for regiment in _cached_regiments:
		if not is_instance_valid(regiment):
			continue
		if not regiment.data or not regiment.data.has_aura:
			continue
		if regiment.state == Regiment.State.DEAD:
			continue

		_apply_aura_effect(regiment)


func _apply_aura_effect(aura_source: Regiment) -> void:
	## Apply morale boost to allies within aura radius.
	if not AIAutoload or not AIAutoload.spatial_hash:
		return

	var my_faction: int = 0 if aura_source.is_player_controlled else 1
	var radius: float = aura_source.data.aura_radius
	var bonus: float = aura_source.data.aura_morale_bonus

	var nearby_allies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		aura_source.global_position,
		radius,
		my_faction
	)

	for ally in nearby_allies:
		if ally == aura_source:
			continue
		if not is_instance_valid(ally):
			continue
		if ally.state == Regiment.State.DEAD:
			continue

		# Apply continuous morale modifier via UnitMorale if available
		if ally.unit_morale:
			ally.unit_morale.set_continuous_modifier_all(
				MoraleEvent.Source.GENERAL_AURA,
				bonus
			)
		else:
			# Fallback: apply direct morale bonus
			apply_morale_bonus(ally, bonus * AURA_TICK_INTERVAL, "aura")


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

	if not AIAutoload or not AIAutoload.spatial_hash:
		return  # Spatial hash not available

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
			# Weather modifier: storms increase fear from routing units
			var base_damage: float = FRIENDLY_ROUTING_NEARBY * MORALE_CHECK_INTERVAL * 0.2
			var weather_mod: float = _get_weather_routing_modifier()
			apply_morale_damage(regiment, base_damage * weather_mod)
			break  # Only apply once per tick

# =============================================================================
# LEADERSHIP BONUS (Spatial Hash Query)
# =============================================================================

func _check_leadership_bonus(regiment: Regiment) -> void:
	## Query for nearby generals/commanders using spatial hash.
	## If a commander is nearby, apply morale bonus.
	## Includes general trait aura bonuses via BattleModifiers.
	if regiment.state == Regiment.State.ROUTING or regiment.state == Regiment.State.DEAD:
		return  # Routing/dead units don't benefit from leadership

	if not AIAutoload or not AIAutoload.spatial_hash:
		return  # Spatial hash not available

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

		# Add general trait aura bonus if BattleModifiers is active
		if BattleModifiers and BattleModifiers.is_active():
			var trait_aura: float = BattleModifiers.get_morale_aura_bonus(regiment.is_player_controlled)
			bonus += trait_aura * MORALE_CHECK_INTERVAL * 0.1

		apply_morale_bonus(regiment, bonus)
		return

	# Fallback: Check for nearby regiment leaders (commanders) if no general
	# Regiment leaders boost nearby regiments even without a general
	if not AIAutoload or not AIAutoload.spatial_hash:
		return
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

# =============================================================================
# CASCADE MORALE SYSTEM
# =============================================================================

func _on_unit_entered_caution(regiment: Regiment) -> void:
	## When a unit enters caution (15% casualties), apply mild morale pressure to nearby allies.
	_apply_cascade_pressure(regiment, CASCADE_CAUTION_RADIUS, CASCADE_CAUTION_PENALTY, "caution_cascade")


func _on_unit_withdrawing(regiment: Regiment) -> void:
	## When a unit starts withdrawing (50% casualties), apply moderate morale pressure to nearby allies.
	_apply_cascade_pressure(regiment, CASCADE_WITHDRAW_RADIUS, CASCADE_WITHDRAW_PENALTY, "withdraw_cascade")


func _on_regiment_routing(regiment: Regiment) -> void:
	## When a unit routs, apply heavy morale pressure to nearby allies.
	_apply_cascade_pressure(regiment, CASCADE_ROUT_RADIUS, CASCADE_ROUT_PENALTY, "rout_cascade")


func _apply_cascade_pressure(source: Regiment, radius: float, penalty: float, source_name: String) -> void:
	## Apply morale pressure to nearby allied units and inflate their casualty tracker's cascade_pressure.
	if not is_instance_valid(source):
		return

	if not AIAutoload or not AIAutoload.spatial_hash:
		return

	var my_faction: int = 0 if source.is_player_controlled else 1

	# Query nearby allies
	var nearby_allies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		source.global_position,
		radius,
		my_faction
	)

	for ally in nearby_allies:
		if ally == source:
			continue
		if not is_instance_valid(ally):
			continue
		if ally.state == Regiment.State.ROUTING or ally.state == Regiment.State.DEAD:
			continue

		# Check for aura protection (heroes/generals reduce cascade impact)
		var reduced_penalty: float = penalty
		if ally.data and ally.data.has_aura:
			reduced_penalty *= (1.0 - ally.data.aura_casualty_resistance)

		# Apply morale damage
		apply_morale_damage(ally, reduced_penalty, source_name)

		# Inflate casualty tracker's cascade pressure
		if ally.casualty_tracker:
			ally.casualty_tracker.cascade_pressure += reduced_penalty * 0.01
			if DebugFlags and DebugFlags.morale:
				print("[CASCADE] %s cascade pressure increased by %.2f (now %.2f)" % [
					ally.name, reduced_penalty * 0.01, ally.casualty_tracker.cascade_pressure
				])
