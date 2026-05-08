@tool
extends EditorScript

## EditorScript to pack unit sprite BMPs into a texture atlas.
## Run from Godot Editor: Project -> Tools -> Run Script
##
## Dark Omen/Shadow of the Horned Rat format uses STRIDE-OF-8:
## - Frame 0-7 = Animation frame 0 for all 8 directions (NE, E, SE, S, SW, W, NW, N)
## - Frame 8-15 = Animation frame 1 for all 8 directions
## - etc.
##
## Input: sothr_sprites_output/<UNIT_NAME>/ folder with BMP files
## Output: assets/sprites/<unit_name>_atlas.png + <unit_name>_atlas.tres

## Configuration
const SPRITES_INPUT_DIR := "res://sothr_sprites_labeled/"
const SPRITES_OUTPUT_DIR := "res://assets/sprites/"

## Directions constant - Dark Omen uses 8 directions
const DIRECTIONS := 8

## Dark Omen direction order: NE, E, SE, S, SW, W, NW, N (indices 0-7)
## Our system direction order: N, NE, E, SE, S, SW, W, NW (indices 0-7, clockwise from North)
## This map converts Dark Omen direction index to our system's row index
const DO_TO_SYSTEM_DIR := {
	0: 1,  # NE -> row 1
	1: 2,  # E  -> row 2
	2: 3,  # SE -> row 3
	3: 4,  # S  -> row 4
	4: 5,  # SW -> row 5
	5: 6,  # W  -> row 6
	6: 7,  # NW -> row 7
	7: 0,  # N  -> row 0
}

## Animation presets by unit type (charge-walk-fight format from Dark Omen wiki)
const INFANTRY_ANIMATIONS := {
	"charge": {"start_frame": 0, "frame_count": 3},
	"walk": {"start_frame": 3, "frame_count": 3},
	"attack": {"start_frame": 6, "frame_count": 5}
}

const INFANTRY_ANIMATIONS_ALT := {
	"charge": {"start_frame": 0, "frame_count": 3},
	"walk": {"start_frame": 3, "frame_count": 3},
	"attack": {"start_frame": 6, "frame_count": 3}
}

const CAVALRY_ANIMATIONS := {
	"charge": {"start_frame": 0, "frame_count": 5},
	"walk": {"start_frame": 5, "frame_count": 4},
	"attack": {"start_frame": 9, "frame_count": 3}
}

## Default animations for unknown unit types - will be auto-calculated
const DEFAULT_ANIMATIONS := {
	"idle": {"start_frame": 0, "frame_count": 1},
	"walk": {"start_frame": 0, "frame_count": 1}
}


func _run():
	print("=== Sprite Atlas Generator (Dark Omen Stride-of-8) ===")

	# Ensure output directory exists
	var output_dir := DirAccess.open("res://")
	if not output_dir.dir_exists("assets"):
		output_dir.make_dir("assets")
	if not output_dir.dir_exists("assets/sprites"):
		output_dir.make_dir_recursive("assets/sprites")

	# Get all unit folders
	var input_dir := DirAccess.open(SPRITES_INPUT_DIR)
	if not input_dir:
		push_error("Cannot open sprites input directory: " + SPRITES_INPUT_DIR)
		return

	print("Scanning: ", SPRITES_INPUT_DIR)

	var unit_folders: PackedStringArray = []
	input_dir.list_dir_begin()
	var folder_name := input_dir.get_next()
	while folder_name != "":
		if input_dir.current_is_dir() and not folder_name.begins_with("."):
			unit_folders.append(folder_name)
		folder_name = input_dir.get_next()
	input_dir.list_dir_end()

	print("Found ", unit_folders.size(), " unit folders")

	# Process specific units for testing - set to unit_folders to process all
	var test_units := ["GRTSWORD", "DWXBOW", "BLACKORC", "GOB1", "REIK", "TROLL"]

	for unit_name in test_units:
		if unit_name in unit_folders:
			_generate_atlas_for_unit(unit_name)
		else:
			push_warning("Unit folder not found: ", unit_name)

	print("=== Generation complete ===")


