class_name MatchDirector
extends RefCounted
## The match loop, in authority-layer code and timed in physics ticks:
##
##   LOBBY -> PVE -> PVE_RESULTS -> WAGER -> PVP_COUNTDOWN -> PVP -> PVP_RESULTS
##         -> (next cycle: PVE ...) -> FINAL -> VICTORY -> LOBBY
##
## Humans play a real PvE run; bots (and humans on autopilot) get a result from the stat model
## when the phase ends. PvP points, wagers and the final all end up in one Standings ledger.

const PVE := &"pve"
const PVE_RESULTS := &"pve_results"
const WAGER := &"wager"
const PVP_COUNTDOWN := &"pvp_countdown"
const PVP := &"pvp"
const PVP_RESULTS := &"pvp_results"
const FINAL := &"final"
const VICTORY := &"victory"
const LOBBY := &"lobby"

## How long a human may take over a PvE run before the phase is forced to end (on top of its length).
const PVE_GRACE_SECONDS := 160.0
const FINAL_START_RADIUS := 34.0
const ZONE_BROADCAST_TICKS := 6
const SPAWN_PROTECTION_SECONDS := 2.0

var config: MatchConfig = load("res://content/match_config.tres")
var standings := Standings.new()
var scorer := PvpScorer.new()

var phase: StringName = LOBBY
## 1-based number of the current cycle (cycles + 1 during the final).
var cycle := 0
var marked_id := 0
var champion_id := 0
## cycle -> player id -> PveResult, for the results screens.
var pve_results: Dictionary = {}
## Player id -> chosen stake option index / points actually staked.
var wager_choices: Dictionary = {}
var stakes: Dictionary = {}
var last_wager_net: Dictionary = {}
## Last PvP finishing order, and who is choosing the modifier from which cards.
var pvp_placement: Array[int] = []
var offer_picker := 0
var offer_cards: Array[StringName] = []
## Final results: ids from first to last, and the live safe-area radius.
var final_placement: Array[int] = []
var safe_radius := FINAL_START_RADIUS

var _game: Game
var _members: Array[int] = []
var _phase_start := 0
var _phase_end := 0
var _tick := 0
var _pending_runs: Dictionary = {}
var _eliminated: Array[int] = []
var _outside_ticks: Dictionary = {}


func setup(game: Game) -> void:
	_game = game
	# Method callables (not lambdas) so the scorer does not keep the director alive.
	scorer.setup(game.events, standings, config, _current_cycle, _current_mark)
	game.events.pve_finished.connect(_on_pve_finished)
	game.events.player_died.connect(_on_player_died)


func _current_cycle() -> int:
	return cycle


func _current_mark() -> int:
	return marked_id


func set_config(value: MatchConfig) -> void:
	config = value
	scorer.set_config(value)


func is_running() -> bool:
	return phase != LOBBY


func members() -> Array[int]:
	return _members


func seconds_left() -> float:
	return maxf(float(_phase_end - _tick) / Engine.physics_ticks_per_second, 0.0)


func phase_seconds() -> float:
	return float(_phase_end - _phase_start) / Engine.physics_ticks_per_second


## PvE difficulty a player faces this cycle: the base, plus the leader penalty for the marked player.
func difficulty_for(player_id: int) -> float:
	return _game.pve_difficulty + (config.leader_difficulty_bonus if player_id == marked_id else 0.0)


# ---- control --------------------------------------------------------------------------------

## Starts a match with everyone who is in the game. Returns "" or the reason it could not.
func start(cycles := -1) -> String:
	if is_running():
		return "A match is already running."
	_members.clear()
	for id in _game.registry.ids():
		if _game.registry.get_record(id).kind != PlayerRegistry.Kind.DUMMY:
			_members.append(id)
	if _members.size() < 2:
		return "Need at least two players: add a bot."
	if cycles > 0:
		config.cycles = cycles
	standings.clear()
	for id in _members:
		standings.register(id)
	pve_results.clear()
	marked_id = 0
	champion_id = 0
	cycle = 1
	_game.modifiers.clear()
	_game.events.match_started.emit(config.cycles)
	_game.events.standings_changed.emit()
	_begin_pve()
	return ""


## Ends the match at once and puts everyone back in the sandbox.
func stop() -> bool:
	if not is_running():
		return false
	for id in _members:
		if _game.pve.is_running(id):
			_game.pve.stop_run(id)
	_wrap_up()
	return true


