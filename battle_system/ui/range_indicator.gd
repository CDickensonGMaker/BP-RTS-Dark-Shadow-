class_name RangeIndicator
extends Node3D

const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")

## Visual indicator for unit range cones and circles.
## Shows firing arcs for ranged units and aura radii for generals/casters.
## Attaches as child of Regiment, responds to selection signals.

# Indicator type determines shape
enum IndicatorType {
	CONE,    # Directional arc for ranged units (archers, crossbows, etc.)
	CIRCLE,  # Full radius for AOE abilities (general auras, spell ranges)
	ARC,     # Partial arc for limited rotation weapons
}

# Ranged weapon classes that show cone indicators
const RANGED_WEAPON_CLASSES := [
	RegimentData.WeaponClass.BOW,
	RegimentData.WeaponClass.CROSSBOW,
	RegimentData.WeaponClass.HANDGUN,
	RegimentData.WeaponClass.THROWN,
	RegimentData.WeaponClass.CANNON,
	RegimentData.WeaponClass.MORTAR,
	RegimentData.WeaponClass.WAR_MACHINE,
	RegimentData.WeaponClass.BREATH_FIRE,
	RegimentData.WeaponClass.BREATH_POISON,
	RegimentData.WeaponClass.MAGIC_MISSILE,
]

# Properties
@export var show_range: bool = false:
	set(value):
		show_range = value
		_update_visibility()

@export var range_distance: float = 40.0:
	set(value):
		range_distance = value
		_rebuild_mesh()

@export var cone_angle: float = 90.0:  # Degrees, full arc
	set(value):
		cone_angle = value
		_rebuild_mesh()

@export var indicator_type: IndicatorType = IndicatorType.CONE:
	set(value):
		indicator_type = value
		_rebuild_mesh()

@export var indicator_color: Color = Color(0.2, 0.5, 1.0, 0.3)  # Semi-transparent blue

# Visual settings
const GROUND_OFFSET: float = 0.1  # Slight offset to avoid z-fighting
const CONE_SEGMENTS: int = 32     # Smoothness of cone arc
const CIRCLE_SEGMENTS: int = 48   # Smoothness of circle
const LINE_WIDTH: float = 0.15    # Width of outline rings
const PLAYER_COLOR := Color(0.2, 0.5, 1.0, 0.3)   # Blue for player
const ENEMY_COLOR := Color(1.0, 0.2, 0.2, 0.3)    # Red for enemy
const AURA_COLOR_SUBTLE := Color(0.8, 0.7, 0.2, 0.15)  # Subtle gold for always-visible auras

# Spell range colors by effect type
const SPELL_COLOR_HEAL := Color(0.2, 0.8, 0.2, 0.3)    # Green for healing
const SPELL_COLOR_DAMAGE := Color(0.8, 0.2, 0.2, 0.3)  # Red for damage
const SPELL_COLOR_BUFF := Color(0.8, 0.8, 0.2, 0.3)    # Yellow for buffs

# Internal refs
var _regiment: Regiment = null
var _mesh_instance: MeshInstance3D = null
var _outline_mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _outline_material: StandardMaterial3D = null
var _current_facing: Vector3 = Vector3.FORWARD

# Spell range circles for heroes/generals
var _spell_ranges: Array[Dictionary] = []  # [{spell_id, range, color, mesh}]
var _show_spell_ranges: bool = false
var _always_show_aura: bool = false  # For generals with auras - always visible
var _is_selected: bool = false       # Track selection state for color changes


func _ready() -> void:
	# Create mesh instance for filled area
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "RangeIndicatorMesh"
	add_child(_mesh_instance)

	# Create mesh instance for outline
	_outline_mesh = MeshInstance3D.new()
	_outline_mesh.name = "RangeIndicatorOutline"
	add_child(_outline_mesh)

	# Create transparent material for fill
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = indicator_color
	_material.no_depth_test = false
	_mesh_instance.material_override = _material

	# Create outline material (slightly more opaque)
	_outline_material = StandardMaterial3D.new()
	_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_material.albedo_color = Color(indicator_color.r, indicator_color.g, indicator_color.b, 0.6)
	_outline_mesh.material_override = _outline_material

	# Start hidden
	visible = false

	# Connect to selection signals
	if BattleSignals:
		BattleSignals.regiment_selected.connect(_on_regiment_selected)
		BattleSignals.regiment_deselected.connect(_on_regiment_deselected)
		BattleSignals.selection_cleared.connect(_on_selection_cleared)


