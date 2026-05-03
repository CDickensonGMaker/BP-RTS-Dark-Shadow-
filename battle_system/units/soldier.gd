class_name Soldier
extends Node3D

## Individual soldier in a regiment formation

var anim_player: AnimationPlayer
var current_anim: String = "Idle"
var anim_offset: float = 0.0

# Morale component (assigned by UnitMorale)
var morale: MoraleComponent = null


func _ready():
	# Find AnimationPlayer in the imported GLB model
	anim_player = _find_animation_player(self)

	if not anim_player:
		push_warning("Soldier: No AnimationPlayer found in model")
		return

	# Randomize animation offset for natural look
	anim_offset = randf()
	if anim_player.has_animation("Idle"):
		anim_player.play("Idle")
		anim_player.seek(anim_offset * anim_player.current_animation_length)


func _find_animation_player(node: Node) -> AnimationPlayer:
	"""Recursively find AnimationPlayer in children"""
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found = _find_animation_player(child)
		if found:
			return found
	return null


func play_animation(anim_name: String, blend: float = 0.2):
	if current_anim == anim_name:
		return
	if anim_player and anim_player.has_animation(anim_name):
		current_anim = anim_name
		anim_player.play(anim_name, blend)


func die():
	play_animation("Death")
	# Don't queue_free - let formation handle cleanup


func get_available_animations() -> PackedStringArray:
	if anim_player:
		return anim_player.get_animation_list()
	return PackedStringArray()
