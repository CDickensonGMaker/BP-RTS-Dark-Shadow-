class_name AbilityManager
extends RefCounted

## Manages active abilities and spells for a regiment.
## Handles cooldowns, activation, and effects.
## Integrates with SpellManager for magic abilities.

const SpellManagerClass = preload("res://battle_system/systems/spell_manager.gd")

var regiment: Node = null
var _ability_effects: Node = null  # Cached reference to AbilityEffects autoload


func _get_ability_effects() -> Node:
	## Get the AbilityEffects autoload via regiment's scene tree.
	if _ability_effects and is_instance_valid(_ability_effects):
		return _ability_effects
	if regiment and regiment.is_inside_tree():
		_ability_effects = regiment.get_node_or_null("/root/AbilityEffects")
	return _ability_effects
var available_abilities: Array[AbilityType.Type] = []
var cooldowns: Dictionary = {}  # AbilityType.Type -> float (remaining cooldown)
var active_abilities: Dictionary = {}  # AbilityType.Type -> float (remaining duration)
var toggle_states: Dictionary = {}  # AbilityType.Type -> bool (for toggle abilities)

## Spell manager for magic abilities
var spell_manager = null  # SpellManagerClass instance

signal ability_activated(ability: AbilityType.Type)
signal ability_ended(ability: AbilityType.Type)
signal ability_ready(ability: AbilityType.Type)
signal cooldown_updated(ability: AbilityType.Type, remaining: float, total: float)
signal spell_cast(spell: SpellData)
signal spell_ready(spell: SpellData)


func _init(p_regiment: Node) -> void:
	regiment = p_regiment
	_setup_abilities()
	_setup_spell_manager()


func _setup_abilities() -> void:
	if not regiment or not regiment.data:
		return

	# Get abilities based on unit type
	available_abilities = AbilityType.get_abilities_for_unit_type(regiment.data.unit_type)

	# Initialize cooldowns
	for ability in available_abilities:
		cooldowns[ability] = 0.0
		toggle_states[ability] = false


func _setup_spell_manager() -> void:
	## Initialize spell manager for this regiment.
	spell_manager = SpellManagerClass.new(regiment)

	# Connect spell manager signals
	spell_manager.spell_cast.connect(_on_spell_cast)
	spell_manager.spell_ready.connect(_on_spell_ready)


func update(delta: float) -> void:
	# Update cooldowns
	for ability in cooldowns.keys():
		if cooldowns[ability] > 0.0:
			cooldowns[ability] = maxf(0.0, cooldowns[ability] - delta)
			if cooldowns[ability] == 0.0:
				ability_ready.emit(ability)

	# Update active abilities (duration-based)
	var ended_abilities: Array[AbilityType.Type] = []
	for ability in active_abilities.keys():
		active_abilities[ability] -= delta
		if active_abilities[ability] <= 0.0:
			ended_abilities.append(ability)

	for ability in ended_abilities:
		_end_ability(ability)

	# Update spell manager cooldowns
	if spell_manager:
		spell_manager.update(delta)


func can_use(ability: AbilityType.Type) -> bool:
	if ability not in available_abilities:
		return false
	if cooldowns.get(ability, 0.0) > 0.0:
		return false
	if regiment.state == Regiment.State.ROUTING or regiment.state == Regiment.State.DEAD:
		return false

	var data: Dictionary = AbilityType.get_ability_data(ability)

	# Check stamina cost
	var stamina_cost: float = data.get("stamina_cost", 0.0)
	if stamina_cost > 0.0 and regiment.stamina:
		if regiment.stamina.current_stamina < stamina_cost:
			return false

	# Check ammo cost for ranged abilities
	var ammo_cost: int = data.get("ammo_cost", 0)
	if ammo_cost > 0:
		if regiment.current_ammo < ammo_cost:
			return false

	return true


func activate(ability: AbilityType.Type, target: Variant = null) -> bool:
	if not can_use(ability):
		return false

	var data: Dictionary = AbilityType.get_ability_data(ability)

	# Consume resources
	var stamina_cost: float = data.get("stamina_cost", 0.0)
	if stamina_cost > 0.0 and regiment.stamina:
		regiment.stamina.consume_stamina(stamina_cost)

	var ammo_cost: int = data.get("ammo_cost", 0)
	if ammo_cost > 0:
		regiment.current_ammo -= ammo_cost

	# Apply ability effect
	_apply_ability_effect(ability, target)

	# Start cooldown
	cooldowns[ability] = data.get("cooldown", 0.0)

	# Track duration if not instant/toggle
	var duration: float = data.get("duration", 0.0)
	if duration > 0.0:
		active_abilities[ability] = duration

	ability_activated.emit(ability)
	return true


