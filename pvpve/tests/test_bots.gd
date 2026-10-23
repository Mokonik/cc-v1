# Headless tests for the solo-first foundation: player registry, spawning, dev commands, bots.
# Run with: pvpve/tools/godot.sh --headless --script res://tests/test_bots.gd
extends SceneTree

var _failures := 0
var _main: Node


func _initialize() -> void:
	_run_all()


func _run_all() -> void:
	# The root is not inside the tree yet during _initialize; wait a frame before building nodes.
	await process_frame
	_test_registry()
	_test_profiles()
	await _test_spawning_and_limits()
	await _test_dev_commands()
	await _test_bot_reaches_target_around_cover()
	await _test_bot_run_is_deterministic()
	await _test_bot_idles_alone()
	print("bot tests: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok   ", message)
	else:
		_failures += 1
		print("  FAIL ", message)


# ---- helpers -------------------------------------------------------------

func _new_main(seed_value := 1) -> Game:
	if _main != null:
		_main.free()
	_main = load("res://world/main.tscn").instantiate()
	_main.start_bots = 0
	root.add_child(_main)
	var game: Game = _main.get_node("Game")
	game.set_seed(seed_value)
	return game


func _frames(count: int) -> void:
	for i in count:
		await physics_frame


func _flat_distance(a: Player, b: Player) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


# ---- tests ---------------------------------------------------------------

func _test_registry() -> void:
	print("registry")
	var registry := PlayerRegistry.new()
	var bot_first := registry.add(PlayerRegistry.Kind.BOT)
	var human := registry.add(PlayerRegistry.Kind.HUMAN)
	var bot_second := registry.add(PlayerRegistry.Kind.BOT)
	_check(human.id == PlayerRegistry.HOST_ID, "human gets the host id even when a bot joined first")
	_check(bot_first.id != human.id and bot_second.id != human.id and bot_first.id != bot_second.id, "ids are unique")
	_check(registry.count() == 3 and registry.count_kind(PlayerRegistry.Kind.BOT) == 2, "counts by kind")
	registry.remove(bot_first.id)
	_check(registry.get_record(bot_first.id) == null and registry.count() == 2, "remove forgets the player")
	var reused := registry.add(PlayerRegistry.Kind.BOT)
	_check(reused.id != bot_second.id and reused.id != human.id, "new bot never reuses a live id")


func _test_profiles() -> void:
	print("bot profiles")
	var rookie := BotPresets.make(0)
	var regular := BotPresets.make(1)
	var veteran := BotPresets.make(2)
	_check(rookie.aim_speed_deg < regular.aim_speed_deg and regular.aim_speed_deg < veteran.aim_speed_deg, "aim speed rises with skill")
	_check(rookie.aim_error_deg > regular.aim_error_deg and regular.aim_error_deg > veteran.aim_error_deg, "aim error falls with skill")
	_check(rookie.reaction_time > veteran.reaction_time, "veterans react faster")
	_check(BotPresets.make(99).display_name == veteran.display_name and BotPresets.make(-5).display_name == rookie.display_name, "levels are clamped")


func _test_spawning_and_limits() -> void:
	print("spawning")
	var game := _new_main()
	await _frames(2)
	var human := game.get_human()
	var bot_a := game.spawn_player(PlayerRegistry.Kind.BOT)
	var bot_b := game.spawn_player(PlayerRegistry.Kind.BOT)
	var bot_c := game.spawn_player(PlayerRegistry.Kind.BOT)
	var extra := game.spawn_player(PlayerRegistry.Kind.BOT)
	_check(human != null and bot_a != null and bot_b != null and bot_c != null, "four players fit (main spawns the human)")
	_check(extra == null, "a fifth player is refused")
	_check(human.player_id == 1, "human is id 1")
	_check(human.input_source is LocalInputSource and bot_a.input_source is BotInputSource, "input sources match player kind")
	_check(human.input_source.is_local_view() and not bot_a.input_source.is_local_view(), "only the human owns the camera")
	_check(bot_a.body.visible and not human.body.visible, "bots are visible, your own body is not")
	var spawns := {}
	for player: Player in [human, bot_a, bot_b, bot_c]:
		spawns[player.global_position.snappedf(0.1)] = true
	_check(spawns.size() == 4, "each player gets a different spawn point")
	game.remove_player(bot_b.player_id)
	_check(game.registry.count() == 3 and game.get_player(bot_b.player_id) == null, "remove_player forgets the bot")
	_check(game.clear_bots() == 2 and game.registry.count() == 1, "clear_bots removes only bots")


