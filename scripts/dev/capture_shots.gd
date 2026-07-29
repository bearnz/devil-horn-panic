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

	# Every shot below this line but one is framed for a camera inside the player's
	# head, and the third-person toggle is a saved preference — so a session that
	# left it on would otherwise re-shoot the whole set from behind the player.
	# Forced in memory rather than written back, so a real preference survives.
	Settings.third_person = false

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	await _settle(1.5)
	_save("shot_gameplay")
	_report(main)

	await _hand_shots(main)
	await _body_shots(main)
	await _third_person_shot(main)
	await _decal_shot(main)
	await _wind_shot(main)
	await _shunt_shot(main)
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
		await _weapon_settled(player, 0.5)
		_save_region("shot_hands_%s" % GameState.loadout[index].data.id)
	await _swap_shot(player)
	await _mantle_shot(player)


## The bottom of a weapon switch, which is the one frame of it that has to be right:
## the old weapon is at the hip and the new one has taken its place down there, and
## none of either should be anywhere in this crop. Anything showing here is geometry
## the player watches change into other geometry.
##
## Stepped frame by frame rather than timed, because the descent is a seventh of a
## second and a timer would land on either side of it.
func _swap_shot(player: Player) -> void:
	player.weapons.equip(0)
	await _weapon_settled(player, 0.3)
	player.weapons.equip(1 if GameState.loadout.size() > 1 else 0)
	var was := player.weapons.current()
	while player.weapons.is_swapping() and player.weapons.current() == was:
		await RenderingServer.frame_post_draw
	_save_region("shot_hands_swap")
	player.weapons.equip(0)
	await _weapon_settled(player, 0.3)


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
	# The view model is parented to the player's camera, so it is still sitting in
	# the world in front of the head — and a second camera photographs it. Without
	# this the body shots come back with two weapons in them: the one in the fist
	# and the one hanging in front of a lens nobody is looking through.
	player.weapons.visible = false
	player.hands.visible = false
	var camera := Camera3D.new()
	main.add_child(camera)
	# Opted out of physics interpolation, which every other camera in the game
	# wants: this one is placed from _process and photographed on the next frame,
	# so interpolating it towards where it was put would shoot from halfway there.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
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
	await _carry_shots(player, camera)
	await _look_shots(player, camera)
	await _dash_shot(player, camera)

	camera.queue_free()
	player.camera.make_current()
	player.body.first_person = true
	player.weapons.visible = true
	player.hands.visible = true
	await _settle(0.4)


## The carry, one shot per weapon, close enough to see the hands on it. This is the
## only pose in the game that is solved rather than authored — where the weapon goes
## is written down and the arms that reach it are worked out — so what these are for
## is checking that the arms which came back are ones a person could have, and that
## both hands landed on the weapon rather than near it. Per weapon, because the
## support hand slides along the barrel to get within reach and how far it slides is
## the weapon's own length talking.
func _carry_shots(player: Player, camera: Camera3D) -> void:
	for index in GameState.loadout.size():
		player.weapons.equip(index)
		await _weapon_settled(player, 0.4)
		# Closer and higher than the full-body shots, framed on the chest: what is
		# being judged here is a grip, and at full height a hand is eight pixels.
		camera.global_position = player.global_position + Vector3(1.15, 1.60, -1.35)
		camera.look_at(player.global_position + Vector3.UP * 1.24, Vector3.UP)
		camera.make_current()
		await _settle(0.3)
		_save("shot_body_hold_%s" % GameState.loadout[index].data.id)
	await _swap_carry_shot(player, camera)
	player.weapons.equip(0)
	await _weapon_settled(player, 0.4)


