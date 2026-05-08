## GeneralTrait - Resource class for campaign general personality traits.
## Affects battle mechanics via BattleModifiers autoload.
## Part of Phase 9 General Trait System.
class_name GeneralTrait
extends Resource

enum Category {
	LEADERSHIP,   # Morale and aura effects
	TACTICAL,     # Combat bonuses and penalties
	HATRED,       # Bonuses vs specific enemy types
	COMMAND,      # Army-wide effects
	PERSONALITY,  # Behavioral modifiers
}

# === IDENTIFICATION ===
@export var trait_id: String = ""
@export var trait_name: String = ""
@export_multiline var description: String = ""
@export var category: Category = Category.LEADERSHIP
@export var icon: Texture2D

# === CONFLICTS ===
## Trait IDs that cannot coexist with this trait.
@export var conflicts_with: Array[String] = []

# === UNLOCK REQUIREMENTS ===
## Number of battles required to unlock this trait.
@export var unlock_battles: int = 0
## Number of kills required to unlock this trait.
@export var unlock_kills: int = 0
## If true, this trait must be unlocked via progression (not available at character creation).
@export var is_unlockable: bool = false

# === SUB-CHOICES (SPECIALIZATIONS) ===
## If true, player must choose a specialization when selecting this trait.
@export var has_subchoices: bool = false
## Names of available sub-choices.
@export var subchoice_names: Array[String] = []
## Descriptions for each sub-choice.
@export var subchoice_descriptions: Array[String] = []

# === COMBAT MODIFIERS ===
## Melee attack modifier (+/- percentage, e.g., 0.1 = +10%).
@export var melee_attack_mod: float = 0.0
## Melee defense modifier (+/- percentage).
@export var melee_defense_mod: float = 0.0
## Ranged attack/accuracy modifier (+/- percentage).
@export var ranged_attack_mod: float = 0.0
## Charge bonus modifier (+/- percentage).
@export var charge_bonus_mod: float = 0.0

# === MORALE MODIFIERS ===
## Flat bonus added to general's morale aura.
@export var morale_aura_bonus: float = 0.0
## Rally DC modifier (negative = easier to rally).
@export var rally_success_mod: float = 0.0
## Rout threshold modifier (higher = more resistant to routing).
@export var rout_threshold_mod: float = 0.0

# === ARMY-WIDE MODIFIERS ===
## Movement speed modifier (+/- percentage).
@export var army_speed_mod: float = 0.0
## Stamina/fatigue resistance modifier (+/- percentage).
@export var army_stamina_mod: float = 0.0
## Reinforcement arrival speed modifier (+/- percentage).
@export var reinforcement_speed_mod: float = 0.0

# === HATRED MODIFIERS ===
## Unit type names this trait provides bonus against (e.g., "Orc", "Undead").
@export var hatred_targets: Array[String] = []
## Attack bonus against hatred targets (+/- percentage).
@export var hatred_attack_bonus: float = 0.0
## Morale bonus when fighting hatred targets.
@export var hatred_morale_bonus: float = 0.0

# === PERSONALITY MODIFIERS (AI behavior) ===
## Aggression modifier for AI generals (affects attack priority).
@export var aggression_mod: float = 0.0
## Caution modifier for AI generals (affects defensive behavior).
@export var caution_mod: float = 0.0
## Opportunism modifier for AI generals (affects flanking/pursuit priority).
@export var opportunism_mod: float = 0.0

# === SUB-CHOICE SPECIFIC MODIFIERS ===
## Additional modifiers applied when specific sub-choice is selected.
## Format: Array of Dictionaries, one per sub-choice.
## Each dict has modifier names as keys (e.g., "melee_attack_mod": 0.1).
@export var subchoice_modifiers: Array[Dictionary] = []


## Check if this trait conflicts with another.
func conflicts_with_trait(other: GeneralTrait) -> bool:
	if not other:
		return false
	return other.trait_id in conflicts_with or trait_id in other.conflicts_with


## Get combined modifier value for a given modifier name, including sub-choice bonus.
## @param modifier_name: The name of the modifier (e.g., "melee_attack_mod").
## @param subchoice_index: The selected sub-choice index (-1 for no sub-choice).
func get_modifier(modifier_name: String, subchoice_index: int = -1) -> float:
	# Get base modifier value
	var base_value: float = 0.0
	if modifier_name in self:
		base_value = get(modifier_name)

	# Add sub-choice modifier if applicable
	if has_subchoices and subchoice_index >= 0 and subchoice_index < subchoice_modifiers.size():
		var sub_mods: Dictionary = subchoice_modifiers[subchoice_index]
		if modifier_name in sub_mods:
			base_value += sub_mods[modifier_name]

	return base_value


## Check if unlock requirements are met.
func can_unlock(battles_fought: int, total_kills: int) -> bool:
	if not is_unlockable:
		return true  # Always available if not unlockable
	return battles_fought >= unlock_battles and total_kills >= unlock_kills


## Get display name for a sub-choice.
func get_subchoice_name(index: int) -> String:
	if index >= 0 and index < subchoice_names.size():
		return subchoice_names[index]
	return ""


## Get description for a sub-choice.
func get_subchoice_description(index: int) -> String:
	if index >= 0 and index < subchoice_descriptions.size():
		return subchoice_descriptions[index]
	return ""
