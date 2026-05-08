class_name WorldCompass
extends RefCounted

## World Compass - Defines "True North" and directional conventions for BP RTS Dark Shadows.
##
## COORDINATE SYSTEM (Top-Down View):
##
##                    NORTH (-Z)
##                       ↑
##                       |
##         WEST (-X) ←———+———→ EAST (+X)
##                       |
##                       ↓
##                    SOUTH (+Z)
##
## When viewing the battle map from above (default camera), north is always
## the top of the screen. This is a WORLD-SPACE concept that never changes
## regardless of camera rotation.
##
## SPRITE DIRECTION INDICES (0-7, clockwise from North):
##
##              0 (N)
##           7       1
##      (W) 6    +    2 (E)
##           5       3
##              4 (S)
##
## Row 0 of sprite sheets = North-facing (unit facing away from camera in top-down)
## Row 4 of sprite sheets = South-facing (unit facing toward camera in top-down)
##
## This matches the SotHR extractor output order: N, NE, E, SE, S, SW, W, NW


# === CARDINAL DIRECTIONS (World Space) ===

## True North: Top of map when viewed top-down (-Z axis)
const NORTH := Vector3(0, 0, -1)

## True South: Bottom of map when viewed top-down (+Z axis)
const SOUTH := Vector3(0, 0, 1)

## True East: Right side of map when viewed top-down (+X axis)
const EAST := Vector3(1, 0, 0)

## True West: Left side of map when viewed top-down (-X axis)
const WEST := Vector3(-1, 0, 0)


# === INTERCARDINAL DIRECTIONS (World Space) ===

const NORTHEAST := Vector3(0.7071, 0, -0.7071)
const NORTHWEST := Vector3(-0.7071, 0, -0.7071)
const SOUTHEAST := Vector3(0.7071, 0, 0.7071)
const SOUTHWEST := Vector3(-0.7071, 0, 0.7071)


# === DIRECTION INDICES ===
## These match sprite sheet row order (clockwise from North)
## Matches SotHR extractor output: N, NE, E, SE, S, SW, W, NW

const DIR_NORTH := 0
const DIR_NORTHEAST := 1
const DIR_EAST := 2
const DIR_SOUTHEAST := 3
const DIR_SOUTH := 4
const DIR_SOUTHWEST := 5
const DIR_WEST := 6
const DIR_NORTHWEST := 7


# === DIRECTION ARRAYS ===

## Direction index to world vector (normalized)
## Order: N, NE, E, SE, S, SW, W, NW (clockwise from North)
const DIRECTION_VECTORS: Array[Vector3] = [
	Vector3(0, 0, -1),      # 0: North (-Z)
	Vector3(0.7071, 0, -0.7071),  # 1: Northeast
	Vector3(1, 0, 0),       # 2: East (+X)
	Vector3(0.7071, 0, 0.7071),   # 3: Southeast
	Vector3(0, 0, 1),       # 4: South (+Z)
	Vector3(-0.7071, 0, 0.7071),  # 5: Southwest
	Vector3(-1, 0, 0),      # 6: West (-X)
	Vector3(-0.7071, 0, -0.7071), # 7: Northwest
]

## Short names for UI/debugging
const DIRECTION_ABBREV: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

## Full names for display
const DIRECTION_NAMES: Array[String] = [
	"North", "Northeast", "East", "Southeast",
	"South", "Southwest", "West", "Northwest"
]


# === CONVERSION FUNCTIONS ===

static func direction_from_vector(dir: Vector3) -> int:
	"""Convert a world-space direction vector to sprite direction index (0-7).

	Args:
		dir: Direction vector in world space (Y component ignored)

	Returns:
		Direction index 0-7 where 0=North, 4=South (clockwise from North)
	"""
	if dir.length_squared() < 0.001:
		return DIR_NORTH  # Default to north if no direction

	# atan2(-z, x) gives angle from +X axis going CCW, but we want CW from -Z (North)
	# We use atan2(x, -z) to get angle from North (-Z axis)
	# Then negate to convert CCW to CW
	var angle := atan2(dir.x, -dir.z)
	return direction_from_angle(-angle)  # Negate to convert CCW to CW


static func direction_from_angle(angle_rad: float) -> int:
	"""Convert a world-space angle to sprite direction index (0-7).

	Args:
		angle_rad: Angle in radians where 0 = facing North (-Z), clockwise

	Returns:
		Direction index 0-7 (clockwise from North)
	"""
	# Normalize to 0-2PI
	var normalized := fmod(angle_rad + TAU, TAU)

	# Each direction covers 45 degrees (PI/4 radians)
	# Offset by 22.5 degrees (PI/8) to center each direction's range
	var adjusted := normalized + PI / 8.0
	return int(adjusted / (PI / 4.0)) % 8


