class_name UnitMorale
extends RefCounted

## Regiment-level morale aggregator.
## Registers all soldier MoraleComponents, ticks them at 4 Hz,
## and emits unit-level routing/rallying signals.
##
## Usage:
##   var unit_morale = UnitMorale.new(regiment)
##   unit_morale.register_soldiers(formation.soldiers)
##   # Called each frame:
##   unit_morale.update(delta)

# =============================================================================
# SIGNALS
# =============================================================================

signal unit_routed()
signal unit_rallied()
signal unit_shattered()  # Too many broken to ever rally
signal average_morale_changed(new_average: float)
signal broken_ratio_changed(ratio: float)

# =============================================================================
# PROPERTIES
# =============================================================================

var owner_regiment: Node = null
var faction: int = 0  # 0 = player, 1 = enemy

# Soldier tracking
var _soldier_components: Array[MoraleComponent] = []
var _broken_count: int = 0
var _total_count: int = 0

# State
var _is_routing: bool = false
var _is_shattered: bool = false
var _average_morale: float = 80.0

# Morale cap system - recovery ceiling that only drops during battle
var morale_cap: float = 100.0  # Recovery ceiling, can only drop during battle
const MORALE_CAP_FLOOR: float = 10.0  # Minimum cap value
const CAP_DRIFT_RATIO: float = 0.10  # 10% of morale damage applies to cap
const CAP_DIMINISHING_DIVISOR: float = 20.0  # Controls diminishing returns above cap

# Tick accumulator (4 Hz = 0.25s tick rate for engaged, 2 Hz for idle)
var _tick_accumulator: float = 0.0
const TICK_INTERVAL: float = MoraleConstants.MORALE_TICK_RATE
const TICK_INTERVAL_IDLE: float = 0.5  # Phase 11: Slower tick for non-engaged units

# Aura/environment tick (1 Hz = 1.0s tick rate for surrounding/winning/aura checks)
var _aura_tick_accumulator: float = 0.0
const AURA_TICK_INTERVAL: float = MoraleConstants.AURA_TICK_RATE

# Combat tracking for WINNING modifier
var _casualties_inflicted: int = 0
var _casualties_received: int = 0
var _last_casualties_inflicted: int = 0
var _last_casualties_received: int = 0

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_regiment: Node = null) -> void:
	owner_regiment = p_regiment
	if p_regiment and p_regiment.has_method("get") and p_regiment.get("is_player_controlled") != null:
		faction = 0 if p_regiment.is_player_controlled else 1


func setup(p_regiment: Node) -> void:
	## Late initialization.
	owner_regiment = p_regiment
	if p_regiment and p_regiment.get("is_player_controlled") != null:
		faction = 0 if p_regiment.is_player_controlled else 1

# =============================================================================
# MORALE CAP SYSTEM
# =============================================================================

func drop_cap(amount: float, reason: String = "") -> void:
	## Lowers the recovery ceiling. Only ever drops, never raises during battle.
	## Floor at MORALE_CAP_FLOOR.
	if amount <= 0:
		return
	var old_cap: float = morale_cap
	morale_cap = maxf(MORALE_CAP_FLOOR, morale_cap - amount)
	if DebugFlags and DebugFlags.morale and old_cap != morale_cap:
		var reg_name: String = owner_regiment.name if owner_regiment else "?"
		print("[CAP] %s cap %.1f -> %.1f (-%.1f from %s)" % [
			reg_name, old_cap, morale_cap, amount, reason
		])


func get_morale_cap() -> float:
	## Returns the current morale cap (recovery ceiling).
	return morale_cap


func set_initial_cap(cap_value: float) -> void:
	## Set the initial cap (used when loading from campaign data).
	morale_cap = clampf(cap_value, MORALE_CAP_FLOOR, 100.0)

# =============================================================================
# SOLDIER REGISTRATION
# =============================================================================

