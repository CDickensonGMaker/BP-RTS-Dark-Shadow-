extends Node3D

## Ambient battlefield atmosphere system.
## Spawns ambient effects like birds, smoke, dust clouds.
## Uses SpriteEffectPool for efficient sprite rendering.

const MAX_BIRDS: int = 12
const BIRD_SPAWN_INTERVAL: float = 3.0
const BIRD_FLIGHT_DURATION: float = 8.0
const BIRD_HEIGHT_MIN: float = 15.0
const BIRD_HEIGHT_MAX: float = 25.0
const BIRD_SPEED: float = 8.0

# Active birds
var _birds: Array[Dictionary] = []
var _spawn_timer: float = 0.0
var _enabled: bool = true

# Battlefield bounds
var _battlefield_center: Vector3 = Vector3.ZERO
var _battlefield_radius: float = 100.0


func _ready() -> void:
	# Connect to battle signals
	if BattleSignals:
		BattleSignals.battle_started.connect(_on_battle_started)
		BattleSignals.battle_ended.connect(_on_battle_ended)


func _process(delta: float) -> void:
	if not _enabled:
		return

	# Update spawn timer
	_spawn_timer += delta
	if _spawn_timer >= BIRD_SPAWN_INTERVAL and _birds.size() < MAX_BIRDS:
		_spawn_timer = 0.0
		_spawn_bird()

	# Update birds
	_update_birds(delta)


func _on_battle_started() -> void:
	## Battle started - enable ambient effects.
	_enabled = true
	_birds.clear()

	# Find battlefield bounds from terrain if available
	var terrain := get_tree().get_first_node_in_group("battle_terrain")
	if terrain and "global_position" in terrain:
		_battlefield_center = terrain.global_position
		# Estimate radius from terrain size
		if "terrain_size" in terrain:
			_battlefield_radius = terrain.terrain_size.x * 0.5
		else:
			_battlefield_radius = 100.0


func _on_battle_ended(_result: Dictionary) -> void:
	## Battle ended - gradually fade out ambient effects.
	# Don't immediately disable - let birds finish flying
	pass


## Spawn a bird flying across the battlefield
func _spawn_bird() -> void:
	var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
	if not sprite_pool:
		return

	# Random start position outside battlefield
	var angle := randf() * TAU
	var start_offset := Vector3(cos(angle), 0, sin(angle)) * (_battlefield_radius + 20.0)
	var start_pos := _battlefield_center + start_offset
	start_pos.y = randf_range(BIRD_HEIGHT_MIN, BIRD_HEIGHT_MAX)

	# Fly toward opposite side (with some randomness)
	var end_angle := angle + PI + randf_range(-0.5, 0.5)
	var end_offset := Vector3(cos(end_angle), 0, sin(end_angle)) * (_battlefield_radius + 20.0)
	var end_pos := _battlefield_center + end_offset
	end_pos.y = randf_range(BIRD_HEIGHT_MIN, BIRD_HEIGHT_MAX)

	# Calculate direction
	var dir := (end_pos - start_pos).normalized()
	var direction_idx := _direction_to_index(dir)

	# Spawn bird sprite
	var effect_idx: int = sprite_pool.spawn_effect(
		"birds_atlas",
		start_pos,
		direction_idx,
		Vector2(1.5, 1.5),  # scale
		true,               # loop
		Color.WHITE,
		BIRD_FLIGHT_DURATION
	)

	if effect_idx >= 0:
		_birds.append({
			"effect_idx": effect_idx,
			"position": start_pos,
			"velocity": dir * BIRD_SPEED,
			"end_pos": end_pos,
			"time_alive": 0.0
		})


func _update_birds(delta: float) -> void:
	## Update bird positions and remove finished ones.
	var to_remove: Array[int] = []

	for i in range(_birds.size()):
		var bird: Dictionary = _birds[i]
		bird.time_alive += delta
		bird.position += bird.velocity * delta

		# Check if bird has left the area or timed out
		if bird.time_alive >= BIRD_FLIGHT_DURATION:
			to_remove.append(i)
			continue

		# Check if bird reached destination
		var dist: float = bird.position.distance_to(bird.end_pos)
		if dist < 5.0:
			to_remove.append(i)
			continue

	# Remove finished birds (reverse order)
	for i in range(to_remove.size() - 1, -1, -1):
		var idx: int = to_remove[i]
		var bird: Dictionary = _birds[idx]

		# Hide the sprite effect
		var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
		if sprite_pool and sprite_pool.has_method("hide_effect"):
			sprite_pool.hide_effect("res://assets/sprites/effects/birds_atlas.tres", bird.effect_idx)

		_birds.remove_at(idx)


## Calculate direction index from velocity vector
func _direction_to_index(dir: Vector3) -> int:
	var angle := atan2(dir.x, -dir.z)
	if angle < 0:
		angle += TAU
	return int(round(angle / (TAU / 8.0))) % 8


## Enable/disable ambient effects
func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		# Clear all birds
		var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
		if sprite_pool:
			for bird in _birds:
				if sprite_pool.has_method("hide_effect"):
					sprite_pool.hide_effect("res://assets/sprites/effects/birds_atlas.tres", bird.effect_idx)
		_birds.clear()


## Set battlefield bounds for bird spawning
func set_battlefield_bounds(center: Vector3, radius: float) -> void:
	_battlefield_center = center
	_battlefield_radius = radius