## Ends the current phase now.
func skip() -> bool:
	if not is_running():
		return false
	if phase == PVE:
		for id in _pending_runs.keys():
			_game.pve.stop_run(id)
		_phase_end = _tick
	else:
		_phase_end = _tick
	return true


## Jumps straight to the final (console / tests).
func jump_to_final() -> bool:
	if not is_running() or phase == FINAL or phase == VICTORY:
		return false
	for id in _members:
		if _game.pve.is_running(id):
			_game.pve.stop_run(id)
	_pending_runs.clear()
	_begin_final()
	return true


## A menu pick (1-3) from a player. True if the match used it.
func choose(player_id: int, pick: int) -> bool:
	if not _members.has(player_id):
		return false
	if phase == WAGER and not _game.is_modeled(player_id):
		return set_wager(player_id, pick - 1)
	if phase == PVP_RESULTS and player_id == offer_picker and not offer_cards.is_empty() \
			and not _game.is_modeled(player_id):
		return pick_modifier(pick - 1)
	return false


func set_wager(player_id: int, option: int) -> bool:
	if phase != WAGER or not _members.has(player_id) or option < 0 or option >= config.stake_options.size():
		return false
	wager_choices[player_id] = option
	return true


## Picks one of the offered modifier cards (index 0-2). True if a modifier was activated.
func pick_modifier(index: int) -> bool:
	if offer_cards.is_empty() or index < 0 or index >= offer_cards.size():
		return false
	var chosen := offer_cards[index]
	offer_cards = []
	_game.modifiers.set_active(chosen, offer_picker, config.modifier_scope)
	_game.events.modifier_chosen.emit(offer_picker, chosen)
	return true


func set_mark(player_id: int) -> void:
	marked_id = player_id
	_game.events.mark_changed.emit(player_id)


# ---- per tick -------------------------------------------------------------------------------

func step(tick: int) -> void:
	_tick = tick
	match phase:
		LOBBY:
			return
		PVE:
			if _pending_runs.is_empty() and not _has_real_human_run() and tick >= _phase_end:
				_end_pve()
			elif tick >= _phase_end and not _pending_runs.is_empty() and tick >= _phase_end:
				# Humans still running past the grace period are cut off.
				for id in _pending_runs.keys():
					_game.pve.stop_run(id)
		PVE_RESULTS:
			if tick >= _phase_end:
				_begin_wager()
		WAGER:
			if tick >= _phase_end:
				_lock_wagers()
				_begin_pvp_countdown()
		PVP_COUNTDOWN:
			if tick >= _phase_end:
				_begin_pvp()
		PVP:
			if tick >= _phase_end:
				_end_pvp()
		PVP_RESULTS:
			if tick >= _phase_end:
				_after_pvp_results()
		FINAL:
			_step_final()
		VICTORY:
			if tick >= _phase_end:
				_wrap_up()


func _has_real_human_run() -> bool:
	return not _pending_runs.is_empty()


func _enter(new_phase: StringName, seconds: float) -> void:
	phase = new_phase
	_phase_start = _tick
	_phase_end = _tick + WeaponDef.seconds_to_ticks(seconds)
	_game.events.match_phase.emit(new_phase, cycle, seconds)


# ---- PvE -----------------------------------------------------------------------------------

func _begin_pve() -> void:
	_game.modifiers.aggregate_for(0)
	for id in _members:
		_game.loot.reset_loot(id)
		if _game.combat.is_alive(id):
			_game.combat.restore(id)
	_pending_runs.clear()
	var seconds := config.pve_seconds
	for id in _members:
		if _game.is_modeled(id):
			continue
		var error := _game.pve.start_run(id, config.pve_seconds, difficulty_for(id))
		if error == "":
			_pending_runs[id] = true
		else:
			push_warning("Match: PvE run for %d did not start: %s" % [id, error])
	_enter(PVE, seconds)
	if not _pending_runs.is_empty():
		_phase_end += WeaponDef.seconds_to_ticks(PVE_GRACE_SECONDS)


func _on_pve_finished(owner_id: int, _result: PveResult, _reason: StringName) -> void:
	_pending_runs.erase(owner_id)


