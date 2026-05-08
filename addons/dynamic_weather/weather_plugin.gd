@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_autoload_singleton("WeatherController", "res://addons/dynamic_weather/weather_controller.gd")


func _exit_tree() -> void:
	remove_autoload_singleton("WeatherController")
