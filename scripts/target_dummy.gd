extends StaticBody3D
## Practice target. Takes damage, flashes when hit, falls over, then gets back up.
## Headshots (above HEAD_HEIGHT) do 2.5x damage, same as on players.

const MAX_HEALTH := 100.0
const HEAD_HEIGHT := 1.5
const HEADSHOT_MULT := 2.5  # same as players
const RESPAWN_TIME := 3.0
const BASE_COLOR := Color(0.6, 0.18, 0.15)

## If above zero, the target slides side to side this many meters.
var strafe_distance := 0.0
var strafe_speed := 1.2

var _health := MAX_HEALTH
var _dead := false
var _start := Vector3.ZERO
var _time := 0.0
var _material := StandardMaterial3D.new()
var _shape := CollisionShape3D.new()


func _ready() -> void:
	_start = position
	_time = randf() * TAU

	_material.albedo_color = BASE_COLOR
	_material.roughness = 0.7
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	mesh.mesh = capsule
	mesh.material_override = _material
	mesh.position.y = 0.9
	mesh.layers = 2  # keep targets off the mini map picture
	add_child(mesh)

	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	_shape.shape = shape
	_shape.position.y = 0.9
	add_child(_shape)


func _physics_process(delta: float) -> void:
	if strafe_distance <= 0.0 or _dead:
		return
	_time += delta * strafe_speed
	position = _start + Vector3(sin(_time) * strafe_distance, 0, 0)


## Called by the player's bullets. Returns true if this hit killed the target.
func take_hit(damage: float, hit_point: Vector3, _attacker_id: int = 0, _zone: String = "") -> bool:
	if _dead:
		return false
	var is_headshot := hit_point.y - global_position.y > HEAD_HEIGHT
	_health -= damage * (HEADSHOT_MULT if is_headshot else 1.0)

	_material.albedo_color = Color.WHITE
	create_tween().tween_property(_material, "albedo_color", BASE_COLOR, 0.15)

	if _health <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	_dead = true
	_shape.set_deferred("disabled", true)
	var tween := create_tween()
	tween.tween_property(self, "rotation:x", deg_to_rad(-90), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(RESPAWN_TIME).timeout
	rotation.x = 0.0
	_health = MAX_HEALTH
	_dead = false
	_shape.set_deferred("disabled", false)
