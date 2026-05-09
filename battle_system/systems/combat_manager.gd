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
const HatredCalculatorScript = preload("res://battle_system/systems/combat/hatred_calculator.gd")
const CombatAudioScript = preload("res://battle_system/systems/combat/combat_audio.gd")
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")
const SpriteUnitAtlasScript = preload("res://battle_system/data/sprite_unit_atlas.gd")

var flanking  # FlankingCalculator
var statistics  # BattleStatistics
var charge_system  # ChargeSystem
var melee_resolver  # MeleeResolver
var ranged_resolver  # RangedResolver
var casualty_processor  # CasualtyProcessor
var hatred_calculator  # HatredCalculator
var combat_audio  # CombatAudio

# === AUDIO INTEGRATION ===
# Delegates to CombatAudio system for all audio playback.

func _cache_audio_manager() -> void:
	## Initialize audio systems.
	if combat_audio:
		combat_audio.debug_combat = debug_combat
		combat_audio.cache_audio_manager(get_tree())
	if casualty_processor:
		casualty_processor.cache_audio_manager(get_tree())


func _update_melee_ambience(delta: float) -> void:
	## Update melee ambience system with current combat state.
	if not combat_audio:
		return
	# Gather melee positions
	var positions: Array = []
	for m in active_melees:
		var att = m.get("attacker")
		var def = m.get("defender")
		if is_instance_valid(att):
			positions.append(att.global_position)
		if is_instance_valid(def):
			positions.append(def.global_position)
	combat_audio.update_melee_ambience(delta, active_melees.size(), positions)


## Play weapon-class-appropriate ranged fire audio.
func _play_ranged_fire_audio(attacker: Regiment) -> void:
	if not is_instance_valid(attacker) or not attacker.data:
		return
	var weapon_class: int = attacker.data.weapon_class
	if combat_audio:
		combat_audio.play_ranged_fire_audio(attacker, weapon_class)
	# Spawn muzzle flash visual effect for artillery
	_spawn_muzzle_flash(attacker, weapon_class)


## Spawn muzzle flash visual effect for artillery weapons.
func _spawn_muzzle_flash(attacker: Regiment, weapon_class: int) -> void:
	if weapon_class not in [RegimentData.WeaponClass.CANNON, RegimentData.WeaponClass.MORTAR,
			RegimentData.WeaponClass.WAR_MACHINE, RegimentData.WeaponClass.HANDGUN]:
		return

	var sprite_pool := get_node_or_null("/root/SpriteEffectPool")
	if sprite_pool and sprite_pool.has_method("spawn_cannon_muzzle"):
		# Get direction from attacker facing
		var facing := attacker.get_facing_direction()
		var dir_idx := _facing_to_direction_index(facing)

		# Spawn at front of regiment (barrel position)
		var muzzle_pos := attacker.global_position + facing * 1.5 + Vector3(0, 0.8, 0)
		sprite_pool.spawn_cannon_muzzle(muzzle_pos, dir_idx)

		if debug_combat:
			print("[CombatManager] Spawned cannon muzzle flash at %s" % muzzle_pos)


## Convert facing vector to 8-direction index matching sprite atlas convention.
## Direction mapping: 0=North, 1=NE, 2=East, 3=SE, 4=South, 5=SW, 6=West, 7=NW (clockwise from North)
func _facing_to_direction_index(facing: Vector3) -> int:
	return SpriteUnitAtlasScript.direction_from_vector(facing)




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

	# Play fire animation with recoil on 3D artillery pieces
	if regiment.artillery_formation:
		regiment.artillery_formation.play_fire_animation()


# Active melee combat pairs
# Each entry: { attacker: Regiment, defender: Regiment, charge_applied: bool, charge_timer: float, charge_time: float }
var active_melees: Array[Dictionary] = []

# Combat timing - ADJUSTED FOR BETTER PACING
# BUG #5 FIX: Reduced from 0.5s to 0.2s for smoother damage distribution.
# This spreads the same total DPS across more ticks, preventing "chunky" casualties.
const MELEE_TICK_RATE: float = 0.2  # resolve combat every 0.2 seconds for smooth damage
const MELEE_DAMAGE_SCALE: float = 0.4  # Scale factor: 0.2/0.5 = 0.4 to maintain same DPS
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

# Damage type effect constants
const FIRE_PANIC_CHANCE: float = 0.15          # 15% chance for fire to cause morale panic
const FIRE_PANIC_MORALE_DAMAGE: float = 8.0    # Extra morale damage on panic proc
const POISON_HAZARD_DURATION: float = 4.0      # Poison hazard lasts 4 seconds
const POISON_HAZARD_DPS: float = 2.0           # Poison does 2 damage per second
const POISON_HAZARD_RADIUS: float = 2.0        # Small localized poison cloud

# Hit chance constants - use melee_resolver.calculate_hit_chance() for calculations

# Debug mode - reads from DebugFlags autoload
var debug_combat: bool:
	get: return DebugFlags.combat if DebugFlags else false
var _debug_state_timer: float = 0.0
const DEBUG_STATE_INTERVAL: float = 2.0  # Print combat states every 2 seconds

# Battle statistics tracking - synced from BattleStatistics system
var battle_stats: Dictionary = {}

# Difficulty profile for damage multipliers (BattleDebug agent calibration)
const DifficultyProfileScript = preload("res://battle_system/ai/data/difficulty_profile.gd")
var difficulty_profile: Resource = null  # DifficultyProfile

var melee_timer: float = 0.0
# Phase 6.4: Terrain access via TerrainHelper (removed _terrain variable)

# Staggered update system - process 1/BUCKET_COUNT of combats per frame
var _update_bucket: int = 0
const BUCKET_COUNT: int = 4  # Reduced from 16 for more responsive combat

# Projectile pool for performance (upgraded pooling system)
var _projectile_pool: ProjectilePool = null
var _projectile_scene: PackedScene = null


# Preload WeaponClassData for projectile configs
const WeaponClassDataScript = preload("res://battle_system/data/weapon_class_data.gd")
# Preload SpellData for DamageType enum (unified damage type system)
const SpellDataScript = preload("res://battle_system/data/spell_data.gd")

func _ready() -> void:
	# Initialize extracted combat systems using preloaded scripts
	flanking = FlankingCalculatorScript.new()
	statistics = BattleStatisticsScript.new()
	charge_system = ChargeSystemScript.new()
	melee_resolver = MeleeResolverScript.new()
	ranged_resolver = RangedResolverScript.new()
	casualty_processor = CasualtyProcessorScript.new()
	hatred_calculator = HatredCalculatorScript.new()
	combat_audio = CombatAudioScript.new()

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


## Set the difficulty profile for damage multipliers
## Used by BattleDebug agent for calibration testing
func set_difficulty_profile(profile: Resource) -> void:
	difficulty_profile = profile
	if debug_combat and profile:
		print("[CombatManager] Difficulty profile set: %s" % profile.display_name)


## Apply difficulty multipliers to damage based on attacker ownership
func _apply_difficulty_damage(base_damage: int, is_player_attacker: bool) -> int:
	if not difficulty_profile:
		return base_damage

	var mult: float = 1.0
	if is_player_attacker:
		mult = difficulty_profile.player_damage_dealt_mult
	else:
		mult = difficulty_profile.ai_damage_dealt_mult

	return maxi(1, int(round(float(base_damage) * mult)))


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


