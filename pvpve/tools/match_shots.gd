# Dev helper: plays a fast match and saves screenshots of its screens: PvE results, the wager,
# the modifier cards, a table flip, the mark, fog, the final's shrinking ring and the victory.
# Needs a display (for example xvfb-run). Usage:
#   godot.sh --script res://tools/match_shots.gd -- <output_dir> [only_shot_name]
extends SceneTree

var _out_dir := "user://shots"
var _only := ""
var _game: Game
var _source: ScriptedSource
var _human: Player
var _director: MatchDirector


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
	main.start_bots = 2
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
	_director = _game.match_director
	var config := MatchPresets.fast()
	config.shrink_start_fraction = 0.0
	_director.set_config(config)
	_director.start(2)

	# 1. PvE results (the human's real run is skipped, bots are modeled).
	await _wait_physics(60)
	_director.skip()
	await _until(func() -> bool: return _director.phase == MatchDirector.PVE_RESULTS, 120)
	await _wait_physics(20)
	await _capture("1_pve_results")

	# 2. The wager menu, with a stake picked.
	await _until(func() -> bool: return _director.phase == MatchDirector.WAGER, 400)
	_director.standings.add(1, 1, &"pve", 400)
	_director.set_wager(1, 1)
	await _wait_physics(10)
	await _capture("2_wager")

	# 3. PvP: the bots across the arena, a leader mark and a table flip.
	await _until(func() -> bool: return _director.phase == MatchDirector.PVP, 600)
	_director.set_mark(2)
	_game.get_player(2).teleport_to(Vector3(0.0, 0.1, 8.0), 0.0)
	_game.get_player(3).teleport_to(Vector3(12.0, 0.1, 14.0), 0.0)
	_source.yaw = 0.0
	_source.pitch = -0.05
	_human.teleport_to(Vector3(0.0, 0.1, 22.0), 0.0)
	await _wait_physics(5)
	await _capture("3_mark")
	_game.events.pvp_kill_scored.emit(1, 2, PvpRules.KillClass.SHOWSTOPPER, 90, 140)
	await _wait_physics(8)
	await _capture("4_table_flip")
	_game.events.pvp_kill_scored.emit(1, 3, PvpRules.KillClass.SKILL, 35, 20)

	# 4. PvP results with the modifier cards for the winner.
	_director.standings.add(1, 1, &"kill", 500)
	_director.skip()
	await _wait_physics(10)
	await _capture("5_modifier_cards")
	_director.pick_modifier(2)

	# 5. Fog in the next PvE (the arena as a stand-in), then the final.
	_game.modifiers.set_active(&"fog", 1)
	_human.teleport_to(Vector3(0.0, 0.1, 22.0), 0.0)
	await _wait_physics(10)
	await _capture("6_fog")
	_game.modifiers.clear()
	_director.jump_to_final()
	await _wait_physics(420)
	_human.teleport_to(Vector3(_director.safe_radius * 0.8, 0.1, 0.0), PI / 2.0)
	_source.yaw = -PI / 2.0 + 0.6
	_source.pitch = 0.05
	await _wait_physics(5)
	await _capture("7_final_ring")
	_director.skip()
	await _wait_physics(10)
	await _capture("8_victory")
	quit(0)


func _until(condition: Callable, max_ticks: int) -> void:
	var waited := 0
	while not condition.call() and waited < max_ticks:
		await physics_frame
		waited += 1


func _wait_physics(count: int) -> void:
	for i in count:
		await physics_frame


func _capture(shot_name: String) -> void:
	if _only != "" and _only != shot_name:
		return
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var path := _out_dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("saved ", path)
