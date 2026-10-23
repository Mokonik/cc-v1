class_name ScriptedSource
extends InputSource
## Test double for the keyboard: a test sets the view and presses buttons frame by frame.

var yaw := 0.0
var pitch := 0.0
var move := Vector2.ZERO
var fire_held := false
var _fire_pressed := false
var _fire_released := false
var _reload := false
var _slot := 0
var _cycle := 0


func press_fire() -> void:
	fire_held = true
	_fire_pressed = true


func release_fire() -> void:
	fire_held = false
	_fire_released = true


func reload() -> void:
	_reload = true


func select(slot: int) -> void:
	_slot = slot


func cycle(direction: int) -> void:
	_cycle = direction


func is_local_view() -> bool:
	return true


func set_view(new_yaw: float, new_pitch: float) -> void:
	yaw = new_yaw
	pitch = new_pitch


func poll(_delta: float) -> PlayerCommand:
	var command := PlayerCommand.new()
	command.yaw = yaw
	command.pitch = pitch
	command.move = move
	command.fire_held = fire_held
	command.fire_pressed = _fire_pressed
	command.fire_released = _fire_released
	command.reload_pressed = _reload
	command.weapon_slot = _slot
	command.weapon_cycle = _cycle
	_fire_pressed = false
	_fire_released = false
	_reload = false
	_slot = 0
	_cycle = 0
	return command
