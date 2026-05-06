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
const COLOR_INCOME := Color(0.5, 0.85, 0.5, 1.0)

# Currently displayed battalion (for refreshing on turn end)
var _current_battalion_data = null

# Contract UI elements
var contracts_button: Button = null
var contract_list_panel: Control = null
var income_label: Label = null


func _ready() -> void:
	_create_contracts_button()
	_create_contract_panel()
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


# =============================================================================
# CONTRACT UI
# =============================================================================

func _create_contracts_button() -> void:
	## Create the Contracts button in the top bar
	if not $TopBar:
		return

	# Find the spacer to insert before it
	var spacer: Control = null
	for child in $TopBar.get_children():
		if child.name == "Spacer":
			spacer = child
			break

	if not spacer:
		return

	# Create income label (shows settlement income)
	income_label = Label.new()
	income_label.text = ""
	income_label.add_theme_color_override("font_color", COLOR_INCOME)
	income_label.add_theme_font_size_override("font_size", 18)
	$TopBar.add_child(income_label)
	$TopBar.move_child(income_label, spacer.get_index())

	# Create contracts button
	contracts_button = Button.new()
	contracts_button.text = "Contracts"
	contracts_button.add_theme_font_size_override("font_size", 18)
	contracts_button.pressed.connect(_on_contracts_button_pressed)
	$TopBar.add_child(contracts_button)
	$TopBar.move_child(contracts_button, spacer.get_index())


func _create_contract_panel() -> void:
	## Create the contract list panel
	var panel_script := load("res://campaign_system/ui/contract_list_panel.gd")
	if panel_script:
		contract_list_panel = PanelContainer.new()
		contract_list_panel.set_script(panel_script)
		contract_list_panel.visible = false

		# Position on right side of screen
		contract_list_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		contract_list_panel.offset_left = -340
		contract_list_panel.offset_top = 60
		contract_list_panel.offset_right = -20
		contract_list_panel.offset_bottom = 500

		add_child(contract_list_panel)


func _update_income_display() -> void:
	## Update the settlement income display
	if not income_label or not ContractManager:
		return

	var total_income: int = ContractManager.get_total_ongoing_income()
	if total_income > 0:
		income_label.text = "Income: +%d/turn" % total_income
	else:
		income_label.text = ""


func _on_contracts_button_pressed() -> void:
	if contract_list_panel:
		contract_list_panel.toggle_visibility()


func update_contract_button_state() -> void:
	## Update contracts button to show active contract indicator
	if not contracts_button or not ContractManager:
		return

	if ContractManager.has_active_contract():
		contracts_button.text = "Contracts [!]"
		contracts_button.add_theme_color_override("font_color", COLOR_GOLD)
	else:
		contracts_button.text = "Contracts"
		contracts_button.remove_theme_color_override("font_color")
