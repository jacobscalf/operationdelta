extends Control
## The pre-match lobby: pick a side, then GREEN UP when you're ready.
## When everyone is green and both sides have a player, the match starts after a countdown.
## Shown by the HUD whenever the Match is in the lobby.

const MatchScript := preload("res://scripts/match.gd")
const GREEN := Color(0.35, 0.95, 0.4)
const GREY := Color(0.65, 0.65, 0.62)

var _match: MatchScript
var _team_lists: Array[VBoxContainer] = [VBoxContainer.new(), VBoxContainer.new()]
var _join_buttons: Array[Button] = [Button.new(), Button.new()]
var _ready_button := Button.new()
var _status := Label.new()
var _settings := Label.new()
var _my_ready := false


func setup(match_node: MatchScript) -> void:
	_match = match_node


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # clicks here never reach the game

	var background := ColorRect.new()
	background.color = Color(0.05, 0.06, 0.05, 0.92)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(760, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	box.add_child(_label("MATCH LOBBY", 44))
	_settings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings.add_theme_color_override("font_color", GREY)
	box.add_child(_settings)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	box.add_child(columns)
	for team in [MatchScript.TEAM_OPS, MatchScript.TEAM_TERRORISTS]:
		columns.add_child(_build_team_column(team))

	_ready_button.custom_minimum_size = Vector2(320, 60)
	_ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ready_button.add_theme_font_size_override("font_size", 26)
	_ready_button.pressed.connect(func() -> void:
		Sfx.play_ui("click" if _my_ready else "green_up", -4.0)
		_match.request_green_up.rpc_id(1, not _my_ready))
	box.add_child(_ready_button)

	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	box.add_child(_status)

	var leave := Button.new()
	leave.text = "Leave Match"
	leave.custom_minimum_size = Vector2(200, 40)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(func() -> void: Network.leave())
	box.add_child(leave)

	_match.lobby_changed.connect(_refresh)
	_match.changed.connect(_refresh)
	_refresh()


func _build_team_column(team: int) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 300)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := _label(MatchScript.TEAM_NAMES[team], 30)
	title.add_theme_color_override("font_color", MatchScript.TEAM_COLORS[team])
	column.add_child(title)

	_team_lists[team].size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_team_lists[team])

	var join := _join_buttons[team]
	join.custom_minimum_size = Vector2(0, 44)
	join.pressed.connect(func() -> void:
		Sfx.play_ui("click", -4.0)
		_match.request_team.rpc_id(1, team))
	column.add_child(join)
	return panel


func _process(_delta: float) -> void:
	_status.text = _status_text()


## Rebuilds both player lists and the buttons from the latest lobby info.
func _refresh() -> void:
	var my_id := multiplayer.get_unique_id()
	var my_team := -1
	_my_ready = false
	for list in _team_lists:
		for child in list.get_children():
			child.queue_free()

	for entry: Dictionary in _match.lobby:
		var is_me: bool = entry["id"] == my_id
		var is_ready: bool = entry["ready"]
		if is_me:
			my_team = entry["team"]
			_my_ready = is_ready
		var text := "%s%s" % [entry["name"], "  (you)" if is_me else ""]
		var row := _label(("READY   " if is_ready else "            ") + text, 20, HORIZONTAL_ALIGNMENT_LEFT)
		row.add_theme_color_override("font_color", GREEN if is_ready else GREY)
		_team_lists[entry["team"]].add_child(row)

	for team: int in [MatchScript.TEAM_OPS, MatchScript.TEAM_TERRORISTS]:
		var on_this_team := my_team == team
		_join_buttons[team].disabled = on_this_team
		_join_buttons[team].text = "You're on %s" % MatchScript.TEAM_NAMES[team] if on_this_team \
			else "Join %s" % MatchScript.TEAM_NAMES[team]

	_ready_button.text = "READY  (click to cancel)" if _my_ready else "GREEN UP"
	_ready_button.modulate = GREEN if _my_ready else Color.WHITE
	_ready_button.disabled = my_team == -1

	_settings.text = "%s   ·   First to %d rounds   ·   %d-minute rounds   ·   Friendly fire %s" % [
		Network.map_name, _match.rounds_to_win, _match.round_minutes,
		"ON" if _match.friendly_fire else "OFF"]


func _status_text() -> String:
	if _match.state == MatchScript.State.STARTING:
		return "Everyone's green!  Match starts in %d" % ceili(_match.time_left)
	var counts := [0, 0]
	var waiting := 0
	for entry: Dictionary in _match.lobby:
		counts[entry["team"]] += 1
		if not entry["ready"]:
			waiting += 1
	if counts[0] == 0 or counts[1] == 0:
		return "Need at least one player on each side"
	if waiting > 0:
		return "Waiting for %d player%s to green up" % [waiting, "" if waiting == 1 else "s"]
	return ""


func _label(text: String, font_size: int,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	return label
