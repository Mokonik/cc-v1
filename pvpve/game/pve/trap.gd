class_name Trap
extends RefCounted
## A trap placed on the ground. Plain data. It arms a moment after being placed, then goes
## off on the first player, bot or dummy (never its owner, never a monster) that steps close.

var id := 0
var owner_id := 0
var position := Vector3.ZERO
var arm_tick := 0
