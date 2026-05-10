class_name Regiment
extends Node3D

# Preload to avoid parse-order issues with class_name
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")
const WorldCompassScript = preload("res://battle_system/data/world_compass.gd")
const ArtilleryFormationScript = preload("res://battle_system/units/artillery_formation.gd")
# TODO: Investigate parsing issue
#const RegimentFiringScript = preload("res://battle_system/ai/commander/regiment_firing.gd")
var RegimentFiringScript = null

@export var data: RegimentData
@export var use_3d_soldiers: bool = true  ## Use 3D animated soldiers (placeholder blocks)
@export var use_sprite_soldiers: bool = false  ## Add batched 2D billboard sprites ON TOP of 3D soldiers
@export var soldier_scene: PackedScene    ## The soldier scene to instance
@export var sprite_atlas: SpriteUnitAtlas  ## Atlas for sprite soldiers

# Runtime state (do not set these in the inspector)
var current_morale: float
var current_soldiers: int
var current_ammo: int
var current_round_type: int = 0  # Current ammo type (WeaponClassData.RoundType)
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

# Stamina, Veterancy, Abilities, Firing
var stamina: StaminaSystem = null
var veterancy: VeterancySystem = null
var abilities: AbilityManager = null
var firing: RefCounted = null  # RegimentFiring - tracks per-soldier reload timers

# Combat state flags
var is_braced: bool = false      # Braced against charge
var hold_fire: bool = false      # Don't auto-fire
var inspire_active: bool = false # Inspired by general
var has_charged: bool = false    # Has applied charge bonus this engagement
var is_position_locked: bool = false  # Unit can't move toward targets (debug/testing)

# Order queue (QOL Phase 4) - shift+click to queue orders
var order_queue: Array[Dictionary] = []  # Each entry: { "order": OrderType.Type, "target": Variant }
const MAX_QUEUE_SIZE: int = 8

# General-specific combat stats
# Generals are single units that fight with strength of soldiers
# They accumulate damage instead of dying from single hits
# HP scales with veterancy level: 12 base -> 20 at Elite
const GENERAL_BASE_HP: int = 15  # Base damage pool at Level 0 (Fresh)
const GENERAL_MAX_HP: int = 20   # Maximum HP cap at Elite level
const GENERAL_ARMOR_SAVE_PER_POINT: float = 0.04  # 4% save per armor point (12 armor = 48%)
var _general_damage_accumulated: int = 0  # Tracks damage taken by general

# Single-model monster HP pools (Giant, Dragon, Treeman)
# These monsters show as 1 sprite but have massive HP pools
const MONSTER_HP_PER_DEFENSE: float = 1.0  # HP scales with defense stat
const MONSTER_BASE_HP: int = 20            # Base HP for monsters
const MONSTER_ARMOR_SAVE_PER_POINT: float = 0.035  # 3.5% save per armor
var _monster_damage_accumulated: int = 0   # Tracks damage taken by single-model monster

# Charge tracking
var charge_start_position: Vector3 = Vector3.ZERO  # Position when charge started
var charge_distance_traveled: float = 0.0           # Distance traveled during charge
const MIN_CHARGE_DISTANCE: float = 10.0             # Minimum distance to apply charge bonus

# Engagement constants (Phase 1 fix + rank-to-rank stopping)
const ENGAGEMENT_MIN_GAP: float = 0.8               # Minimum gap between front ranks (prevents clipping)
const ENGAGEMENT_DEAD_ZONE: float = 0.5             # ±0.5 units from ideal = no correction (prevents oscillation)
const ENGAGEMENT_DECEL_RATE: float = 8.0            # Units/sec of corrective movement toward ideal spacing
const APPROACH_OFFSET: float = 6.0                  # Attack approach point offset (accounts for formation depth)
const FORMATION_SPACING: float = 1.2                # Default soldier spacing in formation


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


## Calculate front rank offset from formation center.
## This is how far forward the front rank extends from the regiment's center point.
func get_front_rank_offset() -> float:
	var ranks: int = 3  # Default for LINE formation
	var spacing: float = FORMATION_SPACING

	# Get actual rank count from formation type
	if current_formation in FormationType.RANKS:
		ranks = FormationType.RANKS[current_formation]
		if ranks == 0:
			# Special formations (wedge, square, schiltron) - estimate based on soldier count
			ranks = maxi(2, ceili(sqrt(float(current_soldiers)) / 2.0))

	# Get actual spacing from sprite formation if available
	if formation and "spacing" in formation:
		spacing = formation.spacing

	# Front rank is at: -(ranks/2 - 0.5) * spacing from center (negative Z is forward)
	# Simplified: (ranks - 1) / 2.0 * spacing
	return (float(ranks - 1) / 2.0) * spacing


## Calculate ideal engagement distance between this regiment and another.
## Uses front rank offsets so units stop rank-to-rank instead of overlapping.
func get_engagement_distance(other: Node) -> float:
	var my_offset: float = get_front_rank_offset()
	var other_offset: float = FORMATION_SPACING  # Default fallback

	if other.has_method("get_front_rank_offset"):
		other_offset = other.get_front_rank_offset()
	elif other is Regiment:
		# Estimate from formation type
		var other_ranks: int = 3
		if other.current_formation in FormationType.RANKS:
			other_ranks = FormationType.RANKS[other.current_formation]
			if other_ranks == 0:
				other_ranks = maxi(2, ceili(sqrt(float(other.current_soldiers)) / 2.0))
		other_offset = (float(other_ranks - 1) / 2.0) * FORMATION_SPACING

	# Total engagement distance = both front rank offsets + minimum gap
	return my_offset + other_offset + ENGAGEMENT_MIN_GAP


# Facing direction for flanking calculations
# NOTE: Initialized to ZERO - must call set_initial_facing() after spawn to face toward enemy
var _facing_direction: Vector3 = Vector3.ZERO

# Spatial hash optimization - only update when position changes significantly
var _last_hash_position: Vector3 = Vector3.ZERO
const HASH_UPDATE_THRESHOLD: float = 2.0  # Update spatial hash when moved 2+ units

# Smooth rotation system (inspired by spring1944)
var _target_heading: float = 0.0  # Desired heading toward enemy
var _current_heading: float = 0.0  # Current actual heading
var _combat_facing_locked: bool = false  # Hysteresis flag to prevent spinning
const DEFAULT_TURN_SPEED: float = 3.0  # radians per second fallback
const HEADING_THRESHOLD: float = 0.05  # ~3 degrees - prevents micro-adjustments
const COMBAT_FACING_LOCK: float = 0.26  # ~15 degrees - stop rotating once aligned (Bug E fix)
const COMBAT_FACING_UNLOCK: float = 0.44  # ~25 degrees - resume rotating if enemy moves (Bug E fix)

# Internal refs
@onready var sprite: Sprite3D = $Sprite3D
@onready var nav_agent: NavigationAgent3D = $RegimentLeader/NavigationAgent3D
@onready var leader: RegimentLeader = $RegimentLeader
@onready var melee_area: Area3D = $MeleeArea

# Soldier formation (SoldierFormation for 3D soldiers)
var formation: Node3D = null
# Sprite overlay (SpriteFormation rendered on top of 3D soldiers)
var sprite_overlay: SpriteFormation = null
# Artillery formation (3D models for cannons/mortars instead of sprites)
# Type hint removed to avoid parse-order issues with class_name
var artillery_formation: Node3D = null  # ArtilleryFormation
# Floating war banner above the regiment
var war_banner: Node3D = null
# Range indicator (weapon range, aura radius)
var range_indicator: Node3D = null
# Selection ring (QOL Phase 3)
var _selection_ring: Node3D = null

