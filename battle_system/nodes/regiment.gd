class_name Regiment
extends Node3D

# Preload to avoid parse-order issues with class_name
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")

@export var data: RegimentData
@export var use_3d_soldiers: bool = true  ## Use 3D animated soldiers (placeholder blocks)
@export var use_sprite_soldiers: bool = false  ## Add batched 2D billboard sprites ON TOP of 3D soldiers
@export var soldier_scene: PackedScene    ## The soldier scene to instance
@export var sprite_atlas: SpriteUnitAtlas  ## Atlas for sprite soldiers

# Runtime state (do not set these in the inspector)
var current_morale: float
var current_soldiers: int
var current_ammo: int
var current_order: OrderType.Type = OrderType.Type.NONE
var is_player_controlled: bool = true
var group_id: int = -1          # -1 = no saved group

# Movement group sync (spring1944-inspired)
# When multiple regiments move together, they sync to slowest speed
var movement_group: Array[Regiment] = []  # Regiments moving with us
var _group_min_speed: float = -1.0        # Cached min speed of group (-1 = no group)
var _group_speed_dirty: bool = false      # Only recalc when stamina changes

# Territory tracking (DEI-inspired - set by campaign layer)
var is_in_friendly_territory: bool = false  # +10% morale when true
var is_in_enemy_territory: bool = false     # -10% morale when true

# Morale modifier optimization - track last state to avoid per-frame iteration
var _last_territory_friendly: bool = false
var _last_territory_enemy: bool = false
var _last_in_melee_for_morale: bool = false  # For unit type morale checks

# Stance and Formation
var current_stance: StanceType.Type = StanceType.Type.AGGRESSIVE
var current_formation: FormationType.Type = FormationType.Type.LINE
var guard_target: Regiment = null  # Unit being guarded (if GUARD stance)

# Formation transition state
var is_reforming: bool = false      # Currently changing formation
var reform_timer: float = 0.0       # Time remaining in transition
var reform_target: FormationType.Type = FormationType.Type.LINE  # Target formation

# Stamina, Veterancy, Abilities
var stamina: StaminaSystem = null
var veterancy: VeterancySystem = null
var abilities: AbilityManager = null

# Combat state flags
var is_braced: bool = false      # Braced against charge
var hold_fire: bool = false      # Don't auto-fire
var inspire_active: bool = false # Inspired by general
var has_charged: bool = false    # Has applied charge bonus this engagement

# Charge tracking
var charge_start_position: Vector3 = Vector3.ZERO  # Position when charge started
var charge_distance_traveled: float = 0.0           # Distance traveled during charge
const MIN_CHARGE_DISTANCE: float = 10.0             # Minimum distance to apply charge bonus

# Engagement constants (Phase 1 fix)
const ENGAGEMENT_DISTANCE: float = 3.0              # Desired center-to-center separation in melee
const ENGAGEMENT_DEAD_ZONE: float = 0.5             # ±0.5 units from ideal = no correction (prevents oscillation)
const ENGAGEMENT_DECEL_RATE: float = 8.0            # Units/sec of corrective movement toward ideal spacing
const APPROACH_OFFSET: float = 4.0                  # Attack approach point offset (slightly beyond ENGAGEMENT_DISTANCE)


## Static helper: Get approach position for attacking a target.
## Aims for a point just outside the target's engagement distance to prevent nav agent
## from trying to path through the enemy.
static func get_attack_approach_position(attacker_pos: Vector3, target_pos: Vector3) -> Vector3:
	var to_target: Vector3 = target_pos - attacker_pos
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		return target_pos  # Already on top of them
	var approach_dir: Vector3 = to_target.normalized()
	return target_pos - approach_dir * APPROACH_OFFSET


# Facing direction for flanking calculations
var _facing_direction: Vector3 = Vector3.FORWARD

# Spatial hash optimization - only update when position changes significantly
var _last_hash_position: Vector3 = Vector3.ZERO
const HASH_UPDATE_THRESHOLD: float = 2.0  # Update spatial hash when moved 2+ units

# Smooth rotation system (inspired by spring1944)
var _target_heading: float = 0.0  # Desired heading toward enemy
var _current_heading: float = 0.0  # Current actual heading
var _combat_facing_locked: bool = false  # Hysteresis flag to prevent spinning
const DEFAULT_TURN_SPEED: float = 3.0  # radians per second fallback
const HEADING_THRESHOLD: float = 0.05  # ~3 degrees - prevents micro-adjustments
const COMBAT_FACING_LOCK: float = 0.35  # ~20 degrees - stop rotating once aligned
const COMBAT_FACING_UNLOCK: float = 0.7  # ~40 degrees - only resume rotating if enemy moves significantly

# Internal refs
@onready var sprite: Sprite3D = $Sprite3D
@onready var nav_agent: NavigationAgent3D = $RegimentLeader/NavigationAgent3D
@onready var leader: RegimentLeader = $RegimentLeader
@onready var melee_area: Area3D = $MeleeArea

# Soldier formation (SoldierFormation for 3D soldiers)
var formation: Node3D = null
# Sprite overlay (SpriteFormation rendered on top of 3D soldiers)
var sprite_overlay: SpriteFormation = null

# AI and Morale systems
var ai_controller: CommanderAI = null
var unit_morale: UnitMorale = null

enum State { IDLE, MARCHING, ENGAGING, ROUTING, RALLYING, DEAD }
var state: State = State.IDLE

# Animation mapping for states (lowercase to match atlas definitions)
const STATE_ANIMATIONS := {
	State.IDLE: "idle",
	State.MARCHING: "walk",
	State.ENGAGING: "attack",
	State.ROUTING: "walk",
	State.RALLYING: "idle",
}


