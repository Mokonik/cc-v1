class_name GrayboxArena
extends ArenaBase
## Procedural gray-box test arena for tuning movement and bots: a run lane with distance
## markers, a jump tower of 1.1 m steps, a ramp, pillars and cover. It is the sandbox now and
## becomes the PvP arena later. Geometry is built in code so layout tweaks are one-line diffs.

const SIZE := 60.0
const WALL_HEIGHT := 8.0

## Four spawns on the arena edges, each facing the center. Index 0 is the human's.
const SPAWN_POINTS: Array[Vector4] = [
	Vector4(0.0, 22.0, 0.0, 0.0),
	Vector4(0.0, -22.0, 0.0, PI),
	Vector4(-22.0, 0.0, 0.0, -PI / 2.0),
	Vector4(22.0, 0.0, 0.0, PI / 2.0),
]


func _ready() -> void:
	_begin_geometry()
	_build_shell(SIZE, WALL_HEIGHT, Color(0.36, 0.38, 0.42), Color(0.38, 0.4, 0.45))
	_build_run_lane()
	_build_jump_tower()
	_build_ramp()
	_build_cover()
	_bake()


## x and y of each Vector4 are the ground position (x, z); w is the facing yaw.
func get_spawn(index: int) -> Spawn:
	var point := SPAWN_POINTS[index % SPAWN_POINTS.size()]
	return Spawn.new(Vector3(point.x, 0.1, point.y), point.w)


## Stripes every 5 m from the human spawn so speed and distance are readable by eye.
func _build_run_lane() -> void:
	var z := SPAWN_POINTS[0].y
	while z > -25.0:
		var stripe := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(6.0, 0.02, 0.3)
		stripe.mesh = mesh
		stripe.material_override = _material(Color(0.95, 0.8, 0.2))
		stripe.position = Vector3(0.0, 0.011, z)
		stripe.name = "Stripe"
		_geometry.add_child(stripe)
		z -= 5.0


## Stacked 1.1 m steps: each is reachable with the default 1.2 m jump, the 2.2 m block is not from the ground.
func _build_jump_tower() -> void:
	var x := -14.0
	var steps := [
		[14.0, 0.5], [8.0, 0.9], [2.0, 1.1], [-2.0, 2.2], [-6.0, 3.3], [-10.0, 4.4],
	]
	for step in steps:
		var h: float = step[1]
		_block(Vector3(x, h / 2.0, step[0]), Vector3(4.0, h, 4.0), Color(0.3, 0.55, 0.75).lerp(Color(0.85, 0.5, 0.3), h / 4.4), "Step%.1f" % h)


func _build_ramp() -> void:
	var ramp := _block(Vector3(14.0, 1.0, 10.0), Vector3(6.0, 0.4, 10.0), Color(0.5, 0.7, 0.45), "Ramp")
	ramp.rotation_degrees.x = 20.0
	_block(Vector3(14.0, 1.425, 0.0), Vector3(6.0, 2.85, 10.6), Color(0.45, 0.62, 0.4), "RampTop")


func _build_cover() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_block(Vector3(6.0 * sx, 2.0, 6.0 * sz), Vector3(1.0, 4.0, 1.0), Color(0.7, 0.45, 0.4), "Pillar")
	_block(Vector3(6.0, 0.6, -14.0), Vector3(6.0, 1.2, 0.6), Color(0.75, 0.7, 0.5), "LowWall")
	var angled := _block(Vector3(-4.0, 0.6, -18.0), Vector3(6.0, 1.2, 0.6), Color(0.75, 0.7, 0.5), "LowWallAngled")
	angled.rotation_degrees.y = 30.0
	_block(Vector3(4.0, 1.5, -8.0), Vector3(4.0, 3.0, 4.0), Color(0.6, 0.5, 0.7), "CenterBlock")
