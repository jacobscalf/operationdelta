extends Node3D
## The match scene: builds the gray-box map "Range 01", its lighting and mini map,
## opens the network connection, and spawns a soldier for every player who joins.
## The rounds themselves are run by the Match node (match.gd).
## All geometry here is placeholder blocks; real art replaces it in a later milestone.

const PlayerScript := preload("res://scripts/player.gd")
const DummyScript := preload("res://scripts/target_dummy.gd")
const MatchScript := preload("res://scripts/match.gd")

const SAND := Color(0.66, 0.57, 0.42)
const CONCRETE := Color(0.6, 0.59, 0.56)
const WALL := Color(0.72, 0.63, 0.5)
const WOOD := Color(0.5, 0.38, 0.25)

## Where each team appears: Ops in the south, Terrorists in the north.
const TEAM_SPAWNS := [
	[
		Vector3(0, 0.1, 55), Vector3(-4, 0.1, 57), Vector3(4, 0.1, 57), Vector3(-12, 0.1, 52),
		Vector3(12, 0.1, 52), Vector3(-8, 0.1, 61), Vector3(8, 0.1, 61), Vector3(0, 0.1, 63),
	],
	[
		Vector3(0, 0.1, -55), Vector3(-4, 0.1, -57), Vector3(4, 0.1, -57), Vector3(12, 0.1, -62),
		Vector3(-25, 0.1, -58), Vector3(25, 0.1, -58), Vector3(-8, 0.1, -62), Vector3(8, 0.1, -62),
	],
]

## How much of the world the mini map covers (the map is 140 x 140 m, centered on 0,0).
const MAP_SIZE := 140.0
## Visual layer for things that should NOT appear on the mini map (players, effects).
const LAYER_DYNAMIC := 2

## A top-down picture of the map, drawn once, for the HUD's mini map.
var minimap_texture: Texture2D
var map_size := MAP_SIZE

var _checker: ImageTexture
var _materials := {}
var _players := Node3D.new()
var _spawner := MultiplayerSpawner.new()
var _match: MatchScript


func _ready() -> void:
	_checker = _make_checker_texture()
	_build_lighting()
	_build_map()
	_build_minimap()
	if Network.mode == Network.Mode.PRACTICE:
		_spawn_targets()

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
	add_child(_match)

	var error_text := Network.open_connection()
	if error_text != "":
		Network.leave(error_text)
		return

	multiplayer.connection_failed.connect(
		func() -> void: Network.leave("Couldn't reach a host at %s." % Network.join_address))
	multiplayer.server_disconnected.connect(
		func() -> void: Network.leave("The host left the game."))

	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_add_player)
		multiplayer.peer_disconnected.connect(_remove_player)
		_add_player(1)  # the host's own soldier


# --- Players (the host decides who exists; the spawner copies that to everyone) -----

func _add_player(peer_id: int) -> void:
	var team := _match.team_for_new_player()
	_spawner.spawn({
		"id": peer_id,
		"team": team,
		"alive": _match.joiner_starts_alive(),
		"position": spawn_point_for(team, -1),
	})
	if peer_id == 1:
		return
	# Wait a moment so the new player's computer has everything loaded, then catch it up.
	await get_tree().create_timer(1.0).timeout
	var player := _players.get_node_or_null(str(peer_id))
	if not player:
		return
	_match.send_state_to(peer_id)
	for other in _players.get_children():
		if other != player:
			other.call("send_life_to", peer_id)
	Network.announce.rpc("%s joined %s" % [
		player.get("display_name"), MatchScript.TEAM_NAMES[player.get("team")]])


func _remove_player(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player:
		Network.announce.rpc("%s left" % player.get("display_name"))
		player.queue_free()
		_match.on_player_left()


## Runs on every computer when the host spawns a player.
func _create_player(data: Variant) -> Node:
	var info: Dictionary = data
	var peer_id: int = info["id"]
	var player: PlayerScript = PlayerScript.new()
	player.name = str(peer_id)
	player.position = info["position"]
	player.team = info["team"]
	player.alive = info["alive"]
	player.set_multiplayer_authority(peer_id)
	return player


## A spawn point for a team. index >= 0 picks that slot (used at round start so teammates
## don't stack); -1 picks the slot farthest from living enemies.
func spawn_point_for(team: int, index: int) -> Vector3:
	var points: Array = TEAM_SPAWNS[team]
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
	viewport.size = Vector2i(512, 512)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = MAP_SIZE
	camera.near = 1.0
	camera.far = 200.0
	camera.cull_mask = 1
	camera.position = Vector3(0, 100, 0)
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


# --- Lighting -------------------------------------------------------------------

func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.3, 0.45, 0.65)
	sky_material.sky_horizon_color = Color(0.75, 0.7, 0.62)
	sky_material.ground_horizon_color = Color(0.7, 0.64, 0.55)
	sky_material.ground_bottom_color = Color(0.35, 0.3, 0.25)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.sdfgi_enabled = true  # real-time bounce lighting
	env.ssao_enabled = true  # contact shadows in corners
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.7, 0.62)
	env.fog_density = 0.002
	env.fog_sky_affect = 0.15
	env.tonemap_exposure = 0.9

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


