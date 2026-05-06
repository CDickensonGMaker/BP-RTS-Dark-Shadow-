## CombatManager.gd - Handles combat calculations between regiments
## Simplified version without terrain/building dependencies
##
## Fixes applied:
## - Removed BattleTerrain dependency
## - Removed BattleBuilding dependency  
## - Removed static function that called get_tree()
## - Added proper type hints
## - Added proper projectiles spawning

extends Node

signal combat_started(attacker: Regiment, defender: Regiment, combat_type: String)
signal combat_ended(attacker: Regiment, defender: Regiment, result: Dictionary)
signal damage_dealt(target: Regiment, amount: int, source: Regiment, damage_type: String)

# === EXTRACTED COMBAT SYSTEMS ===
# These handle specific combat calculations with single responsibility
# Preload scripts to avoid parse-order issues with class_name
const FlankingCalculatorScript = preload("res://battle_system/systems/combat/flanking_calculator.gd")
const BattleStatisticsScript = preload("res://battle_system/systems/combat/battle_statistics.gd")
const ChargeSystemScript = preload("res://battle_system/systems/combat/charge_system.gd")
const MeleeResolverScript = preload("res://battle_system/systems/combat/melee_resolver.gd")
const RangedResolverScript = preload("res://battle_system/systems/combat/ranged_resolver.gd")
const CasualtyProcessorScript = preload("res://battle_system/systems/combat/casualty_processor.gd")
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")

var flanking  # FlankingCalculator
var statistics  # BattleStatistics
var charge_system  # ChargeSystem
var melee_resolver  # MeleeResolver
var ranged_resolver  # RangedResolver
var casualty_processor  # CasualtyProcessor

# === AUDIO INTEGRATION ===
# Helper functions to safely call AudioManager methods
# Handles case where audio files don't exist yet or AudioManager is unavailable

func _cache_audio_manager() -> void:
	## Cache AudioManager reference to avoid per-call lookups.
	if Engine.has_singleton("AudioManager"):
		_audio_manager = Engine.get_singleton("AudioManager")
	elif has_node("/root/AudioManager"):
		_audio_manager = get_node("/root/AudioManager")
	# Also cache for CasualtyProcessor
	if casualty_processor:
		casualty_processor.cache_audio_manager(get_tree())


func _play_combat_sfx(sfx_name: String, position: Vector3 = Vector3.ZERO) -> void:
	if _audio_manager and _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx(sfx_name, position)


func _play_combat_sfx_random(base_name: String, variant_count: int, position: Vector3 = Vector3.ZERO) -> void:
	if _audio_manager and _audio_manager.has_method("play_sfx_random"):
		_audio_manager.play_sfx_random(base_name, variant_count, position)


func _play_morale_sfx(event_name: String) -> void:
	if _audio_manager and _audio_manager.has_method("play_morale_event"):
		_audio_manager.play_morale_event(event_name)


func _play_death_cry(position: Vector3, casualty_count: int = 1) -> void:
	# Play death cry sounds based on casualty count (limit to avoid spam)
	var cries_to_play: int = mini(casualty_count, 2)
	for i in cries_to_play:
		_play_combat_sfx_random("death", 5, position)


## Play ranged attack animation on the firing regiment
func _play_ranged_attack_animation(regiment: Regiment) -> void:
	if not is_instance_valid(regiment):
		return

	# Play attack animation on sprite overlay (2D sprites)
	if regiment.sprite_overlay:
		regiment.sprite_overlay.play_animation_staggered("attack", 0.02)
		# Return to idle after a short delay
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(regiment) and regiment.sprite_overlay:
				regiment.sprite_overlay.play_animation_all("idle")
		)

	# Play attack animation on 3D formation
	if regiment.formation and regiment.formation.has_method("play_animation_staggered"):
		regiment.formation.play_animation_staggered("Attack", 0.02)
		# Return to idle after a short delay
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_instance_valid(regiment) and regiment.formation:
				regiment.formation.play_animation_all("Idle")
		)


# Active melee combat pairs
# Each entry: { attacker: Regiment, defender: Regiment, charge_applied: bool, charge_timer: float, charge_time: float }
var active_melees: Array[Dictionary] = []

# Combat timing - ADJUSTED FOR BETTER PACING
const MELEE_TICK_RATE: float = 1.875  # resolve combat every 1.875 seconds (25% slower than 1.5)
const COMBAT_DAMAGE_MULTIPLIER: float = 0.50  # 50% of base damage (was 36%)
const FRIENDLY_FIRE_CHANCE: float = 0.15  # 15% chance to hit friendly when shooting into melee

# Charge impact constants
const CHARGE_AP_RATIO: float = 0.7  # 70% of charge impact is armor-piercing
const CHARGE_MORALE_RATIO: float = 0.5  # Morale damage from charge impact

# Melee morale constants
const MELEE_MORALE_PER_CASUALTY: float = 0.5  # Base morale damage per casualty

# Ranged combat constants
const RANGED_HIGH_GROUND_BONUS: float = 1.15  # +15% damage from high ground
const RANGED_LOW_GROUND_PENALTY: float = 0.85  # -15% damage from low ground
const RANGED_MORALE_RATIO: float = 0.3  # Morale damage ratio for ranged hits

