extends "res://scripts/maps/map_kit.gd"
## Red Canyon: a 180 x 140 m desert basin walled in by red cliffs.
## Ops insert in the southwest; Terrorists hold a walled compound in the northeast.
## Three lanes: the west flank behind a rock spine, the central plaza around the
## two-story Market Hall, and the dry riverbed (wadi) along the east side.
## North is -Z. Coordinates are meters.

const SAND_RED := Color(0.74, 0.52, 0.36)
const ADOBE := Color(0.78, 0.62, 0.46)


func _init() -> void:
	display_name = "Red Canyon"
	surfaces[SAND_RED] = ["red_sand", 4.0]
	surfaces[ADOBE] = ["clay_plaster", 2.5]
	surfaces[ROCK] = ["rock_boulder_dry", 5.0, Color(1.0, 0.66, 0.5)]  # warm red canyon rock
	size = Vector2(180, 140)
	sun_rotation = Vector3(-38, -60, 0)
	sun_color = Color(1.0, 0.88, 0.74)
	sky_top = Color(0.32, 0.45, 0.62)
	sky_horizon = Color(0.88, 0.66, 0.5)
	ground_horizon = Color(0.7, 0.5, 0.38)
	fog_color = Color(0.86, 0.64, 0.5)
	fog_density = 0.0025

	team_spawns = [
		[  # Ops: southwest insertion point
			Vector3(-78, 0.1, 58), Vector3(-72, 0.1, 60), Vector3(-66, 0.1, 60), Vector3(-60, 0.1, 58),
			Vector3(-80, 0.1, 52), Vector3(-74, 0.1, 53), Vector3(-68, 0.1, 54), Vector3(-62, 0.1, 52),
		],
		[  # Terrorists: inside the compound courtyard
			Vector3(50, 0.1, -40), Vector3(56, 0.1, -44), Vector3(62, 0.1, -40), Vector3(68, 0.1, -44),
			Vector3(74, 0.1, -40), Vector3(80, 0.1, -44), Vector3(52, 0.1, -50), Vector3(78, 0.1, -52),
		],
	]
	waypoints.assign([
		Vector3(0, 0, 20), Vector3(-10, 0, -30), Vector3(25, 0, -30), Vector3(30, 0, 0),
		Vector3(15, 0, -12), Vector3(14, 0, 8), Vector3(-20, 0, -5), Vector3(-28, 0, 15),
		Vector3(-45, 0, 35), Vector3(5, 0, 22), Vector3(65, 0, 0), Vector3(65, 0, 30),
		Vector3(65, 0, -25), Vector3(-74, 0, 0), Vector3(-72, 0, -40), Vector3(-30, 0, -45),
		Vector3(20, 0, -55), Vector3(35, 0, 40), Vector3(0, 0, 55), Vector3(-35, 0, 55),
		Vector3(40, 0, -20), Vector3(28, 0, 25),
	])
	routes = [
		# West flank: out the west gate, along the north cliffs, down behind the rock spine.
		[Vector3(50, 0, -48), Vector3(49, 0, -50), Vector3(41, 0, -50), Vector3(20, 0, -56), Vector3(-10, 0, -56),
			Vector3(-40, 0, -50), Vector3(-72, 0, -44), Vector3(-74, 0, -10), Vector3(-74, 0, 20),
			Vector3(-72, 0, 45)],
		# Center: out the south gate, past the Market Hall, across the plaza.
		[Vector3(62, 0, -40), Vector3(62, 0, -33), Vector3(54, 0, -32), Vector3(35, 0, -20), Vector3(15, 0, -12),
			Vector3(14, 0, 8), Vector3(5, 0, 22), Vector3(-24, 0, 38), Vector3(-45, 0, 50),
			Vector3(-65, 0, 56)],
		# Wadi: down the dry riverbed on the east side, then west along the south cliffs.
		[Vector3(62, 0, -40), Vector3(62, 0, -33), Vector3(65, 0, -28), Vector3(65, 0, 0),
			Vector3(65, 0, 38), Vector3(65, 0, 44), Vector3(50, 0, 50), Vector3(20, 0, 55),
			Vector3(-20, 0, 58), Vector3(-55, 0, 60)],
		# Center-west: past the radio shack and lookout tower, by the ruined house.
		[Vector3(52, 0, -48), Vector3(49, 0, -50), Vector3(41, 0, -50), Vector3(15, 0, -30), Vector3(-12, 0, -22),
			Vector3(-20, 0, -5), Vector3(-28, 0, 15), Vector3(-45, 0, 35), Vector3(-48, 0, 42)],
	]


