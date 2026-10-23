class_name PlayerStats
extends RefCounted
## Everything perks (and later modifiers and curses) can change about a player, folded into
## one aggregate so CombatSystem and Player read a single place. Defaults are "no change".

var max_hp_bonus := 0.0
var speed_mult := 1.0
## Multipliers on outgoing damage, by weapon kind.
var gun_damage_mult := 1.0
var bow_damage_mult := 1.0
var orb_damage_mult := 1.0
var melee_damage_mult := 1.0
var reload_time_mult := 1.0
var draw_time_mult := 1.0
var damage_taken_mult := 1.0
## Health restored whenever you kill something.
var kill_heal := 0.0
var orb_radius_bonus := 0.0
var orb_cooldown_mult := 1.0
## Added to the chance that a monster drops loot (a fraction, 0.1 = +10 points).
var loot_chance_bonus := 0.0
var sabotage_point_bonus := 0


func damage_mult(def: WeaponDef) -> float:
	match def.kind:
		WeaponDef.Kind.HITSCAN:
			return gun_damage_mult
		WeaponDef.Kind.MELEE:
			return melee_damage_mult
		WeaponDef.Kind.PROJECTILE:
			return bow_damage_mult
		WeaponDef.Kind.ABILITY:
			return orb_damage_mult
	return 1.0
