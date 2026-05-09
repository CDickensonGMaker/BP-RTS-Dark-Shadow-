class_name SoldierFormation
extends Node3D

# Preload to avoid parse-order issues with class_name
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")
const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")

## Manages a grid of 3D soldiers for a regiment
## Handles spawning, formation layout, and synchronized animations

signal formation_ready
signal soldiers_updated(count: int)
signal formation_transition_complete

@export var soldier_scene: PackedScene
@export var max_soldiers: int = 100
@export var rows: int = 10
@export var spacing: float = 1.2
@export var row_offset: float = 0.3  # Stagger rows for natural look
@export var faction_color: Color = Color.BLUE

## Model front direction offset (0-7). Maps which direction the 3D model's "front" faces.
## 0 = Model front is North, 4 = Model front is South, etc.
## This adds a rotation offset so the model visually faces the correct direction.
var model_front_direction: int = 0

var soldiers: Array[Node3D] = []  # Can be Soldier or SoldierBlock
var alive_count: int = 0
# Phase 6.4: Terrain access via TerrainHelper (removed _terrain variable)
var _terrain_update_timer: float = 0.0
const TERRAIN_UPDATE_INTERVAL: float = 0.1  # Update terrain positions 10x/sec
var _current_facing: float = 0.0  # Current facing direction in radians

# Formation transition state
var _current_formation_type: int = FormationType.Type.LINE
var _target_positions: Array[Vector3] = []
var _start_positions: Array[Vector3] = []
var _transition_time: float = 0.0
var _transition_duration: float = 0.5
var _is_transitioning: bool = false
var _parent_regiment: Regiment = null  # Reference to parent regiment for signal filtering

# Staggered movement state (Phase 8.3 - aliveness)
var _soldier_start_delays: Array[float] = []  # Per-soldier delay before starting movement
var _soldier_speed_jitter: Array[float] = []  # Per-soldier speed multiplier (±15%)

# Formation spacing constants
const LOOSE_SPACING_MULT: float = 2.0
const SHIELD_WALL_SPACING: float = 0.8
const WEDGE_BASE_SPACING: float = 1.5
const SCHILTRON_RADIUS_PER_SOLDIER: float = 0.2
const SQUARE_SIDE_SPACING: float = 1.0

# Idle sway constants (Phase 7 - formation looseness)
const SWAY_AMPLITUDE: float = 0.04  # Max displacement in units
const SWAY_FREQ_X: float = 0.7      # Horizontal sway frequency
const SWAY_FREQ_Z: float = 0.5      # Forward/back sway frequency
var _soldier_sway_phases: Array[Vector2] = []  # Per-soldier X,Z phase offsets
var _sway_time: float = 0.0


func _ready():
	if soldier_scene:
		spawn_formation(max_soldiers)
	call_deferred("_connect_formation_signal")


func _connect_formation_signal():
	# Find parent regiment to filter formation change signals
	var parent = get_parent()
	while parent:
		if parent is Regiment:
			_parent_regiment = parent
			break
		parent = parent.get_parent()

	# Connect to BattleSignals for formation changes
	if BattleSignals:
		BattleSignals.formation_type_changed.connect(_on_formation_type_changed)


func _on_formation_type_changed(regiment: Regiment, _old_formation: int, new_formation: int):
	# Only respond to our parent regiment's formation changes
	if regiment != _parent_regiment:
		return
	transition_to_formation(new_formation)


func _process(delta: float):
	_terrain_update_timer += delta
	if _terrain_update_timer >= TERRAIN_UPDATE_INTERVAL:
		_terrain_update_timer = 0.0
		_update_soldier_terrain_positions()

	# Handle formation transition animation
	if _is_transitioning:
		_update_formation_transition(delta)

	# Idle sway (Phase 7 - formation looseness)
	_sway_time += delta
	_update_idle_sway()


