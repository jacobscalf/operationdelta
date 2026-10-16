extends "res://scripts/maps/map_kit.gd"
## Range 01: the original 140 x 140 m gray-box test map. Practice puts targets here.

const DummyScript := preload("res://scripts/target_dummy.gd")


func _init() -> void:
	display_name = "Range 01"
	size = Vector2(140, 140)
	team_spawns = [
		[
			Vector3(0, 0.1, 55), Vector3(-4, 0.1, 57), Vector3(4, 0.1, 57), Vector3(-12, 0.1, 52),
			Vector3(12, 0.1, 52), Vector3(-8, 0.1, 61), Vector3(8, 0.1, 61), Vector3(0, 0.1, 63),
		],
		[
			Vector3(0, 0.1, -55), Vector3(-4, 0.1, -57), Vector3(4, 0.1, -57), Vector3(12, 0.1, -62),
			Vector3(-25, 0.1, -58), Vector3(25, 0.1, -58), Vector3(-8, 0.1, -62), Vector3(8, 0.1, -62),
		],
	]
	waypoints.assign([
		Vector3(0, 0, 30), Vector3(-15, 0, 30), Vector3(15, 0, 30), Vector3(-35, 0, 20),
		Vector3(35, 0, 20), Vector3(-12, 0, 10), Vector3(12, 0, 10), Vector3(0, 0, -12),
		Vector3(-15, 0, -20), Vector3(25, 0, -5), Vector3(-40, 0, -20), Vector3(40, 0, -30),
		Vector3(0, 0, -30), Vector3(-28, 0, -45), Vector3(15, 0, -50), Vector3(0, 0, -45),
		Vector3(-35, 0, 40), Vector3(35, 0, 40), Vector3(0, 0, 40), Vector3(-50, 0, 0),
		Vector3(50, 0, 0),
	])
	routes = [
		[Vector3(-40, 0, -40), Vector3(-40, 0, -20), Vector3(-38, 0, 0), Vector3(-35, 0, 20), Vector3(-30, 0, 40)],
		[Vector3(-10, 0, -30), Vector3(-12, 0, -8), Vector3(-12, 0, 15), Vector3(-5, 0, 35)],
		[Vector3(10, 0, -30), Vector3(12, 0, -10), Vector3(12, 0, 10), Vector3(5, 0, 35)],
		[Vector3(40, 0, -30), Vector3(42, 0, -10), Vector3(35, 0, 10), Vector3(35, 0, 30), Vector3(20, 0, 40)],
	]


func build() -> void:
	# Ground and boundary walls
	box(Vector3(140, 1, 140), Vector3(0, -0.5, 0), SAND)
	box(Vector3(140, 4, 1), Vector3(0, 2, -70), WALL)
	box(Vector3(140, 4, 1), Vector3(0, 2, 70), WALL)
	box(Vector3(1, 4, 140), Vector3(-70, 2, 0), WALL)
	box(Vector3(1, 4, 140), Vector3(70, 2, 0), WALL)

	# Spawn area: a 1 m low wall (crouch behind it to hide) and a crate stack
	box(Vector3(10, 1, 0.6), Vector3(0, 0.5, 45), CONCRETE)
	box(Vector3(1.2, 1.2, 1.2), Vector3(-8, 0.6, 42), WOOD)
	box(Vector3(1.2, 1.2, 1.2), Vector3(-6.7, 0.6, 42.3), WOOD, 15)
	box(Vector3(1.2, 1.2, 1.2), Vector3(-7.4, 1.8, 42.1), WOOD, 40)

	# Mid-field low walls
	box(Vector3(6, 1, 0.5), Vector3(-10, 0.5, 22), CONCRETE)
	box(Vector3(6, 1, 0.5), Vector3(12, 0.5, 25), CONCRETE, 20)
	box(Vector3(0.5, 1, 6), Vector3(18, 0.5, -2), CONCRETE)

	# Central building
	box(Vector3(12, 5, 9), Vector3(0, 2.5, 0), WALL)

	# West buildings with an alley between them
	box(Vector3(8, 4, 14), Vector3(-24, 2, -6), WALL)
	box(Vector3(8, 3, 8), Vector3(-24, 1.5, 14), WALL)

	# East: raised platform with a ramp up to it
	box(Vector3(8, 3, 8), Vector3(30, 1.5, -20), CONCRETE)
	box(Vector3(3, 0.3, 8.54), Vector3(30, 1.35, -12), CONCRETE, 0, 20.56)

	# Taller walls to peek around
	box(Vector3(5, 2.5, 0.5), Vector3(-6, 1.25, -18), WALL)
	box(Vector3(5, 2.5, 0.5), Vector3(8, 1.25, -22), WALL, -15)

	# North crate clusters
	box(Vector3(1.2, 1.2, 1.2), Vector3(-3, 0.6, -34), WOOD, 10)
	box(Vector3(1.2, 1.2, 1.2), Vector3(-1.7, 0.6, -34.4), WOOD)
	box(Vector3(2.4, 1.2, 1.2), Vector3(14, 0.6, -40), WOOD, -25)
	box(Vector3(1.2, 2.4, 1.2), Vector3(-20, 1.2, -42), WOOD)

	# Northwest watch tower
	box(Vector3(4, 6, 4), Vector3(-45, 3, -45), CONCRETE)

	if Network.mode == Network.Mode.PRACTICE:
		_spawn_targets()


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
