extends Node3D
## Solo sandbox: you plus a few bots standing in for friends.

## Bots spawned at startup. Use the dev console (`) to add or clear more.
@export_range(0, 3) var start_bots := 1

@onready var game: Game = $Game
@onready var sun: DirectionalLight3D = $Sun


func _ready() -> void:
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	game.spawn_player(PlayerRegistry.Kind.HUMAN)
	for i in start_bots:
		game.spawn_player(PlayerRegistry.Kind.BOT, BotPresets.make(1))
	print("PvPvE Loop Arena booted (Godot %s)" % Engine.get_version_info().string)
