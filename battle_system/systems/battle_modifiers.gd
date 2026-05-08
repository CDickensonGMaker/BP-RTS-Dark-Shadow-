## BattleModifiers - Autoload that applies general traits to combat calculations.
## Access via BattleModifiers singleton during battles.
## Part of Phase 9 General Trait System.
extends Node

# Cached general profiles for current battle (GeneralProfile resources)
var player_general = null
var enemy_general = null

# Battle state
var _battle_active: bool = false


## Set up profiles for a battle.
func setup_battle(player_profile, enemy_profile = null) -> void:
	player_general = player_profile
	enemy_general = enemy_profile
	_battle_active = true
	print("[BattleModifiers] Battle setup - Player: %s, Enemy: %s" % [
		player_profile.general_name if player_profile else "None",
		enemy_profile.general_name if enemy_profile else "None"
	])


## Clear battle state when battle ends.
func clear_battle() -> void:
	player_general = null
	enemy_general = null
	_battle_active = false


## Check if battle modifiers are active.
func is_active() -> bool:
	return _battle_active


# =============================================================================
# MODIFIER QUERIES
# =============================================================================

## Get the GeneralProfile for a faction.
func _get_profile(is_player: bool):
	return player_general if is_player else enemy_general


## Get melee attack modifier for a faction.
## Includes both trait bonuses and commander rank bonuses.
func get_melee_attack_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	# Trait bonus + Bloodied rank bonus (+10%)
	return profile.get_combined_modifier("melee_attack_mod") + profile.get_rank_attack_bonus()


## Get melee defense modifier for a faction.
## Includes both trait bonuses and commander rank bonuses.
func get_melee_defense_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	# Trait bonus + Veteran rank bonus (+5%)
	return profile.get_combined_modifier("melee_defense_mod") + profile.get_rank_defense_bonus()


## Get ranged attack/accuracy modifier for a faction.
func get_ranged_attack_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("ranged_attack_mod")


## Get charge bonus modifier for a faction.
func get_charge_bonus_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("charge_bonus_mod")


