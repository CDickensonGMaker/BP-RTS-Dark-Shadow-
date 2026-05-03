class_name SpellManager
extends RefCounted

## Manages spells for a regiment.
## Handles cooldowns, validation, and casting through SpellCaster.
## Integrates with the existing AbilityManager pattern.

const SpellCasterClass = preload("res://battle_system/systems/spell_caster.gd")

# === SIGNALS ===

signal spell_cast(spell: SpellData)
signal spell_ready(spell: SpellData)
signal cooldown_updated(spell_id: String, remaining: float, total: float)


# === INTERNAL STATE ===

## Reference to owning regiment
var regiment: Regiment = null

## Available spells for this regiment
var available_spells: Array[SpellData] = []

## Spell cooldowns: spell_id -> remaining time
var cooldowns: Dictionary = {}

## Shared spell caster instance
var spell_caster = null  # SpellCasterClass instance


func _init(p_regiment: Regiment) -> void:
	regiment = p_regiment
	spell_caster = SpellCasterClass.new()

	# Connect spell caster signals
	spell_caster.spell_cast_completed.connect(_on_spell_cast_completed)
	spell_caster.spell_hit.connect(_on_spell_hit)


## Load spells available to this regiment.
func setup_spells(spells: Array[SpellData]) -> void:
	available_spells = spells

	# Initialize cooldowns
	for spell in available_spells:
		cooldowns[spell.id] = 0.0


## Add a spell to available spells.
func add_spell(spell: SpellData) -> void:
	if spell not in available_spells:
		available_spells.append(spell)
		cooldowns[spell.id] = 0.0


## Remove a spell from available spells.
func remove_spell(spell_id: String) -> void:
	for i in range(available_spells.size() - 1, -1, -1):
		if available_spells[i].id == spell_id:
			available_spells.remove_at(i)
			cooldowns.erase(spell_id)
			break


## Update cooldowns (call every frame).
func update(delta: float) -> void:
	for spell_id in cooldowns.keys():
		if cooldowns[spell_id] > 0.0:
			cooldowns[spell_id] = maxf(0.0, cooldowns[spell_id] - delta)
			if cooldowns[spell_id] == 0.0:
				# Find spell and emit ready signal
				for spell in available_spells:
					if spell.id == spell_id:
						spell_ready.emit(spell)
						break


## Check if a spell can be cast.
func can_cast_spell(spell: SpellData, target_pos: Vector3 = Vector3.ZERO) -> bool:
	if not spell or not regiment:
		return false

	# Check if spell is available
	if spell not in available_spells:
		return false

	# Check cooldown
	if cooldowns.get(spell.id, 0.0) > 0.0:
		return false

	# Check unit state
	if regiment.state == Regiment.State.ROUTING or regiment.state == Regiment.State.DEAD:
		return false

	# Check unit type restrictions
	if not spell.can_unit_use(regiment):
		return false

	# Check stamina cost
	if spell.stamina_cost > 0.0 and regiment.stamina:
		if regiment.stamina.current_stamina < spell.stamina_cost:
			return false

	# Check ammo cost
	if spell.ammo_cost > 0:
		if regiment.current_ammo < spell.ammo_cost:
			return false

	# Check range (if target provided)
	if target_pos != Vector3.ZERO and spell.target_type != SpellData.TargetType.AOE_SELF:
		var dist: float = regiment.global_position.distance_to(target_pos)
		if dist > spell.range_distance:
			return false

	return true


## Cast a spell at target position.
func cast_spell(spell: SpellData, target_pos: Vector3 = Vector3.ZERO) -> bool:
	# Use regiment position for self-targeted spells
	if spell.target_type == SpellData.TargetType.AOE_SELF:
		target_pos = regiment.global_position

	if not can_cast_spell(spell, target_pos):
		return false

	# Attempt cast through spell caster
	var success: bool = spell_caster.cast_spell(spell, regiment, target_pos)

	if success:
		# Start cooldown
		cooldowns[spell.id] = spell.cooldown
		spell_cast.emit(spell)

	return success


## Cast spell by ID.
func cast_spell_by_id(spell_id: String, target_pos: Vector3 = Vector3.ZERO) -> bool:
	var spell := get_spell_by_id(spell_id)
	if spell:
		return cast_spell(spell, target_pos)
	return false


## Get a spell by its ID.
func get_spell_by_id(spell_id: String) -> SpellData:
	for spell in available_spells:
		if spell.id == spell_id:
			return spell
	return null


## Get cooldown progress (0.0 = ready, 1.0 = just cast).
func get_cooldown_ratio(spell: SpellData) -> float:
	if spell.cooldown <= 0.0:
		return 0.0
	var remaining: float = cooldowns.get(spell.id, 0.0)
	return remaining / spell.cooldown


## Get remaining cooldown time.
func get_cooldown_remaining(spell: SpellData) -> float:
	return cooldowns.get(spell.id, 0.0)


## Check if a spell is ready (off cooldown).
func is_spell_ready(spell: SpellData) -> bool:
	return cooldowns.get(spell.id, 0.0) <= 0.0


## Get all available spells.
func get_available_spells() -> Array[SpellData]:
	return available_spells


## Get all spells that are currently ready to cast.
func get_ready_spells() -> Array[SpellData]:
	var result: Array[SpellData] = []
	for spell in available_spells:
		if is_spell_ready(spell):
			result.append(spell)
	return result


## Reset all cooldowns (for new battle).
func reset_cooldowns() -> void:
	for spell_id in cooldowns.keys():
		cooldowns[spell_id] = 0.0


# === SIGNAL HANDLERS ===

func _on_spell_cast_completed(spell: SpellData, caster: Regiment, target: Vector3) -> void:
	# Emit signal for UI/logging
	if caster == regiment:
		var total: float = spell.cooldown
		var remaining: float = cooldowns.get(spell.id, 0.0)
		cooldown_updated.emit(spell.id, remaining, total)


func _on_spell_hit(spell: SpellData, target: Regiment, damage: int) -> void:
	# Could track statistics here
	pass


# === CLEANUP ===

func cleanup() -> void:
	if spell_caster:
		spell_caster.cleanup()
