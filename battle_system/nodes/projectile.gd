## Projectile for ranged attacks
## Upgraded with Catacombs of Gore patterns:
## - Object pooling (activate/deactivate)
## - Homing with lerp-based direction smoothing
## - Piercing with damage falloff
## - AOE explosions on impact
## - Configurable collision masks
## - Procedural line arrow visuals (ImmediateMesh)

class_name Projectile
extends Node3D

# === Signals ===
signal returned_to_pool(projectile: Node)
signal hit_target(target: Node, damage_multiplier: float)
signal pierced_target(target: Node, pierce_count: int)
signal aoe_triggered(position: Vector3, radius: float)

# === Basic Properties ===
@export var speed: float = 30.0
@export var arc_height: float = 10.0
@export var lifetime: float = 5.0

# === Homing Properties ===
@export var is_homing: bool = false
@export var homing_strength: float = 3.0  # Lerp rate per second
@export var homing_acquire_delay: float = 0.2  # Delay before homing activates

# === Piercing Properties ===
@export var max_pierces: int = 0  # 0 = no piercing
@export var pierce_damage_falloff: float = 0.25  # 25% damage reduction per pierce

# === AOE Properties ===
@export var aoe_radius: float = 0.0  # 0 = no AOE
@export var aoe_damage_falloff: bool = true  # Damage decreases with distance
@export var aoe_min_damage_mult: float = 0.25  # Minimum damage at edge of AOE

# === Collision Configuration ===
@export_flags_3d_physics var collision_mask: int = 2  # Default: Units layer

# === Projectile Type for Visual Color ===
enum ProjectileType { ARROW, CROSSBOW, MAGIC }
@export var projectile_type: ProjectileType = ProjectileType.ARROW

# === Arrow Visual Colors by Type ===
const ARROW_COLORS: Dictionary = {
	ProjectileType.ARROW: Color(0.4, 0.25, 0.1),    # Brown arrow
	ProjectileType.CROSSBOW: Color(0.3, 0.3, 0.35), # Gray crossbow bolt
	ProjectileType.MAGIC: Color(0.3, 0.5, 1.0),     # Blue magic projectile
}

# === Internal State ===
var target: Regiment = null
var origin: Regiment = null
var direction: Vector3 = Vector3.FORWARD
var time_alive: float = 0.0
var initial_height: float = 0.0
var pierce_count: int = 0
var pierced_targets: Array[Node] = []
var is_active: bool = false
var _damage_multiplier: float = 1.0

# Arrow mesh visuals (procedural line drawing)
var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _arrow_material: StandardMaterial3D

# Trail effect for arrow visibility
var _trail_particles: GPUParticles3D
var _trail_material: ParticleProcessMaterial

# Legacy sprite reference (disabled, kept for compatibility)
@onready var sprite: Sprite3D = $Sprite3D


func _ready() -> void:
	# Setup procedural arrow mesh
	_setup_arrow_mesh()

	# Setup trail particles
	_setup_trail()

	# Disable legacy sprite if it exists
	if sprite:
		sprite.visible = false

	# Start deactivated - pool will activate
	deactivate()


## Setup the procedural arrow mesh using ImmediateMesh
func _setup_arrow_mesh() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh

	# Create arrow material (unshaded for clean look)
	_arrow_material = StandardMaterial3D.new()
	_arrow_material.albedo_color = ARROW_COLORS.get(projectile_type, ARROW_COLORS[ProjectileType.ARROW])
	_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_instance.material_override = _arrow_material

	add_child(_mesh_instance)
	_draw_arrow()


## Draw the arrow shape using PRIMITIVE_LINES
## Arrow points along -Z axis (Godot's forward direction for look_at)
## Scaled up 4x from original for visibility
func _draw_arrow() -> void:
	_immediate_mesh.clear_surfaces()
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Arrow shaft (2.0 units long, pointing along -Z which is forward after look_at)
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, 1.0))    # Tail
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -1.0))   # Head (tip)

	# Arrowhead (V shape at the tip)
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -1.0))   # Tip
	_immediate_mesh.surface_add_vertex(Vector3(0.2, 0, -0.6)) # Left barb
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -1.0))   # Tip
	_immediate_mesh.surface_add_vertex(Vector3(-0.2, 0, -0.6))# Right barb

	# Add fletching (tail feathers) for visual interest
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, 0.8))    # Fletching base
	_immediate_mesh.surface_add_vertex(Vector3(0.15, 0, 1.0)) # Fletching right
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, 0.8))    # Fletching base
	_immediate_mesh.surface_add_vertex(Vector3(-0.15, 0, 1.0))# Fletching left

	# Add vertical fletching for visibility from all angles
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, 0.8))    # Fletching base
	_immediate_mesh.surface_add_vertex(Vector3(0, 0.15, 1.0)) # Fletching top
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, 0.8))    # Fletching base
	_immediate_mesh.surface_add_vertex(Vector3(0, -0.15, 1.0))# Fletching bottom

	_immediate_mesh.surface_end()