# Hit chance constants - use melee_resolver.calculate_hit_chance() for calculations

# Debug mode - set to false for production
var debug_combat: bool = false

# Battle statistics tracking - synced from BattleStatistics system
var battle_stats: Dictionary = {}

var melee_timer: float = 0.0
# Phase 6.4: Terrain access via TerrainHelper (removed _terrain variable)

# Staggered update system - process 1/BUCKET_COUNT of combats per frame
var _update_bucket: int = 0
const BUCKET_COUNT: int = 4  # Reduced from 16 for more responsive combat

# Projectile pool for performance (upgraded pooling system)
var _projectile_pool: ProjectilePool = null
var _projectile_scene: PackedScene = null

# Cached AudioManager reference (optimization - avoid per-call lookups)
var _audio_manager: Node = null

# Projectile configurations per unit type
const PROJECTILE_CONFIG_ARROW: Dictionary = {
	"speed": 35.0,
	"arc_height": 8.0,
	"is_homing": false,
	"max_pierces": 0,
	"aoe_radius": 0.0,
	"lifetime": 4.0,
	"collision_mask": 2
}

const PROJECTILE_CONFIG_CROSSBOW: Dictionary = {
	"speed": 50.0,
	"arc_height": 3.0,
	"is_homing": false,
	"max_pierces": 1,  # Can pierce one target
	"pierce_damage_falloff": 0.3,
	"aoe_radius": 0.0,
	"lifetime": 3.0,
	"collision_mask": 2
}

const PROJECTILE_CONFIG_ARTILLERY: Dictionary = {
	"speed": 20.0,
	"arc_height": 20.0,
	"is_homing": false,
	"max_pierces": 0,
	"aoe_radius": 5.0,  # AOE explosion
	"aoe_damage_falloff": true,
	"lifetime": 6.0,
	"collision_mask": 2
}

const PROJECTILE_CONFIG_MAGIC: Dictionary = {
	"speed": 25.0,
	"arc_height": 2.0,
	"is_homing": true,  # Homing projectile
	"homing_strength": 4.0,
	"max_pierces": 2,  # Can pierce two targets
	"pierce_damage_falloff": 0.2,
	"aoe_radius": 3.0,
	"aoe_damage_falloff": true,
	"lifetime": 5.0,
	"collision_mask": 2
}

const PROJECTILE_CONFIG_JAVELIN: Dictionary = {
	"speed": 28.0,
	"arc_height": 6.0,
	"is_homing": false,
	"max_pierces": 0,
	"aoe_radius": 0.0,
	"lifetime": 3.5,
	"collision_mask": 2
}

func _ready() -> void:
	# Initialize extracted combat systems using preloaded scripts
	flanking = FlankingCalculatorScript.new()
	statistics = BattleStatisticsScript.new()
	charge_system = ChargeSystemScript.new()
	melee_resolver = MeleeResolverScript.new()
	ranged_resolver = RangedResolverScript.new()
	casualty_processor = CasualtyProcessorScript.new()

	# Create projectile pool
	_projectile_pool = ProjectilePool.new()
	_projectile_pool.name = "ProjectilePool"
	add_child(_projectile_pool)

	# Keep scene reference for fallback
	_projectile_scene = load("res://battle_system/nodes/projectile.tscn")

	# Cache AudioManager reference (optimization - avoid per-call lookups)
	call_deferred("_cache_audio_manager")

	call_deferred("_init_battle_stats")

	# Connect to regiment_dead signal for death effects
	if BattleSignals:
		if not BattleSignals.regiment_dead.is_connected(_on_regiment_dead):
			BattleSignals.regiment_dead.connect(_on_regiment_dead)


## Initialize battle statistics at start
func _init_battle_stats() -> void:
	# Delegate to BattleStatistics system
	statistics.debug_combat = debug_combat
	statistics.setup(get_tree())
	# Keep local reference synced for backwards compatibility
	battle_stats = statistics.get_stats()


## Track a kill for statistics and WINNING morale modifier
func _track_kill(attacker: Regiment, defender: Regiment, casualties: int) -> void:
	# Delegate to BattleStatistics system
	statistics.track_kill(attacker, defender, casualties)
	# Keep local reference synced
	battle_stats = statistics.get_stats()

	# Track for WINNING morale modifier
	if attacker.unit_morale:
		attacker.unit_morale.track_casualties_inflicted(casualties)
	if defender.unit_morale:
		defender.unit_morale.track_casualties_received(casualties)

	# Check for battle end
	_check_battle_end()


## Check if battle has ended
func _check_battle_end() -> void:
	# Delegate to BattleStatistics system
	var result: Dictionary = statistics.check_battle_end()
	if result.size() > 0:
		# Battle has ended - emit signal
		BattleSignals.battle_ended.emit(result)
		# Keep local reference synced
		battle_stats = statistics.get_stats()


