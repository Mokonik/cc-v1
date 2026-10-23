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
const DUMMY_COLOR := Color(0.92, 0.55, 0.22)

@export var arena: GrayboxArena
@export var players_root: Node3D

var seed_value := 1
var rng := RandomNumberGenerator.new()
var registry := PlayerRegistry.new()
var events := EventBus.new()
var weapons := WeaponCatalog.new()
var combat := CombatSystem.new()
var tick := 0

## Where dummies reappear after dying (player id -> GrayboxArena.Spawn).
var _homes: Dictionary = {}


func _ready() -> void:
	combat.setup(events, weapons, get_player, _space_state, _spawn_for)
	set_seed(seed_value)


func _physics_process(_delta: float) -> void:
	tick += 1
	combat.step(tick)


func set_seed(value: int) -> void:
	seed_value = value
	rng.seed = value
	combat.seed_value = value


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
		var bot := BotInputSource.new()
		bot.get_opponents = get_opponents
		bot.profile = profile if profile != null else BotPresets.make(1)
		bot.rng_seed = hash([seed_value, record.id])
		record.display_name = "%s %d" % [bot.profile.display_name, record.id]
		source = bot

	var player := _create_player(record, source)
	var spawn := arena.get_spawn(registry.count() - registry.count_kind(PlayerRegistry.Kind.DUMMY) - 1)
	player.global_position = spawn.position
	player.set_look(spawn.yaw, 0.0)
	player.set_body_color(BODY_COLORS[(record.id - 1) % BODY_COLORS.size()])
	# Bots only move in M3: they are targets, and do not fire back yet.
	combat.register(record.id, kind == PlayerRegistry.Kind.HUMAN)
	events.player_spawned.emit(record.id)
	return player


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
	registry.remove(id)
	combat.unregister(id)
	_homes.erase(id)
	if is_instance_valid(record.player):
		record.player.queue_free()
	events.player_removed.emit(id)


func clear_bots() -> int:
	return _clear_kind(PlayerRegistry.Kind.BOT)


func clear_dummies() -> int:
	return _clear_kind(PlayerRegistry.Kind.DUMMY)


func get_player(id: int) -> Player:
	var record := registry.get_record(id)
	if record != null and is_instance_valid(record.player):
		return record.player
	return null


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
