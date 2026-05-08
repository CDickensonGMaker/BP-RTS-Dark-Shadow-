extends Node
## Weather Demo Controller - Press keys to test different weather types

@export var weather_types: Array[WeatherPreset] = []
var current_index: int = 0


func _ready() -> void:
	# Load all weather presets
	weather_types = [
		preload("res://addons/dynamic_weather/resources/weather_clear.tres"),
		preload("res://addons/dynamic_weather/resources/weather_cloudy.tres"),
		preload("res://addons/dynamic_weather/resources/weather_rain.tres"),
		preload("res://addons/dynamic_weather/resources/weather_storm.tres"),
		preload("res://addons/dynamic_weather/resources/weather_snow.tres"),
		preload("res://addons/dynamic_weather/resources/weather_blizzard.tres"),
		preload("res://addons/dynamic_weather/resources/weather_fog.tres"),
	]

	# Start with clear weather
	await get_tree().process_frame
	await get_tree().process_frame
	if WeatherController:
		WeatherController.set_weather(weather_types[0], true)
		print("[WeatherDemo] Started with: ", weather_types[0].display_name)
		print("[WeatherDemo] Controls:")
		print("  1: Clear (sunny)")
		print("  2: Cloudy")
		print("  3: Rain")
		print("  4: Storm (rain + lightning)")
		print("  5: Snow")
		print("  6: Blizzard (heavy snow)")
		print("  7: Fog")
		print("  N/P: Next/Previous weather")
		print("  T: Advance time by 2 hours")
		print("  R: Random weather")


func _unhandled_input(event: InputEvent) -> void:
	if not WeatherController:
		return

	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_set_weather_index(0)
			KEY_2:
				_set_weather_index(1)
			KEY_3:
				_set_weather_index(2)
			KEY_4:
				_set_weather_index(3)
			KEY_5:
				_set_weather_index(4)
			KEY_6:
				_set_weather_index(5)
			KEY_7:
				_set_weather_index(6)
			KEY_N:
				current_index = (current_index + 1) % weather_types.size()
				_set_weather_index(current_index)
			KEY_P:
				current_index = (current_index - 1 + weather_types.size()) % weather_types.size()
				_set_weather_index(current_index)
			KEY_T:
				var new_time = fmod(WeatherController.get_time() + 2.0, 24.0)
				WeatherController.set_time(new_time)
				print("[WeatherDemo] Time: %.1f:00" % new_time)
			KEY_R:
				current_index = randi() % weather_types.size()
				_set_weather_index(current_index)


func _set_weather_index(index: int) -> void:
	if index >= 0 and index < weather_types.size():
		current_index = index
		var weather = weather_types[index]
		# Use instant transition for testing (true = instant)
		WeatherController.set_weather(weather, true)
		print("[WeatherDemo] Set weather to: ", weather.display_name)
