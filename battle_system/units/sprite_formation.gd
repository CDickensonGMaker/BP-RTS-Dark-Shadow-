class_name SpriteFormation
extends Node3D

## MultiMesh-based formation manager for efficient sprite soldier rendering.
## Replaces SoldierFormation when use_sprite_soldiers is enabled.
## Uses 1 draw call for all soldiers instead of 1 per soldier.

signal formation_ready
signal soldiers_updated(count: int)

## Atlas resource containing sprite sheet and animation data
@export var atlas: SpriteUnitAtlas

## Maximum number of soldiers in formation
@export var max_soldiers: int = 100

## Grid layout
@export var rows: int = 10
@export var spacing: float = 1.2
@export var row_offset: float = 0.3  # Stagger rows for natural look

## Sprite display size in world units
@export var sprite_scale: Vector2 = Vector2(2.5, 3.0)

## Height offset above ground (so sprites float above 3D blocks)
@export var height_offset: float = 1.5

## Faction color tint (not used yet, reserved)
@export var faction_color: Color = Color.WHITE

# Internal state
var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _material: ShaderMaterial
var _shader: Shader

var alive_count: int = 0
var _soldier_positions: PackedVector3Array  # Local positions of each soldier
var _soldier_alive: PackedFloat32Array  # 1.0 = alive, 0.0 = hidden (dead soldiers stay at 1.0)
var _soldier_dead: PackedFloat32Array  # 0.0 = alive, 1.0 = dead (corpse on ground)
var _soldier_directions: PackedFloat32Array  # Direction index 0-7
var _soldier_time_offsets: PackedFloat32Array  # Animation stagger

var _terrain: Node3D = null
var _terrain_update_timer: float = 0.0
const TERRAIN_UPDATE_INTERVAL: float = 0.1  # Update terrain positions 10x/sec

# Camera-relative direction tracking
var _world_facing_angle: float = 0.0  # Store world-space facing for camera updates
var _last_camera_rotation: float = 0.0
var _direction_update_timer: float = 0.0
const DIRECTION_UPDATE_INTERVAL: float = 0.05  # Update sprite directions 20x/sec when camera rotates
const DIRECTION_HYSTERESIS: float = 0.15  # Radians (~8.5°) of hysteresis to prevent jitter

# Direction tracking for hysteresis
var _current_direction_index: int = -1  # -1 forces initial calculation

# Animation state
var _current_animation: String = "idle"


func _ready():
	_setup_shader()
	_setup_multimesh()
	spawn_formation(max_soldiers)
	call_deferred("_find_terrain")


func _find_terrain():
	var terrains: Array[Node] = get_tree().get_nodes_in_group("terrain")
	if terrains.size() > 0:
		_terrain = terrains[0]


func _process(delta: float):
	_terrain_update_timer += delta
	if _terrain_update_timer >= TERRAIN_UPDATE_INTERVAL:
		_terrain_update_timer = 0.0
		_update_soldier_terrain_positions()

	# Update sprite directions when camera rotates
	_direction_update_timer += delta
	if _direction_update_timer >= DIRECTION_UPDATE_INTERVAL:
		_direction_update_timer = 0.0
		_update_camera_relative_directions()


func _setup_shader():
	# Load shader
	_shader = load("res://battle_system/shaders/unit_sprite.gdshader")
	if not _shader:
		push_error("SpriteFormation: Failed to load shader!")
		return

	_material = ShaderMaterial.new()
	_material.shader = _shader

	# Set atlas texture and dimensions if atlas is available
	if atlas:
		if atlas.texture:
			_material.set_shader_parameter("sprite_atlas", atlas.texture)
			print("SpriteFormation: Atlas texture loaded: ", atlas.texture.get_size())
		else:
			push_warning("SpriteFormation: Atlas has no texture!")
		_material.set_shader_parameter("atlas_columns", atlas.columns)
		_material.set_shader_parameter("atlas_rows", atlas.rows)
		_material.set_shader_parameter("anim_speed", atlas.animation_speed)
		# Debug: set to true to see red quads, false for actual sprites
		_material.set_shader_parameter("debug_mode", false)

		# Set death animation parameters for corpses on ground
		var death_start := atlas.get_animation_start("death")
		var death_frames := atlas.get_animation_frame_count("death")
		_material.set_shader_parameter("death_anim_start", death_start)
		_material.set_shader_parameter("death_anim_frames", death_frames)
		print("SpriteFormation: Death anim params - start=", death_start, " frames=", death_frames)
	else:
		push_warning("SpriteFormation: No atlas assigned!")

	# Set default animation (idle)
	_set_animation_params("idle")


