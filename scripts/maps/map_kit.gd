extends Node3D
## Base for every map. A map script extends this, fills in its data (size, spawns,
## bot routes, lighting) and builds its level in build() using the helpers below.
## All geometry is simple blocks for now ("blockout"); real art replaces it later.

# --- Data each map provides -----------------------------------------------------------
var display_name := "Map"
## Playable area in meters (x = west-east, y = north-south) and its center, for the mini map.
var size := Vector2(140, 140)
var center := Vector2.ZERO
## [Ops spawn points, Terrorist spawn points].
var team_spawns: Array = [[], []]
## Open spots bots wander between.
var waypoints: Array[Vector3] = []
## Bot routes, each listed from the Terrorist end to the Ops end (Ops walk them backwards).
var routes: Array = []

# --- Lighting (maps can change these in _init) -----------------------------------------
var sun_rotation := Vector3(-48, -35, 0)
var sun_color := Color(1.0, 0.94, 0.84)
var sun_energy := 1.3
var sky_top := Color(0.3, 0.45, 0.65)
var sky_horizon := Color(0.75, 0.7, 0.62)
var ground_horizon := Color(0.7, 0.64, 0.55)
var fog_color := Color(0.75, 0.7, 0.62)
var fog_density := 0.002

## Standard opening sizes: [offset along the wall from its middle, width, bottom, top].
const DOOR_W := 1.4
const DOOR_H := 2.3
const WINDOW_W := 1.2

var _checker: ImageTexture
var _materials := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1234  # the same "random" rocks on every computer
	_checker = _make_checker_texture()
	_build_lighting()
	build()


## Override in each map.
func build() -> void:
	pass


# --- Openings -------------------------------------------------------------------------------

func door(offset: float, width: float = DOOR_W) -> Array:
	return [offset, width, 0.0, DOOR_H]


func window(offset: float, bottom: float = 1.0, width: float = WINDOW_W) -> Array:
	return [offset, width, bottom, bottom + 0.9]


# --- Building blocks ------------------------------------------------------------------------

## A solid block with collision. Rotations are in degrees.
func box(box_size: Vector3, pos: Vector3, color: Color, rot_y: float = 0.0, rot_x: float = 0.0,
		rot_z: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = Vector3(rot_x, rot_y, rot_z)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box_size
	mesh.mesh = box_mesh
	mesh.material_override = material(color)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box_size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)
	return body


func cylinder(radius: float, height: float, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos + Vector3(0, height * 0.5, 0)
	var mesh := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius
	cylinder_mesh.height = height
	mesh.mesh = cylinder_mesh
	mesh.material_override = material(color)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var cylinder_shape := CylinderShape3D.new()
	cylinder_shape.radius = radius
	cylinder_shape.height = height
	shape.shape = cylinder_shape
	body.add_child(shape)
	add_child(body)
	return body


## A straight wall from a to b (x/z ground points) with openings cut into it.
## openings: [offset from the wall's middle, width, bottom, top] (see door() / window()).
func wall(a: Vector2, b: Vector2, height: float, color: Color, openings: Array = [],
		thickness: float = 0.3, base_y: float = 0.0) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var rot_y := rad_to_deg(atan2(-dir.y, dir.x))
	# Turn openings into [start, end, bottom, top] measured from a, sorted along the wall.
	var cuts: Array = []
	for opening: Array in openings:
		var mid: float = length * 0.5 + opening[0]
		cuts.append([mid - opening[1] * 0.5, mid + opening[1] * 0.5, opening[2], opening[3]])
	cuts.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])

	var cursor := 0.0
	for cut: Array in cuts:
		_wall_piece(a, dir, rot_y, cursor, cut[0], 0.0, height, thickness, base_y, color)
		_wall_piece(a, dir, rot_y, cut[0], cut[1], 0.0, cut[2], thickness, base_y, color)  # sill
		_wall_piece(a, dir, rot_y, cut[0], cut[1], cut[3], height, thickness, base_y, color)  # lintel
		cursor = cut[1]
	_wall_piece(a, dir, rot_y, cursor, length, 0.0, height, thickness, base_y, color)


func _wall_piece(a: Vector2, dir: Vector2, rot_y: float, from: float, to: float, bottom: float,
		top: float, thickness: float, base_y: float, color: Color) -> void:
	if to - from < 0.05 or top - bottom < 0.05:
		return
	var mid := a + dir * ((from + to) * 0.5)
	box(Vector3(to - from, top - bottom, thickness), Vector3(mid.x, base_y + (bottom + top) * 0.5, mid.y),
		color, rot_y)


## A rectangular building (axis-aligned) with walls, floor and an optional flat roof.
## pos is the ground center; openings is {"n": [...], "s": [...], "e": [...], "w": [...]}.
func building(pos: Vector3, footprint: Vector2, height: float, color: Color, openings: Dictionary,
		roof: bool = true) -> void:
	var hx := footprint.x * 0.5
	var hz := footprint.y * 0.5
	var x0 := pos.x - hx
	var x1 := pos.x + hx
	var z0 := pos.z - hz
	var z1 := pos.z + hz
	wall(Vector2(x0, z0), Vector2(x1, z0), height, color, openings.get("n", []), 0.3, pos.y)
	wall(Vector2(x0, z1), Vector2(x1, z1), height, color, openings.get("s", []), 0.3, pos.y)
	wall(Vector2(x1, z0), Vector2(x1, z1), height, color, openings.get("e", []), 0.3, pos.y)
	wall(Vector2(x0, z0), Vector2(x0, z1), height, color, openings.get("w", []), 0.3, pos.y)
	box(Vector3(footprint.x, 0.1, footprint.y), pos + Vector3(0, 0.05, 0), CONCRETE)
	if roof:
		box(Vector3(footprint.x + 0.4, 0.3, footprint.y + 0.4), pos + Vector3(0, height + 0.15, 0), ROOF)


