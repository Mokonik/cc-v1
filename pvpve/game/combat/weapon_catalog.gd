class_name WeaponCatalog
extends RefCounted
## The set of known weapons, loaded from content/weapons/. Instance-based (owned by Game)
## rather than a static cache, so resources are released with the game.

const PATHS: Array[String] = [
	"res://content/weapons/pistol.tres",
	"res://content/weapons/sword.tres",
	"res://content/weapons/bow.tres",
	"res://content/weapons/fire_orb.tres",
]
const STARTER := &"pistol"

var _defs: Dictionary = {}


func _init() -> void:
	for path in PATHS:
		var def: WeaponDef = load(path)
		_defs[def.id] = def


func get_def(id: StringName) -> WeaponDef:
	return _defs.get(id)


func has(id: StringName) -> bool:
	return _defs.has(id)


## All weapons ordered by slot.
func all() -> Array[WeaponDef]:
	var result: Array[WeaponDef] = []
	for id: StringName in _defs:
		result.append(_defs[id])
	result.sort_custom(func(a: WeaponDef, b: WeaponDef) -> bool: return a.slot < b.slot)
	return result
