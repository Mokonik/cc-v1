# Headless tests for monsters: the brain's state machine (pure logic) and real fights.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_monsters.gd
extends SceneTree

const HUMAN_SPAWN := Vector3(0.0, 0.1, 22.0)

var _failures := 0
var _main: Node
var _catalog := MonsterCatalog.new()


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# The root is not inside the tree yet during _initialize; wait a frame before building nodes.
	await process_frame
	_test_catalog()
	_test_grunt_brain()
	_test_spitter_brain()
	_test_brute_brain()
	_test_boss_brain()
	_test_brain_is_deterministic()
	await _test_spawning()
	await _test_grunt_fight()
	await _test_spitter_fight()
	await _test_brute_fight()
	await _test_boss_fight()
	await _test_killing_monsters()
	await _test_player_weapons_hit_monsters()
	await _test_separation()
	await _test_targeting()
	await _test_fights_are_deterministic()
	await _test_monster_console()
	if _main != null:
		_main.free()
		_main = null
	print("monster tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


# ---- brain helpers ----------------------------------------------------------------

## Feeds a brain a static situation for one tick.
func _think(brain: MonsterBrain, tick: int, distance: float, los := true, hp := 1.0, blocked := false) -> MonsterBrain.Command:
	var pos := Vector3.ZERO
	var target := Vector3(0.0, 0.0, -distance)
	return brain.think(tick, pos, 0.0, target, true, los, target, Vector3.ZERO, hp, blocked)


func _brain(id: StringName, monster_id := 1000) -> MonsterBrain:
	var brain := MonsterBrain.new(_catalog.get_def(id), monster_id)
	brain.start(0, 1)
	return brain


## First tick at or after `from` on which the brain reports an attack landing.
func _first_strike(brain: MonsterBrain, from: int, distance: float, limit := 600) -> Array:
	for tick in range(from, from + limit):
		var command := _think(brain, tick, distance)
		if command.strike != &"":
			return [tick, command.strike]
	return [-1, &""]


# ---- brain tests ------------------------------------------------------------------

func _test_catalog() -> void:
	print("catalog")
	_check(_catalog.ids() == [&"grunt", &"spitter", &"brute", &"warden"], "four monsters in file order")
	var grunt := _catalog.get_def(&"grunt")
	_check(grunt.has_melee() and not grunt.has_spit() and not grunt.has_slam() and not grunt.has_charge(), "grunt only melees")
	var spitter := _catalog.get_def(&"spitter")
	_check(spitter.has_spit() and not spitter.has_melee() and spitter.keep_distance > 0.0, "spitter spits and keeps distance")
	var brute := _catalog.get_def(&"brute")
	_check(brute.has_slam() and brute.has_charge() and not brute.has_melee(), "brute slams and charges")
	var warden := _catalog.get_def(&"warden")
	_check(warden.is_boss and warden.has_slam() and warden.has_charge() and warden.has_spit() and warden.summon_count > 0, "the boss has every ability and summons")
	_check(warden.max_hp > brute.max_hp * 4.0, "the boss is far tankier than a brute")
	_check(grunt.max_hp / 8.0 <= 8.0 and brute.max_hp > grunt.max_hp * 2.0, "grunts die to about eight pistol hits, brutes are much tougher")


func _test_grunt_brain() -> void:
	print("grunt brain")
	var def := _catalog.get_def(&"grunt")
	var brain := _brain(&"grunt")
	var far := _think(brain, 1, 20.0)
	_check(far.move.is_equal_approx(Vector3(0.0, 0.0, -1.0)) and far.speed == def.move_speed, "walks toward a far target at its speed")
	_check(far.strike == &"" and far.telegraph == &"", "does not attack from afar")
	var no_target := brain.think(2, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, Vector3.ZERO, Vector3.ZERO, 1.0, false)
	_check(no_target.move == Vector3.ZERO and brain.state == MonsterBrain.State.IDLE, "idles without a target")

	brain = _brain(&"grunt")
	var started := -1
	var telegraph_seconds := 0.0
	for tick in range(1, 200):
		var command := _think(brain, tick, 1.2)
		if command.telegraph == &"melee":
			started = tick
			telegraph_seconds = command.telegraph_seconds
			break
	_check(started > 0 and is_equal_approx(telegraph_seconds, def.melee_windup), "winds up a melee attack when in reach (windup %.2f s)" % telegraph_seconds)
	var windup_ticks := WeaponDef.seconds_to_ticks(def.melee_windup)
	var strike_at := -1
	for tick in range(started + 1, started + 100):
		if _think(brain, tick, 1.2).strike == &"melee":
			strike_at = tick
			break
	_check(strike_at - started == windup_ticks, "the hit lands exactly one windup later (%d ticks)" % (strike_at - started))
	var second_start := -1
	for tick in range(strike_at + 1, strike_at + 200):
		if _think(brain, tick, 1.2).telegraph == &"melee":
			second_start = tick
			break
	_check(second_start - started == WeaponDef.seconds_to_ticks(def.melee_interval), "the next attack starts one melee interval after the last (%d ticks)" % (second_start - started))
	var holder := _brain(&"grunt")
	var stand := _think(holder, 1, def.melee_range * 0.5, true)
	_check(stand.move == Vector3.ZERO or stand.telegraph == &"melee", "stops pushing into its target once in reach")


func _test_spitter_brain() -> void:
	print("spitter brain")
	var def := _catalog.get_def(&"spitter")
	var brain := _brain(&"spitter")
	var close := _think(brain, 1, 5.0)
	_check(close.move.is_equal_approx(Vector3(0.0, 0.0, 1.0)), "backs away when the target is too close")
	var middle := _think(_brain(&"spitter"), 1, def.keep_distance)
	_check(absf(middle.move.dot(Vector3(0.0, 0.0, -1.0))) < 0.01 and middle.move.length() > 0.3, "circles at its preferred distance")
	var far := _think(_brain(&"spitter"), 1, def.keep_distance * 2.0, true)
	_check(far.move.z < 0.0, "closes in when too far to keep distance")

	brain = _brain(&"spitter")
	var started := -1
	for tick in range(1, 200):
		if _think(brain, tick, def.keep_distance).telegraph == &"spit":
			started = tick
			break
	_check(started > 0, "spits when it has line of sight")
	var landed := -1
	for tick in range(started + 1, started + 100):
		if _think(brain, tick, def.keep_distance).strike == &"spit":
			landed = tick
			break
	_check(landed - started == WeaponDef.seconds_to_ticks(def.spit_windup), "the spit leaves one windup after it starts (%d ticks)" % (landed - started))
	brain = _brain(&"spitter")
	var blind_telegraphs := 0
	for tick in range(1, 300):
		if _think(brain, tick, def.keep_distance, false).telegraph != &"":
			blind_telegraphs += 1
	_check(blind_telegraphs == 0, "never spits without line of sight")
	brain = _brain(&"spitter")
	var out_of_range := 0
	for tick in range(1, 300):
		if _think(brain, tick, def.spit_range + 8.0).telegraph != &"":
			out_of_range += 1
	_check(out_of_range == 0, "never spits beyond its range")


func _test_brute_brain() -> void:
	print("brute brain")
	var def := _catalog.get_def(&"brute")
	var brain := _brain(&"brute")
	var first_slam := _first_strike(brain, 1, 1.5)
	_check(first_slam[1] == &"slam", "slams a target that is close")

	brain = _brain(&"brute")
	var started := -1
	for tick in range(1, 200):
		if _think(brain, tick, 12.0).telegraph == &"charge":
			started = tick
			break
	_check(started > 0, "winds up a charge at mid range with line of sight")
	var charging_from := -1
	for tick in range(started + 1, started + 200):
		_think(brain, tick, 12.0)
		if brain.state == MonsterBrain.State.CHARGING:
			charging_from = tick
			break
	var running := _think(brain, charging_from + 1, 12.0)
	_check(running.speed == def.charge_speed and running.move.is_equal_approx(Vector3(0.0, 0.0, -1.0)), "charges straight at the target at charge speed")
	_check(charging_from - started == WeaponDef.seconds_to_ticks(def.charge_windup), "the charge starts one windup later (%d ticks)" % (charging_from - started))
	var stunned_at := -1
	for tick in range(charging_from + 2, charging_from + 20):
		_think(brain, tick, 12.0, true, 1.0, tick == charging_from + 5)
		if brain.state == MonsterBrain.State.STUNNED:
			stunned_at = tick
			break
	_check(stunned_at == charging_from + 5, "hitting a wall stuns it")
	var moves_while_stunned := 0
	for tick in range(stunned_at + 1, stunned_at + WeaponDef.seconds_to_ticks(def.stun_time) - 1):
		if _think(brain, tick, 12.0).move != Vector3.ZERO:
			moves_while_stunned += 1
	_check(moves_while_stunned == 0, "it cannot move while stunned")
	var recovered := false
	for tick in range(stunned_at + WeaponDef.seconds_to_ticks(def.stun_time), stunned_at + WeaponDef.seconds_to_ticks(def.stun_time) + 3):
		_think(brain, tick, 12.0)
		recovered = recovered or brain.state != MonsterBrain.State.STUNNED
	_check(recovered, "and recovers after the stun time")

	brain = _brain(&"brute")
	var hit_tick := -1
	var charge_started := -1
	for tick in range(1, 400):
		var command := _think(brain, tick, 12.0 if brain.state != MonsterBrain.State.CHARGING else 0.5)
		if command.telegraph == &"charge":
			charge_started = tick
		if command.strike == &"charge":
			hit_tick = tick
			break
	_check(hit_tick > charge_started and brain.state == MonsterBrain.State.STUNNED, "a charge that reaches its target strikes and then staggers")


func _test_boss_brain() -> void:
	print("boss brain")
	var def := _catalog.get_def(&"warden")
	var brain := _brain(&"warden")
	var summons := 0
	for tick in range(1, 20):
		if _think(brain, tick, 15.0, true, 0.8).summon:
			summons += 1
	_check(summons == 0, "no summons while healthy")
	for tick in range(20, 60):
		if _think(brain, tick, 15.0, true, 0.45).summon:
			summons += 1
	_check(summons == 1, "summons exactly once when health drops below half")
	_check(not brain.enraged, "not enraged yet")
	_think(brain, 60, 15.0, true, 0.30)
	_check(brain.enraged, "enrages below 35% health")
	var calm := _think(_brain(&"warden"), 1, 20.0, true, 1.0)
	var angry_brain := _brain(&"warden")
	var angry := _think(angry_brain, 1, 20.0, true, 0.2)
	_check(angry.speed > calm.speed and is_equal_approx(angry.speed / calm.speed, MonsterBrain.ENRAGE_SPEED), "an enraged boss moves faster (x%.2f)" % (angry.speed / calm.speed))
	var normal_windup := 0.0
	var brain_calm := _brain(&"warden")
	for tick in range(1, 200):
		var command := _think(brain_calm, tick, 1.0, true, 1.0)
		if command.telegraph == &"slam":
			normal_windup = command.telegraph_seconds
			break
	var enraged_windup := 0.0
	var brain_angry := _brain(&"warden")
	for tick in range(1, 200):
		var command := _think(brain_angry, tick, 1.0, true, 0.2)
		if command.telegraph == &"slam":
			enraged_windup = command.telegraph_seconds
			break
	_check(enraged_windup > 0.0 and is_equal_approx(enraged_windup, normal_windup * MonsterBrain.ENRAGE_INTERVAL), "and winds up faster (%.2f s vs %.2f s)" % [enraged_windup, normal_windup])
	_check(def.spit_count == 3, "the boss fires a three-orb volley")


func _brain_trace(seed_value: int) -> Array[String]:
	var brain := MonsterBrain.new(_catalog.get_def(&"brute"), 1007)
	brain.start(0, seed_value)
	var trace: Array[String] = []
	for tick in range(1, 400):
		var distance := 10.0 + 8.0 * sin(float(tick) * 0.05)
		var command := _think(brain, tick, distance, tick % 90 < 70, 1.0, tick % 53 == 0)
		trace.append("%d %d %s %s %.3f" % [tick, brain.state, command.strike, command.telegraph, command.speed])
	return trace


func _test_brain_is_deterministic() -> void:
	print("brain determinism")
	var first := _brain_trace(3)
	_check(first == _brain_trace(3), "the same seed gives an identical decision sequence")
	_check(first != _brain_trace(4), "a different seed staggers the first attacks differently")


# ---- integration helpers ------------------------------------------------------------

class Rig extends RefCounted:
	var game: Game
	var human: Player
	var source: ScriptedSource
	var damage: Array[Dictionary] = []
	var killed: Array[Dictionary] = []
	var telegraphs: Array[StringName] = []
	var projectiles := 0


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
	var game := rig.game
	game.events.damage_dealt.connect(func(target: int, source: int, amount: float, _p: Vector3, _w: StringName) -> void:
		rig.damage.append({"tick": game.combat.tick, "target": target, "source": source, "amount": amount}))
	game.events.monster_killed.connect(func(id: int, killer: int, _p: Vector3, def_id: StringName) -> void:
		rig.killed.append({"id": id, "killer": killer, "def": def_id}))
	game.events.monster_telegraph.connect(func(_id: int, ability: StringName, _s: float) -> void: rig.telegraphs.append(ability))
	game.events.projectile_spawned.connect(func(_i: int, _w: StringName, _p: Vector3, _v: Vector3) -> void: rig.projectiles += 1)
	await _frames(3)
	return rig


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


## Spawns a monster this far straight ahead of the human spawn (the human faces -Z).
func _spawn_ahead(rig: Rig, id: StringName, distance: float, x := 0.0, owner_id := 0) -> int:
	var monster_id := rig.game.monsters.spawn(id, Vector3(x, 0.1, HUMAN_SPAWN.z - distance), owner_id)
	await _frames(2)
	return monster_id


## Points the scripted human's view at a monster's chest (the shot starts at the eye).
func _aim_at(rig: Rig, body: Combatant) -> void:
	var from := rig.human.eye_position()
	var to := body.chest_position()
	var flat := Vector2(to.x - from.x, to.z - from.z)
	rig.source.yaw = atan2(-(to.x - from.x), -(to.z - from.z))
	rig.source.pitch = atan2(to.y - from.y, flat.length())


func _damage_from_monsters(rig: Rig) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in rig.damage:
		if entry.source >= MonsterSystem.FIRST_ID and entry.target == PlayerRegistry.HOST_ID:
			result.append(entry)
	return result


# ---- integration tests --------------------------------------------------------------

func _test_spawning() -> void:
	print("spawning")
	var rig := await _new_rig()
	var monsters := rig.game.monsters
	var id := await _spawn_ahead(rig, &"grunt", 10.0)
	_check(id == MonsterSystem.FIRST_ID, "the first monster gets id 1000")
	_check(monsters.spawn(&"nonexistent", Vector3.ZERO) == 0, "an unknown monster type is refused")
	var second := await _spawn_ahead(rig, &"brute", 12.0, 4.0)
	_check(second == id + 1, "ids increase")
	var vitals := rig.game.combat.get_vitals(id)
	_check(vitals != null and vitals.is_monster and vitals.hp == 60.0 and not vitals.accepts_commands, "a monster is a command-less combatant with its definition's hp")
	_check(rig.game.combat.get_vitals(second).max_hp == 160.0, "a brute has 160 hp")
	var scaled := monsters.spawn(&"grunt", Vector3(-4.0, 0.1, 10.0), 0, 2.0, 1.5)
	_check(rig.game.combat.get_vitals(scaled).max_hp == 120.0 and monsters.get_record(scaled).damage_mult == 1.5, "health and damage scaling apply at spawn")
	var body := rig.game.get_body(id)
	_check(body is Monster and body.collision_layer == CombatLayers.MONSTER and body.collision_mask == CombatLayers.WORLD, "the body is on the monster layer and only collides with the world")
	_check(rig.game.get_body(PlayerRegistry.HOST_ID) is Player and rig.game.get_body(5) == null, "get_body resolves players and monsters by id")
	_check(monsters.count() == 3 and monsters.count_owned_by(0) == 3, "monsters are counted")
	_check(rig.game.clear_monsters() == 3 and monsters.count() == 0 and rig.game.combat.get_vitals(id) == null, "clearing removes monsters and their vitals")


func _test_grunt_fight() -> void:
	print("grunt fight")
	var rig := await _new_rig()
	rig.game.combat.set_hp(1, 100.0)
	var grunt_id := await _spawn_ahead(rig, &"grunt", 1.3)
	await _frames(300)
	var hits := _damage_from_monsters(rig)
	_check(hits.size() >= 3, "a grunt keeps hitting a player in reach (%d hits)" % hits.size())
	var all_ten := true
	for hit in hits:
		all_ten = all_ten and hit.amount == 10.0 and hit.source == grunt_id
	_check(all_ten, "every hit is exactly 10 damage from that grunt")
	_check(hits.size() >= 2 and hits[1].tick - hits[0].tick == 66, "hits come one melee interval apart (%d ticks)" % (hits[1].tick - hits[0].tick if hits.size() >= 2 else -1))
	_check(rig.telegraphs.count(&"melee") >= hits.size(), "each hit was telegraphed first")
	var v := rig.game.combat.get_vitals(1)
	_check(not v.alive or v.hp == 100.0 - 10.0 * hits.size(), "the player's health matches the damage taken (%.0f)" % v.hp)

	rig = await _new_rig()
	var far_grunt := await _spawn_ahead(rig, &"grunt", 18.0)
	var start := rig.game.get_body(far_grunt).global_position
	await _frames(60)
	var moved := rig.game.get_body(far_grunt).global_position.distance_to(start)
	_check(moved > 3.0 and moved < 6.0, "a grunt walks toward the player at about 4 m/s (%.1f m in a second)" % moved)
	await _frames(240)
	var distance := rig.game.get_body(far_grunt).global_position.distance_to(rig.human.global_position)
	_check(distance < 2.6 and rig.game.get_body(far_grunt).global_position.y < 0.5, "and arrives and stands next to the player (%.1f m)" % distance)


func _test_spitter_fight() -> void:
	print("spitter fight")
	var rig := await _new_rig()
	var spitter_id := await _spawn_ahead(rig, &"spitter", 14.0)
	await _frames(360)
	var hits := _damage_from_monsters(rig)
	_check(rig.projectiles >= 2, "a spitter fires projectiles (%d)" % rig.projectiles)
	_check(hits.size() >= 1, "and some of them hit a player standing still (%d hits)" % hits.size())
	var all_spit := true
	for hit in hits:
		all_spit = all_spit and hit.amount == 12.0 and hit.source == spitter_id
	_check(all_spit, "spit hits deal 12 damage")
	var distance := rig.game.get_body(spitter_id).global_position.distance_to(rig.human.global_position)
	_check(distance > 8.0 and distance < 20.0, "it keeps its distance (%.1f m)" % distance)

	rig = await _new_rig()
	rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 8.0))
	var shooter := rig.game.monsters.spawn(&"spitter", Vector3(0.0, 0.1, HUMAN_SPAWN.z - 14.0))
	var blocker := rig.game.monsters.spawn(&"brute", Vector3(0.0, 0.1, HUMAN_SPAWN.z - 7.0))
	await _frames(5)
	rig.game.monsters.get_record(blocker).owner_id = 999  # holds still: its owner does not exist
	await _frames(300)
	var through := false
	for hit in _damage_from_monsters(rig):
		through = through or (hit.source == shooter and hit.amount == 12.0)
	_check(through, "spit passes through other monsters and still hits the player")
	_check(rig.game.combat.get_vitals(blocker).hp == 160.0, "and does not hurt the monster in the way")


