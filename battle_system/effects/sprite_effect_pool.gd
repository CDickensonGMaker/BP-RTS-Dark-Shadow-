extends Node3D

## Pooled sprite effect system using MultiMesh for batched rendering.
## Spawns animated billboard sprites for projectiles, spell effects, explosions.
##
## Each effect type gets its own MultiMesh batch for efficient rendering.
## Effects are automatically recycled when their animation completes.
##
## VIEWPORT SUPPORT: Pass a context_node (e.g., source unit) to spawn_effect()
## to ensure effects render in the correct viewport (e.g., Unit Zoo SubViewport).

const MAX_EFFECTS_PER_BATCH: int = 256
const EFFECT_SPRITE_SCALE: Vector2 = Vector2(2.0, 2.0)

# Effect shader
var _shader: Shader

# Loaded effect atlases by name
var _atlases: Dictionary = {}

# Per-atlas AND per-parent batches: "atlas_path::parent_id" -> EffectBatch
# This allows separate batches for different viewports (main scene vs SubViewport)
var _batches: Dictionary = {}

# Cache of parent nodes for batch cleanup
var _batch_parents: Dictionary = {}  # batch_key -> parent_node

# Active effects for cleanup tracking
var _active_effects: Array[Dictionary] = []


func _ready() -> void:
	_shader = preload("res://battle_system/shaders/effect_sprite.gdshader")
	_preload_atlases()


func _preload_atlases() -> void:
	## Preload commonly used effect atlases.
	var effect_dir := "res://assets/sprites/effects/"
	var atlases_to_load: Array[String] = [
		"arrow_atlas",
		"explosion_atlas",
		"fire_skull_projectile_atlas",
		"magic_missile_1_atlas",
		"magic_missile_2_atlas",
		"lightning_1_atlas",
		"lightning_2_atlas",
		"ice_shard_1_atlas",
		"ice_shard_2_atlas",
		"holy_light_atlas",
		"smite_atlas",
		"fire_wall_atlas",
		"attack_spell_atlas",
		"spell_impact_1_atlas",
		"spell_impact_2_atlas",
		"spell_cast_1_atlas",
		"spell_cast_2_atlas",
		"spell_effect_1_atlas",
		"spell_effect_2_atlas",
		"spell_misc_14_atlas",  # Fire explosion rings - good for artillery
		"spell_misc_15_atlas",  # Fire trail effects
		# Cannon effects
		"cannon_explosion_atlas",  # Orange fireball impact
		"cannon_muzzle_atlas",     # Fire pillar muzzle flash
		# Casualty effects
		"fire_casualty_atlas",     # Burning soldier
		"fire_burst_atlas",        # Fire explosion burst
		"poison_casualty_atlas",   # Poison/acid death
		"poison_burst_atlas",      # Poison explosion burst
	]

	for atlas_name in atlases_to_load:
		var path := effect_dir + atlas_name + ".tres"
		if ResourceLoader.exists(path):
			var atlas := load(path)
			if atlas:
				_atlases[atlas_name] = atlas


func _process(_delta: float) -> void:
	_cleanup_finished_effects()
	_cleanup_orphaned_batches()


## Find the appropriate parent node for spawning effects.
## This ensures effects render in the correct viewport (e.g., Unit Zoo SubViewport).
## Similar logic to ProjectilePool for consistency.
func _find_effect_parent(context_node: Node) -> Node:
	if not context_node or not is_instance_valid(context_node):
		return self  # Fallback to autoload (main scene)

	# Look for a "Units", "BattleWorld", or "Effects" container in ancestry
	var check_node: Node = context_node.get_parent() if context_node.get_parent() else context_node
	while check_node:
		if check_node.name in ["Units", "BattleWorld", "Effects"]:
			return check_node
		# Also check for SubViewport - spawn effects inside it
		if check_node is SubViewport:
			# Find or create an Effects container inside the SubViewport
			var effects_container = check_node.get_node_or_null("Effects")
			if not effects_container:
				effects_container = Node3D.new()
				effects_container.name = "Effects"
				check_node.add_child(effects_container)
			return effects_container
		check_node = check_node.get_parent()

	# Fallback: use context_node's direct parent or self
	if context_node.get_parent():
		return context_node.get_parent()
	return self


