class_name Vitals
extends RefCounted
## Health, life state and weapons for one player id. Only CombatSystem mutates it.

const MAX_HP := 100.0

var player_id := 0
var max_hp := MAX_HP
var hp := MAX_HP
var alive := true
var respawn_tick := 0
## Damage is ignored until this tick (0 = not protected).
var protected_until_tick := 0
var kills := 0
var deaths := 0
## Invulnerable (dev console).
var god := false
## False for players whose commands should not trigger combat yet (bots and dummies in M3).
var accepts_commands := true
## Monsters never respawn and report deaths as monster_killed.
var is_monster := false
var monster_def_id: StringName = &""
## Perk and modifier effects on this entity.
var stats := PlayerStats.new()
## Movement slow (status effect): factor applies until this tick.
var slow_until_tick := 0
var slow_factor := 1.0
## slot (1-4) -> WeaponState
var weapons: Dictionary = {}
var current_slot := 0


func current() -> WeaponState:
	return weapons.get(current_slot)


func owned_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot: int in weapons:
		slots.append(slot)
	slots.sort()
	return slots
