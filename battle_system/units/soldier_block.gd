# Placeholder block soldier - simple cube representing a soldier
# Implements same interface as Soldier class for compatibility with SoldierFormation
class_name SoldierBlock
extends Node3D


var mesh_instance: MeshInstance3D
var material: StandardMaterial3D
var current_anim: String = "Idle"
var is_dead: bool = false

# Animation state
var anim_offset: float = 0.0
var bob_time: float = 0.0
var bob_speed: float = 2.0
var bob_amount: float = 0.05

@export var soldier_color: Color = Color.BLUE
@export var soldier_size: float = 0.4


func _ready():
	_create_mesh()
	anim_offset = randf() * TAU


func _create_mesh():
	mesh_instance = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(soldier_size, soldier_size * 1.8, soldier_size)
	mesh_instance.mesh = box

	material = StandardMaterial3D.new()
	material.albedo_color = soldier_color
	material.roughness = 0.7
	mesh_instance.material_override = material

	# Position so feet are at origin
	mesh_instance.position.y = soldier_size * 0.9
	add_child(mesh_instance)


func _process(delta):
	if is_dead:
		return

	# Simple idle bobbing animation
	if current_anim == "Idle":
		bob_time += delta * bob_speed
		mesh_instance.position.y = soldier_size * 0.9 + sin(bob_time + anim_offset) * bob_amount
	elif current_anim == "Walk" or current_anim == "Run":
		bob_time += delta * bob_speed * 2.0
		mesh_instance.position.y = soldier_size * 0.9 + abs(sin(bob_time + anim_offset)) * bob_amount * 2


func play_animation(anim_name: String, _blend: float = 0.2):
	if current_anim == anim_name:
		return
	current_anim = anim_name

	# Visual feedback for different animations
	match anim_name:
		"Attack":
			_flash_color(Color.RED, 0.2)
		"HitReact":
			_flash_color(Color.WHITE, 0.1)
		"Block":
			_scale_pulse(1.1, 0.15)
		"Death":
			is_dead = true
			_play_death()


func _flash_color(flash: Color, duration: float):
	var orig = soldier_color
	material.albedo_color = flash
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self) and not is_dead:
		material.albedo_color = orig


func _scale_pulse(scale_factor: float, duration: float):
	var tween = create_tween()
	tween.tween_property(mesh_instance, "scale", Vector3.ONE * scale_factor, duration / 2)
	tween.tween_property(mesh_instance, "scale", Vector3.ONE, duration / 2)


func _play_death():
	var tween = create_tween()
	# Fall over and fade
	tween.tween_property(self, "rotation:x", -PI / 2, 0.3)
	tween.parallel().tween_property(mesh_instance, "position:y", 0.2, 0.3)
	tween.tween_property(material, "albedo_color:a", 0.3, 0.5)


func die():
	play_animation("Death")


func set_color(color: Color):
	soldier_color = color
	if material:
		material.albedo_color = color


func get_available_animations() -> PackedStringArray:
	return PackedStringArray(["Idle", "Walk", "Run", "Attack", "Block", "HitReact", "Death"])
