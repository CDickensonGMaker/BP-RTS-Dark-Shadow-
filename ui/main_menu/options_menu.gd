# Options Menu - Game settings
extends Control


signal back_pressed

@onready var master_slider: HSlider = $Panel/MarginContainer/VBoxContainer/SettingsContainer/AudioSettings/MasterSlider
@onready var music_slider: HSlider = $Panel/MarginContainer/VBoxContainer/SettingsContainer/AudioSettings/MusicSlider
@onready var sfx_slider: HSlider = $Panel/MarginContainer/VBoxContainer/SettingsContainer/AudioSettings/SFXSlider
@onready var fullscreen_check: CheckButton = $Panel/MarginContainer/VBoxContainer/SettingsContainer/DisplaySettings/FullscreenCheck
@onready var vsync_check: CheckButton = $Panel/MarginContainer/VBoxContainer/SettingsContainer/DisplaySettings/VSyncCheck
@onready var camera_speed_slider: HSlider = $Panel/MarginContainer/VBoxContainer/SettingsContainer/GameplaySettings/CameraSpeedSlider
@onready var apply_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/ApplyButton
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/BackButton

const CONFIG_PATH := "user://settings.cfg"
var config := ConfigFile.new()


func _ready() -> void:
	_load_settings()
	_connect_signals()


func _connect_signals() -> void:
	apply_button.pressed.connect(_on_apply_pressed)
	back_button.pressed.connect(_on_back_pressed)


func _load_settings() -> void:
	var err := config.load(CONFIG_PATH)

	# Audio
	master_slider.value = config.get_value("audio", "master", 80)
	music_slider.value = config.get_value("audio", "music", 70)
	sfx_slider.value = config.get_value("audio", "sfx", 80)

	# Display
	fullscreen_check.button_pressed = config.get_value("display", "fullscreen", false)
	vsync_check.button_pressed = config.get_value("display", "vsync", true)

	# Gameplay
	camera_speed_slider.value = config.get_value("gameplay", "camera_speed", 50)

	# Apply current audio settings
	_apply_audio_settings()


func _save_settings() -> void:
	# Audio
	config.set_value("audio", "master", master_slider.value)
	config.set_value("audio", "music", music_slider.value)
	config.set_value("audio", "sfx", sfx_slider.value)

	# Display
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("display", "vsync", vsync_check.button_pressed)

	# Gameplay
	config.set_value("gameplay", "camera_speed", camera_speed_slider.value)

	config.save(CONFIG_PATH)


func _apply_audio_settings() -> void:
	var master_db := linear_to_db(master_slider.value / 100.0)
	var music_db := linear_to_db(music_slider.value / 100.0)
	var sfx_db := linear_to_db(sfx_slider.value / 100.0)

	if AudioServer.get_bus_index("Master") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_db)
	if AudioServer.get_bus_index("Music") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), music_db)
	if AudioServer.get_bus_index("SFX") >= 0:
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), sfx_db)


func _apply_display_settings() -> void:
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	if vsync_check.button_pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func _on_apply_pressed() -> void:
	_save_settings()
	_apply_audio_settings()
	_apply_display_settings()


func _on_back_pressed() -> void:
	back_pressed.emit()
