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

# === AUDIO INTEGRATION ===
# Helper functions to safely call AudioManager methods
# Handles case where audio files don't exist yet or AudioManager is unavailable

func _play_combat_sfx(sfx_name: String, position: Vector3 = Vector3.ZERO) -> void:
	if Engine.has_singleton("AudioManager"):
		var audio = Engine.get_singleton("AudioManager")
		if audio and audio.has_method("play_sfx"):
			audio.play_sfx(sfx_name, position)
	elif has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio and audio.has_method("play_sfx"):
			audio.play_sfx(sfx_name, position)


func _play_combat_sfx_random(base_name: String, variant_count: int, position: Vector3 = Vector3.ZERO) -> void:
	if Engine.has_singleton("AudioManager"):
		var audio = Engine.get_singleton("AudioManager")
		if audio and audio.has_method("play_sfx_random"):
			audio.play_sfx_random(base_name, variant_count, position)
	elif has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio and audio.has_method("play_sfx_random"):
			audio.play_sfx_random(base_name, variant_count, position)


func _play_morale_sfx(event_name: String) -> void:
	if Engine.has_singleton("AudioManager"):
		var audio = Engine.get_singleton("AudioManager")
		if audio and audio.has_method("play_morale_event"):
			audio.play_morale_event(event_name)
	elif has_node("/root/AudioManager"):
		var audio = get_node("/root/AudioManager")
		if audio and audio.has_method("play_morale_event"):
			audio.play_morale_event(event_name)


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

# Combat timing - SLOWED BY 70%
const MELEE_TICK_RATE: float = 2.5  # resolve combat every 2.5 seconds (was 1.0)
const CHARGE_BONUS_DURATION: float = 3.0
const CHARGE_DECAY_DURATION: float = 10.0  # Charge bonus decays linearly over 10 seconds
const COMBAT_DAMAGE_MULTIPLIER: float = 0.36  # 64% less damage overall (20% faster than before)

# Total War-style hit chance formula
# TotalWarSimulator-style hit chance formula
const BASE_HIT_CHANCE: float = 0.35  # 35% base hit chance (TotalWarSimulator)
const HIT_CHANCE_PER_SKILL: float = 0.01  # +1% per point of attack vs defense
const MIN_HIT_CHANCE: float = 0.08  # Minimum 8% hit chance (TotalWarSimulator)
const MAX_HIT_CHANCE: float = 0.90  # Maximum 90% hit chance

# Debug mode
var debug_combat: bool = true

# Battle statistics tracking
var battle_stats: Dictionary = {
	"player_kills": 0,
	"player_losses": 0,
	"enemy_kills": 0,
	"enemy_losses": 0,
	"player_unit_stats": {},  # unit_name -> {kills, losses, starting}
	"enemy_unit_stats": {},   # unit_name -> {kills, losses, starting}
	"battle_start_time": 0.0,
	"battle_ended": false
}

# Height/terrain combat modifiers
const MELEE_HEIGHT_BONUS: float = 0.15  # +15% damage when attacker is higher
const MELEE_HEIGHT_PENALTY: float = 0.15  # -15% damage when attacker is lower
const HEIGHT_ADVANTAGE_THRESHOLD: float = 1.5  # Min height diff for bonus
const SLOPE_DEFENSE_BONUS: int = 3  # +3 defense when defending uphill

# Flanking combat modifiers
const FLANK_REAR_ANGLE: float = 135.0     # Angle threshold for rear attack (degrees)
const FLANK_SIDE_ANGLE: float = 45.0      # Angle threshold for flank attack (degrees)
const FLANK_REAR_DAMAGE_MULT: float = 2.0   # Rear attacks deal 2x damage
const FLANK_SIDE_DAMAGE_MULT: float = 1.5   # Side attacks deal 1.5x damage
const FLANK_REAR_MORALE_MULT: float = 1.5   # Rear attacks deal 50% more morale damage
const FLANK_SIDE_MORALE_MULT: float = 1.25  # Side attacks deal 25% more morale damage

# Charge impact
const CHARGE_KNOCKBACK_FORCE: float = 2.0  # Units pushed back on charge impact

