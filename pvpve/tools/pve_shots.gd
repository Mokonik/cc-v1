# Dev helper: plays a scripted PvE phase and saves screenshots of the zone, a monster
# telegraph, loot, the perk offer, the boss and the results screen.
# Needs a display (for example xvfb-run). Usage:
#   godot.sh --script res://tools/pve_shots.gd -- <output_dir> [only_shot_name]
extends SceneTree

var _out_dir := "user://shots"
var _only := ""
var _game: Game
var _source: ScriptedSource
var _human: Player
var _counts := {}


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	if args.size() > 1:
		_only = args[1]
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var main: Node = load("res://world/main.tscn").instantiate()
	main.start_bots = 0
	root.add_child(main)
	_game = main.get_node("Game")
	for i in 4:
		await process_frame
	_human = _game.get_human()
	_human.input_source.queue_free()
	_source = ScriptedSource.new()
	_human.input_source = _source
	_human.add_child(_source)
	_game.combat.get_vitals(1).god = true
	_game.combat.give_weapon(1, &"sword")
	_game.combat.give_weapon(1, &"bow")
	_game.combat.give_weapon(1, &"orb")
	for event_name in ["monster_telegraph", "monster_spawned", "explosion"]:
		_game.events.get(event_name).connect(_counter.bind(event_name))

	# 1. The zone as the first wave arrives.
	_game.pve.start_run(1, 120.0, 1.0)
	_game.pve.get_run(1).phase_end_tick = _game.tick  # skip the countdown
	await _until(func() -> bool: return _game.monsters.count() >= 4, 900)
	await _wait_physics(120)
	_source.yaw = 0.0
	_source.pitch = -0.08
	await _wait_physics(2)
	await _capture("1_zone_wave")

	# 2. A brute winding up a slam right next to us, glowing.
	_game.monsters.clear_all()
	var brute := _game.monsters.spawn(&"brute", _human.global_position + Vector3(0.0, 0.0, -2.0), 1)
	_counts["monster_telegraph"] = 0
	await _until(func() -> bool: return _counts.get("monster_telegraph", 0) > 0, 600)
	await _wait_physics(8)
	_look_at(_game.get_body(brute))
	await _wait_physics(2)
	await _capture("2_brute_telegraph")
	_game.monsters.clear_all()

	# 3. A spread of loot on the ground ahead.
	_source.yaw = 0.0
	_source.pitch = -0.25
	var kinds: Array[StringName] = [&"sword", &"health", &"trap", &"xp", &"bow"]
	for i in kinds.size():
		var spot := _human.global_position + Vector3((i - 2) * 1.7, 0.6, -5.5)
		var drop := _game.loot.spawn_named(kinds[i], spot, 99)
		drop.owner_id = 99  # nobody can grab it while we look
	await _wait_physics(40)
	await _capture("3_loot")
	_game.loot.clear_drops()

	# 4. The level-up perk offer.
	_source.pitch = 0.0
	_game.progression.grant_xp(1, 100)
	await _wait_physics(20)
	await _capture("4_perk_offer")
	_game.progression.pick_perk(1, 1)

	# 5. The boss.
	_game.pve.skip_to_boss(1)
	await _until(func() -> bool: return _game.pve.get_run(1).boss_monster_id != 0, 600)
	await _wait_physics(40)
	var boss := _game.get_body(_game.pve.get_run(1).boss_monster_id)
	_look_at(boss)
	await _wait_physics(2)
	await _capture("5_boss")

	# 6. Victory and the results screen.
	_game.combat.apply_damage(boss.entity_id, 400.0, 1, &"console", boss.global_position)
	await _wait_physics(10)
	_game.combat.kill(boss.entity_id, 1, &"pistol")
	await _wait_physics(20)
	await _capture("6_results")
	quit(0)


func _counter(_a = null, _b = null, _c = null, event_name := "") -> void:
	_counts[event_name] = _counts.get(event_name, 0) + 1


func _until(condition: Callable, max_ticks: int) -> void:
	var waited := 0
	while not condition.call() and waited < max_ticks:
		await physics_frame
		waited += 1


func _wait_physics(count: int) -> void:
	for i in count:
		await physics_frame


func _look_at(body: Combatant) -> void:
	if body == null:
		return
	var from := _human.eye_position()
	var to := body.chest_position()
	_source.yaw = atan2(-(to.x - from.x), -(to.z - from.z))
	_source.pitch = atan2(to.y - from.y, Vector2(to.x - from.x, to.z - from.z).length())


func _capture(shot_name: String) -> void:
	if _only != "" and _only != shot_name:
		return
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var path := _out_dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("saved ", path)
