class_name ModifierCatalog
extends RefCounted
## The known world modifiers, loaded from content/modifiers/, and the seeded three-card offer.

const PATHS: Array[String] = [
	"res://content/modifiers/double_spawns.tres",
	"res://content/modifiers/elite_monsters.tres",
	"res://content/modifiers/low_gravity.tres",
	"res://content/modifiers/fog.tres",
	"res://content/modifiers/volatile.tres",
]
const OFFER_SIZE := 3

var _defs: Dictionary = {}
## Ids in the order of PATHS. StringName sorting is not alphabetical, so never sort ids.
var _order: Array[StringName] = []


func _init() -> void:
	for path in PATHS:
		var def: ModifierDef = load(path)
		_defs[def.id] = def
		_order.append(def.id)


func get_def(id: StringName) -> ModifierDef:
	return _defs.get(id)


func has(id: StringName) -> bool:
	return _defs.has(id)


func ids() -> Array[StringName]:
	return _order.duplicate()


## Three distinct modifiers, chosen deterministically from the seed, the picker and the cycle.
func offer(seed_value: int, picker_id: int, cycle: int) -> Array[StringName]:
	var pool := _order.duplicate()
	var cards: Array[StringName] = []
	var slot := 0
	while cards.size() < OFFER_SIZE and not pool.is_empty():
		var roll := float(hash([seed_value, picker_id, cycle, slot, 55]) & 0xFFFFFF) / float(0x1000000)
		cards.append(pool.pop_at(int(roll * pool.size()) % pool.size()))
		slot += 1
	return cards
