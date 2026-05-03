extends SceneTree

## Command-line atlas generator - run with:
## godot --headless --script tools/generate_atlas_cli.gd

const SPRITES_INPUT_DIR := "res://sothr_sprites_output/"
const SPRITES_OUTPUT_DIR := "res://assets/sprites/"

const DIRECTIONS := 8
const FRAMES_PER_DIRECTION := 13
const TOTAL_FRAMES := DIRECTIONS * FRAMES_PER_DIRECTION
const ATLAS_COLUMNS := FRAMES_PER_DIRECTION
const ATLAS_ROWS := DIRECTIONS

const ANIMATIONS := {
	"idle": {"start_frame": 0, "frame_count": 4},
	"walk": {"start_frame": 4, "frame_count": 4},
	"attack": {"start_frame": 8, "frame_count": 3},
	"death": {"start_frame": 11, "frame_count": 2}
}


func _init():
	print("=== Sprite Atlas Generator (CLI) ===")

	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITES_OUTPUT_DIR))

	# Process test unit
	var test_units := ["GRTSWORD"]

	for unit_name in test_units:
		_generate_atlas_for_unit(unit_name)

	print("=== Generation complete ===")
	quit()


func _generate_atlas_for_unit(unit_name: String):
	print("\nGenerating atlas for: ", unit_name)

	var unit_path := ProjectSettings.globalize_path(SPRITES_INPUT_DIR + unit_name + "/")

	# Load all BMP frames
	var frames: Array[Image] = []
	var frame_size := Vector2i.ZERO

	for i in TOTAL_FRAMES:
		var bmp_path := unit_path + unit_name + "_%02d.bmp" % i
		var image := Image.new()
		var err := image.load(bmp_path)

		if err == OK:
			if frame_size == Vector2i.ZERO:
				frame_size = image.get_size()
				print("  Frame size: ", frame_size)

			if image.get_format() != Image.FORMAT_RGBA8:
				image.convert(Image.FORMAT_RGBA8)

			_apply_chroma_key(image, Color(1.0, 0.0, 1.0), 0.1)
			frames.append(image)
		else:
			print("  Missing frame: ", bmp_path)
			if frame_size != Vector2i.ZERO:
				var placeholder := Image.create(frame_size.x, frame_size.y, false, Image.FORMAT_RGBA8)
				placeholder.fill(Color(1.0, 0.0, 1.0, 0.0))
				frames.append(placeholder)

	if frames.is_empty():
		print("  ERROR: No frames loaded!")
		return

	print("  Loaded ", frames.size(), " frames")

	# Calculate atlas dimensions
	var atlas_width := frame_size.x * ATLAS_COLUMNS
	var atlas_height := frame_size.y * ATLAS_ROWS
	print("  Atlas size: ", atlas_width, "x", atlas_height)

	# Create atlas image
	var atlas := Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(1.0, 0.0, 1.0, 0.0))

	# Pack frames into atlas
	for frame_idx in frames.size():
		var direction := frame_idx / FRAMES_PER_DIRECTION
		var frame_in_dir := frame_idx % FRAMES_PER_DIRECTION

		var dest_x := frame_in_dir * frame_size.x
		var dest_y := direction * frame_size.y

		var src_rect := Rect2i(Vector2i.ZERO, frame_size)
		atlas.blit_rect(frames[frame_idx], src_rect, Vector2i(dest_x, dest_y))

	# Save atlas PNG
	var png_path := ProjectSettings.globalize_path(SPRITES_OUTPUT_DIR) + unit_name.to_lower() + "_atlas.png"
	var err := atlas.save_png(png_path)

	if err != OK:
		print("  ERROR: Failed to save PNG: ", err)
		return

	print("  Saved: ", png_path)
	print("  Done! Create .tres resource manually in editor.")


func _apply_chroma_key(image: Image, key_color: Color, threshold: float):
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
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
