class_name RallyAbility
extends RefCounted

## Rally Ability - General's ability to rally nearby routing units.
##
## Usage:
##   var rally = RallyAbility.new(general_regiment)
##   if rally.can_use():
##       var rallied_count = rally.use()

# =============================================================================
# CONSTANTS
# =============================================================================

const RALLY_RADIUS: float = 35.0           # Radius of rally effect
const RALLY_MORALE_BOOST: float = 30.0     # Morale boost to rallied units
const COOLDOWN_DURATION: float = 120.0     # 2 minutes between rallies
const RALLY_DC: int = 12                   # Difficulty class for rally roll

# =============================================================================
# PROPERTIES
# =============================================================================

## The general/hero that owns this ability
var owner: Node = null

## Current cooldown remaining (0 = ready)
var cooldown: float = 0.0

## Whether the general is alive
var _is_active: bool = true

# =============================================================================
# INITIALIZATION
# =============================================================================

func _init(p_owner: Node = null) -> void:
	owner = p_owner


func set_owner(p_owner: Node) -> void:
	owner = p_owner
	_is_active = true


func deactivate() -> void:
	## Called when general dies.
	_is_active = false

# =============================================================================
# ABILITY USAGE
# =============================================================================

func can_use() -> bool:
	## Returns true if rally can be used.
	if not _is_active:
		return false
	if not owner or not is_instance_valid(owner):
		return false
	if owner.state == owner.State.DEAD:
		return false
	return cooldown <= 0.0


func use() -> int:
	## Attempt to rally nearby routing units.
	## Returns: Number of units successfully rallied.
	if not can_use():
		return 0

	var rallied_count: int = 0

	# Query nearby allied routing units
	if AIAutoload and AIAutoload.spatial_hash:
		var my_faction: int = 0 if owner.is_player_controlled else 1
		var nearby_allies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
			owner.global_position,
			RALLY_RADIUS,
			my_faction
		)

		for ally in nearby_allies:
			if ally == owner:
				continue
			if not is_instance_valid(ally):
				continue
			if ally.state != ally.State.ROUTING:
				continue

			# Attempt rally roll: discipline + d10 >= RALLY_DC
			if _attempt_rally_roll(ally):
				_rally_unit(ally)
				rallied_count += 1

	# Start cooldown
	cooldown = COOLDOWN_DURATION

	# Emit signal
	BattleSignals.rally_used.emit(owner, rallied_count)

	print("[RALLY] %s rallied %d units" % [owner.name, rallied_count])
	return rallied_count


func _attempt_rally_roll(regiment: Node) -> bool:
	## Roll to see if unit rallies. discipline + d10 >= RALLY_DC
	var discipline: int = 10
	if regiment.data:
		discipline = regiment.data.discipline

	var roll: int = discipline + randi_range(1, 10)
	var success: bool = roll >= RALLY_DC

	if success:
		print("[RALLY] %s passed rally roll (%d >= %d)" % [regiment.name, roll, RALLY_DC])
	else:
		print("[RALLY] %s failed rally roll (%d < %d)" % [regiment.name, roll, RALLY_DC])

	return success


func _rally_unit(regiment: Node) -> void:
	## Apply rally effect to a single unit.
	if regiment.unit_morale:
		regiment.unit_morale.rally()
	else:
		# Fallback: directly set morale and state
		regiment.current_morale = clampf(regiment.current_morale + RALLY_MORALE_BOOST, 0.0, 100.0)
		regiment.set_state(regiment.State.RALLYING)
		BattleSignals.regiment_rallied.emit(regiment)

# =============================================================================
# TICK
# =============================================================================

func tick(delta: float) -> void:
	## Update cooldown.
	if cooldown > 0.0:
		cooldown = maxf(0.0, cooldown - delta)

# =============================================================================
# QUERIES
# =============================================================================

func get_cooldown() -> float:
	## Returns remaining cooldown in seconds.
	return cooldown


func get_cooldown_percent() -> float:
	## Returns cooldown as 0.0-1.0 (0 = ready, 1 = full cooldown).
	return cooldown / COOLDOWN_DURATION


func is_ready() -> bool:
	## Returns true if ability is ready to use.
	return can_use()


func is_active() -> bool:
	## Returns true if general is alive.
	return _is_active