# AI and Morale systems
var ai_controller: CommanderAI = null
var unit_morale: UnitMorale = null
var casualty_tracker: CasualtyTracker = null
var _casualty_sample_acc: float = 0.0

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

	# All regiments start battles at 100 morale (regardless of base_morale)
	# The morale cap determines recovery ceiling and may be lower if carried from campaign
	current_morale = 100.0
	current_soldiers = data.max_soldiers
	current_ammo = data.max_ammo
	current_round_type = data.default_round_type if data else 0

	# BUG C FIX: set initial facing by reading deployment markers from the scene.
	# Hardcoded axis directions are fragile because battle maps put deployments
	# on diagonals — a hardcoded (1,0,0) is up to 45° off from the actual enemy
	# bearing, which is exactly the flank/frontal threshold. Looking up the
	# markers is map-agnostic and correct for any layout.
	if _facing_direction.length_squared() < 0.001:
		set_initial_facing(_compute_initial_facing_from_deployment())

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
	_setup_firing()

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

	# Add floating war banner above regiment
	_setup_war_banner()

	# Add range indicator for ranged units and generals
	_setup_range_indicator()

	# Add hero emblem for GENERAL (hero) units
	if data.unit_type == UnitType.Type.GENERAL:
		_setup_hero_emblem()

	# Set MeleeArea to collision layer 2 for unit selection
	melee_area.collision_layer = 2
	melee_area.collision_mask = 2  # Detect other units
	melee_area.area_entered.connect(_on_melee_area_contact)
	melee_area.monitorable = true
	melee_area.monitoring = true
	# DEBUG: Verify melee area setup
	var shape_node = melee_area.get_node_or_null("CollisionShape3D")
	var shape_valid = shape_node and shape_node.shape != null and not shape_node.disabled
	print("[MELEE SETUP] %s: MeleeArea connected, shape_valid=%s, layer=%d, mask=%d" % [
		data.regiment_name if data else name, shape_valid, melee_area.collision_layer, melee_area.collision_mask])

	# For artillery units, increase MeleeArea radius to cover crew spread
	# Crew is positioned in a 270° arc with radius up to 3.5m around each cannon
	# With 2 cannons spaced 5m apart, total spread is ~12m
	if data.artillery_model and shape_node and shape_node.shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape_node.shape as CapsuleShape3D
		capsule.radius = 10.0  # Cover crew positioned around both cannons
		capsule.height = 20.0
		print("[MELEE SETUP] %s: Artillery MeleeArea enlarged - radius=%.1f, height=%.1f" % [
			data.regiment_name if data else name, capsule.radius, capsule.height])

	# Final melee configuration debug
	print("[MELEE INIT] %s: layer=%d mask=%d monitoring=%s monitorable=%s pos=%s" % [
		data.regiment_name if data else name,
		melee_area.collision_layer, melee_area.collision_mask,
		melee_area.monitoring, melee_area.monitorable,
		melee_area.global_position])

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

	# Generals get faction-specific spells automatically
	if data and data.unit_type == UnitType.Type.GENERAL:
		_assign_general_spells()


func _setup_firing():
	## Initialize per-soldier firing state for ranged units.
	if not data:
		return
	# Only setup firing for units with a weapon class (ranged capability)
	# TODO: RegimentFiringScript temporarily disabled due to parse issue
	if RegimentFiringScript == null:
		RegimentFiringScript = load("res://battle_system/ai/commander/regiment_firing.gd")
	if RegimentFiringScript and data.weapon_class != RegimentData.WeaponClass.NONE:
		firing = RegimentFiringScript.new(self)


func _assign_general_spells():
	## Assign spells to general based on faction color.
	## Empire (blue): Hold the Line, Healing Light
	## Dwarf (gold): Ancestral Might
	## Orc (green): WAAAGH!
	## Undead (purple): Dread Aura
	var spells_to_add: Array[SpellData] = []

	# Determine faction by color
	var faction_color: Color = data.faction_color
	var empire_color := Color(0.2, 0.4, 0.8, 1)
	var dwarf_color := Color(0.6, 0.5, 0.2, 1)
	var orc_color := Color(0.2, 0.5, 0.2, 1)
	var undead_color := Color(0.3, 0.1, 0.4, 1)

	if faction_color.is_equal_approx(empire_color):
		# Empire General
		var hold_line = load("res://battle_system/data/spells/hold_the_line.tres")
		var healing = load("res://battle_system/data/spells/healing_light.tres")
		if hold_line:
			spells_to_add.append(hold_line)
		if healing:
			spells_to_add.append(healing)
	elif faction_color.is_equal_approx(dwarf_color):
		# Dwarf Thane
		var ancestral = load("res://battle_system/data/spells/ancestral_might.tres")
		if ancestral:
			spells_to_add.append(ancestral)
	elif faction_color.is_equal_approx(orc_color):
		# Orc Warboss
		var waaagh = load("res://battle_system/data/spells/waaagh.tres")
		if waaagh:
			spells_to_add.append(waaagh)
	elif faction_color.is_equal_approx(undead_color):
		# Vampire Lord
		var dread = load("res://battle_system/data/spells/dread_aura.tres")
		if dread:
			spells_to_add.append(dread)

	# Add fireball to all generals as universal spell
	var fireball = load("res://battle_system/data/spells/fireball.tres")
	if fireball:
		spells_to_add.append(fireball)

	# Assign spells to ability manager
	if abilities and spells_to_add.size() > 0:
		abilities.setup_spells(spells_to_add)


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

	# Set model front direction from regiment data
	# This remaps which direction the 3D model's "front" actually faces
	if data:
		soldier_formation.model_front_direction = data.sprite_front_direction

	add_child(soldier_formation)
	formation = soldier_formation


func _setup_sprite_overlay():
	## Set up batched sprite overlay using MultiMesh for performance.
	## Sprites render ON TOP of 3D soldiers for visual fidelity.
	## For Artillery with 3D models, use ArtilleryFormation instead.

	# Check if this is an artillery unit with a 3D model assigned
	if data.unit_type == UnitType.Type.ARTILLERY and data.artillery_model:
		_setup_artillery_formation()
		return

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

	# Generals are rendered larger than normal units (but not 2x - 30% smaller than before)
	if data.unit_type == UnitType.Type.GENERAL:
		sprite_formation.sprite_scale = Vector2(3.5, 4.2)  # ~1.4x normal size (30% smaller than 2x)
		sprite_formation.height_offset = 1.75  # Slightly lower to match smaller size
	# Monsters (trolls, giants, etc.) are rendered 2x normal size - big and scary!
	elif data.unit_type == UnitType.Type.MONSTER:
		sprite_formation.sprite_scale = Vector2(5.0, 6.0)  # 2x normal size
		sprite_formation.height_offset = 3.0  # Higher off ground for large units
		sprite_formation.spacing = 2.5  # More spacing between large units
	# Artillery (cannons, mortars) - large war machines with sprites (fallback if no 3D model)
	elif data.unit_type == UnitType.Type.ARTILLERY:
		sprite_formation.sprite_scale = Vector2(6.0, 7.5)  # 2.5x normal - cannons are BIG
		sprite_formation.height_offset = -1.5  # Negative offset to ground the wheels
		sprite_formation.spacing = 4.0  # Wide spacing between guns

	# Set sprite front direction from regiment data
	# This remaps which sprite row is the unit's visual "front"
	if data:
		sprite_formation.sprite_front_direction = data.sprite_front_direction

	add_child(sprite_formation)
	sprite_overlay = sprite_formation

	# Connect cohesion signal to emit battle signal
	if sprite_formation.cohesion_changed.get_connections().is_empty():
		sprite_formation.cohesion_changed.connect(_on_cohesion_changed)


func _on_cohesion_changed(cohesion: float) -> void:
	## Forward cohesion changes to BattleSignals for UI and other systems.
	BattleSignals.formation_cohesion_changed.emit(self, cohesion)


