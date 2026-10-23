class_name Player
extends CharacterBody3D
## First-person character controller.
## Tuning lives in MovementConfig; player-facing options (sensitivity, FOV) in PlayerSettings.
## Movement is split so it can be tested and later driven by the network:
## _physics_process gathers local input and calls simulate(), which is pure movement.

signal jumped
signal landed(impact_speed: float)

@export var config: MovementConfig
## False for remote puppets and tests: real input is ignored and simulate() is driven externally.
@export var local_control := true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

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
	InputSetup.ensure_actions()
	PlayerSettings.ensure_loaded()
	_head_rest = head.position
	set_look(rotation.y, 0.0)
	camera.fov = PlayerSettings.fov
	if local_control:
		camera.make_current()
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not local_control:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := PlayerSettings.mouse_sensitivity
		_look_yaw -= event.relative.x * sens
		_look_pitch = clampf(_look_pitch - event.relative.y * sens, -config.max_pitch, config.max_pitch)
	elif event.is_action_pressed("ui_cancel"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETLEFT:
			PlayerSettings.scale_sensitivity(1.0 / 1.1)
		elif event.keycode == KEY_BRACKETRIGHT:
			PlayerSettings.scale_sensitivity(1.1)


func _physics_process(delta: float) -> void:
	if not local_control:
		return
	var move := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	simulate(
		move,
		Input.is_action_just_pressed(&"jump"),
		Input.is_action_pressed(&"jump"),
		Input.is_action_pressed(&"sprint"),
		delta)


func _process(delta: float) -> void:
	_update_look(delta)
	_update_camera(delta)


## Sets view direction immediately (spawning, teleports, tests).
func set_look(yaw: float, pitch: float) -> void:
	_look_yaw = yaw
	_look_pitch = clampf(pitch, -config.max_pitch, config.max_pitch)
	_yaw = _look_yaw
	_pitch = _look_pitch
	rotation.y = _yaw
	head.rotation.x = _pitch


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Advances movement by one physics step. move.y < 0 is forward, matching Input.get_vector.
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