func _end_pve() -> void:
	var results: Dictionary = {}
	for id in _members:
		var result: PveResult = null
		if _game.is_modeled(id):
			result = _game.run_bot_pve(id, _game.skill_level_of(id), null, difficulty_for(id))
		else:
			result = _game.pve.last_results.get(id)
		if result == null:
			result = PveResult.new()
			result.player_id = id
		results[id] = result
		standings.add(id, cycle, &"pve", result.score, "PvE")
	pve_results[cycle] = results
	_game.events.standings_changed.emit()
	_enter(PVE_RESULTS, config.pve_results_seconds)


# ---- wager ---------------------------------------------------------------------------------

func _begin_wager() -> void:
	wager_choices.clear()
	stakes.clear()
	for id in _members:
		if _game.is_modeled(id):
			wager_choices[id] = _bot_wager(id)
	_enter(WAGER, config.wager_seconds)


## Trailing bots gamble, leaders play safe, the middle mixes: all seeded, none random.
func _bot_wager(player_id: int) -> int:
	var roll := float(hash([_game.seed_value, player_id, cycle, 91]) & 0xFFFF) / 65536.0
	var rank := standings.rank_of(player_id)
	var top := config.stake_options.size() - 1
	var choice := 1
	if rank == 1:
		choice = 0 if roll < 0.7 else 1
	elif rank == _members.size():
		choice = top if roll < 0.5 else 1
	else:
		choice = 0 if roll < 0.4 else (1 if roll < 0.8 else top)
	return clampi(choice, 0, top)


func _lock_wagers() -> void:
	for id in _members:
		var option: int = wager_choices.get(id, 0)
		var stake := config.stake_for(standings.total(id), option)
		stakes[id] = stake
		_game.events.wager_set.emit(id, stake)


# ---- PvP -----------------------------------------------------------------------------------

func _begin_pvp_countdown() -> void:
	_game.modifiers.clear()
	_place_everyone()
	_set_combat(false)
	_enter(PVP_COUNTDOWN, config.pvp_countdown_seconds)


func _begin_pvp() -> void:
	_set_combat(true)
	_game.set_bots_fight(true)
	scorer.enabled = true
	_enter(PVP, config.pvp_seconds)


func _end_pvp() -> void:
	scorer.enabled = false
	_game.set_bots_fight(false)
	_set_combat(false)
	pvp_placement = _pvp_placement()
	last_wager_net = WagerRules.settle(stakes, pvp_placement)
	for id: int in last_wager_net:
		standings.add(id, cycle, &"wager", last_wager_net[id], "Wager")
	_game.events.wager_settled.emit(last_wager_net)
	set_mark(standings.leader())
	_game.events.standings_changed.emit()
	offer_cards = []
	offer_picker = 0
	if cycle < config.cycles:
		offer_picker = pvp_placement[0]
		offer_cards = _game.modifier_defs.offer(_game.seed_value, offer_picker, cycle)
		_game.events.modifier_offered.emit(offer_picker, offer_cards)
		if _game.is_modeled(offer_picker):
			var roll := hash([_game.seed_value, offer_picker, cycle, 17]) & 0xFFFF
			pick_modifier(roll % offer_cards.size())
	_enter(PVP_RESULTS, config.pvp_results_seconds)


func _pvp_placement() -> Array[int]:
	var order := _members.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		var pa := standings.pvp_points(a, cycle)
		var pb := standings.pvp_points(b, cycle)
		if pa != pb:
			return pa > pb
		var ka := _game.combat.get_vitals(a).kills
		var kb := _game.combat.get_vitals(b).kills
		if ka != kb:
			return ka > kb
		var ta := standings.total(a)
		var tb := standings.total(b)
		if ta != tb:
			return ta > tb
		return a < b)
	var typed: Array[int] = []
	typed.assign(order)
	return typed


func _after_pvp_results() -> void:
	if not offer_cards.is_empty():
		pick_modifier(0)
	if cycle < config.cycles:
		cycle += 1
		_begin_pve()
	else:
		_begin_final()


# ---- final ---------------------------------------------------------------------------------

func _begin_final() -> void:
	cycle = config.cycles + 1
	_game.modifiers.clear()
	scorer.enabled = false
	_game.combat.respawn_enabled = true
	for id in _members:
		if not _game.combat.is_alive(id):
			_game.combat.respawn_now(id)
	_place_everyone()
	_eliminated.clear()
	_outside_ticks.clear()
	safe_radius = FINAL_START_RADIUS
	_set_combat(true)
	_game.set_bots_fight(true)
	_game.combat.respawn_enabled = false
	_enter(FINAL, config.final_seconds)


