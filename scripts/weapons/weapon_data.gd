class_name WeaponData
extends Resource
## Immutable definition of a weapon. Authored as a .tres in res://resources/weapons.
##
## Runtime state (ammo, cooldown, installed upgrades) lives on `WeaponInstance`
## so several instances can share one definition without stomping each other.

@export var id: String = ""
@export var display_name: String = "New Weapon"
@export_multiline var description: String = ""

@export_group("Ballistics")
@export var damage: float = 12.0
## Shots per second.
@export var fire_rate: float = 5.0
@export var automatic: bool = false
## Projectiles per shot (shotguns > 1).
@export_range(1, 24) var pellets: int = 1
## Cone half-angle in degrees applied to every pellet.
@export var spread_deg: float = 0.6
@export var max_range: float = 250.0
@export var crit_chance: float = 0.0
@export var crit_mult: float = 2.0
## Vertical camera kick in degrees per shot.
@export var recoil: float = 0.7
## Knockback dealt to hit enemies.
@export var impact_force: float = 4.0

@export_group("Handling")
## How heavy this weapon is to carry, 0 for something you can flick about and 1
## for a slab. Not a stat: it never reaches damage, rate or range, and nothing in
## `base_stats()` can touch it — it is entirely how the thing *behaves in the
## hands*, which is why it is authored here and read straight off the data rather
## than through the sheet.
##
## One number, because heaviness has exactly two signatures and both fall out of
## it. A heavy weapon **answers slower** — it trails the view further behind a
## turn, comes up to the sights later, takes longer to draw and longer to settle
## after a shot — and it **moves further**, riding the stride and the breath more
## than a light one does. `WeaponController.heft_lag()` and `heft_swing()` are
## those two, and every constant in that file's carry-motion block is quoted for
## the middle of this range, so 0.5 is the weapon those numbers were written
## against. Both rigs read the same pair, so the weapon at the eye and the weapon
## in the player's own shadow are equally heavy.
##
## What it deliberately does not touch is the kick, which already has an authored
## number of its own in `recoil`: how hard a weapon hits is the round's business
## and how long it takes to recover from it is the weapon's, and keeping those two
## apart is what lets a light weapon punch and a heavy one wallow.
@export_range(0.0, 1.0) var heft: float = 0.5

@export_group("Ammo")
@export var mag_size: int = 12
@export var reserve_max: int = 96
@export var reload_time: float = 1.1

@export_group("Projectile")
## Leave null for hitscan. When set, each pellet spawns this scene instead.
@export var projectile: PackedScene
@export var projectile_speed: float = 45.0
## Radius of the explosion on impact. 0 = direct damage only.
@export var blast_radius: float = 0.0

## How the off hand holds this weapon. The trigger hand is always on the grip,
## so it needs no authoring, but "under the barrel" is nonsense on a pistol and
## "cupping the other hand" is nonsense on a carbine — that one is a real choice
## and cannot be guessed from the sizes below.
enum SupportGrip {
	## Off hand under the barrel. Anything with a barrel long enough to hold.
	FOREGRIP,
	## Off hand wrapped around the shooting hand, for pistols.
	CUPPED,
}

@export_group("View Model")
@export var view_color: Color = Color(0.75, 0.16, 0.16)
@export var body_size: Vector3 = Vector3(0.09, 0.13, 0.34)
@export var barrel_size: Vector3 = Vector3(0.045, 0.045, 0.42)
@export var grip_size: Vector3 = Vector3(0.07, 0.16, 0.09)
## Extra offset applied to this weapon's rest pose in the view model rig.
@export var view_offset: Vector3 = Vector3.ZERO
@export var support_grip: SupportGrip = SupportGrip.FOREGRIP

@export_group("Economy")
@export_range(0, 6) var upgrade_slots: int = 3
@export var scrap_cost: int = 0


## Stat keys that upgrades are allowed to modify, seeded with this weapon's
## authored values. Consumed by `WeaponInstance`'s StatSheet.
func base_stats() -> Dictionary:
	return {
		"damage": damage,
		"fire_rate": fire_rate,
		"pellets": float(pellets),
		"spread_deg": spread_deg,
		"max_range": max_range,
		"crit_chance": crit_chance,
		"crit_mult": crit_mult,
		"recoil": recoil,
		"impact_force": impact_force,
		"mag_size": float(mag_size),
		"reserve_max": float(reserve_max),
		"reload_time": reload_time,
		"projectile_speed": projectile_speed,
		"blast_radius": blast_radius,
	}