## Get AI stat multiplier for a regiment.
## Returns 1.0 for player units or AI units without personality.
## AI personality stat_multiplier affects damage dealt by AI units.
func _get_ai_stat_multiplier(regiment: Regiment) -> float:
	if regiment.is_player_controlled:
		return 1.0
	# Get personality from AI controller
	if regiment.ai_controller and regiment.ai_controller.personality:
		return regiment.ai_controller.personality.stat_multiplier
	# Try to get from AIAutoload's GeneralAI for AI faction
	if AIAutoload:
		var faction_general = AIAutoload.get_general_ai(1)  # AI faction is 1
		if faction_general and faction_general.personality:
			return faction_general.personality.stat_multiplier
	return 1.0


## Get height modifier for melee combat (higher ground = bonus)
func _get_height_modifier(attacker: Regiment, defender: Regiment) -> float:
	return melee_resolver.get_height_modifier(attacker, defender)


## Get defense bonus for defending on a slope (Phase 6.4: use helper)
func _get_slope_defense_bonus(defender: Regiment) -> int:
	# MeleeResolver handles height-based defense, but terrain slope needs terrain reference
	var slope: float = TerrainHelperScript.get_slope_at(get_tree(), defender.global_position)
	if slope > 10.0:  # On a significant slope
		return melee_resolver.SLOPE_DEFENSE_BONUS
	return 0


## Delegate flanking calculations to FlankingCalculator
func _calculate_attack_angle(attacker: Regiment, defender: Regiment) -> float:
	return flanking.calculate_attack_angle(attacker, defender)

func _get_flank_damage_modifier(attacker: Regiment, defender: Regiment) -> float:
	return flanking.get_damage_modifier(attacker, defender)

func _is_frontal_attack(attacker: Regiment, defender: Regiment) -> bool:
	return flanking.is_frontal_attack(attacker, defender)

func _get_flank_morale_modifier(attacker: Regiment, defender: Regiment) -> float:
	return flanking.get_morale_modifier(attacker, defender)

func is_flank_attack(attacker: Regiment, defender: Regiment) -> bool:
	return flanking.is_flank_attack(attacker, defender)

func is_rear_attack(attacker: Regiment, defender: Regiment) -> bool:
	return flanking.is_rear_attack(attacker, defender)

## Get projectile configuration based on unit type
func _get_projectile_config(regiment: Regiment) -> Dictionary:
	if not regiment.data:
		return PROJECTILE_CONFIG_ARROW

	# Determine config based on unit type and ranged characteristics
	match regiment.data.unit_type:
		UnitType.Type.ARTILLERY:
			return PROJECTILE_CONFIG_ARTILLERY
		_:
			# Check for specific weapon types via unit name or tags
			var unit_name: String = regiment.data.regiment_name.to_lower() if regiment.data.regiment_name else ""

			if "crossbow" in unit_name:
				return PROJECTILE_CONFIG_CROSSBOW
			elif "javelin" in unit_name or "skirmish" in unit_name:
				return PROJECTILE_CONFIG_JAVELIN
			elif "magic" in unit_name or "wizard" in unit_name or "mage" in unit_name:
				return PROJECTILE_CONFIG_MAGIC
			elif "cannon" in unit_name or "catapult" in unit_name or "trebuchet" in unit_name:
				return PROJECTILE_CONFIG_ARTILLERY
			else:
				return PROJECTILE_CONFIG_ARROW

## Start a melee combat between two regiments
func begin_melee(attacker: Regiment, defender: Regiment) -> void:
	# Don't start combat during deployment phase
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		return

	# Check not already in this melee pair
	for m in active_melees:
		if (m["attacker"] == attacker and m["defender"] == defender) or \
		   (m["attacker"] == defender and m["defender"] == attacker):
			return

	# Handle charge impact at moment of contact
	var charge_negated: bool = false
	var valid_charge: bool = attacker.has_valid_charge()

	if attacker.current_order == OrderType.Type.CHARGE:
		# Check if charge traveled minimum distance
		if not valid_charge:
			pass  # Charge invalid - insufficient distance
		else:
			var was_braced: bool = defender.is_braced
			# Check if bracing applies (frontal charges only)
			var is_frontal_charge: bool = _is_frontal_attack(attacker, defender)

			if was_braced and is_frontal_charge:
				# Defender braced against frontal charge - negate bonus, reduce impact
				charge_negated = true
				# Spawn block effect for braced defender
				if CombatEffects:
					CombatEffects.spawn_block(defender.global_position + Vector3(0, 1.2, 0))
			else:
				# Successful charge impact - calculate impact damage
				var impact_damage: int = attacker.get_charge_impact_damage()
				if impact_damage > 0:
					# Apply impact damage (partially armor-piercing per TotalWarSimulator)
					var ap_damage: int = int(float(impact_damage) * CHARGE_AP_RATIO)
					var normal_damage: int = impact_damage - ap_damage
					# Impact causes instant casualties
					var total_impact_casualties: int = max(1, impact_damage / 3)
					defender.take_casualties(total_impact_casualties)
					defender.take_morale_damage(float(impact_damage) * CHARGE_MORALE_RATIO)

			# Emit charge impact signal
			BattleSignals.charge_impact.emit(attacker, defender, was_braced and is_frontal_charge)

			# Play charge impact audio
			_play_combat_sfx("cavalry_charge_01", defender.global_position)

		# Mark attacker as having charged via CombatState
		CombatState.set_charged(attacker, true, "charge_impact")

	active_melees.append({
		"attacker": attacker,
		"defender": defender,
		"charge_applied": false,
		"charge_negated": charge_negated,
		"charge_timer": 0.0,
		"charge_time": 0.0  # Time since charge impact - for decaying charge bonus
	})

	# Emit signal
	combat_started.emit(attacker, defender, "melee")