func build() -> void:
	ground(Vector2(190, 150), SAND_RED)  # rolling dunes, built last
	_build_cliffs()
	_build_compound()
	_build_market_hall()
	_build_lookout_tower()
	_build_radio_shack()
	_build_checkpoint()
	_build_fuel_depot()
	_build_wadi()
	_build_ruined_house()
	_build_cover()


## The canyon walls, with cut corners so the basin feels like a bowl, plus the rock
## spine on the west and the outcrop in the south that split the map into lanes.
func _build_cliffs() -> void:
	cliff([
		Vector2(-90, -55), Vector2(-75, -70), Vector2(75, -70), Vector2(90, -55),
		Vector2(90, 55), Vector2(78, 70), Vector2(-75, 70), Vector2(-90, 58), Vector2(-90, -55),
	], 14.0, 7.0)
	cliff([Vector2(-58, -38), Vector2(-55, -12), Vector2(-60, 16)], 7.0, 5.0)  # west rock spine
	cliff([Vector2(-15, 41), Vector2(5, 44)], 4.5, 4.0)  # south outcrop
	boulder(Vector3(-70, 0, -56), 2.0)
	boulder(Vector3(-60, 0, -61), 1.6)
	boulder(Vector3(-84, 0, 10), 1.8)
	boulder(Vector3(30, 0, 62), 1.5)


## Terrorist base: a walled courtyard with a barracks, a west gate and a south gate,
## and a guard tower outside overlooking the north path.
func _build_compound() -> void:
	var gate := 7.0
	wall(Vector2(45, -66), Vector2(45, -36), 3.0, ADOBE, [[1.0, gate, 0.0, 3.0]], 0.6)  # west wall, gate at z = -50
	wall(Vector2(45, -36), Vector2(87, -36), 3.0, ADOBE, [[-4.0, gate, 0.0, 3.0]], 0.6)  # south wall, gate at x = 62
	building(Vector3(66, 0, -60), Vector2(14, 7), 3.5, ADOBE, {
		"s": [door(-3.5), door(3.5), window(0)],
		"e": [window(0)],
		"w": [window(0)],
	})
	lamp(Vector3(62, 3.0, -60), 1.0)
	lamp(Vector3(70, 3.0, -60), 1.0)
	crate(Vector3(76, 0, -56))
	crate(Vector3(77.3, 0, -55.7), 20)
	crate(Vector3(76.6, 1.2, -55.9), 45)
	sandbags(Vector3(56, 0, -56), 180)

	# Guard tower outside the west wall: 2.6 m platform, ramp up from the south.
	box(Vector3(3, 0.3, 3), Vector3(40, 2.45, -60), CONCRETE)
	for corner: Vector2 in [Vector2(-1.3, -1.3), Vector2(1.3, -1.3), Vector2(-1.3, 1.3), Vector2(1.3, 1.3)]:
		box(Vector3(0.3, 2.3, 0.3), Vector3(40 + corner.x, 1.15, -60 + corner.y), WOOD)
	box(Vector3(3, 1.0, 0.2), Vector3(40, 3.1, -61.4), WOOD)
	box(Vector3(0.2, 1.0, 3), Vector3(38.6, 3.1, -60), WOOD)
	box(Vector3(0.2, 1.0, 3), Vector3(41.4, 3.1, -60), WOOD)
	ramp(Vector3(40, 0, -53.5), Vector3(40, 2.6, -58.5), 1.6, WOOD)


