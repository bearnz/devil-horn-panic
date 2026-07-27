extends Node
## Headless integration check. Boots the real main scene and drives the systems
## the way a player would, then prints a pass/fail summary and quits.
##
## Run it with:
##   godot --path . --headless --fixed-fps 60 res://scenes/dev/smoke_test.tscn
##
## It leaves progression reset to a fresh-save state so it never pollutes a real
## playthrough.

const SKY_DIR := "res://resources/sky"
## The one level that exists. Assertions name it rather than "whatever is first"
## so renaming it out from under the suite is a failure, not a silent pass.
const POC_LEVEL_ID := "000_poc_1"

var _checks: int = 0
var _failures: PackedStringArray = []

var _main: Main
var _player: Player
## Latched by a listener connected the moment the level loads. The first wave
## runs off a wall-clock timer from that point, so a case ahead of _test_waves()
## that takes its time must not be able to let the wave fire unobserved.
var _wave_started: bool = false
## Deaths seen over the whole run, latched the moment the level loads. A player
## killed mid-suite invalidates whatever case was measuring at the time and does
## it silently: the corpse is eased to a stop and teleported back to spawn, so an
## air-time probe reads a fall that never accelerated and the failure surfaces
## somewhere downstream of the thing that caused it. Recorded here so it is
## reported as the death it was rather than reverse-engineered from an impossible
## velocity.
var _deaths: PackedStringArray = []
## Shots counted off Events.ammo_changed while the fire-rate case holds the
## trigger. A member rather than a local closed over by the listener, because a
## GDScript lambda captures locals by value and would count into its own copy.
var _shots_seen: int = 0