func _update_soldier_terrain_positions():
	## Phase 6.4: Use TerrainHelper for terrain access
	var terrain := TerrainHelperScript.get_terrain(get_tree())
	if not terrain:
		return
	for soldier in soldiers:
		if is_instance_valid(soldier) and soldier.visible:
			var world_pos: Vector3 = soldier.global_position
			var terrain_height: float = terrain.get_height_at(world_pos)
			soldier.global_position.y = terrain_height


func _update_idle_sway():
	## Phase 7 - Formation looseness: subtle per-soldier idle sway
	## Each soldier has a unique phase offset for non-synchronized movement
	if _is_transitioning:
		return  # Don't sway during formation transitions

	for i in soldiers.size():
		if i >= _soldier_sway_phases.size():
			break
		var soldier = soldiers[i]
		if not is_instance_valid(soldier) or not soldier.visible:
			continue

		var phase: Vector2 = _soldier_sway_phases[i]
		var sway_x: float = sin(_sway_time * SWAY_FREQ_X + phase.x) * SWAY_AMPLITUDE
		var sway_z: float = sin(_sway_time * SWAY_FREQ_Z + phase.y) * SWAY_AMPLITUDE

		# Apply sway as local offset (doesn't affect base position)
		# We store the original position in spawn_formation and apply sway on top
		# For simplicity, apply slight rotation instead of position offset
		soldier.rotation.x = sway_z * 0.5  # Subtle forward/back lean
		soldier.rotation.z = sway_x * 0.3  # Subtle side-to-side lean


func spawn_formation(count: int):
	clear_formation()
	_soldier_sway_phases.clear()

	var cols = ceili(float(count) / float(rows))

	for i in count:
		var soldier = soldier_scene.instantiate()
		if not soldier:
			push_error("SoldierFormation: Failed to instantiate soldier scene")
			continue

		var row = i / cols
		var col = i % cols

		# Calculate position with spacing jitter (±0.15 for organic look)
		var x = (col - cols / 2.0) * spacing + randf_range(-0.15, 0.15)
		var z = (row - rows / 2.0) * spacing + randf_range(-0.15, 0.15)

		# Offset alternating rows
		if row % 2 == 1:
			x += row_offset

		soldier.position = Vector3(x, 0, z)
		soldier.rotation.y = randf_range(-0.1, 0.1)  # Slight rotation variance

		# Set color if SoldierBlock
		if soldier.has_method("set_color"):
			soldier.set_color(faction_color)

		add_child(soldier)
		soldiers.append(soldier)

		# Per-soldier sway phase (random offset for non-synchronized sway)
		_soldier_sway_phases.append(Vector2(randf() * TAU, randf() * TAU))

	alive_count = soldiers.size()
	formation_ready.emit()
	soldiers_updated.emit(alive_count)


func clear_formation():
	for soldier in soldiers:
		if is_instance_valid(soldier):
			soldier.queue_free()
	soldiers.clear()
	alive_count = 0


func set_soldier_count(count: int):
	"""Update visible soldiers to match casualties"""
	count = clampi(count, 0, soldiers.size())

	# Hide/show soldiers from the back
	for i in soldiers.size():
		var soldier = soldiers[i]
		if is_instance_valid(soldier):
			if i < count:
				soldier.visible = true
			else:
				soldier.visible = false

	alive_count = count
	soldiers_updated.emit(alive_count)


func kill_soldiers(amount: int):
	"""Kill soldiers with death animation, from back of formation"""
	var killed = 0
	for i in range(soldiers.size() - 1, -1, -1):
		if killed >= amount:
			break
		var soldier = soldiers[i]
		if is_instance_valid(soldier) and soldier.visible:
			soldier.die()
			killed += 1
			alive_count -= 1

	soldiers_updated.emit(alive_count)


func play_animation_all(anim_name: String):
	"""Play animation on all visible soldiers"""
	for soldier in soldiers:
		if is_instance_valid(soldier) and soldier.visible:
			soldier.play_animation(anim_name)