## Get hatred attack bonus for attacker against target based on general traits.
## Delegates to HatredCalculator for race/faction keyword matching.
## Returns 0.0 if no hatred applies, or the bonus multiplier (e.g. 0.25 for +25%).
func _get_hatred_bonus(is_player: bool, target: Regiment) -> float:
	if hatred_calculator:
		return hatred_calculator.get_hatred_bonus(is_player, target)
	return 0.0


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

## Get projectile configuration based on regiment's weapon class and round type
func _get_projectile_config(regiment: Regiment) -> Dictionary:
	## Returns the projectile configuration for this regiment's weapon class.
	## For artillery with non-STANDARD rounds, applies round modifiers.
	## Falls back to BOW config if no weapon class declared (backward compat).
	if not regiment.data:
		return _config_for_weapon_class(RegimentData.WeaponClass.BOW)

	var wc: int = regiment.data.weapon_class
	if wc == RegimentData.WeaponClass.NONE:
		# Legacy fallback: detect from unit_type for unmigrated regiments
		if regiment.data.unit_type == UnitType.Type.ARTILLERY:
			wc = RegimentData.WeaponClass.MORTAR  # Best guess
		elif regiment.data.ballistic_skill > 0:
			# Check unit name for weapon hints
			var unit_name: String = regiment.data.regiment_name.to_lower() if regiment.data.regiment_name else ""
			if "crossbow" in unit_name or "xbow" in unit_name:
				wc = RegimentData.WeaponClass.CROSSBOW
			elif "handgun" in unit_name or "thunder" in unit_name or "engr" in unit_name:
				wc = RegimentData.WeaponClass.HANDGUN
			elif "dragon" in unit_name or "wyvern" in unit_name:
				wc = RegimentData.WeaponClass.BREATH_FIRE
			elif "wizard" in unit_name or "mage" in unit_name or "wiz" in unit_name:
				wc = RegimentData.WeaponClass.MAGIC_MISSILE
			else:
				wc = RegimentData.WeaponClass.BOW
		else:
			wc = RegimentData.WeaponClass.BOW

	# Check if regiment has non-STANDARD round type (artillery only)
	var round_type: int = regiment.current_round_type if regiment else 0
	if round_type != WeaponClassDataScript.RoundType.STANDARD and WeaponClassDataScript.is_artillery_weapon(wc):
		return _config_for_weapon_class_with_round(wc, round_type)

	return _config_for_weapon_class(wc)


func _config_for_weapon_class(weapon_class: int) -> Dictionary:
	## Returns projectile config dictionary from WeaponClassData.
	var config: Dictionary = WeaponClassDataScript.get_projectile_config(weapon_class)
	if config.is_empty():
		push_warning("CombatManager: No WeaponDef for weapon_class %d" % weapon_class)
		# Fallback to BOW
		config = WeaponClassDataScript.get_projectile_config(RegimentData.WeaponClass.BOW)

	# Map visual_type to ProjectileType enum
	config["projectile_type"] = _visual_type_to_enum(config.get("visual_type", "arrow"))

	return config


func _config_for_weapon_class_with_round(weapon_class: int, round_type: int) -> Dictionary:
	## Returns projectile config with round type modifiers applied.
	## Used for artillery with non-STANDARD ammo types.
	var config: Dictionary = WeaponClassDataScript.get_projectile_config_with_round(weapon_class, round_type)
	if config.is_empty():
		push_warning("CombatManager: No config for weapon_class %d round_type %d" % [weapon_class, round_type])
		return _config_for_weapon_class(weapon_class)

	# Map visual_type to ProjectileType enum
	config["projectile_type"] = _visual_type_to_enum(config.get("visual_type", "shell"))

	return config


func _visual_type_to_enum(visual_type: String) -> int:
	## Maps weapon visual_type strings to Projectile.ProjectileType enum values.
	match visual_type:
		"arrow": return 0    # ARROW
		"bolt": return 1     # CROSSBOW
		"magic": return 2    # MAGIC
		"shell", "bullet": return 3  # SHELL
		"flame": return 4    # FLAME
		"pellet": return 5   # PELLET (grapeshot)
		"chain": return 6    # CHAIN (chain shot)
		_: return 0

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
					var _normal_damage: int = impact_damage - ap_damage  # Reserved for future damage split
					# Impact causes instant casualties
					var total_impact_casualties: int = max(1, impact_damage / 3)
					# Apply difficulty profile damage multiplier (BattleDebug agent calibration)
					total_impact_casualties = _apply_difficulty_damage(total_impact_casualties, attacker.is_player_controlled)
					defender.take_casualties(total_impact_casualties)
					defender.take_morale_damage(float(impact_damage) * CHARGE_MORALE_RATIO)

			# Emit charge impact signal
			BattleSignals.charge_impact.emit(attacker, defender, was_braced and is_frontal_charge)

			# Play charge impact audio
			if combat_audio:
				combat_audio.play_charge_impact(defender.global_position)

		# Mark attacker as having charged via CombatState
		CombatState.set_charged(attacker, true, "charge_impact")

		# Check for large unit knockback (rock-paper-scissors Part 2)
		var charge_result: Dictionary = charge_system.process_charge_impact(attacker, defender)
		if charge_result.get("triggered_knockback", false):
			_apply_dramatic_knockback(defender, charge_result)

	# BUG #1 FIX: Track whether impact damage was applied at contact.
	# If true, skip the first combat tick to avoid double-counting charge damage.
	# Impact casualties (crash damage) and charge bonus stats should not stack on the same tick.
	var impact_damage_applied: bool = valid_charge and not charge_negated

	active_melees.append({
		"attacker": attacker,
		"defender": defender,
		"charge_applied": false,
		"charge_negated": charge_negated,
		"charge_timer": 0.0,
		"charge_time": 0.0,  # Time since charge impact - for decaying charge bonus
		"skip_first_tick": impact_damage_applied,  # BUG #1: Skip first tick if impact damage was dealt
		# BUG #5: Damage accumulators for fractional damage (carry over between ticks)
		"attacker_damage_acc": 0.0,
		"defender_damage_acc": 0.0
	})

	# DEBUG: Confirm melee added
	print("[MELEE BEGIN] %s vs %s added to active_melees (total: %d)" % [
		attacker.data.regiment_name if attacker.data else attacker.name,
		defender.data.regiment_name if defender.data else defender.name,
		active_melees.size()
	])

	# Emit signal
	combat_started.emit(attacker, defender, "melee")

	# Play immediate clash sound for responsive feedback (before first damage tick)
	if combat_audio:
		var clash_pos: Vector3 = (attacker.global_position + defender.global_position) * 0.5
		combat_audio.play_melee_clash(clash_pos)

## End a melee combat pair
func end_melee(regiment_a: Regiment, regiment_b: Regiment) -> void:
	active_melees = active_melees.filter(func(m: Dictionary) -> bool:
		return not ((m["attacker"] == regiment_a and m["defender"] == regiment_b) or
		            (m["attacker"] == regiment_b and m["defender"] == regiment_a))
	)


