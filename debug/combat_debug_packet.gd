class_name CombatDebugPacket
extends RefCounted

## All combat constants and formulas extracted for independent debugging.
## Use this class to test combat calculations outside of gameplay.
##
## Usage:
##   CombatDebugPacket.print_all()  # Print all formulas
##   var hit = CombatDebugPacket.melee_hit_chance(14, 10)  # Test hit chance


# =====================================
# MELEE COMBAT
# =====================================

const BASE_HIT_CHANCE: float = 0.35
const HIT_CHANCE_PER_SKILL: float = 0.01
const MIN_HIT_CHANCE: float = 0.08
const MAX_HIT_CHANCE: float = 0.90


static func melee_hit_chance(attack: int, defense: int) -> float:
	## Calculate melee hit chance.
	## Formula: clamp(0.35 + (attack - defense) * 0.01, 0.08, 0.90)
	return clampf(BASE_HIT_CHANCE + (attack - defense) * HIT_CHANCE_PER_SKILL, MIN_HIT_CHANCE, MAX_HIT_CHANCE)


# =====================================
# FLANKING
# =====================================

const FLANK_SIDE_ANGLE: float = 45.0
const FLANK_REAR_ANGLE: float = 135.0
const FLANK_SIDE_MULT: float = 1.5
const FLANK_REAR_MULT: float = 2.0
const FLANK_SIDE_MORALE_MULT: float = 1.25
const FLANK_REAR_MORALE_MULT: float = 1.5


static func flank_damage_mult(angle_degrees: float) -> float:
	## Get damage multiplier based on attack angle.
	## 0-45°: Frontal (1.0x)
	## 45-135°: Flank (1.5x)
	## 135-180°: Rear (2.0x)
	if angle_degrees > FLANK_REAR_ANGLE:
		return FLANK_REAR_MULT
	elif angle_degrees > FLANK_SIDE_ANGLE:
		return FLANK_SIDE_MULT
	return 1.0


static func flank_morale_mult(angle_degrees: float) -> float:
	## Get morale damage multiplier based on attack angle.
	if angle_degrees > FLANK_REAR_ANGLE:
		return FLANK_REAR_MORALE_MULT
	elif angle_degrees > FLANK_SIDE_ANGLE:
		return FLANK_SIDE_MORALE_MULT
	return 1.0


static func calculate_attack_angle(attacker_pos: Vector3, defender_pos: Vector3, defender_facing: Vector3) -> float:
	## Calculate angle between attacker and defender's facing direction.
	## Returns degrees (0 = frontal, 90 = side, 180 = rear)
	var attack_dir: Vector3 = (attacker_pos - defender_pos).normalized()
	attack_dir.y = 0
	defender_facing.y = 0

	if attack_dir.length_squared() < 0.001 or defender_facing.length_squared() < 0.001:
		return 0.0

	var dot: float = attack_dir.normalized().dot(defender_facing.normalized())
	return rad_to_deg(acos(clampf(dot, -1.0, 1.0)))


# =====================================
# RANGED COMBAT
# =====================================

const BASE_RANGED_ACCURACY: float = 0.50
const RANGED_ACCURACY_PER_SKILL: float = 0.02
const EFFECTIVE_RANGE_RATIO: float = 0.6
const MAX_RANGE_PENALTY: float = 0.5
const MIN_RANGED_ACCURACY: float = 0.15
const MAX_RANGED_ACCURACY: float = 0.85


static func ranged_accuracy(ballistic_skill: int, distance: float, max_range: float) -> float:
	## Calculate ranged hit chance.
	## Base: 50% + 2% per ballistic skill
	## Falloff: Linear from 60% range to max range
	var base: float = BASE_RANGED_ACCURACY + ballistic_skill * RANGED_ACCURACY_PER_SKILL
	var effective: float = max_range * EFFECTIVE_RANGE_RATIO

	if distance > effective:
		var falloff: float = (distance - effective) / (max_range - effective)
		base *= lerpf(1.0, MAX_RANGE_PENALTY, clampf(falloff, 0.0, 1.0))

	return clampf(base, MIN_RANGED_ACCURACY, MAX_RANGED_ACCURACY)


