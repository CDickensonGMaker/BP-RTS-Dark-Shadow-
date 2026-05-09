extends Node
## UnitCatalog autoload - do not add class_name as it conflicts with autoload

## Central registry of all available unit types and their data.
## Access via: UnitCatalog.get_regiment_data("grtsword")

# Preloaded regiment data resources
var _regiment_cache: Dictionary = {}

# =============================================================================
# CORE ROSTER - Units available in Unit Zoo (4-7 per faction)
# =============================================================================

# EMPIRE (Player Faction) - 7 units
# Infantry: Halberdiers (T1), Sellswords (T2), Empire Swordsmen (T2.5), Greatswords (T3)
# Ranged: Crossbowmen
# Cavalry: Reiksguard
# Artillery: Imperial Cannon
const EMPIRE_UNITS: Dictionary = {
	"halb": "res://battle_system/data/regiments/nlnhlb_regiment.tres",
	"mcsword": "res://battle_system/data/regiments/mcsword_regiment.tres",
	"empsword": "res://battle_system/data/regiments/empsword_regiment.tres",
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
	"iron": "res://battle_system/data/regiments/ironbrks_regiment.tres",
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
	"gob1": "res://battle_system/data/regiments/ntgoblin_regiment.tres",
	"orcboyz": "res://battle_system/data/regiments/orcboyz_regiment.tres",
	"blackorc": "res://battle_system/data/regiments/blackorc_regiment.tres",
	"gobarch": "res://battle_system/data/regiments/gobarch_regiment.tres",
	"wolfride": "res://battle_system/data/regiments/wolfride_regiment.tres",
	"boarboyz": "res://battle_system/data/regiments/boarboyz_regiment.tres",
	# troll - no sprite yet
}

# UNDEAD (Enemy Faction) - 5 units + Skaven allies
# Infantry: Skeleton Warriors (T1), Grave Guard (T2)
# Ranged: Skeleton Archers
# Cavalry: Grave Knights
# Skaven: Clanrats, Stormvermin, Rat Ogres, Plague Monks, etc.
const UNDEAD_UNITS: Dictionary = {
	"vanheims": "res://battle_system/data/regiments/vanheims_regiment.tres",
	"graveguard": "res://battle_system/data/regiments/graveguard_regiment.tres",
	"gravearch": "res://battle_system/data/regiments/gravearch_regiment.tres",
	"graveknight": "res://battle_system/data/regiments/graveknight_regiment.tres",
	"bandit": "res://battle_system/data/regiments/bandit_regiment.tres",
	# Skaven units (allied with Undead)
	"clanrats": "res://battle_system/data/regiments/clanrats_regiment.tres",
	"stmverm": "res://battle_system/data/regiments/stmverm_regiment.tres",
	"ratslave": "res://battle_system/data/regiments/ratslave_regiment.tres",
	"eshin": "res://battle_system/data/regiments/eshin_regiment.tres",
	"ratogre": "res://battle_system/data/regiments/ratogre_regiment.tres",
	"packmast": "res://battle_system/data/regiments/packmast_regiment.tres",
	"plagmonk": "res://battle_system/data/regiments/plagmonk_regiment.tres",
	"seer": "res://battle_system/data/regiments/seer_regiment.tres",
	"warpfire": "res://battle_system/data/regiments/warpfire_regiment.tres",
}


# =============================================================================
# FULL REGISTRY - All units (for campaign, etc.)
# =============================================================================

