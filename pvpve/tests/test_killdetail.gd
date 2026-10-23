# Headless tests for kill details (how a player died), bot combat and bot loadouts.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_killdetail.gd
extends SceneTree

const HUMAN_SPAWN := Vector3(0.0, 0.1, 22.0)

var _failures := 0
var _main: Node


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# The root is not inside the tree yet during _initialize; wait a frame before building nodes.
	await process_frame
	await _test_pistol_kill()
	await _test_sword_kill()
	await _test_arrow_kills()
	await _test_orb_kills()
	await _test_airborne_kill()
	await _test_environmental_and_console_kills()
	await _test_bots_fight_switch()
	await _test_bot_weapon_chooser()
	await _test_bot_vs_player_fight()
	_test_model_weapon_loot()
	await _test_botfire_console()
	if _main != null:
		_main.free()
		_main = null
	print("kill detail tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


# ---- helpers -------------------------------------------------------------------------------

class Rig extends RefCounted:
	var game: Game
	var human: Player
	var source: ScriptedSource
	var details: Array[Dictionary] = []
	var deaths := 0


func _new_rig(seed_value := 1) -> Rig:
	if _main != null:
		_main.free()
	_main = load("res://world/main.tscn").instantiate()
	_main.start_bots = 0
	root.add_child(_main)
	var rig := Rig.new()
	rig.game = _main.get_node("Game")
	rig.game.set_seed(seed_value)
	rig.human = rig.game.get_human()
	rig.human.input_source.queue_free()
	rig.source = ScriptedSource.new()
	rig.human.input_source = rig.source
	rig.human.add_child(rig.source)
	rig.game.events.kill_detail.connect(func(victim: int, killer: int, weapon: StringName, distance: float, airborne: bool, full: bool, direct: bool) -> void:
		rig.details.append({"victim": victim, "killer": killer, "weapon": weapon, "distance": distance, "airborne": airborne, "full": full, "direct": direct}))
	rig.game.events.player_died.connect(func(_v: int, _k: int, _w: StringName) -> void: rig.deaths += 1)
	await _frames(3)
	return rig


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _aim_at(rig: Rig, body: Combatant) -> void:
	var from := rig.human.eye_position()
	var to := body.chest_position()
	rig.source.yaw = atan2(-(to.x - from.x), -(to.z - from.z))
	rig.source.pitch = atan2(to.y - from.y, Vector2(to.x - from.x, to.z - from.z).length())


## Gives the human a weapon and selects it.
func _arm(rig: Rig, weapon_id: StringName, slot: int) -> void:
	rig.game.combat.give_weapon(1, weapon_id)
	rig.source.select(slot)
	await _frames(2)


func _fire(rig: Rig, ticks := 2) -> void:
	rig.source.press_fire()
	await _frames(ticks)
	rig.source.release_fire()


# ---- kill classification --------------------------------------------------------------------

func _test_pistol_kill() -> void:
	print("pistol kill")
	var rig := await _new_rig()
	var dummy := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 12.0))
	await _frames(3)
	rig.game.combat.set_hp(dummy.player_id, 4.0)
	await _fire(rig)
	await _frames(3)
	_check(rig.details.size() == 1 and rig.deaths == 1, "one death produces one kill detail")
	var d := rig.details[0]
	_check(d.victim == dummy.player_id and d.killer == 1 and d.weapon == &"pistol", "it names the victim, killer and weapon")
	_check(absf(d.distance - 12.0) < 1.0, "the distance is shooter to impact (%.1f m)" % d.distance)
	_check(not d.airborne and not d.full and d.direct, "a grounded pistol kill is not airborne, not full-power, and direct")


func _test_sword_kill() -> void:
	print("sword kill")
	var rig := await _new_rig()
	await _arm(rig, &"sword", 2)
	var dummy := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 2.0))
	await _frames(3)
	rig.game.combat.set_hp(dummy.player_id, 5.0)
	await _fire(rig)
	await _frames(30)
	var d := rig.details[0]
	_check(d.weapon == &"sword" and d.distance < 3.0, "a sword kill reports the sword at close range (%.1f m)" % d.distance)


