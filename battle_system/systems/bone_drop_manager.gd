extends Node3D

## Bone pile spawning system for undead unit deaths.
## Instead of showing death animations, undead units crumble into bone piles.
## Uses batched MultiMesh rendering for performance.

const MAX_BONES_PER_BATCH: int = 2048
const BONE_PILE_SCALE: Vector2 = Vector2(0.8, 0.6)  # Smaller than corpses

# Bone pile texture (generated or loaded)
var _bone_texture: Texture2D
var _multimesh_instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _material: ShaderMaterial
var _bone_count: int = 0

# Undead faction color for identification
const UNDEAD_FACTION_COLOR: Color = Color(0.3, 0.1, 0.4, 1.0)

# Bone pile variation - spawn 2-4 small bone piles per death
const MIN_BONES_PER_DEATH: int = 2
const MAX_BONES_PER_DEATH: int = 4
const BONE_SCATTER_RADIUS: float = 0.8  # How far bones scatter from death point


func _ready() -> void:
	_create_bone_texture()
	_setup_multimesh()

	# Connect to battle signals
	if BattleSignals:
		BattleSignals.battle_started.connect(_on_battle_started)


func _on_battle_started() -> void:
	"""Clear bones from previous battle."""
	clear_all_bones()


func is_undead_unit(faction_color: Color) -> bool:
	"""Check if the given faction color indicates an undead unit."""
	# Compare with small tolerance for float precision
	return faction_color.is_equal_approx(UNDEAD_FACTION_COLOR)


func spawn_bone_pile(world_pos: Vector3, _direction: int = 0) -> void:
	"""Spawn a cluster of bone piles at the given world position."""
	var bone_count = randi_range(MIN_BONES_PER_DEATH, MAX_BONES_PER_DEATH)

	for i in bone_count:
		if _bone_count >= _multimesh.instance_count:
			_expand_batch()

		# Scatter bones around the death point
		var offset := Vector3(
			randf_range(-BONE_SCATTER_RADIUS, BONE_SCATTER_RADIUS),
			0.05,  # Slight height above ground
			randf_range(-BONE_SCATTER_RADIUS, BONE_SCATTER_RADIUS)
		)

		var bone_pos := world_pos + offset

		# Random rotation and slight scale variation
		var xform := Transform3D()
		xform = xform.rotated(Vector3.UP, randf() * TAU)  # Random Y rotation
		xform = xform.scaled(Vector3.ONE * randf_range(0.7, 1.3))  # Size variation
		xform.origin = bone_pos

		_multimesh.set_instance_transform(_bone_count, xform)

		# Custom data: (unused, unused, visibility, bone_type)
		# bone_type 0-3 for texture variation
		var bone_type := randf_range(0.0, 3.99)
		var custom := Color(0.0, 0.0, 1.0, bone_type)
		_multimesh.set_instance_custom_data(_bone_count, custom)

		_bone_count += 1


func clear_all_bones() -> void:
	"""Remove all bones from the battlefield."""
	_bone_count = 0
	# Hide all instances
	for i in _multimesh.instance_count:
		_multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))


func get_bone_count() -> int:
	return _bone_count


func _create_bone_texture() -> void:
	"""Create a simple bone pile texture procedurally."""
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Transparent background

	# Draw multiple small bone/pebble shapes
	var bone_color := Color(0.9, 0.85, 0.75, 1.0)  # Off-white bone color
	var shadow_color := Color(0.6, 0.55, 0.5, 1.0)  # Darker shadow

	# Draw several overlapping ellipses to create bone pile look
	_draw_bone_shape(img, Vector2(32, 32), Vector2(20, 12), bone_color, shadow_color)
	_draw_bone_shape(img, Vector2(24, 28), Vector2(14, 8), bone_color, shadow_color)
	_draw_bone_shape(img, Vector2(40, 30), Vector2(12, 10), bone_color, shadow_color)
	_draw_bone_shape(img, Vector2(28, 38), Vector2(16, 9), bone_color, shadow_color)
	_draw_bone_shape(img, Vector2(36, 24), Vector2(10, 6), bone_color, shadow_color)

	# Add some small pebble/fragment details
	_draw_pebble(img, Vector2(18, 35), 4, bone_color)
	_draw_pebble(img, Vector2(45, 36), 3, bone_color)
	_draw_pebble(img, Vector2(22, 22), 3, bone_color)
	_draw_pebble(img, Vector2(42, 40), 4, bone_color)

	_bone_texture = ImageTexture.create_from_image(img)


