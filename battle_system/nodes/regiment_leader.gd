# The leader is a hidden node that does all the actual pathfinding.
# Soldiers in the regiment follow offsets from the leader's position.
# This keeps formation shape while navigating around obstacles.

class_name RegimentLeader
extends Node3D

# Preload to avoid parse-order issues with class_name
const TerrainHelperScript = preload("res://battle_system/terrain/terrain_helper.gd")

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
var target_position: Vector3

# Base speeds (set from RegimentData in Regiment._ready)
var walk_speed: float = 1.75    # Normal marching pace (50% of old)
var run_speed: float = 2.0      # Slightly faster (running)
var charge_speed: float = 3.5   # Fast burst for charges (old infantry speed)
var charge_speed_distance: float = 15.0  # Distance charge speed lasts

# Speed modifier from parent regiment (fatigue, formation, etc.)
# Updated each frame by Regiment - DEI-inspired fatigue system
var speed_modifier: float = 1.0

# Movement mode (set by Regiment based on orders)
enum MoveMode { WALK, RUN, CHARGE }
var move_mode: MoveMode = MoveMode.WALK

# Charge burst tracking
var _charge_start_pos: Vector3 = Vector3.ZERO
var _charge_distance_used: float = 0.0

# Stuck detection (spring1944-inspired)
var _last_position: Vector3 = Vector3.ZERO
var _stuck_time: float = 0.0
const STUCK_THRESHOLD: float = 3.0  # Seconds before attempting unstuck
const STUCK_MOVE_THRESHOLD: float = 0.5  # Must move more than this to not be stuck

# === VELOCITY-BASED MOVEMENT (Fix for rubberbanding) ===
# Leader computes velocity, Regiment applies it. This breaks the feedback loop
# where both Regiment (parent) and Leader (child) were writing to global_position.
var current_velocity: Vector3 = Vector3.ZERO  # Published for Regiment to read

# Avoidance system - stores safe velocity from NavigationAgent3D callback
var _safe_velocity: Vector3 = Vector3.ZERO
var _avoidance_velocity_computed: bool = false


## Get the effective movement speed based on mode and charge distance
func get_effective_speed() -> float:
	var base_speed: float

	match move_mode:
		MoveMode.CHARGE:
			# Charge speed only lasts for charge_speed_distance, then drops to run
			if _charge_distance_used < charge_speed_distance:
				base_speed = charge_speed
			else:
				base_speed = run_speed  # Slow down after charge burst expires
		MoveMode.RUN:
			base_speed = run_speed
		_:  # WALK
			base_speed = walk_speed

	return base_speed * speed_modifier


## Start a charge burst - resets charge distance tracking
func start_charge() -> void:
	move_mode = MoveMode.CHARGE
	_charge_start_pos = global_position
	_charge_distance_used = 0.0


## Set movement mode (called by Regiment)
func set_move_mode(mode: MoveMode) -> void:
	if move_mode != mode:
		move_mode = mode
		if mode == MoveMode.CHARGE:
			start_charge()


## Reset charge state when combat ends or order changes
func reset_charge_burst() -> void:
	_charge_distance_used = 0.0
	_charge_start_pos = global_position


func _ready():
	# Initialize target to current position to prevent spurious movement
	target_position = global_position
	current_velocity = Vector3.ZERO
	if nav_agent:
		nav_agent.target_position = global_position
		# Enable avoidance so units steer around each other
		nav_agent.avoidance_enabled = true
		nav_agent.neighbor_distance = 25.0   # How far to look for other agents
		nav_agent.max_neighbors = 10         # Max agents to consider
		nav_agent.time_horizon_agents = 1.0  # Lookahead time for agent avoidance
		nav_agent.time_horizon_obstacles = 0.5  # Lookahead for static obstacles
		nav_agent.radius = 4.0               # Avoidance radius (unit size)
		# Connect to velocity_computed signal for proper avoidance
		nav_agent.velocity_computed.connect(_on_velocity_computed)


func _get_terrain() -> DaggerfallTerrain:
	## Get terrain via centralized helper (Phase 6.4 deduplication)
	return TerrainHelperScript.get_terrain(get_tree())


