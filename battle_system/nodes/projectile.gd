## Projectile for ranged attacks
## Upgraded with Catacombs of Gore patterns:
## - Object pooling (activate/deactivate)
## - Homing with lerp-based direction smoothing
## - Piercing with damage falloff
## - AOE explosions on impact
## - Configurable collision masks
## - Procedural line arrow visuals (ImmediateMesh)
## - Optional sprite-based arrow visuals (SpriteEffectPool)

class_name Projectile
extends Node3D

# === Visual Mode Toggle ===
## When true, uses 3D model arrow rendering instead of procedural lines or sprites
@export var use_3d_arrows: bool = true
## When true (and use_3d_arrows is false), uses sprite-based arrow rendering
@export var use_sprite_arrows: bool = false
## DEBUG: Show big red box instead of arrow model for visibility testing
@export var debug_arrow_placeholder: bool = false

# 3D arrow model reference
var _arrow_3d_scene: PackedScene = null
var _arrow_3d_instance: Node3D = null

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
@export var homing_strength: float = 3.0  # Lerp rate per second (legacy)
@export var homing_turn_rate: float = 180.0  # Degrees per second for slerp turning
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
enum ProjectileType { ARROW, CROSSBOW, MAGIC, SHELL, FLAME, PELLET, CHAIN }
@export var projectile_type: ProjectileType = ProjectileType.ARROW

# === Arrow Visual Colors by Type ===
const ARROW_COLORS: Dictionary = {
	ProjectileType.ARROW: Color(0.4, 0.25, 0.1),     # Brown arrow
	ProjectileType.CROSSBOW: Color(0.3, 0.3, 0.35),  # Gray crossbow bolt
	ProjectileType.MAGIC: Color(0.3, 0.5, 1.0),      # Blue magic projectile
	ProjectileType.SHELL: Color(0.15, 0.15, 0.15),   # Dark cannonball
	ProjectileType.FLAME: Color(1.0, 0.5, 0.1),      # Orange fire
	ProjectileType.PELLET: Color(0.2, 0.2, 0.2),     # Dark grapeshot pellet
	ProjectileType.CHAIN: Color(0.25, 0.25, 0.25),   # Dark chain shot
}

# === Trail Color Override (from config) ===
var trail_color_override: Color = Color.TRANSPARENT
var trail_particles_override: int = -1
var trail_lifetime_override: float = -1.0
var impact_effect_type: String = ""

# === Damage Type for Visual Effects ===
## Maps to SpellData.DamageType enum for damage-type-appropriate visuals.
## -1 = not set (use projectile_type colors instead)
var damage_type: int = -1