func _ready():
	# Safety check - data must be assigned before ready
	if not data:
		push_error("Regiment '%s' has no RegimentData assigned! Freeing invalid regiment." % name)
		queue_free()
		return

	current_morale = data.base_morale
	current_soldiers = data.max_soldiers
	current_ammo = data.max_ammo

	# Set leader speeds from regiment data
	if leader and data:
		leader.walk_speed = data.walk_speed
		leader.run_speed = data.run_speed
		leader.charge_speed = data.charge_speed
		leader.charge_speed_distance = data.charge_speed_distance

	# Initialize new systems
	_setup_stamina()
	_setup_veterancy()
	_setup_abilities()

	# Set up visuals based on mode
	# 3D soldiers provide collision/selection, sprites render on top
	if use_3d_soldiers:
		_setup_3d_formation()
		sprite.visible = false
	elif data.sprite_texture:
		sprite.texture = data.sprite_texture
		sprite.visible = true
	else:
		sprite.visible = false

	# Add sprite overlay on top of 3D formation if enabled
	if use_sprite_soldiers:
		_setup_sprite_overlay()

	# Set MeleeArea to collision layer 2 for unit selection
	melee_area.collision_layer = 2
	melee_area.collision_mask = 2  # Detect other units
	melee_area.area_entered.connect(_on_melee_area_contact)
	melee_area.monitorable = true
	melee_area.monitoring = true
	# Add to groups for signal-based selection
	add_to_group("all_regiments")
	if is_player_controlled:
		add_to_group("player_regiments")
	else:
		add_to_group("enemy_regiments")

	# Initialize per-soldier morale system
	_setup_unit_morale()

	# Register with AIAutoload for spatial queries and AI tracking
	if AIAutoload:
		AIAutoload.register_regiment(self)

	# Force idle animation on startup
	call_deferred("_force_idle_animation")

	# Snap to terrain height after terrain is ready, then initialize AI
	call_deferred("_snap_to_terrain_then_init_ai")


func _setup_stamina():
	stamina = StaminaSystem.new()
	stamina.exhausted.connect(_on_stamina_exhausted)
	stamina.recovered.connect(_on_stamina_recovered)
	# Apply armor weight fatigue penalty (Stainless Steel pattern)
	if data:
		stamina.setup_from_regiment_data(data)


func _setup_veterancy():
	veterancy = VeterancySystem.new()
	veterancy.level_up.connect(_on_level_up)


func _setup_abilities():
	abilities = AbilityManager.new(self)
	abilities.ability_activated.connect(_on_ability_activated)
	abilities.ability_ended.connect(_on_ability_ended)


func _setup_3d_formation():
	var soldier_formation := SoldierFormation.new()

	# Use provided soldier scene or fallback to placeholder blocks
	if soldier_scene:
		soldier_formation.soldier_scene = soldier_scene
	else:
		soldier_formation.soldier_scene = load("res://battle_system/units/soldier_block.tscn")

	soldier_formation.max_soldiers = data.max_soldiers
	soldier_formation.rows = ceili(sqrt(float(data.max_soldiers)))
	soldier_formation.spacing = 1.2
	soldier_formation.faction_color = data.faction_color
	add_child(soldier_formation)
	formation = soldier_formation


func _setup_sprite_overlay():
	## Set up batched sprite overlay using MultiMesh for performance.
	## Sprites render ON TOP of 3D soldiers for visual fidelity.
	var sprite_formation := SpriteFormation.new()

	# Use provided atlas or try to get from data
	if sprite_atlas:
		sprite_formation.atlas = sprite_atlas
	elif data and data.sprite_atlas:
		sprite_formation.atlas = data.sprite_atlas

	sprite_formation.max_soldiers = data.max_soldiers
	sprite_formation.rows = ceili(sqrt(float(data.max_soldiers)))
	sprite_formation.spacing = 1.2
	sprite_formation.faction_color = data.faction_color
	add_child(sprite_formation)
	sprite_overlay = sprite_formation


func _force_idle_animation():
	## Force idle animation on both 3D formation and sprite overlay.
	if formation:
		formation.play_animation_all("Idle")
	if sprite_overlay:
		sprite_overlay.play_animation_all("idle")


func _snap_to_terrain_then_init_ai():
	## Snap to terrain first, then initialize AI to ensure proper positioning.
	await _snap_to_terrain()

	# Safety check - regiment might have been freed during await
	if not is_instance_valid(self):
		return

	# Initialize AI controller for enemy units (after terrain snap)
	if not is_player_controlled:
		_setup_ai_controller()


func _snap_to_terrain():
	## Snap regiment and all its parts to terrain height.
	# Wait a bit for terrain to generate
	await get_tree().create_timer(0.6).timeout

	# Safety check - regiment might have been freed during await
	if not is_instance_valid(self):
		return

	# Find terrain (Phase 6.4: use helper)
	var terrain := TerrainHelperScript.get_terrain(get_tree())
	if not terrain:
		return

	# Get terrain height at our XZ position
	var terrain_height = terrain.get_height_at(global_position)

	# Update all positions
	global_position.y = terrain_height
	if leader:
		leader.global_position.y = terrain_height
	if formation:
		formation.global_position.y = terrain_height
	if sprite_overlay:
		sprite_overlay.global_position.y = terrain_height
	if melee_area:
		melee_area.global_position.y = terrain_height


