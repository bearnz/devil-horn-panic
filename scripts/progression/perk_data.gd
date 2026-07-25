class_name PerkData
extends Resource
## A single purchasable perk. Authored as a .tres in res://resources/perks.
##
## Perks only ever describe *data*: flat/multiplicative stat deltas plus
## optional ability flags. `GameState` turns them into live numbers, so no perk
## needs its own script.

@export var id: String = ""
@export var display_name: String = "New Perk"
@export_multiline var description: String = ""

## Which skill line this perk hangs off: "brute", "agile" or "tech".
@export var skill_line: String = "brute"

@export_range(1, 5) var cost: int = 1
@export_range(1, 5) var max_rank: int = 1
@export_range(1, 30) var required_level: int = 1
## Minimum invested rank in `skill_line` before this perk can be bought.
@export_range(0, 10) var min_line_rank: int = 0
## Perk ids that must be owned first.
@export var requires: Array[String] = []

## Stat key -> flat amount added per rank. Keys must exist in GameState.BASE_STATS.
@export var flat_effects: Dictionary = {}
## Stat key -> fractional multiplier added per rank (0.1 == +10%).
@export var mult_effects: Dictionary = {}
## Ability flags granted, e.g. "double_jump", "wall_jump", "dash", "regen".
@export var grants: Array[String] = []


## Multi-line summary used by the perk menu.
func summarize() -> String:
	var lines: PackedStringArray = []
	for key: String in flat_effects:
		lines.append("%s %+.2f" % [_pretty(key), float(flat_effects[key])])
	for key: String in mult_effects:
		lines.append("%s %+.0f%%" % [_pretty(key), float(mult_effects[key]) * 100.0])
	for flag: String in grants:
		lines.append("Unlocks: %s" % _pretty(flag))
	return "\n".join(lines)


func _pretty(key: String) -> String:
	return key.replace("_", " ").capitalize()
