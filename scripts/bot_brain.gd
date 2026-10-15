extends Node
## Simple AI for a bot soldier. Runs only on the host, as a child of the bot's player node.
## Every physics frame think() decides where to walk, where to look, and when to shoot.
##
## Behaviour: wander between open spots on the map. When an enemy is in plain sight,
## stop, crouch, turn toward them, wait a moment to "react", then fire short bursts
## with some built-in inaccuracy so it can be beaten.

const STAND := 0
const CROUCH := 1

## Open spots on Range 01 the bot wanders between.
const WAYPOINTS: Array[Vector3] = [
	Vector3(0, 0, 30), Vector3(-15, 0, 30), Vector3(15, 0, 30), Vector3(-35, 0, 20),
	Vector3(35, 0, 20), Vector3(-12, 0, 10), Vector3(12, 0, 10), Vector3(0, 0, -12),
	Vector3(-15, 0, -20), Vector3(25, 0, -5), Vector3(-40, 0, -20), Vector3(40, 0, -30),
	Vector3(0, 0, -30), Vector3(-28, 0, -45), Vector3(15, 0, -50), Vector3(0, 0, -45),
	Vector3(-35, 0, 40), Vector3(35, 0, 40), Vector3(0, 0, 40), Vector3(-50, 0, 0),
	Vector3(50, 0, 0),
]

const SIGHT_RANGE := 90.0
const LOOK_INTERVAL := 0.2  # how often it checks who it can see
const REACTION_TIME := 0.5  # delay between spotting you and the first shot
const AIM_ERROR_DEG := 2.5  # how far off each shot can be
const TURN_SPEED := 5.0  # radians per second
const ON_TARGET := 0.08  # radians: close enough to start shooting
const SHOT_GAP := 0.13  # seconds between shots in a burst
const BURST_SHOTS := Vector2i(3, 6)
const BURST_PAUSE := Vector2(0.4, 0.9)
const STUCK_CHECK := 1.5  # seconds

## The bot's player node (a CharacterBody3D using player.gd). Set by the player.
var body: CharacterBody3D
## Set for one frame when the bot wants to hop over something.
var wants_jump := false

var _target: Node3D
var _seen_for := 0.0
var _look_timer := 0.0
var _burst_left := 0
var _shot_timer := 0.0
var _goal := Vector3.INF
var _stuck_timer := 0.0
var _last_position := Vector3.ZERO
var _aim_error := 0.0


## Returns the movement input (x = right, y = back) just like WASD would.
func think(delta: float) -> Vector2:
	wants_jump = false

	_look_timer -= delta
	if _look_timer <= 0.0:
		_look_timer = LOOK_INTERVAL
		var seen := _find_target()
		if seen != _target:
			_seen_for = 0.0
			_burst_left = 0
		_target = seen

	if _target:
		_seen_for += delta
		_aim_at(_target.global_position + Vector3(0, 1.0, 0), delta)
		if body.get("stance") == STAND:
			body.call("_try_stance", CROUCH)
		_shoot(delta)
		return Vector2.ZERO

	_seen_for = 0.0
	if body.get("stance") != STAND:
		body.call("_try_stance", STAND)
	return _walk(delta)


# --- Seeing and shooting ---------------------------------------------------------------

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_distance := SIGHT_RANGE
	for other: Node3D in get_tree().get_nodes_in_group("players"):
		if other == body or not other.get("alive") or other.get("team") == body.get("team"):
			continue
		var distance := body.global_position.distance_to(other.global_position)
		if distance < best_distance and _can_see(other):
			best = other
			best_distance = distance
	return best


func _can_see(other: Node3D) -> bool:
	var from := _eye()
	var query := PhysicsRayQueryParameters3D.create(from, other.global_position + Vector3(0, 1.0, 0))
	query.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["collider"] == other


func _aim_at(point: Vector3, delta: float) -> void:
	var to_point := point - _eye()
	var wanted_yaw := atan2(-to_point.x, -to_point.z)
	body.rotation.y = rotate_toward(body.rotation.y, wanted_yaw, TURN_SPEED * delta)
	_aim_error = absf(angle_difference(body.rotation.y, wanted_yaw))
	var wanted_pitch := atan2(to_point.y, Vector2(to_point.x, to_point.z).length())
	body.set("pitch", move_toward(body.get("pitch"), wanted_pitch, TURN_SPEED * delta))


func _shoot(delta: float) -> void:
	_shot_timer -= delta
	if _seen_for < REACTION_TIME or _aim_error > ON_TARGET or _shot_timer > 0.0:
		return
	if _burst_left <= 0:
		_burst_left = randi_range(BURST_SHOTS.x, BURST_SHOTS.y)
		_shot_timer = randf_range(BURST_PAUSE.x, BURST_PAUSE.y)
		return
	var from := _eye()
	var forward := (_target.global_position + Vector3(0, 1.0, 0) - from).normalized()
	var dir: Vector3 = body.call("_random_direction_in_cone", forward, Basis.looking_at(forward), AIM_ERROR_DEG)
	body.call("fire_bullet", from, dir)
	_burst_left -= 1
	_shot_timer = SHOT_GAP


func _eye() -> Vector3:
	return (body.get("_pivot") as Node3D).global_position


# --- Wandering -----------------------------------------------------------------------------

func _walk(delta: float) -> Vector2:
	if _goal == Vector3.INF or _flat_distance(body.global_position, _goal) < 2.0:
		_pick_new_goal()

	# Every so often, check we're actually getting somewhere; if not, hop and try elsewhere.
	_stuck_timer += delta
	if _stuck_timer >= STUCK_CHECK:
		if _flat_distance(body.global_position, _last_position) < 0.5:
			wants_jump = true
			_pick_new_goal()
		_stuck_timer = 0.0
		_last_position = body.global_position

	var to_goal := _goal - body.global_position
	var wanted_yaw := atan2(-to_goal.x, -to_goal.z)
	body.rotation.y = rotate_toward(body.rotation.y, wanted_yaw, TURN_SPEED * delta)
	body.set("pitch", move_toward(body.get("pitch"), 0.0, TURN_SPEED * delta))
	# Walk forward once roughly facing the goal; turn on the spot otherwise.
	if absf(angle_difference(body.rotation.y, wanted_yaw)) < 0.5:
		return Vector2(0, -1)
	return Vector2.ZERO


func _pick_new_goal() -> void:
	var choice := WAYPOINTS[randi() % WAYPOINTS.size()]
	while choice == _goal:
		choice = WAYPOINTS[randi() % WAYPOINTS.size()]
	_goal = choice


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