func _draw_bone_shape(img: Image, center: Vector2, size: Vector2, color: Color, shadow: Color) -> void:
	"""Draw an ellipse bone shape with shadow."""
	# Draw shadow first (offset down-right)
	for y in range(int(center.y - size.y) + 1, int(center.y + size.y) + 2):
		for x in range(int(center.x - size.x) + 1, int(center.x + size.x) + 2):
			var dx := (x - center.x - 1) / size.x
			var dy := (y - center.y - 1) / size.y
			if dx * dx + dy * dy <= 1.0:
				if x >= 0 and x < 64 and y >= 0 and y < 64:
					var existing := img.get_pixel(x, y)
					if existing.a < 0.5:
						img.set_pixel(x, y, shadow)

	# Draw main bone shape
	for y in range(int(center.y - size.y), int(center.y + size.y) + 1):
		for x in range(int(center.x - size.x), int(center.x + size.x) + 1):
			var dx := (x - center.x) / size.x
			var dy := (y - center.y) / size.y
			if dx * dx + dy * dy <= 1.0:
				if x >= 0 and x < 64 and y >= 0 and y < 64:
					# Add slight color variation
					var varied_color := color
					varied_color.r += randf_range(-0.05, 0.05)
					varied_color.g += randf_range(-0.05, 0.05)
					varied_color.b += randf_range(-0.05, 0.05)
					img.set_pixel(x, y, varied_color)


func _draw_pebble(img: Image, center: Vector2, radius: int, color: Color) -> void:
	"""Draw a small circular pebble/bone fragment."""
	for y in range(int(center.y) - radius, int(center.y) + radius + 1):
		for x in range(int(center.x) - radius, int(center.x) + radius + 1):
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				if x >= 0 and x < 64 and y >= 0 and y < 64:
					var varied_color := color
					varied_color.r += randf_range(-0.08, 0.08)
					varied_color.g += randf_range(-0.08, 0.08)
					img.set_pixel(x, y, varied_color)


func _setup_multimesh() -> void:
	"""Initialize the MultiMesh for bone pile rendering."""
	# Create a flat quad for bone piles (lies on ground)
	var quad := QuadMesh.new()
	quad.size = BONE_PILE_SCALE
	quad.orientation = PlaneMesh.FACE_Y  # Horizontal, lies on ground

	# Create MultiMesh
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_custom_data = true
	_multimesh.mesh = quad
	_multimesh.instance_count = MAX_BONES_PER_BATCH

	# Create MultiMeshInstance3D
	_multimesh_instance = MultiMeshInstance3D.new()
	_multimesh_instance.multimesh = _multimesh
	_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_multimesh_instance)

	# Create simple unlit material for bone piles
	_material = ShaderMaterial.new()
	_material.shader = _create_bone_shader()
	_material.set_shader_parameter("bone_texture", _bone_texture)

	_multimesh_instance.material_override = _material

	# Initialize all instances as hidden
	for i in MAX_BONES_PER_BATCH:
		_multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))


func _create_bone_shader() -> Shader:
	"""Create a simple shader for bone pile rendering."""
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform sampler2D bone_texture : source_color, filter_nearest;

// Instance custom data: (unused, unused, visibility, bone_type)
// visibility in .b channel

void vertex() {
	// Read custom data
	float visibility = INSTANCE_CUSTOM.b;

	// Hide if visibility is 0
	if (visibility < 0.5) {
		VERTEX = vec3(0.0);
	}
}

void fragment() {
	vec4 tex_color = texture(bone_texture, UV);

	// Discard transparent pixels
	if (tex_color.a < 0.1) {
		discard;
	}

	ALBEDO = tex_color.rgb;
	ALPHA = tex_color.a;
}
"""
	return shader


func _expand_batch() -> void:
	"""Double batch capacity when full."""
	var old_count := _multimesh.instance_count
	_multimesh.instance_count = old_count * 2
	# Initialize new instances as hidden
	for i in range(old_count, _multimesh.instance_count):
		_multimesh.set_instance_custom_data(i, Color(0, 0, 0, 0))
	print("BoneDropManager: Expanded to ", _multimesh.instance_count, " bones")
