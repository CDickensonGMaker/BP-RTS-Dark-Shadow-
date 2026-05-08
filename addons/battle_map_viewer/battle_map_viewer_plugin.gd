@tool
extends EditorPlugin
## Battle Map Viewer - Preview and navigate battle maps with RTS camera

var dock: Control
var window: Window
var toolbar_button: Button


func _enter_tree() -> void:
	# Create the dock instance
	dock = preload("res://addons/battle_map_viewer/battle_map_viewer_dock.tscn").instantiate()
	dock.name = "BattleMapViewer"

	# Create popup window
	window = Window.new()
	window.title = "Battle Map Viewer"
	window.size = Vector2i(400, 600)
	window.min_size = Vector2i(300, 400)
	window.visible = false
	window.wrap_controls = true
	window.transient = true
	window.exclusive = false
	window.unresizable = false
	window.close_requested.connect(_on_window_close_requested)

	# Add dock content to window
	window.add_child(dock)
	dock.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Add window to editor
	EditorInterface.get_base_control().add_child(window)

	# Add toolbar button
	toolbar_button = Button.new()
	toolbar_button.text = "Map Viewer"
	toolbar_button.tooltip_text = "Open Battle Map Viewer to preview battle maps"
	toolbar_button.toggle_mode = true
	toolbar_button.toggled.connect(_on_toolbar_button_toggled)
	add_control_to_container(CONTAINER_TOOLBAR, toolbar_button)

	print("[BattleMapViewer] Plugin enabled - Click 'Map Viewer' button in toolbar")


func _exit_tree() -> void:
	# Remove toolbar button
	if toolbar_button:
		remove_control_from_container(CONTAINER_TOOLBAR, toolbar_button)
		toolbar_button.queue_free()
		toolbar_button = null

	# Remove window
	if window:
		window.queue_free()
		window = null

	dock = null

	print("[BattleMapViewer] Plugin disabled")


func _on_toolbar_button_toggled(pressed: bool) -> void:
	if window:
		window.visible = pressed
		if pressed:
			# Center window on screen
			var screen_size := DisplayServer.screen_get_size()
			var window_size := window.size
			window.position = Vector2i(
				(screen_size.x - window_size.x) / 2,
				(screen_size.y - window_size.y) / 2
			)
			window.grab_focus()


func _on_window_close_requested() -> void:
	window.visible = false
	if toolbar_button:
		toolbar_button.button_pressed = false


func _get_plugin_name() -> String:
	return "Battle Map Viewer"


func _get_plugin_icon() -> Texture2D:
	return null