## Apply dramatic knockback to a regiment hit by a large unit charge (rock-paper-scissors Part 2)
func _apply_dramatic_knockback(regiment: Node, charge_result: Dictionary) -> void:
	var direction: Vector3 = charge_result.knockback_direction
	var distance: float = charge_result.knockback_distance

	# Move regiment backwards
	var new_pos: Vector3 = regiment.global_position + direction * distance * 0.5
	if regiment.has_method("force_reposition"):
		regiment.force_reposition(new_pos)
	else:
		regiment.global_position = new_pos

	# Apply scatter to formation if available
	if regiment.formation and regiment.formation.has_method("apply_dramatic_scatter"):
		var scatter_amount: float = distance * ChargeSystemScript.KNOCKBACK_SCATTER_MULTIPLIER
		regiment.formation.apply_dramatic_scatter(direction, scatter_amount, charge_result.is_monster_impact)

	# Morale damage from being thrown around
	var morale_damage: float = charge_result.impact_casualties * 3.0
	if charge_result.is_monster_impact:
		morale_damage *= 1.5
	MoraleSystem.apply_morale_damage(regiment, morale_damage, "knockback_terror")


## Get the first enemy regiment engaged in melee with the given regiment.
## Returns null if no engagement found.
func get_engaged_enemy(regiment: Regiment) -> Regiment:
	for melee in active_melees:
		if melee.get("attacker") == regiment:
			var defender = melee.get("defender")
			if is_instance_valid(defender):
				return defender
		elif melee.get("defender") == regiment:
			var attacker = melee.get("attacker")
			if is_instance_valid(attacker):
				return attacker
	return null


## Disengage a regiment from any melee combat (called when player orders retreat)
func disengage_regiment(regiment: Regiment) -> void:
	if not is_instance_valid(regiment):
		return

	# BUG #7 FIX: Set state to IDLE FIRST to prevent re-engagement race condition.
	# The old code removed melee entries first, leaving a window where the regiment
	# was still ENGAGING but had no active melee, allowing _on_melee_area_contact
	# to re-trigger a new melee.
	regiment.set_state(Regiment.State.IDLE)
	CombatState.set_charged(regiment, false, "melee_disengage")

	# FLANKING FIX: clear continuous flank penalties on explicit disengage
	if regiment.unit_morale:
		regiment.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.FLANK_ATTACK)
		regiment.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.REAR_ATTACK)

	# Mark regiment as recently disengaged to prevent immediate re-engagement
	regiment.set_meta("disengage_cooldown", Time.get_ticks_msec())

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

	# Remove all melees involving this regiment
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
			# FLANKING FIX: clear continuous flank penalties for opponent too
			if opponent.unit_morale:
				opponent.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.FLANK_ATTACK)
				opponent.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.REAR_ATTACK)
			opponent.set_state(Regiment.State.IDLE)
			CombatState.set_charged(opponent, false, "melee_disengage")


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
				# FLANKING FIX: clear flank/rear morale penalties when leaving combat.
				# These are set by _apply_flank_morale_events as continuous modifiers
				# and would persist forever without explicit cleanup.
				if regiment.unit_morale:
					regiment.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.FLANK_ATTACK)
					regiment.unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.REAR_ATTACK)
				regiment.set_state(Regiment.State.IDLE)
				regiment.reset_charge_state()