func _test_brute_fight() -> void:
	print("brute fight")
	var rig := await _new_rig()
	await _spawn_ahead(rig, &"brute", 1.5)
	await _frames(240)
	var hits := _damage_from_monsters(rig)
	_check(hits.size() >= 1 and hits[0].amount == 30.0, "a brute's slam deals 30 damage (%s)" % [hits[0].amount if hits.size() > 0 else -1.0])

	rig = await _new_rig()
	var brute_id := await _spawn_ahead(rig, &"brute", 12.0)
	await _frames(240)
	hits = _damage_from_monsters(rig)
	_check(hits.size() >= 1 and hits[0].amount == 25.0, "a brute at range charges and the charge deals 25 (%s)" % [hits[0].amount if hits.size() > 0 else -1.0])
	_check(rig.telegraphs.has(&"charge"), "the charge was telegraphed")
	var record := rig.game.monsters.get_record(brute_id)
	_check(record.brain.state != MonsterBrain.State.IDLE, "the brute is still active afterwards")

	rig = await _new_rig()
	var slammer := await _spawn_ahead(rig, &"brute", 1.5)
	var bystander := await _spawn_ahead(rig, &"grunt", 1.5, 0.8)
	await _frames(200)
	_check(rig.game.combat.get_vitals(bystander).hp == 60.0, "a slam hurts players but not other monsters")