var melee_timer: float = 0.0
var _terrain: Node3D = null

# Staggered update system - process 1/BUCKET_COUNT of combats per frame
var _update_bucket: int = 0
const BUCKET_COUNT: int = 16

# Projectile pool for performance (upgraded pooling system)
var _projectile_pool: ProjectilePool = null
var _projectile_scene: PackedScene = null

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
	# Create projectile pool
	_projectile_pool = ProjectilePool.new()
	_projectile_pool.name = "ProjectilePool"
	add_child(_projectile_pool)

	# Keep scene reference for fallback
	_projectile_scene = load("res://battle_system/nodes/projectile.tscn")

	call_deferred("_find_terrain")
	call_deferred("_init_battle_stats")

	# Connect to regiment_dead signal for death effects
	if BattleSignals:
		BattleSignals.regiment_dead.connect(_on_regiment_dead)


## Initialize battle statistics at start
func _init_battle_stats() -> void:
	battle_stats.battle_start_time = Time.get_ticks_msec() / 1000.0
	battle_stats.battle_ended = false
	battle_stats.player_kills = 0
	battle_stats.player_losses = 0
	battle_stats.enemy_kills = 0
	battle_stats.enemy_losses = 0
	battle_stats.player_unit_stats = {}
	battle_stats.enemy_unit_stats = {}

	# Record starting strength of all regiments
	for regiment in get_tree().get_nodes_in_group("all_regiments"):
		if not is_instance_valid(regiment):
			continue
		var stats_dict = battle_stats.player_unit_stats if regiment.is_player_controlled else battle_stats.enemy_unit_stats
		stats_dict[regiment.name] = {
			"display_name": regiment.data.regiment_name if regiment.data else regiment.name,
			"starting": regiment.current_soldiers,
			"kills": 0,
			"losses": 0
		}

	if debug_combat:
		print("[COMBAT] Battle stats initialized - Player units: %d, Enemy units: %d" % [
			battle_stats.player_unit_stats.size(),
			battle_stats.enemy_unit_stats.size()
		])


## Track a kill for statistics
func _track_kill(attacker: Regiment, defender: Regiment, casualties: int) -> void:
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	# Track kills for attacker
	var attacker_stats = battle_stats.player_unit_stats if attacker.is_player_controlled else battle_stats.enemy_unit_stats
	if attacker.name in attacker_stats:
		attacker_stats[attacker.name].kills += casualties

	# Track losses for defender
	var defender_stats = battle_stats.player_unit_stats if defender.is_player_controlled else battle_stats.enemy_unit_stats
	if defender.name in defender_stats:
		defender_stats[defender.name].losses += casualties

	# Track global totals
	if attacker.is_player_controlled:
		battle_stats.player_kills += casualties
	else:
		battle_stats.enemy_kills += casualties

	if defender.is_player_controlled:
		battle_stats.player_losses += casualties
	else:
		battle_stats.enemy_losses += casualties

	if debug_combat:
		print("[COMBAT] %s killed %d from %s (Total: P:%d/%d E:%d/%d)" % [
			attacker.name, casualties, defender.name,
			battle_stats.player_kills, battle_stats.player_losses,
			battle_stats.enemy_kills, battle_stats.enemy_losses
		])

	# Check for battle end
	_check_battle_end()


