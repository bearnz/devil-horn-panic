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

@export_group("View Model")
@export var view_color: Color = Color(0.75, 0.16, 0.16)
@export var body_size: Vector3 = Vector3(0.09, 0.13, 0.34)
@export var barrel_size: Vector3 = Vector3(0.045, 0.045, 0.42)
@export var grip_size: Vector3 = Vector3(0.07, 0.16, 0.09)
## Extra offset applied to this weapon's rest pose in the view model rig.
@export var view_offset: Vector3 = Vector3.ZERO

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
