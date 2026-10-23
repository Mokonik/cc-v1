# PvPvE Loop Arena (Godot 4.4)

3D first-person online PvPvE game: long PvE prep phase, then a PvP match that changes the next PvE phase, looping until a final match. See the project plan for the full design.

**Status:** M0 (scaffold) and M1 (first-person feel, gray-box arena) are done. Networking starts in M2.

## Run
Open `pvpve/` in Godot 4.4+ and press F5. Use the same engine build as your friends.

| Input | Action |
|---|---|
| WASD / arrows | Move |
| Space | Jump (hold for full height) |
| Shift | Sprint (forward only) |
| `[` / `]` | Mouse sensitivity down / up (saved) |
| F3 | Toggle debug readout |
| Esc | Release / recapture mouse |

## Tuning feel
Everything is in `player/default_movement.tres` (a `MovementConfig`): speeds, acceleration, friction, air control, gravity, jump height, coyote time, jump buffer, head bob, FOV kick, strafe tilt, landing dip, look smoothing. Select the resource in the FileSystem dock and edit it in the inspector; changes apply on the next run. Mouse sensitivity and FOV are player settings (`player/player_settings.gd`, stored in `user://settings.cfg`).

The arena (`world/graybox_arena.gd`) has a run lane with 5 m markers, a tower of 1.1 m steps, a 20 degree ramp, pillars and cover. Known gap: there is no automatic step-up, so anything taller than a few centimeters must be jumped or climbed via the ramp.

## Tests
`tools/run_tests.sh` imports the project and runs every `tests/*.gd` headless (movement math, jump buffer, coyote time, settings, arena, main scene). `tools/godot.sh` runs Godot with a local binary, or the `/opt/godot-root` chroot in the cloud dev container.

`tools/screenshot.gd` renders the main scene to a PNG on a machine with a display (or Xvfb with software GL), for checking visuals without opening the editor.
