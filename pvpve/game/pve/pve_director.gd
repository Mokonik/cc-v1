class_name PveDirector
extends RefCounted
## Runs the PvE phase for each participant: moves them into their private zone, counts down,
## sends waves of monsters through the gates, then the boss, and ends with a scored result.
## One Run per participant, all timed in ticks and seeded, so a phase is reproducible.
##
## Flow: COUNTDOWN -> WAVES (until phase_seconds) -> BOSS (until it dies or time runs out) -> DONE.

enum Phase { COUNTDOWN, WAVES, BOSS, DONE }

## Difficulty scaling (1.0 = base): count follows difficulty directly; health and damage follow
## it more gently; later waves are a little tougher.
const HP_PER_DIFFICULTY := 0.6
const DAMAGE_PER_DIFFICULTY := 0.4
const HP_PER_WAVE := 0.08
## Ticks between monsters of one wave, so a wave streams out of the gates.
const SPAWN_STAGGER_TICKS := 6
const GRUNT_WEIGHT := 6.0
const SPITTER_WEIGHT := 3.0
const BRUTE_WEIGHT := 1.5

class Run extends RefCounted:
	var owner_id := 0
	var config: PveConfig
	var phase := Phase.COUNTDOWN
	var start_tick := 0
	var phase_end_tick := 0
	var waves_end_tick := 0
	var next_wave_tick := 0
	var waves_started := 0
	var boss_monster_id := 0
	var boss_scheduled := false
	var boss_start_tick := 0
	## {"tick", "def_id", "gate", "wave", "hp_mult", "damage_mult", "is_boss"}
	var pending: Array[Dictionary] = []
	var result := PveResult.new()

## owner id -> Run, only while a run is active.
var runs: Dictionary = {}
## owner id -> PveResult of the most recent finished run.
var last_results: Dictionary = {}

var _events: EventBus
var _combat: CombatSystem
var _monsters: MonsterSystem
var _zones: ZoneManager
var _catalog: MonsterCatalog
var _get_player: Callable
var _base_config: PveConfig
## Callable(owner_id) -> ModifierAggregate: world modifiers that apply to that player's phase.
var get_modifier: Callable
var _neutral := ModifierAggregate.new()
var _seed := 1
var _tick := 0


func setup(events: EventBus, combat: CombatSystem, monsters: MonsterSystem, zones: ZoneManager,
		catalog: MonsterCatalog, get_player: Callable, config: PveConfig) -> void:
	_events = events
	_combat = combat
	_monsters = monsters
	_zones = zones
	_catalog = catalog
	_get_player = get_player
	_base_config = config


func set_seed(value: int) -> void:
	_seed = value


func base_config() -> PveConfig:
	return _base_config


func is_running(owner_id: int) -> bool:
	return runs.has(owner_id)


func get_run(owner_id: int) -> Run:
	return runs.get(owner_id)


## Starts a phase for a player. Returns "" on success or the reason it could not start.
## phase_seconds or difficulty below zero use the configured defaults.
func start_run(owner_id: int, phase_seconds := -1.0, difficulty := -1.0) -> String:
	if runs.has(owner_id):
		return "Already in a PvE phase."
	var player: Player = _get_player.call(owner_id)
	if player == null:
		return "No such player."
	if not _combat.is_alive(owner_id):
		return "Wait until you respawn."
	var run := Run.new()
	run.owner_id = owner_id
	run.config = _base_config.duplicate()
	if phase_seconds > 0.0:
		run.config.phase_seconds = phase_seconds
	if difficulty > 0.0:
		run.config.difficulty = difficulty
	run.start_tick = _tick
	run.result.player_id = owner_id
	run.result.difficulty = run.config.difficulty
	run.phase_end_tick = _tick + WeaponDef.seconds_to_ticks(run.config.countdown_seconds)

	_zones.enter(player, owner_id)
	_combat.heal(owner_id, _combat.get_vitals(owner_id).max_hp)
	runs[owner_id] = run
	_events.pve_started.emit(owner_id, run.config.phase_seconds)
	_events.pve_phase.emit(owner_id, &"countdown", run.config.countdown_seconds)
	return ""


## Ends a phase early. Returns false if the player was not in one.
func stop_run(owner_id: int) -> bool:
	var run: Run = runs.get(owner_id)
	if run == null:
		return false
	_finish(run, &"stopped")
	return true


## Jumps from the wave phase straight to the boss.
func skip_to_boss(owner_id: int) -> bool:
	var run: Run = runs.get(owner_id)
	if run == null or run.phase == Phase.DONE or run.phase == Phase.BOSS:
		return false
	if run.phase == Phase.COUNTDOWN:
		_begin_waves(run)
	_begin_boss(run)
	return true