## Check if battle has ended
func _check_battle_end() -> void:
	if battle_stats.battle_ended:
		return

	var player_alive := 0
	var enemy_alive := 0

	for regiment in get_tree().get_nodes_in_group("all_regiments"):
		if not is_instance_valid(regiment):
			continue
		if regiment.state == Regiment.State.DEAD:
			continue
		if regiment.current_soldiers <= 0:
			continue
		if regiment.is_player_controlled:
			player_alive += 1
		else:
			enemy_alive += 1

	if player_alive == 0 or enemy_alive == 0:
		battle_stats.battle_ended = true
		var start_time: float = battle_stats.battle_start_time
		var duration: float = (Time.get_ticks_msec() / 1000.0) - start_time
		var winner: String = "PLAYER" if enemy_alive == 0 else "ENEMY"

		var separator: String = "=".repeat(60)
		print("\n" + separator)
		print("[BATTLE OVER] %s VICTORY!" % winner)
		print(separator)
		print("Duration: %.1f seconds" % duration)
		print("\n--- PLAYER FORCES ---")
		print("Total Kills: %d | Total Losses: %d" % [battle_stats.player_kills, battle_stats.player_losses])
		for unit_name in battle_stats.player_unit_stats:
			var s = battle_stats.player_unit_stats[unit_name]
			var remaining = s.starting - s.losses
			print("  %s: %d/%d remaining (K:%d L:%d)" % [s.display_name, remaining, s.starting, s.kills, s.losses])

		print("\n--- ENEMY FORCES ---")
		print("Total Kills: %d | Total Losses: %d" % [battle_stats.enemy_kills, battle_stats.enemy_losses])
		for unit_name in battle_stats.enemy_unit_stats:
			var s = battle_stats.enemy_unit_stats[unit_name]
			var remaining = s.starting - s.losses
			print("  %s: %d/%d remaining (K:%d L:%d)" % [s.display_name, remaining, s.starting, s.kills, s.losses])
		print(separator + "\n")

		# Emit battle ended signal with proper Dictionary format
		var result: Dictionary = {
			"winner": winner,
			"player_victory": winner == "PLAYER",
			"casualties": {
				"player_kills": battle_stats.player_kills,
				"player_losses": battle_stats.player_losses,
				"enemy_kills": battle_stats.enemy_kills,
				"enemy_losses": battle_stats.enemy_losses,
				"player_unit_stats": battle_stats.player_unit_stats,
				"enemy_unit_stats": battle_stats.enemy_unit_stats
			},
			"duration": duration
		}
		BattleSignals.battle_ended.emit(result)


func _find_terrain() -> void:
	var terrains: Array[Node] = get_tree().get_nodes_in_group("terrain")
	if terrains.size() > 0:
		_terrain = terrains[0]


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
	var height_diff: float = attacker.global_position.y - defender.global_position.y
	if height_diff > HEIGHT_ADVANTAGE_THRESHOLD:
		return 1.0 + MELEE_HEIGHT_BONUS  # Attacking downhill
	elif height_diff < -HEIGHT_ADVANTAGE_THRESHOLD:
		return 1.0 - MELEE_HEIGHT_PENALTY  # Attacking uphill
	return 1.0


## Get defense bonus for defending on a slope
func _get_slope_defense_bonus(defender: Regiment) -> int:
	if _terrain and _terrain.has_method("get_slope_at"):
		var slope: float = _terrain.get_slope_at(defender.global_position)
		if slope > 10.0:  # On a significant slope
			return SLOPE_DEFENSE_BONUS
	return 0


## Calculate attack angle for flanking detection.
## Returns the angle (in degrees) between attacker's attack direction and defender's facing.
## 0 = frontal attack, 90 = side, 180 = rear
func _calculate_attack_angle(attacker: Regiment, defender: Regiment) -> float:
	# Direction from defender to attacker (where attack is coming from)
	var attack_dir: Vector3 = (attacker.global_position - defender.global_position).normalized()
	attack_dir.y = 0  # Flatten to horizontal plane

	# Defender's facing direction
	var defender_facing: Vector3 = defender.get_facing_direction()
	defender_facing.y = 0

	if attack_dir.length_squared() < 0.001 or defender_facing.length_squared() < 0.001:
		return 0.0  # Default to frontal if invalid

	# Calculate angle between attack direction and defender's facing
	# Dot product gives us cos(angle), which is 1 for frontal (same direction),
	# -1 for rear (opposite direction)
	var dot: float = attack_dir.normalized().dot(defender_facing.normalized())

	# Convert to angle in degrees (0-180 range)
	var angle: float = rad_to_deg(acos(clampf(dot, -1.0, 1.0)))

	return angle