## Spawn an animated sprite effect at the given position.
## Returns the effect index for tracking, or -1 on failure.
## @param context_node: Optional node to determine which viewport to spawn in.
##                      Pass the source unit for projectiles to ensure visibility.
func spawn_effect(atlas_name: String, world_pos: Vector3, direction: int = 0,
		scale: Vector2 = EFFECT_SPRITE_SCALE, loop: bool = false,
		tint: Color = Color.WHITE, duration_override: float = -1.0,
		context_node: Node = null) -> int:

	var atlas: Resource = _atlases.get(atlas_name)
	if not atlas:
		# Try to load on demand
		var path := "res://assets/sprites/effects/" + atlas_name + ".tres"
		if ResourceLoader.exists(path):
			atlas = load(path)
			if atlas:
				_atlases[atlas_name] = atlas

	if not atlas:
		push_warning("SpriteEffectPool: Atlas not found: " + atlas_name)
		return -1

	# Find appropriate parent for this effect (viewport-aware)
	var parent_node: Node = _find_effect_parent(context_node)

	var batch := _get_or_create_batch(atlas, parent_node)
	if batch.effect_count >= batch.max_effects:
		# Find an expired effect to recycle
		var recycled := _recycle_oldest_effect(batch)
		if not recycled:
			push_warning("SpriteEffectPool: Batch full for " + atlas_name)
			return -1

	var effect_idx: int = batch.effect_count

	# Set transform
	var xform := Transform3D()
	xform.origin = world_pos
	xform = xform.scaled(Vector3(scale.x, scale.y, 1.0))
	batch.multimesh.set_instance_transform(effect_idx, xform)

	# Set custom data: (start_time, direction, visibility, reserved)
	var custom := Color(float(Time.get_ticks_msec()) / 1000.0, float(clampi(direction, 0, 7)), 1.0, 0.0)
	batch.multimesh.set_instance_custom_data(effect_idx, custom)

	batch.effect_count += 1

	# Calculate duration
	var duration: float
	if duration_override > 0:
		duration = duration_override
	elif atlas.has_method("get_duration"):
		duration = atlas.get_duration()
	else:
		# Estimate: columns / 12 fps
		var cols: int = atlas.columns if "columns" in atlas else 8
		duration = float(cols) / 12.0

	# Track active effect
	var effect_data := {
		"batch": batch,
		"index": effect_idx,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"duration": duration,
		"loop": loop
	}
	_active_effects.append(effect_data)

	# Update material parameters
	if tint != Color.WHITE:
		batch.material.set_shader_parameter("tint_color", tint)

	batch.material.set_shader_parameter("anim_loop", loop)

	return effect_idx


## Spawn an arrow projectile effect.
## @param context_node: Source unit for viewport detection (ensures visibility in SubViewports)
func spawn_arrow(world_pos: Vector3, direction: int, projectile_type: int = 0, context_node: Node = null) -> int:
	var atlas_name := "arrow_atlas"
	var tint := Color.WHITE

	# Tint based on projectile type (matches Projectile.ProjectileType)
	match projectile_type:
		0:  # ARROW
			tint = Color(0.9, 0.8, 0.6)  # Warm wood color
		1:  # CROSSBOW
			tint = Color(0.7, 0.7, 0.75)  # Steel gray
		2:  # MAGIC
			tint = Color(0.6, 0.8, 1.0)  # Magic blue

	return spawn_effect(atlas_name, world_pos, direction, Vector2(1.5, 1.5), true, tint, -1.0, context_node)


## Spawn an explosion effect.
## @param context_node: Source unit for viewport detection
func spawn_explosion(world_pos: Vector3, radius: float = 3.0, context_node: Node = null) -> int:
	# Use fire explosion rings for larger explosions (artillery), smoke for smaller
	var atlas_name: String
	var tint := Color.WHITE
	var duration: float = 0.5

	if radius >= 4.0:
		# Large artillery explosion - use fire rings
		atlas_name = "spell_misc_14_atlas"
		tint = Color(1.0, 0.8, 0.4)  # Warm orange tint
		duration = 0.8
	else:
		# Smaller explosion - use smoke clouds
		atlas_name = "explosion_atlas"
		if not _atlases.has(atlas_name):
			atlas_name = "spell_impact_1_atlas"

	var scale := Vector2(radius * 0.8, radius * 0.8)
	return spawn_effect(atlas_name, world_pos, 0, scale, false, tint, duration, context_node)


