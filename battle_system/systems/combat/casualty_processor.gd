class_name CasualtyProcessor
extends RefCounted

## Handles side effects of combat: audio, visuals, morale, veterancy.
## Extracted from CombatManager for single responsibility.

# Preload flanking calculator for flank damage mult constant
const FlankingCalculatorScript = preload("res://battle_system/systems/combat/flanking_calculator.gd")

# Morale constants
const MELEE_MORALE_PER_CASUALTY: float = 0.5

# Cached references
var _audio_manager: Node = null
var _flanking = null  # FlankingCalculator


func _init() -> void:
	_flanking = FlankingCalculatorScript.new()


## Cache AudioManager reference for performance.
func cache_audio_manager(tree: SceneTree) -> void:
	if Engine.has_singleton("AudioManager"):
		_audio_manager = Engine.get_singleton("AudioManager")
	elif tree.root.has_node("AudioManager"):
		_audio_manager = tree.root.get_node("AudioManager")


## Process all side effects for melee casualties.
## Called after damage is applied.
## Note: Statistics tracking and damage_dealt signal are handled by CombatManager.
func process_melee_casualties(
	victim: Node,  # Regiment taking damage
	attacker: Node,  # Regiment dealing damage
	casualties: int,
	flank_morale_mod: float,
	is_flank: bool,
	is_rear: bool
) -> void:
	if casualties <= 0:
		return

	# === AUDIO ===
	_play_melee_audio(victim.global_position, casualties)

	# === VISUAL EFFECTS ===
	_spawn_melee_effects(victim.global_position)

	# === MORALE DAMAGE ===
	var morale_damage: float = float(casualties) * MELEE_MORALE_PER_CASUALTY * flank_morale_mod
	MoraleSystem.apply_morale_damage(victim, morale_damage, "melee_casualties")

	# === MORALE EVENTS ===
	_push_casualty_morale_events(victim, casualties, attacker)

	# === FLANKING MORALE PENALTY ===
	if is_flank or is_rear:
		_apply_flank_morale_events(victim, attacker, is_rear)

	# === VETERANCY ===
	if attacker.veterancy:
		for i in casualties:
			attacker.veterancy.add_kill()


## Play melee combat audio.
func _play_melee_audio(position: Vector3, casualties: int) -> void:
	# Sword hit sound
	_play_sfx_random("sword_hit", 5, position)

	# Death cries (limit to avoid spam)
	var cries_to_play: int = mini(casualties, 2)
	for i in cries_to_play:
		_play_sfx_random("death", 5, position)


## Spawn melee visual effects.
func _spawn_melee_effects(position: Vector3) -> void:
	if CombatEffects:
		CombatEffects.spawn_melee_hit(position + Vector3(0, 1.0, 0))


## Push per-soldier morale events when casualties occur.
## Batched to prevent N separate events for N casualties.
func _push_casualty_morale_events(defender: Node, casualties: int, attacker: Node) -> void:
	if not defender.unit_morale or casualties <= 0:
		return

	# Batch casualties into single scaled event (cap at 5x multiplier)
	var event: MoraleEvent = MoraleEvent.friend_killed(defender.global_position)
	event.magnitude *= minf(float(casualties), 5.0)
	defender.unit_morale.apply_event_to_nearby(
		event,
		defender.global_position,
		MoraleConstants.FRIEND_KILLED_RADIUS
	)

	# Give kill morale boost to attacker (also batched)
	if attacker.unit_morale:
		var kill_event: MoraleEvent = MoraleEvent.kill_enemy(defender.global_position)
		kill_event.magnitude *= minf(float(casualties), 5.0)
		attacker.unit_morale.apply_event_to_nearby(
			kill_event,
			attacker.global_position,
			MoraleConstants.FRIEND_KILLED_RADIUS
		)


## Apply morale events when a unit is flanked.
func _apply_flank_morale_events(flanked: Node, flanker: Node, is_rear: bool) -> void:
	if not flanked.unit_morale:
		return

	# Flanked units take a morale hit from the shock
	var flank_penalty: float = -15.0 if is_rear else -8.0

	# Apply continuous flanking morale penalty
	flanked.unit_morale.set_continuous_modifier_all(
		MoraleEvent.Source.ENEMY_NEARBY,
		flank_penalty
	)

	# Emit signal for UI/debug
	BattleSignals.unit_flanked.emit(flanked, flanker, is_rear)


## Apply high ground morale modifiers during melee combat.
func apply_height_morale_modifier(attacker: Node, defender: Node, height_threshold: float) -> void:
	var height_diff: float = attacker.global_position.y - defender.global_position.y

	# Attacker on high ground
	if height_diff > height_threshold:
		if attacker.unit_morale:
			attacker.unit_morale.set_continuous_modifier_all(
				MoraleEvent.Source.HIGH_GROUND,
				MoraleConstants.CONTINUOUS_HIGH_GROUND
			)
		if defender.unit_morale:
			defender.unit_morale.set_continuous_modifier_all(
				MoraleEvent.Source.HIGH_GROUND,
				-MoraleConstants.CONTINUOUS_HIGH_GROUND
			)
	# Defender on high ground
	elif height_diff < -height_threshold:
		if defender.unit_morale:
			defender.unit_morale.set_continuous_modifier_all(
				MoraleEvent.Source.HIGH_GROUND,
				MoraleConstants.CONTINUOUS_HIGH_GROUND
			)
		if attacker.unit_morale:
			attacker.unit_morale.set_continuous_modifier_all(
				MoraleEvent.Source.HIGH_GROUND,
				-MoraleConstants.CONTINUOUS_HIGH_GROUND
			)
	# No significant height difference - clear modifiers
	else:
		if attacker.unit_morale:
			attacker.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.HIGH_GROUND)
		if defender.unit_morale:
			defender.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.HIGH_GROUND)


# === AUDIO HELPERS ===

func _play_sfx(sfx_name: String, position: Vector3 = Vector3.ZERO) -> void:
	if _audio_manager and _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx(sfx_name, position)


func _play_sfx_random(base_name: String, variant_count: int, position: Vector3 = Vector3.ZERO) -> void:
	if _audio_manager and _audio_manager.has_method("play_sfx_random"):
		_audio_manager.play_sfx_random(base_name, variant_count, position)
