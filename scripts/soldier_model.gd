extends Node3D
## The visible soldier: an animated Mixamo character holding a rifle.
## The player script calls update() every frame with what the soldier is doing, and this
## picks and blends the animations. Works the same for you, other players and bots.

const ANIMATIONS := preload("res://assets/characters/soldier_anims.res")
const MODELS := [
	preload("res://assets/characters/ops_soldier.scn"),
	preload("res://assets/characters/terrorist_soldier.scn"),
]
const AimModifierScript := preload("res://scripts/aim_modifier.gd")

const STANCE_INPUTS := ["stand", "crouch", "prone"]  # matches Player.Stance order
## Divides movement speed (m/s) into blend-space units: 1 = walk, 2 = run, 3 = sprint.
const STAND_SPEED_UNIT := 2.0
const CROUCH_SPEED_UNIT := 2.0
const PRONE_SPEED_UNIT := 1.2
## Bones the reload animation is allowed to move (the legs keep doing their own thing).
const UPPER_BODY := ["Spine", "Neck", "Head", "Shoulder", "Arm", "Hand"]
const BLEND_SMOOTH := 10.0

## Physics layer (value) for hit zones. Bullets look for these; nothing walks into them.
const HITBOX_LAYER := 4
## Hit zones: bone, its child bone (sets the length), radius, zone name.
const HITBOXES := [
	["mixamorig_Hips", "mixamorig_Spine1", 0.17, "body"],
	["mixamorig_Spine1", "mixamorig_Neck", 0.18, "body"],
	["mixamorig_LeftArm", "mixamorig_LeftForeArm", 0.065, "limb"],
	["mixamorig_LeftForeArm", "mixamorig_LeftHand", 0.055, "limb"],
	["mixamorig_RightArm", "mixamorig_RightForeArm", 0.065, "limb"],
	["mixamorig_RightForeArm", "mixamorig_RightHand", 0.055, "limb"],
	["mixamorig_LeftUpLeg", "mixamorig_LeftLeg", 0.09, "limb"],
	["mixamorig_LeftLeg", "mixamorig_LeftFoot", 0.07, "limb"],
	["mixamorig_RightUpLeg", "mixamorig_RightLeg", 0.09, "limb"],
	["mixamorig_RightLeg", "mixamorig_RightFoot", 0.07, "limb"],
]
const HEAD_RADIUS := 0.13

var _model: Node3D
var _hitboxes: Array[Area3D] = []
var _tree: AnimationTree
var _aim: AimModifierScript
var _gun: MeshInstance3D
var _muzzle: Node3D
var _blend := Vector2.ZERO
var _dead := false
var _last_stance := -1
var _airborne := false


## team: 0 = Ops, 1 = Terrorists. hit_owner: the player that bullets hitting this body damage.
func setup(team: int, hit_owner: Node) -> void:
	if _model:
		_model.queue_free()
	if _gun:
		_gun.queue_free()
	_hitboxes.clear()
	_model = MODELS[team].instantiate()
	_model.rotation.y = PI  # Mixamo characters face +Z; Godot's forward is -Z
	add_child(_model)
	for mesh: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		mesh.layers = 2  # keep soldiers off the mini map picture

	var skeleton: Skeleton3D = _model.find_children("*", "Skeleton3D", true, false)[0]
	_build_gun()
	_aim = AimModifierScript.new()
	_aim.gun = _gun
	skeleton.add_child(_aim)
	_build_tree(skeleton)
	_build_hitboxes(skeleton, hit_owner)
	_last_stance = -1
	_dead = false


## The physics ids of this soldier's hit zones (so a soldier's own shots can skip them).
func hitbox_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for area in _hitboxes:
		rids.append(area.get_rid())
	return rids


func set_hitboxes_enabled(enabled: bool) -> void:
	for area in _hitboxes:
		area.set_deferred("collision_layer", HITBOX_LAYER if enabled else 0)


