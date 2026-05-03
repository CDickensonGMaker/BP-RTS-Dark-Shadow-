class_name UnitType
extends Resource



enum Type {
	INFANTRY,
	CAVALRY,
	RANGED,
	ARTILLERY,
	GENERAL
}


var base_health: Dictionary = {
	Type.INFANTRY: 100,
	Type.CAVALRY: 80,
	Type.RANGED: 60,
	Type.ARTILLERY: 40,
	Type.GENERAL: 150
}


var base_damage: Dictionary = {
	Type.INFANTRY: 15,
	Type.CAVALRY: 25,
	Type.RANGED: 10,
	Type.ARTILLERY: 50,
	Type.GENERAL: 30
}


var base_armor: Dictionary = {
	Type.INFANTRY: 10,
	Type.CAVALRY: 5,
	Type.RANGED: 2,
	Type.ARTILLERY: 0,
	Type.GENERAL: 15
}
