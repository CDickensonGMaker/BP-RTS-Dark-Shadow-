# Main 3D campaign map controller.
# Handles map input, battalion spawning, and movement orders in 3D space.
extends Node3D


## Map size in pixels (matches 2D campaign_map.png)
@export var map_bounds_pixels: Rect2 = Rect2(0, 0, 3053, 2160)

# Node references
var camera: Camera3D
var terrain: Node3D
var battalions_container: Node3D
var enemy_armies_container: Node3D
var fog_of_war: Node3D
var path_preview: Node3D

var battalion_scene_3d: PackedScene

## Loaded region data
var regions: Array = []
var selected_battalion: Node3D = null

# Path preview
var path_lines: Array[MeshInstance3D] = []

# Movement constants
const MOVEMENT_COST_PER_PIXEL := 0.1
const PIXELS_TO_UNITS := 0.1

# Total War-style turn colors
const TURN_COLORS := [
	Color(0.3, 0.85, 0.3, 0.9),   # Turn 0: Green
	Color(0.9, 0.25, 0.25, 0.9),  # Turn 1: Red
	Color(0.0, 0.78, 0.88, 0.9),  # Turn 2: Cyan
	Color(1.0, 0.78, 0.0, 0.9),   # Turn 3: Gold
	Color(0.65, 0.25, 0.85, 0.9), # Turn 4+: Purple
]

# Movement range visualization
var range_mesh: MeshInstance3D = null

# Right-click state
var is_right_click_held: bool = false


func _ready() -> void:
	# Create scene structure
	_create_scene_structure()

	# Connect signals
	if CampaignSignals:
		if not CampaignSignals.battalion_selected.is_connected(_on_battalion_selected):
			CampaignSignals.battalion_selected.connect(_on_battalion_selected)
		if not CampaignSignals.battalion_deselected.is_connected(_on_battalion_deselected):
			CampaignSignals.battalion_deselected.connect(_on_battalion_deselected)
		if not CampaignSignals.turn_started.is_connected(_on_turn_started):
			CampaignSignals.turn_started.connect(_on_turn_started)
		if not CampaignSignals.movement_points_changed.is_connected(_on_movement_points_changed):
			CampaignSignals.movement_points_changed.connect(_on_movement_points_changed)

	# Start campaign if not active
	if not CampaignManager.is_campaign_active:
		CampaignManager.start_new_campaign()

	# Wait for terrain to generate
	await get_tree().create_timer(0.5).timeout

	# Spawn battalions
	_spawn_battalions()

	# Spawn test enemy armies
	_spawn_enemy_armies()

	# Reveal initial fog
	_reveal_initial_fog()


func _create_scene_structure() -> void:
	## Create the 3D scene hierarchy

	# Add directional light (sun)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	# Add ambient light
	var ambient := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	ambient.environment = env
	add_child(ambient)

	# Create terrain
	var terrain_script := load("res://campaign_system/terrain/campaign_terrain_3d.gd")
	terrain = Node3D.new()
	terrain.set_script(terrain_script)
	terrain.name = "CampaignTerrain"
	add_child(terrain)

	# Create camera
	var camera_script := load("res://campaign_system/map/campaign_camera_3d.gd")
	camera = Camera3D.new()
	camera.set_script(camera_script)
	camera.name = "CampaignCamera3D"
	camera.current = true
	add_child(camera)

	# Create battalion container
	battalions_container = Node3D.new()
	battalions_container.name = "BattalionsContainer"
	add_child(battalions_container)

	# Create enemy armies container
	enemy_armies_container = Node3D.new()
	enemy_armies_container.name = "EnemyArmiesContainer"
	add_child(enemy_armies_container)

	# Create fog of war (3D version)
	var fog_script := load("res://campaign_system/systems/fog_of_war_3d.gd")
	if fog_script:
		fog_of_war = Node3D.new()
		fog_of_war.set_script(fog_script)
		fog_of_war.name = "FogOfWar3D"
		add_child(fog_of_war)

	# Create path preview container
	path_preview = Node3D.new()
	path_preview.name = "PathPreview"
	add_child(path_preview)

	# Create range visualization mesh
	_create_range_mesh()

	# Load battalion scene
	var battalion_3d_path := "res://campaign_system/scenes/map_battalion_3d.tscn"
	if ResourceLoader.exists(battalion_3d_path):
		battalion_scene_3d = load(battalion_3d_path)
	else:
		# Will create dynamically if scene doesn't exist
		battalion_scene_3d = null


