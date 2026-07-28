extends Node
## Player progression, autoloaded as `GameState`.
##
## Owns everything earned: XP, level, skill ranks, perks, scrap and the weapon
## loadout with its installed upgrades. Gameplay code never caches derived
## numbers — it asks `GameState.stat("move_speed")` every time so a perk bought
## mid-run takes effect on the next frame.

const SAVE_PATH := "user://devil_horn_save.json"
const SAVE_VERSION := 1

const PERK_DIR := "res://resources/perks"
const UPGRADE_DIR := "res://resources/upgrades"
const WEAPON_DIR := "res://resources/weapons"

const STARTING_WEAPONS: Array[String] = ["sidearm", "shredder"]
const STARTING_SCRAP := 150

## Every stat the game can read. Perks and skills modify these; nothing else
## may introduce new keys, which keeps typos in .tres files findable.
const BASE_STATS := {
	# Survivability
	"max_health": 100.0,
	"health_regen": 0.0,          # hp/sec once out of combat, needs "regen" flag
	"armour": 0.0,                # flat damage reduction per hit
	# Movement
	"move_speed": 7.0,
	"jump_velocity": 9.6,
	"air_jumps": 0.0,             # extra mid-air jumps, needs "double_jump" flag
	"dash_charges": 0.0,          # needs "dash" flag
	"dash_cooldown": 3.0,
	"dash_boost": 14.0,           # m/s added on top of your speed while dashing
	# Gunplay
	"damage_mult": 1.0,
	"fire_rate_mult": 1.0,
	"reload_speed_mult": 1.0,
	"crit_chance": 0.05,
	"crit_mult": 2.0,
	"ammo_reserve_mult": 1.0,
	# Economy
	"xp_mult": 1.0,
	"scrap_mult": 1.0,
}

## The three "minor RPG" lines. Each invested point applies its deltas once.
const SKILL_LINES := {
	"brute": {
		"name": "Brute",
		"blurb": "Meat and violence. More health, harder hits.",
		"flat": {"max_health": 12.0, "armour": 0.4},
		"mult": {"damage_mult": 0.04},
	},
	"agile": {
		"name": "Agile",
		"blurb": "Ground speed and air time.",
		"flat": {"move_speed": 0.22, "jump_velocity": 0.16},
		"mult": {"scrap_mult": 0.03},
	},
	"tech": {
		"name": "Tech",
		"blurb": "Weapon handling, crits and ammo capacity.",
		"flat": {"crit_chance": 0.015},
		"mult": {"reload_speed_mult": 0.06, "ammo_reserve_mult": 0.05},
	},
}

var level: int = 1
var xp: int = 0
var perk_points: int = 1
var skill_points: int = 1
var scrap: int = STARTING_SCRAP
var skills: Dictionary = {"brute": 0, "agile": 0, "tech": 0}
## perk id -> owned rank.
var perk_ranks: Dictionary = {}
## Ability flags granted by perks, e.g. "double_jump".
var flags: Dictionary = {}

var loadout: Array[WeaponInstance] = []
var equipped_index: int = 0

var stats := StatSheet.new()

# Content libraries, keyed by resource id.
var perks: Dictionary = {}
var upgrades: Dictionary = {}
var weapons: Dictionary = {}


func _ready() -> void:
	_load_libraries()
	# Stats have to exist before any WeaponInstance is built: weapons read
	# `ammo_reserve_mult` from here when they load their opening reserve.
	rebuild()
	if not load_game():
		reset_progress(false)
	rebuild()


# --- Content loading --------------------------------------------------------

func _load_libraries() -> void:
	perks = _load_dir(PERK_DIR)
	upgrades = _load_dir(UPGRADE_DIR)
	weapons = _load_dir(WEAPON_DIR)