# =====================================
# MORALE
# =====================================

const MORALE_STEADY: float = 70.0
const MORALE_WAVERING: float = 40.0
const MORALE_SHAKEN: float = 20.0


static func morale_state(value: float) -> String:
	## Get morale state name from value.
	if value >= MORALE_STEADY:
		return "STEADY"
	if value >= MORALE_WAVERING:
		return "WAVERING"
	if value >= MORALE_SHAKEN:
		return "SHAKEN"
	return "BROKEN"


static func morale_effectiveness(value: float) -> float:
	## Get combat effectiveness multiplier from morale.
	if value >= MORALE_STEADY:
		return 1.0
	if value >= MORALE_WAVERING:
		return 0.9
	if value >= MORALE_SHAKEN:
		return 0.75
	return 0.5


# =====================================
# STAMINA / FATIGUE
# =====================================

const FATIGUE_LIGHT: float = 1.0      # Armor 0-3
const FATIGUE_MEDIUM: float = 1.25    # Armor 4-7
const FATIGUE_HEAVY: float = 1.5      # Armor 8+


static func fatigue_mult(armor: int) -> float:
	## Get stamina drain multiplier from armor.
	if armor <= 3:
		return FATIGUE_LIGHT
	if armor <= 7:
		return FATIGUE_MEDIUM
	return FATIGUE_HEAVY


static func fatigue_state(stamina_ratio: float) -> String:
	## Get fatigue state name from stamina percentage.
	if stamina_ratio > 0.7:
		return "FRESH"
	if stamina_ratio > 0.4:
		return "WINDED"
	if stamina_ratio > 0.1:
		return "TIRED"
	return "EXHAUSTED"


static func fatigue_combat_mult(stamina_ratio: float) -> Dictionary:
	## Get combat modifiers from fatigue state.
	if stamina_ratio > 0.7:
		return {"attack": 1.0, "defense": 1.0, "speed": 1.0}
	if stamina_ratio > 0.4:
		return {"attack": 0.95, "defense": 0.95, "speed": 0.95}
	if stamina_ratio > 0.1:
		return {"attack": 0.90, "defense": 0.90, "speed": 0.85}
	return {"attack": 0.80, "defense": 0.85, "speed": 0.50}


# =====================================
# CHARGE
# =====================================

const CHARGE_DECAY_DURATION: float = 10.0
const CHARGE_MIN_DISTANCE: float = 10.0
const CHARGE_AP_RATIO: float = 0.7


static func charge_bonus_decay(time_since_impact: float) -> float:
	## Get charge bonus decay multiplier.
	## Bonus decays linearly over 10 seconds.
	if time_since_impact >= CHARGE_DECAY_DURATION:
		return 0.0
	return 1.0 - (time_since_impact / CHARGE_DECAY_DURATION)


static func charge_impact_damage(mass: float, speed: float) -> int:
	## Calculate charge impact damage.
	## 70% is armor-piercing.
	return int(mass * speed * 2.0)


# =====================================
# FORMATIONS
# =====================================

const FORMATIONS: Dictionary = {
	"LINE":        {"speed": 1.0,  "attack": 1.0, "defense": 1.0,  "allowed": ["INFANTRY", "CAVALRY", "RANGED", "ARTILLERY", "GENERAL"]},
	"COLUMN":      {"speed": 1.2,  "attack": 0.6, "defense": 0.7,  "allowed": ["INFANTRY", "CAVALRY", "RANGED", "ARTILLERY", "GENERAL"]},
	"WEDGE":       {"speed": 1.1,  "attack": 1.3, "defense": 0.8,  "allowed": ["CAVALRY"]},
	"SQUARE":      {"speed": 0.7,  "attack": 0.8, "defense": 1.3,  "allowed": ["INFANTRY"]},
	"LOOSE":       {"speed": 1.15, "attack": 0.7, "defense": 0.6,  "allowed": ["RANGED"]},
	"SHIELD_WALL": {"speed": 0.5,  "attack": 0.8, "defense": 1.5,  "allowed": ["INFANTRY"]},
	"SCHILTRON":   {"speed": 0.0,  "attack": 0.6, "defense": 1.4,  "allowed": ["INFANTRY"]},
}