## The heart of the map: a two-story hall with doors on three sides, windows on both
## floors, and a ramp along the inside of the west wall up to the upper floor.
func _build_market_hall() -> void:
	building(Vector3(0, 0, -2), Vector2(20, 14), 7.0, WALL, {
		"n": [door(0), window(-6), window(6), window(-6, 4.4), window(0, 4.4), window(6, 4.4)],
		"s": [door(-4), door(5), window(1.5), window(-6, 4.4), window(0, 4.4), window(6, 4.4)],
		"e": [door(1), window(-4), window(-4, 4.4), window(3, 4.4)],
		"w": [window(-5), window(-5, 4.4), window(2, 4.4)],
	})
	# Upper floor (top at 3.4 m), leaving a gap above the ramp.
	box(Vector3(17.5, 0.25, 14), Vector3(1.25, 3.275, -2), CONCRETE)
	box(Vector3(2.5, 0.25, 5), Vector3(-8.75, 3.275, -6.5), CONCRETE)
	ramp(Vector3(-8.5, 0, 4.2), Vector3(-8.5, 3.4, -4.0), 1.9)
	# A few things to hide behind inside.
	crate(Vector3(4, 0, -6))
	crate(Vector3(5.3, 0, -6.2), 25)
	box(Vector3(4, 1.0, 1.2), Vector3(2, 0.5, 1.5), WOOD)  # market counter
	crate(Vector3(6, 3.4, 2))
	lamp(Vector3(-3, 2.8, -2))
	lamp(Vector3(5, 2.8, -2))
	lamp(Vector3(-3, 6.4, -2))
	lamp(Vector3(5, 6.4, -2))


## Lookout tower: a 7 m platform with a waist-high wall, reached by one long ramp.
func _build_lookout_tower() -> void:
	var c := Vector3(-28, 0, -32)
	for corner: Vector2 in [Vector2(-2.3, -2.3), Vector2(2.3, -2.3), Vector2(-2.3, 2.3), Vector2(2.3, 2.3)]:
		box(Vector3(0.4, 7.0, 0.4), c + Vector3(corner.x, 3.5, corner.y), METAL)
	box(Vector3(5, 0.3, 5), c + Vector3(0, 6.85, 0), CONCRETE)
	box(Vector3(5, 1.0, 0.2), c + Vector3(0, 7.5, -2.4), METAL)  # north wall
	box(Vector3(0.2, 1.0, 5), c + Vector3(-2.4, 7.5, 0), METAL)  # west wall
	box(Vector3(0.2, 1.0, 5), c + Vector3(2.4, 7.5, 0), METAL)  # east wall
	box(Vector3(1.6, 1.0, 0.2), c + Vector3(-1.7, 7.5, 2.4), METAL)  # south wall, left of the ramp
	box(Vector3(1.6, 1.0, 0.2), c + Vector3(1.7, 7.5, 2.4), METAL)  # south wall, right of the ramp
	ramp(Vector3(-28, 0, -17), Vector3(-28, 7.0, -29.5), 1.6, METAL)


func _build_radio_shack() -> void:
	building(Vector3(5, 0, -40), Vector2(6, 5), 3.0, CONCRETE, {
		"s": [door(0)],
		"n": [window(1.5)],
		"e": [window(0)],
		"w": [window(0)],
	})
	lamp(Vector3(5, 2.6, -40), 0.8, 6.0)
	cylinder(0.15, 14.0, Vector3(9.5, 0, -43), METAL)  # antenna mast
	box(Vector3(1.5, 0.8, 1.0), Vector3(9.5, 0.4, -41.5), METAL)  # generator


## South checkpoint: a guard booth, a road barrier with a gap, and a sandbag nest.
func _build_checkpoint() -> void:
	building(Vector3(-22, 0, 30), Vector2(3, 3), 2.6, CONCRETE, {
		"s": [door(0, 1.2)],
		"n": [window(0, 1.0, 1.4)],
		"e": [window(0, 1.0, 1.4)],
		"w": [window(0, 1.0, 1.4)],
	})
	box(Vector3(3, 0.9, 0.6), Vector3(-30, 0.45, 26), CONCRETE)
	box(Vector3(3, 0.9, 0.6), Vector3(-14, 0.45, 26), CONCRETE)
	sandbags(Vector3(-2, 0, 34), 0)


