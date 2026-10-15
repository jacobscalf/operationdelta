extends CanvasLayer
## On-screen display: crosshair, ammo, health, stance, hit markers, kill feed,
## death screen and the pause screen. Most of it is drawn by hand on one full-screen Control.

const CROSSHAIR_COLOR := Color(0.55, 1.0, 0.55, 0.9)
const TEXT_COLOR := Color(0.92, 0.92, 0.88)
const HELP_TEXT := "WASD move   Shift sprint   C crouch   Z prone   RMB aim   LMB fire   R reload   Q swap shoulder   Esc pause"
const FEED_TIME := 6.0  # seconds a kill-feed line stays up
const FEED_LINES := 5

var _canvas := Control.new()
var _pause_screen := Control.new()
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
	Network.message.connect(_add_feed_line)

	match Network.mode:
		Network.Mode.PRACTICE:
			_mode_text = "Practice"
		Network.Mode.HOST:
			var addresses := Network.lan_addresses()
			_mode_text = "Hosting  —  friends join with: %s" % (
				", ".join(addresses) if not addresses.is_empty() else "127.0.0.1 (this PC only)")
		Network.Mode.JOIN:
			_mode_text = "Connected to %s" % Network.join_address


func _process(delta: float) -> void:
	_hit_alpha = maxf(_hit_alpha - delta * 4.0, 0.0)
	_damage_alpha = maxf(_damage_alpha - delta * 1.5, 0.0)
	_respawn_left = maxf(_respawn_left - delta, 0.0)
	for line in _feed:
		line["time_left"] -= delta
	_feed.assign(_feed.filter(func(line: Dictionary) -> bool: return line["time_left"] > 0.0))
	_pause_screen.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
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


func show_death(killer_name: String, respawn_time: float) -> void:
	_death_text = "KILLED BY %s" % killer_name.to_upper()
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
	if _death_text != "":
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.15, 0, 0, 0.35))
		_text(font, Vector2(0, center.y - 40), _death_text, 40, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		_text(font, Vector2(0, center.y + 4), "Respawning in %d" % ceili(_respawn_left), 22,
			HORIZONTAL_ALIGNMENT_CENTER, size.x)

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

	# Title, mode and controls help (top left)
	_text(font, Vector2(24, 36), "OPERATION: DELTA  —  Range 01  —  %s" % _mode_text, 20,
		HORIZONTAL_ALIGNMENT_LEFT, 1200.0)
	_text(font, Vector2(24, 62), HELP_TEXT, 15, HORIZONTAL_ALIGNMENT_LEFT, 1400.0)

	# Kill feed (top right)
	var y := 40.0
	for line in _feed:
		_text(font, Vector2(size.x - 524, y), line["text"], 18, HORIZONTAL_ALIGNMENT_RIGHT, 500.0)
		y += 26.0


func _text(font: Font, pos: Vector2, text: String, font_size: int,
		align: HorizontalAlignment, width: float = 300.0, color: Color = TEXT_COLOR) -> void:
	_canvas.draw_string_outline(font, pos, text, align, width, font_size, 5, Color(0, 0, 0, 0.8))
	_canvas.draw_string(font, pos, text, align, width, font_size, color)
