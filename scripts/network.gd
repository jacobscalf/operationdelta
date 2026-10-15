extends Node
## Remembers what the player picked in the menu (practice / host / join) and creates
## the network connection once the game map has loaded. Runs as an Autoload ("Network").

enum Mode { PRACTICE, HOST, JOIN }

const PORT := 7777
const MAX_PLAYERS := 16
const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

## Short messages for the on-screen feed (kills, players joining or leaving).
signal message(text: String)

var mode := Mode.PRACTICE
var join_address := "127.0.0.1"
var player_name := "Player"

# Match settings (chosen by the host in the menu)
var friendly_fire := false
var rounds_to_win := 4
var round_minutes := 5
## Shown on the menu after being sent back to it (e.g. "Host left the game").
var last_error := ""


## Called by the menu. Loads the map; the map then calls open_connection().
func start(new_mode: Mode, address: String = "127.0.0.1") -> void:
	mode = new_mode
	join_address = address
	last_error = ""
	get_tree().change_scene_to_file(GAME_SCENE)


## Creates the connection. Returns "" on success, or an error message.
## The map is loaded first so every computer has the same nodes ready when players appear.
func open_connection() -> String:
	if mode == Mode.PRACTICE:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		return ""

	var peer := ENetMultiplayerPeer.new()
	var err: Error
	if mode == Mode.HOST:
		err = peer.create_server(PORT, MAX_PLAYERS)
		if err != OK:
			return "Couldn't host on port %d. Is another copy of the game already hosting?" % PORT
	else:
		err = peer.create_client(join_address, PORT)
		if err != OK:
			return "Couldn't connect to %s." % join_address
	multiplayer.multiplayer_peer = peer
	return ""


## The host calls this (with .rpc) to put a message on everyone's kill feed.
@rpc("authority", "call_local", "reliable")
func announce(text: String) -> void:
	message.emit(text)


## Disconnects and returns to the main menu, optionally showing a message there.
func leave(error_text: String = "") -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	last_error = error_text
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


## This computer's local network addresses, so the host can tell friends what to type.
func lan_addresses() -> PackedStringArray:
	var found := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") \
				and not address.begins_with("169.254."):
			found.append(address)
	return found
