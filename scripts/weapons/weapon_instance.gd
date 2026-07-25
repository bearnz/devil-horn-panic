class_name WeaponInstance
extends RefCounted
## Live weapon: a `WeaponData` definition + installed upgrades + ammo state.
##
## All derived numbers go through `stat()` so weapon upgrades and player perks
## compose: the weapon's own StatSheet handles upgrades, then the player's
## global multipliers from `GameState` are folded in on top.

var data: WeaponData
var installed: Array[WeaponUpgrade] = []
var ammo: int = 0
var reserve: int = 0

var _sheet := StatSheet.new()


func _init(weapon_data: WeaponData = null) -> void:
	if weapon_data != null:
		setup(weapon_data)


func setup(weapon_data: WeaponData) -> void:
	data = weapon_data
	rebuild()
	ammo = mag_size()
	reserve = reserve_max()


## Recompute upgrade contributions. Call after installing an upgrade.
func rebuild() -> void:
	_sheet.reset(data.base_stats())
	for upgrade in installed:
		for key: String in upgrade.flat:
			_sheet.add_flat(key, float(upgrade.flat[key]))
		for key: String in upgrade.mult:
			_sheet.add_mult(key, float(upgrade.mult[key]))


func stat(key: String) -> float:
	return _sheet.get_stat(key)


# --- Player-modified values -------------------------------------------------

func damage() -> float:
	return stat("damage") * GameState.stat("damage_mult")


func fire_interval() -> float:
	return 1.0 / maxf(0.05, stat("fire_rate") * GameState.stat("fire_rate_mult"))


func reload_duration() -> float:
	return stat("reload_time") / maxf(0.1, GameState.stat("reload_speed_mult"))


func mag_size() -> int:
	return maxi(1, _sheet.get_stat_int("mag_size"))


func reserve_max() -> int:
	return maxi(0, int(round(stat("reserve_max") * GameState.stat("ammo_reserve_mult"))))


func pellets() -> int:
	return maxi(1, _sheet.get_stat_int("pellets"))


func crit_chance() -> float:
	return clampf(stat("crit_chance") + GameState.stat("crit_chance"), 0.0, 1.0)


func crit_mult() -> float:
	return maxf(stat("crit_mult"), GameState.stat("crit_mult"))


# --- Upgrades ---------------------------------------------------------------

func has_flag(flag: String) -> bool:
	for upgrade in installed:
		if upgrade.flags.has(flag):
			return true
	return false


func free_slots() -> int:
	return maxi(0, data.upgrade_slots - installed.size())


func install(upgrade: WeaponUpgrade) -> void:
	installed.append(upgrade)
	rebuild()
	# Keep the loaded magazine legal if the upgrade shrank it.
	ammo = mini(ammo, mag_size())
	reserve = mini(reserve, reserve_max())


func upgrade_ids() -> Array[String]:
	var ids: Array[String] = []
	for upgrade in installed:
		ids.append(upgrade.id)
	return ids


# --- Ammo -------------------------------------------------------------------

func is_full() -> bool:
	return ammo >= mag_size()


func can_reload() -> bool:
	return reserve > 0 and not is_full()


func do_reload() -> void:
	var wanted := mag_size() - ammo
	var moved := mini(wanted, reserve)
	ammo += moved
	reserve -= moved


func add_reserve(amount: int) -> int:
	var before := reserve
	reserve = mini(reserve_max(), reserve + amount)
	return reserve - before


func display_name() -> String:
	return data.display_name if data != null else "—"