## Invisible shapes riding on the skeleton's bones, so hits land where the body really is,
## whatever pose the animation has it in. Each remembers its owner and which zone it is.
func _build_hitboxes(skeleton: Skeleton3D, hit_owner: Node) -> void:
	for spec: Array in HITBOXES:
		var bone := skeleton.find_bone(spec[0])
		var end_bone := skeleton.find_bone(spec[1])
		if bone < 0 or end_bone < 0:
			continue
		# Length from this bone to the end bone, measured on the rest pose.
		var start := skeleton.get_bone_global_rest(bone).origin
		var length := start.distance_to(skeleton.get_bone_global_rest(end_bone).origin)
		var capsule := CapsuleShape3D.new()
		capsule.radius = spec[2]
		capsule.height = maxf(length + capsule.radius * 2.0, capsule.radius * 2.0)
		# Mixamo bones point along their local +Y toward the next bone.
		var to_end := skeleton.get_bone_global_rest(bone).basis.inverse() * \
			(skeleton.get_bone_global_rest(end_bone).origin - start)
		var shape_transform := Transform3D(_basis_along(to_end.normalized()), to_end * 0.5)
		_add_hitbox(skeleton, spec[0], capsule, shape_transform, spec[3], hit_owner)

	var head := skeleton.find_bone("mixamorig_Head")
	if head >= 0:
		var sphere := SphereShape3D.new()
		sphere.radius = HEAD_RADIUS
		_add_hitbox(skeleton, "mixamorig_Head", sphere, Transform3D(Basis(), Vector3(0, 0.09, 0.02)),
			"head", hit_owner)


func _add_hitbox(skeleton: Skeleton3D, bone_name: String, shape: Shape3D, shape_transform: Transform3D,
		zone: String, hit_owner: Node) -> void:
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	skeleton.add_child(attachment)
	var area := Area3D.new()
	area.collision_layer = HITBOX_LAYER
	area.collision_mask = 0
	area.monitoring = false
	area.set_meta("hit_owner", hit_owner)
	area.set_meta("zone", zone)
	attachment.add_child(area)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = shape_transform
	area.add_child(collision)
	_hitboxes.append(area)


## A basis whose Y axis points along dir (capsules are tall along Y).
func _basis_along(dir: Vector3) -> Basis:
	var y := dir if dir.length() > 0.001 else Vector3.UP
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	return Basis(x, y, x.cross(y).normalized()).orthonormalized()


## Called every frame by the player.
## local_velocity: movement relative to where the soldier faces (x = right, z = back).
func update(delta: float, local_velocity: Vector3, stance: int, airborne: bool, pitch: float) -> void:
	if not _tree:
		return
	_aim.pitch = pitch if not _dead else 0.0

	if stance != _last_stance:
		_last_stance = stance
		_tree.set("parameters/stance/transition_request", STANCE_INPUTS[stance])
		_tree.set("parameters/reload_kind/transition_request", STANCE_INPUTS[stance])

	if airborne != _airborne and stance == 0:
		_airborne = airborne
		_tree.set("parameters/air/transition_request", "air" if airborne else "ground")

	var unit: float = [STAND_SPEED_UNIT, CROUCH_SPEED_UNIT, PRONE_SPEED_UNIT][stance]
	var target := Vector2(local_velocity.x, -local_velocity.z) / unit
	_blend = _blend.lerp(target, 1.0 - exp(-BLEND_SMOOTH * delta))
	_tree.set("parameters/stand/blend_position", _blend.limit_length(3.0))
	_tree.set("parameters/crouch/blend_position", _blend.limit_length(1.0))
	_tree.set("parameters/prone/blend_position", clampf(_blend.y, -1.0, 1.0))


func play_reload() -> void:
	if _tree and not _dead:
		_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func play_death(stance: int) -> void:
	if not _tree:
		return
	_dead = true
	_tree.set("parameters/reload/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	var death := "front" if randf() < 0.5 else "back"
	if stance == 1:
		death = "crouch"
	elif stance == 2:
		death = "prone"
	_tree.set("parameters/life/transition_request", "dead_" + death)


func revive() -> void:
	if not _tree:
		return
	_dead = false
	_tree.set("parameters/life/transition_request", "alive")


## Where tracers and muzzle flashes should start.
func muzzle_position() -> Vector3:
	return _muzzle.global_position if _muzzle else global_position + Vector3.UP * 1.4


func _build_gun() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.1)
	mat.metallic = 0.6
	mat.roughness = 0.45
	_gun = MeshInstance3D.new()
	_gun.layers = 2
	add_child(_gun)
	# Simple rifle shape along -Z (the way look_at points): stock behind the right hand,
	# barrel reaching past the left hand.
	var parts := [
		[Vector3(0.05, 0.09, 0.55), Vector3(0, 0.01, -0.12)],  # body
		[Vector3(0.03, 0.03, 0.35), Vector3(0, 0.03, -0.55)],  # barrel
		[Vector3(0.045, 0.12, 0.2), Vector3(0, -0.01, 0.22)],  # stock
		[Vector3(0.035, 0.12, 0.05), Vector3(0, -0.08, -0.15)],  # magazine
	]
	for part: Array in parts:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[0]
		piece.mesh = box
		piece.position = part[1]
		piece.material_override = mat
		piece.layers = 2
		_gun.add_child(piece)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.03, -0.73)
	_gun.add_child(_muzzle)