func _setup_multimesh():
	# Create quad mesh for each soldier
	var quad := QuadMesh.new()
	quad.size = sprite_scale
	quad.orientation = PlaneMesh.FACE_Z  # Vertical quad, shader handles billboard rotation

	# Create MultiMesh
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = max_soldiers

	# Create MultiMeshInstance3D
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.material_override = _material
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)


func spawn_formation(count: int):
	"""Spawn soldiers in a grid formation."""
	count = mini(count, max_soldiers)
	alive_count = count

	# Initialize arrays
	_soldier_positions.resize(max_soldiers)
	_soldier_alive.resize(max_soldiers)
	_soldier_dead.resize(max_soldiers)
	_soldier_directions.resize(max_soldiers)
	_soldier_time_offsets.resize(max_soldiers)

	var cols := ceili(float(count) / float(rows))

	for i in max_soldiers:
		var is_alive := i < count

		if is_alive:
			var row := i / cols
			var col := i % cols

			# Calculate position with slight randomization
			var x := (float(col) - cols / 2.0) * spacing + randf_range(-0.1, 0.1)
			var z := (float(row) - rows / 2.0) * spacing + randf_range(-0.1, 0.1)

			# Offset alternating rows
			if row % 2 == 1:
				x += row_offset

			# Y position: half sprite height + offset above blocks
			_soldier_positions[i] = Vector3(x, sprite_scale.y * 0.5 + height_offset, z)
		else:
			_soldier_positions[i] = Vector3.ZERO

		_soldier_alive[i] = 1.0 if is_alive else 0.0
		_soldier_dead[i] = 0.0  # Not dead yet
		_soldier_directions[i] = 0.0  # Default facing south
		_soldier_time_offsets[i] = randf()  # Random stagger for animation variety

		# Set MultiMesh instance transform and custom data
		_update_instance(i)

	formation_ready.emit()
	soldiers_updated.emit(alive_count)


func clear_formation():
	"""Remove all soldiers."""
	alive_count = 0
	for i in max_soldiers:
		_soldier_alive[i] = 0.0
		_update_instance_custom_data(i)


func set_soldier_count(count: int):
	"""Update visible soldiers to match casualties."""
	count = clampi(count, 0, max_soldiers)

	# Hide/show soldiers from the back
	for i in max_soldiers:
		_soldier_alive[i] = 1.0 if i < count else 0.0
		_update_instance_custom_data(i)

	alive_count = count
	soldiers_updated.emit(alive_count)


func kill_soldiers(amount: int):
	"""Kill soldiers from back of formation - they stay visible as corpses."""
	var killed := 0
	for i in range(max_soldiers - 1, -1, -1):
		if killed >= amount:
			break
		# Only kill soldiers that are alive and not already dead
		if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
			_soldier_dead[i] = 1.0  # Mark as dead corpse (stays visible)
			# Don't set _soldier_alive to 0 - we want them to stay rendered
			_update_instance_custom_data(i)
			killed += 1
			alive_count -= 1
			print("SpriteFormation: Killed soldier ", i, " dead_flag=", _soldier_dead[i])

	if killed > 0:
		print("SpriteFormation: Killed ", killed, " soldiers, ", alive_count, " remaining")
	soldiers_updated.emit(alive_count)


func play_animation_all(anim_name: String):
	"""Play animation on all soldiers via shader uniforms."""
	_current_animation = anim_name
	_set_animation_params(anim_name)


