class_name Game
extends Node
## Authority layer. Owns who is playing, the match seed, the tick counter and combat, and is
## the only place that spawns and removes players. Today it runs in-process for solo play;
## when multiplayer arrives the same methods run on the host and clients mirror the results.

## Humans and bots. Dummies are targets and do not count toward this.
const MAX_PLAYERS := 4
const MAX_DUMMIES := 6
const PlayerScene := preload("res://player/player.tscn")
const BODY_COLORS: Array[Color] = [
	Color(0.25, 0.55, 0.95),
	Color(0.9, 0.3, 0.3),
	Color(0.35, 0.8, 0.4),
	Color(0.95, 0.7, 0.2),
]
const NAV_SYNC_TICKS := 10
const DUMMY_COLOR := Color(0.92, 0.55, 0.22)

@export var arena: GrayboxArena
@export var players_root: Node3D
@export var monsters_root: Node3D
@export var zones_root: Node3D

var seed_value := 1
var rng := RandomNumberGenerator.new()
var registry := PlayerRegistry.new()
var events := EventBus.new()
var weapons := WeaponCatalog.new()
var combat := CombatSystem.new()
var monster_defs := MonsterCatalog.new()
var monsters := MonsterSystem.new()
var zones := ZoneManager.new()
var pve := PveDirector.new()
var progression := Progression.new()
var perk_defs := PerkCatalog.new()
var loot := LootSystem.new()
var modifier_defs := ModifierCatalog.new()
var modifiers := ModifierState.new(modifier_defs)
var match_director := MatchDirector.new()
## Default difficulty for new PvE phases (1.0 = base). M5 raises it for the score leader.
var pve_difficulty := 1.0
## Whether bots may use their weapons. Matches turn it on for PvP and the final.
var bots_fight := false
var tick := 0
## Humans driven by a bot brain (player id -> their own LocalInputSource, kept to restore later).
var autopilot: Dictionary = {}
var _bot_profiles: Dictionary = {}

## Where dummies reappear after dying (player id -> GrayboxArena.Spawn).
var _homes: Dictionary = {}


func _ready() -> void:
	combat.setup(events, weapons, get_body, _space_state, _spawn_for)
	monsters.setup(events, combat, monster_defs, monsters_root, get_opponents.bind(0), get_player)
	zones.setup(zones_root)
	pve.setup(events, combat, monsters, zones, monster_defs, get_player, load("res://content/pve_config.tres"))
	match_director.setup(self)
	monsters.get_modifier = modifiers.aggregate_for
	pve.get_modifier = modifiers.aggregate_for
	progression.setup(events, combat, perk_defs)
	loot.setup(events, combat, progression, monster_defs, get_body, load("res://content/loot/default_loot.tres"))
	events.monster_killed.connect(_on_monster_killed)
	events.player_died.connect(_on_player_died)
	events.loot_picked_up.connect(_on_loot_picked_up)
	set_seed(seed_value)


func _physics_process(_delta: float) -> void:
	tick += 1
	if tick <= NAV_SYNC_TICKS:
		# Make the first navigation queries independent of when the server's own sync lands.
		NavigationServer3D.map_force_update(arena.get_world_3d().navigation_map)
	combat.step(tick)
	_apply_player_modifiers()
	_process_player_actions()
	monsters.step(tick)
	pve.step(tick)
	loot.step(tick)
	match_director.step(tick)


## Low gravity and friends reach the player bodies through their scale fields.
func _apply_player_modifiers() -> void:
	for player: Player in get_opponents(0):
		player.gravity_scale = modifiers.aggregate_for(player.entity_id).gravity_mult


func set_seed(value: int) -> void:
	seed_value = value
	rng.seed = value
	combat.seed_value = value
	monsters.set_seed(value)
	pve.set_seed(value)
	progression.set_seed(value)
	loot.set_seed(value)


## Spawns a human or a bot. Returns null when the match is full.
func spawn_player(kind: int, profile: BotProfile = null) -> Player:
	if registry.count() - registry.count_kind(PlayerRegistry.Kind.DUMMY) >= MAX_PLAYERS:
		return null
	var record := registry.add(kind)
	var source: InputSource
	if kind == PlayerRegistry.Kind.HUMAN:
		record.display_name = "You"
		var local := LocalInputSource.new()
		local.events = events
		source = local
	else:
		var bot := _make_bot_source(record.id, profile if profile != null else BotPresets.make(1))
		record.display_name = "%s %d" % [bot.profile.display_name, record.id]
		source = bot

	var player := _create_player(record, source)
	var spawn := arena.get_spawn(registry.count() - registry.count_kind(PlayerRegistry.Kind.DUMMY) - 1)
	player.global_position = spawn.position
	player.set_look(spawn.yaw, 0.0)
	player.set_body_color(BODY_COLORS[(record.id - 1) % BODY_COLORS.size()])
	# Bots are targets in the sandbox; they fight only while bots_fight is on (matches turn it on).
	combat.register(record.id, kind == PlayerRegistry.Kind.HUMAN or bots_fight)
	progression.register(record.id)
	loot.register(record.id)
	events.player_spawned.emit(record.id)
	return player


