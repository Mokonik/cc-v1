class_name CombatSfx
extends Node3D
## Plays a sound for every combat event. Your own actions are played flat (no position);
## everyone else's are positional. Presentation only: it listens to the EventBus.

const NAMES: Array[StringName] = [
	&"shot", &"hit", &"kill", &"hurt", &"reload", &"empty", &"swing",
	&"bow", &"orb", &"explosion", &"respawn", &"draw",
	&"monster_hit", &"monster_die", &"spit", &"slam", &"charge", &"roar",
	&"pickup", &"levelup", &"trap_arm", &"trap_boom", &"heal",
]
## Weapon id -> sound for a fired weapon.
const FIRE_SOUNDS := {&"pistol": &"shot", &"bow": &"bow", &"orb": &"orb"}
## Monster ability -> sound at the monster.
const MONSTER_SOUNDS := {&"melee": &"swing", &"spit": &"spit", &"slam": &"slam", &"charge": &"charge"}

@export var game: Game

var _streams: Dictionary = {}


func _ready() -> void:
	# A headless process (tests, a dedicated server) has nothing to play sound through.
	if DisplayServer.get_name() == "headless":
		return
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
	events.monster_spawned.connect(_on_monster_spawned)
	events.monster_telegraph.connect(_on_monster_telegraph)
	events.monster_attack.connect(func(id: int, ability: StringName, position: Vector3, _r: float) -> void:
		if ability != &"charge":
			_play_3d(MONSTER_SOUNDS.get(ability, &"swing"), position, 2.0 if ability == &"slam" else 0.0))
	events.monster_killed.connect(func(_id: int, _killer: int, position: Vector3, _def: StringName) -> void:
		_play_3d(&"monster_die", position))
	events.loot_picked_up.connect(func(pid: int, _d: int, _k: int, _l: String) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_play_2d(&"pickup"))
	events.level_up.connect(func(pid: int, _level: int) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_play_2d(&"levelup"))
	events.weapon_tier_changed.connect(func(pid: int, _w: StringName, _t: int) -> void:
		if pid == PlayerRegistry.HOST_ID:
			_play_2d(&"levelup", -6.0))
	events.trap_armed.connect(func(trap_id: int) -> void:
		var trap: Trap = game.loot.traps.get(trap_id)
		if trap != null:
			_play_3d(&"trap_arm", trap.position))
	events.trap_triggered.connect(func(_t: int, _v: int, position: Vector3) -> void: _play_3d(&"trap_boom", position, 2.0))
	events.item_used.connect(func(pid: int, item: StringName, _amount: float) -> void:
		if pid == PlayerRegistry.HOST_ID and item == &"health":
			_play_2d(&"heal"))


## Stop anything still playing so the audio server holds no references after we are gone.
func _exit_tree() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()


func _on_weapon_fired(player_id: int, weapon_id: StringName, origin: Vector3, _direction: Vector3, _end: Vector3) -> void:
	var sound: StringName = FIRE_SOUNDS.get(weapon_id, &"")
	if sound == &"":
		return
	if player_id == PlayerRegistry.HOST_ID:
		_play_2d(sound)
	else:
		_play_3d(sound, origin)


func _on_monster_spawned(_monster_id: int, def_id: StringName, position: Vector3) -> void:
	var def := game.monster_defs.get_def(def_id)
	if def != null and def.is_boss:
		_play_3d(&"roar", position, 6.0)


func _on_monster_telegraph(monster_id: int, ability: StringName, _seconds: float) -> void:
	if ability == &"charge":
		var body := game.monsters.get_body(monster_id)
		if body != null:
			_play_3d(&"charge", body.global_position)


func _on_damage_dealt(target_id: int, source_id: int, _amount: float, position: Vector3, _weapon: StringName) -> void:
	if target_id >= MonsterSystem.FIRST_ID and source_id != PlayerRegistry.HOST_ID:
		_play_3d(&"monster_hit", position, -4.0)
	if source_id == PlayerRegistry.HOST_ID and target_id != source_id:
		_play_2d(&"monster_hit" if target_id >= MonsterSystem.FIRST_ID else &"hit", -3.0 if target_id >= MonsterSystem.FIRST_ID else 0.0)
	if target_id == PlayerRegistry.HOST_ID:
		_play_2d(&"hurt")
	elif source_id != PlayerRegistry.HOST_ID and target_id < MonsterSystem.FIRST_ID:
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
