extends StaticBody3D
## Interactable that opens the character menu on the weapon bench tab.
##
## Talks to the UI through the "character_menu" group so the level never needs a
## direct reference to the HUD layer.

@export var open_tab: int = 2


func interact_prompt() -> String:
	return "Workbench — spend scrap (%d)" % GameState.scrap


func interact(_player: Node) -> void:
	var menus := get_tree().get_nodes_in_group("character_menu")
	if menus.is_empty():
		Events.notice.emit("No workbench terminal available")
		return
	menus[0].open(open_tab)
