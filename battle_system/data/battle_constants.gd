class_name BattleConstants
extends RefCounted

## Central combat constants for Dark Shadows RTS.
##
## This file documents ALL game balance values for easy tuning.
## Based on Total War mechanics: morale, flanking, charges, hit chance.
##
## IMPORTANT: These values are carefully tuned. Changes affect game balance.
## See: WIP/dark_shadows_bible.md for design rationale.
##
## References:
## - Total War Morale: https://totalwar.fandom.com/wiki/Morale
## - Total War Flanking: https://totalwarwarhammer.fandom.com/wiki/Flanking
## - Total War Charge: https://totalwarwarhammer.fandom.com/wiki/Charge_Bonus

# =============================================================================
# COMBAT TICK TIMING
# =============================================================================
## How often melee combat resolves (seconds). Lower = smoother damage, higher CPU.
const MELEE_TICK_RATE: float = 0.2

## Damage scale factor per tick. Should match tick rate ratio.
## Example: 0.2s tick / 0.5s base = 0.4 scale
const MELEE_DAMAGE_SCALE: float = 0.4

## Base damage multiplier for all combat (affects time-to-kill).
const COMBAT_DAMAGE_MULTIPLIER: float = 0.50

## Staggered update buckets (process 1/N combats per frame).
const UPDATE_BUCKET_COUNT: int = 4

# =============================================================================
# FLANKING SYSTEM (Total War style defense reduction)
# =============================================================================
## Angle thresholds (degrees from defender's facing)
## 0-45 = Front, 45-135 = Flank, 135-180 = Rear
const FLANK_REAR_ANGLE: float = 135.0
const FLANK_SIDE_ANGLE: float = 45.0

## Damage multipliers by attack direction
## These represent effective defense reduction:
## - Flank (0.6x defense) = 1.5x damage
## - Rear (0.25x defense) = 2.0x damage
const FLANK_FRONT_DAMAGE_MULT: float = 1.0
const FLANK_SIDE_DAMAGE_MULT: float = 1.5
const FLANK_REAR_DAMAGE_MULT: float = 2.0

## Morale penalties for being attacked from different angles
const FLANK_SIDE_MORALE_MULT: float = 1.25
const FLANK_REAR_MORALE_MULT: float = 1.5

# =============================================================================
# CHARGE SYSTEM (Total War Warhammer style)
# =============================================================================
## Charge bonus decays linearly over this duration (seconds)
const CHARGE_DECAY_DURATION: float = 10.0

## Time before charge bonus starts decaying
const CHARGE_BONUS_DURATION: float = 3.0

## Percentage of charge impact that bypasses armor
const CHARGE_AP_RATIO: float = 0.7

## Charge impact morale damage ratio
const CHARGE_MORALE_RATIO: float = 0.5

## Knockback thresholds (for large units charging infantry)
const KNOCKBACK_MASS_THRESHOLD: float = 1.5
const KNOCKBACK_BASE_DISTANCE: float = 5.0
const KNOCKBACK_CASUALTY_THRESHOLD: int = 3
const KNOCKBACK_SCATTER_MULTIPLIER: float = 1.5

# =============================================================================
# HIT CHANCE (Warhammer Tabletop style)
# =============================================================================
## To Hit table based on Weapon Skill difference
## Format: Attacker WS vs Defender WS -> Hit Chance
const TO_HIT_EQUAL: float = 0.50        # WS equal: 4+ roll (50%)
const TO_HIT_HIGHER: float = 0.66       # WS 1-3 higher: 3+ roll (66%)
const TO_HIT_MUCH_HIGHER: float = 0.83  # WS 4+ higher: 2+ roll (83%)
const TO_HIT_LOWER: float = 0.33        # WS 1-3 lower: 5+ roll (33%)
const TO_HIT_MUCH_LOWER: float = 0.17   # WS 4+ lower: 6+ roll (17%)

## To Wound table based on Strength vs Defense difference
const TO_WOUND_EQUAL: float = 0.50
const TO_WOUND_HIGHER: float = 0.66
const TO_WOUND_MUCH_HIGHER: float = 0.83
const TO_WOUND_LOWER: float = 0.33
const TO_WOUND_MUCH_LOWER: float = 0.17

