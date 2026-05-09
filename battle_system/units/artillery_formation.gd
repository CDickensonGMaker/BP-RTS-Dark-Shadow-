class_name ArtilleryFormation
extends Node3D

## Manages 3D artillery models (cannons, mortars) for a regiment
## Handles spawning, formation layout, collision, and rotation

const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")
const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")

signal formation_ready
signal pieces_updated(count: int)

## The 3D model scene to instantiate for each artillery piece
@export var artillery_model: PackedScene
## Maximum number of artillery pieces
@export var max_pieces: int = 4
## Spacing between artillery pieces
@export var spacing: float = 4.0
## Scale factor for the models (adjust to match unit size)
@export var model_scale: Vector3 = Vector3(0.5, 0.5, 0.5)
## Faction color for any colorable parts
@export var faction_color: Color = Color.BLUE
## Whether to add collision shapes
@export var enable_collision: bool = true
## Height offset from terrain
@export var height_offset: float = 0.0

## Recoil settings
@export var recoil_distance: float = 0.8  ## How far the piece kicks back (in local units)
@export var recoil_duration: float = 0.1  ## How fast the kickback happens
@export var recoil_recovery: float = 0.4  ## How long to return to position

## Model front direction offset (0-7). Maps which direction the 3D model's "front" faces.
## 0 = Model front is North, 4 = Model front is South, etc.
## This adds a rotation offset so the model visually faces the correct direction.
var model_front_direction: int = 0

## Array of spawned artillery piece nodes
var pieces: Array[Node3D] = []
## Original local positions for each piece (for recoil recovery)
var _piece_base_positions: Array[Vector3] = []
## Recoil state per piece: 0=idle, >0=recoiling back, <0=recovering
var _piece_recoil_state: Array[float] = []
## Recoil progress per piece (0 to 1 for recoil, 1 to 0 for recovery)
var _piece_recoil_progress: Array[float] = []
## Number of alive/active pieces
var alive_count: int = 0
## Current facing direction in radians
var _current_facing: float = 0.0
## Target facing direction for smooth rotation
var _target_facing: float = 0.0
## Rotation speed in radians per second
var _rotation_speed: float = 1.5
## Parent regiment reference
var _parent_regiment = null

## Terrain update timer
var _terrain_update_timer: float = 0.0
const TERRAIN_UPDATE_INTERVAL: float = 0.1


func _ready():
	call_deferred("_find_parent_regiment")


func _find_parent_regiment():
	var parent = get_parent()
	while parent:
		if parent.has_method("get_regiment_data"):
			_parent_regiment = parent
			break
		parent = parent.get_parent()


func _process(delta: float):
	# Update terrain positions periodically
	_terrain_update_timer += delta
	if _terrain_update_timer >= TERRAIN_UPDATE_INTERVAL:
		_terrain_update_timer = 0.0
		_update_piece_terrain_positions()

	# Smooth rotation towards target
	if abs(_current_facing - _target_facing) > 0.01:
		_current_facing = lerp_angle(_current_facing, _target_facing, delta * _rotation_speed)
		_apply_facing_to_pieces()

	# Update recoil animations
	_update_recoil(delta)


func spawn_formation(count: int):
	"""Spawn artillery pieces in a line formation perpendicular to facing direction."""
	clear_formation()

	if not artillery_model:
		push_error("ArtilleryFormation: No artillery_model scene assigned")
		return

	var actual_count = mini(count, max_pieces)

	# Clear recoil tracking arrays
	_piece_base_positions.clear()
	_piece_recoil_state.clear()
	_piece_recoil_progress.clear()

	# Calculate positions perpendicular to facing direction
	var positions := _calculate_piece_positions(actual_count)

	for i in actual_count:
		var piece = artillery_model.instantiate()
		if not piece:
			push_error("ArtilleryFormation: Failed to instantiate artillery model")
			continue

		# Position perpendicular to facing (side by side)
		var base_pos = positions[i]
		piece.position = base_pos

		# Store base position for recoil recovery
		_piece_base_positions.append(base_pos)
		_piece_recoil_state.append(0.0)  # 0 = idle
		_piece_recoil_progress.append(0.0)

		# Apply scale
		piece.scale = model_scale

		# Apply initial facing with model_front_direction offset
		# Add PI to flip models 180° (most 3D models are exported with +Z forward, but Godot uses -Z)
		var offset_angle := model_front_direction * (PI / 4.0)
		piece.rotation.y = _current_facing + offset_angle + PI

		# Add collision if enabled and not already present
		if enable_collision:
			_ensure_collision(piece)

		add_child(piece)
		pieces.append(piece)

	alive_count = pieces.size()
	pieces_updated.emit(alive_count)
	formation_ready.emit()

	# Initial terrain snap
	call_deferred("_update_piece_terrain_positions")