## End a melee combat pair
func end_melee(regiment_a: Regiment, regiment_b: Regiment) -> void:
	active_melees = active_melees.filter(func(m: Dictionary) -> bool:
		return not ((m["attacker"] == regiment_a and m["defender"] == regiment_b) or
		            (m["attacker"] == regiment_b and m["defender"] == regiment_a))
	)


## Disengage a regiment from any melee combat (called when player orders retreat)
func disengage_regiment(regiment: Regiment) -> void:
	if not is_instance_valid(regiment):
		return

	# Find and remove all melees involving this regiment
	var melees_to_end: Array[Dictionary] = []
	var opponents_to_check: Array[Regiment] = []
	for melee in active_melees:
		if melee.get("attacker") == regiment or melee.get("defender") == regiment:
			melees_to_end.append(melee)
			# Track opponents that might need to return to IDLE
			var other: Regiment = melee.get("defender") if melee.get("attacker") == regiment else melee.get("attacker")
			if is_instance_valid(other) and other not in opponents_to_check:
				opponents_to_check.append(other)

	# Remove all melees involving this regiment first
	for melee in melees_to_end:
		var att = melee.get("attacker")
		var def = melee.get("defender")
		end_melee(att, def)

	# Now check each opponent - only set to IDLE if they have no other active melees
	for opponent in opponents_to_check:
		if not is_instance_valid(opponent):
			continue
		var still_in_combat: bool = false
		for melee in active_melees:
			if melee.size() > 0 and (melee.get("attacker") == opponent or melee.get("defender") == opponent):
				still_in_combat = true
				break
		if not still_in_combat and opponent.state == Regiment.State.ENGAGING:
			opponent.set_state(Regiment.State.IDLE)
			CombatState.set_charged(opponent, false, "melee_disengage")

	# The disengaging regiment returns to IDLE (caller will set MARCHING)
	regiment.set_state(Regiment.State.IDLE)
	CombatState.set_charged(regiment, false, "melee_disengage")


## Resolve active melee combats for the current bucket (staggered updates)
## Each combat is processed once every BUCKET_COUNT frames to spread CPU load
func _resolve_all_melees() -> void:
	var melee_count: int = active_melees.size()
	if melee_count == 0:
		return

	# Track regiments that need state cleanup after melee ends
	var regiments_to_disengage: Array[Regiment] = []

	# Process only combats that belong to the current bucket
	for i in melee_count:
		# Safety check: array may have shrunk if regiments died during iteration
		if i >= active_melees.size():
			break

		# Skip combats not in this frame's bucket
		if i % BUCKET_COUNT != _update_bucket:
			continue

		var m: Dictionary = active_melees[i]
		var att = m.get("attacker")
		var def = m.get("defender")

		# Check for invalid or dead combatants - clean up the melee
		var att_invalid: bool = not is_instance_valid(att) or (att and att.state == Regiment.State.DEAD)
		var def_invalid: bool = not is_instance_valid(def) or (def and def.state == Regiment.State.DEAD)

		if att_invalid or def_invalid:
			# Melee is ending - transition surviving regiment back to IDLE
			if not att_invalid and is_instance_valid(att) and att.state == Regiment.State.ENGAGING:
				regiments_to_disengage.append(att)
			if not def_invalid and is_instance_valid(def) and def.state == Regiment.State.ENGAGING:
				regiments_to_disengage.append(def)
			active_melees[i] = {}  # Mark for removal
			continue

		# Check if either unit is routing - end melee and disengage
		if att.state == Regiment.State.ROUTING or def.state == Regiment.State.ROUTING:
			if att.state == Regiment.State.ENGAGING:
				regiments_to_disengage.append(att)
			if def.state == Regiment.State.ENGAGING:
				regiments_to_disengage.append(def)
			active_melees[i] = {}  # Mark for removal
			continue

		_resolve_melee_tick(m)

	# Clean up invalid entries (marked as empty dicts)
	active_melees = active_melees.filter(func(m: Dictionary) -> bool:
		return m.size() > 0
	)

	# Transition disengaged regiments to IDLE only if they have no other active melees
	for regiment in regiments_to_disengage:
		if is_instance_valid(regiment) and regiment.state == Regiment.State.ENGAGING:
			# Check if this regiment is still in any other active melee
			var still_in_combat: bool = false
			for melee in active_melees:
				if melee.size() > 0 and (melee.get("attacker") == regiment or melee.get("defender") == regiment):
					still_in_combat = true
					break
			if not still_in_combat:
				regiment.set_state(Regiment.State.IDLE)
				regiment.reset_charge_state()

