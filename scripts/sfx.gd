extends Node
## Plays sound effects. Runs as an Autoload ("Sfx").
## - play_3d(): a sound in the world. It gets quieter with distance and comes from its direction.
## - play_ui(): a flat sound that isn't in the world (menus, hit markers, your own gun).
## Each name maps to one or more files; one is picked at random, with a slight pitch change,
## so repeated sounds don't feel robotic.

const SOUNDS := {
	"m4_near": ["weapons/m4_near_1.wav", "weapons/m4_near_2.wav"],
	"m4_far": ["weapons/m4_far_1.wav", "weapons/m4_far_2.wav"],
	"ak_near": ["weapons/ak_near_1.wav", "weapons/ak_near_2.wav", "weapons/ak_near_3.wav"],
	"ak_far": ["weapons/ak_far_1.wav", "weapons/ak_far_2.wav"],
	"mag_out": ["weapons/mag_out.ogg"],
	"mag_in": ["weapons/mag_in.ogg"],
	"charge": ["weapons/charge.ogg"],
	"dry_fire": ["weapons/dry_fire.ogg"],
	"step": ["footsteps/step_1.ogg", "footsteps/step_2.ogg", "footsteps/step_3.ogg",
		"footsteps/step_4.ogg", "footsteps/step_5.ogg"],
	"impact_ground": ["impacts/ground_1.ogg", "impacts/ground_2.ogg", "impacts/ground_3.ogg"],
	"impact_body": ["impacts/body_1.ogg", "impacts/body_2.ogg"],
	"hurt": ["impacts/hurt.ogg"],
	"hit": ["ui/hit.ogg"],
	"kill": ["ui/kill.ogg"],
	"green_up": ["ui/green_up.ogg"],
	"click": ["ui/click.ogg"],
	"tick": ["ui/tick.ogg"],
	"round_start": ["ui/round_start.ogg"],
	"go": ["ui/go.ogg"],
	"round_won": ["ui/round_won.ogg"],
	"round_lost": ["ui/round_lost.ogg"],
}

var _streams := {}  # name -> Array[AudioStream]


func _ready() -> void:
	for sound_name: String in SOUNDS:
		var list: Array[AudioStream] = []
		for file: String in SOUNDS[sound_name]:
			list.append(load("res://assets/audio/" + file))
		_streams[sound_name] = list


## A sound at a place in the world. unit_size is how far (meters) it carries at full volume:
## gunshots ~15, footsteps ~2.
func play_3d(sound_name: String, position: Vector3, volume_db: float = 0.0, unit_size: float = 5.0) -> void:
	var scene := get_tree().current_scene
	if not scene is Node3D:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _pick(sound_name)
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.max_distance = 400.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.pitch_scale = randf_range(0.95, 1.05)
	player.finished.connect(player.queue_free)
	scene.add_child(player)
	player.global_position = position
	player.play()


## A flat (non-positional) sound, e.g. menus, hit markers, or your own gun.
func play_ui(sound_name: String, volume_db: float = 0.0, vary_pitch: bool = false) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = _pick(sound_name)
	player.volume_db = volume_db
	if vary_pitch:
		player.pitch_scale = randf_range(0.96, 1.04)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _pick(sound_name: String) -> AudioStream:
	var list: Array = _streams[sound_name]
	return list[randi() % list.size()]