static func get_formation_modifiers(formation_name: String) -> Dictionary:
	## Get stat modifiers for a formation.
	return FORMATIONS.get(formation_name, FORMATIONS["LINE"])


# =====================================
# UNIT TYPES
# =====================================

const UNIT_TYPES: Dictionary = {
	"INFANTRY":  {"hp": 100, "damage": 15, "armor": 10},
	"CAVALRY":   {"hp": 80,  "damage": 25, "armor": 5},
	"RANGED":    {"hp": 60,  "damage": 10, "armor": 2},
	"ARTILLERY": {"hp": 40,  "damage": 50, "armor": 0},
	"GENERAL":   {"hp": 150, "damage": 30, "armor": 15},
}


static func get_unit_type_stats(type_name: String) -> Dictionary:
	## Get base stats for a unit type.
	return UNIT_TYPES.get(type_name, UNIT_TYPES["INFANTRY"])


# =====================================
# ALL UNITS REGISTRY (113 units)
# =====================================

const FACTIONS: Dictionary = {
	"dwarf": ["dwa2", "dwa3", "dwa4", "dwheel", "dwslay", "dwwar", "dwxbow",
			  "engr", "engrol", "gyrocopt", "iron", "ironbrks", "king"],
	"elf": ["ambwiz", "cele", "elf1", "treeman", "woodelf"],
	"empire": ["avengers", "bodygrd", "grtcanon", "grtcwag", "grtsword", "halb",
			   "hammers", "impcanon", "impcwag", "leit9th", "mccapt", "mcsword",
			   "mercxbow", "mortar", "nlnhlb", "reik", "voleygun", "vollywag"],
	"neutral": ["ambe", "arraboyz", "art1", "azgu", "beri", "bern", "brdhrs",
				"briw", "briwiz", "caravan", "carl", "carlgrd", "caro", "celwiz",
				"cer1", "cer2", "ceri", "ceridan", "comm", "ddcatplt", "dragon",
				"genbatt", "ginf", "gotr", "gourard", "hamm", "holg", "ilmarin",
				"keel", "keelers", "mer1", "mer2", "mrtwag", "mtdrks", "packpony",
				"peasant", "plagmonk", "ragnar", "ramo", "scri", "sheep", "ugle",
				"wagon", "wyvern", "xbow"],
	"orc": ["biguns", "blackorc", "boarboyz", "fanatic", "giant", "gob1",
			"gobarch", "gobsham", "ntgoblin", "orc2", "orcboyz", "rocklob",
			"squigs", "troll", "wolfride"],
	"skaven": ["clanrats", "doomdivr", "eshin", "packmast", "ratogre",
			   "ratslave", "seer", "stmverm", "warpfire"],
	"undead": ["bandit", "vanheims"],
}


static func get_all_unit_ids() -> Array:
	## Get all unit IDs across all factions.
	var all_ids: Array = []
	for faction in FACTIONS:
		all_ids.append_array(FACTIONS[faction])
	return all_ids


static func get_faction_units(faction: String) -> Array:
	## Get unit IDs for a specific faction.
	return FACTIONS.get(faction, [])


# =====================================
# DEBUG PRINT
# =====================================

