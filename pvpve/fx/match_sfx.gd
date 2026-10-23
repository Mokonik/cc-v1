class_name MatchSfx
extends Node
## Sounds for the match loop: phase changes, wagers, skill kills, table flips, the storm
## warning and the victory sting. Presentation only: it listens to the EventBus.

const NAMES: Array[StringName] = [&"phase", &"chip", &"sting", &"flip", &"ring", &"victory"]

@export var game: Game

var _streams: Dictionary = {}
var _last_ring_warning := -1


func _ready() -> void:
	# A headless process (tests, a dedicated server) has nothing to play sound through.
	if DisplayServer.get_name() == "headless":
		return
	for sound_name in NAMES:
		_streams[sound_name] = load("res://assets/sfx/%s.wav" % sound_name)
	var events := game.events
	events.match_phase.connect(func(phase: StringName, _cycle: int, _seconds: float) -> void:
		if phase != MatchDirector.LOBBY:
			_play(&"victory" if phase == MatchDirector.VICTORY else &"phase"))
	events.wager_set.connect(func(player_id: int, stake: int) -> void:
		if player_id == PlayerRegistry.HOST_ID and stake > 0:
			_play(&"chip"))
	events.pvp_kill_scored.connect(func(killer: int, _victim: int, kill_class: int, _gain: int, _loss: int) -> void:
		if kill_class == PvpRules.KillClass.SHOWSTOPPER:
			_play(&"flip")
		elif kill_class == PvpRules.KillClass.SKILL:
			_play(&"sting", 0.0 if killer == PlayerRegistry.HOST_ID else -6.0))
	events.final_zone.connect(func(radius: float, _center: Vector3) -> void:
		# One warning beep whenever the safe area has shrunk by another 4 m.
		var step := int(radius / 4.0)
		if _last_ring_warning != -1 and step < _last_ring_warning:
			_play(&"ring", -4.0)
		_last_ring_warning = step)


## Stop anything still playing so the audio server holds no references after we are gone.
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer:
			child.stop()


func _play(sound: StringName, volume_db := 0.0) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _streams[sound]
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
