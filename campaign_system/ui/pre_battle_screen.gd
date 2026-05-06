# Pre-battle screen showing army comparison, unit roster, and preparation options.
# Inspired by Shadow of the Horned Rat's paymaster system.
# Creates its own UI dynamically - no scene file required.
class_name PreBattleScreen
extends Control


signal battle_started
signal battle_cancelled
signal mercenary_hired(regiment: Resource)
signal unit_refitted(regiment: Resource, upgrade_type: String)


# UI color constants
const BG_COLOR := Color(0.12, 0.1, 0.08, 0.95)
const HEADER_COLOR := Color(0.95, 0.92, 0.85, 1.0)
const TEXT_COLOR := Color(0.8, 0.78, 0.7, 1.0)
const ACCENT_COLOR := Color(0.8, 0.7, 0.4, 1.0)

# References to child panels (created dynamically)
var army_comparison: Control = null
var unit_roster: Control = null
var tab_container: TabContainer = null
var mercenary_shop: Control = null
var refit_panel: Control = null
var reinforcement_panel: Control = null

var battle_title: Label = null
var difficulty_label: Label = null
var gold_label: Label = null
var upkeep_label: Label = null
var begin_button: Button = null
var cancel_button: Button = null

# Battle data
var player_battalion: Resource = null  # BattalionData
var enemy_data: Dictionary = {}  # Enemy army info
var contract_data: Resource = null  # Optional contract
var is_in_friendly_territory: bool = false

# Unit detail popup
var unit_detail_popup: Control = null


func _ready() -> void:
	_create_ui()
	_create_unit_detail_popup()
	visible = false


func _create_ui() -> void:
	# Full screen background
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main container with margin
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)

	# Header section
	_create_header(main_vbox)

	# Main content area (comparison + roster)
	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(content_hbox)

	# Army comparison panel (left side)
	_create_army_comparison(content_hbox)

	# Unit roster panel (right side)
	_create_unit_roster(content_hbox)

	# Tab section for mercenaries, refit, reinforcements
	_create_tab_section(main_vbox)

	# Footer with buttons
	_create_footer(main_vbox)


func _create_header(parent: Control) -> void:
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 20)
	parent.add_child(header_hbox)

	battle_title = Label.new()
	battle_title.text = "BATTLE: Unknown"
	battle_title.add_theme_color_override("font_color", HEADER_COLOR)
	battle_title.add_theme_font_size_override("font_size", 24)
	battle_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(battle_title)

	difficulty_label = Label.new()
	difficulty_label.text = "[**---]"
	difficulty_label.add_theme_color_override("font_color", ACCENT_COLOR)
	difficulty_label.add_theme_font_size_override("font_size", 20)
	header_hbox.add_child(difficulty_label)


