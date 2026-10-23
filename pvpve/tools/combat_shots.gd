# Dev helper: plays a scripted fight and saves screenshots of each weapon in action.
# Needs a display (for example xvfb-run). Usage:
#   godot.sh --script res://tools/combat_shots.gd -- <output_dir> [only_shot_name]
extends SceneTree

## Stands in for the keyboard so the scene can be driven without a person.
class ScriptedSource extends InputSource:
	var yaw := 0.0
	var pitch := 0.0
	var fire_held := false
	var _pressed := false
	var _slot := 0

	func press_fire() -> void:
		fire_held = true
		_pressed = true

	func release_fire() -> void:
		fire_held = false

	func select(slot: int) -> void:
		_slot = slot

	func is_local_view() -> bool:
		return true

	func set_view(new_yaw: float, new_pitch: float) -> void:
		yaw = new_yaw
		pitch = new_pitch

	func poll(_delta: float) -> PlayerCommand:
		var command := PlayerCommand.new()
		command.yaw = yaw
		command.pitch = pitch
		command.fire_held = fire_held
		command.fire_pressed = _pressed
		command.weapon_slot = _slot
		_pressed = false
		_slot = 0
		return command


var _out_dir := "user://shots"
var _only := ""
var _game: Game
var _source: ScriptedSource
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
	main.start_bots = 1
	root.add_child(main)
	_game = main.get_node("Game")
	for i in 4:
		await process_frame
	var human := _game.get_human()
	human.input_source.queue_free()
	_source = ScriptedSource.new()
	human.input_source = _source
	human.add_child(_source)
	_game.combat.give_weapon(1, &"sword")
	_game.combat.give_weapon(1, &"bow")
	_game.combat.give_weapon(1, &"orb")
	for event_name in ["weapon_fired", "damage_dealt", "explosion", "melee_swing", "projectile_spawned"]:
		_game.events.get(event_name).connect(_counter.bind(event_name))
	# Targets: three in a row, one close enough for the sword.
	_game.spawn_dummy(Vector3(-3.0, 0.0, 12.0))
	_game.spawn_dummy(Vector3(0.0, 0.0, 12.0))
	_game.spawn_dummy(Vector3(3.0, 0.0, 12.0))
	_game.spawn_dummy(Vector3(0.0, 0.0, 20.0))
	await _wait_physics(10)
	Engine.time_scale = 0.25

	# Pistol: three shots, then capture while the last tracer and damage numbers are alive.
	_source.yaw = 0.05
	_counts["weapon_fired"] = 0
	_source.press_fire()
	while _counts.get("weapon_fired", 0) < 3:
		await physics_frame
	await _capture("1_pistol")
	_source.release_fire()
	await _wait_physics(30)

	# Sword: capture mid-slash on the close dummy.
	_source.yaw = 0.0
	_source.select(2)
	await _wait_physics(4)
	_source.press_fire()
	await _wait_physics(1)
	_source.release_fire()
	await _wait_physics(19)
	await _capture("2_sword")
	await _wait_physics(60)

	# Bow: capture at full draw, then the arrow in flight.
	_source.select(3)
	await _wait_physics(4)
	_source.press_fire()
	await _wait_physics(40)
	await _capture("3_bow_drawn")
	_source.release_fire()
	await _wait_physics(5)
	await _capture("4_bow_arrow")
	await _wait_physics(60)

	# Orb: capture in flight, then at the explosion.
	_source.select(4)
	await _wait_physics(4)
	_source.press_fire()
	await _wait_physics(1)
	_source.release_fire()
	await _wait_physics(5)
	await _capture("5_orb_flight")
	await _wait_until("explosion")
	await _wait_physics(3)
	await _capture("6_orb_explosion")
	await _wait_physics(40)

	# Death screen.
	_game.combat.kill(1, _game.registry.ids()[1], &"pistol")
	await _wait_physics(40)
	await _capture("7_death")

	Engine.time_scale = 1.0
	quit(0)


func _counter(_a = null, _b = null, _c = null, _d = null, _e = null, event_name := "") -> void:
	_counts[event_name] = _counts.get(event_name, 0) + 1


## Waits for an event to have happened at least once, giving up after a few seconds of game time.
func _wait_until(event_name: String, max_ticks := 600) -> void:
	var waited := 0
	while _counts.get(event_name, 0) < 1 and waited < max_ticks:
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