func _setup_unit_morale():
	## Initialize the per-soldier morale system.
	unit_morale = UnitMorale.new(self)

	# Register soldiers if formation exists
	if formation and is_instance_valid(formation):
		# Check if formation is already ready (has soldiers)
		if formation.soldiers.size() > 0:
			unit_morale.register_soldiers(formation.soldiers, data.base_morale)
		else:
			# Wait for formation to be ready with timeout
			var waited := 0.0
			while formation.soldiers.size() == 0 and waited < 2.0:
				await get_tree().create_timer(0.1).timeout
				waited += 0.1
				# Safety check during wait
				if not is_instance_valid(self) or not is_instance_valid(formation):
					break
			# Register if valid and has soldiers
			if is_instance_valid(self) and is_instance_valid(formation) and formation.soldiers.size() > 0:
				unit_morale.register_soldiers(formation.soldiers, data.base_morale)

	# Safety check before connecting signals
	if not is_instance_valid(self):
		return

	# Connect signals
	unit_morale.unit_routed.connect(_on_unit_morale_routed)
	unit_morale.unit_rallied.connect(_on_unit_morale_rallied)
	unit_morale.average_morale_changed.connect(_on_average_morale_changed)


func _setup_ai_controller():
	## Initialize AI controller for this regiment.
	ai_controller = CommanderAI.new(self, null)


func enable_ai_assist(enabled: bool):
	## Enable/disable AI assist mode for player units.
	if enabled and not ai_controller:
		ai_controller = CommanderAI.new(self, null)
		ai_controller.auto_assist_enabled = true
	elif ai_controller:
		ai_controller.auto_assist_enabled = enabled


func _process(delta):
	# Update formation transition timer
	if is_reforming:
		reform_timer -= delta
		if reform_timer <= 0:
			is_reforming = false
			reform_timer = 0.0
			BattleSignals.formation_reform_completed.emit(self)

	# Update per-soldier morale system
	if unit_morale:
		unit_morale.update(delta)
		# Apply territory morale modifiers ONLY when territory changes (optimization)
		if is_in_friendly_territory != _last_territory_friendly or is_in_enemy_territory != _last_territory_enemy:
			_apply_territory_morale_modifiers()
			_last_territory_friendly = is_in_friendly_territory
			_last_territory_enemy = is_in_enemy_territory
		# Apply unit type morale modifiers ONLY when combat state changes (optimization)
		var in_melee: bool = state == State.ENGAGING
		if in_melee != _last_in_melee_for_morale:
			_apply_unit_type_morale_modifiers()
			_last_in_melee_for_morale = in_melee

	# Update stamina system
	if stamina:
		# Set movement mode based on state
		match state:
			State.IDLE, State.RALLYING:
				stamina.set_movement_mode(StaminaSystem.MovementMode.IDLE)
			State.MARCHING:
				if current_order == OrderType.Type.CHARGE:
					stamina.set_movement_mode(StaminaSystem.MovementMode.CHARGING)
				else:
					stamina.set_movement_mode(StaminaSystem.MovementMode.WALKING)
			State.ROUTING:
				stamina.set_movement_mode(StaminaSystem.MovementMode.RUNNING)
			State.ENGAGING:
				stamina.set_movement_mode(StaminaSystem.MovementMode.IDLE)
		stamina.update(delta)

		# Only recalculate group min speed when stamina state changes (optimization)
		if movement_group.size() > 0 and _group_speed_dirty:
			_recalculate_group_min_speed()
			_group_speed_dirty = false

		# Update leader's speed modifier with fatigue + formation penalties (DEI-inspired)
		if leader:
			leader.speed_modifier = get_speed_modifier()

	# Update abilities (cooldowns)
	if abilities:
		abilities.update(delta)

	# Smooth rotation toward enemy during combat (spring1944-style)
	_update_combat_facing(delta)


func _physics_process(delta):
	# Update position in spatial hash only when moved significantly (optimization)
	if AIAutoload and AIAutoload.spatial_hash:
		if global_position.distance_squared_to(_last_hash_position) > HASH_UPDATE_THRESHOLD * HASH_UPDATE_THRESHOLD:
			AIAutoload.spatial_hash.update_position(self, global_position)
			_last_hash_position = global_position

	match state:
		State.MARCHING:  _process_march(delta)
		State.ENGAGING:  _process_engage(delta)
		State.ROUTING:   _process_route(delta)
		State.RALLYING:  _process_rally(delta)


func _update_combat_facing(delta: float) -> void:
	## Smoothly rotate regiment toward enemy during combat (spring1944-style).
	## Uses atan2 heading calculation with smooth interpolation and hysteresis.
	if state != State.ENGAGING:
		_combat_facing_locked = false  # Reset lock when not engaging
		return

	# Find current combat target
	var enemy := _find_current_combat_target()
	if not enemy or not is_instance_valid(enemy):
		_combat_facing_locked = false
		return

	# Calculate desired heading toward enemy using atan2
	var dir := enemy.global_position - global_position
	dir.y = 0  # Keep rotation horizontal
	if dir.length_squared() < 0.1:
		return  # Too close, don't spin

	_target_heading = atan2(dir.x, dir.z)

	# Smooth rotation toward target heading
	var angle_diff := _wrap_angle(_target_heading - _current_heading)

	# Hysteresis to prevent spinning:
	# - Once locked (facing within COMBAT_FACING_LOCK), stay locked
	# - Only unlock if enemy moves significantly (beyond COMBAT_FACING_UNLOCK)
	if _combat_facing_locked:
		if absf(angle_diff) < COMBAT_FACING_UNLOCK:
			return  # Stay locked, don't rotate
		else:
			_combat_facing_locked = false  # Enemy moved significantly, unlock
	else:
		if absf(angle_diff) < COMBAT_FACING_LOCK:
			_combat_facing_locked = true  # Now facing enemy, lock in place
			return

	if absf(angle_diff) > HEADING_THRESHOLD:
		# Use data.turn_rate if available, otherwise fallback to default
		var turn_speed := data.turn_rate if data else DEFAULT_TURN_SPEED
		# Apply turn speed (spring1944-style frame-by-frame interpolation)
		var turn_amount: float = signf(angle_diff) * minf(absf(angle_diff), turn_speed * delta)
		_current_heading = _wrap_angle(_current_heading + turn_amount)

		# Update facing direction for flanking calculations
		_facing_direction = Vector3(sin(_current_heading), 0, cos(_current_heading))

		# Update sprite overlay facing (smooth, not instant)
		if sprite_overlay:
			sprite_overlay.set_facing_angle(_current_heading)
		if formation and formation.has_method("set_facing_direction"):
			formation.set_facing_direction(_facing_direction)


