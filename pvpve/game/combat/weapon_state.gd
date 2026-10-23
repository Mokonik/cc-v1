class_name WeaponState
extends RefCounted
## One player's runtime state for one weapon. Times are absolute tick numbers; -1 means "not happening".

var def: WeaponDef
var ammo := 0
var next_fire_tick := 0
var reload_done_tick := -1
var draw_start_tick := -1
var swing_hit_tick := -1
## Counts uses, so each shot gets its own deterministic spread.
var shots_fired := 0


func _init(p_def: WeaponDef) -> void:
	def = p_def
	reset()


func reset() -> void:
	ammo = def.magazine
	next_fire_tick = 0
	reload_done_tick = -1
	draw_start_tick = -1
	swing_hit_tick = -1


## Cancels anything in progress (reloading, drawing, swinging) without touching ammo.
func cancel_actions() -> void:
	reload_done_tick = -1
	draw_start_tick = -1
	swing_hit_tick = -1


func is_reloading() -> bool:
	return reload_done_tick >= 0


func is_drawing() -> bool:
	return draw_start_tick >= 0
