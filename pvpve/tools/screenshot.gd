# Dev helper: boots the main scene, poses the human, lets bots run for a while, and saves a PNG.
# Needs a display (e.g. xvfb-run). Usage:
#   godot.sh --script res://tools/screenshot.gd -- out.png [x z yaw_deg pitch_deg [wait_frames [bots [console]]]]
extends SceneTree


func _initialize() -> void:
	_capture()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://shot.png"
	var wait_frames := int(args[5]) if args.size() > 5 else 30
	var main: Node = load("res://world/main.tscn").instantiate()
	main.start_bots = int(args[6]) if args.size() > 6 else 0
	root.add_child(main)
	for i in 5:
		await process_frame
	var game: Game = main.get_node("Game")
	var human := game.get_human()
	if args.size() >= 5:
		human.global_position = Vector3(float(args[1]), 0.1, float(args[2]))
		human.set_look(deg_to_rad(float(args[3])), deg_to_rad(float(args[4])))
	for i in wait_frames:
		await physics_frame
	if args.size() > 7 and args[7] == "console":
		var console := main.get_node("DevConsole")
		console._set_open(true, false)
		for line in ["help", "bot 2", "players"]:
			console._print("> " + line)
			console._print(DevCommands.run(line, game))
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("saved ", out_path, " ", image.get_size())
	quit(0)
