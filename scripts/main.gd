extends Node3D
## Entry point: drops the player on the level's spawn marker and hands the UI
## its player reference. Swap the Level child to play a different map.

@onready var _player: Player = $Player
@onready var _hud: HUD = $HUD
@onready var _menu: CharacterMenu = $CharacterMenu


func _ready() -> void:
	var spawn := get_node_or_null("Level/PlayerSpawn") as Node3D
	if spawn != null:
		_player.global_transform = spawn.global_transform
		_player.spawn_transform = spawn.global_transform

	_hud.setup(_player)
	_menu.setup(_player)

	Events.notice.emit("WASD move · Shift sprint · Ctrl slide · Space jump · Tab character sheet")
	Events.notice.emit("Kill demons for XP and scrap. Spend them at the workbench behind you.")
