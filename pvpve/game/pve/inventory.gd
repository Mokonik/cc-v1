class_name Inventory
extends RefCounted
## One player's consumables. They reset each cycle (M5) along with weapon loot.

const MAX_HEALTH_PACKS := 3
const MAX_TRAPS := 3
const HEALTH_PACK_AMOUNT := 35.0

var health_packs := 0
var traps := 0


func clear() -> void:
	health_packs = 0
	traps = 0
