extends CharacterBody3D
## A soldier. Every player in a match is one of these, on every computer.
##
## Who controls what:
## - The player's own computer (its "authority") controls movement, aiming and stance,
##   and those are copied to everyone else by a MultiplayerSynchronizer.
## - The host decides whether shots hit, and owns health, deaths and respawns,
##   so a player can't cheat damage on their own machine.
## The whole character (body, camera, gun, name tag, HUD) is built in code in _ready().

const HudScript := preload("res://scripts/hud.gd")
const MatchScript := preload("res://scripts/match.gd")

enum Stance { STAND, CROUCH, PRONE }

# --- Body and movement -------------------------------------------------------
const RADIUS := 0.35
const STANCE_NAMES := { Stance.STAND: "STANDING", Stance.CROUCH: "CROUCHED", Stance.PRONE: "PRONE" }
const STANCE_HEIGHT := { Stance.STAND: 1.8, Stance.CROUCH: 1.3, Stance.PRONE: 0.7 }
const STANCE_EYE := { Stance.STAND: 1.6, Stance.CROUCH: 1.2, Stance.PRONE: 0.45 }
const STANCE_SPEED := { Stance.STAND: 4.0, Stance.CROUCH: 2.0, Stance.PRONE: 1.2 }
const SPRINT_SPEED := 6.5
const AIM_MOVE_MULT := 0.6
const ACCEL := 30.0
const AIR_ACCEL := 4.0  # little steering once you've left the ground
const JUMP_VELOCITY := 4.8  # just enough to clear a 1 m wall
const JUMP_COOLDOWN := 0.8
const LANDING_SLOW := 0.35  # seconds of reduced speed after landing
const LANDING_SPEED_MULT := 0.5

# --- Camera ------------------------------------------------------------------
const MOUSE_SENS := 0.0025
const AIM_SENS_MULT := 0.5
const ARM_LENGTH := 3.0
const AIM_ARM_LENGTH := 1.4
const FOV := 70.0
const AIM_FOV := 45.0
const SHOULDER := 0.55
const CAMERA_SMOOTH := 12.0

# --- Weapon (assault rifle) --------------------------------------------------
const DAMAGE := 25.0
const FIRE_INTERVAL := 0.1  # 600 rounds per minute
const MAG_SIZE := 30
const START_RESERVE := 300
const RELOAD_TIME := 2.2
const RANGE := 300.0
const RECOIL_PITCH := 0.008  # radians the view kicks up per shot
const RECOIL_YAW := 0.0025  # random sideways kick per shot
const RECOIL_MAX := 0.1  # the most the view can climb from recoil
const RECOIL_RECOVERY := 0.15  # radians per second the view settles back down
## Where bullets really leave from, relative to the camera pivot: right shoulder, slightly low.
const SHOULDER_OFFSET := Vector3(0.24, -0.12, 0.0)

# --- Accuracy (degrees, half-angle of the cone a bullet can land in) ---------
# The crosshair shows this cone. Like SOCOM, it tightens when you stay still,
# crouch, go prone or aim, and opens up when you move or keep firing.
const STANCE_SPREAD := { Stance.STAND: 1.0, Stance.CROUCH: 0.5, Stance.PRONE: 0.2 }
const AIM_SPREAD_MULT := 0.5
const MOVE_SPREAD := 2.0  # extra spread at full standing speed
const AIR_SPREAD := 3.0
const SHOT_BLOOM := 0.25  # extra spread added per shot
const BLOOM_RECOVERY := 4.0  # degrees per second
const SPREAD_SETTLE := 3.0  # how fast the crosshair tightens (higher = faster)
const MAX_SPREAD := 4.0
const MAX_IMPACTS := 64

# --- Health ------------------------------------------------------------------
const MAX_HEALTH := 100.0
const HEAD_SIZE := 0.3  # top 30 cm of the body counts as the head
const HEADSHOT_MULT := 4.0

## Uniform colors: Ops in olive drab, Terrorists in charcoal.
const TEAM_BODY_COLORS := [Color(0.33, 0.37, 0.25), Color(0.2, 0.19, 0.18)]
## Visual layer for everything a player draws, so the mini map's camera skips it.
const LAYER_DYNAMIC := 2