func _setup_artillery_formation():
	## Set up 3D artillery models (cannons, mortars) using ArtilleryFormation.
	## ALSO sets up crew sprites around the cannons for visible melee combat.
	var arty_formation: Node3D = ArtilleryFormationScript.new()

	arty_formation.artillery_model = data.artillery_model
	arty_formation.max_pieces = data.artillery_pieces_count
	arty_formation.model_scale = data.artillery_model_scale
	arty_formation.spacing = 5.0  # Wide spacing between guns
	arty_formation.faction_color = data.faction_color
	arty_formation.enable_collision = false  # Cannon pieces have NO collision - crew handles melee
	arty_formation.height_offset = 0.0

	# Use artillery_model_direction for 3D cannon models (default 0 = cannon faces forward)
	# This is separate from sprite_front_direction which controls 2D crew sprites
	arty_formation.model_front_direction = data.artillery_model_direction

	add_child(arty_formation)
	artillery_formation = arty_formation

	# Spawn the artillery pieces
	arty_formation.spawn_formation(data.artillery_pieces_count)

	# === CREW SPRITES: Enable hybrid rendering ===
	# Artillery shows BOTH 3D cannon models AND crew sprites around them
	# Melee combat happens between crew sprites, not cannon models
	if data.sprite_atlas:
		use_sprite_soldiers = true
		var crew_formation := SpriteFormation.new()
		crew_formation.atlas = data.sprite_atlas
		crew_formation.max_soldiers = data.max_soldiers
		crew_formation.faction_color = data.faction_color

		# Artillery crew are smaller than normal infantry (working around cannons)
		crew_formation.sprite_scale = Vector2(2.0, 2.5)
		crew_formation.height_offset = 1.2
		crew_formation.spacing = 1.0  # Tight spacing, positioned by artillery crew mode

		# Set sprite front direction from regiment data
		crew_formation.sprite_front_direction = data.sprite_front_direction

		add_child(crew_formation)
		sprite_overlay = crew_formation

		# Enable artillery crew positioning mode
		var piece_positions: Array[Vector3] = arty_formation._calculate_piece_positions(data.artillery_pieces_count)
		crew_formation.set_artillery_crew_mode(piece_positions)

		# Set initial facing direction to match regiment (same as other sprite formations)
		crew_formation.set_facing_direction(_facing_direction)

		# Connect cohesion signal
		if crew_formation.cohesion_changed.get_connections().is_empty():
			crew_formation.cohesion_changed.connect(_on_cohesion_changed)


func _update_artillery_visual_state() -> void:
	## Update artillery formation visual state based on firing state.
	## Called from _process to keep 3D artillery models in sync with firing system.
	if not artillery_formation or not firing:
		return

	# Only for artillery units
	if not data or data.unit_type != UnitType.Type.ARTILLERY:
		return

	# Get current firing state from the firing component
	if not firing.has_method("get_firing_state"):
		return

	var RegimentFiringScript = load("res://battle_system/ai/commander/regiment_firing.gd")
	if not RegimentFiringScript:
		return

	var current_firing_state = firing.get_firing_state()

	# Map RegimentFiring.FiringState to ArtilleryFormation.VisualFiringState
	var visual_state: int = ArtilleryFormationScript.VisualFiringState.IDLE
	if current_firing_state == RegimentFiringScript.FiringState.AIMING:
		visual_state = ArtilleryFormationScript.VisualFiringState.AIMING
	elif current_firing_state == RegimentFiringScript.FiringState.RELOADING:
		visual_state = ArtilleryFormationScript.VisualFiringState.RELOADING

	# Update the artillery formation's visual state
	if artillery_formation.has_method("set_visual_firing_state"):
		artillery_formation.set_visual_firing_state(visual_state)


func _setup_war_banner():
	## Set up floating war banner above the regiment.
	var banner_script := load("res://battle_system/units/regiment_banner.gd")
	if banner_script:
		war_banner = Node3D.new()
		war_banner.set_script(banner_script)
		add_child(war_banner)
		war_banner.setup_for_regiment(self)


func _setup_range_indicator():
	## Set up range indicator for ranged units and generals with auras.
	# Only create for units with ranged capability or aura
	if not data:
		return
	if data.weapon_class == RegimentData.WeaponClass.NONE and not (data.unit_type == UnitType.Type.GENERAL):
		return
	var RangeIndicatorScript = load("res://battle_system/ui/range_indicator.gd")
	if RangeIndicatorScript:
		range_indicator = RangeIndicatorScript.create_for_regiment(self)


var hero_emblem: Node3D = null

func _setup_hero_emblem():
	## Set up floating emblem above hero units for battlefield identification.
	var emblem_script: GDScript = load("res://battle_system/ui/hero_emblem.gd")
	if emblem_script:
		# Create instance directly from script (ensures proper initialization)
		hero_emblem = emblem_script.new()
		hero_emblem.name = "HeroEmblem"
		add_child(hero_emblem)
		# Use player/enemy emblem based on control, fallback to faction
		var emblem_key: String = "player" if is_player_controlled else "enemy"
		hero_emblem.set_emblem_texture(emblem_key)


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
	# Also initialize for player ranged/artillery units so they can fire via behavior tree
	if not is_player_controlled:
		_setup_ai_controller()
	elif data and data.ballistic_skill > 0:
		# Player ranged units need AI controller for firing behavior
		_setup_ai_controller()
		print("[REGIMENT] Player ranged unit %s: AI controller initialized for firing" % (data.regiment_name if data else name))


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
	# Sync MeleeArea to regiment position AFTER terrain snap
	# Artillery crew spread requires the full position sync, not just height
	if melee_area:
		melee_area.global_position = global_position
		melee_area.global_position.y = terrain_height


func _setup_unit_morale():
	## Initialize the per-soldier morale system.
	unit_morale = UnitMorale.new(self)

	# Set morale cap from campaign data (if coming from campaign with persistent cap)
	# Otherwise start at 100 (fresh regiment)
	var initial_cap: float = 100.0
	if data and data.has_meta("battle_morale_cap"):
		initial_cap = data.get_meta("battle_morale_cap")
	unit_morale.set_initial_cap(initial_cap)

	# Initialize casualty tracker
	var is_elite: bool = data.is_elite if data else false
	casualty_tracker = CasualtyTracker.new(self, is_elite)
	casualty_tracker.set_starting_soldiers(current_soldiers)
	casualty_tracker.threshold_reached.connect(_on_casualty_threshold_reached)

	# For sprite-based units, use virtual soldiers (no Node3D soldiers exist)
	# All soldiers start at 100 morale (base_morale affects cap/recovery, not starting value)
	if use_sprite_soldiers and current_soldiers > 0:
		unit_morale.register_virtual_soldiers(current_soldiers, 100.0)
	# Register soldiers if formation exists (3D soldier mode)
	elif formation and is_instance_valid(formation):
		# Check if formation is already ready (has soldiers)
		if formation.soldiers.size() > 0:
			unit_morale.register_soldiers(formation.soldiers, 100.0)
		else:
			# Wait for formation to be ready with timeout
			var waited := 0.0
			while formation.soldiers.is_empty() and waited < 2.0:
				await get_tree().create_timer(0.1).timeout
				waited += 0.1
				# Safety check during wait
				if not is_instance_valid(self) or not is_instance_valid(formation):
					break
			# Register if valid and has soldiers
			if is_instance_valid(self) and is_instance_valid(formation) and formation.soldiers.size() > 0:
				unit_morale.register_soldiers(formation.soldiers, 100.0)

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

	# Update disengage cooldown
	if _disengage_cooldown > 0:
		_disengage_cooldown = maxf(_disengage_cooldown - delta, 0.0)

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

	# Update casualty tracker (sample every 1 second)
	if casualty_tracker:
		_casualty_sample_acc += delta
		if _casualty_sample_acc >= CasualtyTracker.SAMPLE_INTERVAL:
			_casualty_sample_acc -= CasualtyTracker.SAMPLE_INTERVAL
			casualty_tracker.sample(Time.get_ticks_msec() / 1000.0)
		casualty_tracker.tick(delta)

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

	# Update artillery visual state based on firing state
	_update_artillery_visual_state()

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

	# Polling-based melee detection fallback (area_entered signal can be unreliable in Godot 4)
	# Only check when not already engaged and not dead/routing
	if state != State.ENGAGING and state != State.DEAD and state != State.ROUTING:
		_poll_melee_overlaps()


