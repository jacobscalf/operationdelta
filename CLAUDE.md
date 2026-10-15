# Operation: Delta

A SOCOM II-inspired tactical third-person multiplayer shooter (spiritual successor — all
names, maps and assets must be original; never use Sony/SOCOM IP).

- Engine: Godot 4.7.2 (standard, GDScript). Executable: `J:\Godot_v4.7.2-stable_win64.exe\`
  (it's a folder; use `Godot_v4.7.2-stable_win64_console.exe` inside it for CLI runs).
- The developer is a beginner working solo with Claude; Claude writes the code and explains
  steps plainly. Prefer building nodes in code / plain-text scenes so Claude can edit everything.

## Running the game
- The developer plays by double-clicking `Play Operation Delta.bat`.
- Do NOT launch the game for the developer from Claude (Start-Process etc.): Windows denies the
  window real focus, so mouse look and keys silently fail. Claude may still run it itself for
  automated checks (`--headless`, or `--script` test scripts that save screenshots).

## Layout
- `scenes/main.tscn` – entry scene; `scripts/main.gd` builds the gray-box map "Range 01".
- `scripts/player.gd` – movement, stances (stand/crouch/prone), camera, hitscan rifle, spread.
- `scripts/hud.gd` – crosshair (gap = spread cone), ammo, stance, hit markers.
- `scripts/target_dummy.gd` – practice targets (`take_hit(damage, point) -> bool killed`).
- `scripts/input_setup.gd` – autoload that registers all input actions in code.

## Roadmap
1. ✅ Core feel (single player, gray box)
2. LAN multiplayer: host/join, synced players (Godot high-level multiplayer)
3. Rounds: two teams, one life per round, timer (Suppression)
4. Real art, sound, lighting polish (licensed assets only)
5. Internet play: dedicated server, server browser, voice chat

## Known TODO
- Bullets trace from the camera; they should also check the muzzle line so cover in front
  of the gun blocks shots.