func _spawn_battalions() -> void:
	## Spawn battalion tokens from CampaignManager
	for child in battalions_container.get_children():
		child.queue_free()

	for battalion_data in CampaignManager.battalions:
		var battalion_node: Node3D

		if battalion_scene_3d:
			battalion_node = battalion_scene_3d.instantiate()
		else:
			# Create dynamically
			battalion_node = Node3D.new()
			var script := load("res://campaign_system/map/map_battalion_3d.gd")
			battalion_node.set_script(script)

		battalion_node.battalion_data = battalion_data

		# Convert pixel position to world
		var pixel_pos: Vector2 = battalion_data.map_position
		battalion_node.position = Vector3(
			pixel_pos.x * PIXELS_TO_UNITS,
			0,
			pixel_pos.y * PIXELS_TO_UNITS
		)

		battalions_container.add_child(battalion_node)

		# Snap to terrain height
		await get_tree().process_frame
		if terrain and terrain.has_method("get_height_at"):
			battalion_node.position.y = terrain.get_height_at(battalion_node.position) + 0.1

		# Select first battalion by default
		if CampaignManager.battalions.size() == 1:
			battalion_node.call_deferred("select")


func _spawn_enemy_armies() -> void:
	## Spawn enemy armies for testing
	var EnemyArmyScript = load("res://campaign_system/map/map_enemy_army_3d.gd")
	if not EnemyArmyScript:
		return

	# Test enemy armies at various pixel positions
	var test_armies := [
		{"pos": Vector2(800, 600), "faction": 1, "name": "Orc Warband", "regiments": 4},
		{"pos": Vector2(1500, 900), "faction": 2, "name": "Undead Legion", "regiments": 5},
		{"pos": Vector2(2200, 500), "faction": 3, "name": "Dwarf Ironguard", "regiments": 3},
		{"pos": Vector2(1200, 1400), "faction": 0, "name": "Forest Bandits", "regiments": 2},
	]

	for army_data: Dictionary in test_armies:
		var pixel_pos: Vector2 = army_data.pos
		var world_pos := Vector3(
			pixel_pos.x * PIXELS_TO_UNITS,
			0,
			pixel_pos.y * PIXELS_TO_UNITS
		)

		var army := Node3D.new()
		army.set_script(EnemyArmyScript)
		army.faction = army_data.faction
		army.army_name = army_data.name
		army.regiment_count = army_data.regiments
		army.position = world_pos

		enemy_armies_container.add_child(army)


func _reveal_initial_fog() -> void:
	## Reveal fog around starting positions
	if not fog_of_war:
		return

	for battalion_data in CampaignManager.battalions:
		if fog_of_war.has_method("reveal_area"):
			fog_of_war.reveal_area(battalion_data.map_position, 200.0)

	if fog_of_war.has_method("_update_fog_texture"):
		fog_of_war._update_fog_texture()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Right-click: HOLD to preview path, RELEASE to execute
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_right_click_held = true
				if selected_battalion:
					_update_path_preview(_get_mouse_world_position())
			else:
				if is_right_click_held and selected_battalion:
					_order_move(_get_mouse_world_position())
				is_right_click_held = false
				_hide_path_preview()
			get_viewport().set_input_as_handled()

		# Left-click: select battalion or settlement
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var clicked := _get_battalion_at_screen_pos(event.position)
			if clicked:
				clicked.select()
			else:
				# Check for settlement click
				var settlement := _get_settlement_at_screen_pos(event.position)
				if settlement:
					CampaignSignals.settlement_clicked.emit(settlement)
				elif selected_battalion:
					selected_battalion.deselect()
			get_viewport().set_input_as_handled()

	# Update path preview while right-click held
	if event is InputEventMouseMotion and is_right_click_held and selected_battalion:
		_update_path_preview(_get_mouse_world_position())


