extends Node
## UnitCatalog autoload - do not add class_name as it conflicts with autoload

## Central registry of all available unit types and their data.
## Access via: UnitCatalog.get_regiment_data("grtsword")

# Preloaded regiment data resources
var _regiment_cache: Dictionary = {}

# Unit registry: maps unit_id -> resource path
const UNITS: Dictionary = {
	# DWARF
	"dwa2": "res://battle_system/data/regiments/dwa2_regiment.tres",
	"dwa3": "res://battle_system/data/regiments/dwa3_regiment.tres",
	"dwa4": "res://battle_system/data/regiments/dwa4_regiment.tres",
	"dwheel": "res://battle_system/data/regiments/dwheel_regiment.tres",
	"dwslay": "res://battle_system/data/regiments/dwslay_regiment.tres",
	"dwwar": "res://battle_system/data/regiments/dwwar_regiment.tres",
	"dwxbow": "res://battle_system/data/regiments/dwxbow_regiment.tres",
	"engr": "res://battle_system/data/regiments/engr_regiment.tres",
	"engrol": "res://battle_system/data/regiments/engrol_regiment.tres",
	"gyrocopt": "res://battle_system/data/regiments/gyrocopt_regiment.tres",
	"iron": "res://battle_system/data/regiments/iron_regiment.tres",
	"ironbrks": "res://battle_system/data/regiments/ironbrks_regiment.tres",
	"king": "res://battle_system/data/regiments/king_regiment.tres",

	# ELF
	"ambwiz": "res://battle_system/data/regiments/ambwiz_regiment.tres",
	"cele": "res://battle_system/data/regiments/cele_regiment.tres",
	"elf1": "res://battle_system/data/regiments/elf1_regiment.tres",
	"treeman": "res://battle_system/data/regiments/treeman_regiment.tres",
	"woodelf": "res://battle_system/data/regiments/woodelf_regiment.tres",

	# EMPIRE
	"avengers": "res://battle_system/data/regiments/avengers_regiment.tres",
	"bodygrd": "res://battle_system/data/regiments/bodygrd_regiment.tres",
	"grtcanon": "res://battle_system/data/regiments/grtcanon_regiment.tres",
	"grtcwag": "res://battle_system/data/regiments/grtcwag_regiment.tres",
	"grtsword": "res://battle_system/data/regiments/grtsword_regiment.tres",
	"halb": "res://battle_system/data/regiments/halb_regiment.tres",
	"hammers": "res://battle_system/data/regiments/hammers_regiment.tres",
	"impcanon": "res://battle_system/data/regiments/impcanon_regiment.tres",
	"impcwag": "res://battle_system/data/regiments/impcwag_regiment.tres",
	"leit9th": "res://battle_system/data/regiments/leit9th_regiment.tres",
	"mccapt": "res://battle_system/data/regiments/mccapt_regiment.tres",
	"mcsword": "res://battle_system/data/regiments/mcsword_regiment.tres",
	"mercxbow": "res://battle_system/data/regiments/mercxbow_regiment.tres",
	"mortar": "res://battle_system/data/regiments/mortar_regiment.tres",
	"nlnhlb": "res://battle_system/data/regiments/nlnhlb_regiment.tres",
	"reik": "res://battle_system/data/regiments/reik_regiment.tres",
	"voleygun": "res://battle_system/data/regiments/voleygun_regiment.tres",
	"vollywag": "res://battle_system/data/regiments/vollywag_regiment.tres",

	# NEUTRAL
	"ambe": "res://battle_system/data/regiments/ambe_regiment.tres",
	"arraboyz": "res://battle_system/data/regiments/arraboyz_regiment.tres",
	"art1": "res://battle_system/data/regiments/art1_regiment.tres",
	"azgu": "res://battle_system/data/regiments/azgu_regiment.tres",
	"beri": "res://battle_system/data/regiments/beri_regiment.tres",
	"bern": "res://battle_system/data/regiments/bern_regiment.tres",
	"brdhrs": "res://battle_system/data/regiments/brdhrs_regiment.tres",
	"briw": "res://battle_system/data/regiments/briw_regiment.tres",
	"briwiz": "res://battle_system/data/regiments/briwiz_regiment.tres",
	"caravan": "res://battle_system/data/regiments/caravan_regiment.tres",
	"carl": "res://battle_system/data/regiments/carl_regiment.tres",
	"carlgrd": "res://battle_system/data/regiments/carlgrd_regiment.tres",
	"caro": "res://battle_system/data/regiments/caro_regiment.tres",
	"celwiz": "res://battle_system/data/regiments/celwiz_regiment.tres",
	"cer1": "res://battle_system/data/regiments/cer1_regiment.tres",
	"cer2": "res://battle_system/data/regiments/cer2_regiment.tres",
	"ceri": "res://battle_system/data/regiments/ceri_regiment.tres",
	"ceridan": "res://battle_system/data/regiments/ceridan_regiment.tres",
	"comm": "res://battle_system/data/regiments/comm_regiment.tres",
	"ddcatplt": "res://battle_system/data/regiments/ddcatplt_regiment.tres",
	"dragon": "res://battle_system/data/regiments/dragon_regiment.tres",
	"genbatt": "res://battle_system/data/regiments/genbatt_regiment.tres",
	"ginf": "res://battle_system/data/regiments/ginf_regiment.tres",
	"gotr": "res://battle_system/data/regiments/gotr_regiment.tres",
	"gourard": "res://battle_system/data/regiments/gourard_regiment.tres",
	"hamm": "res://battle_system/data/regiments/hamm_regiment.tres",
	"holg": "res://battle_system/data/regiments/holg_regiment.tres",
	"ilmarin": "res://battle_system/data/regiments/ilmarin_regiment.tres",
	"keel": "res://battle_system/data/regiments/keel_regiment.tres",
	"keelers": "res://battle_system/data/regiments/keelers_regiment.tres",
	"mer1": "res://battle_system/data/regiments/mer1_regiment.tres",
	"mer2": "res://battle_system/data/regiments/mer2_regiment.tres",
	"mrtwag": "res://battle_system/data/regiments/mrtwag_regiment.tres",
	"mtdrks": "res://battle_system/data/regiments/mtdrks_regiment.tres",
	"packpony": "res://battle_system/data/regiments/packpony_regiment.tres",
	"peasant": "res://battle_system/data/regiments/peasant_regiment.tres",
	"plagmonk": "res://battle_system/data/regiments/plagmonk_regiment.tres",
	"ragnar": "res://battle_system/data/regiments/ragnar_regiment.tres",
	"ramo": "res://battle_system/data/regiments/ramo_regiment.tres",
	"scri": "res://battle_system/data/regiments/scri_regiment.tres",
	"sheep": "res://battle_system/data/regiments/sheep_regiment.tres",
	"ugle": "res://battle_system/data/regiments/ugle_regiment.tres",
	"wagon": "res://battle_system/data/regiments/wagon_regiment.tres",
	"wyvern": "res://battle_system/data/regiments/wyvern_regiment.tres",
	"xbow": "res://battle_system/data/regiments/xbow_regiment.tres",

	# ORC
	"biguns": "res://battle_system/data/regiments/biguns_regiment.tres",
	"blackorc": "res://battle_system/data/regiments/blackorc_regiment.tres",
	"boarboyz": "res://battle_system/data/regiments/boarboyz_regiment.tres",
	"fanatic": "res://battle_system/data/regiments/fanatic_regiment.tres",
	"giant": "res://battle_system/data/regiments/giant_regiment.tres",
	"gob1": "res://battle_system/data/regiments/gob1_regiment.tres",
	"gobarch": "res://battle_system/data/regiments/gobarch_regiment.tres",
	"gobsham": "res://battle_system/data/regiments/gobsham_regiment.tres",
	"ntgoblin": "res://battle_system/data/regiments/ntgoblin_regiment.tres",
	"orc2": "res://battle_system/data/regiments/orc2_regiment.tres",
	"orcboyz": "res://battle_system/data/regiments/orcboyz_regiment.tres",
	"rocklob": "res://battle_system/data/regiments/rocklob_regiment.tres",
	"squigs": "res://battle_system/data/regiments/squigs_regiment.tres",
	"troll": "res://battle_system/data/regiments/troll_regiment.tres",
	"wolfride": "res://battle_system/data/regiments/wolfride_regiment.tres",

	# SKAVEN
	"clanrats": "res://battle_system/data/regiments/clanrats_regiment.tres",
	"doomdivr": "res://battle_system/data/regiments/doomdivr_regiment.tres",
	"eshin": "res://battle_system/data/regiments/eshin_regiment.tres",
	"packmast": "res://battle_system/data/regiments/packmast_regiment.tres",
	"ratogre": "res://battle_system/data/regiments/ratogre_regiment.tres",
	"ratslave": "res://battle_system/data/regiments/ratslave_regiment.tres",
	"seer": "res://battle_system/data/regiments/seer_regiment.tres",
	"stmverm": "res://battle_system/data/regiments/stmverm_regiment.tres",
	"warpfire": "res://battle_system/data/regiments/warpfire_regiment.tres",

	# UNDEAD
	"bandit": "res://battle_system/data/regiments/bandit_regiment.tres",
	"vanheims": "res://battle_system/data/regiments/vanheims_regiment.tres",
}


