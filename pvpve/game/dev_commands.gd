class_name DevCommands
extends RefCounted
## The dev console's command set, kept separate from the UI so it can be tested headless.
## Commands for systems that do not exist yet (monsters, points, phases, god mode) are
## added together with those systems.

const HELP := """Commands:
  help                  this list
  bot [0-2]             spawn a bot (0 rookie, 1 regular, 2 veteran)
  bot clear             remove all bots
  players               list who is in the match
  tp <x> <z>            teleport yourself
  timescale <0.05-4>    slow down or speed up time
  seed <n>              set the match seed (affects bots spawned afterwards)
  fov <60-110>          set field of view
  sens <value>          set mouse sensitivity (default 0.0025)"""


static func run(line: String, game: Game) -> String:
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return ""
	var command := parts[0].to_lower()
	var args := parts.slice(1)
	match command:
		"help":
			return HELP
		"bot":
			return _bot(args, game)
		"players":
			return _players(game)
		"tp":
			return _teleport(args, game)
		"timescale":
			return _timescale(args)
		"seed":
			return _seed(args, game)
		"fov":
			return _fov(args)
		"sens":
			return _sens(args)
	return "Unknown command '%s'. Type help." % command


static func _bot(args: PackedStringArray, game: Game) -> String:
	if not args.is_empty() and args[0].to_lower() == "clear":
		return "Removed %d bot(s)." % game.clear_bots()
	var level := 1
	if not args.is_empty():
		if not args[0].is_valid_int():
			return "Usage: bot [0-2] | bot clear"
		level = clampi(args[0].to_int(), 0, 2)
	var player := game.spawn_player(PlayerRegistry.Kind.BOT, BotPresets.make(level))
	if player == null:
		return "Match is full (%d players)." % Game.MAX_PLAYERS
	return "Spawned %s (id %d)." % [player.display_name, player.player_id]


static func _players(game: Game) -> String:
	var lines: Array[String] = []
	for id in game.registry.ids():
		var record := game.registry.get_record(id)
		var player := game.get_player(id)
		var where := "(gone)" if player == null else "(%.1f, %.1f)" % [player.global_position.x, player.global_position.z]
		var kind := "human" if record.kind == PlayerRegistry.Kind.HUMAN else "bot"
		lines.append("  %d  %-5s %-12s %s" % [id, kind, record.display_name, where])
	return "\n".join(lines) if not lines.is_empty() else "No players."


static func _teleport(args: PackedStringArray, game: Game) -> String:
	if args.size() < 2 or not args[0].is_valid_float() or not args[1].is_valid_float():
		return "Usage: tp <x> <z>"
	var human := game.get_human()
	if human == null:
		return "No local player."
	var half := GrayboxArena.SIZE / 2.0 - 1.0
	var x := clampf(args[0].to_float(), -half, half)
	var z := clampf(args[1].to_float(), -half, half)
	human.global_position = Vector3(x, 0.1, z)
	human.velocity = Vector3.ZERO
	return "Teleported to (%.1f, %.1f)." % [x, z]


static func _timescale(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_float():
		return "Usage: timescale <0.05-4> (now %.2f)" % Engine.time_scale
	Engine.time_scale = clampf(args[0].to_float(), 0.05, 4.0)
	return "Time scale %.2f." % Engine.time_scale


static func _seed(args: PackedStringArray, game: Game) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "Usage: seed <n> (now %d)" % game.seed_value
	game.set_seed(args[0].to_int())
	return "Seed %d." % game.seed_value


static func _fov(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_float():
		return "Usage: fov <60-110> (now %.0f)" % PlayerSettings.fov
	PlayerSettings.fov = clampf(args[0].to_float(), PlayerSettings.FOV_RANGE.x, PlayerSettings.FOV_RANGE.y)
	PlayerSettings.save_to()
	return "FOV %.0f." % PlayerSettings.fov


static func _sens(args: PackedStringArray) -> String:
	if args.is_empty() or not args[0].is_valid_float():
		return "Usage: sens <value> (now %.4f)" % PlayerSettings.mouse_sensitivity
	PlayerSettings.mouse_sensitivity = clampf(args[0].to_float(), PlayerSettings.SENSITIVITY_RANGE.x, PlayerSettings.SENSITIVITY_RANGE.y)
	PlayerSettings.save_to()
	return "Sensitivity %.4f." % PlayerSettings.mouse_sensitivity
