# ALL inter-system communication goes through here.
# No system holds a direct reference to another system.
extends Node


# Selection
signal regiment_selected(regiment: Regiment)
signal regiment_deselected(regiment: Regiment)
signal selection_cleared()
signal group_saved(group_id: int, regiments: Array)
signal group_recalled(group_id: int)

# Orders
signal order_given(regiment: Regiment, order: OrderType.Type, target: Variant)

# Combat
signal regiment_attacked(attacker: Regiment, defender: Regiment, damage: int)
signal projectile_fired(from: Regiment, target: Regiment)
signal unit_flanked(flanked: Regiment, flanker: Regiment, is_rear: bool)
signal charge_impact(charger: Regiment, target: Regiment, was_braced: bool)

# Morale
signal morale_changed(regiment: Regiment, new_value: float, delta: float)
signal regiment_routing(regiment: Regiment)
signal regiment_rallied(regiment: Regiment)

# State
signal regiment_dead(regiment: Regiment)
signal general_died(general: General)

# Battle
signal battle_started()
signal battle_ended(result: Dictionary)
	# result = { "winner": String, "casualties": Dictionary, "duration": float }

# Deployment Phase
signal deployment_started()
signal deployment_ended()
signal unit_repositioned(regiment: Regiment, new_position: Vector3)

# Formation
signal formation_preview_started(regiment: Regiment, start_pos: Vector3)
signal formation_preview_updated(regiment: Regiment, start_pos: Vector3, end_pos: Vector3)
signal formation_applied(regiment: Regiment, position: Vector3, facing: Vector3, width: float)

# AI System
signal ai_play_started(general_ai, play_name: String)
signal ai_play_completed(general_ai, play_name: String, success: bool)
signal ai_target_acquired(regiment: Regiment, target: Regiment)
signal ai_order_issued(regiment: Regiment, order_type: String, target)

# Per-Soldier Morale (unit_morale_changed is used for regiment-level tracking)
signal unit_morale_changed(regiment: Regiment, average_morale: float)

# Stance and Formation
signal stance_changed(regiment: Regiment, old_stance: int, new_stance: int)
signal formation_type_changed(regiment: Regiment, old_formation: int, new_formation: int)
signal formation_reform_started(regiment: Regiment, duration: float)
signal formation_reform_completed(regiment: Regiment)

# Stamina
signal unit_exhausted(regiment: Regiment)
signal unit_recovered(regiment: Regiment)

# Veterancy
signal unit_leveled_up(regiment: Regiment, old_level: int, new_level: int)

# Abilities
signal ability_used(regiment: Regiment, ability: int)
signal ability_ready(regiment: Regiment, ability: int)

# Spells
signal spell_cast(caster: Regiment, spell_id: String, target_pos: Vector3)
signal spell_hit(spell_id: String, target: Regiment, damage: int)