## Aiming up and aiming down, which is the one part of the pose the first-person view
## can never show: the view model hangs off the camera and pitches with it for free,
## and the body's copy is on the end of an arm that has to be sent after it. Steep on
## purpose — a shallow look is a couple of degrees of shoulder and proves nothing —
## and near enough to the pitch clamp to be the worst case the solve is ever given.
##
## What to look at: the barrel along the line of sight rather than merely tilted
## towards it, the chest leaning into it instead of standing bolt upright under a
## pair of raised arms, and both hands still on the weapon at the top of the swing,
## which is the furthest the off hand is ever asked to reach.
##
## Side-on rather than three-quarter, unlike every other body shot here. Pitch lives
## in the plane that a three-quarter view foreshortens, and this is the only shot
## whose whole subject is an angle in it.
func _look_shots(player: Player, camera: Camera3D) -> void:
	for shot: Array in [["shot_body_pitch_up", 1.45], ["shot_body_pitch_down", -1.45]]:
		# The player's own field rather than the pivot — `_tick_camera` rewrites the
		# pivot from it every physics frame.
		player._pitch = float(shot[1])
		# Square on from the shooting side, at the height of the shoulders the swing
		# happens at. Everything in this shot is an angle in the plane the lens is
		# parallel to, so any turn towards the front foreshortens the whole subject.
		camera.global_position = player.global_position + Vector3(1.5, 1.35, 0.0)
		camera.look_at(player.global_position + Vector3.UP * 1.25, Vector3.UP)
		camera.make_current()
		await _settle(0.4)
		_save(String(shot[0]))
	player._pitch = 0.0
	await _settle(0.3)


## The bottom of a weapon switch, from the outside. The first-person version of this
## shot is deliberately an empty frame — that is the whole point of the animation —
## so this is the only place the pose can actually be looked at: the weapon down
## beside the right hip with the arm that carries it, and the off hand let go and
## hanging, because the far hip is further away than that arm is long.
##
## Framed on the chest like the carry shots above it, since what is being judged is
## the same thing: whether these are arms a person could have.
func _swap_carry_shot(player: Player, camera: Camera3D) -> void:
	# Lower than the carry shots and aimed at the belt, because that is where the
	# thing being photographed has gone.
	camera.global_position = player.global_position + Vector3(1.15, 1.45, -1.35)
	camera.look_at(player.global_position + Vector3.UP * 1.05, Vector3.UP)
	camera.make_current()
	await _settle(0.3)
	# Framed first and then stepped frame by frame, saving the instant the weapon
	# changes hands: the bottom of the stroke lasts exactly one frame, so there is
	# nothing to move a camera to afterwards and no timer that lands on it.
	var was := player.weapons.current()
	player.weapons.equip(1 if GameState.loadout.size() > 1 else 0)
	while player.weapons.is_swapping() and player.weapons.current() == was:
		await RenderingServer.frame_post_draw
	_save("shot_body_swap")


## The dash, which is the one pose that is neither a stance nor a step: the body
## thrown along the dash with the legs streaming out behind it. Held open frame by
## frame rather than dashed for real, because `Player.DASH_TIME` is a third of a
## second — shorter than the settle before any other shot here — and because the
## perk that unlocks the dash may not be bought in whatever save this booted with.
## The player is pinned where they stood while it runs, so the pose arrives
## without the dash carrying its subject out of the frame.
func _dash_shot(player: Player, camera: Camera3D) -> void:
	var stood_at := player.global_position
	player._dash_direction = -player.global_transform.basis.z
	for _i in 14:
		player._dash_time_left = Player.DASH_TIME
		player.global_position = stood_at
		await get_tree().physics_frame
		await get_tree().process_frame

	# Wider and lower than the standing shots, and further round towards the side:
	# what there is to see is the angle between the legs and the ground, and a
	# three-quarter from the front foreshortens exactly that.
	camera.global_position = stood_at + Vector3(2.6, 1.1, -1.6)
	camera.look_at(stood_at + Vector3.UP * 0.85, Vector3.UP)
	camera.make_current()
	await RenderingServer.frame_post_draw
	_save("shot_body_dash")

	player._end_dash()
	player.velocity = Vector3.ZERO
	player.global_position = stood_at


