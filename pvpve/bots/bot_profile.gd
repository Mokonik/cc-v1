class_name BotProfile
extends Resource
## How a bot behaves. Bots exist to stand in for friends while testing solo, so
## profiles stay simple: a few knobs, three presets.

@export var display_name := "Bot"
## 0 rookie, 1 regular, 2 veteran: also picks how well this bot does in its modeled PvE.
@export_range(0, 2) var skill_level := 1
## Fastest the bot can turn its view, in degrees per second.
@export_range(30.0, 720.0, 10.0) var aim_speed_deg := 220.0
## Standard deviation of the random aim error, in degrees.
@export_range(0.0, 15.0, 0.5) var aim_error_deg := 2.5
## Seconds the bot needs to see you before it starts tracking you.
@export_range(0.0, 1.5, 0.05) var reaction_time := 0.25
## Closes in until this far from its target, then circle-strafes.
@export_range(3.0, 30.0, 0.5) var engage_distance := 12.0
## Backs away when closer than this.
@export_range(1.0, 15.0, 0.5) var min_distance := 6.0
## Seconds between strafe direction changes (min, max).
@export var strafe_interval := Vector2(0.8, 2.0)
## Sprints while farther than this from its target.
@export_range(5.0, 40.0, 0.5) var sprint_distance := 16.0

