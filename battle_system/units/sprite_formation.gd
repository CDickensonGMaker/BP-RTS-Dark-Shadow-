class_name SpriteFormation
extends Node3D

# Preload to avoid parse-order issues with class_name
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")
const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")
const FormationTypeScript = preload("res://battle_system/data/formation_type.gd")

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

## Sprite front direction offset (0-7). Maps which sprite row is the unit's "front".
## 0 = North sprite is front, 4 = South sprite is front, etc.
## Most units have their front-facing sprite in the South row, so they use sprite_front_direction=4.
var sprite_front_direction: int = 0

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

# Phase 11: LOD optimization - reduce update frequency for distant formations
var _lod_level: int = 0  # 0 = full quality, 1 = medium, 2 = low
const LOD_DISTANCE_MEDIUM: float = 80.0  # Beyond this, use medium LOD
const LOD_DISTANCE_LOW: float = 150.0     # Beyond this, use low LOD
var _lod_check_timer: float = 0.0
const LOD_CHECK_INTERVAL: float = 0.5  # Check LOD level 2x/sec

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

# Knockback scatter recovery state (rock-paper-scissors Part 2)
var _is_recovering_from_scatter: bool = false
var _scatter_recovery_timer: float = 0.0

# === COHESION & TOLERANCE SYSTEM (Total War-style formation) ===
# Formation is a TARGET, not a constraint - soldiers have assigned slots but can deviate within tolerance

enum SlotToleranceMode { LOCKED, TOLERANT, SUSPENDED }

# Tolerance radii (meters)
const TOLERANCE_LOCKED: float = 0.3       # Strict adherence during march/idle
const TOLERANCE_TOLERANT: float = 1.5     # Combat flexibility
const TOLERANCE_RALLY_WIDE: float = 3.0   # Wide tolerance during early rally

# Cohesion thresholds
const COHESION_FORMED: float = 0.85       # 85%+ = "Formed" - full formation bonuses
const COHESION_LOOSE: float = 0.50        # 50-85% = "Loose" - linear interpolation
const COHESION_UPDATE_INTERVAL: float = 0.25  # 4Hz tick (matches morale system)

# Cohesion state
var _tolerance_mode: SlotToleranceMode = SlotToleranceMode.LOCKED
var _current_tolerance: float = TOLERANCE_LOCKED
var _cohesion: float = 1.0                # 0.0-1.0, ratio of soldiers within tolerance
var _cohesion_update_timer: float = 0.0
var _soldier_slot_deviation: PackedFloat32Array  # Distance from assigned slot per soldier
var _last_emitted_cohesion: float = 1.0   # For signal throttling (>5% change)

# Rally reformation state
var _is_rally_reforming: bool = false
var _rally_phase: int = 0                 # 0=stopped, 1=centroid, 2=flow-back, 3=tightening
var _rally_centroid: Vector3 = Vector3.ZERO
const RALLY_PHASE_STOP: int = 0
const RALLY_PHASE_CENTROID: int = 1
const RALLY_PHASE_FLOWBACK: int = 2
const RALLY_PHASE_TIGHTENING: int = 3
const RALLY_FLOWBACK_DURATION: float = 2.5  # Soldiers drift to slots over 2.5s

signal cohesion_changed(cohesion: float)
signal tolerance_mode_changed(mode: SlotToleranceMode)

# === ARTILLERY CREW MODE ===
# When enabled, crew sprites are positioned in semicircles behind artillery pieces
var artillery_crew_mode: bool = false
var artillery_piece_positions: Array[Vector3] = []
var _crew_per_piece: int = 6  # Default crew count per artillery piece


func _ready():
	_setup_shader()
	_setup_multimesh()
	spawn_formation(max_soldiers)
	call_deferred("_find_parent_regiment")

	# Connect to formation change signal
	if BattleSignals:
		BattleSignals.formation_type_changed.connect(_on_formation_type_changed)


