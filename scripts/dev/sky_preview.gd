extends Node
## Renders every Sky in resources/sky/ from inside the arena and writes the
## shots to disk, so a candidate panorama can be judged against the level's real
## lighting, fog and geometry without playing.
##
##   godot --path . --resolution 1280x720 res://scenes/dev/sky_preview.tscn ++ <out_dir>
##
## Per sky it writes four shots — the horizon at each quarter turn, plus the
## zenith:
##
##   sky_<name>_yaw000.png   looking -Z
##   sky_<name>_yaw090.png   looking -X
##   sky_<name>_yaw180.png   looking +Z
##   sky_<name>_yaw270.png   looking +X
##   sky_<name>_up.png       straight up
##
## Shoot the placeholder panorama through this and the coloured bands tell you
## which part of the image ends up over which side of the arena.

const SKY_DIR := "res://resources/sky"

## High enough to see over the perimeter walls and clear of the platforms, so
## the frame is mostly sky.
const EYE := Vector3(0.0, 24.0, 0.0)

var _out_dir: String = "user://"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(_out_dir)

	# Whichever level sorts first, so this keeps working as levels are added and
	# renamed rather than pinning a path.
	var level := Levels.first()
	if level == null:
		push_error("sky_preview: no levels to preview against")
		get_tree().quit(1)
		return
	var arena: Node3D = load(level.scene).instantiate()

	# This tool assigns skies itself, so the level's own SkyLoader must not be
	# swapping one in behind it. Cleared before add_child, i.e. before the
	# loader's _ready has had a chance to queue anything.
	var world := arena.get_node("WorldEnvironment") as WorldEnvironment
	if world is SkyLoader:
		(world as SkyLoader).sky_path = ""
	add_child(arena)

	var environment := world.environment
	var camera := Camera3D.new()
	arena.add_child(camera)
	camera.fov = 75.0
	camera.far = 400.0
	camera.make_current()

	var names := _sky_names()
	if names.is_empty():
		push_warning("no Sky resources under %s" % SKY_DIR)
	for sky_name: String in names:
		environment.sky = load("%s/%s.tres" % [SKY_DIR, sky_name])
		# A Sky swap only shows up once its radiance has been re-rendered, which
		# takes a frame or two of its own.
		await _settle(0.3)
		for yaw in [0, 90, 180, 270]:
			_aim(camera, deg_to_rad(float(yaw)), 0.0)
			await _settle(0.15)
			_save("sky_%s_yaw%03d" % [sky_name, yaw])
		_aim(camera, 0.0, deg_to_rad(80.0))
		await _settle(0.15)
		_save("sky_%s_up" % sky_name)

	get_tree().quit()


## Whatever .tres files are sitting in the sky folder, same "content is data"
## deal as perks and weapons — drop one in and it shows up in the next run.
func _sky_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(SKY_DIR)
	if dir == null:
		return names
	for file: String in dir.get_files():
		# Exported projects rename .tres to .remap, hence the strip.
		if file.ends_with(".tres") or file.ends_with(".tres.remap"):
			names.append(file.trim_suffix(".remap").trim_suffix(".tres"))
	names.sort()
	return names


func _aim(camera: Camera3D, yaw: float, pitch: float) -> void:
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), EYE)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func _save(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % file_name)
	var error := image.save_png(path)
	print("%s -> %s (%d)" % [file_name, path, error])