func _exit_tree() -> void:
	# Disconnect signals
	if BattleSignals:
		if BattleSignals.regiment_selected.is_connected(_on_regiment_selected):
			BattleSignals.regiment_selected.disconnect(_on_regiment_selected)
		if BattleSignals.regiment_deselected.is_connected(_on_regiment_deselected):
			BattleSignals.regiment_deselected.disconnect(_on_regiment_deselected)
		if BattleSignals.selection_cleared.is_connected(_on_selection_cleared):
			BattleSignals.selection_cleared.disconnect(_on_selection_cleared)


func _process(_delta: float) -> void:
	# Update facing for cone indicators
	if visible and indicator_type == IndicatorType.CONE and _regiment:
		var new_facing: Vector3 = _regiment.get_facing_direction()
		if new_facing.distance_squared_to(_current_facing) > 0.01:
			update_facing(new_facing)


## Setup the indicator based on regiment data.
## Reads range from regiment.data, determines type, sets color.
func setup_for_regiment(regiment: Regiment) -> void:
	if not regiment or not regiment.data:
		push_warning("RangeIndicator: Invalid regiment or missing data")
		return

	_regiment = regiment

	# Read range distance from regiment data
	range_distance = regiment.data.range_distance if regiment.data.range_distance > 0 else 40.0

	# Determine indicator type based on unit type and weapon class
	if regiment.data.unit_type == UnitType.Type.GENERAL:
		# Generals show aura circle if they have an aura
		if regiment.data.has_aura:
			indicator_type = IndicatorType.CIRCLE
			range_distance = regiment.data.aura_radius
			_always_show_aura = true  # Auras always visible (Phase 6.5)
		else:
			# Non-aura generals might have magic attacks
			if regiment.data.weapon_class in RANGED_WEAPON_CLASSES:
				indicator_type = IndicatorType.CONE
				cone_angle = 60.0  # Narrower for magic missiles
			else:
				# Melee general - no range indicator
				indicator_type = IndicatorType.CIRCLE
				range_distance = 0.0
	elif regiment.data.weapon_class in RANGED_WEAPON_CLASSES:
		# Ranged units show cone
		indicator_type = IndicatorType.CONE
		# Set cone angle based on weapon type
		match regiment.data.weapon_class:
			RegimentData.WeaponClass.BOW:
				cone_angle = 120.0  # Wide arc for archers
			RegimentData.WeaponClass.CROSSBOW:
				cone_angle = 90.0   # Medium arc
			RegimentData.WeaponClass.HANDGUN:
				cone_angle = 60.0   # Narrow for accurate fire
			RegimentData.WeaponClass.CANNON, RegimentData.WeaponClass.MORTAR:
				cone_angle = 45.0   # Very narrow for artillery
			RegimentData.WeaponClass.BREATH_FIRE, RegimentData.WeaponClass.BREATH_POISON:
				cone_angle = 90.0   # Breath weapon cone
			_:
				cone_angle = 90.0   # Default
	else:
		# Melee units - no range indicator needed
		indicator_type = IndicatorType.CIRCLE
		range_distance = 0.0

	# Set color based on faction
	if regiment.is_player_controlled:
		indicator_color = PLAYER_COLOR
	else:
		indicator_color = ENEMY_COLOR

	_update_material_color()
	_rebuild_mesh()

	# Initialize facing
	_current_facing = regiment.get_facing_direction()
	update_facing(_current_facing)

	# Add spell range circles for generals/heroes
	if regiment.data.unit_type == UnitType.Type.GENERAL:
		_setup_spell_ranges(regiment)

	# Show aura immediately if always-visible (Phase 6.5)
	if _always_show_aura:
		_set_aura_subtle_color()
		_update_visibility()


## Show the range indicator.
func show_indicator() -> void:
	show_range = true


## Hide the range indicator.
func hide_indicator() -> void:
	show_range = false