func _generate_atlas_for_unit(unit_name: String):
	print("\nGenerating atlas for: ", unit_name)

	var unit_path := SPRITES_INPUT_DIR + unit_name + "/"

	# Auto-detect frame count by counting BMP files
	var total_frames := _count_bmp_files(unit_path, unit_name)
	if total_frames == 0:
		push_error("  No BMP files found for ", unit_name)
		return

	# Calculate animations per direction (stride-of-8 means total_frames / 8)
	var frames_per_direction := total_frames / DIRECTIONS
	print("  Detected ", total_frames, " frames = ", frames_per_direction, " animation frames × 8 directions")

	# Load all BMP frames
	var frames: Array[Image] = []
	var frame_size := Vector2i.ZERO

	for i in total_frames:
		# Try multiple file name formats since source naming varies
		var image: Image = null
		var tried_paths: Array[String] = []

		# Try formats: _00, _0, plain number
		for fmt in ["_%02d.bmp", "_%d.bmp"]:
			var bmp_path := unit_path + unit_name + (fmt % i)
			tried_paths.append(bmp_path)
			image = _load_bmp(bmp_path)
			if image:
				break

		if image:
			if frame_size == Vector2i.ZERO:
				frame_size = image.get_size()
				print("  Frame size: ", frame_size)
			frames.append(image)
		else:
			push_warning("  Missing frame %d, tried: %s" % [i, str(tried_paths)])
			# Create placeholder for missing frames
			if frame_size == Vector2i.ZERO:
				frame_size = Vector2i(64, 64)  # Default size
			var placeholder := Image.create(frame_size.x, frame_size.y, false, Image.FORMAT_RGBA8)
			placeholder.fill(Color.MAGENTA)
			frames.append(placeholder)

	if frames.is_empty():
		push_error("  No frames loaded for ", unit_name)
		return

	print("  Loaded ", frames.size(), " frames")

	# Calculate atlas dimensions
	# Rows = directions (8), Columns = animation frames per direction
	var atlas_columns := frames_per_direction
	var atlas_rows := DIRECTIONS
	var atlas_width := frame_size.x * atlas_columns
	var atlas_height := frame_size.y * atlas_rows

	print("  Atlas layout: ", atlas_columns, " columns × ", atlas_rows, " rows")
	print("  Atlas size: ", atlas_width, "x", atlas_height)

	# Create atlas image
	var atlas := Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(1.0, 0.0, 1.0, 0.0))  # Transparent magenta

	# Pack frames into atlas using STRIDE-OF-8 mapping
	# Dark Omen format: consecutive frames cycle through directions for same animation frame
	# Frame 0 = Anim0, Dir0 (NE)
	# Frame 1 = Anim0, Dir1 (E)
	# ...
	# Frame 7 = Anim0, Dir7 (N)
	# Frame 8 = Anim1, Dir0 (NE)
	# etc.
	for frame_idx in frames.size():
		# Stride-of-8: direction = frame % 8, animation_frame = frame / 8
		var dark_omen_dir := frame_idx % DIRECTIONS  # 0-7 in DO order (NE, E, SE, S, SW, W, NW, N)
		var anim_frame := frame_idx / DIRECTIONS     # 0, 1, 2... animation frame index

		# Convert Dark Omen direction to our system's row
		var dest_row: int = DO_TO_SYSTEM_DIR[dark_omen_dir]

		# Place in atlas: column = animation frame, row = direction (in our system)
		var dest_x := anim_frame * frame_size.x
		var dest_y := dest_row * frame_size.y

		var src_rect := Rect2i(Vector2i.ZERO, frame_size)
		atlas.blit_rect(frames[frame_idx], src_rect, Vector2i(dest_x, dest_y))

	# Save atlas PNG
	var png_path := SPRITES_OUTPUT_DIR + unit_name.to_lower() + "_atlas.png"
	var err := atlas.save_png(png_path.replace("res://", ""))

	if err != OK:
		# Try with full path
		var full_path := ProjectSettings.globalize_path(png_path)
		err = atlas.save_png(full_path)

	if err != OK:
		push_error("  Failed to save atlas PNG: ", png_path)
		return

	print("  Saved: ", png_path)

	# Create SpriteUnitAtlas resource
	var atlas_resource := SpriteUnitAtlas.new()

	# Load the saved texture
	ResourceLoader.load(png_path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
	var texture := load(png_path) as Texture2D
	if texture:
		atlas_resource.texture = texture

	atlas_resource.columns = atlas_columns
	atlas_resource.rows = atlas_rows
	atlas_resource.frame_size = Vector2(frame_size)
	atlas_resource.directions = DIRECTIONS

	# Auto-generate animation definitions based on frame count
	atlas_resource.animations = _generate_animations(frames_per_direction, unit_name)

	# Save resource
	var tres_path := SPRITES_OUTPUT_DIR + unit_name.to_lower() + "_atlas.tres"
	err = ResourceSaver.save(atlas_resource, tres_path)

	if err != OK:
		push_error("  Failed to save atlas resource: ", tres_path)
		return

	print("  Saved: ", tres_path)
	print("  Done!")


func _count_bmp_files(unit_path: String, unit_name: String) -> int:
	"""Count the number of BMP files in a unit folder."""
	var count := 0
	var dir := DirAccess.open(unit_path)
	if not dir:
		# Try globalized path
		var global_path := ProjectSettings.globalize_path(unit_path)
		dir = DirAccess.open(global_path)
		if not dir:
			return 0

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with(".bmp"):
			# Verify it matches the expected naming pattern
			if file_name.begins_with(unit_name):
				count += 1
		file_name = dir.get_next()
	dir.list_dir_end()

	return count


func _generate_animations(frames_per_direction: int, unit_name: String) -> Dictionary:
	"""Generate animation definitions based on frame count and unit type."""
	# Try to detect unit type from name
	var name_upper := unit_name.to_upper()

	# Check for cavalry indicators
	var is_cavalry := (
		name_upper.contains("CAV") or
		name_upper.contains("KNIGHT") or
		name_upper.contains("REIK") or
		name_upper.contains("HORSE")
	)

	if is_cavalry and frames_per_direction >= 12:
		# Cavalry: 5-4-3 (charge-walk-attack)
		return CAVALRY_ANIMATIONS.duplicate(true)
	elif frames_per_direction >= 11:
		# Full infantry: 3-3-5 (charge-walk-attack)
		return INFANTRY_ANIMATIONS.duplicate(true)
	elif frames_per_direction >= 9:
		# Reduced infantry: 3-3-3
		return INFANTRY_ANIMATIONS_ALT.duplicate(true)
	elif frames_per_direction >= 4:
		# Simple unit: split evenly between idle/walk/attack
		var third := frames_per_direction / 3
		var remainder := frames_per_direction % 3
		return {
			"idle": {"start_frame": 0, "frame_count": third},
			"walk": {"start_frame": third, "frame_count": third},
			"attack": {"start_frame": third * 2, "frame_count": third + remainder}
		}
	else:
		# Minimal unit (like single-frame ambient sprites)
		return {
			"idle": {"start_frame": 0, "frame_count": frames_per_direction},
			"walk": {"start_frame": 0, "frame_count": frames_per_direction}
		}


func _load_bmp(path: String) -> Image:
	"""Load a BMP file and convert to RGBA with magenta transparency."""
	var global_path := ProjectSettings.globalize_path(path)

	var image := Image.new()
	var err := image.load(global_path)

	if err != OK:
		return null

	# Convert to RGBA8 for consistency
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)

	# Apply magenta key transparency
	_apply_chroma_key(image, Color(1.0, 0.0, 1.0), 0.1)

	return image


func _apply_chroma_key(image: Image, key_color: Color, threshold: float):
	"""Set alpha to 0 for pixels matching the chroma key color."""
	var width := image.get_width()
	var height := image.get_height()

	for y in height:
		for x in width:
			var pixel := image.get_pixel(x, y)
			var diff := (
				absf(pixel.r - key_color.r) +
				absf(pixel.g - key_color.g) +
				absf(pixel.b - key_color.b)
			) / 3.0

			if diff < threshold:
				image.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
