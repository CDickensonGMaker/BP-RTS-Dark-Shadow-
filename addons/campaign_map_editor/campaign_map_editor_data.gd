@tool
class_name CampaignMapEditorData
extends RefCounted
## Data structures for the Campaign Map Editor


## Terrain types matching RegionData.TerrainType
const TERRAIN_VALUES: Array[String] = [
	"plains", "forest", "hills", "mountains", "desert", "swamp", "coast"
]

## Region colors by terrain type for rendering
const TERRAIN_COLORS: Dictionary = {
	"plains": Color(0.55, 0.70, 0.38),
	"forest": Color(0.24, 0.42, 0.19),
	"hills": Color(0.6, 0.5, 0.4),
	"mountains": Color(0.4, 0.4, 0.45),
	"desert": Color(0.83, 0.72, 0.59),
	"swamp": Color(0.18, 0.29, 0.16),
	"coast": Color(0.3, 0.5, 0.75)
}

## Faction colors for ownership display
const FACTION_COLORS: Dictionary = {
	"": Color(0.5, 0.5, 0.5, 0.5),  # Neutral
	"player": Color(0.2, 0.4, 0.8, 0.7),
	"empire": Color(0.8, 0.2, 0.2, 0.7),
	"orcs": Color(0.2, 0.6, 0.2, 0.7),
	"undead": Color(0.4, 0.2, 0.5, 0.7),
	"dwarves": Color(0.7, 0.5, 0.2, 0.7),
}

## POI types for settlements/locations
const POI_VALUES: Array[String] = [
	"capital", "city", "town", "village", "fortress",
	"dungeon", "camp", "ruins", "landmark"
]

const POI_ICONS: Dictionary = {
	"capital": "K",
	"city": "C",
	"town": "T",
	"village": "v",
	"fortress": "F",
	"dungeon": "D",
	"camp": "^",
	"ruins": "R",
	"landmark": "L"
}

const POI_COLORS: Dictionary = {
	"capital": Color(1.0, 0.85, 0.2),
	"city": Color(0.95, 0.75, 0.3),
	"town": Color(0.9, 0.7, 0.4),
	"village": Color(0.8, 0.65, 0.45),
	"fortress": Color(0.5, 0.5, 0.6),
	"dungeon": Color(0.6, 0.2, 0.2),
	"camp": Color(0.6, 0.4, 0.3),
	"ruins": Color(0.5, 0.45, 0.4),
	"landmark": Color(0.7, 0.7, 0.3)
}