## Update the facing direction for cone indicators.
func update_facing(direction: Vector3) -> void:
	if indicator_type != IndicatorType.CONE:
		return

	direction.y = 0
	if direction.length_squared() < 0.001:
		return

	_current_facing = direction.normalized()

	# Use WorldCompass for consistent angle calculation
	# This aligns the LOS cone with sprite direction (snapped to 8 directions)
	var dir_index := WorldCompassScript.direction_from_vector(_current_facing)
	var angle: float = WorldCompassScript.angle_from_direction(dir_index)
	rotation.y = angle


## Get the current indicator type.
func get_indicator_type() -> IndicatorType:
	return indicator_type


## Check if this indicator should be visible (has valid range).
func has_valid_range() -> bool:
	return range_distance > 0.0


## Add a spell range circle indicator.
## Creates a colored circle at the specified range distance for spell visualization.
func add_spell_range(spell_id: String, range_dist: float, color: Color) -> void:
	var mesh_instance := _create_circle_mesh(range_dist, color)
	mesh_instance.visible = _show_spell_ranges
	add_child(mesh_instance)
	_spell_ranges.append({
		"spell_id": spell_id,
		"range": range_dist,
		"color": color,
		"mesh": mesh_instance
	})


## Toggle visibility of all spell range circles.
func show_spell_ranges(show: bool) -> void:
	_show_spell_ranges = show
	for spell_data in _spell_ranges:
		spell_data.mesh.visible = show


## Clear all spell range circles.
func clear_spell_ranges() -> void:
	for spell_data in _spell_ranges:
		if is_instance_valid(spell_data.mesh):
			spell_data.mesh.queue_free()
	_spell_ranges.clear()


# --- PRIVATE METHODS ---