func _calculate_piece_positions(count: int) -> Array[Vector3]:
	"""Calculate positions for artillery pieces perpendicular to facing direction."""
	var positions: Array[Vector3] = []

	# Get the right vector (perpendicular to facing)
	# _current_facing is radians where 0 = North (-Z), PI/2 = East (+X)
	var facing_vec := Vector3(sin(_current_facing), 0, cos(_current_facing))
	var right_vec := facing_vec.cross(Vector3.UP).normalized()

	# Position pieces along the right vector (side by side)
	var total_width = (count - 1) * spacing
	var start_offset = -total_width / 2.0

	for i in count:
		var offset = start_offset + (i * spacing)
		var pos = right_vec * offset + Vector3(0, height_offset, 0)
		positions.append(pos)

	return positions


func _reposition_pieces():
	"""Reposition all pieces based on current facing direction."""
	if pieces.is_empty():
		return

	var positions := _calculate_piece_positions(pieces.size())

	for i in pieces.size():
		if i < positions.size() and is_instance_valid(pieces[i]):
			pieces[i].position = positions[i]
			_piece_base_positions[i] = positions[i]


func _ensure_collision(piece: Node3D):
	"""Add collision shape to piece if it doesn't have one."""
	# Check if piece already has a collision body
	var has_collision = false
	for child in piece.get_children():
		if child is StaticBody3D or child is Area3D or child is CharacterBody3D:
			has_collision = true
			break

	if not has_collision:
		# Create a simple box collision
		var body = StaticBody3D.new()
		body.name = "CollisionBody"

		var collision_shape = CollisionShape3D.new()
		var box = BoxShape3D.new()

		# Estimate size from model (can be refined per-model)
		# Artillery is roughly 2x1x3 meters scaled
		box.size = Vector3(2.0, 1.5, 3.0) * model_scale
		collision_shape.shape = box
		collision_shape.position.y = box.size.y / 2.0  # Center collision at ground level

		body.add_child(collision_shape)
		piece.add_child(body)

		# Store regiment reference in metadata for collision detection fallback
		# This allows _on_melee_area_contact to find the owning Regiment
		body.set_meta("regiment", _parent_regiment)

		# Artillery pieces should NOT be on unit collision layer
		# Only the regiment's MeleeArea matters for melee detection
		body.collision_layer = 0
		body.collision_mask = 0


func clear_formation():
	"""Remove all artillery pieces."""
	for piece in pieces:
		if is_instance_valid(piece):
			piece.queue_free()
	pieces.clear()
	_piece_base_positions.clear()
	_piece_recoil_state.clear()
	_piece_recoil_progress.clear()
	alive_count = 0


func set_facing_direction(direction: Vector3):
	"""Set the target facing direction for all pieces."""
	if direction.length_squared() < 0.001:
		return

	var dir_flat = direction
	dir_flat.y = 0
	dir_flat = dir_flat.normalized()

	_target_facing = atan2(dir_flat.x, dir_flat.z)


func set_facing_immediate(direction: Vector3):
	"""Immediately set facing without smooth rotation."""
	if direction.length_squared() < 0.001:
		return

	var dir_flat = direction
	dir_flat.y = 0
	dir_flat = dir_flat.normalized()

	_target_facing = atan2(dir_flat.x, dir_flat.z)
	_current_facing = _target_facing
	_apply_facing_to_pieces()


func _apply_facing_to_pieces():
	"""Apply current facing rotation and reposition all pieces."""
	# Reposition pieces perpendicular to new facing direction
	_reposition_pieces()

	# Apply model_front_direction offset for rotation
	# Each direction step (0-7) is 45 degrees (PI/4 radians)
	# Add PI to flip models 180° (most 3D models are exported with +Z forward, but Godot uses -Z)
	var offset_angle := model_front_direction * (PI / 4.0)
	var final_facing := _current_facing + offset_angle + PI

	for piece in pieces:
		if is_instance_valid(piece) and piece.visible:
			piece.rotation.y = final_facing


