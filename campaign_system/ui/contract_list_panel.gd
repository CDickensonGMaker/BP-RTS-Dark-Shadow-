# Panel showing available contracts and active contract status.
# Add this to the campaign HUD to let players browse and accept contracts.
extends PanelContainer


const ContractCardScript = preload("res://campaign_system/ui/contract_card.gd")

# UI Colors
const COLOR_GOLD := Color(0.85, 0.7, 0.4, 1.0)
const COLOR_TEXT := Color(0.95, 0.92, 0.85, 1.0)
const COLOR_ACTIVE := Color(0.5, 0.85, 0.5, 1.0)
const COLOR_HEADER := Color(0.8, 0.75, 0.65, 1.0)

# UI nodes
var _title_label: Label
var _active_contract_box: VBoxContainer
var _active_label: Label
var _abandon_button: Button
var _separator: HSeparator
var _available_label: Label
var _scroll_container: ScrollContainer
var _contract_list: VBoxContainer
var _no_contracts_label: Label
var _close_button: Button

# Card instances
var _contract_cards: Array = []
var _selected_contract: ContractData = null


func _ready() -> void:
	_build_ui()

	# Connect to ContractManager signals
	if CampaignSignals:
		CampaignSignals.contracts_refreshed.connect(_on_contracts_refreshed)
		CampaignSignals.contract_accepted.connect(_on_contract_accepted)
		CampaignSignals.contract_completed.connect(_on_contract_completed)

	# Initial refresh
	call_deferred("_refresh_display")


func _build_ui() -> void:
	# Panel styling
	custom_minimum_size = Vector2(320, 400)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 0.98)
	style.border_color = Color(0.5, 0.4, 0.3, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)

	# Main vertical layout
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	add_child(main_vbox)

	# Header row
	var header_box := HBoxContainer.new()
	main_vbox.add_child(header_box)

	_title_label = Label.new()
	_title_label.text = "CONTRACTS"
	_title_label.add_theme_color_override("font_color", COLOR_HEADER)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_child(_title_label)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(24, 24)
	_close_button.pressed.connect(_on_close_pressed)
	header_box.add_child(_close_button)

	# Active contract section
	_active_contract_box = VBoxContainer.new()
	_active_contract_box.add_theme_constant_override("separation", 4)
	_active_contract_box.visible = false
	main_vbox.add_child(_active_contract_box)

	var active_header := Label.new()
	active_header.text = "Active Contract:"
	active_header.add_theme_color_override("font_color", COLOR_ACTIVE)
	_active_contract_box.add_child(active_header)

	_active_label = Label.new()
	_active_label.add_theme_color_override("font_color", COLOR_TEXT)
	_active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_active_contract_box.add_child(_active_label)

	_abandon_button = Button.new()
	_abandon_button.text = "Abandon Contract"
	_abandon_button.pressed.connect(_on_abandon_pressed)
	_active_contract_box.add_child(_abandon_button)

	# Separator
	_separator = HSeparator.new()
	main_vbox.add_child(_separator)

	# Available contracts header
	_available_label = Label.new()
	_available_label.text = "Available Contracts"
	_available_label.add_theme_color_override("font_color", COLOR_HEADER)
	main_vbox.add_child(_available_label)

	# Scroll container for contract list
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.custom_minimum_size = Vector2(0, 200)
	main_vbox.add_child(_scroll_container)

	_contract_list = VBoxContainer.new()
	_contract_list.add_theme_constant_override("separation", 8)
	_contract_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.add_child(_contract_list)

	# No contracts placeholder
	_no_contracts_label = Label.new()
	_no_contracts_label.text = "No contracts available.\nCheck back next turn."
	_no_contracts_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5, 1.0))
	_no_contracts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_contracts_label.visible = false
	main_vbox.add_child(_no_contracts_label)


func _refresh_display() -> void:
	## Update the panel display based on current ContractManager state
	if not ContractManager:
		return

	# Update active contract section
	var active := ContractManager.get_active_contract()
	if active:
		_active_contract_box.visible = true
		_active_label.text = "%s\n%s - %s" % [
			active.contract_name,
			active.get_objective_text(),
			active.region_name
		]
		_available_label.text = "Available Contracts (Contract Active)"
	else:
		_active_contract_box.visible = false
		_available_label.text = "Available Contracts"

	# Clear existing cards
	for card in _contract_cards:
		card.queue_free()
	_contract_cards.clear()

	# Get available contracts
	var contracts := ContractManager.get_available_contracts()

	if contracts.is_empty():
		_no_contracts_label.visible = true
		_scroll_container.visible = false
	else:
		_no_contracts_label.visible = false
		_scroll_container.visible = true

		# Create cards for each contract
		for contract in contracts:
			var card := PanelContainer.new()
			card.set_script(ContractCardScript)
			_contract_list.add_child(card)
			card.setup(contract)
			card.contract_accepted.connect(_on_card_accept_pressed)
			card.contract_selected.connect(_on_card_selected)
			_contract_cards.append(card)

			# Disable accept button if already have active contract
			if active and card.has_method("set_accept_enabled"):
				card.set_accept_enabled(false)


func _on_contracts_refreshed(_contracts: Array) -> void:
	_refresh_display()


func _on_contract_accepted(_contract: ContractData) -> void:
	_refresh_display()


func _on_contract_completed(_contract: ContractData, _success: bool) -> void:
	_refresh_display()


func _on_card_accept_pressed(contract: ContractData) -> void:
	if ContractManager.accept_contract(contract):
		_refresh_display()


func _on_card_selected(contract: ContractData) -> void:
	_selected_contract = contract
	# Update card highlighting
	for card in _contract_cards:
		if card.has_method("set_active"):
			card.set_active(card.contract == contract)
	# Emit signal for map highlighting
	CampaignSignals.contract_selected.emit(contract)


func _on_abandon_pressed() -> void:
	ContractManager.abandon_contract()
	_refresh_display()


func _on_close_pressed() -> void:
	visible = false


func toggle_visibility() -> void:
	## Toggle panel visibility (for button binding)
	visible = not visible
	if visible:
		_refresh_display()
