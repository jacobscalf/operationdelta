# Operation: Delta

A SOCOM II-inspired tactical third-person multiplayer shooter (spiritual successor — all
names, maps and assets must be original; never use Sony/SOCOM IP).

- Engine: Godot 4.7.2 (standard, GDScript). Executable: `J:\Godot_v4.7.2-stable_win64.exe\`
  (it's a folder; use `Godot_v4.7.2-stable_win64_console.exe` inside it for CLI runs).
- The developer is a beginner working solo with Claude; Claude writes the code and explains
  steps plainly. Prefer building nodes in code / plain-text scenes so Claude can edit everything.

## Version control
- GitHub: https://github.com/jacobscalf/operationdelta (private). Commit each finished
  feature and `git push` right after, so GitHub always has the latest working version.

## Running the game
- The developer plays by double-clicking `Play Operation Delta.bat`.
- Do NOT launch the game for the developer from Claude (Start-Process etc.): Windows denies the
  window real focus, so mouse look and keys silently fail. Claude may still run it itself for
  automated checks (`--headless`, or `--script` test scripts that save screenshots).

## Layout
- `scenes/menu.tscn` + `scripts/menu.gd` – entry scene: name, Practice / Host / Join.
  Test shortcuts: launch with `-- --host` or `-- --join=127.0.0.1`.
- `scenes/main.tscn` + `scripts/main.gd` – the match: builds map "Range 01", opens the
  connection, spawns players via a MultiplayerSpawner (custom spawn_function), spawn points.
- `scripts/network.gd` – autoload `Network`: mode, name, ENet host/join on port 7777, leave().
- `scripts/player.gd` – one per player on every machine. Owner has authority over
  movement/aim/stance (MultiplayerSynchronizer); host decides hits (`_server_fire` traces
  camera ray then shoulder ray), health, death, respawn via RPCs.
- `scripts/match.gd` – node "Match" under Main: host-run referee. Teams OPS (0, south) vs
  TERRORISTS (1, north). LOBBY (pick side, green up) -> STARTING (10 s, all green) ->
  COUNTDOWN (5 s frozen) -> LIVE (one life) -> ROUND_OVER -> ... -> MATCH_OVER -> LOBBY.
  Settings from menu: friendly fire, rounds to win, round minutes.
- `scripts/lobby_panel.gd` – lobby screen shown by the HUD (team columns, Join, GREEN UP).
- `scripts/bot_brain.gd` – host-only AI for bots. A bot is a normal player node with
  `is_bot = true`, id 1000+, authority 1. main.gd adds one when the host is alone in the
  lobby for 15 s and removes bots when a person joins the lobby. Bots fire via `fire_bullet`.
- `scripts/hud.gd` – crosshair, ammo, health, score/timer/banner, mini map (top-down
  SubViewport render in main.gd; players/effects on visual layer 2 so they're excluded),
  kill feed, death screen, pause menu.
- `scripts/target_dummy.gd` – practice-only targets (`take_hit(damage, point, attacker_id)`).
- `scripts/input_setup.gd` – autoload that registers all input actions in code.
- `scripts/soldier_model.gd` – the visible soldier: Mixamo model (Ops = Swat Guy,
  Terrorists = Heraklios) + AnimationTree built in code (stand/crouch BlendSpace2D, prone
  BlendSpace1D, jump, upper-body reload OneShot, death transitions). Driven by
  `player._update_model()` from measured movement, so it works for remote players and bots.
- `scripts/aim_modifier.gd` – SkeletonModifier3D: bends the spine with aim pitch and places
  the rifle from the right hand toward the left hand each frame.
- `tools/build_characters.gd` – rebuilds `assets/characters/*.scn` + `soldier_anims.res`
  from the raw Mixamo FBX files in `assets/characters/source/` (git-ignored; re-download
  from Mixamo if missing). Textures are shrunk to 1024 px, S3TC-compressed.
- `scripts/sfx.gd` – autoload `Sfx`: `play_3d(name, pos, db, unit_size)` / `play_ui(name, db)`.
  Sounds live in `assets/audio/` (all CC0, see `assets/audio/CREDITS.md`). Ops fire M4
  sounds, Terrorists AK; far shots (>45 m) use the distant recordings. Footsteps come from
  each soldier's actual movement (quieter crouched/prone).

## Roadmap
1. ✅ Core feel (single player, gray box)
2. ✅ LAN multiplayer: host/join, synced players (Godot high-level multiplayer)
3. ✅ Rounds: two teams, one life per round, timer, mini map, friendly-fire setting
4. Real art, sound, lighting polish (licensed assets only)
5. Internet play: dedicated server, server browser, voice chat
