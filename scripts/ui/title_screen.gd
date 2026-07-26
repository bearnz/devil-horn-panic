class_name TitleScreen
extends Control
## Boot screen: pick whether this run spawns enemies, then load the first level.
##
## The choice is written straight to Settings so it persists like any other
## preference; the pause menu's "Spawn enemies" checkbox can still flip it
## mid-run afterwards.
##
## Which level "start" means is `Levels.first()`, not a path in this file — there
## is one level right now and a level select belongs here when there are more.

@onready var _start_button: Button = %StartButton
@onready var _start_no_enemies_button: Button = %StartNoEnemiesButton


func _ready() -> void:
	_start_button.pressed.connect(_on_start_pressed.bind(true))
	_start_no_enemies_button.pressed.connect(_on_start_pressed.bind(false))


func _on_start_pressed(spawn_enemies: bool) -> void:
	apply_choice(spawn_enemies)
	Levels.play_first()


## Split out from _on_start_pressed so tests can exercise the persistence
## without also triggering a scene change.
func apply_choice(spawn_enemies: bool) -> void:
	Settings.spawn_enemies_enabled = spawn_enemies
	Settings.save_settings()
