extends Node
## WeatherController - Central manager for dynamic weather system
## Integrates with Sky3D for atmospheric effects, adds precipitation and storms

signal weather_changed(old_weather: WeatherPreset, new_weather: WeatherPreset)
signal weather_transition_started(from: WeatherPreset, to: WeatherPreset)
signal weather_transition_completed(weather: WeatherPreset)
signal lightning_strike(position: Vector3, intensity: float)
signal time_of_day_changed(is_day: bool)

## Current active weather
var current_weather: WeatherPreset
## Weather we're transitioning to (null if not transitioning)
var target_weather: WeatherPreset
## Transition progress 0.0 to 1.0
var transition_progress: float = 0.0

## Reference to Sky3D node (auto-detected or manually set)
var sky3d: Node
## Camera to follow for precipitation positioning
var follow_camera: Camera3D

## Precipitation nodes
var _rain_particles: GPUParticles3D
var _snow_particles: GPUParticles3D
var _lightning_timer: Timer
var _ambient_player: AudioStreamPlayer3D

## Scale mode for RTS vs FPS
enum ScaleMode { FPS, RTS }
@export var scale_mode: ScaleMode = ScaleMode.RTS

## Precipitation area size (larger for RTS top-down view)
@export var precipitation_area_fps: Vector3 = Vector3(30, 40, 30)
@export var precipitation_area_rts: Vector3 = Vector3(200, 60, 200)

## Available weather types for random selection
@export var weather_pool: Array[Resource] = []

## Enable automatic weather changes
@export var auto_weather_enabled: bool = false
## Time range between weather changes (seconds)
@export var auto_weather_min_interval: float = 120.0
@export var auto_weather_max_interval: float = 300.0

var _auto_weather_timer: Timer
var _last_was_day: bool = true
var _transition_tween: Tween

## Reference to gameplay WeatherSystem for combat modifiers (auto-detected)
var _gameplay_weather_system: Node


func _ready() -> void:
	# Find the gameplay weather system if it exists
	if has_node("/root/WeatherSystem"):
		_gameplay_weather_system = get_node("/root/WeatherSystem")
		# Connect our weather changes to update gameplay modifiers
		weather_changed.connect(_on_weather_changed_sync_gameplay)
	_find_sky3d()
	_setup_precipitation()
	_setup_lightning()
	_setup_audio()
	_setup_auto_weather()

	# Load default clear weather if none set
	if current_weather == null:
		var clear = load("res://addons/dynamic_weather/resources/weather_clear.tres")
		if clear:
			set_weather(clear, true)


func _process(delta: float) -> void:
	_update_precipitation_position()
	_check_day_night_change()


func _find_sky3d() -> void:
	# Look for Sky3D in the scene tree
	var sky_nodes = get_tree().get_nodes_in_group("sky3d")
	if sky_nodes.size() > 0:
		sky3d = sky_nodes[0]
		return

	# Search by class name
	for node in get_tree().get_nodes_in_group(""):
		if node.get_class() == "Sky3D" or (node.get_script() and "Sky3D" in str(node.get_script())):
			sky3d = node
			return

	# Search WorldEnvironment nodes
	var root = get_tree().current_scene
	if root:
		sky3d = _find_node_by_script(root, "Sky3D")


func _find_node_by_script(node: Node, script_name: String) -> Node:
	if node.get_script():
		var script_path = str(node.get_script().resource_path)
		if script_name in script_path:
			return node
	for child in node.get_children():
		var result = _find_node_by_script(child, script_name)
		if result:
			return result
	return null


func _setup_precipitation() -> void:
	# Rain particles - visible from RTS camera
	_rain_particles = GPUParticles3D.new()
	_rain_particles.name = "RainParticles"
	_rain_particles.emitting = false
	_rain_particles.amount = 1500  # Enough to be visible
	_rain_particles.lifetime = 0.8  # Quick fall
	_rain_particles.visibility_aabb = AABB(Vector3(-100, -50, -100), Vector3(200, 100, 200))
	_rain_particles.process_material = _create_rain_material()
	_rain_particles.draw_pass_1 = _create_rain_mesh()
	add_child(_rain_particles)

	# Snow particles - visible from RTS camera
	_snow_particles = GPUParticles3D.new()
	_snow_particles.name = "SnowParticles"
	_snow_particles.emitting = false
	_snow_particles.amount = 800  # Enough to be visible
	_snow_particles.lifetime = 2.5  # Slow drift
	_snow_particles.visibility_aabb = AABB(Vector3(-100, -50, -100), Vector3(200, 100, 200))
	_snow_particles.process_material = _create_snow_material()
	_snow_particles.draw_pass_1 = _create_snow_mesh()
	add_child(_snow_particles)