func _update_piece_terrain_positions():
	"""Snap pieces to terrain height."""
	var terrain := TerrainHelperScript.get_terrain(get_tree())
	if not terrain:
		return

	for piece in pieces:
		if is_instance_valid(piece) and piece.visible:
			var world_pos: Vector3 = piece.global_position
			var terrain_height: float = terrain.get_height_at(world_pos)
			piece.global_position.y = terrain_height + height_offset


func kill_piece(index: int):
	"""Mark a piece as destroyed (hide it)."""
	if index < 0 or index >= pieces.size():
		return

	var piece = pieces[index]
	if is_instance_valid(piece) and piece.visible:
		piece.visible = false
		alive_count = maxi(0, alive_count - 1)
		pieces_updated.emit(alive_count)


func kill_random_piece():
	"""Kill a random visible piece. Returns the index killed, or -1 if none available."""
	var visible_indices: Array[int] = []
	for i in pieces.size():
		if is_instance_valid(pieces[i]) and pieces[i].visible:
			visible_indices.append(i)

	if visible_indices.is_empty():
		return -1

	var idx = visible_indices[randi() % visible_indices.size()]
	kill_piece(idx)
	return idx


func get_alive_count() -> int:
	"""Return number of visible/alive pieces."""
	return alive_count


func get_piece_positions() -> Array[Vector3]:
	"""Get world positions of all alive pieces."""
	var positions: Array[Vector3] = []
	for piece in pieces:
		if is_instance_valid(piece) and piece.visible:
			positions.append(piece.global_position)
	return positions


func set_animation_state(anim_name: String):
	"""Set animation state on all pieces (if they have AnimationPlayer)."""
	for piece in pieces:
		if not is_instance_valid(piece):
			continue

		# Look for AnimationPlayer in the piece or its children (GLB imports nest it)
		var anim_player: AnimationPlayer = _find_animation_player(piece)
		if not anim_player:
			continue

		# Try the exact name first, then common variations
		var names_to_try := [anim_name, anim_name.to_lower(), anim_name.capitalize()]
		for anim in names_to_try:
			if anim_player.has_animation(anim):
				anim_player.play(anim)
				break


func _find_animation_player(node: Node) -> AnimationPlayer:
	"""Recursively find AnimationPlayer in node tree (GLB imports nest it deep)."""
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func play_fire_animation():
	"""Play firing animation on all pieces with recoil effect."""
	# Try multiple common animation names for firing
	_play_animation_with_fallbacks(["fire", "attack", "Fire", "Attack", "shoot", "Shoot"])
	play_recoil(-1)  # Trigger recoil on all pieces


func _play_animation_with_fallbacks(anim_names: Array):
	"""Try to play animation using multiple possible names."""
	for piece in pieces:
		if not is_instance_valid(piece):
			continue

		var anim_player: AnimationPlayer = _find_animation_player(piece)
		if not anim_player:
			continue

		for anim_name in anim_names:
			if anim_player.has_animation(anim_name):
				anim_player.play(anim_name)
				break


func play_reload_animation():
	"""Play reload animation on all pieces."""
	set_animation_state("reload")


func play_idle_animation():
	"""Play idle animation on all pieces."""
	# Try multiple common idle animation names
	_play_animation_with_fallbacks(["idle", "Idle", "RESET", "default"])


## --- VISUAL STATE FOR AIMING/RELOADING ---

## Current visual firing state
enum VisualFiringState { IDLE, AIMING, RELOADING }
var _current_visual_state: VisualFiringState = VisualFiringState.IDLE

## Signal emitted when visual state changes
signal firing_state_changed(new_state: VisualFiringState)


func set_visual_firing_state(new_state: int) -> void:
	"""Update the visual state of artillery pieces (IDLE, AIMING, or RELOADING).
	   Call this from Regiment when firing state changes."""
	if new_state == _current_visual_state:
		return

	_current_visual_state = new_state
	firing_state_changed.emit(_current_visual_state)

	match _current_visual_state:
		VisualFiringState.AIMING:
			# Artillery is aimed and ready to fire
			_play_animation_with_fallbacks(["aim", "ready", "Aim", "Ready", "idle"])
			_apply_aiming_visual()
		VisualFiringState.RELOADING:
			# Artillery is being reloaded
			_play_animation_with_fallbacks(["reload", "Reload", "load", "Load"])
			_apply_reloading_visual()
		_:
			# Idle state
			play_idle_animation()
			_clear_state_visual()