func play_animation_staggered(anim_name: String, _stagger_time: float = 0.05):
	"""Play animation with stagger effect (handled by per-instance time offsets)."""
	# The stagger is automatic via _soldier_time_offsets in custom_data
	# Just set the animation
	_current_animation = anim_name
	_set_animation_params(anim_name)


func set_facing_direction(direction: Vector3):
	"""Set all soldiers to face a direction (camera-relative)."""
	# Store world-space angle for later camera rotation updates
	_world_facing_angle = atan2(direction.x, direction.z)
	_current_direction_index = -1  # Force recalculation when facing changes
	_apply_camera_relative_direction()


func set_facing_angle(angle_rad: float):
	"""Set all soldiers to face an angle (radians, camera-relative)."""
	# Store world-space angle for later camera rotation updates
	_world_facing_angle = angle_rad
	_current_direction_index = -1  # Force recalculation when facing changes
	_apply_camera_relative_direction()


func _apply_camera_relative_direction():
	"""Apply camera-relative direction to all soldiers based on stored world angle."""
	var camera := get_viewport().get_camera_3d()
	var camera_y_angle := 0.0
	if camera:
		camera_y_angle = camera.global_rotation.y
		_last_camera_rotation = camera_y_angle

	# Fixed: Add PI offset for correct camera-relative direction
	# This ensures sprites show the correct facing relative to camera view
	var camera_relative_angle := _world_facing_angle - camera_y_angle + PI

	var new_dir_index := SpriteUnitAtlas.direction_from_angle(camera_relative_angle)

	# Hysteresis: Only change direction if clearly in new zone to prevent jitter
	if new_dir_index != _current_direction_index and _current_direction_index >= 0:
		var normalized := fmod(camera_relative_angle + TAU, TAU)
		var center_of_new := float(new_dir_index) * (PI / 4.0)
		var diff := absf(fmod(normalized - center_of_new + PI, TAU) - PI)
		if diff > DIRECTION_HYSTERESIS:
			return  # Stay with current direction until clearly past boundary

	_current_direction_index = new_dir_index

	for i in max_soldiers:
		if _soldier_alive[i] > 0.5:
			_soldier_directions[i] = float(_current_direction_index)
			_update_instance_custom_data(i)


func _update_camera_relative_directions():
	"""Update sprite directions if camera has rotated."""
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return

	var current_camera_rotation := camera.global_rotation.y
	# Only update if camera rotation changed significantly (more than 5 degrees)
	if absf(current_camera_rotation - _last_camera_rotation) > 0.087:  # ~5 degrees in radians
		_apply_camera_relative_direction()


func get_formation_bounds() -> AABB:
	"""Get bounding box of the formation."""
	if alive_count == 0:
		return AABB()

	var min_pos := Vector3.INF
	var max_pos := -Vector3.INF

	for i in max_soldiers:
		if _soldier_alive[i] > 0.5:
			min_pos = min_pos.min(_soldier_positions[i])
			max_pos = max_pos.max(_soldier_positions[i])

	return AABB(min_pos, max_pos - min_pos)


# --- INTERNAL METHODS ---

func _set_animation_params(anim_name: String):
	"""Set shader parameters for the current animation."""
	if not atlas:
		push_warning("SpriteFormation: No atlas when setting animation: ", anim_name)
		return
	if not _material:
		push_warning("SpriteFormation: No material when setting animation: ", anim_name)
		return

	var start_frame := atlas.get_animation_start(anim_name)
	var frame_count := atlas.get_animation_frame_count(anim_name)

	print("SpriteFormation: Setting anim '", anim_name, "' start=", start_frame, " frames=", frame_count)
	_material.set_shader_parameter("current_anim_start", start_frame)
	_material.set_shader_parameter("current_anim_frames", frame_count)


func _update_instance(index: int):
	"""Update both transform and custom data for a soldier instance."""
	var xform := Transform3D()
	xform.origin = _soldier_positions[index]
	_multimesh.set_instance_transform(index, xform)
	_update_instance_custom_data(index)