func _test_boss_fight() -> void:
	print("boss fight")
	var rig := await _new_rig()
	rig.game.combat.get_vitals(1).god = true
	var boss := await _spawn_ahead(rig, &"warden", 16.0)
	var combat := rig.game.combat
	_check(combat.get_vitals(boss).max_hp == 900.0 and rig.game.monsters.count() == 1, "the Warden starts alone with 900 hp")
	combat.apply_damage(boss, 460.0, 1, &"console", Vector3.ZERO)
	await _frames(5)
	_check(rig.game.monsters.count() == 5, "dropping below half health summons four grunts (%d monsters)" % rig.game.monsters.count())
	await _frames(120)
	_check(rig.game.monsters.count() == 5, "and only once")
	combat.apply_damage(boss, 130.0, 1, &"console", Vector3.ZERO)
	await _frames(3)
	_check(rig.game.monsters.get_record(boss).brain.enraged, "below 35% it enrages")
	var volley_before := rig.projectiles
	await _frames(300)
	_check(rig.telegraphs.has(&"spit") or rig.telegraphs.has(&"slam") or rig.telegraphs.has(&"charge"), "the boss uses its abilities")
	_check(rig.projectiles > volley_before or rig.projectiles >= 3, "the boss fired orbs")
	_check(rig.projectiles % 3 == 0, "orb volleys come in threes (%d orbs)" % rig.projectiles)


