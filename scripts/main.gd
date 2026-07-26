class_name Main
extends Node3D
## Entry point. Builds itself around whichever level `Levels.current` points at,
## drops the player on that level's spawn marker and hands the UI its player
## reference.
##
## Nothing here names a level. To play a different one, `Levels.play(id)` before
## this scene loads — the title screen does exactly that.

## Levels are added under this name so `Level/PlayerSpawn` and
## `Level/WorldEnvironment` resolve the same way whatever is loaded.
const LEVEL_NODE_NAME := "Level"

var level: LevelData

@onready var _player: Player = $Player
@onready var _hud: HUD = $HUD
@onready var _menu: CharacterMenu = $CharacterMenu
@onready var _pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	level = Levels.current
	if level == null:
		# Running main.tscn directly from the editor skips the title screen, so
		# fall back rather than booting into an empty void.
		level = Levels.first()
	if level == null:
		push_error("Main: no level to load — is resources/levels/ empty?")
		return

	_build_level()

	var spawn := get_node_or_null("%s/PlayerSpawn" % LEVEL_NODE_NAME) as Node3D
	if spawn != null:
		_player.global_transform = spawn.global_transform
		_player.spawn_transform = spawn.global_transform
	else:
		push_warning("Main: %s has no PlayerSpawn" % level.id)

	_hud.setup(_player)
	_menu.setup(_player)
	_pause_menu.setup(_player)

	for notice in level.intro_notices:
		Events.notice.emit(notice)


## Instanced ahead of the player being positioned, so the spawn marker and the
## floor under it both exist before the first physics frame.
func _build_level() -> void:
	var scene := load(level.scene) as PackedScene
	if scene == null:
		push_error("Main: %s could not load %s" % [level.id, level.scene])
		return
	var instance := scene.instantiate()
	instance.name = LEVEL_NODE_NAME
	# Ahead of the player in the tree, matching the order the scene used to have
	# when the level was a static child.
	add_child(instance)
	move_child(instance, 0)
