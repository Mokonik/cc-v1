class_name LootTable
extends Resource
## Weighted drops. pick() is deterministic: the caller supplies a roll in [0, 1).

@export var entries: Array[LootEntry] = []


## The entry chosen by roll (0 to 1) among those allowed at this wave, or null if none apply.
func pick(roll: float, wave: int) -> LootEntry:
	var total := 0.0
	for entry in entries:
		if entry.min_wave <= wave:
			total += entry.weight
	if total <= 0.0:
		return null
	var target := clampf(roll, 0.0, 0.999999) * total
	for entry in entries:
		if entry.min_wave > wave:
			continue
		target -= entry.weight
		if target < 0.0:
			return entry
	return null
