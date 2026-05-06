# Renders settlement icons on the campaign map.
# Capitals are shown as larger crown icons, minors as smaller dots.
class_name SettlementRenderer
extends Node2D


## Settlement visual settings
const CAPITAL_SIZE := 24.0
const MINOR_SIZE := 12.0
const ICON_Z_INDEX := 15  # Above regions and fog

## Colors
const CAPITAL_COLOR := Color(1.0, 0.85, 0.2, 1.0)  # Gold
const CAPITAL_OUTLINE := Color(0.2, 0.15, 0.0, 1.0)  # Dark brown
const MINOR_COLOR := Color(0.85, 0.75, 0.55, 1.0)  # Tan
const MINOR_OUTLINE := Color(0.3, 0.25, 0.15, 1.0)  # Dark tan
const FORTRESS_COLOR := Color(0.6, 0.6, 0.65, 1.0)  # Stone gray

## Loaded settlements
var settlements: Array[SettlementData] = []
var settlement_icons: Dictionary = {}  # settlement_id -> Node2D

## Show labels
@export var show_labels: bool = true
@export var label_min_zoom: float = 0.4


func _ready() -> void:
	z_index = ICON_Z_INDEX


func load_settlements() -> void:
	## Load all settlement .tres files
	settlements.clear()
	var dir_path := "res://campaign_system/data/settlements/"
	var dir := DirAccess.open(dir_path)

	if not dir:
		push_warning("SettlementRenderer: Could not open settlements directory")
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres"):
			var settlement := load(dir_path + file_name)
			if settlement is SettlementData:
				settlements.append(settlement)
		file_name = dir.get_next()

	dir.list_dir_end()
	print("[SettlementRenderer] Loaded %d settlements" % settlements.size())

	_create_icons()


func _create_icons() -> void:
	## Create visual markers for all settlements
	# Clear existing
	for child in get_children():
		child.queue_free()
	settlement_icons.clear()

	for settlement in settlements:
		var icon := _create_settlement_icon(settlement)
		add_child(icon)
		settlement_icons[settlement.settlement_id] = icon


func _create_settlement_icon(settlement: SettlementData) -> Node2D:
	var icon := Node2D.new()
	icon.position = settlement.map_position
	icon.name = settlement.settlement_id

	if settlement.is_regional_capital:
		_add_capital_visuals(icon, settlement)
	else:
		_add_minor_visuals(icon, settlement)

	return icon


func _add_capital_visuals(icon: Node2D, settlement: SettlementData) -> void:
	## Capital: Castle/crown icon (larger)
	var size := CAPITAL_SIZE

	# Main shape - castle silhouette (simplified)
	var castle := Polygon2D.new()
	castle.polygon = PackedVector2Array([
		# Base
		Vector2(-size * 0.8, size * 0.4),
		Vector2(-size * 0.8, 0),
		# Left tower
		Vector2(-size * 0.6, 0),
		Vector2(-size * 0.6, -size * 0.5),
		Vector2(-size * 0.4, -size * 0.5),
		Vector2(-size * 0.4, -size * 0.2),
		# Center tower (tallest)
		Vector2(-size * 0.2, -size * 0.2),
		Vector2(-size * 0.2, -size * 0.7),
		Vector2(size * 0.2, -size * 0.7),
		Vector2(size * 0.2, -size * 0.2),
		# Right tower
		Vector2(size * 0.4, -size * 0.2),
		Vector2(size * 0.4, -size * 0.5),
		Vector2(size * 0.6, -size * 0.5),
		Vector2(size * 0.6, 0),
		# Base right
		Vector2(size * 0.8, 0),
		Vector2(size * 0.8, size * 0.4),
	])
	castle.color = _get_faction_color(settlement.owner_faction, CAPITAL_COLOR)
	icon.add_child(castle)

	# Outline
	var outline := Line2D.new()
	outline.points = castle.polygon
	outline.closed = true
	outline.width = 2.0
	outline.default_color = CAPITAL_OUTLINE
	icon.add_child(outline)

	# Star indicator on top
	var star := _create_star(Vector2(0, -size * 0.9), size * 0.25)
	star.color = Color(1.0, 0.95, 0.7, 1.0)
	icon.add_child(star)

	# Label
	if show_labels:
		var label := _create_label(settlement.settlement_name, Vector2(0, size * 0.7), true)
		icon.add_child(label)