static func print_all() -> void:
	## Print all combat formulas for reference.
	print("\n=== COMBAT DEBUG PACKET ===\n")

	print("MELEE HIT CHANCE:")
	print("  Formula: clamp(0.35 + (attack - defense) * 0.01, 0.08, 0.90)")
	print("  Example: attack=14, defense=10 -> %.2f (%.0f%%)" % [melee_hit_chance(14, 10), melee_hit_chance(14, 10) * 100])
	print("  Example: attack=10, defense=14 -> %.2f (%.0f%%)" % [melee_hit_chance(10, 14), melee_hit_chance(10, 14) * 100])
	print("")

	print("FLANKING:")
	print("  0-45°:   Frontal  -> 1.0x damage, 1.0x morale")
	print("  45-135°: Flank    -> 1.5x damage, 1.25x morale")
	print("  135-180°: Rear    -> 2.0x damage, 1.5x morale")
	print("")

	print("RANGED ACCURACY:")
	print("  Base: 50%% + 2%% per Ballistic Skill point")
	print("  Range: Full accuracy within 60%% of max range")
	print("  Falloff: Linear to 50%% accuracy at max range")
	print("  Example: BS=12 at 50%% range -> %.2f (%.0f%%)" % [ranged_accuracy(12, 20, 40), ranged_accuracy(12, 20, 40) * 100])
	print("  Example: BS=12 at 100%% range -> %.2f (%.0f%%)" % [ranged_accuracy(12, 40, 40), ranged_accuracy(12, 40, 40) * 100])
	print("")

	print("MORALE STATES:")
	print("  Steady:   >= 70%% morale -> 100%% combat effectiveness")
	print("  Wavering: 40-70%% morale -> 90%% combat effectiveness")
	print("  Shaken:   20-40%% morale -> 75%% combat effectiveness")
	print("  Broken:   < 20%% morale -> 50%% combat effectiveness (routing)")
	print("")

	print("FATIGUE STATES:")
	print("  Fresh:     > 70%% stamina -> 100%% attack, defense, speed")
	print("  Winded:    40-70%% stamina -> 95%% attack, defense, speed")
	print("  Tired:     10-40%% stamina -> 90%% attack, 90%% defense, 85%% speed")
	print("  Exhausted: < 10%% stamina -> 80%% attack, 85%% defense, 50%% speed")
	print("")

	print("ARMOR FATIGUE DRAIN:")
	print("  Light (0-3 armor):  1.0x stamina drain")
	print("  Medium (4-7 armor): 1.25x stamina drain")
	print("  Heavy (8+ armor):   1.5x stamina drain")
	print("")

	print("CHARGE MECHANICS:")
	print("  Minimum distance: 10 units")
	print("  Impact damage: mass * speed * 2.0")
	print("  Armor-piercing: 70%% of impact damage")
	print("  Bonus decay: Linear over 10 seconds after impact")
	print("")

	print("FORMATIONS:")
	for name in FORMATIONS:
		var f: Dictionary = FORMATIONS[name]
		print("  %s: speed=%.2f, attack=%.2f, defense=%.2f" % [name, f["speed"], f["attack"], f["defense"]])
	print("")

	print("UNIT TYPES:")
	for name in UNIT_TYPES:
		var u: Dictionary = UNIT_TYPES[name]
		print("  %s: hp=%d, damage=%d, armor=%d" % [name, u["hp"], u["damage"], u["armor"]])
	print("")

	print("=== END DEBUG PACKET ===\n")


static func test_combat_scenario(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	## Test a combat scenario.
	## attacker/defender format: {"attack": int, "defense": int, "pos": Vector3, "facing": Vector3}
	var result: Dictionary = {}

	result["hit_chance"] = melee_hit_chance(attacker.get("attack", 10), defender.get("defense", 10))
	result["flank_angle"] = calculate_attack_angle(
		attacker.get("pos", Vector3.ZERO),
		defender.get("pos", Vector3.FORWARD),
		defender.get("facing", Vector3.FORWARD)
	)
	result["damage_mult"] = flank_damage_mult(result["flank_angle"])
	result["morale_mult"] = flank_morale_mult(result["flank_angle"])
	result["flank_type"] = "FRONTAL" if result["flank_angle"] <= 45 else ("REAR" if result["flank_angle"] > 135 else "FLANK")

	return result
