class_name Standings
extends RefCounted
## The match scoreboard, kept as a ledger: every change to anyone's points is an entry with
## a cycle, a kind and a note. Totals and ranks are computed from it, so a results screen can
## explain any number and tests can prove which entries conserve points.
##
## Kinds: pve, kill, bounty, skill, steal (zero-sum pairs), reset and flip (points destroyed by
## a Showstopper), wager (zero-sum), final.

const PVP_KINDS: Array[StringName] = [&"kill", &"bounty", &"skill", &"steal", &"reset", &"flip"]

class Entry extends RefCounted:
	var player_id := 0
	var cycle := 0
	var kind: StringName = &""
	var amount := 0
	var note := ""

var entries: Array[Entry] = []
var _players: Array[int] = []


func register(player_id: int) -> void:
	if not _players.has(player_id):
		_players.append(player_id)


func unregister(player_id: int) -> void:
	_players.erase(player_id)


func player_ids() -> Array[int]:
	return _players.duplicate()


func clear() -> void:
	entries.clear()


func add(player_id: int, cycle: int, kind: StringName, amount: int, note := "") -> void:
	register(player_id)
	if amount == 0:
		return
	var entry := Entry.new()
	entry.player_id = player_id
	entry.cycle = cycle
	entry.kind = kind
	entry.amount = amount
	entry.note = note
	entries.append(entry)


func total(player_id: int) -> int:
	var sum := 0
	for entry in entries:
		if entry.player_id == player_id:
			sum += entry.amount
	return sum


## Sum of one player's entries of the given kinds, optionally for one cycle (-1 = all cycles).
func sum_kinds(player_id: int, kinds: Array[StringName], cycle := -1) -> int:
	var sum := 0
	for entry in entries:
		if entry.player_id == player_id and kinds.has(entry.kind) and (cycle < 0 or entry.cycle == cycle):
			sum += entry.amount
	return sum


## The player's PvP points in one cycle (kills, bounties, skill bonuses, steals, resets, flips).
func pvp_points(player_id: int, cycle: int) -> int:
	return sum_kinds(player_id, PVP_KINDS, cycle)


## Everything of one kind added up across all players (a conservation check).
func sum_kind(kind: StringName) -> int:
	var sum := 0
	for entry in entries:
		if entry.kind == kind:
			sum += entry.amount
	return sum


func sum_all() -> int:
	var sum := 0
	for entry in entries:
		sum += entry.amount
	return sum


## Player ids from first to last. Ties go to the higher PvE score, then to the lower id.
func ranking() -> Array[int]:
	var ids := _players.duplicate()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var ta := total(a)
		var tb := total(b)
		if ta != tb:
			return ta > tb
		var pa := sum_kinds(a, [&"pve"])
		var pb := sum_kinds(b, [&"pve"])
		if pa != pb:
			return pa > pb
		return a < b)
	return ids


## The player in front, or 0 if nobody is registered.
func leader() -> int:
	var order := ranking()
	return order[0] if not order.is_empty() else 0


func rank_of(player_id: int) -> int:
	return ranking().find(player_id) + 1


## Entries for one player, oldest first (for the results breakdown).
func entries_for(player_id: int) -> Array[Entry]:
	var result: Array[Entry] = []
	for entry in entries:
		if entry.player_id == player_id:
			result.append(entry)
	return result
