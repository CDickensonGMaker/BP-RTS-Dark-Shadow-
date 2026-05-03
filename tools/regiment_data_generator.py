#!/usr/bin/env python3
"""
Regiment Data Generator
Creates RegimentData .tres files for all unit sprite atlases.

Usage:
    python regiment_data_generator.py              # Generate all regiment data
    python regiment_data_generator.py --list       # List units and their types
"""

import os
import re
from pathlib import Path

# Paths
ATLAS_DIR = Path(__file__).parent.parent / "assets" / "sprites" / "units"
REGIMENT_DIR = Path(__file__).parent.parent / "battle_system" / "data" / "regiments"
CATALOG_PATH = Path(__file__).parent.parent / "battle_system" / "data" / "unit_catalog.gd"

# Unit type classification based on name patterns
UNIT_TYPE_PATTERNS = {
    # RANGED (type 2)
    "RANGED": [
        r"xbow", r"archer", r"gobarch", r"woodelf", r"keelers", r"mercxbow",
        r"dwxbow", r"arraboyz", r"biguns"
    ],
    # CAVALRY (type 1)
    "CAVALRY": [
        r"boarboyz", r"wolfride", r"brdhrs", r"dragon", r"wyvern", r"gyrocopt",
        r"doomdivr", r"packpony", r"caravan", r"wagon"
    ],
    # ARTILLERY (type 3)
    "ARTILLERY": [
        r"cannon", r"mortar", r"catplt", r"rocklob", r"voleygun", r"vollywag",
        r"grtcanon", r"impcanon", r"warpfire", r"dwheel"
    ],
    # GENERAL/HERO (type 4)
    "GENERAL": [
        r"wiz$", r"wizard", r"seer", r"shaman", r"sham$", r"mage",
        r"king", r"ragnar", r"ceridan", r"ilmarin", r"carl$", r"holg",
        r"genbatt", r"comm$", r"capt"
    ],
    # Everything else is INFANTRY (type 0)
}

# Faction classification
FACTION_PATTERNS = {
    "empire": [
        r"grtsword", r"halb", r"hammer", r"reik", r"mcsword", r"mccapt",
        r"mortar", r"impcanon", r"impcwag", r"grtcanon", r"grtcwag",
        r"voleygun", r"vollywag", r"mercxbow", r"bodygrd", r"avengers",
        r"nlnhlb", r"leit9th"
    ],
    "dwarf": [
        r"dw", r"iron", r"hammers", r"engr", r"gyrocopt", r"king"
    ],
    "orc": [
        r"orc", r"blackorc", r"biguns", r"goblin", r"gob", r"ntgoblin",
        r"boarboyz", r"troll", r"giant", r"wolfride", r"squigs", r"fanatic",
        r"rocklob", r"shaman"
    ],
    "skaven": [
        r"clan", r"rat", r"eshin", r"plague", r"warpfire", r"doomdivr",
        r"stmverm", r"seer", r"packmast"
    ],
    "elf": [
        r"elf", r"woodelf", r"treeman", r"cele", r"ambwiz"
    ],
    "undead": [
        r"vanheims", r"bandit"  # Placeholder - adjust as needed
    ],
}

# Faction colors
FACTION_COLORS = {
    "empire": "Color(0.2, 0.4, 0.8, 1)",       # Blue
    "dwarf": "Color(0.6, 0.4, 0.2, 1)",        # Brown/bronze
    "orc": "Color(0.2, 0.6, 0.2, 1)",          # Green
    "skaven": "Color(0.4, 0.3, 0.2, 1)",       # Brownish
    "elf": "Color(0.3, 0.7, 0.4, 1)",          # Light green
    "undead": "Color(0.3, 0.1, 0.4, 1)",       # Purple
    "neutral": "Color(0.5, 0.5, 0.5, 1)",      # Gray
}

