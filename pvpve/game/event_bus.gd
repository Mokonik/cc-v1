class_name EventBus
extends RefCounted
## Signal bus for presentation. Gameplay state changes happen in the authority layer
## (Game, CombatSystem and friends); UI, audio and effects listen here and never mutate
## state. Owned by Game and injected where needed, so there are no globals and every
## Game instance (a test, a headless server) has its own.

signal player_spawned(player_id: int)
signal player_removed(player_id: int)
## True while a UI element (such as the dev console) wants the mouse and keyboard.
signal ui_capture_changed(ui_has_focus: bool)

# Combat. Positions are world-space; ids are player ids and weapon ids.
signal weapon_given(player_id: int, weapon_id: StringName)
signal weapon_changed(player_id: int, weapon_id: StringName)
## A hitscan shot or an instant cast. end_point is where the ray stopped.
signal weapon_fired(player_id: int, weapon_id: StringName, origin: Vector3, direction: Vector3, end_point: Vector3)
signal reload_started(player_id: int, weapon_id: StringName, duration: float)
signal reload_finished(player_id: int, weapon_id: StringName)
signal draw_started(player_id: int, weapon_id: StringName, duration: float)
signal melee_swing(player_id: int, weapon_id: StringName)
signal projectile_spawned(projectile_id: int, weapon_id: StringName, position: Vector3, velocity: Vector3)
## hit_player_id is 0 when the projectile hit the world or expired.
signal projectile_ended(projectile_id: int, position: Vector3, hit_player_id: int)
signal explosion(position: Vector3, radius: float, weapon_id: StringName)
signal damage_dealt(target_id: int, source_id: int, amount: float, position: Vector3, weapon_id: StringName)
signal player_died(victim_id: int, killer_id: int, weapon_id: StringName)
signal player_respawned(player_id: int)
