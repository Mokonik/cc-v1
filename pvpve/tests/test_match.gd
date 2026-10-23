# Headless tests for the match loop: phase order and timing, wagers, the mark, modifiers, the
# final and a whole autopilot match, including determinism.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_match.gd
extends SceneTree

var _failures := 0
var _main: Node


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await process_frame
	await _test_needs_two_players()
	await _test_full_demo_match()
	await _test_determinism()
	await _test_human_pve_run()
	await _test_final_mechanics()
	await _test_wager_choice_and_modifier_pick()
	await _test_console()
	if _main != null:
		_main.free()
		_main = null
	print("match tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


class Rig extends RefCounted:
	var game: Game
	# A getter, not a reference: the event lambdas below capture the rig, and a rig holding the
	# director would form a cycle through the director's event bus and leak at exit.
	var director: MatchDirector:
		get: return game.match_director
	var phases: Array = []
	var champion := -1
	var marks: Array[int] = []
	var offers := 0
	var chosen: Array[StringName] = []


func _new_rig(bots := 2, seed_value := 1, demo := true, cycles := 3) -> Rig:
	# Always build from the same point in the frame, or two rigs would tick one frame apart.
	await process_frame
	if _main != null:
		_main.free()
	_main = load("res://world/main.tscn").instantiate()
	_main.start_bots = bots
	root.add_child(_main)
	var rig := Rig.new()
	rig.game = _main.get_node("Game")
	rig.game.set_seed(seed_value)
	var config := MatchPresets.fast()
	config.cycles = cycles
	rig.director.set_config(config)
	if demo:
		rig.game.set_autopilot(1, true)
	var game := rig.game
	game.events.match_phase.connect(func(phase: StringName, cycle: int, seconds: float) -> void:
		rig.phases.append([phase, cycle, game.tick, seconds]))
	game.events.match_finished.connect(func(id: int) -> void: rig.champion = id)
	game.events.mark_changed.connect(func(id: int) -> void: rig.marks.append(id))
	game.events.modifier_offered.connect(func(_p: int, _ids: Array) -> void: rig.offers += 1)
	game.events.modifier_chosen.connect(func(_p: int, id: StringName) -> void: rig.chosen.append(id))
	# Align on the game's own tick (the first physics frame can land either side of a node's first tick).
	while game.tick < 5:
		await physics_frame
	return rig


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _until_phase(rig: Rig, phase: StringName, max_seconds := 400.0) -> bool:
	var limit := WeaponDef.seconds_to_ticks(max_seconds)
	var waited := 0
	while rig.director.phase != phase and waited < limit:
		await physics_frame
		waited += 1
	return rig.director.phase == phase


func _snapshot(rig: Rig) -> Array:
	var rows: Array = []
	for entry in rig.director.standings.entries:
		rows.append([entry.player_id, entry.cycle, entry.kind, entry.amount])
	return rows


func _test_needs_two_players() -> void:
	print("start rules")
	var rig := await _new_rig(0, 1, false)
	_check(rig.director.start() != "", "a match needs at least two players")
	_check(not rig.director.is_running() and rig.director.phase == MatchDirector.LOBBY, "and stays in the lobby")
	_check(not rig.director.skip() and not rig.director.stop(), "skip and stop do nothing in the lobby")


func _test_full_demo_match() -> void:
	print("full demo match")
	var rig := await _new_rig()
	var director := rig.director
	var game := rig.game
	var gear_checked := [false]
	game.events.match_phase.connect(func(phase: StringName, cycle: int, _s: float) -> void:
		if phase == MatchDirector.PVE and cycle == 2 and not gear_checked[0]:
			gear_checked[0] = true
			rig.phases.append(["loot_reset", game.combat.get_vitals(2).owned_slots().size()]))
	_check(director.start() == "", "the match starts")
	_check(director.phase == MatchDirector.PVE and director.cycle == 1, "straight into the first PvE phase")
	var finished := await _until_phase(rig, MatchDirector.VICTORY)
	_check(finished, "the match reaches the victory screen")
	var order: Array[StringName] = []
	for row in rig.phases:
		if row.size() == 4:
			order.append(row[0])
	var expected: Array[StringName] = []
	for c in 3:
		expected.append_array([&"pve", &"pve_results", &"wager", &"pvp_countdown", &"pvp", &"pvp_results"])
	expected.append_array([&"final", &"victory"])
	_check(order == expected, "phases run in order: %s" % [order])
	_check(rig.champion == director.standings.leader() and rig.champion > 0, "the champion is the standings leader (player %d)" % rig.champion)
	var standings := director.standings
	var pve_total := standings.sum_kind(&"pve")
	_check(pve_total > 0, "PvE scores were booked (%d)" % pve_total)
	_check(standings.sum_kind(&"wager") == 0, "wagers net to zero across the table")
	var final_sum := standings.sum_kind(&"final")
	_check(final_sum == 400 + 200 + 100, "final placement points were awarded (%d)" % final_sum)
	_check(director.final_placement.size() == 3, "and everyone is placed in the final")
	_check(rig.marks.size() == 3 and rig.marks.all(func(id: int) -> bool: return id > 0), "the leader was marked after each PvP (%s)" % [rig.marks])
	_check(rig.offers == 2 and rig.chosen.size() == 2, "modifiers were offered and picked after the first two PvP matches only (%d/%d)" % [rig.offers, rig.chosen.size()])
	_check(director.pve_results.size() == 3 and director.pve_results[1].size() == 3, "every cycle has a PvE result per player")
	var any_pvp := standings.sum_kinds(1, [&"kill"]) + standings.sum_kinds(2, [&"kill"]) + standings.sum_kinds(3, [&"kill"])
	_check(any_pvp > 0, "bots fought in PvP and scored kill points (%d)" % any_pvp)
	var tick_gaps_ok := true
	for i in range(1, rig.phases.size()):
		if rig.phases[i].size() == 4 and rig.phases[i - 1].size() == 4:
			var seconds: float = rig.phases[i - 1][3]
			var gap: int = rig.phases[i][2] - rig.phases[i - 1][2]
			if rig.phases[i - 1][0] not in [&"pve", &"final"] and absi(gap - WeaponDef.seconds_to_ticks(seconds)) > 2:
				tick_gaps_ok = false
	_check(tick_gaps_ok, "timed phases last exactly their configured length")
	var loot_rows := rig.phases.filter(func(row: Array) -> bool: return row[0] == "loot_reset")
	_check(loot_rows.size() == 1 and loot_rows[0][1] == 1, "loot reset at the start of a cycle: back to the starter pistol only")
	await _frames(WeaponDef.seconds_to_ticks(4.0))
	_check(director.phase == MatchDirector.LOBBY and not director.is_running(), "afterwards it returns to the lobby")
	_check(game.combat.respawn_enabled and not game.bots_fight, "and combat is back to sandbox rules")
	_check(game.modifiers.aggregate_for(1).is_neutral(), "with no modifier left over")


## Physics bodies in two worlds of one process settle a hair differently, so the whole-match
## comparison runs each game in its own fresh process.
func _dump_match(seed_value: int) -> String:
	var output: Array = []
	var args := PackedStringArray(["--headless", "--fixed-fps", "60", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/support/match_dump.gd", "--", str(seed_value)])
	OS.execute(OS.get_executable_path(), args, output, true)
	var text := "\n".join(output)
	var lines: Array[String] = []
	for line in text.split("\n"):
		if line.begins_with("LEDGER") or line.begins_with("CHAMPION"):
			lines.append(line)
	return "\n".join(lines)


func _test_determinism() -> void:
	print("determinism")
	var first := _dump_match(7)
	var second := _dump_match(7)
	_check(first.contains("LEDGER") and first.contains("CHAMPION"), "a match plays through in its own process")
	_check(first == second, "the same seed gives an identical ledger and champion")
	var other := _dump_match(8)
	_check(other != first, "a different seed gives a different game")
	if first != second:
		print("    first:  ", first.left(600))
		print("    second: ", second.left(600))


func _test_human_pve_run() -> void:
	print("a real PvE run for the human")
	var rig := await _new_rig(1, 3, false, 1)
	var game := rig.game
	game.combat.get_vitals(1).god = true
	rig.director.start()
	await _frames(WeaponDef.seconds_to_ticks(8.0))
	_check(game.pve.is_running(1), "the human is in a real PvE run")
	_check(game.zones.is_inside(1), "inside their own zone")
	_check(not game.pve.is_running(2), "while the bot is modeled, not simulated")
	_check(is_equal_approx(game.pve.get_run(1).config.difficulty, 1.0), "at base difficulty before anyone is marked")
	rig.director.skip()
	await _frames(5)
	_check(rig.director.phase == MatchDirector.PVE_RESULTS, "skipping ends the PvE phase for everyone")
	_check(not game.pve.is_running(1) and not game.zones.is_inside(1), "and brings the human back to the arena")
	_check(rig.director.standings.entries.size() == 2, "both players got a PvE entry")
	rig.director.set_mark(2)
	_check(is_equal_approx(rig.director.difficulty_for(2), 1.35) and is_equal_approx(rig.director.difficulty_for(1), 1.0), "the marked player faces +0.35 difficulty")
	rig.director.stop()
	_check(not rig.director.is_running(), "stop ends the match")


func _test_final_mechanics() -> void:
	print("the final")
	var rig := await _new_rig(2, 5)
	var game := rig.game
	var director := rig.director
	director.start(1)
	_check(director.jump_to_final(), "the console can jump to the final")
	await _frames(5)
	_check(director.phase == MatchDirector.FINAL and not game.combat.respawn_enabled, "one life each: respawns are off")
	var spawned := true
	for id in director.members():
		spawned = spawned and game.combat.is_alive(id) and game.combat.get_vitals(id).hp == game.combat.get_vitals(id).max_hp
	_check(spawned, "everyone starts at full health")
	var first_radius := director.safe_radius
	await _frames(WeaponDef.seconds_to_ticks(12.0))
	_check(director.safe_radius < first_radius, "the safe area shrinks (%.1f -> %.1f m)" % [first_radius, director.safe_radius])
	# Everyone far outside with no way back: the storm should finish them, last one standing wins.
	game.combat.get_vitals(1).god = true
	game.combat.get_vitals(2).god = true
	var victim := 3
	var hp_before := game.combat.get_vitals(victim).hp
	game.get_player(victim).teleport_to(Vector3(40.0, 5.0, 0.0), 0.0)
	game.combat.get_vitals(victim).protected_until_tick = 0
	await _frames(60)
	_check(game.combat.get_vitals(victim).hp < hp_before or not game.combat.is_alive(victim), "standing outside the safe area hurts")
	director.skip()
	await _frames(5)
	_check(director.phase == MatchDirector.VICTORY, "the final ends and the victory phase starts")
	_check(director.final_placement.size() == 3 and director.final_placement.has(victim), "placements are recorded for all three")
	_check(director.final_placement[0] != victim, "the player who stayed in the storm did not win")
	var points := director.standings.sum_kind(&"final")
	_check(points == 700, "700 final points were handed out in total (%d)" % points)
	director.stop()


func _test_wager_choice_and_modifier_pick() -> void:
	print("menu choices")
	var rig := await _new_rig(2, 2, false, 2)
	var game := rig.game
	var director := rig.director
	game.combat.get_vitals(1).god = true
	director.start()
	_check(not director.choose(1, 1), "menu keys do nothing during PvE")
	director.skip()
	await _frames(3)
	await _until_phase(rig, MatchDirector.WAGER)
	director.standings.add(1, 1, &"pve", 200)
	_check(director.choose(1, 3), "in the wager phase, key 3 stakes the biggest option")
	_check(director.wager_choices.get(1) == 2, "recorded as option 3 (50%)")
	_check(not director.choose(1, 4), "an option that does not exist is refused")
	_check(director.wager_choices.has(2) and director.wager_choices.has(3), "bots have already placed their stakes")
	await _until_phase(rig, MatchDirector.PVP_COUNTDOWN)
	_check(director.stakes[1] == director.config.stake_for(director.standings.total(1), 2), "the stake is locked in as points when the wager closes")
	_check(not game.combat.get_vitals(2).accepts_commands, "weapons are locked during the countdown")
	await _until_phase(rig, MatchDirector.PVP)
	_check(game.combat.get_vitals(2).accepts_commands and game.bots_fight, "and unlocked, bots included, in PvP")
	# Make the human the PvP winner, then pick a modifier by hand.
	director.standings.add(1, 1, &"kill", 500)
	director.skip()
	await _frames(3)
	_check(director.phase == MatchDirector.PVP_RESULTS and director.pvp_placement[0] == 1, "the PvP winner is first")
	_check(director.offer_picker == 1 and director.offer_cards.size() == 3, "and is offered three modifier cards")
	var net := 0
	for id: int in director.last_wager_net:
		net += director.last_wager_net[id]
	_check(net == 0, "the wager settled to zero")
	var card := director.offer_cards[1]
	_check(director.choose(1, 2), "key 2 picks the second card")
	_check(game.modifiers.modifier_id == card, "and that modifier is now active (%s)" % card)
	_check(director.marked_id == director.standings.leader(), "the standings leader wears the mark")
	director.stop()


func _test_console() -> void:
	print("console")
	var rig := await _new_rig(0, 1, false)
	var game := rig.game
	var run := func(line: String) -> String: return DevCommands.run(line, game)
	_check(run.call("match").begins_with("No match running"), "status with no match")
	_check(run.call("match start").begins_with("Need at least two"), "a match needs a rival")
	_check(run.call("standings").begins_with("No standings"), "standings before a match")
	_check(run.call("match fast").contains("Short phases"), "match fast shortens the phases")
	_check(run.call("match start 9").begins_with("Usage"), "too many cycles prints usage")
	_check(run.call("match demo x").begins_with("Usage"), "a bad demo cycle count prints usage")
	_check(run.call("match demo 1").begins_with("Demo match"), "match demo adds a rival, switches on the autopilot and starts")
	_check(game.autopilot.has(1) and rig.director.is_running(), "the human is on autopilot")
	_check(run.call("match status").begins_with("pve"), "status shows the phase")
	_check(run.call("match start").begins_with("A match is already"), "starting twice is refused")
	_check(run.call("standings").contains("Standings"), "standings prints a table")
	_check(run.call("mark 2").contains("marked") and rig.director.marked_id == 2, "mark puts the mark on a player")
	_check(run.call("mark 99").begins_with("No such"), "marking nobody is refused")
	_check(run.call("mark off").begins_with("Mark removed") and rig.director.marked_id == 0, "mark off clears it")
	_check(run.call("modifier fog").contains("Fog"), "modifier activates a world modifier")
	_check(game.modifiers.modifier_id == &"fog", "and it is active")
	_check(run.call("modifier nope").begins_with("Unknown"), "unknown modifiers are refused")
	_check(run.call("modifier off").begins_with("No world"), "modifier off clears it")
	_check(run.call("match wager 2").begins_with("Not possible"), "wagers are refused outside the wager phase")
	_check(run.call("match skip").begins_with("Skipped"), "match skip ends the phase")
	_check(run.call("match final").begins_with("Jumped"), "match final jumps to the final")
	_check(run.call("match stop").begins_with("Match stopped") and not game.autopilot.has(1), "match stop ends it and returns control")
	_check(run.call("match stop").begins_with("No match"), "stopping twice says so")
	_check(run.call("match bogus").begins_with("Usage"), "an unknown subcommand prints usage")
	_check(run.call("help").contains("match demo"), "help lists the match commands")
