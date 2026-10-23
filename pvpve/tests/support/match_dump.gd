# Plays one whole autopilot match in a fresh process and prints the ledger, so a test can run
# it twice and compare. Usage: godot --headless --fixed-fps 60 --script res://tests/support/match_dump.gd -- <seed>
extends SceneTree


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var seed_value := int(args[0]) if args.size() > 0 else 1
	var main: Node = load("res://world/main.tscn").instantiate()
	main.start_bots = 2
	root.add_child(main)
	var game: Game = main.get_node("Game")
	game.set_seed(seed_value)
	game.set_autopilot(1, true)
	var director := game.match_director
	director.set_config(MatchPresets.fast())
	director.start(2)
	var limit := 20000
	while director.phase != MatchDirector.VICTORY and limit > 0:
		await physics_frame
		limit -= 1
	var rows: Array = []
	for entry in director.standings.entries:
		rows.append([entry.player_id, entry.cycle, entry.kind, entry.amount])
	print("LEDGER ", rows)
	print("CHAMPION ", director.champion_id)
	main.free()
	quit(0)