## Fuel depot: an office you can climb onto, and two big fuel tanks.
func _build_fuel_depot() -> void:
	building(Vector3(38, 0, 15), Vector2(8, 6), 3.2, CONCRETE, {
		"n": [door(-1), window(2)],
		"w": [door(0)],
		"e": [window(0)],
		"s": [window(-2.5)],
	})
	ramp(Vector3(38, 0, 26), Vector3(38, 3.5, 18.2), 1.8)  # up to the roof
	lamp(Vector3(38, 2.8, 15), 0.8, 7.0)
	cylinder(2.5, 5.0, Vector3(48, 0, 2), METAL)
	cylinder(2.5, 5.0, Vector3(48, 0, -6), METAL)
	box(Vector3(0.4, 0.4, 8), Vector3(44.5, 0.6, -2), METAL)  # pipe
	sandbags(Vector3(42, 0, -12), 180)


## The wadi: a dry riverbed lane along the east side, between rock banks too tall to
## jump. One gap in the west bank lets you cross to the fuel depot.
func _build_wadi() -> void:
	# (Rock pieces overlap past their end points by ~3.5 m, so the ends here are pulled in.)
	cliff([Vector2(58, -27), Vector2(58, -1)], 2.0, 3.0)
	cliff([Vector2(58, 12), Vector2(58, 37)], 2.0, 3.0)
	cliff([Vector2(72, -27), Vector2(72, 37)], 4.0, 3.0)
	boulder(Vector3(61, 0, -10), 1.0)
	boulder(Vector3(68, 0, 15), 1.2)
	boulder(Vector3(62, 0, 30), 0.9)


## A bombed-out house near the west spine: broken walls of different heights, no roof.
func _build_ruined_house() -> void:
	box(Vector3(10, 0.1, 8), Vector3(-42, 0.05, 0), CONCRETE)
	wall(Vector2(-47, -4), Vector2(-37, -4), 2.8, WALL, [window(-2), door(2.5)])
	wall(Vector2(-47, -4), Vector2(-47, 4), 1.4, WALL)
	wall(Vector2(-37, -4), Vector2(-37, 1), 2.2, WALL)
	wall(Vector2(-47, 4), Vector2(-41, 4), 1.0, WALL)
	crate(Vector3(-43, 0, 1), 30)
	boulder(Vector3(-39, 0, 3), 0.5, WALL)


## Cover scattered across the open ground: wrecked trucks, low walls, crates, sandbags.
func _build_cover() -> void:
	wrecked_truck(Vector3(16, 0, 22), 70)
	wrecked_truck(Vector3(-14, 0, 14), -20)
	wrecked_truck(Vector3(-55, 0, 46), 25)  # Ops insertion point
	wrecked_truck(Vector3(-82, 0, 42), -15)
	box(Vector3(5, 1, 0.5), Vector3(8, 0.5, 30), CONCRETE, 10)
	box(Vector3(5, 1, 0.5), Vector3(-4, 0.5, -20), CONCRETE, -5)
	box(Vector3(0.5, 1, 5), Vector3(20, 0.5, -6), CONCRETE)
	box(Vector3(6, 1, 0.5), Vector3(-66, 0.5, 30), CONCRETE, 15)
	crate(Vector3(24, 0, -10))
	crate(Vector3(25.3, 0, -9.6), 20)
	crate(Vector3(24.6, 1.2, -9.8), 40)
	crate(Vector3(-18, 0, -27))
	crate(Vector3(-16.7, 0, -27.3), 15)
	sandbags(Vector3(25, 0, -25), 180)
	sandbags(Vector3(-36, 0, -40), 180)
	crate(Vector3(30, 0, 45), 10)
	crate(Vector3(-30, 0, 62), 30)
	# Oil drums
	for spot: Vector3 in [Vector3(51, 0, 8), Vector3(51.7, 0, 8.6), Vector3(51.2, 0, 9.4), Vector3(-6, 0, 8),
			Vector3(-6.7, 0, 8.4), Vector3(80, 0, -48), Vector3(80.6, 0, -47.3), Vector3(-63, 0, 47),
			Vector3(12, 0, -36), Vector3(-41, 0, 2.5)]:
		barrel(spot)
	barrel(Vector3(52.5, 0, 7.5), true)
	barrel(Vector3(-5, 0, 9.5), true)
	barrel(Vector3(13, 0, -35), true)