func _get_mouse_world_position() -> Vector3:
	## Raycast from mouse to terrain
	var mouse_pos := get_viewport().get_mouse_position()

	if camera and camera.has_method("screen_to_world"):
		return camera.screen_to_world(mouse_pos)

	# Fallback raycast
	var from := camera.project_ray_origin(mouse_pos)
	var dir := camera.project_ray_normal(mouse_pos)

	# Intersect with Y=0 plane
	if abs(dir.y) < 0.001:
		return Vector3.ZERO

	var t := -from.y / dir.y
	return from + dir * t


func _get_battalion_at_screen_pos(screen_pos: Vector2) -> Node3D:
	## Find battalion at screen position
	if not camera:
		return null

	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 1000

	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true

	var result := space_state.intersect_ray(query)
	if result:
		var hit_node: Node = result.collider
		# Walk up to find battalion
		while hit_node:
			if hit_node.has_method("select") and hit_node.has_method("get_regiment_count"):
				return hit_node
			hit_node = hit_node.get_parent()

	# Fallback: check distance to each battalion
	var world_pos := _get_mouse_world_position()
	var closest: Node3D = null
	var closest_dist := 5.0  # Max click distance in world units

	for battalion in battalions_container.get_children():
		var dist := Vector2(battalion.position.x, battalion.position.z).distance_to(
			Vector2(world_pos.x, world_pos.z)
		)
		if dist < closest_dist:
			closest_dist = dist
			closest = battalion

	return closest


func _get_settlement_at_screen_pos(screen_pos: Vector2) -> Resource:
	## Find settlement at screen position
	if not terrain:
		return null

	var world_pos := _get_mouse_world_position()

	# Check settlement markers for nearby settlements
	var click_radius := 4.0  # World units (40 pixels at 0.1 scale)

	if terrain.has_method("get") and "settlement_markers" in terrain:
		for marker in terrain.settlement_markers:
			if not is_instance_valid(marker):
				continue

			var dist := Vector2(marker.position.x, marker.position.z).distance_to(
				Vector2(world_pos.x, world_pos.z)
			)

			if dist < click_radius:
				# Found a marker - try to get the settlement data
				return _get_settlement_data_for_marker(marker)

	return null


func _get_settlement_data_for_marker(marker: Node3D) -> Resource:
	## Load settlement data for a marker
	# Get position in pixels
	var pixel_pos := Vector2(
		marker.position.x / PIXELS_TO_UNITS,
		marker.position.z / PIXELS_TO_UNITS
	)

	# Try to find matching settlement data
	var dir_path := "res://campaign_system/data/settlements/"

	if not DirAccess.dir_exists_absolute(dir_path):
		return null

	var dir := DirAccess.open(dir_path)
	if not dir:
		return null

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name.ends_with(".tres"):
			var settlement := load(dir_path + file_name)
			if settlement and "map_position" in settlement:
				var settlement_pos: Vector2 = settlement.map_position
				if settlement_pos.distance_to(pixel_pos) < 50:  # Within 50 pixels
					dir.list_dir_end()
					return settlement
		file_name = dir.get_next()

	dir.list_dir_end()
	return null


func _order_move(world_target: Vector3) -> void:
	if not selected_battalion:
		return

	# Convert to pixel coordinates
	var target_pixel := Vector2(
		world_target.x / PIXELS_TO_UNITS,
		world_target.z / PIXELS_TO_UNITS
	)

	# Clamp to map bounds
	target_pixel.x = clampf(target_pixel.x, 50, map_bounds_pixels.size.x - 50)
	target_pixel.y = clampf(target_pixel.y, 50, map_bounds_pixels.size.y - 50)

	var battalion_data = selected_battalion.battalion_data
	var start_pixel: Vector2
	if selected_battalion.has_method("get_pixel_position"):
		start_pixel = selected_battalion.get_pixel_position()
	else:
		start_pixel = Vector2(
			selected_battalion.position.x / PIXELS_TO_UNITS,
			selected_battalion.position.z / PIXELS_TO_UNITS
		)

	var total_distance := start_pixel.distance_to(target_pixel)
	var movement_cost := total_distance * MOVEMENT_COST_PER_PIXEL
	var current_mp: float = battalion_data.movement_points

	# Clear existing queued path
	if battalion_data.has_queued_path():
		battalion_data.clear_queued_path()
		CampaignSignals.path_interrupted.emit(selected_battalion)

	if current_mp >= movement_cost:
		# Can reach this turn
		selected_battalion.move_to(target_pixel)
	else:
		# Multi-turn journey
		var reachable_distance := current_mp / MOVEMENT_COST_PER_PIXEL
		var direction := (target_pixel - start_pixel).normalized()
		var this_turn_target := start_pixel + direction * reachable_distance

		battalion_data.set_queued_path([target_pixel])
		CampaignSignals.path_queued.emit(selected_battalion, [target_pixel])

		selected_battalion.move_to(this_turn_target)

	_hide_path_preview()