## Resolve one melee tick - delegates math to MeleeResolver, side effects to CasualtyProcessor.
func _resolve_melee_tick(melee: Dictionary) -> void:
	var att: Regiment = melee["attacker"]
	var def: Regiment = melee["defender"]

	# Update charge time for decay calculation
	melee["charge_time"] += MELEE_TICK_RATE

	# Determine charge modifiers
	var charge_negated: bool = melee.get("charge_negated", false)
	var had_valid_charge: bool = melee.get("charge_applied", false) or att.has_valid_charge()
	var weather_charge_mod: float = 1.0
	var formation_charge_mod: float = 1.0

	if att.data.charge_bonus > 0 and not charge_negated:
		if (att.current_order == OrderType.Type.CHARGE or melee.get("charge_applied", false)) and had_valid_charge:
			weather_charge_mod = float(WeatherSystem.apply_charge_modifier(att.data.charge_bonus)) / float(att.data.charge_bonus) if att.data.charge_bonus > 0 else 1.0
			formation_charge_mod = att.get_charge_modifier()

	# Delegate ALL combat math to MeleeResolver
	var result: Dictionary = melee_resolver.resolve_bidirectional_melee(
		att, def,
		melee["charge_time"],
		charge_negated,
		_get_ai_stat_multiplier(att),
		_get_ai_stat_multiplier(def),
		weather_charge_mod,
		formation_charge_mod
	)

	# Apply high ground morale modifier
	casualty_processor.apply_height_morale_modifier(att, def, melee_resolver.HEIGHT_ADVANTAGE_THRESHOLD)

	# === ATTACKER'S ATTACK ===
	if result.attacker.hit:
		# Apply damage
		def.take_casualties(result.attacker.casualties)

		# Debug output
		if debug_combat:
			print("[COMBAT] %s(%d) attacks %s(%d) = %d casualties" % [
				att.name, att.current_soldiers, def.name, def.current_soldiers,
				result.attacker.casualties
			])

		# Track statistics
		_track_kill(att, def, result.attacker.casualties)

		# Process side effects (audio, visuals, morale, veterancy)
		_play_combat_sfx_random("sword_hit", 5, def.global_position)
		if CombatEffects:
			CombatEffects.spawn_melee_hit(def.global_position + Vector3(0, 1.0, 0))
		if result.attacker.casualties > 0:
			_play_death_cry(def.global_position, result.attacker.casualties)

		# Morale damage
		var morale_damage: float = float(result.attacker.casualties) * MELEE_MORALE_PER_CASUALTY * result.attacker.flank_morale_mod
		MoraleSystem.apply_morale_damage(def, morale_damage, "melee_casualties")
		damage_dealt.emit(def, result.attacker.casualties, att, "melee")
		BattleSignals.regiment_attacked.emit(att, def, result.attacker.casualties)

		# Morale events
		_push_casualty_morale_events(def, result.attacker.casualties, att)
		if result.attacker.flank_mod > 1.0:
			_apply_flank_morale_events(def, att, result.attacker.is_rear)

		# Veterancy
		if att.veterancy and result.attacker.casualties > 0:
			for i in result.attacker.casualties:
				att.veterancy.add_kill()
	else:
		if debug_combat:
			print("[COMBAT] %s MISSED %s (%.0f%% hit chance)" % [
				att.name, def.name, result.debug_info.attacker.hit_chance * 100.0
			])

	# === DEFENDER'S COUNTER-ATTACK ===
	if result.defender_counter.hit and def.state != Regiment.State.ROUTING and def.current_soldiers > 0:
		# Apply damage
		att.take_casualties(result.defender_counter.casualties)

		# Debug output
		if debug_combat:
			print("[COMBAT] %s(%d) counter-attacks %s(%d) = %d casualties" % [
				def.name, def.current_soldiers, att.name, att.current_soldiers,
				result.defender_counter.casualties
			])

		# Track statistics
		_track_kill(def, att, result.defender_counter.casualties)

		# Process side effects
		_play_combat_sfx_random("sword_hit", 5, att.global_position)
		if CombatEffects:
			CombatEffects.spawn_melee_hit(att.global_position + Vector3(0, 1.0, 0))
		if result.defender_counter.casualties > 0:
			_play_death_cry(att.global_position, result.defender_counter.casualties)

		# Morale damage
		var counter_morale_damage: float = float(result.defender_counter.casualties) * MELEE_MORALE_PER_CASUALTY * result.defender_counter.flank_morale_mod
		MoraleSystem.apply_morale_damage(att, counter_morale_damage, "melee_counter")
		damage_dealt.emit(att, result.defender_counter.casualties, def, "melee")

		# Morale events
		_push_casualty_morale_events(att, result.defender_counter.casualties, def)
		if result.defender_counter.flank_mod > 1.0:
			_apply_flank_morale_events(att, def, result.defender_counter.is_rear)

		# Veterancy
		if def.veterancy and result.defender_counter.casualties > 0:
			for i in result.defender_counter.casualties:
				def.veterancy.add_kill()

	melee["charge_applied"] = true

## Calculate casualties using melee resolver formula
func _calculate_casualties(attack: int, defense: int, strength: int) -> int:
	return melee_resolver.calculate_casualties(attack, defense, strength)