func _wrap_angle(angle: float) -> float:
	## Wrap angle to [-PI, PI] range (shortest-path wrapping).
	while angle > PI:
		angle -= TAU
	while angle < -PI:
		angle += TAU
	return angle


# --- STATE TRANSITIONS ---
func set_state(new_state: State):
	# Prevent duplicate state transitions (especially important for DEAD state)
	if state == new_state:
		return
	# Once dead, cannot transition to other states
	if state == State.DEAD:
		return

	var old_state = state
	state = new_state

	# Update 3D soldier animations
	if formation and old_state != new_state:
		var anim_name = STATE_ANIMATIONS.get(new_state, "Idle")
		if new_state == State.ENGAGING:
			formation.play_animation_staggered(anim_name, 0.03)
		else:
			formation.play_animation_all(anim_name)

	# Update sprite overlay animations (uses lowercase names)
	if sprite_overlay and old_state != new_state:
		var sprite_anim = STATE_ANIMATIONS.get(new_state, "Idle").to_lower()
		if new_state == State.ENGAGING:
			sprite_overlay.play_animation_staggered(sprite_anim, 0.03)
		else:
			sprite_overlay.play_animation_all(sprite_anim)

	match new_state:
		State.ROUTING:
			BattleSignals.regiment_routing.emit(self)
			# Routing units flee at run speed
			if leader:
				leader.set_move_mode(RegimentLeader.MoveMode.RUN)
		State.IDLE:
			# Reset to walk speed when idle
			if leader:
				leader.set_move_mode(RegimentLeader.MoveMode.WALK)
		State.DEAD:
			BattleSignals.regiment_dead.emit(self)
			# Clean up from combat systems before freeing
			CombatManager.disengage_regiment(self)
			# Delay queue_free to let other systems clean up references
			get_tree().create_timer(0.5).timeout.connect(func():
				if is_instance_valid(self):
					queue_free()
			)


# --- ORDER HANDLING ---
func give_order(order: OrderType.Type, target: Variant = null):
	# Player-controlled units CAN disengage from melee (with delay/straggling)
	# AI units stay locked in combat until it resolves
	if state == State.ENGAGING and order in [OrderType.Type.MOVE, OrderType.Type.ATTACK_MOVE, OrderType.Type.CHARGE]:
		if is_player_controlled:
			# Player unit: allow disengagement - they will take some hits while withdrawing
			CombatManager.disengage_regiment(self)
			# Continue to process the order below
		else:
			# AI unit: stay locked in combat
			return

	current_order = order
	BattleSignals.order_given.emit(self, order, target)
	match order:
		OrderType.Type.MOVE, OrderType.Type.ATTACK_MOVE:
			if target is Vector3:
				leader.move_to(target)
				leader.set_move_mode(RegimentLeader.MoveMode.RUN)  # Run to respond to orders
				set_state(State.MARCHING)
		OrderType.Type.CHARGE:
			if target is Vector3:
				leader.move_to(target)
				leader.set_move_mode(RegimentLeader.MoveMode.CHARGE)  # Fast charge burst
				set_state(State.MARCHING)
				CombatState.set_charged(self, false, "charge_order")  # Reset charge flag for fresh charge bonus
				# Track charge start position for minimum distance calculation
				charge_start_position = global_position
				charge_distance_traveled = 0.0
				# Use run animation for charge
				if formation:
					formation.play_animation_all("Run")
				if sprite_overlay:
					sprite_overlay.play_animation_all("walk")  # Use walk, no "run" in sprite atlas
		OrderType.Type.HOLD_POSITION:
			leader.stop_movement()
			leader.set_move_mode(RegimentLeader.MoveMode.WALK)  # Reset to walk
			set_state(State.IDLE)
			# Defensive stance with block animation
			if formation:
				formation.play_animation_all("Block")
			if sprite_overlay:
				sprite_overlay.play_animation_all("idle")


# --- DAMAGE ---
func take_casualties(amount: int):
	current_soldiers = max(0, current_soldiers - amount)

	# Update visuals
	if formation:
		formation.kill_soldiers(amount)
	if sprite_overlay:
		sprite_overlay.kill_soldiers(amount)
	if not formation and not sprite_overlay:
		# Fallback to sprite alpha fade
		var health_ratio = float(current_soldiers) / float(data.max_soldiers)
		sprite.modulate.a = clamp(health_ratio + 0.3, 0.3, 1.0)

	if current_soldiers <= 0:
		set_state(State.DEAD)


func take_morale_damage(amount: float):
	MoraleSystem.apply_morale_damage(self, amount)


func play_hit_reaction():
	"""Play hit reaction on random soldiers in the formation"""
	if formation and formation.soldiers.size() > 0:
		# Play hit react on a few random soldiers
		var soldier_count: int = formation.soldiers.size()
		var react_count: int = mini(5, mini(formation.alive_count, soldier_count))
		if react_count <= 0:
			return
		var indices = range(soldier_count)
		indices.shuffle()
		for i in react_count:
			if i >= indices.size():
				break
			var idx = indices[i]
			if idx < soldier_count:
				var soldier = formation.soldiers[idx]
				if is_instance_valid(soldier) and soldier.visible:
					soldier.play_animation("HitReact")