func register_soldier(soldier_node: Node, base_morale: float = 80.0) -> MoraleComponent:
	## Create and register a MoraleComponent for a soldier.
	var component: MoraleComponent = MoraleComponent.new(soldier_node, base_morale, faction)
	_soldier_components.append(component)
	_total_count = _soldier_components.size()

	# Connect to component signals
	component.soldier_broke.connect(_on_soldier_broke)
	component.state_changed.connect(_on_soldier_state_changed.bind(component))

	return component


func register_soldiers(soldiers: Array, base_morale: float = 80.0) -> void:
	## Register multiple soldiers at once.
	for soldier in soldiers:
		if is_instance_valid(soldier):
			register_soldier(soldier, base_morale)


func register_virtual_soldiers(count: int, base_morale: float = 80.0) -> void:
	## Register virtual soldiers for sprite-based units (no Node3D soldiers).
	## Creates morale components without owner nodes.
	for i in range(count):
		var component: MoraleComponent = MoraleComponent.new(null, base_morale, faction)
		_soldier_components.append(component)
		component.soldier_broke.connect(_on_soldier_broke)
		component.state_changed.connect(_on_soldier_state_changed.bind(component))
	_total_count = _soldier_components.size()
	_update_averages()


func unregister_soldier(component: MoraleComponent) -> void:
	## Remove a soldier (e.g., when killed).
	var idx: int = _soldier_components.find(component)
	if idx >= 0:
		if component.is_broken():
			_broken_count = maxi(0, _broken_count - 1)
		_soldier_components.remove_at(idx)
		_total_count = _soldier_components.size()
		_check_unit_state()


func get_component_for_soldier(soldier_node: Node) -> MoraleComponent:
	## Find the MoraleComponent for a specific soldier.
	for component in _soldier_components:
		if component.owner == soldier_node:
			return component
	return null

# =============================================================================
# UPDATE LOOP
# =============================================================================

func update(delta: float) -> void:
	## Call each frame. Batches soldier ticks at 4 Hz (engaged) or 2 Hz (idle).
	## Phase 11 optimization: slower tick rate for non-engaged units saves CPU.
	_tick_accumulator += delta

	# Use faster tick rate when engaged in combat, slower when idle
	var effective_interval: float = TICK_INTERVAL
	if owner_regiment and owner_regiment.state != Regiment.State.ENGAGING:
		effective_interval = TICK_INTERVAL_IDLE  # 0.5s for idle units

	if _tick_accumulator >= effective_interval:
		_tick_accumulator -= effective_interval
		_tick_all_soldiers(effective_interval)
		_update_averages()
		_check_unit_state()

	# Aura/environment tick at 1 Hz (general aura, surrounded, winning)
	_aura_tick_accumulator += delta
	if _aura_tick_accumulator >= AURA_TICK_INTERVAL:
		_aura_tick_accumulator -= AURA_TICK_INTERVAL
		_update_environment_modifiers()


func _tick_all_soldiers(tick_delta: float) -> void:
	## Tick all registered soldier components.
	for component in _soldier_components:
		component.tick(tick_delta)


func _update_averages() -> void:
	## Recalculate average morale.
	if _soldier_components.is_empty():
		_average_morale = 0.0
		return

	var total: float = 0.0
	for component in _soldier_components:
		total += component.get_morale()

	var new_average: float = total / float(_soldier_components.size())
	if absf(new_average - _average_morale) > 0.5:
		_average_morale = new_average
		average_morale_changed.emit(_average_morale)