func _create_rain_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()

	# Emission shape - box above camera
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(100, 1, 100)

	# Gravity - rain falls fast
	mat.gravity = Vector3(0, -25, 0)

	# Initial velocity
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 5.0
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 25.0

	# Add wind influence
	mat.attractor_interaction_enabled = true

	# Scale
	mat.scale_min = 0.8
	mat.scale_max = 1.2

	# Color - semi-transparent blue-white
	var gradient = Gradient.new()
	gradient.set_color(0, Color(0.7, 0.8, 1.0, 0.6))
	gradient.set_color(1, Color(0.7, 0.8, 1.0, 0.3))
	mat.color_ramp = GradientTexture1D.new()
	mat.color_ramp.gradient = gradient

	return mat


func _create_rain_mesh() -> Mesh:
	# Larger rain streaks visible from RTS camera height
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.15, 3.0)  # Much larger for RTS visibility

	# Create material for rain drops
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.7, 0.8, 1.0, 0.6)
	material.emission_enabled = true
	material.emission = Color(0.6, 0.7, 0.9)
	material.emission_energy_multiplier = 0.5
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material

	return mesh


func _create_snow_material() -> ParticleProcessMaterial:
	var mat = ParticleProcessMaterial.new()

	# Emission shape
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(100, 1, 100)

	# Gravity - snow falls slowly
	mat.gravity = Vector3(0, -2, 0)

	# Initial velocity - gentle drift
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0

	# Turbulence for realistic snow movement
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 2.0
	mat.turbulence_noise_scale = 1.5
	mat.turbulence_noise_speed_random = 0.5

	# Scale variation
	mat.scale_min = 0.5
	mat.scale_max = 1.5

	# Angular velocity for rotation
	mat.angular_velocity_min = -180.0
	mat.angular_velocity_max = 180.0

	# Color - white with fade
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.9))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.4))
	mat.color_ramp = GradientTexture1D.new()
	mat.color_ramp.gradient = gradient

	return mat


func _create_snow_mesh() -> Mesh:
	# Larger snowflakes visible from RTS camera
	var mesh = QuadMesh.new()
	mesh.size = Vector2(0.8, 0.8)  # Much larger for RTS visibility

	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	material.emission_enabled = true
	material.emission = Color(0.95, 0.97, 1.0)
	material.emission_energy_multiplier = 0.4
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material

	return mesh


func _setup_lightning() -> void:
	_lightning_timer = Timer.new()
	_lightning_timer.name = "LightningTimer"
	_lightning_timer.one_shot = true
	_lightning_timer.timeout.connect(_on_lightning_timer)
	add_child(_lightning_timer)


func _setup_audio() -> void:
	_ambient_player = AudioStreamPlayer3D.new()
	_ambient_player.name = "AmbientPlayer"
	_ambient_player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_ambient_player.max_distance = 1000.0
	_ambient_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	add_child(_ambient_player)


func _setup_auto_weather() -> void:
	_auto_weather_timer = Timer.new()
	_auto_weather_timer.name = "AutoWeatherTimer"
	_auto_weather_timer.one_shot = true
	_auto_weather_timer.timeout.connect(_on_auto_weather_timer)
	add_child(_auto_weather_timer)

	if auto_weather_enabled:
		_start_auto_weather_timer()


