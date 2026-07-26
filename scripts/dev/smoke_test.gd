extends Node
## Headless integration check. Boots the real main scene and drives the systems
## the way a player would, then prints a pass/fail summary and quits.
##
## Run it with:
##   godot --path . --headless --fixed-fps 60 res://scenes/dev/smoke_test.tscn
##
## It leaves progression reset to a fresh-save state so it never pollutes a real
## playthrough.

var _checks: int = 0
var _failures: PackedStringArray = []

var _main: Node
var _player: Player


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
	_test_settings()

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _idle(4)

	_player = _main.get_node_or_null("Player") as Player
	_check("player spawned", _player != null, "")
	if _player == null:
		return
	_check("weapon controller found a weapon", _player.weapons.current() != null, "")
	_check("player placed on spawn marker", _player.global_position.distance_to(
			Vector3(0, 0.3, 16)) < 0.5, str(_player.global_position))

	await _test_pause_menu()
	await _test_shooting()
	await _test_progression()
	await _test_persistence()
	await _test_waves()


# --- Cases ------------------------------------------------------------------

## Every action the gameplay scripts poll must exist and have a binding,
## otherwise Godot spams "action not found" at runtime.
func _check_input_map() -> void:
	var required := [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "sprint", "crouch", "dash",
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
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
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

	var started := [false]
	Events.wave_started.connect(func(_index: int, _count: int) -> void: started[0] = true)
	# first_wave_delay is 6s in the arena; give it a little margin.
	await get_tree().create_timer(8.0).timeout
	_check("first wave started", started[0], "")
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