## Spawn a large artillery explosion with fire and smoke.
## @param context_node: Source unit for viewport detection
func spawn_artillery_explosion(world_pos: Vector3, radius: float = 5.0, context_node: Node = null) -> int:
	# Spawn main fire explosion
	var fire_idx := spawn_effect("spell_misc_14_atlas", world_pos, 0, Vector2(radius, radius), false, Color(1.0, 0.7, 0.3), 0.8, context_node)

	# Spawn secondary smoke cloud slightly delayed (offset position)
	var smoke_pos := world_pos + Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
	spawn_effect("explosion_atlas", smoke_pos, 0, Vector2(radius * 0.6, radius * 0.6), false, Color(0.8, 0.8, 0.8), 1.2, context_node)

	return fire_idx


## Spawn a spell impact effect based on damage type.
## @param context_node: Source unit for viewport detection
func spawn_spell_impact(world_pos: Vector3, damage_type: int, radius: float = 3.0, context_node: Node = null) -> int:
	var atlas_name: String
	var tint := Color.WHITE

	# Select atlas based on damage type (SpellData.DamageType)
	match damage_type:
		0:  # FIRE
			atlas_name = "fire_skull_projectile_atlas"
			tint = Color(1.0, 0.6, 0.2)
		1:  # ICE
			atlas_name = "ice_shard_1_atlas"
			tint = Color(0.6, 0.9, 1.0)
		2:  # LIGHTNING
			atlas_name = "lightning_1_atlas"
			tint = Color(0.9, 0.95, 1.0)
		3:  # HOLY
			atlas_name = "holy_light_atlas"
			tint = Color(1.0, 0.95, 0.8)
		4:  # DARK
			atlas_name = "smite_atlas"
			tint = Color(0.6, 0.3, 0.8)
		_:  # PHYSICAL
			atlas_name = "spell_impact_1_atlas"

	var scale := Vector2(radius * 0.6, radius * 0.6)
	return spawn_effect(atlas_name, world_pos, 0, scale, false, tint, 0.6, context_node)


## Spawn a spell projectile effect (for homing/flying spells).
## @param context_node: Source unit for viewport detection
func spawn_spell_projectile(world_pos: Vector3, direction: int, damage_type: int, context_node: Node = null) -> int:
	var atlas_name: String
	var tint := Color.WHITE
	var scale := Vector2(2.0, 2.0)

	match damage_type:
		0:  # FIRE
			atlas_name = "fire_skull_projectile_atlas"
			tint = Color(1.0, 0.5, 0.1)
		1:  # ICE
			atlas_name = "ice_shard_2_atlas"
			tint = Color(0.5, 0.85, 1.0)
		2:  # LIGHTNING
			atlas_name = "lightning_2_atlas"
		3:  # HOLY
			atlas_name = "holy_light_atlas"
			tint = Color(1.0, 0.95, 0.7)
			scale = Vector2(1.5, 1.5)
		4:  # DARK
			atlas_name = "attack_spell_atlas"
			tint = Color(0.5, 0.2, 0.7)
		_:
			atlas_name = "magic_missile_1_atlas"

	return spawn_effect(atlas_name, world_pos, direction, scale, true, tint, -1.0, context_node)


## Spawn a magic missile effect.
## @param context_node: Source unit for viewport detection
func spawn_magic_missile(world_pos: Vector3, direction: int, variant: int = 0, context_node: Node = null) -> int:
	var atlas_name := "magic_missile_" + str(clampi(variant, 1, 4)) + "_atlas"
	return spawn_effect(atlas_name, world_pos, direction, Vector2(1.5, 1.5), true, Color.WHITE, -1.0, context_node)


## Spawn a cast effect at caster position.
## @param context_node: Source unit for viewport detection
func spawn_cast_effect(world_pos: Vector3, damage_type: int, context_node: Node = null) -> int:
	var atlas_name: String

	match damage_type:
		0:  # FIRE
			atlas_name = "spell_cast_1_atlas"
		3:  # HOLY
			atlas_name = "spell_cast_2_atlas"
		_:
			atlas_name = "spell_cast_1_atlas"

	return spawn_effect(atlas_name, world_pos + Vector3(0, 1.5, 0), 0, Vector2(3.0, 3.0), false, Color.WHITE, -1.0, context_node)


## Spawn cannon muzzle flash effect at firing position.
## @param context_node: Source unit for viewport detection
func spawn_cannon_muzzle(world_pos: Vector3, direction: int = 0, context_node: Node = null) -> int:
	# Fire pillar muzzle flash - tall flame burst
	var scale := Vector2(3.0, 4.0)  # Taller than wide for muzzle blast
	return spawn_effect("cannon_muzzle_atlas", world_pos + Vector3(0, 0.5, 0), direction, scale, false, Color(1.0, 0.9, 0.7), 0.4, context_node)