## Resolve one melee tick - delegates math to MeleeResolver, side effects to CasualtyProcessor.
func _resolve_melee_tick(melee: Dictionary) -> void:
	var att: Regiment = melee["attacker"]
	var def: Regiment = melee["defender"]

	# BUG #1 FIX: Skip first combat tick if charge impact damage was already applied.
	# This prevents double-counting: impact casualties + charge-boosted stat damage.
	if melee.get("skip_first_tick", false):
		melee["skip_first_tick"] = false  # Clear flag, subsequent ticks resolve normally
		melee["charge_applied"] = true    # Mark that charge was used
		return

	# Update charge time for decay calculation
	melee["charge_time"] += MELEE_TICK_RATE

	# Determine charge modifiers
	var charge_negated: bool = melee.get("charge_negated", false)
	var had_valid_charge: bool = melee.get("charge_applied", false) or att.has_valid_charge()
	var weather_charge_mod: float = 1.0
	var formation_charge_mod: float = 1.0
	var tide_charge_mod: float = 1.0

	if att.data.charge_bonus > 0 and not charge_negated:
		if (att.current_order == OrderType.Type.CHARGE or melee.get("charge_applied", false)) and had_valid_charge:
			weather_charge_mod = WeatherSystem.get_charge_bonus_modifier()
			formation_charge_mod = att.get_charge_modifier()
			# Apply battle tide modifier to charge
			if BattleTide:
				tide_charge_mod = BattleTide.get_charge_modifier(att.is_player_controlled)
			formation_charge_mod *= tide_charge_mod
			# Apply general trait charge bonus
			if BattleModifiers and BattleModifiers.is_active():
				formation_charge_mod *= (1.0 + BattleModifiers.get_charge_bonus_mod(att.is_player_controlled))

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

	# DEBUG: Trace melee tick results
	print("[MELEE TICK] %s vs %s: att_hit=%s att_cas=%d def_hit=%s def_cas=%d" % [
		att.data.regiment_name if att.data else att.name,
		def.data.regiment_name if def.data else def.name,
		result.attacker.hit, result.attacker.casualties,
		result.defender_counter.hit, result.defender_counter.casualties
	])

	# Apply high ground morale modifier
	casualty_processor.apply_height_morale_modifier(att, def, melee_resolver.HEIGHT_ADVANTAGE_THRESHOLD)

	# === ATTACKER'S ATTACK ===
	if result.attacker.hit:
		# BUG #5 FIX: Use damage accumulator to handle fractional damage properly.
		# Scaled damage is accumulated, and only the integer part is applied as casualties.
		var raw_casualties: float = float(result.attacker.casualties) * MELEE_DAMAGE_SCALE
		melee["attacker_damage_acc"] = melee.get("attacker_damage_acc", 0.0) + raw_casualties
		var final_casualties: int = int(melee["attacker_damage_acc"])
		melee["attacker_damage_acc"] -= float(final_casualties)  # Keep fractional part

		# Apply general trait combat modifiers
		if BattleModifiers and BattleModifiers.is_active():
			var trait_mods: Dictionary = BattleModifiers.get_combat_modifiers(att.is_player_controlled)
			final_casualties = int(float(final_casualties) * (1.0 + trait_mods.melee_attack))

			# Apply hatred bonus if applicable (check regiment_name for race/faction keywords)
			var hatred_bonus: float = _get_hatred_bonus(att.is_player_controlled, def)
			if hatred_bonus > 0.0:
				final_casualties = int(float(final_casualties) * (1.0 + hatred_bonus))

		# Apply difficulty profile damage multiplier (BattleDebug agent calibration)
		final_casualties = _apply_difficulty_damage(final_casualties, att.is_player_controlled)

		# Apply damage
		def.take_casualties(final_casualties)

		# Debug output
		if debug_combat:
			print("[COMBAT] %s(%d) attacks %s(%d) = %d casualties" % [
				att.name, att.current_soldiers, def.name, def.current_soldiers,
				final_casualties
			])

		# Track statistics
		_track_kill(att, def, final_casualties)

		# Process side effects (audio, visuals, morale, veterancy)
		if combat_audio:
			combat_audio.play_layered_melee_hit(def.global_position)
		if CombatEffects:
			CombatEffects.spawn_melee_hit(def.global_position + Vector3(0, 1.0, 0))
		if final_casualties > 0 and combat_audio:
			combat_audio.play_death_cry(def.global_position, final_casualties)

		# Morale damage
		var morale_damage: float = float(final_casualties) * MELEE_MORALE_PER_CASUALTY * result.attacker.flank_morale_mod
		MoraleSystem.apply_morale_damage(def, morale_damage, "melee_casualties")

		# Apply intimidation penalty from Bloodied commanders (only once per melee engagement)
		# Both sides can intimidate each other on first contact
		if BattleModifiers and BattleModifiers.is_active() and not melee.get("intimidation_applied", false):
			# Attacker's intimidation affects defender
			var att_intimidation: float = BattleModifiers.get_intimidation_penalty(att.is_player_controlled)
			if att_intimidation < 0.0:
				MoraleSystem.apply_morale_damage(def, -att_intimidation, "intimidation")

			# Defender's intimidation affects attacker (bidirectional)
			var def_intimidation: float = BattleModifiers.get_intimidation_penalty(def.is_player_controlled)
			if def_intimidation < 0.0:
				MoraleSystem.apply_morale_damage(att, -def_intimidation, "intimidation")

			melee["intimidation_applied"] = true

		damage_dealt.emit(def, final_casualties, att, "melee")
		BattleSignals.regiment_attacked.emit(att, def, final_casualties)

		# Morale events
		_push_casualty_morale_events(def, final_casualties, att)
		if result.attacker.flank_mod > 1.0:
			_apply_flank_morale_events(def, att, result.attacker.is_rear)

		# Veterancy
		if att.veterancy and final_casualties > 0:
			for i in final_casualties:
				att.veterancy.add_kill()
	else:
		if debug_combat:
			print("[COMBAT] %s MISSED %s (%.0f%% hit chance)" % [
				att.name, def.name, result.debug_info.attacker.hit_chance * 100.0
			])

	# === DEFENDER'S COUNTER-ATTACK ===
	if result.defender_counter.hit and def.state != Regiment.State.ROUTING and def.current_soldiers > 0:
		# BUG #5 FIX: Use damage accumulator for defender's counter-attack
		var raw_counter: float = float(result.defender_counter.casualties) * MELEE_DAMAGE_SCALE
		melee["defender_damage_acc"] = melee.get("defender_damage_acc", 0.0) + raw_counter
		var counter_casualties: int = int(melee["defender_damage_acc"])
		melee["defender_damage_acc"] -= float(counter_casualties)  # Keep fractional part

		# Apply general trait combat modifiers for defender
		if BattleModifiers and BattleModifiers.is_active():
			var def_trait_mods: Dictionary = BattleModifiers.get_combat_modifiers(def.is_player_controlled)
			counter_casualties = int(float(counter_casualties) * (1.0 + def_trait_mods.melee_attack))

			# Apply trait defense modifier to reduce incoming damage
			var att_defense_mod: float = BattleModifiers.get_melee_defense_mod(att.is_player_controlled)
			if att_defense_mod > 0.0:
				counter_casualties = int(float(counter_casualties) * (1.0 - att_defense_mod * 0.5))

			# Apply hatred bonus if applicable (check regiment_name for race/faction keywords)
			var def_hatred_bonus: float = _get_hatred_bonus(def.is_player_controlled, att)
			if def_hatred_bonus > 0.0:
				counter_casualties = int(float(counter_casualties) * (1.0 + def_hatred_bonus))

		counter_casualties = maxi(0, counter_casualties)

		# Apply difficulty profile damage multiplier (BattleDebug agent calibration)
		counter_casualties = _apply_difficulty_damage(counter_casualties, def.is_player_controlled)

		# Apply damage
		att.take_casualties(counter_casualties)

		# Debug output
		if debug_combat:
			print("[COMBAT] %s(%d) counter-attacks %s(%d) = %d casualties" % [
				def.name, def.current_soldiers, att.name, att.current_soldiers,
				counter_casualties
			])

		# Track statistics
		_track_kill(def, att, counter_casualties)

		# Process side effects
		if combat_audio:
			combat_audio.play_layered_melee_hit(att.global_position)
		if CombatEffects:
			CombatEffects.spawn_melee_hit(att.global_position + Vector3(0, 1.0, 0))
		if counter_casualties > 0 and combat_audio:
			combat_audio.play_death_cry(att.global_position, counter_casualties)

		# Morale damage
		var counter_morale_damage: float = float(counter_casualties) * MELEE_MORALE_PER_CASUALTY * result.defender_counter.flank_morale_mod
		MoraleSystem.apply_morale_damage(att, counter_morale_damage, "melee_counter")
		damage_dealt.emit(att, counter_casualties, def, "melee")

		# Morale events
		_push_casualty_morale_events(att, counter_casualties, def)
		if result.defender_counter.flank_mod > 1.0:
			_apply_flank_morale_events(att, def, result.defender_counter.is_rear)

		# Veterancy
		if def.veterancy and counter_casualties > 0:
			for i in counter_casualties:
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
	if debug_combat:
		print("[CombatManager] fire_ranged called: %s -> %s (ammo=%d, BS=%d)" % [
			attacker.data.regiment_name, target.data.regiment_name,
			attacker.current_ammo, attacker.data.ballistic_skill
		])

	if attacker.current_ammo <= 0:
		if debug_combat:
			print("[CombatManager] fire_ranged SKIPPED: no ammo")
		return
	if attacker.data.ballistic_skill == 0:
		if debug_combat:
			print("[CombatManager] fire_ranged SKIPPED: no ballistic skill")
		return

	# Check for breath weapons - handled by dedicated function
	var weapon_class: int = attacker.data.weapon_class
	if weapon_class in [RegimentData.WeaponClass.BREATH_FIRE, RegimentData.WeaponClass.BREATH_POISON]:
		_fire_breath_weapon(attacker, target)
		return

	# Weather LOS check - weather may block ranged attacks at distance
	if WeatherSystem.blocks_los(attacker.global_position.distance_to(target.global_position)):
		if debug_combat:
			print("[CombatManager] fire_ranged SKIPPED: weather blocks LOS")
		return

	# LoS check
	if not _has_line_of_sight(attacker, target):
		return

	# Range check
	var dist: float = attacker.global_position.distance_to(target.global_position)
	if dist > attacker.data.range_distance:
		return

	attacker.current_ammo -= 1

	# Play weapon-appropriate ranged fire audio
	_play_ranged_fire_audio(attacker)

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