## Update charge timers
func _update_charge_timers(delta: float) -> void:
	for m in active_melees:
		if not m["charge_applied"]:
			m["charge_timer"] += delta


## Check if a regiment is currently engaged in melee combat
func _is_target_in_melee(target: Regiment) -> bool:
	for m in active_melees:
		if m["attacker"] == target or m["defender"] == target:
			return true
	return false


## Get the friendly regiment engaged in melee with the target
## Used for friendly fire calculations
func _get_friendly_in_melee_with(target: Regiment, attacker_is_player: bool) -> Regiment:
	for m in active_melees:
		# If target is the defender, the attacker might be our friendly
		if m["defender"] == target:
			var potential_friendly: Regiment = m["attacker"]
			if potential_friendly.is_player_controlled == attacker_is_player:
				return potential_friendly
		# If target is the attacker, the defender might be our friendly
		elif m["attacker"] == target:
			var potential_friendly: Regiment = m["defender"]
			if potential_friendly.is_player_controlled == attacker_is_player:
				return potential_friendly
	return null


## Fire ranged attack
func fire_ranged(attacker: Regiment, target: Regiment) -> void:
	if attacker.current_ammo <= 0:
		return
	if attacker.data.ballistic_skill == 0:
		return

	# Weather LOS check - weather may block ranged attacks at distance
	if WeatherSystem.blocks_los(attacker.global_position.distance_to(target.global_position)):
		return

	# LoS check
	if not _has_line_of_sight(attacker, target):
		return

	# Range check
	var dist: float = attacker.global_position.distance_to(target.global_position)
	if dist > attacker.data.range_distance:
		return

	attacker.current_ammo -= 1

	# Play bow release audio
	_play_combat_sfx("bow_release_01", attacker.global_position)

	# Play shooting animation on the attacker
	_play_ranged_attack_animation(attacker)

	# Check for friendly fire risk - is target in active melee?
	var actual_target: Regiment = target
	var friendly_hit: bool = false

	if _is_target_in_melee(target):
		# Target is in melee - risk of hitting friendlies!
		if randf() < FRIENDLY_FIRE_CHANCE:
			# Find the friendly regiment engaged with target
			var friendly: Regiment = _get_friendly_in_melee_with(target, attacker.is_player_controlled)
			if friendly and is_instance_valid(friendly):
				actual_target = friendly
				friendly_hit = true

	# Spawn projectile to actual target
	_spawn_projectile(attacker, actual_target)

	BattleSignals.projectile_fired.emit(attacker, actual_target)

	# Apply extra morale penalty for friendly fire
	if friendly_hit and actual_target.unit_morale:
		var ff_event: MoraleEvent = MoraleEvent.create(
			MoraleEvent.Source.FRIENDLY_FIRE,
			-10.0,  # Morale penalty for being hit by friendly fire
			attacker.global_position
		)
		actual_target.unit_morale.apply_event_to_all(ff_event)

## Check line of sight between two units
func _has_line_of_sight(from: Regiment, to: Regiment) -> bool:
	# First check physics raycast for terrain/buildings
	var space: PhysicsDirectSpaceState3D = from.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from.global_position + Vector3.UP,
		to.global_position + Vector3.UP
	)
	query.exclude = [from]
	query.collision_mask = 1  # World layer only

	var result: Dictionary = space.intersect_ray(query)
	if not (result.is_empty() or result.collider == to):
		return false  # Blocked by terrain

	# Also check cover objects that block LOS
	if _is_blocked_by_cover(from.global_position, to.global_position):
		return false

	return true

## Spawn projectile from attacker to target using pool
func _spawn_projectile(from: Regiment, to: Regiment) -> void:
	if not _projectile_pool:
		push_error("CombatManager: ProjectilePool not initialized")
		return

	# Get projectile configuration based on unit type
	var config: Dictionary = _get_projectile_config(from)

	# Calculate spawn position and direction
	var spawn_pos: Vector3 = from.global_position + Vector3(0, 2, 0)
	var target_pos: Vector3 = to.global_position + Vector3(0, 1, 0)
	var direction: Vector3 = (target_pos - spawn_pos).normalized()

	# Spawn configured projectile from pool
	var projectile = _projectile_pool.spawn_configured(
		from,
		spawn_pos,
		direction,
		to,
		config
	)

	if not projectile:
		# Pool exhausted - fall back to warning
		push_warning("CombatManager: Projectile pool exhausted (active: %d)" % _projectile_pool.get_active_count())
		return

	# Set sprite texture from attacker's data
	if from.data and from.data.sprite_texture and projectile.has_node("Sprite3D"):
		projectile.get_node("Sprite3D").texture = from.data.sprite_texture

	# Initialize flight if using legacy method
	if projectile.has_method("start_flight"):
		projectile.start_flight()

