extends Control
## Unit Viewer Tool - Preview unit sprites and edit RegimentData properties

const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")

# Regiment data paths
const REGIMENTS_PATH := "res://battle_system/data/regiments/"

# UI References
@onready var sprite_preview: TextureRect = $HSplitContainer/LeftPanel/SpritePanel/SpritePreview
@onready var unit_dropdown: OptionButton = $HSplitContainer/LeftPanel/UnitSelector/UnitDropdown
@onready var direction_label: Label = $HSplitContainer/LeftPanel/DirectionPanel/DirectionGrid/DirectionLabel
@onready var anim_dropdown: OptionButton = $HSplitContainer/LeftPanel/AnimPanel/AnimDropdown
@onready var frame_label: Label = $HSplitContainer/LeftPanel/AnimPanel/FrameLabel
@onready var play_button: Button = $HSplitContainer/LeftPanel/AnimPanel/PlayButton

# Color panel
@onready var color_picker: ColorPickerButton = $HSplitContainer/LeftPanel/ColorPanel/ColorPicker
@onready var reset_color_btn: Button = $HSplitContainer/LeftPanel/ColorPanel/ResetColorBtn
@onready var faction_color_picker: ColorPickerButton = $HSplitContainer/LeftPanel/ColorPanel/FactionColorPicker

# Properties panel
@onready var prop_name: LineEdit = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/NameRow/NameEdit
@onready var prop_faction: LineEdit = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/FactionRow/FactionEdit
@onready var prop_unit_type: OptionButton = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/UnitTypeRow/UnitTypeDropdown
@onready var prop_personality: OptionButton = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/PersonalityRow/PersonalityDropdown
@onready var prop_attack: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/AttackRow/AttackSpin
@onready var prop_defense: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/DefenseRow/DefenseSpin
@onready var prop_weapon_skill: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/WeaponSkillRow/WeaponSkillSpin
@onready var prop_ballistic_skill: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/BallisticSkillRow/BallisticSkillSpin
@onready var prop_strength: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/StrengthRow/StrengthSpin
@onready var prop_armor: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/ArmorRow/ArmorSpin
@onready var prop_max_soldiers: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/MaxSoldiersRow/MaxSoldiersSpin
@onready var prop_base_morale: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/BaseMoraleRow/BaseMoraleSpin
@onready var prop_weapon_class: OptionButton = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/WeaponClassRow/WeaponClassDropdown
@onready var prop_max_ammo: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/MaxAmmoRow/MaxAmmoSpin
@onready var prop_range: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/RangeRow/RangeSpin
@onready var prop_walk_speed: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/WalkSpeedRow/WalkSpeedSpin
@onready var prop_run_speed: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/RunSpeedRow/RunSpeedSpin
@onready var prop_charge_speed: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/ChargeSpeedRow/ChargeSpeedSpin
@onready var prop_charge_bonus: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/ChargeBonusRow/ChargeBonusSpin
@onready var prop_mass: SpinBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/MassRow/MassSpin
@onready var prop_is_elite: CheckBox = $HSplitContainer/RightPanel/ScrollContainer/PropertiesVBox/IsEliteRow/IsEliteCheck
@onready var save_button: Button = $HSplitContainer/RightPanel/SaveButton
@onready var status_label: Label = $HSplitContainer/RightPanel/StatusLabel

# State
var current_regiment: RegimentData = null
var regiment_paths: Array[String] = []
var current_direction: int = 0
var current_animation: String = "idle"
var current_frame: int = 0
var is_playing: bool = false
var anim_timer: float = 0.0

# Maps display name to actual animation key in atlas (handles "death"/"dead" variants)
var anim_key_map: Dictionary = {}

const DIRECTION_NAMES := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

# Standard animation display names (in preferred order)
const STANDARD_ANIMS := ["idle", "walk", "attack", "death"]

# Animation name aliases (display name -> possible atlas keys)
const ANIM_ALIASES := {
	"death": ["death", "dead"],
	"idle": ["idle"],
	"walk": ["walk"],
	"attack": ["attack"],
}