## Get flanking damage multiplier based on attack angle.
## Returns: 1.0 for frontal, 1.5 for flank, 2.0 for rear
func _get_flank_damage_modifier(attacker: Regiment, defender: Regiment) -> float:
	var angle: float = _calculate_attack_angle(attacker, defender)

	if angle > FLANK_REAR_ANGLE:
		return FLANK_REAR_DAMAGE_MULT  # Rear attack
	elif angle > FLANK_SIDE_ANGLE:
		return FLANK_SIDE_DAMAGE_MULT  # Flank attack
	return 1.0  # Frontal attack


## Check if this is a frontal attack (for bracing check).
## Returns true if attacker is hitting defender from the front arc.
func _is_frontal_attack(attacker: Regiment, defender: Regiment) -> bool:
	var angle: float = _calculate_attack_angle(attacker, defender)
	return angle <= FLANK_SIDE_ANGLE  # Front is within side flank angle threshold


## Get flanking morale damage multiplier.
func _get_flank_morale_modifier(attacker: Regiment, defender: Regiment) -> float:
	var angle: float = _calculate_attack_angle(attacker, defender)

	if angle > FLANK_REAR_ANGLE:
		return FLANK_REAR_MORALE_MULT
	elif angle > FLANK_SIDE_ANGLE:
		return FLANK_SIDE_MORALE_MULT
	return 1.0


## Check if attack is a flank attack (for UI/debug)
func is_flank_attack(attacker: Regiment, defender: Regiment) -> bool:
	var angle: float = _calculate_attack_angle(attacker, defender)
	return angle > FLANK_SIDE_ANGLE


## Check if attack is a rear attack (for UI/debug)
func is_rear_attack(attacker: Regiment, defender: Regiment) -> bool:
	var angle: float = _calculate_attack_angle(attacker, defender)
	return angle > FLANK_REAR_ANGLE

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
			print("CombatManager: Charge INVALID - %s only traveled %.1f (need %.1f)" % [
				attacker.name, attacker.charge_distance_traveled, attacker.MIN_CHARGE_DISTANCE])
		else:
			var was_braced: bool = defender.is_braced
			# Check if bracing applies (frontal charges only)
			var is_frontal_charge: bool = _is_frontal_attack(attacker, defender)

			if was_braced and is_frontal_charge:
				# Defender braced against frontal charge - negate bonus, reduce impact
				charge_negated = true
				print("CombatManager: Charge impact NEGATED! %s charged braced %s (frontal)" % [attacker.name, defender.name])
				# Spawn block effect for braced defender
				if CombatEffects:
					CombatEffects.spawn_block(defender.global_position + Vector3(0, 1.2, 0))
			else:
				# Successful charge impact - calculate impact damage
				var impact_damage: int = attacker.get_charge_impact_damage()
				if impact_damage > 0:
					# Apply impact damage (partially armor-piercing per TotalWarSimulator)
					var ap_damage: int = int(impact_damage * 0.7)  # 70% armor-piercing
					var normal_damage: int = impact_damage - ap_damage
					# Impact causes instant casualties
					var total_impact_casualties: int = max(1, impact_damage / 3)
					defender.take_casualties(total_impact_casualties)
					defender.take_morale_damage(float(impact_damage) * 0.5)
					print("CombatManager: Charge impact! %s hit %s for %d impact damage (%d casualties)" % [
						attacker.name, defender.name, impact_damage, total_impact_casualties])

				print("CombatManager: Charge bonus: %d, distance: %.1f" % [
					attacker.data.charge_bonus, attacker.charge_distance_traveled])

			# Emit charge impact signal
			BattleSignals.charge_impact.emit(attacker, defender, was_braced and is_frontal_charge)

			# Play charge impact audio
			_play_combat_sfx("cavalry_charge_01", defender.global_position)

		# Mark attacker as having charged
		attacker.has_charged = true

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

	print("[COMBAT] Disengaging regiment: ", regiment.name)

	# Find and remove all melees involving this regiment
	var melees_to_end: Array[Dictionary] = []
	for melee in active_melees:
		if melee.get("attacker") == regiment or melee.get("defender") == regiment:
			melees_to_end.append(melee)

	for melee in melees_to_end:
		var att = melee.get("attacker")
		var def = melee.get("defender")

		# The other regiment returns to IDLE
		if att == regiment and is_instance_valid(def):
			def.set_state(Regiment.State.IDLE)
			def.has_charged = false
		elif def == regiment and is_instance_valid(att):
			att.set_state(Regiment.State.IDLE)
			att.has_charged = false

		# Remove the melee
		end_melee(att, def)

	# The disengaging regiment returns to IDLE (caller will set MARCHING)
	regiment.set_state(Regiment.State.IDLE)
	regiment.has_charged = false


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

	# Transition disengaged regiments to IDLE so they can receive new orders
	for regiment in regiments_to_disengage:
		if is_instance_valid(regiment) and regiment.state == Regiment.State.ENGAGING:
			print("[COMBAT] %s disengaging from melee -> IDLE" % regiment.name)
			regiment.set_state(Regiment.State.IDLE)
			regiment.reset_charge_state()

