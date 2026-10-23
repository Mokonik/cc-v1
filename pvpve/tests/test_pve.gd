# Headless tests for PvE zones and the run director: phases, waves, boss, results, scoring.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_pve.gd
extends SceneTree

var _failures := 0
var _main: Node


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# The root is not inside the tree yet during _initialize; wait a frame before building nodes.
	await process_frame
	_test_scoring()
	await _test_zones()
	await _test_start_rules()
	await _test_phase_flow()
	await _test_wave_scaling_and_cap()
	await _test_spawn_rules()
	await _test_boss_flow()
	await _test_boss_timeout_and_stop()
	await _test_death_in_zone()
	await _test_kills_are_recorded()
	await _test_runs_are_deterministic()
	await _test_pve_console()
	if _main != null:
		_main.free()
		_main = null
	print("pve tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


# ---- helpers ------------------------------------------------------------------------------

class Rig extends RefCounted:
	var game: Game
	var human: Player
	var phases: Array[StringName] = []
	var waves: Array[Vector2i] = []
	var spawns: Array[Dictionary] = []
	var pulses := 0
	var finished: Array[PveResult] = []
	var reasons: Array[StringName] = []
	var human_start := Vector3.ZERO


func _new_rig(seed_value := 1, god := true) -> Rig:
	if _main != null:
		_main.free()
	_main = load("res://world/main.tscn").instantiate()
	_main.start_bots = 0
	root.add_child(_main)
	var rig := Rig.new()
	rig.game = _main.get_node("Game")
	rig.game.set_seed(seed_value)
	rig.human = rig.game.get_human()
	var game := rig.game
	game.combat.get_vitals(1).god = god
	game.events.pve_phase.connect(func(_o: int, phase: StringName, _s: float) -> void: rig.phases.append(phase))
	game.events.pve_wave.connect(func(_o: int, wave: int, count: int) -> void: rig.waves.append(Vector2i(wave, count)))
	game.events.gate_pulse.connect(func(_o: int, _g: int, _s: float) -> void: rig.pulses += 1)
	game.events.pve_finished.connect(func(_o: int, result: PveResult, reason: StringName) -> void:
		rig.finished.append(result)
		rig.reasons.append(reason))
	game.events.monster_spawned.connect(func(id: int, def_id: StringName, position: Vector3) -> void:
		var human := game.get_human()
		rig.spawns.append({"tick": game.tick, "id": id, "def": def_id, "pos": position,
			"player_distance": position.distance_to(human.global_position) if human != null else -1.0}))
	await _frames(3)
	rig.human_start = rig.human.global_position
	return rig


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _ticks(seconds: float) -> int:
	return WeaponDef.seconds_to_ticks(seconds)


# ---- scoring -------------------------------------------------------------------------------

func _test_scoring() -> void:
	print("scoring")
	var catalog := MonsterCatalog.new()
	var result := PveResult.new()
	_check(PveScoring.score(result, catalog) == 0, "an empty result scores nothing")
	result.add_kill(&"grunt")
	result.add_kill(&"grunt")
	result.add_kill(&"spitter")
	result.add_kill(&"brute")
	_check(result.kill_count() == 4, "kills are counted by type")
	_check(PveScoring.score(result, catalog) == 2 * 10 + 18 + 40, "kills score their monster's value (78)")
	result.waves_survived = 3
	_check(PveScoring.score(result, catalog) == 78 + 45, "each wave survived adds 15")
	result.boss_defeated = true
	result.add_kill(&"warden")
	_check(PveScoring.score(result, catalog) == 78 + 45 + 100 + 300, "defeating the boss adds a bonus and the boss's own value")
	result.deaths = 2
	_check(PveScoring.score(result, catalog) == 78 + 45 + 100 + 300 - 80, "each death costs 40")
	var base := PveScoring.score(result, catalog)
	result.difficulty = 2.0
	_check(PveScoring.score(result, catalog) == roundi(base * 1.5), "difficulty 2 is worth 50% more")
	result.difficulty = 0.5
	_check(PveScoring.score(result, catalog) == roundi(base * 0.75), "difficulty 0.5 is worth 25% less")
	var losing := PveResult.new()
	losing.deaths = 5
	_check(PveScoring.score(losing, catalog) == 0, "a score never goes below zero")


# ---- zones -------------------------------------------------------------------------------

func _test_zones() -> void:
	print("zones")
	var rig := await _new_rig()
	var game := rig.game
	var zone := game.zones.enter(rig.human, 1)
	await _frames(3)
	_check(zone != null and game.zones.is_inside(1), "entering builds the zone and marks the player as inside")
	_check(zone.contains(rig.human.global_position), "the player is now inside it")
	_check(absf(rig.human.global_position.x - ZoneManager.SPACING) < 1.0, "far from the sandbox, at the zone's offset (x %.0f)" % rig.human.global_position.x)
	_check(zone.get_navigation_mesh().get_polygon_count() > 0, "the zone has its own baked navigation mesh (%d polygons)" % zone.get_navigation_mesh().get_polygon_count())
	_check(zone.gate_count() == 8, "eight monster gates")
	var gates_ok := true
	for i in zone.gate_count():
		gates_ok = gates_ok and zone.contains(zone.gate_position(i))
	_check(gates_ok, "every gate is inside the zone")
	await _frames(30)
	_check(rig.human.is_on_floor(), "the player stands on the zone floor")
	_check(game.zones.ensure_zone(1) == zone and game.zones.zone_count() == 1, "asking again returns the same zone")

	var bot := game.spawn_player(PlayerRegistry.Kind.BOT)
	var second := game.zones.enter(bot, bot.player_id)
	_check(second != zone and second.global_position.distance_to(zone.global_position) >= ZoneManager.SPACING, "another player gets their own zone, far away")
	_check(not zone.contains(bot.global_position) and not second.contains(rig.human.global_position), "zones do not contain each other's players")

	# A shot from one zone never reaches another: aim straight along the line between them.
	var space := rig.human.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(rig.human.eye_position(), bot.eye_position(), CombatLayers.PLAYER_SHOTS, [rig.human.get_rid()])
	var hit := space.intersect_ray(ray)
	_check(hit.is_empty() or not (hit.collider is Combatant), "a shot toward another zone cannot hit its player")

	_check(game.zones.leave(rig.human, 1) and not game.zones.is_inside(1), "leaving takes the player out of the zone")
	_check(rig.human.global_position.distance_to(rig.human_start) < 0.1, "and puts them back exactly where they were")
	_check(not game.zones.leave(rig.human, 1), "leaving twice does nothing")
	game.zones.free_zone(1)
	await _frames(3)
	_check(game.zones.get_zone(1) == null and game.zones.zone_count() == 1, "a freed zone is gone")


# ---- run director -----------------------------------------------------------------------------

func _test_start_rules() -> void:
	print("start rules")
	var rig := await _new_rig()
	var game := rig.game
	_check(game.pve.start_run(99) == "No such player.", "an unknown player cannot start")
	_check(game.pve.start_run(1, 20.0) == "", "a player can start a phase")
	_check(game.pve.is_running(1) and game.zones.is_inside(1), "the run is active and the player is in their zone")
	_check(game.pve.start_run(1) == "Already in a PvE phase.", "starting twice is refused")
	_check(game.pve.get_run(1).config.phase_seconds == 20.0, "the phase length can be overridden")
	_check(game.pve.base_config().phase_seconds == 240.0, "without changing the shared config")
	_check(game.pve.stop_run(1) and not game.pve.stop_run(1), "stop works once")

	rig = await _new_rig(1, false)
	rig.game.combat.kill(1, 0)
	await _frames(2)
	_check(rig.game.pve.start_run(1) == "Wait until you respawn.", "a dead player cannot start")
	rig.game.combat.set_hp(1, 30.0)
	await _frames(WeaponDef.seconds_to_ticks(3.0) + 5)
	var before := rig.game.combat.get_vitals(1)
	before.hp = 40.0
	_check(rig.game.pve.start_run(1, 20.0) == "" and before.hp == before.max_hp, "starting a phase heals you to full")
	rig.game.pve.stop_run(1)


func _test_phase_flow() -> void:
	print("phase flow")
	var rig := await _new_rig()
	var game := rig.game
	game.pve.start_run(1, 25.0)
	_check(rig.phases == [&"countdown"], "a run starts in the countdown")
	await _frames(_ticks(5.0) - 3)
	_check(game.pve.phase_name(game.pve.get_run(1)) == &"countdown" and game.monsters.count() == 0, "no monsters during the countdown")
	await _frames(10)
	_check(rig.phases == [&"countdown", &"waves"], "waves begin after the 5 s countdown")
	await _frames(_ticks(25.0))
	_check(rig.phases == [&"countdown", &"waves", &"boss"], "the boss phase follows when the wave timer runs out")
	_check(game.pve.seconds_left(1) > 0.0 and game.pve.seconds_left(1) <= 152.0, "the boss phase has its own timer (%.0f s)" % game.pve.seconds_left(1))
	_check(rig.waves.size() == 2 and rig.waves[0].x == 1 and rig.waves[1].x == 2, "two waves arrived 20 s apart in a 25 s phase")
	await _frames(_ticks(3.0))
	var bosses := 0
	for spawn in rig.spawns:
		if spawn.def == &"warden":
			bosses += 1
	_check(bosses == 1, "exactly one Warden steps out after its telegraph")
	game.pve.stop_run(1)


func _test_wave_scaling_and_cap() -> void:
	print("wave scaling and cap")
	var rig := await _new_rig()
	rig.game.pve.start_run(1, 25.0, 1.0)
	await _frames(_ticks(5.0) + _ticks(22.0))
	_check(rig.waves == [Vector2i(1, 4), Vector2i(2, 5)], "at difficulty 1 the waves have 4 then 5 monsters (%s)" % [rig.waves])
	rig.game.pve.stop_run(1)

	rig = await _new_rig()
	rig.game.pve.start_run(1, 25.0, 2.0)
	await _frames(_ticks(5.0) + _ticks(22.0))
	_check(rig.waves == [Vector2i(1, 8), Vector2i(2, 10)], "at difficulty 2 the waves are twice as big (%s)" % [rig.waves])
	var record := rig.game.monsters.get_record(MonsterSystem.FIRST_ID)
	var hp := rig.game.combat.get_vitals(MonsterSystem.FIRST_ID).max_hp
	_check(is_equal_approx(hp, 60.0 * 1.6), "monsters are tougher: grunt hp %.0f at difficulty 2" % hp)
	_check(is_equal_approx(record.damage_mult, 1.4), "and hit harder (x%.1f)" % record.damage_mult)
	rig.game.pve.stop_run(1)

	rig = await _new_rig()
	rig.game.pve.start_run(1, 25.0, 4.0)
	await _frames(_ticks(5.0) + _ticks(23.0))
	_check(rig.waves[0] == Vector2i(1, 16) and rig.waves[1].y == 4, "the alive cap of 20 limits the second wave (%s)" % [rig.waves])
	_check(rig.game.monsters.count() <= 20, "never more than 20 monsters alive (%d)" % rig.game.monsters.count())
	rig.game.pve.stop_run(1)


func _test_spawn_rules() -> void:
	print("spawn rules")
	var rig := await _new_rig()
	var game := rig.game
	game.pve.start_run(1, 25.0)
	await _frames(_ticks(5.0) + _ticks(25.0))
	var zone := game.zones.get_zone(1)
	var grunts_only_first := true
	var all_far := true
	var all_inside := true
	var saw_spitter := false
	var first_wave_ids: Array[int] = []
	for spawn in rig.spawns:
		if spawn.id < MonsterSystem.FIRST_ID + 4:
			first_wave_ids.append(spawn.id)
			grunts_only_first = grunts_only_first and spawn.def == &"grunt"
		all_far = all_far and spawn.player_distance >= 12.0
		all_inside = all_inside and zone.contains(spawn.pos)
		saw_spitter = saw_spitter or spawn.def == &"spitter"
	_check(rig.spawns.size() >= 9, "monsters came through the gates (%d)" % rig.spawns.size())
	_check(grunts_only_first and first_wave_ids.size() == 4, "the first wave is all grunts")
	_check(all_far, "no monster appears within 12 m of the player")
	_check(all_inside, "every monster appears inside the zone")
	_check(rig.pulses >= 9, "each gate glowed before releasing its monster (%d pulses)" % rig.pulses)
	var owned := game.monsters.count_owned_by(1)
	_check(owned == game.monsters.count(), "every monster belongs to the player's zone (%d)" % owned)
	game.pve.stop_run(1)
	await _frames(3)
	_check(game.monsters.count() == 0, "ending the phase removes the monsters")
	_check(rig.human.global_position.distance_to(rig.human_start) < 0.1, "and returns the player")


func _test_boss_flow() -> void:
	print("boss flow")
	var rig := await _new_rig()
	var game := rig.game
	game.pve.start_run(1, 60.0)
	_check(game.pve.skip_to_boss(1), "the boss can be called early")
	_check(not game.pve.skip_to_boss(1), "but only once")
	await _frames(_ticks(2.0) + 10)
	var boss_id := game.pve.get_run(1).boss_monster_id
	_check(boss_id >= MonsterSystem.FIRST_ID and game.monster_defs.get_def(&"warden") != null, "the Warden is out (id %d)" % boss_id)
	_check(game.combat.get_vitals(boss_id).max_hp == 900.0, "with base health at difficulty 1")
	game.combat.kill(boss_id, 1, &"pistol")
	await _frames(3)
	_check(rig.reasons == [&"boss_defeated"], "killing the boss ends the phase as a victory")
	var result := rig.finished[0]
	_check(result.boss_defeated and result.kills.get(&"warden", 0) == 1, "the result records the boss kill")
	_check(result.boss_time_seconds >= 0.0 and result.boss_time_seconds < 5.0, "and how long it took (%.1f s)" % result.boss_time_seconds)
	_check(result.score == PveScoring.score(result, game.monster_defs) and result.score > 0, "the score uses the shared formula (%d)" % result.score)
	_check(game.pve.last_results.get(1) == result and not game.pve.is_running(1), "the result is kept and the run is over")
	_check(game.zones.get_zone(1) == null and game.monsters.count() == 0, "the zone and monsters are cleaned up")
	_check(rig.human.global_position.distance_to(rig.human_start) < 0.1, "the player is back where they started")


func _test_boss_timeout_and_stop() -> void:
	print("boss timeout and stop")
	var rig := await _new_rig()
	var game := rig.game
	game.pve.start_run(1, 60.0)
	game.pve.get_run(1).config.boss_time_limit = 5.0
	game.pve.skip_to_boss(1)
	await _frames(_ticks(2.0) + _ticks(5.0) + 10)
	_check(rig.reasons == [&"boss_timeout"] and not rig.finished[0].boss_defeated, "failing to kill the boss in time ends the phase without a win")

	rig = await _new_rig()
	game = rig.game
	game.pve.start_run(1, 60.0)
	await _frames(_ticks(8.0))
	_check(game.pve.stop_run(1) and rig.reasons == [&"stopped"], "stopping reports why it ended")
	_check(rig.finished[0].waves_survived >= 1 and rig.finished[0].duration_seconds > 7.0, "and records how far it got (%d waves, %.1f s)" % [rig.finished[0].waves_survived, rig.finished[0].duration_seconds])

	rig = await _new_rig()
	game = rig.game
	game.pve.start_run(1, 60.0)
	game.pve.get_run(1).config.boss_enabled = false
	await _frames(_ticks(5.0) + _ticks(60.0) + 5)
	_check(rig.reasons == [&"time_up"] and not rig.phases.has(&"boss"), "with the boss disabled the phase just ends when time is up")

	rig = await _new_rig()
	game = rig.game
	game.pve.start_run(1, 60.0)
	game.remove_player(1)
	_check(not game.pve.is_running(1), "removing a player ends their phase")


func _test_death_in_zone() -> void:
	print("death in zone")
	var rig := await _new_rig(1, false)
	var game := rig.game
	game.pve.start_run(1, 60.0)
	await _frames(5)
	var zone := game.zones.get_zone(1)
	game.combat.kill(1, MonsterSystem.FIRST_ID, &"grunt")
	await _frames(2)
	_check(game.pve.get_run(1).result.deaths == 1, "a death is counted against the run")
	await _frames(_ticks(3.0) + 5)
	_check(game.combat.is_alive(1) and zone.contains(rig.human.global_position), "and the player respawns inside the zone, not back in the sandbox")
	var start := zone.player_start().position
	_check(rig.human.global_position.distance_to(start) < 1.0, "at the zone's player start")
	game.pve.stop_run(1)
	_check(rig.finished[0].deaths == 1, "the final result keeps the death count")


func _test_kills_are_recorded() -> void:
	print("kills")
	var rig := await _new_rig()
	var game := rig.game
	game.pve.start_run(1, 60.0)
	var waited := 0
	while game.monsters.count() < 4 and waited < _ticks(15.0):
		await physics_frame
		waited += 1
	_check(game.monsters.count() >= 4, "the first wave has arrived (%d monsters)" % game.monsters.count())
	var killed := 0
	for id in game.monsters.records.keys():
		if killed >= 3:
			break
		game.combat.kill(id, 1, &"pistol")
		killed += 1
	await _frames(3)
	var run := game.pve.get_run(1)
	_check(run.result.kill_count() == 3, "kills of the zone's monsters are recorded (%d)" % run.result.kill_count())
	game.combat.kill(1, 0)
	game.combat.respawn_now(1)
	var outsider := game.monsters.spawn(&"grunt", Vector3(10.0, 0.1, 5.0))
	game.combat.kill(outsider, 1, &"pistol")
	await _frames(3)
	_check(run.result.kill_count() == 3, "a monster outside the zone does not count")
	game.pve.stop_run(1)


func _spawn_log(seed_value: int) -> Array[String]:
	var rig := await _new_rig(seed_value)
	rig.game.pve.start_run(1, 25.0, 1.5)
	await _frames(_ticks(5.0) + _ticks(23.0))
	var log: Array[String] = []
	for spawn in rig.spawns:
		log.append("%d %s %.2f %.2f" % [spawn.tick, spawn.def, spawn.pos.x, spawn.pos.z])
	rig.game.pve.stop_run(1)
	return log


func _test_runs_are_deterministic() -> void:
	print("determinism")
	var first := await _spawn_log(7)
	var again := await _spawn_log(7)
	var other := await _spawn_log(8)
	_check(first.size() >= 10, "the run produced spawns (%d)" % first.size())
	_check(first == again, "the same seed gives identical spawn ticks, types and gates")
	_check(first != other, "a different seed gives a different pattern")


func _test_pve_console() -> void:
	print("pve console")
	var rig := await _new_rig()
	var game := rig.game
	_check(DevCommands.run("pve status", game).begins_with("Not in a PvE phase"), "status before any run")
	_check(DevCommands.run("pve start x", game).begins_with("Usage"), "a bad duration prints usage")
	_check(DevCommands.run("pve start 30", game).contains("30"), "pve start 30 begins a 30 s phase")
	_check(game.pve.is_running(1), "and the run is active")
	_check(DevCommands.run("pve start", game).contains("Already"), "starting again says so")
	await _frames(_ticks(6.0))
	_check(DevCommands.run("pve status", game).contains("waves") and DevCommands.run("pve status", game).contains("wave 1"), "status shows the phase and wave")
	_check(DevCommands.run("pve skip", game).contains("Boss"), "pve skip calls the boss")
	_check(DevCommands.run("pve stop", game).contains("ended") and not game.pve.is_running(1), "pve stop ends the phase")
	_check(DevCommands.run("pve stop", game).contains("not in"), "stopping twice says so")
	_check(DevCommands.run("pve status", game).begins_with("Last phase"), "status afterwards shows the last result")
	_check(DevCommands.run("pve nonsense", game).begins_with("Usage"), "an unknown subcommand prints usage")
	_check(DevCommands.run("difficulty 2.5", game).contains("2.50") and game.pve_difficulty == 2.5, "difficulty sets the level for new phases")
	_check(DevCommands.run("difficulty 99", game).contains("4.00"), "difficulty is capped at 4")
	_check(DevCommands.run("difficulty x", game).begins_with("Usage"), "bad difficulty prints usage")
	DevCommands.run("difficulty 2", game)
	DevCommands.run("pve start 30", game)
	_check(is_equal_approx(game.pve.get_run(1).config.difficulty, 2.0), "a new phase uses the chosen difficulty")
	game.pve.stop_run(1)
	_check(DevCommands.run("help", game).contains("pve start"), "help lists the pve commands")
