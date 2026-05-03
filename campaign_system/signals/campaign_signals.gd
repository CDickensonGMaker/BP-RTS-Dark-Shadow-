# Campaign event bus. All campaign systems communicate through here.
extends Node


# Battalion selection
signal battalion_selected(battalion: Node2D)
signal battalion_deselected()

# Movement
signal battalion_move_requested(battalion: Node2D, target_position: Vector2)
signal battalion_moved(battalion: Node2D, new_position: Vector2)
signal movement_points_changed(battalion: Node2D, remaining: float)

# Path queue (multi-turn movement)
signal path_queued(battalion: Node2D, path: Array)
signal path_completed(battalion: Node2D)
signal path_interrupted(battalion: Node2D)

# Contracts
signal contract_selected(contract: Resource)
signal contract_accepted(contract: Resource)
signal contract_declined(contract: Resource)
signal contract_completed(contract: Resource, success: bool)

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

# Save/Load
signal campaign_saved()
signal campaign_loaded()
