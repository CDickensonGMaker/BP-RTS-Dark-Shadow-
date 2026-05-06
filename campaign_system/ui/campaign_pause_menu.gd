# Campaign Pause Menu - Access save/load/quit from campaign map
# Press ESC to toggle
extends CanvasLayer


var is_visible: bool = false
var main_panel: PanelContainer


func _ready() -> void:
	layer = 100
	_setup_ui()
	visible = false


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_visible:
			_hide_menu()
		else:
			_show_menu()
		get_viewport().set_input_as_handled()


func _setup_ui() -> void:
	# Darkener
	var darkener := ColorRect.new()
	darkener.set_anchors_preset(Control.PRESET_FULL_RECT)
	darkener.color = Color(0.0, 0.0, 0.0, 0.5)
	darkener.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(darkener)

	# Main panel
	main_panel = PanelContainer.new()
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.offset_left = -150
	main_panel.offset_right = 150
	main_panel.offset_top = -180
	main_panel.offset_bottom = 180

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.95)
	style.border_color = Color(0.7, 0.55, 0.35)
	style.set_border_width_all(3)
	style.set_corner_radius_all(6)
	main_panel.add_theme_stylebox_override("panel", style)
	add_child(main_panel)

	# Content
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	main_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.7, 0.55, 0.35))
	vbox.add_child(title)

	# Buttons
	var resume_btn := _create_button("Resume")
	resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_btn)

	var save_btn := _create_button("Save Game")
	save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(save_btn)

	var options_btn := _create_button("Options")
	options_btn.pressed.connect(_on_options_pressed)
	vbox.add_child(options_btn)

	var main_menu_btn := _create_button("Main Menu")
	main_menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(main_menu_btn)

	var quit_btn := _create_button("Quit Game")
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)


func _create_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 40)
	btn.add_theme_font_size_override("font_size", 16)
	return btn


func _show_menu() -> void:
	is_visible = true
	visible = true
	get_tree().paused = true


func _hide_menu() -> void:
	is_visible = false
	visible = false
	get_tree().paused = false


func _on_resume_pressed() -> void:
	_hide_menu()


func _on_save_pressed() -> void:
	# Generate save name with timestamp
	var datetime := Time.get_datetime_dict_from_system()
	var save_name := "%s_%04d%02d%02d_%02d%02d" % [
		CampaignManager.company_name.replace(" ", "_"),
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"]
	]

	if CampaignManager.save_campaign(save_name):
		print("Game saved!")
		# TODO: Show save confirmation toast
	else:
		print("Save failed!")

	_hide_menu()


func _on_options_pressed() -> void:
	# TODO: Show options dialog
	pass


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	CampaignManager.is_campaign_active = false
	get_tree().change_scene_to_file("res://ui/main_menu/main_menu.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