func play_animation_staggered(anim_name: String, stagger_time: float = 0.05):
	"""Play animation with slight delay between soldiers for wave effect"""
	for i in soldiers.size():
		var soldier = soldiers[i]
		if is_instance_valid(soldier) and soldier.visible:
			get_tree().create_timer(i * stagger_time).timeout.connect(
				func(): soldier.play_animation(anim_name)
			)


func get_formation_bounds() -> AABB:
	"""Get bounding box of the formation"""
	if soldiers.is_empty():
		return AABB()

	var min_pos = Vector3.INF
	var max_pos = -Vector3.INF

	for soldier in soldiers:
		if is_instance_valid(soldier):
			min_pos = min_pos.min(soldier.position)
			max_pos = max_pos.max(soldier.position)

	return AABB(min_pos, max_pos - min_pos)


func set_facing_direction(direction: Vector3):
	"""Set all soldiers to face a world direction (using WorldCompass for consistency)
	Bug A fix: Rotates the formation Node3D so geometry matches facing direction."""
	if direction.length_squared() < 0.001:
		return
	var dir_index := WorldCompassScript.direction_from_vector(direction)
	var target_angle := WorldCompassScript.angle_from_direction(dir_index)
	set_facing_angle(target_angle)


func set_facing_angle(angle_rad: float):
	"""Set all soldiers to face an angle (radians)
	Bug A fix: Rotates the formation Node3D itself, soldiers only get small jitter."""
	_current_facing = angle_rad

	# Apply model_front_direction offset
	# Each direction step (0-7) is 45 degrees (PI/4 radians)
	# This remaps which direction the 3D model's "front" actually faces
	var offset_angle := model_front_direction * (PI / 4.0)
	var final_angle := angle_rad + offset_angle

	# Bug A fix: Rotate the formation node so geometry matches facing
	# This means front rank is physically in front, not just visually facing forward
	rotation.y = final_angle

	# Individual soldiers only get small variance (they're already rotated with parent)
	for soldier in soldiers:
		if is_instance_valid(soldier) and soldier.visible:
			# Small variance for natural look (relative to formation rotation)
			soldier.rotation.y = randf_range(-0.1, 0.1)


# =============================================================================
# FORMATION TRANSITION SYSTEM
# =============================================================================

func transition_to_formation(formation_type: int, duration: float = 0.5):
	"""Begin animated transition to a new formation type with staggered movement."""
	if soldiers.is_empty():
		return

	_current_formation_type = formation_type
	_transition_duration = duration
	_transition_time = 0.0

	# Calculate target positions based on formation type
	var visible_count: int = _count_visible_soldiers()
	_target_positions = _calculate_formation_positions(formation_type, visible_count)

	# Store starting positions and calculate per-soldier stagger (Phase 8.3)
	_start_positions.clear()
	_soldier_start_delays.clear()
	_soldier_speed_jitter.clear()

	var max_delay: float = duration * 0.35  # Outer soldiers start up to 35% later

	for i in soldiers.size():
		var soldier = soldiers[i]
		if is_instance_valid(soldier):
			_start_positions.append(soldier.position)

			# Distance-based stagger: center soldiers move first, outer ranks last
			var distance_from_center: float = soldier.position.length()
			var distance_factor: float = clampf(distance_from_center / 8.0, 0.0, 1.0)
			var delay: float = distance_factor * max_delay + randf_range(0.0, 0.15)
			_soldier_start_delays.append(delay)

			# Per-soldier speed jitter: ±15% kills lockstep feel
			_soldier_speed_jitter.append(randf_range(0.85, 1.15))
		else:
			_start_positions.append(Vector3.ZERO)
			_soldier_start_delays.append(0.0)
			_soldier_speed_jitter.append(1.0)

	_is_transitioning = true


func _count_visible_soldiers() -> int:
	var count: int = 0
	for soldier in soldiers:
		if is_instance_valid(soldier) and soldier.visible:
			count += 1
	return count