## Fire multiple projectiles at once (per-soldier firing).
## Each soldier fires independently, creating N projectiles with slight position offsets.
## Uses weapon class data for projectile configuration.
func fire_ranged_multi(attacker: Regiment, target: Regiment, shot_count: int) -> void:
	# DEBUG: Trace artillery firing
	var is_artillery: bool = attacker.data and attacker.data.unit_type == UnitType.Type.ARTILLERY
	if is_artillery:
		print("[COMBAT DEBUG] fire_ranged_multi called: %s -> %s, shots=%d" % [
			attacker.data.regiment_name if attacker.data else "?",
			target.data.regiment_name if target and target.data else "?",
			shot_count
		])

	if shot_count <= 0:
		if is_artillery: print("[COMBAT DEBUG] REJECTED: shot_count <= 0")
		return
	if attacker.current_ammo <= 0:
		if is_artillery: print("[COMBAT DEBUG] REJECTED: no ammo")
		return
	if attacker.data.ballistic_skill == 0:
		if is_artillery: print("[COMBAT DEBUG] REJECTED: no ballistic skill")
		return

	# Check for breath weapons - handled by dedicated function (no multi-shot)
	var weapon_class: int = attacker.data.weapon_class
	if weapon_class in [RegimentData.WeaponClass.BREATH_FIRE, RegimentData.WeaponClass.BREATH_POISON]:
		_fire_breath_weapon(attacker, target)
		return

	# Weather LOS check
	if WeatherSystem.blocks_los(attacker.global_position.distance_to(target.global_position)):
		if is_artillery: print("[COMBAT DEBUG] REJECTED: weather blocks LOS")
		return

	# LoS check
	if not _has_line_of_sight(attacker, target):
		if is_artillery: print("[COMBAT DEBUG] REJECTED: no line of sight")
		return

	# Range check
	var dist: float = attacker.global_position.distance_to(target.global_position)
	if dist > attacker.data.range_distance:
		if is_artillery: print("[COMBAT DEBUG] REJECTED: out of range (dist=%.1f, max=%.1f)" % [dist, attacker.data.range_distance])
		return

	if is_artillery:
		print("[COMBAT DEBUG] PASSED all checks, spawning %d projectiles" % shot_count)

	# Consume ammo (1 per shot, but cap to available ammo)
	var actual_shots: int = mini(shot_count, attacker.current_ammo)
	attacker.current_ammo -= actual_shots

	# Play weapon-appropriate ranged fire audio (rate limited for volleys)
	_play_ranged_fire_audio(attacker)

	# Play shooting animation
	_play_ranged_attack_animation(attacker)

	# Check friendly fire risk
	var actual_target: Regiment = target
	var friendly_hit: bool = false
	if _is_target_in_melee(target):
		if randf() < FRIENDLY_FIRE_CHANCE:
			var friendly: Regiment = _get_friendly_in_melee_with(target, attacker.is_player_controlled)
			if friendly and is_instance_valid(friendly):
				actual_target = friendly
				friendly_hit = true

	# Spawn projectiles with staggered offsets for visual variety
	var formation_width: float = 2.0 * sqrt(float(attacker.current_soldiers))
	for i in actual_shots:
		# Offset spawn position slightly per projectile (across formation width)
		var lateral_offset: float = randf_range(-formation_width * 0.5, formation_width * 0.5)
		var spawn_offset: Vector3 = attacker.get_facing_direction().cross(Vector3.UP).normalized() * lateral_offset
		_spawn_projectile_at_offset(attacker, actual_target, spawn_offset)

	BattleSignals.projectile_fired.emit(attacker, actual_target)

	# Apply morale effects
	if actual_target.unit_morale:
		actual_target.unit_morale.set_continuous_modifier_all(
			MoraleEvent.Source.UNDER_FIRE,
			MoraleConstants.CONTINUOUS_UNDER_FIRE
		)

	if friendly_hit and actual_target.unit_morale:
		var ff_event: MoraleEvent = MoraleEvent.create(
			MoraleEvent.Source.FRIENDLY_FIRE,
			-10.0,
			attacker.global_position
		)
		actual_target.unit_morale.apply_event_to_all(ff_event)


## Spawn projectile with position offset (for multi-shot volleys).
## For artillery with special round types, spawns appropriate projectile pattern.
func _spawn_projectile_at_offset(from: Regiment, to: Regiment, offset: Vector3) -> void:
	if not _projectile_pool:
		push_error("CombatManager: ProjectilePool not initialized")
		return

	var config: Dictionary = _get_projectile_config(from)
	var round_type: int = config.get("round_type", WeaponClassDataScript.RoundType.STANDARD)

	# Handle special round types
	match round_type:
		WeaponClassDataScript.RoundType.GRAPESHOT:
			_spawn_grapeshot_projectiles(from, to, offset, config)
			return
		WeaponClassDataScript.RoundType.SHRAPNEL:
			_spawn_shrapnel_projectile(from, to, offset, config)
			return
		WeaponClassDataScript.RoundType.INCENDIARY:
			_spawn_incendiary_projectile(from, to, offset, config)
			return

	# Standard/other round types - spawn single projectile
	_spawn_single_projectile(from, to, offset, config)


## Spawn a single standard projectile.
func _spawn_single_projectile(from: Regiment, to: Regiment, offset: Vector3, config: Dictionary) -> void:
	# Calculate spawn position with offset
	var spawn_pos: Vector3 = from.global_position + Vector3(0, 2, 0) + offset
	var target_pos: Vector3 = to.global_position + Vector3(0, 1, 0)
	# Add slight randomness to target position for volley spread
	target_pos += Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	var direction: Vector3 = (target_pos - spawn_pos).normalized()

	var projectile = _projectile_pool.spawn_configured(
		from,
		spawn_pos,
		direction,
		to,
		config
	)

	if not projectile:
		push_warning("CombatManager: Projectile pool exhausted (active: %d)" % _projectile_pool.get_active_count())
		return

	if projectile.has_method("start_flight"):
		projectile.start_flight()


## Spawn grapeshot projectiles - multiple pellets in a spread pattern.
## Creates sub_projectile_count projectiles with random spread within spread_angle.
func _spawn_grapeshot_projectiles(from: Regiment, to: Regiment, offset: Vector3, config: Dictionary) -> void:
	var sub_count: int = config.get("sub_projectile_count", 12)
	var spread_angle: float = deg_to_rad(config.get("spread_angle", 30.0))
	var spread_random: bool = config.get("spread_random", true)

	var spawn_pos: Vector3 = from.global_position + Vector3(0, 2, 0) + offset
	var base_target_pos: Vector3 = to.global_position + Vector3(0, 1, 0)
	var base_direction: Vector3 = (base_target_pos - spawn_pos).normalized()

	# Get perpendicular vectors for spread
	var right: Vector3 = base_direction.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(base_direction).normalized()

	for i in sub_count:
		var spread_dir: Vector3 = base_direction

		if spread_random:
			# Random spread within cone
			var h_angle: float = randf_range(-spread_angle * 0.5, spread_angle * 0.5)
			var v_angle: float = randf_range(-spread_angle * 0.3, spread_angle * 0.3)
			spread_dir = base_direction.rotated(up, h_angle).rotated(right, v_angle)
		else:
			# Uniform spread pattern
			var angle_step: float = spread_angle / float(sub_count - 1) if sub_count > 1 else 0.0
			var h_angle: float = -spread_angle * 0.5 + angle_step * float(i)
			spread_dir = base_direction.rotated(up, h_angle)

		spread_dir = spread_dir.normalized()

		var projectile = _projectile_pool.spawn_configured(
			from,
			spawn_pos,
			spread_dir,
			to,
			config
		)

		if not projectile:
			push_warning("CombatManager: Projectile pool exhausted during grapeshot")
			break

		if projectile.has_method("start_flight"):
			projectile.start_flight()