## Setup particle trail for arrow visibility
func _setup_trail() -> void:
	_trail_particles = GPUParticles3D.new()
	_trail_particles.amount = 20
	_trail_particles.lifetime = 0.3
	_trail_particles.one_shot = false
	_trail_particles.explosiveness = 0.0
	_trail_particles.local_coords = false  # World space for trail effect
	_trail_particles.emitting = false

	# Create particle material
	_trail_material = ParticleProcessMaterial.new()
	_trail_material.direction = Vector3(0, 0, 1)  # Emit behind arrow
	_trail_material.spread = 5.0
	_trail_material.initial_velocity_min = 1.0
	_trail_material.initial_velocity_max = 2.0
	_trail_material.gravity = Vector3.ZERO

	# Scale down over lifetime for tail effect
	_trail_material.scale_min = 0.15
	_trail_material.scale_max = 0.2
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	_trail_material.scale_curve = scale_curve_tex

	# Color based on projectile type with fade out
	var trail_color: Color = ARROW_COLORS.get(projectile_type, Color(0.4, 0.25, 0.1))
	trail_color.a = 0.8
	_trail_material.color = trail_color

	# Alpha fade over lifetime
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 1.0))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_curve_tex := CurveTexture.new()
	alpha_curve_tex.curve = alpha_curve
	_trail_material.alpha_curve = alpha_curve_tex

	_trail_particles.process_material = _trail_material

	# Use a simple quad mesh for particles
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	_trail_particles.draw_pass_1 = quad

	add_child(_trail_particles)


## Update arrow color based on projectile type
func set_projectile_type(type: ProjectileType) -> void:
	projectile_type = type
	if _arrow_material:
		_arrow_material.albedo_color = ARROW_COLORS.get(type, ARROW_COLORS[ProjectileType.ARROW])
	if _trail_material:
		var trail_color: Color = ARROW_COLORS.get(type, Color(0.4, 0.25, 0.1))
		trail_color.a = 0.8
		_trail_material.color = trail_color


## Activate projectile for use (called by pool)
func activate() -> void:
	is_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	time_alive = 0.0
	pierce_count = 0
	pierced_targets.clear()
	_damage_multiplier = 1.0

	# Start trail emission
	if _trail_particles:
		_trail_particles.emitting = true


## Deactivate projectile for pooling (called by pool)
func deactivate() -> void:
	is_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	target = null
	origin = null
	pierced_targets.clear()

	# Stop trail emission
	if _trail_particles:
		_trail_particles.emitting = false


## Initialize projectile for flight (legacy support)
func init(from_regiment: Regiment, to_regiment: Regiment) -> void:
	origin = from_regiment
	target = to_regiment
	global_position = from_regiment.global_position + Vector3(0, 2, 0)
	# Note: No longer uses sprite texture - arrow mesh is procedural
	start_flight()


## Start the flight
func start_flight() -> void:
	initial_height = global_position.y
	time_alive = 0.0
	is_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT

	# Calculate initial direction
	if is_instance_valid(target):
		direction = (target.global_position - global_position).normalized()


## Set target for homing
func set_target(new_target: Node) -> void:
	if new_target is Regiment:
		target = new_target
	elif new_target and new_target.has_method("get_regiment"):
		target = new_target.get_regiment()


## Set source regiment
func set_source(source: Node) -> void:
	if source is Regiment:
		origin = source


## Set movement direction
func set_direction(dir: Vector3) -> void:
	direction = dir.normalized()


## Get current damage multiplier (affected by piercing)
func get_damage_multiplier() -> float:
	return _damage_multiplier


func _process(delta: float) -> void:
	if not is_active:
		return

	time_alive += delta

	# Check lifetime expiration
	if time_alive >= lifetime:
		_return_to_pool()
		return

	# Update homing direction
	if is_homing and time_alive > homing_acquire_delay:
		_update_homing(delta)

	# Move projectile
	_update_movement(delta)

	# Check for collisions
	_check_collisions()


## Update homing behavior with lerp-based direction smoothing
func _update_homing(delta: float) -> void:
	if not is_instance_valid(target):
		return

	if target.state == Regiment.State.DEAD:
		# Target died - disable homing, continue on current path
		is_homing = false
		return

	# Calculate direction to target
	var to_target: Vector3 = (target.global_position - global_position).normalized()

	# Lerp current direction toward target (smooth homing)
	direction = direction.lerp(to_target, homing_strength * delta)
	direction = direction.normalized()


