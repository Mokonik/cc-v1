class_name ProgressionState
extends RefCounted
## One player's XP, level, perks and Sabotage Points. Perks last the whole run; this object
## is owned by Progression and is never touched directly by presentation. Level-ups queue
## perk offers (three seeded choices each); the player picks one at a time.

const XP_BASE := 100
const XP_PER_LEVEL := 50
const OFFER_SIZE := 3

var player_id := 0
var xp := 0
var level := 1
var sabotage_points := 0
## perk id -> stacks
var perks: Dictionary = {}
## Each entry is an Array[StringName] of perk ids to choose from, oldest first.
var offers: Array = []


## XP needed to go from this level to the next.
static func xp_for_level(at_level: int) -> int:
	return XP_BASE + XP_PER_LEVEL * (at_level - 1)


func xp_into_level() -> int:
	return xp - total_xp_to_reach(level)


func xp_needed() -> int:
	return xp_for_level(level)


## Total XP that puts a player at the start of the given level.
static func total_xp_to_reach(target_level: int) -> int:
	var total := 0
	for l in range(1, target_level):
		total += xp_for_level(l)
	return total


func stacks_of(perk_id: StringName) -> int:
	return perks.get(perk_id, 0)


func has_pending_offer() -> bool:
	return not offers.is_empty()
