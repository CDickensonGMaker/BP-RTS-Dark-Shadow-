## GeneralProfile - Stores traits and progression for a campaign general.
## Persists across battles and can be serialized for save/load.
## Part of Phase 9 General Trait System.
class_name GeneralProfile
extends Resource

# === COMMANDER RANK (Progression System) ===
## Ranks earned through battlefield experience. Stacks bonuses.
enum CommanderRank {
	UNTESTED,   # Starting rank - no bonuses
	VETERAN,    # 5+ battles: +5% defense, +5 morale aura
	PROVEN,     # 3+ victories: above + 10% rally, rout resistance
	BLOODIED,   # 50+ kills: above + 10% attack, -5 enemy morale
}

# Rank requirements
const VETERAN_BATTLES: int = 5
const PROVEN_VICTORIES: int = 3
const BLOODIED_KILLS: int = 50

# === IDENTIFICATION ===
@export var general_name: String = ""
@export var portrait: Texture2D

# === TRAITS ===
## Assigned personality traits (max 2).
@export var traits: Array[GeneralTrait] = []
## Active sub-choice index per trait. Key = trait_id, Value = subchoice index.
@export var active_subchoices: Dictionary = {}

# === COMMANDER RANK ===
@export var commander_rank: CommanderRank = CommanderRank.UNTESTED

# === PROGRESS TRACKING ===
@export var battles_fought: int = 0
@export var total_kills: int = 0
@export var victories: int = 0
@export var defeats: int = 0

# === UNLOCKED TRAITS ===
## Trait IDs that have been unlocked via progression (available for selection).
@export var unlocked_traits: Array[String] = []

# === EXPERIENCE SYSTEM ===
@export var experience: int = 0
@export var level: int = 1
const XP_PER_LEVEL: int = 100
const MAX_TRAITS: int = 2


## Add a trait to this general.
## Returns false if trait conflicts or max traits reached.
func add_trait(trait: GeneralTrait, subchoice: int = -1) -> bool:
	if not trait:
		return false

	# Check max traits
	if traits.size() >= MAX_TRAITS:
		push_warning("GeneralProfile: Cannot add trait, max traits (%d) reached" % MAX_TRAITS)
		return false

	# Check for conflicts
	if not can_add_trait(trait):
		push_warning("GeneralProfile: Cannot add trait %s, conflicts with existing trait" % trait.trait_id)
		return false

	# Check if already has this trait
	if has_trait(trait.trait_id):
		push_warning("GeneralProfile: Already has trait %s" % trait.trait_id)
		return false

	traits.append(trait)

	# Store sub-choice if applicable
	if trait.has_subchoices and subchoice >= 0:
		active_subchoices[trait.trait_id] = subchoice

	return true


## Remove a trait from this general.
func remove_trait(trait_id: String) -> bool:
	for i in traits.size():
		if traits[i].trait_id == trait_id:
			traits.remove_at(i)
			active_subchoices.erase(trait_id)
			return true
	return false


## Check if this general has a specific trait.
func has_trait(trait_id: String) -> bool:
	for t in traits:
		if t.trait_id == trait_id:
			return true
	return false


## Get a trait by ID.
func get_trait(trait_id: String) -> GeneralTrait:
	for t in traits:
		if t.trait_id == trait_id:
			return t
	return null


## Check if a trait can be added (no conflicts).
func can_add_trait(new_trait: GeneralTrait) -> bool:
	if not new_trait:
		return false

	# Check max traits
	if traits.size() >= MAX_TRAITS:
		return false

	# Check for conflicts
	for existing in traits:
		if existing.conflicts_with_trait(new_trait):
			return false

	return true


## Get the active sub-choice index for a trait.
func get_subchoice(trait_id: String) -> int:
	if trait_id in active_subchoices:
		return active_subchoices[trait_id]
	return -1


## Get combined modifier value across all traits.
## Sums up the modifier from each trait (with their active sub-choices).
func get_combined_modifier(modifier_name: String) -> float:
	var total: float = 0.0
	for t in traits:
		var subchoice: int = get_subchoice(t.trait_id)
		total += t.get_modifier(modifier_name, subchoice)
	return total


## Get all traits of a specific category.
func get_traits_by_category(category: GeneralTrait.Category) -> Array[GeneralTrait]:
	var result: Array[GeneralTrait] = []
	for t in traits:
		if t.category == category:
			result.append(t)
	return result


## Check if any trait provides hatred bonus against a target type (case-insensitive).
func has_hatred_against(target_type: String) -> bool:
	var target_lower: String = target_type.to_lower()
	for t in traits:
		for hatred_target in t.hatred_targets:
			if hatred_target.to_lower() == target_lower:
				return true
	return false


## Get hatred attack bonus against a specific target type (case-insensitive).
func get_hatred_attack_bonus(target_type: String) -> float:
	var target_lower: String = target_type.to_lower()
	var bonus: float = 0.0
	for t in traits:
		var subchoice: int = get_subchoice(t.trait_id)
		for hatred_target in t.hatred_targets:
			if hatred_target.to_lower() == target_lower:
				bonus += t.get_modifier("hatred_attack_bonus", subchoice)
				break  # Only apply once per trait
	return bonus


