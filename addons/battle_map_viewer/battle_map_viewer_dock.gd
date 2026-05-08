@tool
extends Control

const BATTLE_MAP_PATHS: Array[String] = [
	"res://scenes/battle_maps/",
	"res://battle_system/data/battle_maps/"
]

@onready var map_list: ItemList = $VBoxContainer/MapList
@onready var refresh_btn: Button = $VBoxContainer/HeaderBar/RefreshButton
@onready var view_btn: Button = $VBoxContainer/ViewButton
@onready var search_field: LineEdit = $VBoxContainer/SearchField

var all_maps: Array[Dictionary] = []
var filtered_maps: Array[Dictionary] = []

func _ready() -> void:
	refresh_btn.pressed.connect(_on_refresh_pressed)
	view_btn.pressed.connect(_on_view_pressed)
	search_field.text_changed.connect(_on_search_changed)
	map_list.item_activated.connect(_on_item_double_clicked)

	_scan_for_maps()

func _scan_for_maps() -> void:
	all_maps.clear()

	for base_path in BATTLE_MAP_PATHS:
		_scan_directory(base_path)

	# Sort by name
	all_maps.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)

	_apply_filter()

func _scan_directory(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name = dir.get_next()

	while file_name != "":
		if dir.current_is_dir() and not file_name.begins_with("."):
			_scan_directory(path.path_join(file_name))
		elif file_name.ends_with(".tscn"):
			var full_path = path.path_join(file_name)
			all_maps.append({
				"name": file_name.get_basename().capitalize(),
				"path": full_path,
				"folder": path.get_file()
			})
		file_name = dir.get_next()

	dir.list_dir_end()

func _apply_filter() -> void:
	var search_text = search_field.text.to_lower() if search_field else ""

	filtered_maps.clear()
	map_list.clear()

	for map_data in all_maps:
		if search_text.is_empty() or search_text in map_data.name.to_lower():
			filtered_maps.append(map_data)
			map_list.add_item(map_data.name)
			map_list.set_item_tooltip(map_list.item_count - 1, map_data.path)

func _on_refresh_pressed() -> void:
	_scan_for_maps()

func _on_search_changed(_new_text: String) -> void:
	_apply_filter()

func _on_view_pressed() -> void:
	var selected = map_list.get_selected_items()
	if selected.is_empty():
		return

	_launch_viewer(filtered_maps[selected[0]].path)

func _on_item_double_clicked(index: int) -> void:
	_launch_viewer(filtered_maps[index].path)

func _launch_viewer(map_path: String) -> void:
	# Store the map path for the viewer to load
	ProjectSettings.set_setting("battle_map_viewer/current_map", map_path)

	# Run the viewer scene
	var viewer_scene = "res://addons/battle_map_viewer/map_viewer.tscn"
	EditorInterface.play_custom_scene(viewer_scene)