## Create a standalone circle mesh instance with specified range and color.
## Used for spell range circles that are separate from the main indicator.
func _create_circle_mesh(radius: float, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "SpellRangeCircle"

	# Create material
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	mat.no_depth_test = false
	mesh_instance.material_override = mat

	# Build circle mesh
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step: float = TAU / float(CIRCLE_SEGMENTS)
	var center := Vector3(0, GROUND_OFFSET, 0)

	# Build triangle fan from center
	for i in CIRCLE_SEGMENTS:
		var angle1: float = step * i
		var angle2: float = step * (i + 1)

		var p1 := Vector3(sin(angle1) * radius, GROUND_OFFSET, cos(angle1) * radius)
		var p2 := Vector3(sin(angle2) * radius, GROUND_OFFSET, cos(angle2) * radius)

		surface.add_vertex(center)
		surface.add_vertex(p1)
		surface.add_vertex(p2)

	surface.generate_normals()
	mesh = surface.commit(mesh)
	mesh_instance.mesh = mesh

	return mesh_instance


func _setup_spell_ranges(regiment: Regiment) -> void:
	## Setup spell range circles for a regiment (typically generals/heroes).
	## Gets spells from abilities and creates colored circles based on effect type.
	clear_spell_ranges()

	# Get spells from abilities manager if available
	if not regiment.abilities:
		return

	var spells: Array[SpellData] = regiment.abilities.get_available_spells()
	for spell in spells:
		if not spell:
			continue

		# Determine color based on effect type
		var spell_color: Color
		match spell.effect_type:
			SpellData.EffectType.HEAL:
				spell_color = SPELL_COLOR_HEAL
			SpellData.EffectType.DAMAGE:
				spell_color = SPELL_COLOR_DAMAGE
			SpellData.EffectType.BUFF:
				spell_color = SPELL_COLOR_BUFF
			SpellData.EffectType.DEBUFF:
				spell_color = SPELL_COLOR_DAMAGE  # Debuffs use damage color
			_:
				spell_color = SPELL_COLOR_BUFF  # Default to buff color

		# Add spell range circle
		add_spell_range(spell.id, spell.range_distance, spell_color)


func _update_visibility() -> void:
	# Always-show auras are visible even when not selected
	visible = (show_range or _always_show_aura) and has_valid_range()


func _update_material_color() -> void:
	if _material:
		_material.albedo_color = indicator_color
	if _outline_material:
		_outline_material.albedo_color = Color(
			indicator_color.r,
			indicator_color.g,
			indicator_color.b,
			minf(indicator_color.a * 2.0, 0.8)
		)


func _rebuild_mesh() -> void:
	if not _mesh_instance or not _outline_mesh:
		return

	if range_distance <= 0:
		_mesh_instance.mesh = null
		_outline_mesh.mesh = null
		return

	match indicator_type:
		IndicatorType.CONE:
			_build_cone_mesh()
		IndicatorType.CIRCLE:
			_build_circle_mesh()
		IndicatorType.ARC:
			_build_arc_mesh()


func _build_cone_mesh() -> void:
	## Build a cone/triangle fan mesh for directional range.
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Convert angle to radians (half angle for each side)
	var half_angle: float = deg_to_rad(cone_angle / 2.0)
	var step: float = cone_angle / float(CONE_SEGMENTS)

	# Center point (origin)
	var center := Vector3(0, GROUND_OFFSET, 0)

	# Build triangle fan from center
	for i in CONE_SEGMENTS:
		var angle1: float = deg_to_rad(-cone_angle / 2.0 + step * i)
		var angle2: float = deg_to_rad(-cone_angle / 2.0 + step * (i + 1))

		# Points on arc (cone points toward +Z)
		var p1 := Vector3(sin(angle1) * range_distance, GROUND_OFFSET, cos(angle1) * range_distance)
		var p2 := Vector3(sin(angle2) * range_distance, GROUND_OFFSET, cos(angle2) * range_distance)

		# Add triangle (center, p1, p2)
		surface.add_vertex(center)
		surface.add_vertex(p1)
		surface.add_vertex(p2)

	surface.generate_normals()
	mesh = surface.commit(mesh)
	_mesh_instance.mesh = mesh

	# Build outline
	_build_cone_outline()


func _build_cone_outline() -> void:
	## Build outline for the cone edge.
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var half_angle: float = deg_to_rad(cone_angle / 2.0)
	var step: float = cone_angle / float(CONE_SEGMENTS)

	# Arc outline (thick line as quad strip)
	for i in CONE_SEGMENTS:
		var angle1: float = deg_to_rad(-cone_angle / 2.0 + step * i)
		var angle2: float = deg_to_rad(-cone_angle / 2.0 + step * (i + 1))

		var inner_dist: float = range_distance - LINE_WIDTH
		var outer_dist: float = range_distance

		var inner1 := Vector3(sin(angle1) * inner_dist, GROUND_OFFSET + 0.01, cos(angle1) * inner_dist)
		var outer1 := Vector3(sin(angle1) * outer_dist, GROUND_OFFSET + 0.01, cos(angle1) * outer_dist)
		var inner2 := Vector3(sin(angle2) * inner_dist, GROUND_OFFSET + 0.01, cos(angle2) * inner_dist)
		var outer2 := Vector3(sin(angle2) * outer_dist, GROUND_OFFSET + 0.01, cos(angle2) * outer_dist)

		# Two triangles for quad
		surface.add_vertex(inner1)
		surface.add_vertex(outer1)
		surface.add_vertex(inner2)

		surface.add_vertex(inner2)
		surface.add_vertex(outer1)
		surface.add_vertex(outer2)

	# Side edges (from center to arc edges)
	var left_angle: float = deg_to_rad(-cone_angle / 2.0)
	var right_angle: float = deg_to_rad(cone_angle / 2.0)

	# Left edge
	_add_line_quad(surface,
		Vector3.ZERO,
		Vector3(sin(left_angle) * range_distance, 0, cos(left_angle) * range_distance),
		LINE_WIDTH * 0.5
	)

	# Right edge
	_add_line_quad(surface,
		Vector3.ZERO,
		Vector3(sin(right_angle) * range_distance, 0, cos(right_angle) * range_distance),
		LINE_WIDTH * 0.5
	)

	surface.generate_normals()
	mesh = surface.commit(mesh)
	_outline_mesh.mesh = mesh


func _build_circle_mesh() -> void:
	## Build a circle mesh for AOE range.
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step: float = TAU / float(CIRCLE_SEGMENTS)
	var center := Vector3(0, GROUND_OFFSET, 0)

	# Build triangle fan from center
	for i in CIRCLE_SEGMENTS:
		var angle1: float = step * i
		var angle2: float = step * (i + 1)

		var p1 := Vector3(sin(angle1) * range_distance, GROUND_OFFSET, cos(angle1) * range_distance)
		var p2 := Vector3(sin(angle2) * range_distance, GROUND_OFFSET, cos(angle2) * range_distance)

		surface.add_vertex(center)
		surface.add_vertex(p1)
		surface.add_vertex(p2)

	surface.generate_normals()
	mesh = surface.commit(mesh)
	_mesh_instance.mesh = mesh

	# Build outline ring
	_build_circle_outline()


func _build_circle_outline() -> void:
	## Build outline ring for the circle.
	var mesh := ArrayMesh.new()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)

	var step: float = TAU / float(CIRCLE_SEGMENTS)
	var inner_dist: float = range_distance - LINE_WIDTH
	var outer_dist: float = range_distance

	for i in CIRCLE_SEGMENTS:
		var angle1: float = step * i
		var angle2: float = step * (i + 1)

		var inner1 := Vector3(sin(angle1) * inner_dist, GROUND_OFFSET + 0.01, cos(angle1) * inner_dist)
		var outer1 := Vector3(sin(angle1) * outer_dist, GROUND_OFFSET + 0.01, cos(angle1) * outer_dist)
		var inner2 := Vector3(sin(angle2) * inner_dist, GROUND_OFFSET + 0.01, cos(angle2) * inner_dist)
		var outer2 := Vector3(sin(angle2) * outer_dist, GROUND_OFFSET + 0.01, cos(angle2) * outer_dist)

		# Two triangles for quad
		surface.add_vertex(inner1)
		surface.add_vertex(outer1)
		surface.add_vertex(inner2)

		surface.add_vertex(inner2)
		surface.add_vertex(outer1)
		surface.add_vertex(outer2)

	surface.generate_normals()
	mesh = surface.commit(mesh)
	_outline_mesh.mesh = mesh