## Resolve ranged hit with damage multiplier (for piercing/AOE)
## Total War style: arrows hit easily, armor saves block damage
## Includes terrain: height bonus, forest defense, concealment
func resolve_ranged_hit_with_multiplier(attacker: Regiment, defender: Regiment, damage_multiplier: float = 1.0) -> void:
	# Use RangedResolver for Total War style hit + armor save + terrain
	var result: Dictionary = ranged_resolver.resolve_ranged_attack(attacker, defender)

	# If target is concealed (hidden in forest), can't shoot them
	if result.get("concealed", false):
		if debug_combat:
			print("[COMBAT] RANGED %s -> %s: CONCEALED (hidden in terrain)" % [
				attacker.name, defender.name])
		return

	# Apply weather accuracy modifier to the roll (pre-resolution)
	# Note: This modifies the threshold, not re-rolling
	var weather_mod: float = WeatherSystem.get_ranged_accuracy_modifier()

	# Apply fire mode modifier (Stainless Steel pattern)
	# VOLLEY: Fires more arrows but each is less accurate
	# DIRECT: Fires fewer but more accurate shots
	var fire_mode_mod: float = 1.0
	if attacker.data.fire_mode == RegimentData.FireMode.DIRECT:
		fire_mode_mod = 1.15  # +15% effective accuracy
	else:
		fire_mode_mod = 0.95  # -5% (volley compensates with volume)

	# Combine modifiers for effective accuracy check
	var effective_accuracy: float = result.accuracy * weather_mod * fire_mode_mod

	# Re-check with modifiers if original was a miss but modifiers help
	if not result.hit and not result.blocked:
		if randf() < effective_accuracy:
			# Weather/fire mode saved the shot - now check armor
			var armor_save: float = ranged_resolver.calculate_armor_save(defender)
			if randf() < armor_save:
				result.blocked = true
			else:
				result.hit = true
				result.damage = ranged_resolver.calculate_damage(attacker, defender)

	# If blocked by armor/terrain, no damage
	if result.blocked:
		if debug_combat:
			var terrain_info: String = ""
			if result.get("terrain_defense_mod", 1.0) > 1.0:
				terrain_info = " (terrain: +%.0f%%)" % [(result.terrain_defense_mod - 1.0) * 100]
			print("[COMBAT] RANGED %s -> %s: BLOCKED%s (save: %.0f%%)" % [
				attacker.name, defender.name, terrain_info, result.armor_save * 100])
		return

	# If miss, no effect
	if not result.hit:
		if debug_combat:
			print("[COMBAT] RANGED %s -> %s: MISS (acc: %.0f%%)" % [
				attacker.name, defender.name, effective_accuracy * 100])
		return

	# Hit connected - calculate final damage
	var damage: int = result.damage

	# Play arrow impact audio
	_play_combat_sfx_random("arrow_hit", 3, defender.global_position)

	# Apply high ground bonus/penalty
	var height_diff: float = attacker.global_position.y - defender.global_position.y
	if height_diff > 1.0:
		damage = int(float(damage) * RANGED_HIGH_GROUND_BONUS)
	elif height_diff < -1.0:
		damage = int(float(damage) * RANGED_LOW_GROUND_PENALTY)

	# Check for cover protection
	var cover_reduction: float = _get_cover_damage_reduction(defender)
	if cover_reduction > 0.0:
		damage = int(float(damage) * (1.0 - cover_reduction))

	# Apply AI personality stat_multiplier for ranged damage
	var ranged_ai_stat_mod: float = _get_ai_stat_multiplier(attacker)
	damage = int(float(damage) * ranged_ai_stat_mod)

	# Apply damage multiplier (from piercing/AOE falloff)
	damage = int(float(damage) * damage_multiplier)

	# Apply global combat slowdown multiplier
	damage = int(float(damage) * COMBAT_DAMAGE_MULTIPLIER)

	# Minimum damage of 1
	damage = max(1, damage)

	# Debug ranged combat output
	if debug_combat:
		print("[COMBAT] RANGED %s(%d) hits %s(%d) for %d damage (acc:%.0f%% armor:%.0f%%)" % [
			attacker.name, attacker.current_soldiers, defender.name, defender.current_soldiers,
			damage, result.accuracy * 100, result.armor_save * 100])

	# Apply damage
	defender.take_casualties(damage)

	# Track statistics
	_track_kill(attacker, defender, damage)

	# Spawn ranged hit visual effect
	if CombatEffects:
		CombatEffects.spawn_ranged_hit(defender.global_position + Vector3(0, 0.5, 0))

	# Play death cries for ranged casualties
	if damage > 0:
		_play_death_cry(defender.global_position, damage)

	MoraleSystem.apply_morale_damage(defender, float(damage) * RANGED_MORALE_RATIO, "ranged_hit")
	damage_dealt.emit(defender, damage, attacker, "ranged")
	BattleSignals.regiment_attacked.emit(attacker, defender, damage)

	# Track kills for veterancy
	if attacker.veterancy and damage > 0:
		for i in damage:
			attacker.veterancy.add_kill()

	# Push per-soldier morale events for casualties
	_push_casualty_morale_events(defender, damage, attacker)


## Return projectile to pool (delegated to ProjectilePool)
func return_projectile(projectile) -> void:
	if _projectile_pool:
		_projectile_pool.return_to_pool(projectile)
	else:
		# Fallback cleanup
		projectile.visible = false
		projectile.process_mode = Node.PROCESS_MODE_DISABLED
		if projectile.get_parent():
			projectile.get_parent().remove_child(projectile)