## Which side this player is on (Match.TEAM_OPS or Match.TEAM_TERRORISTS).
## Set by the host at spawn; can only change in the lobby (see set_team).
var team := 0
## When this player last fired (milliseconds), so the mini map can briefly reveal enemies.
var last_shot_msec := -100000

# --- Synced to every computer by the MultiplayerSynchronizer (see _build_sync) ---
var pitch := 0.0
var aiming := false
var display_name := "Player"
var stance: Stance = Stance.STAND:
	set(value):
		stance = value
		if is_node_ready():
			_apply_stance_shape()

# --- Set by the host through RPCs ---
var health := MAX_HEALTH
var alive := true

var _is_local := false
var _match: MatchScript
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _recoil := 0.0  # extra upward view from firing; drifts back to zero
var _jump_cooldown := 0.0
var _landing_slow := 0.0
var _was_on_floor := true
var _shoulder_side := 1.0
var _ammo := MAG_SIZE
var _reserve := START_RESERVE
var _reload_left := 0.0
var _fire_cooldown := 0.0
var _fire_locked := false
var _spread := 2.0
var _bloom := 0.0
var _impacts: Array[Node3D] = []

var _collision: CollisionShape3D
var _capsule: CapsuleShape3D
var _body_mesh: MeshInstance3D
var _body_material: StandardMaterial3D
var _pivot: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _gun: MeshInstance3D
var _muzzle: Node3D
var _flash_light: OmniLight3D
var _name_tag: Label3D
var _hud: HudScript
var _tracer_material: StandardMaterial3D
var _impact_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("players")
	_is_local = is_multiplayer_authority()
	_match = get_tree().current_scene.get_node("Match")
	_build_body()
	_build_camera()
	_build_gun()
	_build_name_tag()
	_build_effect_materials()
	_build_sync()
	_apply_stance_shape()
	_pivot.position.y = STANCE_EYE[stance]
	_apply_team_colors()
	if not alive:
		_hide_body()  # in the lobby, or joined mid-round: sit out until the next round

	if _is_local:
		add_to_group("local_player")
		display_name = Network.player_name
		_camera.current = true
		_hud = HudScript.new()
		add_child(_hud)
		if not alive and not _match.in_lobby():
			_hud.show_death("", -1.0)
		# The mouse stays free until the player clicks into the game (see the HUD's pause screen).
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	# Never keep the mouse locked when the game window isn't the active window.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _is_local:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Building the character ---------------------------------------------------

func _build_body() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_collision = CollisionShape3D.new()
	_collision.shape = _capsule
	add_child(_collision)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = TEAM_BODY_COLORS[0]
	_body_material.roughness = 0.8
	_body_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = RADIUS
	_body_mesh.mesh = mesh
	_body_mesh.material_override = _body_material
	_body_mesh.layers = LAYER_DYNAMIC
	add_child(_body_mesh)


func _build_camera() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)

	_arm = SpringArm3D.new()
	_arm.spring_length = ARM_LENGTH
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	_arm.shape = probe
	_arm.add_excluded_object(get_rid())
	_arm.position.x = SHOULDER
	_pivot.add_child(_arm)

	_camera = Camera3D.new()
	_camera.fov = FOV
	_arm.add_child(_camera)


func _build_gun() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.12)
	mat.metallic = 0.6
	mat.roughness = 0.4
	_gun = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.12, 0.75)
	_gun.mesh = box
	_gun.material_override = mat
	_gun.position = SHOULDER_OFFSET + Vector3(0, 0, -0.45)
	_gun.layers = LAYER_DYNAMIC
	_pivot.add_child(_gun)

	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.02, -0.4)
	_gun.add_child(_muzzle)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.omni_range = 4.0
	_flash_light.light_energy = 0.0
	_muzzle.add_child(_flash_light)


func _build_name_tag() -> void:
	_name_tag = Label3D.new()
	_name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_tag.font_size = 48
	_name_tag.pixel_size = 0.004
	_name_tag.outline_size = 12
	_name_tag.layers = LAYER_DYNAMIC
	_name_tag.visible = false
	add_child(_name_tag)


func _build_effect_materials() -> void:
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = Color(1.0, 0.85, 0.5)

	_impact_material = StandardMaterial3D.new()
	_impact_material.albedo_color = Color(0.08, 0.07, 0.06)
	_impact_material.roughness = 1.0