func _add_minor_visuals(icon: Node2D, settlement: SettlementData) -> void:
	## Minor settlement: Small circle/house icon
	var size := MINOR_SIZE
	var color := _get_settlement_type_color(settlement.settlement_type)

	# Background circle
	var circle := _create_circle(Vector2.ZERO, size, color)
	icon.add_child(circle)

	# Outline
	var outline := _create_circle_outline(Vector2.ZERO, size, MINOR_OUTLINE, 1.5)
	icon.add_child(outline)

	# Type indicator (small shape inside)
	match settlement.settlement_type:
		SettlementData.SettlementType.FORTRESS:
			# Shield shape
			var shield := Polygon2D.new()
			shield.polygon = PackedVector2Array([
				Vector2(0, -size * 0.4),
				Vector2(size * 0.35, -size * 0.2),
				Vector2(size * 0.35, size * 0.1),
				Vector2(0, size * 0.4),
				Vector2(-size * 0.35, size * 0.1),
				Vector2(-size * 0.35, -size * 0.2),
			])
			shield.color = Color(0.3, 0.3, 0.35, 1.0)
			icon.add_child(shield)

		SettlementData.SettlementType.TOWN:
			# House shape
			var house := Polygon2D.new()
			house.polygon = PackedVector2Array([
				Vector2(0, -size * 0.4),
				Vector2(size * 0.3, 0),
				Vector2(size * 0.3, size * 0.3),
				Vector2(-size * 0.3, size * 0.3),
				Vector2(-size * 0.3, 0),
			])
			house.color = Color(0.5, 0.4, 0.3, 1.0)
			icon.add_child(house)

		SettlementData.SettlementType.VILLAGE:
			# Simple dot
			var dot := _create_circle(Vector2.ZERO, size * 0.35, Color(0.4, 0.35, 0.25, 1.0))
			icon.add_child(dot)

		_:
			# Default dot
			var dot := _create_circle(Vector2.ZERO, size * 0.3, Color(0.5, 0.45, 0.35, 1.0))
			icon.add_child(dot)

	# Label (smaller for minor settlements)
	if show_labels:
		var label := _create_label(settlement.settlement_name, Vector2(0, size * 1.2), false)
		icon.add_child(label)


func _get_faction_color(faction: String, default: Color) -> Color:
	match faction:
		"player": return Color(0.3, 0.5, 0.85, 1.0)  # Blue
		"undead": return Color(0.5, 0.3, 0.6, 1.0)  # Purple
		"orcs": return Color(0.3, 0.55, 0.25, 1.0)  # Green
		"empire": return Color(0.8, 0.25, 0.2, 1.0)  # Red
		_: return default


func _get_settlement_type_color(stype: SettlementData.SettlementType) -> Color:
	match stype:
		SettlementData.SettlementType.FORTRESS: return FORTRESS_COLOR
		SettlementData.SettlementType.TOWN: return MINOR_COLOR
		SettlementData.SettlementType.VILLAGE: return Color(0.75, 0.65, 0.5, 1.0)
		SettlementData.SettlementType.CITY: return Color(0.9, 0.8, 0.5, 1.0)
		_: return MINOR_COLOR


func _create_circle(center: Vector2, radius: float, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	var points: PackedVector2Array = []
	var segments := 16

	for i in range(segments):
		var angle := (float(i) / segments) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	poly.polygon = points
	poly.color = color
	return poly


func _create_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	var segments := 16

	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		line.add_point(center + Vector2(cos(angle), sin(angle)) * radius)

	line.width = width
	line.default_color = color
	return line


func _create_star(center: Vector2, size: float) -> Polygon2D:
	var poly := Polygon2D.new()
	var points: PackedVector2Array = []
	var outer_radius := size
	var inner_radius := size * 0.4
	var num_points := 5

	for i in range(num_points * 2):
		var angle := (float(i) / (num_points * 2)) * TAU - PI / 2
		var radius := outer_radius if i % 2 == 0 else inner_radius
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	poly.polygon = points
	return poly


func _create_label(text: String, offset: Vector2, is_capital: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = offset - Vector2(100, 0)  # Center offset
	label.custom_minimum_size.x = 200

	# Style
	label.add_theme_font_size_override("font_size", 14 if is_capital else 11)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

	return label


func get_settlement_at(world_pos: Vector2, radius: float = 30.0) -> SettlementData:
	## Find settlement near a world position
	for settlement in settlements:
		if settlement.map_position.distance_to(world_pos) < radius:
			return settlement
	return null


func highlight_settlement(settlement_id: String, highlight: bool = true) -> void:
	## Highlight a specific settlement
	if settlement_icons.has(settlement_id):
		var icon: Node2D = settlement_icons[settlement_id]
		if highlight:
			icon.modulate = Color(1.3, 1.3, 1.0, 1.0)
			icon.scale = Vector2(1.2, 1.2)
		else:
			icon.modulate = Color.WHITE
			icon.scale = Vector2.ONE