func _update_environment_modifiers() -> void:
	## Update environment-based morale modifiers (1 Hz).
	## Checks: General/Officer auras, Surrounded, Winning combat.
	if not owner_regiment or not is_instance_valid(owner_regiment):
		return

	var position: Vector3 = owner_regiment.global_position

	# --- WINNING MODIFIER ---
	# Check if we're inflicting more casualties than receiving
	var is_winning: bool = _check_winning_combat()
	if is_winning:
		set_continuous_modifier_all(MoraleEvent.Source.WINNING, MoraleConstants.CONTINUOUS_WINNING)
	else:
		clear_continuous_modifier_all(MoraleEvent.Source.WINNING)

	# --- GENERAL AURA ---
	# Check for nearby friendly general
	var has_general_nearby: bool = _check_general_nearby(position)
	if has_general_nearby:
		set_continuous_modifier_all(MoraleEvent.Source.GENERAL_AURA, MoraleConstants.CONTINUOUS_GENERAL_AURA)
	else:
		clear_continuous_modifier_all(MoraleEvent.Source.GENERAL_AURA)

	# --- OFFICER AURA ---
	# Regiment leader provides officer aura (always present if regiment has leader)
	if owner_regiment.leader and is_instance_valid(owner_regiment.leader):
		set_continuous_modifier_all(MoraleEvent.Source.OFFICER_AURA, MoraleConstants.CONTINUOUS_OFFICER_AURA)
	else:
		clear_continuous_modifier_all(MoraleEvent.Source.OFFICER_AURA)

	# --- SURROUNDED MODIFIER ---
	# Check if enemies on 3+ sides
	var is_surrounded: bool = _check_surrounded(position)
	if is_surrounded:
		set_continuous_modifier_all(MoraleEvent.Source.SURROUNDED, MoraleConstants.CONTINUOUS_SURROUNDED)
	else:
		clear_continuous_modifier_all(MoraleEvent.Source.SURROUNDED)

	# --- BATTLE TIDE MODIFIER ---
	# Apply morale modifier based on overall battle momentum
	if BattleTide:
		var tide_bonus: float = BattleTide.get_morale_modifier(owner_regiment.is_player_controlled)
		if tide_bonus != 0.0:
			set_continuous_modifier_all(MoraleEvent.Source.BATTLE_TIDE, tide_bonus)
		else:
			clear_continuous_modifier_all(MoraleEvent.Source.BATTLE_TIDE)

	# --- NEARBY ALLIES BUFF ---
	var ally_count: int = _check_nearby_allies(position)
	if ally_count > 0:
		var ally_bonus: float = MoraleConstants.CONTINUOUS_NEARBY_ALLIES * float(ally_count)
		set_continuous_modifier_all(MoraleEvent.Source.NEARBY_ALLIES, ally_bonus)
	else:
		clear_continuous_modifier_all(MoraleEvent.Source.NEARBY_ALLIES)

	# --- OUTNUMBERED MODIFIER ---
	var is_outnumbered: bool = _check_outnumbered(position)
	if is_outnumbered:
		set_continuous_modifier_all(MoraleEvent.Source.OUTNUMBERED, MoraleConstants.CONTINUOUS_OUTNUMBERED)
	else:
		clear_continuous_modifier_all(MoraleEvent.Source.OUTNUMBERED)

	# --- UNDER FIRE MODIFIER ---
	var is_under_fire: bool = _check_under_fire()
	if is_under_fire:
		set_continuous_modifier_all(MoraleEvent.Source.UNDER_FIRE, MoraleConstants.CONTINUOUS_UNDER_FIRE)
	else:
		clear_continuous_modifier_all(MoraleEvent.Source.UNDER_FIRE)


func _check_winning_combat() -> bool:
	## Check if regiment is inflicting more casualties than receiving.
	## Compares casualties since last check.
	var inflicted_delta: int = _casualties_inflicted - _last_casualties_inflicted
	var received_delta: int = _casualties_received - _last_casualties_received

	_last_casualties_inflicted = _casualties_inflicted
	_last_casualties_received = _casualties_received

	# Winning = inflicted at least 2 more than received in last period
	return inflicted_delta > received_delta + 1


func _check_general_nearby(position: Vector3) -> bool:
	## Check if a friendly general is within aura range.
	if not AIAutoload or not AIAutoload.spatial_hash:
		return false

	# Query for generals within aura range
	var nearby: Array = AIAutoload.spatial_hash.query_radius(
		position,
		MoraleConstants.GENERAL_AURA_RADIUS,
		faction,
		SpatialHash.EntityType.GENERAL
	)

	return nearby.size() > 0


