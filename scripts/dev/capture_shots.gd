extends Node
## Boots the game, renders a few frames and writes screenshots to disk, then
## quits. Handy for checking layout and lighting without playing.
##
##   godot --path . --resolution 1280x720 res://scenes/dev/capture_shots.tscn ++ <output_dir>
##
## Output directory defaults to user://.

var _out_dir: String = "user://"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	await _settle(1.5)
	_save("shot_gameplay")
	_report(main)

	await _overview(main)

	var menu := main.get_node_or_null("CharacterMenu") as CharacterMenu
	if menu != null:
		menu.open(1)
		await _settle(0.5)
		_save("shot_perks")
		menu.open(2)
		await _settle(0.4)
		_save("shot_bench")
		menu.close()

	get_tree().quit()


## Where the player ended up and what it is looking at — cheap sanity check that
## the spawn marker and level geometry line up.
func _report(main: Node) -> void:
	var player := main.get_node_or_null("Player") as Player
	if player == null:
		return
	print("player position: %s" % player.global_position)
	print("player facing:   %s" % (-player.global_transform.basis.z))
	print("grounded:        %s" % player.is_on_floor())

	var camera := player.camera
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 60.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		print("crosshair looking at: nothing within 60m")
	else:
		print("crosshair looking at: %s at %.1fm" % [
			(hit["collider"] as Node).name, from.distance_to(hit["position"])])


## Top-down look at the whole arena, from a throwaway camera.
func _overview(main: Node) -> void:
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.global_position = Vector3(44, 58, 62)
	camera.look_at(Vector3(0, 2, -6), Vector3.UP)
	camera.fov = 62.0
	camera.far = 400.0
	camera.make_current()
	await _settle(0.4)
	_save("shot_overview")
	camera.queue_free()
	var player := main.get_node_or_null("Player") as Player
	if player != null:
		player.camera.make_current()
	await _settle(0.2)


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await RenderingServer.frame_post_draw


func _save(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join("%s.png" % file_name)
	var error := image.save_png(path)
	print("%s -> %s (%d)" % [file_name, path, error])
