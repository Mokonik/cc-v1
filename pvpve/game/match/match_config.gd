class_name MatchConfig
extends Resource
## Every number that shapes a match: how long it runs, how points are scored, how the twist
## and the wager work, and what the final looks like. All of it is data, so balance is changed
## in the inspector (or live from the console) and never in code.

enum ModifierScope { EVERYONE, OPPONENTS }

@export_group("Length")
## PvE and PvP cycles before the final: 3 for testing, 5 for a long game.
@export_range(1, 8) var cycles := 3
@export_range(20.0, 1200.0, 5.0) var pve_seconds := 240.0
@export_range(1.0, 60.0, 1.0) var pve_results_seconds := 15.0
@export_range(1.0, 60.0, 1.0) var wager_seconds := 15.0
@export_range(3.0, 30.0, 1.0) var pvp_countdown_seconds := 5.0
@export_range(15.0, 600.0, 5.0) var pvp_seconds := 120.0
@export_range(1.0, 60.0, 1.0) var pvp_results_seconds := 20.0
@export_range(15.0, 600.0, 5.0) var final_seconds := 150.0
@export_range(1.0, 60.0, 1.0) var victory_seconds := 30.0

@export_group("PvP points")
@export_range(0, 100) var kill_points := 10
## Extra points for killing whoever wears the mark.
@export_range(0, 200) var leader_bounty := 25
## Extra points for a skill kill (sword, long full-power arrow, airborne victim).
@export_range(0, 200) var skill_bonus := 25
## Share of the victim's PvP points that a skill kill steals.
@export_range(0.0, 1.0, 0.05) var skill_steal_fraction := 0.5
## A full-power arrow counts as a skill kill from at least this far away.
@export_range(5.0, 60.0, 1.0) var skill_min_arrow_distance := 18.0

@export_group("Showstopper (skill kill on the marked leader)")
## Share of the victim's total standings that is taken, up to the cap below.
@export_range(0.0, 1.0, 0.01) var showstopper_standings_fraction := 0.15
@export_range(0, 1000) var showstopper_standings_cap := 150
## Share of what was taken that the killer receives.
@export_range(0.0, 1.0, 0.05) var showstopper_killer_share := 0.5

@export_group("Wager")
## Stakes offered before each PvP match, as a share of your standings total (keys Z, X, C).
@export var stake_options: PackedFloat32Array = PackedFloat32Array([0.0, 0.25, 0.5])

@export_group("Mark")
## Added to the PvE difficulty of whoever leads the standings.
@export_range(0.0, 2.0, 0.05) var leader_difficulty_bonus := 0.35

@export_group("Modifiers")
@export var modifier_scope: ModifierScope = ModifierScope.EVERYONE

@export_group("Final")
## Points for placing 1st, 2nd, 3rd and 4th in the final.
@export var final_points: PackedInt32Array = PackedInt32Array([400, 200, 100, 0])
## The safe area starts shrinking after this share of the final has passed.
@export_range(0.0, 0.9, 0.05) var shrink_start_fraction := 0.25
## Radius of the safe area at the end, in meters.
@export_range(2.0, 30.0, 0.5) var shrink_end_radius := 6.0
## Damage per second outside the safe area, rising the longer a player stays out.
@export_range(1.0, 50.0, 0.5) var storm_damage := 6.0
@export_range(0.0, 3.0, 0.1) var storm_escalation := 0.5


func stake_for(total: int, option_index: int) -> int:
	return WagerRules.stake_amount(total, option_index, stake_options)