func _find_parent_regiment():
	# Find parent Regiment node - use duck typing to avoid cyclic dependency
	var parent = get_parent()
	while parent:
		if parent.has_method("get_facing_direction") and parent.get("data") != null:
			_parent_regiment = parent
			# Apply current formation layout now that we know our parent
			if _parent_regiment.current_formation != FormationTypeScript.Type.LINE:
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
	var formation_type: int = FormationTypeScript.Type.LINE
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
	# Phase 11: LOD check - reduce updates for distant formations
	_lod_check_timer += delta
	if _lod_check_timer >= LOD_CHECK_INTERVAL:
		_lod_check_timer = 0.0
		_update_lod_level()

	# Apply LOD-scaled update intervals
	var terrain_interval: float = TERRAIN_UPDATE_INTERVAL * (1.0 + float(_lod_level))  # 0.1s, 0.2s, 0.3s
	var direction_interval: float = DIRECTION_UPDATE_INTERVAL * (1.0 + float(_lod_level) * 2.0)  # 0.05s, 0.15s, 0.25s

	_terrain_update_timer += delta
	if _terrain_update_timer >= terrain_interval:
		_terrain_update_timer = 0.0
		_update_soldier_terrain_positions()

	# Update sprite directions when camera rotates
	_direction_update_timer += delta
	if _direction_update_timer >= direction_interval:
		_direction_update_timer = 0.0
		_update_camera_relative_directions()

	# Handle formation transition animation
	if _is_transitioning:
		_update_formation_transition(delta)

	# Handle scatter recovery - soldiers slowly reform after knockback
	if _is_recovering_from_scatter:
		_scatter_recovery_timer -= delta
		if _scatter_recovery_timer <= 0.0:
			_is_recovering_from_scatter = false
			# Restore TOLERANT mode (combat flexibility) after scatter recovery
			set_tolerance_mode(SlotToleranceMode.TOLERANT)
			# Trigger formation reform to bring soldiers back to positions
			if _parent_regiment:
				_apply_formation_layout(_parent_regiment.current_formation, 2.0)

	# Update cohesion at 4Hz (matches morale system tick rate)
	_update_cohesion(delta)

	# Handle active rally reformation phases
	if _is_rally_reforming:
		_update_rally_reformation(delta)


func _update_lod_level() -> void:
	"""Phase 11: Update LOD level based on camera distance."""
	var camera := get_viewport().get_camera_3d()
	if not camera:
		_lod_level = 0
		return

	var dist: float = camera.global_position.distance_to(global_position)
	if dist > LOD_DISTANCE_LOW:
		_lod_level = 2  # Low quality - fewest updates
	elif dist > LOD_DISTANCE_MEDIUM:
		_lod_level = 1  # Medium quality
	else:
		_lod_level = 0  # Full quality


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

		# Set direction-to-row mapping from atlas
		var dir_row_map: PackedInt32Array = PackedInt32Array()
		dir_row_map.resize(8)
		for i in range(8):
			if atlas.direction_rows.has(i):
				dir_row_map[i] = mini(int(atlas.direction_rows[i]), atlas.rows - 1)
			else:
				dir_row_map[i] = mini(i, atlas.rows - 1)
		_material.set_shader_parameter("direction_row_map", dir_row_map)
		print("SpriteFormation: Direction row map: ", dir_row_map)

		# Initialize direction-to-frame mapping (will be updated per animation)
		var dir_frame_map: PackedInt32Array = PackedInt32Array()
		dir_frame_map.resize(8)
		for i in range(8):
			dir_frame_map[i] = 0  # Default to frame 0, updated by _set_animation_params
		_material.set_shader_parameter("direction_frame_map", dir_frame_map)

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
	_soldier_slot_deviation.resize(max_soldiers)  # Cohesion tracking

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
		_soldier_slot_deviation[i] = 0.0  # Distance from assigned slot (cohesion tracking)

		# Set MultiMesh instance transform and custom data
		_update_instance(i)

	# Initialize cohesion to 1.0 (fully formed)
	_cohesion = 1.0
	_last_emitted_cohesion = 1.0
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
			FormationTypeScript.Type.WEDGE:
				# Triangle/wedge shape - narrow at front, wide at back
				var wedge_offset := float(row) * 0.3
				x = x * (1.0 + wedge_offset * 0.2)
			FormationTypeScript.Type.COLUMN:
				# Deep column - tighter lateral spacing
				x *= 0.7
			FormationTypeScript.Type.LOOSE:
				# Extra spacing between soldiers
				x *= 1.3
				z *= 1.3
			FormationTypeScript.Type.SQUARE:
				# Equal spacing, slight stagger
				if row % 2 == 1:
					x += row_offset * 0.5
			FormationTypeScript.Type.SHIELD_WALL:
				# Very tight line
				x *= 0.6
				z *= 0.8
			FormationTypeScript.Type.SCHILTRON:
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


# === COHESION CALCULATION ===

func _calculate_cohesion() -> float:
	"""Calculate formation cohesion as ratio of soldiers within tolerance of their slots.
	Uses length_squared() to avoid sqrt per soldier for performance."""
	if alive_count <= 0:
		return 1.0

	var within_tolerance: int = 0
	var tolerance_sq: float = _current_tolerance * _current_tolerance

	for i in max_soldiers:
		if _soldier_alive[i] < 0.5 or _soldier_dead[i] > 0.5:
			continue

		# Calculate deviation from assigned slot (target position)
		var deviation: Vector3 = _soldier_positions[i] - _target_positions[i]
		deviation.y = 0.0  # Only horizontal deviation matters
		var deviation_sq: float = deviation.length_squared()

		# Track per-soldier deviation for debugging/visualization
		_soldier_slot_deviation[i] = sqrt(deviation_sq)

		if deviation_sq <= tolerance_sq:
			within_tolerance += 1

	return float(within_tolerance) / float(alive_count)