func _update_path_preview(world_target: Vector3) -> void:
	if not selected_battalion:
		return

	var target_pixel := Vector2(
		world_target.x / PIXELS_TO_UNITS,
		world_target.z / PIXELS_TO_UNITS
	)

	var battalion_data = selected_battalion.battalion_data
	var start_pixel := Vector2(
		selected_battalion.position.x / PIXELS_TO_UNITS,
		selected_battalion.position.z / PIXELS_TO_UNITS
	)

	var current_mp: float = battalion_data.movement_points
	var max_mp: float = battalion_data.max_movement_points

	var segments := _calculate_path_segments(start_pixel, target_pixel, current_mp, max_mp)
	_render_path_segments_3d(segments)


func _calculate_path_segments(start: Vector2, end: Vector2, current_mp: float, max_mp: float) -> Array:
	var segments: Array = []
	var total_distance := start.distance_to(end)

	if total_distance < 5.0:
		return segments

	var direction := (end - start).normalized()
	var remaining_distance := total_distance
	var segment_start := start
	var turn := 0
	var mp_available := current_mp

	while remaining_distance > 0.01:
		var reachable_distance := mp_available / MOVEMENT_COST_PER_PIXEL

		if reachable_distance >= remaining_distance:
			segments.append({
				"start": segment_start,
				"end": end,
				"turn": turn
			})
			break
		else:
			var segment_end := segment_start + direction * reachable_distance
			segments.append({
				"start": segment_start,
				"end": segment_end,
				"turn": turn
			})

			segment_start = segment_end
			remaining_distance -= reachable_distance
			turn += 1
			mp_available = max_mp

	return segments


func _render_path_segments_3d(segments: Array) -> void:
	# Clear existing path lines
	for line in path_lines:
		line.queue_free()
	path_lines.clear()

	for seg in segments:
		var start_pixel: Vector2 = seg.start
		var end_pixel: Vector2 = seg.end
		var turn: int = seg.turn

		# Convert to world coordinates
		var start_world := Vector3(start_pixel.x * PIXELS_TO_UNITS, 0, start_pixel.y * PIXELS_TO_UNITS)
		var end_world := Vector3(end_pixel.x * PIXELS_TO_UNITS, 0, end_pixel.y * PIXELS_TO_UNITS)

		# Elevate above terrain
		if terrain and terrain.has_method("get_height_at"):
			start_world.y = terrain.get_height_at(start_world) + 1.0
			end_world.y = terrain.get_height_at(end_world) + 1.0

		# Create line mesh
		var line_mesh := _create_line_mesh(start_world, end_world)
		var line_inst := MeshInstance3D.new()
		line_inst.mesh = line_mesh

		# Color by turn
		var mat := StandardMaterial3D.new()
		var turn_index := mini(turn, TURN_COLORS.size() - 1)
		mat.albedo_color = TURN_COLORS[turn_index]
		mat.emission_enabled = true
		mat.emission = TURN_COLORS[turn_index]
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line_inst.material_override = mat

		path_preview.add_child(line_inst)
		path_lines.append(line_inst)


func _create_line_mesh(start: Vector3, end: Vector3) -> ArrayMesh:
	## Create a thick line between two points
	var direction := (end - start).normalized()
	var length := start.distance_to(end)

	# Use a box mesh stretched along the path
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Calculate perpendicular for width
	var up := Vector3.UP
	var right := direction.cross(up).normalized() * 0.3

	var v0 := start + right
	var v1 := start - right
	var v2 := end + right
	var v3 := end - right

	# Raise slightly
	v0.y += 0.5
	v1.y += 0.5
	v2.y += 0.5
	v3.y += 0.5

	# Triangle 1
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)

	# Triangle 2
	st.add_vertex(v1)
	st.add_vertex(v3)
	st.add_vertex(v2)

	return st.commit()


