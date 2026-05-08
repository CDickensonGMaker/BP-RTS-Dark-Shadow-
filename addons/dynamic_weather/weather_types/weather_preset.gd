@tool
class_name WeatherPreset
extends Resource

## Base resource for defining weather conditions

@export var id: String = "clear"
@export var display_name: String = "Clear"
@export_multiline var description: String = ""

@export_group("Sky Settings")
## Cloud coverage 0.0 (clear) to 1.0 (overcast)
@export_range(0.0, 1.0) var cloud_coverage: float = 0.0
## Fog density multiplier
@export_range(0.0, 1.0) var fog_density: float = 0.0
## Fog color tint
@export var fog_color: Color = Color(0.8, 0.8, 0.85, 1.0)
## Overall sky brightness modifier
@export_range(0.0, 2.0) var sky_brightness: float = 1.0

@export_group("Precipitation")
## Enable rain particles
@export var has_rain: bool = false
## Rain intensity 0.0 to 1.0
@export_range(0.0, 1.0) var rain_intensity: float = 0.0
## Enable snow particles
@export var has_snow: bool = false
## Snow intensity 0.0 to 1.0
@export_range(0.0, 1.0) var snow_intensity: float = 0.0

@export_group("Wind")
## Wind speed in m/s
@export_range(0.0, 50.0) var wind_speed: float = 1.0
## Wind direction in degrees (0 = north)
@export_range(-180.0, 180.0) var wind_direction: float = 0.0

@export_group("Storm Effects")
## Enable lightning flashes
@export var has_lightning: bool = false
## Average seconds between lightning strikes
@export_range(1.0, 60.0) var lightning_interval: float = 15.0
## Lightning flash intensity
@export_range(0.0, 3.0) var lightning_intensity: float = 2.0

@export_group("Audio")
## Ambient sound to loop (rain, wind, etc)
@export var ambient_sound: AudioStream
## Volume in dB
@export_range(-40.0, 0.0) var ambient_volume_db: float = -10.0

@export_group("Transition")
## How long to transition into this weather (seconds)
@export_range(0.5, 60.0) var transition_duration: float = 10.0
## Probability weight for random weather selection
@export_range(0.0, 100.0) var weight: float = 10.0
