# Dev helper: boots the main scene, poses the player, and saves a PNG.
# Run (needs a display, e.g. xvfb-run): godot.sh --script res://tools/screenshot.gd -- out.png [x z yaw_deg pitch_deg]
extends SceneTree


func _initialize() -> void:
	_capture()


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://shot.png"
	var main: Node = load("res://world/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var player: Player = main.get_node("Player")
	if args.size() >= 5:
		player.global_position = Vector3(float(args[1]), 0.1, float(args[2]))
		player.set_look(deg_to_rad(float(args[3])), deg_to_rad(float(args[4])))
	for i in 30:
		await physics_frame
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png(out_path)
	print("saved ", out_path, " ", image.get_size())
	quit(0)