func _update_formation_transition(delta: float):
	"""Lerp soldiers toward target positions with staggered timing and natural movement."""
	_transition_time += delta
	var all_done: bool = true

	for i in soldiers.size():
		var soldier = soldiers[i]
		if not is_instance_valid(soldier) or not soldier.visible:
			continue
		if i >= _start_positions.size() or i >= _target_positions.size():
			continue
		if i >= _soldier_start_delays.size() or i >= _soldier_speed_jitter.size():
			continue

		# Per-soldier timing with stagger delay
		var personal_elapsed: float = _transition_time - _soldier_start_delays[i]
		if personal_elapsed <= 0.0:
			# This soldier hasn't started yet - stay idle
			if soldier.has_method("play_animation"):
				soldier.play_animation("Idle")
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
		var base_pos: Vector3 = _start_positions[i].lerp(_target_positions[i], eased_t)

		# Add perpendicular sway for natural weaving motion
		var travel: Vector3 = _target_positions[i] - _start_positions[i]
		var sway: Vector3 = Vector3.ZERO
		if travel.length_squared() > 0.5:
			var perp: Vector3 = Vector3(-travel.z, 0, travel.x).normalized()
			sway = perp * sin(t * PI) * 0.15  # Subtle sine-wave weave

		soldier.position = base_pos + sway

		# Per-soldier animation: walk while moving, idle when arrived
		if soldier.has_method("play_animation"):
			if t < 1.0:
				soldier.play_animation("Walk")
			else:
				soldier.play_animation("Idle")

	# Grace period: don't end until all soldiers have had time to arrive
	if all_done and _transition_time >= _transition_duration + 0.5:
		_is_transitioning = false
		formation_transition_complete.emit()


func _ease_in_out_cubic(t: float) -> float:
	"""Smooth ease-in-out for natural acceleration and deceleration."""
	if t < 0.5:
		return 4.0 * t * t * t
	var f: float = -2.0 * t + 2.0
	return 1.0 - f * f * f / 2.0


func _ease_out_quad(t: float) -> float:
	"""Quadratic ease-out for smooth deceleration"""
	return 1.0 - (1.0 - t) * (1.0 - t)


func _calculate_formation_positions(formation_type: int, count: int) -> Array[Vector3]:
	"""Route to appropriate formation calculator based on type"""
	match formation_type:
		FormationType.Type.LINE:
			return _calculate_line_positions(count, rows)
		FormationType.Type.COLUMN:
			return _calculate_column_positions(count)
		FormationType.Type.WEDGE:
			return _calculate_wedge_positions(count)
		FormationType.Type.SQUARE:
			return _calculate_square_positions(count)
		FormationType.Type.LOOSE:
			return _calculate_loose_positions(count)
		FormationType.Type.SHIELD_WALL:
			return _calculate_shield_wall_positions(count)
		FormationType.Type.SCHILTRON:
			return _calculate_schiltron_positions(count)
		_:
			return _calculate_line_positions(count, rows)


# =============================================================================
# FORMATION POSITION CALCULATORS
# =============================================================================

func _calculate_line_positions(count: int, width: int) -> Array[Vector3]:
	"""Standard grid formation - wide, 2-3 ranks deep"""
	var positions: Array[Vector3] = []
	var cols: int = ceili(float(count) / float(width))

	for i in count:
		var row: int = i / cols
		var col: int = i % cols

		var x: float = (col - cols / 2.0) * spacing + randf_range(-0.1, 0.1)
		var z: float = (row - width / 2.0) * spacing + randf_range(-0.1, 0.1)

		# Offset alternating rows for natural look
		if row % 2 == 1:
			x += row_offset

		positions.append(Vector3(x, 0, z))

	return positions


func _calculate_column_positions(count: int) -> Array[Vector3]:
	"""Narrow, deep column - 8 ranks as defined in FormationType"""
	var positions: Array[Vector3] = []
	var ranks: int = FormationType.RANKS[FormationType.Type.COLUMN]  # 8 ranks
	var files: int = ceili(float(count) / float(ranks))

	for i in count:
		var rank: int = i % ranks
		var file: int = i / ranks

		var x: float = (file - files / 2.0) * spacing + randf_range(-0.1, 0.1)
		var z: float = (rank - ranks / 2.0) * spacing + randf_range(-0.1, 0.1)

		positions.append(Vector3(x, 0, z))

	return positions