func _test_killing_monsters() -> void:
	print("killing monsters")
	var rig := await _new_rig()
	var id := await _spawn_ahead(rig, &"grunt", 10.0)
	var node := rig.game.get_body(id)
	rig.game.combat.get_vitals(1).god = true
	rig.source.press_fire()
	for i in 200:
		await physics_frame
		if is_instance_valid(node):
			_aim_at(rig, node)
	rig.source.release_fire()
	_check(rig.killed.size() == 1 and rig.killed[0].id == id and rig.killed[0].killer == 1 and rig.killed[0].def == &"grunt", "killing a monster reports who killed it and what it was")
	_check(rig.game.monsters.get_record(id) == null and rig.game.combat.get_vitals(id) == null, "a dead monster is forgotten")
	_check(rig.game.combat.apply_damage(id, 10.0, 1, &"pistol", Vector3.ZERO) == 0.0, "dead monsters take no more damage")
	_check(rig.game.combat.get_vitals(1).kills == 1, "the kill is credited to the player")
	_check(node.collision_layer == 0 and not node.alive, "the body stops blocking shots")
	await _frames(120)
	_check(not is_instance_valid(node), "and disappears after its death animation")


func _test_player_weapons_hit_monsters() -> void:
	print("player weapons vs monsters")
	var rig := await _new_rig()
	var combat := rig.game.combat
	combat.give_weapon(1, &"sword")
	combat.give_weapon(1, &"orb")
	combat.give_weapon(1, &"bow")
	combat.get_vitals(1).god = true
	rig.source.select(2)
	await _frames(2)
	var near := await _spawn_ahead(rig, &"brute", 2.4)
	rig.source.press_fire()
	await _frames(2)
	rig.source.release_fire()
	await _frames(40)
	_check(combat.get_vitals(near).hp == 140.0, "the sword hits a monster in reach for 20 (hp %.0f)" % combat.get_vitals(near).hp)

	rig = await _new_rig()
	combat = rig.game.combat
	combat.give_weapon(1, &"orb")
	combat.get_vitals(1).god = true
	rig.source.select(4)
	await _frames(2)
	var first := await _spawn_ahead(rig, &"brute", 14.0)
	var second := await _spawn_ahead(rig, &"brute", 14.0, 2.0)
	rig.game.monsters.get_record(first).owner_id = 999
	rig.game.monsters.get_record(second).owner_id = 999
	rig.source.press_fire()
	await _frames(2)
	rig.source.release_fire()
	await _frames(90)
	_check(combat.get_vitals(first).hp == 125.0, "the orb's direct hit damages a monster for 35 (hp %.0f)" % combat.get_vitals(first).hp)
	_check(combat.get_vitals(second).hp < 160.0, "and its splash hurts the monster beside it (hp %.0f)" % combat.get_vitals(second).hp)


