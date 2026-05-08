extends Node


var selected_regiments: Array[Regiment] = []
var saved_groups: Dictionary = {}   # int -> Array[Regiment]
var drag_start: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var last_click_time: float = 0.0
var last_clicked_regiment: Regiment = null
const DOUBLE_CLICK_TIME: float = 0.3
var _show_spell_ranges: bool = false

# QOL Phase 5: Hover preview state
var _hovered_regiment: Regiment = null
var _hover_update_timer: float = 0.0
const HOVER_UPDATE_INTERVAL: float = 0.1  # Update hover 10x/sec


func _process(delta: float) -> void:
	# QOL Phase 5: Hover preview - update periodically
	_hover_update_timer += delta
	if _hover_update_timer >= HOVER_UPDATE_INTERVAL:
		_hover_update_timer = 0.0
		_update_hover_state()


func _unhandled_input(event: InputEvent) -> void:
	# Handle ALT key for spell range display toggle
	if event is InputEventKey:
		if event.keycode == KEY_ALT:
			_show_spell_ranges = event.pressed
			_update_spell_range_display()


func _input(event):
	# Skip all input processing when on the campaign map
	if _is_campaign_map_active():
		return

	# Right-click move orders are now handled by FormationDragHandler
	# which supports both simple moves and drag-to-set-formation

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# During deployment, DeploymentManager handles unit dragging
		# We only handle selection when not dragging a unit
		var is_deployment = DeploymentManager and DeploymentManager.is_deployment_phase()
		var deployment_dragging = is_deployment and DeploymentManager.dragging_regiment != null

		if event.pressed:
			drag_start = event.position
			is_dragging = false
		else:
			# Don't process selection if deployment was dragging a unit
			if not deployment_dragging:
				if is_dragging:
					_finish_drag_select(event.position)
				else:
					_single_select(event.position)
			is_dragging = false

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		# Check if deployment is dragging a unit
		var is_deployment = DeploymentManager and DeploymentManager.is_deployment_phase()
		var deployment_dragging = is_deployment and DeploymentManager.dragging_regiment != null
		var dist = event.position.distance_to(drag_start)

		if not deployment_dragging and dist > 5:
			is_dragging = true

	# Handle keyboard input
	if event is InputEventKey and event.pressed:
		_handle_key_input(event)


func _handle_key_input(event: InputEventKey):
	# Ctrl+G: Create next available group (1-9)
	if event.ctrl_pressed and event.keycode == KEY_G:
		_create_next_group()
		return

	# Control groups: Ctrl+0-9 save, 0-9 recall, Shift+0-9 add to selection
	for i in range(10):
		var key: int = KEY_0 + i
		if event.keycode == key:
			if event.ctrl_pressed:
				_save_group(i)
			elif event.shift_pressed:
				_add_group_to_selection(i)
			else:
				_recall_group(i)
			return

	# Stance hotkeys (Z, X, C, V)
	if not selected_regiments.is_empty():
		match event.keycode:
			KEY_Z:
				_set_stance_for_selected(StanceType.Type.AGGRESSIVE)
			KEY_X:
				_set_stance_for_selected(StanceType.Type.DEFENSIVE)
			KEY_C:
				_set_stance_for_selected(StanceType.Type.HOLD_GROUND)
			KEY_V:
				_set_stance_for_selected(StanceType.Type.SKIRMISH)
			KEY_G:
				# Guard mode - next click sets target
				_enter_guard_mode()

	# Formation hotkeys (F1-F4)
	if not selected_regiments.is_empty():
		match event.keycode:
			KEY_F1:
				_set_formation_for_selected(FormationType.Type.LINE)
			KEY_F2:
				_set_formation_for_selected(FormationType.Type.COLUMN)
			KEY_F3:
				_set_formation_for_selected(FormationType.Type.WEDGE)
			KEY_F4:
				_set_formation_for_selected(FormationType.Type.SQUARE)

	# Ability hotkeys (Q, E, F)
	if not selected_regiments.is_empty():
		match event.keycode:
			KEY_Q:
				_use_ability_hotkey(0)  # First ability
			KEY_E:
				_use_ability_hotkey(1)  # Second ability
			KEY_F:
				_use_ability_hotkey(2)  # Third ability (moved from R)

	# Run/Walk toggle (R key)
	if event.keycode == KEY_R and not selected_regiments.is_empty():
		_toggle_run_for_selected()

	# Hold position command (H key - not S, since S is used for WASD camera)
	if event.keycode == KEY_H:
		for regiment in selected_regiments:
			regiment.give_order(OrderType.Type.HOLD_POSITION)

	# === CAMERA SHORTCUTS (QOL Phase 1) ===

	# Space: Focus on selected units (cycles through if multiple)
	if event.keycode == KEY_SPACE and not selected_regiments.is_empty():
		_camera_focus_selected()
		return

	# Home: Focus on player's general
	if event.keycode == KEY_HOME:
		_camera_focus_general()
		return

	# End: Focus on battle center
	if event.keycode == KEY_END:
		_camera_focus_battle_center()
		return

	# Pause toggle (P key)
	if event.keycode == KEY_P:
		_toggle_pause()
		return

	# Camera bookmarks: F5-F8 to save, Shift+F5-F8 to recall
	for i in 4:
		var save_key: int = KEY_F5 + i
		if event.keycode == save_key:
			if event.shift_pressed:
				_camera_recall_bookmark(i)
			else:
				_camera_save_bookmark(i)
			return
