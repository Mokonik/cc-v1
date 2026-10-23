class_name Progression
extends RefCounted
## XP, levels, perks and Sabotage Points for every player. The only code that changes a
## ProgressionState; it pushes the resulting PlayerStats into CombatSystem whenever perks change.
## Perk offers are seeded by (seed, player, level, offer number), so they are reproducible.

var _events: EventBus
var _combat: CombatSystem
var _perks: PerkCatalog
var _states: Dictionary = {}
var _seed := 1
var _offer_counter: Dictionary = {}


func setup(events: EventBus, combat: CombatSystem, perks: PerkCatalog) -> void:
	_events = events
	_combat = combat
	_perks = perks


func set_seed(value: int) -> void:
	_seed = value


func perks_catalog() -> PerkCatalog:
	return _perks


func register(player_id: int) -> ProgressionState:
	var state := ProgressionState.new()
	state.player_id = player_id
	_states[player_id] = state
	return state


func unregister(player_id: int) -> void:
	_states.erase(player_id)
	_offer_counter.erase(player_id)


func get_state(player_id: int) -> ProgressionState:
	return _states.get(player_id)


## Adds XP and returns how many levels were gained. Each level queues a perk offer.
func grant_xp(player_id: int, amount: int) -> int:
	var state: ProgressionState = _states.get(player_id)
	if state == null or amount <= 0:
		return 0
	state.xp += amount
	var gained := 0
	while state.xp >= ProgressionState.total_xp_to_reach(state.level + 1):
		state.level += 1
		gained += 1
		var offer := _make_offer(state)
		if not offer.is_empty():
			state.offers.append(offer)
			_events.perk_offered.emit(player_id, offer)
		_events.level_up.emit(player_id, state.level)
	_events.xp_changed.emit(player_id, state.xp, state.level)
	return gained


func grant_sabotage_points(player_id: int, amount: int) -> void:
	var state: ProgressionState = _states.get(player_id)
	if state == null or amount == 0:
		return
	state.sabotage_points = maxi(state.sabotage_points + amount, 0)
	_events.sabotage_points_changed.emit(player_id, state.sabotage_points)


## Spends points if the player has enough. Returns false (and spends nothing) otherwise.
func spend_sabotage_points(player_id: int, amount: int) -> bool:
	var state: ProgressionState = _states.get(player_id)
	if state == null or amount < 0 or state.sabotage_points < amount:
		return false
	grant_sabotage_points(player_id, -amount)
	return true


## Picks choice 1-3 from the oldest pending offer. Returns the perk id, or "" if there was
## nothing to pick or the choice was invalid.
func pick_perk(player_id: int, choice: int) -> StringName:
	var state: ProgressionState = _states.get(player_id)
	if state == null or state.offers.is_empty():
		return &""
	var offer: Array = state.offers[0]
	if choice < 1 or choice > offer.size():
		return &""
	state.offers.remove_at(0)
	var perk_id: StringName = offer[choice - 1]
	apply_perk(player_id, perk_id)
	_events.perk_picked.emit(player_id, perk_id)
	return perk_id


## Gives a perk stack directly (also used by the console and the bot model).
## Returns false if the perk is unknown or already at its maximum.
func apply_perk(player_id: int, perk_id: StringName) -> bool:
	var state: ProgressionState = _states.get(player_id)
	var def := _perks.get_def(perk_id)
	if state == null or def == null or state.stacks_of(perk_id) >= def.max_stacks:
		return false
	state.perks[perk_id] = state.stacks_of(perk_id) + 1
	refresh_stats(player_id)
	return true


## Recomputes a player's PlayerStats from their perks and hands them to CombatSystem.
func refresh_stats(player_id: int) -> PlayerStats:
	var stats := stats_for(player_id)
	_combat.set_stats(player_id, stats)
	return stats


func stats_for(player_id: int) -> PlayerStats:
	var stats := PlayerStats.new()
	var state: ProgressionState = _states.get(player_id)
	if state == null:
		return stats
	for perk_id: StringName in state.perks:
		var def := _perks.get_def(perk_id)
		if def != null:
			def.apply(stats, state.perks[perk_id])
	return stats


## Three distinct perks the player can still stack, chosen deterministically.
func _make_offer(state: ProgressionState) -> Array[StringName]:
	var pool: Array[StringName] = []
	for perk_id in _perks.ids():
		if state.stacks_of(perk_id) < _perks.get_def(perk_id).max_stacks:
			pool.append(perk_id)
	var counter: int = _offer_counter.get(state.player_id, 0)
	_offer_counter[state.player_id] = counter + 1
	var offer: Array[StringName] = []
	var slot := 0
	while offer.size() < ProgressionState.OFFER_SIZE and not pool.is_empty():
		var roll := float(hash([_seed, state.player_id, state.level, counter, slot]) & 0xFFFFFF) / float(0x1000000)
		offer.append(pool.pop_at(int(roll * pool.size()) % pool.size()))
		slot += 1
	return offer
