extends CanvasLayer
## Backtick toggles a command line for solo testing (spawn bots, teleport, time scale...).
## The commands themselves live in DevCommands so they can be tested without a UI.

@export var game: Game

var _panel: PanelContainer
var _log: RichTextLabel
var _line: LineEdit
var _history: Array[String] = []
var _history_index := 0


func _ready() -> void:
	layer = 10
	_build_ui()
	_set_open(false, false)
	_print("Dev console. Type help.")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_QUOTELEFT:
		_set_open(not _panel.visible, true)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.keycode == KEY_ESCAPE:
		_set_open(false, true)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.keycode == KEY_UP:
		_browse_history(-1)
		get_viewport().set_input_as_handled()
	elif _panel.visible and event.keycode == KEY_DOWN:
		_browse_history(1)
		get_viewport().set_input_as_handled()


func _set_open(open: bool, notify: bool) -> void:
	_panel.visible = open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_line.grab_focus()
	else:
		_line.release_focus()
		if notify and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if notify:
		game.events.ui_capture_changed.emit(open)


func _on_submitted(text: String) -> void:
	_line.clear()
	if text.strip_edges().is_empty():
		return
	_history.append(text)
	_history_index = _history.size()
	_print("> " + text)
	var result := DevCommands.run(text, game)
	if not result.is_empty():
		_print(result)
	_line.grab_focus()


func _browse_history(step: int) -> void:
	if _history.is_empty():
		return
	_history_index = clampi(_history_index + step, 0, _history.size())
	_line.text = "" if _history_index == _history.size() else _history[_history_index]
	_line.caret_column = _line.text.length()


func _print(text: String) -> void:
	_log.append_text(text + "\n")


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_panel.custom_minimum_size = Vector2(0.0, 260.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	_panel.add_theme_stylebox_override(&"panel", style)
	add_child(_panel)

	var column := VBoxContainer.new()
	_panel.add_child(column)

	_log = RichTextLabel.new()
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_log)

	_line = LineEdit.new()
	_line.placeholder_text = "command (help)"
	_line.text_submitted.connect(_on_submitted)
	column.add_child(_line)
