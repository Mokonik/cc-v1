class_name DevCommands
extends RefCounted
## The dev console's command set, kept separate from the UI so it can be tested headless.
## Commands for systems that do not exist yet (monsters, points, phases) are added
## together with those systems.

const HELP := """Commands:
  help                  this list
  bot [0-2]             spawn a bot (0 rookie, 1 regular, 2 veteran)
  bot clear             remove all bots
  players               list who is in the match (hp, kills, deaths)
  give <weapon|all>     give yourself pistol, sword, bow, orb (or all)
  weapons               list your weapons and ammo
  hp <1-100>            set your health
  god                   toggle invulnerability for yourself
  kill <id>             kill a player, bot or dummy
  damage <id> <n>       hurt a player, bot or dummy (credited to you)
  dummy [stand|strafe]  spawn a target dummy in front of you (max 6)
  dummy clear           remove all dummies
  respawn               bring yourself back from the dead right now
  ttk                   ideal time to kill (100 hp) for each weapon
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
		"give":
			return _give(args, game)
		"weapons":
			return _weapons(game)
		"hp":
			return _hp(args, game)
		"god":
			return _god(game)
		"kill":
			return _kill(args, game)
		"damage":
			return _damage(args, game)
		"dummy":
			return _dummy(args, game)
		"respawn":
			return _respawn(game)
		"ttk":
			return _ttk(game)
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
		var kind: String = ["human", "bot", "dummy"][record.kind]
		var vitals := game.combat.get_vitals(id)
		var status := ""
		if vitals != null:
			status = "%3.0f hp  K%d D%d%s" % [vitals.hp, vitals.kills, vitals.deaths, "" if vitals.alive else "  dead"]
		lines.append("  %d  %-6s %-12s %-14s %s" % [id, kind, record.display_name, where, status])
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


static func _human_id(game: Game) -> int:
	return PlayerRegistry.HOST_ID if game.get_human() != null else 0


static func _give(args: PackedStringArray, game: Game) -> String:
	if _human_id(game) == 0:
		return "No local player."
	if args.is_empty():
		return "Usage: give <pistol|sword|bow|orb|all>"
	var wanted := args[0].to_lower()
	if wanted == "all":
		for def in game.weapons.all():
			game.combat.give_weapon(PlayerRegistry.HOST_ID, def.id)
		return "You have every weapon (keys 1-4)."
	if wanted == "fire_orb":
		wanted = "orb"
	if not game.weapons.has(StringName(wanted)):
		return "Unknown weapon '%s'. Try pistol, sword, bow, orb or all." % wanted
	game.combat.give_weapon(PlayerRegistry.HOST_ID, StringName(wanted))
	var def := game.weapons.get_def(StringName(wanted))
	return "Gave %s (key %d)." % [def.display_name, def.slot]


static func _weapons(game: Game) -> String:
	var vitals := game.combat.get_vitals(PlayerRegistry.HOST_ID)
	if vitals == null:
		return "No local player."
	var lines: Array[String] = []
	for def in game.weapons.all():
		var state: WeaponState = vitals.weapons.get(def.slot)
		var owned := "      " if state == null else ("held  " if def.slot == vitals.current_slot else "owned ")
		var ammo := ""
		if state != null and def.uses_ammo():
			ammo = "  %d/%d" % [state.ammo, def.magazine]
		lines.append("  [%d] %s%s%s" % [def.slot, owned, def.display_name, ammo])
	return "\n".join(lines)


static func _hp(args: PackedStringArray, game: Game) -> String:
	if args.is_empty() or not args[0].is_valid_float():
		return "Usage: hp <1-100>"
	game.combat.set_hp(PlayerRegistry.HOST_ID, args[0].to_float())
	var vitals := game.combat.get_vitals(PlayerRegistry.HOST_ID)
	return "Health %.0f." % vitals.hp if vitals != null else "No local player."


static func _god(game: Game) -> String:
	var vitals := game.combat.get_vitals(PlayerRegistry.HOST_ID)
	if vitals == null:
		return "No local player."
	vitals.god = not vitals.god
	return "God mode %s." % ("on" if vitals.god else "off")


static func _kill(args: PackedStringArray, game: Game) -> String:
	if args.is_empty() or not args[0].is_valid_int():
		return "Usage: kill <id> (see players)"
	var id := args[0].to_int()
	if game.combat.get_vitals(id) == null:
		return "No player with id %d." % id
	if not game.combat.is_alive(id):
		return "Player %d is already dead." % id
	game.combat.kill(id, PlayerRegistry.HOST_ID if id != PlayerRegistry.HOST_ID else 0)
	return "Killed player %d." % id


static func _damage(args: PackedStringArray, game: Game) -> String:
	if args.size() < 2 or not args[0].is_valid_int() or not args[1].is_valid_float():
		return "Usage: damage <id> <amount>"
	var id := args[0].to_int()
	var player := game.get_player(id)
	if player == null:
		return "No player with id %d." % id
	var dealt := game.combat.apply_damage(id, args[1].to_float(), PlayerRegistry.HOST_ID, &"console", player.global_position)
	if dealt <= 0.0:
		return "No damage dealt (dead, protected, god mode, or amount <= 0)."
	return "Dealt %.0f damage to player %d." % [dealt, id]


static func _dummy(args: PackedStringArray, game: Game) -> String:
	if not args.is_empty() and args[0].to_lower() == "clear":
		return "Removed %d dummy(ies)." % game.clear_dummies()
	var pattern := DummyInputSource.Pattern.STAND
	if not args.is_empty():
		match args[0].to_lower():
			"stand":
				pattern = DummyInputSource.Pattern.STAND
			"strafe":
				pattern = DummyInputSource.Pattern.STRAFE
			_:
				return "Usage: dummy [stand|strafe] | dummy clear"
	var human := game.get_human()
	if human == null:
		return "No local player."
	var index := game.registry.count_kind(PlayerRegistry.Kind.DUMMY)
	var forward := Player.direction_from(human.rotation.y, 0.0)
	var right := Vector3(forward.z * -1.0, 0.0, forward.x)
	var spot := human.global_position + forward * (12.0 + 3.0 * (index / 5)) + right * (((index % 5) - 2) * 2.5)
	var half := GrayboxArena.SIZE / 2.0 - 2.0
	spot.x = clampf(spot.x, -half, half)
	spot.z = clampf(spot.z, -half, half)
	var dummy := game.spawn_dummy(spot, pattern)
	if dummy == null:
		return "Dummy limit reached (%d)." % Game.MAX_DUMMIES
	return "Spawned %s (id %d)." % [dummy.display_name, dummy.player_id]


static func _respawn(game: Game) -> String:
	if game.combat.get_vitals(PlayerRegistry.HOST_ID) == null:
		return "No local player."
	if game.combat.is_alive(PlayerRegistry.HOST_ID):
		return "You are alive."
	game.combat.respawn_now(PlayerRegistry.HOST_ID)
	return "Respawning."


static func _ttk(game: Game) -> String:
	var lines: Array[String] = []
	for def in game.weapons.all():
		lines.append("  %-9s %5.1f dmg  %5.2f s ideal TTK from 100 hp" % [def.display_name, def.damage, def.ttk(Vitals.MAX_HP)])
	return "\n".join(lines)