## Update projectile movement
func _update_movement(delta: float) -> void:
	# Apply velocity
	var velocity: Vector3 = direction * speed * delta

	# Apply arc (parabolic trajectory)
	var arc_progress: float = time_alive / lifetime
	var arc_offset: float = arc_height * sin(arc_progress * PI)

	global_position += velocity
	global_position.y = initial_height + arc_offset

	# Face movement direction
	if velocity.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP)


## Check for collisions with targets
func _check_collisions() -> void:
	if not is_instance_valid(target):
		_check_ground_collision()
		return

	# Check distance to target
	var dist_to_target: float = global_position.distance_to(target.global_position + Vector3(0, 1, 0))

	if dist_to_target < 1.5:  # Hit radius
		_on_hit_target(target)


## Check if projectile hit ground
func _check_ground_collision() -> void:
	if global_position.y < initial_height - 1.0:
		# Hit ground - check for AOE
		if aoe_radius > 0:
			_trigger_aoe(global_position)
		_return_to_pool()


## Handle hitting a target
func _on_hit_target(target_regiment: Regiment) -> void:
	# Skip if already pierced this target
	if target_regiment in pierced_targets:
		return

	# Calculate damage multiplier with pierce falloff
	# Formula from Catacombs of Gore: damage *= pow(1.0 - falloff, pierce_count)
	_damage_multiplier = pow(1.0 - pierce_damage_falloff, pierce_count)

	# Emit hit signal (use self to access signal, not parameter)
	hit_target.emit(target_regiment, _damage_multiplier)

	# Resolve the hit through combat manager
	if is_instance_valid(origin):
		CombatManager.resolve_ranged_hit_with_multiplier(origin, target_regiment, _damage_multiplier)

	# Check for piercing
	if pierce_count < max_pierces:
		pierce_count += 1
		pierced_targets.append(target_regiment)
		pierced_target.emit(target_regiment, pierce_count)
		# Continue flight - find next target
		_acquire_next_target()
	else:
		# No more pierces - check AOE and return
		if aoe_radius > 0:
			_trigger_aoe(global_position)
		_return_to_pool()


## Find next target for piercing projectile
func _acquire_next_target() -> void:
	if not is_instance_valid(origin):
		return

	# Get nearby enemies in direction of travel
	var regiments: Array = get_tree().get_nodes_in_group("regiments")
	var best_target: Regiment = null
	var best_score: float = -1.0

	for reg in regiments:
		if not is_instance_valid(reg):
			continue
		if reg in pierced_targets:
			continue
		if reg.faction == origin.faction:
			continue
		if reg.state == Regiment.State.DEAD:
			continue

		# Score based on distance and alignment with direction
		var to_reg: Vector3 = reg.global_position - global_position
		var dist: float = to_reg.length()

		if dist > 20.0:  # Max pierce range
			continue

		var alignment: float = direction.dot(to_reg.normalized())
		if alignment < 0.5:  # Must be roughly in front
			continue

		var score: float = alignment / (dist + 1.0)
		if score > best_score:
			best_score = score
			best_target = reg

	if best_target:
		target = best_target


## Trigger AOE explosion
func _trigger_aoe(pos: Vector3) -> void:
	aoe_triggered.emit(pos, aoe_radius)

	if not is_instance_valid(origin):
		return

	# Find all regiments in AOE radius
	var regiments: Array = get_tree().get_nodes_in_group("regiments")

	for reg in regiments:
		if not is_instance_valid(reg):
			continue
		if reg.faction == origin.faction:
			continue
		if reg.state == Regiment.State.DEAD:
			continue

		var dist: float = pos.distance_to(reg.global_position)
		if dist > aoe_radius:
			continue

		# Calculate AOE damage multiplier
		var aoe_mult: float = 1.0
		if aoe_damage_falloff:
			# Linear falloff from center to edge
			var falloff_ratio: float = dist / aoe_radius
			aoe_mult = lerp(1.0, aoe_min_damage_mult, falloff_ratio)

		# Apply piercing falloff on top of AOE
		var total_mult: float = _damage_multiplier * aoe_mult

		# Deal damage
		CombatManager.resolve_ranged_hit_with_multiplier(origin, reg, total_mult)

	# Spawn explosion visual effect
	if CombatEffects:
		CombatEffects.spawn_explosion(pos, aoe_radius)


## Return projectile to pool
func _return_to_pool() -> void:
	is_active = false
	returned_to_pool.emit(self)


## Legacy callback for impact (for compatibility)
func _on_impact() -> void:
	if is_instance_valid(target):
		_on_hit_target(target)
	else:
		_return_to_pool()