# Trail colors by damage type (matches SpellData.DamageType enum values)
# 0=FIRE, 1=ICE, 2=LIGHTNING, 3=HOLY, 4=DARK, 5=PHYSICAL
const DAMAGE_TYPE_TRAIL_COLORS: Dictionary = {
	0: Color(1.0, 0.4, 0.1, 0.9),    # FIRE: orange/red
	1: Color(0.4, 0.7, 1.0, 0.9),    # ICE: light blue
	2: Color(0.8, 0.9, 1.0, 0.9),    # LIGHTNING: white/yellow
	3: Color(1.0, 0.95, 0.7, 0.9),   # HOLY: gold
	4: Color(0.3, 0.1, 0.4, 0.9),    # DARK: purple
	5: Color(0.5, 0.45, 0.4, 0.9),   # PHYSICAL: brown/gray
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

# Arc tracking for proper parabolic motion
var _start_position: Vector3 = Vector3.ZERO
var _target_position: Vector3 = Vector3.ZERO
var _total_distance: float = 0.0
var _distance_traveled: float = 0.0

# === Chain Shot Rotation ===
var _chain_rotation: float = 0.0

# === Airburst Properties ===
var airburst_height: float = 0.0  # Height above target to explode (0 = disabled)
var is_airburst: bool = false

# Arrow mesh visuals (procedural line drawing)
var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _arrow_material: StandardMaterial3D

# Trail effect for arrow visibility
var _trail_particles: GPUParticles3D
var _trail_material: ParticleProcessMaterial

# Sprite-based arrow effect (when use_sprite_arrows is true)
var _sprite_effect_idx: int = -1
var _sprite_direction: int = 0

# Legacy sprite reference (disabled, kept for compatibility)
@onready var sprite: Sprite3D = $Sprite3D


func _ready() -> void:
	# Load 3D arrow scene for model-based rendering
	if use_3d_arrows:
		_arrow_3d_scene = load("res://battle_system/nodes/arrow_3d.tscn")

	# Setup procedural arrow mesh (hidden if using 3D or sprites)
	_setup_arrow_mesh()

	# Setup trail particles
	_setup_trail()

	# Disable legacy sprite if it exists
	if sprite:
		sprite.visible = false

	# Hide procedural mesh if using 3D arrows or sprite arrows
	if (use_3d_arrows or use_sprite_arrows) and _mesh_instance:
		_mesh_instance.visible = false

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


## Draw the projectile shape using PRIMITIVE_LINES
## Shape depends on projectile_type
func _draw_arrow() -> void:
	_immediate_mesh.clear_surfaces()

	match projectile_type:
		ProjectileType.SHELL:
			_draw_shell()
		ProjectileType.FLAME:
			_draw_flame()
		ProjectileType.MAGIC:
			_draw_magic()
		ProjectileType.PELLET:
			_draw_pellet()
		ProjectileType.CHAIN:
			_draw_chain()
		_:
			_draw_arrow_shape()


## Draw arrow/bolt shape (default)
func _draw_arrow_shape() -> void:
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


## Draw cannonball/shell shape (sphere outline)
func _draw_shell() -> void:
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Draw sphere wireframe with 3 circles
	var radius: float = 0.4
	var segments: int = 12

	# Horizontal circle (XZ plane)
	for i in segments:
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle1) * radius, 0, sin(angle1) * radius))
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle2) * radius, 0, sin(angle2) * radius))

	# Vertical circle (XY plane)
	for i in segments:
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle1) * radius, sin(angle1) * radius, 0))
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle2) * radius, sin(angle2) * radius, 0))

	# Vertical circle (YZ plane)
	for i in segments:
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_add_vertex(Vector3(0, cos(angle1) * radius, sin(angle1) * radius))
		_immediate_mesh.surface_add_vertex(Vector3(0, cos(angle2) * radius, sin(angle2) * radius))

	_immediate_mesh.surface_end()


## Draw flame projectile shape (elongated with flickering edges)
func _draw_flame() -> void:
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Core flame shape - elongated teardrop pointing forward (-Z)
	# Front point
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -0.8))
	_immediate_mesh.surface_add_vertex(Vector3(0.3, 0, 0))

	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -0.8))
	_immediate_mesh.surface_add_vertex(Vector3(-0.3, 0, 0))

	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -0.8))
	_immediate_mesh.surface_add_vertex(Vector3(0, 0.3, 0))

	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -0.8))
	_immediate_mesh.surface_add_vertex(Vector3(0, -0.3, 0))

	# Rear flames (jagged tail)
	_immediate_mesh.surface_add_vertex(Vector3(0.3, 0, 0))
	_immediate_mesh.surface_add_vertex(Vector3(0.15, 0.1, 0.6))

	_immediate_mesh.surface_add_vertex(Vector3(-0.3, 0, 0))
	_immediate_mesh.surface_add_vertex(Vector3(-0.15, -0.1, 0.6))

	_immediate_mesh.surface_add_vertex(Vector3(0, 0.3, 0))
	_immediate_mesh.surface_add_vertex(Vector3(0.1, 0.15, 0.7))

	_immediate_mesh.surface_add_vertex(Vector3(0, -0.3, 0))
	_immediate_mesh.surface_add_vertex(Vector3(-0.1, -0.15, 0.7))

	# Cross-hatching for volume
	_immediate_mesh.surface_add_vertex(Vector3(0.3, 0, 0))
	_immediate_mesh.surface_add_vertex(Vector3(-0.3, 0, 0))

	_immediate_mesh.surface_add_vertex(Vector3(0, 0.3, 0))
	_immediate_mesh.surface_add_vertex(Vector3(0, -0.3, 0))

	_immediate_mesh.surface_end()


