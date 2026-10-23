class_name GrayboxArena
extends Node3D
## Procedural gray-box test arena for tuning movement: a run lane with distance
## markers, a jump tower of 1.1 m steps, a ramp, pillars and cover.
## Geometry is built in code so layout tweaks are one-line diffs.

const SIZE := 60.0
const WALL_HEIGHT := 8.0

var spawn_position := Vector3(0.0, 0.1, 22.0)
var spawn_yaw := 0.0

var _materials: Dictionary = {}
var _grid_texture: ImageTexture


func _ready() -> void:
	_build_shell()
	_build_run_lane()
	_build_jump_tower()
	_build_ramp()
	_build_cover()


func _build_shell() -> void:
	_block(Vector3(0.0, -0.5, 0.0), Vector3(SIZE, 1.0, SIZE), Color(0.36, 0.38, 0.42), "Floor")
	var half := SIZE / 2.0
	var wall_color := Color(0.38, 0.4, 0.45)
	_block(Vector3(0.0, WALL_HEIGHT / 2.0, -half - 0.5), Vector3(SIZE + 2.0, WALL_HEIGHT, 1.0), wall_color, "WallN")
	_block(Vector3(0.0, WALL_HEIGHT / 2.0, half + 0.5), Vector3(SIZE + 2.0, WALL_HEIGHT, 1.0), wall_color, "WallS")
	_block(Vector3(-half - 0.5, WALL_HEIGHT / 2.0, 0.0), Vector3(1.0, WALL_HEIGHT, SIZE), wall_color, "WallW")
	_block(Vector3(half + 0.5, WALL_HEIGHT / 2.0, 0.0), Vector3(1.0, WALL_HEIGHT, SIZE), wall_color, "WallE")


## Stripes every 5 m from the spawn so speed and distance are readable by eye.
func _build_run_lane() -> void:
	var z := spawn_position.z
	while z > -25.0:
		var stripe := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(6.0, 0.02, 0.3)
		stripe.mesh = mesh
		stripe.material_override = _material(Color(0.95, 0.8, 0.2))
		stripe.position = Vector3(0.0, 0.011, z)
		stripe.name = "Stripe"
		add_child(stripe)
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

	add_child(body)
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
