class_name WeaponUpgrade
extends Resource
## A bolt-on modification bought with scrap at the workbench.
##
## Authored as a .tres in res://resources/upgrades. Occupies one upgrade slot on
## the weapon it is installed into.

@export var id: String = ""
@export var display_name: String = "New Upgrade"
@export_multiline var description: String = ""
@export var cost: int = 60
@export_range(1, 3) var tier: int = 1
## Weapon ids this fits. Empty = universal.
@export var applies_to: Array[String] = []

## Weapon stat key -> flat delta. Keys come from WeaponData.base_stats().
@export var flat: Dictionary = {}
## Weapon stat key -> fractional multiplier (0.25 == +25%).
@export var mult: Dictionary = {}
## Behaviour flags: "pierce", "explosive", "homing", "ricochet".
@export var flags: Array[String] = []


func fits(weapon: WeaponData) -> bool:
	return applies_to.is_empty() or applies_to.has(weapon.id)


func summarize() -> String:
	var lines: PackedStringArray = []
	for key: String in flat:
		lines.append("%s %+.2f" % [_pretty(key), float(flat[key])])
	for key: String in mult:
		lines.append("%s %+.0f%%" % [_pretty(key), float(mult[key]) * 100.0])
	for flag: String in flags:
		lines.append("Adds: %s" % _pretty(flag))
	return "\n".join(lines)


func _pretty(key: String) -> String:
	return key.replace("_", " ").capitalize()
