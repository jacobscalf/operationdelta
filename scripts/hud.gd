extends CanvasLayer
## On-screen display: dynamic crosshair, ammo, stance, hit markers and controls help.
## Everything is drawn by hand on one full-screen Control.

const CROSSHAIR_COLOR := Color(0.55, 1.0, 0.55, 0.9)
const TEXT_COLOR := Color(0.92, 0.92, 0.88)
const HELP_TEXT := "WASD move   Shift sprint   C crouch   Z prone   RMB aim   LMB fire   R reload   Q swap shoulder   Esc pause"

var _canvas := Control.new()
var _spread_px := 10.0
var _ammo := 0
var _reserve := 0
var _stance_name := ""
var _reloading := false
var _sprinting := false
var _hit_alpha := 0.0
var _hit_was_kill := false
var _kills := 0


var _pause_screen := Control.new()


func _ready() -> void:
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_build_pause_screen()


func _process(delta: float) -> void:
	_hit_alpha = maxf(_hit_alpha - delta * 4.0, 0.0)
	_pause_screen.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	_canvas.queue_redraw()


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

	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(240, 48)
	resume.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume.pressed.connect(func() -> void: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	box.add_child(resume)

	var quit := Button.new()
	quit.text = "Quit Game"
	quit.custom_minimum_size = Vector2(240, 48)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(quit)


func update_state(spread_px: float, ammo: int, reserve: int, stance_name: String,
		reloading: bool, sprinting: bool) -> void:
	_spread_px = spread_px
	_ammo = ammo
	_reserve = reserve
	_stance_name = stance_name
	_reloading = reloading
	_sprinting = sprinting


func show_hit_marker(killed: bool) -> void:
	_hit_alpha = 1.0
	_hit_was_kill = killed
	if killed:
		_kills += 1


func _draw_hud() -> void:
	var size := _canvas.size
	var center := size * 0.5
	var font := ThemeDB.fallback_font

	# Crosshair: four ticks whose gap shows where bullets can land.
	if not _sprinting:
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

	# Ammo (bottom right)
	var ammo_text := "%d / %d" % [_ammo, _reserve]
	_text(font, Vector2(size.x - 324, size.y - 30), ammo_text, 34, HORIZONTAL_ALIGNMENT_RIGHT)
	if _reloading:
		_text(font, Vector2(size.x - 324, size.y - 74), "RELOADING", 20, HORIZONTAL_ALIGNMENT_RIGHT)

	# Stance and kills (bottom left)
	_text(font, Vector2(24, size.y - 30), _stance_name, 24, HORIZONTAL_ALIGNMENT_LEFT)
	_text(font, Vector2(24, size.y - 66), "KILLS  %d" % _kills, 20, HORIZONTAL_ALIGNMENT_LEFT)

	# Controls help (top left)
	_text(font, Vector2(24, 36), "OPERATION: DELTA  —  Range 01", 20, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
	_text(font, Vector2(24, 62), HELP_TEXT, 15, HORIZONTAL_ALIGNMENT_LEFT, 1400.0)


func _text(font: Font, pos: Vector2, text: String, font_size: int,
		align: HorizontalAlignment, width: float = 300.0) -> void:
	_canvas.draw_string_outline(font, pos, text, align, width, font_size, 5, Color(0, 0, 0, 0.8))
	_canvas.draw_string(font, pos, text, align, width, font_size, TEXT_COLOR)
