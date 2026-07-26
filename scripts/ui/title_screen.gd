class_name TitleScreen
extends Control
## Boot screen: pick whether this run spawns enemies, then load the arena.
##
## The choice is written straight to Settings so it persists like any other
## preference; the pause menu's "Spawn enemies" checkbox can still flip it
## mid-run afterwards.

const MAIN_SCENE := "res://scenes/main.tscn"

@onready var _start_button: Button = %StartButton
@onready var _start_no_enemies_button: Button = %StartNoEnemiesButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed.bind(true))
	_start_no_enemies_button.pressed.connect(_on_start_pressed.bind(false))


func _on_start_pressed(spawn_enemies: bool) -> void:
	apply_choice(spawn_enemies)
	get_tree().change_scene_to_file(MAIN_SCENE)


## Split out from _on_start_pressed so tests can exercise the persistence
## without also triggering a scene change.
func apply_choice(spawn_enemies: bool) -> void:
	Settings.spawn_enemies_enabled = spawn_enemies
	Settings.save_settings()
