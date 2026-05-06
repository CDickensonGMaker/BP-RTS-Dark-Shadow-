class_name TaskSeekSupply
extends BTNode

## Behavior tree task for seeking supply when low on ammo.
## Spring 1944-inspired automatic resupply behavior.

var commander: CommanderAI
var _ammo_threshold: float = 0.3  # Seek supply when below 30% ammo
var _supply_arrival_threshold: float = 10.0  # Close enough to supply

func _init(p_commander: CommanderAI) -> void:
	super._init("SeekSupply")
	commander = p_commander


func tick(_delta: float) -> Status:
	## Check if we need supply, and move towards nearest supply wagon.

	var regiment: Regiment = commander.regiment
	if not regiment:
		return Status.FAILURE

	# Don't seek supply if in combat
	if regiment.state == Regiment.State.ENGAGING:
		return Status.FAILURE

	# Check if we need ammo
	if not _needs_resupply():
		return Status.SUCCESS  # Don't need supply, task complete

	# Check if already in supply range
	if SupplySystem and SupplySystem.is_in_supply_range(regiment):
		# We're in range, stay put and resupply
		if regiment.state == Regiment.State.MARCHING:
			regiment.leader.stop_movement()
		return Status.RUNNING  # Wait for resupply to complete

	# Find nearest supply wagon
	var faction: int = 0 if regiment.is_player_controlled else 1
	var nearest_wagon: Node = SupplySystem.find_nearest_wagon(regiment.global_position, faction) if SupplySystem else null

	if not nearest_wagon:
		return Status.FAILURE  # No supply available

	# Move towards supply wagon
	var distance: float = regiment.global_position.distance_to(nearest_wagon.global_position)
	if distance > _supply_arrival_threshold:
		commander.issue_move_order(nearest_wagon.global_position)
		return Status.RUNNING

	# We've arrived, wait for resupply
	return Status.RUNNING


func _needs_resupply() -> bool:
	## Check if regiment needs ammo resupply.
	var regiment: Regiment = commander.regiment
	if not regiment or not regiment.data:
		return false

	# Only ranged units need ammo
	if regiment.data.max_ammo <= 0:
		return false

	# Check ammo percentage
	var ammo_pct: float = float(regiment.current_ammo) / float(regiment.data.max_ammo)
	return ammo_pct < _ammo_threshold