func toggle(ability: AbilityType.Type) -> bool:
	## Toggle an ability on/off.
	var data: Dictionary = AbilityType.get_ability_data(ability)
	if data.get("duration", 1.0) != 0.0:
		return false  # Not a toggle ability

	toggle_states[ability] = not toggle_states.get(ability, false)

	if toggle_states[ability]:
		ability_activated.emit(ability)
		_apply_toggle_on(ability)
	else:
		ability_ended.emit(ability)
		_apply_toggle_off(ability)

	return true


func _apply_ability_effect(ability: AbilityType.Type, target: Variant) -> void:
	match ability:
		AbilityType.Type.CHARGE:
			_do_charge(target)
		AbilityType.Type.WEDGE_CHARGE:
			_do_wedge_charge(target)
		AbilityType.Type.BRACE:
			_do_brace()
		AbilityType.Type.VOLLEY_FIRE:
			_do_volley_fire(target)
		AbilityType.Type.WAR_CRY:
			_do_war_cry()
		AbilityType.Type.RALLY:
			_do_rally()
		AbilityType.Type.INSPIRE:
			_do_inspire()


func _end_ability(ability: AbilityType.Type) -> void:
	active_abilities.erase(ability)
	ability_ended.emit(ability)

	match ability:
		AbilityType.Type.BRACE:
			_end_brace()
		AbilityType.Type.WAR_CRY:
			_end_war_cry()
		AbilityType.Type.INSPIRE:
			_end_inspire()


func _apply_toggle_on(ability: AbilityType.Type) -> void:
	match ability:
		AbilityType.Type.SHIELD_WALL:
			regiment.current_formation = FormationType.Type.SHIELD_WALL
		AbilityType.Type.HOLD_FIRE:
			regiment.hold_fire = true


func _apply_toggle_off(ability: AbilityType.Type) -> void:
	match ability:
		AbilityType.Type.SHIELD_WALL:
			regiment.current_formation = FormationType.Type.LINE
		AbilityType.Type.HOLD_FIRE:
			regiment.hold_fire = false


# === Ability Implementations ===

func _do_charge(target: Variant) -> void:
	if target is Vector3:
		regiment.give_order(OrderType.Type.CHARGE, target)
	elif target is Node:
		regiment.give_order(OrderType.Type.CHARGE, target.global_position)

	# Spawn charge visual effect
	var _fx = _get_ability_effects()
	if _fx:
		_fx.spawn_charge_effect(regiment)


func _do_wedge_charge(target: Variant) -> void:
	regiment.current_formation = FormationType.Type.WEDGE
	_do_charge(target)


func _do_brace() -> void:
	# Set braced state - handled by combat system
	regiment.is_braced = true
	regiment.give_order(OrderType.Type.HOLD_POSITION)

	# Spawn brace visual effect
	var _fx = _get_ability_effects()
	if _fx:
		_fx.spawn_brace_effect(regiment)


func _end_brace() -> void:
	regiment.is_braced = false

	# Stop brace visual effect
	var _fx = _get_ability_effects()
	if _fx:
		_fx.stop_brace_effect(regiment)


func _do_volley_fire(target: Variant) -> void:
	if target is Node and regiment.data.ballistic_skill > 0:
		# Fire synchronized volley with morale damage bonus
		var volley_data: Dictionary = {
			"volley": true,
			"morale_multiplier": 1.5,
		}
		if CombatManager:
			for i in range(5):  # 5 shots in a volley
				CombatManager.fire_ranged(regiment, target)


func _do_war_cry() -> void:
	var data: Dictionary = AbilityType.get_ability_data(AbilityType.Type.WAR_CRY)
	var radius: float = data.get("effect_radius", 25.0)
	var my_faction: int = 0 if regiment.is_player_controlled else 1

	# Use spatial hash for efficient radius query
	var nearby_allies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		regiment.global_position,
		radius,
		my_faction
	)

	# Apply morale boost to nearby friendly units
	for reg in nearby_allies:
		if not is_instance_valid(reg):
			continue
		if reg is Regiment and reg.unit_morale:
			var event: MoraleEvent = MoraleEvent.create(
				MoraleEvent.Source.VICTORY_CHEER,
				MoraleConstants.EVENT_VICTORY_CHEER,
				regiment.global_position
			)
			reg.unit_morale.apply_event_to_all(event)

	# Spawn war cry visual effect
	var _fx = _get_ability_effects()
	if _fx:
		_fx.spawn_war_cry_effect(regiment.global_position)