# --- PRIVATE PROCESS FUNCTIONS ---
func _process_march(delta):
	# Don't process march movement when engaged in combat - prevents rubberbanding
	if state == State.ENGAGING:
		return

	# Follow the leader position with clamped lerp coefficient
	var old_pos: Vector3 = global_position
	var lerp_speed := clampf(delta * 5.0, 0.0, 0.9)  # Clamp to prevent overshoot
	global_position = global_position.lerp(leader.global_position, lerp_speed)

	# Track charge distance if charging
	if current_order == OrderType.Type.CHARGE:
		charge_distance_traveled = global_position.distance_to(charge_start_position)

	# NOTE: formation, sprite_overlay, and melee_area are children of Regiment node
	# and inherit transforms automatically — no manual position writes needed.

	# Update soldier facing direction based on leader's facing
	var move_dir = leader.target_position - global_position
	move_dir.y = 0
	if move_dir.length_squared() > 0.1:
		# Track facing direction for flanking calculations
		_facing_direction = move_dir.normalized()

		# Sync heading so combat transition is smooth
		_current_heading = atan2(move_dir.x, move_dir.z)
		_target_heading = _current_heading

		if formation and formation.has_method("set_facing_direction"):
			formation.set_facing_direction(move_dir)
		if sprite_overlay:
			sprite_overlay.set_facing_direction(move_dir)

	if leader and leader.nav_agent and leader.nav_agent.is_navigation_finished():
		global_position = leader.global_position
		clear_movement_group()  # Clear group sync when arrived
		set_state(State.IDLE)


func _process_engage(delta: float) -> void:
	## Soft-separation: glide units to ideal spacing over multiple frames.
	## Only one of the pair applies correction (lower instance ID) to avoid oscillation.
	## Uses dead zone to prevent constant micro-corrections (Shadow of the Horned Rat style).
	var enemy := _find_current_combat_target()
	if not enemy or not is_instance_valid(enemy):
		return

	var to_enemy: Vector3 = enemy.global_position - global_position
	to_enemy.y = 0.0
	var dist: float = to_enemy.length()
	if dist < 0.001:
		return  # Stacked — let next frame resolve via facing logic

	var dir: Vector3 = to_enemy / dist
	var error: float = dist - ENGAGEMENT_DISTANCE  # +ve = too far, -ve = too close

	# DEAD ZONE: If within ±ENGAGEMENT_DEAD_ZONE of ideal distance, don't correct.
	# This prevents constant oscillation and gives stable "locked in combat" feel.
	if absf(error) <= ENGAGEMENT_DEAD_ZONE:
		return  # Close enough - no correction needed

	# Only one of the pair applies correction (lower id), and only half of the error,
	# so units settle without oscillating against each other.
	if get_instance_id() < enemy.get_instance_id():
		# Reduce error by dead zone amount so we stop AT the dead zone edge, not overshoot
		var effective_error: float = signf(error) * (absf(error) - ENGAGEMENT_DEAD_ZONE)
		var correction: float = signf(effective_error) * minf(absf(effective_error) * 0.5, ENGAGEMENT_DECEL_RATE * delta)
		var new_pos: Vector3 = global_position + dir * correction
		# Snap to terrain height if leader has terrain reference
		if leader and leader.has_method("get_terrain_height"):
			new_pos.y = leader.get_terrain_height(new_pos)
		global_position = new_pos
		# NOTE: Do NOT sync leader position here - leader should stay static during combat.
		# Moving the leader causes position fighting with nav agent and rubber-banding.


func _process_route(_delta):
	# Flee away from nearest enemy
	var nearest_enemy = _find_nearest_enemy()
	if nearest_enemy:
		var flee_dir = (global_position - nearest_enemy.global_position).normalized()
		leader.move_to(global_position + flee_dir * 5.0)
		# Position sync happens in _process_march via leader.global_position


func _process_rally(_delta):
	if current_morale >= 40.0:
		set_state(State.IDLE)


func _find_current_combat_target() -> Regiment:
	## Find the regiment we're currently fighting in melee.
	if not CombatManager:
		return null
	for melee in CombatManager.active_melees:
		if melee.attacker == self:
			# Check if defender is still valid (not freed)
			if is_instance_valid(melee.defender):
				return melee.defender
		if melee.defender == self:
			# Check if attacker is still valid (not freed)
			if is_instance_valid(melee.attacker):
				return melee.attacker
	# Fallback to nearest enemy if not found in active melees
	return _find_nearest_enemy()


func _on_melee_area_contact(area: Area3D) -> void:
	## Simple stop-and-engage handler. NO teleport — soft separation happens in _process_engage.
	if not is_instance_valid(area):
		return

	var other: Regiment = area.get_parent() as Regiment
	if not is_instance_valid(other) or other == self:
		return
	if other.state == State.DEAD or state == State.DEAD:
		return
	if other.is_player_controlled == is_player_controlled:
		return  # Same faction — no engagement

	# Already engaged with this exact unit? Bail — don't re-trigger.
	if state == State.ENGAGING and _find_current_combat_target() == other:
		return

	# Lower instance ID owns engagement-start to avoid double-processing.
	if get_instance_id() > other.get_instance_id():
		return

	# Stop both units where they actually are. No teleport.
	leader.stop_movement()
	other.leader.stop_movement()

	# Start combat — charge impact logic runs inside begin_melee
	CombatManager.begin_melee(self, other)
	set_state(State.ENGAGING)
	other.set_state(State.ENGAGING)


