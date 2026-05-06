# Displays a single contract with info and accept button.
# Instantiate this for each available contract.
extends PanelContainer


signal contract_accepted(contract: ContractData)
signal contract_selected(contract: ContractData)

# UI Colors
const COLOR_GOLD := Color(0.85, 0.7, 0.4, 1.0)
const COLOR_TEXT := Color(0.95, 0.92, 0.85, 1.0)
const COLOR_STAR_FILLED := Color(1.0, 0.85, 0.2, 1.0)
const COLOR_STAR_EMPTY := Color(0.4, 0.4, 0.4, 1.0)
const COLOR_INCOME := Color(0.5, 0.85, 0.5, 1.0)

# Objective type icons
const OBJECTIVE_ICONS := {
	ContractData.ObjectiveType.DEFEAT_ARMY: "[BATTLE]",
	ContractData.ObjectiveType.SACK_CITY: "[RAID]",
	ContractData.ObjectiveType.OCCUPY_CITY: "[CAPTURE]",
	ContractData.ObjectiveType.CAPTURE_TERRITORY: "[CONQUER]",
}

# The contract this card displays
var contract: ContractData = null

# UI nodes (created dynamically)
var _header_box: HBoxContainer
var _threat_label: Label
var _name_label: Label
var _region_label: Label
var _objective_label: Label
var _info_box: HBoxContainer
var _enemies_label: Label
var _reward_label: Label
var _accept_button: Button


func _ready() -> void:
	# Build UI structure
	_build_ui()


func _build_ui() -> void:
	# Panel styling
	custom_minimum_size = Vector2(280, 100)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.1, 0.95)
	style.border_color = Color(0.4, 0.35, 0.25, 1.0)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)

	# Main container
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	# Header row: Threat stars + Name
	_header_box = HBoxContainer.new()
	_header_box.add_theme_constant_override("separation", 8)
	vbox.add_child(_header_box)

	_threat_label = Label.new()
	_threat_label.add_theme_color_override("font_color", COLOR_STAR_FILLED)
	_header_box.add_child(_threat_label)

	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", COLOR_TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_box.add_child(_name_label)

	# Objective type label
	_objective_label = Label.new()
	_objective_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9, 1.0))
	vbox.add_child(_objective_label)

	# Region
	_region_label = Label.new()
	_region_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.6, 1.0))
	vbox.add_child(_region_label)

	# Info row: enemies | reward
	_info_box = HBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 16)
	vbox.add_child(_info_box)

	_enemies_label = Label.new()
	_enemies_label.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5, 1.0))
	_info_box.add_child(_enemies_label)

	_reward_label = Label.new()
	_reward_label.add_theme_color_override("font_color", COLOR_GOLD)
	_reward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_box.add_child(_reward_label)

	# Accept button
	_accept_button = Button.new()
	_accept_button.text = "Accept"
	_accept_button.pressed.connect(_on_accept_pressed)
	_info_box.add_child(_accept_button)

	# Make card clickable
	gui_input.connect(_on_gui_input)


func setup(p_contract: ContractData) -> void:
	## Configure this card to display a contract
	contract = p_contract

	if not is_node_ready():
		await ready

	_refresh_display()


func _refresh_display() -> void:
	if not contract:
		return

	# Threat stars
	if _threat_label:
		_threat_label.text = contract.get_threat_stars()

	# Contract name
	if _name_label:
		_name_label.text = contract.contract_name

	# Objective type
	if _objective_label:
		var icon: String = OBJECTIVE_ICONS.get(contract.objective_type, "[?]")
		_objective_label.text = "%s %s" % [icon, contract.get_objective_text()]

	# Region
	if _region_label:
		_region_label.text = contract.region_name

	# Enemy count
	if _enemies_label:
		var enemy_count := contract.get_total_enemies()
		_enemies_label.text = "~%d enemies" % enemy_count

	# Reward (with ongoing income if applicable)
	if _reward_label:
		_reward_label.text = contract.get_reward_text()
		if contract.ongoing_income > 0:
			_reward_label.add_theme_color_override("font_color", COLOR_INCOME)


func set_active(is_active: bool) -> void:
	## Highlight this contract card as active/selected
	var style := get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		if is_active:
			style.border_color = COLOR_GOLD
		else:
			style.border_color = Color(0.4, 0.35, 0.25, 1.0)


func _on_accept_pressed() -> void:
	if contract:
		contract_accepted.emit(contract)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			contract_selected.emit(contract)
