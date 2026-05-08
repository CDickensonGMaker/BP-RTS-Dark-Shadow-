## Effect atlas resource for animated sprite effects.
## Similar to SpriteUnitAtlas but simplified for effects (projectiles, spells, explosions).
##
## Atlas layout: rows = 8 directions (N, NE, E, SE, S, SW, W, NW), columns = animation frames.
## For non-directional effects, row 0 is used for all directions.

class_name EffectAtlas
extends Resource

@export var texture: Texture2D
@export var columns: int = 8  # Animation frames
@export var rows: int = 8     # Directions (8 for directional, 1 for non-directional)
@export var frame_size: Vector2 = Vector2(80, 80)

# Effect playback settings
@export var fps: float = 12.0
@export var loop: bool = false
@export var directional: bool = true  # Whether to use direction rows


## Get total frame count
func get_frame_count() -> int:
	return columns


## Get animation duration in seconds
func get_duration() -> float:
	if fps <= 0:
		return 0.0
	return float(columns) / fps


## Get UV rect for a specific frame and direction
func get_frame_uv(frame: int, direction: int = 0) -> Rect2:
	var frame_idx := clampi(frame, 0, columns - 1)
	var dir_idx := clampi(direction, 0, rows - 1) if directional else 0

	var frame_w := 1.0 / float(columns)
	var frame_h := 1.0 / float(rows)

	return Rect2(
		frame_idx * frame_w,
		dir_idx * frame_h,
		frame_w,
		frame_h
	)
