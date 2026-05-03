extends Node

## Debug controller for testing sprite formations vs 3D formations.
##
## CONTROLS:
## - Left-click to select units (uses SelectionManager)
## - Right-click to move selected units (uses FormationDragHandler)
## - 1-4 = Switch animations (idle/walk/attack/death)
## - K = Kill 5 soldiers from each regiment
## - R = Rotate all regiments 45 degrees
## - N = Cycle to next animation
## - H = Show help

var _regiments_3d: Array[Node] = []
var _regiments_sprite: Array[Node] = []
var _current_anim_index: int = 0
var _animations: Array[String] = ["idle", "walk", "attack", "death"]
var _current_direction: float = 0.0


func _ready():
	# Find all regiments after scene is ready
	await get_tree().process_frame
	await get_tree().process_frame
	_find_regiments()
	_print_help()


func _find_regiments():
	# Find 3D regiments
	var node_3d = get_parent().get_node_or_null("3D_Units")
	if node_3d:
		for child in node_3d.get_children():
			if child is Regiment:
				_regiments_3d.append(child)

	# Find sprite regiments
	var node_sprite = get_parent().get_node_or_null("Sprite_Units")
	if node_sprite:
		for child in node_sprite.get_children():
			if child is Regiment:
				_regiments_sprite.append(child)

	print("SpriteTestController: Found ", _regiments_3d.size(), " 3D regiments")
	print("SpriteTestController: Found ", _regiments_sprite.size(), " sprite regiments")
	print("Total regiments: ", _regiments_3d.size() + _regiments_sprite.size())


func _print_help():
	print("")
	print("============= SPRITE VS 3D TEST =============")
	print("LAYOUT:")
	print("  Back row (Z=-15):  3D placeholder blocks")
	print("  Front row (Z=+15): 2D billboard sprites")
	print("")
	print("SELECTION & MOVEMENT:")
	print("  Left-click  = Select unit")
	print("  Right-click = Move selected unit(s)")
	print("  Drag select = Box select multiple")
	print("")
	print("DEBUG CONTROLS:")
	print("  1 = Idle animation")
	print("  2 = Walk animation")
	print("  3 = Attack animation")
	print("  4 = Death animation")
	print("  K = Kill 5 soldiers from all regiments")
	print("  R = Rotate all regiments 45 degrees")
	print("  N = Cycle to next animation")
	print("  F1 = Show this help")
	print("")
	print("UNIT CONTROLS (H = Hold position):")
	print("=============================================")
	print("")


func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_play_animation(0)
			KEY_2:
				_play_animation(1)
			KEY_3:
				_play_animation(2)
			KEY_4:
				_play_animation(3)
			KEY_K:
				_kill_soldiers(5)
			KEY_R:
				_rotate_regiments()
			KEY_N:
				_next_animation()
			KEY_F1:
				_print_help()


func _get_all_regiments() -> Array[Node]:
	var all: Array[Node] = []
	all.append_array(_regiments_3d)
	all.append_array(_regiments_sprite)
	return all


func _play_animation(index: int):
	_current_anim_index = index
	var anim_name = _animations[index]
	print("Playing animation: ", anim_name)

	for reg in _get_all_regiments():
		# Play on 3D formation
		if reg.formation:
			var anim_3d = anim_name.capitalize()  # "idle" -> "Idle"
			reg.formation.play_animation_all(anim_3d)
		# Play on sprite overlay
		if reg.sprite_overlay:
			reg.sprite_overlay.play_animation_all(anim_name)


func _next_animation():
	_current_anim_index = (_current_anim_index + 1) % _animations.size()
	_play_animation(_current_anim_index)


func _kill_soldiers(amount: int):
	print("Killing ", amount, " soldiers from each regiment")
	for reg in _get_all_regiments():
		reg.take_casualties(amount)


func _rotate_regiments():
	_current_direction += PI / 4.0  # 45 degrees
	if _current_direction >= TAU:
		_current_direction -= TAU
	print("Rotating to direction: ", rad_to_deg(_current_direction), " degrees")

	for reg in _get_all_regiments():
		# Rotate sprite formations
		if reg.sprite_overlay:
			reg.sprite_overlay.set_facing_angle(_current_direction)
		# For 3D formations, we could rotate the formation node
		# but that's handled by the Regiment state machine during movement
