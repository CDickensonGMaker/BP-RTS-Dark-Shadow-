class_name SpriteFormation
extends Node3D

# Preload to avoid parse-order issues with class_name
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")

## MultiMesh-based formation manager for efficient sprite soldier rendering.
## Replaces SoldierFormation when use_sprite_soldiers is enabled.
## Uses 1 draw call for all soldiers instead of 1 per soldier.

signal formation_ready
signal soldiers_updated(count: int)

## Atlas resource containing sprite sheet and animation data
@export var atlas: SpriteUnitAtlas

## Maximum number of soldiers in formation
@export var max_soldiers: int = 100

## Grid layout (defaults, overridden by formation type)
@export var rows: int = 10
@export var spacing: float = 1.2
@export var row_offset: float = 0.3  # Stagger rows for natural look

## Parent regiment reference for formation changes
var _parent_regiment: Node = null

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

# Phase 6.4: Terrain access via TerrainHelper (removed _terrain variable)
var _terrain_update_timer: float = 0.0
const TERRAIN_UPDATE_INTERVAL: float = 0.1  # Update terrain positions 10x/sec

# Corpse system - dead soldiers stay at world position where they died
var _corpse_world_positions: PackedVector3Array  # World position where soldier died
var _is_corpse: PackedFloat32Array  # 1.0 if this slot is now a static corpse

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

# Formation transition state
var _target_positions: PackedVector3Array  # Target positions for smooth transition
var _start_positions: PackedVector3Array  # Starting positions for lerp
var _is_transitioning: bool = false
var _transition_time: float = 0.0
var _transition_duration: float = 1.5  # Current transition duration (can be set per-transition)
const DEFAULT_TRANSITION_DURATION: float = 1.5  # Default duration if none specified
const MIN_TRANSITION_SPEED: float = 2.0  # Minimum movement speed so soldiers don't crawl

# Staggered movement state (Phase 8.3 - aliveness)
var _soldier_start_delays: PackedFloat32Array  # Per-soldier delay before starting movement
var _soldier_speed_jitter: PackedFloat32Array  # Per-soldier speed multiplier (±15%)


func _ready():
	_setup_shader()
	_setup_multimesh()
	spawn_formation(max_soldiers)
	call_deferred("_find_parent_regiment")

	# Connect to formation change signal
	if BattleSignals:
		BattleSignals.formation_type_changed.connect(_on_formation_type_changed)


func _find_parent_regiment():
	# Find parent Regiment node - use type check like SoldierFormation
	var parent = get_parent()
	while parent:
		if parent is Regiment:
			_parent_regiment = parent
			# Apply current formation layout now that we know our parent
			if _parent_regiment.current_formation != FormationType.Type.LINE:
				_apply_formation_layout(_parent_regiment.current_formation)
			break
		parent = parent.get_parent()


func set_formation_type(formation_type: int, animate: bool = true, duration: float = -1.0):
	"""Directly set formation type (fallback for when signals don't work)
	Duration: -1 uses default FORMATION_TRANSITION_DURATION, otherwise uses the specified value."""
	if animate:
		_apply_formation_layout(formation_type, duration)
	else:
		# Immediate snap (no animation)
		var layout := _get_formation_layout(formation_type, alive_count)
		var new_rows: int = layout.rows
		var new_spacing: float = layout.spacing
		var cols := ceili(float(alive_count) / float(new_rows))

		var alive_idx := 0
		for i in max_soldiers:
			if _soldier_alive[i] < 0.5 or _soldier_dead[i] > 0.5:
				continue
			var row := alive_idx / cols
			var col := alive_idx % cols
			var x := (float(col) - cols / 2.0) * new_spacing
			var z := (float(row) - new_rows / 2.0) * new_spacing
			_soldier_positions[i].x = x
			_soldier_positions[i].z = z
			_target_positions[i] = _soldier_positions[i]
			var xform := Transform3D()
			xform.origin = _soldier_positions[i]
			_multimesh.set_instance_transform(i, xform)
			alive_idx += 1


func set_formation_width(file_count: int, animate: bool = true) -> void:
	"""Set the formation width (number of soldier files across the front rank).
	Triggers a smooth transition to the new layout. Used by formation drag."""
	if alive_count < 2:
		return

	# Clamp to physical limits — min 2 wide, min 2 deep
	var max_width: int = maxi(2, alive_count / 2)
	file_count = clampi(file_count, 2, max_width)

	# Update rows based on desired width
	rows = ceili(float(alive_count) / float(file_count))

	# Get current formation type from parent if available
	var formation_type: int = FormationType.Type.LINE
	if _parent_regiment:
		formation_type = _parent_regiment.current_formation

	if animate:
		_apply_formation_layout(formation_type, _transition_duration)
	else:
		set_formation_type(formation_type, false, -1.0)