func _update_cohesion(delta: float) -> void:
	"""Tick-based cohesion update at 4Hz. Emits signal only if change > 5%."""
	_cohesion_update_timer += delta
	if _cohesion_update_timer < COHESION_UPDATE_INTERVAL:
		return
	_cohesion_update_timer = 0.0

	var new_cohesion: float = _calculate_cohesion()
	_cohesion = new_cohesion

	# Only emit signal if cohesion changed by more than 5%
	if absf(new_cohesion - _last_emitted_cohesion) > 0.05:
		_last_emitted_cohesion = new_cohesion
		cohesion_changed.emit(new_cohesion)


func get_cohesion() -> float:
	"""Get current formation cohesion (0.0-1.0).
	0.85+ = Formed (full bonuses)
	0.50-0.85 = Loose (linear interpolation)
	<0.50 = Broken (no bonuses)"""
	return _cohesion


func get_cohesion_state() -> String:
	"""Get human-readable cohesion state for debug/UI."""
	if _cohesion >= COHESION_FORMED:
		return "Formed"
	elif _cohesion >= COHESION_LOOSE:
		return "Loose"
	else:
		return "Broken"


# === TOLERANCE MODE SYSTEM ===

func set_tolerance_mode(mode: SlotToleranceMode) -> void:
	"""Set the formation slot tolerance mode.
	LOCKED: Strict adherence (±0.3m) - marching, idle, reformed
	TOLERANT: Combat flexibility (±1.5m) - engaging
	SUSPENDED: Unlimited - routing, scattered"""
	if mode == _tolerance_mode:
		return

	_tolerance_mode = mode
	match mode:
		SlotToleranceMode.LOCKED:
			_current_tolerance = TOLERANCE_LOCKED
		SlotToleranceMode.TOLERANT:
			_current_tolerance = TOLERANCE_TOLERANT
		SlotToleranceMode.SUSPENDED:
			_current_tolerance = 999.0  # Effectively unlimited
	tolerance_mode_changed.emit(mode)


func set_tolerance_radius(radius: float) -> void:
	"""Set a custom tolerance radius (for rally phases)."""
	_current_tolerance = radius


func get_tolerance_mode() -> SlotToleranceMode:
	"""Get current tolerance mode."""
	return _tolerance_mode


func get_tolerance_radius() -> float:
	"""Get current tolerance radius in meters."""
	return _current_tolerance


# === RALLY REFORMATION SYSTEM ===

func begin_rally_reformation() -> void:
	"""Start multi-phase rally reformation process.
	Called when regiment transitions to RALLYING state."""
	_is_rally_reforming = true
	_rally_phase = RALLY_PHASE_STOP
	# Wide tolerance during early rally
	set_tolerance_radius(TOLERANCE_RALLY_WIDE)
	set_tolerance_mode(SlotToleranceMode.TOLERANT)


func advance_rally_phase(current_morale: float) -> void:
	"""Advance rally phase based on morale thresholds.
	Called from regiment.gd during RALLYING state updates."""
	if not _is_rally_reforming:
		return

	match _rally_phase:
		RALLY_PHASE_STOP:
			# Phase 0→1: Morale ≥35 - compute centroid
			if current_morale >= 35.0:
				_rally_phase = RALLY_PHASE_CENTROID
				_rally_centroid = compute_rally_centroid()
				_recompute_slots_around_centroid(_rally_centroid)

		RALLY_PHASE_CENTROID:
			# Phase 1→2: Morale ≥38 - start flow-back animation
			if current_morale >= 38.0:
				_rally_phase = RALLY_PHASE_FLOWBACK
				_start_rally_flowback()

		RALLY_PHASE_FLOWBACK:
			# Phase 2→3: After flowback animation + morale ≥40 - tightening
			if current_morale >= 40.0 and not _is_transitioning:
				_rally_phase = RALLY_PHASE_TIGHTENING
				set_tolerance_radius(TOLERANCE_TOLERANT)  # 1.5m
				# Schedule final tightening to LOCKED
				_start_final_tightening()

		RALLY_PHASE_TIGHTENING:
			# Phase 3→complete: Full cohesion
			if _cohesion >= COHESION_FORMED and not _is_transitioning:
				complete_rally_reformation()