## Lists which properties get copied from this player's owner to every other computer.
func _build_sync() -> void:
	var config := SceneReplicationConfig.new()
	for property: String in [":position", ":rotation", ":pitch", ":stance", ":aiming"]:
		var path := NodePath("." + property)
		config.add_property(path)
		config.property_set_spawn(path, true)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var name_path := NodePath(".:display_name")
	config.add_property(name_path)
	config.property_set_spawn(name_path, true)
	config.property_set_replication_mode(name_path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = config
	sync.set_multiplayer_authority(get_multiplayer_authority())
	add_child(sync)


# --- Input (own player only) ---------------------------------------------------

## Mouse look is read here, before the on-screen interface sees the event,
## so no HUD element can ever swallow it.
func _input(event: InputEvent) -> void:
	if not _is_local or not event is InputEventMouseMotion:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	var sens := MOUSE_SENS * (AIM_SENS_MULT if aiming else 1.0)
	rotation.y -= motion.relative.x * sens
	pitch = clampf(pitch - motion.relative.y * sens, deg_to_rad(-80), deg_to_rad(70))


func _unhandled_input(event: InputEvent) -> void:
	if not _is_local or _match.in_lobby():
		return  # The lobby screen handles its own clicks.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion:
		return  # handled in _input()
	elif event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
		_fire_locked = true
	elif event is InputEventMouseButton and event.is_pressed() and not captured:
		# Clicking the pause screen (outside its buttons) resumes without firing a shot.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_fire_locked = true
	elif not captured or not alive:
		return  # Paused or dead: ignore gameplay keys.
	elif event.is_action_pressed("crouch"):
		_try_stance(Stance.STAND if stance == Stance.CROUCH else Stance.CROUCH)
	elif event.is_action_pressed("prone"):
		_try_stance(Stance.STAND if stance == Stance.PRONE else Stance.PRONE)
	elif event.is_action_pressed("reload"):
		_start_reload()
	elif event.is_action_pressed("switch_shoulder"):
		_shoulder_side = -_shoulder_side


# --- Every physics frame -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if not _is_local:
		_update_remote_visuals(delta)
		return

	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# During the countdown before a round you can look around but not move or shoot.
	var can_act := captured and alive and not _match.is_frozen()
	var input := Vector2.ZERO
	if can_act:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	aiming = can_act and Input.is_action_pressed("aim")

	var sprinting := (
		Input.is_action_pressed("sprint") and stance == Stance.STAND
		and not aiming and input.y < 0.0 and _reload_left <= 0.0
	)
	var speed: float = SPRINT_SPEED if sprinting else STANCE_SPEED[stance]
	if aiming:
		speed *= AIM_MOVE_MULT
	if _landing_slow > 0.0:
		speed *= LANDING_SPEED_MULT

	_jump_cooldown = maxf(_jump_cooldown - delta, 0.0)
	_landing_slow = maxf(_landing_slow - delta, 0.0)

	if alive:  # Dead bodies have no collision, so they must not fall.
		var on_floor := is_on_floor()
		if not on_floor:
			velocity.y -= _gravity * delta
		elif not _was_on_floor:
			_landing_slow = LANDING_SLOW
		_was_on_floor = on_floor

		if can_act and on_floor and Input.is_action_just_pressed("jump"):
			_try_jump()

		var target := transform.basis * Vector3(input.x, 0.0, input.y) * speed
		var accel := ACCEL if on_floor else AIR_ACCEL
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)
		move_and_slide()

	_update_camera(delta)
	_update_weapon(delta, sprinting, can_act)


func _update_camera(delta: float) -> void:
	var k := 1.0 - exp(-CAMERA_SMOOTH * delta)
	var eye: float = STANCE_EYE[stance]
	_pivot.position.y = lerpf(_pivot.position.y, eye, k)
	_recoil = move_toward(_recoil, 0.0, RECOIL_RECOVERY * delta)
	_pivot.rotation.x = clampf(pitch + _recoil, deg_to_rad(-80), deg_to_rad(70))
	_arm.spring_length = lerpf(_arm.spring_length, AIM_ARM_LENGTH if aiming else ARM_LENGTH, k)
	_arm.position.x = lerpf(_arm.position.x, SHOULDER * _shoulder_side, k)
	_camera.fov = lerpf(_camera.fov, AIM_FOV if aiming else FOV, k)


