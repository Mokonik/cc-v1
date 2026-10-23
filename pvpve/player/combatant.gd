class_name Combatant
extends CharacterBody3D
## Anything CombatSystem can hurt and kill: a Player or a Monster. The system finds bodies by
## entity id (players 1-4, monsters from 1000) and never needs to know which kind it has.

var entity_id := 0
var display_name := ""
var alive := true


## Where this combatant's view or aim originates.
func eye_position() -> Vector3:
	return global_position + Vector3(0.0, 1.6, 0.0)


## Roughly the middle of the torso: where melee swings and projectiles aim.
func chest_position() -> Vector3:
	return global_position + Vector3(0.0, 1.0, 0.0)


## The center of the body, used to measure distance for explosions.
func center_position() -> Vector3:
	return global_position + Vector3(0.0, 0.9, 0.0)


func body_radius() -> float:
	return 0.4


func set_alive(value: bool) -> void:
	alive = value


## Spawn protection flag (a visual cue; the rule lives in CombatSystem).
func set_protected(_value: bool) -> void:
	pass


## Moves the combatant back into play with a clean slate.
func respawn_at(position: Vector3, _yaw: float) -> void:
	global_position = position
	velocity = Vector3.ZERO
	set_alive(true)