## Resolve one melee tick
func _resolve_melee_tick(melee: Dictionary) -> void:
	var att: Regiment = melee["attacker"]
	var def: Regiment = melee["defender"]

	# Update charge time for decay calculation
	melee["charge_time"] += MELEE_TICK_RATE

	# Calculate damage using regiment modifiers (formation + veterancy + stamina + buffs)
	var att_base: int = att.data.attack
	var att_modifier: float = att.get_attack_modifier()  # Includes formation, veterancy, inspire, stamina
	var att_score: int = int(float(att_base) * att_modifier)

	# Apply decaying charge bonus (Total War style - decays linearly over 10 seconds)
	# Charge bonus requires minimum distance traveled and not negated by bracing
	var charge_bonus_applied: bool = false
	if att.data.charge_bonus > 0 and not melee.get("charge_negated", false):
		# Check if attacker was charging AND traveled minimum distance
		var had_valid_charge: bool = melee.get("charge_applied", false) or att.has_valid_charge()
		if (att.current_order == OrderType.Type.CHARGE or melee.get("charge_applied", false)) and had_valid_charge:
			# Calculate charge decay: 100% at t=0, 0% at t=CHARGE_DECAY_DURATION
			var charge_decay: float = clampf(1.0 - (melee["charge_time"] / CHARGE_DECAY_DURATION), 0.0, 1.0)
			if charge_decay > 0.0:
				# Apply weather modifier to charge bonus (muddy/wet ground reduces charge effectiveness)
				var weather_adjusted_charge: int = WeatherSystem.apply_charge_modifier(att.data.charge_bonus)
				# Apply formation charge modifier (WEDGE: 1.5x, COLUMN: 1.3x, LINE: 0.9x, etc.)
				var formation_charge_mod: float = att.get_charge_modifier()
				# Apply decay to get effective charge bonus
				var effective_charge: int = int(float(weather_adjusted_charge) * formation_charge_mod * charge_decay)
				att_score += effective_charge
				charge_bonus_applied = true
				if debug_combat and effective_charge > 0:
					print("[COMBAT] Charge bonus: %d (%.0f%% decay remaining)" % [effective_charge, charge_decay * 100.0])

	# Apply anti-cavalry modifier if attacker is cavalry
	if att.data.unit_type == UnitType.Type.CAVALRY:
		var anti_cav: float = def.get_anti_cavalry_modifier()
		if anti_cav > 1.0:
			# Reduce attacker effectiveness vs anti-cavalry formations
			att_score = int(float(att_score) / anti_cav)

	# Calculate defense using regiment modifiers (formation + braced status)
	var def_base: int = def.data.defense
	var def_modifier: float = def.get_defense_modifier()  # Includes formation, braced status
	var def_score: int = int(float(def_base) * def_modifier) + _get_slope_defense_bonus(def)

	# Total War-style hit chance: Base 40% + (attack - defense), clamped 10%-90%
	var hit_chance: float = clampf(BASE_HIT_CHANCE + (float(att_score - def_score) * HIT_CHANCE_PER_SKILL), MIN_HIT_CHANCE, MAX_HIT_CHANCE)
	if randf() > hit_chance:
		# Miss - no damage this tick
		if debug_combat:
			print("[COMBAT] %s MISSED %s (%.0f%% hit chance)" % [att.name, def.name, hit_chance * 100.0])
		melee["charge_applied"] = true  # Still mark charge as applied even on miss
		return

	# Calculate base casualties
	var base_casualties: int = _calculate_casualties(att_score, def_score, att.data.strength)

	# Apply height modifier
	var height_mod: float = _get_height_modifier(att, def)

	# Apply flanking modifier (MAJOR ADDITION)
	var flank_mod: float = _get_flank_damage_modifier(att, def)
	var flank_morale_mod: float = _get_flank_morale_modifier(att, def)

	# Apply AI personality stat_multiplier (affects AI damage output)
	var ai_stat_mod: float = _get_ai_stat_multiplier(att)

	# Calculate final casualties with all modifiers (including global slowdown)
	var casualties: int = maxi(1, int(float(base_casualties) * height_mod * flank_mod * ai_stat_mod * COMBAT_DAMAGE_MULTIPLIER))

	# Debug combat output
	if debug_combat:
		print("[COMBAT] %s(%d) attacks %s(%d) - ATK:%d vs DEF:%d = %d casualties" % [
			att.name, att.current_soldiers, def.name, def.current_soldiers,
			att_score, def_score, casualties
		])

	# Log flanking attacks for debugging
	if flank_mod > 1.0:
		var flank_type: String = "REAR" if flank_mod >= FLANK_REAR_DAMAGE_MULT else "FLANK"
		print("[COMBAT] %s attack! %s -> %s (%.1fx damage)" % [flank_type, att.name, def.name, flank_mod])

	# Apply high ground morale modifier
	_apply_height_morale_modifier(att, def)

	# Defender takes damage
	def.take_casualties(casualties)

	# Track statistics
	_track_kill(att, def, casualties)

	# Play melee hit audio and spawn visual effect
	_play_combat_sfx_random("sword_hit", 5, def.global_position)
	if CombatEffects:
		CombatEffects.spawn_melee_hit(def.global_position + Vector3(0, 1.0, 0))

	# Play death cries for casualties
	if casualties > 0:
		_play_death_cry(def.global_position, casualties)

	# Apply morale damage with flank modifier
	var morale_damage: float = casualties * 0.5 * flank_morale_mod
	MoraleSystem.apply_morale_damage(def, morale_damage)
	damage_dealt.emit(def, casualties, att, "melee")
	BattleSignals.regiment_attacked.emit(att, def, casualties)

	# Push per-soldier morale events for casualties
	_push_casualty_morale_events(def, casualties, att)

	# Apply flanking morale penalty events
	if flank_mod > 1.0:
		_apply_flank_morale_events(def, att, flank_mod >= FLANK_REAR_DAMAGE_MULT)

	# Track kills for veterancy
	if att.veterancy and casualties > 0:
		for i in casualties:
			att.veterancy.add_kill()

	# Defender hits back (unless routing or dead)
	if def.state != Regiment.State.ROUTING and def.current_soldiers > 0:
		# Defender's attack with modifiers
		var def_base2: int = def.data.attack
		var def_modifier2: float = def.get_attack_modifier()
		var def_score2: int = int(float(def_base2) * def_modifier2)

		# Attacker's defense with modifiers
		var att_base2: int = att.data.defense
		var att_modifier2: float = att.get_defense_modifier()
		var att_score2: int = int(float(att_base2) * att_modifier2) + _get_slope_defense_bonus(att)

		# Anti-cavalry check for defender
		if def.data.unit_type == UnitType.Type.CAVALRY:
			var anti_cav2: float = att.get_anti_cavalry_modifier()
			if anti_cav2 > 1.0:
				def_score2 = int(float(def_score2) / anti_cav2)

		# Total War-style hit chance for counter-attack
		var counter_hit_chance: float = clampf(BASE_HIT_CHANCE + (float(def_score2 - att_score2) * HIT_CHANCE_PER_SKILL), MIN_HIT_CHANCE, MAX_HIT_CHANCE)
		if randf() > counter_hit_chance:
			# Counter-attack missed
			if debug_combat:
				print("[COMBAT] %s counter-attack MISSED %s (%.0f%% hit chance)" % [def.name, att.name, counter_hit_chance * 100.0])
			melee["charge_applied"] = true
			return

		var base_counter: int = _calculate_casualties(def_score2, att_score2, def.data.strength)

		# Apply height modifier (defender attacking, attacker defending)
		var counter_height_mod: float = _get_height_modifier(def, att)

		# Defender's counter-attack also checks flanking (they might be flanking the attacker)
		var counter_flank_mod: float = _get_flank_damage_modifier(def, att)
		var counter_flank_morale_mod: float = _get_flank_morale_modifier(def, att)

		# Apply AI personality stat_multiplier for defender's counter-attack
		var counter_ai_stat_mod: float = _get_ai_stat_multiplier(def)

		var counter_casualties: int = maxi(1, int(float(base_counter) * counter_height_mod * counter_flank_mod * counter_ai_stat_mod * COMBAT_DAMAGE_MULTIPLIER))

		# Debug counter-attack
		if debug_combat:
			print("[COMBAT] %s(%d) counter-attacks %s(%d) - ATK:%d vs DEF:%d = %d casualties" % [
				def.name, def.current_soldiers, att.name, att.current_soldiers,
				def_score2, att_score2, counter_casualties
			])

		att.take_casualties(counter_casualties)

		# Track statistics for counter-attack
		_track_kill(def, att, counter_casualties)

		# Play melee hit audio and spawn visual effect for counter-attack
		_play_combat_sfx_random("sword_hit", 5, att.global_position)
		if CombatEffects:
			CombatEffects.spawn_melee_hit(att.global_position + Vector3(0, 1.0, 0))

		# Play death cries for counter-attack casualties
		if counter_casualties > 0:
			_play_death_cry(att.global_position, counter_casualties)

		var counter_morale_damage: float = counter_casualties * 0.5 * counter_flank_morale_mod
		MoraleSystem.apply_morale_damage(att, counter_morale_damage)
		damage_dealt.emit(att, counter_casualties, def, "melee")

		# Push per-soldier morale events for casualties
		_push_casualty_morale_events(att, counter_casualties, def)

		# Apply flanking morale penalty events to attacker if being flanked
		if counter_flank_mod > 1.0:
			_apply_flank_morale_events(att, def, counter_flank_mod >= FLANK_REAR_DAMAGE_MULT)

		# Track counter-attack kills for defender's veterancy
		if def.veterancy and counter_casualties > 0:
			for i in counter_casualties:
				def.veterancy.add_kill()

	melee["charge_applied"] = true

