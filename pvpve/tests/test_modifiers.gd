# Headless tests for world modifiers: aggregate numbers and the hooks that apply them.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_modifiers.gd
extends SceneTree

var _failures := 0
var _main: Node


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	await process_frame
	_test_aggregates()
	await _test_double_spawns()
	await _test_elite()
	await _test_low_gravity()
	await _test_volatile()
	await _test_fog_and_scope()
	if _main != null:
		_main.free()
		_main = null
	print("modifier tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


func _new_game() -> Game:
	if _main != null:
		_main.free()
	_main = load("res://world/main.tscn").instantiate()
	_main.start_bots = 0
	root.add_child(_main)
	var game: Game = _main.get_node("Game")
	game.set_seed(1)
	game.combat.get_vitals(1).god = true
	await _frames(3)
	return game


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _test_aggregates() -> void:
	print("aggregates")
	var catalog := ModifierCatalog.new()
	var neutral := ModifierAggregate.new()
	_check(neutral.is_neutral() and neutral.threat_mult() == 1.0, "nothing active changes nothing")
	var double := ModifierAggregate.new()
	double.add(catalog.get_def(&"double_spawns"))
	_check(double.count_mult == 2.0 and double.loot_chance_bonus > 0.0, "double spawns: 2x monsters and more loot")
	_check(double.threat_mult() > 1.5, "and bots find it harder (%.2f)" % double.threat_mult())
	var elite := ModifierAggregate.new()
	elite.add(catalog.get_def(&"elite_monsters"))
	_check(is_equal_approx(elite.hp_mult, 1.5) and is_equal_approx(elite.damage_mult, 1.3) and is_equal_approx(elite.xp_mult, 1.5), "elite: 1.5x health, 1.3x damage, 1.5x XP")
	var gravity := ModifierAggregate.new()
	gravity.add(catalog.get_def(&"low_gravity"))
	_check(is_equal_approx(gravity.gravity_mult, 0.55) and gravity.threat_mult() < 1.0, "low gravity: x0.55 and slightly easier")
	var fog := ModifierAggregate.new()
	fog.add(catalog.get_def(&"fog"))
	_check(is_equal_approx(fog.range_mult, 0.5) and fog.fog_density > 0.0, "fog: half range and a fog density")
	var volatile := ModifierAggregate.new()
	volatile.add(catalog.get_def(&"volatile"))
	_check(volatile.volatile_damage == 20.0 and volatile.volatile_radius == 3.0, "volatile: 20 damage in 3 m")
	_check(double.bot_effects().threat_mult == double.threat_mult(), "bot effects carry the threat")


func _wave_sizes(game: Game, difficulty := 1.0) -> Array[int]:
	var sizes: Array[int] = []
	game.events.pve_wave.connect(func(_o: int, _wave: int, count: int) -> void: sizes.append(count))
	game.pve.start_run(1, 25.0, difficulty)
	await _frames(WeaponDef.seconds_to_ticks(5.0) + WeaponDef.seconds_to_ticks(12.0))
	game.pve.stop_run(1)
	return sizes


func _test_double_spawns() -> void:
	print("double spawns")
	var game := await _new_game()
	var plain := await _wave_sizes(game)
	game = await _new_game()
	game.modifiers.set_active(&"double_spawns", 1)
	var doubled := await _wave_sizes(game)
	_check(plain.size() >= 1 and doubled.size() >= 1, "waves ran (%s vs %s)" % [plain, doubled])
	_check(doubled[0] == plain[0] * 2, "the first wave is twice as big (%d vs %d)" % [doubled[0], plain[0]])


func _test_elite() -> void:
	print("elite monsters")
	var game := await _new_game()
	game.modifiers.set_active(&"elite_monsters", 1)
	var id := game.monsters.spawn(&"grunt", Vector3(0, 1, 5), 0, 1.0, 1.0)
	_check(id != 0, "plain spawns are unaffected by the modifier (%.0f hp)" % game.combat.get_vitals(id).max_hp)
	game.pve.start_run(1, 25.0)
	await _frames(WeaponDef.seconds_to_ticks(5.0) + 90)
	var hp := 0.0
	var damage := 0.0
	for monster_id: int in game.monsters.records:
		var record := game.monsters.get_record(monster_id)
		if record.owner_id == 1:
			hp = game.combat.get_vitals(monster_id).max_hp
			damage = record.damage_mult
			break
	game.pve.stop_run(1)
	_check(is_equal_approx(hp, 60.0 * 1.5), "run monsters have 1.5x health (%.0f)" % hp)
	_check(is_equal_approx(damage, 1.3), "and hit 1.3x as hard (x%.2f)" % damage)


func _apex(game: Game) -> float:
	var player := game.get_human()
	player.global_position = Vector3(0, 0.1, 0)
	await _frames(20)
	var apex := 0.0
	var dt := 1.0 / Engine.physics_ticks_per_second
	for i in 140:
		await physics_frame
		player.simulate(Vector2.ZERO, i == 0, true, false, dt)
		apex = maxf(apex, player.global_position.y)
	return apex


func _test_low_gravity() -> void:
	print("low gravity")
	var game := await _new_game()
	var normal := await _apex(game)
	game.modifiers.set_active(&"low_gravity", 1)
	await _frames(2)
	_check(is_equal_approx(game.get_human().gravity_scale, 0.55), "the player's gravity scale follows the modifier")
	var floaty := await _apex(game)
	_check(floaty > normal * 1.5, "a jump goes much higher (%.2f m vs %.2f m)" % [floaty, normal])
	game.modifiers.clear()
	await _frames(2)
	_check(is_equal_approx(game.get_human().gravity_scale, 1.0), "clearing it restores gravity")


func _test_volatile() -> void:
	print("volatile")
	var game := await _new_game()
	game.modifiers.set_active(&"volatile", 1)
	game.combat.get_vitals(1).god = false
	var player := game.get_human()
	player.global_position = Vector3(0, 0.1, 0)
	await _frames(5)
	var blasts: Array[int] = []
	game.events.monster_exploded.connect(func(_id: int, _p: Vector3, _r: float) -> void: blasts.append(1))
	var near := game.monsters.spawn(&"grunt", player.global_position + Vector3(0, 0, 1.5), 0)
	var bystander := game.monsters.spawn(&"grunt", player.global_position + Vector3(0, 0, 2.5), 0)
	var before := game.combat.get_vitals(1).hp
	var bystander_before := game.combat.get_vitals(bystander).hp
	game.combat.apply_damage(near, 9999.0, 1, &"pistol", Vector3.ZERO)
	await _frames(2)
	_check(blasts.size() == 1, "the dead monster exploded")
	_check(is_equal_approx(before - game.combat.get_vitals(1).hp, 20.0), "the player took 20 damage (%.1f)" % (before - game.combat.get_vitals(1).hp))
	_check(game.combat.get_vitals(bystander).hp == bystander_before, "other monsters are not hurt")


func _test_fog_and_scope() -> void:
	print("fog and scope")
	var game := await _new_game()
	game.modifiers.set_active(&"fog", 1)
	_check(is_equal_approx(game.modifiers.aggregate_for(1).range_mult, 0.5), "fog halves monster range for everyone")
	game.modifiers.set_active(&"fog", 1, MatchConfig.ModifierScope.OPPONENTS)
	_check(game.modifiers.aggregate_for(1).is_neutral(), "opponents-only scope spares the picker")
	_check(not game.modifiers.aggregate_for(2).is_neutral(), "and applies to the others")
	_check(not game.modifiers.set_active(&"nope", 1), "unknown modifiers are refused")
