# Devil Horn Panic

3D first-person platformer / shooter in **Godot 4.7.1** (Forward+). Boots to
`res://scenes/ui/title_screen.tscn` (`application/run/main_scene`); gameplay
lives in `res://scenes/main.tscn`, which the title screen loads via
`Levels.play_first()`.

`main.tscn` holds the player and the UI but **no level**. `main.gd` instances
whichever scene `Levels.current` points at, as a child named `Level`. There is
one level so far: `000_poc_1`.

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

Writes `shot_gameplay.png`, `shot_overview.png`, `shot_perks.png`,
`shot_bench.png`, `shot_pause.png` and `shot_pause_keybinds.png`, and prints
where the player ended up and what the crosshair is pointing at. Use it to check
layout and lighting without playing.

```bash
godot --path . --resolution 1280x720 res://scenes/dev/sky_preview.tscn ++ <out_dir>
```

Renders every `Sky` in `resources/sky/` from inside the arena — horizon at each
quarter turn plus the zenith — against the level's real fog and lighting. See
[assets/sky/README.md](assets/sky/README.md) for the image format and which part
of a panorama lands over which side of the level.

## Layout

```
scripts/autoload/   Events (signal bus), GameState (progression), Settings (prefs),
                    Levels (level library + which one is loaded)
scripts/levels/     LevelData
scripts/progression/ StatSheet, PerkData
scripts/weapons/    WeaponData, WeaponUpgrade, WeaponInstance, WeaponController, projectile
scripts/player/     player.gd
scripts/enemies/    enemy.gd (all archetypes), enemy_spawner.gd
scripts/world/      platform, jump pad, checkpoint, ammo crate, workbench,
                    sky_loader.gd (WorldEnvironment with a gradient fallback)
scripts/ui/         hud.gd, crosshair.gd, character_menu.gd, pause_menu.gd, title_screen.gd
scripts/dev/        smoke_test.gd, capture_shots.gd, sky_preview.gd,
                    gen_sky_placeholder.gd
resources/{weapons,upgrades,perks}/   authored .tres content
resources/levels/   LevelData .tres, one per playable level
resources/sky/      Sky resources; swap one into the level's WorldEnvironment
assets/sky/         sky images + the format spec they have to follow
scenes/             mirrors scripts/, plus levels/000_poc_1.tscn
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

**Levels are content too.** A level is a `LevelData` .tres in
`resources/levels/` naming a scene path, plus the scene itself in
`scenes/levels/`. `Levels` scans the folder at boot the same way. Nothing
hard-codes a level path — not `main.tscn`, not the title screen, not the dev
tools. Ids carry an ordered numeric prefix (`000_poc_1`) so the folder sorts the
way the game plays; `LevelData.order` is the real sort key and the id breaks
ties. **`GameState.level` is the player's XP level, not a map** — that collision
is why level loading lives in its own autoload.

A level scene owes `main.gd` two things: a `PlayerSpawn` `Marker3D` and a
`WorldEnvironment`. Everything else is the level's business.

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
because `GameState._ready()` emits on it. `Levels` is independent of all three
and sits last.

A new `class_name` is no more visible to a headless run than a new autoload is
to a running editor — it lives in `.godot/global_script_class_cache.cfg`, which
only a reimport rebuilds. If a script suddenly cannot find a type that plainly
exists, run `godot --path . --headless --import` before debugging anything else.

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
- **Levels do not end.** There is no completion condition, so nothing calls
  `Levels.next_of()` and `000_poc_1` runs until you quit. The registry, the
  ordering and the loading are in place; deciding what finishing a level *means*
  is not.
- **Sky is a placeholder.** The level's `WorldEnvironment` is a `SkyLoader`: its
  `sky` is the procedural gradient and stays that way, while `sky_path` names
  the real sky to load and swap in. `sky_path` is empty today, so the gradient
  is what you see — and it is also the fallback for a missing, broken or
  wrong-typed sky, so the background is never empty. `arena_panorama.tres` is
  wired up and waiting for real art. `Environment.fog_sky_affect` defaults to
  1.0, which erases the sky entirely — the arena pins it to 0.25 and the smoke
  test guards that.
- **Threaded resource loading does not work here.**
  `ResourceLoader.load_threaded_request()` never completes for any resource with
  an `ext_resource` dependency, level scenes included; sub-threads do not help.
  `SkyLoader` defers a synchronous load instead. Do not reach for the threaded
  API without re-testing it.
- **Level geometry is CSG.** `CSGBox3D` with `use_collision` is convenient to
  edit but rebuilds meshes at load. Bake to `MeshInstance3D` + `StaticBody3D` or
  a `GridMap` before shipping.
- **No audio or video options** on the title screen or settings menu — only
  sensitivity, FOV, keybinds and the enemy-spawn toggle exist so far. Progress
  itself auto-loads from `user://devil_horn_save.json`; reset from the
  character menu.
- View models are procedural boxes built in `WeaponController._build_view_model()`
  from `WeaponData` sizes. Replace with real meshes when art exists.