func _find_nearest_enemy() -> Regiment:
	## Find the nearest enemy regiment using spatial hash for O(1) queries.
	# Safety check - AIAutoload and spatial_hash must exist
	if not AIAutoload or not AIAutoload.spatial_hash:
		return _find_nearest_enemy_fallback()

	var my_faction: int = 0 if is_player_controlled else 1

	# Use spatial hash for efficient query (search within reasonable radius)
	var search_radius: float = 200.0  # Large enough to find enemies on battlefield
	var nearest: Node = AIAutoload.spatial_hash.query_nearest_enemy(
		global_position,
		search_radius,
		my_faction
	)

	# Ensure it's a valid, living regiment
	if nearest is Regiment and nearest.state != State.DEAD:
		return nearest

	# Fallback to wider search if nothing found
	# (This handles edge cases where enemy is beyond initial radius)
	if nearest == null:
		nearest = AIAutoload.spatial_hash.query_nearest_enemy(
			global_position,
			1000.0,  # Very large fallback radius
			my_faction
		)
		if nearest is Regiment and nearest.state != State.DEAD:
			return nearest

	return null


func _find_nearest_enemy_fallback() -> Regiment:
	## Fallback linear search when spatial hash unavailable.
	var my_group: String = "enemy_regiments" if is_player_controlled else "player_regiments"
	var enemies := get_tree().get_nodes_in_group(my_group)
	var nearest: Regiment = null
	var nearest_dist: float = INF

	for enemy in enemies:
		if not is_instance_valid(enemy) or not (enemy is Regiment):
			continue
		if enemy.state == State.DEAD:
			continue
		var dist: float = global_position.distance_squared_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy

	return nearest


# --- MORALE SIGNAL HANDLERS ---
func _on_unit_morale_routed():
	## Called when per-soldier morale causes unit to rout.
	set_state(State.ROUTING)


func _on_unit_morale_rallied():
	## Called when per-soldier morale allows unit to rally.
	set_state(State.RALLYING)


func _on_average_morale_changed(new_average: float):
	## Sync regiment-level morale with per-soldier average.
	current_morale = new_average
	BattleSignals.unit_morale_changed.emit(self, new_average)


# --- STANCE MANAGEMENT ---
func set_stance(stance: StanceType.Type, target: Regiment = null):
	var old_stance: StanceType.Type = current_stance
	current_stance = stance
	guard_target = target if stance == StanceType.Type.GUARD else null

	# SYNC TO AI CONTROLLER - sync regiment stance to CommanderAI stance
	if ai_controller:
		var ai_stance_value: int = _map_stance_to_ai_stance(stance)
		ai_controller.set_stance(ai_stance_value as CommanderAI.Stance)

	# Apply stance behavior
	match stance:
		StanceType.Type.HOLD_GROUND:
			give_order(OrderType.Type.HOLD_POSITION)
		StanceType.Type.GUARD:
			if target:
				give_order(OrderType.Type.GUARD, target)

	BattleSignals.stance_changed.emit(self, old_stance, stance)


func _map_stance_to_ai_stance(stance: StanceType.Type) -> int:
	## Map Regiment stance to CommanderAI stance enum.
	## Returns int to avoid circular reference with CommanderAI class.
	match stance:
		StanceType.Type.AGGRESSIVE:
			return 2  # CommanderAI.Stance.AGGRESSIVE
		StanceType.Type.DEFENSIVE:
			return 1  # CommanderAI.Stance.DEFENSIVE
		StanceType.Type.HOLD_GROUND:
			return 0  # CommanderAI.Stance.PASSIVE
		StanceType.Type.SKIRMISH:
			return 4  # CommanderAI.Stance.SKIRMISH
		StanceType.Type.GUARD:
			return 1  # CommanderAI.Stance.DEFENSIVE (guard handled separately)
		_:
			return 2  # Default AGGRESSIVE


func get_stance_name() -> String:
	return StanceType.get_stance_name(current_stance)


# --- FORMATION MANAGEMENT ---
func set_formation(formation_type: FormationType.Type):
	if not FormationType.can_unit_use(formation_type, data.unit_type):
		return  # Can't use this formation

	if formation_type == current_formation:
		return  # Already in this formation

	var old_formation: FormationType.Type = current_formation

	# Start formation transition
	is_reforming = true
	reform_target = formation_type
	reform_timer = FormationType.get_transition_time(formation_type, data.unit_type)

	# Immediately update the target formation for visuals
	current_formation = formation_type

	# Signal the change (visual update happens now, but combat penalties apply during transition)
	BattleSignals.formation_type_changed.emit(self, old_formation, formation_type)
	BattleSignals.formation_reform_started.emit(self, reform_timer)

	# Direct calls to visuals with reform_timer duration so animations match gameplay penalty window
	if formation and formation.has_method("transition_to_formation"):
		formation.transition_to_formation(formation_type, reform_timer)
	if sprite_overlay and sprite_overlay.has_method("set_formation_type"):
		sprite_overlay.set_formation_type(formation_type, true, reform_timer)


func get_formation_name() -> String:
	return FormationType.get_formation_name(current_formation)


func get_speed_modifier() -> float:
	var base: float = FormationType.get_speed_modifier(current_formation)
	if stamina:
		base *= stamina.get_speed_modifier()

	# Group speed sync (spring1944-inspired)
	# When moving with slower units, constrain to group minimum
	if _group_min_speed > 0 and movement_group.size() > 0:
		var my_base_speed: float = data.run_speed if data else 0.9  # Use run speed for group movement
		var my_absolute_speed: float = my_base_speed * base
		if my_absolute_speed > _group_min_speed:
			# Scale down our modifier to match the slowest unit
			base = _group_min_speed / my_base_speed

	return base


func set_movement_group(group: Array[Regiment]) -> void:
	## Set the movement group for synchronized speed.
	## Pass empty array to clear the group.
	movement_group = group
	_group_speed_dirty = true  # Force recalc on next update
	_recalculate_group_min_speed()