func _build_tree(skeleton: Skeleton3D) -> void:
	if _tree:
		_tree.queue_free()
	_tree = AnimationTree.new()
	_tree.add_animation_library("", ANIMATIONS)
	_model.add_child(_tree)
	_tree.root_node = _tree.get_path_to(_model)

	var root := AnimationNodeBlendTree.new()

	# Standing: idle in the middle, walk at 1, run at 2, sprint forward at 3.
	var stand := AnimationNodeBlendSpace2D.new()
	stand.min_space = Vector2(-3, -3)
	stand.max_space = Vector2(3, 3)
	for point: Array in [
		["idle", Vector2.ZERO],
		["walk_forward", Vector2(0, 1)], ["walk_backward", Vector2(0, -1)],
		["walk_left", Vector2(-1, 0)], ["walk_right", Vector2(1, 0)],
		["run_forward", Vector2(0, 2)], ["run_backward", Vector2(0, -2)],
		["run_left", Vector2(-2, 0)], ["run_right", Vector2(2, 0)],
		["sprint", Vector2(0, 3)],
	]:
		stand.add_blend_point(_clip(point[0]), point[1], -1, point[0])
	root.add_node("stand", stand)

	var crouch := AnimationNodeBlendSpace2D.new()
	for point: Array in [
		["crouch_idle", Vector2.ZERO],
		["crouch_forward", Vector2(0, 1)], ["crouch_backward", Vector2(0, -1)],
		["crouch_left", Vector2(-1, 0)], ["crouch_right", Vector2(1, 0)],
	]:
		crouch.add_blend_point(_clip(point[0]), point[1], -1, point[0])
	root.add_node("crouch", crouch)

	var prone := AnimationNodeBlendSpace1D.new()
	prone.add_blend_point(_clip("prone_backward"), -1.0, -1, "prone_backward")
	prone.add_blend_point(_clip("prone_idle"), 0.0, -1, "prone_idle")
	prone.add_blend_point(_clip("prone_forward"), 1.0, -1, "prone_forward")
	root.add_node("prone", prone)

	var stance := _transition(["stand", "crouch", "prone"], 0.25)
	root.add_node("stance", stance)
	root.connect_node("stance", 0, "stand")
	root.connect_node("stance", 1, "crouch")
	root.connect_node("stance", 2, "prone")

	# In the air (jumping): a held mid-jump pose.
	root.add_node("air", _transition(["ground", "air"], 0.15))
	root.add_node("jump", _clip("jump_loop"))
	root.connect_node("air", 0, "stance")
	root.connect_node("air", 1, "jump")

	# Reload plays on the upper body only, using the version for the current stance.
	root.add_node("reload_kind", _transition(["stand", "crouch", "prone"], 0.0))
	root.add_node("reload_stand", _clip("reload"))
	root.add_node("reload_crouch", _clip("reload_crouch"))
	root.add_node("reload_prone", _clip("reload_prone"))
	root.connect_node("reload_kind", 0, "reload_stand")
	root.connect_node("reload_kind", 1, "reload_crouch")
	root.connect_node("reload_kind", 2, "reload_prone")
	var reload := AnimationNodeOneShot.new()
	reload.fadein_time = 0.15
	reload.fadeout_time = 0.25
	reload.filter_enabled = true
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		for part: String in UPPER_BODY:
			if bone_name.contains(part):
				reload.set_filter_path(NodePath("%s:%s" % [_model.get_path_to(skeleton), bone_name]), true)
				break
	root.add_node("reload", reload)
	root.connect_node("reload", 0, "air")
	root.connect_node("reload", 1, "reload_kind")

	# Alive, or one of the death falls.
	root.add_node("life", _transition(["alive", "dead_front", "dead_back", "dead_crouch", "dead_prone"], 0.15))
	root.connect_node("life", 0, "reload")
	for i in 4:
		var death: String = ["front", "back", "crouch", "prone"][i]
		root.add_node("death_" + death, _clip("death_" + death))
		root.connect_node("life", i + 1, "death_" + death)

	root.connect_node("output", 0, "life")
	_tree.tree_root = root
	_tree.active = true


func _clip(anim_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = anim_name
	return node


func _transition(inputs: Array, fade: float) -> AnimationNodeTransition:
	var node := AnimationNodeTransition.new()
	node.input_count = inputs.size()
	for i in inputs.size():
		node.set_input_name(i, inputs[i])
	node.xfade_time = fade
	return node
