class_name SpriteUnitAtlas
extends Resource

const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")

## Resource class holding packed texture atlas + frame metadata for unit sprites.
## Used by SpriteFormation for efficient batched rendering via MultiMesh.

## The packed atlas image containing all animation frames
@export var texture: Texture2D

## Number of columns in the atlas grid
@export var columns: int = 13

## Number of rows in the atlas grid (typically 8 for 8 directions)
@export var rows: int = 8

## Size of each frame in pixels
@export var frame_size: Vector2 = Vector2(64, 64)

## Number of facing directions (typically 8)
@export var directions: int = 8

## Animation speed multiplier
@export var animation_speed: float = 8.0

## Direction offset for legacy assets
## Set to 0 since WorldCompass now uses N=0 (clockwise from North), matching SotHR/Dark Omen extractors
@export var direction_offset: int = 0

## Optional custom direction-to-row mapping
## If empty, assumes row index = direction index (row 0 = North, row 1 = NE, etc.)
## Example: {0: 0, 1: 1, 2: 0, 3: 1, 4: 1, 5: 1, 6: 0, 7: 1} means N/E use row 0, others use row 1
@export var direction_rows: Dictionary = {}

## Maps animation name to {start_frame: int, frame_count: int, per_direction?: {dir: {start_frame, frame_count, row}}}
## Example: {"idle": {start_frame: 0, frame_count: 4}, "walk": {start_frame: 4, frame_count: 4}}
## With per-direction: {"idle": {start_frame: 0, frame_count: 4, per_direction: {0: {start_frame: 8, frame_count: 1, row: 0}}}}
@export var animations: Dictionary = {
	"idle": {"start_frame": 0, "frame_count": 4},
	"walk": {"start_frame": 4, "frame_count": 4},
	"attack": {"start_frame": 8, "frame_count": 3},
	"death": {"start_frame": 11, "frame_count": 2}
}

## Direction mapping - See WorldCompass for canonical compass definition
## 0=North, 1=NE, 2=East, 3=SE, 4=South, 5=SW, 6=West, 7=NW (clockwise from North)
const DIRECTION_NAMES := ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"]


func get_total_frames() -> int:
	"""Returns total number of frames per direction."""
	return columns


func get_animation_start(anim_name: String) -> int:
	"""Returns the starting frame index for an animation."""
	if animations.has(anim_name):
		return animations[anim_name].get("start_frame", 0)
	return 0


func get_animation_frame_count(anim_name: String) -> int:
	"""Returns the number of frames in an animation."""
	if animations.has(anim_name):
		return animations[anim_name].get("frame_count", 1)
	return 1


func _remap_direction(direction: int) -> int:
	"""Apply direction_offset to convert from WorldCompass to atlas direction."""
	return (direction + direction_offset) % directions


func get_animation_start_for_direction(anim_name: String, direction: int) -> int:
	"""Returns the starting frame index for an animation, with per-direction override if available."""
	if not animations.has(anim_name):
		return 0

	var remapped := _remap_direction(direction)
	var anim_data = animations[anim_name]

	# Check for per-direction override
	if anim_data.has("per_direction") and anim_data["per_direction"].has(remapped):
		return anim_data["per_direction"][remapped].get("start_frame", anim_data.get("start_frame", 0))

	return anim_data.get("start_frame", 0)


func get_animation_frame_count_for_direction(anim_name: String, direction: int) -> int:
	"""Returns the number of frames in an animation, with per-direction override if available."""
	if not animations.has(anim_name):
		return 1

	var remapped := _remap_direction(direction)
	var anim_data = animations[anim_name]

	# Check for per-direction override
	if anim_data.has("per_direction") and anim_data["per_direction"].has(remapped):
		return anim_data["per_direction"][remapped].get("frame_count", anim_data.get("frame_count", 1))

	return anim_data.get("frame_count", 1)


func get_row_for_direction_and_anim(anim_name: String, direction: int) -> int:
	"""Returns the row to use for a specific direction and animation.

	Priority: per-direction animation override > direction_rows mapping > direction index
	"""
	var remapped := _remap_direction(direction)

	# Check for per-direction override in animation
	if animations.has(anim_name):
		var anim_data = animations[anim_name]
		if anim_data.has("per_direction") and anim_data["per_direction"].has(remapped):
			return clampi(anim_data["per_direction"][remapped].get("row", remapped), 0, rows - 1)

	# Fall back to direction_rows mapping
	if direction_rows.has(remapped):
		return clampi(direction_rows[remapped], 0, rows - 1)

	# Default: direction index = row index
	return clampi(remapped, 0, rows - 1)


func get_uv_rect(direction: int, frame: int) -> Rect2:
	"""Calculate UV rectangle for a specific direction and frame.

	Atlas layout: rows are directions (0=North to 7=NW, clockwise), columns are frames
	Uses direction_rows mapping if defined, otherwise direction index = row index
	"""
	var dir_clamped := clampi(direction, 0, directions - 1)
	var frame_clamped := clampi(frame, 0, columns - 1)

	# Use custom direction-to-row mapping if defined, otherwise use direction as row
	var actual_row: int
	if direction_rows.has(dir_clamped):
		actual_row = clampi(direction_rows[dir_clamped], 0, rows - 1)
	else:
		actual_row = clampi(dir_clamped, 0, rows - 1)

	var uv_size := Vector2(1.0 / float(columns), 1.0 / float(rows))
	var uv_pos := Vector2(
		float(frame_clamped) / float(columns),
		float(actual_row) / float(rows)
	)

	return Rect2(uv_pos, uv_size)


func get_uv_rect_for_animation(anim_name: String, direction: int, frame_offset: int) -> Rect2:
	"""Calculate UV rectangle for an animation frame with full per-direction support.

	Args:
		anim_name: Name of the animation (e.g., "idle", "walk")
		direction: Direction index 0-7
		frame_offset: Frame offset within the animation (0 to frame_count-1)

	Returns UV rect accounting for per-direction overrides if defined.
	"""
	var dir_clamped := clampi(direction, 0, directions - 1)

	# Get animation data with per-direction support
	var start_frame := get_animation_start_for_direction(anim_name, dir_clamped)
	var frame_count := get_animation_frame_count_for_direction(anim_name, dir_clamped)
	var actual_row := get_row_for_direction_and_anim(anim_name, dir_clamped)

	# Calculate actual frame column
	var frame_clamped := clampi(frame_offset, 0, frame_count - 1)
	var actual_col := (start_frame + frame_clamped) % columns

	var uv_size := Vector2(1.0 / float(columns), 1.0 / float(rows))
	var uv_pos := Vector2(
		float(actual_col) / float(columns),
		float(actual_row) / float(rows)
	)

	return Rect2(uv_pos, uv_size)


static func direction_from_angle(angle_rad: float) -> int:
	"""Convert a facing angle (radians) to direction index 0-7.

	Angle 0 = facing -Z (North in our convention), clockwise
	See WorldCompass for canonical compass definition.
	"""
	return WorldCompassScript.direction_from_angle(angle_rad)


static func direction_from_vector(dir: Vector3) -> int:
	"""Convert a direction vector to direction index 0-7.

	See WorldCompass for canonical compass definition.
	"""
	return WorldCompassScript.direction_from_vector(dir)
