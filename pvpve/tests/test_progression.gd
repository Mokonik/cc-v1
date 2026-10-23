# Headless tests for loot, consumables, traps, XP, perks, Sabotage Points and the bot PvE model.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_progression.gd
extends SceneTree

var _failures := 0
var _main: Node
var _monsters := MonsterCatalog.new()


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# The root is not inside the tree yet during _initialize; wait a frame before building nodes.
	await process_frame
	_test_tier_math()
	_test_loot_table()
	await _test_xp_and_levels()
	await _test_perks()
	await _test_perk_effects_on_combat()
	await _test_sabotage_points()
	await _test_pickups()
	await _test_weapon_loot_and_tiers()
	await _test_health_packs()
	await _test_traps()
	await _test_monster_kill_rewards()
	await _test_loot_reset()
	await _test_input_commands()
	_test_bot_model()
	await _test_bot_progression()
	await _test_console()
	if _main != null:
		_main.free()
		_main = null
	print("progression tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


# ---- helpers ---------------------------------------------------------------------------------

class Rig extends RefCounted:
	var game: Game
	var human: Player
	var source: ScriptedSource
	var levels: Array[int] = []
	var offers: Array = []
	var picked: Array[StringName] = []
	var picked_up: Array[String] = []
	var dropped: Array[String] = []
	var traps_triggered: Array[Dictionary] = []


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
	events.level_up.connect(func(_p: int, level: int) -> void: rig.levels.append(level))
	events.perk_offered.connect(func(_p: int, perk_ids: Array) -> void: rig.offers.append(perk_ids))
	events.perk_picked.connect(func(_p: int, perk_id: StringName) -> void: rig.picked.append(perk_id))
	events.loot_picked_up.connect(func(_p: int, _d: int, _k: int, label: String) -> void: rig.picked_up.append(label))
	events.loot_dropped.connect(func(_d: int, _k: int, label: String, _p: Vector3) -> void: rig.dropped.append(label))
	events.trap_triggered.connect(func(_t: int, victim: int, _p: Vector3) -> void: rig.traps_triggered.append({"victim": victim}))
	await _frames(3)
	return rig


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


# ---- weapon tiers --------------------------------------------------------------------------------

func _test_tier_math() -> void:
	print("tier math")
	var catalog := WeaponCatalog.new()
	var pistol := catalog.get_def(&"pistol")
	_check(pistol.damage_at(1) == 8.0 and pistol.damage_at(2) == 10.0 and pistol.damage_at(3) == 12.0, "tiers add 25% of base damage each (8, 10, 12)")
	_check(is_equal_approx(pistol.interval_at(1), 0.25) and is_equal_approx(pistol.interval_at(2), 0.225) and is_equal_approx(pistol.interval_at(3), 0.2), "and shorten the interval by 10% of base each")
	_check(pistol.damage_at(0) == 8.0 and pistol.damage_at(9) == 12.0, "tiers are clamped to 1-3")
	var orb := catalog.get_def(&"orb")
	_check(orb.splash_damage_at(3) == 45.0, "splash scales with tier too (30 -> 45)")


func _test_loot_table() -> void:
	print("loot table")
	var table: LootTable = load("res://content/loot/default_loot.tres")
	_check(table.entries.size() == 7, "seven loot rows")
	_check(table.pick(0.0, 1) != null and table.pick(0.0, 1).kind == LootEntry.Kind.HEALTH, "a roll of 0 picks the first row")
	var seen_orb_early := false
	for i in 200:
		var entry := table.pick(float(i) / 200.0, 1)
		seen_orb_early = seen_orb_early or (entry.kind == LootEntry.Kind.WEAPON and entry.id == &"orb")
	_check(not seen_orb_early, "the orb is not offered before wave 2")
	var seen_orb_late := false
	for i in 200:
		var entry := table.pick(float(i) / 200.0, 2)
		seen_orb_late = seen_orb_late or (entry.kind == LootEntry.Kind.WEAPON and entry.id == &"orb")
	_check(seen_orb_late, "but it can drop from wave 2")
	_check(table.pick(0.5, 1) == table.pick(0.5, 1), "picking is deterministic for a given roll")
	var empty := LootTable.new()
	_check(empty.pick(0.5, 1) == null, "an empty table drops nothing")
	var counts := {}
	for i in 1000:
		var entry := table.pick(float(i) / 1000.0, 5)
		var key := "%d%s" % [entry.kind, entry.id]
		counts[key] = counts.get(key, 0) + 1
	_check(counts["1"] > counts["0sword"] and counts["1"] > counts["0orb"], "health drops more often than a weapon, following the weights")


# ---- XP, levels, perks ----------------------------------------------------------------------------

func _test_xp_and_levels() -> void:
	print("xp and levels")
	_check(ProgressionState.xp_for_level(1) == 100 and ProgressionState.xp_for_level(2) == 150 and ProgressionState.xp_for_level(5) == 300, "the curve is 100 plus 50 per level")
	_check(ProgressionState.total_xp_to_reach(1) == 0 and ProgressionState.total_xp_to_reach(2) == 100 and ProgressionState.total_xp_to_reach(4) == 450, "totals add up (level 4 at 450)")
	var rig := await _new_rig()
	var progression := rig.game.progression
	var state := progression.get_state(1)
	_check(state.xp == 0 and state.level == 1 and state.sabotage_points == 0 and state.perks.is_empty(), "a new player starts at level 1 with nothing")
	_check(progression.grant_xp(1, 99) == 0 and state.level == 1, "99 XP is not enough for level 2")
	_check(progression.grant_xp(1, 1) == 1 and state.level == 2, "100 XP reaches level 2")
	_check(state.xp_into_level() == 0 and state.xp_needed() == 150, "and 150 more are needed for level 3")
	_check(rig.levels == [2] and rig.offers.size() == 1, "a level-up fires an event and queues one perk offer")
	rig.levels.clear()
	_check(progression.grant_xp(1, 600) == 3 and state.level == 5, "a big gain can skip several levels (700 XP in total is level 5)")
	_check(rig.levels == [3, 4, 5], "each level is announced")
	_check(state.offers.size() == 4, "and each queues its own offer, including the first (%d pending)" % state.offers.size())
	_check(progression.grant_xp(1, 0) == 0 and progression.grant_xp(1, -5) == 0 and progression.grant_xp(99, 50) == 0, "zero, negative and unknown-player gains do nothing")


func _test_perks() -> void:
	print("perks")
	var rig := await _new_rig(3)
	var progression := rig.game.progression
	var state := progression.get_state(1)
	progression.grant_xp(1, 100)
	var offer: Array = rig.offers[0]
	_check(offer.size() == 3, "an offer holds three perks")
	var distinct := {}
	for id in offer:
		distinct[id] = true
	_check(distinct.size() == 3 and offer.all(func(id: StringName) -> bool: return rig.game.perk_defs.has(id)), "all different and real")

	var again := await _new_rig(3)
	again.game.progression.grant_xp(1, 100)
	_check(again.offers[0] == offer, "the same seed offers the same perks")
	var other := await _new_rig(4)
	other.game.progression.grant_xp(1, 100)
	var differs: bool = other.offers[0] != offer
	var more := await _new_rig(5)
	more.game.progression.grant_xp(1, 100)
	_check(differs or more.offers[0] != offer, "a different seed can offer different perks")

	rig = await _new_rig(3)
	progression = rig.game.progression
	state = progression.get_state(1)
	progression.grant_xp(1, 100)
	_check(progression.pick_perk(1, 0) == &"" and progression.pick_perk(1, 4) == &"", "choices outside 1-3 are refused")
	_check(state.has_pending_offer(), "and the offer is still waiting")
	var chosen := progression.pick_perk(1, 2)
	_check(chosen == rig.offers[0][1] and state.stacks_of(chosen) == 1 and not state.has_pending_offer(), "picking choice 2 takes the second perk and clears the offer")
	_check(rig.picked == [chosen], "and announces it")
	_check(progression.pick_perk(1, 1) == &"", "with nothing pending there is nothing to pick")

	_check(progression.apply_perk(1, &"vitality") and progression.apply_perk(1, &"vitality") and progression.apply_perk(1, &"vitality") and progression.apply_perk(1, &"vitality"), "a perk stacks up to its maximum (vitality: 4)")
	_check(not progression.apply_perk(1, &"vitality") and state.stacks_of(&"vitality") == 4, "and no further")
	_check(not progression.apply_perk(1, &"nonsense"), "unknown perks are refused")
	progression.grant_xp(1, 5000)
	var all_ok := true
	for pending in state.offers:
		all_ok = all_ok and not pending.has(&"vitality")
	_check(all_ok, "offers never include a maxed-out perk")


func _test_perk_effects_on_combat() -> void:
	print("perk effects")
	var rig := await _new_rig()
	var game := rig.game
	var progression := game.progression
	var vitals := game.combat.get_vitals(1)
	_check(vitals.max_hp == 100.0, "base max health is 100")
	progression.apply_perk(1, &"vitality")
	_check(vitals.max_hp == 115.0 and vitals.hp == 115.0, "Vitality raises max health and fills it (%.0f)" % vitals.max_hp)
	vitals.hp = 57.5
	progression.apply_perk(1, &"vitality")
	_check(vitals.max_hp == 130.0 and is_equal_approx(vitals.hp, 65.0), "a wounded player keeps their health fraction when max rises (%.1f of 130)" % vitals.hp)

	var stats := progression.stats_for(1)
	_check(stats.max_hp_bonus == 30.0 and stats.speed_mult == 1.0, "stats aggregate by stack")
	progression.apply_perk(1, &"swiftness")
	progression.apply_perk(1, &"swiftness")
	_check(is_equal_approx(progression.stats_for(1).speed_mult, 1.12), "Swiftness adds 6% per stack (x1.12)")
	await _frames(3)
	_check(is_equal_approx(rig.human.speed_scale, 1.12), "and the player's movement scale follows")
	progression.apply_perk(1, &"marksman")
	progression.apply_perk(1, &"berserker")
	progression.apply_perk(1, &"quick_hands")
	progression.apply_perk(1, &"iron_skin")
	progression.apply_perk(1, &"second_wind")
	progression.apply_perk(1, &"pyromancer")
	progression.apply_perk(1, &"scavenger")
	var all := progression.stats_for(1)
	_check(is_equal_approx(all.gun_damage_mult, 1.08) and is_equal_approx(all.melee_damage_mult, 1.10), "Marksman +8% gun damage, Berserker +10% sword damage")
	_check(is_equal_approx(all.reload_time_mult, 0.88) and is_equal_approx(all.draw_time_mult, 0.88), "Quick Hands -12% reload and draw time")
	_check(is_equal_approx(all.damage_taken_mult, 0.92) and all.kill_heal == 6.0, "Iron Skin -8% damage taken, Second Wind heals 6 on a kill")
	_check(is_equal_approx(all.orb_radius_bonus, 0.6) and is_equal_approx(all.orb_cooldown_mult, 0.9), "Pyromancer widens the orb and shortens its cooldown")
	_check(is_equal_approx(all.loot_chance_bonus, 0.08) and all.sabotage_point_bonus == 1, "Scavenger adds loot chance and Sabotage Points")

	# Damage actually changes.
	var dummy := rig.game.spawn_dummy(Vector3(0.0, 0.0, 12.0))
	await _frames(3)
	var before := game.combat.get_vitals(dummy.player_id).hp
	game.combat.apply_damage(dummy.player_id, 10.0, 1, &"console", Vector3.ZERO)
	_check(game.combat.get_vitals(dummy.player_id).hp == before - 10.0, "damage from the console (own source) is unmodified by the dealer's perks")
	var tough := game.combat.get_vitals(1)
	var hp_before := tough.hp
	game.combat.apply_damage(1, 50.0, dummy.player_id, &"x", Vector3.ZERO)
	_check(is_equal_approx(hp_before - tough.hp, 46.0), "Iron Skin reduces incoming damage (50 -> 46)")
	var gun_hit := game.weapons.get_def(&"pistol").damage_at(1) * all.gun_damage_mult
	_check(is_equal_approx(gun_hit, 8.64), "a pistol shot with Marksman is 8.64")
	var kills := game.combat.get_vitals(dummy.player_id)
	tough.hp = 50.0
	game.combat.kill(dummy.player_id, 1, &"pistol")
	_check(is_equal_approx(tough.hp, 56.0), "killing something heals a Second Wind owner (50 -> 56)")
	_check(kills.hp == 0.0, "and the target is dead")


func _test_sabotage_points() -> void:
	print("sabotage points")
	var rig := await _new_rig()
	var progression := rig.game.progression
	var state := progression.get_state(1)
	progression.grant_sabotage_points(1, 5)
	_check(state.sabotage_points == 5, "points accrue")
	_check(not progression.spend_sabotage_points(1, 6) and state.sabotage_points == 5, "spending more than you have fails and costs nothing")
	_check(progression.spend_sabotage_points(1, 3) and state.sabotage_points == 2, "spending what you have works")
	_check(not progression.spend_sabotage_points(1, -1), "a negative spend is refused")
	progression.grant_sabotage_points(1, -100)
	_check(state.sabotage_points == 0, "points never go below zero")


# ---- loot ----------------------------------------------------------------------------------------------

func _test_pickups() -> void:
	print("pickups")
	var rig := await _new_rig()
	var loot := rig.game.loot
	var here := rig.human.global_position
	var near := loot.spawn_named(&"health", here + Vector3(1.0, 0.0, 0.0))
	var far := loot.spawn_named(&"health", here + Vector3(5.0, 0.0, 0.0))
	await _frames(3)
	_check(rig.dropped.size() == 2 and rig.dropped[0] == "Health pack", "drops announce themselves")
	_check(not loot.drops.has(near.id) and loot.drops.has(far.id), "walking within 1.6 m picks up; farther away does not")
	_check(loot.get_inventory(1).health_packs == 1 and rig.picked_up == ["Health pack"], "the pickup is added and announced")
	rig.human.global_position = here + Vector3(5.0, 0.0, 0.0)
	await _frames(3)
	_check(loot.get_inventory(1).health_packs == 2, "moving to the other one collects it")

	for i in 3:
		loot.spawn_named(&"health", rig.human.global_position)
	await _frames(3)
	_check(loot.get_inventory(1).health_packs == Inventory.MAX_HEALTH_PACKS and loot.drops.size() == 2, "a full pack (3) cannot take more; the two extras stay on the ground")

	var owned := loot.spawn_named(&"trap", rig.human.global_position, 99)
	await _frames(3)
	_check(loot.drops.has(owned.id) and loot.get_inventory(1).traps == 0, "loot owned by another zone cannot be taken")
	loot.clear_owned_by(99)
	_check(not loot.drops.has(owned.id), "and is removed with that zone")

	rig.game.combat.kill(1, 0)
	var dead_drop := loot.spawn_named(&"trap", rig.human.global_position)
	await _frames(3)
	_check(loot.drops.has(dead_drop.id), "the dead cannot pick things up")

	loot.clear_drops()
	var expiring := loot.spawn_named(&"xp", Vector3(40.0, 0.5, 40.0))
	await _frames(WeaponDef.seconds_to_ticks(LootSystem.DROP_LIFETIME_SECONDS) + 5)
	_check(not loot.drops.has(expiring.id), "uncollected drops disappear after 60 s")


func _test_weapon_loot_and_tiers() -> void:
	print("weapon loot")
	var rig := await _new_rig()
	var combat := rig.game.combat
	var loot := rig.game.loot
	var vitals := combat.get_vitals(1)
	_check(vitals.owned_slots() == [1] and vitals.weapons[1].tier == 1, "you start with the pistol at tier 1")
	var tiers: Array[int] = []
	rig.game.events.weapon_tier_changed.connect(func(_p: int, _w: StringName, tier: int) -> void: tiers.append(tier))
	loot.spawn_named(&"sword", rig.human.global_position)
	await _frames(3)
	_check(vitals.weapons.has(2) and vitals.weapons[2].tier == 1 and rig.picked_up == ["Sword"], "a sword drop unlocks the sword")
	loot.spawn_named(&"sword", rig.human.global_position)
	await _frames(3)
	_check(vitals.weapons[2].tier == 2, "a second sword raises it to tier 2")
	loot.spawn_named(&"sword", rig.human.global_position)
	await _frames(3)
	_check(vitals.weapons[2].tier == 3 and tiers == [2, 3], "and a third to tier 3, announcing each tier-up")
	var left_over := loot.spawn_named(&"sword", rig.human.global_position)
	await _frames(3)
	_check(vitals.weapons[2].tier == 3 and loot.drops.has(left_over.id), "tier 3 is the cap: a fourth sword stays on the ground")
	loot.clear_drops()
	loot.spawn_named(&"pistol", rig.human.global_position)
	await _frames(3)
	_check(vitals.weapons[1].tier == 2, "a pistol drop upgrades the starter pistol")
	_check(combat.grant_weapon_loot(1, &"nonsense") == &"" and combat.grant_weapon_loot(99, &"sword") == &"", "unknown weapons and players are refused")

	# A tiered weapon really hits harder and faster.
	var dummy := rig.game.spawn_dummy(Vector3(0.0, 0.0, HUMAN_AHEAD))
	await _frames(3)
	rig.source.press_fire()
	await _frames(2)
	rig.source.release_fire()
	await _frames(2)
	var damage := 100.0 - combat.get_vitals(dummy.player_id).hp
	_check(is_equal_approx(damage, 10.0), "a tier-2 pistol hit deals 10 (%.1f)" % damage)
	var state: WeaponState = vitals.weapons[1]
	_check(state.next_fire_tick - combat.tick > 0 and state.def.interval_at(2) < state.def.fire_interval, "and fires faster")


const HUMAN_AHEAD := 10.0


func _test_health_packs() -> void:
	print("health packs")
	var rig := await _new_rig()
	var game := rig.game
	var inventory := game.loot.get_inventory(1)
	_check(not game.loot.use_health_pack(1), "using one with none does nothing")
	inventory.health_packs = 2
	_check(not game.loot.use_health_pack(1) and inventory.health_packs == 2, "at full health a pack is not wasted")
	game.combat.set_hp(1, 50.0)
	_check(game.loot.use_health_pack(1) and game.combat.get_vitals(1).hp == 85.0 and inventory.health_packs == 1, "a pack heals 35 (50 -> 85)")
	_check(game.loot.use_health_pack(1) and game.combat.get_vitals(1).hp == 100.0, "healing stops at max health (85 -> 100)")
	inventory.health_packs = 1
	game.combat.kill(1, 0)
	_check(not game.loot.use_health_pack(1), "the dead cannot use items")


func _test_traps() -> void:
	print("traps")
	var rig := await _new_rig()
	var game := rig.game
	var loot := game.loot
	var inventory := loot.get_inventory(1)
	_check(not loot.place_trap(1), "placing a trap with none does nothing")
	inventory.traps = 2
	var armed: Array[int] = []
	game.events.trap_armed.connect(func(trap_id: int) -> void: armed.append(trap_id))
	_check(loot.place_trap(1) and inventory.traps == 1 and loot.traps.size() == 1, "placing a trap uses one")
	var trap: Trap = loot.traps.values()[0]
	_check(trap.position.distance_to(rig.human.global_position) < 0.1 and trap.owner_id == 1, "it sits at your feet and remembers its owner")
	await _frames(5)
	_check(loot.traps.has(trap.id), "the owner standing on it does not trigger it")
	await _frames(WeaponDef.seconds_to_ticks(LootSystem.TRAP_ARM_SECONDS) + 2)
	_check(loot.traps.has(trap.id) and armed == [trap.id], "even once armed (announced once)")

	var dummy := game.spawn_dummy(trap.position + Vector3(8.0, 0.0, 0.0))
	await _frames(3)
	_check(loot.traps.has(trap.id) and game.combat.get_vitals(dummy.player_id).hp == 100.0, "a target outside the radius is safe")
	dummy.global_position = trap.position + Vector3(1.0, 0.0, 0.0)
	await _frames(2)
	_check(not loot.traps.has(trap.id) and rig.traps_triggered.size() == 1, "a target stepping within 1.5 m sets it off, once")
	var victim := game.combat.get_vitals(dummy.player_id)
	_check(victim.hp == 70.0, "for 30 damage (%.0f hp left)" % victim.hp)
	_check(victim.slow_factor == 0.6 and victim.slow_until_tick > game.combat.tick, "and a 40% slow")
	await _frames(WeaponDef.seconds_to_ticks(LootSystem.TRAP_SLOW_SECONDS) + 5)
	_check(game.combat.tick >= victim.slow_until_tick, "the slow wears off after 2.5 s")

	# Slow affects movement speed on a player.
	game.combat.apply_slow(1, 0.6, 2.0)
	await _frames(3)
	_check(is_equal_approx(rig.human.speed_scale, 0.6), "a slowed player really moves slower (x%.2f)" % rig.human.speed_scale)
	game.combat.apply_slow(1, 0.9, 5.0)
	_check(game.combat.get_vitals(1).slow_factor == 0.6, "a weaker slow does not replace a stronger one")

	# Monsters and the dead never trigger traps.
	inventory.traps = 1
	var spot := Vector3(-20.0, 0.1, -20.0)
	rig.human.global_position = spot
	await _frames(2)
	loot.place_trap(1)
	rig.human.global_position = Vector3(20.0, 0.1, 20.0)
	await _frames(WeaponDef.seconds_to_ticks(LootSystem.TRAP_ARM_SECONDS) + 5)
	var monster_id := game.monsters.spawn(&"grunt", spot + Vector3(0.5, 0.0, 0.0), 999)
	await _frames(5)
	_check(game.combat.get_vitals(monster_id).hp == 60.0 and loot.traps.size() == 1, "a monster walking over a trap does not set it off")
	loot.traps.clear()


func _test_monster_kill_rewards() -> void:
	print("kill rewards")
	var rig := await _new_rig(2)
	var game := rig.game
	var state := game.progression.get_state(1)
	var grunt := game.monsters.spawn(&"grunt", Vector3(10.0, 0.1, 10.0), 999)
	game.combat.kill(grunt, 1, &"pistol")
	await _frames(3)
	_check(state.xp == 20 and state.sabotage_points == 1, "a grunt kill gives 20 XP and 1 Sabotage Point")
	var brute := game.monsters.spawn(&"brute", Vector3(10.0, 0.1, 14.0), 999)
	game.combat.kill(brute, 1, &"pistol")
	await _frames(3)
	_check(state.xp == 90 and state.sabotage_points == 3, "a brute gives 70 XP and 2 points")
	var spitter := game.monsters.spawn(&"spitter", Vector3(10.0, 0.1, 18.0), 999)
	game.combat.kill(spitter, 0, &"")
	await _frames(3)
	_check(state.xp == 90, "a monster that dies with no player killer rewards nobody")
	game.progression.apply_perk(1, &"scavenger")
	var extra := game.monsters.spawn(&"grunt", Vector3(12.0, 0.1, 10.0), 999)
	game.combat.kill(extra, 1, &"pistol")
	await _frames(3)
	_check(state.sabotage_points == 3 + 2, "Scavenger adds a Sabotage Point per kill")

	# Drops are seeded: the same kill under the same seed drops the same thing.
	var first := await _drop_labels(11)
	var again := await _drop_labels(11)
	_check(first.size() > 0 and first == again, "the same seed gives the same drops (%s)" % [first])
	var other := await _drop_labels(12)
	_check(first != other, "a different seed gives different drops")
	var boss_rig := await _new_rig(1)
	var boss := boss_rig.game.monsters.spawn(&"warden", Vector3(10.0, 0.1, 10.0), 999)
	boss_rig.game.combat.kill(boss, 1, &"pistol")
	await _frames(3)
	_check(boss_rig.dropped.size() == 1 and boss_rig.game.progression.get_state(1).xp == 400, "the boss always drops loot (loot chance 100%) and gives 400 XP")


func _drop_labels(seed_value: int) -> Array[String]:
	var rig := await _new_rig(seed_value)
	var ids: Array[int] = []
	for i in 24:
		ids.append(rig.game.monsters.spawn(&"brute", Vector3(-25.0 + (i % 12) * 4.0, 0.1, -20.0 + (i / 12) * 4.0), 999))
	for id in ids:
		rig.game.combat.kill(id, 1, &"pistol")
	await _frames(3)
	return rig.dropped


func _test_loot_reset() -> void:
	print("loot reset")
	var rig := await _new_rig()
	var game := rig.game
	game.progression.apply_perk(1, &"vitality")
	game.combat.give_weapon(1, &"sword")
	game.combat.grant_weapon_loot(1, &"sword")
	var inventory := game.loot.get_inventory(1)
	inventory.health_packs = 2
	inventory.traps = 1
	game.loot.reset_loot(1)
	var vitals := game.combat.get_vitals(1)
	_check(inventory.health_packs == 0 and inventory.traps == 0, "consumables are cleared")
	_check(vitals.owned_slots() == [1] and vitals.weapons[1].tier == 1 and vitals.current_slot == 1, "weapons go back to the tier-1 pistol")
	_check(game.progression.get_state(1).stacks_of(&"vitality") == 1 and vitals.max_hp == 115.0, "but perks are kept for the whole run")


func _test_input_commands() -> void:
	print("item and perk commands")
	var rig := await _new_rig()
	var game := rig.game
	var inventory := game.loot.get_inventory(1)
	inventory.health_packs = 1
	game.combat.set_hp(1, 40.0)
	var command_source := rig.source
	# Drive the commands through the real pipeline with a source that sets the new fields.
	var driver := CommandDriver.new()
	rig.human.input_source = driver
	rig.human.add_child(driver)
	driver.use_item = true
	await _frames(2)
	driver.use_item = false
	_check(game.combat.get_vitals(1).hp == 75.0 and inventory.health_packs == 0, "the use-item command drinks a health pack")
	inventory.traps = 1
	driver.place_trap = true
	await _frames(2)
	driver.place_trap = false
	_check(game.loot.traps.size() == 1 and inventory.traps == 0, "the place-trap command lays a trap")
	game.progression.grant_xp(1, 100)
	driver.perk_pick = 3
	await _frames(2)
	driver.perk_pick = 0
	_check(game.progression.get_state(1).perks.size() == 1 and not game.progression.get_state(1).has_pending_offer(), "the perk-pick command takes choice 3")
	game.combat.kill(1, 0)
	inventory.health_packs = 1
	driver.use_item = true
	await _frames(2)
	_check(inventory.health_packs == 1, "a dead player's item commands are ignored")
	driver.use_item = false
	rig.human.input_source = command_source
	driver.queue_free()

	InputSetup.ensure_actions()
	var source := LocalInputSource.new()
	await process_frame
	Input.action_press(&"use_item")
	_check(source.poll(0.0).use_item, "the F action maps to use_item")
	Input.action_release(&"use_item")
	await process_frame
	Input.action_press(&"place_trap")
	_check(source.poll(0.0).place_trap, "G maps to place_trap")
	Input.action_release(&"place_trap")
	await process_frame
	Input.action_press(&"perk_2")
	_check(source.poll(0.0).perk_pick == 2, "X maps to perk choice 2")
	Input.action_release(&"perk_2")
	source.free()


## A source that sets the item and perk fields directly.
class CommandDriver extends InputSource:
	var use_item := false
	var place_trap := false
	var perk_pick := 0

	func poll(_delta: float) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.use_item = use_item
		command.place_trap = place_trap
		command.perk_pick = perk_pick
		return command


# ---- bot model ----------------------------------------------------------------------------------------

func _config(difficulty := 1.0) -> PveConfig:
	var config: PveConfig = load("res://content/pve_config.tres").duplicate()
	config.difficulty = difficulty
	return config


func _test_bot_model() -> void:
	print("bot model")
	var config := _config()
	var rookie := BotPveModel.simulate(BotPveModel.skill_for_level(0), config, _monsters, 5, 2)
	var regular := BotPveModel.simulate(BotPveModel.skill_for_level(1), config, _monsters, 5, 2)
	var veteran := BotPveModel.simulate(BotPveModel.skill_for_level(2), config, _monsters, 5, 2)
	_check(rookie.score < regular.score and regular.score < veteran.score, "higher skill scores more (%d < %d < %d)" % [rookie.score, regular.score, veteran.score])
	_check(rookie.kill_count() < regular.kill_count() and regular.kill_count() < veteran.kill_count(), "and kills more (%d, %d, %d)" % [rookie.kill_count(), regular.kill_count(), veteran.kill_count()])
	_check(rookie.deaths >= regular.deaths and regular.deaths >= veteran.deaths, "and dies less (%d, %d, %d)" % [rookie.deaths, regular.deaths, veteran.deaths])
	_check(rookie.xp < veteran.xp and rookie.sabotage_points <= veteran.sabotage_points, "XP and Sabotage Points follow kills")
	_check(veteran.score == PveScoring.score(veteran, _monsters), "the model scores through the shared formula")

	var kills_somewhere := true
	for difficulty in [0.5, 1.0, 1.5, 2.0, 3.0]:
		kills_somewhere = kills_somewhere and BotPveModel.simulate(0.6, _config(difficulty), _monsters, 9, 2).kill_count() > 0
	_check(kills_somewhere, "a regular bot kills something at every difficulty")
	var kills_by_difficulty: Array[float] = []
	for difficulty in [0.5, 1.0, 2.0, 4.0]:
		var result := BotPveModel.simulate(0.6, _config(difficulty), _monsters, 9, 2)
		kills_by_difficulty.append(float(result.kill_count()) / float(maxi(BotPveModel.wave_threat(_config(difficulty), _monsters, 9, 2).counts.values().reduce(func(a: int, b: int) -> int: return a + b, 0), 1)))
	var clear_rate_falls := true
	for i in range(1, kills_by_difficulty.size()):
		clear_rate_falls = clear_rate_falls and kills_by_difficulty[i] <= kills_by_difficulty[i - 1] + 0.0001
	_check(clear_rate_falls, "the share of monsters a bot clears falls as difficulty rises (%s)" % [kills_by_difficulty.map(func(x: float) -> String: return "%.2f" % x)])
	var easy := BotPveModel.simulate(0.85, _config(0.5), _monsters, 5, 2)
	var hard := BotPveModel.simulate(0.85, _config(3.0), _monsters, 5, 2)
	_check(hard.deaths >= easy.deaths, "a harder phase never means fewer deaths (%d vs %d)" % [easy.deaths, hard.deaths])

	var strong := BotPveModel.Effects.new()
	strong.power_mult = 1.3
	var buffed := BotPveModel.simulate(0.6, config, _monsters, 5, 2, strong)
	var plain := BotPveModel.simulate(0.6, config, _monsters, 5, 2)
	_check(buffed.kill_count() >= plain.kill_count(), "perk power helps")
	var sabotaged := BotPveModel.Effects.new()
	sabotaged.extra_difficulty = 1.0
	var hurt := BotPveModel.simulate(0.6, config, _monsters, 5, 2, sabotaged)
	_check(hurt.difficulty == 2.0 and hurt.kill_count() <= plain.kill_count() + 1, "sabotage raises the effective difficulty (%.1f)" % hurt.difficulty)
	var doubled := BotPveModel.Effects.new()
	doubled.threat_mult = 2.0
	_check(BotPveModel.simulate(0.6, config, _monsters, 5, 2, doubled).deaths >= plain.deaths, "a double-spawns modifier never helps")

	var again := BotPveModel.simulate(BotPveModel.skill_for_level(1), config, _monsters, 5, 2)
	_check(again.score == regular.score and again.kills == regular.kills and again.deaths == regular.deaths and again.boss_defeated == regular.boss_defeated, "the same seed gives the identical result")
	var scores := {}
	for seed_value in range(20):
		scores[BotPveModel.simulate(0.6, config, _monsters, seed_value, 2).score] = true
	_check(scores.size() > 5, "different seeds give varied scores (%d distinct of 20)" % scores.size())
	var in_range := true
	for seed_value in range(40):
		for level in 3:
			var result := BotPveModel.simulate(BotPveModel.skill_for_level(level), config, _monsters, seed_value, 3)
			in_range = in_range and result.score >= 0 and result.deaths >= 0 and result.kill_count() >= 0 and result.deaths < 20 and result.waves_survived >= 0
	_check(in_range, "scores, kills and deaths stay in sane ranges across 120 runs")
	var boss_wins := 0
	var boss_losses := 0
	for seed_value in range(60):
		if BotPveModel.simulate(0.85, config, _monsters, seed_value, 2).boss_defeated:
			boss_wins += 1
		else:
			boss_losses += 1
	_check(boss_wins > 0 and boss_losses > 0, "a veteran sometimes beats the boss and sometimes does not (%d of 60)" % boss_wins)
	var rookie_wins := 0
	for seed_value in range(60):
		if BotPveModel.simulate(0.35, _config(2.0), _monsters, seed_value, 2).boss_defeated:
			rookie_wins += 1
	_check(rookie_wins < boss_wins, "a rookie at double difficulty beats it less often (%d of 60)" % rookie_wins)
	_check(BotPveModel.boss_chance(0.0, 1.0, 0) == 0.0 and BotPveModel.boss_chance(10.0, 1.0, 0) <= 0.97, "boss chance is clamped to 0-97%")
	_check(BotPveModel.boss_chance(0.8, 1.0, 3) < BotPveModel.boss_chance(0.8, 1.0, 0), "and deaths lower it")

	var no_boss := _config()
	no_boss.boss_enabled = false
	_check(BotPveModel.simulate(0.85, no_boss, _monsters, 5, 2).reason == &"time_up", "with no boss the phase ends on time")
	var counts: Dictionary = BotPveModel.wave_threat(config, _monsters, 5, 2).counts
	_check(counts.get(&"grunt", 0) > counts.get(&"spitter", 0) and counts.get(&"brute", 0) > 0, "the model faces the same wave mix as a human: mostly grunts, some spitters, some brutes (%s)" % [counts])
	var total := 0
	for type_id in counts:
		total += counts[type_id]
	_check(total == 4 + 5 + 6 + 7 + 8 + 9 + 10 + 11 + 12 + 13 + 14 + 15, "and the same number of monsters as 12 real waves (%d)" % total)


func _test_bot_progression() -> void:
	print("bot progression")
	var rig := await _new_rig(2)
	var game := rig.game
	var bot := game.spawn_player(PlayerRegistry.Kind.BOT)
	await _frames(3)
	_check(game.run_bot_pve(1, 1) == null, "only bots can use the stat model")
	var result := game.run_bot_pve(bot.player_id, 2)
	var state := game.progression.get_state(bot.player_id)
	_check(result != null and state.xp == result.xp and state.sabotage_points == result.sabotage_points, "the bot receives the XP and Sabotage Points it earned")
	_check(state.level > 1 and not state.has_pending_offer(), "it levels up and spends its perk offers (level %d)" % state.level)
	var perk_count := 0
	for id in state.perks:
		perk_count += state.perks[id]
	_check(perk_count == state.level - 1, "one perk per level gained (%d perks)" % perk_count)
	_check(game.combat.get_vitals(bot.player_id).max_hp >= 100.0, "and its stats are applied")
	_check(game.pve.last_results.get(bot.player_id) == result, "its result is recorded like a human's")
	_check(BotPerkPicker.choose([&"scavenger", &"vitality", &"pyromancer"]) == 2, "a bot prefers Vitality over weaker choices")
	_check(BotPerkPicker.choose([&"scavenger", &"pyromancer", &"berserker"]) == 3 and BotPerkPicker.choose([]) == 0, "and picks the best of what is offered, or nothing")
	var again := await _new_rig(2)
	var bot2 := again.game.spawn_player(PlayerRegistry.Kind.BOT)
	await _frames(3)
	var result2 := again.game.run_bot_pve(bot2.player_id, 2)
	_check(result2.score == result.score and again.game.progression.get_state(bot2.player_id).perks == state.perks, "two identical setups give the same score and the same perk build")


func _test_console() -> void:
	print("console")
	var rig := await _new_rig()
	var game := rig.game
	_check(DevCommands.run("loot", game).begins_with("Usage"), "loot without arguments prints usage")
	_check(DevCommands.run("loot spoon", game).begins_with("Unknown"), "an unknown loot name is reported")
	_check(DevCommands.run("loot bow", game).contains("Bow") and game.loot.drops.size() == 1, "loot bow drops a bow")
	await _frames(3)
	_check(game.combat.get_vitals(1).weapons.has(3), "walking into it unlocks the bow")
	_check(DevCommands.run("xp x", game).begins_with("Usage"), "bad xp prints usage")
	_check(DevCommands.run("xp 100", game).contains("Level up"), "xp 100 levels you up")
	_check(DevCommands.run("perk list", game).contains("vitality") and DevCommands.run("perk list", game).contains("0/4"), "perk list shows stacks")
	_check(DevCommands.run("perk give vitality", game).contains("now 1"), "perk give gives a stack")
	_check(DevCommands.run("perk give nonsense", game).begins_with("Unknown"), "an unknown perk is reported")
	for i in 3:
		DevCommands.run("perk give vitality", game)
	_check(DevCommands.run("perk give vitality", game).contains("maximum"), "a maxed perk says so")
	_check(DevCommands.run("perk", game).contains("swiftness"), "perk alone lists them")
	_check(DevCommands.run("sp 7", game).contains("7"), "sp grants Sabotage Points")
	_check(DevCommands.run("sp x", game).begins_with("Usage"), "bad sp prints usage")
	game.combat.set_hp(1, 20.0)
	_check(DevCommands.run("heal", game) == "Healed." and game.combat.get_vitals(1).hp == game.combat.get_vitals(1).max_hp, "heal restores health")
	_check(DevCommands.run("botpve", game).begins_with("No such bot"), "botpve with no bot says so")
	game.spawn_player(PlayerRegistry.Kind.BOT)
	var output := DevCommands.run("botpve 2", game)
	_check(output.contains("score") and output.contains("skill 0.85"), "botpve runs the model for a veteran (%s)" % output)
	_check(DevCommands.run("botpve x", game).begins_with("Usage"), "bad botpve prints usage")
	_check(DevCommands.run("help", game).contains("botpve"), "help lists the new commands")