## Spawn shrapnel projectile - single shell that airbursts above target.
## Sets airburst_height on projectile to trigger explosion at specified height.
func _spawn_shrapnel_projectile(from: Regiment, to: Regiment, offset: Vector3, config: Dictionary) -> void:
	var spawn_pos: Vector3 = from.global_position + Vector3(0, 2, 0) + offset
	var airburst_height: float = config.get("airburst_height", 6.0)

	# Target the airburst point above the target
	var target_pos: Vector3 = to.global_position + Vector3(0, airburst_height, 0)
	var direction: Vector3 = (target_pos - spawn_pos).normalized()

	var projectile = _projectile_pool.spawn_configured(
		from,
		spawn_pos,
		direction,
		to,
		config
	)

	if not projectile:
		push_warning("CombatManager: Projectile pool exhausted")
		return

	# Set airburst properties on projectile
	if projectile.has_method("set"):
		projectile.airburst_height = airburst_height
		projectile.is_airburst = true

	if projectile.has_method("start_flight"):
		projectile.start_flight()


## Spawn incendiary projectile - creates hazard zone on impact.
## Config includes hazard_duration and hazard_damage_per_sec for HazardZone setup.
func _spawn_incendiary_projectile(from: Regiment, to: Regiment, offset: Vector3, config: Dictionary) -> void:
	var spawn_pos: Vector3 = from.global_position + Vector3(0, 2, 0) + offset
	var target_pos: Vector3 = to.global_position + Vector3(0, 1, 0)
	target_pos += Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
	var direction: Vector3 = (target_pos - spawn_pos).normalized()

	var projectile = _projectile_pool.spawn_configured(
		from,
		spawn_pos,
		direction,
		to,
		config
	)

	if not projectile:
		push_warning("CombatManager: Projectile pool exhausted")
		return

	# Connect to projectile's AOE signal to spawn hazard zone
	# The projectile will emit aoe_triggered when it impacts
	if projectile.has_signal("aoe_triggered"):
		# Store hazard config on projectile for retrieval at impact
		projectile.set_meta("leaves_hazard", config.get("leaves_hazard", true))
		projectile.set_meta("hazard_duration", config.get("hazard_duration", 8.0))
		projectile.set_meta("hazard_damage_per_sec", config.get("hazard_damage_per_sec", 3.0))
		projectile.set_meta("hazard_radius", config.get("aoe_radius", 4.0))
		projectile.set_meta("source_regiment", from)

		# Connect to spawn hazard on impact
		if not projectile.aoe_triggered.is_connected(_on_incendiary_impact):
			projectile.aoe_triggered.connect(_on_incendiary_impact.bind(projectile))

	if projectile.has_method("start_flight"):
		projectile.start_flight()


## Callback for incendiary projectile impact - spawns HazardZone using unified factory.
func _on_incendiary_impact(impact_pos: Vector3, _radius: float, projectile: Node) -> void:
	if not is_instance_valid(projectile):
		return

	var leaves_hazard: bool = projectile.get_meta("leaves_hazard", true)
	if not leaves_hazard:
		return

	# Prevent double-spawning if another system (spell_caster) also handles this
	if projectile.get_meta("hazard_spawned", false):
		return
	projectile.set_meta("hazard_spawned", true)

	var duration: float = projectile.get_meta("hazard_duration", 8.0)
	var dps: float = projectile.get_meta("hazard_damage_per_sec", 3.0)
	var hazard_radius: float = projectile.get_meta("hazard_radius", 4.0)
	var source: Regiment = projectile.get_meta("source_regiment", null)

	# Build config for unified factory method
	var config: Dictionary = {
		"radius": hazard_radius,
		"damage_per_tick": int(dps),
		"tick_interval": 0.5,
		"duration": duration,
		"damage_type": SpellData.DamageType.FIRE,
		# Colors are auto-derived from damage_type by the factory
	}

	# Create hazard zone using unified factory
	var hazard := HazardZone.create_from_config(config, impact_pos, source)

	# Add to scene tree
	if get_tree():
		get_tree().current_scene.add_child(hazard)


## Check if target is within the unit's firing arc based on facing direction.
## Artillery has a narrow 90° arc, ranged infantry has a wide 180° arc.
func _is_within_firing_arc(from: Regiment, to: Regiment) -> bool:
	if not from or not to:
		return false

	# Get the unit's facing direction
	var facing: Vector3 = from.get_facing_direction()
	facing.y = 0
	if facing.length_squared() < 0.001:
		# No facing set - allow fire in any direction (fallback)
		return true

	# Calculate direction to target
	var to_target: Vector3 = to.global_position - from.global_position
	to_target.y = 0
	if to_target.length_squared() < 0.001:
		return true  # Target at same position

	to_target = to_target.normalized()
	facing = facing.normalized()

	# Calculate angle between facing and target direction
	var dot: float = facing.dot(to_target)
	var angle_rad: float = acos(clampf(dot, -1.0, 1.0))
	var angle_deg: float = rad_to_deg(angle_rad)

	# Determine firing arc based on unit type
	var max_arc_half: float = 90.0  # Default: 180° total arc (90° each side)

	if from.data:
		if from.data.unit_type == UnitType.Type.ARTILLERY:
			max_arc_half = 45.0  # 90° total arc for artillery (limited traverse)
		# Breath weapons use cone_angle from weapon definition
		var weapon_class: int = from.data.weapon_class
		if weapon_class in [RegimentData.WeaponClass.BREATH_FIRE, RegimentData.WeaponClass.BREATH_POISON]:
			var weapon_def = WeaponClassDataScript.get_def(weapon_class)
			if weapon_def and weapon_def.cone_angle > 0:
				max_arc_half = weapon_def.cone_angle / 2.0

	# DEBUG: Log arc check for artillery
	var is_artillery: bool = from.data and from.data.unit_type == UnitType.Type.ARTILLERY
	if is_artillery:
		print("[ARC DEBUG] %s -> %s: angle=%.1f° max=%.1f° %s" % [
			from.data.regiment_name,
			to.data.regiment_name if to.data else "?",
			angle_deg,
			max_arc_half,
			"PASS" if angle_deg <= max_arc_half else "FAIL"
		])

	return angle_deg <= max_arc_half