func _update_precipitation_position() -> void:
	if not follow_camera:
		follow_camera = get_viewport().get_camera_3d()

	if follow_camera:
		var cam_pos = follow_camera.global_position
		# Get camera forward direction and position particles in front of view
		var cam_forward = -follow_camera.global_basis.z
		var cam_up = follow_camera.global_basis.y

		# Position particles in front of camera, filling the view
		# For RTS, offset forward and slightly down to fill the viewport
		var offset_forward = 30.0  # Distance in front of camera
		var offset_up = 15.0  # Height above camera look point
		var particle_pos = cam_pos + cam_forward * offset_forward + Vector3(0, offset_up, 0)

		_rain_particles.global_position = particle_pos
		_snow_particles.global_position = particle_pos

		# Use smaller emission box since particles are closer to camera
		var rain_mat = _rain_particles.process_material as ParticleProcessMaterial
		var snow_mat = _snow_particles.process_material as ParticleProcessMaterial
		if rain_mat:
			rain_mat.emission_box_extents = Vector3(60, 5, 60)
		if snow_mat:
			snow_mat.emission_box_extents = Vector3(60, 5, 60)


func _check_day_night_change() -> void:
	if sky3d and sky3d.has_method("is_day"):
		var is_day = sky3d.is_day()
		if is_day != _last_was_day:
			_last_was_day = is_day
			time_of_day_changed.emit(is_day)


## Set weather immediately or with transition
func set_weather(weather: WeatherPreset, instant: bool = false) -> void:
	if weather == null:
		return

	var old_weather = current_weather

	if instant:
		current_weather = weather
		target_weather = null
		transition_progress = 1.0
		_apply_weather(weather, 1.0)
		weather_changed.emit(old_weather, weather)
		weather_transition_completed.emit(weather)
	else:
		target_weather = weather
		transition_progress = 0.0
		weather_transition_started.emit(current_weather, weather)
		_start_transition(weather)


func _start_transition(to_weather: WeatherPreset) -> void:
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()

	var duration = to_weather.transition_duration
	_transition_tween = create_tween()
	_transition_tween.tween_method(_on_transition_update, 0.0, 1.0, duration)
	_transition_tween.tween_callback(_on_transition_complete)


func _on_transition_update(progress: float) -> void:
	transition_progress = progress
	if target_weather:
		_apply_weather_blend(current_weather, target_weather, progress)


func _on_transition_complete() -> void:
	var old_weather = current_weather
	current_weather = target_weather
	target_weather = null
	transition_progress = 1.0
	_apply_weather(current_weather, 1.0)
	weather_changed.emit(old_weather, current_weather)
	weather_transition_completed.emit(current_weather)


func _apply_weather(weather: WeatherPreset, intensity: float = 1.0) -> void:
	if weather == null:
		return

	print("[WeatherController] Applying: ", weather.display_name, " | Rain: ", weather.has_rain, " (", weather.rain_intensity, ") | Snow: ", weather.has_snow, " (", weather.snow_intensity, ")")

	# Apply to Sky3D if available
	if sky3d:
		if sky3d.has_method("set"):
			# Fog
			if "fog_enabled" in sky3d:
				sky3d.fog_enabled = weather.fog_density > 0.01
			# Wind
			if "wind_speed" in sky3d:
				sky3d.wind_speed = weather.wind_speed
			if "wind_direction" in sky3d:
				sky3d.wind_direction = deg_to_rad(weather.wind_direction)

	# Update environment fog if we have access
	_update_environment_fog(weather, intensity)

	# Rain - visible from RTS height
	_rain_particles.emitting = weather.has_rain and weather.rain_intensity > 0.01
	if weather.has_rain:
		_rain_particles.amount = int(lerp(800.0, 2500.0, weather.rain_intensity))
		print("[WeatherController] Rain particles ENABLED: ", _rain_particles.amount)
		var rain_mat = _rain_particles.process_material as ParticleProcessMaterial
		if rain_mat:
			# Add wind to rain
			rain_mat.gravity = Vector3(
				sin(deg_to_rad(weather.wind_direction)) * weather.wind_speed * 0.5,
				-25.0,
				cos(deg_to_rad(weather.wind_direction)) * weather.wind_speed * 0.5
			)
	elif not _rain_particles.emitting:
		print("[WeatherController] Rain particles DISABLED")

	# Snow - visible from RTS height
	_snow_particles.emitting = weather.has_snow and weather.snow_intensity > 0.01
	if weather.has_snow:
		_snow_particles.amount = int(lerp(400.0, 1200.0, weather.snow_intensity))
		print("[WeatherController] Snow particles ENABLED: ", _snow_particles.amount)
		var snow_mat = _snow_particles.process_material as ParticleProcessMaterial
		if snow_mat:
			# Gentler wind effect on snow
			snow_mat.gravity = Vector3(
				sin(deg_to_rad(weather.wind_direction)) * weather.wind_speed * 0.2,
				-2.0,
				cos(deg_to_rad(weather.wind_direction)) * weather.wind_speed * 0.2
			)
	else:
		print("[WeatherController] Snow particles DISABLED")

	# Lightning
	if weather.has_lightning:
		_schedule_next_lightning(weather.lightning_interval)
	else:
		_lightning_timer.stop()

	# Audio
	if weather.ambient_sound:
		if _ambient_player.stream != weather.ambient_sound:
			_ambient_player.stream = weather.ambient_sound
			_ambient_player.play()
		_ambient_player.volume_db = weather.ambient_volume_db
	else:
		_ambient_player.stop()


