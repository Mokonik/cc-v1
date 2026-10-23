# PvPvE Loop Arena (Godot 4.4)

3D first-person online PvPvE game: long PvE prep phase, then a PvP match that changes the next PvE phase, looping until a final match. See the project plan for the full design.

**Status:** M0 (scaffold), M1 (first-person feel) and M2 (solo-first foundation with bot rivals) are done. Combat is next (M3). Multiplayer is deliberately last (M8); until then everything is built and tested solo against bots.

## Run
Open `pvpve/` in Godot 4.4+ and press F5. Use the same engine build as your friends.

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Space | Jump (hold for full height) |
| Shift | Sprint (forward only) |
| `[` / `]` | Mouse sensitivity down / up (saved) |
| F3 | Toggle debug readout |
| ` (backtick) | Dev console |
| Esc | Release / recapture mouse |

## Solo mode: bots and the dev console
The game starts with you plus one bot standing in for a friend. Press `` ` `` for the dev console:

| Command | What it does |
|---|---|
| `bot [0-2]` | Spawn a bot (0 rookie, 1 regular, 2 veteran); up to 3 bots |
| `bot clear` | Remove all bots |
| `players` | List who is in the match |
| `tp <x> <z>` | Teleport yourself |
| `timescale <0.05-4>` | Slow down or speed up time |
| `seed <n>` | Match seed (bots spawned afterwards use it; same seed = same behavior) |
| `fov <60-110>`, `sens <value>` | Player settings |

Bots path around cover with a baked navmesh, circle-strafe at their engage distance, and flag when they would fire (combat arrives in M3). More console commands (monsters, points, phases) arrive with those systems.

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
`tools/run_tests.sh` imports the project and runs every `tests/*.gd` headless: movement math, jump buffer and coyote time, settings, arena and navmesh, player registry, spawning limits, dev commands, bot pathing and determinism, and the architecture rules. `tools/godot.sh` runs Godot with a local binary, or the `/opt/godot-root` chroot in the cloud dev container.

`tools/screenshot.gd` renders the main scene to a PNG on a machine with a display (or Xvfb with software GL), optionally with bots running or the console open, for checking visuals without opening the editor.