func stop_movement():
	## Stop all movement immediately - for combat engagement
	target_position = global_position
	nav_agent.target_position = global_position
	nav_agent.set_velocity(Vector3.ZERO)  # Force velocity stop to prevent rubberbanding
	current_velocity = Vector3.ZERO  # Clear published velocity


const ARENA_MARGIN: float = 5.0  # Stay this far inside arena bounds


func move_to(pos: Vector3):
	# Clamp to arena bounds with safety margin (Phase 9.2)
	var map_bound: float = 90.0
	if AIAutoload:
		map_bound = AIAutoload.get_map_bounds()
	var safe_bound: float = map_bound - ARENA_MARGIN
	pos.x = clampf(pos.x, -safe_bound, safe_bound)
	pos.z = clampf(pos.z, -safe_bound, safe_bound)

	target_position = pos
	# Adjust target height to terrain (Phase 6.4: use helper)
	var terrain := _get_terrain()
	if terrain:
		pos.y = terrain.get_height_at(pos)

	# Check if navigation map is available
	var nav_map = nav_agent.get_navigation_map()
	var _nav_available = NavigationServer3D.map_get_iteration_id(nav_map) > 0

	nav_agent.target_position = pos


func _physics_process(delta):
	# === VELOCITY-BASED MOVEMENT WITH AVOIDANCE ===
	# Leader computes desired velocity, passes it through NavigationAgent3D avoidance,
	# then publishes the safe velocity for Regiment to apply.

	if nav_agent.is_navigation_finished():
		_stuck_time = 0.0  # Reset stuck timer when navigation complete
		current_velocity = Vector3.ZERO
		nav_agent.set_velocity(Vector3.ZERO)
		return

	# Stuck detection (spring1944-inspired)
	_check_stuck(delta)

	# Check if nav map is available
	var nav_map = nav_agent.get_navigation_map()
	var nav_available = nav_map != RID() and NavigationServer3D.map_get_iteration_id(nav_map) > 0

	var next: Vector3
	var dist_to_target = global_position.distance_to(nav_agent.target_position)

	if nav_available:
		next = nav_agent.get_next_path_position()
	else:
		# No navigation available - move directly towards target
		next = nav_agent.target_position

	var dist_to_next = global_position.distance_to(next)

	# Check if we've arrived at target
	if dist_to_target < 1.0:
		current_velocity = Vector3.ZERO
		nav_agent.set_velocity(Vector3.ZERO)
		return

	# Calculate direction to move
	var direction: Vector3

	# If next position is basically our current position but we're not at target, move directly
	# This handles: nav mesh not ready, position outside nav mesh, or nav stuck
	if dist_to_next < 0.5 and dist_to_target > 1.0:
		# Navigation is stuck or unavailable - move directly towards target
		var dir_to_target = (nav_agent.target_position - global_position)
		dir_to_target.y = 0
		if dir_to_target.length() > 0.1:
			direction = dir_to_target.normalized()
		else:
			current_velocity = Vector3.ZERO
			nav_agent.set_velocity(Vector3.ZERO)
			return
	else:
		direction = (next - global_position).normalized()
		direction.y = 0  # Keep movement horizontal

	if direction.length_squared() < 0.01:
		current_velocity = Vector3.ZERO
		nav_agent.set_velocity(Vector3.ZERO)
		return

	# Get speed based on movement mode (walk/run/charge)
	var effective_speed: float = get_effective_speed()

	# Track charge distance used
	if move_mode == MoveMode.CHARGE:
		_charge_distance_used += effective_speed * delta

	# Compute desired velocity
	var desired_velocity: Vector3 = direction * effective_speed

	# Pass through NavigationAgent3D avoidance system
	# The velocity_computed callback will update current_velocity with the safe velocity
	if nav_agent.avoidance_enabled:
		nav_agent.set_velocity(desired_velocity)
		# current_velocity is set in _on_velocity_computed callback
	else:
		# No avoidance - use desired velocity directly
		current_velocity = desired_velocity

	# Update facing based on velocity direction (rotation is fine to set here)
	if direction.length() > 0.01:
		var look_target = global_position + direction
		look_at(look_target, Vector3.UP)


## Callback from NavigationAgent3D avoidance system
## Receives the computed safe velocity that avoids other agents
func _on_velocity_computed(safe_velocity: Vector3) -> void:
	current_velocity = safe_velocity