## Draw magic projectile shape (star/sparkle)
func _draw_magic() -> void:
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Six-pointed star
	var outer_radius: float = 0.4
	var inner_radius: float = 0.2

	for i in 6:
		var angle_out: float = TAU * float(i) / 6.0
		var angle_in: float = TAU * (float(i) + 0.5) / 6.0

		# Outer point to center
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle_out) * outer_radius, sin(angle_out) * outer_radius, 0))
		_immediate_mesh.surface_add_vertex(Vector3.ZERO)

		# Center to inner point
		_immediate_mesh.surface_add_vertex(Vector3.ZERO)
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle_in) * inner_radius, sin(angle_in) * inner_radius, 0))

	# Forward spike
	_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, -0.5))

	# Back spike
	_immediate_mesh.surface_add_vertex(Vector3.ZERO)
	_immediate_mesh.surface_add_vertex(Vector3(0, 0, 0.3))

	_immediate_mesh.surface_end()


## Draw pellet shape (small grapeshot pellet - simpler than shell)
func _draw_pellet() -> void:
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Small simple circle - single ring instead of full sphere wireframe
	var radius: float = 0.15
	var segments: int = 8

	# Single horizontal circle (XZ plane)
	for i in segments:
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle1) * radius, 0, sin(angle1) * radius))
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle2) * radius, 0, sin(angle2) * radius))

	# Single vertical circle for depth (XY plane)
	for i in segments:
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle1) * radius, sin(angle1) * radius, 0))
		_immediate_mesh.surface_add_vertex(Vector3(cos(angle2) * radius, sin(angle2) * radius, 0))

	_immediate_mesh.surface_end()


## Draw chain shot shape (two spheres connected by a chain line, rotates over time)
func _draw_chain() -> void:
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	var ball_radius: float = 0.2
	var chain_length: float = 0.6  # Distance from center to each ball
	var segments: int = 8

	# Apply rotation around the forward axis (Z)
	var rot_cos: float = cos(_chain_rotation)
	var rot_sin: float = sin(_chain_rotation)

	# Ball 1 position (rotated)
	var ball1_pos := Vector3(rot_cos * chain_length, rot_sin * chain_length, 0)
	# Ball 2 position (opposite side)
	var ball2_pos := Vector3(-rot_cos * chain_length, -rot_sin * chain_length, 0)

	# Draw chain line connecting the two balls
	_immediate_mesh.surface_add_vertex(ball1_pos)
	_immediate_mesh.surface_add_vertex(ball2_pos)

	# Draw ball 1 (simple circle in XY plane at ball1 position)
	for i in segments:
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_add_vertex(ball1_pos + Vector3(cos(angle1) * ball_radius, sin(angle1) * ball_radius, 0))
		_immediate_mesh.surface_add_vertex(ball1_pos + Vector3(cos(angle2) * ball_radius, sin(angle2) * ball_radius, 0))

	# Draw ball 2 (simple circle in XY plane at ball2 position)
	for i in segments:
		var angle1: float = TAU * float(i) / float(segments)
		var angle2: float = TAU * float(i + 1) / float(segments)
		_immediate_mesh.surface_add_vertex(ball2_pos + Vector3(cos(angle1) * ball_radius, sin(angle1) * ball_radius, 0))
		_immediate_mesh.surface_add_vertex(ball2_pos + Vector3(cos(angle2) * ball_radius, sin(angle2) * ball_radius, 0))

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


