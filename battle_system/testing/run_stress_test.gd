extends Node

## Entry point for running the stress test.
## Run this scene to execute 5000 battle simulations.

@onready var stress_tester: Node = null


func _ready() -> void:
	print("[RunStressTest] Initializing stress test...")

	# Create and add the stress tester
	var StressTestScript = load("res://battle_system/testing/stress_test_runner.gd")
	stress_tester = StressTestScript.new()
	add_child(stress_tester)

	# Start after a short delay
	await get_tree().create_timer(0.5).timeout

	print("[RunStressTest] Starting 5000 battle stress test...")
	stress_tester.start_stress_test()
