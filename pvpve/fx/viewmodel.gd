class_name Viewmodel
extends Node3D
## The first-person weapon in your hand: gray-box meshes with procedural kick, sway, bob,
## swing, bow draw and reload animations. Parented to the local player's camera.
## Presentation only; it is told what happened by CombatView.

const REST := Vector3(0.27, -0.25, -0.52)
const SWING_SECONDS := 0.5

var player: Player

var _models: Dictionary = {}
var _muzzles: Dictionary = {}
var _current: StringName = &""

var _kick := 0.0
var _swing := -1.0
var _draw := 0.0
var _reload := 0.0
var _reloading := false
var _freeze := 0.0
var _flash_time := 0.0
var _flash: Node3D
var _flash_light: OmniLight3D
var _bob_phase := 0.0
var _sway := Vector2.ZERO
var _last_view := Vector2.ZERO


func _ready() -> void:
	position = REST
	_models[&"pistol"] = _build_pistol()
	_models[&"sword"] = _build_sword()
	_models[&"bow"] = _build_bow()
	_models[&"orb"] = _build_orb()
	for weapon_id: StringName in _models:
		var model: Node3D = _models[weapon_id]
		model.visible = false
		add_child(model)
	_flash = Node3D.new()
	_flash.visible = false
	var flash_mesh := MeshInstance3D.new()
	var quad := SphereMesh.new()
	quad.radius = 0.05
	quad.height = 0.1
	flash_mesh.mesh = quad
	flash_mesh.material_override = _unshaded(Color(1.0, 0.85, 0.4))
	flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.add_child(flash_mesh)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.8, 0.5)
	_flash_light.light_energy = 2.0
	_flash_light.omni_range = 5.0
	_flash.add_child(_flash_light)
	add_child(_flash)


func show_weapon(weapon_id: StringName) -> void:
	_current = weapon_id
	for id: StringName in _models:
		(_models[id] as Node3D).visible = id == weapon_id
	_kick = 0.12  # a small dip as the weapon comes up
	_reloading = false
	_draw = 0.0


## Camera-relative position where shots visually leave the weapon.
func muzzle_global_position() -> Vector3:
	var muzzle: Node3D = _muzzles.get(_current)
	return muzzle.global_position if muzzle != null else global_position


func fire(kick: float, flash: bool) -> void:
	_kick = maxf(_kick, kick)
	if flash:
		var muzzle: Node3D = _muzzles.get(_current)
		if muzzle != null:
			_flash.global_position = muzzle.global_position
		_flash.visible = true
		_flash_time = 0.045


func swing() -> void:
	_swing = 0.0


func set_draw(progress: float) -> void:
	_draw = clampf(progress, 0.0, 1.0)


func set_reloading(value: bool) -> void:
	_reloading = value


## Freezes the animation for a moment so a melee hit feels heavy.
func hit_stop(seconds: float) -> void:
	_freeze = maxf(_freeze, seconds)


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time -= delta
		if _flash_time <= 0.0:
			_flash.visible = false
	if _freeze > 0.0:
		_freeze -= delta
		return
	if player == null:
		return

	var speed := player.get_horizontal_speed()
	var moving := player.is_on_floor() and speed > 0.5
	if moving:
		_bob_phase += speed * 1.5 * delta
	var bob := Vector3(cos(_bob_phase) * 0.006, absf(sin(_bob_phase)) * 0.008, 0.0) if moving else Vector3.ZERO

	var view := Vector2(player.rotation.y, player.head.rotation.x)
	var look_delta := Vector2(angle_difference(_last_view.x, view.x), view.y - _last_view.y)
	_last_view = view
	var sway_target := Vector2(clampf(look_delta.x * 1.2, -0.05, 0.05), clampf(-look_delta.y * 1.2, -0.04, 0.04))
	_sway = _sway.lerp(sway_target, 1.0 - exp(-12.0 * delta))

	_kick = lerpf(_kick, 0.0, 1.0 - exp(-14.0 * delta))
	_reload = move_toward(_reload, 1.0 if _reloading else 0.0, delta * 5.0)

	var pose_position := REST + bob + Vector3(_sway.x, _sway.y, 0.0) + Vector3(0.0, 0.0, _kick)
	var pose_rotation := Vector3(_kick * 2.0, 0.0, 0.0)
	pose_position.y -= 0.16 * _reload
	pose_rotation.x -= 0.5 * _reload

	if _current == &"bow":
		pose_position.z += 0.07 * _draw
		pose_position.x -= 0.05 * _draw
		pose_rotation.z += 0.12 * _draw
	if _swing >= 0.0:
		_swing += delta / SWING_SECONDS
		var arc := _swing_pose(_swing)
		pose_position += arc[0]
		pose_rotation += arc[1]
		if _swing >= 1.0:
			_swing = -1.0
	position = pose_position
	rotation = pose_rotation


