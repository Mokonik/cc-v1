# PvPvE Loop Arena (Godot 4.4)

3D first-person online PvPvE game: long PvE prep phase, then a PvP match that changes the next PvE phase, looping until a final match. See the project plan for the full design.

**Status:** M0 (scaffold), M1 (first-person feel), M2 (solo foundation with bot rivals), M3 (combat) and M4 (PvE) are done. The match loop that ties PvE and PvP together is next (M5). Multiplayer is deliberately last (M8); until then everything is built and tested solo against bots, dummies and monsters.

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
| F | Drink a health pack |
| G | Place a trap at your feet |
| Z, X, C | Pick perk 1, 2 or 3 when you level up |
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

## PvE
Type `pve start` in the console (`pve start 60` for a 60 s phase) to enter your private PvE zone. Every player gets their own copy of the zone, built far from everyone else's, so what happens in yours never touches anyone else. The phase runs: 5 s countdown, waves of monsters coming through eight glowing gates every 20 s until the timer ends, then the boss. It ends when the boss dies, its 150 s limit runs out, or you `pve stop`; you are returned to where you started and see a results screen. If you die you respawn in the zone.

| Monster | Behavior |
|---|---|
| Grunt (60 hp) | Walks at you and claws. First wave onward |
| Spitter (40 hp) | Keeps its distance, circles, and spits slow projectiles. From wave 2 |
| Brute (160 hp) | Slow; slams everything close, or telegraphs a straight-line charge and staggers itself if it hits a wall. From wave 4 |
| Warden (boss, 900 hp) | Slam, three-orb volley and charge; summons four grunts at half health and enrages (faster, shorter windups) under 35% |

Every attack glows or shows a ground marker first. `difficulty <x>` (0.25-4) scales monster count (directly), health and damage (more gently), and the score; the alive cap is 20.

**Loot and progression.** Monsters drop loot by a seeded table. Weapon drops unlock the sword, bow and orb; a duplicate raises that weapon's tier (to 3: +25% damage and 10% faster per tier). Health packs (F, +35) and traps (G; arm after 1 s, then hit the first non-owner player, bot or dummy within 1.5 m for 30 damage and a 40% slow; monsters never set them off) are stored, up to 3 each. Kills give XP (levels cost 100 + 50 per level), and each level offers three seeded perks to pick one from with Z, X or C; perks last the whole run. Kills also earn **Sabotage Points**, which are only displayed for now: they are spent in M6.

Perks: Vitality, Swiftness, Marksman, Berserker, Quick Hands, Pyromancer, Iron Skin, Second Wind, Scavenger (`perk list` shows what each does). Loot and consumables are meant to reset every cycle (M5 will call `LootSystem.reset_loot`); perks persist.

**Bots' PvE** is simulated, not played: `botpve [0-2]` runs the stat model (`BotPveModel`) for a bot and gives it the result exactly as a human would earn it, through the same scoring formula, XP, level-ups and perk choices. It faces the same wave schedule as a human; better skill and easier difficulty mean more kills, fewer deaths and a better chance at the boss. It is a stand-in for a friend, validated for consistency (monotonic in skill and difficulty, seeded), not for realism.

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
| `monster <grunt\|spitter\|brute\|warden> [n]`, `monster clear` | Spawn monsters ahead of you in the sandbox (up to 12 per command) |
| `pve start [seconds]`, `pve stop`, `pve skip`, `pve status` | Run, end, fast-forward to the boss, or inspect your PvE phase |
| `difficulty [x]` | PvE difficulty for new phases |
| `loot <sword\|bow\|orb\|pistol\|health\|trap\|xp>` | Drop a pickup at your feet |
| `xp <n>`, `perk list`, `perk give <id>`, `sp <n>`, `heal` | Progression helpers |
| `botpve [0-2] [bot id]` | Simulate a bot's PvE phase and show the result |
| `fov <60-110>`, `sens <value>` | Player settings |

Bots path around cover with a baked navmesh and circle-strafe at their engage distance; they chase you but do not attack until M5. More console commands (monsters, points, phases) arrive with those systems.

## Content
Weapons, monsters, perks and loot are data. Monsters, perks and the loot table are generated from the tables in `tools/make_content.py` (the single place to read and tune the numbers; re-run it after editing, or tune the `.tres` files in the inspector instead). New monsters are a new `MonsterDef`: its abilities switch on by their numbers, so a monster with `spit` set spits and one with `charge_damage` charges, with no AI code. Waves are paced by `content/pve_config.tres`.

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
`tools/run_tests.sh` imports the project and runs every `tests/*.gd` headless: movement math, jump buffer and coyote time, settings, arena and navmesh, player registry, spawning limits, dev commands, bot pathing and determinism, every weapon type (damage, timing, spread, walls, arcs, gravity, splash), death, respawn and protection, weapon switching, input mapping, deterministic fights, monster brains (every attack's timing, kiting, charge and stun, boss phases) and real monster fights, private zones, the run director (phases, wave scaling, caps, spawn rules, boss, results, scoring), loot, traps, health packs, XP, perks, Sabotage Points, the bot model, and the architecture rules. They run with `--fixed-fps` so they finish in under a minute while staying identical to a real-time run. `tools/godot.sh` runs Godot with a local binary, or the `/opt/godot-root` chroot in the cloud dev container.

`tools/screenshot.gd` renders the main scene to a PNG, and `tools/combat_shots.gd` plays a scripted fight and saves a screenshot of each weapon in action, and `tools/pve_shots.gd` does the same for a PvE phase (zone, telegraph, loot, perk offer, boss, results). Both need a display (or Xvfb with software GL) and are for checking visuals without opening the editor.