func _test_separation() -> void:
	print("separation")
	var rig := await _new_rig()
	rig.game.combat.get_vitals(1).god = true
	var ids: Array[int] = []
	for i in 6:
		ids.append(rig.game.monsters.spawn(&"grunt", Vector3(0.0, 0.1, 6.0)))
	await _frames(150)
	var closest := INF
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			closest = minf(closest, rig.game.get_body(ids[i]).global_position.distance_to(rig.game.get_body(ids[j]).global_position))
	_check(closest > 0.55, "six monsters spawned on one spot spread out instead of stacking (closest %.2f m)" % closest)


func _test_targeting() -> void:
	print("targeting")
	var rig := await _new_rig()
	var bot := rig.game.spawn_player(PlayerRegistry.Kind.BOT)
	await _frames(3)
	# A clear row along the north wall: no cover in the way.
	bot.global_position = Vector3(22.0, 0.1, -26.0)
	rig.human.global_position = Vector3(-22.0, 0.1, -26.0)
	var free_monster := rig.game.monsters.spawn(&"grunt", Vector3(17.0, 0.1, -26.0))
	var owned_monster := rig.game.monsters.spawn(&"grunt", Vector3(20.0, 0.1, -23.0), PlayerRegistry.HOST_ID)
	var free_body := rig.game.get_body(free_monster)
	var owned_body := rig.game.get_body(owned_monster)
	var free_start := free_body.global_position
	var owned_start := owned_body.global_position
	await _frames(20)
	_check(free_body.global_position.x > free_start.x + 0.5, "an unowned monster first heads for the nearest player: the bot to the east (x %.1f -> %.1f)" % [free_start.x, free_body.global_position.x])
	await _frames(40)
	_check(owned_body.global_position.x < owned_start.x - 2.0, "a monster owned by the human heads west for them even though the bot is closer")
	rig.game.combat.kill(1, 0)
	await _frames(2)
	var parked := owned_body.global_position
	await _frames(40)
	_check(owned_body.global_position.distance_to(parked) < 0.2, "a monster whose owner is dead stops and waits")


