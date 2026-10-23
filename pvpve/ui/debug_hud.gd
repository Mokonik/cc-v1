extends CanvasLayer
## Crosshair plus a toggleable (F3) readout of the values that matter when tuning movement.

@export var game: Game

var _label: Label


func _ready() -> void:
	_build_crosshair()
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_label.visible = not _label.visible


func _process(_delta: float) -> void:
	if not _label.visible:
		return
	var lines: Array[String] = ["FPS %d" % Engine.get_frames_per_second()]
	var player := game.get_human()
	if player != null:
		var cfg := player.config
		lines.append("Speed %.1f m/s  (walk %.1f / sprint %.1f)" % [player.get_horizontal_speed(), cfg.walk_speed, cfg.sprint_speed])
		lines.append("Vertical %.1f m/s   %s" % [player.velocity.y, "grounded" if player.is_on_floor() else "airborne"])
	lines.append("Players: %d human, %d bots" % [
		game.registry.count_kind(PlayerRegistry.Kind.HUMAN),
		game.registry.count_kind(PlayerRegistry.Kind.BOT)])
	lines.append("Sensitivity %.4f   ([ / ] to change)" % PlayerSettings.mouse_sensitivity)
	lines.append("")
	lines.append("WASD move  |  Space jump  |  Shift sprint  |  ` console  |  Esc release mouse  |  F3 hide")
	_label.text = "\n".join(lines)


func _build_crosshair() -> void:
	var center := Control.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	for rect in [Rect2(-1, -7, 2, 14), Rect2(-7, -1, 14, 2)]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.85)
		bar.position = rect.position
		bar.size = rect.size
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(bar)
