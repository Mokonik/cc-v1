class_name MonsterCatalog
extends RefCounted
## The known monsters, loaded from content/monsters/.

const PATHS: Array[String] = [
	"res://content/monsters/grunt.tres",
	"res://content/monsters/spitter.tres",
	"res://content/monsters/brute.tres",
	"res://content/monsters/warden.tres",
]

var _defs: Dictionary = {}
## Ids in the order of PATHS. StringName sorting is not alphabetical, so never sort ids.
var _order: Array[StringName] = []


func _init() -> void:
	for path in PATHS:
		var def: MonsterDef = load(path)
		_defs[def.id] = def
		_order.append(def.id)


func get_def(id: StringName) -> MonsterDef:
	return _defs.get(id)


func has(id: StringName) -> bool:
	return _defs.has(id)


func ids() -> Array[StringName]:
	return _order.duplicate()