func _test_arrow_kills() -> void:
	print("arrow kills")
	var rig := await _new_rig()
	await _arm(rig, &"bow", 3)
	var far := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 24.0))
	await _frames(3)
	rig.game.combat.set_hp(far.player_id, 5.0)
	rig.source.press_fire()
	await _frames(WeaponDef.seconds_to_ticks(0.7) + 4)
	_aim_at(rig, far)
	rig.source.pitch += 0.03  # arrows drop, so aim a touch high at long range
	await _frames(1)
	rig.source.release_fire()
	await _frames(120)
	_check(rig.details.size() == 1, "a distant arrow kill is reported")
	if rig.details.size() == 1:
		var d := rig.details[0]
		_check(d.weapon == &"bow" and d.full and d.direct and d.distance > 18.0, "a full draw from far away is full-power and over 18 m (%.1f m)" % d.distance)

	rig = await _new_rig()
	await _arm(rig, &"bow", 3)
	var near := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 8.0))
	await _frames(3)
	rig.game.combat.set_hp(near.player_id, 5.0)
	rig.source.press_fire()
	await _frames(WeaponDef.seconds_to_ticks(0.7) + 4)
	rig.source.release_fire()
	await _frames(60)
	_check(rig.details.size() == 1 and rig.details[0].full and rig.details[0].distance < 12.0, "a full draw at close range is still full-power but short (%.1f m)" % (rig.details[0].distance if rig.details.size() > 0 else -1.0))

	rig = await _new_rig()
	await _arm(rig, &"bow", 3)
	var tap := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 8.0))
	await _frames(3)
	rig.game.combat.set_hp(tap.player_id, 5.0)
	await _fire(rig, 1)
	await _frames(90)
	_check(rig.details.size() == 1 and not rig.details[0].full, "a quick tap shot is not full-power")


func _test_orb_kills() -> void:
	print("orb kills")
	var rig := await _new_rig()
	await _arm(rig, &"orb", 4)
	var direct := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 10.0))
	await _frames(3)
	rig.game.combat.set_hp(direct.player_id, 5.0)
	await _fire(rig, 1)
	await _frames(100)
	_check(rig.details.size() == 1 and rig.details[0].weapon == &"orb" and rig.details[0].direct, "an orb that hits a player directly is a direct kill")

	rig = await _new_rig()
	await _arm(rig, &"orb", 4)
	var splashed := rig.game.spawn_dummy(Vector3(2.0, 0.0, HUMAN_SPAWN.z - 10.0))
	rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 10.0))
	await _frames(3)
	rig.game.combat.set_hp(splashed.player_id, 5.0)
	await _fire(rig, 1)
	await _frames(100)
	var splash_kills := rig.details.filter(func(d: Dictionary) -> bool: return d.victim == splashed.player_id)
	_check(splash_kills.size() == 1 and not splash_kills[0].direct and not splash_kills[0].full, "a kill by splash is marked as not direct")


func _test_airborne_kill() -> void:
	print("airborne kill")
	var rig := await _new_rig()
	var dummy := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 10.0))
	await _frames(3)
	dummy.global_position.y = 6.0
	dummy.velocity = Vector3.ZERO
	await _frames(2)
	_check(not dummy.is_on_floor(), "the dummy is in the air")
	var settling := rig.game.spawn_dummy(Vector3(8.0, 0.4, HUMAN_SPAWN.z - 10.0))
	await _frames(1)
	rig.game.combat.kill(settling.player_id, 1, &"pistol")
	await _frames(1)
	_check(rig.details.size() == 1 and not rig.details[0].airborne, "a body just above the floor (settling or on a ramp) is not airborne")
	rig.details.clear()
	rig.game.combat.kill(dummy.player_id, 1, &"pistol")
	await _frames(2)
	_check(rig.details.size() == 1 and rig.details[0].airborne, "a victim who dies in the air is reported as airborne")
	rig.game.combat.respawn_now(dummy.player_id)
	await _frames(6)
	rig.game.combat.kill(dummy.player_id, 1, &"pistol")
	await _frames(2)
	_check(rig.details.size() == 2 and not rig.details[1].airborne, "and one who dies standing is not")


