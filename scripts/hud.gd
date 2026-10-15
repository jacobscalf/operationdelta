extends CanvasLayer
## On-screen display: crosshair, ammo, health, stance, hit markers, kill feed,
## death screen and the pause screen. Most of it is drawn by hand on one full-screen Control.

const CROSSHAIR_COLOR := Color(0.55, 1.0, 0.55, 0.9)
const TEXT_COLOR := Color(0.92, 0.92, 0.88)
const HELP_TEXT := "WASD move   Shift sprint   Space jump   C crouch   Z prone   RMB aim   LMB fire   R reload   Q swap shoulder   Esc pause"
const FEED_TIME := 6.0  # seconds a kill-feed line stays up
const FEED_LINES := 5
const MatchScript := preload("res://scripts/match.gd")
const LobbyPanelScript := preload("res://scripts/lobby_panel.gd")
const MINIMAP_SIZE := 200.0
const MINIMAP_MARGIN := 20.0
const ENEMY_REVEAL_MSEC := 1500  # enemies show on the mini map this long after they fire
const TEAMMATE_DOT := Color(0.4, 0.75, 1.0)
const ENEMY_DOT := Color(1.0, 0.3, 0.25)

var _canvas := Control.new()
var _pause_screen := Control.new()
var _lobby_panel: LobbyPanelScript
var _match: MatchScript
var _was_in_lobby := false
var _spread_px := 10.0
var _ammo := 0
var _reserve := 0
var _health := 100.0
var _stance_name := ""
var _reloading := false
var _hide_crosshair := false
var _hit_alpha := 0.0
var _hit_was_kill := false
var _damage_alpha := 0.0
var _kills := 0
var _feed: Array[Dictionary] = []  # { "text": String, "time_left": float }
var _death_text := ""
var _respawn_left := 0.0
var _mode_text := ""


func _ready() -> void:
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_build_pause_screen()
	_match = get_tree().current_scene.get_node("Match")
	_lobby_panel = LobbyPanelScript.new()
	_lobby_panel.setup(_match)
	_lobby_panel.visible = false
	add_child(_lobby_panel)
	Network.message.connect(_add_feed_line)

	match Network.mode:
		Network.Mode.PRACTICE:
			_mode_text = "Practice"
		Network.Mode.HOST:
			var addresses := Network.lan_addresses()
			_mode_text = "Hosting  —  friends join with:  %s" % (
				", ".join(addresses) if not addresses.is_empty() else "127.0.0.1 (this PC only)")
		Network.Mode.JOIN:
			_mode_text = "Connected to %s" % Network.join_address


func _process(delta: float) -> void:
	_hit_alpha = maxf(_hit_alpha - delta * 4.0, 0.0)
	_damage_alpha = maxf(_damage_alpha - delta * 1.5, 0.0)
	if _respawn_left > 0.0:
		_respawn_left = maxf(_respawn_left - delta, 0.0)
	for line in _feed:
		line["time_left"] -= delta
	_feed.assign(_feed.filter(func(line: Dictionary) -> bool: return line["time_left"] > 0.0))
	# The lobby screen replaces the pause screen while it's up.
	var in_lobby := _match.in_lobby()
	if in_lobby and not _was_in_lobby:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif _was_in_lobby and not in_lobby and get_window().has_focus():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # straight into the action
	_was_in_lobby = in_lobby
	_lobby_panel.visible = in_lobby
	_pause_screen.visible = not in_lobby and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	_canvas.queue_redraw()


# --- Called by the player script ---------------------------------------------------

func update_state(spread_px: float, ammo: int, reserve: int, stance_name: String,
		reloading: bool, hide_crosshair: bool, health: float) -> void:
	_spread_px = spread_px
	_ammo = ammo
	_reserve = reserve
	_stance_name = stance_name
	_reloading = reloading
	_hide_crosshair = hide_crosshair
	_health = health


func show_hit_marker(killed: bool) -> void:
	_hit_alpha = 1.0
	_hit_was_kill = killed
	if killed:
		_kills += 1


func show_damage() -> void:
	_damage_alpha = 0.6


## respawn_time < 0 means "wait for the next round". An empty killer_name means
## we joined in the middle of a round.
func show_death(killer_name: String, respawn_time: float) -> void:
	_death_text = "KILLED BY %s" % killer_name.to_upper() if killer_name != "" else "ROUND IN PROGRESS"
	_respawn_left = respawn_time


func hide_death() -> void:
	_death_text = ""


func _add_feed_line(text: String) -> void:
	_feed.append({ "text": text, "time_left": FEED_TIME })
	if _feed.size() > FEED_LINES:
		_feed.pop_front()