func _update_rally_reformation(_delta: float) -> void:
	"""Update rally reformation state each frame."""
	if not _is_rally_reforming:
		return
	# Phase advancement is driven by morale changes from regiment.gd
	# This method handles any per-frame rally-specific updates
	pass


func compute_rally_centroid() -> Vector3:
	"""Compute center of mass of surviving soldiers (for rally reformation)."""
	if alive_count == 0:
		return global_position

	var sum := Vector3.ZERO
	var count := 0

	for i in max_soldiers:
		if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
			sum += _soldier_positions[i]
			count += 1

	if count == 0:
		return global_position

	return sum / float(count)


func _recompute_slots_around_centroid(centroid: Vector3) -> void:
	"""Recompute target slot positions centered on the rally centroid.
	Slots are regenerated around the new center point."""
	var formation_type: int = FormationTypeScript.Type.LINE
	if _parent_regiment:
		formation_type = _parent_regiment.current_formation

	var layout := _get_formation_layout(formation_type, alive_count)
	var target_rows: int = layout.rows
	var target_spacing: float = layout.spacing
	var cols := ceili(float(alive_count) / float(target_rows))

	var alive_idx := 0
	for i in max_soldiers:
		if _soldier_alive[i] < 0.5 or _soldier_dead[i] > 0.5:
			continue

		var row := alive_idx / cols
		var col := alive_idx % cols

		# Calculate slot position relative to centroid
		var x := (float(col) - cols / 2.0) * target_spacing + centroid.x
		var z := (float(row) - target_rows / 2.0) * target_spacing + centroid.z

		_target_positions[i] = Vector3(x, _soldier_positions[i].y, z)
		alive_idx += 1


func _start_rally_flowback() -> void:
	"""Start the flow-back animation where soldiers drift to their new slots.
	Duration: 2.5 seconds with natural movement."""
	# Use the existing formation transition system
	_start_positions.resize(max_soldiers)
	_soldier_start_delays.resize(max_soldiers)
	_soldier_speed_jitter.resize(max_soldiers)

	var max_delay: float = RALLY_FLOWBACK_DURATION * 0.2  # Slight stagger

	for i in max_soldiers:
		_start_positions[i] = _soldier_positions[i]
		if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
			_soldier_start_delays[i] = randf_range(0.0, max_delay)
			_soldier_speed_jitter[i] = randf_range(0.85, 1.15)
		else:
			_soldier_start_delays[i] = 0.0
			_soldier_speed_jitter[i] = 1.0

	_is_transitioning = true
	_transition_time = 0.0
	_transition_duration = RALLY_FLOWBACK_DURATION


func _start_final_tightening() -> void:
	"""Start final tightening phase - soldiers snap to strict positions."""
	# Regenerate slots with standard formation (no centroid offset needed anymore)
	if _parent_regiment:
		_apply_formation_layout(_parent_regiment.current_formation, 1.0)


func complete_rally_reformation() -> void:
	"""Complete the rally reformation - restore LOCKED mode and full bonuses."""
	_is_rally_reforming = false
	_rally_phase = 0
	set_tolerance_mode(SlotToleranceMode.LOCKED)


func is_rally_reforming() -> bool:
	"""Check if currently in rally reformation process."""
	return _is_rally_reforming


func get_rally_phase() -> int:
	"""Get current rally phase (0-3)."""
	return _rally_phase


