class_name LootEntry
extends Resource
## One row of a loot table.

enum Kind { WEAPON, HEALTH, TRAP, XP }

@export var kind: Kind = Kind.HEALTH
## Weapon id for WEAPON rows (pistol, sword, bow, orb); unused otherwise.
@export var id: StringName = &""
@export_range(0.0, 100.0, 0.5) var weight := 10.0
## Not dropped before this wave (1 = from the start; the boss counts as a late wave).
@export_range(1, 20) var min_wave := 1
## Health restored for HEALTH, XP granted for XP; ignored otherwise.
@export_range(0, 500) var amount := 0
