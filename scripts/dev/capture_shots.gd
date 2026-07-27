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
	await _body_shots(main)
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


## The body. Nothing in a normal frame shows more than its shins, so these are the
## only views of it that exist: one down the player's own nose, and two from a
## throwaway camera with `first_person` switched off so the head and arms come
## back. Standing and crouched, because the crouch is a deep squat and the pose
## that folds it is the one most likely to be wrong.
func _body_shots(main: Node) -> void:
	var player := main.get_node_or_null("Player") as Player
	if player == null or player.body == null:
		return

	# The player's own pitch field, not the camera pivot: `_tick_camera` rewrites
	# the pivot from it every physics frame, so nothing set on the pivot would
	# survive long enough to be photographed.
	# A glance at your own feet, not the full 83° the pitch clamp allows: this is
	# the angle a player actually looks down at, and the one the lower body is
	# built to be seen from.
	# Three angles, because they answer different questions. A glance at your feet
	# is what a player actually does, and is mostly a test of the shadow. The full
	# pitch clamp is the only angle that ever sees the boots, and the one where an
	# eye set too far back or too far forward shows up as either a plate across the
	# screen or nothing under you at all. The third is the same clamp crouched,
	# which is where the knees are, and the only view of the squat that anybody
	# playing this game will ever have.
	for shot: Array in [["shot_body_first_person", -0.95, false],
			["shot_body_look_down", -1.42, false],
			["shot_body_crouch_look_down", -1.42, true]]:
		_hold("crouch", bool(shot[2]))
		player._pitch = float(shot[1])
		await _settle(0.5)
		_save(String(shot[0]))
	_hold("crouch", false)
	player._pitch = 0.0
	await _settle(0.4)

	player.body.first_person = false
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.fov = 50.0
	for shot: Array in [["shot_body", false], ["shot_body_crouched", true]]:
		_hold("crouch", bool(shot[1]))
		await _settle(0.5)
		# Three quarters on from the front, the player's own facing (-Z) towards the
		# lens: the carry pose, the visor and the fold of a crouch are all on that
		# side, and a shot from behind is a shot of a slab.
		camera.global_position = player.global_position + Vector3(1.5, 1.3, -2.2)
		camera.look_at(player.global_position + Vector3.UP * 0.85, Vector3.UP)
		camera.make_current()
		await _settle(0.3)
		_save(String(shot[0]))
	_hold("crouch", false)

	camera.queue_free()
	player.camera.make_current()
	player.body.first_person = true
	await _settle(0.4)


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