func _on_formation_type_changed(regiment: Node, _old_formation: int, new_formation: int):
	# Only respond to our parent regiment's formation changes
	if regiment != _parent_regiment:
		return

	# Rearrange soldiers based on new formation
	_apply_formation_layout(new_formation)


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

	# Handle formation transition animation
	if _is_transitioning:
		_update_formation_transition(delta)


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
	_target_positions.resize(max_soldiers)
	_soldier_alive.resize(max_soldiers)
	_soldier_dead.resize(max_soldiers)
	_soldier_directions.resize(max_soldiers)
	_soldier_time_offsets.resize(max_soldiers)
	_corpse_world_positions.resize(max_soldiers)
	_is_corpse.resize(max_soldiers)

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
		_corpse_world_positions[i] = Vector3.ZERO
		_is_corpse[i] = 0.0
		_target_positions[i] = _soldier_positions[i]  # Target = current initially

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


func _apply_formation_layout(formation_type: int, duration: float = -1.0):
	"""Rearrange soldiers based on formation type with staggered transition.
	Duration: -1 uses default, otherwise uses specified value (synced with gameplay reform_timer)."""
	# Set transition duration
	_transition_duration = duration if duration > 0.0 else DEFAULT_TRANSITION_DURATION

	# Initialize stagger arrays
	_start_positions.resize(max_soldiers)
	_soldier_start_delays.resize(max_soldiers)
	_soldier_speed_jitter.resize(max_soldiers)

	var max_delay: float = _transition_duration * 0.35  # Outer soldiers start up to 35% later

	# Get formation-specific layout parameters
	var layout := _get_formation_layout(formation_type, alive_count)
	var new_rows: int = layout.rows
	var new_spacing: float = layout.spacing
	var cols := ceili(float(alive_count) / float(new_rows))

	# Calculate TARGET positions and stagger data for all alive soldiers
	var alive_idx := 0
	for i in max_soldiers:
		# Store start position for lerping
		_start_positions[i] = _soldier_positions[i]

		if _soldier_alive[i] < 0.5 or _soldier_dead[i] > 0.5:
			_target_positions[i] = _soldier_positions[i]  # Keep current for dead
			_soldier_start_delays[i] = 0.0
			_soldier_speed_jitter[i] = 1.0
			continue

		var row := alive_idx / cols
		var col := alive_idx % cols

		# Calculate new position
		var x := (float(col) - cols / 2.0) * new_spacing
		var z := (float(row) - new_rows / 2.0) * new_spacing

		# Apply formation-specific offsets
		match formation_type:
			FormationType.Type.WEDGE:
				# Triangle/wedge shape - narrow at front, wide at back
				var wedge_offset := float(row) * 0.3
				x = x * (1.0 + wedge_offset * 0.2)
			FormationType.Type.COLUMN:
				# Deep column - tighter lateral spacing
				x *= 0.7
			FormationType.Type.LOOSE:
				# Extra spacing between soldiers
				x *= 1.3
				z *= 1.3
			FormationType.Type.SQUARE:
				# Equal spacing, slight stagger
				if row % 2 == 1:
					x += row_offset * 0.5
			FormationType.Type.SHIELD_WALL:
				# Very tight line
				x *= 0.6
				z *= 0.8
			FormationType.Type.SCHILTRON:
				# Circular formation (approximated)
				var angle := float(alive_idx) / float(alive_count) * TAU
				var radius := new_spacing * sqrt(float(alive_count)) * 0.3
				x = cos(angle) * radius
				z = sin(angle) * radius

		# Set TARGET position (keep current Y)
		var current_y := _soldier_positions[i].y
		_target_positions[i] = Vector3(x, current_y, z)

		# Calculate per-soldier stagger delay based on distance from center
		var distance_from_center: float = _soldier_positions[i].length()
		var distance_factor: float = clampf(distance_from_center / 8.0, 0.0, 1.0)
		_soldier_start_delays[i] = distance_factor * max_delay + randf_range(0.0, 0.15)

		# Per-soldier speed jitter: ±15%
		_soldier_speed_jitter[i] = randf_range(0.85, 1.15)

		alive_idx += 1

	# Start the transition
	_is_transitioning = true
	_transition_time = 0.0


