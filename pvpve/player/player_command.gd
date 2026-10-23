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
## Primary action (shoot, swing, draw, cast). Bots set fire_held as an intent signal.
var fire_pressed := false
var fire_held := false
var fire_released := false
var reload_pressed := false
## 1-4 selects that weapon slot; 0 means no change.
var weapon_slot := 0
## +1 / -1 cycles to the next / previous owned weapon; 0 means no change.
var weapon_cycle := 0
## Use a health pack.
var use_item := false
## Place a trap at your feet.
var place_trap := false
## 1-3 picks that perk from your oldest pending level-up offer; 0 means no pick.
var perk_pick := 0
