# Campaign event bus. All campaign systems communicate through here.
extends Node


# Battalion selection (Node to support both 2D and 3D battalions)
signal battalion_selected(battalion: Node)
signal battalion_deselected()

# Movement (Node to support both 2D and 3D battalions)
signal battalion_move_requested(battalion: Node, target_position: Vector2)
signal battalion_moved(battalion: Node, new_position: Vector2)
signal movement_points_changed(battalion: Node, remaining: float)

# Path queue (multi-turn movement)
signal path_queued(battalion: Node, path: Array)
signal path_completed(battalion: Node)
signal path_interrupted(battalion: Node)

# Contracts
signal contract_selected(contract: Resource)
signal contract_accepted(contract: Resource)
signal contract_declined(contract: Resource)
signal contract_completed(contract: Resource, success: bool)
signal contracts_refreshed(contracts: Array)

# Battle
signal battle_requested(battalion: Node2D, enemy_army: Node2D)
signal battle_contract_requested(battalion: Node2D, contract: Resource)
signal battle_returning(result: Dictionary)

# Turn system
signal turn_started(turn_number: int)
signal turn_ended(turn_number: int)

# Economy
signal gold_changed(new_amount: int, delta: int)
signal upkeep_paid(amount: int)
signal reward_received(amount: int, source: String)
signal insufficient_funds(required: int, available: int)

# Enemy armies
signal enemy_army_moved(army: Node2D, new_position: Vector2)
signal enemy_army_defeated(army: Node2D)
signal enemy_army_spawned(army: Node2D)

# Regions
signal region_entered(battalion: Node2D, region: Node2D)
signal region_clicked(region: Node2D)
signal region_captured(region: Resource, new_owner: String)

# Settlements
signal settlement_clicked(settlement: Resource)
signal settlement_selected(settlement: Resource)
signal settlement_captured(settlement: Resource, new_owner: String)

# Buildings
signal building_started(settlement: Resource, building: Resource)
signal building_completed(settlement: Resource, building: Resource)
signal building_destroyed(settlement: Resource, building: Resource)

# Supply (DEI/Napoleon style)
signal supply_changed(battalion: Node2D, new_status: float)
signal attrition_applied(battalion: Node2D, losses: int, attrition_type: String)
signal replenishment_applied(battalion: Node2D, amount: int)

# Army management
signal army_slots_changed(new_max: int)
signal army_created(battalion: Resource)
signal army_disbanded(battalion: Resource)

# Pre-Battle
signal pre_battle_opened(battalion: Node2D, enemy: Node2D)
signal mercenary_hired(regiment: Resource, cost: int)
signal unit_refitted(regiment: Resource, upgrade_type: String, cost: int)

# Battle Reinforcements
signal reinforcements_available(wave: int, count: int)
signal reinforcements_arrived(wave: int)
signal reinforcements_requested()

# Save/Load
signal campaign_saved()
signal campaign_loaded()
