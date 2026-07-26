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

	await _test_pause_menu()
	await _test_shooting()
	await _test_progression()
	await _test_dash()
	await _test_hud_points_label()
	await _test_persistence()
	await _test_waves()
	await _test_spawn_toggle()


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
		"fire", "aim", "reload", "interact", "menu",
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

	# Projectile weapon path.
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


## The dash lends speed rather than setting it: entry speed + "dash_boost" for
## the duration, back to entry speed on exit. Vertically it holds its height,
## then a climb resumes and a fall restarts from zero.
## Runs after _test_progression() so the agile line is already ranked up enough
## to buy Blink Step.
func _test_dash() -> void:
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

	await _test_dash_boost_perk(boost)
	await _test_speed_caps()


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

	# Terminal velocity: 34 m/s arrives 1.31s in, so by 1.6s it is holding.
	_player.global_position = Vector3(0, 45, 20)
	_player.velocity = Vector3.ZERO
	await get_tree().create_timer(1.6).timeout
	_check("fall speed is capped at terminal velocity",
			_player.velocity.y > -Player.MAX_FALL_SPEED - 0.5
					and _player.velocity.y < -Player.MAX_FALL_SPEED + 1.0,
			"%.2f vs cap %.2f" % [_player.velocity.y, -Player.MAX_FALL_SPEED])

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

	# Enemies should close on the player rather than stand still. Pick the one
	# furthest away: anything already in melee range is busy attacking.
	var enemy: Enemy = null
	var distance_before := 0.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var candidate := node as Enemy
		var distance := candidate.global_position.distance_to(_player.global_position)
		if distance > distance_before:
			enemy = candidate
			distance_before = distance
	if enemy == null or distance_before < 8.0:
		return
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(enemy):
		var distance_after := enemy.global_position.distance_to(_player.global_position)
		_check("enemy closed the distance", distance_after < distance_before,
				"%.1f -> %.1f" % [distance_before, distance_after])


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
