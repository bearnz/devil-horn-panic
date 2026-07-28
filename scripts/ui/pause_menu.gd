class_name PauseMenu
extends CanvasLayer
## Esc-triggered pause menu: resume, settings, quit.
##
## Mutually exclusive with CharacterMenu via the "character_menu" / "pause_menu"
## groups so Tab and Esc never open both screens at once.
##
## The settings screen has a nested keybindings screen. Esc backs out one
## level at a time: keybindings -> settings -> main -> resume.

var player: Player

## Action currently waiting for its next key/mouse press, or "" when idle.
## While set, _unhandled_input consumes everything instead of acting on Esc.
var _listening_action: String = ""
var _keybind_row_buttons: Dictionary = {}

@onready var _main_panel: Control = %MainPanel
@onready var _settings_panel: Control = %SettingsPanel
@onready var _keybinds_panel: Control = %KeybindsPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_back_button: Button = %SettingsBackButton
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _fov_slider: HSlider = %FovSlider
@onready var _spawn_enemies_check: CheckBox = %SpawnEnemiesCheck
@onready var _third_person_check: CheckBox = %ThirdPersonCheck
@onready var _keybinds_button: Button = %KeybindsButton
@onready var _keybind_list: VBoxContainer = %KeybindList
@onready var _reset_keybinds_button: Button = %ResetKeybindsButton
@onready var _keybinds_back_button: Button = %KeybindsBackButton


func _ready() -> void:
	add_to_group("pause_menu")
	visible = false
	_resume_button.pressed.connect(close)
	_settings_button.pressed.connect(_open_settings)
	_settings_back_button.pressed.connect(_open_main)
	_quit_button.pressed.connect(_on_quit_pressed)
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_fov_slider.value_changed.connect(_on_fov_changed)
	_spawn_enemies_check.toggled.connect(_on_spawn_enemies_toggled)
	_third_person_check.toggled.connect(_on_third_person_toggled)
	_keybinds_button.pressed.connect(_open_keybinds)
	_keybinds_back_button.pressed.connect(_open_settings)
	_reset_keybinds_button.pressed.connect(_on_reset_keybinds_pressed)
	_build_keybind_rows()


func setup(new_player: Player) -> void:
	player = new_player
	_sensitivity_slider.value = Settings.mouse_sensitivity
	_fov_slider.value = Settings.fov
	_spawn_enemies_check.button_pressed = Settings.spawn_enemies_enabled
	_third_person_check.set_pressed_no_signal(Settings.third_person)


func _unhandled_input(event: InputEvent) -> void:
	if _listening_action != "":
		_capture_keybind_input(event)
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if visible:
		if _keybinds_panel.visible:
			_open_settings()
		elif _settings_panel.visible:
			_open_main()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif not _character_menu_visible():
		open()
		get_viewport().set_input_as_handled()


func _character_menu_visible() -> bool:
	var menus := get_tree().get_nodes_in_group("character_menu")
	return not menus.is_empty() and (menus[0] as CanvasLayer).visible


func open() -> void:
	_open_main()
	# The same toggle also has a key on it, so the box has to be re-read on the
	# way in rather than set once in setup(). No signal: assigning it would write
	# the settings file every time the game is paused.
	_third_person_check.set_pressed_no_signal(Settings.third_person)
	visible = true
	get_tree().paused = true
	if is_instance_valid(player):
		player.set_control_active(false)


func close() -> void:
	visible = false
	get_tree().paused = false
	if is_instance_valid(player):
		player.set_control_active(true)


func _open_main() -> void:
	_main_panel.visible = true
	_settings_panel.visible = false
	_keybinds_panel.visible = false


func _open_settings() -> void:
	_main_panel.visible = false
	_settings_panel.visible = true
	_keybinds_panel.visible = false


func _open_keybinds() -> void:
	_main_panel.visible = false
	_settings_panel.visible = false
	_keybinds_panel.visible = true


func _on_sensitivity_changed(value: float) -> void:
	Settings.mouse_sensitivity = value
	if is_instance_valid(player):
		player.mouse_sensitivity = value
	Settings.save_settings()


func _on_fov_changed(value: float) -> void:
	Settings.fov = value
	Settings.save_settings()


func _on_spawn_enemies_toggled(enabled: bool) -> void:
	Settings.spawn_enemies_enabled = enabled
	Settings.save_settings()
	for spawner in get_tree().get_nodes_in_group("enemy_spawner"):
		spawner.set_active(enabled)


func _on_third_person_toggled(enabled: bool) -> void:
	Settings.third_person = enabled
	Settings.save_settings()
	if is_instance_valid(player):
		player.set_third_person(enabled)


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


# --- Keybindings --------------------------------------------------------

func _build_keybind_rows() -> void:
	for action: String in Settings.REBINDABLE_ACTIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var label := Label.new()
		label.text = Settings.REBINDABLE_ACTIONS[action]
		label.custom_minimum_size = Vector2(170, 0)
		row.add_child(label)

		var bind_button := Button.new()
		bind_button.text = Settings.action_label(action)
		bind_button.custom_minimum_size = Vector2(150, 32)
		bind_button.pressed.connect(_on_rebind_pressed.bind(action, bind_button))
		row.add_child(bind_button)

		_keybind_list.add_child(row)
		_keybind_row_buttons[action] = bind_button


func _on_rebind_pressed(action: String, button: Button) -> void:
	if _listening_action != "":
		return
	_listening_action = action
	button.text = "Press a key…"


func _capture_keybind_input(event: InputEvent) -> void:
	var action := _listening_action
	var button := _keybind_row_buttons.get(action) as Button
	if event is InputEventKey and event.pressed and not event.echo:
		get_viewport().set_input_as_handled()
		# Esc cancels the capture instead of binding — it stays reserved for this menu.
		if (event as InputEventKey).keycode != KEY_ESCAPE and Settings.rebind_action(action, event):
			Settings.save_settings()
		_listening_action = ""
		if button != null:
			button.text = Settings.action_label(action)
	elif event is InputEventMouseButton and event.pressed:
		get_viewport().set_input_as_handled()
		if Settings.rebind_action(action, event):
			Settings.save_settings()
		_listening_action = ""
		if button != null:
			button.text = Settings.action_label(action)


func _on_reset_keybinds_pressed() -> void:
	Settings.reset_all_keybinds()
	Settings.save_settings()
	for action: String in _keybind_row_buttons:
		(_keybind_row_buttons[action] as Button).text = Settings.action_label(action)
