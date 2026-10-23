class_name LootDrop
extends RefCounted
## A pickup lying in the world. Plain data (id, kind, position), so it replicates cleanly.
## Weapon drops carry a weapon id; health and XP drops carry an amount.

var id := 0
var kind := LootEntry.Kind.HEALTH
var weapon_id: StringName = &""
var amount := 0
var position := Vector3.ZERO
var spawn_tick := 0
## The player whose zone this belongs to (0 = anyone), so loot in one zone is never taken from another.
var owner_id := 0


func label() -> String:
	match kind:
		LootEntry.Kind.WEAPON:
			return String(weapon_id).capitalize()
		LootEntry.Kind.HEALTH:
			return "Health pack"
		LootEntry.Kind.TRAP:
			return "Trap"
		LootEntry.Kind.XP:
			return "XP +%d" % amount
	return "Loot"