func _hide_path_preview() -> void:
	for line in path_lines:
		line.queue_free()
	path_lines.clear()


func _create_range_mesh() -> void:
	range_mesh = MeshInstance3D.new()
	range_mesh.visible = false

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.8, 0.3, 0.3)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	range_mesh.material_override = mat

	add_child(range_mesh)


func _update_range_mesh() -> void:
	if not selected_battalion or not range_mesh:
		return

	var battalion_data = selected_battalion.battalion_data
	var current_mp: float = battalion_data.movement_points
	var radius_pixels := current_mp / MOVEMENT_COST_PER_PIXEL
	var radius_world := radius_pixels * PIXELS_TO_UNITS

	if radius_world < 1.0:
		range_mesh.visible = false
		return

	# Create circle mesh
	var torus := TorusMesh.new()
	torus.inner_radius = radius_world - 0.5
	torus.outer_radius = radius_world + 0.5
	range_mesh.mesh = torus

	range_mesh.position = selected_battalion.position
	range_mesh.position.y = 0.5
	range_mesh.rotation.x = -PI / 2
	range_mesh.visible = true


func _on_battalion_selected(battalion: Node3D) -> void:
	if selected_battalion and selected_battalion != battalion:
		selected_battalion.deselect()

	selected_battalion = battalion
	_update_range_mesh()


func _on_battalion_deselected() -> void:
	selected_battalion = null
	is_right_click_held = false
	_hide_path_preview()
	if range_mesh:
		range_mesh.visible = false


func _on_movement_points_changed(battalion: Node3D, _remaining: float) -> void:
	if battalion == selected_battalion:
		_update_range_mesh()


func _on_turn_started(_turn: int) -> void:
	_update_range_mesh()

	await get_tree().create_timer(0.3).timeout

	if not is_instance_valid(self):
		return

	# Continue queued movement
	for battalion in battalions_container.get_children():
		if is_instance_valid(battalion) and battalion.battalion_data and battalion.battalion_data.has_queued_path():
			_continue_queued_movement(battalion)


func _continue_queued_movement(battalion: Node3D) -> void:
	var battalion_data = battalion.battalion_data
	if not battalion_data.has_queued_path():
		return

	var waypoint: Vector2 = battalion_data.get_next_waypoint()
	var start_pixel := Vector2(
		battalion.position.x / PIXELS_TO_UNITS,
		battalion.position.z / PIXELS_TO_UNITS
	)

	var distance := start_pixel.distance_to(waypoint)
	var movement_cost := distance * MOVEMENT_COST_PER_PIXEL
	var current_mp: float = battalion_data.movement_points

	if current_mp >= movement_cost:
		battalion_data.consume_waypoint()
		battalion.move_to(waypoint)

		if not battalion_data.has_queued_path():
			CampaignSignals.path_completed.emit(battalion)
	else:
		var reachable_distance := current_mp / MOVEMENT_COST_PER_PIXEL
		var direction := (waypoint - start_pixel).normalized()
		var this_turn_target := start_pixel + direction * reachable_distance
		battalion.move_to(this_turn_target)


func _input(event: InputEvent) -> void:
	# Press B to start test battle
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		if selected_battalion:
			_start_test_battle()


func _start_test_battle() -> void:
	if not selected_battalion or not selected_battalion.battalion_data:
		return

	var enemy_regiments: Array = []

	var enemy_swords := RegimentData.new()
	enemy_swords.regiment_name = "Bandit Swordsmen"
	enemy_swords.unit_type = UnitType.Type.INFANTRY
	enemy_swords.max_soldiers = 30
	enemy_swords.current_soldiers = 30
	enemy_swords.attack = 8
	enemy_swords.defense = 8
	enemy_swords.faction_color = Color.RED
	enemy_regiments.append(enemy_swords)

	BattleTransition.start_battle_from_campaign(
		selected_battalion.battalion_data,
		enemy_regiments,
		"plains"
	)