## Spawn cannon impact explosion effect.
## @param context_node: Source unit for viewport detection
func spawn_cannon_explosion(world_pos: Vector3, radius: float = 4.0, context_node: Node = null) -> int:
	# Main orange fireball explosion
	var scale := Vector2(radius * 1.2, radius * 1.2)
	var main_idx := spawn_effect("cannon_explosion_atlas", world_pos, 0, scale, false, Color(1.0, 0.8, 0.5), 0.5, context_node)

	# Add secondary smoke/dust cloud
	var smoke_pos := world_pos + Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5))
	spawn_effect("explosion_atlas", smoke_pos, 0, Vector2(radius * 0.8, radius * 0.8), false, Color(0.7, 0.65, 0.6), 0.8, context_node)

	return main_idx


## Spawn fire casualty effect (burning soldier death).
## @param context_node: Source unit for viewport detection
func spawn_fire_casualty(world_pos: Vector3, direction: int = 0, context_node: Node = null) -> int:
	return spawn_effect("fire_casualty_atlas", world_pos, direction, Vector2(2.0, 4.0), false, Color.WHITE, 0.8, context_node)


## Spawn fire burst effect (explosion damage).
## @param context_node: Source unit for viewport detection
func spawn_fire_burst(world_pos: Vector3, radius: float = 3.0, context_node: Node = null) -> int:
	var scale := Vector2(radius * 0.8, radius * 0.8)
	return spawn_effect("fire_burst_atlas", world_pos, 0, scale, false, Color(1.0, 0.9, 0.7), 0.6, context_node)


## Spawn poison casualty effect (acid/poison death).
## @param context_node: Source unit for viewport detection
func spawn_poison_casualty(world_pos: Vector3, direction: int = 0, context_node: Node = null) -> int:
	return spawn_effect("poison_casualty_atlas", world_pos, direction, Vector2(2.0, 4.0), false, Color.WHITE, 0.8, context_node)


## Spawn poison burst effect (poison AOE damage).
## @param context_node: Source unit for viewport detection
func spawn_poison_burst(world_pos: Vector3, radius: float = 3.0, context_node: Node = null) -> int:
	var scale := Vector2(radius * 0.8, radius * 0.8)
	return spawn_effect("poison_burst_atlas", world_pos, 0, scale, false, Color(0.8, 1.0, 0.7), 0.6, context_node)


## Hide a specific effect (before its animation completes).
## Note: With SubViewport support, batch keys are now "atlas_path::parent_id"
## This function searches all batches matching the atlas_path prefix.
func hide_effect(batch_atlas_path: String, effect_idx: int) -> void:
	# Search all batches that match this atlas path (may have different parent IDs)
	for batch_key in _batches:
		if batch_key.begins_with(batch_atlas_path):
			var batch: Dictionary = _batches[batch_key]
			if effect_idx >= 0 and effect_idx < batch.max_effects:
				# Set visibility to 0
				var custom: Color = batch.multimesh.get_instance_custom_data(effect_idx)
				custom.b = 0.0
				batch.multimesh.set_instance_custom_data(effect_idx, custom)
				return  # Effect found and hidden


## Clear all active effects.
func clear_all_effects() -> void:
	for effect in _active_effects:
		var batch: Dictionary = effect.batch
		var idx: int = effect.index
		if idx < batch.max_effects:
			batch.multimesh.set_instance_custom_data(idx, Color(0, 0, 0, 0))

	_active_effects.clear()

	for batch in _batches.values():
		batch.effect_count = 0


func _cleanup_finished_effects() -> void:
	## Remove effects that have completed their animation.
	var current_time := Time.get_ticks_msec() / 1000.0
	var to_remove: Array[int] = []

	for i in range(_active_effects.size()):
		var effect: Dictionary = _active_effects[i]
		if effect.loop:
			continue  # Looping effects don't auto-cleanup

		var elapsed: float = current_time - effect.start_time
		if elapsed >= effect.duration:
			# Hide the effect
			var batch: Dictionary = effect.batch
			var idx: int = effect.index
			if idx < batch.max_effects:
				batch.multimesh.set_instance_custom_data(idx, Color(0, 0, 0, 0))
			to_remove.append(i)

	# Remove in reverse order to preserve indices
	for i in range(to_remove.size() - 1, -1, -1):
		_active_effects.remove_at(to_remove[i])


