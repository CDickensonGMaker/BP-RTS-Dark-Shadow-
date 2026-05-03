# Main campaign map controller.
# Handles map input, battalion spawning, and movement orders.
extends Node2D


@export var map_bounds: Rect2 = Rect2(0, 0, 1920, 1080)

@onready var camera: Camera2D = $CampaignCamera
@onready var battalions_container: Node2D = $BattalionsContainer
@onready var path_preview: Line2D = $PathPreview
@onready var hud: CanvasLayer = $CampaignHUD

var battalion_scene: PackedScene = preload("res://campaign_system/scenes/map_battalion.tscn")
var selected_battalion: Node2D = null

# Path preview colors (legacy - kept for compatibility)
const PATH_COLOR := Color(0.85, 0.7, 0.4, 0.8)
const PATH_INVALID := Color(0.8, 0.2, 0.2, 0.6)

# Total War-style turn colors for multi-turn path visualization
const TURN_COLORS := [
	Color(0.3, 0.85, 0.3, 0.9),   # Turn 0: Green (this turn)
	Color(0.9, 0.25, 0.25, 0.9),  # Turn 1: Red (next turn)
	Color(0.0, 0.78, 0.88, 0.9),  # Turn 2: Cyan
	Color(1.0, 0.78, 0.0, 0.9),   # Turn 3: Gold
	Color(0.65, 0.25, 0.85, 0.9), # Turn 4+: Purple
]

# Movement cost per pixel (distance * this = movement points spent)
const MOVEMENT_COST_PER_PIXEL := 0.1

# Path segment pool for multi-turn rendering
var path_segments: Array[Line2D] = []
var segment_pool_size := 10

# Movement range circle
var movement_range_circle: Line2D = null
const RANGE_CIRCLE_SEGMENTS := 64
const RANGE_CIRCLE_COLOR := Color(0.4, 0.8, 0.3, 0.5)  # Semi-transparent green

# Right-click hold state for Total War-style path preview
var is_right_click_held: bool = false


func _ready() -> void:
	# Set up camera bounds
	if camera:
		camera.map_bounds = map_bounds

	# Connect signals
	CampaignSignals.battalion_selected.connect(_on_battalion_selected)
	CampaignSignals.battalion_deselected.connect(_on_battalion_deselected)
	CampaignSignals.turn_started.connect(_on_turn_started)
	CampaignSignals.movement_points_changed.connect(_on_movement_points_changed)

	# Initialize path preview (legacy single line - hidden, we use segments now)
	if path_preview:
		path_preview.width = 3.0
		path_preview.default_color = PATH_COLOR
		path_preview.visible = false

	# Initialize path segment pool for multi-turn visualization
	_initialize_path_segments()

	# Initialize movement range circle
	_initialize_range_circle()

	# Start new campaign if not active (for testing)
	if not CampaignManager.is_campaign_active:
		CampaignManager.start_new_campaign()

	# Spawn battalions from CampaignManager
	_spawn_battalions()


func _spawn_battalions() -> void:
	# Clear existing
	for child in battalions_container.get_children():
		child.queue_free()

	# Spawn from campaign manager
	for battalion_data in CampaignManager.battalions:
		var battalion_node := battalion_scene.instantiate()
		battalion_node.battalion_data = battalion_data
		battalion_node.position = battalion_data.map_position
		battalions_container.add_child(battalion_node)

		# Select first battalion by default
		if CampaignManager.battalions.size() == 1:
			battalion_node.call_deferred("select")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Right-click: HOLD to preview path, RELEASE to execute move (Total War style)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# START preview mode
				is_right_click_held = true
				if selected_battalion:
					_update_path_preview(get_global_mouse_position())
			else:
				# RELEASE = execute move order
				if is_right_click_held and selected_battalion:
					_order_move(get_global_mouse_position())
				is_right_click_held = false
				_hide_path_segments()
			get_viewport().set_input_as_handled()

		# Left-click: select battalion or deselect
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var clicked_battalion := get_battalion_at(get_global_mouse_position())
			if clicked_battalion:
				clicked_battalion.select()
			elif selected_battalion:
				selected_battalion.deselect()
			get_viewport().set_input_as_handled()

	# Update path preview ONLY while right-click is held
	if event is InputEventMouseMotion:
		if is_right_click_held and selected_battalion:
			_update_path_preview(get_global_mouse_position())


