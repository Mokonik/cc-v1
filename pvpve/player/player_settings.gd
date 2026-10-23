class_name PlayerSettings
extends RefCounted
## Player-facing settings (as opposed to gameplay tuning in MovementConfig),
## persisted to user://settings.cfg.

const DEFAULT_PATH := "user://settings.cfg"
const SENSITIVITY_RANGE := Vector2(0.0005, 0.01)
const FOV_RANGE := Vector2(60.0, 110.0)

## Radians of camera rotation per pixel of mouse movement.
static var mouse_sensitivity := 0.0025
static var fov := 80.0
static var _loaded := false


static func ensure_loaded() -> void:
	if not _loaded:
		load_from(DEFAULT_PATH)


static func load_from(path: String = DEFAULT_PATH) -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	mouse_sensitivity = clampf(float(cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)), SENSITIVITY_RANGE.x, SENSITIVITY_RANGE.y)
	fov = clampf(float(cfg.get_value("video", "fov", fov)), FOV_RANGE.x, FOV_RANGE.y)


static func save_to(path: String = DEFAULT_PATH) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fov", fov)
	cfg.save(path)


static func scale_sensitivity(factor: float) -> void:
	mouse_sensitivity = clampf(mouse_sensitivity * factor, SENSITIVITY_RANGE.x, SENSITIVITY_RANGE.y)
	save_to()
