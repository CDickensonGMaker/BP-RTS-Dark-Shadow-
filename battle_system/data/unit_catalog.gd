extends Node
## UnitCatalog autoload - do not add class_name as it conflicts with autoload

## Central registry of all available unit types and their data.
## Access via: UnitCatalog.get_regiment_data("grtsword")

# Preloaded regiment data resources
var _regiment_cache: Dictionary = {}

# =============================================================================
# CORE ROSTER - Units available in Unit Zoo (4-7 per faction)
# =============================================================================

# EMPIRE (Player Faction) - 6 units
# Infantry: Halberdiers (T1), Sellswords (T2), Greatswords (T3)
# Ranged: Crossbowmen
# Cavalry: Reiksguard
# Artillery: Imperial Cannon
const EMPIRE_UNITS: Dictionary = {
	"halb": "res://battle_system/data/regiments/halb_regiment.tres",
	"mcsword": "res://battle_system/data/regiments/mcsword_regiment.tres",
	"grtsword": "res://battle_system/data/regiments/grtsword_regiment.tres",
	"xbow": "res://battle_system/data/regiments/xbow_regiment.tres",
	"reik": "res://battle_system/data/regiments/reik_regiment.tres",
	"impcanon": "res://battle_system/data/regiments/impcanon_regiment.tres",
}

# DWARVES (Player Faction) - 6 units
# Infantry: Dwarf Warriors (T1), Ironguard (T2), Ironbreakers (T3)
# Ranged: Thunderers
# Artillery: Grudge Thrower
# Special: Gyrocopter
const DWARF_UNITS: Dictionary = {
	"dwwar": "res://battle_system/data/regiments/dwwar_regiment.tres",
	"iron": "res://battle_system/data/regiments/iron_regiment.tres",
	"ironbrks": "res://battle_system/data/regiments/ironbrks_regiment.tres",
	"engr": "res://battle_system/data/regiments/engr_regiment.tres",
	"grtcanon": "res://battle_system/data/regiments/grtcanon_regiment.tres",
	"gyrocopt": "res://battle_system/data/regiments/gyrocopt_regiment.tres",
}

# ORCS (Enemy Faction) - 7 units
# Infantry: Goblin Mob (T1), Orc Boyz (T2), Black Orcs (T3)
# Ranged: Goblin Archers
# Cavalry: Wolf Riders (light), Boar Boyz (heavy)
# Monster: Trolls
const ORC_UNITS: Dictionary = {
	"gob1": "res://battle_system/data/regiments/gob1_regiment.tres",
	"orcboyz": "res://battle_system/data/regiments/orcboyz_regiment.tres",
	"blackorc": "res://battle_system/data/regiments/blackorc_regiment.tres",
	"gobarch": "res://battle_system/data/regiments/gobarch_regiment.tres",
	"wolfride": "res://battle_system/data/regiments/wolfride_regiment.tres",
	"boarboyz": "res://battle_system/data/regiments/boarboyz_regiment.tres",
	# troll - no sprite yet
}

# UNDEAD (Enemy Faction) - 5 units
# Infantry: Skeleton Warriors (T1), Grave Guard (T2)
# Ranged: Skeleton Archers
# Cavalry: Grave Knights
const UNDEAD_UNITS: Dictionary = {
	"vanheims": "res://battle_system/data/regiments/vanheims_regiment.tres",
	"graveguard": "res://battle_system/data/regiments/graveguard_regiment.tres",
	"gravearch": "res://battle_system/data/regiments/gravearch_regiment.tres",
	"graveknight": "res://battle_system/data/regiments/graveknight_regiment.tres",
	"bandit": "res://battle_system/data/regiments/bandit_regiment.tres",
}


# =============================================================================
# FULL REGISTRY - All units (for campaign, etc.)
# =============================================================================

