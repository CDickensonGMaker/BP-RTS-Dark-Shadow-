# Renders campaign map regions with borders, fills, and labels.
# Add as child of campaign map to visualize RegionData polygons.
class_name RegionRenderer
extends Node2D


## All regions to render
var regions: Array[RegionData] = []

## Visual settings
@export var show_fills: bool = true
@export var show_borders: bool = true
@export var show_labels: bool = true
@export var border_width: float = 3.0
@export var hover_highlight: bool = true

## Faction colors (faction_id -> Color)
var faction_colors: Dictionary = {
	"player": Color(0.2, 0.5, 0.8, 0.3),      # Blue
	"enemy": Color(0.8, 0.2, 0.2, 0.3),       # Red
	"neutral": Color(0.5, 0.5, 0.5, 0.2),     # Gray
	"orc": Color(0.2, 0.6, 0.2, 0.3),         # Green
	"undead": Color(0.4, 0.2, 0.5, 0.3),      # Purple
}

## Internal state
var _region_polygons: Dictionary = {}  # region_id -> Polygon2D
var _region_borders: Dictionary = {}   # region_id -> Line2D
var _region_labels: Dictionary = {}    # region_id -> Label
var _hovered_region: RegionData = null

## Signals
signal region_clicked(region: RegionData)
signal region_hovered(region: RegionData)


func _ready() -> void:
	# Connect to campaign signals
	if CampaignSignals:
		CampaignSignals.region_captured.connect(_on_region_captured)


func setup_regions(region_list: Array) -> void:
	## Initialize renderer with region data
	regions.clear()
	for region in region_list:
		if region is RegionData:
			regions.append(region)

	_create_visuals()


func _create_visuals() -> void:
	## Create visual nodes for all regions
	# Clear existing
	for child in get_children():
		child.queue_free()
	_region_polygons.clear()
	_region_borders.clear()
	_region_labels.clear()

	for region in regions:
		if region.map_polygon.size() < 3:
			continue

		# Create fill polygon
		if show_fills:
			var polygon := Polygon2D.new()
			polygon.polygon = region.map_polygon
			polygon.color = _get_region_color(region)
			polygon.z_index = 1
			add_child(polygon)
			_region_polygons[region.region_id] = polygon

		# Create border
		if show_borders:
			var border := Line2D.new()
			# Close the polygon
			var points := region.map_polygon.duplicate()
			if points.size() > 0:
				points.append(points[0])
			border.points = points
			border.width = border_width
			border.default_color = _get_border_color(region)
			border.z_index = 2
			add_child(border)
			_region_borders[region.region_id] = border

		# Create label
		if show_labels:
			var label := Label.new()
			label.text = region.region_name
			label.position = region.map_center - Vector2(50, 10)
			label.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05, 0.9))
			label.add_theme_color_override("font_shadow_color", Color(0.9, 0.85, 0.7, 0.5))
			label.add_theme_constant_override("shadow_offset_x", 1)
			label.add_theme_constant_override("shadow_offset_y", 1)
			label.z_index = 3
			add_child(label)
			_region_labels[region.region_id] = label


func _get_region_color(region: RegionData) -> Color:
	## Get fill color based on ownership
	if region.region_color != Color(0.5, 0.5, 0.5, 0.3):
		# Use custom color if set
		return region.region_color

	if region.owner_faction == "":
		return faction_colors.get("neutral", Color(0.5, 0.5, 0.5, 0.2))

	return faction_colors.get(region.owner_faction, region.region_color)


func _get_border_color(region: RegionData) -> Color:
	## Get border color based on terrain/ownership
	if region.border_color != Color(0.3, 0.3, 0.3, 1.0):
		return region.border_color

	# Terrain-based border colors
	match region.terrain_type:
		RegionData.TerrainType.FOREST:
			return Color(0.2, 0.4, 0.15, 0.8)
		RegionData.TerrainType.MOUNTAINS:
			return Color(0.4, 0.35, 0.3, 0.8)
		RegionData.TerrainType.DESERT:
			return Color(0.6, 0.5, 0.3, 0.8)
		RegionData.TerrainType.SWAMP:
			return Color(0.3, 0.4, 0.3, 0.8)
		_:
			return Color(0.3, 0.25, 0.2, 0.8)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var region := get_region_at(get_global_mouse_position())
			if region:
				region_clicked.emit(region)
				CampaignSignals.region_clicked.emit(self)  # For compatibility

	if event is InputEventMouseMotion and hover_highlight:
		var region := get_region_at(get_global_mouse_position())
		if region != _hovered_region:
			_set_hovered_region(region)


func get_region_at(world_pos: Vector2) -> RegionData:
	## Find which region contains the given point
	for region in regions:
		if region.contains_point(world_pos):
			return region
	return null


func _set_hovered_region(region: RegionData) -> void:
	## Update hover state
	# Unhighlight previous
	if _hovered_region and _region_polygons.has(_hovered_region.region_id):
		var poly: Polygon2D = _region_polygons[_hovered_region.region_id]
		poly.color = _get_region_color(_hovered_region)

	_hovered_region = region

	# Highlight new
	if region and _region_polygons.has(region.region_id):
		var poly: Polygon2D = _region_polygons[region.region_id]
		poly.color = _get_region_color(region).lightened(0.2)
		region_hovered.emit(region)


func _on_region_captured(region_resource: Resource, new_owner: String) -> void:
	## Update visual when region changes hands
	if region_resource is RegionData:
		region_resource.owner_faction = new_owner

		if _region_polygons.has(region_resource.region_id):
			var poly: Polygon2D = _region_polygons[region_resource.region_id]
			poly.color = _get_region_color(region_resource)


func refresh_visuals() -> void:
	## Refresh all region visuals
	for region in regions:
		if _region_polygons.has(region.region_id):
			var poly: Polygon2D = _region_polygons[region.region_id]
			poly.color = _get_region_color(region)

		if _region_borders.has(region.region_id):
			var border: Line2D = _region_borders[region.region_id]
			border.default_color = _get_border_color(region)
