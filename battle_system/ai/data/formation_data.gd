class_name FormationData
extends RefCounted

## Formation types and their properties.
## Used by CommanderAI to position soldiers within a regiment.

# =============================================================================
# ENUMS
# =============================================================================

enum Type {
	LINE,       # Wide formation, good for melee and ranged
	COLUMN,     # Deep formation, good for marching and charges
	WEDGE,      # Triangle, good for cavalry charges
	SQUARE,     # Defensive formation against cavalry
	SKIRMISH,   # Loose formation, good for ranged/avoiding fire
}

# =============================================================================
# FORMATION PROPERTIES
# =============================================================================

class FormationInfo:
	var type: Type
	var name: String
	var rows: int          # Number of rows
	var spacing: float     # Space between soldiers
	var depth_spacing: float  # Space between rows
	var frontage_mult: float  # Width multiplier (1.0 = standard)

	# Combat modifiers
	var attack_modifier: float = 1.0
	var defense_modifier: float = 1.0
	var charge_modifier: float = 1.0
	var ranged_modifier: float = 1.0
	var morale_modifier: float = 1.0

	# Movement
	var speed_modifier: float = 1.0
	var rotation_speed: float = 1.0

	func _init(p_type: Type, p_name: String) -> void:
		type = p_type
		name = p_name

# =============================================================================
# FORMATION DEFINITIONS
# =============================================================================

static var _formations: Dictionary = {}

static func _init_formations() -> void:
	if not _formations.is_empty():
		return

	# LINE - Standard battle formation
	var line: FormationInfo = FormationInfo.new(Type.LINE, "Line")
	line.rows = 3
	line.spacing = 1.2
	line.depth_spacing = 1.0
	line.frontage_mult = 1.0
	line.attack_modifier = 1.0
	line.defense_modifier = 1.0
	line.charge_modifier = 0.9
	line.ranged_modifier = 1.2
	line.morale_modifier = 1.0
	line.speed_modifier = 1.0
	line.rotation_speed = 0.8
	_formations[Type.LINE] = line

	# COLUMN - Marching/charging formation
	var column: FormationInfo = FormationInfo.new(Type.COLUMN, "Column")
	column.rows = 8
	column.spacing = 1.0
	column.depth_spacing = 0.8
	column.frontage_mult = 0.4
	column.attack_modifier = 0.7
	column.defense_modifier = 0.8
	column.charge_modifier = 1.3
	column.ranged_modifier = 0.5
	column.morale_modifier = 1.1
	column.speed_modifier = 1.15
	column.rotation_speed = 0.5
	_formations[Type.COLUMN] = column

	# WEDGE - Cavalry charge formation
	var wedge: FormationInfo = FormationInfo.new(Type.WEDGE, "Wedge")
	wedge.rows = 5
	wedge.spacing = 1.5
	wedge.depth_spacing = 1.2
	wedge.frontage_mult = 0.6
	wedge.attack_modifier = 1.2
	wedge.defense_modifier = 0.7
	wedge.charge_modifier = 1.5
	wedge.ranged_modifier = 0.4
	wedge.morale_modifier = 1.2
	wedge.speed_modifier = 1.1
	wedge.rotation_speed = 0.7
	_formations[Type.WEDGE] = wedge

	# SQUARE - Anti-cavalry defense
	var square: FormationInfo = FormationInfo.new(Type.SQUARE, "Square")
	square.rows = 4
	square.spacing = 0.8
	square.depth_spacing = 0.8
	square.frontage_mult = 1.0
	square.attack_modifier = 0.6
	square.defense_modifier = 1.5
	square.charge_modifier = 0.3
	square.ranged_modifier = 0.8
	square.morale_modifier = 1.3
	square.speed_modifier = 0.6
	square.rotation_speed = 0.3
	_formations[Type.SQUARE] = square

	# SKIRMISH - Loose ranged formation
	var skirmish: FormationInfo = FormationInfo.new(Type.SKIRMISH, "Skirmish")
	skirmish.rows = 2
	skirmish.spacing = 2.5
	skirmish.depth_spacing = 3.0
	skirmish.frontage_mult = 1.5
	skirmish.attack_modifier = 0.8
	skirmish.defense_modifier = 0.6
	skirmish.charge_modifier = 0.4
	skirmish.ranged_modifier = 1.3
	skirmish.morale_modifier = 0.9
	skirmish.speed_modifier = 1.2
	skirmish.rotation_speed = 1.2
	_formations[Type.SKIRMISH] = skirmish


static func get_formation(type: Type) -> FormationInfo:
	## Get formation info by type.
	_init_formations()
	return _formations.get(type)


