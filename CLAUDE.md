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
  TERRORISTS (1, north), warm-up -> countdown (frozen) -> live (one life) -> round over ->
  match over. Settings from menu: friendly fire, rounds to win, round minutes.
- `scripts/hud.gd` – crosshair, ammo, health, score/timer/banner, mini map (top-down
  SubViewport render in main.gd; players/effects on visual layer 2 so they're excluded),
  kill feed, death screen, pause menu.
- `scripts/target_dummy.gd` – practice-only targets (`take_hit(damage, point, attacker_id)`).
- `scripts/input_setup.gd` – autoload that registers all input actions in code.

## Roadmap
1. ✅ Core feel (single player, gray box)
2. ✅ LAN multiplayer: host/join, synced players (Godot high-level multiplayer)
3. ✅ Rounds: two teams, one life per round, timer, mini map, friendly-fire setting
4. Real art, sound, lighting polish (licensed assets only)
5. Internet play: dedicated server, server browser, voice chat