# Unit registry: maps unit_id -> resource path
const UNITS: Dictionary = {
	# EMPIRE (Core)
	"halb": "res://battle_system/data/regiments/nlnhlb_regiment.tres",
	"mcsword": "res://battle_system/data/regiments/mcsword_regiment.tres",
	"empsword": "res://battle_system/data/regiments/empsword_regiment.tres",
	"grtsword": "res://battle_system/data/regiments/grtsword_regiment.tres",
	"xbow": "res://battle_system/data/regiments/xbow_regiment.tres",
	"reik": "res://battle_system/data/regiments/reik_regiment.tres",
	"impcanon": "res://battle_system/data/regiments/impcanon_regiment.tres",
	# Empire (Extended)
	"carlgrd": "res://battle_system/data/regiments/carlgrd_regiment.tres",
	"bodygrd": "res://battle_system/data/regiments/bodygrd_regiment.tres",
	"avengers": "res://battle_system/data/regiments/avengers_regiment.tres",
	# grtcwag removed - duplicate of grtcanon
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
	"iron": "res://battle_system/data/regiments/ironbrks_regiment.tres",
	"ironbrks": "res://battle_system/data/regiments/ironbrks_regiment.tres",
	"engr": "res://battle_system/data/regiments/engr_regiment.tres",
	"grtcanon": "res://battle_system/data/regiments/grtcanon_regiment.tres",
	"gyrocopt": "res://battle_system/data/regiments/gyrocopt_regiment.tres",
	# Dwarf (Extended) - dwslay now has working sprites
	"dwslay": "res://battle_system/data/regiments/dwslay_regiment.tres",
	"dwxbow": "res://battle_system/data/regiments/dwxbow_regiment.tres",
	# dwa2, dwa3, dwa4 removed - portrait sprites, not unit sprites
	"dwheel": "res://battle_system/data/regiments/dwheel_regiment.tres",
	"engrol": "res://battle_system/data/regiments/engrol_regiment.tres",
	# king removed - portrait sprite, not unit sprite

	# ORC (Core)
	"gob1": "res://battle_system/data/regiments/ntgoblin_regiment.tres",
	"orcboyz": "res://battle_system/data/regiments/orcboyz_regiment.tres",
	"blackorc": "res://battle_system/data/regiments/blackorc_regiment.tres",
	"gobarch": "res://battle_system/data/regiments/gobarch_regiment.tres",
	"wolfride": "res://battle_system/data/regiments/wolfride_regiment.tres",
	"boarboyz": "res://battle_system/data/regiments/boarboyz_regiment.tres",
	"troll": "res://battle_system/data/regiments/troll_regiment.tres",
	"biguns": "res://battle_system/data/regiments/biguns_regiment.tres",
	"ntgoblin": "res://battle_system/data/regiments/ntgoblin_regiment.tres",
	"giant": "res://battle_system/data/regiments/giant_regiment.tres",
	# Orc (Extended)
	"fanatic": "res://battle_system/data/regiments/fanatic_regiment.tres",
	"gobsham": "res://battle_system/data/regiments/gobsham_regiment.tres",
	# orc2 removed - portrait sprite, not unit sprite
	"rocklob": "res://battle_system/data/regiments/rocklob_regiment.tres",
	"squigs": "res://battle_system/data/regiments/squigs_regiment.tres",

	# UNDEAD (Core)
	"vanheims": "res://battle_system/data/regiments/vanheims_regiment.tres",
	"graveguard": "res://battle_system/data/regiments/graveguard_regiment.tres",
	"gravearch": "res://battle_system/data/regiments/gravearch_regiment.tres",
	"graveknight": "res://battle_system/data/regiments/graveknight_regiment.tres",
	"bandit": "res://battle_system/data/regiments/bandit_regiment.tres",
	# Skaven (allied with Undead for simplicity)
	"clanrats": "res://battle_system/data/regiments/clanrats_regiment.tres",
	"stmverm": "res://battle_system/data/regiments/stmverm_regiment.tres",
	"ratslave": "res://battle_system/data/regiments/ratslave_regiment.tres",
	"eshin": "res://battle_system/data/regiments/eshin_regiment.tres",
	"ratogre": "res://battle_system/data/regiments/ratogre_regiment.tres",
	"packmast": "res://battle_system/data/regiments/packmast_regiment.tres",
	"plagmonk": "res://battle_system/data/regiments/plagmonk_regiment.tres",
	"seer": "res://battle_system/data/regiments/seer_regiment.tres",
	"warpfire": "res://battle_system/data/regiments/warpfire_regiment.tres",
	"ddcatplt": "res://battle_system/data/regiments/ddcatplt_regiment.tres",
	"doomdivr": "res://battle_system/data/regiments/doomdivr_regiment.tres",

	# WOOD ELVES (Neutral/Other)
	"woodelf": "res://battle_system/data/regiments/woodelf_regiment.tres",
	"treeman": "res://battle_system/data/regiments/treeman_regiment.tres",

	# EMPIRE (Extended)
	"mercxbow": "res://battle_system/data/regiments/mercxbow_regiment.tres",
	"peasant": "res://battle_system/data/regiments/peasant_regiment.tres",
	"brdhrs": "res://battle_system/data/regiments/brdhrs_regiment.tres",
	"arraboyz": "res://battle_system/data/regiments/arraboyz_regiment.tres",
	"keelers": "res://battle_system/data/regiments/keelers_regiment.tres",
	"dragon": "res://battle_system/data/regiments/dragon_regiment.tres",
	"mtdrks": "res://battle_system/data/regiments/mtdrks_regiment.tres",
	"mrtwag": "res://battle_system/data/regiments/mrtwag_regiment.tres",

	# SUPPLY/LOGISTICS
	"caravan": "res://battle_system/data/regiments/caravan_regiment.tres",
	# "wagon" removed - no wagon_regiment.tres exists (use mrtwag/impcwag for artillery wagons)
	"packpony": "res://battle_system/data/regiments/packpony_regiment.tres",
	"sheep": "res://battle_system/data/regiments/sheep_regiment.tres",

	# ORC (Extended)
	"wyvern": "res://battle_system/data/regiments/wyvern_regiment.tres",

	# HEROES (holg removed - portrait sprite)
	"ceridan": "res://battle_system/data/regiments/ceridan_regiment.tres",
	"gourard": "res://battle_system/data/regiments/gourard_regiment.tres",
	"ragnar": "res://battle_system/data/regiments/ragnar_regiment.tres",
	"ilmarin": "res://battle_system/data/regiments/ilmarin_regiment.tres",

	# WIZARDS
	"ambwiz": "res://battle_system/data/regiments/ambwiz_regiment.tres",
	"briwiz": "res://battle_system/data/regiments/briwiz_regiment.tres",
	"celwiz": "res://battle_system/data/regiments/celwiz_regiment.tres",

	# GENERALS (one per faction)
	"empire_general": "res://battle_system/data/regiments/empire_general_regiment.tres",
	"dwarf_general": "res://battle_system/data/regiments/dwarf_general_regiment.tres",
	"orc_general": "res://battle_system/data/regiments/orc_general_regiment.tres",
	"undead_general": "res://battle_system/data/regiments/undead_general_regiment.tres",
}


