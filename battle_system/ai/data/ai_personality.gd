class_name AIPersonality
extends Resource

## AI personality/difficulty settings.
## Controls how aggressive, reactive, and smart the AI behaves.
##
## Usage:
##   var personality = AIPersonality.new()
##   personality.aggression = 0.8  # Very aggressive
##   var general = GeneralAI.new(faction, personality)

# =============================================================================
# PERSONALITY TRAITS (0.0 to 1.0)
# =============================================================================

## How likely to attack vs defend
@export_range(0.0, 1.0) var aggression: float = 0.5

## How quickly AI reacts to threats
@export_range(0.0, 1.0) var reaction_speed: float = 0.5

## Willingness to attempt flanking maneuvers
@export_range(0.0, 1.0) var tactical_flexibility: float = 0.5

## Risk tolerance (0 = very cautious, 1 = reckless)
@export_range(0.0, 1.0) var risk_tolerance: float = 0.5

## How much to value preserving units
@export_range(0.0, 1.0) var unit_preservation: float = 0.5

## Willingness to concentrate forces
@export_range(0.0, 1.0) var focus_fire: float = 0.5

## How much to prioritize high-value targets
@export_range(0.0, 1.0) var target_priority: float = 0.5

## How aggressively to pursue routing enemies
@export_range(0.0, 1.0) var pursuit_aggression: float = 0.5

## How well the AI exploits battlefield opportunities
## Affects reactive plays like PunishOvercommit and ExploitLowMorale
@export_range(0.0, 1.0) var opportunism: float = 0.5

# =============================================================================
# DIFFICULTY MODIFIERS
# =============================================================================

## Reaction delay multiplier (higher = slower reactions)
@export_range(0.5, 2.0) var reaction_delay_mult: float = 1.0

## Target selection accuracy (lower = worse choices)
@export_range(0.0, 1.0) var targeting_accuracy: float = 1.0

## Morale resistance bonus (affects unit morale)
@export_range(0.0, 0.5) var morale_bonus: float = 0.0

## Combat stat multiplier
@export_range(0.8, 1.5) var stat_multiplier: float = 1.0

# =============================================================================
# PRESETS
# =============================================================================

static func easy() -> AIPersonality:
	## Create an easy AI opponent.
	var p: AIPersonality = AIPersonality.new()
	p.aggression = 0.3
	p.reaction_speed = 0.3
	p.tactical_flexibility = 0.2
	p.risk_tolerance = 0.3
	p.unit_preservation = 0.7
	p.focus_fire = 0.3
	p.target_priority = 0.3
	p.pursuit_aggression = 0.2
	p.opportunism = 0.2

	p.reaction_delay_mult = 1.5
	p.targeting_accuracy = 0.6
	p.morale_bonus = 0.0
	p.stat_multiplier = 0.9
	return p


static func normal() -> AIPersonality:
	## Create a normal difficulty AI.
	var p: AIPersonality = AIPersonality.new()
	p.aggression = 0.5
	p.reaction_speed = 0.5
	p.tactical_flexibility = 0.5
	p.risk_tolerance = 0.5
	p.unit_preservation = 0.5
	p.focus_fire = 0.5
	p.target_priority = 0.5
	p.pursuit_aggression = 0.5
	p.opportunism = 0.5

	p.reaction_delay_mult = 1.0
	p.targeting_accuracy = 0.8
	p.morale_bonus = 0.0
	p.stat_multiplier = 1.0
	return p


static func hard() -> AIPersonality:
	## Create a hard AI opponent.
	var p: AIPersonality = AIPersonality.new()
	p.aggression = 0.7
	p.reaction_speed = 0.7
	p.tactical_flexibility = 0.7
	p.risk_tolerance = 0.5
	p.unit_preservation = 0.4
	p.focus_fire = 0.7
	p.target_priority = 0.7
	p.pursuit_aggression = 0.7
	p.opportunism = 0.7

	p.reaction_delay_mult = 0.8
	p.targeting_accuracy = 0.95
	p.morale_bonus = 0.1
	p.stat_multiplier = 1.1
	return p


static func legendary() -> AIPersonality:
	## Create a legendary (cheating) AI opponent.
	var p: AIPersonality = AIPersonality.new()
	p.aggression = 0.8
	p.reaction_speed = 0.9
	p.tactical_flexibility = 0.9
	p.risk_tolerance = 0.6
	p.unit_preservation = 0.3
	p.focus_fire = 0.9
	p.target_priority = 0.9
	p.pursuit_aggression = 0.8
	p.opportunism = 0.9

	p.reaction_delay_mult = 0.6
	p.targeting_accuracy = 1.0
	p.morale_bonus = 0.2
	p.stat_multiplier = 1.25
	return p


static func defensive() -> AIPersonality:
	## Create a defensive-focused AI.
	var p: AIPersonality = AIPersonality.new()
	p.aggression = 0.2
	p.reaction_speed = 0.6
	p.tactical_flexibility = 0.4
	p.risk_tolerance = 0.2
	p.unit_preservation = 0.9
	p.focus_fire = 0.4
	p.target_priority = 0.5
	p.pursuit_aggression = 0.2
	p.opportunism = 0.4

	p.reaction_delay_mult = 1.0
	p.targeting_accuracy = 0.8
	p.morale_bonus = 0.15
	p.stat_multiplier = 1.0
	return p


static func aggressive() -> AIPersonality:
	## Create an aggressive AI.
	var p: AIPersonality = AIPersonality.new()
	p.aggression = 0.9
	p.reaction_speed = 0.8
	p.tactical_flexibility = 0.3
	p.risk_tolerance = 0.8
	p.unit_preservation = 0.2
	p.focus_fire = 0.8
	p.target_priority = 0.6
	p.pursuit_aggression = 0.9
	p.opportunism = 0.6

	p.reaction_delay_mult = 0.8
	p.targeting_accuracy = 0.7
	p.morale_bonus = 0.0
	p.stat_multiplier = 1.0
	return p

# =============================================================================
# UTILITY
# =============================================================================

func get_adjusted_tick_rate(base_rate: float) -> float:
	## Adjust tick rate based on reaction speed.
	return base_rate * reaction_delay_mult


func should_retreat(strength_ratio: float) -> bool:
	## Decide if unit should retreat based on personality.
	var threshold: float = 0.5 + (unit_preservation - risk_tolerance) * 0.3
	return strength_ratio < threshold


func get_target_score_modifier(target_type: String) -> float:
	## Get score modifier for target types based on personality.
	match target_type:
		"weak": return 1.0 + (1.0 - unit_preservation) * 0.3
		"routing": return 1.0 + pursuit_aggression * 0.5
		"high_value": return 1.0 + target_priority * 0.4
		"close": return 1.0 + aggression * 0.2
		_: return 1.0
