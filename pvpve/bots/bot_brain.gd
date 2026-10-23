class_name BotBrain
extends RefCounted
## Steering and aiming for one bot. Pure logic: it is handed positions, a waypoint and
## line-of-sight, and returns a PlayerCommand, so it never touches the scene tree or
## physics directly. All randomness comes from its own seeded generator.

const MAX_PITCH := 1.4
const STUCK_CHECK_SECONDS := 0.6
const STUCK_MIN_PROGRESS := 0.2
const HOP_HOLD_SECONDS := 0.4
const FIRE_CONE_DEG := 5.0

var profile: BotProfile

var _rng := RandomNumberGenerator.new()
var _yaw := 0.0
var _pitch := 0.0
var _aim_error := Vector2.ZERO
var _aim_error_timer := 0.0
var _strafe_dir := 1.0
var _strafe_timer := 0.0
var _seen_time := 0.0
var _stuck_timer := 0.0
var _stuck_origin := Vector3.ZERO
var _jump_hold := 0.0


func _init(p_profile: BotProfile, seed_value: int) -> void:
	profile = p_profile
	_rng.seed = seed_value
	_strafe_dir = 1.0 if _rng.randf() < 0.5 else -1.0


func set_view(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch


## waypoint: where to head next (a path point, or the target itself if there is no path).
func think(delta: float, me: Player, target: Player, waypoint: Vector3, has_los: bool) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = _yaw
	command.pitch = _pitch
	if target == null:
		return command

	var my_pos := me.global_position
	var eye := my_pos + Vector3(0.0, Player.EYE_HEIGHT, 0.0)
	var target_eye := target.global_position + Vector3(0.0, Player.EYE_HEIGHT, 0.0)
	var to_target := target.global_position - my_pos
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var distance := flat.length()

	_seen_time = _seen_time + delta if has_los else 0.0
	var tracking := has_los and _seen_time >= profile.reaction_time
	var aim_off := _aim(delta, eye, target_eye, my_pos, waypoint, tracking)
	command.yaw = _yaw
	command.pitch = _pitch

	var world_dir := Vector3.ZERO
	var strafing := false
	if distance > profile.engage_distance or not has_los:
		world_dir = Vector3(waypoint.x - my_pos.x, 0.0, waypoint.z - my_pos.z)
		command.sprint = distance > profile.sprint_distance
	elif distance < profile.min_distance:
		world_dir = -flat
	else:
		strafing = true
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_dir = -_strafe_dir
			_strafe_timer = _rng.randf_range(profile.strafe_interval.x, profile.strafe_interval.y)
		var middle := (profile.engage_distance + profile.min_distance) * 0.5
		command.move = Vector2(_strafe_dir, clampf((middle - distance) * 0.2, -0.5, 0.5))

	if not strafing and world_dir.length_squared() > 0.0001:
		var local := me.global_transform.basis.inverse() * world_dir.normalized()
		command.move = Vector2(local.x, local.z)

	_unstick(delta, me, command)
	command.fire_held = tracking and distance <= profile.engage_distance * 1.2 and aim_off < deg_to_rad(FIRE_CONE_DEG)
	return command


## Turns the view toward the target (or where the bot is heading) at the profile's turn rate.
## Returns the remaining angle to the true target direction, ignoring aim error.
func _aim(delta: float, eye: Vector3, target_eye: Vector3, my_pos: Vector3, waypoint: Vector3, tracking: bool) -> float:
	var aim_vec := target_eye - eye
	if not tracking:
		aim_vec = Vector3(waypoint.x - my_pos.x, 0.0, waypoint.z - my_pos.z)
	if aim_vec.length_squared() < 0.0001:
		return PI

	var true_yaw := atan2(-aim_vec.x, -aim_vec.z)
	var want_yaw := true_yaw
	var want_pitch := atan2(aim_vec.y, Vector2(aim_vec.x, aim_vec.z).length())
	_aim_error_timer -= delta
	if _aim_error_timer <= 0.0:
		_aim_error_timer = 0.4
		var sigma := deg_to_rad(profile.aim_error_deg)
		_aim_error = Vector2(_rng.randfn(0.0, sigma), _rng.randfn(0.0, sigma))
	if tracking:
		want_yaw += _aim_error.x
		want_pitch += _aim_error.y

	var step := deg_to_rad(profile.aim_speed_deg) * delta
	_yaw += clampf(angle_difference(_yaw, want_yaw), -step, step)
	_pitch = clampf(_pitch + clampf(want_pitch - _pitch, -step, step), -MAX_PITCH, MAX_PITCH)
	return absf(angle_difference(_yaw, true_yaw))


## If the bot is pushing but not getting anywhere, hop and reverse its strafe.
func _unstick(delta: float, me: Player, command: PlayerCommand) -> void:
	var my_pos := me.global_position
	if command.move.length() > 0.5 and me.is_on_floor():
		_stuck_timer += delta
		if _stuck_timer >= STUCK_CHECK_SECONDS:
			if my_pos.distance_to(_stuck_origin) < STUCK_MIN_PROGRESS:
				command.jump_pressed = true
				_jump_hold = HOP_HOLD_SECONDS
				_strafe_dir = -_strafe_dir
			_stuck_timer = 0.0
			_stuck_origin = my_pos
	else:
		_stuck_timer = 0.0
		_stuck_origin = my_pos
	if _jump_hold > 0.0:
		_jump_hold -= delta
		command.jump_held = true
