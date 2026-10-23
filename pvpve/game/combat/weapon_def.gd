class_name WeaponDef
extends Resource
## Everything that defines one weapon. Weapons are data: add a .tres under
## content/weapons/ and list it in WeaponCatalog; no combat code changes.

enum Kind { HITSCAN, MELEE, PROJECTILE, ABILITY }

@export var id: StringName = &"pistol"
@export var display_name := "Pistol"
@export var kind: Kind = Kind.HITSCAN
## Number key that selects this weapon.
@export_range(1, 4) var slot := 1

@export_group("Damage")
@export_range(1.0, 200.0, 0.5) var damage := 8.0
## Minimum seconds between the starts of two uses. For abilities this is the cooldown.
@export_range(0.05, 20.0, 0.05) var fire_interval := 0.25
## Hitscan range or melee reach, in meters.
@export_range(1.0, 200.0, 0.5) var reach := 80.0
## Half-angle of the random cone for hitscan shots, in degrees.
@export_range(0.0, 10.0, 0.1) var spread_deg := 0.6

@export_group("Ammo")
## Rounds per magazine. 0 means the weapon does not use ammo.
@export_range(0, 100) var magazine := 15
@export_range(0.1, 5.0, 0.05) var reload_time := 1.3

@export_group("Melee")
## Seconds from starting a swing until it can hit.
@export_range(0.0, 1.0, 0.01) var windup := 0.25
@export_range(10.0, 360.0, 5.0) var arc_deg := 110.0

@export_group("Projectile")
@export_range(1.0, 100.0, 0.5) var projectile_speed := 40.0
@export_range(0.0, 40.0, 0.5) var projectile_gravity := 0.0
@export_range(0.5, 10.0, 0.1) var projectile_lifetime := 4.0
## Seconds the button must be held for a full-power shot (0 fires instantly).
@export_range(0.0, 3.0, 0.05) var draw_time := 0.0
## Power of the weakest shot (released immediately), as a fraction of full power.
@export_range(0.0, 1.0, 0.05) var min_power := 0.35
@export_range(0.0, 10.0, 0.1) var splash_radius := 0.0
## Splash damage at the center of an explosion; it falls off to 25% at the edge.
@export_range(0.0, 200.0, 0.5) var splash_damage := 0.0

@export_group("Feel")
## Camera kick per use, in degrees. Visual only; it never changes where shots go.
@export_range(0.0, 10.0, 0.05) var recoil_pitch_deg := 1.0
@export_range(0.0, 5.0, 0.05) var recoil_yaw_deg := 0.3
## How far the viewmodel is pushed back per use, in meters.
@export_range(0.0, 0.5, 0.01) var viewmodel_kick := 0.06


static func seconds_to_ticks(seconds: float) -> int:
	return roundi(seconds * Engine.physics_ticks_per_second)


func uses_ammo() -> bool:
	return magazine > 0


## Delay between pressing fire and the first damage being possible.
func first_hit_delay() -> float:
	match kind:
		Kind.MELEE:
			return windup
		Kind.PROJECTILE:
			return draw_time
	return 0.0


## Time to kill a target with perfect aim, ignoring reloads and travel time.
func ttk(hp: float) -> float:
	var hits := ceili(hp / damage)
	return first_hit_delay() + (hits - 1) * fire_interval