# Base stats by unit type
BASE_STATS = {
    "INFANTRY": {
        "attack": 10, "defense": 10, "weapon_skill": 10, "ballistic_skill": 0,
        "strength": 3, "max_soldiers": 40, "base_morale": 60.0, "morale_save": 5,
        "speed": 3.5, "charge_bonus": 6, "max_ammo": 0, "range_distance": 0.0
    },
    "CAVALRY": {
        "attack": 14, "defense": 8, "weapon_skill": 12, "ballistic_skill": 0,
        "strength": 4, "max_soldiers": 20, "base_morale": 70.0, "morale_save": 6,
        "speed": 6.0, "charge_bonus": 12, "max_ammo": 0, "range_distance": 0.0
    },
    "RANGED": {
        "attack": 6, "defense": 6, "weapon_skill": 6, "ballistic_skill": 12,
        "strength": 3, "max_soldiers": 30, "base_morale": 50.0, "morale_save": 4,
        "speed": 3.0, "charge_bonus": 2, "max_ammo": 24, "range_distance": 40.0
    },
    "ARTILLERY": {
        "attack": 4, "defense": 4, "weapon_skill": 4, "ballistic_skill": 14,
        "strength": 8, "max_soldiers": 8, "base_morale": 55.0, "morale_save": 4,
        "speed": 1.5, "charge_bonus": 0, "max_ammo": 12, "range_distance": 80.0
    },
    "GENERAL": {
        "attack": 16, "defense": 14, "weapon_skill": 16, "ballistic_skill": 0,
        "strength": 5, "max_soldiers": 1, "base_morale": 90.0, "morale_save": 9,
        "speed": 4.0, "charge_bonus": 10, "max_ammo": 0, "range_distance": 0.0
    },
}

# Elite unit bonuses (added to base stats)
ELITE_PATTERNS = {
    r"grtsword": {"attack": 4, "defense": 2, "strength": 1, "base_morale": 10.0},
    r"blackorc": {"attack": 6, "defense": 4, "strength": 2, "base_morale": 15.0},
    r"ironbrks": {"attack": 4, "defense": 6, "strength": 1, "base_morale": 20.0},
    r"hammers": {"attack": 4, "defense": 4, "strength": 2, "base_morale": 15.0},
    r"dwslay": {"attack": 8, "defense": 0, "strength": 3, "base_morale": 25.0},
    r"avengers": {"attack": 6, "defense": 4, "strength": 2, "base_morale": 20.0},
    r"eshin": {"attack": 6, "defense": 2, "strength": 2, "base_morale": 10.0},
    r"treeman": {"attack": 10, "defense": 8, "strength": 4, "max_soldiers": -35},
    r"giant": {"attack": 12, "defense": 6, "strength": 6, "max_soldiers": -38},
    r"troll": {"attack": 8, "defense": 6, "strength": 4, "max_soldiers": -32},
    r"ratogre": {"attack": 8, "defense": 4, "strength": 4, "max_soldiers": -36},
    r"dragon": {"attack": 14, "defense": 10, "strength": 6, "max_soldiers": -19},
    r"wyvern": {"attack": 10, "defense": 6, "strength": 4, "max_soldiers": -18},
}


def classify_unit_type(unit_name: str) -> str:
    """Determine unit type from name."""
    name_lower = unit_name.lower()

    for unit_type, patterns in UNIT_TYPE_PATTERNS.items():
        for pattern in patterns:
            if re.search(pattern, name_lower):
                return unit_type

    return "INFANTRY"


def classify_faction(unit_name: str) -> str:
    """Determine faction from unit name."""
    name_lower = unit_name.lower()

    for faction, patterns in FACTION_PATTERNS.items():
        for pattern in patterns:
            if re.search(pattern, name_lower):
                return faction

    return "neutral"


