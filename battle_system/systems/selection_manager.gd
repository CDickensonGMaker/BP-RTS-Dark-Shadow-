extends Node


var selected_regiments: Array[Regiment] = []
var saved_groups: Dictionary = {}   # int -> Array[Regiment]
var drag_start: Vector2 = Vector2.ZERO
var is_dragging: bool = false
var last_click_time: float = 0.0
var last_clicked_regiment: Regiment = null
const DOUBLE_CLICK_TIME: float = 0.3


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

	# Ability hotkeys (Q, E, R)
	if not selected_regiments.is_empty():
		match event.keycode:
			KEY_Q:
				_use_ability_hotkey(0)  # First ability
			KEY_E:
				_use_ability_hotkey(1)  # Second ability
			KEY_R:
				_use_ability_hotkey(2)  # Third ability

	# Hold position command (H key - not S, since S is used for WASD camera)
	if event.keycode == KEY_H:
		for regiment in selected_regiments:
			regiment.give_order(OrderType.Type.HOLD_POSITION)
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
		BattleSignals.regiment_selected.emit(regiment)
func clear_selection():
	for r in selected_regiments:
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
	var closest_dist: float = 50.0  # Max screen pixels to count as a hit

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


# === CAMPAIGN MAP CHECK ===

func _is_campaign_map_active() -> bool:
	"""Check if we're on the campaign map - skip battle selection processing"""
	var tree := get_tree()
	if not tree:
		return false
	var current_scene := tree.current_scene
	return current_scene and current_scene.name == "CampaignMap"
