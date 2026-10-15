extends SceneTree
## Turns the raw Mixamo downloads in assets/characters/source/ (git-ignored, very large)
## into small game-ready files that are committed:
##   assets/characters/<name>.scn       - character model, textures shrunk to 1024 px
##   assets/characters/soldier_anims.res - every animation in one AnimationLibrary
##
## Run from the project folder:
##   Godot_console.exe --headless --path . --script res://tools/build_characters.gd

const SRC := "res://assets/characters/source/"
const OUT := "res://assets/characters/"
const TEXTURE_SIZE := 1024

## Output name -> source file.
const CHARACTERS := {
	"ops_soldier": "character_swat_guy.fbx",
	"terrorist_soldier": "character_heraklios.fbx",
}

## Animations that repeat (everything else plays once and holds its last frame).
const LOOPING := [
	"idle", "walk_forward", "walk_backward", "walk_left", "walk_right",
	"run_forward", "run_backward", "run_left", "run_right", "sprint",
	"crouch_idle", "crouch_forward", "crouch_backward", "crouch_left", "crouch_right",
	"prone_idle", "prone_forward", "prone_backward", "jump_loop",
]

const TEXTURE_PROPERTIES := [
	"albedo_texture", "normal_texture", "roughness_texture", "metallic_texture",
	"emission_texture", "ao_texture",
]


func _initialize() -> void:
	for out_name: String in CHARACTERS:
		_build_character(out_name, SRC + CHARACTERS[out_name])
	_build_animation_library()
	quit()


func _build_character(out_name: String, path: String) -> void:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.name = "Model"
	# The model's own AnimationPlayer only holds a T-pose; ours comes from soldier_anims.
	for child in model.get_children():
		if child is AnimationPlayer:
			model.remove_child(child)
			child.free()

	for mesh_instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_instance.mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface)
			if material is BaseMaterial3D:
				mesh.surface_set_material(surface, _shrink_material(material as BaseMaterial3D))
	_own_everything(model, model)

	var packed := PackedScene.new()
	packed.pack(model)
	var file := OUT + out_name + ".scn"
	var err := ResourceSaver.save(packed, file, ResourceSaver.FLAG_BUNDLE_RESOURCES | ResourceSaver.FLAG_COMPRESS)
	print("%s -> %s (%s, %.1f MB)" % [path.get_file(), file, error_string(err),
		FileAccess.get_file_as_bytes(file).size() / 1048576.0])
	model.free()


## Copies the material with every texture shrunk and stored GPU-compressed inside the scene.
func _shrink_material(source: BaseMaterial3D) -> BaseMaterial3D:
	var material := source.duplicate() as BaseMaterial3D
	for property: String in TEXTURE_PROPERTIES:
		var texture: Texture2D = material.get(property)
		if texture == null:
			continue
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		if image.get_width() > TEXTURE_SIZE:
			image.resize(TEXTURE_SIZE, TEXTURE_SIZE * image.get_height() / image.get_width(), Image.INTERPOLATE_LANCZOS)
		image.generate_mipmaps()
		image.compress(Image.COMPRESS_S3TC)
		material.set(property, ImageTexture.create_from_image(image))
		print("  %s: %dx%d" % [property, image.get_width(), image.get_height()])
	return material


## PackedScene only saves nodes owned by the root.
func _own_everything(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own_everything(child, root)


func _build_animation_library() -> void:
	var library := AnimationLibrary.new()
	for file in DirAccess.get_files_at(SRC):
		if not file.begins_with("anim_") or not file.ends_with(".fbx"):
			continue
		var anim_name := file.trim_prefix("anim_").trim_suffix(".fbx")
		var root := (load(SRC + file) as PackedScene).instantiate()
		var player: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
		var source := player.get_animation(player.get_animation_list()[0])
		var anim := source.duplicate(true) as Animation
		anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE
		library.add_animation(anim_name, anim)
		root.free()
	var file := OUT + "soldier_anims.res"
	var err := ResourceSaver.save(library, file, ResourceSaver.FLAG_COMPRESS)
	print("%d animations -> %s (%s, %.1f MB): %s" % [library.get_animation_list().size(), file,
		error_string(err), FileAccess.get_file_as_bytes(file).size() / 1048576.0,
		", ".join(library.get_animation_list())])
