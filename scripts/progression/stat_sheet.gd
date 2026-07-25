class_name StatSheet
extends RefCounted
## Aggregates base stats with additive and multiplicative modifiers.
##
## Final value = (base + sum_of_flat) * (1 + sum_of_mult). Modifiers are never
## stored on the source (perk resources stay immutable); the sheet is rebuilt
## from scratch whenever progression changes.

var _base: Dictionary = {}
var _flat: Dictionary = {}
var _mult: Dictionary = {}


func reset(base: Dictionary) -> void:
	_base = base.duplicate()
	_flat.clear()
	_mult.clear()


func add_flat(key: String, value: float) -> void:
	_flat[key] = float(_flat.get(key, 0.0)) + value


func add_mult(key: String, value: float) -> void:
	_mult[key] = float(_mult.get(key, 0.0)) + value


func get_stat(key: String, fallback: float = 0.0) -> float:
	var base_value := float(_base.get(key, fallback))
	return (base_value + float(_flat.get(key, 0.0))) * (1.0 + float(_mult.get(key, 0.0)))


func get_stat_int(key: String, fallback: float = 0.0) -> int:
	return int(round(get_stat(key, fallback)))


## Human-readable delta for menus: "+12" / "x1.20" style summary of what the
## modifiers are doing to a stat, or "" when the stat is unmodified.
func describe_modifier(key: String) -> String:
	var parts: PackedStringArray = []
	var flat := float(_flat.get(key, 0.0))
	var mult := float(_mult.get(key, 0.0))
	if not is_zero_approx(flat):
		parts.append("%+.2f" % flat)
	if not is_zero_approx(mult):
		parts.append("%+.0f%%" % (mult * 100.0))
	return " ".join(parts)


func base_keys() -> Array:
	return _base.keys()