## Update trail settings based on projectile type or config overrides
func _update_trail_for_type() -> void:
	if not _trail_material or not _trail_particles:
		return

	# Apply overrides if set, otherwise use type defaults
	# Priority: trail_color_override > damage_type color > projectile_type color
	var trail_color: Color
	if trail_color_override.a > 0:
		trail_color = trail_color_override
	elif damage_type >= 0 and damage_type in DAMAGE_TYPE_TRAIL_COLORS:
		trail_color = DAMAGE_TYPE_TRAIL_COLORS[damage_type]
	else:
		trail_color = ARROW_COLORS.get(projectile_type, Color(0.4, 0.25, 0.1))
		trail_color.a = 0.8

	_trail_material.color = trail_color

	# Update particle count and lifetime
	if trail_particles_override > 0:
		_trail_particles.amount = trail_particles_override
	if trail_lifetime_override > 0:
		_trail_particles.lifetime = trail_lifetime_override

	# Type-specific trail adjustments
	match projectile_type:
		ProjectileType.SHELL:
			# Smoke trail for cannonballs
			_trail_material.spread = 15.0
			_trail_material.scale_min = 0.3
			_trail_material.scale_max = 0.5
			_trail_material.gravity = Vector3(0, 0.5, 0)  # Smoke rises slightly
		ProjectileType.FLAME:
			# Fire trail for breath weapons
			_trail_material.spread = 25.0
			_trail_material.scale_min = 0.4
			_trail_material.scale_max = 0.8
			_trail_material.initial_velocity_min = 2.0
			_trail_material.initial_velocity_max = 4.0
			# Add ember-like behavior
			_trail_material.gravity = Vector3(0, 1.0, 0)  # Fire rises
		ProjectileType.MAGIC:
			# Sparkle trail for magic
			_trail_material.spread = 10.0
			_trail_material.scale_min = 0.1
			_trail_material.scale_max = 0.25
		ProjectileType.PELLET:
			# Minimal trail for small grapeshot pellets
			_trail_material.spread = 8.0
			_trail_material.scale_min = 0.08
			_trail_material.scale_max = 0.12
			_trail_material.gravity = Vector3.ZERO
		ProjectileType.CHAIN:
			# Light smoke trail for chain shot
			_trail_material.spread = 12.0
			_trail_material.scale_min = 0.2
			_trail_material.scale_max = 0.35
			_trail_material.gravity = Vector3(0, 0.3, 0)  # Slight rise
		_:
			# Default arrow/bolt trail
			_trail_material.spread = 5.0
			_trail_material.scale_min = 0.15
			_trail_material.scale_max = 0.2
			_trail_material.gravity = Vector3.ZERO


## Update arrow color based on projectile type
func set_projectile_type(type: ProjectileType) -> void:
	projectile_type = type
	if _arrow_material:
		_arrow_material.albedo_color = ARROW_COLORS.get(type, ARROW_COLORS[ProjectileType.ARROW])
	if _immediate_mesh:
		_draw_arrow()  # Redraw shape for new type
	_update_trail_for_type()


## Apply configuration from WeaponClassData or SpellData
## Called after spawn_configured sets core properties.
## Handles visual/effect config and any remaining overrides.
func apply_config(config: Dictionary) -> void:
	# === TRAIL VISUAL OVERRIDES ===
	if "trail_color" in config and config["trail_color"] is Color:
		trail_color_override = config["trail_color"]
	if "trail_particles" in config:
		trail_particles_override = config["trail_particles"]
	if "trail_lifetime" in config:
		trail_lifetime_override = config["trail_lifetime"]

	# === IMPACT EFFECT TYPE ===
	if "impact_effect" in config:
		impact_effect_type = config["impact_effect"]

	# === PROJECTILE TYPE (visual shape) ===
	if "projectile_type" in config:
		set_projectile_type(config["projectile_type"] as ProjectileType)

	# === DAMAGE TYPE (for trail/impact coloring) ===
	if "damage_type" in config:
		damage_type = config["damage_type"]

	# === HOMING (can be set via config or spawn_configured) ===
	if "is_homing" in config:
		is_homing = config["is_homing"]
	if "homing_turn_rate" in config:
		homing_turn_rate = config["homing_turn_rate"]
	if "homing_strength" in config:
		homing_strength = config["homing_strength"]

	# === AOE (can be set via config or spawn_configured) ===
	if "aoe_radius" in config:
		aoe_radius = config["aoe_radius"]

	# === AIRBURST (shrapnel rounds) ===
	if "airburst_height" in config and config["airburst_height"] > 0.0:
		airburst_height = config["airburst_height"]
		is_airburst = true

	# === HAZARD CREATION (incendiary rounds, fire spells) ===
	# Store hazard metadata for impact handling
	if config.get("leaves_hazard", false):
		set_meta("leaves_hazard", true)
		set_meta("hazard_duration", config.get("hazard_duration", 8.0))
		set_meta("hazard_damage_per_sec", config.get("hazard_damage_per_sec", 3.0))
		set_meta("hazard_radius", config.get("aoe_radius", 4.0))

	# Update trail visuals after all config applied
	_update_trail_for_type()


