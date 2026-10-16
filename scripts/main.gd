extends Node3D
## The match scene: loads the chosen map (see scripts/maps/), builds the mini map,
## opens the network connection, and spawns a soldier for every player who joins.
## The rounds themselves are run by the Match node (match.gd).

const PlayerScript := preload("res://scripts/player.gd")
const MatchScript := preload("res://scripts/match.gd")

## Visual layer for things that should NOT appear on the mini map (players, effects).
const LAYER_DYNAMIC := 2

## Bots: how long the host waits alone in the lobby before one joins, and their ids/names.
const BOT_JOIN_DELAY := 15.0
const BOT_ID_START := 1000
const BOT_NAMES := ["Hawk", "Viper", "Ghost", "Rook", "Mako", "Jinx"]

## The level being played (a script from scripts/maps/, built on map_kit.gd).
var map: Node3D
## A top-down picture of the map, drawn once, for the HUD's mini map.
var minimap_texture: Texture2D
## Size (x by z, meters) and center of the area the mini map shows.
var map_size := Vector2(140, 140)
var map_center := Vector2.ZERO
## Host only: clients that have loaded the map and can be sent players.
var ready_peers: Array[int] = []

var _alone_time := 0.0
var _bot_count := 0
var _players := Node3D.new()
var _spawner := MultiplayerSpawner.new()
var _match: MatchScript


func _ready() -> void:
	map = load(Network.MAPS[Network.map_name]).new()
	map.name = "Map"
	add_child(map)
	map_size = map.get("size")
	map_center = map.get("center")
	_build_minimap()

	# Every computer builds these with the same names, so the network can match them up.
	_players.name = "Players"
	add_child(_players)
	_spawner.name = "PlayerSpawner"
	_spawner.spawn_function = _create_player
	add_child(_spawner)
	_spawner.spawn_path = _spawner.get_path_to(_players)
	_match = MatchScript.new()
	_match.name = "Match"
	_match.players_node = _players
	_match.spawn_point_for = spawn_point_for
	_match.ready_peers = ready_peers
	add_child(_match)

	var error_text := Network.open_connection()
	if error_text != "":
		Network.leave(error_text)
		return

	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_remove_player)
		_add_player(1)  # the host's own soldier
	else:
		client_ready.rpc_id(1)  # map loaded: the host can send us everything now


## Host only: if the host sits alone in the lobby for a while, a bot joins to play against.
func _process(delta: float) -> void:
	if not multiplayer.is_server() or Network.mode != Network.Mode.HOST:
		return
	var alone_in_lobby := _match.in_lobby() and _players.get_child_count() == 1
	_alone_time = _alone_time + delta if alone_in_lobby else 0.0
	if _alone_time >= BOT_JOIN_DELAY:
		_alone_time = 0.0
		_add_bot()


# --- Players (the host decides who exists; the spawner copies that to everyone) -----

## Host: someone connected. First tell them which map to load; they'll call client_ready.
func _on_peer_connected(peer_id: int) -> void:
	Network.tell_map.rpc_id(peer_id, Network.map_name)


## Client -> host: "I've loaded the map." Now show them everyone and give them a soldier.
@rpc("any_peer", "call_remote", "reliable")
func client_ready() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id in ready_peers:
		return
	ready_peers.append(peer_id)
	for player in _players.get_children():
		player.call("show_to_peer", peer_id)
	_match.send_state_to(peer_id)
	_add_player(peer_id)


func _add_player(peer_id: int) -> void:
	# A real person is joining: bots step aside so the teams are made of people.
	if _match.in_lobby():
		for bot in _bots():
			_remove_player(String(bot.name).to_int())
	var team := _match.team_for_new_player()
	_spawner.spawn({
		"id": peer_id,
		"team": team,
		"alive": _match.joiner_starts_alive(),
		"position": spawn_point_for(team, -1),
	})
	if peer_id == 1:
		return
	# Wait a moment so the new player's soldier exists everywhere, then catch them up.
	await get_tree().create_timer(1.0).timeout
	var player := _players.get_node_or_null(str(peer_id))
	if not player:
		return
	for other in _players.get_children():
		if other != player:
			other.call("send_life_to", peer_id)
	Network.announce.rpc("%s joined %s" % [
		player.get("display_name"), MatchScript.TEAM_NAMES[player.get("team")]])


func _remove_player(peer_id: int) -> void:
	ready_peers.erase(peer_id)
	var player := _players.get_node_or_null(str(peer_id))
	if player:
		Network.announce.rpc("%s left" % player.get("display_name"))
		player.queue_free()
		_match.on_player_left(peer_id)


func _add_bot() -> void:
	_bot_count += 1
	var bot_id := BOT_ID_START + _bot_count
	var team := _match.team_for_new_player()
	_spawner.spawn({
		"id": bot_id,
		"team": team,
		"alive": _match.joiner_starts_alive(),
		"position": spawn_point_for(team, -1),
		"bot": true,
		"name": "BOT %s" % BOT_NAMES[(_bot_count - 1) % BOT_NAMES.size()],
	})
	_match.mark_green(bot_id)
	Network.announce.rpc("A bot joined %s" % MatchScript.TEAM_NAMES[team])


func _bots() -> Array[Node]:
	var list: Array[Node] = []
	for player in _players.get_children():
		if player.get("is_bot") and not player.is_queued_for_deletion():
			list.append(player)
	return list


## Runs on every computer when the host spawns a player.
func _create_player(data: Variant) -> Node:
	var info: Dictionary = data
	var peer_id: int = info["id"]
	var player: PlayerScript = PlayerScript.new()
	player.name = str(peer_id)
	player.position = info["position"]
	player.team = info["team"]
	player.alive = info["alive"]
	player.is_bot = info.get("bot", false)
	if player.is_bot:
		player.display_name = info["name"]
		player.set_multiplayer_authority(1)  # the host runs bots
	else:
		player.set_multiplayer_authority(peer_id)
	return player


## A spawn point for a team. index >= 0 picks that slot (used at round start so teammates
## don't stack); -1 picks the slot farthest from living enemies.
func spawn_point_for(team: int, index: int) -> Vector3:
	var points: Array = map.get("team_spawns")[team]
	if index >= 0:
		return points[index % points.size()]
	var best: Vector3 = points[0]
	var best_distance := -1.0
	for point: Vector3 in points:
		var nearest := INF
		for player in _players.get_children():
			if player.get("alive") and player.get("team") != team:
				nearest = minf(nearest, point.distance_to((player as Node3D).global_position))
		if nearest > best_distance:
			best_distance = nearest
			best = point
	return best


# --- Mini map ------------------------------------------------------------------------

## Takes one top-down picture of the map with an extra camera. Only visual layer 1
## (the level) is drawn, so players and effects never end up baked into the picture.
func _build_minimap() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, roundi(512.0 * map_size.y / map_size.x))
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = map_size.x
	camera.near = 1.0
	camera.far = 200.0
	camera.cull_mask = 1
	camera.position = Vector3(map_center.x, 100, map_center.y)
	camera.rotation_degrees = Vector3(-90, 0, 0)  # straight down, north (-Z) at the top
	# Its own lighting setup: no fog or haze, extra contrast so walls stand out from the sand.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	env.ssao_enabled = true
	env.ssao_intensity = 4.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.6
	env.adjustment_brightness = 0.85
	camera.environment = env
	viewport.add_child(camera)
	minimap_texture = viewport.get_texture()