## Map state container - the actual data being edited
class MapState:
	var version: int = 1
	var grid_width: int = 32   # Number of columns (finer detail grid)
	var grid_height: int = 18  # Number of rows (2x resolution of original)
	var map_size: Vector2 = Vector2(3053, 2160)  # Actual map image size

	## Cell data: index -> region_id
	var cell_regions: Array = []  # Array of String (region_id or "")

	## Region definitions
	var regions: Dictionary = {}  # region_id -> RegionInfo

	## POI data
	var poi_data: Dictionary = {}  # String(index) -> POI info dict


	func _init() -> void:
		_init_cells()


	func _init_cells() -> void:
		var total_cells: int = grid_width * grid_height
		cell_regions.clear()
		cell_regions.resize(total_cells)
		for i: int in range(total_cells):
			cell_regions[i] = ""


	func get_cell_size() -> Vector2:
		return Vector2(map_size.x / float(grid_width), map_size.y / float(grid_height))


	func get_cell_index(x: int, y: int) -> int:
		return y * grid_width + x


	func get_cell_coords(index: int) -> Vector2i:
		return Vector2i(index % grid_width, index / grid_width)


	func set_cell_region(x: int, y: int, region_id: String) -> void:
		if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
			return
		var index: int = get_cell_index(x, y)
		if index >= 0 and index < cell_regions.size():
			cell_regions[index] = region_id


	func get_cell_region(x: int, y: int) -> String:
		if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
			return ""
		var index: int = get_cell_index(x, y)
		if index >= 0 and index < cell_regions.size():
			return cell_regions[index]
		return ""


	func add_region(region_id: String) -> void:
		if not regions.has(region_id):
			regions[region_id] = RegionInfo.new(region_id)


	func get_region(region_id: String) -> RegionInfo:
		if regions.has(region_id):
			return regions[region_id]
		return null


	func get_all_region_ids() -> Array[String]:
		var ids: Array[String] = []
		for id: String in regions:
			ids.append(id)
		ids.sort()
		return ids


	func clear_all() -> void:
		_init_cells()
		regions.clear()
		poi_data.clear()


	func to_dict() -> Dictionary:
		var regions_dict: Dictionary = {}
		for region_id: String in regions:
			var info: RegionInfo = regions[region_id]
			regions_dict[region_id] = info.to_dict()

		return {
			"version": version,
			"grid": {"width": grid_width, "height": grid_height},
			"map_size": {"x": map_size.x, "y": map_size.y},
			"cell_regions": cell_regions.duplicate(),
			"regions": regions_dict,
			"poi_data": poi_data.duplicate(true)
		}


	func from_dict(data: Dictionary) -> void:
		version = data.get("version", 1)
		var grid_data: Dictionary = data.get("grid", {})
		grid_width = grid_data.get("width", 32)
		grid_height = grid_data.get("height", 18)
		var size_data: Dictionary = data.get("map_size", {})
		map_size = Vector2(size_data.get("x", 3053), size_data.get("y", 2160))

		_init_cells()

		var loaded_cells: Array = data.get("cell_regions", [])
		for i: int in range(mini(loaded_cells.size(), cell_regions.size())):
			cell_regions[i] = loaded_cells[i]

		regions.clear()
		var loaded_regions: Dictionary = data.get("regions", {})
		for region_id: String in loaded_regions:
			var info := RegionInfo.new(region_id)
			info.from_dict(loaded_regions[region_id])
			regions[region_id] = info

		poi_data = data.get("poi_data", {}).duplicate(true)


## Region information
class RegionInfo:
	var region_id: String = ""
	var region_name: String = ""
	var terrain_type: String = "plains"
	var owner_faction: String = ""
	var is_passable: bool = true
	var capital_settlement_id: String = ""  # Regional capital
	var minor_settlement_ids: Array[String] = []  # Optional minor settlements
	var region_color: Color = Color(0.5, 0.5, 0.5, 0.3)


	func _init(id: String = "") -> void:
		region_id = id
		region_name = id.capitalize().replace("_", " ")
		region_color = TERRAIN_COLORS.get(terrain_type, Color(0.5, 0.5, 0.5, 0.3))


	func to_dict() -> Dictionary:
		return {
			"region_id": region_id,
			"region_name": region_name,
			"terrain_type": terrain_type,
			"owner_faction": owner_faction,
			"is_passable": is_passable,
			"capital_settlement_id": capital_settlement_id,
			"minor_settlement_ids": minor_settlement_ids.duplicate(),
			"region_color": {"r": region_color.r, "g": region_color.g, "b": region_color.b, "a": region_color.a}
		}


	func from_dict(data: Dictionary) -> void:
		region_id = data.get("region_id", "")
		region_name = data.get("region_name", region_id.capitalize().replace("_", " "))
		terrain_type = data.get("terrain_type", "plains")
		owner_faction = data.get("owner_faction", "")
		is_passable = data.get("is_passable", true)
		capital_settlement_id = data.get("capital_settlement_id", "")
		var sids: Array = data.get("minor_settlement_ids", [])
		minor_settlement_ids.clear()
		for sid: Variant in sids:
			minor_settlement_ids.append(str(sid))
		var col: Dictionary = data.get("region_color", {})
		region_color = Color(col.get("r", 0.5), col.get("g", 0.5), col.get("b", 0.5), col.get("a", 0.3))


## Editor state container - UI/tool state
class EditorState:
	var current_region_id: String = ""
	var current_brush: String = "region"  # "region", "terrain", "poi", "erase"
	var brush_size: int = 1
	var is_eraser: bool = false
	var selected_poi_index: int = -1
	var selected_cell: Vector2i = Vector2i(-1, -1)
	var zoom: float = 0.5
	var pan_offset: Vector2 = Vector2.ZERO
	var show_grid: bool = true
	var show_regions: bool = true
	var show_labels: bool = true
	var show_pois: bool = true
	var color_by: String = "terrain"  # "terrain", "owner", "region"