## Calculate casualties using simple formula
func _calculate_casualties(attack: int, defense: int, strength: int) -> int:
	# d10-style resolution
	var margin: int = max(0, attack - defense)
	var base: int = randi() % 3 + 1  # 1-3 base casualties
	return base + int(margin / 5) + int(strength / 3)

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

## Friendly fire chance when shooting into melee
const FRIENDLY_FIRE_CHANCE: float = 0.15  # 15% chance to hit friendly

## Fire ranged attack
func fire_ranged(attacker: Regiment, target: Regiment) -> void:
	print("[RANGED] fire_ranged called: %s -> %s" % [attacker.name, target.name])

	if attacker.current_ammo <= 0:
		print("[RANGED] BLOCKED: No ammo")
		return
	if attacker.data.ballistic_skill == 0:
		print("[RANGED] BLOCKED: No ballistic_skill")
		return

	# Weather LOS check - weather may block ranged attacks at distance
	if WeatherSystem.blocks_los(attacker.global_position.distance_to(target.global_position)):
		print("[RANGED] BLOCKED: Weather blocks LOS")
		return

	# LoS check
	if not _has_line_of_sight(attacker, target):
		print("[RANGED] BLOCKED: No LOS")
		return

	# Range check
	var dist: float = attacker.global_position.distance_to(target.global_position)
	if dist > attacker.data.range_distance:
		print("[RANGED] BLOCKED: Out of range (%.1f > %.1f)" % [dist, attacker.data.range_distance])
		return

	print("[RANGED] FIRING! ammo %d -> %d" % [attacker.current_ammo, attacker.current_ammo - 1])
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
				print("CombatManager: FRIENDLY FIRE! %s hit %s while aiming at %s" % [
					attacker.name, friendly.name, target.name
				])

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
func resolve_ranged_hit_with_multiplier(attacker: Regiment, defender: Regiment, damage_multiplier: float = 1.0) -> void:
	# Calculate hit chance with attacker's ranged modifier (formation + veterancy + stamina)
	var base_hit_chance: float = attacker.data.ballistic_skill / 20.0  # 0-1
	var ranged_mod: float = attacker.get_ranged_modifier()
	var hit_chance: float = base_hit_chance * ranged_mod

	# Apply weather accuracy modifier (rain, fog, storm reduce accuracy)
	hit_chance = WeatherSystem.apply_accuracy_modifier(hit_chance)

	if randf() > hit_chance:
		return  # Miss

	# Play arrow impact audio
	_play_combat_sfx_random("arrow_hit", 3, defender.global_position)

	# Base damage
	var damage: int = max(1, attacker.data.strength - defender.data.defense / 2)

	# Apply high ground bonus/penalty
	var height_diff: float = attacker.global_position.y - defender.global_position.y
	if height_diff > 1.0:
		damage = int(float(damage) * 1.15)  # High ground bonus for ranged
	elif height_diff < -1.0:
		damage = int(float(damage) * 0.85)  # Low ground penalty for ranged

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
		print("[COMBAT] RANGED(pierce) %s(%d) hits %s(%d) for %d damage" % [
			attacker.name, attacker.current_soldiers, defender.name, defender.current_soldiers, damage
		])

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

	MoraleSystem.apply_morale_damage(defender, damage * 0.3)
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
	# Staggered combat resolution - process one bucket per frame
	# Each combat gets resolved once every BUCKET_COUNT frames
	# Combined with MELEE_TICK_RATE, effective tick rate = MELEE_TICK_RATE * BUCKET_COUNT frames
	melee_timer += delta
	if melee_timer >= MELEE_TICK_RATE / float(BUCKET_COUNT):
		melee_timer = 0.0
		var start_time := Time.get_ticks_usec()
		_resolve_all_melees()
		var elapsed := (Time.get_ticks_usec() - start_time) / 1000.0
		if elapsed > 16.0:  # More than 16ms = frame drop
			print("[PERF_WARN] Combat _resolve_all_melees took %.1fms (melees=%d)" % [elapsed, active_melees.size()])
		_update_bucket = (_update_bucket + 1) % BUCKET_COUNT
	_update_charge_timers(delta)


