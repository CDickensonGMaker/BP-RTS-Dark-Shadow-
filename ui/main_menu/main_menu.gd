# Main Menu - Entry point for Dark Shadows RTS
# Grim medieval fantasy aesthetic
extends Control


@onready var main_panel: VBoxContainer = $MainPanel
@onready var title_label: Label = $MainPanel/TitleLabel
@onready var subtitle_label: Label = $MainPanel/SubtitleLabel
@onready var buttons_container: VBoxContainer = $MainPanel/ButtonsContainer
@onready var version_label: Label = $VersionLabel

# Sub-menus
var faction_select_scene: PackedScene = preload("res://ui/main_menu/faction_select.tscn")
var options_menu_scene: PackedScene = preload("res://ui/main_menu/options_menu.tscn")
var load_game_scene: PackedScene = preload("res://ui/main_menu/load_game_menu.tscn")
var quick_battle_scene: PackedScene = preload("res://ui/main_menu/quick_battle_menu.tscn")

var current_submenu: Control = null


func _ready() -> void:
	# Apply theme
	theme = DarkShadowsTheme.create_theme()

	_setup_ui()
	_connect_signals()

	# Fade in
	modulate.a = 0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.5)


func _setup_ui() -> void:
	# Title styling
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", DarkShadowsTheme.COLOR_ACCENT)

	subtitle_label.add_theme_font_size_override("font_size", 16)
	subtitle_label.add_theme_color_override("font_color", DarkShadowsTheme.COLOR_TEXT_DIM)

	version_label.add_theme_font_size_override("font_size", 12)
	version_label.add_theme_color_override("font_color", DarkShadowsTheme.COLOR_TEXT_DIM)

	# Setup buttons with cursor hints and better click targets
	for button in buttons_container.get_children():
		if button is Button:
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.focus_mode = Control.FOCUS_ALL  # Allow keyboard navigation


func _connect_signals() -> void:
	$MainPanel/ButtonsContainer/NewGameButton.pressed.connect(_on_new_game_pressed)
	$MainPanel/ButtonsContainer/LoadGameButton.pressed.connect(_on_load_game_pressed)
	$MainPanel/ButtonsContainer/QuickBattleButton.pressed.connect(_on_quick_battle_pressed)
	$MainPanel/ButtonsContainer/OptionsButton.pressed.connect(_on_options_pressed)
	$MainPanel/ButtonsContainer/QuitButton.pressed.connect(_on_quit_pressed)


func _on_new_game_pressed() -> void:
	_show_submenu(faction_select_scene)


func _on_load_game_pressed() -> void:
	_show_submenu(load_game_scene)


func _on_quick_battle_pressed() -> void:
	_show_submenu(quick_battle_scene)


func _on_options_pressed() -> void:
	_show_submenu(options_menu_scene)


func _on_quit_pressed() -> void:
	# Fade out then quit
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(get_tree().quit)


func _show_submenu(scene: PackedScene) -> void:
	if current_submenu:
		current_submenu.queue_free()

	current_submenu = scene.instantiate()
	current_submenu.theme = theme
	add_child(current_submenu)

	# Connect back signal
	if current_submenu.has_signal("back_pressed"):
		current_submenu.back_pressed.connect(_on_submenu_back)

	# Hide main panel
	main_panel.visible = false


func _on_submenu_back() -> void:
	if current_submenu:
		current_submenu.queue_free()
		current_submenu = null

	main_panel.visible = true


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if current_submenu:
			_on_submenu_back()
		else:
			_on_quit_pressed()
