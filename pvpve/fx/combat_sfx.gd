class_name CombatSfx
extends Node3D
## Plays a sound for every combat event. Your own actions are played flat (no position);
## everyone else's are positional. Presentation only: it listens to the EventBus.

const NAMES: Array[StringName] = [
	&"shot", &"hit", &"kill", &"hurt", &"reload", &"empty", &"swing",
	&"bow", &"orb", &"explosion", &"respawn", &"draw",
]
## Weapon id -> sound for a fired weapon.
const FIRE_SOUNDS := {&"pistol": &"shot", &"bow": &"bow", &"orb": &"orb"}

@export var game: Game

var _streams: Dictionary = {}


func _ready() -> void:
	for sound_name in NAMES:
		_streams[sound_name] = load("res://assets/sfx/%s.wav" % sound_name)
	var events := game.events
	events.weapon_fired.connect(_on_weapon_fired)
	events.melee_swing.connect(func(pid: int, _wid: StringName) -> void: _play_for(pid, &"swing"))
	events.reload_started.connect(func(pid: int, _wid: StringName, _d: float) -> void: _play_for(pid, &"reload"))
	events.draw_started.connect(func(pid: int, _wid: StringName, _d: float) -> void: _play_for(pid, &"draw"))
	events.explosion.connect(func(position: Vector3, _r: float, _w: StringName) -> void: _play_3d(&"explosion", position, 4.0))
	events.damage_dealt.connect(_on_damage_dealt)
	events.player_died.connect(func(_victim: int, killer: int, _w: StringName) -> void:
		if killer == PlayerRegistry.HOST_ID:
			_play_2d(&"kill"))
	events.player_respawned.connect(func(pid: int) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_play_2d(&"respawn"))


func _on_weapon_fired(player_id: int, weapon_id: StringName, origin: Vector3, _direction: Vector3, _end: Vector3) -> void:
	var sound: StringName = FIRE_SOUNDS.get(weapon_id, &"")
	if sound == &"":
		return
	if player_id == PlayerRegistry.HOST_ID:
		_play_2d(sound)
	else:
		_play_3d(sound, origin)


func _on_damage_dealt(target_id: int, source_id: int, _amount: float, position: Vector3, _weapon: StringName) -> void:
	if source_id == PlayerRegistry.HOST_ID and target_id != source_id:
		_play_2d(&"hit")
	if target_id == PlayerRegistry.HOST_ID:
		_play_2d(&"hurt")
	elif source_id != PlayerRegistry.HOST_ID:
		_play_3d(&"hit", position, -6.0)


func _play_for(player_id: int, sound: StringName) -> void:
	if player_id == PlayerRegistry.HOST_ID:
		_play_2d(sound)
	else:
		var player := game.get_player(player_id)
		if player != null:
			_play_3d(sound, player.global_position)


func _play_2d(sound: StringName, volume_db := 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.finished.connect(voice.queue_free)
	add_child(voice)
	voice.play()


func _play_3d(sound: StringName, position: Vector3, volume_db := 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.volume_db = volume_db
	voice.unit_size = 8.0
	voice.finished.connect(voice.queue_free)
	add_child(voice)
	voice.global_position = position
	voice.play()