func _create_army_comparison(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	# Load and instantiate army comparison script
	var script := load("res://campaign_system/ui/army_comparison_panel.gd")
	if script:
		army_comparison = Control.new()
		army_comparison.set_script(script)
		army_comparison.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(army_comparison)


func _create_unit_roster(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	# Load and instantiate unit roster script
	var script := load("res://campaign_system/ui/unit_roster_panel.gd")
	if script:
		unit_roster = Control.new()
		unit_roster.set_script(script)
		unit_roster.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.add_child(unit_roster)

		# Connect signals
		if unit_roster.has_signal("unit_right_clicked"):
			unit_roster.unit_right_clicked.connect(_on_unit_card_right_clicked)
		if unit_roster.has_signal("unit_clicked"):
			unit_roster.unit_clicked.connect(_on_unit_card_clicked)


func _create_tab_section(parent: Control) -> void:
	tab_container = TabContainer.new()
	tab_container.custom_minimum_size = Vector2(0, 200)
	parent.add_child(tab_container)

	# Army Overview tab (placeholder)
	var overview := Control.new()
	overview.name = "Army Overview"
	tab_container.add_child(overview)

	var overview_label := Label.new()
	overview_label.text = "Army overview and statistics"
	overview_label.add_theme_color_override("font_color", TEXT_COLOR)
	overview.add_child(overview_label)

	# Contracts tab - shows current contract and available contracts
	_create_contracts_tab()

	# Mercenaries tab
	var merc_script := load("res://campaign_system/ui/mercenary_shop.gd")
	if merc_script:
		mercenary_shop = Control.new()
		mercenary_shop.set_script(merc_script)
		mercenary_shop.name = "Mercenaries"
		tab_container.add_child(mercenary_shop)

	# Refit tab
	var refit_script := load("res://campaign_system/ui/refit_panel.gd")
	if refit_script:
		refit_panel = Control.new()
		refit_panel.set_script(refit_script)
		refit_panel.name = "Refit Units"
		tab_container.add_child(refit_panel)

	# Reinforcements tab
	var reinforce_script := load("res://campaign_system/ui/reinforcement_panel.gd")
	if reinforce_script:
		reinforcement_panel = Control.new()
		reinforcement_panel.set_script(reinforce_script)
		reinforcement_panel.name = "Reinforcements"
		tab_container.add_child(reinforcement_panel)


func _create_footer(parent: Control) -> void:
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 20)
	parent.add_child(footer_hbox)

	gold_label = Label.new()
	gold_label.text = "Gold: 0"
	gold_label.add_theme_color_override("font_color", ACCENT_COLOR)
	footer_hbox.add_child(gold_label)

	upkeep_label = Label.new()
	upkeep_label.text = "Upkeep: 0/turn"
	upkeep_label.add_theme_color_override("font_color", TEXT_COLOR)
	footer_hbox.add_child(upkeep_label)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(spacer)

	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(120, 40)
	cancel_button.pressed.connect(_on_cancel_pressed)
	footer_hbox.add_child(cancel_button)

	begin_button = Button.new()
	begin_button.text = "Begin Battle"
	begin_button.custom_minimum_size = Vector2(150, 40)
	begin_button.pressed.connect(_on_begin_pressed)
	footer_hbox.add_child(begin_button)


func _create_unit_detail_popup() -> void:
	var popup_script := load("res://campaign_system/ui/unit_detail_panel.gd")
	if popup_script:
		unit_detail_popup = Control.new()
		unit_detail_popup.set_script(popup_script)
		unit_detail_popup.visible = false
		add_child(unit_detail_popup)


func show_pre_battle(battalion: Resource, enemy: Dictionary, contract: Resource = null, friendly_territory: bool = false) -> void:
	player_battalion = battalion
	enemy_data = enemy
	contract_data = contract
	is_in_friendly_territory = friendly_territory

	_refresh_display()
	visible = true

	# Emit signal
	CampaignSignals.pre_battle_opened.emit(battalion, null)


func _refresh_display() -> void:
	_update_header()
	_update_army_comparison()
	_update_unit_roster()
	_update_tabs()
	_update_footer()


func _update_header() -> void:
	if not battle_title:
		return

	if contract_data and "title" in contract_data:
		battle_title.text = "CONTRACT: %s" % contract_data.title
		var diff: int = contract_data.difficulty if "difficulty" in contract_data else 2
		difficulty_label.text = _get_difficulty_stars(diff)
	else:
		var location: String = enemy_data.get("location", "Unknown")
		battle_title.text = "BATTLE: %s" % location
		difficulty_label.text = _get_difficulty_stars(enemy_data.get("difficulty", 2))


func _get_difficulty_stars(level: int) -> String:
	var filled := ""
	var empty := ""
	for i in range(5):
		if i < level:
			filled += "*"
		else:
			empty += "-"
	return "[%s%s]" % [filled, empty]


func _update_army_comparison() -> void:
	if army_comparison and army_comparison.has_method("update_comparison"):
		army_comparison.update_comparison(player_battalion, enemy_data)


func _update_unit_roster() -> void:
	if unit_roster and unit_roster.has_method("display_roster"):
		unit_roster.display_roster(player_battalion.regiments)


func _update_tabs() -> void:
	# Disable refit tab if not in friendly territory
	if tab_container and refit_panel:
		var refit_index: int = tab_container.get_tab_idx_from_control(refit_panel)
		if refit_index >= 0:
			tab_container.set_tab_disabled(refit_index, not is_in_friendly_territory)
			if not is_in_friendly_territory:
				tab_container.set_tab_title(refit_index, "Refit (Unavailable)")
			else:
				tab_container.set_tab_title(refit_index, "Refit Units")

	# Update mercenary shop
	if mercenary_shop and mercenary_shop.has_method("refresh_available"):
		mercenary_shop.refresh_available()

	# Update reinforcement display
	if reinforcement_panel and reinforcement_panel.has_method("update_reinforcements"):
		reinforcement_panel.update_reinforcements(player_battalion)

	# Update contracts tab
	_update_contracts_tab()


func _update_footer() -> void:
	if gold_label:
		gold_label.text = "Gold: %d" % CampaignManager.current_gold

	if upkeep_label and player_battalion:
		upkeep_label.text = "Upkeep: %d/turn" % player_battalion.get_total_upkeep()


func show_unit_detail(regiment: Resource, screen_position: Vector2) -> void:
	if unit_detail_popup and unit_detail_popup.has_method("show_for_regiment"):
		unit_detail_popup.show_for_regiment(regiment, screen_position)


func hide_unit_detail() -> void:
	if unit_detail_popup:
		unit_detail_popup.visible = false


func _on_begin_pressed() -> void:
	visible = false
	battle_started.emit()


func _on_cancel_pressed() -> void:
	visible = false
	battle_cancelled.emit()


# =============================================================================
# Unit Roster Interaction
# =============================================================================

func _on_unit_card_right_clicked(regiment: Resource, position: Vector2) -> void:
	show_unit_detail(regiment, position)


func _on_unit_card_clicked(_regiment: Resource) -> void:
	# Select unit for potential actions
	pass


# =============================================================================
# Mercenary Hiring
# =============================================================================

func hire_mercenary(regiment: Resource, cost: int) -> bool:
	if CampaignManager.current_gold < cost:
		return false

	if not player_battalion.can_add_regiment():
		return false

	CampaignManager.current_gold -= cost
	player_battalion.regiments.append(regiment)

	mercenary_hired.emit(regiment)
	CampaignSignals.mercenary_hired.emit(regiment, cost)

	_refresh_display()
	return true


# =============================================================================
# Unit Refitting
# =============================================================================

func refit_unit(regiment: Resource, upgrade_type: String, cost: int) -> bool:
	if not is_in_friendly_territory:
		return false

	if CampaignManager.current_gold < cost:
		return false

	CampaignManager.current_gold -= cost

	match upgrade_type:
		"armor":
			var current: int = regiment.get_meta("armor_bonus", 0)
			regiment.set_meta("armor_bonus", current + 1)
		"attack":
			var current: int = regiment.get_meta("attack_bonus", 0)
			regiment.set_meta("attack_bonus", current + 1)

	unit_refitted.emit(regiment, upgrade_type)
	CampaignSignals.unit_refitted.emit(regiment, upgrade_type, cost)

	_refresh_display()
	return true


# =============================================================================
# Contracts Tab
# =============================================================================

var contracts_tab: Control = null
var active_contract_panel: VBoxContainer = null
var available_contracts_list: VBoxContainer = null

func _create_contracts_tab() -> void:
	## Create the contracts tab with active and available contracts
	contracts_tab = Control.new()
	contracts_tab.name = "Contracts"
	tab_container.add_child(contracts_tab)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 20)
	contracts_tab.add_child(hbox)

	# Left side: Active contract
	var active_panel := PanelContainer.new()
	active_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(active_panel)

	active_contract_panel = VBoxContainer.new()
	active_contract_panel.add_theme_constant_override("separation", 8)
	active_panel.add_child(active_contract_panel)

	var active_header := Label.new()
	active_header.text = "ACTIVE CONTRACT"
	active_header.add_theme_color_override("font_color", ACCENT_COLOR)
	active_header.add_theme_font_size_override("font_size", 16)
	active_contract_panel.add_child(active_header)

	# Right side: Available contracts
	var available_panel := PanelContainer.new()
	available_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(available_panel)

	var available_vbox := VBoxContainer.new()
	available_vbox.add_theme_constant_override("separation", 8)
	available_panel.add_child(available_vbox)

	var available_header := Label.new()
	available_header.text = "AVAILABLE CONTRACTS"
	available_header.add_theme_color_override("font_color", HEADER_COLOR)
	available_header.add_theme_font_size_override("font_size", 16)
	available_vbox.add_child(available_header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	available_vbox.add_child(scroll)

	available_contracts_list = VBoxContainer.new()
	available_contracts_list.add_theme_constant_override("separation", 6)
	scroll.add_child(available_contracts_list)


func _update_contracts_tab() -> void:
	## Refresh the contracts tab display
	if not contracts_tab or not ContractManager:
		return

	# Clear previous content
	for child in active_contract_panel.get_children():
		if child is Label and child.text == "ACTIVE CONTRACT":
			continue
		child.queue_free()

	for child in available_contracts_list.get_children():
		child.queue_free()

	# Display active contract
	var active := ContractManager.get_active_contract()
	if active:
		_add_contract_display(active_contract_panel, active, true)
	else:
		var no_active := Label.new()
		no_active.text = "No active contract.\nAccept one from the list."
		no_active.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5, 1.0))
		active_contract_panel.add_child(no_active)

	# Display available contracts
	var available := ContractManager.get_available_contracts()
	if available.is_empty():
		var no_contracts := Label.new()
		no_contracts.text = "No contracts available."
		no_contracts.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5, 1.0))
		available_contracts_list.add_child(no_contracts)
	else:
		for contract in available:
			_add_contract_display(available_contracts_list, contract, false)


