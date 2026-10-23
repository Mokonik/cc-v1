class_name InputSetup
extends RefCounted
## Registers gameplay input actions in code so they are testable headless and
## stay in one reviewable place. Safe to call repeatedly.

const ACTIONS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"reload": [KEY_R],
	&"slot_1": [KEY_1],
	&"slot_2": [KEY_2],
	&"slot_3": [KEY_3],
	&"slot_4": [KEY_4],
	&"weapon_next": [KEY_Q],
	&"use_item": [KEY_F],
	&"place_trap": [KEY_G],
	&"perk_1": [KEY_Z],
	&"perk_2": [KEY_X],
	&"perk_3": [KEY_C],
}
const MOUSE_ACTIONS := {
	&"fire": [MOUSE_BUTTON_LEFT],
	&"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN],
	&"weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
}


static func ensure_actions() -> void:
	for action: StringName in ACTIONS:
		_ensure(action)
		for keycode: Key in ACTIONS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			_add_once(action, event)
	for action: StringName in MOUSE_ACTIONS:
		_ensure(action)
		for button: MouseButton in MOUSE_ACTIONS[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			_add_once(action, event)


static func all_actions() -> Array[StringName]:
	var result: Array[StringName] = []
	for action: StringName in ACTIONS:
		result.append(action)
	for action: StringName in MOUSE_ACTIONS:
		if not result.has(action):
			result.append(action)
	return result


static func _ensure(action: StringName) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.5)


static func _add_once(action: StringName, event: InputEvent) -> void:
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)