func _single_select(screen_pos: Vector2):
	var regiment: Regiment = _raycast_regiment(screen_pos)
	var current_time: float = Time.get_unix_time_from_system()

	# Check for double-click on same unit
	if regiment and regiment == last_clicked_regiment:
		if current_time - last_click_time < DOUBLE_CLICK_TIME:
			# Double-click: select all units of same type
			_select_all_of_type(regiment)
			last_clicked_regiment = null
			return

	last_click_time = current_time
	last_clicked_regiment = regiment

	# Shift+click: add to selection
	# Ctrl+click: toggle in selection
	if Input.is_key_pressed(KEY_SHIFT):
		if regiment and regiment.is_player_controlled:
			_add_to_selection(regiment)
	elif Input.is_key_pressed(KEY_CTRL):
		if regiment and regiment.is_player_controlled:
			if regiment in selected_regiments:
				_remove_from_selection(regiment)
			else:
				_add_to_selection(regiment)
	else:
		# Normal click: clear and select
		clear_selection()
		if regiment and regiment.is_player_controlled:
			_add_to_selection(regiment)
func _finish_drag_select(end_pos: Vector2):
	# Shift or Ctrl: add to existing selection
	if not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_SHIFT):
		clear_selection()
	var box: Rect2 = Rect2(drag_start, end_pos - drag_start).abs()
	for regiment in get_tree().get_nodes_in_group("player_regiments"):
		if _regiment_in_screen_rect(regiment, box):
			_add_to_selection(regiment)
func _add_to_selection(regiment: Regiment):
	if regiment not in selected_regiments:
		selected_regiments.append(regiment)
		# Show selection ring (QOL Phase 3)
		if regiment.has_method("set_selected_visual"):
			regiment.set_selected_visual(true)
		BattleSignals.regiment_selected.emit(regiment)


func clear_selection():
	for r in selected_regiments:
		# Hide selection ring (QOL Phase 3)
		if is_instance_valid(r) and r.has_method("set_selected_visual"):
			r.set_selected_visual(false)
		BattleSignals.regiment_deselected.emit(r)
	selected_regiments.clear()
	BattleSignals.selection_cleared.emit()
func _save_group(id: int):
	saved_groups[id] = selected_regiments.duplicate()
	BattleSignals.group_saved.emit(id, saved_groups[id])
func _recall_group(id: int):
	if saved_groups.has(id):
		clear_selection()
		for r in saved_groups[id]:
			if is_instance_valid(r):
				_add_to_selection(r)
		BattleSignals.group_recalled.emit(id)