def get_display_name(unit_id: str) -> str:
    """Convert unit ID to display name."""
    # Common abbreviation expansions
    name_map = {
        "grtsword": "Greatswords",
        "dwwar": "Dwarf Warriors",
        "dwslay": "Dwarf Slayers",
        "dwxbow": "Dwarf Crossbows",
        "blackorc": "Black Orcs",
        "orcboyz": "Orc Boyz",
        "gobarch": "Goblin Archers",
        "wolfride": "Wolf Riders",
        "boarboyz": "Boar Boyz",
        "clanrats": "Clanrats",
        "stmverm": "Stormvermin",
        "ratogre": "Rat Ogres",
        "plagmonk": "Plague Monks",
        "woodelf": "Wood Elf Archers",
        "treeman": "Treeman",
        "ironbrks": "Ironbreakers",
        "hammers": "Hammerers",
        "avengers": "Avengers",
        "nlnhlb": "Nuln Halberdiers",
        "mcsword": "Mercenary Swords",
        "mercxbow": "Mercenary Crossbows",
        "bodygrd": "Bodyguard",
        "brdhrs": "Border Horse",
        "grtcanon": "Great Cannon",
        "impcanon": "Imperial Cannon",
        "mortar": "Mortar",
        "voleygun": "Volley Gun",
        "gyrocopt": "Gyrocopter",
        "warpfire": "Warpfire Thrower",
        "doomdivr": "Doom Diver",
        "rocklob": "Rock Lobber",
        "ntgoblin": "Night Goblins",
        "squigs": "Squig Hoppers",
        "fanatic": "Fanatics",
        "giant": "Giant",
        "troll": "Troll",
        "dragon": "Dragon",
        "wyvern": "Wyvern",
        "eshin": "Clan Eshin",
        "packmast": "Packmaster",
        "keelers": "Keelers",
        "biguns": "Big'Uns",
        "vanheims": "Vanheims",
    }

    if unit_id.lower() in name_map:
        return name_map[unit_id.lower()]

    # Default: capitalize and clean up
    return unit_id.replace("_", " ").title()


def get_unit_stats(unit_id: str, unit_type: str) -> dict:
    """Get stats for a unit, applying elite bonuses if applicable."""
    stats = BASE_STATS[unit_type].copy()
    name_lower = unit_id.lower()

    # Apply elite bonuses
    for pattern, bonuses in ELITE_PATTERNS.items():
        if re.search(pattern, name_lower):
            for stat, bonus in bonuses.items():
                if stat in stats:
                    stats[stat] += bonus

    # Ensure soldiers don't go below 1
    stats["max_soldiers"] = max(1, stats["max_soldiers"])
    stats["current_soldiers"] = stats["max_soldiers"]

    return stats


def generate_regiment_tres(unit_id: str, atlas_path: str) -> str:
    """Generate RegimentData .tres file content."""
    unit_type = classify_unit_type(unit_id)
    faction = classify_faction(unit_id)
    display_name = get_display_name(unit_id)
    stats = get_unit_stats(unit_id, unit_type)
    faction_color = FACTION_COLORS.get(faction, FACTION_COLORS["neutral"])

    # Unit type enum value
    type_values = {"INFANTRY": 0, "CAVALRY": 1, "RANGED": 2, "ARTILLERY": 3, "GENERAL": 4}
    type_value = type_values.get(unit_type, 0)

    content = f'''[gd_resource type="Resource" script_class="RegimentData" load_steps=3 format=3]

[ext_resource type="Script" path="res://battle_system/data/regiment_data.gd" id="1"]
[ext_resource type="Resource" path="{atlas_path}" id="2"]

[resource]
script = ExtResource("1")
regiment_name = "{display_name}"
unit_type = {type_value}
attack = {stats["attack"]}
defense = {stats["defense"]}
weapon_skill = {stats["weapon_skill"]}
ballistic_skill = {stats["ballistic_skill"]}
strength = {stats["strength"]}
max_soldiers = {stats["max_soldiers"]}
current_soldiers = {stats["current_soldiers"]}
base_morale = {stats["base_morale"]}
morale_save = {stats["morale_save"]}
speed = {stats["speed"]}
charge_bonus = {stats["charge_bonus"]}
max_ammo = {stats["max_ammo"]}
current_ammo = {stats["max_ammo"]}
range_distance = {stats["range_distance"]}
faction_color = {faction_color}
sprite_atlas = ExtResource("2")
'''
    return content