func _load_dir(dir_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("GameState: cannot open %s" % dir_path)
		return out
	for entry in dir.get_files():
		# Exported builds rename .tres to .tres.remap.
		var file_name := entry.trim_suffix(".remap")
		if not file_name.ends_with(".tres"):
			continue
		var res: Resource = ResourceLoader.load(dir_path.path_join(file_name))
		if res == null or not ("id" in res) or String(res.id).is_empty():
			push_warning("GameState: %s has no usable id" % file_name)
			continue
		out[String(res.id)] = res
	return out


# --- Stats ------------------------------------------------------------------

## Rebuild the stat sheet and ability flags from scratch. Cheap; call freely.
func rebuild() -> void:
	stats.reset(BASE_STATS)
	flags.clear()

	for line_id: String in skills:
		var rank: int = int(skills[line_id])
		if rank <= 0 or not SKILL_LINES.has(line_id):
			continue
		var line: Dictionary = SKILL_LINES[line_id]
		for key: String in line["flat"]:
			stats.add_flat(key, float(line["flat"][key]) * rank)
		for key: String in line["mult"]:
			stats.add_mult(key, float(line["mult"][key]) * rank)

	for perk_id: String in perk_ranks:
		var perk: PerkData = perks.get(perk_id)
		if perk == null:
			continue
		var rank: int = int(perk_ranks[perk_id])
		for key: String in perk.flat_effects:
			stats.add_flat(key, float(perk.flat_effects[key]) * rank)
		for key: String in perk.mult_effects:
			stats.add_mult(key, float(perk.mult_effects[key]) * rank)
		for flag: String in perk.grants:
			flags[flag] = true

	Events.stats_changed.emit()


## Falls back to the authored base value, so a stat read before `rebuild()` can
## never come back as a ruinous 0.0 multiplier.
func stat(key: String) -> float:
	return stats.get_stat(key, float(BASE_STATS.get(key, 0.0)))


func stat_int(key: String) -> int:
	return int(round(stat(key)))


func has_flag(flag: String) -> bool:
	return flags.has(flag)


# --- XP and levels ----------------------------------------------------------

func xp_to_next() -> int:
	return 60 + (level - 1) * 45


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var gained := int(round(amount * stat("xp_mult")))
	xp += gained
	Events.xp_gained.emit(gained)
	var levelled := false
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		perk_points += 1
		skill_points += 1
		levelled = true
		Events.level_up.emit(level)
	if levelled:
		rebuild()
		save_game()


func add_scrap(amount: int) -> void:
	if amount == 0:
		return
	if amount > 0:
		amount = int(round(amount * stat("scrap_mult")))
	scrap = maxi(0, scrap + amount)
	Events.scrap_changed.emit(scrap)


# --- Skills -----------------------------------------------------------------

func skill_rank(line_id: String) -> int:
	return int(skills.get(line_id, 0))


func spend_skill_point(line_id: String) -> bool:
	if skill_points <= 0 or not SKILL_LINES.has(line_id):
		return false
	skill_points -= 1
	skills[line_id] = skill_rank(line_id) + 1
	rebuild()
	Events.skill_ranked.emit(line_id, skill_rank(line_id))
	save_game()
	return true


# --- Perks ------------------------------------------------------------------

func perk_rank(perk_id: String) -> int:
	return int(perk_ranks.get(perk_id, 0))


## "" when the perk can be bought right now, otherwise the reason why not.
func perk_block_reason(perk: PerkData) -> String:
	if perk == null:
		return "Unknown perk"
	if perk_rank(perk.id) >= perk.max_rank:
		return "Maxed"
	if level < perk.required_level:
		return "Needs level %d" % perk.required_level
	if skill_rank(perk.skill_line) < perk.min_line_rank:
		var line_name: String = SKILL_LINES.get(perk.skill_line, {}).get("name", perk.skill_line)
		return "Needs %s %d" % [line_name, perk.min_line_rank]
	for required: String in perk.requires:
		if perk_rank(required) <= 0:
			var dep: PerkData = perks.get(required)
			return "Needs %s" % (dep.display_name if dep != null else required)
	if perk_points < perk.cost:
		return "Needs %d PP" % perk.cost
	return ""


func unlock_perk(perk_id: String) -> bool:
	var perk: PerkData = perks.get(perk_id)
	if perk == null or perk_block_reason(perk) != "":
		return false
	perk_points -= perk.cost
	perk_ranks[perk_id] = perk_rank(perk_id) + 1
	rebuild()
	Events.perk_unlocked.emit(perk)
	Events.notice.emit("Perk acquired: %s" % perk.display_name)
	save_game()
	return true


func perks_in_line(line_id: String) -> Array[PerkData]:
	var out: Array[PerkData] = []
	for perk_id: String in perks:
		var perk: PerkData = perks[perk_id]
		if perk.skill_line == line_id:
			out.append(perk)
	out.sort_custom(func(a: PerkData, b: PerkData) -> bool:
		if a.min_line_rank != b.min_line_rank:
			return a.min_line_rank < b.min_line_rank
		return a.display_name < b.display_name)
	return out


# --- Weapons ----------------------------------------------------------------

func give_weapon(weapon_id: String) -> WeaponInstance:
	var data: WeaponData = weapons.get(weapon_id)
	if data == null:
		push_warning("GameState: unknown weapon '%s'" % weapon_id)
		return null
	for existing in loadout:
		if existing.data.id == weapon_id:
			return existing
	var inst := WeaponInstance.new(data)
	loadout.append(inst)
	save_game()
	return inst


func owns_weapon(weapon_id: String) -> bool:
	for inst in loadout:
		if inst.data.id == weapon_id:
			return true
	return false


## Weapons not yet carried that can be bought at the bench.
func purchasable_weapons() -> Array[WeaponData]:
	var out: Array[WeaponData] = []
	for weapon_id: String in weapons:
		var data: WeaponData = weapons[weapon_id]
		if data.scrap_cost > 0 and not owns_weapon(weapon_id):
			out.append(data)
	out.sort_custom(func(a: WeaponData, b: WeaponData) -> bool: return a.scrap_cost < b.scrap_cost)
	return out


## "" on success, otherwise the reason the purchase failed.
func buy_weapon(weapon_id: String) -> String:
	var data: WeaponData = weapons.get(weapon_id)
	if data == null:
		return "Unknown weapon"
	if owns_weapon(weapon_id):
		return "Already owned"
	if scrap < data.scrap_cost:
		return "Needs %d Metal" % data.scrap_cost
	scrap -= data.scrap_cost
	loadout.append(WeaponInstance.new(data))
	Events.scrap_changed.emit(scrap)
	Events.notice.emit("%s acquired" % data.display_name)
	save_game()
	return ""


## Upgrades that fit this weapon and are not installed on it yet.
func available_upgrades(inst: WeaponInstance) -> Array[WeaponUpgrade]:
	var out: Array[WeaponUpgrade] = []
	if inst == null:
		return out
	var owned := inst.upgrade_ids()
	for upgrade_id: String in upgrades:
		var upgrade: WeaponUpgrade = upgrades[upgrade_id]
		if upgrade.fits(inst.data) and not owned.has(upgrade_id):
			out.append(upgrade)
	out.sort_custom(func(a: WeaponUpgrade, b: WeaponUpgrade) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.cost < b.cost)
	return out


## "" on success, otherwise the reason the install failed.
func install_upgrade(inst: WeaponInstance, upgrade_id: String) -> String:
	var upgrade: WeaponUpgrade = upgrades.get(upgrade_id)
	if inst == null or upgrade == null:
		return "Unknown upgrade"
	if not upgrade.fits(inst.data):
		return "Does not fit %s" % inst.data.display_name
	if inst.upgrade_ids().has(upgrade_id):
		return "Already installed"
	if inst.free_slots() <= 0:
		return "No free slots"
	if scrap < upgrade.cost:
		return "Needs %d Metal" % upgrade.cost
	scrap -= upgrade.cost
	inst.install(upgrade)
	Events.scrap_changed.emit(scrap)
	Events.weapon_upgraded.emit(inst, upgrade)
	Events.notice.emit("%s installed on %s" % [upgrade.display_name, inst.data.display_name])
	save_game()
	return ""


## Count of weapons/upgrades the bench could sell right now: enough Metal and,
## for upgrades, a free slot. Used by the HUD to flag "bench upgrades available"
## without the player having to open the character menu to find out.
func affordable_bench_upgrade_count() -> int:
	var count := 0
	for data in purchasable_weapons():
		if data.scrap_cost <= scrap:
			count += 1
	for inst in loadout:
		if inst.free_slots() <= 0:
			continue
		for upgrade in available_upgrades(inst):
			if upgrade.cost <= scrap:
				count += 1
	return count


# --- Save / load ------------------------------------------------------------

func to_dict() -> Dictionary:
	var weapon_entries: Array = []
	for inst in loadout:
		weapon_entries.append({"id": inst.data.id, "upgrades": inst.upgrade_ids()})
	return {
		"version": SAVE_VERSION,
		"level": level,
		"xp": xp,
		"perk_points": perk_points,
		"skill_points": skill_points,
		"scrap": scrap,
		"skills": skills,
		"perk_ranks": perk_ranks,
		"weapons": weapon_entries,
		"equipped_index": equipped_index,
	}


func save_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("GameState: cannot write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("GameState: save file is corrupt, starting fresh")
		return false
	var data: Dictionary = parsed
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("GameState: save version mismatch, starting fresh")
		return false

	level = maxi(1, int(data.get("level", 1)))
	xp = maxi(0, int(data.get("xp", 0)))
	perk_points = maxi(0, int(data.get("perk_points", 0)))
	skill_points = maxi(0, int(data.get("skill_points", 0)))
	scrap = maxi(0, int(data.get("scrap", 0)))

	skills = {"brute": 0, "agile": 0, "tech": 0}
	for line_id: String in data.get("skills", {}):
		if skills.has(line_id):
			skills[line_id] = maxi(0, int(data["skills"][line_id]))

	perk_ranks = {}
	for perk_id: String in data.get("perk_ranks", {}):
		if perks.has(perk_id):
			perk_ranks[perk_id] = maxi(0, int(data["perk_ranks"][perk_id]))

	loadout.clear()
	for entry: Dictionary in data.get("weapons", []):
		var weapon_data: WeaponData = weapons.get(String(entry.get("id", "")))
		if weapon_data == null:
			continue
		var inst := WeaponInstance.new(weapon_data)
		for upgrade_id: Variant in entry.get("upgrades", []):
			var upgrade: WeaponUpgrade = upgrades.get(String(upgrade_id))
			if upgrade != null and upgrade.fits(weapon_data):
				inst.install(upgrade)
		loadout.append(inst)
	if loadout.is_empty():
		_grant_starting_weapons()
	equipped_index = clampi(int(data.get("equipped_index", 0)), 0, maxi(0, loadout.size() - 1))
	return true


func reset_progress(persist: bool = true) -> void:
	level = 1
	xp = 0
	perk_points = 1
	skill_points = 1
	scrap = STARTING_SCRAP
	skills = {"brute": 0, "agile": 0, "tech": 0}
	perk_ranks = {}
	loadout.clear()
	equipped_index = 0
	rebuild()
	_grant_starting_weapons()
	if persist:
		save_game()
		Events.notice.emit("Progress reset")


func _grant_starting_weapons() -> void:
	for weapon_id in STARTING_WEAPONS:
		var data: WeaponData = weapons.get(weapon_id)
		if data != null:
			loadout.append(WeaponInstance.new(data))
