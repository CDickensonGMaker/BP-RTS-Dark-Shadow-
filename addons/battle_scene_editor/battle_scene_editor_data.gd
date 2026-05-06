@tool
class_name BattleSceneEditorData
extends RefCounted
## Data structures for the Battle Scene Editor


## Terrain tile types
const TERRAIN_VALUES: Array[String] = [
	"grass", "dirt", "mud", "stone", "sand",
	"water_shallow", "water_deep",
	"forest_light", "forest_dense",
	"hill_low", "hill_high",
	"cliff", "road"
]

## Terrain colors for 2D preview
const TERRAIN_COLORS: Dictionary = {
	"grass": Color(0.35, 0.55, 0.25),
	"dirt": Color(0.55, 0.45, 0.35),
	"mud": Color(0.4, 0.35, 0.25),
	"stone": Color(0.5, 0.5, 0.52),
	"sand": Color(0.85, 0.78, 0.6),
	"water_shallow": Color(0.4, 0.55, 0.7),
	"water_deep": Color(0.2, 0.35, 0.6),
	"forest_light": Color(0.2, 0.4, 0.18),
	"forest_dense": Color(0.12, 0.28, 0.1),
	"hill_low": Color(0.5, 0.45, 0.35),
	"hill_high": Color(0.6, 0.55, 0.45),
	"cliff": Color(0.4, 0.38, 0.35),
	"road": Color(0.6, 0.55, 0.45)
}

## Terrain movement costs
const TERRAIN_MOVEMENT_COST: Dictionary = {
	"grass": 1.0,
	"dirt": 1.0,
	"mud": 1.5,
	"stone": 1.0,
	"sand": 1.2,
	"water_shallow": 2.0,
	"water_deep": -1.0,  # Impassable
	"forest_light": 1.3,
	"forest_dense": 1.8,
	"hill_low": 1.4,
	"hill_high": 1.8,
	"cliff": -1.0,  # Impassable
	"road": 0.8  # Faster
}

## Object types that can be placed
const OBJECT_VALUES: Array[String] = [
	"tree_small", "tree_large", "tree_dead",
	"rock_small", "rock_medium", "rock_large",
	"bush", "fence", "wall_section",
	"building_small", "building_large", "tower",
	"bridge", "gate",
	"deployment_player", "deployment_enemy",
	"objective_capture", "objective_defend", "objective_destroy"
]

## Object icons for 2D preview
const OBJECT_ICONS: Dictionary = {
	"tree_small": "t",
	"tree_large": "T",
	"tree_dead": "x",
	"rock_small": ".",
	"rock_medium": "o",
	"rock_large": "O",
	"bush": "*",
	"fence": "=",
	"wall_section": "#",
	"building_small": "b",
	"building_large": "B",
	"tower": "!",
	"bridge": "=",
	"gate": "G",
	"deployment_player": "P",
	"deployment_enemy": "E",
	"objective_capture": "C",
	"objective_defend": "D",
	"objective_destroy": "X"
}

const OBJECT_COLORS: Dictionary = {
	"tree_small": Color(0.2, 0.5, 0.2),
	"tree_large": Color(0.15, 0.4, 0.15),
	"tree_dead": Color(0.4, 0.35, 0.3),
	"rock_small": Color(0.5, 0.5, 0.5),
	"rock_medium": Color(0.45, 0.45, 0.45),
	"rock_large": Color(0.4, 0.4, 0.4),
	"bush": Color(0.3, 0.5, 0.25),
	"fence": Color(0.55, 0.45, 0.35),
	"wall_section": Color(0.5, 0.5, 0.52),
	"building_small": Color(0.6, 0.55, 0.45),
	"building_large": Color(0.55, 0.5, 0.4),
	"tower": Color(0.5, 0.48, 0.45),
	"bridge": Color(0.55, 0.5, 0.4),
	"gate": Color(0.5, 0.45, 0.4),
	"deployment_player": Color(0.2, 0.4, 0.8),
	"deployment_enemy": Color(0.8, 0.2, 0.2),
	"objective_capture": Color(1.0, 0.85, 0.2),
	"objective_defend": Color(0.2, 0.8, 0.2),
	"objective_destroy": Color(0.8, 0.4, 0.1)
}


