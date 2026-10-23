class_name Player
extends CharacterBody3D
## First-person character controller.
## Tuning lives in MovementConfig; player-facing options (sensitivity, FOV) in PlayerSettings.
## The player is driven by PlayerCommands from an InputSource (keyboard, bot, later network);
## simulate() is pure movement so it can be tested headless and replayed.

const EYE_HEIGHT := 1.6

signal jumped
signal landed(impact_speed: float)

@export var config: MovementConfig
## Without an input source the player is a puppet: it only moves when simulate() is called.
@export var input_source: InputSource

var player_id := 0
var display_name := ""

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var body: MeshInstance3D = $Body
@onready var visor: MeshInstance3D = $Head/Visor

var _coyote := 0.0
var _jump_buffer := 0.0
var _jump_active := false
var _was_on_floor := false

var _look_yaw := 0.0
var _look_pitch := 0.0
var _yaw := 0.0
var _pitch := 0.0

var _bob_phase := 0.0
var _bob_amount := 0.0
var _land_offset := 0.0
var _head_rest := Vector3.ZERO


func _ready() -> void:
	if config == null:
		config = MovementConfig.new()
	_head_rest = head.position
	set_look(rotation.y, 0.0)
	camera.fov = PlayerSettings.fov
	var local_view := input_source != null and input_source.is_local_view()
	body.visible = not local_view
	visor.visible = not local_view
	if local_view:
		camera.make_current()


func _physics_process(delta: float) -> void:
	if input_source == null:
		return
	apply_command(input_source.poll(delta), delta)


func _process(delta: float) -> void:
	_update_look(delta)
	_update_camera(delta)


func apply_command(command: PlayerCommand, delta: float) -> void:
	_look_yaw = command.yaw
	_look_pitch = clampf(command.pitch, -config.max_pitch, config.max_pitch)
	simulate(command.move, command.jump_pressed, command.jump_held, command.sprint, delta)


## Sets view direction immediately (spawning, teleports, tests).
func set_look(yaw: float, pitch: float) -> void:
	_look_yaw = yaw
	_look_pitch = clampf(pitch, -config.max_pitch, config.max_pitch)
	_yaw = _look_yaw
	_pitch = _look_pitch
	rotation.y = _yaw
	head.rotation.x = _pitch
	if input_source != null:
		input_source.set_view(_look_yaw, _look_pitch)


func set_body_color(color: Color) -> void:
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = color
	body.material_override = body_material
	var visor_material := StandardMaterial3D.new()
	visor_material.albedo_color = Color(0.08, 0.1, 0.12)
	visor.material_override = visor_material


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Advances movement by one physics step. move.y < 0 is forward, matching PlayerCommand.move.
func simulate(move: Vector2, jump_pressed: bool, jump_held: bool, sprint: bool, delta: float) -> void:
	move = move.limit_length(1.0)
	var on_floor := is_on_floor()

	_coyote = config.coyote_time if on_floor else maxf(_coyote - delta, 0.0)
	_jump_buffer = config.jump_buffer_time if jump_pressed else maxf(_jump_buffer - delta, 0.0)

	if on_floor:
		_jump_active = false
		velocity.y = maxf(velocity.y, 0.0)
	else:
		var g := config.gravity
		if velocity.y < 0.0:
			g *= config.fall_gravity_multiplier
		velocity.y -= g * delta

	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = config.jump_velocity()
		_jump_buffer = 0.0
		_coyote = 0.0
		_jump_active = true
		jumped.emit()
	elif _jump_active and not jump_held and velocity.y > 0.0:
		velocity.y *= config.jump_cut
		_jump_active = false

	var wish_dir := (global_transform.basis * Vector3(move.x, 0.0, move.y)).normalized()
	var top_speed := config.sprint_speed if (sprint and move.y < -0.1) else config.walk_speed
	var wish_speed := top_speed * move.length()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if on_floor and velocity.y <= 0.0:
		horizontal = _apply_friction(horizontal, delta)
		horizontal = _accelerate(horizontal, wish_dir, wish_speed, config.ground_accel, delta)
	else:
		horizontal = _accelerate(horizontal, wish_dir, wish_speed, config.air_accel, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var vy_before := velocity.y
	move_and_slide()
	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor and vy_before < 0.0:
		landed.emit(-vy_before)
		_land_offset = minf(-vy_before * config.land_dip_per_speed, config.land_dip_max)
	_was_on_floor = now_on_floor


func _apply_friction(horizontal: Vector3, delta: float) -> Vector3:
	var speed := horizontal.length()
	if speed < 0.001:
		return Vector3.ZERO
	var drop := maxf(speed, config.stop_speed) * config.ground_friction * delta
	return horizontal * (maxf(speed - drop, 0.0) / speed)


## Quake-style acceleration: only adds speed along wish_dir up to wish_speed,
## so diagonal input never exceeds top speed and momentum is preserved.
func _accelerate(horizontal: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	if wish_speed <= 0.0:
		return horizontal
	var headroom := wish_speed - horizontal.dot(wish_dir)
	if headroom <= 0.0:
		return horizontal
	var gain := minf(accel * wish_speed * delta, headroom)
	return horizontal + wish_dir * gain


func _update_look(delta: float) -> void:
	if config.look_smoothing <= 0.0:
		_yaw = _look_yaw
		_pitch = _look_pitch
	else:
		var t := 1.0 - exp(-config.look_smoothing * delta)
		_yaw = lerpf(_yaw, _look_yaw, t)
		_pitch = lerpf(_pitch, _look_pitch, t)
	rotation.y = _yaw
	head.rotation.x = _pitch


func _update_camera(delta: float) -> void:
	var h_speed := get_horizontal_speed()
	var moving := is_on_floor() and h_speed > 0.5
	_bob_amount = move_toward(_bob_amount, 1.0 if moving else 0.0, delta * config.bob_blend_speed)
	if moving:
		_bob_phase += h_speed * config.bob_frequency * delta
	var speed_ratio := clampf(h_speed / config.sprint_speed, 0.0, 1.0)
	var bob := Vector3(cos(_bob_phase * 0.5) * 0.5, sin(_bob_phase), 0.0)
	bob *= config.bob_amplitude * _bob_amount * speed_ratio

	_land_offset = lerpf(_land_offset, 0.0, 1.0 - exp(-config.land_recover * delta))
	head.position = _head_rest + bob - Vector3(0.0, _land_offset, 0.0)

	var sprint_blend := clampf((h_speed - config.walk_speed) / maxf(config.sprint_speed - config.walk_speed, 0.01), 0.0, 1.0)
	var fov_target := PlayerSettings.fov + config.sprint_fov_kick * sprint_blend
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-config.fov_smoothing * delta))

	var side_ratio := clampf(global_transform.basis.x.dot(velocity) / config.sprint_speed, -1.0, 1.0)
	var roll_target := deg_to_rad(-config.strafe_tilt_deg) * side_ratio
	camera.rotation.z = lerp_angle(camera.rotation.z, roll_target, 1.0 - exp(-config.tilt_smoothing * delta))