func _test_dev_commands() -> void:
	print("dev commands")
	var game := _new_main()
	await _frames(2)
	var human := game.get_human()
	_check(DevCommands.run("help", game).contains("bot"), "help lists commands")
	_check(DevCommands.run("nonsense", game).begins_with("Unknown command"), "unknown command is reported")
	_check(DevCommands.run("bot 2", game).contains("Veteran"), "bot <level> spawns that profile")
	_check(game.registry.count_kind(PlayerRegistry.Kind.BOT) == 1, "bot count is 1")
	DevCommands.run("bot", game)
	DevCommands.run("bot", game)
	_check(DevCommands.run("bot", game).contains("full"), "bot refuses when the match is full")
	_check(DevCommands.run("bot clear", game).contains("3"), "bot clear reports how many it removed")
	_check(DevCommands.run("tp 5 -7", game).begins_with("Teleported") and absf(human.global_position.x - 5.0) < 0.01 and absf(human.global_position.z + 7.0) < 0.01, "tp moves the player")
	DevCommands.run("tp 999 999", game)
	_check(absf(human.global_position.x) <= GrayboxArena.SIZE / 2.0, "tp is kept inside the arena")
	DevCommands.run("timescale 2", game)
	_check(is_equal_approx(Engine.time_scale, 2.0), "timescale applies")
	DevCommands.run("timescale 1", game)
	DevCommands.run("seed 42", game)
	_check(game.seed_value == 42, "seed applies")
	_check(DevCommands.run("tp x", game).begins_with("Usage"), "bad arguments print usage")


## Spawns the human behind the center block from the bot's side and runs the bot for a while.
## Returns the bot and human, plus how many ticks the bot wanted to fire.
func _run_chase(seed_value: int, frames: int) -> Dictionary:
	var game := _new_main(seed_value)
	await _frames(2)
	var human := game.get_human()
	var bot := game.spawn_player(PlayerRegistry.Kind.BOT, BotPresets.make(2))
	human.global_position = Vector3(4.0, 0.1, -2.0)
	human.velocity = Vector3.ZERO
	var fire_ticks := 0
	for i in frames:
		await physics_frame
		var source := bot.input_source as BotInputSource
		if source.last_command.fire_held:
			fire_ticks += 1
	return {"bot": bot, "human": human, "fire_ticks": fire_ticks}


func _test_bot_reaches_target_around_cover() -> void:
	print("bot pathing")
	var run := await _run_chase(1, 900)
	var bot: Player = run.bot
	var human: Player = run.human
	var profile := (bot.input_source as BotInputSource).profile
	var distance := _flat_distance(bot, human)
	_check(distance < profile.engage_distance + 1.5, "bot closes to engage range around the cover block (%.1f m)" % distance)
	_check(run.fire_ticks > 0, "bot wanted to fire once it had line of sight (%d ticks)" % run.fire_ticks)
	_check((bot.input_source as BotInputSource).target_id == human.player_id, "bot targets the human")
	var to_human := human.global_position - bot.global_position
	var facing := Vector3(-sin(bot.rotation.y), 0.0, -cos(bot.rotation.y))
	_check(facing.angle_to(Vector3(to_human.x, 0.0, to_human.z)) < deg_to_rad(15.0), "bot is facing its target")
	_check(bot.global_position.y < 0.5, "bot stayed on the ground")


func _test_bot_run_is_deterministic() -> void:
	print("determinism")
	var first := await _run_chase(7, 600)
	var first_position: Vector3 = (first.bot as Player).global_position
	var first_yaw: float = (first.bot as Player).rotation.y
	var second := await _run_chase(7, 600)
	var second_position: Vector3 = (second.bot as Player).global_position
	var second_yaw: float = (second.bot as Player).rotation.y
	_check(first_position.distance_to(second_position) < 0.05, "same seed gives the same bot position (%.4f apart)" % first_position.distance_to(second_position))
	_check(absf(angle_difference(first_yaw, second_yaw)) < 0.01, "same seed gives the same bot facing")
	var other := await _run_chase(8, 600)
	var other_position: Vector3 = (other.bot as Player).global_position
	_check(first_position.distance_to(other_position) > 0.05 or absf(angle_difference(first_yaw, (other.bot as Player).rotation.y)) > 0.001, "a different seed changes bot behavior")


func _test_bot_idles_alone() -> void:
	print("bot alone")
	var game := _new_main()
	await _frames(2)
	game.remove_player(PlayerRegistry.HOST_ID)
	await _frames(2)
	var bot := game.spawn_player(PlayerRegistry.Kind.BOT)
	var start := bot.global_position
	await _frames(120)
	_check(bot.global_position.distance_to(start) < 0.3, "a bot with nobody to chase stands still")
	_check((bot.input_source as BotInputSource).target_id == 0, "and has no target")
	_main.free()
	_main = null
