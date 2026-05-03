extends SceneTree

## Run the sprite atlas generator from command line.
## Usage: godot --headless --path <project> -s tools/run_atlas_generator.gd

const SPRITES_INPUT_DIR := "res://sothr_sprites_labeled/"
const SPRITES_OUTPUT_DIR := "res://assets/sprites/"
const DIRECTIONS := 8

## Direction name to row index mapping
## Our system: 0=S, 1=SW, 2=W, 3=NW, 4=N, 5=NE, 6=E, 7=SE
const DIR_NAME_TO_ROW := {
	"S": 0, "SW": 1, "W": 2, "NW": 3,
	"N": 4, "NE": 5, "E": 6, "SE": 7
}

## Animation folder order (determines column layout)
const ANIMATION_ORDER := ["Idle", "Walk", "Attack", "Dead"]


func _init():
	print("=== Sprite Atlas Generator (Labeled Sprites) ===")

	# Ensure output directory exists
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SPRITES_OUTPUT_DIR))

	# Get all unit folders
	var input_path: String = ProjectSettings.globalize_path(SPRITES_INPUT_DIR)
	var input_dir: DirAccess = DirAccess.open(input_path)
	if not input_dir:
		push_error("Cannot open sprites input directory: " + input_path)
		quit(1)
		return

	var unit_folders: PackedStringArray = []
	input_dir.list_dir_begin()
	var folder_name: String = input_dir.get_next()
	while folder_name != "":
		if input_dir.current_is_dir() and not folder_name.begins_with("."):
			unit_folders.append(folder_name)
		folder_name = input_dir.get_next()
	input_dir.list_dir_end()

	print("Found ", unit_folders.size(), " unit folders")

	# Process specific units - change to unit_folders to process all
	var units_to_process: Array = ["MCCAPT", "NTGOBLIN"]

	for unit_name in units_to_process:
		if unit_name in unit_folders:
			_generate_atlas_for_unit(unit_name)
		else:
			push_warning("Unit folder not found: ", unit_name)

	print("\n=== Generation complete ===")
	quit(0)