## Other players: their position arrives from the network; we just pose the gun and name tag.
func _update_remote_visuals(delta: float) -> void:
	var k := 1.0 - exp(-CAMERA_SMOOTH * delta)
	var eye: float = STANCE_EYE[stance]
	_pivot.position.y = lerpf(_pivot.position.y, eye, k)
	_pivot.rotation.x = pitch
	_name_tag.text = display_name
	_name_tag.position.y = float(STANCE_HEIGHT[stance]) + 0.35
	# Only teammates get name tags; spotting enemies is up to you.
	var me := get_tree().get_first_node_in_group("local_player")
	_name_tag.visible = alive and me != null and me.get("team") == team


func _update_weapon(delta: float, sprinting: bool, can_act: bool) -> void:
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

	# Accuracy: settle toward the stance's base spread, plus movement and bloom.
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	var move_ratio := clampf(ground_speed / float(STANCE_SPEED[Stance.STAND]), 0.0, 1.5)
	var target_spread: float = STANCE_SPREAD[stance] + MOVE_SPREAD * move_ratio
	if not is_on_floor():
		target_spread += AIR_SPREAD
	if aiming:
		target_spread *= AIM_SPREAD_MULT
	_spread = lerpf(_spread, target_spread, 1.0 - exp(-SPREAD_SETTLE * delta))
	_bloom = move_toward(_bloom, 0.0, BLOOM_RECOVERY * delta)
	var total_spread := minf(_spread + _bloom, MAX_SPREAD)

	# Firing
	var trigger := Input.is_action_pressed("fire")
	if not trigger:
		_fire_locked = false
	var can_fire := (
		can_act and trigger and not _fire_locked and not sprinting
		and _reload_left <= 0.0 and _fire_cooldown <= 0.0
	)
	if can_fire:
		if _ammo > 0:
			_shoot(total_spread)
		else:
			_start_reload()

	_hud.update_state(
		_spread_to_pixels(total_spread), _ammo, _reserve,
		STANCE_NAMES[stance], _reload_left > 0.0, sprinting or not alive, health
	)


# --- Jumping and stances ------------------------------------------------------------

## Like SOCOM: a short hop for getting over low walls. From crouch or prone, Space stands you up.
func _try_jump() -> void:
	if stance != Stance.STAND:
		_try_stance(Stance.STAND)
		return
	if _jump_cooldown > 0.0 or _landing_slow > 0.0:
		return
	velocity.y = JUMP_VELOCITY
	_jump_cooldown = JUMP_COOLDOWN


func _try_stance(new_stance: Stance) -> void:
	var new_height: float = STANCE_HEIGHT[new_stance]
	var current_height: float = STANCE_HEIGHT[stance]
	if new_height > current_height and not _can_fit(new_height):
		return  # Something is above us; we can't stand up here.
	stance = new_stance


func _apply_stance_shape() -> void:
	var height: float = STANCE_HEIGHT[stance]
	_capsule.height = height
	_collision.position.y = height * 0.5
	var mesh := _body_mesh.mesh as CapsuleMesh
	mesh.height = height
	_body_mesh.position.y = height * 0.5


func _can_fit(height: float) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = RADIUS * 0.95
	shape.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3(0, height * 0.5 + 0.05, 0))
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


# --- Shooting ----------------------------------------------------------------------

## Runs on the shooter's computer: works out where the crosshair points (with spread)
## and asks the host to fire the bullet.
func _shoot(spread_deg: float) -> void:
	_ammo -= 1
	_fire_cooldown = FIRE_INTERVAL
	_bloom = minf(_bloom + SHOT_BLOOM, MAX_SPREAD)

	var cam_basis := _camera.global_basis
	var forward := -cam_basis.z
	var dir := _random_direction_in_cone(forward, cam_basis, spread_deg)
	var cam_pos := _camera.global_position
	# Start the ray level with the player so we never hit things behind us.
	var start_dist := maxf((_pivot.global_position - cam_pos).dot(forward), 0.0)
	_server_fire.rpc_id(1, cam_pos + dir * start_dist, dir)

	# Recoil kicks the view up (then settles back) and slightly sideways.
	_recoil = minf(_recoil + RECOIL_PITCH * randf_range(0.7, 1.2), RECOIL_MAX)
	rotation.y += randf_range(-1.0, 1.0) * RECOIL_YAW


