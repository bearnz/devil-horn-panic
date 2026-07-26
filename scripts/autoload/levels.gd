extends Node
## The level library and which one is being played, autoloaded as `Levels`.
##
## Deliberately separate from GameState: `GameState.level` is the player's XP
## level and always has been, so map progression living in the same object would
## make every read of `level` ambiguous. GameState owns what you have earned,
## Levels owns where you are playing it.
##
## Progression is *not* per-level — XP, perks, scrap and the weapon loadout carry
## across, because that is what GameState already saves. Levels only decides
## which scene main.tscn builds itself around.

const LEVEL_DIR := "res://resources/levels"
const MAIN_SCENE := "res://scenes/main.tscn"

## Level id -> LevelData.
var library: Dictionary = {}

## What main.tscn will instance. Never null once _ready has run, as long as the
## library is not empty.
var current: LevelData = null


func _ready() -> void:
	_load_library()
	current = first()


func _load_library() -> void:
	library = {}
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		push_warning("Levels: cannot open %s" % LEVEL_DIR)
		return
	for entry in dir.get_files():
		# Exported builds rename .tres to .tres.remap.
		var file_name := entry.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var data := ResourceLoader.load(LEVEL_DIR.path_join(file_name)) as LevelData
		if data == null or not data.is_valid():
			push_warning("Levels: %s is not a usable LevelData" % file_name)
			continue
		library[data.id] = data


## Play order: `order` first, then id, so an unset `order` still sorts sensibly
## as long as ids carry their numeric prefix.
func ordered() -> Array[LevelData]:
	var out: Array[LevelData] = []
	for level_id: String in library:
		out.append(library[level_id])
	out.sort_custom(func(a: LevelData, b: LevelData) -> bool:
		if a.order != b.order:
			return a.order < b.order
		return a.id < b.id)
	return out


func first() -> LevelData:
	var all := ordered()
	return null if all.is_empty() else all[0]


func get_level(level_id: String) -> LevelData:
	return library.get(level_id) as LevelData


## The level after `level_id`, or null at the end of the list. Nothing calls this
## yet — levels have no completion condition — but the ordering it reads is the
## whole point of the numeric id prefix, so it is worth having defined and
## tested rather than reinvented per caller later.
func next_of(level_id: String) -> LevelData:
	var all := ordered()
	for index in all.size():
		if all[index].id == level_id:
			return all[index + 1] if index + 1 < all.size() else null
	return null


## Point at a level without loading it, for callers that are about to change
## scene themselves. Returns false for an unknown id rather than leaving
## `current` in a state main.gd cannot build from.
func select(level_id: String) -> bool:
	var data := get_level(level_id)
	if data == null:
		push_warning("Levels: unknown level '%s'" % level_id)
		return false
	current = data
	return true


## Select a level and drop into it. main.tscn reads `current` on _ready, so this
## is the only entry point gameplay needs.
func play(level_id: String) -> bool:
	if not select(level_id):
		return false
	get_tree().change_scene_to_file(MAIN_SCENE)
	return true


func play_first() -> bool:
	var data := first()
	if data == null:
		push_warning("Levels: no levels in %s" % LEVEL_DIR)
		return false
	return play(data.id)
