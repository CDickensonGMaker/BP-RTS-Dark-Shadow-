class_name OrderType
extends Resource



enum Type {
	NONE,
	MOVE,
	ATTACK_MOVE,    # engage anything in path
	HOLD_POSITION,  # don't pursue, fight in place
	GUARD,          # protect a target unit
	SKIRMISH,       # ranged + fallback if engaged
	CHARGE,         # attack with charge bonus applied
	WITHDRAW        # disengage and move to point
}