func _update_formation_transition(delta: float):
	"""Smoothly lerp soldiers with staggered timing and natural movement."""
	_transition_time += delta
	var all_done: bool = true

	for i in max_soldiers:
		if _soldier_alive[i] < 0.5 or _soldier_dead[i] > 0.5:
			continue

		# Per-soldier timing with stagger delay
		var personal_elapsed: float = _transition_time - _soldier_start_delays[i]
		if personal_elapsed <= 0.0:
			# This soldier hasn't started yet
			all_done = false
			continue

		# Adjust duration by speed jitter
		var personal_duration: float = _transition_duration * (1.0 / _soldier_speed_jitter[i])
		var t: float = clampf(personal_elapsed / personal_duration, 0.0, 1.0)
		if t < 1.0:
			all_done = false

		# Smooth ease-in-out for natural acceleration/deceleration
		var eased_t: float = _ease_in_out_cubic(t)

		# Calculate base interpolated position
		var start_pos := _start_positions[i]
		var target := _target_positions[i]
		var base_pos: Vector3 = start_pos.lerp(target, eased_t)

		# Add perpendicular sway for natural weaving motion
		var travel: Vector3 = target - start_pos
		travel.y = 0.0
		var sway: Vector3 = Vector3.ZERO
		if travel.length_squared() > 0.5:
			var perp: Vector3 = Vector3(-travel.z, 0, travel.x).normalized()
			sway = perp * sin(t * PI) * 0.15  # Subtle sine-wave weave

		# Keep original Y (terrain handling)
		base_pos.y = _soldier_positions[i].y
		_soldier_positions[i] = base_pos + sway

		# Update MultiMesh transform
		var xform := Transform3D()
		xform.origin = _soldier_positions[i]
		_multimesh.set_instance_transform(i, xform)

	# Grace period: don't end until all soldiers have had time to arrive
	if all_done and _transition_time >= _transition_duration + 0.5:
		_is_transitioning = false
		# Snap to final positions
		for i in max_soldiers:
			if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
				_soldier_positions[i].x = _target_positions[i].x
				_soldier_positions[i].z = _target_positions[i].z
				var xform := Transform3D()
				xform.origin = _soldier_positions[i]
				_multimesh.set_instance_transform(i, xform)
		# Return to idle animation
		play_animation_all("idle")


func _ease_in_out_cubic(t: float) -> float:
	"""Smooth ease-in-out for natural acceleration and deceleration."""
	if t < 0.5:
		return 4.0 * t * t * t
	var f: float = -2.0 * t + 2.0
	return 1.0 - f * f * f / 2.0


func _get_formation_layout(formation_type: int, soldier_count: int) -> Dictionary:
	"""Get rows and spacing for a formation type."""
	match formation_type:
		FormationType.Type.LINE:
			return {"rows": maxi(2, soldier_count / 8), "spacing": spacing}
		FormationType.Type.COLUMN:
			return {"rows": maxi(8, soldier_count / 3), "spacing": spacing * 0.9}
		FormationType.Type.WEDGE:
			return {"rows": maxi(4, soldier_count / 5), "spacing": spacing}
		FormationType.Type.SQUARE:
			var side := ceili(sqrt(float(soldier_count)))
			return {"rows": side, "spacing": spacing}
		FormationType.Type.LOOSE:
			return {"rows": maxi(3, soldier_count / 6), "spacing": spacing * 1.5}
		FormationType.Type.SHIELD_WALL:
			return {"rows": 2, "spacing": spacing * 0.7}
		FormationType.Type.SCHILTRON:
			return {"rows": soldier_count, "spacing": spacing}  # Circular, rows not used directly
		_:
			return {"rows": rows, "spacing": spacing}


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
	"""Kill soldiers from back of formation - they stay visible as corpses at death position."""
	# Safety check - arrays must be initialized
	if _soldier_alive.is_empty() or _soldier_dead.is_empty():
		return

	var killed := 0
	for i in range(max_soldiers - 1, -1, -1):
		if killed >= amount:
			break
		# Only kill soldiers that are alive and not already dead
		if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
			_soldier_dead[i] = 1.0  # Mark as dead corpse (stays visible)

			# Store world position where soldier died - corpse stays here
			var world_pos: Vector3 = global_position + _soldier_positions[i]
			# Drop corpse to ground level (Phase 6.4: use helper)
			var terrain := TerrainHelperScript.get_terrain(get_tree())
			if terrain:
				world_pos.y = terrain.get_height_at(world_pos) + 0.1  # Slight offset above ground
			else:
				world_pos.y = global_position.y - height_offset + 0.1
			_corpse_world_positions[i] = world_pos
			_is_corpse[i] = 1.0

			# Update position to corpse world position (converted to local space)
			_soldier_positions[i] = world_pos - global_position
			_soldier_positions[i].y = 0.1  # Ground level in local space

			# Don't set _soldier_alive to 0 - we want them to stay rendered
			_update_instance(i)
			killed += 1
			alive_count -= 1

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
	var viewport := get_viewport()
	if not viewport:
		return
	var camera := viewport.get_camera_3d()
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
	var viewport := get_viewport()
	if not viewport:
		return
	var camera := viewport.get_camera_3d()
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
	"""Update soldier Y positions based on terrain height. (Phase 6.4: use helper)"""
	var terrain := TerrainHelperScript.get_terrain(get_tree())
	if not terrain:
		return

	for i in max_soldiers:
		if _soldier_alive[i] > 0.5:
			# Corpses stay at their death world position - convert back to local space
			if _is_corpse[i] > 0.5:
				var local_corpse_pos: Vector3 = _corpse_world_positions[i] - global_position
				local_corpse_pos.y = 0.1  # Keep at ground level
				if _soldier_positions[i].distance_to(local_corpse_pos) > 0.01:
					_soldier_positions[i] = local_corpse_pos
					var xform := Transform3D()
					xform.origin = _soldier_positions[i]
					_multimesh.set_instance_transform(i, xform)
			else:
				# Living soldiers follow terrain
				var world_pos: Vector3 = global_position + _soldier_positions[i]
				var terrain_height: float = terrain.get_height_at(world_pos)
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
