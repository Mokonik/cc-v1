class_name GrayboxArena
extends Node3D
## Procedural gray-box test arena for tuning movement and bots: a run lane with distance
## markers, a jump tower of 1.1 m steps, a ramp, pillars and cover.
## Geometry is built in code so layout tweaks are one-line diffs. All solid geometry lives
## under a NavigationRegion3D that is baked at startup, so bots can path around it.

const SIZE := 60.0
const WALL_HEIGHT := 8.0

class Spawn extends RefCounted:
	var position := Vector3.ZERO
	var yaw := 0.0

	func _init(p_position: Vector3, p_yaw: float) -> void:
		position = p_position
		yaw = p_yaw

## Four spawns on the arena edges, each facing the center. Index 0 is the human's.
const SPAWN_POINTS: Array[Vector4] = [
	Vector4(0.0, 22.0, 0.0, 0.0),
	Vector4(0.0, -22.0, 0.0, PI),
	Vector4(-22.0, 0.0, 0.0, -PI / 2.0),
	Vector4(22.0, 0.0, 0.0, PI / 2.0),
]

var _geometry: NavigationRegion3D
var _materials: Dictionary = {}
var _grid_texture: ImageTexture


func _ready() -> void:
	_geometry = NavigationRegion3D.new()
	_geometry.name = "Geometry"
	_geometry.navigation_mesh = _make_navigation_mesh()
	add_child(_geometry)

	_build_shell()
	_build_run_lane()
	_build_jump_tower()
	_build_ramp()
	_build_cover()
	_geometry.bake_navigation_mesh(false)


## x and y of each Vector4 are the ground position (x, z); w is the facing yaw.
func get_spawn(index: int) -> Spawn:
	var point := SPAWN_POINTS[index % SPAWN_POINTS.size()]
	return Spawn.new(Vector3(point.x, 0.1, point.y), point.w)


func get_navigation_mesh() -> NavigationMesh:
	return _geometry.navigation_mesh


func _make_navigation_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	# Voxel sizes match the default navigation map (0.25) so regions merge without warnings.
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.5
	mesh.agent_height = 2.0
	# One voxel: bots do not path over ledges the player could not walk up without jumping.
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 45.0
	return mesh


func _build_shell() -> void:
	_block(Vector3(0.0, -0.5, 0.0), Vector3(SIZE, 1.0, SIZE), Color(0.36, 0.38, 0.42), "Floor")
	var half := SIZE / 2.0
	var wall_color := Color(0.38, 0.4, 0.45)
	_block(Vector3(0.0, WALL_HEIGHT / 2.0, -half - 0.5), Vector3(SIZE + 2.0, WALL_HEIGHT, 1.0), wall_color, "WallN")
	_block(Vector3(0.0, WALL_HEIGHT / 2.0, half + 0.5), Vector3(SIZE + 2.0, WALL_HEIGHT, 1.0), wall_color, "WallS")
	_block(Vector3(-half - 0.5, WALL_HEIGHT / 2.0, 0.0), Vector3(1.0, WALL_HEIGHT, SIZE), wall_color, "WallW")
	_block(Vector3(half + 0.5, WALL_HEIGHT / 2.0, 0.0), Vector3(1.0, WALL_HEIGHT, SIZE), wall_color, "WallE")


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


func _block(center: Vector3, size: Vector3, color: Color, block_name: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = block_name
	body.position = center

	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _material(color)
	body.add_child(mesh_instance)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)

	_geometry.add_child(body)
	return body


func _material(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = _get_grid_texture()
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3(0.5, 0.5, 0.5)
	material.roughness = 1.0
	_materials[color] = material
	return material


## A light 2 m checker so scale and speed read clearly on every surface.
func _get_grid_texture() -> ImageTexture:
	if _grid_texture == null:
		var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y in 64:
			for x in 64:
				var checker := ((x / 32) + (y / 32)) % 2 == 0
				image.set_pixel(x, y, Color(1, 1, 1) if checker else Color(0.72, 0.72, 0.72))
		_grid_texture = ImageTexture.create_from_image(image)
	return _grid_texture