## The review camera, through the game's own toggle rather than a throwaway camera:
## unlike every other shot here this one is a mode the player can actually be in, so
## what it is checking is the swap — body back, view model gone — as much as the
## framing. Taken mid-stride, because a chase camera exists to watch the legs.
func _third_person_shot(main: Node) -> void:
	var player := main.get_node_or_null("Player") as Player
	if player == null:
		return
	player.set_third_person(true)
	_hold("move_forward", true)
	await _settle(0.6)
	_save("shot_third_person")
	_hold("move_forward", false)
	player.set_third_person(false)
	await _settle(0.3)
	player.global_position = Vector3(0, 0.3, 34)
	player.reset_physics_interpolation()
	player.velocity = Vector3.ZERO
	await _settle(0.2)


## A burst emptied into the west wall from a few metres out — west for the lighting
## reason three paragraphs down. Bullet holes are
## `Decal`s, which project onto whatever geometry falls inside a box rather than
## sitting on a quad in front of it, and everything that can go wrong with that is
## invisible in code and obvious here: a hole projected along the wall instead of
## into it reads as a smear, one whose box is too shallow does not land at all, and
## a texture whose corners are not empty puts a square on the wall.
##
## Fired at an angle rather than square on, because a projection is only tested by
## a surface the box is not aligned with, and spread across the wall so the retire
## order can be seen if the cap ever starts evicting the wrong end.
##
## The west wall and not the nearer south one: the sun travels towards -X, -Y, -Z,
## so the two inward faces it lights are the west wall's and the north wall's, and a
## mark on an unlit wall is a dark shape on a dark shape.
func _decal_shot(main: Node) -> void:
	var player := main.get_node_or_null("Player") as Player
	if player == null:
		return
	await _revived(player)
	player.global_position = Vector3(-43, 0.3, 34)
	player.reset_physics_interpolation()
	player.velocity = Vector3.ZERO
	# Yaw of +90° turns the player's -Z forward onto -X, into the wall.
	player.rotation.y = PI * 0.5
	await _settle(0.5)

	var fired := 0
	var attempts := 0
	while fired < 8 and attempts < 200:
		attempts += 1
		# Topped up rather than counted on: a dry trigger pull is still accepted, it
		# just spends the frame starting a reload, so a magazine running out part-way
		# through would leave half the burst as holes that were never punched.
		var inst := player.weapons.current()
		if inst != null:
			inst.ammo = inst.mag_size()
		player.rotation.y = PI * 0.5 + sin(fired * 1.7) * 0.10
		player._pitch = 0.30 + cos(fired * 2.3) * 0.10
		await _settle(0.05)
		if player.weapons.try_fire():
			fired += 1
	player.rotation.y = PI * 0.5
	player._pitch = 0.22
	# Long enough for the muzzle flash and the impact sparks to have gone: what is
	# being photographed is what a wall looks like *after* being shot.
	await _settle(0.8)
	_save("shot_decals")

	player.global_position = Vector3(0, 0.3, 34)
	player.reset_physics_interpolation()
	player.rotation.y = 0.0
	player._pitch = 0.0
	await _settle(0.3)


## The dash, from the player's own eyes. A dash is a third of a second, so this
## holds one open frame by frame the way `_dash_shot` does — the difference being
## that this one is taken through the game's own camera, because two of its three
## subjects are HUD layers and a throwaway camera has no HUD in front of it.
##
## Three things land in the one frame: the streaks, the radial smear behind them,
## and the lens opened up by `DASH_FOV_PUNCH`. The last is the reason the arena in
## this shot never quite matches the arena in `shot_gameplay.png` from the same
## spot — more of it is in frame, which is the entire effect.
##
## Sideways rather than forward: a forward dash puts the streaks' origin in the
## middle of the frame, where "radiating from the middle" and "a ring drawn round
## the middle" are the same picture. Dashing right pushes that origin right, and
## what this is for is checking that it went the correct way, that the streaks still
## read as flow rather than as a wheel, that the smear grows out of that same point
## and leaves the middle of the frame legible, and above all that they left the
## crosshair alone — which is a bound in `SpeedLines` and a thing you have to look
## at.
func _wind_shot(main: Node) -> void:
	var player := main.get_node_or_null("Player") as Player
	if player == null:
		return
	await _revived(player)
	player.global_position = Vector3(0, 0.3, 34)
	player.reset_physics_interpolation()
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player._pitch = 0.0
	await _settle(0.4)

	var stood_at := player.global_position
	# The player's own right. Set on the field rather than through `_try_dash()`,
	# which would need the perk bought and would pick its own direction.
	player._dash_direction = player.global_transform.basis.x
	# Long enough for the wind to reach full strength and for the streaks to be part
	# way through their runs — a shot taken on the first frame of a dash is a shot of
	# an effect fading in. Not much longer than that, though: the field is one wave
	# launched at the start of the dash and it thins out as the dash runs, so holding
	# this open the way `_dash_shot` holds a pose open photographs an empty sky. Twelve
	# frames is a fifth of a second, which puts the wave across the middle of the
	# frame with the fastest streaks nearing the edge and the slowest still inside it.
	for _i in 12:
		player._dash_time_left = Player.DASH_TIME
		player.global_position = stood_at
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save("shot_dash_wind")

	player._end_dash()
	player.velocity = Vector3.ZERO
	player.global_position = stood_at
	player.reset_physics_interpolation()
	await _settle(0.5)