## Activate projectile for use (called by pool)
func activate() -> void:
	print("[PROJECTILE ACTIVATE] Called! use_3d=", use_3d_arrows, " type=", projectile_type, " debug=", debug_arrow_placeholder)
	is_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	time_alive = 0.0
	pierce_count = 0
	pierced_targets.clear()
	_damage_multiplier = 1.0
	_chain_rotation = 0.0

	# Update trail settings for current type
	_update_trail_for_type()

	# Start trail emission
	if _trail_particles:
		_trail_particles.emitting = true

	# Determine which visual mode to use
	var is_arrow_type: bool = projectile_type in [ProjectileType.ARROW, ProjectileType.CROSSBOW]

	# Use 3D arrow model for arrows and crossbow bolts
	if use_3d_arrows and is_arrow_type:
		print("[PROJECTILE] activate() - type=", projectile_type, " use_3d=", use_3d_arrows, " debug=", debug_arrow_placeholder)
		_spawn_3d_arrow()
		if _mesh_instance:
			_mesh_instance.visible = false
	# Use sprite arrows if 3D disabled but sprites enabled
	elif use_sprite_arrows and is_arrow_type:
		_spawn_sprite_arrow()
		if _mesh_instance:
			_mesh_instance.visible = false
	else:
		# Use procedural mesh for special projectile types (shells, magic, flame, etc.)
		if _mesh_instance:
			_mesh_instance.visible = true
			# Update mesh material color for projectile type
			if _arrow_material:
				_arrow_material.albedo_color = ARROW_COLORS.get(projectile_type, ARROW_COLORS[ProjectileType.ARROW])
		# Hide 3D arrow if it exists
		if _arrow_3d_instance:
			_arrow_3d_instance.visible = false


