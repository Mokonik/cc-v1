class_name Projectile
extends RefCounted
## A projectile in flight. Plain data (no nodes) so it can be simulated on the authority
## and replicated later; presentation draws it from this state.

var id := 0
var def: WeaponDef
var owner_id := 0
var position := Vector3.ZERO
## Where it was launched from; used to measure how far a shot travelled.
var origin := Vector3.ZERO
var velocity := Vector3.ZERO
var spawn_tick := 0
## Draw strength (0-1). Scales an arrow's damage and speed; always 1 for abilities.
var power := 1.0
## Resolved at launch so later tier or perk changes never alter a shot already in flight.
var damage := 0.0
var splash_radius := 0.0
var splash_damage := 0.0
## Physics mask this projectile collides with (see CombatLayers).
var mask := CombatLayers.PLAYER_SHOTS