## Armor save calculation
const ARMOR_SAVE_PER_POINT: float = 0.033  # ~3.3% per armor point
const MAX_ARMOR_SAVE: float = 0.66         # Maximum 66% save (3+ roll)

# =============================================================================
# MORALE SYSTEM (Total War states)
# =============================================================================
## Morale states (values are thresholds out of 100)
## eager(100) -> confident(80) -> steady(60) -> shaken(40) -> wavering(20) -> broken(0)
const MORALE_CONFIDENT: float = 80.0
const MORALE_STEADY: float = 60.0
const MORALE_SHAKEN: float = 40.0
const MORALE_WAVERING: float = 20.0
const MORALE_BROKEN: float = 0.0

## Morale damage per casualty in melee
const MELEE_MORALE_PER_CASUALTY: float = 0.5

## Morale shock threshold (casualties as % of unit in short time)
## 20% casualties in 4 seconds triggers massive morale penalty
const MORALE_SHOCK_THRESHOLD: float = 0.20
const MORALE_SHOCK_WINDOW: float = 4.0

## Key morale modifiers (from Total War research)
const MORALE_CHARGE_BONUS: float = 5.0
const MORALE_FLANKS_SECURE: float = 4.0
const MORALE_NEAR_GENERAL: float = 4.0
const MORALE_UNDER_ARTILLERY: float = -4.0
const MORALE_FLANK_ATTACK: float = -3.0
const MORALE_REAR_ATTACK: float = -5.0

## Fire damage panic effect
const FIRE_PANIC_CHANCE: float = 0.15
const FIRE_PANIC_MORALE_DAMAGE: float = 8.0

# =============================================================================
# RANGED COMBAT
# =============================================================================
## High ground bonus for ranged attacks
const RANGED_HIGH_GROUND_BONUS: float = 1.15

## Low ground penalty for ranged attacks
const RANGED_LOW_GROUND_PENALTY: float = 0.85

## Morale damage ratio for ranged hits
const RANGED_MORALE_RATIO: float = 0.3

## Friendly fire chance when shooting into melee
const FRIENDLY_FIRE_CHANCE: float = 0.15

# =============================================================================
# HEIGHT MODIFIERS
# =============================================================================
## Height difference threshold for advantage/disadvantage (units)
const HEIGHT_ADVANTAGE_THRESHOLD: float = 1.5

## Melee attack bonus when on higher ground
const MELEE_HEIGHT_BONUS: float = 0.15

## Melee attack penalty when on lower ground
const MELEE_HEIGHT_PENALTY: float = 0.15

## WS bonus for defending uphill
const SLOPE_WS_BONUS: int = 2

# =============================================================================
# FRONT RANK LIMITING (Historical realism)
# =============================================================================
## Only front rank soldiers can engage. Support rank fights at reduced strength.
const DEFAULT_FILES_PER_RANK: int = 8
const SUPPORT_RANK_MULTIPLIER: float = 0.5

## Generals fight as multiple elite soldiers
const GENERAL_EFFECTIVE_SOLDIERS: int = 10

# =============================================================================
# POISON/HAZARD EFFECTS
# =============================================================================
const POISON_HAZARD_DURATION: float = 4.0
const POISON_HAZARD_DPS: float = 2.0
const POISON_HAZARD_RADIUS: float = 2.0

# =============================================================================
# UNIT TYPE MATCHUP (Rock-Paper-Scissors)
# =============================================================================
## These are base multipliers for combat effectiveness.
## Actual implementation in matchup_calculator.gd
const SPEAR_VS_CAVALRY_BONUS: float = 1.5
const CAVALRY_VS_RANGED_BONUS: float = 1.3
const RANGED_VS_INFANTRY_BONUS: float = 1.1

## Flanking disorder reduces counter-attack effectiveness
const FLANK_DISORDER_ATTACK_MULT: float = 0.65
const REAR_DISORDER_ATTACK_MULT: float = 0.4
const FLANK_DISORDER_MATCHUP_MULT: float = 0.6
const REAR_DISORDER_MATCHUP_MULT: float = 0.3