func _build_arc_mesh() -> void:
	## Build an arc mesh (partial circle) for limited rotation weapons.
	## Similar to cone but without the side lines.
	_build_cone_mesh()  # Same geometry, different styling if needed


func _add_line_quad(surface: SurfaceTool, from: Vector3, to: Vector3, width: float) -> void:
	## Add a quad representing a thick line from 'from' to 'to'.
	var dir: Vector3 = (to - from).normalized()
	var perp := Vector3(-dir.z, 0, dir.x) * width  # Perpendicular in XZ plane

	var y: float = GROUND_OFFSET + 0.01
	var p1 := from + perp + Vector3(0, y, 0)
	var p2 := from - perp + Vector3(0, y, 0)
	var p3 := to + perp + Vector3(0, y, 0)
	var p4 := to - perp + Vector3(0, y, 0)

	# Two triangles for quad
	surface.add_vertex(p1)
	surface.add_vertex(p2)
	surface.add_vertex(p3)

	surface.add_vertex(p3)
	surface.add_vertex(p2)
	surface.add_vertex(p4)


# --- SIGNAL HANDLERS ---

func _on_regiment_selected(regiment: Regiment) -> void:
	if regiment == _regiment:
		_is_selected = true
		show_indicator()
		# Restore full color when selected
		_update_material_color()


func _on_regiment_deselected(regiment: Regiment) -> void:
	if regiment == _regiment:
		_is_selected = false
		if _always_show_aura:
			# Keep aura visible but use subtle color
			_set_aura_subtle_color()
		else:
			hide_indicator()


func _on_selection_cleared() -> void:
	_is_selected = false
	if _always_show_aura:
		# Keep aura visible but use subtle color
		_set_aura_subtle_color()
	else:
		hide_indicator()


func _set_aura_subtle_color() -> void:
	## Set the aura to subtle color when deselected (always-visible auras).
	if _material:
		_material.albedo_color = AURA_COLOR_SUBTLE
	if _outline_material:
		var outline_color: Color = AURA_COLOR_SUBTLE
		outline_color.a = minf(AURA_COLOR_SUBTLE.a + 0.1, 0.5)
		_outline_material.albedo_color = outline_color


# --- STATIC FACTORY ---

## Create and attach a range indicator to a regiment.
static func create_for_regiment(regiment: Regiment) -> RangeIndicator:
	var script: GDScript = load("res://battle_system/ui/range_indicator.gd")
	var indicator: RangeIndicator = script.new()
	indicator.name = "RangeIndicator"
	regiment.add_child(indicator)
	indicator.setup_for_regiment(regiment)
	return indicator