func step(tick: int) -> void:
	_tick = tick
	var ids: Array = runs.keys()
	ids.sort()
	for id: int in ids:
		var run: Run = runs.get(id)
		if run == null:
			continue
		if _get_player.call(id) == null:
			_finish(run, &"stopped")
			continue
		_step_run(run, tick)


## A monster owned by this run's player died: count it.
func record_kill(owner_id: int, def_id: StringName, monster_id: int, xp := 0, sabotage_points := 0) -> void:
	var run: Run = runs.get(owner_id)
	if run == null:
		return
	run.result.add_kill(def_id)
	run.result.xp += xp
	run.result.sabotage_points += sabotage_points
	if monster_id == run.boss_monster_id and run.boss_monster_id != 0:
		run.result.boss_defeated = true
		run.result.boss_time_seconds = float(_tick - run.boss_start_tick) / Engine.physics_ticks_per_second


func record_loot(owner_id: int, label: String) -> void:
	var run: Run = runs.get(owner_id)
	if run != null:
		run.result.loot.append(label)


func record_death(owner_id: int) -> void:
	var run: Run = runs.get(owner_id)
	if run != null:
		run.result.deaths += 1


## Seconds left in the current phase (0 once finished).
func seconds_left(owner_id: int) -> float:
	var run: Run = runs.get(owner_id)
	if run == null:
		return 0.0
	return maxf(float(run.phase_end_tick - _tick) / Engine.physics_ticks_per_second, 0.0)


func phase_name(run: Run) -> StringName:
	match run.phase:
		Phase.COUNTDOWN:
			return &"countdown"
		Phase.WAVES:
			return &"waves"
		Phase.BOSS:
			return &"boss"
	return &"done"


# ---- phases ---------------------------------------------------------------------------

func _step_run(run: Run, tick: int) -> void:
	_release_pending(run, tick)
	match run.phase:
		Phase.COUNTDOWN:
			if tick >= run.phase_end_tick:
				_begin_waves(run)
		Phase.WAVES:
			if tick >= run.next_wave_tick and tick < run.waves_end_tick:
				_spawn_wave(run, tick)
			if tick >= run.waves_end_tick:
				if run.config.boss_enabled:
					_begin_boss(run)
				else:
					_finish(run, &"time_up")
		Phase.BOSS:
			if run.result.boss_defeated:
				_finish(run, &"boss_defeated")
			elif tick >= run.phase_end_tick:
				_finish(run, &"boss_timeout")


func _begin_waves(run: Run) -> void:
	run.phase = Phase.WAVES
	var length := WeaponDef.seconds_to_ticks(run.config.phase_seconds)
	run.waves_end_tick = _tick + length
	run.phase_end_tick = run.waves_end_tick
	run.next_wave_tick = _tick
	_events.pve_phase.emit(run.owner_id, &"waves", run.config.phase_seconds)


func _begin_boss(run: Run) -> void:
	run.phase = Phase.BOSS
	run.boss_start_tick = _tick + WeaponDef.seconds_to_ticks(run.config.boss_telegraph)
	run.phase_end_tick = _tick + WeaponDef.seconds_to_ticks(run.config.boss_telegraph + run.config.boss_time_limit)
	_events.pve_phase.emit(run.owner_id, &"boss", run.config.boss_time_limit)
	if run.boss_scheduled:
		return
	run.boss_scheduled = true
	var gate := _farthest_gate(run)
	var telegraph := run.config.boss_telegraph
	_events.gate_pulse.emit(run.owner_id, gate, telegraph)
	run.pending.append({
		"tick": run.boss_start_tick,
		"def_id": run.config.boss_id,
		"gate": gate,
		"wave": run.waves_started,
		"hp_mult": _hp_mult(run, 1) * _modifier(run).hp_mult,
		"damage_mult": _damage_mult(run) * _modifier(run).damage_mult,
		"is_boss": true,
	})


func _spawn_wave(run: Run, tick: int) -> void:
	run.waves_started += 1
	var wave := run.waves_started
	var config := run.config
	var modifier := _modifier(run)
	var wanted := roundi((config.base_wave_size + config.wave_growth * (wave - 1)) * config.difficulty * modifier.count_mult)
	var alive := _monsters.count_owned_by(run.owner_id) + run.pending.size()
	var count := mini(wanted, maxi(config.alive_cap - alive, 0))
	var gates := _usable_gates(run)
	var telegraph_ticks := WeaponDef.seconds_to_ticks(config.spawn_telegraph)
	for i in count:
		var gate: int = gates[int(_roll(run, wave, i, 1) * gates.size()) % gates.size()]
		run.pending.append({
			"tick": tick + telegraph_ticks + i * SPAWN_STAGGER_TICKS,
			"def_id": _pick_type(run, wave, i),
			"gate": gate,
			"wave": wave,
			"hp_mult": _hp_mult(run, wave) * modifier.hp_mult,
			"damage_mult": _damage_mult(run) * modifier.damage_mult,
			"is_boss": false,
		})
		_events.gate_pulse.emit(run.owner_id, gate, config.spawn_telegraph + i * SPAWN_STAGGER_TICKS / float(Engine.physics_ticks_per_second))
	run.next_wave_tick = tick + WeaponDef.seconds_to_ticks(config.wave_interval)
	_events.pve_wave.emit(run.owner_id, wave, count)