func _add_contract_display(parent: Control, contract: ContractData, is_active: bool) -> void:
	## Add a contract display to the given container
	var panel := PanelContainer.new()
	parent.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.1, 0.8)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# Header: stars + name
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var stars := Label.new()
	stars.text = contract.get_threat_stars()
	stars.add_theme_color_override("font_color", ACCENT_COLOR)
	header.add_child(stars)

	var name_label := Label.new()
	name_label.text = "  " + contract.contract_name
	name_label.add_theme_color_override("font_color", HEADER_COLOR)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	# Info row
	var info := Label.new()
	info.text = "%s - %s  |  ~%d enemies  |  %s" % [
		contract.get_objective_text(),
		contract.region_name,
		contract.get_total_enemies(),
		contract.get_reward_text()
	]
	info.add_theme_color_override("font_color", TEXT_COLOR)
	vbox.add_child(info)

	# Buttons
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)
	vbox.add_child(button_row)

	# Show on Map button
	var map_button := Button.new()
	map_button.text = "Show on Map"
	map_button.pressed.connect(func(): _zoom_to_contract(contract))
	button_row.add_child(map_button)

	if not is_active:
		# Accept button for available contracts
		var accept_button := Button.new()
		accept_button.text = "Accept"
		accept_button.pressed.connect(func(): _accept_contract_from_tab(contract))
		button_row.add_child(accept_button)

		# Disable if already have active contract
		if ContractManager.has_active_contract():
			accept_button.disabled = true