func _get_formation_layout(formation_type: int, soldier_count: int) -> Dictionary:
	"""Get rows and spacing for a formation type."""
	match formation_type:
		FormationTypeScript.Type.LINE:
			return {"rows": maxi(2, soldier_count / 8), "spacing": spacing}
		FormationTypeScript.Type.COLUMN:
			return {"rows": maxi(8, soldier_count / 3), "spacing": spacing * 0.9}
		FormationTypeScript.Type.WEDGE:
			return {"rows": maxi(4, soldier_count / 5), "spacing": spacing}
		FormationTypeScript.Type.SQUARE:
			var side := ceili(sqrt(float(soldier_count)))
			return {"rows": side, "spacing": spacing}
		FormationTypeScript.Type.LOOSE:
			return {"rows": maxi(3, soldier_count / 6), "spacing": spacing * 1.5}
		FormationTypeScript.Type.SHIELD_WALL:
			return {"rows": 2, "spacing": spacing * 0.7}
		FormationTypeScript.Type.SCHILTRON:
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
	"""Kill soldiers from back of formation - transfer corpses to CorpseField immediately.
	Front-rank casualties trigger instant slot reassignment for combat responsiveness."""
	# Safety check - arrays must be initialized
	if _soldier_alive.is_empty() or _soldier_dead.is_empty():
		return

	var killed := 0
	var front_rank_deaths: Array[int] = []  # Track front-rank deaths for instant reassignment

	for i in range(max_soldiers - 1, -1, -1):
		if killed >= amount:
			break
		# Only kill soldiers that are alive and not already dead
		if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
			# Check if this is a front-rank soldier (for instant reassignment)
			var was_front_rank: bool = _is_front_rank_soldier(i)

			# Calculate world position where soldier died
			var world_pos: Vector3 = global_position + _soldier_positions[i]
			# Drop corpse to ground level (Phase 6.4: use helper)
			var terrain := TerrainHelperScript.get_terrain(get_tree())
			if terrain:
				world_pos.y = terrain.get_height_at(world_pos) + 0.1  # Slight offset above ground
			else:
				world_pos.y = global_position.y - height_offset + 0.1

			# Transfer corpse to CorpseField or spawn bones for undead
			# Corpses are owned by CorpseField in world space, not local to regiment
			var bone_manager := get_node_or_null("/root/BoneDropManager")
			if bone_manager and bone_manager.is_undead_unit(faction_color):
				# Undead units crumble into bone piles instead of leaving corpses
				bone_manager.spawn_bone_pile(world_pos, int(_soldier_directions[i]))
			else:
				# Normal units leave corpses
				var corpse_field := get_node_or_null("/root/CorpseField")
				if corpse_field and atlas:
					corpse_field.add_corpse(world_pos, atlas, int(_soldier_directions[i]))

			# Mark as dead and HIDE locally (corpse is now in CorpseField)
			_soldier_dead[i] = 1.0  # Track that this slot was killed
			_soldier_alive[i] = 0.0  # Hide from local MultiMesh (no longer rendered here)
			_update_instance(i)
			killed += 1
			alive_count -= 1

			# Queue front-rank deaths for instant reassignment
			if was_front_rank:
				front_rank_deaths.append(i)

	# Instant front-rank slot reassignment (prevents gaps in fighting line)
	for dead_idx in front_rank_deaths:
		_reassign_front_rank_slot(dead_idx)

	soldiers_updated.emit(alive_count)

	# Consolidate formation - fill gaps in back ranks (animated)
	if killed > 0:
		_consolidate_formation()


func _consolidate_formation() -> void:
	"""Move back-rank soldiers forward to fill gaps in front ranks.
	Keeps front ranks fighting and prevents gaps from appearing in formation."""
	if alive_count < 2:
		return

	# Get current formation layout
	var formation_type: int = FormationTypeScript.Type.LINE
	if _parent_regiment:
		formation_type = _parent_regiment.current_formation

	var layout := _get_formation_layout(formation_type, alive_count)
	var target_rows: int = layout.rows
	var target_spacing: float = layout.spacing
	var cols := ceili(float(alive_count) / float(target_rows))

	# Collect all living soldier indices
	var living_indices: Array[int] = []
	for i in max_soldiers:
		if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
			living_indices.append(i)

	if living_indices.is_empty():
		return

	# Reassign positions based on optimal grid (front ranks first)
	_start_positions.resize(max_soldiers)
	_target_positions.resize(max_soldiers)
	_soldier_start_delays.resize(max_soldiers)
	_soldier_speed_jitter.resize(max_soldiers)

	for slot_idx in range(living_indices.size()):
		var soldier_idx: int = living_indices[slot_idx]
		var row := slot_idx / cols
		var col := slot_idx % cols

		# Calculate new target position (compact grid with front ranks filled first)
		var x := (float(col) - cols / 2.0) * target_spacing
		var z := (float(row) - target_rows / 2.0) * target_spacing

		# Apply formation-specific offsets (same as _apply_formation_layout)
		match formation_type:
			FormationTypeScript.Type.WEDGE:
				var wedge_offset := float(row) * 0.3
				x = x * (1.0 + wedge_offset * 0.2)
			FormationTypeScript.Type.COLUMN:
				x *= 0.7
			FormationTypeScript.Type.LOOSE:
				x *= 1.3
				z *= 1.3
			FormationTypeScript.Type.SQUARE:
				if row % 2 == 1:
					x += row_offset * 0.5
			FormationTypeScript.Type.SHIELD_WALL:
				x *= 0.6
				z *= 0.8
			FormationTypeScript.Type.SCHILTRON:
				var angle := float(slot_idx) / float(alive_count) * TAU
				var radius := target_spacing * sqrt(float(alive_count)) * 0.3
				x = cos(angle) * radius
				z = sin(angle) * radius

		# Store for transition animation
		_start_positions[soldier_idx] = _soldier_positions[soldier_idx]
		_target_positions[soldier_idx] = Vector3(x, _soldier_positions[soldier_idx].y, z)
		_soldier_start_delays[soldier_idx] = randf_range(0.0, 0.3)  # Slight stagger
		_soldier_speed_jitter[soldier_idx] = randf_range(0.9, 1.1)

	# Start smooth consolidation transition (shorter than full formation change)
	_is_transitioning = true
	_transition_time = 0.0
	_transition_duration = 0.8  # Quick consolidation