func _recalculate_group_min_speed() -> void:
	## Recalculate the minimum speed of the movement group.
	if movement_group.is_empty():
		_group_min_speed = -1.0
		return

	_group_min_speed = INF
	for regiment in movement_group:
		if not is_instance_valid(regiment):
			continue
		# Calculate absolute speed (base speed × modifiers)
		# Use run_speed since group movement responds to orders
		var regiment_speed: float = regiment.data.run_speed if regiment.data else 0.9
		var modifier: float = FormationType.get_speed_modifier(regiment.current_formation)
		if regiment.stamina:
			modifier *= regiment.stamina.get_speed_modifier()
		var absolute_speed: float = regiment_speed * modifier
		_group_min_speed = minf(_group_min_speed, absolute_speed)

	if _group_min_speed == INF:
		_group_min_speed = -1.0


func clear_movement_group() -> void:
	## Clear movement group when movement completes.
	movement_group = []
	_group_min_speed = -1.0


func get_attack_modifier() -> float:
	var base: float = FormationType.get_attack_modifier(current_formation)
	# Penalty while reforming - vulnerable during transition
	if is_reforming:
		base *= FormationType.get_transition_combat_penalty()
	if stamina:
		base *= stamina.get_combat_modifier()
	if veterancy:
		base += veterancy.get_melee_bonus()
	if inspire_active:
		base += 0.1  # +10% when inspired
	# Personality modifier (Impetuous/Fanatic = +10% attack)
	if data:
		base *= data.get_attack_modifier()
	return base


func get_defense_modifier() -> float:
	var base: float = FormationType.get_defense_modifier(current_formation)
	# Penalty while reforming - vulnerable during transition
	if is_reforming:
		base *= FormationType.get_transition_defense_penalty()
	# Stamina defense penalty (TotalWarSimulator)
	if stamina:
		base *= stamina.get_defense_modifier()
	if is_braced:
		base += 0.5  # +50% defense when braced
	# Personality modifier (Impetuous = -10%, Fanatic = -20%)
	if data:
		base *= data.get_defense_modifier()
	return base


func get_anti_cavalry_modifier() -> float:
	var base: float = FormationType.get_anti_cavalry_modifier(current_formation)
	if is_braced:
		base *= 2.0  # Double when braced
	return base


func get_ranged_modifier() -> float:
	## Get ranged accuracy modifier (formation + veterancy + stamina).
	var base: float = FormationType.get_ranged_modifier(current_formation)
	# Veterancy ranged bonus
	if veterancy:
		base += veterancy.get_ranged_bonus()
	# Stamina affects accuracy
	if stamina:
		base *= stamina.get_combat_modifier()
	return base


func get_charge_modifier() -> float:
	## Get charge damage modifier (formation + stamina).
	var base: float = FormationType.get_charge_modifier(current_formation)
	# Stamina affects charge power
	if stamina:
		base *= stamina.get_combat_modifier()
	return base


func set_formation_dimensions(file_count: int, animate: bool = true) -> void:
	## Reshape the regiment's internal layout to a target width (in soldier files).
	## Called by formation drag to make units wider/narrower based on drag width.
	if formation and formation.has_method("set_formation_width"):
		formation.set_formation_width(file_count, animate)
	if sprite_overlay and sprite_overlay.has_method("set_formation_width"):
		sprite_overlay.set_formation_width(file_count, animate)


func get_facing_direction() -> Vector3:
	## Returns the direction the regiment is facing (for flanking calculations).
	## Normalized vector pointing "forward" from the regiment's perspective.
	return _facing_direction.normalized() if _facing_direction.length_squared() > 0.001 else -global_transform.basis.z


func reset_charge_state():
	## Reset charge flag when combat ends or unit disengages.
	CombatState.set_charged(self, false, "reset_charge_state")
	charge_distance_traveled = 0.0
	charge_start_position = Vector3.ZERO


func has_valid_charge() -> bool:
	## Returns true if unit charged far enough to apply charge bonus.
	return current_order == OrderType.Type.CHARGE and charge_distance_traveled >= MIN_CHARGE_DISTANCE


func get_charge_impact_damage() -> int:
	## Calculate impact damage based on mass × velocity (speed).
	## Used for cavalry charges - represents the crushing force of impact.
	if not has_valid_charge():
		return 0
	# Impact damage = mass × charge_speed × charge_bonus_modifier
	# Base formula inspired by TotalWarSimulator: 70% of impact is armor-piercing
	var impact: float = data.mass * data.charge_speed * 2.0  # Multiplier for meaningful damage
	return int(impact)


# --- ABILITY SHORTCUTS ---
func use_ability(ability: AbilityType.Type, target: Variant = null) -> bool:
	if abilities:
		return abilities.activate(ability, target)
	return false


func toggle_ability(ability: AbilityType.Type) -> bool:
	if abilities:
		return abilities.toggle(ability)
	return false


# --- SPELL SHORTCUTS ---
func cast_spell(spell: SpellData, target_pos: Vector3 = Vector3.ZERO) -> bool:
	## Cast a spell at the target position.
	if abilities:
		return abilities.cast_spell(spell, target_pos)
	return false


func cast_spell_by_id(spell_id: String, target_pos: Vector3 = Vector3.ZERO) -> bool:
	## Cast a spell by its ID.
	if abilities:
		return abilities.cast_spell_by_id(spell_id, target_pos)
	return false


func add_spell(spell: SpellData) -> void:
	## Add a spell to this regiment's available spells.
	if abilities:
		abilities.add_spell(spell)


func get_available_spells() -> Array[SpellData]:
	## Get all available spells for this regiment.
	if abilities:
		return abilities.get_available_spells()
	return []


