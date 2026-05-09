extends SceneTree

func _init():
	print("User data dir: %s" % OS.get_user_data_dir())
	print("Spec path would be: %s" % (OS.get_user_data_dir() + "/agent/spec.json"))

	# Check if file exists
	var path = "user://agent/spec.json"
	print("FileAccess.file_exists('%s'): %s" % [path, FileAccess.file_exists(path)])

	# Try to list directory
	var dir = DirAccess.open("user://")
	if dir:
		print("Contents of user://")
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			print("  - %s" % file_name)
			file_name = dir.get_next()
	else:
		print("Could not open user://")

	quit()