# Faction groupings for army building
const FACTIONS: Dictionary = {
	"empire": [
		# Core Infantry
		"halb", "mcsword", "empsword", "grtsword", "carlgrd", "bodygrd",
		# Ranged
		"xbow", "mercxbow",
		# Cavalry
		"reik", "brdhrs", "keelers",
		# Artillery
		"impcanon", "mortar", "voleygun",
		# Support
		"peasant", "arraboyz",
		# Special
		"dragon",
		# Heroes/Wizards
		"ambwiz", "briwiz", "celwiz", "ceridan", "gourard",
		# General
		"empire_general"
	],
	"dwarf": [
		# Core Infantry
		"dwwar", "iron", "ironbrks", "dwslay",
		# Ranged
		"engr", "dwxbow",
		# Artillery
		"grtcanon", "dwheel",
		# Special
		"gyrocopt",
		# Heroes (king, holg removed - portrait sprites)
		"ragnar",
		# General
		"dwarf_general"
	],
	"orc": [
		# Goblins
		"gob1", "ntgoblin", "gobarch", "gobsham", "fanatic", "squigs",
		# Orcs
		"orcboyz", "biguns", "blackorc",
		# Cavalry
		"wolfride", "boarboyz",
		# Monsters
		"troll", "giant", "wyvern",
		# Artillery
		"rocklob",
		# General
		"orc_general"
	],
	"undead": [
		# Undead Core
		"vanheims", "graveguard", "gravearch", "graveknight", "bandit",
		# Skaven Infantry
		"clanrats", "stmverm", "ratslave", "plagmonk",
		# Skaven Elite
		"eshin", "ratogre",
		# Skaven Ranged/Artillery
		"warpfire", "ddcatplt", "doomdivr",
		# Skaven Heroes
		"seer", "packmast",
		# General
		"undead_general"
	],
	"woodelf": ["woodelf", "treeman", "ilmarin"],
}