## Runs on the host: traces the bullet, applies damage, and tells everyone to draw it.
@rpc("any_peer", "call_local", "reliable")
func _server_fire(from: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	if sender != get_multiplayer_authority() or not alive:
		return  # Only a living player's own computer may fire their gun.
	if from.distance_to(_pivot.global_position) > 6.0:
		return  # Shot claims to start far from the player; ignore it.
	dir = dir.normalized()
	var space := get_world_3d().direct_space_state

	# 1) What is under the crosshair?
	var aim := _raycast(space, from, from + dir * RANGE)
	var aim_point: Vector3 = from + dir * RANGE
	if not aim.is_empty():
		aim_point = aim["position"]

	# 2) Can the gun actually reach that point from the shoulder?
	#    This stops you shooting through cover your camera can see over but your gun can't.
	var shoulder := _shoulder_point()
	var to := aim_point + (aim_point - shoulder).normalized() * 0.1
	var hit := _raycast(space, shoulder, to)

	var end_point := to
	var normal := Vector3.ZERO
	if not hit.is_empty():
		end_point = hit["position"]
		var target: Object = hit["collider"]
		if target.has_method("take_hit"):
			if _can_damage(target):
				var killed: bool = target.take_hit(DAMAGE, end_point, get_multiplayer_authority())
				_hit_confirmed.rpc_id(get_multiplayer_authority(), killed)
		else:
			normal = hit["normal"]
	_show_shot.rpc(end_point, normal)


## Teammates can only be hurt when the host turned friendly fire on.
func _can_damage(target: Object) -> bool:
	var target_team: Variant = target.get("team")
	return target_team == null or target_team != team or _match.friendly_fire


func _raycast(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return space.intersect_ray(query)


func _shoulder_point() -> Vector3:
	return _pivot.global_position + global_basis * Vector3(SHOULDER_OFFSET.x, SHOULDER_OFFSET.y, 0)


## Runs on everyone: draws the tracer, muzzle flash and bullet hole.
@rpc("any_peer", "call_local", "reliable")
func _show_shot(end_point: Vector3, impact_normal: Vector3) -> void:
	if not _from_host():
		return
	last_shot_msec = Time.get_ticks_msec()
	_spawn_tracer(_muzzle.global_position, end_point)
	_muzzle_flash()
	if impact_normal != Vector3.ZERO:
		_spawn_impact(end_point, impact_normal)


## Runs on the shooter: shows the hit marker.
@rpc("any_peer", "call_local", "reliable")
func _hit_confirmed(killed: bool) -> void:
	if _from_host() and _hud:
		_hud.show_hit_marker(killed)


func _random_direction_in_cone(forward: Vector3, basis: Basis, half_angle_deg: float) -> Vector3:
	# Most shots land near the center of the crosshair; only a few reach its edge.
	var radius := tan(deg_to_rad(half_angle_deg)) * randf()
	var angle := randf() * TAU
	var offset := basis.x * cos(angle) * radius + basis.y * sin(angle) * radius
	return (forward + offset).normalized()


func _spread_to_pixels(spread_deg: float) -> float:
	var half_height := get_viewport().get_visible_rect().size.y * 0.5
	return tan(deg_to_rad(spread_deg)) / tan(deg_to_rad(_camera.fov * 0.5)) * half_height


func _start_reload() -> void:
	if _reload_left > 0.0 or _ammo == MAG_SIZE or _reserve == 0:
		return
	_reload_left = RELOAD_TIME


func _finish_reload() -> void:
	_reload_left = 0.0
	var taken := mini(MAG_SIZE - _ammo, _reserve)
	_ammo += taken
	_reserve -= taken


# --- Health, death and respawn (decided by the host) --------------------------------

## Called on the host when a bullet hits this player. Returns true if it killed them.
func take_hit(damage: float, hit_point: Vector3, attacker_id: int = 0) -> bool:
	if not multiplayer.is_server() or not alive:
		return false
	var height: float = STANCE_HEIGHT[stance]
	var headshot := stance != Stance.PRONE and hit_point.y - global_position.y > height - HEAD_SIZE
	health = maxf(health - damage * (HEADSHOT_MULT if headshot else 1.0), 0.0)
	_set_health.rpc(health)
	if health > 0.0:
		return false
	_die.rpc(attacker_id)
	_match.on_player_killed(self)
	return true


@rpc("any_peer", "call_local", "reliable")
func _set_health(value: float) -> void:
	if not _from_host():
		return
	if value < health and _hud:
		_hud.show_damage()
	health = value


@rpc("any_peer", "call_local", "reliable")
func _die(killer_id: int) -> void:
	if not _from_host():
		return
	alive = false
	_collision.set_deferred("disabled", true)
	create_tween().tween_property(_body_mesh, "rotation:x", deg_to_rad(-90), 0.4)
	var killer_name := _name_of(killer_id)
	var killer := get_parent().get_node_or_null(str(killer_id))
	if killer and killer != self and killer.get("team") == team:
		Network.message.emit("%s killed teammate %s" % [killer_name, display_name])
	else:
		Network.message.emit("%s killed %s" % [killer_name, display_name])
	if _hud:
		var respawn_time := MatchScript.PRACTICE_RESPAWN_TIME if _match.respawns_enabled() else -1.0
		_hud.show_death(killer_name, respawn_time)
		_reload_left = 0.0


## Host only: bring this player back at a spawn point (used by the Match).
func respawn_at(spawn_point: Vector3) -> void:
	_respawn.rpc(spawn_point)


## Host only: tell a newly joined player this player's side and whether they're alive.
func send_life_to(peer_id: int) -> void:
	_sync_life.rpc_id(peer_id, alive, health, team)


@rpc("any_peer", "call_local", "reliable")
func _sync_life(is_alive: bool, value: float, new_team: int) -> void:
	if not _from_host():
		return
	health = value
	team = new_team
	_apply_team_colors()
	if not is_alive and alive:
		alive = false
		_hide_body()


## Host only: move this player to the other side (lobby only).
func set_team(new_team: int) -> void:
	_set_team.rpc(new_team)


@rpc("any_peer", "call_local", "reliable")
func _set_team(new_team: int) -> void:
	if not _from_host():
		return
	team = new_team
	_apply_team_colors()


func _apply_team_colors() -> void:
	_body_material.albedo_color = TEAM_BODY_COLORS[team]
	_name_tag.modulate = MatchScript.TEAM_COLORS[team]


## Host only: take this player off the field (going back to the lobby).
func leave_field() -> void:
	_leave_field.rpc()


@rpc("any_peer", "call_local", "reliable")
func _leave_field() -> void:
	if not _from_host():
		return
	alive = false
	_hide_body()
	if _hud:
		_hud.hide_death()


## Removes the body completely (for players sitting out a round they joined late).
func _hide_body() -> void:
	_collision.set_deferred("disabled", true)
	_body_mesh.visible = false
	_gun.visible = false


@rpc("any_peer", "call_local", "reliable")
func _respawn(spawn_point: Vector3) -> void:
	if not _from_host():
		return
	alive = true
	health = MAX_HEALTH
	_collision.set_deferred("disabled", false)
	_body_mesh.rotation.x = 0.0
	_body_mesh.visible = true
	_gun.visible = true
	if _is_local:
		global_position = spawn_point
		velocity = Vector3.ZERO
		stance = Stance.STAND
		_ammo = MAG_SIZE
		_reserve = START_RESERVE
		_recoil = 0.0
		_hud.hide_death()


func _from_host() -> bool:
	return multiplayer.get_remote_sender_id() in [0, 1]


func _name_of(peer_id: int) -> String:
	var other := get_parent().get_node_or_null(str(peer_id))
	if other and other.get("display_name") != null:
		return other.get("display_name")
	return "Someone"


# --- Effects ----------------------------------------------------------------------

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.1:
		return
	var tracer := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.015, 0.015, length)
	tracer.mesh = box
	tracer.material_override = _tracer_material
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(tracer)
	tracer.look_at_from_position((from + to) * 0.5, to, Vector3.UP)
	get_tree().create_timer(0.04).timeout.connect(tracer.queue_free)


func _spawn_impact(point: Vector3, normal: Vector3) -> void:
	var mark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	mark.mesh = sphere
	mark.material_override = _impact_material
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mark)
	mark.global_position = point + normal * 0.01
	_impacts.append(mark)
	if _impacts.size() > MAX_IMPACTS:
		_impacts.pop_front().queue_free()


func _muzzle_flash() -> void:
	_flash_light.light_energy = 4.0
	var tween := create_tween()
	tween.tween_property(_flash_light, "light_energy", 0.0, 0.06)
