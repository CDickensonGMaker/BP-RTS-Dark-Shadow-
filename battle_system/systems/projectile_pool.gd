## ProjectilePool - Object pooling system for projectiles
## Based on Catacombs of Gore patterns with deactivate/reactivate pattern
## Optimized for RTS-scale battles with regiment volleys

class_name ProjectilePool
extends Node

# Pool configuration - tuned for RTS scale
const DEFAULT_POOL_SIZE: int = 100   # Pre-allocated projectiles
const MAX_ACTIVE: int = 200          # Max simultaneous active projectiles

# Pool arrays
var _pool: Array[Node] = []
var _active: Array[Node] = []

# Scene reference for creating new projectiles
var _projectile_scene: PackedScene = null

# Statistics for debugging/profiling
var _stats: Dictionary = {
	"spawned_total": 0,
	"returned_total": 0,
	"pool_misses": 0,
	"max_active_reached": 0
}


func _ready() -> void:
	# Lazy load projectile scene
	_projectile_scene = load("res://battle_system/nodes/projectile.tscn")

	# Pre-allocate pool
	call_deferred("_preallocate_pool")


## Pre-allocate projectiles for the pool
func _preallocate_pool() -> void:
	for i in DEFAULT_POOL_SIZE:
		var projectile: Node = _create_projectile()
		if projectile:
			projectile.deactivate()
			_pool.append(projectile)


## Create a new projectile instance
func _create_projectile() -> Node:
	if not _projectile_scene:
		push_error("ProjectilePool: No projectile scene loaded")
		return null

	var projectile: Node = _projectile_scene.instantiate()

	# Connect return signal if projectile supports it
	if projectile.has_signal("returned_to_pool"):
		projectile.returned_to_pool.connect(_on_projectile_returned)

	return projectile


## Spawn a projectile from the pool
## Returns null if max active reached or pool exhausted
func spawn(
	scene: PackedScene,
	source: Node,
	pos: Vector3,
	dir: Vector3,
	target: Node = null
) -> Node:
	# Check max active limit
	if _active.size() >= MAX_ACTIVE:
		_stats["max_active_reached"] += 1
		return null

	var projectile: Node = null

	# Try to get from pool
	if _pool.size() > 0:
		projectile = _pool.pop_back()
	else:
		# Pool exhausted - create new if under limit
		_stats["pool_misses"] += 1
		projectile = _create_projectile()
		if not projectile:
			return null

	# Add to scene tree if not already
	if not projectile.is_inside_tree():
		var tree := get_tree()
		if tree and tree.current_scene:
			tree.current_scene.add_child(projectile)
		else:
			# Fallback - add as sibling
			add_child(projectile)

	# Configure projectile
	projectile.global_position = pos

	# Set direction if projectile supports it
	if projectile.has_method("set_direction"):
		projectile.set_direction(dir)

	# Set target for homing projectiles
	if projectile.has_method("set_target"):
		projectile.set_target(target)

	# Set source reference
	if projectile.has_method("set_source"):
		projectile.set_source(source)
	elif "origin" in projectile:
		projectile.origin = source

	# Activate the projectile
	if projectile.has_method("activate"):
		projectile.activate()
	else:
		# Fallback activation
		projectile.visible = true
		projectile.process_mode = Node.PROCESS_MODE_INHERIT

	_active.append(projectile)
	_stats["spawned_total"] += 1

	return projectile


## Spawn with full configuration for different projectile types
func spawn_configured(
	source: Node,
	pos: Vector3,
	dir: Vector3,
	target: Node,
	config: Dictionary
) -> Node:
	var projectile: Node = spawn(_projectile_scene, source, pos, dir, target)
	if not projectile:
		return null

	# Apply configuration
	if "speed" in config:
		projectile.speed = config["speed"]
	if "is_homing" in config:
		projectile.is_homing = config["is_homing"]
	if "homing_strength" in config:
		projectile.homing_strength = config["homing_strength"]
	if "max_pierces" in config:
		projectile.max_pierces = config["max_pierces"]
	if "pierce_damage_falloff" in config:
		projectile.pierce_damage_falloff = config["pierce_damage_falloff"]
	if "aoe_radius" in config:
		projectile.aoe_radius = config["aoe_radius"]
	if "aoe_damage_falloff" in config:
		projectile.aoe_damage_falloff = config["aoe_damage_falloff"]
	if "collision_mask" in config:
		projectile.collision_mask = config["collision_mask"]
	if "arc_height" in config:
		projectile.arc_height = config["arc_height"]
	if "lifetime" in config:
		projectile.lifetime = config["lifetime"]

	return projectile


## Return a projectile to the pool
func return_to_pool(projectile: Node) -> void:
	if not is_instance_valid(projectile):
		return

	# Remove from active list
	var idx: int = _active.find(projectile)
	if idx >= 0:
		_active.remove_at(idx)

	# Deactivate the projectile
	if projectile.has_method("deactivate"):
		projectile.deactivate()
	else:
		# Fallback deactivation
		projectile.visible = false
		projectile.process_mode = Node.PROCESS_MODE_DISABLED

	# Remove from scene tree (stays in memory)
	if projectile.get_parent():
		projectile.get_parent().remove_child(projectile)

	# Return to pool
	_pool.append(projectile)
	_stats["returned_total"] += 1


## Handle projectile returning itself
func _on_projectile_returned(projectile: Node) -> void:
	return_to_pool(projectile)


## Get pool statistics
func get_stats() -> Dictionary:
	return {
		"pool_size": _pool.size(),
		"active_count": _active.size(),
		"spawned_total": _stats["spawned_total"],
		"returned_total": _stats["returned_total"],
		"pool_misses": _stats["pool_misses"],
		"max_active_reached": _stats["max_active_reached"],
		"pool_hit_rate": _calculate_hit_rate()
	}


## Calculate pool hit rate percentage
func _calculate_hit_rate() -> float:
	var total: int = _stats["spawned_total"]
	if total == 0:
		return 100.0
	var hits: int = total - _stats["pool_misses"]
	return (float(hits) / float(total)) * 100.0


## Clear all projectiles (for scene cleanup)
func clear_all() -> void:
	# Return all active projectiles
	for projectile in _active.duplicate():
		return_to_pool(projectile)

	# Free all pooled projectiles
	for projectile in _pool:
		if is_instance_valid(projectile):
			projectile.queue_free()

	_pool.clear()
	_active.clear()


## Get count of active projectiles
func get_active_count() -> int:
	return _active.size()


## Get count of available projectiles in pool
func get_available_count() -> int:
	return _pool.size()


## Process function to clean up invalid projectiles
func _process(_delta: float) -> void:
	# Periodically clean up any invalid references
	_active = _active.filter(func(p: Node) -> bool:
		return is_instance_valid(p)
	)
