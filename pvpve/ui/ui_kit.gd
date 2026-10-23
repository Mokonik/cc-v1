class_name UiKit
extends RefCounted
## Small helpers shared by the HUD scripts so each one stays about layout, not boilerplate.


static func label(font_size: int, color := Color.WHITE) -> Label:
	var node := Label.new()
	node.add_theme_font_size_override(&"font_size", font_size)
	node.add_theme_color_override(&"font_color", color)
	node.add_theme_color_override(&"font_outline_color", Color.BLACK)
	node.add_theme_constant_override(&"outline_size", 6)
	return node


## Adds a control to a parent and pins it to a screen anchor, then shifts it by offset.
static func anchored(parent: Node, control: Control, preset: int, offset := Vector2.ZERO) -> Control:
	parent.add_child(control)
	control.set_anchors_and_offsets_preset(preset)
	control.position += offset
	return control


static func panel(color := Color(0.04, 0.05, 0.07, 0.82)) -> PanelContainer:
	var node := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	node.add_theme_stylebox_override(&"panel", style)
	return node


static func bar(size: Vector2, fill_color: Color) -> Array[ColorRect]:
	var back := ColorRect.new()
	back.color = Color(0.0, 0.0, 0.0, 0.6)
	back.size = size
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.position = Vector2(2.0, 2.0)
	fill.size = Vector2(size.x - 4.0, size.y - 4.0)
	back.add_child(fill)
	return [back, fill]