func _end_war_cry() -> void:
	pass  # Effect is one-time


func _do_rally() -> void:
	var data: Dictionary = AbilityType.get_ability_data(AbilityType.Type.RALLY)
	var radius: float = data.get("effect_radius", 30.0)
	var my_faction: int = 0 if regiment.is_player_controlled else 1

	# Use spatial hash for efficient radius query
	var nearby_allies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		regiment.global_position,
		radius,
		my_faction
	)

	# Attempt to rally nearby routing units
	for reg in nearby_allies:
		if not is_instance_valid(reg):
			continue
		if reg is Regiment and reg.state == Regiment.State.ROUTING:
			reg.set_state(Regiment.State.RALLYING)

	# Spawn rally visual effect
	var _fx = _get_ability_effects()
	if _fx:
		_fx.spawn_rally_effect(regiment.global_position)


func _do_inspire() -> void:
	# Temporary combat boost handled via modifier
	regiment.inspire_active = true

	# Spawn inspire visual effect
	var _fx = _get_ability_effects()
	if _fx:
		_fx.spawn_inspire_effect(regiment)


func _end_inspire() -> void:
	regiment.inspire_active = false

	# Stop inspire visual effect
	var _fx = _get_ability_effects()
	if _fx:
		_fx.stop_inspire_effect(regiment)


func get_cooldown_ratio(ability: AbilityType.Type) -> float:
	var data: Dictionary = AbilityType.get_ability_data(ability)
	var total: float = data.get("cooldown", 1.0)
	if total <= 0.0:
		return 0.0
	return cooldowns.get(ability, 0.0) / total


func is_ability_active(ability: AbilityType.Type) -> bool:
	if ability in active_abilities:
		return true
	return toggle_states.get(ability, false)


func get_tree() -> SceneTree:
	if regiment:
		return regiment.get_tree()
	return null


# === SPELL MANAGEMENT ===

func add_spell(spell: SpellData) -> void:
	## Add a spell to this regiment's available spells.
	if spell_manager:
		spell_manager.add_spell(spell)


func remove_spell(spell_id: String) -> void:
	## Remove a spell from this regiment.
	if spell_manager:
		spell_manager.remove_spell(spell_id)


func setup_spells(spells: Array[SpellData]) -> void:
	## Setup all available spells for this regiment.
	if spell_manager:
		spell_manager.setup_spells(spells)


func can_cast_spell(spell: SpellData, target_pos: Vector3 = Vector3.ZERO) -> bool:
	## Check if a spell can be cast.
	if spell_manager:
		return spell_manager.can_cast_spell(spell, target_pos)
	return false


func cast_spell(spell: SpellData, target_pos: Vector3 = Vector3.ZERO) -> bool:
	## Cast a spell at target position.
	if spell_manager:
		return spell_manager.cast_spell(spell, target_pos)
	return false


func cast_spell_by_id(spell_id: String, target_pos: Vector3 = Vector3.ZERO) -> bool:
	## Cast a spell by its ID.
	if spell_manager:
		return spell_manager.cast_spell_by_id(spell_id, target_pos)
	return false


func get_spell_by_id(spell_id: String) -> SpellData:
	## Get a spell by its ID.
	if spell_manager:
		return spell_manager.get_spell_by_id(spell_id)
	return null


func get_available_spells() -> Array[SpellData]:
	## Get all available spells for this regiment.
	if spell_manager:
		return spell_manager.get_available_spells()
	return []


func get_ready_spells() -> Array[SpellData]:
	## Get all spells that are ready to cast.
	if spell_manager:
		return spell_manager.get_ready_spells()
	return []


func get_spell_cooldown_ratio(spell: SpellData) -> float:
	## Get spell cooldown progress (0.0 = ready, 1.0 = just cast).
	if spell_manager:
		return spell_manager.get_cooldown_ratio(spell)
	return 0.0


func is_spell_ready(spell: SpellData) -> bool:
	## Check if a spell is ready to cast.
	if spell_manager:
		return spell_manager.is_spell_ready(spell)
	return false


func _on_spell_cast(spell: SpellData) -> void:
	## Handle spell cast event.
	spell_cast.emit(spell)
	BattleSignals.ability_used.emit(regiment, -1)  # -1 indicates spell


func _on_spell_ready(spell: SpellData) -> void:
	## Handle spell ready event.
	spell_ready.emit(spell)
