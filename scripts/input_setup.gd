extends Node
## Registers every control in code, so they're easy to read and change in one place.
## Runs automatically at startup (it's an Autoload in project.godot).

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],
	"crouch": [KEY_C, KEY_CTRL],
	"prone": [KEY_Z],
	"reload": [KEY_R],
	"switch_shoulder": [KEY_Q],
	"toggle_mouse": [KEY_ESCAPE],
}

const MOUSE_BUTTONS := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
}


func _enter_tree() -> void:
	for action: String in KEYS:
		_ensure_action(action)
		var keys: Array = KEYS[action]
		for key: int in keys:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

	for action: String in MOUSE_BUTTONS:
		_ensure_action(action)
		var buttons: Array = MOUSE_BUTTONS[action]
		for button: int in buttons:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)


func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.action_erase_events(action)
	else:
		InputMap.add_action(action)