func _check_surrounded(position: Vector3) -> bool:
	## Check if enemies are on 3+ sides (N/S/E/W quadrants).
	if not AIAutoload or not AIAutoload.spatial_hash:
		return false

	var _enemy_faction: int = 1 if faction == 0 else 0  # Reserved for faction checks
	var nearby_enemies: Array = AIAutoload.spatial_hash.query_radius_enemies(
		position, 25.0, faction
	)

	if nearby_enemies.size() < 2:
		return false  # Need at least 2 enemies to be surrounded

	# Count enemies in each quadrant (N, S, E, W)
	var quadrants_with_enemies: int = 0
	var north: bool = false
	var south: bool = false
	var east: bool = false
	var west: bool = false

	for enemy in nearby_enemies:
		if not is_instance_valid(enemy):
			continue
		var dir: Vector3 = enemy.global_position - position
		dir.y = 0

		# Determine quadrant based on dominant axis
		if absf(dir.z) > absf(dir.x):
			if dir.z > 0:
				south = true
			else:
				north = true
		else:
			if dir.x > 0:
				east = true
			else:
				west = true

	# Count occupied quadrants
	if north:
		quadrants_with_enemies += 1
	if south:
		quadrants_with_enemies += 1
	if east:
		quadrants_with_enemies += 1
	if west:
		quadrants_with_enemies += 1

	# Surrounded = enemies in 3+ quadrants
	return quadrants_with_enemies >= 3


func _check_nearby_allies(position: Vector3) -> int:
	## Count friendly regiments within support radius.
	if not AIAutoload or not AIAutoload.spatial_hash:
		return 0

	var nearby_allies: Array = AIAutoload.spatial_hash.query_radius(
		position,
		MoraleConstants.NEARBY_ALLIES_RADIUS,
		faction,
		SpatialHash.EntityType.REGIMENT
	)

	# Count valid, living allies (exclude self)
	var count: int = 0
	for ally in nearby_allies:
		if not is_instance_valid(ally) or ally == owner_regiment:
			continue
		if ally.state == Regiment.State.DEAD or ally.state == Regiment.State.ROUTING:
			continue
		count += 1

	return mini(count, MoraleConstants.NEARBY_ALLIES_MAX_BONUS)


func _check_outnumbered(position: Vector3) -> bool:
	## Check if locally outnumbered (enemies > allies * 1.5).
	if not AIAutoload or not AIAutoload.spatial_hash:
		return false

	var check_radius: float = 25.0

	var nearby_enemies: Array = AIAutoload.spatial_hash.query_radius_enemies(
		position, check_radius, faction
	)
	var nearby_allies: Array = AIAutoload.spatial_hash.query_radius(
		position, check_radius, faction, SpatialHash.EntityType.REGIMENT
	)

	var enemy_count: int = nearby_enemies.size()
	var ally_count: int = nearby_allies.size()  # Includes self

	return enemy_count > int(float(ally_count) * 1.5)


func _check_under_fire() -> bool:
	## Check if regiment recently took ranged damage.
	## Uses casualty tracker's recent damage flag.
	if not owner_regiment or not owner_regiment.casualty_tracker:
		return false
	return owner_regiment.casualty_tracker.took_ranged_damage_recently()


func track_casualties_inflicted(count: int) -> void:
	## Called when this regiment inflicts casualties (for WINNING check).
	_casualties_inflicted += count


func track_casualties_received(count: int) -> void:
	## Called when this regiment receives casualties (for WINNING check).
	_casualties_received += count

# =============================================================================
# STATE CHECKING
# =============================================================================