func _make_bot_source(id: int, profile: BotProfile) -> BotInputSource:
	var bot := BotInputSource.new()
	bot.get_opponents = get_opponents
	bot.get_loadout = get_loadout
	bot.profile = profile
	bot.rng_seed = hash([seed_value, id])
	_bot_profiles[id] = profile
	return bot


## Lets a bot brain play a human's character (the demo / watch-it-play mode), or hands it back.
func set_autopilot(player_id: int, enabled: bool) -> bool:
	var player := get_player(player_id)
	var record := registry.get_record(player_id)
	if player == null or record == null or record.kind != PlayerRegistry.Kind.HUMAN:
		return false
	if enabled == autopilot.has(player_id):
		return true
	if enabled:
		var bot := _make_bot_source(player_id, BotPresets.make(1))
		autopilot[player_id] = player.input_source
		player.add_child(bot)
		player.input_source = bot
		bot.set_view(player.rotation.y, 0.0)
	else:
		var bot := player.input_source
		player.input_source = autopilot[player_id]
		autopilot.erase(player_id)
		bot.queue_free()
	return true


## The PvE skill level (0-2) of a bot or autopilot player.
func skill_level_of(player_id: int) -> int:
	var profile: BotProfile = _bot_profiles.get(player_id)
	return profile.skill_level if profile != null else 1


## True for bots and for humans on autopilot: their PvE comes from the stat model.
func is_modeled(player_id: int) -> bool:
	var record := registry.get_record(player_id)
	return record != null and (record.kind == PlayerRegistry.Kind.BOT or autopilot.has(player_id))


## Spawns a target dummy at a ground position. Returns null at the dummy limit.
func spawn_dummy(position: Vector3, pattern: int = DummyInputSource.Pattern.STAND) -> Player:
	if registry.count_kind(PlayerRegistry.Kind.DUMMY) >= MAX_DUMMIES:
		return null
	var record := registry.add(PlayerRegistry.Kind.DUMMY)
	record.display_name = "Dummy %d" % record.id
	var source := DummyInputSource.new()
	source.pattern = pattern
	var player := _create_player(record, source)
	var home := GrayboxArena.Spawn.new(Vector3(position.x, 0.1, position.z), 0.0)
	_homes[record.id] = home
	player.global_position = home.position
	player.set_look(home.yaw, 0.0)
	player.set_body_color(DUMMY_COLOR)
	combat.register(record.id, false)
	events.player_spawned.emit(record.id)
	return player


func remove_player(id: int) -> void:
	var record := registry.get_record(id)
	if record == null:
		return
	pve.stop_run(id)
	zones.free_zone(id)
	registry.remove(id)
	combat.unregister(id)
	progression.unregister(id)
	loot.unregister(id)
	_homes.erase(id)
	if is_instance_valid(record.player):
		record.player.queue_free()
	events.player_removed.emit(id)


func clear_bots() -> int:
	return _clear_kind(PlayerRegistry.Kind.BOT)


func clear_dummies() -> int:
	return _clear_kind(PlayerRegistry.Kind.DUMMY)


func clear_monsters() -> int:
	return monsters.clear_all()


func get_player(id: int) -> Player:
	var record := registry.get_record(id)
	if record != null and is_instance_valid(record.player):
		return record.player
	return null


## Lets bots shoot and swing (or not). Applies to every bot now and to bots spawned later.
func set_bots_fight(enabled: bool) -> void:
	bots_fight = enabled
	for id in registry.ids():
		if registry.get_record(id).kind == PlayerRegistry.Kind.BOT:
			var vitals := combat.get_vitals(id)
			if vitals != null:
				vitals.accepts_commands = enabled


## What a bot is holding, for its weapon chooser.
func get_loadout(id: int) -> Dictionary:
	var vitals := combat.get_vitals(id)
	if vitals == null:
		return {}
	return {"owned": vitals.owned_slots(), "current": vitals.current_slot}


## Any combatant by entity id: a player, and (later) a monster.
func get_body(id: int) -> Combatant:
	if id >= MonsterSystem.FIRST_ID:
		return monsters.get_body(id)
	return get_player(id)


func get_human() -> Player:
	return get_player(PlayerRegistry.HOST_ID)


func get_other_players(id: int) -> Array[Player]:
	var others: Array[Player] = []
	for other_id in registry.ids():
		if other_id != id:
			var player := get_player(other_id)
			if player != null:
				others.append(player)
	return others


## Who a bot should consider hostile: living humans and bots, never dummies.
func get_opponents(id: int) -> Array[Player]:
	var opponents: Array[Player] = []
	for other_id in registry.ids():
		if other_id == id or registry.get_record(other_id).kind == PlayerRegistry.Kind.DUMMY:
			continue
		var player := get_player(other_id)
		if player != null and combat.is_alive(other_id):
			opponents.append(player)
	return opponents