func _test_environmental_and_console_kills() -> void:
	print("environmental kills")
	var rig := await _new_rig()
	var dummy := rig.game.spawn_dummy(Vector3(0.0, 0.0, 0.0))
	await _frames(6)
	rig.game.combat.apply_damage(dummy.player_id, 500.0, 0, &"storm", dummy.global_position)
	await _frames(2)
	_check(rig.details.size() == 1 and rig.details[0].killer == 0 and rig.details[0].weapon == &"storm", "a death with no killer reports killer 0 and the cause")
	var monster := rig.game.monsters.spawn(&"grunt", Vector3(10.0, 0.1, 10.0), 999)
	rig.game.combat.kill(monster, 1, &"pistol")
	await _frames(3)
	_check(rig.details.size() == 1, "monster deaths do not produce player kill details")


# ---- bot combat ---------------------------------------------------------------------------------

func _test_bots_fight_switch() -> void:
	print("bots fight switch")
	var rig := await _new_rig()
	var bot := rig.game.spawn_player(PlayerRegistry.Kind.BOT)
	await _frames(3)
	_check(not rig.game.combat.get_vitals(bot.player_id).accepts_commands and not rig.game.bots_fight, "bots are passive by default")
	rig.game.set_bots_fight(true)
	_check(rig.game.combat.get_vitals(bot.player_id).accepts_commands and rig.game.bots_fight, "turning it on lets existing bots fight")
	var second := rig.game.spawn_player(PlayerRegistry.Kind.BOT)
	_check(rig.game.combat.get_vitals(second.player_id).accepts_commands, "and bots spawned afterwards")
	_check(rig.game.combat.get_vitals(1).accepts_commands, "the human is unaffected")
	rig.game.set_bots_fight(false)
	_check(not rig.game.combat.get_vitals(bot.player_id).accepts_commands and not rig.game.combat.get_vitals(second.player_id).accepts_commands, "turning it off silences them again")


func _test_bot_weapon_chooser() -> void:
	print("bot weapon chooser")
	var rig := await _new_rig()
	rig.game.set_bots_fight(true)
	var bot := rig.game.spawn_player(PlayerRegistry.Kind.BOT)
	rig.game.combat.give_weapon(bot.player_id, &"sword")
	await _frames(3)
	rig.game.combat.get_vitals(1).god = true
	var vitals := rig.game.combat.get_vitals(bot.player_id)
	var swaps := {"sword": 0}
	rig.game.events.weapon_changed.connect(func(pid: int, weapon_id: StringName) -> void:
		if pid == bot.player_id and weapon_id == &"sword":
			swaps.sword += 1)
	rig.human.global_position = bot.global_position + Vector3(0.0, 0.0, -2.0)
	await _frames(40)
	_check(swaps.sword >= 1, "a bot with a sword takes it out when its target is within 3 m")
	rig.human.global_position = bot.global_position + Vector3(0.0, 0.0, -14.0)
	await _frames(60)
	_check(vitals.current_slot == 1, "and goes back to the pistol when the target is far away")

	rig = await _new_rig()
	rig.game.set_bots_fight(true)
	var plain := rig.game.spawn_player(PlayerRegistry.Kind.BOT)
	await _frames(3)
	rig.game.combat.get_vitals(1).god = true
	rig.human.global_position = plain.global_position + Vector3(0.0, 0.0, -2.0)
	await _frames(40)
	_check(rig.game.combat.get_vitals(plain.player_id).current_slot == 1, "a bot without a sword keeps the pistol up close")


