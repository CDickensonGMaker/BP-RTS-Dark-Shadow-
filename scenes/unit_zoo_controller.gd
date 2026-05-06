class_name UnitZooController
extends Node

## Unit Zoo Controller
## Debug scene for testing individual units: formations, pathfinding, combat,
## morale, stamina, and ammo systems.

const REGIMENT_SCENE: PackedScene = preload("res://battle_system/nodes/regiment.tscn")

# UI References - Left side controls
@onready var player_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox/SideBySide/PlayerColumn/PlayerUnitSelector
@onready var enemy_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox/SideBySide/EnemyColumn/EnemyUnitSelector
@onready var formation_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox/SideBySide/PlayerColumn/FormationSelector
@onready var stance_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox/SideBySide/PlayerColumn/StanceSelector
@onready var enemy_formation_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox/SideBySide/EnemyColumn/EnemyFormationSelector
@onready var enemy_stance_selector: OptionButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox/SideBySide/EnemyColumn/EnemyStanceSelector
@onready var player_info: Label = $ZooDebugUI/MainLayout/LeftSide/InfoPanel/InfoContainer/PlayerInfo
@onready var enemy_info: Label = $ZooDebugUI/MainLayout/LeftSide/InfoPanel/InfoContainer/EnemyInfo

# 3D viewport references
@onready var battle_viewport: SubViewport = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport
@onready var unit_container: Node3D = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport/BattleWorld/Units
@onready var battle_camera: Camera3D = $ZooDebugUI/MainLayout/ViewportContainer/BattleViewport/BattleWorld/BattleCamera
@onready var camera_lock_toggle: CheckButton = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox/CameraLockToggle

var player_regiment: Node = null
var enemy_regiment: Node = null
var all_unit_ids: Array = []

# Default starting units
const DEFAULT_PLAYER_UNIT: String = "grtsword"
const DEFAULT_ENEMY_UNIT: String = "orcboyz"


func _ready() -> void:
	_populate_unit_dropdowns()
	_populate_formation_dropdown()
	_populate_stance_dropdown()
	_connect_signals()

	# Spawn initial units after a frame to ensure autoloads are ready
	call_deferred("_spawn_initial_units")


func _populate_unit_dropdowns() -> void:
	# Use only ZOO units (core roster) instead of all units
	all_unit_ids = UnitCatalog.get_zoo_unit_ids()

	player_selector.clear()
	enemy_selector.clear()

	var player_default_idx: int = 0
	var enemy_default_idx: int = 0
	var valid_idx: int = 0

	for i in range(all_unit_ids.size()):
		var unit_id: String = all_unit_ids[i]
		var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
		if not data:
			continue  # Skip missing units

		var display_name: String = data.regiment_name

		player_selector.add_item(display_name)
		player_selector.set_item_metadata(valid_idx, unit_id)

		enemy_selector.add_item(display_name)
		enemy_selector.set_item_metadata(valid_idx, unit_id)

		if unit_id == DEFAULT_PLAYER_UNIT:
			player_default_idx = valid_idx
		if unit_id == DEFAULT_ENEMY_UNIT:
			enemy_default_idx = valid_idx

		valid_idx += 1

	player_selector.select(player_default_idx)
	enemy_selector.select(enemy_default_idx)


func _populate_formation_dropdown() -> void:
	var formations: Array[String] = ["Line", "Column", "Wedge", "Square", "Loose", "Shield Wall", "Schiltron"]

	formation_selector.clear()
	enemy_formation_selector.clear()

	for formation in formations:
		formation_selector.add_item(formation)
		enemy_formation_selector.add_item(formation)


func _populate_stance_dropdown() -> void:
	var stances: Array[String] = ["Aggressive", "Defensive", "Hold Ground", "Skirmish", "Guard"]

	stance_selector.clear()
	enemy_stance_selector.clear()

	for stance in stances:
		stance_selector.add_item(stance)
		enemy_stance_selector.add_item(stance)


func _connect_signals() -> void:
	player_selector.item_selected.connect(_on_player_unit_changed)
	enemy_selector.item_selected.connect(_on_enemy_unit_changed)
	formation_selector.item_selected.connect(_on_formation_changed)
	stance_selector.item_selected.connect(_on_stance_changed)
	enemy_formation_selector.item_selected.connect(_on_enemy_formation_changed)
	enemy_stance_selector.item_selected.connect(_on_enemy_stance_changed)

	# Camera lock toggle
	camera_lock_toggle.toggled.connect(_on_camera_lock_toggled)

	# Connect button signals
	var vbox: VBoxContainer = $ZooDebugUI/MainLayout/LeftSide/ControlsPanel/VBox
	vbox.get_node("ActionButtons/MoveButton").pressed.connect(_on_move_button_pressed)
	vbox.get_node("ActionButtons/AttackButton").pressed.connect(_on_attack_button_pressed)
	vbox.get_node("ActionButtons/ChargeButton").pressed.connect(_on_charge_button_pressed)
	vbox.get_node("ActionButtons/DisengageButton").pressed.connect(_on_disengage_button_pressed)
	vbox.get_node("ResetButton").pressed.connect(_on_reset_button_pressed)