func _create_player(record: PlayerRegistry.Record, source: InputSource) -> Player:
	var player: Player = PlayerScene.instantiate()
	player.player_id = record.id
	player.display_name = record.display_name
	player.input_source = source
	player.add_child(source)
	record.player = player
	players_root.add_child(player)
	return player


func _clear_kind(kind: int) -> int:
	var removed := 0
	for id in registry.ids():
		if registry.get_record(id).kind == kind:
			remove_player(id)
			removed += 1
	return removed


func _space_state() -> PhysicsDirectSpaceState3D:
	return players_root.get_world_3d().direct_space_state


## Dummies return to where they were placed; everyone else takes the spawn point
## farthest from the other living players.
func _spawn_for(id: int) -> GrayboxArena.Spawn:
	if _homes.has(id):
		return _homes[id]
	if zones.is_inside(id):
		return zones.get_zone(id).player_start()
	var best_index := 0
	var best_distance := -1.0
	for i in GrayboxArena.SPAWN_POINTS.size():
		var spawn := arena.get_spawn(i)
		var nearest := INF
		for other in get_other_players(id):
			if combat.is_alive(other.player_id):
				nearest = minf(nearest, spawn.position.distance_to(other.global_position))
		if nearest > best_distance:
			best_distance = nearest
			best_index = i
	return arena.get_spawn(best_index)


## Rewards for a monster kill: XP, Sabotage Points and a seeded loot roll, all to the killer.
## Runs a bot's PvE phase through the stat model instead of a real zone, then gives the bot the
## results exactly as a human would earn them: XP (and so level-ups and perks), Sabotage Points
## and a recorded result. level selects the skill (0 rookie, 1 regular, 2 veteran).
func run_bot_pve(bot_id: int, level := 1, effects: BotPveModel.Effects = null, difficulty := -1.0) -> PveResult:
	if not is_modeled(bot_id):
		return null
	var config: PveConfig = pve.base_config().duplicate()
	config.difficulty = difficulty if difficulty > 0.0 else pve_difficulty
	if effects == null:
		effects = modifiers.aggregate_for(bot_id).bot_effects()
	var result := BotPveModel.simulate(BotPveModel.skill_for_level(level), config, monster_defs, seed_value, bot_id, effects)
	progression.grant_xp(bot_id, result.xp)
	progression.grant_sabotage_points(bot_id, result.sabotage_points)
	var state := progression.get_state(bot_id)
	while state.has_pending_offer():
		progression.pick_perk(bot_id, BotPerkPicker.choose(state.offers[0]))
	for weapon_id in result.weapon_loot:
		combat.grant_weapon_loot(bot_id, weapon_id)
	pve.last_results[bot_id] = result
	return result


func _on_monster_killed(monster_id: int, killer_id: int, position: Vector3, def_id: StringName) -> void:
	var record := monsters.get_record(monster_id)
	var def := monster_defs.get_def(def_id)
	if record != null and def != null:
		var xp := 0
		var points := 0
		if progression.get_state(killer_id) != null:
			var killer_stats := combat.get_vitals(killer_id).stats
			xp = roundi(def.xp * modifiers.aggregate_for(record.owner_id).xp_mult)
			points = def.sabotage_points + killer_stats.sabotage_point_bonus
			progression.grant_xp(killer_id, xp)
			progression.grant_sabotage_points(killer_id, points)
		var modifier := modifiers.aggregate_for(record.owner_id)
		loot.roll_drop(monster_id, def, killer_id, record.owner_id, position + Vector3(0.0, 0.4, 0.0), record.wave, modifier.loot_chance_bonus)
		if modifier.volatile_damage > 0.0:
			# Volatile: the corpse bursts and hurts players only (never other monsters).
			events.monster_exploded.emit(monster_id, position, modifier.volatile_radius)
			combat.area_damage(monster_id, position, modifier.volatile_radius, modifier.volatile_damage, &"volatile")
		pve.record_kill(record.owner_id, def_id, monster_id, xp, points)
	monsters.mark_dead(monster_id)


func _on_loot_picked_up(player_id: int, _drop_id: int, _kind: int, label: String) -> void:
	pve.record_loot(player_id, label)


## Item, trap and perk-choice commands from each player's last command. One-shot flags, so
## each applies once per tick.
func _process_player_actions() -> void:
	for id in registry.ids():
		var player := get_player(id)
		if player == null or not combat.is_alive(id) or not combat.get_vitals(id).accepts_commands:
			continue
		var command := player.last_command
		if command.use_item:
			loot.use_health_pack(id)
		if command.place_trap:
			loot.place_trap(id)
		if command.perk_pick != 0 and not match_director.choose(id, command.perk_pick):
			progression.pick_perk(id, command.perk_pick)


func _on_player_died(victim_id: int, _killer_id: int, _weapon_id: StringName) -> void:
	pve.record_death(victim_id)
