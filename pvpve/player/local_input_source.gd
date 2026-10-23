class_name LocalInputSource
extends InputSource
## Keyboard and mouse. The only gameplay class allowed to read Input directly.

## False while a UI element (such as the dev console) owns the keyboard and mouse.
var enabled := true
## Set by Game before the source enters the tree.
var events: EventBus

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	InputSetup.ensure_actions()
	PlayerSettings.ensure_loaded()
	if events != null:
		events.ui_capture_changed.connect(func(ui_has_focus: bool) -> void: enabled = not ui_has_focus)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_local_view() -> bool:
	return true


func set_view(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch


func poll(_delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = _yaw
	command.pitch = _pitch
	if not enabled:
		return command
	command.move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	command.jump_pressed = Input.is_action_just_pressed(&"jump")
	command.jump_held = Input.is_action_pressed(&"jump")
	command.sprint = Input.is_action_pressed(&"sprint")
	return command


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var sensitivity := PlayerSettings.mouse_sensitivity
			var max_pitch := _max_pitch()
			_yaw -= event.relative.x * sensitivity
			_pitch = clampf(_pitch - event.relative.y * sensitivity, -max_pitch, max_pitch)
	elif event.is_action_pressed(&"ui_cancel"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_BRACKETLEFT:
			PlayerSettings.scale_sensitivity(1.0 / 1.1)
		elif event.keycode == KEY_BRACKETRIGHT:
			PlayerSettings.scale_sensitivity(1.1)


func _max_pitch() -> float:
	var player := get_parent() as Player
	return player.config.max_pitch if player != null and player.config != null else 1.5