# === FRONT-RANK SLOT REASSIGNMENT (Combat) ===

func _is_front_rank_soldier(idx: int) -> bool:
	"""Check if soldier at index is in the front rank (lowest Z value, fighting row).
	Front rank is determined by target position Z being in the first row."""
	if idx < 0 or idx >= max_soldiers:
		return false
	if _soldier_alive[idx] < 0.5 or _soldier_dead[idx] > 0.5:
		return false

	# Get current formation layout
	var formation_type: int = FormationTypeScript.Type.LINE
	if _parent_regiment:
		formation_type = _parent_regiment.current_formation

	var layout := _get_formation_layout(formation_type, alive_count + 1)  # +1 since we're checking before death
	var target_rows: int = layout.rows
	var target_spacing: float = layout.spacing

	# Front rank Z threshold (negative Z is forward/front)
	var front_rank_z: float = -(float(target_rows - 1) / 2.0) * target_spacing
	var soldier_z: float = _target_positions[idx].z

	# Within half spacing of front rank Z = front rank
	return soldier_z <= front_rank_z + target_spacing * 0.5


func _get_soldier_file(idx: int) -> int:
	"""Get the file (column) index of a soldier based on their X position."""
	if idx < 0 or idx >= max_soldiers:
		return -1

	var formation_type: int = FormationTypeScript.Type.LINE
	if _parent_regiment:
		formation_type = _parent_regiment.current_formation

	var layout := _get_formation_layout(formation_type, alive_count)
	var target_spacing: float = layout.spacing

	# Calculate file based on X position
	var soldier_x: float = _target_positions[idx].x
	var file: int = int(round(soldier_x / target_spacing))
	return file


func _find_soldier_behind(dead_idx: int) -> int:
	"""Find soldier directly behind (same file, next rank back) to promote forward.
	Returns -1 if no suitable soldier found."""
	var dead_file: int = _get_soldier_file(dead_idx)
	var dead_z: float = _target_positions[dead_idx].z

	var formation_type: int = FormationTypeScript.Type.LINE
	if _parent_regiment:
		formation_type = _parent_regiment.current_formation

	var layout := _get_formation_layout(formation_type, alive_count)
	var _target_spacing: float = layout.spacing  # Used for file calculation

	var best_idx: int = -1
	var best_z: float = INF

	for i in max_soldiers:
		if i == dead_idx:
			continue
		if _soldier_alive[i] < 0.5 or _soldier_dead[i] > 0.5:
			continue

		# Same file?
		var soldier_file: int = _get_soldier_file(i)
		if soldier_file != dead_file:
			continue

		# Behind the dead soldier (higher Z = further back)?
		var soldier_z: float = _target_positions[i].z
		if soldier_z > dead_z and soldier_z < best_z:
			best_z = soldier_z
			best_idx = i

	return best_idx


func _reassign_front_rank_slot(dead_idx: int) -> void:
	"""Instantly promote back-rank soldier to fill front-rank gap.
	No animation - immediate slot swap for combat responsiveness."""
	var replacement_idx: int = _find_soldier_behind(dead_idx)
	if replacement_idx < 0:
		return  # No soldier behind to promote

	# Instant slot swap - replacement takes dead soldier's target position
	var old_target: Vector3 = _target_positions[dead_idx]

	# Swap targets (replacement soldier's new slot is the front-rank slot)
	_target_positions[replacement_idx] = old_target

	# Instant visual snap (no transition during combat)
	_soldier_positions[replacement_idx] = old_target

	# Update MultiMesh transform
	var xform := Transform3D()
	xform.origin = _soldier_positions[replacement_idx]
	_multimesh.set_instance_transform(replacement_idx, xform)


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
	"""Set all soldiers to face a direction (camera-relative).
	Bug A fix: Also rotates the formation Node3D so geometry matches facing."""
	if direction.length_squared() < 0.001:
		return

	# Bug A fix: Rotate the formation node so positions match facing
	var dir_index := WorldCompassScript.direction_from_vector(direction)
	var facing_angle := WorldCompassScript.angle_from_direction(dir_index)
	rotation.y = facing_angle

	# Store world-space direction index using WorldCompass
	_world_facing_angle = float(dir_index)
	_current_direction_index = -1  # Force recalculation when facing changes
	_apply_camera_relative_direction()


