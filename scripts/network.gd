extends Node
## Remembers what the player picked in the menu (practice / host / join, which map) and
## creates the network connection. Runs as an Autoload ("Network").
##
## Joining works in steps so nothing arrives before the map exists:
##   1. The client connects while still on the menu.
##   2. The host tells it which map to load (tell_map).
##   3. The client loads that map and tells the host it's ready (Main.client_ready).
##   4. Only then does the host send it the players and the match state.

enum Mode { PRACTICE, HOST, JOIN }

const PORT := 7777
const MAX_PLAYERS := 16
const MENU_SCENE := "res://scenes/menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
## Every playable map: name -> script that builds it.
const MAPS := {
	"Red Canyon": "res://scripts/maps/red_canyon.gd",
	"Range 01": "res://scripts/maps/range_01.gd",
}

## Short messages for the on-screen feed (kills, players joining or leaving).
signal message(text: String)

var mode := Mode.PRACTICE
var join_address := "127.0.0.1"
var player_name := "Player"
var map_name := "Red Canyon"

# Match settings (chosen by the host in the menu)
var friendly_fire := false
var rounds_to_win := 4
var round_minutes := 5
## Shown on the menu after being sent back to it (e.g. "Host left the game").
var last_error := ""

var _leaving := false


func _ready() -> void:
	multiplayer.connection_failed.connect(
		func() -> void: leave("Couldn't reach a host at %s." % join_address))
	multiplayer.server_disconnected.connect(func() -> void:
		if not _leaving:
			leave("The host left the game."))


## Called by the menu. Practice and Host load the map straight away; Join connects first
## and loads whichever map the host is playing.
func start(new_mode: Mode, address: String = "127.0.0.1") -> void:
	mode = new_mode
	join_address = address
	last_error = ""
	if mode == Mode.JOIN:
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client(join_address, PORT) != OK:
			leave("Couldn't connect to %s." % join_address)
			return
		multiplayer.multiplayer_peer = peer
		return  # wait for the host's tell_map
	get_tree().change_scene_to_file(GAME_SCENE)


## Host -> a newly connected client: "we're playing this map; load it."
@rpc("authority", "call_remote", "reliable")
func tell_map(host_map: String) -> void:
	if not MAPS.has(host_map):
		leave("The host is playing a map you don't have (%s)." % host_map)
		return
	map_name = host_map
	get_tree().change_scene_to_file(GAME_SCENE)


## Called by the map scene once it has loaded. Returns "" on success, or an error message.
func open_connection() -> String:
	if mode == Mode.PRACTICE:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		return ""
	if mode == Mode.JOIN:
		return ""  # already connected from the menu
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		return "Couldn't host on port %d. Is another copy of the game already hosting?" % PORT
	multiplayer.multiplayer_peer = peer
	return ""


## The host calls this (with .rpc) to put a message on everyone's kill feed.
@rpc("authority", "call_local", "reliable")
func announce(text: String) -> void:
	message.emit(text)


## Disconnects and returns to the main menu, optionally showing a message there.
func leave(error_text: String = "") -> void:
	_leaving = true  # closing our own connection shouldn't count as "the host left"
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_leaving = false
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