# Unit registry: maps unit_id -> resource path
const UNITS: Dictionary = {
	# EMPIRE (Core)
	"halb": "res://battle_system/data/regiments/halb_regiment.tres",
	"mcsword": "res://battle_system/data/regiments/mcsword_regiment.tres",
	"grtsword": "res://battle_system/data/regiments/grtsword_regiment.tres",
	"xbow": "res://battle_system/data/regiments/xbow_regiment.tres",
	"reik": "res://battle_system/data/regiments/reik_regiment.tres",
	"impcanon": "res://battle_system/data/regiments/impcanon_regiment.tres",
	# Empire (Extended)
	"avengers": "res://battle_system/data/regiments/avengers_regiment.tres",
	"bodygrd": "res://battle_system/data/regiments/bodygrd_regiment.tres",
	"grtcwag": "res://battle_system/data/regiments/grtcwag_regiment.tres",
	"hammers": "res://battle_system/data/regiments/hammers_regiment.tres",
	"impcwag": "res://battle_system/data/regiments/impcwag_regiment.tres",
	"leit9th": "res://battle_system/data/regiments/leit9th_regiment.tres",
	"mccapt": "res://battle_system/data/regiments/mccapt_regiment.tres",
	"mortar": "res://battle_system/data/regiments/mortar_regiment.tres",
	"nlnhlb": "res://battle_system/data/regiments/nlnhlb_regiment.tres",
	"voleygun": "res://battle_system/data/regiments/voleygun_regiment.tres",
	"vollywag": "res://battle_system/data/regiments/vollywag_regiment.tres",

	# DWARF (Core)
	"dwwar": "res://battle_system/data/regiments/dwwar_regiment.tres",
	"iron": "res://battle_system/data/regiments/iron_regiment.tres",
	"ironbrks": "res://battle_system/data/regiments/ironbrks_regiment.tres",
	"engr": "res://battle_system/data/regiments/engr_regiment.tres",
	"grtcanon": "res://battle_system/data/regiments/grtcanon_regiment.tres",
	"gyrocopt": "res://battle_system/data/regiments/gyrocopt_regiment.tres",
	# Dwarf (Extended)
	"dwa2": "res://battle_system/data/regiments/dwa2_regiment.tres",
	"dwa3": "res://battle_system/data/regiments/dwa3_regiment.tres",
	"dwa4": "res://battle_system/data/regiments/dwa4_regiment.tres",
	"dwheel": "res://battle_system/data/regiments/dwheel_regiment.tres",
	"dwslay": "res://battle_system/data/regiments/dwslay_regiment.tres",
	"engrol": "res://battle_system/data/regiments/engrol_regiment.tres",
	"king": "res://battle_system/data/regiments/king_regiment.tres",

	# ORC (Core)
	"gob1": "res://battle_system/data/regiments/gob1_regiment.tres",
	"orcboyz": "res://battle_system/data/regiments/orcboyz_regiment.tres",
	"blackorc": "res://battle_system/data/regiments/blackorc_regiment.tres",
	"gobarch": "res://battle_system/data/regiments/gobarch_regiment.tres",
	"wolfride": "res://battle_system/data/regiments/wolfride_regiment.tres",
	"boarboyz": "res://battle_system/data/regiments/boarboyz_regiment.tres",
	# "troll": NO SPRITE YET
	# Orc (Extended)
	"fanatic": "res://battle_system/data/regiments/fanatic_regiment.tres",
	"giant": "res://battle_system/data/regiments/giant_regiment.tres",
	"gobsham": "res://battle_system/data/regiments/gobsham_regiment.tres",
	"ntgoblin": "res://battle_system/data/regiments/ntgoblin_regiment.tres",
	"orc2": "res://battle_system/data/regiments/orc2_regiment.tres",
	"rocklob": "res://battle_system/data/regiments/rocklob_regiment.tres",
	"squigs": "res://battle_system/data/regiments/squigs_regiment.tres",

	# UNDEAD (Core)
	"vanheims": "res://battle_system/data/regiments/vanheims_regiment.tres",
	"graveguard": "res://battle_system/data/regiments/graveguard_regiment.tres",
	"gravearch": "res://battle_system/data/regiments/gravearch_regiment.tres",
	"graveknight": "res://battle_system/data/regiments/graveknight_regiment.tres",
	"bandit": "res://battle_system/data/regiments/bandit_regiment.tres",
}


# Faction groupings for army building
const FACTIONS: Dictionary = {
	"empire": ["halb", "mcsword", "grtsword", "xbow", "reik", "impcanon"],
	"dwarf": ["dwwar", "iron", "ironbrks", "engr", "grtcanon", "gyrocopt"],
	"orc": ["gob1", "orcboyz", "blackorc", "gobarch", "wolfride", "boarboyz"],
	"undead": ["vanheims", "graveguard", "gravearch", "graveknight"],
}

# Units available in Unit Zoo (only units with valid 8-direction sprite sheets)
# Uses coc_chars sprites for: halb, xbow, reik, iron, engr, gob1
# Uses grave sprites for undead: vanheims, graveguard, gravearch, graveknight
const ZOO_UNITS: Array = [
	# Empire (6 units)
	"halb", "mcsword", "grtsword", "xbow", "reik", "impcanon",
	# Dwarf (6 units)
	"dwwar", "iron", "ironbrks", "engr", "grtcanon", "gyrocopt",
	# Orc (6 units)
	"gob1", "orcboyz", "blackorc", "gobarch", "wolfride", "boarboyz",
	# Undead (4 units)
	"vanheims", "graveguard", "gravearch", "graveknight",
]


func get_regiment_data(unit_id: String) -> RegimentData:
	"""Get RegimentData for a unit, loading and caching if needed."""
	if unit_id in _regiment_cache:
		return _regiment_cache[unit_id]

	if unit_id not in UNITS:
		push_error("Unknown unit: " + unit_id)
		return null

	var data = load(UNITS[unit_id]) as RegimentData
	if data:
		_regiment_cache[unit_id] = data
	return data


func get_faction_units(faction: String) -> Array:
	"""Get list of unit IDs for a faction."""
	return FACTIONS.get(faction, [])


func get_all_unit_ids() -> Array:
	"""Get all available unit IDs."""
	return UNITS.keys()


func get_zoo_unit_ids() -> Array:
	"""Get unit IDs available in Unit Zoo (core roster)."""
	return ZOO_UNITS.duplicate()


func get_units_by_type(unit_type: UnitType.Type) -> Array:
	"""Get all unit IDs of a specific type."""
	var result = []
	for unit_id in UNITS.keys():
		var data = get_regiment_data(unit_id)
		if data and data.unit_type == unit_type:
			result.append(unit_id)
	return result