## Get hatred morale bonus against a specific target type (case-insensitive).
func get_hatred_morale_bonus(target_type: String) -> float:
	var target_lower: String = target_type.to_lower()
	var bonus: float = 0.0
	for t in traits:
		var subchoice: int = get_subchoice(t.trait_id)
		for hatred_target in t.hatred_targets:
			if hatred_target.to_lower() == target_lower:
				bonus += t.get_modifier("hatred_morale_bonus", subchoice)
				break  # Only apply once per trait
	return bonus


## Record a battle result and update progression.
func record_battle(won: bool, kills: int) -> void:
	battles_fought += 1
	total_kills += kills

	if won:
		victories += 1
		add_experience(50 + kills)  # Base XP + kills
	else:
		defeats += 1
		add_experience(20 + kills / 2)  # Less XP for defeat

	# Check for rank advancement
	_update_commander_rank()


## Update commander rank based on current progression stats.
func _update_commander_rank() -> void:
	var old_rank: CommanderRank = commander_rank

	# Check ranks in order (highest first so we get the best applicable)
	if total_kills >= BLOODIED_KILLS and victories >= PROVEN_VICTORIES and battles_fought >= VETERAN_BATTLES:
		commander_rank = CommanderRank.BLOODIED
	elif victories >= PROVEN_VICTORIES and battles_fought >= VETERAN_BATTLES:
		commander_rank = CommanderRank.PROVEN
	elif battles_fought >= VETERAN_BATTLES:
		commander_rank = CommanderRank.VETERAN
	else:
		commander_rank = CommanderRank.UNTESTED

	# Log rank advancement
	if commander_rank != old_rank and commander_rank != CommanderRank.UNTESTED:
		print("[GeneralProfile] %s achieved rank: %s!" % [general_name, get_rank_name()])


## Get the display name for current commander rank.
func get_rank_name() -> String:
	match commander_rank:
		CommanderRank.VETERAN:
			return "Veteran"
		CommanderRank.PROVEN:
			return "Proven"
		CommanderRank.BLOODIED:
			return "Bloodied"
		_:
			return "Untested"


## Check if commander has reached at least Veteran rank.
func is_veteran() -> bool:
	return commander_rank >= CommanderRank.VETERAN


## Check if commander has reached at least Proven rank.
func is_proven() -> bool:
	return commander_rank >= CommanderRank.PROVEN


## Check if commander has reached Bloodied rank.
func is_bloodied() -> bool:
	return commander_rank >= CommanderRank.BLOODIED


# === COMMANDER RANK BONUSES ===

## Get melee defense bonus from commander rank.
## Veteran+: +5% melee defense
func get_rank_defense_bonus() -> float:
	if is_veteran():
		return 0.05
	return 0.0


## Get melee attack bonus from commander rank.
## Bloodied: +10% melee attack
func get_rank_attack_bonus() -> float:
	if is_bloodied():
		return 0.10
	return 0.0


## Get morale aura bonus from commander rank.
## Veteran+: +5 morale aura
func get_rank_morale_aura() -> float:
	if is_veteran():
		return 5.0
	return 0.0


## Get rally success bonus from commander rank.
## Proven+: +10% rally success
func get_rank_rally_bonus() -> float:
	if is_proven():
		return 0.10
	return 0.0


## Get rout threshold bonus from commander rank.
## Proven+: +5% rout resistance (troops rout at lower morale)
func get_rank_rout_resistance() -> float:
	if is_proven():
		return 0.05
	return 0.0


## Get enemy morale penalty from commander rank (intimidation).
## Bloodied: -5 enemy morale when engaged
func get_rank_intimidation() -> float:
	if is_bloodied():
		return -5.0
	return 0.0


## Add experience and check for level up.
func add_experience(amount: int) -> void:
	experience += amount

	# Check for level up
	while experience >= XP_PER_LEVEL:
		experience -= XP_PER_LEVEL
		level += 1
		print("[GeneralProfile] %s leveled up to %d!" % [general_name, level])


## Get progress towards next level (0.0 to 1.0).
func get_level_progress() -> float:
	return float(experience) / float(XP_PER_LEVEL)


## Serialize for save data.
func to_save_data() -> Dictionary:
	var trait_ids: Array[String] = []
	for t in traits:
		trait_ids.append(t.trait_id)

	return {
		"general_name": general_name,
		"trait_ids": trait_ids,
		"active_subchoices": active_subchoices.duplicate(),
		"commander_rank": commander_rank,
		"battles_fought": battles_fought,
		"total_kills": total_kills,
		"victories": victories,
		"defeats": defeats,
		"unlocked_traits": unlocked_traits.duplicate(),
		"experience": experience,
		"level": level,
	}


## Load from save data (requires TraitManager to resolve trait IDs).
## Call TraitManager.load_profile_traits() after loading.
func from_save_data(data: Dictionary) -> void:
	general_name = data.get("general_name", "Unknown General")
	active_subchoices = data.get("active_subchoices", {})
	commander_rank = data.get("commander_rank", CommanderRank.UNTESTED)
	battles_fought = data.get("battles_fought", 0)
	total_kills = data.get("total_kills", 0)
	victories = data.get("victories", 0)
	defeats = data.get("defeats", 0)
	unlocked_traits = data.get("unlocked_traits", [])
	experience = data.get("experience", 0)
	level = data.get("level", 1)
	# Note: traits must be resolved separately via TraitManager