func set_facing_angle(angle_rad: float):
	"""Set all soldiers to face an angle (radians, camera-relative).
	Bug A fix: Also rotates the formation Node3D so geometry matches facing."""
	# Bug A fix: Rotate the formation node so positions match facing
	rotation.y = angle_rad

	# Convert angle to direction index using WorldCompass
	_world_facing_angle = float(WorldCompassScript.direction_from_angle(angle_rad))
	_current_direction_index = -1  # Force recalculation when facing changes
	_apply_camera_relative_direction()


func _apply_camera_relative_direction():
	"""Apply camera-relative direction to all soldiers based on stored world direction."""
	var viewport := get_viewport()
	if not viewport:
		return
	var camera := viewport.get_camera_3d()
	var camera_y_angle := 0.0
	if camera:
		camera_y_angle = camera.global_rotation.y
		_last_camera_rotation = camera_y_angle

	# Convert world-space facing to screen-relative sprite direction
	# This makes sprites show different sides as camera rotates around units
	var world_dir_index := int(_world_facing_angle)

	# Apply sprite_front_direction offset
	# This remaps which sprite row represents the unit's "front"
	# Example: If sprite_front_direction=4 (South), when unit faces North (0),
	# we offset by 4 to show sprite row 4 (the actual front-facing sprite)
	var offset_dir_index := (world_dir_index + sprite_front_direction) % 8

	# Then apply camera-relative conversion
	var new_dir_index := WorldCompassScript.world_to_screen_direction(offset_dir_index, camera_y_angle)

	# Simple change detection (WorldCompass handles the conversion consistently)
	if new_dir_index == _current_direction_index:
		return  # No change needed

	_current_direction_index = new_dir_index

	for i in max_soldiers:
		if _soldier_alive[i] > 0.5:
			_soldier_directions[i] = float(_current_direction_index)
			_update_instance_custom_data(i)


func get_current_direction_index() -> int:
	"""Get the current screen-relative direction index (0-7) for debugging."""
	return _current_direction_index


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


func apply_dramatic_scatter(direction: Vector3, scatter_amount: float, is_monster: bool) -> void:
	"""Apply dramatic knockback scatter - soldiers thrown in different directions.
	Sets tolerance mode to SUSPENDED so cohesion doesn't penalize scattered soldiers."""
	var perpendicular: Vector3 = Vector3(-direction.z, 0, direction.x)

	# Set SUSPENDED tolerance during scatter - soldiers can be anywhere
	set_tolerance_mode(SlotToleranceMode.SUSPENDED)

	for i in range(_soldier_positions.size()):
		if _soldier_alive[i] > 0.5:
			var throw_angle: float = randf_range(-PI * 0.7, PI * 0.7)
			var throw_distance: float = randf_range(0.3, 1.0) * scatter_amount

			if is_monster:
				throw_distance *= randf_range(1.2, 2.0)

			var throw_dir: Vector3 = direction.rotated(Vector3.UP, throw_angle)
			var offset: Vector3 = throw_dir * throw_distance
			offset += perpendicular * randf_range(-1.0, 1.0) * throw_distance * 0.5

			_soldier_positions[i] += offset

			# Update MultiMesh transform immediately
			var xform := Transform3D()
			xform.origin = _soldier_positions[i]
			_multimesh.set_instance_transform(i, xform)

	_is_recovering_from_scatter = true
	_scatter_recovery_timer = 1.5


# --- INTERNAL METHODS ---

func _set_animation_params(anim_name: String):
	"""Set shader parameters for the current animation, including per-direction overrides."""
	if not atlas:
		push_warning("SpriteFormation: No atlas when setting animation: ", anim_name)
		return
	if not _material:
		push_warning("SpriteFormation: No material when setting animation: ", anim_name)
		return

	var default_start_frame := atlas.get_animation_start(anim_name)
	var default_frame_count := atlas.get_animation_frame_count(anim_name)

	# Build per-direction frame and row maps for this animation
	var dir_frame_map: PackedInt32Array = PackedInt32Array()
	var dir_row_map: PackedInt32Array = PackedInt32Array()
	dir_frame_map.resize(8)
	dir_row_map.resize(8)

	for i in range(8):
		# Get per-direction start frame (uses atlas helper which checks per_direction)
		dir_frame_map[i] = atlas.get_animation_start_for_direction(anim_name, i)
		# Get per-direction row (uses atlas helper which checks per_direction then direction_rows)
		dir_row_map[i] = atlas.get_row_for_direction_and_anim(anim_name, i)

	print("SpriteFormation: Setting anim '", anim_name, "' default_start=", default_start_frame, " frames=", default_frame_count)
	print("  Per-dir frame map: ", dir_frame_map)
	print("  Per-dir row map: ", dir_row_map)

	_material.set_shader_parameter("current_anim_start", default_start_frame)
	_material.set_shader_parameter("current_anim_frames", default_frame_count)
	_material.set_shader_parameter("direction_frame_map", dir_frame_map)
	_material.set_shader_parameter("direction_row_map", dir_row_map)


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
	"""Update soldier Y positions based on terrain height. (Phase 6.4: use helper)
	Note: Corpses are now handled by CorpseField in world space, not here."""
	var terrain := TerrainHelperScript.get_terrain(get_tree())
	if not terrain:
		return

	for i in max_soldiers:
		# Only update LIVING soldiers - corpses are in CorpseField now
		if _soldier_alive[i] > 0.5 and _soldier_dead[i] < 0.5:
			var world_pos: Vector3 = global_position + _soldier_positions[i]
			var terrain_height: float = terrain.get_height_at(world_pos)
			# Include height_offset so sprites properly float above terrain slopes
			var local_y := terrain_height - global_position.y + sprite_scale.y * 0.5 + height_offset

			if absf(_soldier_positions[i].y - local_y) > 0.01:
				_soldier_positions[i].y = local_y
				var xform := Transform3D()
				xform.origin = _soldier_positions[i]
				_multimesh.set_instance_transform(i, xform)