## A walkable ramp between two points on its top surface (keep it under ~35 degrees).
func ramp(from: Vector3, to: Vector3, width: float, color: Color = CONCRETE) -> void:
	var forward := (to - from).normalized()
	var basis := Basis.looking_at(forward, Vector3.UP)
	var body := StaticBody3D.new()
	var thickness := 0.3
	body.transform = Transform3D(basis, (from + to) * 0.5 - basis.y * thickness * 0.5)
	var length := from.distance_to(to)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, thickness, length)
	mesh.mesh = box_mesh
	mesh.material_override = material(color)
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box_mesh.size
	shape.shape = box_shape
	body.add_child(shape)
	add_child(body)


## A rough rock wall along a chain of points: chunky blocks with uneven heights and tilts.
func cliff(points: Array, height: float, thickness: float, color: Color = ROCK) -> void:
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length := a.distance_to(b)
		var pieces := maxi(1, ceili(length / 8.0))
		var dir := (b - a) / length
		var rot_y := rad_to_deg(atan2(-dir.y, dir.x))
		for p in pieces:
			var mid := a + dir * (length * (p + 0.5) / pieces)
			var h := height * _rng.randf_range(0.75, 1.15)
			var shade := color.darkened(_rng.randf_range(-0.08, 0.12))
			box(Vector3(length / pieces + 2.0, h, thickness * _rng.randf_range(0.85, 1.2)),
				Vector3(mid.x, h * 0.5 - 0.3, mid.y), shade,
				rot_y + _rng.randf_range(-6, 6), _rng.randf_range(-4, 4), _rng.randf_range(-3, 3))


## A loose boulder.
func boulder(pos: Vector3, scale: float, color: Color = ROCK) -> void:
	box(Vector3(2.2, 1.6, 1.8) * scale, pos + Vector3(0, 0.6 * scale, 0), color.darkened(_rng.randf_range(0.0, 0.15)),
		_rng.randf_range(0, 90), _rng.randf_range(-10, 10), _rng.randf_range(-10, 10))


## A burnt-out truck: cover you can hide behind or jump onto the back of.
func wrecked_truck(pos: Vector3, rot_y: float) -> void:
	var dir := Vector3(sin(deg_to_rad(rot_y)), 0, cos(deg_to_rad(rot_y)))
	box(Vector3(2.3, 2.0, 2.0), pos + Vector3(0, 1.1, 0) + dir * 2.4, WRECK, rot_y)  # cab
	box(Vector3(2.4, 1.2, 4.2), pos + Vector3(0, 0.8, 0) - dir * 0.8, WRECK, rot_y)  # bed


## A warm hanging lamp so building interiors aren't pitch black.
func lamp(pos: Vector3, energy: float = 1.2, reach: float = 9.0) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color(1.0, 0.8, 0.55)
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = true
	add_child(light)
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	bulb.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.8, 0.55)
	glow.emission_energy_multiplier = 3.0
	bulb.material_override = glow
	bulb.position = pos
	add_child(bulb)


func crate(pos: Vector3, rot_y: float = 0.0, scale: float = 1.0) -> void:
	box(Vector3.ONE * 1.2 * scale, pos + Vector3(0, 0.6 * scale, 0), WOOD, rot_y)


## A U-shaped sandbag nest, open toward rot_y.
func sandbags(pos: Vector3, rot_y: float) -> void:
	var r := deg_to_rad(rot_y)
	var forward := Vector3(sin(r), 0, cos(r))
	var right := Vector3(cos(r), 0, -sin(r))
	box(Vector3(3.2, 0.9, 0.7), pos - forward * 1.2 + Vector3(0, 0.45, 0), SANDBAG, rot_y)
	box(Vector3(0.7, 0.9, 2.2), pos + right * 1.6 + Vector3(0, 0.45, 0), SANDBAG, rot_y)
	box(Vector3(0.7, 0.9, 2.2), pos - right * 1.6 + Vector3(0, 0.45, 0), SANDBAG, rot_y)


# --- Colors ---------------------------------------------------------------------------------
const SAND := Color(0.66, 0.57, 0.42)
const CONCRETE := Color(0.6, 0.59, 0.56)
const WALL := Color(0.72, 0.63, 0.5)
const WOOD := Color(0.5, 0.38, 0.25)
const ROOF := Color(0.45, 0.42, 0.38)
const ROCK := Color(0.55, 0.3, 0.2)
const WRECK := Color(0.28, 0.24, 0.2)
const SANDBAG := Color(0.62, 0.55, 0.4)
const METAL := Color(0.45, 0.47, 0.48)


## A 1 m checker pattern projected in world space, so distances are easy to judge.
func material(color: Color) -> StandardMaterial3D:
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


func _build_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_rotation
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top
	sky_material.sky_horizon_color = sky_horizon
	sky_material.ground_horizon_color = ground_horizon
	sky_material.ground_bottom_color = ground_horizon.darkened(0.5)
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
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_sky_affect = 0.15
	env.tonemap_exposure = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
