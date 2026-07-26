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
	DirAccess.make_dir_recursive_absolute(_out_dir)

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	await _settle(1.5)
	_save("shot_gameplay")
	_report(main)

	await _hand_shots(main)
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

	await _pause_shots(main)

	get_tree().quit()


## Both pause screens. The panel sizes itself to whichever one is showing, so
## the short main screen and the tall keybindings list are worth seeing together.
func _pause_shots(main: Node) -> void:
	var pause := main.get_node_or_null("PauseMenu") as PauseMenu
	if pause == null:
		return
	pause.open()
	await _settle(0.4)
	_save("shot_pause")
	pause._open_keybinds()
	await _settle(0.4)
	_save("shot_pause_keybinds")
	pause.close()
	await _settle(0.2)


## The view model up close: one shot per weapon in the loadout, plus one taken
## mid-mantle with both hands on a ledge. Cropped out of the frame and doubled,
## because the hands occupy a corner of it and the detail is the whole point.
func _hand_shots(main: Node) -> void:
	var player := main.get_node_or_null("Player") as Player
	if player == null:
		return
	for index in GameState.loadout.size():
		player.weapons.equip(index)
		await _settle(0.5)
		_save_region("shot_hands_%s" % GameState.loadout[index].data.id)
	player.weapons.equip(0)
	await _mantle_shot(player)


## Drives a real mantle on the arena's west step and grabs two frames from it:
## the hang, where both hands are planted on the lip and the weapon is stowed, and
## the climb a moment later, where they should be letting go rather than trailing.
func _mantle_shot(player: Player) -> void:
	player.global_position = Vector3(-39, 0.05, 26.8)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	var settle := 0
	while not player.is_on_floor() and settle < 120:
		await get_tree().physics_frame
		settle += 1

	# Same launch the smoke test uses: airborne, moving into the face.
	player.velocity = Vector3(0, 9.6, 0)
	_hold("move_forward", true)
	for beat: Array in [["shot_hands_mantle_grab", 0.20], ["shot_hands_mantle_climb", 0.55]]:
		var guard := 0
		while guard < 180 and not (player.is_mantling()
				and player.mantle_phase() > float(beat[1])):
			await get_tree().physics_frame
			guard += 1
		var caught := player.is_mantling()
		await RenderingServer.frame_post_draw
		if caught:
			_save_region(String(beat[0]))
		else:
			print("%s -> skipped, no mantle within %d frames" % [beat[0], guard])
	_hold("move_forward", false)
	player.global_position = Vector3(0, 0.3, 34)
	player.velocity = Vector3.ZERO
	await _settle(0.3)


func _hold(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


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
	_write(get_viewport().get_texture().get_image(), file_name)


## The bottom-centre of the frame at double size — the corner the view model and
## the hands live in, whatever resolution the run was given.
func _save_region(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var size := image.get_size()
	var region := Rect2i(int(size.x * 0.28), int(size.y * 0.40),
			int(size.x * 0.50), int(size.y * 0.60))
	var crop := image.get_region(region)
	crop.resize(region.size.x * 2, region.size.y * 2, Image.INTERPOLATE_NEAREST)
	_write(crop, file_name)


func _write(image: Image, file_name: String) -> void:
	var path := _out_dir.path_join("%s.png" % file_name)
	var error := image.save_png(path)
	print("%s -> %s (%d)" % [file_name, path, error])