func can_cast_spell(spell: SpellData, target_pos: Vector3 = Vector3.ZERO) -> bool:
	## Check if this regiment can cast a spell.
	if abilities:
		return abilities.can_cast_spell(spell, target_pos)
	return false


# --- SIGNAL HANDLERS ---
func _on_stamina_exhausted():
	# Force slow movement
	if state == State.MARCHING and current_order == OrderType.Type.CHARGE:
		current_order = OrderType.Type.MOVE
		if formation:
			formation.play_animation_all("Walk")
	_group_speed_dirty = true  # Mark for group speed recalc
	BattleSignals.unit_exhausted.emit(self)


func _on_stamina_recovered():
	_group_speed_dirty = true  # Mark for group speed recalc
	BattleSignals.unit_recovered.emit(self)


func _on_level_up(old_level: VeterancySystem.Level, new_level: VeterancySystem.Level):
	# Apply morale bonus from veterancy
	if unit_morale and veterancy:
		var bonus: float = veterancy.get_morale_bonus()
		# This is applied as a continuous modifier to base morale
	BattleSignals.unit_leveled_up.emit(self, old_level, new_level)


func _on_ability_activated(ability: AbilityType.Type):
	BattleSignals.ability_used.emit(self, ability)


func _on_ability_ended(ability: AbilityType.Type):
	pass


# --- TERRITORY & UNIT TYPE MORALE (DEI-inspired) ---

func _apply_territory_morale_modifiers() -> void:
	## Apply territory-based morale modifiers.
	## Friendly territory = +10% morale recovery, Enemy territory = -10% morale.
	if not unit_morale:
		return

	# Clear both first, then apply the active one
	if is_in_friendly_territory:
		unit_morale.set_continuous_modifier_all(
			MoraleEvent.Source.FRIENDLY_TERRITORY,
			MoraleConstants.CONTINUOUS_FRIENDLY_TERRITORY
		)
		unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.ENEMY_TERRITORY)
	elif is_in_enemy_territory:
		unit_morale.set_continuous_modifier_all(
			MoraleEvent.Source.ENEMY_TERRITORY,
			MoraleConstants.CONTINUOUS_ENEMY_TERRITORY
		)
		unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.FRIENDLY_TERRITORY)
	else:
		# Neutral territory - clear both
		unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.FRIENDLY_TERRITORY)
		unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.ENEMY_TERRITORY)


func _apply_unit_type_morale_modifiers() -> void:
	## Apply unit type-based morale modifiers based on combat situation.
	## - Heavy infantry: +5% morale resistance (disciplined)
	## - Ranged units: -15% morale when in melee (out of element)
	## - Cavalry: +10% morale bonus (mobile, confident)
	## - Artillery: -20% morale when in melee (vulnerable)
	if not unit_morale or not data:
		return

	var in_melee: bool = state == State.ENGAGING

	match data.unit_type:
		UnitType.Type.INFANTRY:
			# Heavy infantry (mass >= 1.0, defense >= 12) gets bonus
			if data.mass >= 1.0 and data.defense >= 12:
				unit_morale.set_continuous_modifier_all(
					MoraleEvent.Source.UNIT_TYPE_BONUS,
					MoraleConstants.UNIT_TYPE_HEAVY_INFANTRY_SAVE
				)
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_PENALTY)
			else:
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_BONUS)
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_PENALTY)

		UnitType.Type.RANGED:
			# Ranged units suffer morale penalty when stuck in melee
			if in_melee:
				unit_morale.set_continuous_modifier_all(
					MoraleEvent.Source.UNIT_TYPE_PENALTY,
					MoraleConstants.UNIT_TYPE_RANGED_MELEE_PENALTY
				)
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_BONUS)
			else:
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_PENALTY)
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_BONUS)

		UnitType.Type.CAVALRY:
			# Cavalry gets morale bonus (mobile, can escape)
			unit_morale.set_continuous_modifier_all(
				MoraleEvent.Source.UNIT_TYPE_BONUS,
				MoraleConstants.UNIT_TYPE_CAVALRY_MORALE_BONUS
			)
			unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_PENALTY)

		UnitType.Type.ARTILLERY:
			# Artillery is vulnerable in melee
			if in_melee:
				unit_morale.set_continuous_modifier_all(
					MoraleEvent.Source.UNIT_TYPE_PENALTY,
					MoraleConstants.UNIT_TYPE_ARTILLERY_VULNERABLE
				)
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_BONUS)
			else:
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_PENALTY)
				unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_BONUS)

		_:
			# General/other - no special modifiers
			unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_BONUS)
			unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_PENALTY)


func set_territory(friendly: bool, enemy: bool) -> void:
	## Set the territory status for this regiment.
	## Called by campaign layer when regiment enters different territories.
	is_in_friendly_territory = friendly
	is_in_enemy_territory = enemy


# --- POSITION SYNC ---
func sync_all_positions(pos: Vector3) -> void:
	## Sync regiment, leader, and all children to a new position.
	## Use this when setting regiment position externally (e.g., spawning in Unit Zoo).
	global_position = pos
	if leader:
		leader.global_position = pos
		leader.target_position = pos  # Clear any pending movement
		if leader.nav_agent:
			leader.nav_agent.target_position = pos
	if formation:
		formation.global_position = pos
	if sprite_overlay:
		sprite_overlay.global_position = pos
	if melee_area:
		melee_area.global_position = pos


# --- CLEANUP ---
func _exit_tree():
	# Clear movement group references (prevent stale refs in other regiments)
	for regiment in movement_group:
		if is_instance_valid(regiment) and regiment != self:
			regiment.movement_group.erase(self)
	movement_group.clear()
	_group_min_speed = -1.0

	if ai_controller:
		ai_controller.destroy()
	if AIAutoload:
		AIAutoload.unregister_entity(self)
