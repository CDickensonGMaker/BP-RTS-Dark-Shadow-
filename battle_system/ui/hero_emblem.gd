class_name HeroEmblem
extends Sprite3D

## Floating emblem displayed above hero units for battlefield identification.
## Billboards toward camera and pulses subtly to draw attention.

# Emblem textures by faction/type
# Factions: empire, dwarf, greenskin, undead, skaven, woodelf, neutral
# Also supports "player" and "enemy" for side-based emblems
const EMBLEM_PATHS := {
	"player": "res://assets/ui/hero_emblems/emblem_player.png",
	"enemy": "res://assets/ui/hero_emblems/emblem_enemy.png",
	"empire": "res://assets/ui/hero_emblems/emblem_empire.png",
	"undead": "res://assets/ui/hero_emblems/emblem_undead.png",
	"greenskin": "res://assets/ui/hero_emblems/emblem_greenskin.png",
	"dwarf": "res://assets/ui/hero_emblems/emblem_dwarf.png",
	"skaven": "res://assets/ui/hero_emblems/emblem_skaven.png",
	"woodelf": "res://assets/ui/hero_emblems/emblem_woodelf.png",
	"neutral": "res://assets/ui/hero_emblems/emblem_neutral.png",
	"default": "res://assets/ui/hero_emblems/emblem_default.png",
}

# Visual settings
@export var float_height: float = 6.0  # Height above regiment center (lower for smaller heroes)
@export var emblem_size: float = 2.0   # World-space size (smaller to match hero size)
@export var pulse_speed: float = 2.0   # Pulse animation speed
@export var pulse_amount: float = 0.15 # Scale pulse intensity (±15%)
@export var bob_speed: float = 1.5     # Vertical bob speed
@export var bob_amount: float = 0.3    # Vertical bob distance

var _base_scale: Vector3
var _time: float = 0.0
var _target_regiment: Node = null


func _ready() -> void:
	# Billboard toward camera
	billboard = BaseMaterial3D.BILLBOARD_ENABLED

	# Set up rendering
	shaded = false
	transparent = true
	no_depth_test = false  # Render behind terrain/units when occluded

	# Base scale from emblem_size
	_base_scale = Vector3(emblem_size, emblem_size, emblem_size)
	scale = _base_scale

	# Position above parent
	position.y = float_height


func _process(delta: float) -> void:
	_time += delta

	# Subtle pulse effect
	var pulse: float = 1.0 + sin(_time * pulse_speed) * pulse_amount
	scale = _base_scale * pulse

	# Gentle vertical bob
	var bob: float = sin(_time * bob_speed) * bob_amount
	position.y = float_height + bob


func set_emblem_texture(faction: String) -> void:
	"""Set emblem texture based on faction name."""
	var path: String = EMBLEM_PATHS.get(faction.to_lower(), EMBLEM_PATHS["default"])

	if ResourceLoader.exists(path):
		texture = load(path)
	else:
		# Fallback - try default
		if ResourceLoader.exists(EMBLEM_PATHS["default"]):
			texture = load(EMBLEM_PATHS["default"])
		else:
			push_warning("HeroEmblem: No emblem texture found for faction '%s'" % faction)


func set_custom_texture(tex: Texture2D) -> void:
	"""Set a custom emblem texture directly."""
	texture = tex


static func create_for_regiment(regiment: Node) -> Sprite3D:
	"""Factory method to create and attach emblem to a regiment."""
	# Must load script explicitly in static functions (can't use class name directly)
	var script: GDScript = load("res://battle_system/ui/hero_emblem.gd")
	var emblem: Sprite3D = script.new()
	emblem.name = "HeroEmblem"
	emblem._target_regiment = regiment

	# Determine faction from regiment data
	var faction_str: String = "default"
	if regiment.data and regiment.data.faction:
		faction_str = regiment.data.faction

	regiment.add_child(emblem)
	emblem.set_emblem_texture(faction_str)

	return emblem