func _input(event: InputEvent) -> void:
	# L key toggles camera lock
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_L:
			camera_lock_toggle.button_pressed = not camera_lock_toggle.button_pressed


func _on_camera_lock_toggled(pressed: bool) -> void:
	if battle_camera:
		battle_camera.camera_locked = pressed
		print("[UnitZoo] Camera %s" % ("locked" if pressed else "unlocked"))


func _spawn_initial_units() -> void:
	_spawn_player_unit(DEFAULT_PLAYER_UNIT)
	_spawn_enemy_unit(DEFAULT_ENEMY_UNIT)


func _on_player_unit_changed(index: int) -> void:
	var unit_id: String = player_selector.get_item_metadata(index)
	if unit_id:
		_spawn_player_unit(unit_id)


func _on_enemy_unit_changed(index: int) -> void:
	var unit_id: String = enemy_selector.get_item_metadata(index)
	if unit_id:
		_spawn_enemy_unit(unit_id)


func _spawn_player_unit(unit_id: String) -> void:
	# Clean up existing
	if player_regiment and is_instance_valid(player_regiment):
		if AIAutoload and AIAutoload.spatial_hash:
			AIAutoload.spatial_hash.unregister(player_regiment)
		player_regiment.queue_free()
		await get_tree().process_frame

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		push_error("UnitZoo: Could not load regiment data for " + unit_id)
		return

	player_regiment = REGIMENT_SCENE.instantiate()
	player_regiment.name = "PlayerRegiment"
	# Set data BEFORE adding to tree (Regiment._ready() checks for data)
	player_regiment.data = data.duplicate()
	player_regiment.is_player_controlled = true
	# Use sprites only (no 3D soldiers) to match battle scene
	player_regiment.use_3d_soldiers = false
	player_regiment.use_sprite_soldiers = true
	# Override scene's default atlas with the unit's actual atlas
	player_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(player_regiment)

	# Sync all positions after added to tree (prevents rubber-banding)
	player_regiment.sync_all_positions(Vector3(-15, 0, 0))
	player_regiment.look_at(Vector3(15, 0, 0))

	# Note: AIAutoload registration happens in Regiment._ready(), no need to duplicate

	# Enable AI assist so stance changes work in Unit Zoo
	player_regiment.enable_ai_assist(true)

	# Add to group for selection manager
	player_regiment.add_to_group("player_regiments")

	print("[UnitZoo] Spawned player unit: %s (%s)" % [data.regiment_name, unit_id])


func _spawn_enemy_unit(unit_id: String) -> void:
	# Clean up existing
	if enemy_regiment and is_instance_valid(enemy_regiment):
		if AIAutoload and AIAutoload.spatial_hash:
			AIAutoload.spatial_hash.unregister(enemy_regiment)
		enemy_regiment.queue_free()
		await get_tree().process_frame

	var data: RegimentData = UnitCatalog.get_regiment_data(unit_id)
	if not data:
		push_error("UnitZoo: Could not load regiment data for " + unit_id)
		return

	enemy_regiment = REGIMENT_SCENE.instantiate()
	enemy_regiment.name = "EnemyRegiment"
	# Set data BEFORE adding to tree (Regiment._ready() checks for data)
	enemy_regiment.data = data.duplicate()
	enemy_regiment.is_player_controlled = false
	# Use sprites only (no 3D soldiers) to match battle scene
	enemy_regiment.use_3d_soldiers = false
	enemy_regiment.use_sprite_soldiers = true
	# Override scene's default atlas with the unit's actual atlas
	enemy_regiment.sprite_atlas = data.sprite_atlas
	unit_container.add_child(enemy_regiment)

	# Sync all positions after added to tree (prevents rubber-banding)
	enemy_regiment.sync_all_positions(Vector3(15, 0, 0))
	enemy_regiment.look_at(Vector3(-15, 0, 0))

	# Note: AIAutoload registration happens in Regiment._ready(), no need to duplicate

	# Add to group for selection manager
	enemy_regiment.add_to_group("enemy_regiments")

	print("[UnitZoo] Spawned enemy unit: %s (%s)" % [data.regiment_name, unit_id])


func _on_formation_changed(index: int) -> void:
	if not player_regiment or not is_instance_valid(player_regiment):
		return

	# Use set_formation() to properly trigger formation change with visuals
	player_regiment.set_formation(index as FormationType.Type)
	print("[UnitZoo] Player formation changed to: %s" % FormationType.Type.keys()[index])