func _apply_aiming_visual():
	"""Apply visual effects when aiming (ready to fire)."""
	# Slight forward tilt to indicate readiness
	for piece in pieces:
		if is_instance_valid(piece) and piece.visible:
			# Could add a glow effect or particle here
			pass


func _apply_reloading_visual():
	"""Apply visual effects when reloading."""
	# Could show crew animation, smoke clearing, etc.
	for piece in pieces:
		if is_instance_valid(piece) and piece.visible:
			pass


func _clear_state_visual():
	"""Clear any state-specific visual effects."""
	pass


func get_visual_firing_state() -> VisualFiringState:
	"""Get the current visual firing state."""
	return _current_visual_state


func get_visual_firing_state_name() -> String:
	"""Get human-readable name of current visual state."""
	match _current_visual_state:
		VisualFiringState.AIMING:
			return "AIMING"
		VisualFiringState.RELOADING:
			return "RELOADING"
		_:
			return "IDLE"


## --- RECOIL SYSTEM ---

func _update_recoil(delta: float):
	"""Update recoil animation for all pieces."""
	for i in pieces.size():
		if not is_instance_valid(pieces[i]) or not pieces[i].visible:
			continue

		var state = _piece_recoil_state[i]
		if state == 0.0:
			continue  # Idle, no recoil

		var progress = _piece_recoil_progress[i]

		if state > 0:
			# Recoiling backward
			progress += delta / recoil_duration
			if progress >= 1.0:
				progress = 1.0
				_piece_recoil_state[i] = -1.0  # Start recovery
			_piece_recoil_progress[i] = progress
		else:
			# Recovering to original position
			progress -= delta / recoil_recovery
			if progress <= 0.0:
				progress = 0.0
				_piece_recoil_state[i] = 0.0  # Done
			_piece_recoil_progress[i] = progress

		# Apply recoil offset (kick backward along facing direction)
		_apply_recoil_offset(i, progress)


func _apply_recoil_offset(piece_index: int, progress: float):
	"""Apply recoil offset to a piece based on progress (0-1)."""
	if piece_index >= pieces.size():
		return

	var piece = pieces[piece_index]
	if not is_instance_valid(piece):
		return

	var base_pos = _piece_base_positions[piece_index]

	# Calculate recoil direction (backward from facing)
	# Facing is rotation around Y, so backward is -Z in local space rotated by facing
	var recoil_dir = Vector3(sin(_current_facing), 0, cos(_current_facing))

	# Use smooth easing for natural feel
	var eased_progress = _ease_out_quad(progress)

	# Apply offset
	var offset = recoil_dir * recoil_distance * eased_progress
	piece.position = base_pos - offset  # Subtract to go backward


func _ease_out_quad(t: float) -> float:
	"""Quadratic ease-out for smooth deceleration."""
	return 1.0 - (1.0 - t) * (1.0 - t)


func play_recoil(piece_index: int = -1):
	"""
	Trigger recoil animation on a specific piece, or all pieces if index is -1.
	Call this when the artillery fires.
	"""
	if piece_index == -1:
		# Recoil all pieces (volley fire)
		for i in pieces.size():
			_trigger_piece_recoil(i)
	else:
		# Recoil specific piece
		_trigger_piece_recoil(piece_index)


func _trigger_piece_recoil(index: int):
	"""Start recoil animation for a specific piece."""
	if index < 0 or index >= pieces.size():
		return

	if not is_instance_valid(pieces[index]) or not pieces[index].visible:
		return

	# Only start if not already recoiling
	if _piece_recoil_state[index] == 0.0:
		_piece_recoil_state[index] = 1.0  # Start recoiling
		_piece_recoil_progress[index] = 0.0


func play_recoil_staggered(delay_between: float = 0.15):
	"""
	Play recoil on each piece with a stagger delay.
	Creates a sequential firing effect.
	"""
	for i in pieces.size():
		if is_instance_valid(pieces[i]) and pieces[i].visible:
			# Use a timer to stagger the recoil
			get_tree().create_timer(i * delay_between).timeout.connect(
				func(): _trigger_piece_recoil(i)
			)
