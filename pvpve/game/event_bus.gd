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
## Raw facts about how a player died, for scoring rules. distance is killer-to-victim in meters,
## airborne is whether the victim was off the ground, full_power is a fully drawn arrow, direct
## is false for splash damage. killer_id is 0 for environmental deaths.
signal kill_detail(victim_id: int, killer_id: int, weapon_id: StringName, distance: float, airborne: bool, full_power: bool, direct: bool)
signal monster_killed(monster_id: int, killer_id: int, position: Vector3, def_id: StringName)
signal monster_exploded(monster_id: int, position: Vector3, radius: float)
signal weapon_tier_changed(player_id: int, weapon_id: StringName, tier: int)
signal monster_spawned(monster_id: int, def_id: StringName, position: Vector3)
## A monster started winding up an attack ("melee", "spit", "slam" or "charge").
signal monster_telegraph(monster_id: int, ability: StringName, seconds: float)
## An attack landed or fired. radius is the area it covers (0 for single-target attacks).
signal monster_attack(monster_id: int, ability: StringName, position: Vector3, radius: float)

# PvE phase (one run per participant).
signal pve_started(owner_id: int, phase_seconds: float)
## phase_name is "countdown", "waves" or "boss"; seconds is how long it lasts.
signal pve_phase(owner_id: int, phase_name: StringName, seconds: float)
signal pve_wave(owner_id: int, wave: int, count: int)
signal pve_finished(owner_id: int, result: PveResult, reason: StringName)
## A gate is about to release a monster; presentation makes it glow.
signal gate_pulse(owner_id: int, gate_index: int, seconds: float)

# Progression.
signal xp_changed(player_id: int, xp: int, level: int)
signal level_up(player_id: int, level: int)
## A level-up queued three perks to choose from.
signal perk_offered(player_id: int, perk_ids: Array)
signal perk_picked(player_id: int, perk_id: StringName)
signal sabotage_points_changed(player_id: int, points: int)

# Loot, consumables and traps.
signal loot_dropped(drop_id: int, kind: int, label: String, position: Vector3)
signal loot_picked_up(player_id: int, drop_id: int, kind: int, label: String)
signal loot_removed(drop_id: int)
signal item_used(player_id: int, item: StringName, amount: float)
signal trap_placed(trap_id: int, owner_id: int, position: Vector3)
signal trap_armed(trap_id: int)
signal trap_triggered(trap_id: int, victim_id: int, position: Vector3)

# Match loop.
## phase is one of lobby, pve, pve_results, wager, pvp_countdown, pvp, pvp_results, final, victory.
signal match_started(cycles: int)
signal match_phase(phase: StringName, cycle: int, seconds: float)
signal match_finished(champion_id: int)
signal standings_changed
## kill_class is PvpRules.KillClass (0 normal, 1 skill, 2 showstopper).
signal pvp_kill_scored(killer_id: int, victim_id: int, kill_class: int, killer_gain: int, victim_loss: int)
signal mark_changed(player_id: int)
signal wager_set(player_id: int, stake: int)
signal wager_settled(net_changes: Dictionary)
signal modifier_offered(picker_id: int, modifier_ids: Array)
signal modifier_chosen(picker_id: int, modifier_id: StringName)
signal final_zone(radius: float, center: Vector3)
