# Stores battle configuration from pre-battle screen.
# Passed to BattleManager to setup the battle with proper deployment.
class_name BattleSetupData
extends Resource


# Player forces
@export var player_battalion: Resource = null  # BattalionData
@export var core_regiments: Array = []         # First wave (max 8)
@export var reinforcement_regiments: Array = [] # Subsequent waves

# Enemy forces
@export var enemy_regiments: Array = []
@export var enemy_reinforcements: Array = []

# Battle context
@export var contract: Resource = null          # ContractData if contract battle
@export var battle_location: String = ""
@export var terrain_type: String = "plains"
@export var time_of_day: String = "day"
@export var weather: String = "clear"

# Difficulty
@export var difficulty: int = 2                # 1-5 stars
@export var is_scouted: bool = false           # Player has intel on enemy

# Map configuration
@export var map_seed: int = 0
@export var map_size: Vector2 = Vector2(200, 200)

# Deployment zones
@export var player_deployment_zone: Rect2 = Rect2(0, 0, 200, 50)
@export var enemy_deployment_zone: Rect2 = Rect2(0, 150, 200, 50)

# Win conditions
@export var objective_type: String = "defeat_enemy"  # defeat_enemy, hold_position, capture_point
@export var objective_position: Vector3 = Vector3.ZERO
@export var time_limit_seconds: float = -1.0  # -1 = no limit

# Rewards (from contract)
@export var gold_reward: int = 0
@export var bonus_conditions: Array = []  # [{condition, bonus}]


static func create_from_pre_battle(
	battalion: Resource,
	core: Array,
	reinforcements: Array,
	enemy_data: Dictionary,
	contract_data: Resource = null
) -> BattleSetupData:
	var setup := BattleSetupData.new()

	setup.player_battalion = battalion
	setup.core_regiments = core.duplicate()
	setup.reinforcement_regiments = reinforcements.duplicate()

	# Enemy data
	setup.enemy_regiments = enemy_data.get("regiments", [])
	setup.enemy_reinforcements = enemy_data.get("reinforcements", [])
	setup.is_scouted = enemy_data.get("scouted", false)
	setup.difficulty = enemy_data.get("difficulty", 2)

	# Location
	setup.battle_location = enemy_data.get("location", "Unknown")
	setup.terrain_type = enemy_data.get("terrain", "plains")
	setup.time_of_day = enemy_data.get("time_of_day", "day")
	setup.weather = enemy_data.get("weather", "clear")

	# Contract specifics
	if contract_data:
		setup.contract = contract_data
		setup.gold_reward = contract_data.completion_reward
		setup.bonus_conditions = contract_data.bonus_conditions
		setup.objective_type = _contract_type_to_objective(contract_data.contract_type)
		if contract_data.get("time_limit"):
			setup.time_limit_seconds = contract_data.time_limit

	# Generate map seed
	setup.map_seed = randi()

	return setup


static func _contract_type_to_objective(contract_type: int) -> String:
	match contract_type:
		0:  # BATTLE
			return "defeat_enemy"
		1:  # DEFENSE
			return "hold_position"
		2:  # ESCORT
			return "escort"
		3:  # RAID
			return "defeat_enemy"
		4:  # SIEGE
			return "capture_point"
		5:  # AMBUSH
			return "defeat_enemy"
		_:
			return "defeat_enemy"


func get_player_total_strength() -> int:
	var total := 0
	for regiment in core_regiments:
		total += _get_regiment_soldiers(regiment)
	for regiment in reinforcement_regiments:
		total += _get_regiment_soldiers(regiment)
	return total


func get_player_core_strength() -> int:
	var total := 0
	for regiment in core_regiments:
		total += _get_regiment_soldiers(regiment)
	return total


func get_enemy_total_strength() -> int:
	var total := 0
	for regiment in enemy_regiments:
		total += _get_regiment_soldiers(regiment)
	for regiment in enemy_reinforcements:
		total += _get_regiment_soldiers(regiment)
	return total


func _get_regiment_soldiers(regiment: Resource) -> int:
	if regiment.get("current_soldiers"):
		return regiment.current_soldiers
	elif regiment.has_meta("current_soldiers"):
		return regiment.get_meta("current_soldiers")
	return 0


func get_strength_ratio() -> float:
	var player := get_player_total_strength()
	var enemy := get_enemy_total_strength()
	if enemy == 0:
		return 999.0
	return float(player) / float(enemy)


func get_summary() -> Dictionary:
	return {
		"location": battle_location,
		"terrain": terrain_type,
		"weather": weather,
		"time_of_day": time_of_day,
		"player_strength": get_player_total_strength(),
		"player_core": get_player_core_strength(),
		"player_reinforcements": reinforcement_regiments.size(),
		"enemy_strength": get_enemy_total_strength(),
		"scouted": is_scouted,
		"difficulty": difficulty,
		"objective": objective_type,
		"has_time_limit": time_limit_seconds > 0,
		"reward": gold_reward
	}