func _check_unit_state() -> void:
	## Check for routing/rally/shattered transitions.
	if _total_count == 0:
		return

	var broken_ratio: float = float(_broken_count) / float(_total_count)

	# Check if unit can rout (Fanatic units cannot rout - they fight to the death)
	var can_unit_rout: bool = true
	if owner_regiment and owner_regiment.data and not owner_regiment.data.can_rout():
		can_unit_rout = false

	# Check for shattered (too many broken to rally)
	if broken_ratio >= MoraleConstants.UNIT_SHATTERED_RATIO:
		if not _is_shattered and can_unit_rout:
			_is_shattered = true
			_is_routing = true
			unit_shattered.emit()
		return

	# Check for routing
	if broken_ratio >= MoraleConstants.UNIT_ROUT_BROKEN_RATIO:
		if not _is_routing and can_unit_rout:
			_is_routing = true
			unit_routed.emit()
			BattleSignals.regiment_routing.emit(owner_regiment)
		return

	# Check for rally (only if currently routing but not shattered)
	if _is_routing and not _is_shattered:
		if broken_ratio < MoraleConstants.UNIT_RALLY_BROKEN_RATIO:
			_is_routing = false
			unit_rallied.emit()
			BattleSignals.regiment_rallied.emit(owner_regiment)


func _on_soldier_broke(_soldier: Node) -> void:
	## Called when an individual soldier breaks.
	_broken_count += 1
	broken_ratio_changed.emit(get_broken_ratio())
	_check_unit_state()


func _on_soldier_state_changed(old_state: MoraleEvent.State, new_state: MoraleEvent.State, _component: MoraleComponent) -> void:
	## Track state changes for broken count.
	# If soldier recovered from broken
	if old_state == MoraleEvent.State.BROKEN and new_state != MoraleEvent.State.BROKEN:
		_broken_count = maxi(0, _broken_count - 1)
		broken_ratio_changed.emit(get_broken_ratio())
		_check_unit_state()

# =============================================================================
# MASS EVENT APPLICATION
# =============================================================================

func apply_event_to_all(event: MoraleEvent) -> void:
	## Apply an event to all soldiers in the unit.
	## Disciplined units take less morale damage.
	var modified_event: MoraleEvent = _apply_morale_resistance(event)
	for component in _soldier_components:
		component.apply_event(modified_event)


func apply_event_to_nearby(event: MoraleEvent, center: Vector3, radius: float) -> void:
	## Apply event only to soldiers near a position.
	## Disciplined units take less morale damage.
	## Optimization: if radius > 15 units, skip per-soldier distance checks (covers whole formation)
	var modified_event: MoraleEvent = _apply_morale_resistance(event)

	if radius >= 15.0:
		# Large radius - apply to all soldiers without distance check (optimization)
		for component in _soldier_components:
			component.apply_event(modified_event)
	else:
		# Small radius - check distance per soldier
		for component in _soldier_components:
			if component.owner and is_instance_valid(component.owner):
				var dist: float = component.owner.global_position.distance_to(center)
				if dist <= radius:
					component.apply_event(modified_event)


func _apply_morale_resistance(event: MoraleEvent) -> MoraleEvent:
	## Apply personality-based morale resistance to negative events.
	## Disciplined units take 25% less morale damage.
	if event.magnitude >= 0:
		return event  # Only modify negative (damaging) events

	if owner_regiment and owner_regiment.data:
		var resistance: float = owner_regiment.data.get_morale_resistance_modifier()
		if resistance != 1.0:
			# Create modified event with reduced damage
			var modified: MoraleEvent = MoraleEvent.new()
			modified.source = event.source
			modified.magnitude = event.magnitude * resistance
			modified.source_position = event.source_position
			return modified

	return event


func set_continuous_modifier_all(source: MoraleEvent.Source, per_second: float) -> void:
	## Set a continuous modifier on all soldiers.
	for component in _soldier_components:
		component.set_continuous_modifier(source, per_second)


func clear_continuous_modifier_all(source: MoraleEvent.Source) -> void:
	## Clear a continuous modifier from all soldiers.
	for component in _soldier_components:
		component.clear_continuous_modifier(source)

# =============================================================================
# QUERIES
# =============================================================================

