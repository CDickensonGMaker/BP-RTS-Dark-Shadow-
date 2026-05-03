## General - Hero unit with morale aura.
## Uses AIAutoload's spatial hash for efficient O(1) proximity queries.
##
## NOTE: Generals are registered as GENERAL type (not REGIMENT) in the spatial hash.
## This allows MoraleSystem to query for nearby generals for leadership bonuses.
class_name General
extends Regiment


@export var morale_aura_radius: float = 20.0
@export var friendly_aura_bonus: float = 20.0
@export var fear_aura_penalty: float = 10.0
@export var special_ability_name: String = ""


var aura_timer: float = 0.0
const AURA_TICK: float = 2.0


func _ready() -> void:
	super()
	# Re-register as GENERAL type (parent registered as REGIMENT)
	# The spatial hash's register() handles updates gracefully
	_register_as_general()


func _register_as_general() -> void:
	## Re-register this general with GENERAL entity type.
	## Overrides the REGIMENT type set by parent class.
	var my_faction: int = 0 if is_player_controlled else 1

	# Unregister first (parent registered as REGIMENT)
	AIAutoload.spatial_hash.unregister(self)

	# Register with GENERAL type for leadership queries
	AIAutoload.spatial_hash.register(
		self,
		global_position,
		SpatialHash.EntityType.GENERAL,
		my_faction
	)


func _physics_process(delta: float) -> void:
	super(delta)

	# Update position in spatial hash
	AIAutoload.spatial_hash.update_position(self, global_position)

	aura_timer += delta
	if aura_timer >= AURA_TICK:
		aura_timer = 0.0
		_apply_aura()


func _apply_aura() -> void:
	## Apply morale aura to nearby regiments using spatial hash queries.
	var my_faction: int = 0 if is_player_controlled else 1
	var enemy_faction: int = 1 if my_faction == 0 else 0

	# Query nearby friendly regiments for morale bonus
	var nearby_friendlies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		global_position,
		morale_aura_radius,
		my_faction
	)

	for regiment in nearby_friendlies:
		if regiment == self:
			continue
		if not is_instance_valid(regiment):
			continue
		MoraleSystem.apply_morale_bonus(regiment, friendly_aura_bonus * 0.1)

	# Query nearby enemy regiments for fear penalty
	var nearby_enemies: Array[Node] = AIAutoload.spatial_hash.query_regiments_in_radius(
		global_position,
		morale_aura_radius,
		enemy_faction
	)

	for regiment in nearby_enemies:
		if not is_instance_valid(regiment):
			continue
		MoraleSystem.apply_morale_damage(regiment, fear_aura_penalty * 0.1)
