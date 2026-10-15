extends SkeletonModifier3D
## Runs after the animations each frame:
## 1. Bends the spine up/down so the soldier aims where the player is looking.
## 2. Places the rifle in the hands: stock at the right hand, barrel through the left hand.

## Radians: positive looks up.
var pitch := 0.0
## The rifle (positioned every frame) and its muzzle point.
var gun: Node3D

var _spine_bones: Array[int] = []
var _right_hand := -1
var _left_hand := -1


func _ready() -> void:
	var skeleton := get_skeleton()
	for bone_name in ["mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2"]:
		var bone := skeleton.find_bone(bone_name)
		if bone >= 0:
			_spine_bones.append(bone)
	_right_hand = skeleton.find_bone("mixamorig_RightHand")
	_left_hand = skeleton.find_bone("mixamorig_LeftHand")


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return

	# The model faces +Z in its own space, so its right side is -X; tilting around
	# that axis raises or lowers the chest (and the arms and rifle with it).
	var share := pitch / maxf(_spine_bones.size(), 1)
	for bone in _spine_bones:
		var axis := (skeleton.get_bone_global_pose(bone).basis.inverse() * Vector3.LEFT).normalized()
		var rotation := skeleton.get_bone_pose_rotation(bone) * Quaternion(axis, share)
		skeleton.set_bone_pose_rotation(bone, rotation)

	if gun and _right_hand >= 0 and _left_hand >= 0:
		var to_world := skeleton.global_transform
		var right := to_world * skeleton.get_bone_global_pose(_right_hand).origin
		var left := to_world * skeleton.get_bone_global_pose(_left_hand).origin
		if right.distance_to(left) > 0.05:
			var forward := (left - right).normalized()
			var up := to_world.basis.y.normalized()
			if absf(forward.dot(up)) > 0.98:
				up = to_world.basis.z.normalized()
			gun.global_transform = Transform3D(Basis.looking_at(forward, up), right)
