extends CharacterBody3D
## The local player: third-person movement, stances, aiming and shooting.
## The whole character (body, camera, gun, HUD) is built in code in _ready().

const HudScript := preload("res://scripts/hud.gd")

enum Stance { STAND, CROUCH, PRONE }

# --- Body and movement -------------------------------------------------------
const RADIUS := 0.35
const STANCE_NAMES := { Stance.STAND: "STANDING", Stance.CROUCH: "CROUCHED", Stance.PRONE: "PRONE" }
const STANCE_HEIGHT := { Stance.STAND: 1.8, Stance.CROUCH: 1.2, Stance.PRONE: 0.7 }
const STANCE_EYE := { Stance.STAND: 1.6, Stance.CROUCH: 1.05, Stance.PRONE: 0.45 }
const STANCE_SPEED := { Stance.STAND: 4.0, Stance.CROUCH: 2.0, Stance.PRONE: 0.8 }
const SPRINT_SPEED := 6.5
const AIM_MOVE_MULT := 0.6
const ACCEL := 30.0

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

var stance: Stance = Stance.STAND
var aiming := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _pitch := 0.0
var _recoil := 0.0  # extra upward view from firing; drifts back to zero
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
var _pivot: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _muzzle: Node3D
var _flash_light: OmniLight3D
var _hud: HudScript
var _tracer_material: StandardMaterial3D
var _impact_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("player")
	_build_body()
	_build_camera()
	_build_gun()
	_build_effect_materials()
	_hud = HudScript.new()
	add_child(_hud)
	_apply_stance(Stance.STAND)
	_pivot.position.y = STANCE_EYE[Stance.STAND]
	# The mouse stays free until the player clicks into the game (see the HUD's pause screen).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	# Never keep the mouse locked when the game window isn't the active window.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Building the character ---------------------------------------------------

func _build_body() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = RADIUS
	_collision = CollisionShape3D.new()
	_collision.shape = _capsule
	add_child(_collision)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.37, 0.25)  # olive drab
	mat.roughness = 0.8
	_body_mesh = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = RADIUS
	_body_mesh.mesh = mesh
	_body_mesh.material_override = mat
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
	_camera.current = true


func _build_gun() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.12)
	mat.metallic = 0.6
	mat.roughness = 0.4
	var gun := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.12, 0.75)
	gun.mesh = box
	gun.material_override = mat
	gun.position = Vector3(0.24, -0.22, -0.45)
	_pivot.add_child(gun)

	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.02, -0.4)
	gun.add_child(_muzzle)

	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.4)
	_flash_light.omni_range = 4.0
	_flash_light.light_energy = 0.0
	_muzzle.add_child(_flash_light)


func _build_effect_materials() -> void:
	_tracer_material = StandardMaterial3D.new()
	_tracer_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracer_material.albedo_color = Color(1.0, 0.85, 0.5)

	_impact_material = StandardMaterial3D.new()
	_impact_material.albedo_color = Color(0.08, 0.07, 0.06)
	_impact_material.roughness = 1.0


# --- Input ----------------------------------------------------------------------

## Mouse look is read here, before the on-screen interface sees the event,
## so no HUD element can ever swallow it.
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var motion := event as InputEventMouseMotion
	var sens := MOUSE_SENS * (AIM_SENS_MULT if aiming else 1.0)
	rotation.y -= motion.relative.x * sens
	_pitch = clampf(_pitch - motion.relative.y * sens, deg_to_rad(-80), deg_to_rad(70))


func _unhandled_input(event: InputEvent) -> void:
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
	elif not captured:
		return  # Paused: ignore gameplay keys.
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
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Vector2.ZERO
	if captured:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	aiming = captured and Input.is_action_pressed("aim")

	var sprinting := (
		Input.is_action_pressed("sprint") and stance == Stance.STAND
		and not aiming and input.y < 0.0
	)
	if sprinting and _reload_left > 0.0:
		sprinting = false

	var speed: float = SPRINT_SPEED if sprinting else STANCE_SPEED[stance]
	if aiming:
		speed *= AIM_MOVE_MULT

	if not is_on_floor():
		velocity.y -= _gravity * delta

	var target := transform.basis * Vector3(input.x, 0.0, input.y) * speed
	velocity.x = move_toward(velocity.x, target.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target.z, ACCEL * delta)
	move_and_slide()

	_update_camera(delta)
	_update_weapon(delta, sprinting, captured)


func _update_camera(delta: float) -> void:
	var k := 1.0 - exp(-CAMERA_SMOOTH * delta)
	var eye: float = STANCE_EYE[stance]
	_pivot.position.y = lerpf(_pivot.position.y, eye, k)
	_recoil = move_toward(_recoil, 0.0, RECOIL_RECOVERY * delta)
	_pivot.rotation.x = clampf(_pitch + _recoil, deg_to_rad(-80), deg_to_rad(70))
	_arm.spring_length = lerpf(_arm.spring_length, AIM_ARM_LENGTH if aiming else ARM_LENGTH, k)
	_arm.position.x = lerpf(_arm.position.x, SHOULDER * _shoulder_side, k)
	_camera.fov = lerpf(_camera.fov, AIM_FOV if aiming else FOV, k)


func _update_weapon(delta: float, sprinting: bool, captured: bool) -> void:
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
		captured and trigger and not _fire_locked and not sprinting
		and _reload_left <= 0.0 and _fire_cooldown <= 0.0
	)
	if can_fire:
		if _ammo > 0:
			_shoot(total_spread)
		else:
			_start_reload()

	_hud.update_state(
		_spread_to_pixels(total_spread), _ammo, _reserve,
		STANCE_NAMES[stance], _reload_left > 0.0, sprinting
	)


# --- Stances ---------------------------------------------------------------------

func _try_stance(new_stance: Stance) -> void:
	var new_height: float = STANCE_HEIGHT[new_stance]
	var current_height: float = STANCE_HEIGHT[stance]
	if new_height > current_height and not _can_fit(new_height):
		return  # Something is above us; we can't stand up here.
	_apply_stance(new_stance)


func _apply_stance(new_stance: Stance) -> void:
	stance = new_stance
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


# --- Shooting --------------------------------------------------------------------

func _shoot(spread_deg: float) -> void:
	_ammo -= 1
	_fire_cooldown = FIRE_INTERVAL
	_bloom = minf(_bloom + SHOT_BLOOM, MAX_SPREAD)

	# Bullets travel from the camera through the crosshair, randomly within the spread cone.
	var cam_basis := _camera.global_basis
	var forward := -cam_basis.z
	var dir := _random_direction_in_cone(forward, cam_basis, spread_deg)
	var cam_pos := _camera.global_position
	# Start the ray level with the player so we never hit things behind us.
	var start_dist := maxf((_pivot.global_position - cam_pos).dot(forward), 0.0)
	var from := cam_pos + dir * start_dist
	var to := from + dir * RANGE

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	var end_point := to
	if not hit.is_empty():
		end_point = hit["position"]
		var collider: Object = hit["collider"]
		if collider.has_method("take_hit"):
			var killed: bool = collider.take_hit(DAMAGE, end_point)
			_hud.show_hit_marker(killed)
		else:
			_spawn_impact(end_point, hit["normal"])

	_spawn_tracer(_muzzle.global_position, end_point)
	_muzzle_flash()

	# Recoil kicks the view up (then settles back) and slightly sideways.
	_recoil = minf(_recoil + RECOIL_PITCH * randf_range(0.7, 1.2), RECOIL_MAX)
	rotation.y += randf_range(-1.0, 1.0) * RECOIL_YAW


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
