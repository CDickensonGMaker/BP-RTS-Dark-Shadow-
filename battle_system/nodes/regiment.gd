class_name Regiment
extends Node3D


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

# Facing direction for flanking calculations
var _facing_direction: Vector3 = Vector3.FORWARD

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
	current_morale = data.base_morale
	current_soldiers = data.max_soldiers
	current_ammo = data.max_ammo

	# Set leader speed from regiment data (fixes speed not being applied)
	if leader and data:
		leader.move_speed = data.speed

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

	# Initialize AI controller for enemy units (after terrain snap)
	if not is_player_controlled:
		_setup_ai_controller()


func _snap_to_terrain():
	## Snap regiment and all its parts to terrain height.
	# Wait a bit for terrain to generate
	await get_tree().create_timer(0.6).timeout

	# Find terrain
	var terrain = _find_terrain()
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


func _find_terrain() -> Node:
	## Find terrain node in the scene.
	var terrains = get_tree().get_nodes_in_group("terrain")
	if terrains.size() > 0:
		return terrains[0]
	# Fallback: search parent nodes
	var parent = get_parent()
	while parent:
		for child in parent.get_children():
			if child.has_method("get_height_at"):
				return child
		parent = parent.get_parent()
	return null


func _setup_unit_morale():
	## Initialize the per-soldier morale system.
	unit_morale = UnitMorale.new(self)

	# Register soldiers if formation exists
	if formation:
		# Wait for formation to be ready
		await formation.formation_ready
		unit_morale.register_soldiers(formation.soldiers, data.base_morale)

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

	# Update abilities (cooldowns)
	if abilities:
		abilities.update(delta)

	# Smooth rotation toward enemy during combat (spring1944-style)
	_update_combat_facing(delta)


func _physics_process(delta):
	# Update position in spatial hash for efficient proximity queries
	if AIAutoload and AIAutoload.spatial_hash:
		AIAutoload.spatial_hash.update_position(self, global_position)

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
				set_state(State.MARCHING)
		OrderType.Type.CHARGE:
			if target is Vector3:
				leader.move_to(target)
				set_state(State.MARCHING)
				has_charged = false  # Reset charge flag for fresh charge bonus
				# Track charge start position for minimum distance calculation
				charge_start_position = global_position
				charge_distance_traveled = 0.0
				# Use run animation for charge
				if formation:
					formation.play_animation_all("Run")
				if sprite_overlay:
					sprite_overlay.play_animation_all("walk")  # Use walk, no "run" in sprite atlas
		OrderType.Type.HOLD_POSITION:
			nav_agent.set_velocity(Vector3.ZERO)
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
	if formation:
		# Play hit react on a few random soldiers
		var react_count = mini(5, formation.alive_count)
		var indices = range(formation.soldiers.size())
		indices.shuffle()
		for i in react_count:
			var idx = indices[i]
			if idx < formation.soldiers.size():
				var soldier = formation.soldiers[idx]
				if is_instance_valid(soldier) and soldier.visible:
					soldier.play_animation("HitReact")


# --- PRIVATE PROCESS FUNCTIONS ---
func _process_march(delta):
	# Follow the leader position
	var old_pos: Vector3 = global_position
	global_position = global_position.lerp(leader.global_position, delta * 5.0)

	# Track charge distance if charging
	if current_order == OrderType.Type.CHARGE:
		charge_distance_traveled = global_position.distance_to(charge_start_position)

	# Update formation and melee area to follow regiment position
	if formation:
		formation.global_position = global_position
	if sprite_overlay:
		sprite_overlay.global_position = global_position
	if melee_area:
		melee_area.global_position = global_position

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

	if leader.nav_agent.is_navigation_finished():
		global_position = leader.global_position
		set_state(State.IDLE)


func _process_engage(_delta):
	# Combat facing is now handled by _update_combat_facing() in _process()
	# This function can be used for other engage-specific state updates
	pass


func _process_route(_delta):
	# Flee away from nearest enemy
	var nearest_enemy = _find_nearest_enemy()
	if nearest_enemy:
		var flee_dir = (global_position - nearest_enemy.global_position).normalized()
		leader.move_to(global_position + flee_dir * 5.0)
		global_position = leader.global_position


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


func _on_melee_area_contact(area: Area3D):
	# Get the regiment that owns this melee area
	var other_regiment: Regiment = area.get_parent() as Regiment
	if other_regiment and other_regiment != self and other_regiment.is_player_controlled != is_player_controlled:
		# Stop movement immediately on contact - no rubberbanding
		leader.stop_movement()
		other_regiment.leader.stop_movement()

		# Start combat
		CombatManager.begin_melee(self, other_regiment)
		set_state(State.ENGAGING)
		other_regiment.set_state(State.ENGAGING)


func _find_nearest_enemy() -> Regiment:
	## Find the nearest enemy regiment using spatial hash for O(1) queries.
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

	# Apply stance behavior
	match stance:
		StanceType.Type.HOLD_GROUND:
			give_order(OrderType.Type.HOLD_POSITION)
		StanceType.Type.GUARD:
			if target:
				give_order(OrderType.Type.GUARD, target)

	BattleSignals.stance_changed.emit(self, old_stance, stance)


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


func get_formation_name() -> String:
	return FormationType.get_formation_name(current_formation)


func get_speed_modifier() -> float:
	var base: float = FormationType.get_speed_modifier(current_formation)
	if stamina:
		base *= stamina.get_speed_modifier()
	return base


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


func get_facing_direction() -> Vector3:
	## Returns the direction the regiment is facing (for flanking calculations).
	## Normalized vector pointing "forward" from the regiment's perspective.
	return _facing_direction.normalized() if _facing_direction.length_squared() > 0.001 else -global_transform.basis.z


func reset_charge_state():
	## Reset charge flag when combat ends or unit disengages.
	has_charged = false
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
	# Impact damage = mass × speed × charge_bonus_modifier
	# Base formula inspired by TotalWarSimulator: 70% of impact is armor-piercing
	var impact: float = data.mass * data.speed * 2.0  # Multiplier for meaningful damage
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
	BattleSignals.unit_exhausted.emit(self)


func _on_stamina_recovered():
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


# --- CLEANUP ---
func _exit_tree():
	if ai_controller:
		ai_controller.destroy()
	if AIAutoload:
		AIAutoload.unregister_entity(self)
