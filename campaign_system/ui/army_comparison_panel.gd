# Panel displaying side-by-side comparison of player vs enemy army strength.
# Shows total soldiers, unit breakdown, morale, and supply status.
class_name ArmyComparisonPanel
extends Control


# UI References (set these in the scene or create dynamically)
@onready var player_panel: Control = $HBoxContainer/PlayerPanel
@onready var enemy_panel: Control = $HBoxContainer/EnemyPanel
@onready var vs_label: Label = $HBoxContainer/VSLabel

# Player side labels
@onready var player_title: Label = $HBoxContainer/PlayerPanel/VBox/Title
@onready var player_total: Label = $HBoxContainer/PlayerPanel/VBox/TotalSoldiers
@onready var player_infantry: Label = $HBoxContainer/PlayerPanel/VBox/Infantry
@onready var player_ranged: Label = $HBoxContainer/PlayerPanel/VBox/Ranged
@onready var player_cavalry: Label = $HBoxContainer/PlayerPanel/VBox/Cavalry
@onready var player_morale: Label = $HBoxContainer/PlayerPanel/VBox/Morale
@onready var player_supply: Label = $HBoxContainer/PlayerPanel/VBox/Supply

# Enemy side labels
@onready var enemy_title: Label = $HBoxContainer/EnemyPanel/VBox/Title
@onready var enemy_total: Label = $HBoxContainer/EnemyPanel/VBox/TotalSoldiers
@onready var enemy_infantry: Label = $HBoxContainer/EnemyPanel/VBox/Infantry
@onready var enemy_ranged: Label = $HBoxContainer/EnemyPanel/VBox/Ranged
@onready var enemy_cavalry: Label = $HBoxContainer/EnemyPanel/VBox/Cavalry
@onready var enemy_morale: Label = $HBoxContainer/EnemyPanel/VBox/Morale

# Strength bar (visual comparison)
@onready var strength_bar: ProgressBar = $StrengthBar

# Colors
const COLOR_ADVANTAGE := Color(0.2, 0.8, 0.2)  # Green
const COLOR_DISADVANTAGE := Color(0.8, 0.2, 0.2)  # Red
const COLOR_NEUTRAL := Color(0.8, 0.8, 0.8)  # Gray
const COLOR_UNKNOWN := Color(0.5, 0.5, 0.5)  # Dark gray


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# Create UI if not set up in scene
	if not player_panel:
		_create_comparison_ui()


func _create_comparison_ui() -> void:
	# Dynamically create the comparison UI
	var hbox := HBoxContainer.new()
	hbox.name = "HBoxContainer"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# Player panel
	player_panel = _create_army_panel("YOUR FORCES", true)
	hbox.add_child(player_panel)

	# VS label
	vs_label = Label.new()
	vs_label.name = "VSLabel"
	vs_label.text = "VS"
	vs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs_label.custom_minimum_size = Vector2(60, 0)
	hbox.add_child(vs_label)

	# Enemy panel
	enemy_panel = _create_army_panel("ENEMY FORCES", false)
	hbox.add_child(enemy_panel)

	# Strength bar
	strength_bar = ProgressBar.new()
	strength_bar.name = "StrengthBar"
	strength_bar.min_value = 0
	strength_bar.max_value = 100
	strength_bar.value = 50
	strength_bar.show_percentage = false
	strength_bar.custom_minimum_size = Vector2(0, 20)
	add_child(strength_bar)


func _create_army_panel(title: String, is_player: bool) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	panel.add_child(vbox)

	# Title
	var title_label := Label.new()
	title_label.name = "Title"
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Separator
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Stats
	var stats := ["TotalSoldiers", "Infantry", "Ranged", "Cavalry", "Morale", "Supply"]
	for stat in stats:
		var label := Label.new()
		label.name = stat
		label.text = "%s: ---" % stat
		vbox.add_child(label)

		# Store reference
		if is_player:
			match stat:
				"TotalSoldiers": player_total = label
				"Infantry": player_infantry = label
				"Ranged": player_ranged = label
				"Cavalry": player_cavalry = label
				"Morale": player_morale = label
				"Supply": player_supply = label
		else:
			match stat:
				"TotalSoldiers": enemy_total = label
				"Infantry": enemy_infantry = label
				"Ranged": enemy_ranged = label
				"Cavalry": enemy_cavalry = label
				"Morale": enemy_morale = label

	if is_player:
		player_title = vbox.get_node("Title")
	else:
		enemy_title = vbox.get_node("Title")

	return panel


