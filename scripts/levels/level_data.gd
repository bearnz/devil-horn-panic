class_name LevelData
extends Resource
## One playable level, authored as a .tres in resources/levels/.
##
## Same deal as perks and weapons: drop a file in the folder and `Levels` picks
## it up at boot. Nothing hard-codes a level scene except this resource.
##
## The scene is held as a path rather than a PackedScene on purpose. An
## exported PackedScene is loaded eagerly when the .tres is read, so a
## twenty-level library would pull every level's geometry into memory at boot
## just to list their names. The smoke test checks the paths resolve, which is
## the safety a direct reference would have bought.

## Stable key. Convention is an ordered prefix — 000_poc_1, 010_foundry — so the
## folder sorts the way the game plays even before `order` is read.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var blurb: String = ""

## res:// path to the level scene. Its root wants a `PlayerSpawn` Marker3D and a
## `WorldEnvironment`; everything else is up to the level.
@export_file("*.tscn") var scene: String = ""

## Play order. Ties are broken by id, so leaving these at 0 still gives a stable
## sequence as long as the ids are prefixed.
@export var order: int = 0

## Lines pushed to the HUD when the level starts, in order. Level flavour lives
## here rather than in main.gd so a new level does not mean a code change.
@export var intro_notices: PackedStringArray = []


func is_valid() -> bool:
	return not id.is_empty() and not scene.is_empty()
