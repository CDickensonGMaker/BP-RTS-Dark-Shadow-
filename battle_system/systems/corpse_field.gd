extends Node3D

## Battlefield-wide corpse rendering system.
## Owns all corpse data independently of regiment lifecycle.
## Uses per-atlas batched MultiMesh rendering for performance.

const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")

const MAX_CORPSES_PER_BATCH: int = 1024
const CORPSE_SPRITE_SCALE: Vector2 = Vector2(2.5, 3.0)

# Per-atlas corpse batches: SpriteUnitAtlas -> CorpseBatch
var _batches: Dictionary = {}

# Shader for corpse rendering (reuses unit_sprite.gdshader)
var _shader: Shader


func _ready() -> void:
	_shader = preload("res://battle_system/shaders/unit_sprite.gdshader")

	# Connect to battle signals
	if BattleSignals:
		BattleSignals.battle_started.connect(_on_battle_started)
		BattleSignals.battle_ended.connect(_on_battle_ended)


func _on_battle_started() -> void:
	"""Clear corpses from previous battle when new battle starts."""
	clear_all_corpses()


func add_corpse(world_pos: Vector3, atlas: SpriteUnitAtlas, direction: int) -> void:
	"""Add a corpse at the given world position using the specified atlas."""
	if not atlas:
		return

	var batch := _get_or_create_batch(atlas)
	if batch.corpse_count >= batch.max_corpses:
		_expand_batch(batch)

	# Set transform for this corpse instance (world space - no parent drift)
	var xform := Transform3D()
	xform.origin = world_pos
	batch.multimesh.set_instance_transform(batch.corpse_count, xform)

	# Set custom data: (time_offset, direction, visibility, is_dead)
	# All corpses: time_offset=0, visibility=1.0, is_dead=1.0
	var custom := Color(0.0, float(clampi(direction, 0, 7)), 1.0, 1.0)
	batch.multimesh.set_instance_custom_data(batch.corpse_count, custom)

	batch.corpse_count += 1


func clear_all_corpses() -> void:
	"""Remove all corpses from the battlefield."""
	for batch in _batches.values():
		batch.corpse_count = 0
		# Hide all instances by setting visibility to 0
		for i in batch.multimesh.instance_count:
			batch.multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))


func get_total_corpse_count() -> int:
	"""Returns total number of corpses on the battlefield."""
	var total := 0
	for batch in _batches.values():
		total += batch.corpse_count
	return total


func _get_or_create_batch(atlas: SpriteUnitAtlas) -> Dictionary:
	"""Get existing batch for atlas or create new one."""
	if _batches.has(atlas):
		return _batches[atlas]

	var batch := {
		"atlas": atlas,
		"multimesh_instance": null,
		"multimesh": null,
		"material": null,
		"corpse_count": 0,
		"max_corpses": MAX_CORPSES_PER_BATCH
	}
	_setup_batch(batch)
	_batches[atlas] = batch
	return batch


func _setup_batch(batch: Dictionary) -> void:
	"""Initialize MultiMesh and material for a batch."""
	var atlas: SpriteUnitAtlas = batch.atlas

	# Create quad mesh
	var quad := QuadMesh.new()
	quad.size = CORPSE_SPRITE_SCALE
	quad.orientation = PlaneMesh.FACE_Z  # Vertical quad, shader handles billboard/lying

	# Create MultiMesh
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_custom_data = true
	batch.multimesh.mesh = quad
	batch.multimesh.instance_count = batch.max_corpses

	# Create MultiMeshInstance3D
	batch.multimesh_instance = MultiMeshInstance3D.new()
	batch.multimesh_instance.multimesh = batch.multimesh
	batch.multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(batch.multimesh_instance)

	# Setup material (reuse unit_sprite shader)
	batch.material = ShaderMaterial.new()
	batch.material.shader = _shader
	batch.material.set_shader_parameter("sprite_atlas", atlas.texture)
	batch.material.set_shader_parameter("atlas_columns", atlas.columns)
	batch.material.set_shader_parameter("atlas_rows", atlas.rows)
	batch.material.set_shader_parameter("anim_speed", 0.0)  # No animation for corpses

	# Set death animation parameters
	var death_start := atlas.get_animation_start("death")
	var death_frames := atlas.get_animation_frame_count("death")
	batch.material.set_shader_parameter("death_anim_start", death_start)
	batch.material.set_shader_parameter("death_anim_frames", death_frames)
	batch.material.set_shader_parameter("debug_mode", false)

	# Set idle animation params (not used for corpses but shader expects them)
	batch.material.set_shader_parameter("current_anim_start", 0)
	batch.material.set_shader_parameter("current_anim_frames", 1)

	batch.multimesh_instance.material_override = batch.material

	# Initialize all instances as hidden
	for i in batch.max_corpses:
		batch.multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))


func _expand_batch(batch: Dictionary) -> void:
	"""Double batch capacity when full."""
	var old_count: int = batch.max_corpses
	batch.max_corpses *= 2
	batch.multimesh.instance_count = batch.max_corpses
	# Initialize new instances as hidden
	for i in range(old_count, batch.max_corpses):
		batch.multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
	print("CorpseField: Expanded batch for ", batch.atlas.resource_path, " to ", batch.max_corpses, " corpses")


func _on_battle_ended(_result: Dictionary) -> void:
	"""Battle ended - keep corpses visible for victory/defeat screen.
	Corpses are cleared when a new battle starts, not when one ends."""
	pass  # Don't clear - let corpses stay for the aftermath view
