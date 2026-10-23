class_name PlayerCommand
extends RefCounted
## One tick of player intent, produced by an InputSource (keyboard and mouse, a bot,
## and later the network). The Player only ever consumes commands, never raw input.

## x = right, y = back (so forward is -1), the same convention as Input.get_vector.
var move := Vector2.ZERO
var jump_pressed := false
var jump_held := false
var sprint := false
## Absolute view angles in radians (yaw 0 faces -Z, positive pitch looks up).
var yaw := 0.0
var pitch := 0.0
## Unused until combat lands in M3; bots already set it so their aiming is testable.
var fire_held := false