func _ready() -> void:
	_populate_unit_dropdown()
	_populate_enum_dropdowns()
	_connect_signals()

	# Load first unit if available
	if regiment_paths.size() > 0:
		_load_regiment(regiment_paths[0])


func _process(delta: float) -> void:
	if is_playing and current_regiment and current_regiment.sprite_atlas:
		var atlas: SpriteUnitAtlas = current_regiment.sprite_atlas
		anim_timer += delta * atlas.animation_speed
		var frame_count: int = atlas.get_animation_frame_count(current_animation)
		if anim_timer >= 1.0:
			anim_timer -= 1.0
			current_frame = (current_frame + 1) % frame_count
			_update_sprite_preview()


func _populate_unit_dropdown() -> void:
	unit_dropdown.clear()
	regiment_paths.clear()

	var dir := DirAccess.open(REGIMENTS_PATH)
	if not dir:
		push_error("Could not open regiments directory: " + REGIMENTS_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			regiment_paths.append(REGIMENTS_PATH + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Sort alphabetically
	regiment_paths.sort()
	unit_dropdown.clear()
	for path in regiment_paths:
		var display_name := path.get_file().get_basename()
		unit_dropdown.add_item(display_name)


func _populate_enum_dropdowns() -> void:
	# Unit Type
	prop_unit_type.clear()
	prop_unit_type.add_item("Infantry", UnitType.Type.INFANTRY)
	prop_unit_type.add_item("Ranged", UnitType.Type.RANGED)
	prop_unit_type.add_item("Cavalry", UnitType.Type.CAVALRY)
	prop_unit_type.add_item("Artillery", UnitType.Type.ARTILLERY)
	prop_unit_type.add_item("General", UnitType.Type.GENERAL)

	# Personality
	prop_personality.clear()
	prop_personality.add_item("Normal", 0)
	prop_personality.add_item("Disciplined", 1)
	prop_personality.add_item("Impetuous", 2)
	prop_personality.add_item("Fanatic", 3)

	# Weapon Class
	prop_weapon_class.clear()
	prop_weapon_class.add_item("None", 0)
	prop_weapon_class.add_item("Bow", 1)
	prop_weapon_class.add_item("Crossbow", 2)
	prop_weapon_class.add_item("Handgun", 3)
	prop_weapon_class.add_item("Thrown", 4)
	prop_weapon_class.add_item("Cannon", 5)
	prop_weapon_class.add_item("Mortar", 6)
	prop_weapon_class.add_item("War Machine", 7)
	prop_weapon_class.add_item("Breath Fire", 8)
	prop_weapon_class.add_item("Breath Poison", 9)
	prop_weapon_class.add_item("Magic Missile", 10)

	# Animations - populated dynamically from atlas in _populate_animations()


func _populate_animations() -> void:
	"""Populate animation dropdown from current regiment's atlas."""
	anim_dropdown.clear()
	anim_key_map.clear()

	if not current_regiment or not current_regiment.sprite_atlas:
		# Fall back to standard animations
		for anim_name in STANDARD_ANIMS:
			anim_dropdown.add_item(anim_name)
			anim_key_map[anim_name] = anim_name
		return

	var atlas: SpriteUnitAtlas = current_regiment.sprite_atlas
	var atlas_anims: Dictionary = atlas.animations

	# First add standard animations in order (if they exist in atlas)
	for display_name in STANDARD_ANIMS:
		var actual_key := _find_anim_key(atlas_anims, display_name)
		if actual_key != "":
			anim_dropdown.add_item(display_name)
			anim_key_map[display_name] = actual_key

	# Then add any extra animations not in standard list
	for key in atlas_anims.keys():
		var is_alias := false
		for display_name in ANIM_ALIASES:
			if key in ANIM_ALIASES[display_name]:
				is_alias = true
				break
		if not is_alias and not anim_key_map.has(key):
			anim_dropdown.add_item(key)
			anim_key_map[key] = key

	# Select first animation
	if anim_dropdown.item_count > 0:
		anim_dropdown.select(0)
		current_animation = anim_key_map[anim_dropdown.get_item_text(0)]


func _find_anim_key(atlas_anims: Dictionary, display_name: String) -> String:
	"""Find the actual animation key in atlas for a display name (handles aliases)."""
	if ANIM_ALIASES.has(display_name):
		for alias in ANIM_ALIASES[display_name]:
			if atlas_anims.has(alias):
				return alias
	elif atlas_anims.has(display_name):
		return display_name
	return ""


func _connect_signals() -> void:
	unit_dropdown.item_selected.connect(_on_unit_selected)
	anim_dropdown.item_selected.connect(_on_animation_selected)
	play_button.pressed.connect(_on_play_pressed)
	save_button.pressed.connect(_on_save_pressed)
	color_picker.color_changed.connect(_on_color_changed)
	reset_color_btn.pressed.connect(_on_reset_color)
	faction_color_picker.color_changed.connect(_on_faction_color_changed)

	# Direction buttons
	for i in range(8):
		var btn_name := "Dir%d" % i
		var btn: Button = $HSplitContainer/LeftPanel/DirectionPanel/DirectionGrid.get_node_or_null(btn_name)
		if btn:
			btn.pressed.connect(_on_direction_pressed.bind(i))


func _load_regiment(path: String) -> void:
	current_regiment = load(path) as RegimentData
	if not current_regiment:
		push_error("Failed to load regiment: " + path)
		return

	# Populate animations from this unit's atlas
	_populate_animations()

	_update_properties_display()
	_update_sprite_preview()
	current_frame = 0
	anim_timer = 0.0

	# Set faction color picker
	faction_color_picker.color = current_regiment.faction_color

	# Reset modulate color
	color_picker.color = Color.WHITE
	sprite_preview.modulate = Color.WHITE

	status_label.text = "Loaded: " + path.get_file()


func _update_properties_display() -> void:
	if not current_regiment:
		return

	prop_name.text = current_regiment.regiment_name
	prop_faction.text = current_regiment.faction

	# Find matching index for enums
	for i in range(prop_unit_type.item_count):
		if prop_unit_type.get_item_id(i) == current_regiment.unit_type:
			prop_unit_type.select(i)
			break

	for i in range(prop_personality.item_count):
		if prop_personality.get_item_id(i) == current_regiment.personality:
			prop_personality.select(i)
			break

	for i in range(prop_weapon_class.item_count):
		if prop_weapon_class.get_item_id(i) == current_regiment.weapon_class:
			prop_weapon_class.select(i)
			break

	prop_attack.value = current_regiment.attack
	prop_defense.value = current_regiment.defense
	prop_weapon_skill.value = current_regiment.weapon_skill
	prop_ballistic_skill.value = current_regiment.ballistic_skill
	prop_strength.value = current_regiment.strength
	prop_armor.value = current_regiment.armor
	prop_max_soldiers.value = current_regiment.max_soldiers
	prop_base_morale.value = current_regiment.base_morale
	prop_max_ammo.value = current_regiment.max_ammo
	prop_range.value = current_regiment.range_distance
	prop_walk_speed.value = current_regiment.walk_speed
	prop_run_speed.value = current_regiment.run_speed
	prop_charge_speed.value = current_regiment.charge_speed
	prop_charge_bonus.value = current_regiment.charge_bonus
	prop_mass.value = current_regiment.mass
	prop_is_elite.button_pressed = current_regiment.is_elite


func _update_sprite_preview() -> void:
	if not current_regiment or not current_regiment.sprite_atlas:
		sprite_preview.texture = null
		frame_label.text = "No sprite atlas"
		return

	var atlas: SpriteUnitAtlas = current_regiment.sprite_atlas
	if not atlas.texture:
		sprite_preview.texture = null
		frame_label.text = "No texture"
		return

	# Get the UV rect for current direction/animation/frame
	var uv_rect: Rect2 = atlas.get_uv_rect_for_animation(current_animation, current_direction, current_frame)

	# Create AtlasTexture to show just this frame
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas = atlas.texture

	# Convert UV rect to pixel coordinates
	var tex_size: Vector2 = atlas.texture.get_size()
	atlas_tex.region = Rect2(
		uv_rect.position.x * tex_size.x,
		uv_rect.position.y * tex_size.y,
		uv_rect.size.x * tex_size.x,
		uv_rect.size.y * tex_size.y
	)

	sprite_preview.texture = atlas_tex

	# Update labels
	direction_label.text = DIRECTION_NAMES[current_direction]
	var frame_count: int = atlas.get_animation_frame_count(current_animation)
	# Show frame info and actual animation key (helpful when "death" maps to "dead")
	frame_label.text = "Frame %d/%d [%s]" % [current_frame + 1, frame_count, current_animation]


func _on_unit_selected(index: int) -> void:
	if index >= 0 and index < regiment_paths.size():
		_load_regiment(regiment_paths[index])


func _on_direction_pressed(dir: int) -> void:
	current_direction = dir
	current_frame = 0
	anim_timer = 0.0
	_update_sprite_preview()


func _on_animation_selected(index: int) -> void:
	var display_name := anim_dropdown.get_item_text(index)
	# Map display name to actual atlas key
	current_animation = anim_key_map.get(display_name, display_name)
	current_frame = 0
	anim_timer = 0.0
	_update_sprite_preview()


func _on_play_pressed() -> void:
	is_playing = not is_playing
	play_button.text = "Stop" if is_playing else "Play"


func _on_color_changed(color: Color) -> void:
	# Apply modulate color to sprite preview
	sprite_preview.modulate = color


func _on_reset_color() -> void:
	color_picker.color = Color.WHITE
	sprite_preview.modulate = Color.WHITE


func _on_faction_color_changed(color: Color) -> void:
	if current_regiment:
		current_regiment.faction_color = color


func _on_save_pressed() -> void:
	if not current_regiment:
		status_label.text = "No regiment loaded"
		return

	# Update regiment data from UI
	current_regiment.regiment_name = prop_name.text
	current_regiment.faction = prop_faction.text
	current_regiment.unit_type = prop_unit_type.get_selected_id()
	current_regiment.personality = prop_personality.get_selected_id()
	current_regiment.weapon_class = prop_weapon_class.get_selected_id()
	current_regiment.attack = int(prop_attack.value)
	current_regiment.defense = int(prop_defense.value)
	current_regiment.weapon_skill = int(prop_weapon_skill.value)
	current_regiment.ballistic_skill = int(prop_ballistic_skill.value)
	current_regiment.strength = int(prop_strength.value)
	current_regiment.armor = int(prop_armor.value)
	current_regiment.max_soldiers = int(prop_max_soldiers.value)
	current_regiment.current_soldiers = int(prop_max_soldiers.value)  # Sync current to max
	current_regiment.base_morale = prop_base_morale.value
	current_regiment.max_ammo = int(prop_max_ammo.value)
	current_regiment.current_ammo = int(prop_max_ammo.value)  # Sync current to max
	current_regiment.range_distance = prop_range.value
	current_regiment.walk_speed = prop_walk_speed.value
	current_regiment.run_speed = prop_run_speed.value
	current_regiment.charge_speed = prop_charge_speed.value
	current_regiment.charge_bonus = int(prop_charge_bonus.value)
	current_regiment.mass = prop_mass.value
	current_regiment.is_elite = prop_is_elite.button_pressed
	current_regiment.faction_color = faction_color_picker.color

	# Save the resource
	var path := current_regiment.resource_path
	var err := ResourceSaver.save(current_regiment, path)
	if err == OK:
		status_label.text = "Saved: " + path.get_file()
	else:
		status_label.text = "Save failed! Error: " + str(err)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT:
				current_direction = (current_direction - 1 + 8) % 8
				_update_sprite_preview()
			KEY_RIGHT:
				current_direction = (current_direction + 1) % 8
				_update_sprite_preview()
			KEY_UP:
				var idx := anim_dropdown.selected - 1
				if idx >= 0:
					anim_dropdown.select(idx)
					_on_animation_selected(idx)
			KEY_DOWN:
				var idx := anim_dropdown.selected + 1
				if idx < anim_dropdown.item_count:
					anim_dropdown.select(idx)
					_on_animation_selected(idx)
			KEY_SPACE:
				_on_play_pressed()
