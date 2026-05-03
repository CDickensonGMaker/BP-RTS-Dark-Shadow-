class_name SpriteUnitAtlas
extends Resource

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

## Maps animation name to {start_frame: int, frame_count: int}
## Example: {"idle": {start_frame: 0, frame_count: 4}, "walk": {start_frame: 4, frame_count: 4}}
@export var animations: Dictionary = {
	"idle": {"start_frame": 0, "frame_count": 4},
	"walk": {"start_frame": 4, "frame_count": 4},
	"attack": {"start_frame": 8, "frame_count": 3},
	"death": {"start_frame": 11, "frame_count": 2}
}

## Direction mapping: 0=South, 1=SW, 2=West, 3=NW, 4=North, 5=NE, 6=East, 7=SE
const DIRECTION_NAMES := ["south", "southwest", "west", "northwest", "north", "northeast", "east", "southeast"]


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


func get_uv_rect(direction: int, frame: int) -> Rect2:
	"""Calculate UV rectangle for a specific direction and frame.

	Atlas layout: rows are directions (0=South to 7=SE), columns are frames
	"""
	var dir_clamped := clampi(direction, 0, directions - 1)
	var frame_clamped := clampi(frame, 0, columns - 1)

	var uv_size := Vector2(1.0 / float(columns), 1.0 / float(rows))
	var uv_pos := Vector2(
		float(frame_clamped) / float(columns),
		float(dir_clamped) / float(rows)
	)

	return Rect2(uv_pos, uv_size)


static func direction_from_angle(angle_rad: float) -> int:
	"""Convert a facing angle (radians) to direction index 0-7.

	Angle 0 = facing +Z (South in our convention)
	"""
	# Normalize angle to 0-2PI
	var normalized := fmod(angle_rad + TAU, TAU)

	# Each direction covers 45 degrees (PI/4 radians)
	# Offset by 22.5 degrees (PI/8) to center each direction range
	var adjusted := normalized + PI / 8.0
	var index := int(adjusted / (PI / 4.0)) % 8

	return index


static func direction_from_vector(dir: Vector3) -> int:
	"""Convert a direction vector to direction index 0-7."""
	if dir.length_squared() < 0.001:
		return 0  # Default to South if no direction

	var angle := atan2(dir.x, dir.z)
	return direction_from_angle(angle)