func _accept_contract_from_tab(contract: ContractData) -> void:
	## Accept a contract from the contracts tab
	if ContractManager.accept_contract(contract):
		_update_contracts_tab()


func _zoom_to_contract(contract: ContractData) -> void:
	## Signal the map to zoom to this contract's location
	CampaignSignals.contract_selected.emit(contract)


# =============================================================================
# Strength Calculations
# =============================================================================

func get_player_strength() -> Dictionary:
	return player_battalion.get_strength_summary()


func get_enemy_strength() -> Dictionary:
	return {
		"total": enemy_data.get("estimated_soldiers", 0),
		"infantry": enemy_data.get("infantry_estimate", 0),
		"ranged": enemy_data.get("ranged_estimate", 0),
		"cavalry": enemy_data.get("cavalry_estimate", 0),
		"known": enemy_data.get("scouted", false)
	}


func get_strength_ratio() -> float:
	var player_total: int = get_player_strength().total
	var enemy_total: int = get_enemy_strength().total

	if enemy_total == 0:
		return 999.0

	return float(player_total) / float(enemy_total)


# =============================================================================
# Deployment Data
# =============================================================================

func get_deployment_order() -> Dictionary:
	# Get deployment order from reinforcement panel
	if reinforcement_panel and reinforcement_panel.has_method("get_deployment_order"):
		return reinforcement_panel.get_deployment_order()

	# Fallback: all units as core
	return {
		"core": player_battalion.regiments.duplicate(),
		"reinforcements": []
	}