def generate_unit_catalog(units: list) -> str:
    """Generate the unit catalog autoload script."""
    # Group units by faction
    factions = {}
    for unit_id in units:
        faction = classify_faction(unit_id)
        if faction not in factions:
            factions[faction] = []
        factions[faction].append(unit_id)

    content = '''class_name UnitCatalog
extends Node

## Central registry of all available unit types and their data.
## Access via: UnitCatalog.get_regiment_data("grtsword")

# Preloaded regiment data resources
var _regiment_cache: Dictionary = {}

# Unit registry: maps unit_id -> resource path
const UNITS: Dictionary = {
'''

    for faction in sorted(factions.keys()):
        content += f'\t# {faction.upper()}\n'
        for unit_id in sorted(factions[faction]):
            path = f"res://battle_system/data/regiments/{unit_id}_regiment.tres"
            content += f'\t"{unit_id}": "{path}",\n'
        content += '\n'

    content = content.rstrip('\n') + '\n}\n\n'

    content += '''
# Faction groupings for army building
const FACTIONS: Dictionary = {
'''

    for faction in sorted(factions.keys()):
        unit_list = ', '.join(f'"{u}"' for u in sorted(factions[faction]))
        content += f'\t"{faction}": [{unit_list}],\n'

    content += '''}\n

func _ready() -> void:
\tpass


func get_regiment_data(unit_id: String) -> RegimentData:
\t"""Get RegimentData for a unit, loading and caching if needed."""
\tif unit_id in _regiment_cache:
\t\treturn _regiment_cache[unit_id]
\t
\tif unit_id not in UNITS:
\t\tpush_error("Unknown unit: " + unit_id)
\t\treturn null
\t
\tvar data = load(UNITS[unit_id]) as RegimentData
\tif data:
\t\t_regiment_cache[unit_id] = data
\treturn data


func get_faction_units(faction: String) -> Array:
\t"""Get list of unit IDs for a faction."""
\treturn FACTIONS.get(faction, [])


func get_all_unit_ids() -> Array:
\t"""Get all available unit IDs."""
\treturn UNITS.keys()


func get_units_by_type(unit_type: UnitType.Type) -> Array:
\t"""Get all unit IDs of a specific type."""
\tvar result = []
\tfor unit_id in UNITS.keys():
\t\tvar data = get_regiment_data(unit_id)
\t\tif data and data.unit_type == unit_type:
\t\t\tresult.append(unit_id)
\treturn result
'''

    return content


def main():
    import argparse

    parser = argparse.ArgumentParser(description="Generate RegimentData resources")
    parser.add_argument("--list", action="store_true", help="List units and types")
    parser.add_argument("--force", action="store_true", help="Overwrite existing files")
    parser.add_argument("units", nargs="*", help="Specific units to process")

    args = parser.parse_args()

    # Find all atlas files
    atlas_files = list(ATLAS_DIR.glob("*_atlas.tres"))

    # Extract unit IDs
    all_units = []
    for atlas_path in atlas_files:
        unit_id = atlas_path.stem.replace("_atlas", "")
        # Skip non-combat sprites
        if unit_id in ["icons", "spells", "sparkle", "beam", "backall", "stickers"]:
            continue
        all_units.append(unit_id)

    if args.list:
        print("Available units:")
        print("-" * 60)
        for unit_id in sorted(all_units):
            unit_type = classify_unit_type(unit_id)
            faction = classify_faction(unit_id)
            name = get_display_name(unit_id)
            print(f"  {unit_id:15} | {unit_type:10} | {faction:8} | {name}")
        return

    # Filter units if specified
    if args.units:
        units_to_process = [u.lower() for u in args.units if u.lower() in all_units]
    else:
        units_to_process = all_units

    # Create output directory
    REGIMENT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"Generating regiment data for {len(units_to_process)} units...")
    print(f"Output: {REGIMENT_DIR}")
    print()

    success = 0
    skipped = 0

    for unit_id in sorted(units_to_process):
        output_path = REGIMENT_DIR / f"{unit_id}_regiment.tres"
        atlas_path = f"res://assets/sprites/units/{unit_id}_atlas.tres"

        if output_path.exists() and not args.force:
            skipped += 1
            continue

        content = generate_regiment_tres(unit_id, atlas_path)

        with open(output_path, 'w') as f:
            f.write(content)

        unit_type = classify_unit_type(unit_id)
        faction = classify_faction(unit_id)
        print(f"  {unit_id}: {unit_type} ({faction})")
        success += 1

    print()
    print(f"Created: {success}, Skipped: {skipped}")

    # Generate unit catalog
    print()
    print("Generating unit catalog...")
    catalog_content = generate_unit_catalog(units_to_process)

    with open(CATALOG_PATH, 'w') as f:
        f.write(catalog_content)

    print(f"Created: {CATALOG_PATH}")
    print()
    print("Done!")


if __name__ == "__main__":
    main()
