class_name StanceType
extends RefCounted

## Player-accessible unit stances.
## Controls automatic behavior when not given direct orders.

enum Type {
	AGGRESSIVE,   # Pursue enemies, auto-engage threats
	DEFENSIVE,    # Hold position, engage only in range
	HOLD_GROUND,  # Stay put, don't move, fight in place
	SKIRMISH,     # Maintain distance, use ranged, retreat if charged
	GUARD,        # Protect a specific unit
}

# Hotkey mappings
const HOTKEYS := {
	Type.AGGRESSIVE: KEY_Z,
	Type.DEFENSIVE: KEY_X,
	Type.HOLD_GROUND: KEY_C,
	Type.SKIRMISH: KEY_V,
}

# Display names
const NAMES := {
	Type.AGGRESSIVE: "Aggressive",
	Type.DEFENSIVE: "Defensive",
	Type.HOLD_GROUND: "Hold Ground",
	Type.SKIRMISH: "Skirmish",
	Type.GUARD: "Guard",
}

# Icons (placeholder paths)
const ICONS := {
	Type.AGGRESSIVE: "res://assets/ui/stance_aggressive.png",
	Type.DEFENSIVE: "res://assets/ui/stance_defensive.png",
	Type.HOLD_GROUND: "res://assets/ui/stance_hold.png",
	Type.SKIRMISH: "res://assets/ui/stance_skirmish.png",
	Type.GUARD: "res://assets/ui/stance_guard.png",
}

static func get_stance_name(stance: Type) -> String:
	return NAMES.get(stance, "Unknown")

static func get_hotkey(stance: Type) -> int:
	return HOTKEYS.get(stance, 0)
