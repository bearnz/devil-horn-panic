# Devil Horn Panic

3D first-person platformer / shooter in **Godot 4.7.1** (Forward+). Boots to
`res://scenes/ui/title_screen.tscn` (`application/run/main_scene`); gameplay
itself lives in `res://scenes/main.tscn`, which the title screen loads.

## Running and checking

```bash
godot --path . --headless --fixed-fps 60 res://scenes/dev/smoke_test.tscn
```

Integration test: boots the real main scene and drives movement, shooting,
progression, the bench and the wave spawner. Prints `ok`/`FAIL` per check and
exits non-zero on failure. Add a check here for anything you fix — it is the
only automated coverage in the project. `--fixed-fps` matters: without it the
headless loop runs with near-zero delta and timers never elapse.

```bash
godot --path . --resolution 1280x720 res://scenes/dev/capture_shots.tscn ++ <out_dir>
```

Writes `shot_gameplay.png`, `shot_overview.png`, `shot_perks.png` and
`shot_bench.png`, and prints where the player ended up and what the crosshair is
pointing at. Use it to check layout and lighting without playing.

## Layout

```
scripts/autoload/   Events (signal bus), GameState (progression), Settings (prefs)
scripts/progression/ StatSheet, PerkData
scripts/weapons/    WeaponData, WeaponUpgrade, WeaponInstance, WeaponController, projectile
scripts/player/     player.gd
scripts/enemies/    enemy.gd (all archetypes), enemy_spawner.gd
scripts/world/      platform, jump pad, checkpoint, ammo crate, workbench
scripts/ui/         hud.gd, crosshair.gd, character_menu.gd, pause_menu.gd, title_screen.gd
scripts/dev/        smoke_test.gd, capture_shots.gd
resources/{weapons,upgrades,perks}/   authored .tres content
scenes/             mirrors scripts/, plus levels/test_arena.tscn
```

## The rules that keep this coherent

**Never cache a derived stat.** Ask `GameState.stat("move_speed")` every time.
That is what makes a perk bought mid-run apply on the next frame. The same goes
for weapons: `WeaponInstance.damage()`, `fire_interval()`, `mag_size()`.

**`GameState.BASE_STATS` is the closed set of stat keys.** Perks and upgrades in
.tres files address stats by string. A typo silently does nothing, so a new stat
means a new entry in `BASE_STATS` first.

**Two modifier layers, both rebuilt from scratch.** `StatSheet` computes
`(base + flat) * (1 + mult)`. `GameState.rebuild()` refills the player's sheet
from skill ranks and perks; `WeaponInstance.rebuild()` refills the weapon's from
installed upgrades. Resources are never mutated — several instances share one
`WeaponData`.

**Content is data, not code.** A new perk, weapon or upgrade is a .tres dropped
into `resources/<kind>/`; `GameState._load_dir()` scans the folder at boot and
the menus generate their rows from what it finds. No script changes needed.

**Damage is duck-typed:** `apply_damage(amount, is_crit, at, direction)`, with
optional `apply_knockback(impulse)`. Anything implementing it can be shot.
`CombatFX.explode()` finds targets by group.

**Ability flags gate traversal.** `double_jump`, `wall_jump`, `dash` and `regen`
come from perk `grants` and are read via `GameState.has_flag()`. The wall shaft
in the test arena is deliberately impassable until Wall Runner is bought.

Groups: `player`, `enemies`, `character_menu` (the workbench opens the menu
through this group rather than holding a reference).

Physics layers: 1 world, 2 player, 3 enemies, 4 projectiles, 5 triggers.
Projectiles build their mask from `target_group` at launch, so the shooter is
filtered out by physics instead of bookkeeping.

## GDScript gotchas in this project

Inferring a type from a Variant is **an error**, not a warning. `var x :=
some_dict.get(key)` and `var y := a if cond else b` (mixed types) both fail to
parse. Annotate explicitly or cast: `var x := float(dict.get(key, 0.0))`.

`%UniqueName` returns `Node`, so accessing a subclass member on it errors at
parse time. Declare `@onready var b: Button = %CloseButton`.

Autoload order matters: `Events` must stay above `GameState` in `project.godot`,
because `GameState._ready()` emits on it.

## Editor caveat

Autoloads registered by writing `project.godot` (as the MCP server does) are not
picked up by a **running** editor — its GDScript analyzer keeps reporting
`Identifier "GameState" not declared`. Restart the editor after touching
autoloads. The game itself is unaffected; verify with the headless commands
above.

`application/run/main_scene` also has to be written directly to
`project.godot` — the MCP server refuses that key.

## Known gaps

- **No audio at all.** `WeaponData` has no sound fields yet.
- **Enemy AI has no navigation.** `enemy.gd` chases on the horizontal plane and
  hops when it hits a wall. Fine for an arena, will not handle corridors — swap
  in `NavigationAgent3D` when levels get interior geometry.
- **Level geometry is CSG.** `CSGBox3D` with `use_collision` is convenient to
  edit but rebuilds meshes at load. Bake to `MeshInstance3D` + `StaticBody3D` or
  a `GridMap` before shipping.
- **No audio or video options** on the title screen or settings menu — only
  sensitivity, FOV, keybinds and the enemy-spawn toggle exist so far. Progress
  itself auto-loads from `user://devil_horn_save.json`; reset from the
  character menu.
- View models are procedural boxes built in `WeaponController._build_view_model()`
  from `WeaponData` sizes. Replace with real meshes when art exists.