## The jolt at the far end of that dash. `_end_dash` hands back 14 m/s in one frame
## and kicks a spring on the camera to say so, and this photographs the spring at
## full swing.
##
## Diagonally forward and to the right, because the kick is quoted along two axes
## and a dash down either one of them alone only shows half of it: this way the one
## frame carries the dip that answers being stopped and the roll that answers being
## stopped sideways. Compare it against `shot_gameplay.png`, which is the same
## arena from the same spot with a level horizon — what you are looking for is that
## horizon tipped and dropped.
##
## The wind is still in the frame, and that is not a mistake to fix: the spring
## reaches full swing about an eighth of a second after the dash lets go and the
## streaks take a third of one to leave, so the jolt genuinely happens inside the
## tail of the wind. Wait for a clean frame and there is nothing left to
## photograph.
func _shunt_shot(main: Node) -> void:
	var player := main.get_node_or_null("Player") as Player
	if player == null:
		return
	await _revived(player)
	player.global_position = Vector3(0, 0.3, 34)
	player.reset_physics_interpolation()
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	player._pitch = 0.0
	await _settle(0.5)

	var stood_at := player.global_position
	var facing := player.global_transform.basis
	player._dash_direction = (-facing.z + facing.x).normalized()
	for _i in 10:
		player._dash_time_left = Player.DASH_TIME
		player.global_position = stood_at
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().process_frame

	player._end_dash()
	# Walked to the turning point rather than counted to it: the peak is a quarter
	# of the spring's period in, and a frame count would go stale the moment
	# `SHUNT_FREQUENCY` is retuned. One frame past the top is close enough — the
	# spring is barely moving there, which is why it is the top.
	var peak := 0.0
	for _i in 30:
		player.global_position = stood_at
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().process_frame
		var swing := player.camera_shunt().length()
		if swing < peak:
			break
		peak = swing
	await RenderingServer.frame_post_draw
	_save("shot_dash_shunt")

	player.velocity = Vector3.ZERO
	player.global_position = stood_at
	player.reset_physics_interpolation()
	await _settle(0.8)


## Waits out a death if one is in flight, then tops the player back up. The two
## shots below it park the player in the open for seconds at a time with the wave
## still running, and a frame of a corpse being eased to a stop and teleported to
## spawn is a picture of nothing — the HUD in it reads 0/100 with a respawn notice
## across the middle of the screen.
func _revived(player: Player) -> void:
	var guard := 0
	while player.is_dead and guard < 400:
		await get_tree().process_frame
		guard += 1
	player.heal(player.max_health)


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


## `_settle`, after waiting out a weapon switch. Equipping is an animation now — the
## old weapon goes to the hip, is swapped down there and comes back up — so a shot
## framed on the hands taken too soon after one is a shot of an empty pair of hands.
## Polled rather than given a longer timer, so retuning the animation cannot quietly
## turn the whole per-weapon set into pictures of the hip.
func _weapon_settled(player: Player, seconds: float) -> void:
	while player.weapons.is_swapping():
		await get_tree().process_frame
	await _settle(seconds)


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