## Get projectile pool statistics for debugging
func get_projectile_stats() -> Dictionary:
	if _projectile_pool:
		return _projectile_pool.get_stats()
	return {}

func _process(delta: float) -> void:
	# Don't process combat during deployment phase
	if DeploymentManager and DeploymentManager.is_deployment_phase():
		return

	# Advance bucket every frame so each melee gets serviced at the correct rate
	_update_bucket = (_update_bucket + 1) % BUCKET_COUNT

	# Staggered combat resolution - process one bucket per tick interval
	# Each melee is resolved once every MELEE_TICK_RATE seconds
	melee_timer += delta
	var bucket_interval: float = MELEE_TICK_RATE / float(BUCKET_COUNT)
	if melee_timer >= bucket_interval:
		melee_timer -= bucket_interval  # Subtract, don't reset, to avoid drift
		var start_time := Time.get_ticks_usec()
		_resolve_all_melees()
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed > 16.0:  # More than 16ms = frame drop
			print("[PERF_WARN] Combat _resolve_all_melees took %.1fms (melees=%d)" % [elapsed, active_melees.size()])
	_update_charge_timers(delta)


## Push per-soldier morale events when casualties occur
## Batched to prevent N separate events for N casualties
func _push_casualty_morale_events(defender: Regiment, casualties: int, attacker: Regiment) -> void:
	if not defender.unit_morale or casualties <= 0:
		return

	# Batch casualties into single scaled event (cap at 5x multiplier)
	var event: MoraleEvent = MoraleEvent.friend_killed(defender.global_position)
	event.magnitude *= minf(float(casualties), 5.0)  # Scale by casualties, cap at 5x
	defender.unit_morale.apply_event_to_nearby(
		event,
		defender.global_position,
		MoraleConstants.FRIEND_KILLED_RADIUS
	)

	# Give kill morale boost to attacker (also batched)
	if attacker.unit_morale:
		var kill_event: MoraleEvent = MoraleEvent.kill_enemy(defender.global_position)
		kill_event.magnitude *= minf(float(casualties), 5.0)  # Scale by kills, cap at 5x
		attacker.unit_morale.apply_event_to_nearby(
			kill_event,
			attacker.global_position,
			MoraleConstants.FRIEND_KILLED_RADIUS
		)


## Apply morale events when a unit is flanked
func _apply_flank_morale_events(flanked: Regiment, flanker: Regiment, is_rear: bool) -> void:
	if not flanked.unit_morale:
		return

	# Flanked units take a morale hit from the shock
	var flank_penalty: float = -15.0 if is_rear else -8.0

	# Create a flanking event and apply to all soldiers
	# Using ENEMY_NEARBY as base source since there's no specific FLANKED source
	flanked.unit_morale.set_continuous_modifier_all(
		MoraleEvent.Source.ENEMY_NEARBY,
		flank_penalty
	)

	# Emit signal for UI/debug
	BattleSignals.unit_flanked.emit(flanked, flanker, is_rear)


## Get cover damage reduction for a defender position.
## Queries nearby CoverObjects and returns the best cover bonus.
func _get_cover_damage_reduction(defender: Regiment) -> float:
	var cover_objects: Array[Node] = get_tree().get_nodes_in_group("cover_objects")
	var best_cover: float = 0.0

	for cover in cover_objects:
		if not cover is CoverObject:
			continue
		if not is_instance_valid(cover):
			continue

		# Check if defender is within cover radius
		if cover.is_position_in_cover(defender.global_position):
			var cover_bonus: float = cover.get_cover_bonus()
			if cover_bonus > best_cover:
				best_cover = cover_bonus

	return best_cover


## Check if a position has line-of-sight blocking cover nearby.
## Used to validate ranged attacks.
func _is_blocked_by_cover(from_pos: Vector3, to_pos: Vector3) -> bool:
	var cover_objects: Array[Node] = get_tree().get_nodes_in_group("cover_objects")

	for cover in cover_objects:
		if not cover is CoverObject:
			continue
		if not cover.blocks_line_of_sight:
			continue

		# Simple check: is the cover between attacker and defender?
		var to_cover: Vector3 = cover.global_position - from_pos
		var to_target: Vector3 = to_pos - from_pos

		# Flatten to XZ plane for distance check
		to_cover.y = 0
		to_target.y = 0

		var dist_to_cover: float = to_cover.length()
		var dist_to_target: float = to_target.length()

		# Cover must be between us and target
		if dist_to_cover >= dist_to_target:
			continue

		# Check if cover is roughly in the line of fire
		var angle: float = to_cover.angle_to(to_target)
		if angle < deg_to_rad(15.0):  # Within 15 degrees of line of fire
			# Check if we're close enough to the cover for it to block
			var perpendicular_dist: float = dist_to_cover * sin(angle)
			if perpendicular_dist < cover.cover_radius:
				return true

	return false


## Handle regiment death - spawn death visual effect
func _on_regiment_dead(regiment: Regiment) -> void:
	if not is_instance_valid(regiment):
		return

	# Spawn death effect at regiment's last position
	if CombatEffects:
		CombatEffects.spawn_death(regiment.global_position + Vector3(0, 0.8, 0))
