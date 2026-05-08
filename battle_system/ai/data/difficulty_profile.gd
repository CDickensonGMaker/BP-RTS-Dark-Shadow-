extends Resource

## Calibration Difficulty Profile for BattleDebug Agent Testing
## NOTE: No class_name to avoid conflict with main DifficultyProfile in systems/
## Access via preload: const Profile = preload("res://battle_system/ai/data/difficulty_profile.gd")
##
## Defines asymmetric damage and behavior multipliers for testing

# Self-reference for static factory methods
const _Self = preload("res://battle_system/ai/data/difficulty_profile.gd")
## the difficulty system. The agent uses these to verify that:
## - Easy mode gives players a significant advantage
## - Normal mode is roughly fair (50/50 win rate in mirror matchups)
## - Hard mode gives AI an advantage
## - Iron Man mode is brutally unfair
##
## Usage:
##   var profile = DifficultyProfile.normal()
##   CombatManager.set_difficulty_profile(profile)
##
## Or for calibration testing:
##   for level in DifficultyProfile.Level.values():
##       var profile = DifficultyProfile.from_level(level)
##       run_calibration_battles(profile)

# =============================================================================
# DIFFICULTY LEVELS
# =============================================================================

enum Level {
	EASY = 0,       # Player-friendly, forgiving
	NORMAL = 1,     # Balanced, fair
	HARD = 2,       # Challenging
	VERY_HARD = 3,  # Punishing
	IRON_MAN = 4    # Brutal, AI cheats
}

# =============================================================================
# PROPERTIES
# =============================================================================

## Current difficulty level
@export var level: Level = Level.NORMAL

## Display name for this difficulty
@export var display_name: String = "Normal"

# --- Damage Multipliers ---

## Multiplier for damage dealt BY AI units to player units
@export_range(0.5, 2.0) var ai_damage_dealt_mult: float = 1.0

## Multiplier for damage dealt BY player units to AI units
@export_range(0.5, 2.0) var player_damage_dealt_mult: float = 1.0

# --- AI Behavior Modifiers ---

## AI aggression multiplier (affects attack frequency and target selection)
@export_range(0.5, 2.0) var ai_aggression_mult: float = 1.0

## AI flanking skill (0.0 = never flanks, 1.0 = perfect flanking)
@export_range(0.0, 1.5) var ai_flanking_skill: float = 1.0

## AI reaction speed multiplier (lower = faster reactions)
@export_range(0.5, 2.0) var ai_reaction_mult: float = 1.0

# --- Player Modifiers ---

## Player morale modifier (added to player unit morale)
@export_range(-20.0, 20.0) var player_morale_bonus: float = 0.0

## Player unit charge bonus multiplier
@export_range(0.5, 2.0) var player_charge_mult: float = 1.0

# --- Global Modifiers ---

## Battle duration multiplier (affects fatigue and pacing)
@export_range(0.5, 2.0) var battle_duration_mult: float = 1.0

# =============================================================================
# STATIC FACTORY METHODS
# =============================================================================

static func from_level(lvl: Level) -> Resource:
	"""Create a DifficultyProfile from a level enum."""
	match lvl:
		Level.EASY:
			return easy()
		Level.NORMAL:
			return normal()
		Level.HARD:
			return hard()
		Level.VERY_HARD:
			return very_hard()
		Level.IRON_MAN:
			return iron_man()
		_:
			return normal()


static func easy() -> Resource:
	"""Easy mode: Player advantage, AI is sluggish and weak.

	Expected win rate in mirror matchup: ~80%+ for player
	"""
	var p := _Self.new()
	p.level = Level.EASY
	p.display_name = "Easy"

	# Player deals more damage, takes less
	p.ai_damage_dealt_mult = 0.75
	p.player_damage_dealt_mult = 1.25

	# AI is slow and doesn't flank well
	p.ai_aggression_mult = 0.7
	p.ai_flanking_skill = 0.5
	p.ai_reaction_mult = 1.5

	# Player morale advantage
	p.player_morale_bonus = 15.0
	p.player_charge_mult = 1.2

	return p


static func normal() -> Resource:
	"""Normal mode: Balanced gameplay.

	Expected win rate in mirror matchup: ~50% for player
	"""
	var p := _Self.new()
	p.level = Level.NORMAL
	p.display_name = "Normal"

	# Everything at 1.0 (fair)
	p.ai_damage_dealt_mult = 1.0
	p.player_damage_dealt_mult = 1.0
	p.ai_aggression_mult = 1.0
	p.ai_flanking_skill = 1.0
	p.ai_reaction_mult = 1.0
	p.player_morale_bonus = 0.0
	p.player_charge_mult = 1.0

	return p