## Spawns every pending monster whose time has come.
func _release_pending(run: Run, tick: int) -> void:
	if run.pending.is_empty():
		return
	var zone := _zones.get_zone(run.owner_id)
	if zone == null:
		return
	var waiting: Array[Dictionary] = []
	for entry in run.pending:
		if entry.tick > tick:
			waiting.append(entry)
			continue
		var monster_id := _monsters.spawn(entry.def_id, zone.gate_position(entry.gate), run.owner_id,
			entry.hp_mult, entry.damage_mult, entry.wave)
		if entry.is_boss:
			run.boss_monster_id = monster_id
	run.pending = waiting


func _finish(run: Run, reason: StringName) -> void:
	if run.phase == Phase.DONE:
		return
	run.phase = Phase.DONE
	var result := run.result
	result.reason = reason
	result.waves_survived = run.waves_started
	result.duration_seconds = float(_tick - run.start_tick) / Engine.physics_ticks_per_second
	result.score = PveScoring.score(result, _catalog)
	run.pending.clear()
	_monsters.clear_owned_by(run.owner_id)
	var player: Player = _get_player.call(run.owner_id)
	if player != null:
		_zones.leave(player, run.owner_id)
	_zones.free_zone(run.owner_id)
	runs.erase(run.owner_id)
	last_results[run.owner_id] = result
	_events.pve_finished.emit(run.owner_id, result, reason)


# ---- scaling and choices ----------------------------------------------------------------

func _modifier(run: Run) -> ModifierAggregate:
	return get_modifier.call(run.owner_id) if get_modifier.is_valid() else _neutral


func _hp_mult(run: Run, wave: int) -> float:
	return (1.0 + (run.config.difficulty - 1.0) * HP_PER_DIFFICULTY) * (1.0 + HP_PER_WAVE * (wave - 1))


func _damage_mult(run: Run) -> float:
	return 1.0 + (run.config.difficulty - 1.0) * DAMAGE_PER_DIFFICULTY


## Which monster comes next: grunts always, spitters and brutes join in at their wave.
func _pick_type(run: Run, wave: int, index: int) -> StringName:
	var weights := {&"grunt": GRUNT_WEIGHT}
	if wave >= run.config.spitter_from_wave:
		weights[&"spitter"] = SPITTER_WEIGHT
	if wave >= run.config.brute_from_wave:
		weights[&"brute"] = BRUTE_WEIGHT
	var total := 0.0
	for id: StringName in weights:
		total += weights[id]
	var target := _roll(run, wave, index, 2) * total
	for id: StringName in [&"grunt", &"spitter", &"brute"]:
		if not weights.has(id):
			continue
		target -= weights[id]
		if target < 0.0:
			return id
	return &"grunt"


## Gates far enough from the player not to spawn monsters on top of them.
func _usable_gates(run: Run) -> Array[int]:
	var zone := _zones.get_zone(run.owner_id)
	var player: Player = _get_player.call(run.owner_id)
	var usable: Array[int] = []
	if zone == null or player == null:
		return [0]
	for i in zone.gate_count():
		if zone.gate_position(i).distance_to(player.global_position) >= run.config.spawn_min_distance:
			usable.append(i)
	if usable.is_empty():
		for i in zone.gate_count():
			usable.append(i)
	return usable


func _farthest_gate(run: Run) -> int:
	var zone := _zones.get_zone(run.owner_id)
	var player: Player = _get_player.call(run.owner_id)
	var best := 0
	var best_distance := -1.0
	if zone == null or player == null:
		return 0
	for i in zone.gate_count():
		var distance := zone.gate_position(i).distance_to(player.global_position)
		if distance > best_distance:
			best_distance = distance
			best = i
	return best


## Stateless pseudo-random float in [0, 1): the same wave and slot always get the same number.
func _roll(run: Run, wave: int, index: int, salt: int) -> float:
	return float(hash([_seed, run.owner_id, wave, index, salt]) & 0xFFFFFF) / float(0x1000000)
