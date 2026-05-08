# Enemy army token on the 3D campaign map.
# Uses faction-specific banner textures for orcs, undead, dwarfs, etc.
extends Node3D


signal clicked(army: Node3D)


enum Faction {
	BANDIT,
	ORC,
	UNDEAD,
	DWARF,
	REBEL,
}


@export var faction: Faction = Faction.BANDIT
@export var army_name: String = "Enemy Army"
@export var regiment_count: int = 3

# Visual components
var army_sprite: Sprite3D
var base_mesh: MeshInstance3D
var name_label: Label3D

# Banner textures by faction
const BANNER_PATHS := {
	Faction.BANDIT: "res://assets/icons/army_banner_player.png",  # Reuse for bandits
	Faction.ORC: "res://assets/icons/army_banner_orc.png",
	Faction.UNDEAD: "res://assets/icons/army_banner_undead.png",
	Faction.DWARF: "res://assets/icons/army_banner_dwarf.png",
	Faction.REBEL: "res://assets/icons/army_banner_player.png",  # Placeholder
}

# Faction colors for base mesh
const FACTION_COLORS := {
	Faction.BANDIT: Color(0.6, 0.3, 0.2),
	Faction.ORC: Color(0.3, 0.5, 0.2),
	Faction.UNDEAD: Color(0.3, 0.25, 0.35),
	Faction.DWARF: Color(0.5, 0.4, 0.3),
	Faction.REBEL: Color(0.5, 0.2, 0.2),
}

# Reference to terrain for height queries
var campaign_terrain: Node3D = null

# Hover state
var is_hovered: bool = false


func _ready() -> void:
	campaign_terrain = get_tree().get_first_node_in_group("campaign_terrain")
	_create_visuals()
	_snap_to_terrain()


func _create_visuals() -> void:
	## Create the 3D visual representation of the enemy army

	# Army billboard sprite
	army_sprite = Sprite3D.new()
	var banner_tex := _load_banner_texture()
	if banner_tex:
		army_sprite.texture = banner_tex
		army_sprite.pixel_size = 0.04
	army_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	army_sprite.transparent = true
	army_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	army_sprite.position.y = 2.5
	army_sprite.no_depth_test = false
	army_sprite.render_priority = 1
	add_child(army_sprite)

	# Ground marker
	base_mesh = MeshInstance3D.new()
	var base := CylinderMesh.new()
	base.top_radius = 2.5
	base.bottom_radius = 3.0
	base.height = 0.3
	base_mesh.mesh = base
	base_mesh.position.y = 0.15

	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = FACTION_COLORS.get(faction, Color(0.5, 0.2, 0.2))
	base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	base_mat.albedo_color.a = 0.8
	base_mesh.material_override = base_mat
	add_child(base_mesh)

	# Name label
	name_label = Label3D.new()
	name_label.text = army_name
	name_label.position.y = 8.0
	name_label.font_size = 48
	name_label.outline_size = 6
	name_label.modulate = Color(1.0, 0.7, 0.7)  # Reddish tint for enemy
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(name_label)

	# Click detection area
	var click_area := Area3D.new()
	click_area.name = "ClickArea"
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(6.0, 10.0, 6.0)
	collision.shape = shape
	collision.position.y = 5.0
	click_area.add_child(collision)
	click_area.input_ray_pickable = true
	click_area.mouse_entered.connect(_on_mouse_entered)
	click_area.mouse_exited.connect(_on_mouse_exited)
	add_child(click_area)


func _process(delta: float) -> void:
	# Subtle bob animation
	if army_sprite:
		army_sprite.position.y = 2.5 + sin(Time.get_ticks_msec() * 0.0025) * 0.15


func _snap_to_terrain() -> void:
	if campaign_terrain and campaign_terrain.has_method("get_height_at"):
		position.y = campaign_terrain.get_height_at(position) + 0.1


func _load_banner_texture() -> Texture2D:
	var path: String = BANNER_PATHS.get(faction, BANNER_PATHS[Faction.BANDIT])

	if ResourceLoader.exists(path):
		var tex := load(path)
		if tex is Texture2D:
			return tex

	# Fall back to loading from absolute path
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var image := Image.new()
		var err := image.load(abs_path)
		if err == OK:
			return ImageTexture.create_from_image(image)

	push_warning("[MapEnemyArmy3D] Could not load banner texture: " + path)
	return null


func _on_mouse_entered() -> void:
	is_hovered = true
	# Brighten on hover
	if name_label:
		name_label.modulate = Color(1.0, 0.85, 0.85)


func _on_mouse_exited() -> void:
	is_hovered = false
	if name_label:
		name_label.modulate = Color(1.0, 0.7, 0.7)


func set_faction(new_faction: Faction) -> void:
	faction = new_faction
	# Reload banner texture
	if army_sprite:
		var banner_tex := _load_banner_texture()
		if banner_tex:
			army_sprite.texture = banner_tex
	# Update base color
	if base_mesh:
		var mat := base_mesh.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color = FACTION_COLORS.get(faction, Color(0.5, 0.2, 0.2))
			mat.albedo_color.a = 0.8


func set_army_name(new_name: String) -> void:
	army_name = new_name
	if name_label:
		name_label.text = new_name


func get_faction_name() -> String:
	match faction:
		Faction.BANDIT:
			return "Bandits"
		Faction.ORC:
			return "Orcs"
		Faction.UNDEAD:
			return "Undead"
		Faction.DWARF:
			return "Dwarfs"
		Faction.REBEL:
			return "Rebels"
	return "Unknown"


# Static factory for spawning enemy armies
static func spawn_enemy_army(parent: Node, pos: Vector3, army_faction: Faction, name: String, regiments: int = 3) -> Node3D:
	var script := load("res://campaign_system/map/map_enemy_army_3d.gd")
	var army := Node3D.new()
	army.set_script(script)
	army.faction = army_faction
	army.army_name = name
	army.regiment_count = regiments
	army.position = pos
	parent.add_child(army)
	return army
