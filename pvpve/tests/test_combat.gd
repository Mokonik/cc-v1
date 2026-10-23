# Headless tests for weapons, damage, death and respawn.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_combat.gd
extends SceneTree

const TICK := 60
## Human spawn (index 0): z = 22 facing -Z. Dummies are placed straight ahead of it.
const HUMAN_SPAWN := Vector3(0.0, 0.1, 22.0)

## Replaces the human's keyboard source so a test controls every command.
class ScriptedSource extends InputSource:
	var yaw := 0.0
	var pitch := 0.0
	var fire_held := false
	var _fire_pressed := false
	var _fire_released := false
	var _reload := false
	var _slot := 0
	var _cycle := 0

	func press_fire() -> void:
		fire_held = true
		_fire_pressed = true

	func release_fire() -> void:
		fire_held = false
		_fire_released = true

	func reload() -> void:
		_reload = true

	func select(slot: int) -> void:
		_slot = slot

	func cycle(direction: int) -> void:
		_cycle = direction

	func poll(_delta: float) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.yaw = yaw
		command.pitch = pitch
		command.fire_held = fire_held
		command.fire_pressed = _fire_pressed
		command.fire_released = _fire_released
		command.reload_pressed = _reload
		command.weapon_slot = _slot
		command.weapon_cycle = _cycle
		_fire_pressed = false
		_fire_released = false
		_reload = false
		_slot = 0
		_cycle = 0
		return command

	func set_view(new_yaw: float, new_pitch: float) -> void:
		yaw = new_yaw
		pitch = new_pitch


