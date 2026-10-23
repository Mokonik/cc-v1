class_name WagerRules
extends RefCounted
## The wager before each PvP match. Everyone stakes some of their standings points into a pot,
## and the pot is paid out by PvP placement. Pure and zero-sum: the changes it returns always
## add up to exactly zero.


## Points staked for a stake option. You cannot stake points you do not have.
static func stake_amount(total: int, option_index: int, options: PackedFloat32Array) -> int:
	if option_index < 0 or option_index >= options.size():
		return 0
	return floori(float(maxi(total, 0)) * options[option_index])


## How the pot is split by finishing place, for a given number of players.
static func payout_shares(player_count: int) -> Array[float]:
	match player_count:
		1:
			return [1.0]
		2:
			return [0.7, 0.3]
		3:
			return [0.55, 0.30, 0.15]
	return [0.5, 0.3, 0.15, 0.05]


## stakes: player id -> points staked. placement: player ids from 1st to last.
## Returns player id -> net change (payout minus stake). Rounding leftovers go to 1st place.
static func settle(stakes: Dictionary, placement: Array[int]) -> Dictionary:
	var net := {}
	var pot := 0
	for id: int in stakes:
		pot += stakes[id]
		net[id] = -stakes[id]
	if pot == 0 or placement.is_empty():
		return net
	var shares := payout_shares(placement.size())
	var paid := 0
	for i in placement.size():
		var payout := floori(float(pot) * shares[i])
		paid += payout
		net[placement[i]] = net.get(placement[i], 0) + payout
	net[placement[0]] += pot - paid
	return net
