class_name PveZone
extends ArenaBase
## A player's private PvE arena: bigger than the sandbox, with eight monster gates around the
## edge, a player start, and cover to fight around. Each player gets their own copy, built far
## from the others (see ZoneManager), so what happens in one zone never touches another.
## Build it at its final position: the navigation mesh is baked in _ready.

const SIZE := 70.0
const WALL_HEIGHT := 8.0
const PLAYER_START := Vector3(0.0, 0.1, 26.0)
## Ground positions (x, z) of the monster gates, relative to the zone center.
const GATES: Array[Vector2] = [
	Vector2(0.0, -31.5), Vector2(0.0, 31.5), Vector2(31.5, 0.0), Vector2(-31.5, 0.0),
	Vector2(26.0, -26.0), Vector2(-26.0, -26.0), Vector2(26.0, 26.0), Vector2(-26.0, 26.0),
]

var _gate_lights: Array[MeshInstance3D] = []


func _ready() -> void:
	_begin_geometry()
	_build_shell(SIZE, WALL_HEIGHT, Color(0.42, 0.38, 0.34), Color(0.32, 0.28, 0.28))
	_build_gates()
	_build_cover()
	_bake()


func gate_count() -> int:
	return GATES.size()


## World position of a gate (on the ground).
func gate_position(index: int) -> Vector3:
	var gate := GATES[index % GATES.size()]
	return to_global(Vector3(gate.x, 0.1, gate.y))


func player_start() -> ArenaBase.Spawn:
	return ArenaBase.Spawn.new(to_global(PLAYER_START), 0.0)


## True if a world position is inside this zone's walls.
func contains(point: Vector3) -> bool:
	var local := to_local(point)
	return absf(local.x) <= SIZE / 2.0 and absf(local.z) <= SIZE / 2.0 and local.y > -2.0 and local.y < WALL_HEIGHT + 4.0


## Makes a gate glow (monsters are about to come through) for a moment.
func pulse_gate(index: int, seconds: float) -> void:
	var light := _gate_lights[index % _gate_lights.size()]
	var material := light.material_override as StandardMaterial3D
	material.emission_energy_multiplier = 4.0
	var tween := light.create_tween()
	tween.tween_property(material, "emission_energy_multiplier", 0.8, seconds)


func _build_gates() -> void:
	for i in GATES.size():
		var gate := GATES[i]
		var along_x := absf(gate.x) < 1.0  # gates on the north and south walls face along z
		var size := Vector3(3.2, 3.4, 0.2) if along_x else Vector3(0.2, 3.4, 3.2)
		var center := Vector3(gate.x, 1.7, gate.y)
		if i >= 4:
			size = Vector3(2.4, 3.4, 0.2)
		var light := _decal(center, size, Color(1.0, 0.35, 0.15), "Gate%d" % i, 0.8)
		if i >= 4:
			light.rotation_degrees.y = 45.0
		_gate_lights.append(light)


func _build_cover() -> void:
	var stone := Color(0.55, 0.5, 0.45)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_block(Vector3(12.0 * sx, 2.5, 12.0 * sz), Vector3(2.0, 5.0, 2.0), Color(0.6, 0.45, 0.4), "Pillar")
	_block(Vector3(0.0, 0.6, 0.0), Vector3(6.0, 1.2, 6.0), stone, "CenterPlinth")
	_block(Vector3(-20.0, 0.65, -8.0), Vector3(6.0, 1.3, 0.8), stone, "LowWallA")
	_block(Vector3(20.0, 0.65, 8.0), Vector3(6.0, 1.3, 0.8), stone, "LowWallB")
	var angled_a := _block(Vector3(-8.0, 0.65, 20.0), Vector3(6.0, 1.3, 0.8), stone, "LowWallC")
	angled_a.rotation_degrees.y = 20.0
	var angled_b := _block(Vector3(10.0, 0.65, -18.0), Vector3(6.0, 1.3, 0.8), stone, "LowWallD")
	angled_b.rotation_degrees.y = -30.0
	_block(Vector3(-22.0, 1.5, 14.0), Vector3(3.0, 3.0, 3.0), Color(0.5, 0.55, 0.62), "CrateWest")
	_block(Vector3(22.0, 1.5, -14.0), Vector3(3.0, 3.0, 3.0), Color(0.5, 0.55, 0.62), "CrateEast")
