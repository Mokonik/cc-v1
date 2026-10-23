class_name Monster
extends Combatant
## The physical body of a monster: a capsule that falls, walks and collides with the world.
## It makes no decisions; MonsterBrain decides and MonsterSystem moves it with simulate().
## Monsters collide only with the world (not each other, not players); players are still
## blocked by them. MonsterBrain steers around neighbors so they do not stack.

const GRAVITY := 25.0
const TURN_SPEED := TAU * 1.2
const DESPAWN_SECONDS := 1.6

var def: MonsterDef
## True when the last move was stopped by a wall (a charging brute uses it to stun itself).
var hit_wall := false

var _mesh: MeshInstance3D
var _visor: MeshInstance3D
var _material: StandardMaterial3D
var _flash := 0.0
var _flash_color := Color.WHITE
var _glow := 0.0
var _glow_color := Color.WHITE
var _despawn := -1.0


func setup(p_def: MonsterDef) -> void:
	def = p_def
	display_name = def.display_name
	collision_layer = CombatLayers.MONSTER
	collision_mask = CombatLayers.WORLD
	floor_snap_length = 0.4

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = def.radius
	capsule.height = def.height
	shape.shape = capsule
	shape.position.y = def.height * 0.5
	add_child(shape)

	_material = StandardMaterial3D.new()
	_material.albedo_color = def.color
	_material.roughness = 0.85
	_mesh = MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = def.radius
	capsule_mesh.height = def.height
	_mesh.mesh = capsule_mesh
	_mesh.material_override = _material
	_mesh.position.y = def.height * 0.5
	add_child(_mesh)

	_visor = MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(def.radius * 1.3, def.radius * 0.35, def.radius * 0.5)
	_visor.mesh = visor_mesh
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color(0.9, 0.2, 0.15)
	visor_material.emission_enabled = true
	visor_material.emission = Color(1.0, 0.2, 0.1)
	_visor.material_override = visor_material
	_visor.position = Vector3(0.0, def.height * 0.78, -def.radius * 0.85)
	add_child(_visor)


func eye_position() -> Vector3:
	return global_position + Vector3(0.0, def.height * 0.8, 0.0)


func chest_position() -> Vector3:
	return global_position + Vector3(0.0, def.height * 0.6, 0.0)


func center_position() -> Vector3:
	return global_position + Vector3(0.0, def.height * 0.5, 0.0)


func body_radius() -> float:
	return def.radius


## Turns toward yaw at a limited rate.
func face(yaw: float, dt: float) -> void:
	var step := TURN_SPEED * dt
	rotation.y += clampf(angle_difference(rotation.y, yaw), -step, step)


## Moves with the given horizontal velocity for one physics step.
func simulate(horizontal: Vector3, dt: float) -> void:
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = maxf(velocity.y, 0.0)
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
	hit_wall = is_on_wall() and horizontal.length_squared() > 0.01


func set_alive(value: bool) -> void:
	if alive == value:
		return
	alive = value
	collision_layer = CombatLayers.MONSTER if alive else 0
	if not alive:
		_despawn = DESPAWN_SECONDS
		var tween := create_tween().set_parallel(true)
		tween.tween_property(_mesh, "rotation:x", -PI / 2.0, 0.3)
		tween.tween_property(_mesh, "position:y", def.radius, 0.3)


## A brief white (or colored) hit flash.
func flash(color := Color.WHITE, seconds := 0.08) -> void:
	_flash = seconds
	_flash_color = color


## A glow while winding up an attack, so players can read it.
func glow(color: Color, seconds: float) -> void:
	_glow = seconds
	_glow_color = color


func _process(delta: float) -> void:
	if _despawn >= 0.0:
		_despawn -= delta
		if _despawn < 0.0:
			queue_free()
			return
	var emission := Color.BLACK
	if _flash > 0.0:
		_flash -= delta
		emission = _flash_color * 1.5
	elif _glow > 0.0:
		_glow -= delta
		emission = _glow_color * (0.8 + 0.6 * sin(Time.get_ticks_msec() * 0.03))
	_material.emission_enabled = emission != Color.BLACK
	_material.emission = emission