# Faction groupings for army building
const FACTIONS: Dictionary = {
	"dwarf": ["dwa2", "dwa3", "dwa4", "dwheel", "dwslay", "dwwar", "dwxbow", "engr", "engrol", "gyrocopt", "iron", "ironbrks", "king"],
	"elf": ["ambwiz", "cele", "elf1", "treeman", "woodelf"],
	"empire": ["avengers", "bodygrd", "grtcanon", "grtcwag", "grtsword", "halb", "hammers", "impcanon", "impcwag", "leit9th", "mccapt", "mcsword", "mercxbow", "mortar", "nlnhlb", "reik", "voleygun", "vollywag"],
	"neutral": ["ambe", "arraboyz", "art1", "azgu", "beri", "bern", "brdhrs", "briw", "briwiz", "caravan", "carl", "carlgrd", "caro", "celwiz", "cer1", "cer2", "ceri", "ceridan", "comm", "ddcatplt", "dragon", "genbatt", "ginf", "gotr", "gourard", "hamm", "holg", "ilmarin", "keel", "keelers", "mer1", "mer2", "mrtwag", "mtdrks", "packpony", "peasant", "plagmonk", "ragnar", "ramo", "scri", "sheep", "ugle", "wagon", "wyvern", "xbow"],
	"orc": ["biguns", "blackorc", "boarboyz", "fanatic", "giant", "gob1", "gobarch", "gobsham", "ntgoblin", "orc2", "orcboyz", "rocklob", "squigs", "troll", "wolfride"],
	"skaven": ["clanrats", "doomdivr", "eshin", "packmast", "ratogre", "ratslave", "seer", "stmverm", "warpfire"],
	"undead": ["bandit", "vanheims"],
}


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


func get_units_by_type(unit_type: UnitType.Type) -> Array:
	"""Get all unit IDs of a specific type."""
	var result = []
	for unit_id in UNITS.keys():
		var data = get_regiment_data(unit_id)
		if data and data.unit_type == unit_type:
			result.append(unit_id)
	return result
