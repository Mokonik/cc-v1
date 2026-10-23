class_name ArenaBase
extends Node3D
## What every gray-box arena shares: a NavigationRegion3D that holds all solid geometry and is
## baked once the layout is built, block and material helpers (a world-scale checker so size
## and speed read on every surface), and a perimeter shell of floor and walls.
## Subclasses build their own layout in _ready: call _begin_geometry(), add blocks, then _bake().

class Spawn extends RefCounted:
	var position := Vector3.ZERO
	var yaw := 0.0

	func _init(p_position: Vector3, p_yaw: float) -> void:
		position = p_position
		yaw = p_yaw

var _geometry: NavigationRegion3D
var _materials: Dictionary = {}
var _grid_texture: ImageTexture


func get_navigation_mesh() -> NavigationMesh:
	return _geometry.navigation_mesh


func _begin_geometry() -> void:
	_geometry = NavigationRegion3D.new()
	_geometry.name = "Geometry"
	_geometry.navigation_mesh = _make_navigation_mesh()
	add_child(_geometry)


func _bake() -> void:
	_geometry.bake_navigation_mesh(false)


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


## A floor with its top at y = 0 and four walls around it.
func _build_shell(size: float, wall_height: float, floor_color: Color, wall_color: Color) -> void:
	_block(Vector3(0.0, -0.5, 0.0), Vector3(size, 1.0, size), floor_color, "Floor")
	var half := size / 2.0
	_block(Vector3(0.0, wall_height / 2.0, -half - 0.5), Vector3(size + 2.0, wall_height, 1.0), wall_color, "WallN")
	_block(Vector3(0.0, wall_height / 2.0, half + 0.5), Vector3(size + 2.0, wall_height, 1.0), wall_color, "WallS")
	_block(Vector3(-half - 0.5, wall_height / 2.0, 0.0), Vector3(1.0, wall_height, size), wall_color, "WallW")
	_block(Vector3(half + 0.5, wall_height / 2.0, 0.0), Vector3(1.0, wall_height, size), wall_color, "WallE")


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


## A box you can see but not touch (markers, stripes, glows). No collision, no navmesh effect.
func _decal(center: Vector3, size: Vector3, color: Color, decal_name: String, glow := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = decal_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	if glow > 0.0:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
		instance.material_override = material
	else:
		instance.material_override = _material(color)
	instance.position = center
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_geometry.add_child(instance)
	return instance


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
