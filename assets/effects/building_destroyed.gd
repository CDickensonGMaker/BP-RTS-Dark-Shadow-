extends Node3D

@onready var particles: GPUParticles3D = $GPUParticles3D
@onready var timer: Timer = $Timer


func _ready() -> void:
	timer.timeout.connect(_on_timer_timeout)
	timer.start()


func _on_timer_timeout() -> void:
	queue_free()
