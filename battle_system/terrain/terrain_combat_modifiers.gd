class_name TerrainCombatModifiers
extends RefCounted

## Comprehensive terrain combat modifiers.
## Handles height, terrain type, cover, and concealment.

# === TERRAIN TYPES ===
enum TerrainType {
	OPEN,       # Normal grassland/plains
	FOREST,     # Trees - blocks charges, defense bonus, can hide
	MUD,        # Soft ground - slows, defense penalty
	WATER,      # Shallow water - slows greatly, defense penalty
	ROCKY,      # Rough terrain - slows cavalry, no charge
	ROAD,       # Faster movement
}

# === HEIGHT THRESHOLDS ===
const HEIGHT_ADVANTAGE_MIN: float = 1.5      # Meters for small bonus
const HEIGHT_ADVANTAGE_MAJOR: float = 3.0    # Meters for major bonus
const SLOPE_SLOW_THRESHOLD: float = 20.0     # Degrees for movement penalty

# === HEIGHT COMBAT MODIFIERS ===
# Melee
const MELEE_UPHILL_DEFENSE: float = 1.15     # +15% defense when uphill
const MELEE_UPHILL_ATTACK: float = 0.90      # -10% attack when attacking uphill
const MELEE_DOWNHILL_ATTACK: float = 1.10    # +10% attack when attacking downhill
const MELEE_MAJOR_HEIGHT_MULT: float = 1.5   # Multiplier for major height advantage

# Ranged
const RANGED_UPHILL_ACCURACY: float = 1.15   # +15% accuracy shooting downhill
const RANGED_DOWNHILL_ACCURACY: float = 0.85 # -15% accuracy shooting uphill
const RANGED_HEIGHT_DAMAGE: float = 1.10     # +10% damage from height

# === TERRAIN TYPE MODIFIERS ===
const TERRAIN_MODIFIERS: Dictionary = {
	TerrainType.OPEN: {
		"speed": 1.0,
		"defense": 1.0,
		"ranged_defense": 1.0,
		"charge_allowed": true,
		"concealment": 0.0,
	},
	TerrainType.FOREST: {
		"speed": 0.8,           # 20% slower in forest
		"defense": 1.20,        # +20% melee defense (trees block attacks)
		"ranged_defense": 1.35, # +35% vs ranged (trees block arrows)
		"charge_allowed": false, # No charges in forest
		"concealment": 0.6,     # 60% chance to be hidden
	},
	TerrainType.MUD: {
		"speed": 0.6,           # 40% slower in mud
		"defense": 0.90,        # -10% defense (hard to maneuver)
		"ranged_defense": 1.0,
		"charge_allowed": false, # No charges in mud
		"concealment": 0.0,
	},
	TerrainType.WATER: {
		"speed": 0.4,           # 60% slower in water
		"defense": 0.80,        # -20% defense (very exposed)
		"ranged_defense": 0.90, # -10% vs ranged (stuck in water)
		"charge_allowed": false,
		"concealment": 0.0,
	},
	TerrainType.ROCKY: {
		"speed": 0.75,          # 25% slower
		"defense": 1.10,        # +10% defense (rocks provide some cover)
		"ranged_defense": 1.15, # +15% vs ranged
		"charge_allowed": false, # No cavalry charges
		"concealment": 0.2,
	},
	TerrainType.ROAD: {
		"speed": 1.20,          # 20% faster on roads
		"defense": 1.0,
		"ranged_defense": 1.0,
		"charge_allowed": true,
		"concealment": 0.0,
	},
}

# === COVER MODIFIERS (stacks with terrain) ===
const COVER_DEFENSE_BONUS: Dictionary = {
	CoverObject.CoverType.LIGHT: 1.10,   # +10% defense
	CoverObject.CoverType.MEDIUM: 1.25,  # +25% defense
	CoverObject.CoverType.HEAVY: 1.50,   # +50% defense
}

const COVER_RANGED_DEFENSE: Dictionary = {
	CoverObject.CoverType.LIGHT: 1.15,   # +15% vs ranged
	CoverObject.CoverType.MEDIUM: 1.35,  # +35% vs ranged
	CoverObject.CoverType.HEAVY: 1.60,   # +60% vs ranged (walls, buildings)
}


# === STATIC QUERY METHODS ===

## Get height difference between two units.
static func get_height_difference(attacker: Node3D, defender: Node3D) -> float:
	return attacker.global_position.y - defender.global_position.y


## Check if attacker has height advantage.
static func has_height_advantage(attacker: Node3D, defender: Node3D) -> bool:
	return get_height_difference(attacker, defender) > HEIGHT_ADVANTAGE_MIN


## Check if defender has height advantage (attacker attacking uphill).
static func attacking_uphill(attacker: Node3D, defender: Node3D) -> bool:
	return get_height_difference(attacker, defender) < -HEIGHT_ADVANTAGE_MIN