func _apply_weather_blend(from: WeatherPreset, to: WeatherPreset, t: float) -> void:
	if from == null:
		_apply_weather(to, t)
		return
	if to == null:
		_apply_weather(from, 1.0 - t)
		return

	# Blend precipitation
	var rain_active = (from.has_rain and from.rain_intensity > 0.01) or (to.has_rain and to.rain_intensity > 0.01)
	var snow_active = (from.has_snow and from.snow_intensity > 0.01) or (to.has_snow and to.snow_intensity > 0.01)

	_rain_particles.emitting = rain_active
	_snow_particles.emitting = snow_active

	if rain_active:
		var rain_intensity = lerp(from.rain_intensity if from.has_rain else 0.0, to.rain_intensity if to.has_rain else 0.0, t)
		_rain_particles.amount = int(lerp(800.0, 2500.0, rain_intensity))

	if snow_active:
		var snow_intensity = lerp(from.snow_intensity if from.has_snow else 0.0, to.snow_intensity if to.has_snow else 0.0, t)
		_snow_particles.amount = int(lerp(400.0, 1200.0, snow_intensity))

	# Blend fog
	var fog_density = lerp(from.fog_density, to.fog_density, t)
	var fog_color = from.fog_color.lerp(to.fog_color, t)
	_update_environment_fog_values(fog_density, fog_color)

	# Blend wind
	var wind_speed = lerp(from.wind_speed, to.wind_speed, t)
	var wind_dir = lerp_angle(deg_to_rad(from.wind_direction), deg_to_rad(to.wind_direction), t)

	if sky3d:
		if "wind_speed" in sky3d:
			sky3d.wind_speed = wind_speed
		if "wind_direction" in sky3d:
			sky3d.wind_direction = wind_dir


func _update_environment_fog(weather: WeatherPreset, intensity: float) -> void:
	_update_environment_fog_values(weather.fog_density * intensity, weather.fog_color)


func _update_environment_fog_values(density: float, color: Color) -> void:
	var env: Environment

	if sky3d and "environment" in sky3d:
		env = sky3d.environment
	else:
		var world_env = get_viewport().find_child("WorldEnvironment", true, false)
		if world_env and world_env is WorldEnvironment:
			env = world_env.environment

	if env:
		env.volumetric_fog_enabled = density > 0.05
		if density > 0.05:
			env.volumetric_fog_density = density * 0.1
			env.volumetric_fog_albedo = color
			env.volumetric_fog_emission = color * 0.1


func _schedule_next_lightning(base_interval: float) -> void:
	var variance = randf_range(0.5, 1.5)
	_lightning_timer.start(base_interval * variance)


func _on_lightning_timer() -> void:
	if current_weather and current_weather.has_lightning:
		_trigger_lightning()
		_schedule_next_lightning(current_weather.lightning_interval)