## Check line of sight between two units
func _has_line_of_sight(from: Regiment, to: Regiment) -> bool:
	# Check firing arc first - target must be in front of the unit
	if not _is_within_firing_arc(from, to):
		var is_artillery: bool = from.data and from.data.unit_type == UnitType.Type.ARTILLERY
		if is_artillery:
			print("[LOS DEBUG] %s -> %s: REJECTED - outside firing arc" % [
				from.data.regiment_name, to.data.regiment_name if to.data else "?"])
		return false

	# Check physics raycast for terrain/buildings
	var space: PhysicsDirectSpaceState3D = from.get_world_3d().direct_space_state
	var from_pos: Vector3 = from.global_position + Vector3.UP * 2.0  # Raise higher to clear terrain
	var to_pos: Vector3 = to.global_position + Vector3.UP * 1.5
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.exclude = [from]
	query.collision_mask = 1  # World layer only

	var result: Dictionary = space.intersect_ray(query)

	# DEBUG: Log LOS check for artillery
	var is_artillery: bool = from.data and from.data.unit_type == UnitType.Type.ARTILLERY
	if is_artillery:
		if result.is_empty():
			print("[LOS DEBUG] %s -> %s: CLEAR (no hit)" % [from.data.regiment_name, to.data.regiment_name if to.data else "?"])
		else:
			print("[LOS DEBUG] %s -> %s: HIT %s at %s" % [
				from.data.regiment_name,
				to.data.regiment_name if to.data else "?",
				result.collider.name if result.collider else "null",
				str(result.position) if result.has("position") else "?"
			])

	if not (result.is_empty() or result.collider == to):
		return false  # Blocked by terrain

	# Also check cover objects that block LOS
	if _is_blocked_by_cover(from.global_position, to.global_position):
		if is_artillery:
			print("[LOS DEBUG] %s -> %s: BLOCKED by cover" % [from.data.regiment_name, to.data.regiment_name if to.data else "?"])
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
## Applies round-specific modifiers (damage_modifier, anti_large_bonus)
func resolve_ranged_hit_with_multiplier(attacker: Regiment, defender: Regiment, damage_multiplier: float = 1.0) -> void:
	# Use RangedResolver for Total War style hit + armor save + terrain
	var result: Dictionary = ranged_resolver.resolve_ranged_attack(attacker, defender)

	# If target is concealed (hidden in forest), can't shoot them
	if result.get("concealed", false):
		if debug_combat:
			print("[COMBAT] RANGED %s -> %s: CONCEALED (hidden in terrain)" % [
				attacker.name, defender.name])
		return

	# Get round-specific modifiers for artillery
	var round_damage_mod: float = 1.0
	var round_accuracy_mod: float = 1.0
	var anti_large_bonus: float = 0.0

	if attacker and attacker.data:
		var round_type: int = attacker.current_round_type
		if round_type != WeaponClassDataScript.RoundType.STANDARD:
			var round_def = WeaponClassDataScript.get_round_def(round_type)
			if round_def:
				round_damage_mod = round_def.damage_modifier
				round_accuracy_mod = round_def.accuracy_modifier
				anti_large_bonus = round_def.anti_large_bonus

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

	# Combine modifiers for effective accuracy check (including round type accuracy modifier)
	var effective_accuracy: float = result.accuracy * weather_mod * fire_mode_mod * round_accuracy_mod

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
	if combat_audio:
		combat_audio.play_arrow_hit(defender.global_position)

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

	# Apply round type damage modifier (grapeshot pellets do less per hit, solid shot does more)
	damage = int(float(damage) * round_damage_mod)

	# Apply anti-large bonus vs CAVALRY and MONSTER unit types (chain shot, solid shot)
	if anti_large_bonus > 0.0 and defender.data:
		var defender_type: int = defender.data.unit_type
		if defender_type == UnitType.Type.CAVALRY or defender_type == UnitType.Type.MONSTER:
			damage = int(float(damage) * (1.0 + anti_large_bonus))
			if debug_combat:
				print("[COMBAT] Anti-large bonus applied: +%.0f%% vs %s" % [
					anti_large_bonus * 100.0, UnitType.Type.keys()[defender_type]])

	# Apply global combat slowdown multiplier
	damage = int(float(damage) * COMBAT_DAMAGE_MULTIPLIER)

	# Minimum damage of 1
	damage = max(1, damage)

	# Apply difficulty profile damage multiplier (BattleDebug agent calibration)
	damage = _apply_difficulty_damage(damage, attacker.is_player_controlled)

	# Debug ranged combat output
	if debug_combat:
		print("[COMBAT] RANGED %s(%d) hits %s(%d) for %d damage (acc:%.0f%% armor:%.0f%%)" % [
			attacker.name, attacker.current_soldiers, defender.name, defender.current_soldiers,
			damage, result.accuracy * 100, result.armor_save * 100])

	# Apply damage
	defender.take_casualties(damage)

	# Record ranged damage for UNDER_FIRE morale modifier
	if defender.casualty_tracker:
		defender.casualty_tracker.record_ranged_damage()

	# Track statistics
	_track_kill(attacker, defender, damage)

	# Spawn ranged hit visual effect
	if CombatEffects:
		CombatEffects.spawn_ranged_hit(defender.global_position + Vector3(0, 0.5, 0))

	# Play death cries for ranged casualties
	if damage > 0 and combat_audio:
		combat_audio.play_death_cry(defender.global_position, damage)

	MoraleSystem.apply_morale_damage(defender, float(damage) * RANGED_MORALE_RATIO, "ranged_hit")
	damage_dealt.emit(defender, damage, attacker, "ranged")
	BattleSignals.regiment_attacked.emit(attacker, defender, damage)

	# === DAMAGE TYPE SPECIAL EFFECTS ===
	# Get damage type from projectile config or round type override
	var damage_type: int = SpellDataScript.DamageType.PHYSICAL
	if attacker and attacker.data:
		var proj_config: Dictionary = _get_projectile_config(attacker)
		damage_type = proj_config.get("damage_type", SpellDataScript.DamageType.PHYSICAL)

	_apply_damage_type_effects(attacker, defender, damage_type, damage)

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


## Apply special effects based on damage type.
## Called after ranged hit is confirmed.
## - FIRE: Chance to cause morale panic
## - POISON: Creates small damage-over-time hazard zone
## - ICE: Slow effect (future implementation)
func _apply_damage_type_effects(attacker: Regiment, defender: Regiment, damage_type: int, _damage: int) -> void:
	if not is_instance_valid(defender):
		return

	match damage_type:
		SpellDataScript.DamageType.FIRE:
			# Fire has a chance to cause morale panic
			if randf() < FIRE_PANIC_CHANCE:
				MoraleSystem.apply_morale_damage(defender, FIRE_PANIC_MORALE_DAMAGE, "fire_panic")
				if debug_combat:
					print("[COMBAT] FIRE PANIC: %s suffers morale damage from flames!" % defender.name)
				# Spawn fire visual effect
				if CombatEffects and CombatEffects.has_method("spawn_fire_burst"):
					CombatEffects.spawn_fire_burst(defender.global_position + Vector3(0, 1.0, 0))

		SpellDataScript.DamageType.POISON:
			# Poison creates a small lingering hazard zone
			_spawn_poison_hazard(attacker, defender.global_position)
			if debug_combat:
				print("[COMBAT] POISON: Hazard zone created at %s position" % defender.name)

		SpellDataScript.DamageType.ICE:
			# ICE: Future implementation - apply slow effect
			# TODO: When slow system is implemented, apply speed debuff here
			pass

		SpellDataScript.DamageType.LIGHTNING:
			# LIGHTNING: Future implementation - chain to nearby targets
			pass

		SpellDataScript.DamageType.HOLY:
			# HOLY: Extra damage vs undead (handled in damage calculation)
			pass

		SpellDataScript.DamageType.DARK:
			# DARK: Extra morale drain (already handled)
			pass


## Spawn a small poison hazard zone at impact location.
## Used by POISON damage type weapons (breath_poison).
func _spawn_poison_hazard(source: Regiment, position: Vector3) -> void:
	var hazard := HazardZone.new()
	hazard.setup_raw(
		POISON_HAZARD_RADIUS,
		int(POISON_HAZARD_DPS),
		0.5,  # tick_interval
		POISON_HAZARD_DURATION,
		SpellDataScript.DamageType.POISON,
		Color(0.2, 0.8, 0.2, 0.6),  # Green poison color
		0 if (source and source.is_player_controlled) else 1
	)
	hazard.caster = source
	hazard.global_position = position

	# Add to scene tree
	if get_tree():
		get_tree().current_scene.add_child(hazard)


