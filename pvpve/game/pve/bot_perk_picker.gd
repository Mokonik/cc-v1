class_name BotPerkPicker
extends RefCounted
## How a bot chooses among three offered perks: it takes the one it values most, with ties
## going to the earlier choice. Fixed preferences keep bot builds predictable and testable.

const PREFERENCE: Array[StringName] = [
	&"vitality", &"marksman", &"iron_skin", &"swiftness", &"quick_hands",
	&"second_wind", &"berserker", &"pyromancer", &"scavenger",
]


## Returns the choice (1-3) to pick from an offer, or 0 for an empty offer.
static func choose(offer: Array) -> int:
	var best := 0
	var best_rank := PREFERENCE.size() + 1
	for i in offer.size():
		var rank := PREFERENCE.find(offer[i])
		if rank < 0:
			rank = PREFERENCE.size()
		if rank < best_rank:
			best_rank = rank
			best = i + 1
	return best
