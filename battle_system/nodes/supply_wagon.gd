# SupplyWagon - Provides area-based resupply for regiments
# Inspired by Spring 1944's supply depot mechanics
# Units within range automatically resupply arrows/mana over time

class_name SupplyWagon
extends Node3D


## Supply range in world units (default: 50)
@export var supply_range: float = 50.0

## Arrows resupplied per second per regiment
@export var arrow_resupply_rate: float = 5.0

## Mana resupplied per second per regiment (for mage units)
@export var mana_resupply_rate: float = 2.0

## Whether this wagon provides arrows
@export var provides_arrows: bool = true

## Whether this wagon provides mana
@export var provides_mana: bool = false

## Team/faction (0 = player, 1 = enemy)
@export var faction: int = 0

## Visual color for the supply radius overlay
@export var supply_color: Color = Color(0.2, 0.8, 0.2, 0.3)

# Internal state
var _resupply_timer: float = 0.0
const RESUPPLY_INTERVAL: float = 1.0  # Check every second

# Visual components
var _mesh: MeshInstance3D = null
var _radius_overlay: MeshInstance3D = null


func _ready() -> void:
	add_to_group("supply_wagons")

	# Create placeholder cube mesh
	_create_placeholder_mesh()

	# Create supply radius visualization
	_create_radius_overlay()

	# Register with supply system
	if SupplySystem:
		SupplySystem.register_wagon(self)


func _create_placeholder_mesh() -> void:
	## Create a simple cube as placeholder for the wagon model.
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.0, 2.0, 5.0)  # Wagon-ish proportions
	_mesh.mesh = box

	# Create material
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.35, 0.2)  # Brown wood color
	mat.roughness = 0.8
	_mesh.material_override = mat

	# Position slightly above ground
	_mesh.position.y = 1.0
	add_child(_mesh)


func _create_radius_overlay() -> void:
	## Create a circle mesh to show supply range.
	_radius_overlay = MeshInstance3D.new()

	# Create circle mesh
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var segments := 48
	for i in range(segments + 1):
		var angle := float(i) / float(segments) * TAU
		var x := cos(angle) * supply_range
		var z := sin(angle) * supply_range
		immediate.surface_add_vertex(Vector3(x, 0.2, z))

	immediate.surface_end()
	_radius_overlay.mesh = immediate

	# Material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = supply_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_radius_overlay.material_override = mat

	# Only show when selected or hovered (controlled by SupplySystem)
	_radius_overlay.visible = false
	add_child(_radius_overlay)


func _process(delta: float) -> void:
	_resupply_timer += delta

	if _resupply_timer >= RESUPPLY_INTERVAL:
		_resupply_timer = 0.0
		_do_resupply(RESUPPLY_INTERVAL)


func _do_resupply(delta_time: float) -> void:
	## Resupply all friendly regiments within range.
	var regiments_in_range := _find_regiments_in_range()

	for regiment in regiments_in_range:
		if not is_instance_valid(regiment):
			continue

		# Resupply arrows
		if provides_arrows and regiment.current_ammo < regiment.data.max_ammo:
			var arrows_to_add: int = int(arrow_resupply_rate * delta_time)
			regiment.current_ammo = mini(regiment.current_ammo + arrows_to_add, regiment.data.max_ammo)
			BattleSignals.unit_resupplied.emit(regiment, "arrows", arrows_to_add)

		# Resupply mana (if regiment has mana - check spell caster)
		if provides_mana and regiment.abilities:
			# Mana resupply handled through abilities system
			pass  # TODO: Add mana to abilities when spell system tracks mana


func _find_regiments_in_range() -> Array[Regiment]:
	## Find all friendly regiments within supply range.
	var result: Array[Regiment] = []

	# Use spatial hash for efficient query
	if AIAutoload and AIAutoload.spatial_hash:
		var nearby: Array = AIAutoload.spatial_hash.query_radius(global_position, supply_range)
		for entity in nearby:
			if entity is Regiment:
				var regiment: Regiment = entity
				# Check faction match (player wagon supplies player units)
				var is_friendly: bool = (faction == 0 and regiment.is_player_controlled) or \
										(faction == 1 and not regiment.is_player_controlled)
				if is_friendly and regiment.state != Regiment.State.DEAD:
					result.append(regiment)
	else:
		# Fallback to group iteration if no spatial hash
		for regiment in get_tree().get_nodes_in_group("all_regiments"):
			if regiment is Regiment:
				var dist: float = global_position.distance_to(regiment.global_position)
				if dist <= supply_range:
					var is_friendly: bool = (faction == 0 and regiment.is_player_controlled) or \
											(faction == 1 and not regiment.is_player_controlled)
					if is_friendly and regiment.state != Regiment.State.DEAD:
						result.append(regiment)

	return result


func show_radius_overlay(visible: bool) -> void:
	## Show or hide the supply radius overlay.
	if _radius_overlay:
		_radius_overlay.visible = visible


func get_supply_range() -> float:
	return supply_range


func is_in_range(position: Vector3) -> bool:
	return global_position.distance_to(position) <= supply_range


func _exit_tree() -> void:
	if SupplySystem:
		SupplySystem.unregister_wagon(self)