static func hard() -> Resource:
	"""Hard mode: AI has advantage.

	Expected win rate in mirror matchup: ~35-40% for player
	"""
	var p := _Self.new()
	p.level = Level.HARD
	p.display_name = "Hard"

	# AI deals slightly more damage
	p.ai_damage_dealt_mult = 1.15
	p.player_damage_dealt_mult = 0.95

	# AI is more aggressive and skilled
	p.ai_aggression_mult = 1.2
	p.ai_flanking_skill = 1.2
	p.ai_reaction_mult = 0.8

	# Player has slight morale disadvantage
	p.player_morale_bonus = -5.0
	p.player_charge_mult = 1.0

	return p


static func very_hard() -> Resource:
	"""Very Hard mode: Significant AI advantage.

	Expected win rate in mirror matchup: ~20-25% for player
	"""
	var p := _Self.new()
	p.level = Level.VERY_HARD
	p.display_name = "Very Hard"

	# AI deals more damage, player deals less
	p.ai_damage_dealt_mult = 1.25
	p.player_damage_dealt_mult = 0.85

	# AI is very aggressive and skilled
	p.ai_aggression_mult = 1.4
	p.ai_flanking_skill = 1.3
	p.ai_reaction_mult = 0.7

	# Player morale disadvantage
	p.player_morale_bonus = -10.0
	p.player_charge_mult = 0.9

	return p


static func iron_man() -> Resource:
	"""Iron Man mode: Brutal difficulty, AI cheats.

	Expected win rate in mirror matchup: ~15-20% for player
	Requires near-perfect play and favorable matchups to win.
	"""
	var p := _Self.new()
	p.level = Level.IRON_MAN
	p.display_name = "Iron Man"

	# AI deals significantly more damage
	p.ai_damage_dealt_mult = 1.4
	p.player_damage_dealt_mult = 0.75

	# AI is extremely aggressive and skilled
	p.ai_aggression_mult = 1.5
	p.ai_flanking_skill = 1.5
	p.ai_reaction_mult = 0.6

	# Significant player morale disadvantage
	p.player_morale_bonus = -15.0
	p.player_charge_mult = 0.85

	# Battles feel longer (more attrition)
	p.battle_duration_mult = 1.2

	return p


# =============================================================================
# CALIBRATION TARGETS
# =============================================================================

## Expected player win rates for calibration validation
const CALIBRATION_TARGETS: Dictionary = {
	Level.EASY: { "min": 0.75, "max": 0.95, "target": 0.85 },
	Level.NORMAL: { "min": 0.45, "max": 0.55, "target": 0.50 },
	Level.HARD: { "min": 0.30, "max": 0.45, "target": 0.38 },
	Level.VERY_HARD: { "min": 0.18, "max": 0.30, "target": 0.25 },
	Level.IRON_MAN: { "min": 0.10, "max": 0.22, "target": 0.17 },
}

func get_calibration_target() -> Dictionary:
	"""Get the expected win rate range for this difficulty level."""
	return CALIBRATION_TARGETS.get(level, CALIBRATION_TARGETS[Level.NORMAL])


func is_calibrated(actual_win_rate: float) -> bool:
	"""Check if actual win rate is within expected range."""
	var target := get_calibration_target()
	return actual_win_rate >= target.min and actual_win_rate <= target.max


# =============================================================================
# UTILITY
# =============================================================================

func get_effective_damage(base_damage: int, is_player_attacking: bool) -> int:
	"""Calculate effective damage with difficulty modifiers applied."""
	var mult: float = player_damage_dealt_mult if is_player_attacking else ai_damage_dealt_mult
	return int(round(float(base_damage) * mult))


func to_dict() -> Dictionary:
	"""Export profile to dictionary for JSON serialization."""
	return {
		"level": level,
		"display_name": display_name,
		"ai_damage_dealt_mult": ai_damage_dealt_mult,
		"player_damage_dealt_mult": player_damage_dealt_mult,
		"ai_aggression_mult": ai_aggression_mult,
		"ai_flanking_skill": ai_flanking_skill,
		"ai_reaction_mult": ai_reaction_mult,
		"player_morale_bonus": player_morale_bonus,
		"player_charge_mult": player_charge_mult,
		"battle_duration_mult": battle_duration_mult,
	}


static func from_dict(data: Dictionary) -> Resource:
	"""Create profile from dictionary."""
	var p := _Self.new()
	p.level = data.get("level", Level.NORMAL)
	p.display_name = data.get("display_name", "Custom")
	p.ai_damage_dealt_mult = data.get("ai_damage_dealt_mult", 1.0)
	p.player_damage_dealt_mult = data.get("player_damage_dealt_mult", 1.0)
	p.ai_aggression_mult = data.get("ai_aggression_mult", 1.0)
	p.ai_flanking_skill = data.get("ai_flanking_skill", 1.0)
	p.ai_reaction_mult = data.get("ai_reaction_mult", 1.0)
	p.player_morale_bonus = data.get("player_morale_bonus", 0.0)
	p.player_charge_mult = data.get("player_charge_mult", 1.0)
	p.battle_duration_mult = data.get("battle_duration_mult", 1.0)
	return p