func _update_instance_custom_data(index: int):
	"""Update custom data for a soldier instance.

	Custom data layout:
	- r: animation time offset (0-1 for stagger)
	- g: direction index (0-7)
	- b: visibility (1.0 = visible, 0.0 = hidden)
	- a: dead flag (0.0 = alive, 1.0 = dead corpse - uses death animation)
	"""
	var custom := Color(
		_soldier_time_offsets[index],  # r: time offset
		_soldier_directions[index],     # g: direction
		_soldier_alive[index],          # b: visibility
		_soldier_dead[index]            # a: dead flag (0=alive, 1=dead corpse)
	)
	_multimesh.set_instance_custom_data(index, custom)


func _update_soldier_terrain_positions():
	"""Update soldier Y positions based on terrain height."""
	if not _terrain or not _terrain.has_method("get_height_at"):
		return

	for i in max_soldiers:
		if _soldier_alive[i] > 0.5:
			var world_pos: Vector3 = global_position + _soldier_positions[i]
			var terrain_height: float = _terrain.get_height_at(world_pos)
			var local_y := terrain_height - global_position.y + sprite_scale.y * 0.5

			if absf(_soldier_positions[i].y - local_y) > 0.01:
				_soldier_positions[i].y = local_y
				var xform := Transform3D()
				xform.origin = _soldier_positions[i]
				_multimesh.set_instance_transform(i, xform)


# --- COMPATIBILITY METHODS ---
# These provide interface compatibility with SoldierFormation

## Dummy property for interface compatibility
var soldiers: Array[Node3D]:
	get:
		# Return empty array - sprite formation doesn't use Node3D soldiers
		return []


func die():
	"""Kill a single soldier (called by external systems)."""
	kill_soldiers(1)


# --- DEBUG METHODS ---

func debug_cycle_animation():
	"""Cycle through all animations for testing."""
	var anims: Array[String] = ["idle", "walk", "attack", "death"]
	var current_index := anims.find(_current_animation)
	var next_index := (current_index + 1) % anims.size()
	var next_anim := anims[next_index]
	print("SpriteFormation: Cycling to animation: ", next_anim)
	play_animation_all(next_anim)


func debug_set_direction(dir_index: int):
	"""Set all soldiers to face a specific direction index (0-7)."""
	dir_index = clampi(dir_index, 0, 7)
	print("SpriteFormation: Setting direction to: ", dir_index)
	for i in max_soldiers:
		if _soldier_alive[i] > 0.5:
			_soldier_directions[i] = float(dir_index)
			_update_instance_custom_data(i)


func debug_get_status() -> Dictionary:
	"""Get current debug status information."""
	# Count dead soldiers (corpses)
	var dead_count := 0
	var visible_count := 0
	for i in max_soldiers:
		if _soldier_dead[i] > 0.5:
			dead_count += 1
		if _soldier_alive[i] > 0.5:
			visible_count += 1

	return {
		"alive_count": alive_count,
		"dead_count": dead_count,
		"visible_count": visible_count,
		"max_soldiers": max_soldiers,
		"current_animation": _current_animation,
		"atlas_loaded": atlas != null,
		"texture_loaded": atlas != null and atlas.texture != null,
		"atlas_size": atlas.texture.get_size() if atlas and atlas.texture else Vector2.ZERO,
		"columns": atlas.columns if atlas else 0,
		"rows": atlas.rows if atlas else 0,
		"death_anim_start": atlas.get_animation_start("death") if atlas else -1,
		"death_anim_frames": atlas.get_animation_frame_count("death") if atlas else 0
	}


func debug_print_soldier_states():
	"""Print detailed soldier visibility states for debugging."""
	print("=== SpriteFormation Debug ===")
	print("Alive: ", alive_count, " / ", max_soldiers)
	var corpse_indices: Array[int] = []
	for i in max_soldiers:
		if _soldier_dead[i] > 0.5:
			corpse_indices.append(i)
	print("Corpse indices: ", corpse_indices)
	print("Death anim start: ", atlas.get_animation_start("death") if atlas else "NO ATLAS")
	print("Death anim frames: ", atlas.get_animation_frame_count("death") if atlas else 0)
	print("===============================")
