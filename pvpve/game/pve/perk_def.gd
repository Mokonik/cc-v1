class_name PerkDef
extends Resource
## A perk. Each stack adds the numbers below to the player's PlayerStats; perks last the
## whole run. Fractions are per stack (0.08 = +8%).

@export var id: StringName = &"vitality"
@export var display_name := "Vitality"
@export_multiline var description := ""
@export_range(1, 10) var max_stacks := 3

@export_group("Effects per stack")
@export var max_hp_bonus := 0.0
@export var speed_bonus := 0.0
@export var gun_damage_bonus := 0.0
@export var bow_damage_bonus := 0.0
@export var orb_damage_bonus := 0.0
@export var melee_damage_bonus := 0.0
@export var reload_time_reduction := 0.0
@export var draw_time_reduction := 0.0
@export var damage_taken_reduction := 0.0
@export var kill_heal := 0.0
@export var orb_radius_bonus := 0.0
@export var orb_cooldown_reduction := 0.0
@export var loot_chance_bonus := 0.0
@export var sabotage_point_bonus := 0


## Adds this perk's effect for the given number of stacks.
func apply(stats: PlayerStats, stacks: int) -> void:
	var n := float(stacks)
	stats.max_hp_bonus += max_hp_bonus * n
	stats.speed_mult += speed_bonus * n
	stats.gun_damage_mult += gun_damage_bonus * n
	stats.bow_damage_mult += bow_damage_bonus * n
	stats.orb_damage_mult += orb_damage_bonus * n
	stats.melee_damage_mult += melee_damage_bonus * n
	stats.reload_time_mult -= reload_time_reduction * n
	stats.draw_time_mult -= draw_time_reduction * n
	stats.damage_taken_mult -= damage_taken_reduction * n
	stats.kill_heal += kill_heal * n
	stats.orb_radius_bonus += orb_radius_bonus * n
	stats.orb_cooldown_mult -= orb_cooldown_reduction * n
	stats.loot_chance_bonus += loot_chance_bonus * n
	stats.sabotage_point_bonus += sabotage_point_bonus * stacks