## Get melee attack modifier based on height.
static func get_melee_attack_height_mod(attacker: Node3D, defender: Node3D) -> float:
	var height_diff: float = get_height_difference(attacker, defender)

	if height_diff > HEIGHT_ADVANTAGE_MAJOR:
		return MELEE_DOWNHILL_ATTACK * MELEE_MAJOR_HEIGHT_MULT  # Major downhill bonus
	elif height_diff > HEIGHT_ADVANTAGE_MIN:
		return MELEE_DOWNHILL_ATTACK  # Small downhill bonus
	elif height_diff < -HEIGHT_ADVANTAGE_MAJOR:
		return MELEE_UPHILL_ATTACK / MELEE_MAJOR_HEIGHT_MULT  # Major uphill penalty
	elif height_diff < -HEIGHT_ADVANTAGE_MIN:
		return MELEE_UPHILL_ATTACK  # Small uphill penalty
	return 1.0


## Get melee defense modifier based on height (defender uphill = bonus).
static func get_melee_defense_height_mod(attacker: Node3D, defender: Node3D) -> float:
	var height_diff: float = get_height_difference(attacker, defender)

	if height_diff < -HEIGHT_ADVANTAGE_MAJOR:
		return MELEE_UPHILL_DEFENSE * MELEE_MAJOR_HEIGHT_MULT  # Major uphill defense
	elif height_diff < -HEIGHT_ADVANTAGE_MIN:
		return MELEE_UPHILL_DEFENSE  # Small uphill defense
	return 1.0


## Get ranged accuracy modifier based on height.
static func get_ranged_accuracy_height_mod(shooter: Node3D, target: Node3D) -> float:
	var height_diff: float = get_height_difference(shooter, target)

	if height_diff > HEIGHT_ADVANTAGE_MAJOR:
		return RANGED_UPHILL_ACCURACY * 1.1  # Major height = very accurate
	elif height_diff > HEIGHT_ADVANTAGE_MIN:
		return RANGED_UPHILL_ACCURACY  # Shooting downhill is easier
	elif height_diff < -HEIGHT_ADVANTAGE_MAJOR:
		return RANGED_DOWNHILL_ACCURACY * 0.9  # Shooting uphill is much harder
	elif height_diff < -HEIGHT_ADVANTAGE_MIN:
		return RANGED_DOWNHILL_ACCURACY  # Shooting uphill is harder
	return 1.0


## Get ranged damage modifier based on height (arrows hit harder from above).
static func get_ranged_damage_height_mod(shooter: Node3D, target: Node3D) -> float:
	var height_diff: float = get_height_difference(shooter, target)

	if height_diff > HEIGHT_ADVANTAGE_MIN:
		return RANGED_HEIGHT_DAMAGE  # Arrows from above hit harder
	return 1.0


## Get terrain type at a position.
## This checks the terrain and nearby objects to determine terrain type.
static func get_terrain_type_at(tree: SceneTree, pos: Vector3) -> TerrainType:
	# Check for forest (trees nearby)
	var cover_objects = tree.get_nodes_in_group("cover_objects")
	for cover in cover_objects:
		if not is_instance_valid(cover):
			continue
		var dist: float = cover.global_position.distance_to(pos)
		if dist < 5.0:  # Within 5m of cover
			if cover is CoverObject:
				# Trees = forest
				if cover.cover_type == CoverObject.CoverType.MEDIUM and cover.blocks_line_of_sight:
					return TerrainType.FOREST

	# Check terrain height for water (negative = water)
	var terrain = TerrainHelper.get_terrain(tree)
	if terrain:
		var height: float = terrain.get_height_at(pos)
		if height < -0.5:
			return TerrainType.WATER

		# Check slope for rocky terrain
		var slope: float = TerrainHelper.get_slope_at(tree, pos)
		if slope > 25.0:
			return TerrainType.ROCKY

	return TerrainType.OPEN


## Get terrain modifiers for a position.
static func get_terrain_mods_at(tree: SceneTree, pos: Vector3) -> Dictionary:
	var terrain_type: TerrainType = get_terrain_type_at(tree, pos)
	return TERRAIN_MODIFIERS[terrain_type].duplicate()


## Get speed modifier at a position.
static func get_speed_modifier_at(tree: SceneTree, pos: Vector3) -> float:
	var mods: Dictionary = get_terrain_mods_at(tree, pos)
	return mods.get("speed", 1.0)


## Get defense modifier at a position.
static func get_defense_modifier_at(tree: SceneTree, pos: Vector3) -> float:
	var mods: Dictionary = get_terrain_mods_at(tree, pos)
	var base: float = mods.get("defense", 1.0)

	# Add cover bonus
	var cover_bonus: float = get_cover_defense_at(tree, pos)
	return base * cover_bonus


## Get ranged defense modifier at a position.
static func get_ranged_defense_at(tree: SceneTree, pos: Vector3) -> float:
	var mods: Dictionary = get_terrain_mods_at(tree, pos)
	var base: float = mods.get("ranged_defense", 1.0)

	# Add cover bonus
	var cover_bonus: float = get_cover_ranged_defense_at(tree, pos)
	return base * cover_bonus


