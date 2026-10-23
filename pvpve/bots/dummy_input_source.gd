class_name DummyInputSource
extends InputSource
## Drives a target dummy: it stands still, or strafes back and forth so projectile
## leading can be tested. Produces PlayerCommands like every other source.

enum Pattern { STAND, STRAFE }

const STRAFE_SECONDS := 1.4

var pattern := Pattern.STAND

var _yaw := 0.0
var _pitch := 0.0
var _timer := 0.0
var _direction := 1.0


func set_view(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch


func poll(delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = _yaw
	command.pitch = _pitch
	if pattern == Pattern.STRAFE:
		_timer += delta
		if _timer >= STRAFE_SECONDS:
			_timer = 0.0
			_direction = -_direction
		command.move = Vector2(_direction, 0.0)
	return command
