# PvPvE Loop Arena (Godot 4.4)

3D first-person online PvPvE game: long PvE prep phase, then a PvP match that changes the next PvE phase, looping until a final match. See the project plan for the full design.

**Status:** M0 (scaffold), M1 (first-person feel), M2 (solo foundation with bot rivals) and M3 (combat) are done. PvE monsters are next (M4). Multiplayer is deliberately last (M8); until then everything is built and tested solo against bots and dummies.

## Run
Open `pvpve/` in Godot 4.4+ and press F5. Use the same engine build as your friends.

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Space | Jump (hold for full height) |
| Shift | Sprint (forward only) |
| `[` / `]` | Mouse sensitivity down / up (saved) |
| Left mouse | Fire / swing / draw and loose / cast |
| R | Reload |
| 1-4, mouse wheel, Q | Select weapon (only ones you own) |
| F3 | Toggle debug readout |
| ` (backtick) | Dev console |
| Esc | Release / recapture mouse |

## Combat
You start with only the **pistol**. The other three weapon types exist already and are handed out with the console (`give all`) until loot arrives in M4.

| Slot | Weapon | How it works |
|---|---|---|
| 1 | Pistol | Hitscan, 8 damage, 4 shots/s, 15-round magazine, 1.3 s reload, slight random spread |
| 2 | Sword | Melee: short windup, then an arc sweep that hits everyone in reach and in front, 20 damage |
| 3 | Bow | Hold to draw (0.7 s for full power), release to loose an arrow; damage and speed scale with the draw, arrows drop under gravity |
| 4 | Fire Orb | Ability: a slow orb that explodes on impact, 35 direct plus distance-scaled splash, 6 s cooldown, never hurts you |

Fights are deliberately slow: 100 health, and the pistol needs 3 s of perfect aim to kill. Dying shows a death camera and respawns you after 3 s at the spawn farthest from the others, with 2 s of spawn protection. Bots and dummies can be hurt and respawn too; bots do not shoot back yet.

All numbers live in `content/weapons/*.tres` (see `WeaponDef` for every field, including recoil and viewmodel kick), so retuning needs no code. `ttk` in the console prints each weapon's ideal time to kill.

Combat is authoritative and tick-based (`game/combat/`): `CombatSystem` is the only code that changes health, ammo and cooldowns, projectiles are plain data in `ProjectileSystem`, and spread is a stateless function of the seed, so a fight is reproducible and ready to replicate in M8. Everything you see and hear (`fx/`, `ui/combat_hud.gd`) listens to events only. Sound effects are synthesized placeholders (`tools/make_sfx.py`).

## Solo mode: bots, dummies and the dev console
The game starts with you plus one bot standing in for a friend. Press `` ` `` for the dev console:

| Command | What it does |
|---|---|
| `bot [0-2]` | Spawn a bot (0 rookie, 1 regular, 2 veteran); up to 3 bots |
| `bot clear` | Remove all bots |
| `players` | List who is in the match |
| `tp <x> <z>` | Teleport yourself |
| `timescale <0.05-4>` | Slow down or speed up time |
| `seed <n>` | Match seed (bots spawned afterwards use it; same seed = same behavior) |
| `give <pistol\|sword\|bow\|orb\|all>`, `weapons` | Hand yourself weapons, list what you have |
| `dummy [stand\|strafe]`, `dummy clear` | Spawn or remove target dummies (max 6) |
| `hp <n>`, `god`, `respawn` | Set health, toggle invulnerability, come back from the dead |
| `kill <id>`, `damage <id> <n>` | Kill or hurt anyone (ids from `players`) |
| `ttk` | Ideal time to kill for each weapon |
| `fov <60-110>`, `sens <value>` | Player settings |

Bots path around cover with a baked navmesh and circle-strafe at their engage distance; they chase you but do not attack until M5. More console commands (monsters, points, phases) arrive with those systems.

## Architecture rules
Written so multiplayer can be added last without a rewrite; `tests/test_architecture.gd` enforces the checkable ones.
1. Gameplay state lives in the authority layer (`game/`) and changes only through its methods.
2. Players are driven by `PlayerCommand`s from an `InputSource` (`LocalInputSource`, `BotInputSource`; a network source later). Only `LocalInputSource` and UI may read `Input`.
3. Players and entities refer to each other by id, not node paths.
4. Presentation listens to `EventBus` (owned by `Game`, injected, no globals).
5. Fixed tick and seeded RNG, so headless bot-only matches are reproducible.
6. Content (weapons, monsters, perks, modifiers) will be `Resource` files.

## Tuning feel
Everything is in `player/default_movement.tres` (a `MovementConfig`): speeds, acceleration, friction, air control, gravity, jump height, coyote time, jump buffer, head bob, FOV kick, strafe tilt, landing dip, look smoothing. Select the resource in the FileSystem dock and edit it in the inspector; changes apply on the next run. Mouse sensitivity and FOV are player settings (`player/player_settings.gd`, stored in `user://settings.cfg`).

The arena (`world/graybox_arena.gd`) has a run lane with 5 m markers, a tower of 1.1 m steps, a 20 degree ramp, pillars and cover. Known gap: there is no automatic step-up, so anything taller than a few centimeters must be jumped or climbed via the ramp.

## Tests
`tools/run_tests.sh` imports the project and runs every `tests/*.gd` headless: movement math, jump buffer and coyote time, settings, arena and navmesh, player registry, spawning limits, dev commands, bot pathing and determinism, every weapon type (damage, timing, spread, walls, arcs, gravity, splash), death, respawn and protection, weapon switching, input mapping, deterministic fights, and the architecture rules. `tools/godot.sh` runs Godot with a local binary, or the `/opt/godot-root` chroot in the cloud dev container.

`tools/screenshot.gd` renders the main scene to a PNG, and `tools/combat_shots.gd` plays a scripted fight and saves a screenshot of each weapon in action. Both need a display (or Xvfb with software GL) and are for checking visuals without opening the editor.