func _fight_trace(seed_value: int) -> Array[String]:
	var rig := await _new_rig(seed_value)
	rig.game.monsters.spawn(&"grunt", Vector3(-6.0, 0.1, HUMAN_SPAWN.z - 12.0))
	rig.game.monsters.spawn(&"spitter", Vector3(6.0, 0.1, HUMAN_SPAWN.z - 16.0))
	rig.game.monsters.spawn(&"brute", Vector3(0.0, 0.1, HUMAN_SPAWN.z - 14.0))
	await _frames(300)
	var trace: Array[String] = []
	for id in rig.game.monsters.records.keys():
		var body := rig.game.get_body(id)
		trace.append("%d %.3f %.3f %.3f" % [id, body.global_position.x, body.global_position.y, body.global_position.z])
	for entry in rig.damage:
		trace.append("%d %d %d %.1f" % [entry.tick, entry.target, entry.source, entry.amount])
	return trace


func _test_fights_are_deterministic() -> void:
	print("determinism")
	var first := await _fight_trace(5)
	var again := await _fight_trace(5)
	_check(first.size() > 4, "the scripted pack produced results (%d lines)" % first.size())
	_check(first == again, "the same seed gives identical monster positions and damage")


func _test_monster_console() -> void:
	print("monster console")
	var rig := await _new_rig()
	var game := rig.game
	_check(DevCommands.run("monster", game).begins_with("Usage"), "monster without arguments prints usage")
	_check(DevCommands.run("monster dragon", game).begins_with("Unknown"), "an unknown monster is reported")
	_check(DevCommands.run("monster grunt", game).contains("1") and game.monsters.count() == 1, "monster grunt spawns one")
	_check(DevCommands.run("monster spitter 3", game).contains("3") and game.monsters.count() == 4, "monster spitter 3 spawns three")
	_check(DevCommands.run("monster brute x", game).begins_with("Usage"), "a bad count prints usage")
	DevCommands.run("monster grunt 99", game)
	_check(game.monsters.count() == 16, "the count is capped at 12 per command")
	_check(DevCommands.run("monster clear", game).contains("16") and game.monsters.count() == 0, "monster clear removes them all")
	_check(DevCommands.run("help", game).contains("monster"), "help lists the monster command")
