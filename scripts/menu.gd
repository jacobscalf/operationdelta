extends Control
## Main menu: pick a name, then Practice (solo with targets), Host a match, or Join one.

var _name_edit := LineEdit.new()
var _address_edit := LineEdit.new()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.09, 0.1, 0.09)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(380, 0)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	box.add_child(_label("OPERATION: DELTA", 52))
	box.add_child(_label("", 8))

	box.add_child(_label("Your name", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_name_edit.text = Network.player_name
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(0, 40)
	box.add_child(_name_edit)

	box.add_child(_button("Practice (solo, with targets)", _on_practice))
	box.add_child(_button("Host Match", _on_host))

	box.add_child(_label("Host's IP address", 16, HORIZONTAL_ALIGNMENT_LEFT))
	_address_edit.text = Network.join_address
	_address_edit.custom_minimum_size = Vector2(0, 40)
	box.add_child(_address_edit)
	box.add_child(_button("Join Match", _on_join))

	box.add_child(_label("", 8))
	box.add_child(_button("Quit", func() -> void: get_tree().quit()))

	if Network.last_error != "":
		var error_label := _label(Network.last_error, 18)
		error_label.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
		error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(error_label)

	# Shortcuts for testing: launch with  -- --host  or  -- --join=127.0.0.1
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host.call_deferred()
		elif arg.begins_with("--join="):
			_address_edit.text = arg.trim_prefix("--join=")
			_on_join.call_deferred()


func _on_practice() -> void:
	_save_name()
	Network.start(Network.Mode.PRACTICE)


func _on_host() -> void:
	_save_name()
	Network.start(Network.Mode.HOST)


func _on_join() -> void:
	_save_name()
	Network.start(Network.Mode.JOIN, _address_edit.text.strip_edges())


func _save_name() -> void:
	var player_name := _name_edit.text.strip_edges()
	Network.player_name = player_name if player_name != "" else "Player"


func _label(text: String, font_size: int,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.pressed.connect(on_pressed)
	return button
