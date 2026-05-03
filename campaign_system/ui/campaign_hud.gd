# Campaign map HUD - displays gold, upkeep, turn info, and battalion panel.
extends CanvasLayer


@onready var gold_label: Label = $TopBar/GoldLabel
@onready var upkeep_label: Label = $TopBar/UpkeepLabel
@onready var turn_label: Label = $TopBar/TurnLabel
@onready var end_turn_button: Button = $TopBar/EndTurnButton
@onready var battalion_panel: Panel = $BattalionPanel
@onready var battalion_name_label: Label = $BattalionPanel/VBox/NameLabel
@onready var regiment_list: VBoxContainer = $BattalionPanel/VBox/RegimentList
@onready var movement_bar: ProgressBar = $BattalionPanel/VBox/MovementBar

# UI Colors
const COLOR_GOLD := Color(0.85, 0.7, 0.4, 1.0)
const COLOR_TEXT := Color(0.95, 0.92, 0.85, 1.0)
const COLOR_WARNING := Color(0.9, 0.3, 0.2, 1.0)

# Currently displayed battalion (for refreshing on turn end)
var _current_battalion_data = null


func _ready() -> void:
	# Connect signals
	CampaignSignals.gold_changed.connect(_on_gold_changed)
	CampaignSignals.turn_started.connect(_on_turn_started)
	CampaignSignals.movement_points_changed.connect(_on_movement_changed)
	CampaignSignals.battalion_selected.connect(_on_battalion_selected)
	CampaignSignals.battalion_deselected.connect(_on_battalion_deselected)

	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)

	# Initial state
	_update_display()
	hide_battalion_info()


func _update_display() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % CampaignManager.current_gold
		gold_label.add_theme_color_override("font_color", COLOR_GOLD)

	if upkeep_label:
		var upkeep := CampaignManager.get_total_upkeep()
		upkeep_label.text = "Upkeep: %d/turn" % upkeep
		# Warn if upkeep exceeds gold
		if upkeep > CampaignManager.current_gold:
			upkeep_label.add_theme_color_override("font_color", COLOR_WARNING)
		else:
			upkeep_label.add_theme_color_override("font_color", COLOR_TEXT)

	if turn_label:
		turn_label.text = "Turn: %d" % CampaignManager.turn_number


func show_battalion_info(battalion_data) -> void:
	if not battalion_panel:
		return

	battalion_panel.visible = true

	if battalion_name_label:
		battalion_name_label.text = battalion_data.battalion_name

	if movement_bar:
		movement_bar.max_value = battalion_data.max_movement_points
		movement_bar.value = battalion_data.movement_points

	# Populate regiment list
	if regiment_list:
		for child in regiment_list.get_children():
			child.queue_free()

		for regiment in battalion_data.regiments:
			var label := Label.new()
			label.text = "%s (%d/%d)" % [
				regiment.regiment_name,
				regiment.current_soldiers,
				regiment.max_soldiers
			]
			label.add_theme_color_override("font_color", COLOR_TEXT)
			regiment_list.add_child(label)


func hide_battalion_info() -> void:
	if battalion_panel:
		battalion_panel.visible = false


func _on_gold_changed(new_amount: int, _delta: int) -> void:
	_update_display()


func _on_turn_started(turn: int) -> void:
	_update_display()


func _on_movement_changed(battalion: Node2D, remaining: float) -> void:
	if movement_bar and battalion_panel.visible:
		movement_bar.value = remaining


func _on_battalion_selected(battalion: Node2D) -> void:
	show_battalion_info(battalion.battalion_data)


func _on_battalion_deselected() -> void:
	hide_battalion_info()


func _on_end_turn_pressed() -> void:
	CampaignManager.end_turn()
	_update_display()
