extends Node
## Global signal bus, autoloaded as `Events`.
##
## Gameplay systems that should not know about each other talk through here:
## the HUD listens for combat and progression events without ever holding a
## reference to the player, weapons or spawner.

# --- Combat ---
signal damage_dealt(target: Node, amount: float, is_crit: bool, at: Vector3)
signal enemy_killed(enemy: Node, xp: int, scrap: int)
## `from` is a **unit vector in world space pointing from the player at whatever
## hurt them**, or `Vector3.ZERO` when nothing can say — falling, a scripted
## hurt, a blast gone off directly underfoot. It is the negated push direction
## every `apply_damage` caller already supplies, which is the one thing that is
## consistently "away from the source" across melee, a projectile and a blast;
## the `at` those callers pass is not (melee quotes the *player's* own position).
## A direction rather than a screen angle, because the receiver has to be able to
## swing the mark round as the player turns to look — see `DamageIndicator`.
signal player_damaged(amount: float, health: float, max_health: float, from: Vector3)
signal player_healed(amount: float, health: float, max_health: float)
signal player_died()
signal player_respawned()

# --- Weapons ---
signal weapon_equipped(instance)
signal ammo_changed(instance)
signal reload_started(instance, duration: float)
signal reload_finished(instance)

# --- Progression ---
signal xp_gained(amount: int)
signal level_up(new_level: int)
signal scrap_changed(total: int)
signal perk_unlocked(perk)
signal skill_ranked(line_id: String, rank: int)
signal weapon_upgraded(instance, upgrade)
signal stats_changed()

# --- Flow ---
signal wave_started(index: int, enemy_count: int)
signal wave_cleared(index: int)
signal notice(text: String)
