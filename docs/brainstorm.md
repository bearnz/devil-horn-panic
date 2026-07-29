# Brainstorm

A running list of what could be built next, and why. Nothing here is a
commitment — an item moves out of this file when it becomes a commit, and gets
deleted when it turns out to be a bad idea. Keep the reasoning with the idea:
"add audio" is a note anyone could write, and the useful part is knowing that
every hook for it already exists on the signal bus.

Ordered by how much the game is missing them, not by effort.

---

## Tier 1 — the three real holes

### Audio. There is none at all.

The only `AudioStream` references anywhere in the project are inside the MCP
addon. Half of "feel" is sound, and this project has spent an enormous budget on
the other half.

The cheap part is that [`Events`](../scripts/autoload/events.gd) already emits
every moment worth a sound — `damage_dealt`, `enemy_killed`, `reload_started`,
`level_up`, `wave_started` — so a single `Audio` autoload subscribing to the bus
covers most of it with no plumbing in the systems themselves. Beyond that:
stream fields on [`WeaponData`](../scripts/weapons/weapon_data.gd) (fire, reload,
empty), positional `AudioStreamPlayer3D` on enemies, and player-driven footsteps,
landing and a dash whoosh. Then Master/SFX/Music buses and sliders in
[`pause_menu.gd`](../scripts/ui/pause_menu.gd) — there are no audio options today
because there is no audio.

### The enemies are capsules and the player is a solved humanoid.

[`enemy.gd`](../scripts/enemies/enemy.gd) is a `$Mesh` with an emission flash
doing double duty for "I'm hurt" and "I'm winding up", against 1189 lines of
joint hierarchy and two-bone IK in
[`player_body.gd`](../scripts/player/player_body.gd). `attack_windup` is 0.35
seconds and is documented as existing *so the player can react* — which it cannot,
because a colour change is not a telegraph. An `EnemyBody` built the same way, on
`HandRig.make_material()` so it reads as the same costume department, closes the
biggest gap between how the player feels and what they are shooting at.

### Levels do not end.

`Levels.next_of()` is called by nothing. The registry, the ordering and the
loading all work; what is missing is a decision about what *finishing* means.
Smallest coherent version: an objective on `LevelData` (survive N waves, clear
the arena, reach an exit volume), a `level_cleared` signal on the bus, and a
results panel that hands off to the next level. That is what closes title → play
→ next and makes the arena a game rather than a sandbox.

---

## Tier 2 — combat feel, at the bar the dash set

**Hit feedback.** ~~Floating damage numbers~~ — done, `scripts/fx/damage_numbers.gd`,
merged per target rather than per shot. Still missing from this item:

- ~~**Hitstop.**~~ Dropped. A few frames of `Engine.time_scale` on a kill is the
  cheapest piece left, but this game is a dash, a slide and a mantle strung
  together — stopping the clock to punctuate a kill stops the *movement* too,
  and momentum is the thing the whole feel budget has been spent on. Noted here
  rather than deleted so it does not get re-proposed on the "it's cheap"
  argument alone.
- **A directional damage indicator.** Needs `player_damaged` to carry a direction
  — it currently carries only the amount and the resulting health, so this is a
  signal signature change, and worth making once rather than working around.
- ~~**Something for a kill specifically.**~~ — done. The finishing hit takes the
  merged number over: brighter, bigger, harder punch. Merging is what made it
  cheap, since there is exactly one label per target to hand the kill to and it
  is already carrying the total that did it. The squash tween is no longer alone.

**Firing deserves what the dash got.** The dash has a lens, a smear, wind and a
spring jolt. A shot has recoil and a tracer. Muzzle flash light, a camera kick
reusing the shunt spring, shell ejection, an ADS FOV pull, a dry-fire click and a
low-ammo cue.

**A second level.** One level means "levels are content" is an assertion rather
than a demonstration. A second one proves nothing is hard-coded to `000_poc_1`,
and it is what forces the navigation question below into the open.

---

## Tier 3 — half-built systems

**More enemies.** Two archetypes exist, and
[`enemy_spawner.gd`](../scripts/enemies/enemy_spawner.gd) picks from
`1 + wave / 2` of them — so "later waves lean towards the tougher end" barely has
a pool to lean into. A charger, a flier, a shielded one; each is one `.tscn`.

**`NavigationAgent3D`.** Flat chase plus hop-at-wall is fine for an arena and
breaks the moment a level has a corridor. Do this *with* the second level, not
before it.

**Wave structure.** The spawner is a linear ramp with a timer between waves. No
elites, no boss, no pacing beat.

**More weapons and upgrades.** Three and seven, all `.tres`. A charge weapon or a
beam would exercise [`WeaponController`](../scripts/weapons/weapon_controller.gd)
in ways the current three do not.

**Death has no consequence or screen.** The corpse is eased back to spawn. With
progression persisting across a run, a summary is the obvious missing beat.

---

## Tier 4 — infrastructure worth queuing

- **Video settings** — resolution, vsync, quality. Nothing exists beyond
  sensitivity, FOV and keybinds.
- **Bake the CSG** to `MeshInstance3D` + `StaticBody3D`. Already flagged in
  CLAUDE.md; the cost grows with every level added.
- **Real sky art** — `arena_panorama.tres` is wired up and waiting.
- **Split [`smoke_test.gd`](../scripts/dev/smoke_test.gd)** — 3221 lines, 29% of
  all script code, and it is the only coverage in the project, so it only grows.
  Per-area suites behind a runner would keep it addable-to.

---

## Where to start

Audio, then enemy bodies. Audio has the best ratio in the list: every hook
already exists on the bus, and it is the loudest thing missing from a game this
concerned with feel. Enemy bodies second, because they are the other half of
every fight and the wind-up telegraph is invisible until they exist. Level
completion third — it is the most design-dependent of the three and wants the
question "what is a run" answered first.
