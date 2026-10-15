extends Node3D
## Builds the gray-box test map "Range 01", its lighting, and spawns the player and targets.
## All geometry here is placeholder blocks; real art replaces it in a later milestone.

const PlayerScript := preload("res://scripts/player.gd")
const DummyScript := preload("res://scripts/target_dummy.gd")

const SAND := Color(0.66, 0.57, 0.42)
const CONCRETE := Color(0.6, 0.59, 0.56)
const WALL := Color(0.72, 0.63, 0.5)
const WOOD := Color(0.5, 0.38, 0.25)

const PLAYER_SPAWN := Vector3(0, 0.1, 55)

var _checker: ImageTexture
var _materials := {}


func _ready() -> void:
	_checker = _make_checker_texture()
	_build_lighting()
	_build_map()
	_spawn_targets()

	var player: CharacterBody3D = PlayerScript.new()
	player.position = PLAYER_SPAWN
	add_child(player)


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
