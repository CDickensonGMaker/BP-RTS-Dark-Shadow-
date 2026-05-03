class_name VeterancySystem
extends RefCounted

## Tracks unit experience and veterancy level.
## Per bible §3.4:
## - Level 0 (Fresh): No bonuses
## - Level 1 (Blooded): +5% melee, +5 morale
## - Level 2 (Veteran): +10% melee, +10 morale, +5% ranged
## - Level 3 (Elite): +15% melee, +15 morale, +10% ranged, visual badge

enum Level {
	FRESH,    # 0
	BLOODED,  # 1
	VETERAN,  # 2
	ELITE,    # 3
}

const LEVEL_NAMES := {
	Level.FRESH: "Fresh",
	Level.BLOODED: "Blooded",
	Level.VETERAN: "Veteran",
	Level.ELITE: "Elite",
}

# XP thresholds for each level
const XP_THRESHOLDS := {
	Level.FRESH: 0,
	Level.BLOODED: 100,
	Level.VETERAN: 300,
	Level.ELITE: 600,
}

# Bonuses per level
const MELEE_BONUS := {
	Level.FRESH: 0.0,
	Level.BLOODED: 0.05,
	Level.VETERAN: 0.10,
	Level.ELITE: 0.15,
}

const MORALE_BONUS := {
	Level.FRESH: 0.0,
	Level.BLOODED: 5.0,
	Level.VETERAN: 10.0,
	Level.ELITE: 15.0,
}

const RANGED_BONUS := {
	Level.FRESH: 0.0,
	Level.BLOODED: 0.0,
	Level.VETERAN: 0.05,
	Level.ELITE: 0.10,
}

# XP gains per action
const XP_PER_KILL: int = 10
const XP_PER_BATTLE_SURVIVED: int = 25
const XP_PER_CHARGE_SURVIVED: int = 15
const XP_FOR_ROUTING_ENEMY: int = 20

var current_xp: int = 0
var current_level: Level = Level.FRESH
var kills: int = 0
var battles_survived: int = 0

signal level_up(old_level: Level, new_level: Level)
signal xp_gained(amount: int, total: int)


func add_xp(amount: int) -> void:
	current_xp += amount
	xp_gained.emit(amount, current_xp)
	_check_level_up()


func add_kill() -> void:
	kills += 1
	add_xp(XP_PER_KILL)


func on_battle_survived() -> void:
	battles_survived += 1
	add_xp(XP_PER_BATTLE_SURVIVED)


func on_charge_survived() -> void:
	add_xp(XP_PER_CHARGE_SURVIVED)


func on_routed_enemy() -> void:
	add_xp(XP_FOR_ROUTING_ENEMY)


func _check_level_up() -> void:
	var new_level: Level = current_level

	# Check from highest to lowest
	if current_xp >= XP_THRESHOLDS[Level.ELITE]:
		new_level = Level.ELITE
	elif current_xp >= XP_THRESHOLDS[Level.VETERAN]:
		new_level = Level.VETERAN
	elif current_xp >= XP_THRESHOLDS[Level.BLOODED]:
		new_level = Level.BLOODED
	else:
		new_level = Level.FRESH

	if new_level != current_level:
		var old_level: Level = current_level
		current_level = new_level
		level_up.emit(old_level, new_level)


func demote_one_level() -> void:
	## Called when unit is replenished below 30% strength.
	if current_level > Level.FRESH:
		var old_level: Level = current_level
		current_level = (current_level - 1) as Level
		# Reset XP to threshold of new level
		current_xp = XP_THRESHOLDS[current_level]
		level_up.emit(old_level, current_level)


func get_melee_bonus() -> float:
	return MELEE_BONUS.get(current_level, 0.0)


func get_ranged_bonus() -> float:
	return RANGED_BONUS.get(current_level, 0.0)


func get_morale_bonus() -> float:
	return MORALE_BONUS.get(current_level, 0.0)


func get_level_name() -> String:
	return LEVEL_NAMES.get(current_level, "Unknown")


func is_elite() -> bool:
	return current_level == Level.ELITE


func get_xp_to_next_level() -> int:
	match current_level:
		Level.FRESH:
			return XP_THRESHOLDS[Level.BLOODED] - current_xp
		Level.BLOODED:
			return XP_THRESHOLDS[Level.VETERAN] - current_xp
		Level.VETERAN:
			return XP_THRESHOLDS[Level.ELITE] - current_xp
		Level.ELITE:
			return 0  # Max level
	return 0


func get_save_data() -> Dictionary:
	return {
		"xp": current_xp,
		"level": current_level,
		"kills": kills,
		"battles": battles_survived,
	}


func load_save_data(data: Dictionary) -> void:
	current_xp = data.get("xp", 0)
	current_level = data.get("level", Level.FRESH) as Level
	kills = data.get("kills", 0)
	battles_survived = data.get("battles", 0)