## Deactivate projectile for pooling (called by pool)
## CRITICAL: Must reset ALL state to prevent carryover between uses.
func deactivate() -> void:
	is_active = false
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

	# === CLEAR REFERENCES ===
	target = null
	origin = null
	pierced_targets.clear()

	# === RESET MOVEMENT PROPERTIES ===
	speed = 30.0  # Default
	arc_height = 10.0  # Default
	lifetime = 5.0  # Default
	direction = Vector3.FORWARD
	time_alive = 0.0
	_distance_traveled = 0.0

	# === RESET HOMING ===
	is_homing = false
	homing_strength = 3.0  # Default
	homing_turn_rate = 180.0  # Default

	# === RESET PIERCING ===
	max_pierces = 0
	pierce_damage_falloff = 0.25  # Default
	pierce_count = 0
	_damage_multiplier = 1.0

	# === RESET AOE ===
	aoe_radius = 0.0
	aoe_damage_falloff = true
	aoe_min_damage_mult = 0.25

	# === RESET AIRBURST ===
	airburst_height = 0.0
	is_airburst = false

	# === RESET VISUAL OVERRIDES ===
	trail_color_override = Color.TRANSPARENT
	trail_particles_override = -1
	trail_lifetime_override = -1.0
	impact_effect_type = ""
	damage_type = -1
	projectile_type = ProjectileType.ARROW  # Default
	_chain_rotation = 0.0

	# === CLEAR METADATA ===
	# Remove any metadata set by spell_caster or combat_manager
	if has_meta("spell_data"):
		remove_meta("spell_data")
	if has_meta("caster"):
		remove_meta("caster")
	if has_meta("target_pos"):
		remove_meta("target_pos")
	if has_meta("leaves_hazard"):
		remove_meta("leaves_hazard")
	if has_meta("hazard_duration"):
		remove_meta("hazard_duration")
	if has_meta("hazard_damage_per_sec"):
		remove_meta("hazard_damage_per_sec")
	if has_meta("hazard_radius"):
		remove_meta("hazard_radius")
	if has_meta("source_regiment"):
		remove_meta("source_regiment")
	if has_meta("hazard_spawned"):
		remove_meta("hazard_spawned")

	# === STOP EFFECTS ===
	if _trail_particles:
		_trail_particles.emitting = false

	# Clean up 3D arrow
	_hide_3d_arrow()

	# Clean up sprite arrow
	_hide_sprite_arrow()

	# === DISCONNECT SIGNALS ===
	# Clear any one-shot signal connections from spell_caster
	# This prevents stale callbacks when projectile is reused
	_disconnect_all_custom_signals()


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
	_start_position = global_position
	time_alive = 0.0
	_distance_traveled = 0.0
	is_active = true
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT

	# Calculate initial direction and distance
	if is_instance_valid(target):
		_target_position = target.global_position + Vector3(0, 1.0, 0)
		var to_target: Vector3 = _target_position - global_position
		_total_distance = to_target.length()
		direction = to_target.normalized()
	else:
		_target_position = global_position + direction * 50.0
		_total_distance = 50.0


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

	# Update chain shot rotation (spinning effect)
	if projectile_type == ProjectileType.CHAIN:
		_chain_rotation += delta * 10.0
		# Redraw mesh each frame to show rotation
		if _immediate_mesh:
			_draw_chain()

	# Update homing direction
	if is_homing and time_alive > homing_acquire_delay:
		_update_homing(delta)

	# Move projectile
	_update_movement(delta)

	# Update sprite arrow position to follow projectile
	_update_sprite_arrow()

	# Check for airburst (shrapnel exploding above target)
	if is_airburst and airburst_height > 0.0 and is_instance_valid(target):
		var target_ground_y: float = target.global_position.y
		var airburst_trigger_y: float = target_ground_y + airburst_height
		# Check if we're at or past airburst altitude and descending
		var arc_progress: float = time_alive / lifetime
		if arc_progress > 0.5 and global_position.y <= airburst_trigger_y:
			# Trigger early explosion
			if aoe_radius > 0:
				_trigger_aoe(global_position)
			_return_to_pool()
			return

	# Check for collisions
	_check_collisions()


## Update homing behavior with slerp-based turning (XZ plane only, Y handled by arc)
func _update_homing(delta: float) -> void:
	if not is_instance_valid(target):
		return

	if target.state == Regiment.State.DEAD:
		# Target died - disable homing, continue on current path
		is_homing = false
		return

	# Update target position
	_target_position = target.global_position + Vector3(0, 1.0, 0)

	# Calculate direction to target in XZ plane only (arc handles Y)
	var current_xz := Vector3(direction.x, 0.0, direction.z).normalized()
	var target_xz := Vector3(
		_target_position.x - global_position.x,
		0.0,
		_target_position.z - global_position.z
	).normalized()

	# Smoothly turn toward target using slerp
	var max_turn: float = deg_to_rad(homing_turn_rate) * delta
	var new_xz: Vector3 = current_xz.slerp(target_xz, clampf(max_turn / PI, 0.0, 1.0))
	new_xz = new_xz.normalized()

	# Update direction (keep Y component for arc calculations)
	direction = Vector3(new_xz.x, direction.y, new_xz.z).normalized()


