# Floating war banner displayed above a regiment.
# Shows unit type for player (sword, archer, spear, cavalry)
# Shows faction for enemies (orc, undead, dwarf, empire)
class_name RegimentBanner
extends Node3D


# Banner height above the regiment
@export var banner_height: float = 8.0

# Banner scale (world units)
@export var banner_scale: float = 0.025

# Subtle bob animation
@export var bob_enabled: bool = true
@export var bob_amount: float = 0.3
@export var bob_speed: float = 1.5

# Banner textures by unit type (player)
const UNIT_TYPE_BANNERS := {
	UnitType.Type.INFANTRY: "res://assets/banners/sword_banner_player.png",
	UnitType.Type.RANGED: "res://assets/banners/archer_banner_player.png",
	UnitType.Type.CAVALRY: "res://assets/banners/calvary_banner_player.png",
	UnitType.Type.ARTILLERY: "res://assets/banners/spear_banner_player.png",  # Reuse for artillery
}

# Banner textures by faction (enemy)
const FACTION_BANNERS := {
	"orc": "res://assets/banners/ork_units_banner.png",
	"undead": "res://assets/banners/undead_units_banner.png",
	"dwarf": "res://assets/banners/dwarf_units_banner.png",
	"empire": "res://assets/banners/empire_units_banner.png",
	"bandit": "res://assets/banners/sword_banner_player.png",  # Fallback
}

# Special unit type banners (override defaults)
const SPECIAL_UNIT_BANNERS := {
	"spearmen": "res://assets/banners/spear_banner_player.png",
	"pikemen": "res://assets/banners/spear_banner_player.png",
	"halberdiers": "res://assets/banners/spear_banner_player.png",
}

var banner_sprite: Sprite3D
var regiment: Node = null  # Parent Regiment
var base_y: float = 0.0


func _ready() -> void:
	_create_banner_sprite()


func _create_banner_sprite() -> void:
	banner_sprite = Sprite3D.new()
	banner_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	banner_sprite.transparent = true
	banner_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	banner_sprite.no_depth_test = false
	banner_sprite.render_priority = 10  # Render above soldiers
	banner_sprite.pixel_size = banner_scale
	banner_sprite.position.y = banner_height
	base_y = banner_height
	add_child(banner_sprite)


func _process(delta: float) -> void:
	if bob_enabled and banner_sprite:
		var bob_offset: float = sin(Time.get_ticks_msec() * 0.001 * bob_speed) * bob_amount
		banner_sprite.position.y = base_y + bob_offset


func setup_for_regiment(reg: Node) -> void:
	## Setup banner based on regiment data
	regiment = reg

	if not regiment or not "data" in regiment or not regiment.data:
		return

	var texture_path: String = ""

	# Determine which banner to use
	if regiment.is_player_controlled:
		# Player unit: use unit type banner
		texture_path = _get_player_unit_banner(regiment)
	else:
		# Enemy unit: use faction banner
		texture_path = _get_enemy_faction_banner(regiment)

	# Load and apply texture
	if texture_path != "" and ResourceLoader.exists(texture_path):
		var tex: Texture2D = load(texture_path)
		if tex and banner_sprite:
			banner_sprite.texture = tex
	else:
		# Fallback: try loading from absolute path
		var abs_path := ProjectSettings.globalize_path(texture_path)
		if FileAccess.file_exists(abs_path):
			var image := Image.new()
			var err := image.load(abs_path)
			if err == OK and banner_sprite:
				banner_sprite.texture = ImageTexture.create_from_image(image)


func _get_player_unit_banner(reg: Node) -> String:
	var data = reg.data

	# Check for special unit name overrides first
	var unit_name: String = data.unit_name.to_lower() if "unit_name" in data else ""
	for keyword in SPECIAL_UNIT_BANNERS.keys():
		if keyword in unit_name:
			return SPECIAL_UNIT_BANNERS[keyword]

	# Fall back to unit type
	var unit_type: int = data.unit_type if "unit_type" in data else UnitType.Type.INFANTRY
	return UNIT_TYPE_BANNERS.get(unit_type, UNIT_TYPE_BANNERS[UnitType.Type.INFANTRY])


func _get_enemy_faction_banner(reg: Node) -> String:
	var data = reg.data

	# Try to get faction from regiment data
	var faction_name: String = ""

	if "faction_name" in data:
		faction_name = data.faction_name.to_lower()
	elif "faction_id" in data:
		faction_name = str(data.faction_id).to_lower()
	elif "unit_name" in data:
		# Try to infer faction from unit name
		var unit_name: String = data.unit_name.to_lower()
		for faction in FACTION_BANNERS.keys():
			if faction in unit_name:
				faction_name = faction
				break

	# Look up faction banner
	if faction_name in FACTION_BANNERS:
		return FACTION_BANNERS[faction_name]

	# Fallback: empire banner for generic enemies
	return FACTION_BANNERS["empire"]


func set_banner_visible(visible: bool) -> void:
	if banner_sprite:
		banner_sprite.visible = visible


func set_banner_height(height: float) -> void:
	banner_height = height
	base_y = height
	if banner_sprite:
		banner_sprite.position.y = height


func set_banner_scale(scale: float) -> void:
	banner_scale = scale
	if banner_sprite:
		banner_sprite.pixel_size = scale


# Static factory method
static func attach_to_regiment(reg: Node) -> RegimentBanner:
	## Create and attach a banner to a regiment
	var banner := RegimentBanner.new()
	reg.add_child(banner)
	banner.setup_for_regiment(reg)
	return banner
