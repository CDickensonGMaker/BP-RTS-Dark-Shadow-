class_name FlankingCalculator
extends RefCounted

## Calculates flanking angles and modifiers for combat.
## Extracted from CombatManager for single responsibility.

# Flanking combat modifiers
const FLANK_REAR_ANGLE: float = 135.0     # Angle threshold for rear attack (degrees)
const FLANK_SIDE_ANGLE: float = 45.0      # Angle threshold for flank attack (degrees)
const FLANK_REAR_DAMAGE_MULT: float = 2.0   # Rear attacks deal 2x damage
const FLANK_SIDE_DAMAGE_MULT: float = 1.5   # Side attacks deal 1.5x damage
const FLANK_REAR_MORALE_MULT: float = 1.5   # Rear attacks deal 50% more morale damage
const FLANK_SIDE_MORALE_MULT: float = 1.25  # Side attacks deal 25% more morale damage


## Calculate attack angle for flanking detection.
## Returns the angle (in degrees) between attacker's attack direction and defender's facing.
## 0 = frontal attack, 90 = side, 180 = rear
func calculate_attack_angle(attacker: Node, defender: Node) -> float:
	# Direction from defender to attacker (where attack is coming from)
	var attack_dir: Vector3 = (attacker.global_position - defender.global_position).normalized()
	attack_dir.y = 0  # Flatten to horizontal plane

	# Defender's facing direction
	var defender_facing: Vector3 = Vector3.FORWARD
	if defender.has_method("get_facing_direction"):
		defender_facing = defender.get_facing_direction()
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
func get_damage_modifier(attacker: Node, defender: Node) -> float:
	var angle: float = calculate_attack_angle(attacker, defender)

	if angle > FLANK_REAR_ANGLE:
		return FLANK_REAR_DAMAGE_MULT  # Rear attack
	elif angle > FLANK_SIDE_ANGLE:
		return FLANK_SIDE_DAMAGE_MULT  # Flank attack
	return 1.0  # Frontal attack


## Check if this is a frontal attack (for bracing check).
## Returns true if attacker is hitting defender from the front arc.
func is_frontal_attack(attacker: Node, defender: Node) -> bool:
	var angle: float = calculate_attack_angle(attacker, defender)
	return angle <= FLANK_SIDE_ANGLE  # Front is within side flank angle threshold


## Get flanking morale damage multiplier.
func get_morale_modifier(attacker: Node, defender: Node) -> float:
	var angle: float = calculate_attack_angle(attacker, defender)

	if angle > FLANK_REAR_ANGLE:
		return FLANK_REAR_MORALE_MULT
	elif angle > FLANK_SIDE_ANGLE:
		return FLANK_SIDE_MORALE_MULT
	return 1.0


## Check if attack is a flank attack (for UI/debug)
func is_flank_attack(attacker: Node, defender: Node) -> bool:
	var angle: float = calculate_attack_angle(attacker, defender)
	return angle > FLANK_SIDE_ANGLE


## Check if attack is a rear attack (for UI/debug)
func is_rear_attack(attacker: Node, defender: Node) -> bool:
	var angle: float = calculate_attack_angle(attacker, defender)
	return angle > FLANK_REAR_ANGLE