## Get morale aura bonus for a faction.
## Includes both trait bonuses and commander rank bonuses.
func get_morale_aura_bonus(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	# Trait bonus + Veteran rank bonus (+5 morale aura)
	return profile.get_combined_modifier("morale_aura_bonus") + profile.get_rank_morale_aura()


## Get rally success modifier for a faction.
## Includes both trait bonuses and commander rank bonuses.
func get_rally_success_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	# Trait bonus + Proven rank bonus (+10% rally success)
	return profile.get_combined_modifier("rally_success_mod") + profile.get_rank_rally_bonus()


## Get rout threshold modifier for a faction.
## Includes both trait bonuses and commander rank bonuses.
func get_rout_threshold_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	# Trait bonus + Proven rank bonus (+5% rout resistance)
	return profile.get_combined_modifier("rout_threshold_mod") + profile.get_rank_rout_resistance()


## Get army movement speed modifier for a faction.
func get_army_speed_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("army_speed_mod")


## Get army stamina/fatigue resistance modifier.
func get_army_stamina_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("army_stamina_mod")


## Get reinforcement arrival speed modifier.
func get_reinforcement_speed_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("reinforcement_speed_mod")


# =============================================================================
# COMMANDER RANK BONUSES
# =============================================================================

## Get intimidation penalty applied to enemies (Bloodied rank).
## Returns negative value (e.g., -5.0) that reduces enemy morale.
func get_intimidation_penalty(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_rank_intimidation()


## Get the commander rank name for display.
func get_commander_rank_name(is_player: bool) -> String:
	var profile = _get_profile(is_player)
	if not profile:
		return "Unknown"
	return profile.get_rank_name()


## Check if commander is at least Veteran rank.
func is_veteran(is_player: bool) -> bool:
	var profile = _get_profile(is_player)
	if not profile:
		return false
	return profile.is_veteran()


## Check if commander is at least Proven rank.
func is_proven(is_player: bool) -> bool:
	var profile = _get_profile(is_player)
	if not profile:
		return false
	return profile.is_proven()


## Check if commander is Bloodied rank.
func is_bloodied(is_player: bool) -> bool:
	var profile = _get_profile(is_player)
	if not profile:
		return false
	return profile.is_bloodied()


# =============================================================================
# HATRED MODIFIERS
# =============================================================================

## Get hatred attack bonus against a specific target type.
func get_hatred_attack_bonus(is_player: bool, target_type: String) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_hatred_attack_bonus(target_type)


## Get hatred morale bonus against a specific target type.
func get_hatred_morale_bonus(is_player: bool, target_type: String) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_hatred_morale_bonus(target_type)


## Check if faction has hatred against a target type.
func has_hatred_against(is_player: bool, target_type: String) -> bool:
	var profile = _get_profile(is_player)
	if not profile:
		return false
	return profile.has_hatred_against(target_type)


# =============================================================================
# PERSONALITY MODIFIERS (AI Behavior)
# =============================================================================

## Get aggression modifier for AI generals.
func get_aggression_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("aggression_mod")


## Get caution modifier for AI generals.
func get_caution_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("caution_mod")


## Get opportunism modifier for AI generals.
func get_opportunism_mod(is_player: bool) -> float:
	var profile = _get_profile(is_player)
	if not profile:
		return 0.0
	return profile.get_combined_modifier("opportunism_mod")


# =============================================================================
# COMBINED MODIFIER DICTIONARIES
# =============================================================================

## Get all combat modifiers as a dictionary for easy application.
## Includes both trait bonuses and commander rank bonuses.
func get_combat_modifiers(is_player: bool) -> Dictionary:
	return {
		"melee_attack": get_melee_attack_mod(is_player),
		"melee_defense": get_melee_defense_mod(is_player),
		"ranged_attack": get_ranged_attack_mod(is_player),
		"charge_bonus": get_charge_bonus_mod(is_player),
		"intimidation": get_intimidation_penalty(is_player),
	}


## Get all morale modifiers as a dictionary.
func get_morale_modifiers(is_player: bool) -> Dictionary:
	return {
		"aura_bonus": get_morale_aura_bonus(is_player),
		"rally_mod": get_rally_success_mod(is_player),
		"rout_threshold": get_rout_threshold_mod(is_player),
	}


## Get all army-wide modifiers as a dictionary.
func get_army_modifiers(is_player: bool) -> Dictionary:
	return {
		"speed": get_army_speed_mod(is_player),
		"stamina": get_army_stamina_mod(is_player),
		"reinforcement_speed": get_reinforcement_speed_mod(is_player),
	}


## Get all personality modifiers as a dictionary (for AI).
func get_personality_modifiers(is_player: bool) -> Dictionary:
	return {
		"aggression": get_aggression_mod(is_player),
		"caution": get_caution_mod(is_player),
		"opportunism": get_opportunism_mod(is_player),
	}


# =============================================================================
# UTILITY
# =============================================================================

## Get general name for a faction.
func get_general_name(is_player: bool) -> String:
	var profile = _get_profile(is_player)
	if not profile:
		return "Unknown"
	return profile.general_name


## Check if a faction has any traits.
func has_traits(is_player: bool) -> bool:
	var profile = _get_profile(is_player)
	if not profile:
		return false
	return profile.traits.size() > 0


## Get trait count for a faction.
func get_trait_count(is_player: bool) -> int:
	var profile = _get_profile(is_player)
	if not profile:
		return 0
	return profile.traits.size()


## Get all trait names for a faction (for UI/debug).
func get_trait_names(is_player: bool) -> Array[String]:
	var profile = _get_profile(is_player)
	if not profile:
		return []

	var names: Array[String] = []
	for t in profile.traits:
		names.append(t.trait_name)
	return names