static func get_all_formations() -> Array:
	## Get all formation types.
	_init_formations()
	return _formations.values()

# =============================================================================
# POSITION CALCULATION
# =============================================================================

static func calculate_positions(type: Type, soldier_count: int, center: Vector3, facing: Vector3) -> Array[Vector3]:
	## Calculate soldier positions for a formation.
	_init_formations()

	var info: FormationInfo = _formations.get(type)
	if not info:
		return []

	var positions: Array[Vector3] = []

	# Calculate formation dimensions
	var cols: int = ceili(float(soldier_count) / float(info.rows))
	var total_width: float = (cols - 1) * info.spacing * info.frontage_mult
	var total_depth: float = (info.rows - 1) * info.depth_spacing

	# Calculate basis vectors
	facing = facing.normalized()
	facing.y = 0
	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	# Special handling for wedge formation
	if type == Type.WEDGE:
		return _calculate_wedge_positions(soldier_count, center, facing, info)

	# Special handling for square formation
	if type == Type.SQUARE:
		return _calculate_square_positions(soldier_count, center, facing, info)

	# Standard grid formation (LINE, COLUMN, SKIRMISH)
	var soldier_idx: int = 0
	for row in info.rows:
		for col in cols:
			if soldier_idx >= soldier_count:
				break

			var x_offset: float = (col - (cols - 1) / 2.0) * info.spacing * info.frontage_mult
			var z_offset: float = (row - (info.rows - 1) / 2.0) * info.depth_spacing

			var pos: Vector3 = center + right * x_offset - facing * z_offset
			positions.append(pos)
			soldier_idx += 1

	return positions


static func _calculate_wedge_positions(soldier_count: int, center: Vector3, facing: Vector3, info: FormationInfo) -> Array[Vector3]:
	## Calculate positions for wedge formation.
	var positions: Array[Vector3] = []

	facing.y = 0
	facing = facing.normalized()
	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	var soldier_idx: int = 0
	var row: int = 0

	while soldier_idx < soldier_count:
		var soldiers_in_row: int = row * 2 + 1
		var row_width: float = (soldiers_in_row - 1) * info.spacing

		for i in soldiers_in_row:
			if soldier_idx >= soldier_count:
				break

			var x_offset: float = (i - (soldiers_in_row - 1) / 2.0) * info.spacing
			var z_offset: float = row * info.depth_spacing

			var pos: Vector3 = center + right * x_offset - facing * z_offset
			positions.append(pos)
			soldier_idx += 1

		row += 1

	return positions


static func _calculate_square_positions(soldier_count: int, center: Vector3, facing: Vector3, info: FormationInfo) -> Array[Vector3]:
	## Calculate positions for defensive square.
	var positions: Array[Vector3] = []

	facing.y = 0
	facing = facing.normalized()
	var right: Vector3 = facing.cross(Vector3.UP).normalized()

	var side_length: int = ceili(sqrt(float(soldier_count)))
	var half: float = (side_length - 1) / 2.0

	var soldier_idx: int = 0

	# Create hollow square (soldiers on edges only)
	for row in side_length:
		for col in side_length:
			if soldier_idx >= soldier_count:
				break

			# Only place on edges
			var is_edge: bool = row == 0 or row == side_length - 1 or col == 0 or col == side_length - 1

			if is_edge:
				var x_offset: float = (col - half) * info.spacing
				var z_offset: float = (row - half) * info.depth_spacing

				var pos: Vector3 = center + right * x_offset - facing * z_offset
				positions.append(pos)
				soldier_idx += 1

	# Fill interior if we have soldiers left
	for row in range(1, side_length - 1):
		for col in range(1, side_length - 1):
			if soldier_idx >= soldier_count:
				break

			var x_offset: float = (col - half) * info.spacing
			var z_offset: float = (row - half) * info.depth_spacing

			var pos: Vector3 = center + right * x_offset - facing * z_offset
			positions.append(pos)
			soldier_idx += 1

	return positions

# =============================================================================
# RECOMMENDED FORMATIONS
# =============================================================================

static func get_recommended_formation(unit_type: int, situation: String) -> Type:
	## Get recommended formation for a unit type and situation.
	match situation:
		"march":
			return Type.COLUMN
		"charge":
			if unit_type == UnitType.Type.CAVALRY:
				return Type.WEDGE
			return Type.COLUMN
		"defend":
			return Type.SQUARE
		"ranged":
			return Type.SKIRMISH
		"melee":
			if unit_type == UnitType.Type.CAVALRY:
				return Type.WEDGE
			return Type.LINE
		_:
			return Type.LINE