func update_comparison(player_battalion: Resource, enemy_data: Dictionary) -> void:
	_update_player_side(player_battalion)
	_update_enemy_side(enemy_data)
	_update_strength_bar(player_battalion, enemy_data)


func _update_player_side(battalion: Resource) -> void:
	if not battalion:
		return

	var strength := battalion.get_strength_summary()

	if player_total:
		player_total.text = "Total: %d soldiers" % strength.total
	if player_infantry:
		player_infantry.text = "Infantry: %d" % strength.infantry
	if player_ranged:
		player_ranged.text = "Ranged: %d" % strength.ranged
	if player_cavalry:
		player_cavalry.text = "Cavalry: %d" % strength.cavalry

	# Morale status
	if player_morale:
		var avg_morale := _get_average_morale(battalion)
		player_morale.text = "Morale: %s" % _morale_to_text(avg_morale)

	# Supply status
	if player_supply:
		player_supply.text = "Supply: %d%%" % int(battalion.supply_status)
		if battalion.supply_status < 50:
			player_supply.modulate = COLOR_DISADVANTAGE
		else:
			player_supply.modulate = COLOR_NEUTRAL


func _update_enemy_side(enemy_data: Dictionary) -> void:
	var scouted: bool = enemy_data.get("scouted", false)

	if enemy_total:
		var total: int = enemy_data.get("estimated_soldiers", 0)
		if scouted:
			enemy_total.text = "Total: %d soldiers" % total
		else:
			enemy_total.text = "Total: ~%d soldiers" % total

	if enemy_infantry:
		if scouted:
			enemy_infantry.text = "Infantry: %d" % enemy_data.get("infantry", 0)
		else:
			enemy_infantry.text = "Infantry: ???"

	if enemy_ranged:
		if scouted:
			enemy_ranged.text = "Ranged: %d" % enemy_data.get("ranged", 0)
		else:
			enemy_ranged.text = "Ranged: ???"

	if enemy_cavalry:
		if scouted:
			enemy_cavalry.text = "Cavalry: %d" % enemy_data.get("cavalry", 0)
		else:
			enemy_cavalry.text = "Cavalry: ???"

	if enemy_morale:
		if scouted:
			enemy_morale.text = "Morale: %s" % enemy_data.get("morale_text", "Unknown")
		else:
			enemy_morale.text = "Morale: Unknown"
			enemy_morale.modulate = COLOR_UNKNOWN


func _update_strength_bar(battalion: Resource, enemy_data: Dictionary) -> void:
	if not strength_bar:
		return

	var player_strength: int = battalion.get_total_soldiers()
	var enemy_strength: int = enemy_data.get("estimated_soldiers", 1)

	var total := player_strength + enemy_strength
	if total == 0:
		total = 1

	var player_percent := (float(player_strength) / total) * 100.0
	strength_bar.value = player_percent

	# Color based on advantage
	if player_percent > 55:
		strength_bar.modulate = COLOR_ADVANTAGE
	elif player_percent < 45:
		strength_bar.modulate = COLOR_DISADVANTAGE
	else:
		strength_bar.modulate = COLOR_NEUTRAL


func _get_average_morale(battalion: Resource) -> float:
	var total_morale := 0.0
	var count := 0

	for regiment in battalion.regiments:
		if regiment.has_meta("base_morale"):
			total_morale += regiment.get_meta("base_morale")
			count += 1
		else:
			total_morale += 70.0  # Default
			count += 1

	if count == 0:
		return 70.0

	return total_morale / count


func _morale_to_text(morale: float) -> String:
	if morale >= 90:
		return "Excellent"
	elif morale >= 75:
		return "High"
	elif morale >= 60:
		return "Steady"
	elif morale >= 45:
		return "Wavering"
	elif morale >= 30:
		return "Shaken"
	else:
		return "Broken"


func get_strength_assessment() -> String:
	if not strength_bar:
		return "Unknown"

	var value: float = strength_bar.value
	if value > 65:
		return "Strong Advantage"
	elif value > 55:
		return "Slight Advantage"
	elif value > 45:
		return "Even Match"
	elif value > 35:
		return "Slight Disadvantage"
	else:
		return "Strong Disadvantage"