func _ready() -> void:
	# A save from a previous session would make the assertions below meaningless.
	if FileAccess.file_exists(GameState.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
	GameState.reset_progress(false)
	_reset_settings_files()

	await _run()

	print("\n--- smoke test: %d checks, %d failed ---" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL  %s" % failure)
	if _failures.is_empty():
		print("all good")
	GameState.reset_progress(false)
	_reset_settings_files()
	get_tree().quit(0 if _failures.is_empty() else 1)


## Wipes any real settings file/backup so test writes never leak into (or
## get confused by) a real session's preferences.
func _reset_settings_files() -> void:
	for path in [Settings.SAVE_PATH, Settings.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Settings.mouse_sensitivity = Settings.DEFAULT_MOUSE_SENSITIVITY
	Settings.fov = Settings.DEFAULT_FOV
	Settings.spawn_enemies_enabled = true
	Settings.third_person = false
	Settings.reset_all_keybinds()


func _run() -> void:
	_check("weapon library loaded", GameState.weapons.size() >= 3, str(GameState.weapons.keys()))
	_check("upgrade library loaded", GameState.upgrades.size() >= 7, str(GameState.upgrades.size()))
	_check("perk library loaded", GameState.perks.size() >= 13, str(GameState.perks.size()))
	_check("starting loadout", GameState.loadout.size() == 2, str(GameState.loadout.size()))
	# Regression guard: weapons used to be built before the stat sheet existed,
	# which multiplied their opening reserve by a zeroed ammo_reserve_mult.
	_check("starting weapons carry reserve ammo",
			GameState.loadout[0].reserve == GameState.loadout[0].reserve_max()
					and GameState.loadout[0].reserve > 0,
			"%d / %d" % [GameState.loadout[0].reserve, GameState.loadout[0].reserve_max()])

	_check_input_map()
	_test_level_library()
	_test_sky_library()
	await _test_sky_loader()
	_test_settings()
	await _test_title_screen()

	Events.wave_started.connect(func(_index: int, _count: int) -> void: _wave_started = true)
	Events.player_died.connect(_on_player_died)
	_main = load("res://scenes/main.tscn").instantiate() as Main
	add_child(_main)
	await _idle(4)

	_player = _main.get_node_or_null("Player") as Player
	_check("player spawned", _player != null, "")
	if _player == null:
		return
	_check("weapon controller found a weapon", _player.weapons.current() != null, "")
	_check_main_built_the_level()
	_check_arena_sky()

	# Runs first of the gameplay cases: it is ungated, so it needs no progression,
	# and getting it in early keeps it clear of the first enemy wave.
	await _test_mantle()
	await _test_slide()
	await _test_pause_menu()
	await _test_shooting()

	# The four below measure the player rather than the fight, and a wave walking
	# into them is not a regression, it is noise: an enemy in melee range knocks
	# the body about and kicks the camera between the frame a pose is applied and
	# the frame it is read, so a hand lands a centimetre off its grip and a crouch
	# is measured against a floor the player is being shoved along. Some of them
	# also want a known number of enemies rather than however many the seed put
	# nearby, and the fire-rate window stands still with the trigger down for two
	# seconds, which is long enough to be killed where it stands. Held across all
	# four and released together.
	_hold_the_wave(true)
	await _test_enemy_reach()
	await _test_fire_rate()
	await _test_hands()
	await _test_body()
	_hold_the_wave(false)

	await _test_third_person()

	await _test_progression()
	await _test_dash()
	await _test_hud_points_label()
	await _test_persistence()
	await _test_waves()
	await _test_spawn_toggle()

	# Last, so it covers everything above it. No case here is supposed to get the
	# player killed, and every case that leaves the ground is measuring a body it
	# assumes is still being driven by gravity rather than by the respawn.
	_check("nothing killed the player over the whole run", _deaths.is_empty(),
			"died at %s" % ", ".join(_deaths))


# --- Cases ------------------------------------------------------------------

## The level registry. A LevelData whose `scene` path is wrong loads fine and
## only fails at the moment someone tries to play it, so the paths are resolved
## here rather than trusted.
func _test_level_library() -> void:
	_check("level library loaded", Levels.library.size() >= 1, str(Levels.library.keys()))
	_check("poc 1 is in the library", Levels.get_level(POC_LEVEL_ID) != null, POC_LEVEL_ID)

	for level: LevelData in Levels.ordered():
		_check("%s points at a scene that exists" % level.id,
				ResourceLoader.exists(level.scene), level.scene)
		_check("%s has a display name" % level.id, not level.display_name.is_empty(), "")

	var first := Levels.first()
	_check("first level resolves", first != null, "")
	if first != null:
		_check("poc 1 sorts first", first.id == POC_LEVEL_ID, first.id)

	# Ordering is what the numeric id prefix is for, so it gets asserted rather
	# than assumed by whatever eventually advances between levels.
	var ordered := Levels.ordered()
	var sorted := true
	for index in range(1, ordered.size()):
		var previous := ordered[index - 1]
		var current := ordered[index]
		if previous.order > current.order \
				or (previous.order == current.order and previous.id > current.id):
			sorted = false
	_check("levels come back in play order", sorted, str(ordered.size()))
	_check("the last level has nothing after it",
			ordered.is_empty() or Levels.next_of(ordered[-1].id) == null, "")

	# The title screen's Start button no longer holds a scene path of its own, so
	# a typo in this constant is the one that would silently break booting.
	_check("the scene Levels boots into exists",
			ResourceLoader.exists(Levels.MAIN_SCENE), Levels.MAIN_SCENE)

	_check("selecting an unknown level is refused", not Levels.select("no_such_level"), "")
	_check("a refused select left the current level alone",
			Levels.current != null and Levels.current.id == POC_LEVEL_ID,
			"" if Levels.current == null else Levels.current.id)


## main.tscn no longer contains a level — it builds one from Levels.current — so
## the wiring that replaced the static child is worth an explicit check.
func _check_main_built_the_level() -> void:
	var level_node := _main.get_node_or_null("Level")
	_check("main instanced the level", level_node != null, "")
	_check("main recorded which level it built",
			_main.level != null and _main.level.id == POC_LEVEL_ID,
			"" if _main.level == null else _main.level.id)
	_check("player placed on the level's spawn marker",
			_player.global_position.distance_to(Vector3(0, 0.3, 34)) < 0.5,
			str(_player.global_position))


## Guards the sky swap: every .tres in resources/sky/ has to load as a usable
## Sky, because the whole point of the folder is that a new one can be dropped
## in without touching code. A panorama whose image failed to import loads as a
## material with a null texture and renders black, which is easy to miss in a
## dark level, so the texture is checked too.
func _test_sky_library() -> void:
	var dir := DirAccess.open(SKY_DIR)
	_check("sky folder exists", dir != null, SKY_DIR)
	if dir == null:
		return

	var found := 0
	for file: String in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		found += 1
		var path := "%s/%s" % [SKY_DIR, file]
		var sky := load(path) as Sky
		_check("%s loads as a Sky" % file, sky != null, path)
		if sky == null:
			continue
		_check("%s has a sky material" % file, sky.sky_material != null, "")

		var panorama := sky.sky_material as PanoramaSkyMaterial
		if panorama == null:
			continue
		var texture := panorama.panorama
		_check("%s resolved its panorama image" % file, texture != null, "")
		if texture == null:
			continue
		# Equirectangular means exactly 2:1 — anything else is silently squashed
		# onto the sphere rather than rejected.
		var size := texture.get_size()
		_check("%s panorama is 2:1 equirectangular" % file,
				absf(size.x - size.y * 2.0) < 1.0, "%dx%d" % [size.x, size.y])

	_check("sky folder has something in it", found > 0, str(found))


## The fallback contract: whatever happens to the real sky, something is on
## screen. Each case is driven through a throwaway SkyLoader rather than the
## level's, so a failure case can be provoked without breaking the arena.
func _test_sky_loader() -> void:
	# 1. Nothing asked for — the state the project is in until there is sky art.
	var idle := await _run_sky_loader("", true)
	_check("no sky requested resolves to the fallback",
			idle["state"] == SkyLoader.State.FALLBACK, str(idle["state"]))
	_check("fallback case still has a sky on screen", idle["sky"] != null, "")
	_check("fallback case reports it is showing the fallback", bool(idle["fallback"]), "")

	# 2. A path that is not there — a sky deleted, renamed or never committed.
	var missing := await _run_sky_loader("res://resources/sky/does_not_exist.tres", true)
	_check("a missing sky fails rather than blanking the background",
			missing["state"] == SkyLoader.State.FAILED, str(missing["state"]))
	_check("a missing sky leaves the gradient up", missing["sky"] != null, "")

	# 3. Pointed at something real. The load is deferred, so this one needs frames
	# to land — and the gradient has to be what was up in the meantime.
	var loaded := await _run_sky_loader("res://resources/sky/arena_panorama.tres", true)
	_check("a real sky loads and swaps in",
			loaded["state"] == SkyLoader.State.LOADED, str(loaded["state"]))
	_check("the loaded sky replaced the gradient",
			loaded["sky"] != null and loaded["sky"] is Sky
					and (loaded["sky"] as Sky).sky_material is PanoramaSkyMaterial, "")
	# The regression this guards: loading in _ready would pass every check above
	# while stalling the first frame, which is exactly what the fallback exists
	# to avoid.
	var first_frame := loaded["sky_on_first_frame"] as Sky
	_check("the gradient was on screen before the real sky arrived",
			first_frame != null and first_frame.sky_material is ProceduralSkyMaterial,
			"" if first_frame == null else str(first_frame.sky_material))

	# 4. A level authored with no sky at all: the loader has to supply one, or
	# the "always something on screen" promise only holds for scenes that
	# already had it.
	var bare := await _run_sky_loader("", false)
	_check("an environment with no sky gets the gradient anyway",
			bare["sky"] != null, str(bare["state"]))


## Builds a SkyLoader on its own Environment, waits for it to settle and reports
## where it landed. `with_sky` seeds the environment with the gradient the way a
## level scene would; false leaves it empty.
func _run_sky_loader(sky_path: String, with_sky: bool) -> Dictionary:
	var loader := SkyLoader.new()
	loader.environment = Environment.new()
	loader.environment.background_mode = Environment.BG_SKY
	if with_sky:
		loader.environment.sky = load("res://resources/sky/arena_dusk.tres") as Sky
	loader.sky_path = sky_path

	var result: Dictionary = {}
	# Connected before add_child because the synchronous cases resolve inside
	# _ready() and would otherwise emit into an empty room.
	loader.sky_resolved.connect(func(sky: Sky, state: int) -> void:
		result["sky"] = sky
		result["state"] = state)
	add_child(loader)

	# Sampled before any waiting: this is what is on screen the instant the level
	# appears, which is the whole point of the fallback.
	result["sky_on_first_frame"] = loader.environment.sky

	var guard := 0
	while not result.has("state") and guard < 600:
		await _idle(1)
		guard += 1
	result["fallback"] = loader.showing_fallback()
	result["timed_out"] = not result.has("state")
	_check("sky loader settled for '%s'" % sky_path, result.has("state"), "%d frames" % guard)
	loader.queue_free()
	return result


## The level has to actually be drawing one of those skies — a WorldEnvironment
## left on the default background renders flat grey and no amount of sky
## authoring would show up.
func _check_arena_sky() -> void:
	var world := _main.get_node_or_null("Level/WorldEnvironment") as WorldEnvironment
	_check("level has a WorldEnvironment", world != null, "")
	if world == null or world.environment == null:
		return
	var environment := world.environment
	_check("level draws the sky as its background",
			environment.background_mode == Environment.BG_SKY, str(environment.background_mode))
	_check("level environment has a sky assigned", environment.sky != null, "")
	# The level's WorldEnvironment is the SkyLoader itself, so the gradient is up
	# from frame one whatever the real sky ends up doing.
	_check("level's environment is a SkyLoader", world is SkyLoader, world.get_class())
	if world is SkyLoader:
		var loader := world as SkyLoader
		_check("level sky settled rather than hanging", not loader.is_loading(),
				str(loader.state))
		_check("level has a fallback sky recorded", loader.fallback_sky != null, "")
	# Fog at full strength replaces the sky with flat fog colour, which makes any
	# authored image invisible. See assets/sky/README.md.
	_check("fog leaves the sky visible", environment.fog_sky_affect < 0.9,
			"fog_sky_affect %.2f" % environment.fog_sky_affect)


## Every action the gameplay scripts poll must exist and have a binding,
## otherwise Godot spams "action not found" at runtime.
func _check_input_map() -> void:
	var required := [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "crouch", "dash",
		"fire", "aim", "reload", "interact", "menu", "third_person",
		"weapon_1", "weapon_2", "weapon_3", "weapon_next", "weapon_prev",
	]
	var missing: PackedStringArray = []
	for action: String in required:
		if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
			missing.append(action)
	_check("all input actions bound", missing.is_empty(), ", ".join(missing))

## Settings are wiped fresh by _reset_settings_files() before this runs.
func _test_settings() -> void:
	_check("settings start at default",
			is_equal_approx(Settings.mouse_sensitivity, Settings.DEFAULT_MOUSE_SENSITIVITY),
			str(Settings.mouse_sensitivity))

	Settings.mouse_sensitivity = 0.0050
	Settings.save_settings()
	_check("settings file written", FileAccess.file_exists(Settings.SAVE_PATH), "")
	_check("no backup yet on first save", not FileAccess.file_exists(Settings.BACKUP_PATH), "")

	# A second save must back up what was on disk (0.0050) before overwriting it.
	Settings.mouse_sensitivity = 0.0065
	Settings.save_settings()
	_check("settings backup written", FileAccess.file_exists(Settings.BACKUP_PATH), "")

	# Simulate a future settings-format refactor gone wrong: the primary file
	# ends up unreadable. load_settings() should recover the last-known-good
	# value from the backup rather than falling back to defaults.
	var corrupt := FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
	corrupt.store_string("not valid json")
	corrupt.close()

	var recovered := Settings.load_settings()
	_check("settings recovered from backup after corruption",
			recovered and is_equal_approx(Settings.mouse_sensitivity, 0.0050),
			str(Settings.mouse_sensitivity))

	_reset_settings_files()


## Exercises TitleScreen.apply_choice() directly rather than pressing the real
## buttons: those call get_tree().change_scene_to_file(), which would tear
## down this very test (the smoke test node is the tree's current scene).
##
## Calls apply_choice() via call() rather than a static TitleScreen type so
## this doesn't depend on the global script-class cache already knowing about
## a class_name added in the same editing session as this test.
func _test_title_screen() -> void:
	var title: Node = load("res://scenes/ui/title_screen.tscn").instantiate()
	add_child(title)
	await _idle(1)

	var start_btn := title.get_node_or_null("Center/Root/StartButton") as Button
	var no_enemies_btn := title.get_node_or_null("Center/Root/StartNoEnemiesButton") as Button
	_check("title screen buttons present", start_btn != null and no_enemies_btn != null, "")

	if start_btn != null and no_enemies_btn != null:
		title.call("apply_choice", false)
		_check("'no enemies' choice disables spawning", not Settings.spawn_enemies_enabled, "")
		_check("title screen choice persisted to disk", FileAccess.file_exists(Settings.SAVE_PATH), "")

		title.call("apply_choice", true)
		_check("'start' choice re-enables spawning", Settings.spawn_enemies_enabled, "")

	title.queue_free()
	await _idle(1)
	_reset_settings_files()


## Mantling is baseline, so this needs nothing but geometry and a held direction
## — but it still asks for intent, and the case that has to stay refused is
## simply running into the lip. WestStep1 is a 1.9m lip on the west approach
## (too tall to walk onto, inside MANTLE_MAX_HEIGHT); the 18m west arena wall
## beside it is the control that must stay unclimbable however you approach it.
##
## Every probe starts at z = 26.8, facing -Z, just short of the step's south face
## at z = 26.
func _test_mantle() -> void:
	_check("mantle window can actually reach a 1.9m lip",
			Player.MANTLE_MAX_HEIGHT >= 1.9 and Player.MANTLE_MIN_HEIGHT < 1.9,
			"%.2f..%.2f" % [Player.MANTLE_MIN_HEIGHT, Player.MANTLE_MAX_HEIGHT])

	# The case the gate exists for: grounded, walking straight into the face, no
	# jump. Must never climb, however long the direction is held.
	var walked := await _mantle_probe(Vector3(-39, 0.05, 26.8), 0.0, "move_forward", false)
	_check("mantle probe settled the player on the floor first", bool(walked["settled"]), "")
	_check("running into a ledge does not mantle", not bool(walked["started"]),
			str(walked["end_position"]))
	_check("running into a ledge leaves the player on the ground",
			float(walked["end_y"]) < 0.5, str(walked["end_position"]))

	# Airborne, carrying a jump's worth of rise but with the jump action never
	# touched — this is the "properly off the ground" branch on its own.
	var airborne := await _mantle_probe(Vector3(-39, 0.05, 26.8), 9.6, "move_forward", false)
	_check("airborne mantle triggered on a reachable ledge", bool(airborne["started"]),
			"%d frames" % int(airborne["frames"]))
	_check("airborne mantle put the player on top of the ledge",
			absf(float(airborne["end_y"]) - 1.9) < 0.25, str(airborne["end_position"]))
	_check("mantle handed back forward speed rather than stopping dead",
			float(airborne["exit_speed"]) > 1.0, "%.2f" % float(airborne["exit_speed"]))
	_check_mantle_hands(airborne)

	# Standing still against the face and pressing jump: the other branch, and the
	# one that would fire the jump instead if the buffer were not spent on it.
	var jumped := await _mantle_probe(Vector3(-39, 0.05, 26.8), 0.0, "move_forward", true)
	_check("jump press mantles from a standstill", bool(jumped["started"]),
			"%d frames" % int(jumped["frames"]))
	_check("jump press mantles straight off the ground rather than jumping first",
			bool(jumped["floor_at_start"]), "%d frames" % int(jumped["frames"]))
	_check("jump press mantle put the player on top of the ledge",
			absf(float(jumped["end_y"]) - 1.9) < 0.25, str(jumped["end_position"]))

	# The 18m arena wall. The face probe would hit, but the overhead one does too,
	# which is the check that separates a lip from a wall — and a jump press must
	# not talk it round.
	var wall := await _mantle_probe(Vector3(-45.5, 0.05, 20), 0.0, "move_left", true)
	_check("mantle refuses a wall with no lip in reach", not bool(wall["started"]),
			str(wall["end_position"]))

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	await _idle(2)


## Puts the player at `from`, lets them come to rest on the floor, then hands them
## `launch_vy` and holds `action` (plus the jump action if `with_jump`). Reports
## whether a mantle fired and where they ended up.
##
## The settle matters: teleporting mid-fall leaves the player genuinely airborne
## with coyote time already expired, which is a state a mantle is *allowed* to
## fire from — so without it the grounded cases would prove nothing.
##
## `launch_vy` is set directly rather than by pressing jump so the airborne branch
## can be exercised without the jump-press one covering for it.
func _mantle_probe(from: Vector3, launch_vy: float, action: String,
		with_jump: bool) -> Dictionary:
	_player.global_position = from
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	var settle := 0
	while not _player.is_on_floor() and settle < 90:
		await _idle(1)
		settle += 1
	_player.velocity = Vector3(0, launch_vy, 0)

	_press_action(action)
	if with_jump:
		_press_action("jump")

	# Sampled the moment the mantle starts. A mantle drives position directly and
	# never calls move_and_slide, so is_on_floor() is frozen at whatever it was on
	# the frame the pull-up began — which is exactly "did this fire from the
	# ground", and so which of the two branches let it through.
	var started := false
	var floor_at_start := false
	var frames := 0
	while frames < 90 and not started:
		await _idle(1)
		frames += 1
		started = _player.is_mantling()
		floor_at_start = _player.is_on_floor()

	# Every frame the hands are fully on the ledge. Keyed off the weight the rig
	# actually applied rather than off the mantle phase: animation runs on the idle
	# loop and this runs on the physics one, so a phase read here is not the phase
	# the pose was built from.
	var samples: Array[Dictionary] = []
	var guard := 0
	while _player.is_mantling() and guard < 90:
		await _idle(1)
		guard += 1
		if _player.hands.grab_weight() >= 0.999:
			samples.append(_hand_sample())
	var exit_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_release_action(action)
	if with_jump:
		_release_action("jump")
	await _idle(2)
	return {
		"started": started,
		"settled": settle < 90,
		"floor_at_start": started and floor_at_start,
		"frames": frames,
		"exit_speed": exit_speed,
		"hand_samples": samples,
		"end_y": _player.global_position.y,
		"end_position": str(_player.global_position),
	}


## Everything worth knowing about the view model on one frame of a mantle.
func _hand_sample() -> Dictionary:
	return {
		"left": _player.hands.hand_position(WeaponController.HAND_LEFT),
		"right": _player.hands.hand_position(WeaponController.HAND_RIGHT),
		"camera": _player.camera.global_position,
		"grab": _player.mantle_grab_point(),
		"phase": _player.mantle_phase(),
		"stow": _player.weapons.stow_amount(),
		"fired": _player.weapons.try_fire(),
	}


## The ledge grab. The hands are pinned to a point in the *world* rather than to
## the camera, so the assertion that matters is that they hold still while the body
## climbs past them — a rig that merely animated in view space would ride along
## with it and never look like it was holding anything.
func _check_mantle_hands(probe: Dictionary) -> void:
	var samples: Array = probe["hand_samples"]
	_check("the hands spent real time fully on the ledge", samples.size() >= 3,
			"%d frames" % samples.size())
	if samples.size() < 3:
		return
	# First and last of the planted window, so the drift below covers all of it.
	var first: Dictionary = samples[0]
	var last: Dictionary = samples[-1]
	var grab: Vector3 = first["grab"]

	for side: String in ["left", "right"]:
		var reach: float = (first[side] as Vector3).distance_to(grab)
		_check("%s hand reached the ledge it is holding" % side, reach < 0.35,
				"%.2f m from %s" % [reach, grab])

	var drift: float = (last["right"] as Vector3).distance_to(first["right"])
	var climb: float = (last["camera"] as Vector3).distance_to(first["camera"])
	_check("the body climbed between the two samples", climb > 0.10, "%.2f m" % climb)
	_check("the hands stayed put on the ledge while it did", drift < 0.03,
			"%.3f m between phase %.2f and %.2f"
					% [drift, float(first["phase"]), float(last["phase"])])
	_check("the weapon was stowed while both hands were busy",
			float(last["stow"]) > 0.5, "%.2f" % float(last["stow"]))
	_check("firing is refused mid-mantle",
			not bool(first["fired"]) and not bool(last["fired"]), "")


## Crouch-sliding is the only way to move faster than the run ceiling under your
## own power, and the boost is meant to outlive the crouch key: stand up and you
## keep it for a moment before running settles you back. All three beats are
## asserted, because each has its own way of going wrong — a slide that never
## boosts, a stand-up that clips the boost off on the first frame (which is what
## GROUND_FRICTION did before `Player.MOMENTUM_DECAY` existed), and a boost that
## never decays and just becomes the new run speed.
##
## Driven along x = -18 heading -Z, which is 50m of bare plaza: no pillar, prop
## or pad is within reach of the ~45m the run below covers. Placed with the
## mantle case, ahead of the first wave, so nothing can walk into it.
func _test_slide() -> void:
	var ceiling := GameState.stat("move_speed") * Player.MAX_SPEED_MULT

	_player.global_position = Vector3(-18, 0.3, 42)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	var settle := 0
	while not _player.is_on_floor() and settle < 90:
		await _idle(1)
		settle += 1
	_check("slide probe settled the player on the floor first", settle < 90, "")

	# Up to the ceiling first. A slide needs SLIDE_MIN_SPEED to start at all, and
	# "boost" only means anything measured against what running alone manages.
	_press_action("move_forward")
	await get_tree().create_timer(1.0).timeout
	var running := _planar_speed()
	_check("running alone reaches the run ceiling", running > ceiling - 0.5,
			"%.2f vs ceiling %.2f" % [running, ceiling])

	_press_action("crouch")
	await _idle(6)
	_check("crouching at speed starts a slide", _player.is_sliding(), "")
	var sliding := _planar_speed()
	_check("the slide carries speed past the run ceiling", sliding > ceiling + 1.0,
			"%.2f vs ceiling %.2f" % [sliding, ceiling])

	# Standing up hands the boost to running rather than clipping it away.
	_release_action("crouch")
	await _idle(6)
	var kept := _planar_speed()
	_check("standing up out of a slide keeps the boost",
			not _player.is_sliding() and kept > ceiling + 0.5,
			"%.2f vs ceiling %.2f" % [kept, ceiling])

	# Long enough for MOMENTUM_DECAY to have eaten a whole SLIDE_BOOST twice over.
	await get_tree().create_timer(2.5).timeout
	var settled := _planar_speed()
	_release_action("move_forward")
	_check("running spends the slide boost and settles back at the ceiling",
			settled < ceiling + 0.2 and settled > ceiling - 0.5,
			"%.2f vs ceiling %.2f" % [settled, ceiling])

	await _check_camera_roll()

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	await _idle(2)


## The horizon tilt, which is a hint and not a manoeuvre. Both halves are worth
## holding: it is bounded by construction — a fraction of the run ceiling, never
## raw m/s, so no amount of carried momentum can lever it further over — and it
## has to land back at *exactly* level, because a lerp on its own only approaches
## zero and leaves a sliver of tilt on screen for as long as the player stands
## still.
##
## Strafes left rather than right so the strafe and slide terms add instead of
## cancelling: that sum is the worst the view ever gets.
func _check_camera_roll() -> void:
	var most := Player.STRAFE_ROLL + Player.SLIDE_ROLL

	# Pitch lives on the pivot and yaw on the body, so roll is the *only* thing the
	# camera node's own basis is ever allowed to hold. An authored rotation on it in
	# player.tscn reads as a permanent head tilt that no amount of standing still
	# will level out, and because `_tick_camera()` writes .z and leaves .x and .y
	# alone, nothing in the game ever takes it back off again. It also aims every
	# shot somewhere the crosshair is not.
	_check("the camera node itself carries no pitch or yaw of its own",
			absf(_player.camera.rotation.x) < 0.0001
					and absf(_player.camera.rotation.y) < 0.0001,
			str(_player.camera.rotation))

	_player.global_position = Vector3(-10, 0.3, 30)
	_player.rotation.y = 0.0
	_player.velocity = Vector3.ZERO
	await _idle(4)

	_press_action("move_left")
	await get_tree().create_timer(1.0).timeout
	var strafing := absf(_player.camera.rotation.z)
	_check("a flat-out strafe tilts the horizon, but only a little",
			strafing > 0.002 and strafing <= Player.STRAFE_ROLL + 0.001,
			"%.4f rad vs cap %.4f" % [strafing, Player.STRAFE_ROLL])

	_press_action("crouch")
	await _idle(20)
	var slid := absf(_player.camera.rotation.z)
	_release_action("crouch")
	_release_action("move_left")
	_check("a slide leans further, and still no further than both terms together",
			slid > strafing and slid <= most + 0.001,
			"%.4f rad vs cap %.4f" % [slid, most])

	await get_tree().create_timer(1.5).timeout
	_check("the horizon returns to exactly level once the player stops",
			_player.camera.rotation.z == 0.0, "%.5f rad" % _player.camera.rotation.z)


func _planar_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _test_pause_menu() -> void:
	var pause_menu := _main.get_node_or_null("PauseMenu") as PauseMenu
	var character_menu := _main.get_node_or_null("CharacterMenu") as CharacterMenu
	_check("pause menu present", pause_menu != null, "")
	if pause_menu == null:
		return

	var resume_btn := pause_menu.get_node_or_null("Panel/Root/MainPanel/ResumeButton") as Button
	var settings_btn := pause_menu.get_node_or_null("Panel/Root/MainPanel/SettingsButton") as Button
	var quit_btn := pause_menu.get_node_or_null("Panel/Root/MainPanel/QuitButton") as Button
	var back_btn := pause_menu.get_node_or_null("Panel/Root/SettingsPanel/SettingsBackButton") as Button
	var main_panel := pause_menu.get_node_or_null("Panel/Root/MainPanel") as Control
	var settings_panel := pause_menu.get_node_or_null("Panel/Root/SettingsPanel") as Control
	_check("pause menu buttons present",
			resume_btn != null and settings_btn != null and quit_btn != null and back_btn != null, "")

	_press_ui_cancel()
	await _idle(2)
	_check("esc opened the pause menu", pause_menu.visible, "")
	_check("esc paused the game", get_tree().paused, "")

	settings_btn.pressed.emit()
	await _idle(1)
	_check("settings button opened the settings panel",
			settings_panel.visible and not main_panel.visible, "")

	var sensitivity_slider := pause_menu.get_node_or_null(
			"Panel/Root/SettingsPanel/SensitivitySlider") as HSlider
	if sensitivity_slider != null:
		# Must land exactly on the slider's step grid (min 0.0005, step 0.0002).
		sensitivity_slider.value = 0.0045
		await _idle(1)
		_check("sensitivity slider updated the player",
				is_equal_approx(_player.mouse_sensitivity, 0.0045), str(_player.mouse_sensitivity))
		_check("sensitivity slider persisted to settings",
				is_equal_approx(Settings.mouse_sensitivity, 0.0045), str(Settings.mouse_sensitivity))
		_check("sensitivity change saved to disk", FileAccess.file_exists(Settings.SAVE_PATH), "")

	var fov_slider := pause_menu.get_node_or_null("Panel/Root/SettingsPanel/FovSlider") as HSlider
	if fov_slider != null:
		fov_slider.value = 100.0
		await _idle(1)
		_check("fov slider persisted to settings",
				is_equal_approx(Settings.fov, 100.0), str(Settings.fov))

	await _test_keybindings(pause_menu)

	back_btn.pressed.emit()
	await _idle(1)
	_check("back button returned to the main panel",
			main_panel.visible and not settings_panel.visible, "")

	resume_btn.pressed.emit()
	await _idle(2)
	_check("resume button closed the pause menu", not pause_menu.visible, "")
	_check("resume unpaused the game", not get_tree().paused, "")

	# Esc should close an open character menu rather than stack the pause menu on top.
	if character_menu != null:
		character_menu.open()
		await _idle(1)
		_press_ui_cancel()
		await _idle(2)
		_check("esc closed the character menu instead of opening pause",
				not character_menu.visible and not pause_menu.visible, "")


## Called from _test_pause_menu() with the settings panel already open.
func _test_keybindings(pause_menu: PauseMenu) -> void:
	var keybinds_btn := pause_menu.get_node_or_null(
			"Panel/Root/SettingsPanel/KeybindsButton") as Button
	var keybinds_panel := pause_menu.get_node_or_null("Panel/Root/KeybindsPanel") as Control
	var keybind_list := pause_menu.get_node_or_null(
			"Panel/Root/KeybindsPanel/Scroll/KeybindList") as VBoxContainer
	var keybinds_back_btn := pause_menu.get_node_or_null(
			"Panel/Root/KeybindsPanel/Footer/KeybindsBackButton") as Button
	var reset_btn := pause_menu.get_node_or_null(
			"Panel/Root/KeybindsPanel/Footer/ResetKeybindsButton") as Button
	_check("keybindings ui present",
			keybinds_btn != null and keybinds_panel != null and keybind_list != null
					and keybinds_back_btn != null and reset_btn != null, "")
	if keybinds_btn == null or keybinds_panel == null or keybind_list == null:
		return

	keybinds_btn.pressed.emit()
	await _idle(1)
	_check("keybindings button opened the keybinds panel", keybinds_panel.visible, "")
	_check("one row exists per rebindable action",
			keybind_list.get_child_count() == Settings.REBINDABLE_ACTIONS.size(),
			str(keybind_list.get_child_count()))

	var jump_index: int = Settings.REBINDABLE_ACTIONS.keys().find("jump")
	var jump_row := keybind_list.get_child(jump_index) as HBoxContainer
	var jump_button := jump_row.get_child(1) as Button
	var jump_default_label := jump_button.text

	jump_button.pressed.emit()
	await _idle(1)
	_check("rebind button entered listening state", jump_button.text == "Press a key…", jump_button.text)

	# Esc must cancel the capture rather than become the new binding.
	var esc_key := InputEventKey.new()
	esc_key.keycode = KEY_ESCAPE
	esc_key.pressed = true
	Input.parse_input_event(esc_key)
	await _idle(1)
	_check("esc cancelled the capture instead of rebinding",
			jump_button.text == jump_default_label, jump_button.text)
	_check("esc did not become a saved override", not Settings.keybinds.has("jump"), "")
	_check("pause menu still open after the cancelled capture", pause_menu.visible, "")

	# A real key should rebind, update the InputMap, and persist.
	jump_button.pressed.emit()
	await _idle(1)
	var new_key := InputEventKey.new()
	new_key.keycode = KEY_J
	new_key.pressed = true
	Input.parse_input_event(new_key)
	await _idle(1)
	_check("jump rebound to J",
			Settings.keybinds.get("jump", {}).get("code") == KEY_J, str(Settings.keybinds.get("jump")))
	var j_probe := InputEventKey.new()
	j_probe.keycode = KEY_J
	var j_label := j_probe.as_text().strip_edges()
	_check("input map actually fires jump on J",
			InputMap.event_is_action(new_key, "jump"), Settings.action_label("jump"))
	_check("jump button label reflects the new binding", jump_button.text == j_label,
			"%s vs %s" % [jump_button.text, j_label])
	_check("rebind saved to disk", FileAccess.file_exists(Settings.SAVE_PATH), "")

	reset_btn.pressed.emit()
	await _idle(1)
	_check("reset restored jump to its default binding",
			Settings.action_label("jump") == jump_default_label, Settings.action_label("jump"))
	_check("reset cleared the saved override", not Settings.keybinds.has("jump"), "")

	keybinds_back_btn.pressed.emit()
	await _idle(1)
	_check("keybindings back button returned to settings",
			not keybinds_panel.visible and pause_menu.visible, "")


func _press_ui_cancel() -> void:
	_press_action("ui_cancel")


func _press_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


## An action parsed as pressed stays held, and a held action never reports
## just_pressed again — so anything pressed twice has to be released between.
func _release_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)


func _test_shooting() -> void:
	var enemy: Enemy = load("res://scenes/enemies/enemy_grunt.tscn").instantiate()
	_main.add_child(enemy)
	enemy.global_position = Vector3(0, 0.3, 8)
	# Freeze it so it cannot wander out of the shot before we fire.
	enemy.set_physics_process(false)
	# equip() holds a short ready delay before the first shot will go off.
	await _weapon_ready()

	var inst := _player.weapons.current()
	var ammo_before := inst.ammo
	var health_before := enemy.health

	_check("trigger pull accepted", _player.weapons.try_fire(), "")
	await _idle(2)
	_check("firing consumed a round", inst.ammo == ammo_before - 1,
			"%d -> %d" % [ammo_before, inst.ammo])
	_check("hitscan damaged the enemy", enemy.health < health_before,
			"%.1f -> %.1f" % [health_before, enemy.health])

	# Reload path: empty the magazine, then let the timer run out.
	inst.ammo = 0
	_player.weapons.start_reload()
	_check("reload started", _player.weapons.is_reloading(), "")
	await get_tree().create_timer(inst.reload_duration() + 0.2).timeout
	_check("reload refilled the magazine", inst.ammo == inst.mag_size(),
			"%d / %d" % [inst.ammo, inst.mag_size()])

	# Kill it and confirm the rewards land.
	var xp_before := GameState.xp
	var scrap_before := GameState.scrap
	enemy.apply_damage(9999.0, false, enemy.global_position, Vector3.FORWARD)
	await _idle(2)
	_check("kill granted xp", GameState.xp > xp_before or GameState.level > 1,
			"%d -> %d" % [xp_before, GameState.xp])
	_check("kill granted scrap", GameState.scrap > scrap_before,
			"%d -> %d" % [scrap_before, GameState.scrap])

	# Back on the floor before physics resumes, or the next case starts mid-fall.
	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	_player.set_physics_process(true)
	await _idle(2)


## A held trigger has to deliver the weapon's rate of fire, not the frame rate's.
## Firing is polled on the idle loop, so a shot can only start on a frame; the
## cooldown carries the sliver it overran by, which is what keeps the two apart.
## Assign the interval outright instead — as this did until the carry went in —
## and every shot rounds up to a whole frame: the Shredder's 11/s measured 9.96
## at 60fps against 11.00 at 240, a tenth more damage for the better machine.
## This case can only see the rate the harness runs at, so it is the 60fps end of
## that pair, and it is the end that was wrong.
func _test_fire_rate() -> void:
	var index := -1
	for i in GameState.loadout.size():
		if GameState.loadout[i].data.id == "shredder":
			index = i
	_check("the automatic weapon is in the loadout", index >= 0, "")
	if index < 0:
		return
	var was_equipped := _player.weapons.current()
	_player.weapons.equip(index)
	await _weapon_ready()

	var inst := _player.weapons.current()
	var nominal := 1.0 / inst.fire_interval()
	_shots_seen = 0
	Events.ammo_changed.connect(_count_shot)

	_press_action("fire")
	var elapsed := 0.0
	while elapsed < 2.0:
		# Topped up every frame: a reload in the middle of the window would be
		# measured as a very slow weapon.
		inst.ammo = inst.mag_size()
		await _idle(1)
		elapsed += get_process_delta_time()
	_release_action("fire")
	Events.ammo_changed.disconnect(_count_shot)

	var rate := _shots_seen / elapsed
	_check("a held trigger fires at the weapon's own rate",
			rate > nominal * 0.94, "%.2f/s against a nominal %.2f/s" % [rate, nominal])

	if was_equipped != null:
		for i in GameState.loadout.size():
			if GameState.loadout[i] == was_equipped:
				_player.weapons.equip(i)
	await _weapon_ready()


func _count_shot(_instance) -> void:
	_shots_seen += 1


## How far an enemy can actually hit. `enemy.gd` steers on the horizontal plane,
## which is the documented crude-navigation behaviour, but for a while it *struck*
## on that plane too — so a player on a platform was inside punching range of
## everything on the floor underneath them, however high the platform was.
##
## `_test_speed_caps()` is what found it: it drops the player from 200m to measure
## terminal velocity, and the wave milling about below kept landing melee hits on
## a target in the stratosphere until one run killed them part-way through the
## measurement. That reads as a fall that never accelerated, so the failure
## surfaced three cases away from its cause and only on the seeds that spawned
## enough grunts near the drop.
##
## Both halves are asserted, because "nothing hit me" also passes when the enemy
## has simply stopped working.
func _test_enemy_reach() -> void:
	var enemy: Enemy = load("res://scenes/enemies/enemy_grunt.tscn").instantiate()
	_main.add_child(enemy)
	enemy.global_position = Vector3(0, 0.3, 20)
	await _idle(1)

	# Directly overhead, so the horizontal distance between them is nothing and the
	# only thing keeping the player safe is height. Physics off so they stay up
	# there rather than falling into range while the enemy winds up.
	_player.set_physics_process(false)
	_player.global_position = Vector3(0, 20, 20)
	_player.heal(_player.max_health)
	var health_before := _player.health
	# Comfortably past attack_windup plus a whole attack_cooldown.
	await get_tree().create_timer(2.0).timeout
	_check("an enemy cannot punch a player standing 20m above it",
			_player.health == health_before,
			"%.1f -> %.1f" % [health_before, _player.health])

	# The same enemy at the same horizontal distance still has to connect, or the
	# check above is passing because nothing attacks at all.
	_player.global_position = Vector3(0, 0.3, 21.6)
	health_before = _player.health
	await get_tree().create_timer(2.0).timeout
	_check("but it still lands one on a player standing next to it",
			_player.health < health_before,
			"%.1f -> %.1f" % [health_before, _player.health])

	_player.set_physics_process(true)
	await _check_enemy_cannot_ride(enemy)

	enemy.queue_free()
	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	_player.heal(_player.max_health)
	await _idle(2)


## The player is not scenery. An enemy that can stand on them rides wherever they
## go and blocks their movement from on top of their own head — which is how this
## surfaced: `_dash_probe()` teleports the player 18m up, a passenger came with
## them, and the dash spent its whole duration grinding against a grunt instead of
## travelling. Enemies chase until they are inside attack range rather than until
## they touch, so on a melee cooldown they used to keep shoving into the capsule
## until they had walked up it.
##
## What is asserted is the gap it settles at, not where it ends up. Enemies and
## the player collide symmetrically and that is worth keeping — the alternative,
## dropping the player off their mask, lets them overlap and the player's own
## depenetration pushes them out through the plaza — so nothing stops an enemy
## *placed* on the player's head from standing there. What can be ruled out is the
## walk-in that put it there, which is the thing that actually happens.
##
## Started outside its reach and left to close in over three seconds, which is
## long enough for two full attack cooldowns to come and go. Touching starts at
## the two radii together, 0.9m.
func _check_enemy_cannot_ride(enemy: Enemy) -> void:
	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	enemy.global_position = Vector3(0, 0.3, 30)
	enemy.velocity = Vector3.ZERO

	var closest := 999.0
	var highest := 0.0
	for _f in 180:
		await _idle(1)
		closest = minf(closest, enemy.global_position.distance_to(_player.global_position))
		highest = maxf(highest, enemy.global_position.y - _player.global_position.y)
	_check("a melee enemy holds its distance instead of shoving into the player",
			closest > 1.2, "closed to %.2f m" % closest)
	_check("so it never gets a footing on top of them", highest < 1.0,
			"got %.2f m above them" % highest)


## The hold pose. Hands are presentation, so what is worth asserting is the wiring
## that keeps them honest: each wrist sits exactly a palm's length behind the part
## of the weapon it is holding, switching weapons moves them, and a shot shifts
## them along with the kick rather than leaving them hanging in the air.
func _test_hands() -> void:
	var hands := _player.hands
	var weapons := _player.weapons
	_check("view hands built", hands != null
			and hands.hand_position(WeaponController.HAND_RIGHT) != Vector3.ZERO, "")
	if hands == null:
		return

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	weapons.equip(0)
	await _idle(2)

	for side in [WeaponController.HAND_LEFT, WeaponController.HAND_RIGHT]:
		var anchor := weapons.hand_anchor(side)
		_check("hand %d has a place on the weapon to be" % side, anchor != null, "")
		if anchor == null:
			continue
		# Exact, not approximate: the pose is assigned from the anchor rather than
		# eased towards it, so any drift here means something else is moving them.
		var gap := hands.hand_position(side).distance_to(anchor.global_position)
		_check("hand %d sits a palm's length behind what it holds" % side,
				absf(gap - HandRig.KNUCKLE_REACH) < 0.01,
				"%.3f vs %.3f" % [gap, HandRig.KNUCKLE_REACH])

	# Switching weapons rebuilds the anchors, which is the whole reason the hands
	# read them every frame instead of being placed once.
	var before_switch := hands.hand_position(WeaponController.HAND_LEFT)
	weapons.equip(1)
	await _idle(2)
	var support := weapons.hand_anchor(WeaponController.HAND_LEFT)
	_check("switching weapons moved the support hand",
			hands.hand_position(WeaponController.HAND_LEFT).distance_to(before_switch) > 0.02,
			str(hands.hand_position(WeaponController.HAND_LEFT)))
	_check("the support hand followed the new weapon rather than the old one",
			support != null and absf(hands.hand_position(WeaponController.HAND_LEFT)
					.distance_to(support.global_position) - HandRig.KNUCKLE_REACH) < 0.01, "")
	# The two weapons hold differently, so the rule that picks between them matters.
	_check("a carbine takes the off hand to the barrel",
			weapons.current().data.support_grip == WeaponData.SupportGrip.FOREGRIP,
			weapons.current().data.id)

	weapons.equip(0)
	await _weapon_ready()
	_check("a pistol cups the off hand instead",
			weapons.current().data.support_grip == WeaponData.SupportGrip.CUPPED,
			weapons.current().data.id)

	# Taken in the camera's frame rather than the world's. The question this asks is
	# whether the *rig* put the hand back, and in world space the answer is drowned
	# out by whatever moved the player: a wave enemy landing a hit knocks the body
	# along and kicks the camera's pitch, and both would read as a hand that never
	# settled. Converted at each sample rather than once, so the camera's own motion
	# divides out too.
	var rested := _hand_in_view(hands)
	_check("trigger pull accepted for the recoil check", weapons.try_fire(), "")
	# Two frames, not one: the pose is set on the idle loop and this runs on the
	# physics one, so the first frame back still reports the pose from before the
	# shot. See ViewHands.hand_position().
	await _idle(2)
	_check("the shot registered as recoil", weapons.recoil_strength() > 0.0,
			"%.2f" % weapons.recoil_strength())
	var kicked := rested.distance_to(_hand_in_view(hands))
	_check("recoil moved the hand with the weapon", kicked > 0.004, "%.4f m" % kicked)

	# And it has to settle back, or every shot would walk the hands out of frame.
	await get_tree().create_timer(0.6).timeout
	_check("the hand returned to its rest pose", rested.distance_to(_hand_in_view(hands)) < 0.004,
			"%.4f m" % rested.distance_to(_hand_in_view(hands)))


## The shooting hand's last drawn placement, in the camera's frame. See the note
## where the rest pose is taken for why this is not the world-space reading.
func _hand_in_view(hands: ViewHands) -> Vector3:
	return _player.camera.to_local(hands.hand_position(WeaponController.HAND_RIGHT))


## The body. Presentation again, so the assertions are the ones that would stop it
## being a body: that it is as tall as the collider claims, that its feet are on
## the floor rather than through it, that a crouch folds it instead of sinking it,
## and that the parts the camera sits inside are kept out of the frame without
## being kept out of the shadow.
func _test_body() -> void:
	var body := _player.body
	_check("player body built", body != null and body.head_top() > 0.0, "")
	if body == null:
		return

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	await _idle(6)
	var floor_y := _player.global_position.y

	var standing := body.head_top() - floor_y
	_check("body stands as tall as the collider says it is",
			absf(standing - Player.STAND_HEIGHT) < 0.05,
			"%.2f vs %.2f" % [standing, Player.STAND_HEIGHT])
	_check("body's feet are on the floor", absf(body.sole_height() - floor_y) < 0.04,
			"%.3f above the floor" % (body.sole_height() - floor_y))

	# The hands on the arms are the same class as the pair on the screen. That is
	# the whole point of HandRig, and it is one `_build_hand` away from silently
	# becoming two different hands again.
	_check("the body's arms end in the same hand rig the view model uses",
			body.hand(PlayerBody.SIDE_LEFT) is HandRig
					and body.hand(PlayerBody.SIDE_RIGHT) is HandRig, "")

	_check_body_visibility(body)
	await _check_body_weapon(body)
	await _check_body_crouch(body, standing)
	await _check_body_walk(body)


## Shadows-only is not the same as hidden: the arena still has to see a humanoid
## on the wall, and the player still must not have a chest across the screen.
func _check_body_visibility(body: PlayerBody) -> void:
	var skull := body.find_child("Skull", true, false) as MeshInstance3D
	var shin := body.find_child("Shin", true, false) as MeshInstance3D
	_check("body has a head and a shin to check", skull != null and shin != null, "")
	if skull == null or shin == null:
		return

	_check("the camera's own head is not drawn in front of it",
			skull.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			str(skull.cast_shadow))
	_check("but it still casts a shadow with a head on it",
			skull.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "")
	_check("the legs are drawn, so looking down finds them",
			shin.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			str(shin.cast_shadow))

	body.first_person = false
	_check("switching out of first person puts the whole model back",
			skull.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
			str(skull.cast_shadow))
	body.first_person = true


## The weapon in the body's fist — the one anybody but the player sees, and the
## only one a third-person camera renders.
##
## Three things are asserted, and none of them is "it looks right". It has to be
## the *equipped* weapon, or a switch has quietly stopped rebuilding it. It has to
## point where the player is facing, because the barrel's heading is five arm
## angles times a fixed grip and every one of those is a number somebody will
## retune for the pose rather than for the aim. And it has to sit far enough out
## from the centre line to clear a 0.21 half-chest plus the arm in front of it —
## the difference between a weapon a chase camera can see and one its owner is
## standing in front of.
func _check_body_weapon(body: PlayerBody) -> void:
	var weapon := body.weapon_model()
	_check("the body is holding the equipped weapon", weapon != null, "")
	if weapon == null:
		return
	_check("the weapon in the fist is the one that is equipped",
			_receiver_size(weapon) == _player.weapons.current().data.body_size,
			"%s vs %s" % [_receiver_size(weapon), _player.weapons.current().data.body_size])

	# In the player's own frame: -Z is where they are facing, +X the shooting side.
	var aim := _player.global_transform.basis.inverse() * -weapon.global_transform.basis.z
	_check("the body's weapon points where the player is facing", aim.z < -0.95,
			"%+.2f forward, %+.2f right, %+.2f up" % [-aim.z, aim.x, aim.y])

	var at := _player.to_local(weapon.global_position)
	_check("and sits out where a camera behind the player can see it", at.x > 0.30,
			"%.2f from the centre line" % at.x)
	_check("at the chest rather than up by the chin", at.y > 1.15 and at.y < 1.50,
			"%.2f off the ground" % at.y)

	# The rebuild wiring: a switch has to put the new weapon in the hand, not leave
	# the old one there with a new colour on it.
	var was := GameState.equipped_index
	_player.weapons.equip(1 if was == 0 else 0)
	await _idle(2)
	_check("switching weapons rebuilt the one in the fist",
			body.weapon_model() != null
					and _receiver_size(body.weapon_model()) == _player.weapons.current().data.body_size,
			str(_receiver_size(body.weapon_model())))
	_player.weapons.equip(was)
	await _weapon_ready()


## The receiver box of a built weapon model — the first mesh `build_model()` adds,
## and enough to tell one weapon's geometry from another's.
func _receiver_size(weapon: Node3D) -> Vector3:
	var mesh := weapon.get_child(0) as MeshInstance3D
	if mesh == null or mesh.mesh is not BoxMesh:
		return Vector3.ZERO
	return (mesh.mesh as BoxMesh).size


## A crouch has to take the head down and leave the feet where they are — the
## failure this catches is a pose that drops the hips without bending anything,
## which sinks the legs through the floor instead of folding them.
func _check_body_crouch(body: PlayerBody, standing: float) -> void:
	var floor_y := _player.global_position.y
	_press_action("crouch")
	await _idle(30)
	var crouched := body.head_top() - floor_y
	_check("crouching folds the body down", crouched < standing - 0.40,
			"%.2f from %.2f" % [crouched, standing])
	# Loosely near the collider it is crouching inside, and no tighter than that on
	# purpose. 1.05 wants thighs flat enough that the pose has no knee in it from
	# above, and the squat is the thing being looked at — so the model is the taller
	# of the two and the gap is a known one, not a regression.
	_check("crouched body is roughly as tall as the crouched collider",
			absf(crouched - Player.CROUCH_HEIGHT) < 0.35,
			"%.2f vs %.2f" % [crouched, Player.CROUCH_HEIGHT])
	_check("crouching kept the feet on the floor",
			absf(body.sole_height() - floor_y) < 0.05,
			"%.3f above the floor" % (body.sole_height() - floor_y))
	_check_eye_clears_the_knees(body)

	_release_action("crouch")
	await _idle(30)
	_check("standing back up returns the body to full height",
			absf((body.head_top() - floor_y) - standing) < 0.05,
			"%.2f vs %.2f" % [body.head_top() - floor_y, standing])


## Called mid-crouch. The eye has to be in front of the knees, not above them:
## that is the difference between looking down over the front of your own legs and
## looking straight through the middle of them at the floor. Two things buy it —
## `Player.EYE_FORWARD` moving the camera off the body's centre line, and
## `PlayerBody.CROUCH_SET_BACK` sliding the hips back as the squat deepens — and
## either one being lost quietly undoes it, so the property is asserted rather
## than the two numbers.
func _check_eye_clears_the_knees(body: PlayerBody) -> void:
	var knee := body.find_child("Knee", true, false) as Node3D
	_check("body has a knee to look over", knee != null, "")
	if knee == null:
		return
	# In the player's own frame, where -Z is forward.
	var eye := _player.to_local(_player.camera.global_position).z
	var knee_z := _player.to_local(knee.global_position).z
	_check("the crouched eye sits in front of the knees", eye < knee_z,
			"eye %.3f vs knee %.3f" % [eye, knee_z])


## Walking has to move the legs, and has to do it without lifting the body off the
## ground — the stride swings the hips and the bob rides on top of it, so this is
## the check that keeps the two of them in proportion to each other.
func _check_body_walk(body: PlayerBody) -> void:
	var hip := body.find_child("HipRight", true, false) as Node3D
	_check("body has a hip joint to swing", hip != null, "")
	if hip == null:
		return
	var floor_y := _player.global_position.y

	_press_action("move_forward")
	await _idle(12)
	var first := hip.rotation.x
	var lowest := body.sole_height()
	var swing := 0.0
	for _i in 24:
		await _idle(1)
		swing = maxf(swing, absf(hip.rotation.x - first))
		lowest = minf(lowest, body.sole_height())
	_release_action("move_forward")

	_check("walking swings the legs", swing > 0.15, "%.3f rad" % swing)
	_check("and never puts a foot through the floor",
			lowest > floor_y - 0.05, "%.3f below the floor" % (floor_y - lowest))

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	await _idle(4)


## The third-person review camera. It is a dev tool, so what is worth asserting is
## not how it looks but that the swap is complete in both directions: the chase
## camera is the one the viewport actually renders from, the body the first-person
## view keeps out of frame comes back, and the view model — which lives in front of
## the *other* camera — stops being drawn, or it hangs in the air through the
## player's head. Every one of those is a separate line in `set_third_person()` and
## any of them can be dropped without the other three noticing.
##
## Driven through the keybind rather than by calling the setter, because the key is
## how it will actually be used: watching a slide means toggling mid-run, not from
## a menu.
func _test_third_person() -> void:
	var skull := _player.body.find_child("Skull", true, false) as MeshInstance3D
	_check("body has a head to check the swap with", skull != null, "")
	if skull == null:
		return

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0
	await _idle(4)

	_check("the game starts in first person",
			not _player.third_person and _player.camera.current, "")

	_press_action("third_person")
	await _idle(2)
	_release_action("third_person")
	await _idle(2)

	_check("the key switched to third person", _player.third_person, "")
	_check("the viewport renders from the chase camera",
			get_viewport().get_camera_3d() == _player.third_person_camera,
			str(get_viewport().get_camera_3d()))
	# Behind the eye, in the player's own frame: -Z is forward, so the chase camera
	# has to be at positive Z and a long way from the head. A spring arm that never
	# extended would pass every other check here while sitting inside the skull.
	var offset := _player.to_local(_player.third_person_camera.global_position)
	_check("the chase camera is actually behind the player", offset.z > 1.0,
			"%.2f m back" % offset.z)
	_check("switching out of first person put the whole body back",
			skull.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
					and not _player.body.first_person, str(skull.cast_shadow))
	_check("the view model is not left floating through the head",
			not _player.weapons.visible and not _player.hands.visible, "")
	_check("the toggle persisted", Settings.third_person, "")
	# Aim still leaves the head down the pivot's direction, so the weapon has to go
	# on working from back here — the camera moved, not the gun.
	await _weapon_ready()
	_check("the weapon still fires in third person", _player.weapons.try_fire(), "")

	_press_action("third_person")
	await _idle(2)
	_release_action("third_person")
	await _idle(2)

	_check("the key switched back to first person",
			not _player.third_person and _player.camera.current, "")
	_check("the body is hidden from its own camera again",
			skull.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
					and _player.body.first_person, str(skull.cast_shadow))
	_check("the view model came back with it",
			_player.weapons.visible and _player.hands.visible, "")

	_reset_settings_files()


func _test_progression() -> void:
	# Skill points into agile, then buy the traversal perks it gates.
	GameState.skill_points += 4
	GameState.perk_points += 6
	GameState.level = 8
	for _i in 3:
		GameState.spend_skill_point("agile")
	_check("skill line ranked up", GameState.skill_rank("agile") == 3,
			str(GameState.skill_rank("agile")))

	var speed_before := GameState.stat("move_speed")
	_check("skills raised move speed", speed_before > 7.0, "%.2f" % speed_before)

	_check("double jump bought", GameState.unlock_perk("double_jump"), "")
	_check("double jump flag set", GameState.has_flag("double_jump"), "")
	_check("air jump stat applied", GameState.stat_int("air_jumps") == 1,
			str(GameState.stat_int("air_jumps")))
	_check("wall runner bought", GameState.unlock_perk("wall_runner"), "")
	_check("wall jump flag set", GameState.has_flag("wall_jump"), "")

	# Gating still has to bite: sky_dancer needs level 6 + agile 3, which we
	# have, but blink_step's second rank must stop when points run out.
	var blocked := GameState.perks.get("iron_gut") as PerkData
	_check("perk gated by wrong skill line", GameState.perk_block_reason(blocked) != "",
			GameState.perk_block_reason(blocked))

	# Weapon bench.
	GameState.scrap += 500
	var inst := GameState.loadout[0]
	var damage_before := inst.damage()
	var error := GameState.install_upgrade(inst, "heavy_rounds")
	_check("upgrade installed", error == "", error)
	_check("upgrade changed damage", inst.damage() > damage_before,
			"%.2f -> %.2f" % [damage_before, inst.damage()])
	_check("upgrade took a slot", inst.free_slots() == inst.data.upgrade_slots - 1,
			str(inst.free_slots()))
	_check("upgrade cannot be installed twice",
			GameState.install_upgrade(inst, "heavy_rounds") != "", "")

	var bought := GameState.buy_weapon("hellmouth")
	_check("weapon purchased", bought == "", bought)
	_check("loadout grew", GameState.loadout.size() == 3, str(GameState.loadout.size()))

	# Projectile weapon path. Fired from clear air above the arena, the way
	# `_dash_probe()` works: a shell only travels about a metre in the two frames
	# before it is counted, so anything standing in front of the muzzle detonates it
	# first and the count comes back empty. Wave enemies converge on the player, so
	# on the ground that is a coin toss rather than a test.
	var was_at := _player.global_position
	_player.global_position = Vector3(0, 20, 20)
	_player.weapons.equip(2)
	await _weapon_ready()
	var launcher := _player.weapons.current()
	_check("equipped the launcher", launcher.data.id == "hellmouth", launcher.data.id)
	var shells := launcher.ammo
	_player.weapons.try_fire()
	await _idle(2)
	_check("launcher fired a shell", launcher.ammo == shells - 1,
			"%d -> %d" % [shells, launcher.ammo])
	_check("shell spawned a projectile", _count_projectiles() > 0, str(_count_projectiles()))
	_player.weapons.equip(0)
	_player.global_position = was_at
	_player.velocity = Vector3.ZERO


## The dash lends speed rather than setting it: entry speed + "dash_boost" for
## the duration, back to entry speed on exit. Vertically it holds its height,
## then a climb resumes and a fall restarts from zero.
## Runs after _test_progression() so the agile line is already ranked up enough
## to buy Blink Step.
func _test_dash() -> void:
	_require_alive("the dash")
	GameState.perk_points += 5
	GameState.unlock_perk("blink_step")
	_check("blink step bought", GameState.has_flag("dash"), "")
	if not GameState.has_flag("dash"):
		return
	_check("dash charge granted", GameState.stat("dash_charges") >= 1.0,
			str(GameState.stat("dash_charges")))
	_check("dash boost is a known stat", GameState.BASE_STATS.has("dash_boost"), "")

	var boost := GameState.stat("dash_boost")
	var rising := await _dash_probe(9.0, 10.0)
	_check("dash added its boost on top of entry speed",
			absf(float(rising["dash_speed"]) - (10.0 + boost)) < 0.4,
			"%.2f vs 10.00 + %.2f" % [float(rising["dash_speed"]), boost])
	_check("dash handed entry speed back on exit",
			absf(float(rising["exit_speed"]) - 10.0) < 0.5,
			"%.2f vs 10.00" % float(rising["exit_speed"]))
	_check("dash carried the player forward", float(rising["travel"]) > 3.5,
			"%.2f m" % float(rising["travel"]))
	_check("dash held its height", absf(float(rising["drift"])) < 0.15,
			"%.3f m" % float(rising["drift"]))
	_check("dash preserved upward momentum on exit", float(rising["exit_vy"]) > 6.5,
			"%.2f entering 9.00" % float(rising["exit_vy"]))

	var falling := await _dash_probe(-14.0, 0.0)
	_check("dash fired from a standstill while falling", float(falling["travel"]) > 2.0,
			"%.2f m" % float(falling["travel"]))
	_check("dash reset downward momentum on exit",
			float(falling["exit_vy"]) > -3.0 and float(falling["exit_vy"]) < 0.5,
			"%.2f entering -14.00" % float(falling["exit_vy"]))

	await _check_body_dash()
	await _test_dash_boost_perk(boost)
	await _test_speed_caps()


## The dash pose. A dash is neither a fast run nor a fall: the body is thrown
## along it and the legs stream out behind. The numbers that do that are tuning,
## so what is asserted is the three properties they exist to produce — the feet
## end up behind the hips, the chest is out over them, and the hips do not sink
## while it happens. The last is the one that breaks silently: hip height is
## derived from the leg angles so the soles stay on the ground, and legs swung
## out behind the body are the one case that does not describe, so feeding the
## fling into it drops the body half a metre to chase boots that have left the
## floor.
func _check_body_dash() -> void:
	var body := _player.body
	_check("body is there to strike the dash pose", body != null, "")
	if body == null:
		return
	var hip := body.find_child("HipRight", true, false) as Node3D
	var hips := body.find_child("Hips", true, false) as Node3D
	var spine := body.find_child("Spine", true, false) as Node3D
	var ankle: Node3D = null
	if hip != null:
		ankle = hip.find_child("Ankle", true, false) as Node3D
	_check("body has a leg to fling", ankle != null and hips != null and spine != null, "")
	if ankle == null or hips == null or spine == null:
		return

	# Airborne and well clear of the arena, like _dash_probe: the pose is read off
	# nodes between two frames, and a grunt shoving the body mid-sample would move
	# every one of them.
	_player._dash_charges = 1.0
	_player.global_position = Vector3(0, 18, 8)
	_player.velocity = Vector3.ZERO
	await _idle(4)
	# Taken airborne rather than standing, so the only thing between this reading
	# and the one below is the dash itself.
	var hips_before := hips.position.y
	_press_action("dash")
	# Long enough for the pose to have eased in (about a tenth of a second) and
	# still comfortably inside DASH_TIME.
	await _idle(10)

	var dashing := _player.is_dashing()
	var foot := _player.to_local(ankle.global_position).z
	var hip_z := _player.to_local(hip.global_position).z
	var lean := spine.rotation.x
	var hips_y := hips.position.y
	_release_action("dash")

	_check("still dashing when the pose was read", dashing, "")
	# Player-local, where -Z is forward: a foot behind its own hip is a leg the
	# body has been flung out from under.
	_check("dashing leaves the legs trailing behind the hips", foot - hip_z > 0.15,
			"foot %.3f vs hip %.3f" % [foot, hip_z])
	# Forward lean is quoted forward-positive and negated onto the spine.
	_check("and throws the chest forward over them", lean < -0.2, "%.3f rad" % lean)
	_check("without sinking the hips into the legs it just swung back",
			absf(hips_y - hips_before) < 0.06,
			"%.3f vs %.3f before the dash" % [hips_y, hips_before])

	await _wait_out_dash()
	await _check_body_dash_sideways(hip, ankle, spine)

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	await _idle(2)


## The same fling taken sideways, which is where the signs are: the pose rolls
## about Z instead of pitching about X, and it is one lean rather than two —
## the chest goes over into the dash and the feet come out from under it, the
## way a body leans off its own contact patch. Get either sign backwards and a
## strafing dash falls away from the direction it is travelling.
func _check_body_dash_sideways(hip: Node3D, ankle: Node3D, spine: Node3D) -> void:
	_player._dash_charges = 1.0
	_player.global_position = Vector3(0, 18, 8)
	_player.velocity = Vector3.ZERO
	await _idle(4)
	# The dash takes its heading from the movement keys at the moment it fires.
	_press_action("move_right")
	await _idle(2)
	_press_action("dash")
	await _idle(10)

	var dashing := _player.is_dashing()
	var foot := _player.to_local(ankle.global_position).x
	var hip_x := _player.to_local(hip.global_position).x
	var roll := spine.rotation.z
	_release_action("dash")
	_release_action("move_right")

	_check("still dashing when the sideways pose was read", dashing, "")
	_check("a dash to the right sweeps the feet out to the left",
			foot - hip_x < -0.1, "foot %.3f vs hip %.3f" % [foot, hip_x])
	_check("and tips the chest over the way it is going", roll < -0.1,
			"%.3f rad" % roll)
	await _wait_out_dash()


func _wait_out_dash() -> void:
	var guard := 0
	while _player.is_dashing() and guard < 120:
		await _idle(1)
		guard += 1


## The whole point of routing the boost through a stat: buying the perk in the
## menu has to change what the dash actually does, with no code in between.
func _test_dash_boost_perk(boost_before: float) -> void:
	var perk := GameState.perks.get("kinetic_surge") as PerkData
	_check("dash boost perk exists in the library", perk != null, "")
	if perk == null:
		return
	_check("dash boost perk is buyable now", GameState.perk_block_reason(perk) == "",
			GameState.perk_block_reason(perk))
	_check("dash boost perk bought", GameState.unlock_perk("kinetic_surge"), "")

	var boost_after := GameState.stat("dash_boost")
	_check("perk raised the dash boost stat", boost_after > boost_before,
			"%.2f -> %.2f" % [boost_before, boost_after])

	var probe := await _dash_probe(0.0, 8.0)
	_check("upgraded boost reached the dash itself",
			absf(float(probe["dash_speed"]) - (8.0 + boost_after)) < 0.4,
			"%.2f vs 8.00 + %.2f" % [float(probe["dash_speed"]), boost_after])

	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	await _idle(2)


## Air control used to have no ceiling at all — a held direction accelerated for
## as long as you stayed airborne — so these guard the caps that bound running.
func _test_speed_caps() -> void:
	_require_alive("the speed caps")
	var ceiling := GameState.stat("move_speed") * Player.MAX_SPEED_MULT

	# Launched straight up so there is ~1.7s of air time to accelerate through.
	_player.global_position = Vector3(0, 6, 20)
	_player.velocity = Vector3(0, 22, 0)
	_press_action("move_forward")
	await get_tree().create_timer(1.5).timeout
	var planar := Vector2(_player.velocity.x, _player.velocity.z).length()
	_release_action("move_forward")
	_check("held direction cannot accelerate past the run ceiling",
			planar <= ceiling + 0.5, "%.2f vs ceiling %.2f" % [planar, ceiling])

	# Terminal velocity, waited out by watching the speed stop changing rather than
	# by counting out the 1.31s it nominally takes. Gravity is skipped on any step
	# the body spends dashing, mantling or still reporting the floor it was
	# teleported off, so a fixed budget can silently come up a few m/s short — and
	# does. Dropped from high enough that it cannot reach the plaza first.
	_player.global_position = Vector3(0, 200, 20)
	_player.velocity = Vector3.ZERO
	var previous := 0.0
	var falling := 0
	while falling < 300:
		await _idle(1)
		falling += 1
		# Clamped to exactly -MAX_FALL_SPEED once it arrives, so "settled" is exact.
		if falling > 4 and _player.velocity.y == previous:
			break
		previous = _player.velocity.y
	_check("fall speed is capped at terminal velocity",
			_player.velocity.y > -Player.MAX_FALL_SPEED - 0.5
					and _player.velocity.y < -Player.MAX_FALL_SPEED + 1.0,
			"%.2f vs cap %.2f after %d frames" % [_player.velocity.y,
					-Player.MAX_FALL_SPEED, falling])

	# Anything that hands out more rise than the cap gets clamped on the next
	# airborne frame rather than sailing over the arena.
	_player.global_position = Vector3(0, 20, 20)
	_player.velocity = Vector3(0, 40, 0)
	await _idle(2)
	_check("rise speed is capped", _player.velocity.y <= Player.MAX_RISE_SPEED,
			"%.2f vs cap %.2f" % [_player.velocity.y, Player.MAX_RISE_SPEED])


## Drops the player into clear air above the arena carrying `entry_vy` and
## `entry_speed` (the latter along -Z, which is also the way they are facing and
## so the way they will dash), presses the real dash action, and reports what
## the dash did to their speed, height and travel.
func _dash_probe(entry_vy: float, entry_speed: float) -> Dictionary:
	# Hand the charge over rather than waiting out the ~2.5s cooldown: the first
	# wave spawns on a wall-clock timer from level load, and two probes' worth of
	# waiting here is enough to shift what the later cases see.
	_player._dash_charges = 1.0
	_player.global_position = Vector3(0, 18, 8)
	_player.velocity = Vector3.ZERO
	# is_on_floor() reports the last move_and_slide(), so the frame right after a
	# teleport into the air still counts as grounded — and would bleed the entry
	# speed off at ground friction. Let it fall clear before handing it speed.
	await _idle(1)
	_player.velocity = Vector3(0, entry_vy, -entry_speed)

	var start := _player.global_position
	_press_action("dash")

	# Sample a third of the way in — comfortably mid-dash for any DASH_TIME worth
	# tuning to, without hard-coding a frame count that goes stale the next time
	# the dash is lengthened or shortened.
	var dash_frames := int(ceil(Player.DASH_TIME * Engine.physics_ticks_per_second))
	await _idle(maxi(2, dash_frames / 3))
	var drift := _player.global_position.y - start.y
	var dash_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_release_action("dash")

	# Then wait the dash out and let exactly two frames of gravity act on the
	# vertical speed it handed back, so exit_vy is read close to the handover.
	var guard := 0
	while _player._dash_time_left > 0.0 and guard < dash_frames * 3 + 10:
		await _idle(1)
		guard += 1
	await _idle(2)
	return {
		"drift": drift,
		"dash_speed": dash_speed,
		"travel": Vector2(_player.global_position.x - start.x,
				_player.global_position.z - start.z).length(),
		"exit_vy": _player.velocity.y,
		"exit_speed": Vector2(_player.velocity.x, _player.velocity.z).length(),
	}


## Drives the HUD's category-aware points label by emitting Events.stats_changed
## (the same signal the HUD already listens to) rather than calling its private
## refresh method directly. Restores GameState afterwards.
func _test_hud_points_label() -> void:
	var hud := _main.get_node_or_null("HUD") as HUD
	var points_label: Label = null
	if hud != null:
		points_label = hud.get_node_or_null("XPPanel/PointsLabel") as Label
	_check("points label present", points_label != null, "")
	if points_label == null:
		return

	var skill_before := GameState.skill_points
	var perk_before := GameState.perk_points

	GameState.skill_points = 0
	GameState.perk_points = 0
	Events.stats_changed.emit()
	await _idle(1)
	# The bench itself can still have an affordable upgrade regardless of SP/PP,
	# so only assert "hidden" when that's actually the case right now.
	var bench_idle := GameState.affordable_bench_upgrade_count()
	_check("points label visibility matches whether anything is spendable",
			points_label.visible == (bench_idle > 0),
			"visible=%s bench_available=%d" % [points_label.visible, bench_idle])

	if bench_idle == 0:
		GameState.skill_points = 4
		Events.stats_changed.emit()
		await _idle(1)
		_check("skill-only label names SP", points_label.text.begins_with("4 SP available"),
				points_label.text)
		GameState.skill_points = 0

		GameState.perk_points = 3
		Events.stats_changed.emit()
		await _idle(1)
		_check("perk-only label names PP", points_label.text.begins_with("3 PP available"),
				points_label.text)
		GameState.perk_points = 0

	GameState.skill_points = 1
	GameState.perk_points = 1
	Events.stats_changed.emit()
	await _idle(1)
	_check("multiple categories collapse to one line",
			points_label.text.begins_with("Multiple upgrades available"), points_label.text)

	# The bench count itself should actually respond to Metal, not just exist.
	var scrap_before := GameState.scrap
	GameState.scrap = 0
	_check("no Metal means no affordable bench upgrades",
			GameState.affordable_bench_upgrade_count() == 0, "")
	GameState.scrap = 999999
	_check("plenty of Metal makes bench upgrades affordable",
			GameState.affordable_bench_upgrade_count() > 0, "")
	GameState.scrap = scrap_before

	GameState.skill_points = skill_before
	GameState.perk_points = perk_before
	Events.stats_changed.emit()
	await _idle(1)


func _test_persistence() -> void:
	GameState.save_game()
	var level := GameState.level
	var perks := GameState.perk_ranks.duplicate()
	var upgrades := GameState.loadout[0].upgrade_ids()

	GameState.reset_progress(false)
	_check("reset cleared perks", GameState.perk_ranks.is_empty(), "")

	_check("save reloaded", GameState.load_game(), "")
	GameState.rebuild()
	_check("level survived the round trip", GameState.level == level,
			"%d vs %d" % [GameState.level, level])
	_check("perks survived the round trip", GameState.perk_ranks == perks, "")
	_check("weapon upgrades survived the round trip",
			GameState.loadout[0].upgrade_ids() == upgrades, "")
	_check("flags rebuilt from the save", GameState.has_flag("double_jump"), "")


func _test_waves() -> void:
	var spawner := _main.get_node_or_null("Level/Spawner")
	_check("spawner present", spawner != null, "")
	if spawner == null:
		return

	# first_wave_delay is 6s in the arena; give it a little margin.
	var waited := 0.0
	while not _wave_started and waited < 10.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_check("first wave started", _wave_started, "%.1fs" % waited)

	# The wave signal fires before the first body exists — spawns are staggered
	# by spawn_interval — so give the spawner a moment to actually produce them.
	waited = 0.0
	while get_tree().get_nodes_in_group("enemies").size() < 2 and waited < 4.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_check("enemies exist", get_tree().get_nodes_in_group("enemies").size() > 0,
			str(get_tree().get_nodes_in_group("enemies").size()))

	# Standing on the floor before any of this is measured. `_test_speed_caps()`
	# hands the player over mid-launch off the rise cap — 20 m up and climbing at
	# 21 m/s — and an enemy that cannot fly loses ground to that however hard it
	# chases, which is what used to fail here.
	_player.global_position = Vector3(0, 0.3, 34)
	_player.velocity = Vector3.ZERO
	var settle := 0
	while not _player.is_on_floor() and settle < 90:
		await _idle(1)
		settle += 1
	_check("player settled on the floor before the chase is watched", settle < 90, "")

	# Enemies should close on the player rather than stand still. Everything not
	# already in melee range is watched, and one of them closing is the assertion:
	# enemy.gd has no navigation, so a single spawn stuck behind a platform is the
	# documented behaviour rather than a regression. All of them stuck is not.
	#
	# Measured flat, because chasing is a horizontal act here: `enemy.gd` steers on
	# the xz plane and only leaves the ground to hop a wall, so counting height in
	# would make the player's own footing part of the enemy's score.
	var watched: Array[Enemy] = []
	var before: Array[float] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var candidate := node as Enemy
		var distance := _flat_distance(candidate.global_position, _player.global_position)
		if distance > 8.0:
			watched.append(candidate)
			before.append(distance)
	if watched.is_empty():
		return

	await get_tree().create_timer(1.5).timeout
	var closed := 0
	var alive := 0
	var best := 0.0
	for index in watched.size():
		if not is_instance_valid(watched[index]):
			continue
		alive += 1
		var now := _flat_distance(watched[index].global_position, _player.global_position)
		var gained := before[index] - now
		best = maxf(best, gained)
		if gained > 0.0:
			closed += 1
	if alive == 0:
		return
	_check("enemies closed the distance", closed > 0,
			"%d of %d moved in, best %.1f m" % [closed, alive, best])


## Run after _test_waves() so unchecking this can't disturb the earlier
## first-wave timing assertion.
func _test_spawn_toggle() -> void:
	var spawner := _main.get_node_or_null("Level/Spawner")
	var pause_menu := _main.get_node_or_null("PauseMenu") as PauseMenu
	_check("spawn toggle test setup", spawner != null and pause_menu != null, "")
	if spawner == null or pause_menu == null:
		return

	_check("spawn enemies enabled by default", Settings.spawn_enemies_enabled, "")
	_check("spawner active by default", spawner.is_active(), "")

	pause_menu.open()
	var settings_btn := pause_menu.get_node_or_null("Panel/Root/MainPanel/SettingsButton") as Button
	var check := pause_menu.get_node_or_null(
			"Panel/Root/SettingsPanel/SpawnEnemiesCheck") as CheckBox
	settings_btn.pressed.emit()
	await _idle(1)
	_check("spawn enemies checkbox present and checked", check != null and check.button_pressed, "")

	check.button_pressed = false
	await _idle(2)
	_check("unchecking stopped the spawner", not spawner.is_active(), "")
	_check("unchecking cleared existing enemies",
			get_tree().get_nodes_in_group("enemies").is_empty(),
			str(get_tree().get_nodes_in_group("enemies").size()))
	_check("disabling saved to settings", not Settings.spawn_enemies_enabled, "")

	check.button_pressed = true
	await _idle(2)
	_check("re-checking restarted the spawner", spawner.is_active(), "")
	_check("re-enabling saved to settings", Settings.spawn_enemies_enabled, "")

	pause_menu.close()


# --- Helpers ----------------------------------------------------------------

func _check(what: String, passed: bool, detail: String) -> void:
	_checks += 1
	if passed:
		print("ok    %s" % what)
	else:
		_failures.append("%s  (%s)" % [what, detail])
		print("FAIL  %s  (%s)" % [what, detail])


## Suspends wave spawning and clears the arena, or sets it running again. Goes
## through the spawner's own toggle — the one the pause menu drives — rather than
## freeing enemies directly, so its alive-count stays consistent and the waves
## pick up again cleanly afterwards. `Settings` is untouched, which is what
## `_test_spawn_toggle()` reads later.
func _hold_the_wave(held: bool) -> void:
	var spawner := _main.get_node_or_null("Level/Spawner")
	if spawner != null:
		spawner.set_active(not held)


func _on_player_died() -> void:
	var where := "?" if _player == null else str(_player.global_position.round())
	_deaths.append(where)
	print("      !! player died at %s" % where)


## Anything measured in mid-air is measuring gravity, and gravity is not what
## moves a corpse: a dead player has their velocity eased to zero at 40 m/s² and
## is then teleported back to spawn part-way through, which reads as a fall that
## never accelerated rather than as the death it was. The wave running in the
## background is what decides whether that happens, so the probes say out loud
## that they started from a living player, and top them up rather than merely
## assert — one unlucky hit should not take the case after it down as well.
func _require_alive(where: String) -> void:
	_check("player is alive going into %s" % where, not _player.is_dead, "")
	_player.heal(_player.max_health)


func _idle(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


## Waits out the post-equip ready delay so the next trigger pull registers.
func _weapon_ready() -> void:
	await get_tree().create_timer(0.5).timeout


func _count_projectiles() -> int:
	var count := 0
	for child in _main.get_children():
		if child is Area3D:
			count += 1
	return count