func _generate_atlas_for_unit(unit_name: String) -> void:
	print("\n--- Generating atlas for: ", unit_name, " ---")

	var unit_path: String = ProjectSettings.globalize_path(SPRITES_INPUT_DIR + unit_name + "/")

	# Check which animation folders exist
	var available_anims: Array[String] = []
	for anim in ANIMATION_ORDER:
		var check_path: String = unit_path + anim
		if DirAccess.dir_exists_absolute(check_path):
			available_anims.append(anim)

	if available_anims.is_empty():
		push_error("  No animation folders found for ", unit_name)
		return

	print("  Available animations: ", available_anims)

	# Parse frames from each animation folder
	var animations: Dictionary = {}
	var frame_size: Vector2i = Vector2i.ZERO
	var max_frames_per_anim: Dictionary = {}

	for anim in available_anims:
		animations[anim] = {}
		for dir_name in DIR_NAME_TO_ROW.keys():
			animations[anim][dir_name] = []

		var anim_path: String = unit_path + anim + "/"
		var anim_dir: DirAccess = DirAccess.open(anim_path)
		if not anim_dir:
			continue

		anim_dir.list_dir_begin()
		var file_name: String = anim_dir.get_next()
		while file_name != "":
			if not anim_dir.current_is_dir() and file_name.to_lower().ends_with(".png") and not file_name.ends_with(".import"):
				var parsed: Dictionary = _parse_frame_filename(file_name)
				if parsed.is_empty():
					file_name = anim_dir.get_next()
					continue

				var frame_idx: int = parsed["frame"]
				var direction: String = parsed["direction"]

				if direction in DIR_NAME_TO_ROW:
					var img_path: String = anim_path + file_name
					var image: Image = Image.new()
					var err: int = image.load(img_path)
					if err == OK:
						if image.get_format() != Image.FORMAT_RGBA8:
							image.convert(Image.FORMAT_RGBA8)

						if frame_size == Vector2i.ZERO:
							frame_size = image.get_size()
							print("  Frame size: ", frame_size)

						var dir_frames: Array = animations[anim][direction]
						while dir_frames.size() <= frame_idx:
							dir_frames.append(null)
						dir_frames[frame_idx] = image

			file_name = anim_dir.get_next()
		anim_dir.list_dir_end()

		# Count frames for this animation
		for dir_name in DIR_NAME_TO_ROW.keys():
			var frames_arr: Array = animations[anim][dir_name]
			var valid_count: int = 0
			for f in frames_arr:
				if f != null:
					valid_count += 1
			if valid_count > 0:
				max_frames_per_anim[anim] = valid_count
				break

	# Calculate total columns
	var total_columns: int = 0
	var anim_metadata: Dictionary = {}
	for anim in available_anims:
		var frame_count: int = max_frames_per_anim.get(anim, 0)
		if frame_count > 0:
			anim_metadata[anim.to_lower()] = {
				"start_frame": total_columns,
				"frame_count": frame_count
			}
			total_columns += frame_count
			print("  ", anim, ": ", frame_count, " frames (columns ", total_columns - frame_count, "-", total_columns - 1, ")")

	if total_columns == 0:
		push_error("  No frames found for ", unit_name)
		return

	# Create atlas
	var atlas_width: int = frame_size.x * total_columns
	var atlas_height: int = frame_size.y * DIRECTIONS

	print("  Atlas layout: ", total_columns, " columns x ", DIRECTIONS, " rows")
	print("  Atlas size: ", atlas_width, "x", atlas_height)

	var atlas: Image = Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(1.0, 0.0, 1.0, 0.0))

	# Pack frames into atlas
	var current_col: int = 0
	for anim in available_anims:
		var frame_count: int = max_frames_per_anim.get(anim, 0)
		if frame_count == 0:
			continue

		for dir_name in DIR_NAME_TO_ROW.keys():
			var row: int = DIR_NAME_TO_ROW[dir_name]
			var frames_arr: Array = animations[anim][dir_name]

			for frame_idx in frame_count:
				var image: Image = null
				if frame_idx < frames_arr.size():
					image = frames_arr[frame_idx]

				if image:
					var dest_x: int = (current_col + frame_idx) * frame_size.x
					var dest_y: int = row * frame_size.y
					var src_rect: Rect2i = Rect2i(Vector2i.ZERO, frame_size)
					atlas.blit_rect(image, src_rect, Vector2i(dest_x, dest_y))

		current_col += frame_count

	# Save atlas PNG
	var output_base: String = ProjectSettings.globalize_path(SPRITES_OUTPUT_DIR)
	var png_path: String = output_base + unit_name.to_lower() + "_atlas.png"
	var err: int = atlas.save_png(png_path)

	if err != OK:
		push_error("  Failed to save atlas PNG: ", png_path)
		return

	print("  Saved: ", png_path)

	# Create metadata JSON
	var metadata: Dictionary = {
		"columns": total_columns,
		"rows": DIRECTIONS,
		"frame_size": {"x": frame_size.x, "y": frame_size.y},
		"directions": DIRECTIONS,
		"animations": anim_metadata
	}

	var json_path: String = output_base + unit_name.to_lower() + "_atlas.json"
	var json_file: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
	if json_file:
		json_file.store_string(JSON.stringify(metadata, "\t"))
		json_file.close()
		print("  Saved: ", json_path)

	print("  Done!")


func _parse_frame_filename(filename: String) -> Dictionary:
	var base: String = filename.get_basename()
	var parts: PackedStringArray = base.split("_")

	if parts.size() < 3:
		return {}

	var direction: String = parts[-1]
	var frame_str: String = parts[-2]
	if not frame_str.is_valid_int():
		return {}

	var frame_idx: int = frame_str.to_int()
	var anim_frame: int = frame_idx / DIRECTIONS

	return {"frame": anim_frame, "direction": direction}