func _raycast_regiment(screen_pos: Vector2) -> Regiment:
	var viewport := get_viewport()
	if not viewport:
		return null
	var camera := viewport.get_camera_3d()
	if camera == null:
		return null
	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)
	var ray_end = ray_origin + ray_dir * 1000
	var space = get_viewport().get_world_3d().direct_space_state

	# First try to detect areas (units)
	var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = true  # Enable Area3D detection (MeleeArea)
	query.collide_with_bodies = false  # Don't hit terrain/bodies
	query.collision_mask = 2  # Only check layer 2 (units)
	var result = space.intersect_ray(query)

	if result:
		var collider = result.collider
		# Check if collider's owner/parent is a Regiment (e.g., MeleeArea)
		var parent = collider.get_parent()
		while parent:
			if parent is Regiment:
				return parent
			parent = parent.get_parent()

	# FALLBACK: Screen-space distance check (more reliable for RTS selection)
	# If raycast failed, check if click is near any regiment's screen position
	var closest_regiment: Regiment = null
	var closest_dist: float = 30.0  # Max screen pixels to count as a hit (tighter selection)

	for regiment in get_tree().get_nodes_in_group("all_regiments"):
		if regiment is Regiment:
			var regiment_screen_pos = camera.unproject_position(regiment.global_position)
			var dist = screen_pos.distance_to(regiment_screen_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_regiment = regiment

	return closest_regiment
func _regiment_in_screen_rect(regiment: Regiment, rect: Rect2) -> bool:
	var viewport := get_viewport()
	if not viewport:
		return false
	var camera := viewport.get_camera_3d()
	if camera == null:
		return false
	var screen_pos = camera.unproject_position(regiment.global_position)
	return rect.has_point(screen_pos)


func select_regiment(regiment: Regiment):
	"""Public method to select a regiment from UI"""
	if not regiment or not regiment.is_player_controlled:
		return
	clear_selection()
	_add_to_selection(regiment)


func add_to_selection(regiment: Regiment):
	"""Public method to add a regiment to selection (shift+click from UI)"""
	if not regiment or not regiment.is_player_controlled:
		return
	_add_to_selection(regiment)


# Note: Move orders are now handled by FormationDragHandler
# which supports both simple right-click moves and drag-to-set-formation
func _issue_move_order(screen_pos: Vector2):
	"""Issue move order to selected regiments via right-click (legacy)"""
	if selected_regiments.is_empty():
		return

	var target = _raycast_ground(screen_pos)
	if target == Vector3.INF:
		return

	# Move all selected regiments to target
	for regiment in selected_regiments:
		if is_instance_valid(regiment):
			regiment.give_order(OrderType.Type.MOVE, target)


func _raycast_ground(screen_pos: Vector2) -> Vector3:
	"""Raycast to find ground position under mouse"""
	var viewport := get_viewport()
	if not viewport:
		return Vector3.INF
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return Vector3.INF

	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_end: Vector3 = ray_origin + ray_dir * 1000

	var space: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer

	var result: Dictionary = space.intersect_ray(query)
	if result:
		return result.position

	# Fallback: intersect with y=0 plane
	if ray_dir.y != 0:
		var t: float = -ray_origin.y / ray_dir.y
		if t > 0:
			return ray_origin + ray_dir * t

	return Vector3.INF


func _remove_from_selection(regiment: Regiment):
	"""Remove a regiment from selection"""
	var idx: int = selected_regiments.find(regiment)
	if idx >= 0:
		selected_regiments.remove_at(idx)
		BattleSignals.regiment_deselected.emit(regiment)


func _select_all_of_type(regiment: Regiment):
	"""Select all units of the same type on screen"""
	if not regiment or not regiment.data:
		return

	clear_selection()
	var target_type: UnitType.Type = regiment.data.unit_type

	for reg in get_tree().get_nodes_in_group("player_regiments"):
		if reg is Regiment and reg.data and reg.data.unit_type == target_type:
			_add_to_selection(reg)


func _add_group_to_selection(id: int):
	"""Add a saved group to current selection without clearing"""
	if saved_groups.has(id):
		for r in saved_groups[id]:
			if is_instance_valid(r):
				_add_to_selection(r)


func _create_next_group():
	"""Create group in first empty slot (1-9)"""
	if selected_regiments.is_empty():
		return

	# Find first empty slot (1-9, skip 0)
	for i in range(1, 10):
		var group_is_empty: bool = not saved_groups.has(i) or saved_groups.get(i, []).is_empty()
		# Also check if all units in group are dead (effectively empty)
		if saved_groups.has(i):
			var any_valid: bool = false
			for r in saved_groups[i]:
				if is_instance_valid(r) and r.state != Regiment.State.DEAD:
					any_valid = true
					break
			if not any_valid:
				group_is_empty = true

		if group_is_empty:
			_save_group(i)
			print("[SelectionManager] Created control group %d" % i)
			return

	# All full - find oldest/smallest group to overwrite
	push_warning("[SelectionManager] All 9 control groups are full - overwriting group 9")
	_save_group(9)


# === STANCE MANAGEMENT ===

func _set_stance_for_selected(stance: StanceType.Type):
	"""Set stance for all selected regiments"""
	for regiment in selected_regiments:
		if is_instance_valid(regiment):
			regiment.set_stance(stance)


var _guard_mode_active: bool = false

func _enter_guard_mode():
	"""Enter guard mode - next click on friendly unit sets guard target"""
	_guard_mode_active = true
	# TODO: Change cursor to guard cursor


func _check_guard_click(screen_pos: Vector2) -> bool:
	"""Check if we're in guard mode and handle guard target selection"""
	if not _guard_mode_active:
		return false

	var target: Regiment = _raycast_regiment(screen_pos)
	if target and target.is_player_controlled:
		for regiment in selected_regiments:
			if is_instance_valid(regiment) and regiment != target:
				regiment.set_stance(StanceType.Type.GUARD, target)

	_guard_mode_active = false
	return true


# === FORMATION MANAGEMENT ===

func _set_formation_for_selected(formation: FormationType.Type):
	"""Set formation for all selected regiments"""
	for regiment in selected_regiments:
		if is_instance_valid(regiment):
			regiment.set_formation(formation)


# === ABILITY MANAGEMENT ===

func _use_ability_hotkey(slot: int):
	"""Use ability in the given slot for selected units"""
	for regiment in selected_regiments:
		if not is_instance_valid(regiment) or not regiment.abilities:
			continue

		var abilities_list: Array = regiment.abilities.available_abilities
		if slot < abilities_list.size():
			var ability: AbilityType.Type = abilities_list[slot]
			var data: Dictionary = AbilityType.get_ability_data(ability)
			var target_mode: int = data.get("target_mode", AbilityType.TargetMode.SELF)

			match target_mode:
				AbilityType.TargetMode.SELF, AbilityType.TargetMode.NONE:
					regiment.use_ability(ability)
				AbilityType.TargetMode.ENEMY:
					# Use current AI target or nearest enemy
					if regiment.ai_controller and regiment.ai_controller.current_target:
						regiment.use_ability(ability, regiment.ai_controller.current_target)
					else:
						var nearest: Regiment = regiment._find_nearest_enemy()
						if nearest:
							regiment.use_ability(ability, nearest)
				AbilityType.TargetMode.DIRECTION:
					# Use facing direction
					var forward: Vector3 = -regiment.global_transform.basis.z
					regiment.use_ability(ability, regiment.global_position + forward * 30.0)


# === RUN/WALK TOGGLE ===

func _toggle_run_for_selected() -> void:
	"""Toggle run/walk mode for selected regiments. If any are walking, set all to run. Otherwise, set all to walk."""
	if selected_regiments.is_empty():
		return

	# Check if any selected regiment is walking
	var any_walking: bool = false
	for regiment in selected_regiments:
		if not is_instance_valid(regiment) or not regiment.leader:
			continue
		if regiment.leader.move_mode == RegimentLeader.MoveMode.WALK:
			any_walking = true
			break

	# If any are walking, set all to run. Otherwise, set all to walk.
	# Don't override CHARGE mode.
	var new_mode: RegimentLeader.MoveMode = (
		RegimentLeader.MoveMode.RUN if any_walking
		else RegimentLeader.MoveMode.WALK
	)

	for regiment in selected_regiments:
		if not is_instance_valid(regiment) or not regiment.leader:
			continue
		# Don't interrupt charge mode
		if regiment.leader.move_mode != RegimentLeader.MoveMode.CHARGE:
			regiment.leader.set_move_mode(new_mode)

	# Emit signal for UI update
	BattleSignals.move_mode_changed.emit(new_mode)


# === RANGE DISPLAY ===

func _update_spell_range_display() -> void:
	"""Update spell range display for all selected regiments based on ALT key state."""
	for regiment in selected_regiments:
		if not is_instance_valid(regiment):
			continue
		if regiment.range_indicator:
			if regiment.range_indicator.has_method("show_spell_ranges"):
				regiment.range_indicator.show_spell_ranges(_show_spell_ranges)


# === CAMPAIGN MAP CHECK ===

func _is_campaign_map_active() -> bool:
	"""Check if we're on the campaign map - skip battle selection processing"""
	var tree := get_tree()
	if not tree:
		return false
	var current_scene := tree.current_scene
	return current_scene and current_scene.name == "CampaignMap"


# === CAMERA SHORTCUTS (QOL Phase 1) ===

var _last_focused_index: int = 0  # For cycling through multiple selections

func _camera_focus_selected() -> void:
	"""Focus camera on selected units. Cycles through if multiple selected."""
	if selected_regiments.is_empty():
		return
	var camera := _get_battle_camera()
	if not camera:
		return

	# Cycle through selected if multiple
	var target = selected_regiments[_last_focused_index % selected_regiments.size()]
	_last_focused_index += 1
	if camera.has_method("center_on_regiment"):
		camera.center_on_regiment(target)


func _camera_focus_general() -> void:
	"""Focus camera on the player's general (unit with aura)."""
	var general := _find_player_general()
	if general and is_instance_valid(general):
		var camera := _get_battle_camera()
		if camera and camera.has_method("center_on_regiment"):
			camera.center_on_regiment(general)


func _camera_focus_battle_center() -> void:
	"""Focus camera on the centroid of all units in battle."""
	var all_units: Array = (
		get_tree().get_nodes_in_group("player_regiments") +
		get_tree().get_nodes_in_group("enemy_regiments")
	)
	if all_units.is_empty():
		return

	var center := Vector3.ZERO
	var count: int = 0
	for u in all_units:
		if is_instance_valid(u) and u.state != Regiment.State.DEAD:
			center += u.global_position
			count += 1
	if count > 0:
		center /= count
		var camera := _get_battle_camera()
		if camera and camera.has_method("center_on_position"):
			camera.center_on_position(center)


func _camera_save_bookmark(slot: int) -> void:
	"""Save current camera position to a bookmark slot."""
	var camera := _get_battle_camera()
	if camera and camera.has_method("save_bookmark"):
		camera.save_bookmark(slot)


func _camera_recall_bookmark(slot: int) -> void:
	"""Recall a saved camera bookmark."""
	var camera := _get_battle_camera()
	if camera and camera.has_method("snap_to_bookmark"):
		camera.snap_to_bookmark(slot)


func _find_player_general() -> Node:
	"""Find the player's general (unit with aura)."""
	for r in get_tree().get_nodes_in_group("player_regiments"):
		if r.data and r.data.has_aura:
			return r
	return null


func _get_battle_camera() -> Node:
	"""Get the battle camera from scene group."""
	var cameras := get_tree().get_nodes_in_group("battle_camera")
	return cameras[0] if cameras.size() > 0 else null


# === PAUSE TOGGLE (QOL Phase 2) ===

func _toggle_pause() -> void:
	"""Toggle battle pause state."""
	get_tree().paused = not get_tree().paused
	BattleSignals.battle_paused.emit(get_tree().paused)


# === HOVER PREVIEW (QOL Phase 5) ===

func _update_hover_state() -> void:
	"""Update which regiment the mouse is hovering over."""
	if _is_campaign_map_active():
		_set_hovered_regiment(null)
		return

	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var regiment: Regiment = _raycast_regiment(mouse_pos)

	# Only trigger hover for units not already selected
	if regiment and regiment in selected_regiments:
		regiment = null

	_set_hovered_regiment(regiment)


func _set_hovered_regiment(regiment: Regiment) -> void:
	"""Set the currently hovered regiment, emitting signals on change."""
	if regiment == _hovered_regiment:
		return

	var old_hover: Regiment = _hovered_regiment
	_hovered_regiment = regiment

	# Emit signals for UI
	if old_hover and is_instance_valid(old_hover):
		BattleSignals.regiment_hover_exited.emit(old_hover)

	if regiment and is_instance_valid(regiment):
		BattleSignals.regiment_hover_entered.emit(regiment)


func get_hovered_regiment() -> Regiment:
	"""Get the currently hovered regiment (if any)."""
	return _hovered_regiment
