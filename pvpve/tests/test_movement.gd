# Headless tests for the first-person controller and its supporting pieces.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_movement.gd
extends SceneTree

var _failures := 0
var _spawned: Array[Node] = []
var _dt := 1.0 / 60.0


func _initialize() -> void:
	_dt = 1.0 / Engine.physics_ticks_per_second
	_run_all()


func _run_all() -> void:
	# The root is not inside the tree yet during _initialize; wait a frame before building nodes.
	await process_frame
	await _test_settle_on_floor()
	await _test_walk_speed_and_direction()
	await _test_sprint_and_strafe_sprint()
	await _test_diagonal_not_faster()
	await _test_friction_stops()
	await _test_jump_height()
	await _test_jump_cut()
	await _test_jump_buffer()
	await _test_coyote_time()
	await _test_air_speed_cap()
	await _test_landing_signal()
	_test_input_actions()
	_test_settings_roundtrip()
	await _test_arena_builds()
	await _test_main_scene()
	_clear()
	print("movement tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


# ---- helpers -------------------------------------------------------------

func _clear() -> void:
	for node in _spawned:
		if is_instance_valid(node):
			node.free()
	_spawned.clear()


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = center
	_spawned.append(body)
	return body


## Fresh world with a floor whose top surface is at y = 0.
func _new_world(floor_size: Vector3 = Vector3(80, 1, 80)) -> void:
	_clear()
	_add_box(Vector3(0, -0.5, 0), floor_size)
	await physics_frame
	await physics_frame


func _new_player(position: Vector3) -> Player:
	# Loaded on demand: a PackedScene held by this script would be reported as leaked at exit.
	var player: Player = load("res://player/player.tscn").instantiate()
	root.add_child(player)
	player.global_position = position
	_spawned.append(player)
	return player


func _step(player: Player, move := Vector2.ZERO, jump_pressed := false, jump_held := false, sprint := false) -> void:
	await physics_frame
	player.simulate(move, jump_pressed, jump_held, sprint, _dt)


func _run(player: Player, frames: int, move := Vector2.ZERO, sprint := false) -> void:
	for i in frames:
		await _step(player, move, false, false, sprint)


func _count_jumps(player: Player) -> Array[int]:
	var counter: Array[int] = [0]
	player.jumped.connect(func() -> void: counter[0] += 1)
	return counter


# ---- movement tests ------------------------------------------------------

func _test_settle_on_floor() -> void:
	print("settle on floor")
	await _new_world()
	var player := _new_player(Vector3(0, 2, 0))
	await _run(player, 90)
	_check(player.is_on_floor(), "player ends grounded")
	_check(absf(player.global_position.y) < 0.02, "feet rest on the floor surface (y=%.3f)" % player.global_position.y)


func _test_walk_speed_and_direction() -> void:
	print("walk speed")
	await _new_world()
	var player := _new_player(Vector3.ZERO)
	var top := 0.0
	for i in 90:
		await _step(player, Vector2(0, -1))
		top = maxf(top, player.get_horizontal_speed())
	var walk := player.config.walk_speed
	_check(absf(player.get_horizontal_speed() - walk) < 0.05, "reaches walk speed (%.2f vs %.2f)" % [player.get_horizontal_speed(), walk])
	_check(top <= walk + 0.01, "never exceeds walk speed (peak %.3f)" % top)
	_check(player.velocity.z < 0.0, "forward is -Z")


func _test_sprint_and_strafe_sprint() -> void:
	print("sprint")
	await _new_world()
	var player := _new_player(Vector3.ZERO)
	await _run(player, 90, Vector2(0, -1), true)
	var sprint := player.config.sprint_speed
	_check(absf(player.get_horizontal_speed() - sprint) < 0.05, "forward sprint reaches sprint speed (%.2f vs %.2f)" % [player.get_horizontal_speed(), sprint])

	await _new_world()
	var strafer := _new_player(Vector3.ZERO)
	await _run(strafer, 90, Vector2(1, 0), true)
	_check(absf(strafer.get_horizontal_speed() - strafer.config.walk_speed) < 0.05, "sprint only applies when moving forward (%.2f)" % strafer.get_horizontal_speed())
	_check(strafer.velocity.x > 0.0, "right is +X")


func _test_diagonal_not_faster() -> void:
	print("diagonal")
	await _new_world()
	var player := _new_player(Vector3.ZERO)
	var top := 0.0
	for i in 90:
		await _step(player, Vector2(1, -1))
		top = maxf(top, player.get_horizontal_speed())
	_check(top <= player.config.walk_speed + 0.01, "diagonal input is not faster than straight (peak %.3f)" % top)


func _test_friction_stops() -> void:
	print("friction")
	await _new_world()
	var player := _new_player(Vector3.ZERO)
	await _run(player, 60, Vector2(0, -1))
	await _run(player, 60)
	_check(player.get_horizontal_speed() < 0.05, "stops within 1s of releasing input (%.3f)" % player.get_horizontal_speed())


func _test_jump_height() -> void:
	print("jump height")
	await _new_world()
	var player := _new_player(Vector3.ZERO)
	await _run(player, 20)
	var jumps := _count_jumps(player)
	var apex := 0.0
	for i in 70:
		await _step(player, Vector2.ZERO, i == 0, true)
		apex = maxf(apex, player.global_position.y)
	var target := player.config.jump_height
	_check(absf(apex - target) < 0.1, "apex %.2f m is within 0.1 of jump_height %.2f" % [apex, target])
	_check(jumps[0] == 1, "exactly one jump fired (%d)" % jumps[0])
	_check(player.is_on_floor(), "lands again")


func _test_jump_cut() -> void:
	print("jump cut")
	await _new_world()
	var player := _new_player(Vector3.ZERO)
	await _run(player, 20)
	var apex := 0.0
	for i in 70:
		await _step(player, Vector2.ZERO, i == 0, i < 3)
		apex = maxf(apex, player.global_position.y)
	var full := player.config.jump_height
	_check(apex > 0.1 and apex < full * 0.8, "releasing early lowers the apex (%.2f vs full %.2f)" % [apex, full])


func _frames_until_landing(start_y: float) -> int:
	await _new_world()
	var player := _new_player(Vector3(0, start_y, 0))
	var frames := 0
	while not player.is_on_floor() and frames < 300:
		await _step(player)
		frames += 1
	return frames


func _jumps_with_press_at(start_y: float, press_frame: int, total_frames: int) -> int:
	await _new_world()
	var player := _new_player(Vector3(0, start_y, 0))
	var jumps := _count_jumps(player)
	for i in total_frames:
		await _step(player, Vector2.ZERO, i == press_frame, false)
	return jumps[0]


func _test_jump_buffer() -> void:
	print("jump buffer")
	var landing := await _frames_until_landing(1.5)
	_check(landing > 15, "control run lands after %d frames" % landing)
	var buffered := await _jumps_with_press_at(1.5, landing - 4, landing + 20)
	_check(buffered == 1, "jump pressed just before landing fires on touchdown")
	var too_early := await _jumps_with_press_at(1.5, landing - 15, landing + 20)
	_check(too_early == 0, "jump pressed long before landing is ignored")


func _coyote_jumps(press_after_leaving: int) -> int:
	await _new_world(Vector3(10, 1, 10))
	var player := _new_player(Vector3(3, 0, 0))
	var jumps := _count_jumps(player)
	var left_at := -1
	for i in 120:
		var press := left_at >= 0 and i == left_at + press_after_leaving
		await _step(player, Vector2(1, 0), press, false)
		if left_at < 0 and not player.is_on_floor():
			left_at = i
	_check(left_at >= 0, "player walked off the ledge")
	return jumps[0]


func _test_coyote_time() -> void:
	print("coyote time")
	_check(await _coyote_jumps(3) == 1, "jump shortly after leaving a ledge still works")
	_check(await _coyote_jumps(14) == 0, "jump long after leaving a ledge is refused")


func _test_air_speed_cap() -> void:
	print("air speed")
	await _new_world()
	var player := _new_player(Vector3.ZERO)
	var top := 0.0
	for i in 150:
		await _step(player, Vector2(0, -1), i % 40 == 0, true, true)
		top = maxf(top, player.get_horizontal_speed())
	_check(top <= player.config.sprint_speed + 0.05, "bunny-hopping never beats sprint speed (peak %.2f)" % top)


func _test_landing_signal() -> void:
	print("landing")
	await _new_world()
	var player := _new_player(Vector3(0, 3, 0))
	var impacts: Array[float] = []
	player.landed.connect(func(speed: float) -> void: impacts.append(speed))
	await _run(player, 100)
	_check(impacts.size() == 1, "landed fires exactly once (%d)" % impacts.size())
	_check(impacts.size() == 1 and impacts[0] > 5.0, "reports a meaningful impact speed")


# ---- support tests -------------------------------------------------------

func _test_input_actions() -> void:
	print("input actions")
	InputSetup.ensure_actions()
	var counts := {}
	for action in InputSetup.all_actions():
		_check(InputMap.has_action(action), "action %s exists" % action)
		counts[action] = InputMap.action_get_events(action).size()
	InputSetup.ensure_actions()
	var stable := true
	for action: StringName in counts:
		stable = stable and InputMap.action_get_events(action).size() == counts[action]
	_check(stable, "ensure_actions is idempotent")


func _test_settings_roundtrip() -> void:
	print("settings")
	var path := "user://test_settings.cfg"
	PlayerSettings.mouse_sensitivity = 0.004
	PlayerSettings.fov = 95.0
	PlayerSettings.save_to(path)
	PlayerSettings.mouse_sensitivity = 0.001
	PlayerSettings.fov = 70.0
	PlayerSettings.load_from(path)
	_check(is_equal_approx(PlayerSettings.mouse_sensitivity, 0.004), "sensitivity persists")
	_check(is_equal_approx(PlayerSettings.fov, 95.0), "fov persists")
	for i in 40:
		PlayerSettings.scale_sensitivity(1.5)
	_check(PlayerSettings.mouse_sensitivity <= PlayerSettings.SENSITIVITY_RANGE.y, "sensitivity is clamped")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(PlayerSettings.DEFAULT_PATH)


func _test_arena_builds() -> void:
	print("arena")
	_clear()
	var arena := GrayboxArena.new()
	root.add_child(arena)
	_spawned.append(arena)
	await process_frame
	var bodies := arena.find_children("*", "StaticBody3D", true, false)
	_check(bodies.size() >= 20, "arena has colliders (%d)" % bodies.size())
	_check(arena.get_spawn(0).position.y >= 0.0, "spawn point is above the floor")
	_check(arena.get_navigation_mesh().get_polygon_count() > 0, "navigation mesh baked (%d polygons)" % arena.get_navigation_mesh().get_polygon_count())


func _test_main_scene() -> void:
	print("main scene")
	_clear()
	var main: Node = load("res://world/main.tscn").instantiate()
	main.start_bots = 0
	root.add_child(main)
	_spawned.append(main)
	for i in 120:
		await physics_frame
	var game: Game = main.get_node("Game")
	var arena: GrayboxArena = main.get_node("Arena")
	var player := game.get_human()
	_check(player != null and player.player_id == PlayerRegistry.HOST_ID, "human spawns with the host id")
	_check(player.is_on_floor(), "player spawns and lands on the arena floor")
	var spawn := arena.get_spawn(0)
	_check(player.global_position.distance_to(Vector3(spawn.position.x, 0, spawn.position.z)) < 0.2, "player is at the arena spawn")
	_check(player.camera.current, "local player's camera is current")
	_check(not player.body.visible, "local player's own body is hidden")