func get_average_morale() -> float:
	## Returns average morale across all soldiers.
	return _average_morale


func get_average_effectiveness() -> float:
	## Returns average combat effectiveness.
	if _soldier_components.is_empty():
		return 1.0

	var total: float = 0.0
	for component in _soldier_components:
		total += component.get_effectiveness()

	return total / float(_soldier_components.size())


func get_broken_count() -> int:
	## Returns number of broken soldiers.
	return _broken_count


func get_broken_ratio() -> float:
	## Returns ratio of broken soldiers (0.0-1.0).
	if _total_count == 0:
		return 0.0
	return float(_broken_count) / float(_total_count)


func get_steady_count() -> int:
	## Returns number of soldiers at STEADY state.
	var count: int = 0
	for component in _soldier_components:
		if component.is_steady():
			count += 1
	return count


func is_routing() -> bool:
	## Returns true if unit is routing.
	return _is_routing


func is_shattered() -> bool:
	## Returns true if unit is shattered (cannot rally).
	return _is_shattered


func force_rout() -> void:
	## Force the unit to immediately rout (from casualty threshold).
	if _is_routing:
		return
	# Check if unit can rout (Fanatic units cannot)
	if owner_regiment and owner_regiment.data and not owner_regiment.data.can_rout():
		return
	_is_routing = true
	unit_routed.emit()
	BattleSignals.regiment_routing.emit(owner_regiment)


func rally() -> void:
	## Rally the unit from routing state.
	if not _is_routing or _is_shattered:
		return
	_is_routing = false
	# Restore average morale to 40%
	apply_morale_modifier(40.0 - _average_morale)
	unit_rallied.emit()
	BattleSignals.regiment_rallied.emit(owner_regiment)


func apply_morale_modifier(amount: float) -> void:
	## Apply a direct morale modifier to all soldiers.
	for component in _soldier_components:
		component.apply_direct_modifier(amount)


func get_soldier_count() -> int:
	## Returns total registered soldiers.
	return _total_count


func get_morale_state() -> MoraleEvent.State:
	## Returns overall unit state based on average morale.
	if _average_morale >= MoraleConstants.STATE_STEADY_MIN:
		return MoraleEvent.State.STEADY
	elif _average_morale >= MoraleConstants.STATE_WAVERING_MIN:
		return MoraleEvent.State.WAVERING
	elif _average_morale >= MoraleConstants.STATE_SHAKEN_MIN:
		return MoraleEvent.State.SHAKEN
	else:
		return MoraleEvent.State.BROKEN

# =============================================================================
# SOLDIER DEATH HANDLING
# =============================================================================

func on_soldier_killed(soldier_node: Node) -> void:
	## Called when a soldier dies. Removes from tracking and applies nearby morale hit.
	var component: MoraleComponent = get_component_for_soldier(soldier_node)
	if component:
		component.kill()
		unregister_soldier(component)

	# Apply morale hit to nearby soldiers
	if soldier_node and is_instance_valid(soldier_node):
		var position: Vector3 = soldier_node.global_position
		var event: MoraleEvent = MoraleEvent.friend_killed(position)
		apply_event_to_nearby(event, position, MoraleConstants.FRIEND_KILLED_RADIUS)

		# Extra strong hit for very close soldiers
		var close_event: MoraleEvent = MoraleEvent.friend_killed(position, true)
		apply_event_to_nearby(close_event, position, MoraleConstants.FRIEND_KILLED_CLOSE_RADIUS)

# =============================================================================
# DEBUG
# =============================================================================

func get_debug_info() -> Dictionary:
	## Returns debug information for visualization.
	return {
		"total_soldiers": _total_count,
		"broken_count": _broken_count,
		"broken_ratio": get_broken_ratio(),
		"average_morale": _average_morale,
		"average_effectiveness": get_average_effectiveness(),
		"is_routing": _is_routing,
		"is_shattered": _is_shattered,
		"unit_state": MoraleEvent.State.keys()[get_morale_state()],
	}