func _update_combat_facing(delta: float) -> void:
	## Smoothly rotate sprites toward enemy during combat.
	## FLANKING FIX: _facing_direction is LOCKED to the first engaged enemy
	## for the entire engagement. New attackers do NOT cause facing to track them,
	## so flanking attacks register correctly as flank/rear.
	if state != State.ENGAGING:
		_combat_facing_locked = false  # Reset lock when not engaging
		return

	# Find current combat target
	var enemy := _find_current_combat_target()
	if not enemy or not is_instance_valid(enemy):
		_combat_facing_locked = false
		return

	# Calculate desired heading toward the LOCKED target
	var dir := enemy.global_position - global_position
	dir.y = 0
	if dir.length_squared() < 0.1:
		return  # Too close, don't spin

	# FLANKING FIX (key change): only update _facing_direction on the FIRST
	# tick of engagement. After that, it stays locked even if new enemies appear.
	# This is what makes flanking persist beyond the first tick.
	if not _combat_facing_locked:
		_facing_direction = dir.normalized()

	# Snap heading for sprite display (8-way)
	var target_dir_index := WorldCompassScript.direction_from_vector(dir)
	_target_heading = WorldCompassScript.angle_from_direction(target_dir_index)

	var angle_diff := _wrap_angle(_target_heading - _current_heading)

	# Hysteresis for sprite rotation only (NOT for combat math anymore)
	if _combat_facing_locked:
		if absf(angle_diff) < COMBAT_FACING_UNLOCK:
			return  # Sprite stays where it is
		# else: sprite catches up below, but _facing_direction does NOT change
	else:
		if absf(angle_diff) < COMBAT_FACING_LOCK:
			_combat_facing_locked = true  # Lock both sprite and facing
			return

	if absf(angle_diff) > HEADING_THRESHOLD:
		var turn_speed := data.turn_rate if data else DEFAULT_TURN_SPEED
		var turn_amount: float = signf(angle_diff) * minf(absf(angle_diff), turn_speed * delta)
		_current_heading = _wrap_angle(_current_heading + turn_amount)

		# Sprite-only quantized direction
		var sprite_dir_index := WorldCompassScript.direction_from_angle(_current_heading)
		var sprite_dir := WorldCompassScript.vector_from_direction(sprite_dir_index)

		if range_indicator and range_indicator.has_method("update_facing"):
			range_indicator.update_facing(sprite_dir)
		if sprite_overlay:
			sprite_overlay.set_facing_angle(_current_heading)
		if formation and formation.has_method("set_facing_direction"):
			formation.set_facing_direction(sprite_dir)
		if artillery_formation:
			artillery_formation.set_facing_direction(sprite_dir)


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

	# Update formation tolerance mode based on state
	_update_tolerance_mode_for_state()

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
			# QOL Phase 4: Advance to next queued order if any
			_try_advance_to_next_queued_order()
		State.DEAD:
			BattleSignals.regiment_dead.emit(self)
			# Clean up from combat systems before freeing
			CombatManager.disengage_regiment(self)
			# Delay queue_free to let other systems clean up references
			get_tree().create_timer(0.5).timeout.connect(func():
				if is_instance_valid(self):
					queue_free()
			)


# Disengage cooldown tracking
var _disengage_cooldown: float = 0.0
const DISENGAGE_COOLDOWN_DURATION: float = 3.0


## Attempt to disengage from melee combat.
## Roll: discipline + d10 vs enemy weapon_skill + d10
## Returns true if disengage succeeds.
func attempt_disengage() -> bool:
	if state != State.ENGAGING:
		return true  # Not in combat, auto-success

	# Check cooldown
	if _disengage_cooldown > 0:
		print("[Combat] %s disengage on cooldown (%.1fs remaining)" % [name, _disengage_cooldown])
		BattleSignals.unit_disengage_failed.emit(self)
		return false

	# Find engaged enemy
	var enemy: Regiment = CombatManager.get_engaged_enemy(self)
	if not enemy:
		return true  # No enemy, auto-success

	# Roll: discipline + d10 vs enemy weapon_skill + d10
	var my_discipline: int = data.discipline if data else 10
	var enemy_ws: int = enemy.data.weapon_skill if enemy.data else 10

	var my_roll: int = my_discipline + randi_range(1, 10)
	var enemy_roll: int = enemy_ws + randi_range(1, 10)

	print("[Combat] %s disengage roll: %d (disc %d + d10) vs %d (ws %d + d10)" % [
		name, my_roll, my_discipline, enemy_roll, enemy_ws
	])

	if my_roll >= enemy_roll:
		# Success - disengage
		CombatManager.disengage_regiment(self)
		# Set WITHDRAWING stance via AI controller
		if ai_controller:
			ai_controller.set_stance(CommanderAI.Stance.WITHDRAWING)
		BattleSignals.unit_disengage_success.emit(self)
		print("[Combat] %s disengaged successfully!" % name)
		return true
	else:
		# Fail - cooldown
		_disengage_cooldown = DISENGAGE_COOLDOWN_DURATION
		BattleSignals.unit_disengage_failed.emit(self)
		print("[Combat] %s failed to disengage, cooldown started" % name)
		return false


# --- ORDER HANDLING ---
func give_order(order: OrderType.Type, target: Variant = null, append: bool = false):
	# QOL Phase 4: If append is true, queue the order instead of executing immediately
	if append:
		queue_order(order, target)
		return

	# Clear queue when receiving a fresh order (not queued)
	clear_order_queue()

	# Position-locked units can't receive movement orders (debug/testing feature)
	# They can still route/flee via morale breaks and WITHDRAW orders
	if is_position_locked and order in [OrderType.Type.MOVE, OrderType.Type.ATTACK_MOVE, OrderType.Type.CHARGE]:
		return  # Ignore movement orders when locked

	# Player-controlled units CAN disengage from melee (with roll)
	# AI units stay locked in combat until it resolves
	if state == State.ENGAGING and order in [OrderType.Type.MOVE, OrderType.Type.ATTACK_MOVE, OrderType.Type.CHARGE]:
		if is_player_controlled:
			# Player unit: attempt disengage with roll
			if not attempt_disengage():
				return  # Disengage failed, ignore order
			# Continue to process the order below
		else:
			# AI unit: stay locked in combat
			return

	current_order = order
	BattleSignals.order_given.emit(self, order, target)

	# ARTILLERY SPECIAL CASE: Artillery never moves to engage
	# For ATTACK_MOVE, set target on AI controller and let behavior tree handle firing
	var is_artillery: bool = data and data.unit_type == UnitType.Type.ARTILLERY
	if is_artillery and order == OrderType.Type.ATTACK_MOVE:
		# Don't move - artillery is stationary. AI controller will handle firing.
		leader.stop_movement()
		set_state(State.IDLE)
		# SET THE TARGET on AI controller so behavior tree can fire at it
		if ai_controller and target is Node:
			ai_controller.set_target(target)
			print("[REGIMENT] Artillery %s: ATTACK_MOVE -> stationary fire, target=%s" % [
				data.regiment_name if data else name,
				target.data.regiment_name if target is Node and target.data else str(target)
			])
		else:
			print("[REGIMENT] Artillery %s: ATTACK_MOVE but no valid target" % (data.regiment_name if data else name))
		return

	match order:
		OrderType.Type.MOVE, OrderType.Type.ATTACK_MOVE:
			if target is Vector3:
				leader.move_to(target)
				# Use current move mode (walk or run based on toggle)
				if leader.move_mode == RegimentLeader.MoveMode.WALK:
					leader.set_move_mode(RegimentLeader.MoveMode.WALK)
				else:
					leader.set_move_mode(RegimentLeader.MoveMode.RUN)
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


# --- ORDER QUEUE (QOL Phase 4) ---
func queue_order(order: OrderType.Type, target: Variant) -> void:
	"""Append an order to the queue. Shift+click uses this."""
	if order_queue.size() >= MAX_QUEUE_SIZE:
		order_queue.pop_front()  # Drop oldest if queue full
	order_queue.append({ "order": order, "target": target })