func _calculate_wedge_positions(count: int) -> Array[Vector3]:
	"""Triangular wedge formation for cavalry charges"""
	var positions: Array[Vector3] = []

	# Leader at the tip
	positions.append(Vector3(0, 0, -WEDGE_BASE_SPACING))

	# Build rows that expand outward
	var placed: int = 1
	var row: int = 1

	while placed < count:
		var soldiers_in_row: int = row + 1
		var _row_width: float = soldiers_in_row * WEDGE_BASE_SPACING  # Reserved for centering

		for col in soldiers_in_row:
			if placed >= count:
				break
			var x: float = (col - soldiers_in_row / 2.0) * WEDGE_BASE_SPACING + randf_range(-0.1, 0.1)
			var z: float = row * spacing + randf_range(-0.1, 0.1)
			positions.append(Vector3(x, 0, z))
			placed += 1

		row += 1

	return positions


func _calculate_square_positions(count: int) -> Array[Vector3]:
	"""Hollow square formation - soldiers on perimeter only"""
	var positions: Array[Vector3] = []

	if count < 4:
		# Too few for a square, fall back to line
		return _calculate_line_positions(count, 2)

	# Calculate square dimensions
	var side_count: int = ceili(float(count) / 4.0)
	var half_side: float = (side_count - 1) * SQUARE_SIDE_SPACING / 2.0

	var placed: int = 0

	# Front side (negative Z)
	for i in side_count:
		if placed >= count:
			break
		var x: float = (i - side_count / 2.0) * SQUARE_SIDE_SPACING + randf_range(-0.05, 0.05)
		positions.append(Vector3(x, 0, -half_side))
		placed += 1

	# Right side (positive X)
	for i in range(1, side_count - 1):
		if placed >= count:
			break
		var z: float = (i - side_count / 2.0) * SQUARE_SIDE_SPACING + randf_range(-0.05, 0.05)
		positions.append(Vector3(half_side, 0, z))
		placed += 1

	# Back side (positive Z)
	for i in range(side_count - 1, -1, -1):
		if placed >= count:
			break
		var x: float = (i - side_count / 2.0) * SQUARE_SIDE_SPACING + randf_range(-0.05, 0.05)
		positions.append(Vector3(x, 0, half_side))
		placed += 1

	# Left side (negative X)
	for i in range(side_count - 2, 0, -1):
		if placed >= count:
			break
		var z: float = (i - side_count / 2.0) * SQUARE_SIDE_SPACING + randf_range(-0.05, 0.05)
		positions.append(Vector3(-half_side, 0, z))
		placed += 1

	# If we still have soldiers, add them to inner ring
	while placed < count:
		var inner_half: float = half_side - SQUARE_SIDE_SPACING
		var angle: float = (placed - side_count * 4) * TAU / maxi(count - side_count * 4, 1)
		var x: float = cos(angle) * inner_half * 0.5
		var z: float = sin(angle) * inner_half * 0.5
		positions.append(Vector3(x, 0, z))
		placed += 1

	return positions


func _calculate_loose_positions(count: int) -> Array[Vector3]:
	"""Spread out grid - reduced missile casualties"""
	var positions: Array[Vector3] = []
	var loose_spacing: float = spacing * LOOSE_SPACING_MULT
	var ranks: int = FormationType.RANKS[FormationType.Type.LOOSE]  # 2 ranks
	var files: int = ceili(float(count) / float(ranks))

	for i in count:
		var rank: int = i % ranks
		var file: int = i / ranks

		var x: float = (file - files / 2.0) * loose_spacing + randf_range(-0.2, 0.2)
		var z: float = (rank - ranks / 2.0) * loose_spacing + randf_range(-0.2, 0.2)

		positions.append(Vector3(x, 0, z))

	return positions