# Generals registry for quick access
const GENERALS: Dictionary = {
	"empire": "empire_general",
	"dwarf": "dwarf_general",
	"orc": "orc_general",
	"undead": "undead_general",
}

# Units available in Unit Zoo (only units with valid 8-direction sprite sheets)
# All units listed here have working sprite atlases
const ZOO_UNITS: Array = [
	# Empire (28 units)
	"halb", "mcsword", "empsword", "grtsword", "carlgrd", "bodygrd",
	"xbow", "mercxbow",
	"reik", "brdhrs", "keelers", "mtdrks", "mccapt",
	"impcanon", "mortar", "voleygun", "mrtwag", "impcwag", "vollywag",
	"peasant", "arraboyz",
	"avengers", "hammers", "leit9th", "nlnhlb",
	"empire_general",
	# Empire Heroes/Wizards
	"ambwiz", "briwiz", "celwiz", "ceridan", "gourard",

	# Dwarf (10 units) - king and holg removed (portrait sprites)
	"dwwar", "iron", "ironbrks", "dwslay", "dwxbow",
	"engr", "engrol",
	"grtcanon", "dwheel",
	"gyrocopt",
	"ragnar",
	"dwarf_general",

	# Orc (16 units)
	"gob1", "ntgoblin", "gobarch", "gobsham", "fanatic", "squigs",
	"orcboyz", "biguns", "blackorc",
	"wolfride", "boarboyz",
	"troll", "giant", "wyvern",
	"rocklob",
	"orc_general",

	# Undead + Skaven (16 units)
	"vanheims", "graveguard", "gravearch", "graveknight", "bandit",
	"clanrats", "stmverm", "ratslave", "plagmonk",
	"eshin", "ratogre",
	"warpfire", "ddcatplt", "doomdivr",
	"seer", "packmast",
	"undead_general",

	# Wood Elves (3 units)
	"woodelf", "treeman", "ilmarin",

	# Special/Standalone
	"dragon",

	# Supply/Logistics (3 units)
	"caravan", "packpony", "sheep",
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


func get_filtered_zoo_units(faction_filter: String, type_filter: String) -> Array:
	"""Get zoo unit IDs filtered by faction and/or type."""
	var result = []
	for unit_id in ZOO_UNITS:
		var data = get_regiment_data(unit_id)
		if not data:
			continue

		# Faction filter
		if faction_filter != "All":
			var faction_lower: String = faction_filter.to_lower()
			var unit_faction: String = data.faction.to_lower() if data.faction else "neutral"
			# Handle greenskin matching orc
			if faction_lower == "greenskin":
				if unit_faction != "greenskin" and unit_faction != "orc" and unit_faction != "goblin":
					continue
			elif unit_faction != faction_lower:
				continue

		# Type filter
		if type_filter != "All":
			if not _matches_type_filter(data, type_filter):
				continue

		result.append(unit_id)

	return result


func _matches_type_filter(data: RegimentData, type_filter: String) -> bool:
	"""Check if a unit matches the type filter."""
	match type_filter:
		"Melee":
			# Infantry with no ranged
			return data.unit_type == UnitType.Type.INFANTRY and data.ballistic_skill == 0
		"Ranged":
			# Any unit with ranged capability
			return data.unit_type == UnitType.Type.RANGED or data.ballistic_skill > 0
		"Spear":
			# Units with spear/halberd/pike/lance weapons (check name)
			var name_lower: String = data.regiment_name.to_lower()
			return "halb" in name_lower or "pike" in name_lower or "spear" in name_lower or "lance" in name_lower or "polearm" in name_lower
		"Cavalry":
			return data.unit_type == UnitType.Type.CAVALRY
		"Artillery":
			return data.unit_type == UnitType.Type.ARTILLERY
		"Hero":
			return data.unit_type == UnitType.Type.GENERAL
		"Monster":
			return data.unit_type == UnitType.Type.MONSTER
		_:
			return true


func get_available_factions() -> Array:
	"""Get list of faction names for UI dropdown."""
	return ["All", "Empire", "Dwarf", "Greenskin", "Undead", "Skaven", "Wood Elf", "Neutral"]


func get_available_types() -> Array:
	"""Get list of type filter names for UI dropdown."""
	return ["All", "Melee", "Ranged", "Spear", "Cavalry", "Artillery", "Hero", "Monster"]
