class_name Game
extends Node
## Authority layer. Owns who is playing, the match seed and the tick counter, and is the
## only place that spawns and removes players. Today it runs in-process for solo play;
## when multiplayer arrives the same methods run on the host and clients mirror the results.

const MAX_PLAYERS := 4
const PlayerScene := preload("res://player/player.tscn")
const BODY_COLORS: Array[Color] = [
	Color(0.25, 0.55, 0.95),
	Color(0.9, 0.3, 0.3),
	Color(0.35, 0.8, 0.4),
	Color(0.95, 0.7, 0.2),
]

@export var arena: GrayboxArena
@export var players_root: Node3D

var seed_value := 1
var rng := RandomNumberGenerator.new()
var registry := PlayerRegistry.new()
var events := EventBus.new()
var tick := 0


func _ready() -> void:
	set_seed(seed_value)


func _physics_process(_delta: float) -> void:
	tick += 1


func set_seed(value: int) -> void:
	seed_value = value
	rng.seed = value


## Returns null when the match is full.
func spawn_player(kind: int, profile: BotProfile = null) -> Player:
	if registry.count() >= MAX_PLAYERS:
		return null
	var record := registry.add(kind)
	var player: Player = PlayerScene.instantiate()
	var source: InputSource
	if kind == PlayerRegistry.Kind.HUMAN:
		record.display_name = "You"
		var local := LocalInputSource.new()
		local.events = events
		source = local
	else:
		var bot := BotInputSource.new()
		bot.get_other_players = get_other_players
		bot.profile = profile if profile != null else BotPresets.make(1)
		bot.rng_seed = hash([seed_value, record.id])
		record.display_name = "%s %d" % [bot.profile.display_name, record.id]
		source = bot

	player.player_id = record.id
	player.display_name = record.display_name
	player.input_source = source
	player.add_child(source)
	record.player = player
	players_root.add_child(player)

	var spawn := arena.get_spawn(registry.count() - 1)
	player.global_position = spawn.position
	player.set_look(spawn.yaw, 0.0)
	player.set_body_color(BODY_COLORS[(record.id - 1) % BODY_COLORS.size()])
	events.player_spawned.emit(record.id)
	return player


func remove_player(id: int) -> void:
	var record := registry.get_record(id)
	if record == null:
		return
	registry.remove(id)
	if is_instance_valid(record.player):
		record.player.queue_free()
	events.player_removed.emit(id)


func clear_bots() -> int:
	var removed := 0
	for id in registry.ids():
		if registry.get_record(id).kind == PlayerRegistry.Kind.BOT:
			remove_player(id)
			removed += 1
	return removed


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