## Check if charges are allowed at a position.
static func can_charge_at(tree: SceneTree, pos: Vector3) -> bool:
	var mods: Dictionary = get_terrain_mods_at(tree, pos)
	return mods.get("charge_allowed", true)


## Get concealment chance at a position (0-1).
static func get_concealment_at(tree: SceneTree, pos: Vector3) -> float:
	var mods: Dictionary = get_terrain_mods_at(tree, pos)
	return mods.get("concealment", 0.0)


## Check if a unit is concealed at their position.
static func is_unit_concealed(tree: SceneTree, unit: Node3D) -> bool:
	var concealment: float = get_concealment_at(tree, unit.global_position)
	if concealment <= 0.0:
		return false

	# Roll for concealment
	return randf() < concealment


## Get cover defense bonus at a position.
static func get_cover_defense_at(tree: SceneTree, pos: Vector3) -> float:
	var best_cover: float = 1.0
	var cover_objects = tree.get_nodes_in_group("cover_objects")

	for cover in cover_objects:
		if not is_instance_valid(cover) or not cover is CoverObject:
			continue

		if cover.is_position_in_cover(pos):
			var bonus: float = COVER_DEFENSE_BONUS.get(cover.cover_type, 1.0)
			best_cover = maxf(best_cover, bonus)

	return best_cover


## Get cover ranged defense bonus at a position.
static func get_cover_ranged_defense_at(tree: SceneTree, pos: Vector3) -> float:
	var best_cover: float = 1.0
	var cover_objects = tree.get_nodes_in_group("cover_objects")

	for cover in cover_objects:
		if not is_instance_valid(cover) or not cover is CoverObject:
			continue

		if cover.is_position_in_cover(pos):
			var bonus: float = COVER_RANGED_DEFENSE.get(cover.cover_type, 1.0)
			best_cover = maxf(best_cover, bonus)

	return best_cover


## Get all combat modifiers for an attack.
## Returns Dictionary with all relevant modifiers.
static func get_combat_modifiers(tree: SceneTree, attacker: Node3D, defender: Node3D, is_ranged: bool) -> Dictionary:
	var result: Dictionary = {
		# Height
		"height_attack_mod": 1.0,
		"height_defense_mod": 1.0,
		"height_accuracy_mod": 1.0,
		"height_damage_mod": 1.0,
		# Terrain
		"terrain_type": TerrainType.OPEN,
		"terrain_defense_mod": 1.0,
		"terrain_ranged_defense_mod": 1.0,
		"charge_allowed": true,
		"concealed": false,
		# Cover
		"cover_defense_mod": 1.0,
		"cover_ranged_mod": 1.0,
	}

	# Height modifiers
	if is_ranged:
		result.height_accuracy_mod = get_ranged_accuracy_height_mod(attacker, defender)
		result.height_damage_mod = get_ranged_damage_height_mod(attacker, defender)
	else:
		result.height_attack_mod = get_melee_attack_height_mod(attacker, defender)
		result.height_defense_mod = get_melee_defense_height_mod(attacker, defender)

	# Defender terrain modifiers
	var def_pos: Vector3 = defender.global_position
	result.terrain_type = get_terrain_type_at(tree, def_pos)

	var terrain_mods: Dictionary = TERRAIN_MODIFIERS[result.terrain_type]
	result.terrain_defense_mod = terrain_mods.get("defense", 1.0)
	result.terrain_ranged_defense_mod = terrain_mods.get("ranged_defense", 1.0)
	result.charge_allowed = terrain_mods.get("charge_allowed", true)
	result.concealed = is_unit_concealed(tree, defender)

	# Cover modifiers
	result.cover_defense_mod = get_cover_defense_at(tree, def_pos)
	result.cover_ranged_mod = get_cover_ranged_defense_at(tree, def_pos)

	return result


## Calculate final defense modifier combining all terrain effects.
static func get_total_defense_modifier(tree: SceneTree, attacker: Node3D, defender: Node3D, is_ranged: bool) -> float:
	var mods: Dictionary = get_combat_modifiers(tree, attacker, defender, is_ranged)

	var total: float = 1.0

	# Height
	if not is_ranged:
		total *= mods.height_defense_mod

	# Terrain type
	if is_ranged:
		total *= mods.terrain_ranged_defense_mod
		total *= mods.cover_ranged_mod
	else:
		total *= mods.terrain_defense_mod
		total *= mods.cover_defense_mod

	return total


## Calculate final attack/accuracy modifier combining all terrain effects.
static func get_total_attack_modifier(tree: SceneTree, attacker: Node3D, defender: Node3D, is_ranged: bool) -> float:
	var mods: Dictionary = get_combat_modifiers(tree, attacker, defender, is_ranged)

	if is_ranged:
		return mods.height_accuracy_mod
	else:
		return mods.height_attack_mod
