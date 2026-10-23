class_name CombatLayers
extends RefCounted
## Physics layers and the masks used by shots. Players and monsters are on separate layers so
## monster projectiles can pass through other monsters while player shots hit both.

const WORLD := 1
const PLAYER := 2
const MONSTER := 4
## What a player's hitscan, melee line-of-sight and projectiles can hit.
const PLAYER_SHOTS := WORLD | PLAYER | MONSTER
## What a monster's projectiles can hit: never other monsters.
const MONSTER_SHOTS := WORLD | PLAYER