func clear_order_queue() -> void:
	"""Clear all queued orders."""
	order_queue.clear()


func _try_advance_to_next_queued_order() -> bool:
	"""Called when regiment becomes IDLE. Pulls next order from queue if any."""
	if order_queue.is_empty():
		return false
	var next: Dictionary = order_queue.pop_front()
	give_order(next.order, next.target)
	return true


# --- DAMAGE ---
func take_casualties(amount: int):
	# Generals use damage pool with armor saves instead of dying from single hits
	if data and data.unit_type == UnitType.Type.GENERAL:
		var max_hp: int = _get_general_max_hp()
		var armor_save_chance: float = float(data.armor) * GENERAL_ARMOR_SAVE_PER_POINT

		# Roll armor save for each incoming damage point
		var actual_damage: int = 0
		for i in amount:
			if randf() >= armor_save_chance:  # Failed save = take damage
				actual_damage += 1

		_general_damage_accumulated += actual_damage

		# General only dies when accumulated damage exceeds their HP pool
		if _general_damage_accumulated >= max_hp:
			current_soldiers = 0
			if sprite_overlay:
				sprite_overlay.kill_soldiers(1)
			set_state(State.DEAD)
		return

	# Single-model monsters (Giant, Dragon, Treeman) use HP pool like generals
	if data and data.unit_type == UnitType.Type.MONSTER and data.max_soldiers == 1:
		var max_hp: int = _get_monster_max_hp()
		var armor_save_chance: float = float(data.armor) * MONSTER_ARMOR_SAVE_PER_POINT

		# Roll armor save for each incoming damage point
		var actual_damage: int = 0
		for i in amount:
			if randf() >= armor_save_chance:  # Failed save = take damage
				actual_damage += 1

		_monster_damage_accumulated += actual_damage

		# Monster only dies when accumulated damage exceeds their HP pool
		if _monster_damage_accumulated >= max_hp:
			current_soldiers = 0
			if sprite_overlay:
				sprite_overlay.kill_soldiers(1)
			set_state(State.DEAD)
		return

	current_soldiers = max(0, current_soldiers - amount)

	# Resync firing timers when soldiers die (trim stagger arrays)
	if firing and firing.has_method("resync_after_casualty"):
		firing.resync_after_casualty()

	# Update visuals
	if formation:
		formation.kill_soldiers(amount)
	if sprite_overlay:
		sprite_overlay.kill_soldiers(amount)
	# Kill artillery pieces proportionally when taking casualties
	# Artillery has fewer pieces than max_soldiers, so we calculate target piece count
	if artillery_formation and artillery_formation.has_method("kill_random_piece"):
		var max_pieces: int = data.artillery_pieces_count if data else 4
		var soldiers_per_piece: float = float(data.max_soldiers) / float(max_pieces)
		var target_pieces: int = ceili(float(current_soldiers) / soldiers_per_piece)
		target_pieces = clampi(target_pieces, 0, max_pieces)
		# Kill pieces until we reach target count
		while artillery_formation.alive_count > target_pieces:
			artillery_formation.kill_random_piece()
	if not formation and not sprite_overlay and not artillery_formation:
		# Fallback to sprite alpha fade
		var health_ratio = float(current_soldiers) / float(data.max_soldiers)
		sprite.modulate.a = clamp(health_ratio + 0.3, 0.3, 1.0)

	if current_soldiers <= 0:
		set_state(State.DEAD)


## Get the general's maximum HP based on veterancy level.
func _get_general_max_hp() -> int:
	var base_hp: int = GENERAL_BASE_HP
	if veterancy:
		base_hp += veterancy.get_general_hp_bonus()
	return mini(base_hp, GENERAL_MAX_HP)  # Cap at maximum


## Get general's remaining health as a percentage (for UI display).
func get_general_health_percent() -> float:
	if data and data.unit_type == UnitType.Type.GENERAL:
		var max_hp: int = _get_general_max_hp()
		return 1.0 - (float(_general_damage_accumulated) / float(max_hp))
	return float(current_soldiers) / float(data.max_soldiers)


## Get the single-model monster's maximum HP based on defense stat.
func _get_monster_max_hp() -> int:
	var defense: int = data.defense if data else 10
	return MONSTER_BASE_HP + int(float(defense) * MONSTER_HP_PER_DEFENSE)


## Get single-model monster's remaining health as a percentage (for UI display).
func get_monster_health_percent() -> float:
	if data and data.unit_type == UnitType.Type.MONSTER and data.max_soldiers == 1:
		var max_hp: int = _get_monster_max_hp()
		return 1.0 - (float(_monster_damage_accumulated) / float(max_hp))
	return float(current_soldiers) / float(data.max_soldiers)


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

## Apply separation steering to avoid overlapping with nearby units
func _apply_separation_steering(velocity: Vector3) -> Vector3:
	if not AIAutoload or not AIAutoload.spatial_hash:
		return velocity

	var separation := Vector3.ZERO
	var nearby: Array = AIAutoload.spatial_hash.query_regiments_in_radius(
		global_position, 20.0, -1  # All factions, 20 unit radius
	)

	for other in nearby:
		if other == self or not is_instance_valid(other):
			continue
		# Only separate from living units
		if other.state == State.DEAD or other.state == State.ROUTING:
			continue

		var other_pos: Vector3 = other.global_position
		var diff: Vector3 = global_position - other_pos
		diff.y = 0  # Only separate horizontally
		var dist: float = diff.length()

		# Apply stronger separation when closer
		if dist > 0.5 and dist < 15.0:
			# Inverse distance weighting - closer = stronger push
			separation += diff.normalized() * (15.0 - dist) / 15.0

	# Apply separation force (scaled down to not overwhelm navigation)
	if separation.length_squared() > 0.01:
		velocity += separation.normalized() * 1.5

	return velocity


func _process_march(delta):
	# Don't process march movement when engaged in combat - prevents rubberbanding
	if state == State.ENGAGING:
		return

	# === VELOCITY-BASED MOVEMENT (Fix for rubberbanding) ===
	# Regiment reads leader's computed velocity and applies it directly.
	# This breaks the feedback loop where both parent and child wrote to global_position.

	if not leader:
		return

	var velocity: Vector3 = leader.current_velocity

	# Apply separation steering to avoid overlapping with other units
	velocity = _apply_separation_steering(velocity)

	if velocity.length_squared() > 0.0001:
		# Apply velocity to regiment position
		var movement = velocity * delta
		global_position += movement

		# Sync leader position back to regiment (child follows parent)
		leader.global_position = global_position

		# Apply terrain height
		if leader.has_method("get_terrain_height"):
			var terrain_height = leader.get_terrain_height(global_position)
			global_position.y = terrain_height
			leader.global_position.y = terrain_height

		# Apply arena bounds (fallback 590 for 1200x1200 map if AIAutoload unavailable)
		var map_bound: float = 590.0
		if AIAutoload:
			map_bound = AIAutoload.get_map_bounds()
		var hard_limit: float = map_bound - 1.0
		if absf(global_position.x) > hard_limit:
			global_position.x = signf(global_position.x) * hard_limit
		if absf(global_position.z) > hard_limit:
			global_position.z = signf(global_position.z) * hard_limit
		leader.global_position = global_position

	# Track charge distance if charging
	if current_order == OrderType.Type.CHARGE:
		charge_distance_traveled = global_position.distance_to(charge_start_position)

	# NOTE: formation, sprite_overlay, and melee_area are children of Regiment node
	# and inherit transforms automatically — no manual position writes needed.

	# Update soldier facing direction based on ACTUAL movement velocity (not target direction)
	# This fixes sprites facing wrong direction when moving along curved paths
	# Bug B fix: Use SAME direction for both sprite AND logical facing so flanking math matches visuals
	var velocity_dir: Vector3 = leader.current_velocity
	velocity_dir.y = 0

	# Use velocity for facing if moving fast enough, otherwise use target direction
	var facing_dir: Vector3
	if velocity_dir.length_squared() > 0.5:
		facing_dir = velocity_dir.normalized()
	else:
		# Fallback to target direction when nearly stopped
		facing_dir = (leader.target_position - global_position)
		facing_dir.y = 0
		if facing_dir.length_squared() < 0.1:
			facing_dir = _facing_direction  # Keep current facing

	# Bug B fix: SYNC both logical facing AND sprite facing to same direction
	# This ensures flanking calculations match what player sees
	if facing_dir.length_squared() > 0.01:
		_facing_direction = facing_dir.normalized()
		# Sync heading so combat transition is smooth (use WorldCompass)
		var march_dir_index := WorldCompassScript.direction_from_vector(_facing_direction)
		_current_heading = WorldCompassScript.angle_from_direction(march_dir_index)
		_target_heading = _current_heading

		# Update all visual components with same direction
		if formation and formation.has_method("set_facing_direction"):
			formation.set_facing_direction(_facing_direction)
		if sprite_overlay:
			sprite_overlay.set_facing_direction(_facing_direction)
		if artillery_formation:
			artillery_formation.set_facing_direction(_facing_direction)
		if range_indicator and range_indicator.has_method("update_facing"):
			range_indicator.update_facing(_facing_direction)

	if leader and leader.nav_agent and leader.nav_agent.is_navigation_finished():
		clear_movement_group()  # Clear group sync when arrived
		set_state(State.IDLE)


