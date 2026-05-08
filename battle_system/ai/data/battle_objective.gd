class_name BattleObjective
extends Resource

## Per-side battle objective. Set by the campaign-to-battle bridge (or hardcoded
## for skirmish), consumed by GeneralAI to influence play scoring.
##
## Attacker/defender asymmetry is NOT a single boolean — it's a configuration of
## these fields. A "siege defender" is HOLD_GROUND with no time pressure. A
## "raiding attacker" is BREAKTHROUGH with high time pressure. A normal field
## battle for both sides is ANNIHILATE. Etc.

enum Type {
	ANNIHILATE,      # Default: destroy the enemy. No time pressure, no special positioning.
	HOLD_GROUND,     # Defender: hold a position, win by survival/timer.
	BREAKTHROUGH,    # Attacker: must reach a point or destroy a key target. Time pressure.
	CAPTURE_POINTS,  # Hold/take specific zones. (Reserved for future siege work.)
	ESCORT,          # Protect a moving target. (Reserved.)
	RAID,            # Hit and run. Goal is damage dealt, not annihilation.
}

## What kind of objective this is.
@export var type: Type = Type.ANNIHILATE

## Position to hold (used by HOLD_GROUND). World-space, Y-flat.
@export var hold_position: Vector3 = Vector3.ZERO

## Maximum acceptable distance from hold_position for HOLD_GROUND.
## Defenders that drift further get pulled back.
@export var hold_radius: float = 30.0

## Time pressure in seconds. -1 = unlimited (no pressure).
## Attackers with time_limit_sec > 0 get progressively more aggressive
## as the timer winds down.
@export var time_limit_sec: float = -1.0

## When this objective was created (set automatically). Used to compute
## remaining time. Initialized to 0; GeneralAI sets it on first tick.
var start_time_sec: float = 0.0


## Returns 0.0 (no pressure) to 1.0 (out of time).
## Always 0.0 for objectives without a time limit.
func get_time_pressure(now_sec: float) -> float:
	if time_limit_sec <= 0.0:
		return 0.0
	if start_time_sec <= 0.0:
		# Not started yet
		return 0.0
	var elapsed: float = now_sec - start_time_sec
	return clampf(elapsed / time_limit_sec, 0.0, 1.0)


## Convenience: "is this a defending side?"
func is_defender() -> bool:
	return type == Type.HOLD_GROUND or type == Type.CAPTURE_POINTS or type == Type.ESCORT


## Convenience: "is this an attacking side?"
func is_attacker() -> bool:
	return type == Type.BREAKTHROUGH or type == Type.RAID


## Default attacker objective for use when no explicit objective is set.
static func default_attacker() -> Resource:
	var script := load("res://battle_system/ai/data/battle_objective.gd")
	var obj = script.new()
	obj.type = Type.BREAKTHROUGH
	return obj


## Default defender objective for use when no explicit objective is set.
static func default_defender() -> Resource:
	var script := load("res://battle_system/ai/data/battle_objective.gd")
	var obj = script.new()
	obj.type = Type.HOLD_GROUND
	return obj


## Default skirmish objective (both sides ANNIHILATE — current behavior).
static func default_skirmish() -> Resource:
	var script := load("res://battle_system/ai/data/battle_objective.gd")
	return script.new()
