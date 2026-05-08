class_name HatredCalculator
extends RefCounted

## Calculates hatred attack bonuses based on general traits and target race/faction.
## Extracted from CombatManager for single responsibility.

## Hatred keyword mapping - maps regiment name keywords to hatred types.
## Includes abbreviated forms used in the unit zoo (orc2, elf1, dwa2, gob1, etc.)
const HATRED_KEYWORDS: Dictionary = {
	# Orc/Greenskin variations
	"orc": "orc",
	"ork": "orc",
	"gob": "orc",       # Abbreviated goblin (gob1)
	"goblin": "orc",
	"greenskin": "orc",
	"squig": "orc",     # Squigs are greenskin
	"boar": "orc",      # Boar boyz
	"wolf": "orc",      # Wolf riders
	"black": "orc",     # Black orcs (partial match OK)
	# Undead variations
	"undead": "undead",
	"skeleton": "undead",
	"zombie": "undead",
	"vampire": "undead",
	"ghost": "undead",
	"wraith": "undead",
	"necro": "undead",
	# Elf variations
	"elf": "elf",
	"elven": "elf",
	"eldar": "elf",
	# Dwarf variations (dwa2, dwxbow, dwwar, etc.)
	"dw": "dwarf",      # Abbreviated dwarf (dwa2, dwxbow, dwwar)
	"dwarf": "dwarf",
	"dwarven": "dwarf",
	"iron": "dwarf",    # Ironbreakers are dwarfs
	"hamm": "dwarf",    # Hammerers are dwarfs
	# Human variations
	"human": "human",
	"empire": "human",
	"knight": "human",
	"peasant": "human",
	"militia": "human",
	"reik": "human",    # Reiksguard
	"grt": "human",     # Greatswords (grtsword)
	"halb": "human",    # Halberdiers
	"xbow": "human",    # Crossbowmen (could be mercenary, but often human)
}


## Get hatred attack bonus for attacker against target based on general traits.
## Checks target regiment name for race/faction keywords (Orc, Undead, Elf, etc.)
## Returns 0.0 if no hatred applies, or the bonus multiplier (e.g. 0.25 for +25%).
func get_hatred_bonus(is_player: bool, target: Node) -> float:
	if not BattleModifiers or not BattleModifiers.is_active():
		return 0.0

	if not is_instance_valid(target) or not target.data:
		return 0.0

	# Build target type string from regiment name
	var target_name: String = target.data.regiment_name.to_lower() if target.data.regiment_name else ""

	# Check against hatred keywords - map regiment name keywords to hatred types
	for keyword in HATRED_KEYWORDS:
		if keyword in target_name:
			var hatred_type: String = HATRED_KEYWORDS[keyword]
			var bonus: float = BattleModifiers.get_hatred_attack_bonus(is_player, hatred_type)
			if bonus > 0.0:
				return bonus

	return 0.0


## Detect the race/faction type of a regiment from its name.
## Returns the hatred type string (e.g., "orc", "undead", "elf") or empty string.
func detect_race_type(regiment: Node) -> String:
	if not is_instance_valid(regiment) or not regiment.data:
		return ""

	var target_name: String = regiment.data.regiment_name.to_lower() if regiment.data.regiment_name else ""

	for keyword in HATRED_KEYWORDS:
		if keyword in target_name:
			return HATRED_KEYWORDS[keyword]

	return ""


## Check if attacker has hatred bonus against target.
## Returns true if any hatred bonus applies.
func has_hatred_against(is_player: bool, target: Node) -> bool:
	return get_hatred_bonus(is_player, target) > 0.0


## Get a human-readable hatred description for tooltips.
## Returns empty string if no hatred applies.
func get_hatred_tooltip(is_player: bool, target: Node) -> String:
	var bonus: float = get_hatred_bonus(is_player, target)
	if bonus <= 0.0:
		return ""

	var race_type: String = detect_race_type(target)
	if race_type.is_empty():
		return ""

	# Format: "+25% damage (hatred: humans hate goblins)"
	var attacker_race: String = "your forces" if is_player else "enemy forces"
	return "+%.0f%% damage (hatred: %s hate %s)" % [bonus * 100.0, attacker_race, race_type]