func _process_engage(delta: float) -> void:
	## Soft-separation: glide units to ideal spacing over multiple frames.
	## Uses dynamic engagement distance based on formation depth for rank-to-rank stopping.
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

	# Calculate dynamic engagement distance based on both formations' front rank offsets
	var ideal_distance: float = get_engagement_distance(enemy)
	var error: float = dist - ideal_distance  # +ve = too far, -ve = too close (overlapping)

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


func _process_route(delta: float):
	## Routing units flee away from enemies continuously.
	## Shattered units (can't rally) flee to map edge and are destroyed.
	## Non-shattered units flee until safe, then transition to RALLYING.

	if not leader:
		return

	# Check if we've fled off the map
	var map_bound: float = 80.0
	if AIAutoload:
		map_bound = AIAutoload.get_map_bounds()

	var dist_from_center: float = Vector2(global_position.x, global_position.z).length()
	if dist_from_center > map_bound + 5.0:
		# Unit has fled off the battlefield - mark as destroyed
		print("[Regiment] %s fled the battlefield!" % data.regiment_name)
		set_state(State.DEAD)
		return

	# Check if unit is shattered (80%+ broken soldiers - can NEVER rally)
	var is_shattered: bool = false
	if unit_morale:
		var broken_ratio: float = unit_morale.get_broken_ratio()
		is_shattered = broken_ratio >= MoraleConstants.UNIT_SHATTERED_RATIO

	# Find nearest enemy
	var nearest_enemy = _find_nearest_enemy()
	var enemy_distance: float = INF
	if nearest_enemy:
		enemy_distance = global_position.distance_to(nearest_enemy.global_position)

	# Determine flee direction
	var flee_dir: Vector3
	if nearest_enemy:
		# Flee away from nearest enemy
		flee_dir = (global_position - nearest_enemy.global_position).normalized()
	else:
		# No enemies visible - flee toward nearest map edge (away from center)
		flee_dir = Vector3(global_position.x, 0, global_position.z).normalized()
		if flee_dir.length_squared() < 0.01:
			flee_dir = Vector3(0, 0, 1)  # Default: flee south

	# Shattered units flee to map edge and are destroyed
	if is_shattered:
		var flee_target: Vector3 = flee_dir * (map_bound + 20.0)
		flee_target.y = global_position.y
		leader.move_to(flee_target)
		_apply_route_movement(delta, map_bound)
		return

	# Non-shattered units: check if we're safe enough to try rallying
	if enemy_distance > MoraleConstants.RALLY_DISTANCE_FROM_ENEMY:
		# Far enough from enemies - check if morale allows rally attempt
		if current_morale >= MoraleConstants.RALLY_MORALE_THRESHOLD:
			# Stop fleeing and try to rally
			leader.stop_movement()
			set_state(State.RALLYING)
			return

	# Still need to flee - move away from enemy
	var flee_distance: float = MoraleConstants.RALLY_DISTANCE_FROM_ENEMY + 15.0
	var flee_target: Vector3 = global_position + flee_dir * flee_distance
	flee_target.y = global_position.y
	leader.move_to(flee_target)
	_apply_route_movement(delta, map_bound)


func _apply_route_movement(delta: float, map_bound: float):
	## Apply leader velocity to regiment position during routing.
	## BUG FIX: Previously leader.move_to() was called but velocity was never applied.
	var velocity: Vector3 = leader.current_velocity
	if velocity.length_squared() < 0.0001:
		return

	# Apply velocity to regiment position
	var movement = velocity * delta
	global_position += movement

	# Sync leader position back to regiment (child follows parent)
	leader.global_position = global_position

	# Apply terrain height
	if leader.has_method("get_terrain_height"):
		var terrain_height = leader.get_terrain_height(global_position)
		global_position.y = terrain_height
		leader.global_position.y = terrain_height

	# Apply arena bounds (but don't clamp routing units - let them flee off map)
	# The map boundary check at the start of _process_route handles cleanup


func _process_rally(delta: float) -> void:
	# BUG #4 FIX: Actively recover morale during RALLYING state.
	# Previously just checked morale threshold without any recovery.
	current_morale += MoraleConstants.CONTINUOUS_RALLY_RECOVERY * delta
	current_morale = clampf(current_morale, 0.0, 100.0)

	# Advance rally reformation phases based on morale thresholds
	# Phase progression: Stop (30) → Centroid (35) → Flow-back (38) → Tighten (40)
	if sprite_overlay and sprite_overlay.has_method("advance_rally_phase"):
		sprite_overlay.advance_rally_phase(current_morale)

	# Check if we've rallied enough to return to IDLE
	if current_morale >= MoraleConstants.RALLY_SUCCESS_THRESHOLD:
		# Complete rally reformation if still in progress
		if sprite_overlay and sprite_overlay.has_method("complete_rally_reformation"):
			sprite_overlay.complete_rally_reformation()
		set_state(State.IDLE)


func _find_current_combat_target() -> Regiment:
	## Find the regiment we're currently fighting in melee.
	## BUG #6 FIX: Return null if not in active melee, don't fallback to nearest enemy.
	## The fallback was masking bugs where melee registration failed.
	## Callers already handle null gracefully.
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
	# No active melee found - return null so caller can handle appropriately
	return null