# --- Pause screen --------------------------------------------------------------------

## Shown whenever the mouse is free: at startup, after Esc, or when the window loses focus.
## Clicking anywhere except a button resumes the game (handled by the player script).
func _build_pause_screen() -> void:
	_pause_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pause_screen)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_screen.add_child(dim)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 16)
	_pause_screen.add_child(box)

	var title := Label.new()
	title.text = "OPERATION: DELTA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var hint := Label.new()
	hint.text = "Click anywhere to play  ·  Esc to pause"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 20)
	box.add_child(hint)

	box.add_child(_pause_button("Resume",
		func() -> void: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED))
	box.add_child(_pause_button("Leave Match", func() -> void: Network.leave()))
	box.add_child(_pause_button("Quit Game", func() -> void: get_tree().quit()))


func _pause_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(on_pressed)
	return button


# --- Drawing --------------------------------------------------------------------------

func _draw_hud() -> void:
	var size := _canvas.size
	var center := size * 0.5
	var font := ThemeDB.fallback_font

	# Red edge flash when we take damage.
	if _damage_alpha > 0.0:
		var red := Color(0.8, 0.05, 0.05, _damage_alpha * 0.5)
		var edge := 60.0
		_canvas.draw_rect(Rect2(0, 0, size.x, edge), red)
		_canvas.draw_rect(Rect2(0, size.y - edge, size.x, edge), red)
		_canvas.draw_rect(Rect2(0, 0, edge, size.y), red)
		_canvas.draw_rect(Rect2(size.x - edge, 0, edge, size.y), red)

	# Crosshair: four ticks whose gap shows where bullets can land.
	if not _hide_crosshair:
		var gap := _spread_px + 3.0
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			_canvas.draw_line(center + dir * gap, center + dir * (gap + 10.0), CROSSHAIR_COLOR, 2.0)
		_canvas.draw_circle(center, 1.5, CROSSHAIR_COLOR)

	# Hit marker: white X for a hit, red X for a kill.
	if _hit_alpha > 0.0:
		var hit_color := Color(1, 0.2, 0.2) if _hit_was_kill else Color.WHITE
		hit_color.a = _hit_alpha
		for dir: Vector2 in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			var d := dir.normalized()
			_canvas.draw_line(center + d * 7.0, center + d * 15.0, hit_color, 2.0)

	# Death screen
	if _death_text != "" and not _match.in_lobby():
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0, 0, 0.35))
		_text(font, Vector2(0, center.y - 40), _death_text, 40, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		var sub_text := "Respawning in %d" % ceili(_respawn_left)
		if _respawn_left < 0.0:
			sub_text = "You'll be back next round"
		_text(font, Vector2(0, center.y + 4), sub_text, 22, HORIZONTAL_ALIGNMENT_CENTER, size.x)

	# Ammo (bottom right)
	var ammo_text := "%d / %d" % [_ammo, _reserve]
	_text(font, Vector2(size.x - 324, size.y - 30), ammo_text, 34, HORIZONTAL_ALIGNMENT_RIGHT)
	if _reloading:
		_text(font, Vector2(size.x - 324, size.y - 74), "RELOADING", 20, HORIZONTAL_ALIGNMENT_RIGHT)

	# Health, stance and kills (bottom left)
	var health_color := TEXT_COLOR if _health > 30.0 else Color(1, 0.35, 0.3)
	_text(font, Vector2(24, size.y - 30), "HEALTH  %d" % ceili(_health), 30,
		HORIZONTAL_ALIGNMENT_LEFT, 300.0, health_color)
	_text(font, Vector2(24, size.y - 72), _stance_name, 20, HORIZONTAL_ALIGNMENT_LEFT)
	_text(font, Vector2(24, size.y - 100), "KILLS  %d" % _kills, 20, HORIZONTAL_ALIGNMENT_LEFT)

	# Title and mode (top left), controls help (bottom center)
	_text(font, Vector2(24, 36), "OPERATION: DELTA  —  Range 01", 20, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
	_text(font, Vector2(24, 60), _mode_text, 15, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
	_text(font, Vector2(0, size.y - 14), HELP_TEXT, 14, HORIZONTAL_ALIGNMENT_CENTER, size.x)

	_draw_match_info(font, size)
	_draw_minimap(size)

	# Kill feed (top right, under the mini map)
	var y := MINIMAP_MARGIN + MINIMAP_SIZE + 34.0
	for line in _feed:
		_text(font, Vector2(size.x - 524, y), line["text"], 18, HORIZONTAL_ALIGNMENT_RIGHT, 500.0)
		y += 26.0


## Score, round timer and the big banner in the middle (round start, round won, etc).
func _draw_match_info(font: Font, size: Vector2) -> void:
	var match_node := _match
	if match_node.state == MatchScript.State.PRACTICE or match_node.in_lobby():
		return
	var center_x := size.x * 0.5
	var my_team: int = get_parent().get("team")

	# Your team (top left of center) and the score.
	_text(font, Vector2(0, 112), "YOU ARE %s" % MatchScript.TEAM_NAMES[my_team], 16,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, MatchScript.TEAM_COLORS[my_team])
	var ops := "%s  %d" % [MatchScript.TEAM_NAMES[MatchScript.TEAM_OPS], match_node.scores[MatchScript.TEAM_OPS]]
	var terrorists := "%d  %s" % [match_node.scores[MatchScript.TEAM_TERRORISTS],
		MatchScript.TEAM_NAMES[MatchScript.TEAM_TERRORISTS]]
	_text(font, Vector2(center_x - 424, 40), ops, 26, HORIZONTAL_ALIGNMENT_RIGHT, 400.0,
		MatchScript.TEAM_COLORS[MatchScript.TEAM_OPS])
	_text(font, Vector2(center_x + 24, 40), terrorists, 26, HORIZONTAL_ALIGNMENT_LEFT, 400.0,
		MatchScript.TEAM_COLORS[MatchScript.TEAM_TERRORISTS])

	var status := ""
	match match_node.state:
		MatchScript.State.COUNTDOWN, MatchScript.State.LIVE:
			var seconds := ceili(match_node.time_left)
			status = "%d:%02d" % [seconds / 60, seconds % 60]
		_:
			status = "First to %d" % match_node.rounds_to_win
	_text(font, Vector2(0, 76), status, 20, HORIZONTAL_ALIGNMENT_CENTER, size.x)

	var banner := match_node.banner
	if match_node.state == MatchScript.State.COUNTDOWN:
		banner += "   —   GO IN %d" % ceili(match_node.time_left)
	if banner != "":
		_text(font, Vector2(0, size.y * 0.3), banner, 38, HORIZONTAL_ALIGNMENT_CENTER, size.x)


## North-up map of the whole level: you are the white arrow, teammates are blue dots,
## and enemies flash up as red dots for a moment whenever they fire.
func _draw_minimap(size: Vector2) -> void:
	var texture: Texture2D = get_tree().current_scene.get("minimap_texture")
	if not texture:
		return
	var rect := Rect2(size.x - MINIMAP_SIZE - MINIMAP_MARGIN, MINIMAP_MARGIN, MINIMAP_SIZE, MINIMAP_SIZE)
	_canvas.draw_rect(rect.grow(3), Color(0, 0, 0, 0.6))
	_canvas.draw_texture_rect(texture, rect, false, Color(1, 1, 1, 0.9))

	var me := get_parent() as Node3D
	var my_team: int = me.get("team")
	var now := Time.get_ticks_msec()
	for player: Node3D in get_tree().get_nodes_in_group("players"):
		if player == me or not player.get("alive"):
			continue
		var point := _map_point(player.global_position, rect)
		if player.get("team") == my_team:
			_canvas.draw_circle(point, 4.0, TEAMMATE_DOT)
		elif now - int(player.get("last_shot_msec")) < ENEMY_REVEAL_MSEC:
			_canvas.draw_circle(point, 4.0, ENEMY_DOT)

	# You: an arrow pointing the way you face.
	var facing := Vector2(-sin(me.rotation.y), -cos(me.rotation.y))
	var side := Vector2(-facing.y, facing.x)
	var tip := _map_point(me.global_position, rect)
	_canvas.draw_colored_polygon(PackedVector2Array([
		tip + facing * 8.0, tip - facing * 5.0 + side * 5.0, tip - facing * 5.0 - side * 5.0,
	]), Color.WHITE)


## Converts a world position (x, z) to a point on the mini map.
func _map_point(world: Vector3, rect: Rect2) -> Vector2:
	var map_size: float = get_tree().current_scene.get("map_size")
	var u := clampf(world.x / map_size + 0.5, 0.0, 1.0)
	var v := clampf(world.z / map_size + 0.5, 0.0, 1.0)
	return rect.position + Vector2(u, v) * rect.size


func _text(font: Font, pos: Vector2, text: String, font_size: int,
		align: HorizontalAlignment, width: float = 300.0, color: Color = TEXT_COLOR) -> void:
	_canvas.draw_string_outline(font, pos, text, align, width, font_size, 5, Color(0, 0, 0, 0.8))
	_canvas.draw_string(font, pos, text, align, width, font_size, color)