# === ARTILLERY CREW POSITIONING ===

func set_artillery_crew_mode(piece_positions: Array[Vector3]) -> void:
	"""Enable crew positioning around artillery pieces.
	Crew are positioned in semicircles behind/beside each cannon."""
	artillery_crew_mode = true
	artillery_piece_positions = piece_positions
	if piece_positions.size() > 0:
		_crew_per_piece = ceili(float(alive_count) / float(piece_positions.size()))
	_recalculate_artillery_crew_positions()


func _recalculate_artillery_crew_positions() -> void:
	"""Recalculate crew positions around artillery pieces."""
	if not artillery_crew_mode or artillery_piece_positions.is_empty():
		return

	var pieces_count := artillery_piece_positions.size()

	# Update target positions for all alive crew members
	var alive_idx := 0
	for i in max_soldiers:
		if _soldier_alive[i] < 0.5 or _soldier_dead[i] > 0.5:
			continue

		var new_pos := _calculate_artillery_crew_position(alive_idx, pieces_count)
		_target_positions[i] = new_pos
		_soldier_positions[i] = new_pos

		# Update MultiMesh transform
		var xform := Transform3D()
		xform.origin = _soldier_positions[i]
		_multimesh.set_instance_transform(i, xform)

		alive_idx += 1


func _calculate_artillery_crew_position(crew_index: int, pieces_count: int) -> Vector3:
	"""Position crew scattered around each cannon (sides and behind, not front).
	Creates a more organic, busy look around the artillery pieces."""
	var crew_per_piece := ceili(float(alive_count) / float(pieces_count))
	var piece_index := mini(crew_index / crew_per_piece, pieces_count - 1)
	var local_index := crew_index % crew_per_piece

	var piece_pos := artillery_piece_positions[piece_index]

	# Scatter crew around the cannon in a 270° arc (everything except front)
	# Front of cannon is at angle 0, we want crew from PI/4 (45°) to 7*PI/4 (315°)
	# This keeps the front 90° arc clear for the cannon barrel
	var min_angle := PI * 0.25  # 45° - right side edge
	var max_angle := PI * 1.75  # 315° - left side edge (wrapping around back)
	var angle_range := max_angle - min_angle  # 270° arc

	# Distribute crew evenly around the 270° arc, with slight randomization
	var base_angle := min_angle + (float(local_index) / float(crew_per_piece)) * angle_range
	# Add small random offset for organic scatter (±15°)
	var angle := base_angle + randf_range(-0.26, 0.26)

	# Vary the distance from cannon (1.8 to 3.5 units) for depth
	var min_radius := 1.8
	var max_radius := 3.5
	# Alternate between inner and outer ring based on index
	var radius: float
	if local_index % 2 == 0:
		radius = randf_range(min_radius, min_radius + 0.6)  # Inner ring
	else:
		radius = randf_range(max_radius - 0.6, max_radius)  # Outer ring

	var offset := Vector3(sin(angle), 0, cos(angle)) * radius

	# Keep same Y as sprite scale
	var y_pos := sprite_scale.y * 0.5 + height_offset

	return Vector3(piece_pos.x + offset.x, y_pos, piece_pos.z + offset.z)


func update_artillery_piece_positions(piece_positions: Array[Vector3]) -> void:
	"""Update crew positions when artillery pieces move/rotate.
	Called by ArtilleryFormation when facing changes."""
	if not artillery_crew_mode:
		return
	artillery_piece_positions = piece_positions
	_recalculate_artillery_crew_positions()


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