# --- Map layout -----------------------------------------------------------------
# Coordinates are in meters. The player spawns in the south (+Z) looking north (-Z).

func _build_map() -> void:
	# Ground and boundary walls
	_box(Vector3(140, 1, 140), Vector3(0, -0.5, 0), SAND)
	_box(Vector3(140, 4, 1), Vector3(0, 2, -70), WALL)
	_box(Vector3(140, 4, 1), Vector3(0, 2, 70), WALL)
	_box(Vector3(1, 4, 140), Vector3(-70, 2, 0), WALL)
	_box(Vector3(1, 4, 140), Vector3(70, 2, 0), WALL)

	# Spawn area: a 1 m low wall (crouch behind it to hide) and a crate stack
	_box(Vector3(10, 1, 0.6), Vector3(0, 0.5, 45), CONCRETE)
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-8, 0.6, 42), WOOD)
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-6.7, 0.6, 42.3), WOOD, 15)
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-7.4, 1.8, 42.1), WOOD, 40)

	# Mid-field low walls
	_box(Vector3(6, 1, 0.5), Vector3(-10, 0.5, 22), CONCRETE)
	_box(Vector3(6, 1, 0.5), Vector3(12, 0.5, 25), CONCRETE, 20)
	_box(Vector3(0.5, 1, 6), Vector3(18, 0.5, -2), CONCRETE)

	# Central building
	_box(Vector3(12, 5, 9), Vector3(0, 2.5, 0), WALL)

	# West buildings with an alley between them
	_box(Vector3(8, 4, 14), Vector3(-24, 2, -6), WALL)
	_box(Vector3(8, 3, 8), Vector3(-24, 1.5, 14), WALL)

	# East: raised platform with a ramp up to it
	_box(Vector3(8, 3, 8), Vector3(30, 1.5, -20), CONCRETE)
	_box(Vector3(3, 0.3, 8.54), Vector3(30, 1.35, -12), CONCRETE, 0, 20.56)

	# Taller walls to peek around
	_box(Vector3(5, 2.5, 0.5), Vector3(-6, 1.25, -18), WALL)
	_box(Vector3(5, 2.5, 0.5), Vector3(8, 1.25, -22), WALL, -15)

	# North crate clusters
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-3, 0.6, -34), WOOD, 10)
	_box(Vector3(1.2, 1.2, 1.2), Vector3(-1.7, 0.6, -34.4), WOOD)
	_box(Vector3(2.4, 1.2, 1.2), Vector3(14, 0.6, -40), WOOD, -25)
	_box(Vector3(1.2, 2.4, 1.2), Vector3(-20, 1.2, -42), WOOD)

	# Northwest watch tower
	_box(Vector3(4, 6, 4), Vector3(-45, 3, -45), CONCRETE)


func _spawn_targets() -> void:
	var still := [
		Vector3(-5, 0, 30), Vector3(5, 0, 30), Vector3(-12, 0, 10), Vector3(12, 0, 8),
		Vector3(0, 0, -12), Vector3(-20, 0, -20), Vector3(25, 0, -5),
		Vector3(30, 3, -22), Vector3(-45, 6, -45),
		Vector3(0, 0, -40), Vector3(-15, 0, -50), Vector3(15, 0, -50),
	]
	for pos: Vector3 in still:
		_spawn_target(pos, 0.0)

	_spawn_target(Vector3(0, 0, -28), 4.0)
	_spawn_target(Vector3(22, 0, -34), 3.0)
	_spawn_target(Vector3(-32, 0, -28), 5.0)


func _spawn_target(pos: Vector3, strafe: float) -> void:
	var dummy: DummyScript = DummyScript.new()
	dummy.position = pos
	dummy.strafe_distance = strafe
	add_child(dummy)


# --- Helpers ------------------------------------------------------------------------

## Creates a solid block with collision. Rotations are in degrees.
func _box(size: Vector3, pos: Vector3, color: Color, rot_y: float = 0.0, rot_x: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = Vector3(rot_x, rot_y, 0)

	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = _material(color)
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	add_child(body)
	return body


## A 1 m checker pattern projected in world space, so distances are easy to judge.
func _material(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = _checker
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.5
	mat.roughness = 0.9
	_materials[color] = mat
	return mat


func _make_checker_texture() -> ImageTexture:
	var img := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var light := ((x >> 5) + (y >> 5)) % 2 == 0
			img.set_pixel(x, y, Color(1, 1, 1) if light else Color(0.86, 0.86, 0.86))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