func _test_bot_vs_player_fight() -> void:
	print("bot fights back")
	var rig := await _new_rig(3)
	rig.game.set_bots_fight(true)
	var bot := rig.game.spawn_player(PlayerRegistry.Kind.BOT, BotPresets.make(2))
	await _frames(3)
	var tally := {"damage": 0.0, "shots": 0}
	rig.game.events.damage_dealt.connect(func(target: int, source: int, amount: float, _p: Vector3, _w: StringName) -> void:
		if target == 1 and source == bot.player_id:
			tally.damage += amount)
	rig.game.events.weapon_fired.connect(func(pid: int, _w: StringName, _o: Vector3, _d: Vector3, _e: Vector3) -> void:
		if pid == bot.player_id:
			tally.shots += 1)
	rig.human.global_position = Vector3(0.0, 0.1, 10.0)
	bot.global_position = Vector3(0.0, 0.1, -10.0)
	await _frames(600)
	_check(tally.shots > 5, "a bot with fighting enabled shoots at a player in view (%d shots)" % tally.shots)
	_check(tally.damage > 0.0, "and its shots hurt (%.0f damage)" % tally.damage)

	rig = await _new_rig(3)
	var quiet := rig.game.spawn_player(PlayerRegistry.Kind.BOT, BotPresets.make(2))
	await _frames(3)
	var quiet_tally := {"shots": 0}
	rig.game.events.weapon_fired.connect(func(pid: int, _w: StringName, _o: Vector3, _d: Vector3, _e: Vector3) -> void:
		if pid == quiet.player_id:
			quiet_tally.shots += 1)
	rig.human.global_position = Vector3(0.0, 0.1, 10.0)
	quiet.global_position = Vector3(0.0, 0.1, -10.0)
	await _frames(600)
	_check(quiet_tally.shots == 0 and rig.game.combat.get_vitals(1).hp == 100.0, "a passive bot never fires, as before")


# ---- model loot -----------------------------------------------------------------------------------

func _test_model_weapon_loot() -> void:
	print("model weapon loot")
	var monsters := MonsterCatalog.new()
	var config: PveConfig = load("res://content/pve_config.tres")
	var strong_total := 0
	var weak_total := 0
	for seed_value in range(40):
		strong_total += BotPveModel.simulate(0.9, config, monsters, seed_value, 2).weapon_loot.size()
		weak_total += BotPveModel.simulate(0.3, config, monsters, seed_value, 2).weapon_loot.size()
	_check(strong_total > weak_total, "a stronger bot finds more weapons (%d vs %d over 40 phases)" % [strong_total, weak_total])
	var a := BotPveModel.simulate(0.6, config, monsters, 5, 2)
	var b := BotPveModel.simulate(0.6, config, monsters, 5, 2)
	_check(a.weapon_loot == b.weapon_loot, "weapon rolls are deterministic for a seed")
	var valid := true
	for seed_value in range(30):
		for id in BotPveModel.simulate(0.7, config, monsters, seed_value, 2).weapon_loot:
			valid = valid and id in [&"sword", &"bow", &"orb", &"pistol"]
	_check(valid, "rolled ids are real weapons")
	var labels_match := true
	for seed_value in range(30):
		var result := BotPveModel.simulate(0.7, config, monsters, seed_value, 2)
		labels_match = labels_match and result.loot.size() == result.weapon_loot.size()
	_check(labels_match, "each weapon is also listed as a readable loot label")


func _test_botfire_console() -> void:
	print("botfire console")
	var rig := await _new_rig()
	var game := rig.game
	var bot := game.spawn_player(PlayerRegistry.Kind.BOT)
	_check(DevCommands.run("botfire", game).contains("do not"), "botfire alone reports the state")
	_check(DevCommands.run("botfire on", game).contains("shoot") and game.combat.get_vitals(bot.player_id).accepts_commands, "botfire on lets bots shoot back")
	_check(DevCommands.run("botfire", game).contains("do fire"), "and reports it")
	_check(DevCommands.run("botfire off", game).contains("passive") and not game.combat.get_vitals(bot.player_id).accepts_commands, "botfire off makes them passive")
	_check(DevCommands.run("botfire maybe", game).begins_with("Usage"), "a bad argument prints usage")
	_check(DevCommands.run("help", game).contains("botfire"), "help lists botfire")
	var result := game.run_bot_pve(bot.player_id, 2)
	var owned := game.combat.get_vitals(bot.player_id).owned_slots()
	var found := {}
	for weapon_id in result.weapon_loot:
		found[weapon_id] = true
	var has_all_found := true
	var extra_weapons := 0
	for weapon_id: StringName in found:
		has_all_found = has_all_found and owned.has(game.weapons.get_def(weapon_id).slot)
		if weapon_id != &"pistol":
			extra_weapons += 1
	_check(has_all_found and owned.size() == 1 + extra_weapons, "run_bot_pve gives the bot the weapons its result found (%s, owns slots %s)" % [result.weapon_loot, owned])