func _calculate_shield_wall_positions(count: int) -> Array[Vector3]:
	"""Tight 2-rank formation for frontal defense"""
	var positions: Array[Vector3] = []
	var ranks: int = FormationType.RANKS[FormationType.Type.SHIELD_WALL]  # 2 ranks
	var files: int = ceili(float(count) / float(ranks))

	for i in count:
		var rank: int = i % ranks
		var file: int = i / ranks

		# Tight horizontal spacing, very tight vertical
		var x: float = (file - files / 2.0) * SHIELD_WALL_SPACING + randf_range(-0.02, 0.02)
		var z: float = rank * SHIELD_WALL_SPACING * 0.8  # Tighter ranks

		positions.append(Vector3(x, 0, z))

	return positions


func _calculate_schiltron_positions(count: int) -> Array[Vector3]:
	"""Circular formation - anti-cavalry bristling hedgehog"""
	var positions: Array[Vector3] = []

	if count < 3:
		return _calculate_line_positions(count, 2)

	# Calculate radius based on soldier count
	var circumference: float = count * SCHILTRON_RADIUS_PER_SOLDIER * 3.0
	var radius: float = circumference / TAU

	# Minimum radius for visual clarity
	radius = maxf(radius, 2.0)

	# Outer ring - most soldiers
	var outer_count: int = ceili(float(count) * 0.7)
	for i in outer_count:
		var angle: float = float(i) / float(outer_count) * TAU
		var x: float = cos(angle) * radius + randf_range(-0.05, 0.05)
		var z: float = sin(angle) * radius + randf_range(-0.05, 0.05)
		positions.append(Vector3(x, 0, z))

	# Inner ring - remaining soldiers
	var inner_count: int = count - outer_count
	var inner_radius: float = radius * 0.6
	for i in inner_count:
		var angle: float = float(i) / float(maxi(inner_count, 1)) * TAU
		# Offset inner ring to stagger with outer
		angle += TAU / (outer_count * 2)
		var x: float = cos(angle) * inner_radius + randf_range(-0.05, 0.05)
		var z: float = sin(angle) * inner_radius + randf_range(-0.05, 0.05)
		positions.append(Vector3(x, 0, z))

	return positions


# =============================================================================
# PUBLIC API FOR DIRECT FORMATION CONTROL
# =============================================================================

func set_formation_type(formation_type: int, animate: bool = true):
	"""Directly set formation type (alternative to signal-based approach)"""
	if animate:
		transition_to_formation(formation_type)
	else:
		_current_formation_type = formation_type
		var visible_count: int = _count_visible_soldiers()
		var positions: Array[Vector3] = _calculate_formation_positions(formation_type, visible_count)
		_apply_positions_immediately(positions)


func _apply_positions_immediately(positions: Array[Vector3]):
	"""Snap soldiers to positions without animation"""
	for i in soldiers.size():
		var soldier = soldiers[i]
		if not is_instance_valid(soldier) or not soldier.visible:
			continue
		if i < positions.size():
			soldier.position = positions[i]


func get_current_formation_type() -> int:
	return _current_formation_type


func is_transitioning() -> bool:
	return _is_transitioning


func set_formation_width(file_count: int, animate: bool = true) -> void:
	"""Set the formation width (number of soldier files across the front rank).
	Triggers a smooth transition to the new layout. Used by formation drag."""
	var alive: int = _count_visible_soldiers()
	if alive < 2:
		return

	# Clamp to physical limits — min 2 wide, min 2 deep
	var max_width: int = maxi(2, alive / 2)
	file_count = clampi(file_count, 2, max_width)

	# Update rows based on desired width
	rows = ceili(float(alive) / float(file_count))

	if animate:
		transition_to_formation(_current_formation_type, _transition_duration)
	else:
		var positions: Array[Vector3] = _calculate_formation_positions(_current_formation_type, alive)
		_apply_positions_immediately(positions)