static func angle_from_direction(dir_index: int) -> float:
	"""Convert a sprite direction index to world-space angle.

	Args:
		dir_index: Direction index 0-7

	Returns:
		Angle in radians where 0 = facing North (-Z), clockwise
	"""
	return float(dir_index) * (PI / 4.0)


static func vector_from_direction(dir_index: int) -> Vector3:
	"""Convert a sprite direction index to world-space vector.

	Args:
		dir_index: Direction index 0-7

	Returns:
		Normalized direction vector in world space
	"""
	var clamped := clampi(dir_index, 0, 7)
	return DIRECTION_VECTORS[clamped]


static func opposite_direction(dir_index: int) -> int:
	"""Get the opposite direction (180 degrees).

	Args:
		dir_index: Direction index 0-7

	Returns:
		Opposite direction index (e.g., North -> South)
	"""
	return (dir_index + 4) % 8


static func rotate_direction(dir_index: int, steps: int) -> int:
	"""Rotate a direction by 45-degree steps.

	Args:
		dir_index: Starting direction index 0-7
		steps: Number of 45-degree steps (positive = clockwise)

	Returns:
		New direction index after rotation
	"""
	return (dir_index + steps + 8) % 8


static func direction_name(dir_index: int, abbreviated: bool = false) -> String:
	"""Get human-readable name for a direction.

	Args:
		dir_index: Direction index 0-7
		abbreviated: If true, return "N" instead of "North"

	Returns:
		Direction name string
	"""
	var clamped := clampi(dir_index, 0, 7)
	if abbreviated:
		return DIRECTION_ABBREV[clamped]
	return DIRECTION_NAMES[clamped]


# === CAMERA-RELATIVE CONVERSION ===

static func world_to_screen_direction(world_dir_index: int, camera_y_rotation: float) -> int:
	"""Convert world-space direction to screen-relative direction.

	When the camera rotates, a unit facing "North" in world space will
	appear to face a different screen direction. This function calculates
	which sprite direction to display.

	Args:
		world_dir_index: The unit's actual facing in world space (0-7)
		camera_y_rotation: Camera's Y rotation in radians

	Returns:
		Screen-relative direction index for sprite selection
	"""
	# Convert camera rotation to direction steps (each step = 45 degrees)
	# Add PI because we want the direction the camera is looking FROM, not TO
	var camera_offset := int(round((camera_y_rotation + PI) / (PI / 4.0))) % 8
	return (world_dir_index - camera_offset + 8) % 8


static func screen_to_world_direction(screen_dir_index: int, camera_y_rotation: float) -> int:
	"""Convert screen-relative direction to world-space direction.

	Inverse of world_to_screen_direction. Given what direction something
	appears on screen, determine its actual world-space facing.

	Args:
		screen_dir_index: How the unit appears on screen (0-7)
		camera_y_rotation: Camera's Y rotation in radians

	Returns:
		World-space direction index
	"""
	var camera_offset := int(round((camera_y_rotation + PI) / (PI / 4.0))) % 8
	return (screen_dir_index + camera_offset) % 8


# === UTILITY FUNCTIONS ===

static func angle_between_directions(dir_a: int, dir_b: int) -> float:
	"""Calculate the angle between two direction indices.

	Args:
		dir_a: First direction index 0-7
		dir_b: Second direction index 0-7

	Returns:
		Angle in radians (0 to PI)
	"""
	var diff := absi(dir_a - dir_b)
	if diff > 4:
		diff = 8 - diff
	return float(diff) * (PI / 4.0)


static func is_facing_direction(unit_dir: int, target_dir: int, tolerance_steps: int = 1) -> bool:
	"""Check if a unit is roughly facing a target direction.

	Args:
		unit_dir: Unit's facing direction (0-7)
		target_dir: Target direction to check against (0-7)
		tolerance_steps: How many 45-degree steps of tolerance (default 1 = 45 degrees)

	Returns:
		True if unit is facing within tolerance of target direction
	"""
	var diff := absi(unit_dir - target_dir)
	if diff > 4:
		diff = 8 - diff
	return diff <= tolerance_steps


static func flanking_zone(attacker_dir: int, defender_dir: int) -> String:
	"""Determine flanking zone based on attack and defense directions.

	Args:
		attacker_dir: Direction FROM which attack is coming (0-7)
		defender_dir: Direction defender is FACING (0-7)

	Returns:
		"front", "flank", or "rear"
	"""
	# What direction would the defender need to face to meet the attacker?
	var needed_facing := opposite_direction(attacker_dir)
	var diff := absi(defender_dir - needed_facing)
	if diff > 4:
		diff = 8 - diff

	if diff <= 1:
		return "front"   # 0-45 degrees
	elif diff <= 3:
		return "flank"   # 45-135 degrees
	else:
		return "rear"    # 135-180 degrees
