class_name ControlGroupBar
extends Control

## Displays saved control groups at top of screen.
## Per bible §13.3:
## - Group number
## - Group composition icon (cav/inf/ranged mix)
## - Average health bar
## - Status (engaged, moving, idle)

const GROUP_COUNT: int = 10

var group_panels: Array[Panel] = []
var group_labels: Array[Label] = []
var group_health_bars: Array[ProgressBar] = []
var group_status_labels: Array[Label] = []
var group_composition_labels: Array[Label] = []

# Colors
const COLOR_PANEL_BG = Color(0.08, 0.06, 0.05, 0.9)
const COLOR_PANEL_BORDER = Color(0.6, 0.5, 0.3, 1.0)
const COLOR_GOLD = Color(0.85, 0.7, 0.4, 1.0)
const COLOR_ACTIVE = Color(0.4, 0.8, 0.5, 1.0)
const COLOR_INACTIVE = Color(0.4, 0.35, 0.3, 0.5)


func _ready():
	_setup_ui()
	_connect_signals()


func _setup_ui():
	# Container for all groups
	var container: HBoxContainer = HBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	container.offset_left = 10
	container.offset_top = 10
	container.add_theme_constant_override("separation", 5)
	add_child(container)

	for i in range(GROUP_COUNT):
		var panel: Panel = _create_group_panel(i)
		container.add_child(panel)
		group_panels.append(panel)
		panel.visible = false  # Hidden until group is saved


func _create_group_panel(group_id: int) -> Panel:
	var panel: Panel = Panel.new()
	panel.custom_minimum_size = Vector2(70, 55)  # Larger click target
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_INACTIVE
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	# Add hover effect
	panel.mouse_entered.connect(func(): _on_panel_hover(panel, true))
	panel.mouse_exited.connect(func(): _on_panel_hover(panel, false))

	# Group number (top left)
	var number_label: Label = Label.new()
	number_label.text = str((group_id + 1) % 10)  # 1-9, 0
	number_label.offset_left = 4
	number_label.offset_top = 2
	number_label.add_theme_font_size_override("font_size", 14)
	number_label.add_theme_color_override("font_color", COLOR_GOLD)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(number_label)
	group_labels.append(number_label)

	# Composition indicator (top right)
	var comp_label: Label = Label.new()
	comp_label.text = ""
	comp_label.offset_left = 40
	comp_label.offset_top = 2
	comp_label.add_theme_font_size_override("font_size", 10)
	comp_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1.0))
	comp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(comp_label)
	group_composition_labels.append(comp_label)

	# Health bar (middle)
	var health_bar: ProgressBar = ProgressBar.new()
	health_bar.offset_left = 4
	health_bar.offset_top = 22
	health_bar.offset_right = 66
	health_bar.offset_bottom = 32
	health_bar.min_value = 0.0
	health_bar.max_value = 1.0
	health_bar.value = 1.0
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(health_bar)
	group_health_bars.append(health_bar)

	# Status label (bottom)
	var status_label: Label = Label.new()
	status_label.text = "Idle"
	status_label.offset_left = 4
	status_label.offset_top = 36
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55, 1.0))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(status_label)
	group_status_labels.append(status_label)

	# Click handler
	panel.gui_input.connect(_on_panel_input.bind(group_id))

	return panel


func _connect_signals():
	if BattleSignals:
		BattleSignals.group_saved.connect(_on_group_saved)
		BattleSignals.group_recalled.connect(_on_group_recalled)


func _on_group_saved(group_id: int, regiments: Array):
	if group_id < 0 or group_id >= GROUP_COUNT:
		return

	var panel: Panel = group_panels[group_id]

	if regiments.is_empty():
		panel.visible = false
		return

	panel.visible = true
	_update_group_display(group_id, regiments)


func _on_group_recalled(group_id: int):
	if group_id < 0 or group_id >= GROUP_COUNT:
		return

	# Highlight the recalled group briefly
	var panel: Panel = group_panels[group_id]
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	style.border_color = COLOR_ACTIVE
	panel.add_theme_stylebox_override("panel", style)

	# Reset after short delay
	get_tree().create_timer(0.3).timeout.connect(func():
		style.border_color = COLOR_PANEL_BORDER
		panel.add_theme_stylebox_override("panel", style)
	)


func _update_group_display(group_id: int, regiments: Array):
	if regiments.is_empty():
		return

	# Calculate averages
	var total_health: float = 0.0
	var total_max_health: float = 0.0
	var infantry_count: int = 0
	var cavalry_count: int = 0
	var ranged_count: int = 0
	var status_counts: Dictionary = {}

	for reg in regiments:
		if not is_instance_valid(reg):
			continue

		total_health += reg.current_soldiers
		total_max_health += reg.data.max_soldiers

		match reg.data.unit_type:
			UnitType.Type.INFANTRY:
				infantry_count += 1
			UnitType.Type.CAVALRY:
				cavalry_count += 1
			UnitType.Type.RANGED:
				ranged_count += 1

		var state_name: String = Regiment.State.keys()[reg.state]
		status_counts[state_name] = status_counts.get(state_name, 0) + 1

	# Update health bar
	var health_ratio: float = total_health / maxf(total_max_health, 1.0)
	group_health_bars[group_id].value = health_ratio

	# Update composition
	var comp_str: String = ""
	if infantry_count > 0:
		comp_str += "I%d" % infantry_count
	if cavalry_count > 0:
		comp_str += "C%d" % cavalry_count
	if ranged_count > 0:
		comp_str += "R%d" % ranged_count
	group_composition_labels[group_id].text = comp_str

	# Update status (most common state)
	var max_count: int = 0
	var dominant_status: String = "Idle"
	for status in status_counts:
		if status_counts[status] > max_count:
			max_count = status_counts[status]
			dominant_status = status

	match dominant_status:
		"IDLE":
			group_status_labels[group_id].text = "Idle"
		"MARCHING":
			group_status_labels[group_id].text = "Moving"
		"ENGAGING":
			group_status_labels[group_id].text = "Fighting"
		"ROUTING":
			group_status_labels[group_id].text = "Routing!"
		_:
			group_status_labels[group_id].text = dominant_status.capitalize()


func _on_panel_input(event: InputEvent, group_id: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Click to select group
		if SelectionManager:
			SelectionManager._recall_group(group_id)


func _process(_delta):
	# Update group displays periodically
	if SelectionManager:
		for i in range(GROUP_COUNT):
			if SelectionManager.saved_groups.has(i):
				var regiments: Array = SelectionManager.saved_groups[i]
				# Filter out invalid regiments
				regiments = regiments.filter(func(r): return is_instance_valid(r))
				if regiments.is_empty():
					group_panels[i].visible = false
				else:
					_update_group_display(i, regiments)


func _on_panel_hover(panel: Panel, is_hovered: bool):
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	if is_hovered:
		style.border_color = COLOR_GOLD
		style.bg_color = Color(0.12, 0.10, 0.08, 0.95)
	else:
		style.border_color = COLOR_PANEL_BORDER
		style.bg_color = COLOR_PANEL_BG
	panel.add_theme_stylebox_override("panel", style)