func _apply_terrain_height():
	## Snap to terrain height (Phase 6.4: use helper)
	var terrain := _get_terrain()
	if terrain:
		var terrain_height = terrain.get_height_at(global_position)
		global_position.y = terrain_height


func _enforce_arena_bounds() -> void:
	## Per-frame safety net: clamp position to arena bounds (Phase 9.3).
	## Catches edge cases where units drift outside via terrain push, formation reform, etc.
	var map_bound: float = 90.0
	if AIAutoload:
		map_bound = AIAutoload.get_map_bounds()
	var hard_limit: float = map_bound - 1.0  # 1 unit inside actual edge

	var clamped: bool = false
	if absf(global_position.x) > hard_limit:
		global_position.x = signf(global_position.x) * hard_limit
		clamped = true
	if absf(global_position.z) > hard_limit:
		global_position.z = signf(global_position.z) * hard_limit
		clamped = true

	if clamped and OS.is_debug_build():
		var parent_name: String = get_parent().name if get_parent() else "?"
		push_warning("RegimentLeader %s clamped to arena bounds at %s" % [parent_name, global_position])


func get_terrain_height(pos: Vector3) -> float:
	## Get terrain height at a position (Phase 6.4: use helper)
	return TerrainHelperScript.get_height_at(get_tree(), pos)


func get_terrain_slope() -> float:
	## Get slope angle at current position (in degrees) (Phase 6.4: use helper)
	return TerrainHelperScript.get_slope_at(get_tree(), global_position)


func _check_stuck(delta: float) -> void:
	## Check if unit is stuck and attempt recovery (spring1944-inspired).
	var moved_dist: float = global_position.distance_to(_last_position)

	if moved_dist < STUCK_MOVE_THRESHOLD:
		# Haven't moved much, might be stuck
		_stuck_time += delta
		if _stuck_time >= STUCK_THRESHOLD:
			_attempt_unstuck()
			_stuck_time = 0.0  # Reset timer after attempt
	else:
		# Moving normally, reset stuck timer
		_stuck_time = 0.0

	_last_position = global_position


func _attempt_unstuck() -> void:
	## Try to find a valid nearby position and walk there (spring1944-inspired).
	## Uses tight radius search (max 6 units) to avoid large visible jumps.
	## Walks to recovery point via nav mesh rather than teleporting.

	var map_bound: float = 90.0
	if AIAutoload:
		map_bound = AIAutoload.get_map_bounds()
	var safe_bound: float = map_bound - ARENA_MARGIN

	# Tight search radii - never jump more than 6 units (Phase 9.1)
	var search_radii := [2.0, 4.0, 6.0]
	var angles := [0.0, PI/4, PI/2, 3*PI/4, PI, 5*PI/4, 3*PI/2, 7*PI/4]

	var best_pos: Vector3 = Vector3.INF
	var best_score: float = INF

	for radius in search_radii:
		for angle in angles:
			var test_offset := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			var test_pos := global_position + test_offset

			# Skip positions outside safe arena bounds
			if absf(test_pos.x) > safe_bound or absf(test_pos.z) > safe_bound:
				continue

			if not _is_valid_position(test_pos):
				continue

			# Prefer positions closer to original target (don't flee sideways)
			var score: float = test_pos.distance_to(target_position)
			if score < best_score:
				best_score = score
				best_pos = test_pos

	if best_pos == Vector3.INF:
		return  # No valid recovery - retry in 3 seconds

	# Walk to recovery point via nav mesh, don't teleport
	nav_agent.target_position = best_pos
	_last_position = global_position  # Prevent immediate re-stuck detection


func _is_valid_position(pos: Vector3) -> bool:
	## Check if a position is valid for movement.
	## Uses navigation map query if available, otherwise terrain check.

	# Check nav map if available
	var nav_map := nav_agent.get_navigation_map()
	if nav_map != RID() and NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		var closest := NavigationServer3D.map_get_closest_point(nav_map, pos)
		var dist_to_closest := pos.distance_to(closest)
		return dist_to_closest < 1.5  # Tighter threshold - land ON the nav mesh

	# Fallback: just check terrain height is reasonable (Phase 6.4: use helper)
	var terrain := _get_terrain()
	if terrain:
		var height := terrain.get_height_at(pos)
		return height > -100.0  # Not below water/void

	return true  # Assume valid if no checks possible