func _on_melee_area_contact(area: Area3D) -> void:
	## Simple stop-and-engage handler. NO teleport — soft separation happens in _process_engage.
	var my_name = data.regiment_name if data else name
	print("[MELEE DEBUG] %s: _on_melee_area_contact triggered with area=%s, my_pos=%s, area_pos=%s" % [my_name, area.name if area else "null", melee_area.global_position if melee_area else "null", area.global_position if area else "null"])
	if not is_instance_valid(area):
		return

	# Try direct parent first (standard case: MeleeArea -> Regiment)
	var other: Regiment = area.get_parent() as Regiment

	# If direct parent isn't Regiment, check metadata (artillery collision case)
	# Artillery pieces: StaticBody3D -> ArtilleryPiece -> ArtilleryFormation -> Regiment
	if not is_instance_valid(other) or other == self:
		other = _find_regiment_from_node(area)

	if not is_instance_valid(other) or other == self:
		print("[MELEE DEBUG] %s: area parent is not valid regiment (parent=%s)" % [my_name, area.get_parent().name if area and area.get_parent() else "null"])
		return
	if other.state == State.DEAD or state == State.DEAD:
		print("[MELEE DEBUG] %s: Contact with %s blocked - one is DEAD" % [data.regiment_name if data else name, other.data.regiment_name if other.data else other.name])
		return
	if other.is_player_controlled == is_player_controlled:
		return  # Same faction — no engagement

	# BUG #7 FIX: Check disengagement cooldown to prevent immediate re-engagement.
	# Units that just disengaged have a 500ms grace period before re-engaging.
	const DISENGAGE_COOLDOWN_MS: int = 500
	var my_cooldown: int = get_meta("disengage_cooldown", 0)
	var other_cooldown: int = other.get_meta("disengage_cooldown", 0)
	var now: int = Time.get_ticks_msec()
	if (now - my_cooldown) < DISENGAGE_COOLDOWN_MS or (now - other_cooldown) < DISENGAGE_COOLDOWN_MS:
		print("[MELEE DEBUG] %s: Contact with %s blocked - disengage cooldown" % [data.regiment_name if data else name, other.data.regiment_name if other.data else other.name])
		return  # Still in cooldown, don't re-engage

	# Already engaged with this exact unit? Bail — don't re-trigger.
	if state == State.ENGAGING and _find_current_combat_target() == other:
		return

	# Lower instance ID owns engagement-start to avoid double-processing.
	if get_instance_id() > other.get_instance_id():
		return

	print("[MELEE DEBUG] %s: Starting melee with %s" % [data.regiment_name if data else name, other.data.regiment_name if other.data else other.name])

	# Stop both units where they actually are. No teleport.
	leader.stop_movement()
	other.leader.stop_movement()

	# Start combat — charge impact logic runs inside begin_melee
	CombatManager.begin_melee(self, other)
	set_state(State.ENGAGING)
	other.set_state(State.ENGAGING)


func _find_regiment_from_node(node: Node) -> Regiment:
	## Walk up the parent chain looking for a Regiment.
	## Also checks metadata "regiment" key for indirect references (e.g., artillery collision bodies).
	if not is_instance_valid(node):
		return null

	var current: Node = node
	var depth: int = 0
	const MAX_DEPTH: int = 8  # Prevent infinite loops

	while current and depth < MAX_DEPTH:
		# Check metadata first (set by artillery_formation._ensure_collision)
		var meta_regiment: Variant = current.get_meta("regiment", null)
		if meta_regiment is Regiment and is_instance_valid(meta_regiment):
			return meta_regiment

		# Check if current node is a Regiment
		if current is Regiment:
			return current

		current = current.get_parent()
		depth += 1

	return null


func _poll_melee_overlaps() -> void:
	## Polling-based fallback for melee detection when area_entered signal fails.
	## This catches overlaps that the signal misses (common in Godot 4 with fast movement).
	if not melee_area or not is_instance_valid(melee_area):
		return

	var overlapping: Array[Area3D] = melee_area.get_overlapping_areas()
	for area in overlapping:
		if not is_instance_valid(area):
			continue

		# Find regiment from this area
		var other: Regiment = area.get_parent() as Regiment
		if not is_instance_valid(other) or other == self:
			other = _find_regiment_from_node(area)
		if not is_instance_valid(other) or other == self:
			continue

		# Skip same faction
		if other.is_player_controlled == is_player_controlled:
			continue

		# Skip dead units
		if other.state == State.DEAD or state == State.DEAD:
			continue

		# Check disengage cooldown
		const DISENGAGE_COOLDOWN_MS: int = 500
		var my_cooldown: int = get_meta("disengage_cooldown", 0)
		var other_cooldown: int = other.get_meta("disengage_cooldown", 0)
		var now: int = Time.get_ticks_msec()
		if (now - my_cooldown) < DISENGAGE_COOLDOWN_MS or (now - other_cooldown) < DISENGAGE_COOLDOWN_MS:
			continue

		# Already engaged with this unit?
		if state == State.ENGAGING and _find_current_combat_target() == other:
			continue

		# Lower instance ID owns engagement-start
		if get_instance_id() > other.get_instance_id():
			continue

		print("[MELEE POLL] %s: Detected overlap with %s via polling fallback" % [
			data.regiment_name if data else name,
			other.data.regiment_name if other.data else other.name])

		# Stop both units and start combat
		leader.stop_movement()
		other.leader.stop_movement()
		CombatManager.begin_melee(self, other)
		set_state(State.ENGAGING)
		other.set_state(State.ENGAGING)
		return  # Only process one engagement per tick


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


func _on_casualty_threshold_reached(threshold_name: String, loss_pct: float):
	## Called when casualty tracker hits a loss threshold.
	## This is a HARD trigger - heavy casualties force routing regardless of individual soldier morale.
	print("[Regiment] %s: Casualty threshold '%s' reached (%.0f%% loss)" % [
		data.regiment_name if data else name, threshold_name, loss_pct * 100.0])

	match threshold_name:
		"rout":
			# Force immediate rout - 75%+ casualties in window
			if state != State.ROUTING and state != State.DEAD:
				set_state(State.ROUTING)
				BattleSignals.regiment_routing.emit(self)
		"withdraw":
			# Drop morale significantly to encourage routing soon
			if unit_morale:
				unit_morale.apply_morale_modifier(-30.0)
		"caution":
			# Minor morale hit, AI should go defensive
			if unit_morale:
				unit_morale.apply_morale_modifier(-10.0)
			if ai_controller:
				ai_controller.set_stance(CommanderAI.Stance.DEFENSIVE)


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
	## Get attack modifier scaled by formation cohesion.
	var cohesion: float = get_formation_cohesion()
	var base: float = FormationType.get_attack_modifier_scaled(current_formation, cohesion)
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
	## Get defense modifier scaled by formation cohesion.
	var cohesion: float = get_formation_cohesion()
	var base: float = FormationType.get_defense_modifier_scaled(current_formation, cohesion)
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
	## Get anti-cavalry modifier scaled by formation cohesion.
	var cohesion: float = get_formation_cohesion()
	var base: float = FormationType.get_anti_cavalry_modifier_scaled(current_formation, cohesion)
	if is_braced:
		base *= 2.0  # Double when braced
	return base


func get_ranged_modifier() -> float:
	## Get ranged accuracy modifier (formation + veterancy + stamina), scaled by cohesion.
	var cohesion: float = get_formation_cohesion()
	var base: float = FormationType.get_ranged_modifier_scaled(current_formation, cohesion)
	# Veterancy ranged bonus
	if veterancy:
		base += veterancy.get_ranged_bonus()
	# Stamina affects accuracy
	if stamina:
		base *= stamina.get_combat_modifier()
	return base


func get_charge_modifier() -> float:
	## Get charge damage modifier (formation + stamina), scaled by cohesion.
	var cohesion: float = get_formation_cohesion()
	var base: float = FormationType.get_charge_modifier_scaled(current_formation, cohesion)
	# Stamina affects charge power
	if stamina:
		base *= stamina.get_combat_modifier()
	return base


# === FORMATION COHESION SYSTEM ===

func get_formation_cohesion() -> float:
	## Get current formation cohesion (0.0-1.0).
	## Delegates to sprite_overlay if available.
	if sprite_overlay and sprite_overlay.has_method("get_cohesion"):
		return sprite_overlay.get_cohesion()
	return 1.0  # Default to fully formed if no sprite overlay


func _update_tolerance_mode_for_state() -> void:
	## Map regiment state to appropriate tolerance mode.
	## Called when state changes to sync formation tolerance.
	if not sprite_overlay:
		return
	if not sprite_overlay.has_method("set_tolerance_mode"):
		return

	# Import SlotToleranceMode from SpriteFormation
	const LOCKED = 0  # SpriteFormation.SlotToleranceMode.LOCKED
	const TOLERANT = 1  # SpriteFormation.SlotToleranceMode.TOLERANT
	const SUSPENDED = 2  # SpriteFormation.SlotToleranceMode.SUSPENDED

	match state:
		State.IDLE, State.MARCHING:
			sprite_overlay.set_tolerance_mode(LOCKED)
		State.ENGAGING:
			sprite_overlay.set_tolerance_mode(TOLERANT)
		State.ROUTING:
			sprite_overlay.set_tolerance_mode(SUSPENDED)
		State.RALLYING:
			# Start wide, tighten progressively (handled by rally phase system)
			if not sprite_overlay.is_rally_reforming():
				sprite_overlay.begin_rally_reformation()


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
	## Fallback to South if not initialized (should not happen if set_initial_facing() is called).
	if _facing_direction.length_squared() > 0.001:
		return _facing_direction.normalized()
	# Fallback: use South (toward typical enemy position) if not set
	return WorldCompassScript.SOUTH