## Push per-soldier morale events when casualties occur
func _push_casualty_morale_events(defender: Regiment, casualties: int, attacker: Regiment) -> void:
	if not defender.unit_morale:
		return

	# For each casualty, push friend_killed event to nearby soldiers
	for i in casualties:
		var event: MoraleEvent = MoraleEvent.friend_killed(defender.global_position)
		defender.unit_morale.apply_event_to_nearby(
			event,
			defender.global_position,
			MoraleConstants.FRIEND_KILLED_RADIUS
		)

	# Give kill morale boost to attacker
	if attacker.unit_morale and casualties > 0:
		var kill_event: MoraleEvent = MoraleEvent.kill_enemy(defender.global_position)
		attacker.unit_morale.apply_event_to_nearby(
			kill_event,
			attacker.global_position,
			MoraleConstants.FRIEND_KILLED_RADIUS
		)


## Apply high ground morale modifiers during melee combat
func _apply_height_morale_modifier(attacker: Regiment, defender: Regiment) -> void:
	var height_diff: float = attacker.global_position.y - defender.global_position.y

	# Attacker on high ground
	if height_diff > HEIGHT_ADVANTAGE_THRESHOLD:
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
	elif height_diff < -HEIGHT_ADVANTAGE_THRESHOLD:
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