func _recycle_oldest_effect(batch: Dictionary) -> bool:
	## Find and recycle the oldest effect in this batch.
	var oldest_idx := -1
	var oldest_time := INF

	for i in range(_active_effects.size()):
		var effect: Dictionary = _active_effects[i]
		if effect.batch == batch and effect.start_time < oldest_time:
			oldest_time = effect.start_time
			oldest_idx = i

	if oldest_idx >= 0:
		var effect: Dictionary = _active_effects[oldest_idx]
		var idx: int = effect.index
		batch.multimesh.set_instance_custom_data(idx, Color(0, 0, 0, 0))
		_active_effects.remove_at(oldest_idx)
		batch.effect_count -= 1
		return true

	return false


func _cleanup_orphaned_batches() -> void:
	## Remove batches whose parent nodes have been freed.
	var keys_to_remove: Array[String] = []

	for batch_key in _batch_parents:
		var parent: Node = _batch_parents[batch_key]
		if not is_instance_valid(parent):
			keys_to_remove.append(batch_key)

	for key in keys_to_remove:
		if _batches.has(key):
			var batch: Dictionary = _batches[key]
			# Free the MultiMeshInstance if it still exists
			if batch.multimesh_instance and is_instance_valid(batch.multimesh_instance):
				batch.multimesh_instance.queue_free()
			_batches.erase(key)
		_batch_parents.erase(key)


func _get_or_create_batch(atlas: Resource, parent_node: Node = null) -> Dictionary:
	## Get existing batch for atlas+parent or create new one.
	## Parent-specific batches ensure effects render in the correct viewport.
	var atlas_path: String = atlas.resource_path if atlas else "default"

	# Use parent's instance ID to create unique batch key per viewport
	var parent_id: String = str(parent_node.get_instance_id()) if parent_node and is_instance_valid(parent_node) else "self"
	var batch_key: String = atlas_path + "::" + parent_id

	if _batches.has(batch_key):
		return _batches[batch_key]

	var batch := {
		"atlas": atlas,
		"atlas_path": atlas_path,
		"batch_key": batch_key,
		"multimesh_instance": null,
		"multimesh": null,
		"material": null,
		"effect_count": 0,
		"max_effects": MAX_EFFECTS_PER_BATCH,
		"parent_node": parent_node
	}
	_setup_batch(batch, parent_node)
	_batches[batch_key] = batch
	_batch_parents[batch_key] = parent_node
	return batch


func _setup_batch(batch: Dictionary, parent_node: Node = null) -> void:
	## Initialize MultiMesh and material for a batch.
	## Adds the batch to the specified parent (for SubViewport support).
	var atlas: Resource = batch.atlas

	# Create quad mesh
	var quad := QuadMesh.new()
	quad.size = EFFECT_SPRITE_SCALE
	quad.orientation = PlaneMesh.FACE_Z

	# Create MultiMesh
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_custom_data = true
	batch.multimesh.mesh = quad
	batch.multimesh.instance_count = batch.max_effects

	# Create MultiMeshInstance3D
	batch.multimesh_instance = MultiMeshInstance3D.new()
	batch.multimesh_instance.multimesh = batch.multimesh
	batch.multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Add to appropriate parent (SubViewport support)
	# If parent_node is provided and valid, add there; otherwise add to self (autoload)
	if parent_node and is_instance_valid(parent_node):
		parent_node.add_child(batch.multimesh_instance)
	else:
		add_child(batch.multimesh_instance)

	# Setup material
	batch.material = ShaderMaterial.new()
	batch.material.shader = _shader

	# Get atlas properties
	var texture: Texture2D = atlas.texture if "texture" in atlas else null
	var columns: int = atlas.columns if "columns" in atlas else 8
	var rows: int = atlas.rows if "rows" in atlas else 8

	batch.material.set_shader_parameter("sprite_atlas", texture)
	batch.material.set_shader_parameter("atlas_columns", columns)
	batch.material.set_shader_parameter("atlas_rows", rows)
	batch.material.set_shader_parameter("anim_fps", 12.0)
	batch.material.set_shader_parameter("anim_loop", false)
	batch.material.set_shader_parameter("directional", rows > 1)
	batch.material.set_shader_parameter("tint_color", Color.WHITE)
	batch.material.set_shader_parameter("alpha_multiplier", 1.0)

	batch.multimesh_instance.material_override = batch.material

	# Initialize all instances as hidden
	for i in batch.max_effects:
		batch.multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