func _order_move(target: Vector2) -> void:
	if not selected_battalion:
		return

	# Clamp to map bounds
	target.x = clampf(target.x, map_bounds.position.x + 50, map_bounds.end.x - 50)
	target.y = clampf(target.y, map_bounds.position.y + 50, map_bounds.end.y - 50)

	var battalion_data = selected_battalion.battalion_data
	var start_pos := selected_battalion.position
	var total_distance := start_pos.distance_to(target)
	var movement_cost := total_distance * MOVEMENT_COST_PER_PIXEL
	var current_mp: float = battalion_data.movement_points

	# Clear any existing queued path (new orders replace old)
	if battalion_data.has_queued_path():
		battalion_data.clear_queued_path()
		CampaignSignals.path_interrupted.emit(selected_battalion)

	if current_mp >= movement_cost:
		# Can reach this turn - immediate move, no queue
		selected_battalion.move_to(target)
	else:
		# Multi-turn journey: move as far as possible this turn, queue destination
		var reachable_distance := current_mp / MOVEMENT_COST_PER_PIXEL
		var direction := (target - start_pos).normalized()
		var this_turn_target := start_pos + direction * reachable_distance

		# Queue the final destination
		battalion_data.set_queued_path([target])
		CampaignSignals.path_queued.emit(selected_battalion, [target])

		# Move to this turn's limit
		selected_battalion.move_to(this_turn_target)

	_hide_path_segments()


func _update_path_preview(target: Vector2) -> void:
	if not selected_battalion:
		return

	var battalion_data = selected_battalion.battalion_data
	var start := selected_battalion.position
	var current_mp: float = battalion_data.movement_points
	var max_mp: float = battalion_data.max_movement_points

	# Calculate path segments for multi-turn visualization
	var segments := _calculate_path_segments(start, target, current_mp, max_mp)
	_render_path_segments(segments)


func _on_battalion_selected(battalion: Node2D) -> void:
	# Deselect previous
	if selected_battalion and selected_battalion != battalion:
		selected_battalion.deselect()

	selected_battalion = battalion

	# Show movement range circle
	_update_range_circle()

	# Update HUD
	if hud and hud.has_method("show_battalion_info"):
		hud.show_battalion_info(battalion.battalion_data)


func _on_battalion_deselected() -> void:
	selected_battalion = null
	is_right_click_held = false
	_hide_path_segments()
	_hide_range_circle()

	if hud and hud.has_method("hide_battalion_info"):
		hud.hide_battalion_info()


func _on_movement_points_changed(battalion: Node2D, remaining: float) -> void:
	# Update range circle when selected battalion's movement changes
	if battalion == selected_battalion:
		_update_range_circle()


func get_battalion_at(position: Vector2) -> Node2D:
	for battalion in battalions_container.get_children():
		if battalion.position.distance_to(position) < 30:
			return battalion
	return null


func _input(event: InputEvent) -> void:
	# Press B to start a test battle with selected battalion
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		if selected_battalion:
			_start_test_battle()


func _start_test_battle() -> void:
	if not selected_battalion or not selected_battalion.battalion_data:
		return

	# Create test enemy regiments
	var enemy_regiments: Array = []

	var enemy_swords := RegimentData.new()
	enemy_swords.regiment_name = "Bandit Swordsmen"
	enemy_swords.unit_type = UnitType.Type.INFANTRY
	enemy_swords.max_soldiers = 30
	enemy_swords.current_soldiers = 30
	enemy_swords.attack = 8
	enemy_swords.defense = 8
	enemy_swords.faction_color = Color.RED
	enemy_regiments.append(enemy_swords)

	var enemy_spears := RegimentData.new()
	enemy_spears.regiment_name = "Bandit Spearmen"
	enemy_spears.unit_type = UnitType.Type.INFANTRY
	enemy_spears.max_soldiers = 25
	enemy_spears.current_soldiers = 25
	enemy_spears.attack = 7
	enemy_spears.defense = 10
	enemy_spears.faction_color = Color.RED
	enemy_regiments.append(enemy_spears)

	# Start battle through transition system
	BattleTransition.start_battle_from_campaign(
		selected_battalion.battalion_data,
		enemy_regiments,
		"plains"
	)


# =====================
# Multi-Turn Path System
# =====================

func _initialize_path_segments() -> void:
	# Create pooled Line2D nodes for path visualization
	for i in range(segment_pool_size):
		var line := Line2D.new()
		line.width = 4.0
		line.visible = false
		line.z_index = 5  # Above terrain, below units
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		add_child(line)
		path_segments.append(line)


