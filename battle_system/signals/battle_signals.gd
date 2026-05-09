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

# Combat State Flags
signal combat_state_changed(regiment: Regiment, flag: int, value: bool)

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
signal formation_cohesion_changed(regiment: Regiment, cohesion: float)  # Total War-style cohesion

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

# Reinforcements
signal reinforcements_available(wave: int, count: int)
signal reinforcements_arrived(wave: int)
signal reinforcements_requested()
signal spawn_reinforcement(spawn_info: Dictionary)
	# spawn_info = { regiment_data, position, facing, is_reinforcement, wave }

# Supply System (spring1944-inspired)
signal unit_resupplied(regiment: Regiment, resource_type: String, amount: int)
signal entered_supply_range(regiment: Regiment, wagon: Node)
signal left_supply_range(regiment: Regiment, wagon: Node)

# Casualty Tracker Thresholds
signal unit_entered_caution(regiment: Regiment)
signal unit_withdrawing(regiment: Regiment)
signal unit_disengage_success(regiment: Regiment)
signal unit_disengage_failed(regiment: Regiment)

# Rally System
signal rally_used(general: Node, units_rallied: int)

# Ammo Type
signal round_type_changed(regiment: Regiment, old_type: int, new_type: int)

# Movement Mode
signal move_mode_changed(new_mode: int)  # RegimentLeader.MoveMode

# Pause (QOL Phase 2)
signal battle_paused(is_paused: bool)

# Hover Preview (QOL Phase 5)
signal regiment_hover_entered(regiment: Regiment)
signal regiment_hover_exited(regiment: Regiment)