func _alive_members() -> Array[int]:
	var alive: Array[int] = []
	for id in _members:
		if _game.combat.is_alive(id):
			alive.append(id)
	return alive


func _on_player_died(victim_id: int, _killer_id: int, _weapon_id: StringName) -> void:
	if phase == FINAL and _members.has(victim_id) and not _eliminated.has(victim_id):
		_eliminated.append(victim_id)


func _step_final() -> void:
	var elapsed := float(_tick - _phase_start) / maxf(float(_phase_end - _phase_start), 1.0)
	var shrink := clampf((elapsed - config.shrink_start_fraction) / maxf(1.0 - config.shrink_start_fraction, 0.01), 0.0, 1.0)
	safe_radius = lerpf(FINAL_START_RADIUS, config.shrink_end_radius, shrink)
	if (_tick - _phase_start) % ZONE_BROADCAST_TICKS == 0:
		_game.events.final_zone.emit(safe_radius, Vector3.ZERO)
	var dt := 1.0 / Engine.physics_ticks_per_second
	for id in _alive_members():
		var player := _game.get_player(id)
		if player == null:
			continue
		var flat := Vector2(player.global_position.x, player.global_position.z).length()
		if flat > safe_radius:
			_outside_ticks[id] = _outside_ticks.get(id, 0) + 1
			var seconds_out := float(_outside_ticks[id]) * dt
			var damage := config.storm_damage * (1.0 + config.storm_escalation * seconds_out) * dt
			_game.combat.apply_damage(id, damage, 0, &"storm", player.chest_position())
		else:
			_outside_ticks[id] = 0
	if _alive_members().size() <= 1 or _tick >= _phase_end:
		_end_final()


func _end_final() -> void:
	_set_combat(false)
	_game.set_bots_fight(false)
	var survivors := _alive_members()
	survivors.sort_custom(func(a: int, b: int) -> bool:
		var ha := _game.combat.get_vitals(a).hp
		var hb := _game.combat.get_vitals(b).hp
		return ha > hb if ha != hb else a < b)
	final_placement = survivors.duplicate()
	for i in range(_eliminated.size() - 1, -1, -1):
		if not final_placement.has(_eliminated[i]):
			final_placement.append(_eliminated[i])
	for id in _members:
		if not final_placement.has(id):
			final_placement.append(id)
	for i in final_placement.size():
		var points := config.final_points[i] if i < config.final_points.size() else 0
		standings.add(final_placement[i], cycle, &"final", points, "Final place %d" % (i + 1))
	champion_id = standings.leader()
	_game.events.standings_changed.emit()
	_game.events.match_finished.emit(champion_id)
	_enter(VICTORY, config.victory_seconds)


func _wrap_up() -> void:
	scorer.enabled = false
	_pending_runs.clear()
	_game.combat.respawn_enabled = true
	_game.set_bots_fight(false)
	_game.modifiers.clear()
	for id in _members:
		var vitals := _game.combat.get_vitals(id)
		if vitals != null:
			vitals.accepts_commands = _game.registry.get_record(id).kind == PlayerRegistry.Kind.HUMAN
		if not _game.combat.is_alive(id):
			_game.combat.respawn_now(id)
	_place_everyone()
	for id in _members:
		_game.combat.restore(id)
	marked_id = 0
	offer_cards = []
	phase = LOBBY
	_game.events.match_phase.emit(LOBBY, cycle, 0.0)


# ---- shared helpers ----------------------------------------------------------------------------

## Everyone on their own arena spawn, at full health.
func _place_everyone() -> void:
	for i in _members.size():
		var id := _members[i]
		var player := _game.get_player(id)
		if player == null:
			continue
		var spawn := _game.arena.get_spawn(i)
		if not _game.combat.is_alive(id):
			continue
		player.teleport_to(spawn.position, spawn.yaw)
		_game.combat.restore(id, SPAWN_PROTECTION_SECONDS)


## Whether weapons work: off during countdowns and results, on for PvP and the final.
func _set_combat(enabled: bool) -> void:
	for id in _members:
		var vitals := _game.combat.get_vitals(id)
		if vitals != null:
			vitals.accepts_commands = enabled