var _failures := 0
var _main: Node


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# The root is not inside the tree yet during _initialize; wait a frame before building nodes.
	await process_frame
	_test_balance()
	await _test_hitscan_damage_and_rate()
	await _test_magazine_and_reload()
	await _test_spread_is_deterministic()
	await _test_walls_and_self()
	await _test_melee()
	await _test_bow()
	await _test_orb()
	await _test_projectile_expiry()
	await _test_death_and_respawn()
	await _test_protection_and_god()
	await _test_weapon_switching()
	await _test_local_input_mapping()
	await _test_bots_and_dummies()
	await _test_dev_commands()
	await _test_fight_is_deterministic()
	if _main != null:
		_main.free()
		_main = null
	print("combat tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


# ---- helpers -------------------------------------------------------------

class Rig extends RefCounted:
	var game: Game
	var human: Player
	var source: ScriptedSource
	var log: Array[String] = []
	var counts := {}
	var damage_amounts: Array[float] = []
	## Event name -> combat tick at which it last happened.
	var marks := {}

	func count(name: String) -> int:
		return counts.get(name, 0)


## A fresh game with the human driven by a scripted source and event counters attached.
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
	var events := rig.game.events
	var game := rig.game
	events.weapon_fired.connect(func(pid: int, wid: StringName, _o: Vector3, _d: Vector3, end: Vector3) -> void:
		_bump(rig, "fired")
		rig.log.append("t%d fired %d %s %.3f,%.3f,%.3f" % [game.combat.tick, pid, wid, end.x, end.y, end.z]))
	events.damage_dealt.connect(func(target: int, source: int, amount: float, _p: Vector3, wid: StringName) -> void:
		_bump(rig, "damage")
		rig.damage_amounts.append(amount)
		rig.log.append("t%d damage %d<-%d %.2f %s" % [game.combat.tick, target, source, amount, wid]))
	events.player_died.connect(func(victim: int, killer: int, wid: StringName) -> void:
		_bump(rig, "died")
		rig.marks["died"] = game.combat.tick
		rig.log.append("t%d died %d<-%d %s" % [game.combat.tick, victim, killer, wid]))
	events.player_respawned.connect(func(pid: int) -> void:
		_bump(rig, "respawned")
		rig.marks["respawned"] = game.combat.tick
		rig.log.append("t%d respawned %d" % [game.combat.tick, pid]))
	events.reload_started.connect(func(_p: int, _w: StringName, _d: float) -> void: _bump(rig, "reload_started"))
	events.reload_finished.connect(func(_p: int, _w: StringName) -> void: _bump(rig, "reload_finished"))
	events.melee_swing.connect(func(_p: int, _w: StringName) -> void: _bump(rig, "swing"))
	events.draw_started.connect(func(_p: int, _w: StringName, _d: float) -> void: _bump(rig, "draw"))
	events.explosion.connect(func(_p: Vector3, _r: float, _w: StringName) -> void: _bump(rig, "explosion"))
	events.projectile_spawned.connect(func(_i: int, _w: StringName, _p: Vector3, _v: Vector3) -> void: _bump(rig, "projectile"))
	events.projectile_ended.connect(func(_i: int, _p: Vector3, hit: int) -> void:
		_bump(rig, "projectile_ended")
		if hit != 0:
			_bump(rig, "projectile_hit"))
	events.weapon_changed.connect(func(_p: int, _w: StringName) -> void: _bump(rig, "weapon_changed"))
	await _frames(3)
	return rig


func _bump(rig: Rig, name: String) -> void:
	rig.counts[name] = rig.counts.get(name, 0) + 1


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _vitals(rig: Rig, id: int) -> Vitals:
	return rig.game.combat.get_vitals(id)


## Spawns a standing dummy this far straight ahead of the human spawn.
func _dummy_ahead(rig: Rig, distance: float, x := 0.0) -> Player:
	var dummy := rig.game.spawn_dummy(Vector3(x, 0.0, HUMAN_SPAWN.z - distance))
	await _frames(3)
	return dummy


func _fire_once(rig: Rig) -> void:
	rig.source.press_fire()
	await _frames(1)
	rig.source.release_fire()


# ---- tests ---------------------------------------------------------------

func _test_balance() -> void:
	print("balance")
	var catalog := WeaponCatalog.new()
	var weapons := catalog.all()
	_check(weapons.size() == 4, "four weapons are defined")
	var slots := {}
	var sane := true
	for def in weapons:
		slots[def.slot] = true
		sane = sane and def.damage > 0.0 and def.fire_interval > 0.0 and def.id != &""
	_check(slots.size() == 4 and sane, "slots are unique and values sane")
	var kinds := {}
	for def in weapons:
		kinds[def.kind] = true
	_check(kinds.size() == 4, "all four weapon kinds are represented")
	var pistol := catalog.get_def(WeaponCatalog.STARTER)
	_check(pistol.kind == WeaponDef.Kind.HITSCAN, "the starter weapon is the hitscan pistol")
	_check(pistol.ttk(100.0) >= 3.0 - 0.0001, "starter ideal TTK is at least 3 s (%.2f)" % pistol.ttk(100.0))
	var slow_enough := true
	for def in weapons:
		slow_enough = slow_enough and def.ttk(100.0) >= 3.0 - 0.0001
	_check(slow_enough, "every weapon takes 3 s or more to kill from full health")
	_check(WeaponDef.seconds_to_ticks(1.3) == 78 and WeaponDef.seconds_to_ticks(0.25) == 15, "seconds convert to ticks without rounding drift")


func _test_hitscan_damage_and_rate() -> void:
	print("hitscan damage and rate")
	var rig := await _new_rig()
	var dummy := await _dummy_ahead(rig, 10.0)
	await _fire_once(rig)
	await _frames(2)
	var target := _vitals(rig, dummy.player_id)
	_check(target.hp == 92.0, "one pistol shot deals exactly 8 damage (hp %.1f)" % target.hp)
	_check(rig.count("fired") == 1 and rig.count("damage") == 1, "one shot fired, one hit reported")
	_check(_vitals(rig, 1).current().ammo == 14, "the shot used one round")
	_check(_vitals(rig, 1).hp == 100.0, "the shooter is unharmed")

	rig = await _new_rig()
	dummy = await _dummy_ahead(rig, 10.0)
	rig.source.press_fire()
	await _frames(60)
	rig.source.release_fire()
	await _frames(1)
	_check(rig.count("fired") == 4, "holding fire for 1 s gives 4 shots at 4 shots/s (%d)" % rig.count("fired"))
	_check(_vitals(rig, dummy.player_id).hp == 68.0, "four hits deal 32 damage")
	_check(_vitals(rig, 1).current().ammo == 11, "four rounds used")


func _test_magazine_and_reload() -> void:
	print("magazine and reload")
	var rig := await _new_rig()
	rig.source.pitch = 0.5  # shoot at the sky so nothing interferes
	rig.source.press_fire()
	await _frames(15 * 14 + 2)
	var state := _vitals(rig, 1).current()
	_check(rig.count("fired") == 15 and state.ammo == 0, "an empty magazine after 15 shots (%d fired)" % rig.count("fired"))
	_check(state.is_reloading() and rig.count("reload_started") == 1, "an empty magazine starts a reload by itself")
	var started_tick: int = state.reload_done_tick - WeaponDef.seconds_to_ticks(1.3)
	_check(started_tick > 0 and state.reload_done_tick - started_tick == 78, "the reload takes 78 ticks (1.3 s)")
	await _frames(40)
	_check(rig.count("fired") == 15, "no shots while reloading even with fire held")
	await _frames(50)
	_check(rig.count("reload_finished") == 1 and rig.count("fired") > 15, "the magazine refills and firing resumes")
	rig.source.release_fire()

	rig = await _new_rig()
	rig.source.pitch = 0.5
	await _fire_once(rig)
	await _frames(20)
	await _fire_once(rig)
	await _frames(20)
	rig.source.reload()
	await _frames(2)
	_check(rig.count("reload_started") == 1, "pressing reload with a partial magazine reloads")
	await _frames(90)
	_check(_vitals(rig, 1).current().ammo == 15, "a manual reload refills the magazine")
	rig.source.reload()
	await _frames(2)
	_check(rig.count("reload_started") == 1, "reload does nothing when the magazine is full")


func _spread_ends(seed_value: int) -> Array[String]:
	var rig := await _new_rig(seed_value)
	rig.source.press_fire()
	await _frames(15 * 6)
	rig.source.release_fire()
	var ends: Array[String] = []
	for line in rig.log:
		if " fired " in line:
			ends.append(line.substr(line.find(" ", 3)))
	return ends


func _test_spread_is_deterministic() -> void:
	print("spread")
	var first := await _spread_ends(1)
	var again := await _spread_ends(1)
	var other := await _spread_ends(2)
	_check(first.size() >= 5, "recorded several shots (%d)" % first.size())
	_check(first == again, "the same seed gives identical shot placement")
	_check(first != other, "a different seed changes shot placement")
	var distinct := {}
	for entry in first:
		distinct[entry] = true
	_check(distinct.size() > 1, "consecutive shots land in different places (spread works)")


func _test_walls_and_self() -> void:
	print("walls and self")
	var rig := await _new_rig()
	# The center block spans x 2..6, z -10..-6. Stand in line with it, dummy hidden behind.
	rig.human.global_position = Vector3(4.0, 0.1, 2.0)
	var dummy := rig.game.spawn_dummy(Vector3(4.0, 0.0, -14.0))
	await _frames(5)
	rig.source.press_fire()
	await _frames(40)
	rig.source.release_fire()
	_check(rig.count("fired") >= 2 and _vitals(rig, dummy.player_id).hp == 100.0, "a wall blocks shots (%d fired, dummy untouched)" % rig.count("fired"))

	rig = await _new_rig()
	rig.source.pitch = -PI / 2.0
	await _fire_once(rig)
	await _frames(2)
	_check(rig.count("fired") == 1 and rig.count("damage") == 0 and _vitals(rig, 1).hp == 100.0, "a shot at your own feet never hurts you")


func _test_melee() -> void:
	print("melee")
	var rig := await _new_rig()
	rig.game.combat.give_weapon(1, &"sword")
	rig.source.select(2)
	await _frames(2)
	var dummy := await _dummy_ahead(rig, 2.0)
	await _fire_once(rig)
	await _frames(8)
	_check(rig.count("swing") == 1 and _vitals(rig, dummy.player_id).hp == 100.0, "no damage during the windup")
	await _frames(12)
	_check(_vitals(rig, dummy.player_id).hp == 80.0, "the swing lands after the windup for 20 damage (hp %.0f)" % _vitals(rig, dummy.player_id).hp)
	await _frames(60)
	_check(_vitals(rig, dummy.player_id).hp == 80.0 and rig.count("damage") == 1, "one swing hits a target only once")

	rig = await _new_rig()
	rig.game.combat.give_weapon(1, &"sword")
	rig.source.select(2)
	dummy = await _dummy_ahead(rig, 6.0)
	await _fire_once(rig)
	await _frames(30)
	_check(_vitals(rig, dummy.player_id).hp == 100.0 and rig.count("swing") == 1, "a target out of reach is missed")

	rig = await _new_rig()
	rig.game.combat.give_weapon(1, &"sword")
	rig.source.select(2)
	dummy = await _dummy_ahead(rig, 2.0)
	rig.source.yaw = PI  # turn around: the dummy is now behind
	await _frames(2)
	await _fire_once(rig)
	await _frames(30)
	_check(_vitals(rig, dummy.player_id).hp == 100.0, "a target outside the swing arc is missed")


func _test_bow() -> void:
	print("bow")
	var rig := await _new_rig()
	rig.game.combat.give_weapon(1, &"bow")
	rig.source.select(3)
	var dummy := await _dummy_ahead(rig, 10.0)
	var speeds: Array[float] = []
	var ends: Array[Vector3] = []
	rig.game.events.projectile_spawned.connect(func(_i: int, _w: StringName, _p: Vector3, velocity: Vector3) -> void: speeds.append(velocity.length()))
	rig.game.events.projectile_ended.connect(func(_i: int, position: Vector3, _h: int) -> void: ends.append(position))
	rig.source.press_fire()
	await _frames(WeaponDef.seconds_to_ticks(0.7) + 6)
	_check(rig.count("draw") == 1 and rig.count("projectile") == 0, "holding fire draws the bow without loosing")
	rig.source.release_fire()
	await _frames(60)
	_check(rig.count("projectile") == 1 and speeds[0] > 44.0, "a full draw loosed an arrow at full speed (%.1f m/s)" % (speeds[0] if speeds.size() > 0 else 0.0))
	_check(_vitals(rig, dummy.player_id).hp == 70.0, "a full-power arrow deals 30 damage (hp %.1f)" % _vitals(rig, dummy.player_id).hp)
	_check(ends.size() == 1 and ends[0].y < Player.EYE_HEIGHT - 0.2, "the arrow drops under gravity (hit at y=%.2f from eye 1.60)" % (ends[0].y if ends.size() > 0 else 0.0))

	rig = await _new_rig()
	rig.game.combat.give_weapon(1, &"bow")
	rig.source.select(3)
	dummy = await _dummy_ahead(rig, 10.0)
	speeds.clear()
	rig.game.events.projectile_spawned.connect(func(_i: int, _w: StringName, _p: Vector3, velocity: Vector3) -> void: speeds.append(velocity.length()))
	await _fire_once(rig)
	await _frames(80)
	var tap_damage: float = 100.0 - _vitals(rig, dummy.player_id).hp
	_check(absf(tap_damage - 30.0 * 0.35) < 0.01, "a quick tap does minimum-power damage (%.2f)" % tap_damage)
	_check(speeds.size() == 1 and speeds[0] < 30.0, "and a slower arrow (%.1f m/s)" % (speeds[0] if speeds.size() > 0 else 0.0))

	rig = await _new_rig()
	rig.game.combat.give_weapon(1, &"bow")
	rig.source.select(3)
	rig.source.pitch = 0.3
	rig.source.press_fire()
	await _frames(50)
	rig.source.release_fire()
	await _frames(1)
	rig.source.press_fire()
	await _frames(10)
	rig.source.release_fire()
	await _frames(1)
	_check(rig.count("projectile") == 1, "the bow cannot be drawn again before its cooldown ends")


func _test_orb() -> void:
	print("fire orb")
	var rig := await _new_rig()
	rig.game.combat.give_weapon(1, &"orb")
	rig.source.select(4)
	var direct := await _dummy_ahead(rig, 10.0)
	var splashed := await _dummy_ahead(rig, 10.0, 2.5)
	var far := await _dummy_ahead(rig, 10.0, 8.0)
	var blast: Array[Vector3] = []
	rig.game.events.explosion.connect(func(position: Vector3, _r: float, _w: StringName) -> void: blast.append(position))
	await _fire_once(rig)
	await _frames(90)
	_check(rig.count("projectile") == 1 and rig.count("explosion") == 1, "the orb flies and explodes on impact")
	_check(_vitals(rig, direct.player_id).hp == 65.0, "a direct hit deals 35 (hp %.1f)" % _vitals(rig, direct.player_id).hp)
	var splash_taken: float = 100.0 - _vitals(rig, splashed.player_id).hp
	var center := splashed.global_position + Vector3(0.0, CombatSystem.BODY_CENTER_HEIGHT, 0.0)
	var expected := 30.0 * lerpf(1.0, CombatSystem.SPLASH_EDGE_FRACTION, center.distance_to(blast[0]) / 4.0)
	_check(blast.size() == 1 and splash_taken > 0.0 and absf(splash_taken - expected) < 0.01, "a nearby target takes distance-scaled splash (%.2f, expected %.2f)" % [splash_taken, expected])
	_check(splash_taken < 30.0, "splash is weaker than the center value")
	_check(_vitals(rig, far.player_id).hp == 100.0, "a target outside the radius is untouched")
	_check(_vitals(rig, 1).hp == 100.0, "the caster is never hurt by their own orb")
	await _fire_once(rig)
	await _frames(30)
	_check(rig.count("projectile") == 1, "the cooldown blocks a second cast")
	await _frames(WeaponDef.seconds_to_ticks(6.0))
	await _fire_once(rig)
	await _frames(2)
	_check(rig.count("projectile") == 2, "the orb can be cast again after 6 s")

	rig = await _new_rig()
	rig.game.combat.give_weapon(1, &"orb")
	rig.source.select(4)
	rig.human.global_position = Vector3(0.0, 0.1, -26.0)  # one meter from the north wall
	rig.source.yaw = 0.0
	await _frames(3)
	await _fire_once(rig)
	await _frames(40)
	_check(rig.count("explosion") == 1 and _vitals(rig, 1).hp == 100.0, "an orb that hits a wall next to you explodes without hurting you")


func _test_projectile_expiry() -> void:
	print("projectile expiry")
	var rig := await _new_rig()
	rig.game.combat.give_weapon(1, &"orb")
	rig.source.select(4)
	rig.source.pitch = PI / 2.0 - 0.01
	await _frames(2)
	await _fire_once(rig)
	await _frames(WeaponDef.seconds_to_ticks(4.0) + 10)
	_check(rig.count("projectile") == 1 and rig.count("projectile_ended") == 1, "a projectile that hits nothing ends at its lifetime")
	_check(rig.count("explosion") == 0 and rig.count("projectile_hit") == 0, "and it fizzles without exploding")
	_check(rig.game.combat.projectiles.count() == 0, "no projectiles remain")


func _test_death_and_respawn() -> void:
	print("death and respawn")
	var rig := await _new_rig()
	var dummy := await _dummy_ahead(rig, 10.0)
	rig.game.combat.set_hp(dummy.player_id, 5.0)
	await _fire_once(rig)
	await _frames(3)
	var target := _vitals(rig, dummy.player_id)
	_check(rig.count("died") == 1 and not target.alive and target.hp == 0.0, "lethal damage kills")
	_check(rig.log.any(func(line: String) -> bool: return line.contains("died %d<-1 pistol" % dummy.player_id)), "the death names the killer and the weapon")
	_check(_vitals(rig, 1).kills == 1 and target.deaths == 1, "the kill and death are counted")
	_check(rig.damage_amounts == [5.0], "only the 5 hp that remained was dealt (%s)" % [rig.damage_amounts])
	_check(dummy.collision_layer == 0 and not dummy.alive, "a dead body stops blocking shots")
	rig.source.press_fire()
	await _frames(45)
	rig.source.release_fire()
	_check(rig.count("damage") == 1 and target.hp == 0.0, "damage to the dead is ignored")
	await _frames(WeaponDef.seconds_to_ticks(3.0))
	_check(target.alive and rig.count("respawned") == 1, "the dummy respawns")
	_check(rig.marks["respawned"] - rig.marks["died"] == WeaponDef.seconds_to_ticks(CombatSystem.RESPAWN_SECONDS), "exactly 3 s (180 ticks) after dying (%d)" % (rig.marks["respawned"] - rig.marks["died"]))
	_check(target.hp == target.max_hp, "with full health")
	_check(dummy.global_position.distance_to(Vector3(0.0, 0.1, HUMAN_SPAWN.z - 10.0)) < 0.3, "back where it was placed")
	_check(dummy.collision_layer == Player.COLLISION_LAYER, "and hittable again")

	rig = await _new_rig()
	var blocker := rig.game.spawn_dummy(Vector3(HUMAN_SPAWN.x, 0.0, HUMAN_SPAWN.z - 1.5))
	await _frames(5)
	var human_state := _vitals(rig, 1).current()
	human_state.ammo = 3
	rig.game.combat.kill(1, blocker.player_id, &"pistol")
	await _frames(2)
	_check(not rig.human.alive and rig.count("died") == 1, "the human can die")
	rig.source.press_fire()
	await _frames(30)
	rig.source.release_fire()
	_check(rig.count("fired") == 0, "the dead cannot shoot")
	await _frames(WeaponDef.seconds_to_ticks(3.0))
	_check(rig.human.alive and _vitals(rig, 1).hp == 100.0, "the human respawns with full health")
	_check(human_state.ammo == 15, "and a full magazine")
	var spawn_1 := rig.game.arena.get_spawn(1).position
	_check(rig.human.global_position.distance_to(spawn_1) < 0.5, "at the spawn point farthest from the other player (%s)" % rig.human.global_position)


func _test_protection_and_god() -> void:
	print("protection and god mode")
	var rig := await _new_rig()
	var dummy := await _dummy_ahead(rig, 10.0)
	rig.game.combat.kill(dummy.player_id, 1, &"pistol")
	await _frames(WeaponDef.seconds_to_ticks(3.0) + 2)
	_check(_vitals(rig, dummy.player_id).alive, "the dummy is back")
	var dealt := rig.game.combat.apply_damage(dummy.player_id, 10.0, 1, &"pistol", Vector3.ZERO)
	_check(dealt == 0.0 and _vitals(rig, dummy.player_id).hp == 100.0, "spawn protection blocks damage")
	await _frames(WeaponDef.seconds_to_ticks(2.0))
	dealt = rig.game.combat.apply_damage(dummy.player_id, 10.0, 1, &"pistol", Vector3.ZERO)
	_check(dealt == 10.0, "damage works again after 2 s")

	var god := _vitals(rig, dummy.player_id)
	god.god = true
	_check(rig.game.combat.apply_damage(dummy.player_id, 50.0, 1, &"pistol", Vector3.ZERO) == 0.0, "god mode blocks damage")
	_check(rig.game.combat.apply_damage(dummy.player_id, -5.0, 1, &"pistol", Vector3.ZERO) == 0.0, "negative damage does nothing")
	_check(rig.game.combat.apply_damage(9999, 5.0, 1, &"pistol", Vector3.ZERO) == 0.0, "damage to an unknown id does nothing")


func _test_weapon_switching() -> void:
	print("weapon switching")
	var rig := await _new_rig()
	var combat := rig.game.combat
	_check(_vitals(rig, 1).owned_slots() == [1] and _vitals(rig, 1).current_slot == 1, "you start with only the pistol")
	rig.source.select(3)
	await _frames(2)
	_check(_vitals(rig, 1).current_slot == 1, "an unowned weapon cannot be selected")
	combat.give_weapon(1, &"bow")
	combat.give_weapon(1, &"orb")
	_check(_vitals(rig, 1).owned_slots() == [1, 3, 4], "given weapons are owned")
	_check(not combat.give_weapon(1, &"nonexistent"), "an unknown weapon is refused")
	rig.source.select(3)
	await _frames(2)
	_check(_vitals(rig, 1).current_slot == 3 and rig.count("weapon_changed") >= 1, "a number key selects an owned weapon")
	rig.source.cycle(1)
	await _frames(2)
	_check(_vitals(rig, 1).current_slot == 4, "cycling moves to the next owned weapon")
	rig.source.cycle(1)
	await _frames(2)
	_check(_vitals(rig, 1).current_slot == 1, "and wraps around")
	rig.source.cycle(-1)
	await _frames(2)
	_check(_vitals(rig, 1).current_slot == 4, "cycling backwards wraps the other way")

	rig.source.select(1)
	await _frames(2)
	rig.source.pitch = 0.5
	await _fire_once(rig)
	await _frames(2)
	rig.source.reload()
	await _frames(2)
	_check(_vitals(rig, 1).current().is_reloading(), "reloading")
	rig.source.select(3)
	await _frames(2)
	rig.source.select(1)
	await _frames(2)
	_check(not _vitals(rig, 1).current().is_reloading(), "switching weapons cancels a reload")

	rig.game.combat.kill(1, 0)
	await _frames(2)
	_check(not combat.select_slot(1, 3), "the dead cannot switch weapons")


func _test_local_input_mapping() -> void:
	print("local input mapping")
	# Input.is_action_just_pressed only sees a manual press from an idle frame, not straight after a physics step.
	await process_frame
	InputSetup.ensure_actions()
	var source := LocalInputSource.new()
	var idle := source.poll(0.0)
	_check(not idle.fire_held and idle.weapon_slot == 0 and not idle.reload_pressed, "no input gives a quiet command")
	Input.action_press(&"fire")
	var firing := source.poll(0.0)
	_check(firing.fire_held and firing.fire_pressed, "the fire action sets fire_held and fire_pressed")
	Input.action_release(&"fire")
	Input.action_press(&"slot_3")
	_check(source.poll(0.0).weapon_slot == 3, "slot_3 selects weapon slot 3")
	Input.action_release(&"slot_3")
	Input.action_press(&"reload")
	_check(source.poll(0.0).reload_pressed, "reload maps to reload_pressed")
	Input.action_release(&"reload")
	Input.action_press(&"weapon_next")
	_check(source.poll(0.0).weapon_cycle == 1, "weapon_next cycles forward")
	Input.action_release(&"weapon_next")
	await process_frame
	Input.action_press(&"weapon_prev")
	_check(source.poll(0.0).weapon_cycle == -1, "weapon_prev cycles backward")
	Input.action_release(&"weapon_prev")
	source.enabled = false
	Input.action_press(&"fire")
	_check(not source.poll(0.0).fire_held, "a disabled source (console open) ignores the mouse")
	Input.action_release(&"fire")
	source.free()


func _test_bots_and_dummies() -> void:
	print("bots and dummies")
	var rig := await _new_rig()
	var bot := rig.game.spawn_player(PlayerRegistry.Kind.BOT, BotPresets.make(2))
	await _frames(3)
	_check(not _vitals(rig, bot.player_id).accepts_commands, "bots do not fire back in M3")
	var dealt := rig.game.combat.apply_damage(bot.player_id, 40.0, 1, &"pistol", bot.global_position)
	_check(dealt == 40.0 and _vitals(rig, bot.player_id).hp == 60.0, "bots take damage")
	await _frames(400)
	_check(_vitals(rig, 1).hp == 100.0, "a bot that wants to fire never hurts you")
	rig.game.combat.kill(bot.player_id, 1, &"pistol")
	await _frames(2)
	_check(rig.game.get_opponents(1).is_empty(), "a dead bot is no longer an opponent")
	await _frames(WeaponDef.seconds_to_ticks(3.0) + 2)
	_check(rig.game.combat.is_alive(bot.player_id) and rig.game.get_opponents(1).size() == 1, "bots respawn like players")

	rig = await _new_rig()
	var spawned := 0
	for i in 6:
		if rig.game.spawn_dummy(Vector3(-20.0 + i * 3.0, 0.0, 0.0)) != null:
			spawned += 1
	_check(spawned == 6, "six dummies spawn")
	_check(rig.game.spawn_dummy(Vector3.ZERO) == null, "a seventh dummy is refused")
	var bots := 0
	for i in 3:
		if rig.game.spawn_player(PlayerRegistry.Kind.BOT) != null:
			bots += 1
	_check(bots == 3, "dummies do not count toward the four-player limit")
	_check(rig.game.spawn_player(PlayerRegistry.Kind.BOT) == null, "a fifth human-or-bot is still refused")
	_check(rig.game.get_opponents(1).size() == 3, "dummies are not opponents for bots")
	_check(rig.game.clear_dummies() == 6 and rig.game.registry.count() == 4, "clear_dummies removes only dummies")


func _test_dev_commands() -> void:
	print("dev commands")
	var rig := await _new_rig()
	var game := rig.game
	var listing := DevCommands.run("weapons", game)
	_check(listing.contains("held  Pistol") and listing.contains("Sword") and listing.contains("15/15"), "weapons lists what you hold and what exists")
	_check(DevCommands.run("give sword", game).contains("Sword") and _vitals(rig, 1).weapons.has(2), "give sword")
	_check(DevCommands.run("give orb", game).contains("Fire Orb") and _vitals(rig, 1).weapons.has(4), "give orb")
	_check(DevCommands.run("give all", game).contains("every") and _vitals(rig, 1).owned_slots() == [1, 2, 3, 4], "give all")
	_check(DevCommands.run("give spoon", game).begins_with("Unknown"), "unknown weapon is reported")
	_check(DevCommands.run("give", game).begins_with("Usage"), "give without arguments prints usage")
	_check(DevCommands.run("hp 40", game) == "Health 40." and _vitals(rig, 1).hp == 40.0, "hp sets health")
	_check(DevCommands.run("hp x", game).begins_with("Usage"), "bad hp prints usage")
	_check(DevCommands.run("god", game).contains("on") and _vitals(rig, 1).god, "god turns on")
	_check(game.combat.apply_damage(1, 10.0, 0, &"x", Vector3.ZERO) == 0.0, "and protects you")
	_check(DevCommands.run("god", game).contains("off") and not _vitals(rig, 1).god, "god turns off")
	_check(DevCommands.run("dummy", game).begins_with("Spawned") and game.registry.count_kind(PlayerRegistry.Kind.DUMMY) == 1, "dummy spawns a target")
	_check(DevCommands.run("dummy strafe", game).begins_with("Spawned"), "dummy strafe spawns a moving target")
	_check(DevCommands.run("dummy nonsense", game).begins_with("Usage"), "bad dummy pattern prints usage")
	var dummy_id: int = game.registry.ids().filter(func(id: int) -> bool: return game.registry.get_record(id).kind == PlayerRegistry.Kind.DUMMY)[0]
	_check(DevCommands.run("damage %d 30" % dummy_id, game).contains("30") and _vitals(rig, dummy_id).hp == 70.0, "damage hurts a target")
	_check(DevCommands.run("kill %d" % dummy_id, game).contains("Killed") and not game.combat.is_alive(dummy_id), "kill kills")
	_check(DevCommands.run("kill %d" % dummy_id, game).contains("already dead"), "killing the dead is reported")
	_check(DevCommands.run("kill 9999", game).begins_with("No player"), "kill of an unknown id is reported")
	_check(DevCommands.run("players", game).contains("dummy") and DevCommands.run("players", game).contains("dead"), "players shows kind, health and dead state")
	_check(DevCommands.run("respawn", game).contains("alive"), "respawn while alive says so")
	game.combat.kill(1, 0)
	await _frames(2)
	_check(DevCommands.run("respawn", game) == "Respawning.", "respawn brings you back")
	await _frames(4)
	_check(rig.human.alive, "and you are alive again")
	var ttk := DevCommands.run("ttk", game)
	_check(ttk.contains("Pistol") and ttk.contains("3.00"), "ttk lists the pistol at 3.00 s")
	_check(DevCommands.run("dummy clear", game).contains("2"), "dummy clear removes the dummies")
	_check(DevCommands.run("help", game).contains("give"), "help lists the new commands")


## A scripted fight against a strafing dummy, returning the event log.
func _fight_log(seed_value: int) -> Array[String]:
	var rig := await _new_rig(seed_value)
	rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_SPAWN.z - 12.0), DummyInputSource.Pattern.STRAFE)
	await _frames(3)
	rig.source.press_fire()
	for i in 360:
		await physics_frame
		rig.source.yaw = sin(float(i) * 0.05) * 0.05
	rig.source.release_fire()
	await _frames(2)
	return rig.log


func _test_fight_is_deterministic() -> void:
	print("determinism")
	var first := await _fight_log(5)
	var second := await _fight_log(5)
	_check(first.size() > 10, "the scripted fight produced events (%d)" % first.size())
	_check(first == second, "the same seed gives an identical fight, event for event")
	var other := await _fight_log(6)
	_check(first != other, "a different seed gives a different fight")
