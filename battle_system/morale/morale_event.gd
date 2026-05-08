class_name MoraleEvent
extends RefCounted

## Data class representing a morale-affecting event.
## Passed to MoraleComponent.apply_event() for one-time effects,
## or used as source identifier for continuous modifiers.

# =============================================================================
# ENUMS
# =============================================================================

enum Source {
	# Combat deaths
	FRIEND_KILLED,
	FRIEND_KILLED_CLOSE,
	OFFICER_KILLED,
	GENERAL_KILLED,

	# Charges and attacks
	CAVALRY_CHARGE,
	INFANTRY_CHARGE,
	FLANK_ATTACK,
	REAR_ATTACK,

	# Positive combat events
	KILL_ENEMY,
	ENEMY_ROUTED,
	VICTORY_CHEER,
	REINFORCEMENTS,

	# Continuous negative
	FLANKED,
	SURROUNDED,
	OUTNUMBERED,
	UNDER_FIRE,
	ENEMY_NEARBY,
	FRIENDLY_FIRE,

	# Continuous positive
	GENERAL_AURA,
	OFFICER_AURA,
	WINNING,
	HIGH_GROUND,
	BATTLE_TIDE,  # Momentum modifier from BattleTide system
	NEARBY_ALLIES,  # Supported by nearby friendly units

	# Territory modifiers (DEI-inspired)
	FRIENDLY_TERRITORY,
	ENEMY_TERRITORY,

	# Unit type modifiers (DEI-inspired)
	UNIT_TYPE_BONUS,
	UNIT_TYPE_PENALTY,

	# Recovery
	NATURAL_RECOVERY,
	RALLY_RECOVERY,

	# Custom/generic
	CUSTOM,
}

enum State {
	STEADY,      # 70+, full effectiveness
	WAVERING,    # 40-70, slightly reduced
	SHAKEN,      # 20-40, significantly impaired
	BROKEN,      # <20, flee/cower
}

# =============================================================================
# PROPERTIES
# =============================================================================

var source: Source = Source.CUSTOM
var magnitude: float = 0.0
var origin_position: Vector3 = Vector3.ZERO
var source_unit: Node = null  # Optional: the unit that caused this event

# =============================================================================
# CONSTRUCTORS
# =============================================================================

func _init(p_source: Source = Source.CUSTOM, p_magnitude: float = 0.0, p_origin: Vector3 = Vector3.ZERO, p_source_unit: Node = null) -> void:
	source = p_source
	magnitude = p_magnitude
	origin_position = p_origin
	source_unit = p_source_unit


static func create(p_source: Source, p_magnitude: float, p_origin: Vector3 = Vector3.ZERO) -> MoraleEvent:
	## Factory method for creating morale events.
	var event: MoraleEvent = MoraleEvent.new()
	event.source = p_source
	event.magnitude = p_magnitude
	event.origin_position = p_origin
	return event


static func friend_killed(position: Vector3, close: bool = false) -> MoraleEvent:
	## Factory for friend death events.
	if close:
		return create(Source.FRIEND_KILLED_CLOSE, MoraleConstants.EVENT_FRIEND_KILLED_CLOSE, position)
	return create(Source.FRIEND_KILLED, MoraleConstants.EVENT_FRIEND_KILLED, position)


static func cavalry_charge(cavalry_position: Vector3) -> MoraleEvent:
	## Factory for cavalry charge shock.
	return create(Source.CAVALRY_CHARGE, MoraleConstants.EVENT_CAVALRY_CHARGE, cavalry_position)


static func infantry_charge(charger_position: Vector3) -> MoraleEvent:
	## Factory for infantry charge.
	return create(Source.INFANTRY_CHARGE, MoraleConstants.EVENT_INFANTRY_CHARGE, charger_position)


static func flank_attack(attacker_position: Vector3) -> MoraleEvent:
	## Factory for flank attack.
	return create(Source.FLANK_ATTACK, MoraleConstants.EVENT_FLANK_ATTACK, attacker_position)


static func rear_attack(attacker_position: Vector3) -> MoraleEvent:
	## Factory for rear attack.
	return create(Source.REAR_ATTACK, MoraleConstants.EVENT_REAR_ATTACK, attacker_position)


static func kill_enemy(victim_position: Vector3) -> MoraleEvent:
	## Factory for killing an enemy (morale boost).
	return create(Source.KILL_ENEMY, MoraleConstants.EVENT_KILL_ENEMY, victim_position)


static func enemy_routed(routed_unit_position: Vector3) -> MoraleEvent:
	## Factory for nearby enemy routing.
	return create(Source.ENEMY_ROUTED, MoraleConstants.EVENT_ENEMY_ROUTED, routed_unit_position)


static func officer_killed(officer_position: Vector3) -> MoraleEvent:
	## Factory for regiment leader death.
	return create(Source.OFFICER_KILLED, MoraleConstants.EVENT_OFFICER_KILLED, officer_position)


static func general_killed(general_position: Vector3) -> MoraleEvent:
	## Factory for army general death.
	return create(Source.GENERAL_KILLED, MoraleConstants.EVENT_GENERAL_KILLED, general_position)

# =============================================================================
# UTILITY
# =============================================================================

func is_positive() -> bool:
	## Returns true if this event improves morale.
	return magnitude > 0.0


func is_negative() -> bool:
	## Returns true if this event damages morale.
	return magnitude < 0.0


static func get_source_name(src: Source) -> String:
	## Returns human-readable name for a source.
	match src:
		Source.FRIEND_KILLED: return "Friend Killed"
		Source.FRIEND_KILLED_CLOSE: return "Close Friend Killed"
		Source.OFFICER_KILLED: return "Officer Killed"
		Source.GENERAL_KILLED: return "General Killed"
		Source.CAVALRY_CHARGE: return "Cavalry Charge"
		Source.INFANTRY_CHARGE: return "Infantry Charge"
		Source.FLANK_ATTACK: return "Flanked"
		Source.REAR_ATTACK: return "Rear Attack"
		Source.KILL_ENEMY: return "Killed Enemy"
		Source.ENEMY_ROUTED: return "Enemy Routed"
		Source.VICTORY_CHEER: return "Victory Cheer"
		Source.REINFORCEMENTS: return "Reinforcements"
		Source.FLANKED: return "Being Flanked"
		Source.SURROUNDED: return "Surrounded"
		Source.OUTNUMBERED: return "Outnumbered"
		Source.UNDER_FIRE: return "Under Fire"
		Source.ENEMY_NEARBY: return "Enemy Nearby"
		Source.FRIENDLY_FIRE: return "Friendly Fire"
		Source.GENERAL_AURA: return "General Nearby"
		Source.OFFICER_AURA: return "Officer Nearby"
		Source.WINNING: return "Winning"
		Source.HIGH_GROUND: return "High Ground"
		Source.NEARBY_ALLIES: return "Allied Support"
		Source.FRIENDLY_TERRITORY: return "Home Territory"
		Source.ENEMY_TERRITORY: return "Enemy Territory"
		Source.UNIT_TYPE_BONUS: return "Unit Discipline"
		Source.UNIT_TYPE_PENALTY: return "Out of Element"
		Source.NATURAL_RECOVERY: return "Recovery"
		Source.RALLY_RECOVERY: return "Rallying"
		Source.CUSTOM: return "Custom"
		_: return "Unknown"