func _calculate_path_segments(start: Vector2, end: Vector2, current_mp: float, max_mp: float) -> Array:
	"""
	Calculate path segments for multi-turn movement visualization.
	Returns array of {start: Vector2, end: Vector2, turn: int} dictionaries.
	"""
	var segments: Array = []
	var total_distance := start.distance_to(end)

	# Always show path, even for very short distances (minimum 5 pixels to avoid jitter)
	if total_distance < 5.0:
		return segments

	var direction := (end - start).normalized()

	var remaining_distance := total_distance
	var segment_start := start
	var turn := 0
	var mp_available := current_mp

	while remaining_distance > 0.01:
		# How far can we go this turn?
		var reachable_distance := mp_available / MOVEMENT_COST_PER_PIXEL

		if reachable_distance >= remaining_distance:
			# Can finish this turn
			segments.append({
				"start": segment_start,
				"end": end,
				"turn": turn
			})
			break
		else:
			# Partial progress this turn
			var segment_end := segment_start + direction * reachable_distance
			segments.append({
				"start": segment_start,
				"end": segment_end,
				"turn": turn
			})

			# Move to next turn
			segment_start = segment_end
			remaining_distance -= reachable_distance
			turn += 1
			mp_available = max_mp  # Full movement next turn

	return segments


func _render_path_segments(segments: Array) -> void:
	# Hide all segments first
	for line in path_segments:
		line.visible = false

	# Render each segment with appropriate turn color
	for i in range(mini(segments.size(), path_segments.size())):
		var seg: Dictionary = segments[i]
		var line: Line2D = path_segments[i]

		line.clear_points()
		line.add_point(seg.start)
		line.add_point(seg.end)

		# Color based on turn (clamp to available colors)
		var turn_index: int = mini(seg.turn, TURN_COLORS.size() - 1)
		line.default_color = TURN_COLORS[turn_index]
		line.visible = true


func _hide_path_segments() -> void:
	for line in path_segments:
		line.visible = false
	if path_preview:
		path_preview.visible = false


# =====================
# Turn Auto-Movement
# =====================

func _on_turn_started(_turn: int) -> void:
	# Refresh movement range circle for selected battalion (MP just got reset)
	if selected_battalion:
		_update_range_circle()

	# Brief delay for visual clarity before auto-movement
	await get_tree().create_timer(0.3).timeout

	# Continue movement for all battalions with queued paths
	for battalion in battalions_container.get_children():
		if battalion.battalion_data and battalion.battalion_data.has_queued_path():
			_continue_queued_movement(battalion)


func _continue_queued_movement(battalion: Node2D) -> void:
	var battalion_data = battalion.battalion_data
	if not battalion_data.has_queued_path():
		return

	var waypoint: Vector2 = battalion_data.get_next_waypoint()
	var start_pos := battalion.position
	var distance := start_pos.distance_to(waypoint)
	var movement_cost := distance * MOVEMENT_COST_PER_PIXEL
	var current_mp: float = battalion_data.movement_points

	if current_mp >= movement_cost:
		# Can reach waypoint this turn - consume it
		battalion_data.consume_waypoint()
		battalion.move_to(waypoint)

		# Check if path complete
		if not battalion_data.has_queued_path():
			CampaignSignals.path_completed.emit(battalion)
	else:
		# Move partial distance toward waypoint
		var reachable_distance := current_mp / MOVEMENT_COST_PER_PIXEL
		var direction := (waypoint - start_pos).normalized()
		var this_turn_target := start_pos + direction * reachable_distance
		battalion.move_to(this_turn_target)


# =====================
# Movement Range Circle
# =====================

func _initialize_range_circle() -> void:
	movement_range_circle = Line2D.new()
	movement_range_circle.width = 3.0
	movement_range_circle.default_color = RANGE_CIRCLE_COLOR
	movement_range_circle.closed = true
	movement_range_circle.visible = false
	movement_range_circle.z_index = 4  # Below path lines
	add_child(movement_range_circle)


func _update_range_circle() -> void:
	if not selected_battalion or not movement_range_circle:
		return

	var battalion_data = selected_battalion.battalion_data
	var center := selected_battalion.position
	var current_mp: float = battalion_data.movement_points
	var radius := current_mp / MOVEMENT_COST_PER_PIXEL

	# Don't show if no movement left
	if radius < 10.0:
		movement_range_circle.visible = false
		return

	# Generate circle points
	movement_range_circle.clear_points()
	for i in range(RANGE_CIRCLE_SEGMENTS):
		var angle := (float(i) / RANGE_CIRCLE_SEGMENTS) * TAU
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		movement_range_circle.add_point(point)

	movement_range_circle.visible = true


func _hide_range_circle() -> void:
	if movement_range_circle:
		movement_range_circle.visible = false