## [position offset, rotation offset] for the sword swing: lift back, slash across, recover.
func _swing_pose(t: float) -> Array[Vector3]:
	var lift := smoothstep(0.0, 0.45, t)
	var slash := smoothstep(0.45, 0.65, t)
	var recover := smoothstep(0.7, 1.0, t)
	var amount := lift * (1.0 - slash) * (1.0 - recover)
	var strike := slash * (1.0 - recover)
	var offset := Vector3(-0.12 * strike + 0.05 * amount, 0.1 * amount - 0.08 * strike, -0.1 * strike)
	var turn := Vector3(0.9 * amount - 1.1 * strike, 0.7 * strike - 0.2 * amount, -0.6 * amount + 0.9 * strike)
	return [offset, turn]


# ---- gray-box models --------------------------------------------------------

func _unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _lit(color: Color, emission := Color.BLACK) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
	return material


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _lit(color)
	mesh_instance.position = at
	mesh_instance.rotation_degrees = rot
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)
	return mesh_instance


func _build_pistol() -> Node3D:
	var root := Node3D.new()
	_box(root, Vector3(0.055, 0.06, 0.28), Vector3(0.0, 0.0, -0.06), Color(0.22, 0.24, 0.28))
	_box(root, Vector3(0.05, 0.12, 0.07), Vector3(0.0, -0.08, 0.05), Color(0.14, 0.15, 0.18), Vector3(12.0, 0.0, 0.0))
	_box(root, Vector3(0.02, 0.02, 0.05), Vector3(0.0, 0.04, -0.17), Color(0.8, 0.8, 0.85))
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0.0, 0.0, -0.22)
	root.add_child(muzzle)
	_muzzles[&"pistol"] = muzzle
	return root


func _build_sword() -> Node3D:
	var root := Node3D.new()
	root.rotation_degrees = Vector3(-14.0, 8.0, 0.0)
	_box(root, Vector3(0.04, 0.012, 0.62), Vector3(0.0, 0.0, -0.42), Color(0.75, 0.78, 0.85))
	_box(root, Vector3(0.2, 0.03, 0.04), Vector3(0.0, 0.0, -0.1), Color(0.55, 0.4, 0.2))
	_box(root, Vector3(0.035, 0.035, 0.16), Vector3(0.0, 0.0, 0.0), Color(0.3, 0.2, 0.12))
	return root


func _build_bow() -> Node3D:
	var root := Node3D.new()
	root.rotation_degrees = Vector3(0.0, -6.0, 0.0)
	var wood := Color(0.5, 0.33, 0.18)
	_box(root, Vector3(0.025, 0.14, 0.03), Vector3(0.0, 0.0, 0.0), wood)
	_box(root, Vector3(0.02, 0.26, 0.026), Vector3(0.0, 0.18, 0.03), wood, Vector3(-18.0, 0.0, 0.0))
	_box(root, Vector3(0.02, 0.26, 0.026), Vector3(0.0, -0.18, 0.03), wood, Vector3(18.0, 0.0, 0.0))
	_box(root, Vector3(0.004, 0.62, 0.004), Vector3(0.0, 0.0, 0.1), Color(0.9, 0.9, 0.85))
	_box(root, Vector3(0.012, 0.012, 0.5), Vector3(0.0, 0.0, -0.18), Color(0.8, 0.7, 0.5))
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0.0, 0.0, -0.45)
	root.add_child(muzzle)
	_muzzles[&"bow"] = muzzle
	return root


func _build_orb() -> Node3D:
	var root := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.055
	sphere.height = 0.11
	mesh_instance.mesh = sphere
	mesh_instance.material_override = _lit(Color(1.0, 0.45, 0.1), Color(1.0, 0.4, 0.05) * 0.9)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh_instance)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 0.8
	light.omni_range = 3.0
	root.add_child(light)
	_box(root, Vector3(0.14, 0.008, 0.008), Vector3(0.0, -0.07, 0.0), Color(0.3, 0.2, 0.15))
	root.position = Vector3(-0.04, 0.02, -0.08)
	var muzzle := Node3D.new()
	muzzle.position = Vector3(0.0, 0.0, -0.1)
	root.add_child(muzzle)
	_muzzles[&"orb"] = muzzle
	return root
