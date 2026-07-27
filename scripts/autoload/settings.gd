extends Node
## Client-side preferences, autoloaded as `Settings`.
##
## Kept separate from GameState: these are local prefs, not save-file
## progression. Every save backs up the previous on-disk copy first, so if a
## future settings-format refactor writes something load_settings() can't
## parse, it falls back to the last known-good copy instead of resetting
## everyone's preferences to default.

const SAVE_PATH := "user://devil_horn_settings.json"
const BACKUP_PATH := "user://devil_horn_settings.json.bak"
const SAVE_VERSION := 1

const DEFAULT_MOUSE_SENSITIVITY := 0.0022
const DEFAULT_FOV := 90.0

## The closed set of actions the keybindings menu may rebind, and their
## display names. Esc (the built-in "ui_cancel" action) is deliberately not
## in here — it opens/closes this very menu and is not rebindable yet.
const REBINDABLE_ACTIONS := {
	"move_forward": "Move forward",
	"move_back": "Move back",
	"move_left": "Move left",
	"move_right": "Move right",
	"jump": "Jump",
	"crouch": "Crouch / slide",
	"dash": "Dash",
	"fire": "Fire",
	"aim": "Aim",
	"reload": "Reload",
	"interact": "Interact",
	"menu": "Character menu",
	"third_person": "Third-person view",
	"weapon_1": "Weapon slot 1",
	"weapon_2": "Weapon slot 2",
	"weapon_3": "Weapon slot 3",
	"weapon_next": "Next weapon",
	"weapon_prev": "Previous weapon",
}

var mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY
var fov: float = DEFAULT_FOV
## Dev/tuning toggle: turn off wave spawning to tweak movement and other
## systems without enemies interrupting.
var spawn_enemies_enabled: bool = true
## Dev/review toggle: pull the camera back behind the player so the body, its
## stances and the dash pose can be watched while they move. See
## `Player.set_third_person()` for what it costs.
var third_person: bool = false
## action -> {"type": "key" | "mouse_button", "code": int}. Only actions with
## a saved override appear here; everything else stays on its project.godot
## default.
var keybinds: Dictionary = {}

## Snapshot of each rebindable action's original events, taken before any
## saved override is applied, so a rebind can be reset back to it.
var _default_events: Dictionary = {}


func _ready() -> void:
	_capture_default_keybinds()
	load_settings()
	apply_keybinds()


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"mouse_sensitivity": mouse_sensitivity,
		"fov": fov,
		"spawn_enemies_enabled": spawn_enemies_enabled,
		"third_person": third_person,
		"keybinds": keybinds,
	}


func save_settings() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var err := DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
		if err != OK:
			push_warning("Settings: failed to back up %s (error %d)" % [SAVE_PATH, err])
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Settings: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))


## Tries the primary file, then falls back to the backup if it's missing or
## corrupt. Returns false only when neither could be read.
func load_settings() -> bool:
	if _load_from(SAVE_PATH):
		return true
	if _load_from(BACKUP_PATH):
		push_warning("Settings: primary file unreadable, restored from backup")
		save_settings()
		return true
	return false


func _load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	mouse_sensitivity = float(data.get("mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY))
	fov = float(data.get("fov", DEFAULT_FOV))
	spawn_enemies_enabled = bool(data.get("spawn_enemies_enabled", true))
	third_person = bool(data.get("third_person", false))
	keybinds = {}
	for action: String in data.get("keybinds", {}):
		if not REBINDABLE_ACTIONS.has(action):
			continue
		var entry: Dictionary = data["keybinds"][action]
		if entry.get("type") in ["key", "mouse_button"] and entry.has("code"):
			keybinds[action] = {"type": entry["type"], "code": int(entry["code"])}
	return true


# --- Keybindings --------------------------------------------------------

func _capture_default_keybinds() -> void:
	for action: String in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			_default_events[action] = InputMap.action_get_events(action).duplicate()


## Pushes every saved override into the live InputMap. Call once at boot,
## after load_settings(); rebind_action()/reset_keybind() keep the map in
## sync with `keybinds` from then on.
func apply_keybinds() -> void:
	for action: String in keybinds:
		_apply_single_keybind(action, keybinds[action])


func _apply_single_keybind(action: String, entry: Dictionary) -> void:
	var event := _event_from_entry(entry)
	if event == null or not InputMap.has_action(action):
		return
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)


func _event_from_entry(entry: Dictionary) -> InputEvent:
	var code := int(entry.get("code", 0))
	match String(entry.get("type", "")):
		"key":
			var event := InputEventKey.new()
			event.keycode = code
			return event
		"mouse_button":
			var event := InputEventMouseButton.new()
			event.button_index = code
			return event
	return null


## Current display label for whatever is bound to `action` right now.
func action_label(action: String) -> String:
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "—"
	return events[0].as_text().strip_edges()


## Rebinds `action` to whatever key/mouse button `event` represents. Refuses
## Esc (reserved for the pause menu) and anything not in REBINDABLE_ACTIONS.
## Does not persist — call save_settings() once the caller is done rebinding.
func rebind_action(action: String, event: InputEvent) -> bool:
	if not REBINDABLE_ACTIONS.has(action):
		return false
	var entry: Dictionary
	if event is InputEventKey:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			return false
		entry = {"type": "key", "code": (event as InputEventKey).keycode}
	elif event is InputEventMouseButton:
		entry = {"type": "mouse_button", "code": (event as InputEventMouseButton).button_index}
	else:
		return false
	keybinds[action] = entry
	_apply_single_keybind(action, entry)
	return true


## Restores every rebindable action to its project.godot default. Does not
## persist — call save_settings() afterwards to make it stick.
func reset_all_keybinds() -> void:
	for action: String in REBINDABLE_ACTIONS:
		keybinds.erase(action)
		if _default_events.has(action):
			InputMap.action_erase_events(action)
			for event: InputEvent in _default_events[action]:
				InputMap.action_add_event(action, event)