## Update projectile movement
func _update_movement(delta: float) -> void:
	# Move forward in XZ direction
	var move_dist: float = speed * delta
	_distance_traveled += move_dist

	# Calculate arc progress (0 to 1) based on distance traveled
	var arc_progress: float = 0.0
	if _total_distance > 0.0:
		arc_progress = clampf(_distance_traveled / _total_distance, 0.0, 1.0)

	# Calculate parabolic arc offset (peaks at midpoint)
	var arc_offset: float = 4.0 * arc_height * arc_progress * (1.0 - arc_progress)

	# Calculate base height interpolation
	var base_height: float = lerpf(_start_position.y, _target_position.y, arc_progress)

	# Apply XZ movement
	var xz_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	global_position.x += xz_direction.x * move_dist
	global_position.z += xz_direction.z * move_dist

	# Apply Y with arc
	global_position.y = base_height + arc_offset

	# Face movement direction (use actual velocity for visual)
	var face_dir: Vector3 = xz_direction
	face_dir.y = (arc_height * 4.0 * (0.5 - arc_progress)) / maxf(_total_distance, 1.0)  # Arc slope
	if face_dir.length_squared() > 0.001:
		look_at(global_position + face_dir.normalized(), Vector3.UP)


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
	var regiments: Array = get_tree().get_nodes_in_group("all_regiments")
	var best_target: Regiment = null
	var best_score: float = -1.0

	for reg in regiments:
		if not is_instance_valid(reg):
			continue
		if reg in pierced_targets:
			continue
		if reg.is_player_controlled == origin.is_player_controlled:
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

	# Play explosion audio via CombatAudio system
	if CombatManager and CombatManager.combat_audio:
		CombatManager.combat_audio.play_explosion_audio(pos, aoe_radius)

	if not is_instance_valid(origin):
		return

	# Find all regiments in AOE radius
	var regiments: Array = get_tree().get_nodes_in_group("all_regiments")

	for reg in regiments:
		if not is_instance_valid(reg):
			continue
		if reg.is_player_controlled == origin.is_player_controlled:
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

	# Spawn damage-type-appropriate impact effect
	_spawn_impact_effect(pos)


## Spawn impact effect based on damage_type or fallback to generic explosion
func _spawn_impact_effect(pos: Vector3) -> void:
	# Cannon/artillery shells use dedicated cannon explosion effect
	if projectile_type == ProjectileType.SHELL or impact_effect_type == "explosion":
		var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
		if sprite_pool and sprite_pool.has_method("spawn_cannon_explosion"):
			# Pass self as context_node for SubViewport support
			sprite_pool.spawn_cannon_explosion(pos, aoe_radius, self)
			return

	# If damage_type is set, use SpellEffects for damage-type-colored burst
	if damage_type >= 0:
		var spell_effects := get_node_or_null("/root/SpellEffects")
		if spell_effects and spell_effects.has_method("spawn_impact_burst"):
			# SpellEffects expects SpellData.DamageType enum, damage_type matches those values
			spell_effects.spawn_impact_burst(pos, damage_type, aoe_radius, self)
			return

	# Fallback to CombatEffects generic explosion
	if CombatEffects:
		CombatEffects.spawn_explosion(pos, aoe_radius, self)


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


# =============================================================================
# 3D ARROW MODEL SUPPORT
# =============================================================================

## Spawn 3D arrow model instance
func _spawn_3d_arrow() -> void:
	# DEBUG MODE: Spawn big red box instead
	if debug_arrow_placeholder:
		_spawn_debug_placeholder()
		return

	if not _arrow_3d_scene:
		push_warning("[ARROW] Failed to load arrow_3d.tscn - scene is null!")
		_spawn_debug_placeholder()  # Fallback to debug box
		return

	# Reuse existing instance if available
	if _arrow_3d_instance and is_instance_valid(_arrow_3d_instance):
		_arrow_3d_instance.visible = true
		print("[ARROW] Reusing 3D arrow instance")
		return

	# Create new instance
	_arrow_3d_instance = _arrow_3d_scene.instantiate()
	add_child(_arrow_3d_instance)
	print("[ARROW] Spawned new 3D arrow instance")

	# Apply tint based on projectile type
	_apply_3d_arrow_tint()


## DEBUG: Create a big red box placeholder for arrow visibility testing
func _spawn_debug_placeholder() -> void:
	# Create a large visible box
	var debug_mesh := MeshInstance3D.new()
	debug_mesh.name = "DebugArrowBox"

	# Big red box - 2x2x2 units (very visible!)
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	debug_mesh.mesh = box

	# Bright red unshaded material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 0.0, 1.0)  # Bright red
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Always visible
	mat.no_depth_test = true  # Render on top of everything
	debug_mesh.material_override = mat

	add_child(debug_mesh)
	print("[DEBUG ARROW] Spawned red placeholder at ", global_position)