func _on_stance_changed(index: int) -> void:
	if not player_regiment or not is_instance_valid(player_regiment):
		return

	if player_regiment.ai_controller:
		player_regiment.ai_controller.current_stance = index as CommanderAI.Stance
		print("[UnitZoo] Player stance changed to: %s" % CommanderAI.Stance.keys()[index])


func _on_enemy_formation_changed(index: int) -> void:
	if not enemy_regiment or not is_instance_valid(enemy_regiment):
		return

	# Use set_formation() to properly trigger formation change with visuals
	enemy_regiment.set_formation(index as FormationType.Type)
	print("[UnitZoo] Enemy formation changed to: %s" % FormationType.Type.keys()[index])


func _on_enemy_stance_changed(index: int) -> void:
	if not enemy_regiment or not is_instance_valid(enemy_regiment):
		return

	if enemy_regiment.ai_controller:
		enemy_regiment.ai_controller.current_stance = index as CommanderAI.Stance
		print("[UnitZoo] Enemy stance changed to: %s" % CommanderAI.Stance.keys()[index])


func _process(_delta: float) -> void:
	_update_info_panels()


func _update_info_panels() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		player_info.text = _format_regiment_info(player_regiment, "PLAYER")
	else:
		player_info.text = "=== PLAYER ===\n(No unit)"

	if enemy_regiment and is_instance_valid(enemy_regiment):
		enemy_info.text = _format_regiment_info(enemy_regiment, "ENEMY")
	else:
		enemy_info.text = "=== ENEMY ===\n(No unit)"


func _format_regiment_info(reg: Node, label: String) -> String:
	var info: String = "=== %s ===\n" % label

	if not reg.data:
		return info + "(No data)"

	info += "Name: %s\n" % reg.data.regiment_name
	info += "Type: %s\n" % UnitType.Type.keys()[reg.data.unit_type]
	info += "State: %s\n" % Regiment.State.keys()[reg.state]
	info += "Soldiers: %d/%d\n" % [reg.current_soldiers, reg.data.max_soldiers]
	info += "Morale: %.1f\n" % reg.current_morale

	if reg.stamina:
		var stamina_pct: float = (reg.stamina.current_stamina / StaminaSystem.MAX_STAMINA) * 100.0
		info += "Stamina: %.1f%%\n" % stamina_pct

	if reg.data.max_ammo > 0:
		info += "Ammo: %d/%d\n" % [reg.current_ammo, reg.data.max_ammo]

	info += "Formation: %s\n" % FormationType.Type.keys()[reg.current_formation]

	# Combat stats
	info += "\n--- Stats ---\n"
	info += "Attack: %d\n" % reg.data.attack
	info += "Defense: %d\n" % reg.data.defense
	info += "Speed: Walk=%.2f Run=%.2f Charge=%.2f\n" % [reg.data.walk_speed, reg.data.run_speed, reg.data.charge_speed]

	if reg.data.ballistic_skill > 0:
		info += "BS: %d\n" % reg.data.ballistic_skill
		info += "Range: %.0f\n" % reg.data.range_distance

	return info


# === ACTION BUTTONS ===

func _on_move_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		player_regiment.give_order(OrderType.Type.MOVE, Vector3(0, 0, 0))
		print("[UnitZoo] Player ordered to move to center")


func _on_attack_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		if enemy_regiment and is_instance_valid(enemy_regiment):
			player_regiment.give_order(OrderType.Type.ATTACK_MOVE, enemy_regiment.global_position)
			print("[UnitZoo] Player ordered to attack enemy")


func _on_charge_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		if enemy_regiment and is_instance_valid(enemy_regiment):
			player_regiment.give_order(OrderType.Type.CHARGE, enemy_regiment.global_position)
			print("[UnitZoo] Player ordered to charge enemy")


func _on_disengage_button_pressed() -> void:
	if player_regiment and is_instance_valid(player_regiment):
		# Order unit to retreat away from enemy
		var retreat_dir: Vector3 = Vector3(-1, 0, 0)  # Default retreat left
		if enemy_regiment and is_instance_valid(enemy_regiment):
			retreat_dir = (player_regiment.global_position - enemy_regiment.global_position).normalized()
		var retreat_pos: Vector3 = player_regiment.global_position + retreat_dir * 20.0
		player_regiment.give_order(OrderType.Type.WITHDRAW, retreat_pos)
		print("[UnitZoo] Player ordered to disengage/retreat")


func _on_reset_button_pressed() -> void:
	_spawn_initial_units()
	formation_selector.select(0)
	stance_selector.select(0)
	enemy_formation_selector.select(0)
	enemy_stance_selector.select(0)
	print("[UnitZoo] Reset to initial state")
