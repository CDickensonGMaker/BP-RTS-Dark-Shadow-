# Load Game Menu - Browse and load saved campaigns
extends Control


signal back_pressed

@onready var save_list: ItemList = $Panel/MarginContainer/VBoxContainer/SaveList
@onready var load_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/LoadButton
@onready var delete_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/DeleteButton
@onready var back_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonContainer/BackButton

const SAVE_DIR := "user://saves/"
var save_files: Array[String] = []
var selected_save: String = ""


func _ready() -> void:
	_ensure_save_directory()
	_connect_signals()
	_refresh_save_list()


func _ensure_save_directory() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func _connect_signals() -> void:
	load_button.pressed.connect(_on_load_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	back_button.pressed.connect(_on_back_pressed)
	save_list.item_selected.connect(_on_save_selected)


func _refresh_save_list() -> void:
	save_list.clear()
	save_files.clear()
	selected_save = ""
	load_button.disabled = true
	delete_button.disabled = true

	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".sav"):
			save_files.append(file_name)
			var display_name := file_name.trim_suffix(".sav")
			save_list.add_item(display_name)
		file_name = dir.get_next()

	dir.list_dir_end()

	if save_files.is_empty():
		save_list.add_item("No saved games found")


func _on_save_selected(index: int) -> void:
	if index < 0 or index >= save_files.size():
		return

	selected_save = save_files[index]
	load_button.disabled = false
	delete_button.disabled = false


func _on_load_pressed() -> void:
	if selected_save.is_empty():
		return

	var save_path := SAVE_DIR + selected_save
	var file := FileAccess.open(save_path, FileAccess.READ)
	if not file:
		push_error("Failed to open save file: %s" % save_path)
		return

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		push_error("Failed to parse save file: %s" % json.get_error_message())
		return

	var data: Dictionary = json.data
	CampaignManager.load_save_data(data)

	# Transition to campaign map
	get_tree().change_scene_to_file("res://campaign_system/scenes/campaign_map.tscn")


func _on_delete_pressed() -> void:
	if selected_save.is_empty():
		return

	var save_path := SAVE_DIR + selected_save
	DirAccess.remove_absolute(save_path)
	_refresh_save_list()


func _on_back_pressed() -> void:
	back_pressed.emit()
