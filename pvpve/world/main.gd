extends Node3D

@onready var arena: GrayboxArena = $Arena
@onready var player: Player = $Player
@onready var sun: DirectionalLight3D = $Sun


func _ready() -> void:
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	player.global_position = arena.spawn_position
	player.set_look(arena.spawn_yaw, 0.0)
	print("PvPvE Loop Arena booted (Godot %s)" % Engine.get_version_info().string)
