class_name MonsterDef
extends Resource
## One kind of monster. Abilities are switched on by their numbers (damage above zero), so a
## new monster is a new .tres under content/monsters/ with no AI code: the Grunt melees, the
## Spitter kites and spits, the Brute slams and charges, and the Warden does all of it.

@export var id: StringName = &"grunt"
@export var display_name := "Grunt"

@export_group("Body")
@export_range(0.1, 2.0, 0.05) var radius := 0.4
@export_range(0.5, 5.0, 0.05) var height := 1.6
@export var color := Color(0.55, 0.7, 0.35)

@export_group("Stats")
@export_range(1.0, 5000.0, 1.0) var max_hp := 60.0
@export_range(0.5, 20.0, 0.1) var move_speed := 4.0
## Ignores players farther away than this.
@export_range(5.0, 200.0, 1.0) var sight_range := 70.0

@export_group("Melee")
## Damage per hit; 0 disables the ability.
@export_range(0.0, 200.0, 0.5) var melee_damage := 10.0
@export_range(0.5, 6.0, 0.1) var melee_range := 1.9
@export_range(0.05, 3.0, 0.05) var melee_windup := 0.35
@export_range(0.2, 10.0, 0.05) var melee_interval := 1.1

@export_group("Ranged")
## Projectile definition for spitting; null disables the ability.
@export var spit: WeaponDef
## Projectiles per spit, fanned out over spit_spread_deg.
@export_range(1, 8) var spit_count := 1
@export_range(0.0, 60.0, 0.5) var spit_spread_deg := 0.0
@export_range(2.0, 60.0, 0.5) var spit_range := 22.0
@export_range(0.05, 3.0, 0.05) var spit_windup := 0.5
@export_range(0.2, 10.0, 0.05) var spit_interval := 1.8
## Prefers to stay about this far from its target (0 = just closes in).
@export_range(0.0, 40.0, 0.5) var keep_distance := 0.0

@export_group("Slam")
@export_range(0.0, 200.0, 0.5) var slam_damage := 0.0
@export_range(0.5, 12.0, 0.1) var slam_radius := 3.0
@export_range(0.05, 3.0, 0.05) var slam_windup := 0.7
@export_range(0.5, 20.0, 0.1) var slam_cooldown := 2.4

@export_group("Charge")
@export_range(0.0, 200.0, 0.5) var charge_damage := 0.0
@export_range(0.05, 3.0, 0.05) var charge_windup := 0.8
@export_range(2.0, 30.0, 0.5) var charge_speed := 14.0
@export_range(0.2, 4.0, 0.05) var charge_time := 1.2
@export_range(1.0, 30.0, 0.5) var charge_cooldown := 6.0
## Helpless for this long after a charge ends or hits a wall.
@export_range(0.0, 5.0, 0.05) var stun_time := 1.5

@export_group("Boss")
## Summons this monster (by id) when health first drops below summon_at_fraction.
@export var summon_id: StringName = &""
@export_range(0, 10) var summon_count := 0
@export_range(0.0, 1.0, 0.05) var summon_at_fraction := 0.5
## Below this health fraction it enrages: faster and attacks more often.
@export_range(0.0, 1.0, 0.05) var enrage_fraction := 0.0
@export var is_boss := false

@export_group("Rewards")
@export_range(0, 1000) var score_value := 10
@export_range(0, 1000) var xp := 20
@export_range(0, 100) var sabotage_points := 1
## Chance (0-1) to drop loot from the loot table.
@export_range(0.0, 1.0, 0.01) var loot_chance := 0.3


func has_melee() -> bool:
	return melee_damage > 0.0


func has_spit() -> bool:
	return spit != null


func has_slam() -> bool:
	return slam_damage > 0.0


func has_charge() -> bool:
	return charge_damage > 0.0
