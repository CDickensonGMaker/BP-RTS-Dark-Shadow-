class_name MoraleConstants
extends RefCounted

## Centralized tuning values for the per-soldier morale system.
## All morale thresholds, event magnitudes, and timing constants live here.

# =============================================================================
# STATE THRESHOLDS
# =============================================================================
## Morale ranges 0-100. State determined by current morale value.
const STATE_STEADY_MIN: float = 70.0       # 70+ = steady, full effectiveness
const STATE_WAVERING_MIN: float = 40.0     # 40-70 = wavering, slightly reduced
const STATE_SHAKEN_MIN: float = 20.0       # 20-40 = shaken, significantly impaired
const STATE_BROKEN_MIN: float = 0.0        # <20 = broken, flee/cower

# Effectiveness multipliers per state
const EFFECTIVENESS_STEADY: float = 1.0
const EFFECTIVENESS_WAVERING: float = 0.9
const EFFECTIVENESS_SHAKEN: float = 0.75
const EFFECTIVENESS_BROKEN: float = 0.3

# =============================================================================
# ONE-TIME EVENT MAGNITUDES
# =============================================================================
## Applied once when the event occurs. Negative = morale loss.

# Combat events
const EVENT_FRIEND_KILLED: float = -3.0           # Nearby ally dies
const EVENT_FRIEND_KILLED_CLOSE: float = -5.0     # Very close ally dies (<3m)
const EVENT_OFFICER_KILLED: float = -15.0         # Regiment leader dies
const EVENT_GENERAL_KILLED: float = -25.0         # Army general dies

# Charge/shock events
const EVENT_CAVALRY_CHARGE: float = -12.0         # Charged by cavalry
const EVENT_INFANTRY_CHARGE: float = -6.0         # Charged by infantry
const EVENT_FLANK_ATTACK: float = -8.0            # Hit from flank
const EVENT_REAR_ATTACK: float = -15.0            # Hit from behind

# Positive events
const EVENT_KILL_ENEMY: float = 2.0               # Personally killed an enemy
const EVENT_ENEMY_ROUTED: float = 5.0             # Nearby enemy unit routs
const EVENT_VICTORY_CHEER: float = 8.0            # Commander ordered cheer
const EVENT_REINFORCEMENTS: float = 10.0          # Friendly reinforcements arrive

# =============================================================================
# CONTINUOUS MODIFIERS (per second)
# =============================================================================
## Applied every tick while condition is active.

# Negative continuous
const CONTINUOUS_FLANKED: float = -1.5            # Being flanked
const CONTINUOUS_SURROUNDED: float = -2.5         # Enemies on multiple sides
const CONTINUOUS_OUTNUMBERED: float = -0.8        # Significantly outnumbered locally
const CONTINUOUS_UNDER_FIRE: float = -0.5         # Taking ranged fire

# Positive continuous
const CONTINUOUS_GENERAL_AURA: float = 0.4        # Near friendly general
const CONTINUOUS_OFFICER_AURA: float = 0.2        # Near regiment leader
const CONTINUOUS_WINNING: float = 0.3             # Winning the current engagement
const CONTINUOUS_HIGH_GROUND: float = 0.15        # On elevated terrain

# Territory modifiers (DEI-inspired)
const CONTINUOUS_FRIENDLY_TERRITORY: float = 0.2  # +10% morale in friendly territory
const CONTINUOUS_ENEMY_TERRITORY: float = -0.2    # -10% morale in enemy territory

# Unit type morale modifiers (DEI-inspired)
const UNIT_TYPE_HEAVY_INFANTRY_SAVE: float = 0.05 # +5% morale save for heavy infantry
const UNIT_TYPE_RANGED_MELEE_PENALTY: float = -0.15 # -15% morale when ranged in melee
const UNIT_TYPE_CAVALRY_MORALE_BONUS: float = 0.1  # +10% morale for cavalry (mobile, can flee)
const UNIT_TYPE_ARTILLERY_VULNERABLE: float = -0.2 # -20% morale when artillery in melee

# Recovery
const CONTINUOUS_NATURAL_RECOVERY: float = 0.5    # Base recovery when safe
const CONTINUOUS_RALLY_RECOVERY: float = 1.5      # Recovery during active rally

# =============================================================================
# RALLY CONDITIONS
# =============================================================================
const RALLY_SAFETY_TIME: float = 5.0              # Seconds of safety before rally
const RALLY_MORALE_THRESHOLD: float = 30.0        # Min morale to attempt rally
const RALLY_SUCCESS_THRESHOLD: float = 40.0       # Morale needed to complete rally
const RALLY_DISTANCE_FROM_ENEMY: float = 20.0     # Min distance from enemies

# =============================================================================
# UNIT-LEVEL THRESHOLDS
# =============================================================================
const UNIT_ROUT_BROKEN_RATIO: float = 0.5         # 50%+ soldiers broken = unit routs
const UNIT_RALLY_BROKEN_RATIO: float = 0.25       # <25% broken = unit can rally
const UNIT_SHATTERED_RATIO: float = 0.8           # 80%+ broken = unit shattered (no rally)

# =============================================================================
# DISTANCE THRESHOLDS
# =============================================================================
const FRIEND_KILLED_RADIUS: float = 8.0           # Radius for friend death morale hit
const FRIEND_KILLED_CLOSE_RADIUS: float = 3.0     # Close friend death (stronger hit)
const GENERAL_AURA_RADIUS: float = 25.0           # General morale aura range
const OFFICER_AURA_RADIUS: float = 10.0           # Regiment leader aura range
const ENEMY_ROUT_BONUS_RADIUS: float = 15.0       # Range to receive enemy rout bonus

# =============================================================================
# TICK RATES
# =============================================================================
const MORALE_TICK_RATE: float = 0.25              # 4 Hz morale updates
const AURA_TICK_RATE: float = 1.0                 # 1 Hz aura recalculation

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

static func get_state_from_morale(morale: float) -> int:
	## Returns MoraleState enum value based on morale value.
	## Uses MoraleEvent.State enum (0=STEADY, 1=WAVERING, 2=SHAKEN, 3=BROKEN)
	if morale >= STATE_STEADY_MIN:
		return 0  # STEADY
	elif morale >= STATE_WAVERING_MIN:
		return 1  # WAVERING
	elif morale >= STATE_SHAKEN_MIN:
		return 2  # SHAKEN
	else:
		return 3  # BROKEN


static func get_effectiveness_for_state(state: int) -> float:
	## Returns combat effectiveness multiplier for given state.
	match state:
		0: return EFFECTIVENESS_STEADY
		1: return EFFECTIVENESS_WAVERING
		2: return EFFECTIVENESS_SHAKEN
		3: return EFFECTIVENESS_BROKEN
		_: return EFFECTIVENESS_STEADY
