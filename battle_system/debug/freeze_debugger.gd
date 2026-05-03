extends Node

## Freeze Debugger - Helps identify where game freezes
## Add this to your battle scene to track which system freezes.
##
## Usage: Add as child of BattleScene, check console output before freeze.

var _frame_count: int = 0
var _last_print_time: float = 0.0
var _systems_checked: Dictionary = {}

func _ready():
	print("[FREEZE_DEBUG] Debugger started at ", Time.get_ticks_msec())

	# Connect to key signals that might indicate freeze point
	if BattleSignals:
		BattleSignals.battle_started.connect(_on_battle_started)
		BattleSignals.regiment_selected.connect(_on_regiment_selected)
		BattleSignals.regiment_dead.connect(_on_regiment_dead)
		BattleSignals.regiment_routing.connect(_on_regiment_routing)

func _process(delta):
	_frame_count += 1

	# Print every second to show we're alive
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_print_time >= 1.0:
		_last_print_time = now
		_print_status()

func _print_status():
	var status: String = "[FREEZE_DEBUG] Frame %d | Time %.1fs" % [_frame_count, Time.get_ticks_msec() / 1000.0]

	# Check key systems
	if AIAutoload:
		status += " | AI: %d commanders" % AIAutoload._commander_ais.size()

	if CombatManager:
		status += " | Melees: %d" % CombatManager.active_melees.size()

	var regiments = get_tree().get_nodes_in_group("all_regiments")
	status += " | Regiments: %d" % regiments.size()

	# Count states
	var engaging: int = 0
	var routing: int = 0
	for r in regiments:
		if r.state == Regiment.State.ENGAGING:
			engaging += 1
		elif r.state == Regiment.State.ROUTING:
			routing += 1
	status += " | Engaging: %d, Routing: %d" % [engaging, routing]

	print(status)

func _on_battle_started():
	print("[FREEZE_DEBUG] >>> BATTLE STARTED at frame %d" % _frame_count)

func _on_regiment_selected(regiment):
	print("[FREEZE_DEBUG] Regiment selected: %s" % regiment.name)

func _on_regiment_dead(regiment):
	print("[FREEZE_DEBUG] Regiment DEAD: %s at frame %d" % [regiment.name, _frame_count])

func _on_regiment_routing(regiment):
	print("[FREEZE_DEBUG] Regiment ROUTING: %s at frame %d" % [regiment.name, _frame_count])
