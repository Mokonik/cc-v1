class_name PveConfig
extends Resource
## Pacing and scaling of one PvE phase. Difficulty multiplies monster count, health and damage.

@export_group("Timing")
## Length of the wave phase; the boss arrives when it runs out.
@export_range(20.0, 1200.0, 5.0) var phase_seconds := 240.0
@export_range(0.0, 30.0, 0.5) var countdown_seconds := 5.0
@export_range(3.0, 120.0, 1.0) var wave_interval := 20.0

@export_group("Waves")
@export_range(1, 30) var base_wave_size := 4
## Extra monsters added each wave.
@export_range(0.0, 10.0, 0.25) var wave_growth := 1.0
@export_range(4, 60) var alive_cap := 20
@export_range(1, 20) var spitter_from_wave := 2
@export_range(1, 20) var brute_from_wave := 4
@export_range(3.0, 40.0, 0.5) var spawn_min_distance := 12.0
## Seconds a gate glows before its monster appears.
@export_range(0.0, 5.0, 0.1) var spawn_telegraph := 1.0

@export_group("Boss")
@export var boss_enabled := true
@export var boss_id: StringName = &"warden"
## Seconds the gate glows before the boss steps out.
@export_range(0.0, 10.0, 0.5) var boss_telegraph := 2.0
## The boss fight fails if it takes longer than this.
@export_range(30.0, 600.0, 5.0) var boss_time_limit := 150.0

@export_group("Scaling")
@export_range(0.25, 4.0, 0.05) var difficulty := 1.0