## Apply color tint to 3D arrow model based on projectile type
func _apply_3d_arrow_tint() -> void:
	if not _arrow_3d_instance:
		return

	var tint_color: Color
	match projectile_type:
		ProjectileType.ARROW:
			tint_color = Color(0.85, 0.75, 0.6)  # Warm wood color
		ProjectileType.CROSSBOW:
			tint_color = Color(0.7, 0.7, 0.75)  # Steel gray for bolts
		_:
			tint_color = Color.WHITE

	# Find mesh instances and apply tint
	_apply_tint_recursive(_arrow_3d_instance, tint_color)


## Recursively apply tint to all MeshInstance3D nodes
func _apply_tint_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		# Create override material with tint
		for i in mesh_inst.get_surface_override_material_count():
			var mat = mesh_inst.get_surface_override_material(i)
			if not mat:
				mat = mesh_inst.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.albedo_color = new_mat.albedo_color * tint
				mesh_inst.set_surface_override_material(i, new_mat)

	for child in node.get_children():
		_apply_tint_recursive(child, tint)


## Hide 3D arrow instance
func _hide_3d_arrow() -> void:
	if _arrow_3d_instance and is_instance_valid(_arrow_3d_instance):
		_arrow_3d_instance.visible = false


# =============================================================================
# SPRITE ARROW SUPPORT
# =============================================================================

## Calculate direction index (0-7) from movement direction vector
func _direction_to_index(dir: Vector3) -> int:
	# Convert direction to 8-way index
	# 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW
	var angle := atan2(dir.x, -dir.z)  # Angle from north
	if angle < 0:
		angle += TAU

	# Convert to 8-way index (each direction covers 45 degrees)
	var index := int(round(angle / (TAU / 8.0))) % 8
	return index


## Spawn sprite arrow effect
func _spawn_sprite_arrow() -> void:
	var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
	if not sprite_pool or not sprite_pool.has_method("spawn_arrow"):
		return

	_sprite_direction = _direction_to_index(direction)
	# Pass self as context_node to ensure effect spawns in correct viewport (Unit Zoo SubViewport support)
	_sprite_effect_idx = sprite_pool.spawn_arrow(global_position, _sprite_direction, projectile_type, self)


## Update sprite arrow position to follow projectile during flight
func _update_sprite_arrow() -> void:
	if _sprite_effect_idx < 0:
		return

	var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
	if not sprite_pool or not sprite_pool.has_method("update_effect_position"):
		return

	# Update direction based on current movement
	var new_direction: int = _direction_to_index(direction)

	# Update both position and direction
	sprite_pool.update_effect_position(
		"res://assets/sprites/effects/arrow_atlas.tres",
		_sprite_effect_idx,
		global_position,
		new_direction
	)


## Hide/cleanup sprite arrow effect
func _hide_sprite_arrow() -> void:
	if _sprite_effect_idx < 0:
		return

	var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
	if sprite_pool and sprite_pool.has_method("hide_effect"):
		sprite_pool.hide_effect("res://assets/sprites/effects/arrow_atlas.tres", _sprite_effect_idx)

	_sprite_effect_idx = -1


## Disconnect all custom signal connections to prevent stale callbacks.
## Called during deactivate() before returning to pool.
func _disconnect_all_custom_signals() -> void:
	# Disconnect hit_target signal callbacks (from spell_caster, combat_manager)
	for conn in hit_target.get_connections():
		var callable: Callable = conn["callable"]
		if hit_target.is_connected(callable):
			hit_target.disconnect(callable)

	# Disconnect aoe_triggered signal callbacks
	for conn in aoe_triggered.get_connections():
		var callable: Callable = conn["callable"]
		if aoe_triggered.is_connected(callable):
			aoe_triggered.disconnect(callable)

	# Disconnect pierced_target signal callbacks
	for conn in pierced_target.get_connections():
		var callable: Callable = conn["callable"]
		if pierced_target.is_connected(callable):
			pierced_target.disconnect(callable)

	# Note: returned_to_pool signal should NOT be disconnected
	# as it's used by the pool system itself
