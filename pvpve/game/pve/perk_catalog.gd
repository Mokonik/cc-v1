class_name PerkCatalog
extends RefCounted
## The known perks, loaded from content/perks/.

const PATHS: Array[String] = [
	"res://content/perks/vitality.tres",
	"res://content/perks/swiftness.tres",
	"res://content/perks/marksman.tres",
	"res://content/perks/berserker.tres",
	"res://content/perks/quick_hands.tres",
	"res://content/perks/pyromancer.tres",
	"res://content/perks/iron_skin.tres",
	"res://content/perks/second_wind.tres",
	"res://content/perks/scavenger.tres",
]

var _defs: Dictionary = {}
## Ids in the order of PATHS. StringName sorting is not alphabetical, so never sort ids.
var _order: Array[StringName] = []


func _init() -> void:
	for path in PATHS:
		var def: PerkDef = load(path)
		_defs[def.id] = def
		_order.append(def.id)


func get_def(id: StringName) -> PerkDef:
	return _defs.get(id)


func has(id: StringName) -> bool:
	return _defs.has(id)


## All perk ids, in a stable order.
func ids() -> Array[StringName]:
	return _order.duplicate()