func set_facing_direction(direction: Vector3) -> void:
	## Set the regiment's facing direction (for ranged attacks, formations).
	## Updates sprites, LOS cone, and internal facing state.
	direction.y = 0
	if direction.length_squared() < 0.001:
		return

	_facing_direction = direction.normalized()
	# Use WorldCompass for consistent angle calculation
	var dir_index := WorldCompassScript.direction_from_vector(_facing_direction)
	_current_heading = WorldCompassScript.angle_from_direction(dir_index)
	_target_heading = _current_heading

	# Update formation sprite facing
	if formation and formation.has_method("set_facing_direction"):
		formation.set_facing_direction(_facing_direction)

	# Update sprite overlay
	if sprite_overlay:
		sprite_overlay.set_facing_direction(_facing_direction)

	# Update artillery formation
	if artillery_formation:
		artillery_formation.set_facing_direction(_facing_direction)
		# Update crew sprite positions around the rotated cannons
		if sprite_overlay and sprite_overlay.has_method("update_artillery_piece_positions"):
			var piece_positions: Array[Vector3] = artillery_formation._calculate_piece_positions(data.artillery_pieces_count)
			sprite_overlay.update_artillery_piece_positions(piece_positions)

	# Update range indicator LOS cone
	if range_indicator and range_indicator.has_method("update_facing"):
		range_indicator.update_facing(_facing_direction)


func set_initial_facing(direction: Vector3) -> void:
	## Set initial facing direction on spawn (Bug C fix).
	## Call this after spawning to orient regiment toward enemy deployment zone.
	## This is separate from set_facing_direction() to be explicit about spawn-time setup.
	direction.y = 0
	if direction.length_squared() < 0.001:
		# Default: face South if no direction provided (toward typical enemy position)
		direction = WorldCompassScript.SOUTH

	_facing_direction = direction.normalized()
	var dir_index := WorldCompassScript.direction_from_vector(_facing_direction)
	_current_heading = WorldCompassScript.angle_from_direction(dir_index)
	_target_heading = _current_heading

	# Update all visual components
	if formation and formation.has_method("set_facing_direction"):
		formation.set_facing_direction(_facing_direction)
	if sprite_overlay:
		sprite_overlay.set_facing_direction(_facing_direction)
	if artillery_formation:
		artillery_formation.set_facing_immediate(_facing_direction)
		# Update crew sprite positions around the rotated cannons
		if sprite_overlay and sprite_overlay.has_method("update_artillery_piece_positions"):
			var piece_positions: Array[Vector3] = artillery_formation._calculate_piece_positions(data.artillery_pieces_count)
			sprite_overlay.update_artillery_piece_positions(piece_positions)
	if range_indicator and range_indicator.has_method("update_facing"):
		range_indicator.update_facing(_facing_direction)


func _compute_initial_facing_from_deployment() -> Vector3:
	## Look up PlayerDeployment / EnemyDeployment markers in the scene and
	## compute the initial facing as the direction toward the opposing side.
	## Falls back to an east-west assumption if markers aren't found.
	var scene_root: Node = get_tree().current_scene
	if scene_root:
		var player_marker: Node = scene_root.find_child("PlayerDeployment", true, false)
		var enemy_marker: Node = scene_root.find_child("EnemyDeployment", true, false)
		if player_marker and enemy_marker and \
		   player_marker is Node3D and enemy_marker is Node3D:
			var dir: Vector3
			if is_player_controlled:
				dir = enemy_marker.global_position - player_marker.global_position
			else:
				dir = player_marker.global_position - enemy_marker.global_position
			dir.y = 0.0
			if dir.length_squared() > 0.001:
				return dir.normalized()
	# Fallback: previous east-west hardcoded behavior.
	return Vector3(1, 0, 0) if is_player_controlled else Vector3(-1, 0, 0)


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
		var _bonus: float = veterancy.get_morale_bonus()  # Applied via unit_morale modifiers
		# This is applied as a continuous modifier to base morale
	BattleSignals.unit_leveled_up.emit(self, old_level, new_level)


func _on_ability_activated(ability: AbilityType.Type):
	BattleSignals.ability_used.emit(self, ability)


func _on_ability_ended(_ability: AbilityType.Type):
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

		UnitType.Type.MONSTER:
			# Monsters get a confidence bonus - they're big and scary!
			unit_morale.set_continuous_modifier_all(
				MoraleEvent.Source.UNIT_TYPE_BONUS,
				MoraleConstants.UNIT_TYPE_CAVALRY_MORALE_BONUS  # +10% like cavalry
			)
			unit_morale.clear_continuous_modifier_all(MoraleEvent.Source.UNIT_TYPE_PENALTY)

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
		leader.current_velocity = Vector3.ZERO  # Clear velocity to prevent drift
		if leader.nav_agent:
			leader.nav_agent.target_position = pos
	if formation:
		formation.global_position = pos
	if sprite_overlay:
		sprite_overlay.global_position = pos
	if melee_area:
		melee_area.global_position = pos


# --- AMMO TYPE ---
func set_round_type(round_type: int) -> bool:
	## Change the current ammo/round type for artillery weapons.
	## Returns true if the change was successful, false if invalid.
	## Only artillery weapons (cannon, mortar, war_machine) support multiple round types.
	if not data:
		return false

	# Check if this is an artillery weapon that supports round switching
	if not WeaponClassData.is_artillery_weapon(data.weapon_class):
		return false

	# Check if the requested round type is valid for this weapon
	var available_rounds: Array[int] = WeaponClassData.get_available_rounds(data.weapon_class)
	if round_type not in available_rounds:
		return false

	# Don't emit signal if round type hasn't changed
	if round_type == current_round_type:
		return true

	var old_type: int = current_round_type
	current_round_type = round_type

	# Emit signal for UI and other systems to respond
	BattleSignals.round_type_changed.emit(self, old_type, round_type)

	return true


func get_round_type_name() -> String:
	## Returns the human-readable name of the current round type.
	## e.g., "Grapeshot", "Solid Shot", "Explosive"
	return WeaponClassData.get_round_type_name(current_round_type)


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


# === SELECTION VISUAL (QOL Phase 3) ===

func set_selected_visual(is_selected: bool) -> void:
	"""Show or hide selection ring on ground."""
	if is_selected:
		if not _selection_ring:
			var SelectionRingScript := preload("res://battle_system/effects/selection_ring.gd")
			_selection_ring = SelectionRingScript.new()
			add_child(_selection_ring)
			# Position at ground level
			_selection_ring.position = Vector3(0, 0.05, 0)

			# Tint by faction
			var color: Color = (
				Color(0.4, 0.8, 1.0, 0.6) if is_player_controlled
				else Color(1.0, 0.4, 0.4, 0.6)
			)
			if _selection_ring.has_method("set_color"):
				_selection_ring.set_color(color)

			# Size to formation extent
			var radius: float = _calculate_formation_radius()
			if _selection_ring.has_method("set_size"):
				_selection_ring.set_size(radius)
	else:
		if _selection_ring:
			_selection_ring.queue_free()
			_selection_ring = null


func _calculate_formation_radius() -> float:
	"""Approximate radius of formation footprint."""
	if not data:
		return 3.0
	# Estimate based on soldier count and spacing
	var soldier_count: int = current_soldiers if current_soldiers > 0 else data.max_soldiers
	var rows: int = ceili(sqrt(float(soldier_count)))
	var spacing: float = 1.2  # Default formation spacing
	return rows * spacing * 0.7
