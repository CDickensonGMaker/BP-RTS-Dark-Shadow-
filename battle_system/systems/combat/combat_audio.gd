class_name CombatAudio
extends RefCounted

## Handles combat audio playback - melee sounds, ranged fire, impacts, ambience.
## Extracted from CombatManager for single responsibility.

# Preload for sprite direction lookup
const SpriteUnitAtlasScript = preload("res://battle_system/data/sprite_unit_atlas.gd")

# Cached AudioManager reference
var _audio_manager: Node = null

# Debug mode
var debug_combat: bool = false


## Cache AudioManager reference to avoid per-call lookups.
func cache_audio_manager(tree: SceneTree) -> void:
	if Engine.has_singleton("AudioManager"):
		_audio_manager = Engine.get_singleton("AudioManager")
		if debug_combat:
			print("[CombatAudio] Cached AudioManager from singleton")
	elif tree.root.has_node("AudioManager"):
		_audio_manager = tree.root.get_node("AudioManager")
		if debug_combat:
			print("[CombatAudio] Cached AudioManager from /root/AudioManager")
	else:
		if debug_combat:
			print("[CombatAudio] WARNING: AudioManager not found!")


## Play a combat sound effect at a position.
func play_sfx(sfx_name: String, position: Vector3 = Vector3.ZERO) -> void:
	if _audio_manager and _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx(sfx_name, position)


## Play a random variant of a combat sound effect.
func play_sfx_random(base_name: String, variant_count: int, position: Vector3 = Vector3.ZERO) -> void:
	if _audio_manager and _audio_manager.has_method("play_sfx_random"):
		if debug_combat:
			print("[CombatAudio] Calling AudioManager.play_sfx_random('%s', %d)" % [base_name, variant_count])
		_audio_manager.play_sfx_random(base_name, variant_count, position)
	elif debug_combat:
		print("[CombatAudio] SKIPPED audio: _audio_manager=%s has_method=%s" % [
			"valid" if _audio_manager else "NULL",
			_audio_manager.has_method("play_sfx_random") if _audio_manager else "N/A"
		])


## Play morale event audio.
func play_morale_sfx(event_name: String) -> void:
	if _audio_manager and _audio_manager.has_method("play_morale_event"):
		_audio_manager.play_morale_event(event_name)


## Play death cry sounds based on casualty count (limited to prevent spam).
func play_death_cry(position: Vector3, casualty_count: int = 1) -> void:
	var cries_to_play: int = mini(casualty_count, 2)
	for i in cries_to_play:
		play_sfx_random("death", 5, position)


## Play layered melee impact sounds for fuller combat feel.
func play_layered_melee_hit(position: Vector3) -> void:
	if _audio_manager and _audio_manager.has_method("play_layered_melee_hit"):
		_audio_manager.play_layered_melee_hit(position)
	else:
		play_sfx_random("sword_hit", 5, position)


## Play cannon boom cut short sound for artillery fire.
func play_cannon_boom(position: Vector3) -> void:
	if _audio_manager and _audio_manager.has_method("play_cannon_boom"):
		_audio_manager.play_cannon_boom(position)
	else:
		play_sfx_random("cannon_fire", 2, position)


## Update melee ambience system with current combat state.
func update_melee_ambience(delta: float, melee_count: int, melee_positions: Array) -> void:
	if not _audio_manager:
		return

	if melee_count > 0:
		# Start ambience if not already active
		if _audio_manager.has_method("start_melee_ambience"):
			_audio_manager.start_melee_ambience()

		# Update with positions
		if _audio_manager.has_method("update_melee_ambience"):
			_audio_manager.update_melee_ambience(delta, melee_count, melee_positions)
	else:
		# No active melee - stop ambience
		if _audio_manager.has_method("stop_melee_ambience"):
			_audio_manager.stop_melee_ambience()


## Play weapon-class-appropriate ranged fire audio.
## Different weapon classes use different fire sounds.
func play_ranged_fire_audio(attacker: Node, weapon_class: int) -> void:
	if not is_instance_valid(attacker):
		return

	var position: Vector3 = attacker.global_position

	if debug_combat:
		print("[CombatAudio] play_ranged_fire_audio: weapon_class=%d audio_manager=%s" % [
			weapon_class, "valid" if _audio_manager else "NULL"
		])

	match weapon_class:
		RegimentData.WeaponClass.CANNON, RegimentData.WeaponClass.MORTAR, RegimentData.WeaponClass.WAR_MACHINE:
			# Artillery fire - use cannon boom cut short for punchier sound
			if debug_combat:
				print("[CombatAudio] Playing cannon_boom audio")
			play_cannon_boom(position)
		RegimentData.WeaponClass.MAGIC_MISSILE:
			# Magic missile cast - mystical whoosh
			play_sfx_random("magic_missile", 2, position)
		RegimentData.WeaponClass.HANDGUN:
			# Handgun fire - use cannon boom (no dedicated gunshot yet)
			play_cannon_boom(position)
		RegimentData.WeaponClass.CROSSBOW:
			# Crossbow - deeper thunk than bow
			play_sfx_random("bow_release", 2, position)
		_:
			# Default: bow/thrown weapons
			play_sfx_random("bow_release", 2, position)


## Play explosion audio at impact location.
## Called when projectiles with AOE hit their target.
func play_explosion_audio(position: Vector3, radius: float = 3.0) -> void:
	# Larger explosions use more variants
	var variant_count: int = 3 if radius >= 4.0 else 2
	play_sfx_random("explosion", variant_count, position)


## Play arrow impact audio.
func play_arrow_hit(position: Vector3) -> void:
	play_sfx_random("arrow_hit", 3, position)


## Play cavalry charge impact audio.
func play_charge_impact(position: Vector3) -> void:
	play_sfx("cavalry_charge_01", position)


## Play melee clash sound for initial contact.
func play_melee_clash(position: Vector3) -> void:
	play_sfx_random("sword_hit", 5, position)


## Play breath weapon audio based on damage type.
func play_breath_weapon(position: Vector3, is_fire: bool) -> void:
	if is_fire:
		play_sfx_random("breath_fire", 2, position)
	else:
		play_sfx_random("breath_poison", 2, position)


## Convert facing vector to 8-direction index matching sprite atlas convention.
## Direction mapping: 0=North, 1=NE, 2=East, 3=SE, 4=South, 5=SW, 6=West, 7=NW (clockwise from North)
func facing_to_direction_index(facing: Vector3) -> int:
	return SpriteUnitAtlasScript.direction_from_vector(facing)


## Check if audio manager is available.
func is_available() -> bool:
	return _audio_manager != null
