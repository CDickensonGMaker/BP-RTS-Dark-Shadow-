# Pure data resource. No Node dependencies. Fully serializable.
class_name RegimentData
extends Resource


@export var regiment_name: String = "Unnamed Regiment"
@export var unit_type: UnitType.Type = UnitType.Type.INFANTRY

# Combat stats
@export var attack: int = 10
@export var defense: int = 10
@export var weapon_skill: int = 10      # melee accuracy
@export var ballistic_skill: int = 0    # ranged accuracy (0 = no ranged)
@export var strength: int = 3           # damage per hit

# Regiment composition
@export var max_soldiers: int = 40      # visual/HP representation
@export var current_soldiers: int = 40

# Morale
@export var base_morale: float = 60.0   # starting morale 0-100
@export var morale_save: int = 5        # resistance to morale damage

# Movement (1.5 = infantry walk, 2.5 = cavalry, 3.0+ = charge/run)
@export var speed: float = 1.5
@export var charge_bonus: int = 6       # attack bonus on charge tick
@export var mass: float = 1.0           # unit mass for charge impact (cavalry=2.0-3.0, infantry=1.0)
@export var turn_rate: float = 3.0      # radians/sec (infantry=3.0, cavalry=1.5, artillery=0.5)

# Ranged (optional)
@export var max_ammo: int = 0           # 0 = melee only
@export var current_ammo: int = 0
@export var range_distance: float = 0.0

# Display
@export var sprite_texture: Texture2D
@export var unit_card_portrait: Texture2D
@export var faction_color: Color = Color.BLUE

# Batched sprite soldiers (for use_sprite_soldiers mode)
@export var sprite_atlas: SpriteUnitAtlas