func _trigger_lightning() -> void:
	if not current_weather:
		return

	# Random position in sky
	var strike_pos = Vector3.ZERO
	if follow_camera:
		strike_pos = follow_camera.global_position + Vector3(
			randf_range(-100, 100),
			50,
			randf_range(-100, 100)
		)

	lightning_strike.emit(strike_pos, current_weather.lightning_intensity)

	# Flash effect - briefly increase sky brightness
	if sky3d and "tonemap_exposure" in sky3d:
		var original_exposure = sky3d.tonemap_exposure
		var flash_tween = create_tween()
		flash_tween.tween_property(sky3d, "tonemap_exposure", original_exposure * current_weather.lightning_intensity, 0.05)
		flash_tween.tween_property(sky3d, "tonemap_exposure", original_exposure, 0.3)


func _on_auto_weather_timer() -> void:
	if weather_pool.size() > 0:
		var next_weather = _select_random_weather()
		if next_weather and next_weather != current_weather:
			set_weather(next_weather, false)

	if auto_weather_enabled:
		_start_auto_weather_timer()


func _select_random_weather():
	if weather_pool.size() == 0:
		return null

	# Weighted random selection
	var total_weight = 0.0
	for w in weather_pool:
		total_weight += w.weight

	var roll = randf() * total_weight
	var accumulated = 0.0

	for w in weather_pool:
		accumulated += w.weight
		if roll <= accumulated:
			return w as WeatherPreset

	return weather_pool[0] as WeatherPreset


func _start_auto_weather_timer() -> void:
	var interval = randf_range(auto_weather_min_interval, auto_weather_max_interval)
	_auto_weather_timer.start(interval)


## Public API

## Get current weather type
func get_current_weather() -> WeatherPreset:
	return current_weather


## Check if currently transitioning
func is_transitioning() -> bool:
	return target_weather != null


## Get transition progress (0-1)
func get_transition_progress() -> float:
	return transition_progress


## Force clear weather
func clear_weather() -> void:
	var clear = load("res://addons/dynamic_weather/resources/weather_clear.tres")
	if clear:
		set_weather(clear, false)


## Set time of day (0-24 hours) - forwards to Sky3D
func set_time(hours: float) -> void:
	if sky3d and "current_time" in sky3d:
		sky3d.current_time = fmod(hours, 24.0)


## Get current time of day
func get_time() -> float:
	if sky3d and "current_time" in sky3d:
		return sky3d.current_time
	return 12.0


## Check if it's daytime
func is_day() -> bool:
	if sky3d and sky3d.has_method("is_day"):
		return sky3d.is_day()
	var time = get_time()
	return time >= 6.0 and time < 18.0


## Pause time progression
func pause_time() -> void:
	if sky3d and sky3d.has_method("pause"):
		sky3d.pause()


## Resume time progression
func resume_time() -> void:
	if sky3d and sky3d.has_method("resume"):
		sky3d.resume()


## Set the camera to follow for precipitation
func set_follow_camera(camera: Camera3D) -> void:
	follow_camera = camera


## Register Sky3D node manually
func register_sky3d(node: Node) -> void:
	sky3d = node


## Sync visual weather with gameplay WeatherSystem combat modifiers
func _on_weather_changed_sync_gameplay(_old: WeatherPreset, new_weather: WeatherPreset) -> void:
	if not _gameplay_weather_system:
		return
	if not new_weather:
		return

	# Map visual weather ID to gameplay weather type
	# The existing WeatherSystem uses WeatherPreset.Type enum
	match new_weather.id:
		"clear":
			if _gameplay_weather_system.has_method("set_weather"):
				_gameplay_weather_system.call("debug_set_weather", "clear")
		"cloudy":
			if _gameplay_weather_system.has_method("set_weather"):
				_gameplay_weather_system.call("debug_set_weather", "clear")
		"rain":
			if _gameplay_weather_system.has_method("set_weather"):
				_gameplay_weather_system.call("debug_set_weather", "rain")
		"storm":
			if _gameplay_weather_system.has_method("set_weather"):
				_gameplay_weather_system.call("debug_set_weather", "storm")
		"snow", "blizzard":
			# Map snow to fog for combat purposes (reduced visibility)
			if _gameplay_weather_system.has_method("set_weather"):
				_gameplay_weather_system.call("debug_set_weather", "fog")
		"fog":
			if _gameplay_weather_system.has_method("set_weather"):
				_gameplay_weather_system.call("debug_set_weather", "fog")
