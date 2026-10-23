class_name ModifierDef
extends Resource
## One world modifier, picked by the PvP winner for the next PvE phase. Pure data: each field
## is a number the game reads from a ModifierAggregate; leave a field at its default and that
## part of the game is untouched.

@export var id: StringName = &"double_spawns"
@export var display_name := "Double Spawns"
@export_multiline var description := ""
@export var color := Color(1.0, 0.54, 0.31)

@export_group("Monsters")
@export_range(0.25, 4.0, 0.05) var count_mult := 1.0
@export_range(0.25, 4.0, 0.05) var hp_mult := 1.0
@export_range(0.25, 4.0, 0.05) var damage_mult := 1.0
@export_range(0.25, 4.0, 0.05) var speed_mult := 1.0
## Scales how far monsters can use ranged attacks and charges (fog shortens it).
@export_range(0.25, 2.0, 0.05) var range_mult := 1.0

@export_group("Rewards")
@export_range(0.25, 4.0, 0.05) var xp_mult := 1.0
## Added to every monster's chance to drop loot (0.15 = 15 percentage points).
@export_range(0.0, 1.0, 0.05) var loot_chance_bonus := 0.0

@export_group("Players")
@export_range(0.2, 2.0, 0.05) var gravity_mult := 1.0

@export_group("Volatile")
## Monsters explode on death for this much damage to players within the radius.
@export_range(0.0, 200.0, 1.0) var volatile_damage := 0.0
@export_range(0.0, 10.0, 0.1) var volatile_radius := 0.0

@export_group("Look")
## Fog density for presentation (0 = no fog).
@export_range(0.0, 0.2, 0.005) var fog_density := 0.0