## Fire a breath weapon cone attack at target.
## Breath weapons don't fire projectiles - they hit instantly in a cone area.
## Damage falls off with distance from the cone origin.
func _fire_breath_weapon(attacker: Regiment, target: Regiment) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return

	# Get weapon definition for cone parameters
	var weapon_def = WeaponClassDataScript.get_def(attacker.data.weapon_class)
	if not weapon_def:
		push_warning("CombatManager: No WeaponDef for breath weapon class %d" % attacker.data.weapon_class)
		return

	var cone_angle: float = weapon_def.cone_angle
	var cone_length: float = weapon_def.cone_length
	var damage_type: int = weapon_def.damage_type

	# Calculate cone direction toward target
	var origin: Vector3 = attacker.global_position
	var direction: Vector3 = (target.global_position - origin).normalized()
	direction.y = 0  # Flatten to horizontal

	# Consume ammo
	attacker.current_ammo -= 1

	# Play breath audio based on damage type
	if combat_audio:
		combat_audio.play_breath_weapon(origin, damage_type == SpellDataScript.DamageType.FIRE)

	# Play ranged attack animation
	_play_ranged_attack_animation(attacker)

	# Spawn cone visual effect using SpellEffects if available
	var spell_effects: Node = null
	if attacker.is_inside_tree():
		spell_effects = attacker.get_node_or_null("/root/SpellEffects")
	if spell_effects and spell_effects.has_method("spawn_cone_effect"):
		spell_effects.spawn_cone_effect(origin, direction, cone_angle, cone_length, damage_type)

	# Query enemies in cone radius using spatial hash
	if not AIAutoload or not AIAutoload.spatial_hash:
		push_warning("CombatManager: AIAutoload.spatial_hash unavailable for breath weapon")
		return

	var my_faction: int = 0 if attacker.is_player_controlled else 1
	var enemy_faction: int = 1 if my_faction == 0 else 0

	var regiments_in_radius: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		origin,
		cone_length,
		enemy_faction
	)

	# Filter to enemies in cone (dot product check)
	var half_angle_rad: float = deg_to_rad(cone_angle / 2.0)
	var cos_half_angle: float = cos(half_angle_rad)
	var targets_hit: int = 0
	const MAX_BREATH_TARGETS: int = 20

	for node in regiments_in_radius:
		if targets_hit >= MAX_BREATH_TARGETS:
			break
		if not node is Regiment:
			continue
		var regiment: Regiment = node
		if regiment.state == Regiment.State.DEAD:
			continue

		var to_target: Vector3 = regiment.global_position - origin
		to_target.y = 0  # Flatten

		var dist: float = to_target.length()
		if dist > cone_length or dist < 0.1:
			continue

		# Dot product check for cone angle
		var to_target_norm: Vector3 = to_target.normalized()
		var dot: float = direction.dot(to_target_norm)
		if dot < cos_half_angle:
			continue  # Outside cone angle

		# Target is in cone - calculate damage with distance falloff
		var distance_factor: float = 1.0 - (dist / cone_length) * 0.5  # 50% falloff at max range
		distance_factor = clampf(distance_factor, 0.5, 1.0)

		# Calculate base damage from attacker's ranged stats
		var base_damage: int = ranged_resolver.calculate_damage(attacker, regiment)
		var final_damage: int = maxi(1, int(float(base_damage) * distance_factor * COMBAT_DAMAGE_MULTIPLIER))

		# Apply AI stat modifier
		final_damage = int(float(final_damage) * _get_ai_stat_multiplier(attacker))

		# Apply damage
		regiment.take_casualties(final_damage)
		targets_hit += 1

		# Track statistics
		_track_kill(attacker, regiment, final_damage)

		# Emit damage signal
		damage_dealt.emit(regiment, final_damage, attacker, "breath")
		BattleSignals.regiment_attacked.emit(attacker, regiment, final_damage)

		# Apply damage type special effects (fire panic, poison DoT)
		_apply_damage_type_effects(attacker, regiment, damage_type, final_damage)

		# Morale damage
		var morale_damage: float = float(final_damage) * RANGED_MORALE_RATIO * 1.5  # Extra morale damage from breath
		MoraleSystem.apply_morale_damage(regiment, morale_damage, "breath_attack")

		# Death cries
		if final_damage > 0 and combat_audio:
			combat_audio.play_death_cry(regiment.global_position, final_damage)

		# Visual feedback
		if CombatEffects:
			if damage_type == SpellDataScript.DamageType.FIRE:
				CombatEffects.spawn_melee_hit(regiment.global_position + Vector3(0, 1.0, 0))
			else:
				CombatEffects.spawn_ranged_hit(regiment.global_position + Vector3(0, 0.5, 0))

		# Track veterancy
		if attacker.veterancy and final_damage > 0:
			for i in final_damage:
				attacker.veterancy.add_kill()

		# Push morale events
		_push_casualty_morale_events(regiment, final_damage, attacker)

	if debug_combat:
		print("[COMBAT] BREATH %s hits %d targets in %.1f° cone (length %.1f)" % [
			attacker.name, targets_hit, cone_angle, cone_length])


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

	# Update melee ambience system for continuous combat sounds
	_update_melee_ambience(delta)

	# Periodic debug output for all unit combat states
	if debug_combat:
		_debug_state_timer += delta
		if _debug_state_timer >= DEBUG_STATE_INTERVAL:
			_debug_state_timer = 0.0
			_print_all_unit_combat_states()


## Debug: Print combat state of all regiments
func _print_all_unit_combat_states() -> void:
	var regiments: Array = get_tree().get_nodes_in_group("regiments")
	if regiments.is_empty():
		return

	print("=== COMBAT STATES (active_melees=%d) ===" % active_melees.size())
	for regiment in regiments:
		if not is_instance_valid(regiment):
			continue
		var r: Regiment = regiment as Regiment
		if not r or not r.data:
			continue

		var state_name: String = Regiment.State.keys()[r.state] if r.state < Regiment.State.size() else "UNKNOWN"
		var side: String = "PLAYER" if r.is_player_controlled else "ENEMY"
		var ammo_str: String = "ammo=%d/%d" % [r.current_ammo, r.data.max_ammo] if r.data.max_ammo > 0 else ""
		var target_str: String = ""
		if r.target_regiment and is_instance_valid(r.target_regiment):
			target_str = " -> %s" % r.target_regiment.data.regiment_name

		print("  [%s] %s: %s soldiers=%d morale=%.0f %s%s" % [
			side, r.data.regiment_name, state_name, r.current_soldiers,
			r.current_morale, ammo_str, target_str
		])
	print("=========================================")


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
	var source = MoraleEvent.Source.REAR_ATTACK if is_rear else MoraleEvent.Source.FLANK_ATTACK

	# FLANKING FIX: use dedicated FLANK_ATTACK/REAR_ATTACK sources so we can
	# clear them precisely when the engagement ends, without affecting
	# unrelated ENEMY_NEARBY pressure.
	flanked.unit_morale.set_continuous_modifier_all(source, flank_penalty)

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