## Battle map data
class BattleMapState:
	var version: int = 1
	var map_name: String = "Unnamed Battle"
	var map_id: String = ""
	var grid_width: int = 32   # Number of tiles
	var grid_height: int = 32
	var tile_size: float = 10.0  # World units per tile

	## Terrain grid
	var terrain_grid: Array = []  # Array of terrain type strings

	## Placed objects
	var objects: Array = []  # Array of ObjectData dicts

	## Deployment zones (rectangular areas)
	var player_deployment: Rect2 = Rect2(2, 2, 8, 6)
	var enemy_deployment: Rect2 = Rect2(22, 24, 8, 6)

	## Battle settings
	var time_of_day: String = "day"  # day, dawn, dusk, night
	var weather: String = "clear"    # clear, rain, fog, snow


	func _init() -> void:
		_init_terrain()


	func _init_terrain() -> void:
		var total: int = grid_width * grid_height
		terrain_grid.clear()
		terrain_grid.resize(total)
		for i: int in range(total):
			terrain_grid[i] = "grass"


	func resize(new_width: int, new_height: int) -> void:
		var old_terrain := terrain_grid.duplicate()
		var old_width := grid_width
		var old_height := grid_height

		grid_width = new_width
		grid_height = new_height
		_init_terrain()

		# Copy old data
		for y: int in range(mini(old_height, new_height)):
			for x: int in range(mini(old_width, new_width)):
				var old_idx: int = y * old_width + x
				var new_idx: int = y * new_width + x
				if old_idx < old_terrain.size():
					terrain_grid[new_idx] = old_terrain[old_idx]


	func get_cell_index(x: int, y: int) -> int:
		return y * grid_width + x


	func get_cell_coords(index: int) -> Vector2i:
		return Vector2i(index % grid_width, index / grid_width)


	func set_terrain(x: int, y: int, terrain: String) -> void:
		if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
			return
		var idx: int = get_cell_index(x, y)
		if idx >= 0 and idx < terrain_grid.size():
			terrain_grid[idx] = terrain


	func get_terrain(x: int, y: int) -> String:
		if x < 0 or x >= grid_width or y < 0 or y >= grid_height:
			return ""
		var idx: int = get_cell_index(x, y)
		if idx >= 0 and idx < terrain_grid.size():
			return terrain_grid[idx]
		return ""


	func add_object(obj_type: String, x: int, y: int, rotation: float = 0.0) -> void:
		objects.append({
			"type": obj_type,
			"x": x,
			"y": y,
			"rotation": rotation
		})


	func remove_object_at(x: int, y: int) -> bool:
		for i: int in range(objects.size() - 1, -1, -1):
			var obj: Dictionary = objects[i]
			if obj.get("x", -1) == x and obj.get("y", -1) == y:
				objects.remove_at(i)
				return true
		return false


	func get_objects_at(x: int, y: int) -> Array:
		var result: Array = []
		for obj: Dictionary in objects:
			if obj.get("x", -1) == x and obj.get("y", -1) == y:
				result.append(obj)
		return result


	func to_dict() -> Dictionary:
		return {
			"version": version,
			"map_name": map_name,
			"map_id": map_id,
			"grid": {"width": grid_width, "height": grid_height},
			"tile_size": tile_size,
			"terrain_grid": terrain_grid.duplicate(),
			"objects": objects.duplicate(true),
			"player_deployment": {"x": player_deployment.position.x, "y": player_deployment.position.y, "w": player_deployment.size.x, "h": player_deployment.size.y},
			"enemy_deployment": {"x": enemy_deployment.position.x, "y": enemy_deployment.position.y, "w": enemy_deployment.size.x, "h": enemy_deployment.size.y},
			"time_of_day": time_of_day,
			"weather": weather
		}


	func from_dict(data: Dictionary) -> void:
		version = data.get("version", 1)
		map_name = data.get("map_name", "Unnamed Battle")
		map_id = data.get("map_id", "")
		var grid_data: Dictionary = data.get("grid", {})
		grid_width = grid_data.get("width", 32)
		grid_height = grid_data.get("height", 32)
		tile_size = data.get("tile_size", 10.0)

		_init_terrain()
		var loaded_terrain: Array = data.get("terrain_grid", [])
		for i: int in range(mini(loaded_terrain.size(), terrain_grid.size())):
			terrain_grid[i] = loaded_terrain[i]

		objects = data.get("objects", []).duplicate(true)

		var pd: Dictionary = data.get("player_deployment", {})
		player_deployment = Rect2(pd.get("x", 2), pd.get("y", 2), pd.get("w", 8), pd.get("h", 6))
		var ed: Dictionary = data.get("enemy_deployment", {})
		enemy_deployment = Rect2(ed.get("x", 22), ed.get("y", 24), ed.get("w", 8), ed.get("h", 6))

		time_of_day = data.get("time_of_day", "day")
		weather = data.get("weather", "clear")


## Editor state
class EditorState:
	var current_tool: String = "terrain"  # terrain, object, deployment, erase
	var current_terrain: String = "grass"
	var current_object: String = "tree_small"
	var brush_size: int = 1
	var zoom: float = 1.0
	var pan_offset: Vector2 = Vector2.ZERO
	var show_grid: bool = true
	var show_deployment: bool = true
	var show_objects: bool = true
	var selected_object_index: int = -1
