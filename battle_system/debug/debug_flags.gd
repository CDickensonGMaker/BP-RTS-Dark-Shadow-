extends Node

## Central debug-logging gate for Dark Shadows battle system.
## Wrap informational prints behind these flags.
## push_warning and push_error are independent and always fire.
##
## Usage:
##   if DebugFlags.ai_general:
##       print("[AI] GeneralAI selecting play...")
##
## Add to project.godot autoload:
##   DebugFlags="*res://battle_system/debug/debug_flags.gd"
##
## NOTE: Do NOT use class_name here - it conflicts with the autoload singleton name.

# =============================================================================
# DEBUG FLAGS
# =============================================================================

## GeneralAI play decisions, role assignments
@export var ai_general: bool = false

## Per-regiment CommanderAI tick details
@export var ai_commander: bool = false

## TaskFireRanged debug (was [AI-DEBUG] spam)
@export var ai_firing: bool = false

## Morale changes, cascade events, cap drift
@export var morale: bool = false

## Combat tick details, damage resolution
@export var combat: bool = false

## Flanking detection: log every flank/rear angle calculation
@export var flanking: bool = false

## Casualty tracker thresholds
@export var casualty: bool = false

## Battle start/end, setup info (keep on by default — useful, low-volume)
@export var battle_setup: bool = true

## Battle tide events
@export var tide: bool = false

## Movement and pathfinding
@export var movement: bool = false

## Spell casting and effects
@export var spells: bool = false
