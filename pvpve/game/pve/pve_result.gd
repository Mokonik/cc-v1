class_name PveResult
extends RefCounted
## What came out of one PvE phase. Produced by a real run (PveDirector) for a human and by
## BotPveModel for a bot, and scored by the same PveScoring formula either way.

var player_id := 0
var difficulty := 1.0
## Monster def id -> number killed.
var kills := {}
var boss_defeated := false
var boss_time_seconds := 0.0
var deaths := 0
var waves_survived := 0
var duration_seconds := 0.0
var xp := 0
var sabotage_points := 0
## Human-readable list of what was picked up ("Sword", "Health pack", ...).
var loot: Array[String] = []
## Weapon ids picked up (a repeat is a tier-up), so a modeled bot can be given the same gear.
var weapon_loot: Array[StringName] = []
var score := 0
## How the phase ended: boss_defeated, boss_timeout, time_up, stopped.
var reason: StringName = &""


func kill_count() -> int:
	var total := 0
	for def_id: StringName in kills:
		total += kills[def_id]
	return total


func add_kill(def_id: StringName) -> void:
	kills[def_id] = kills.get(def_id, 0) + 1
