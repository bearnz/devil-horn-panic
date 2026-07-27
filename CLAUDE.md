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

The spawner is seeded randomly, so the wave is the one thing in the run that
differs between passes — which makes anything it can walk into flaky rather than
wrong. The wave is held (through the spawner's own toggle) across the cases that
measure the player rather than the fight — the view hands, the body, and the
two seconds the fire-rate case stands still with the trigger down: an enemy
in melee range shoves the body and kicks the camera between the frame a pose is
applied and the frame it is read, and that reads as a hand a centimetre off its
grip. A player death anywhere in the run is latched and reported for the same
reason — a corpse is eased to a stop and teleported back to spawn, so an air-time
probe downstream measures a fall that never accelerated and fails somewhere far
from the cause.

```bash
godot --path . --resolution 1280x720 res://scenes/dev/capture_shots.tscn ++ <out_dir>
```

Writes `shot_gameplay.png`, `shot_overview.png`, `shot_perks.png`,
`shot_bench.png`, `shot_pause.png` and `shot_pause_keybinds.png`, and prints
where the player ended up and what the crosshair is pointing at. Use it to check
layout and lighting without playing.

It also writes a close-up of the view model per weapon in the loadout
(`shot_hands_<weapon id>.png`) plus `shot_hands_mantle_grab.png` and
`shot_hands_mantle_climb.png`, taken from a real mantle on the arena's west step.
Those are cropped out of the bottom-centre of the frame and doubled, because the
hands occupy a corner of it. Tuning a hold pose or the ledge grab means looking
at these — there is no other way to see whether a hand is on the grip or behind
it.

The player's body gets the same treatment, for the same reason: nothing in a
normal frame shows more than its shins. `shot_body.png` and
`shot_body_crouched.png` are three-quarter views from a throwaway camera with
`PlayerBody.first_person` switched off, so the head and arms come back, and
`shot_body_dash.png` is one more from the same camera with a dash held open —
the only pose in the game that is neither a stance nor a step, and the only way
to see whether the legs are trailing or the body is just falling over;
`shot_body_first_person.png`, `shot_body_look_down.png` and
`shot_body_crouch_look_down.png` are down the player's own nose at a glance, at
the pitch clamp, and at the pitch clamp crouched. Those three are what tell you
whether the eye clears the legs — too little and they are a plate across the
screen, too much and there is nothing under you at all. The crouched one is the
only view of the squat anybody playing the game will ever get.

`shot_third_person.png` is the odd one out: taken mid-stride through the game's
own third-person toggle rather than a throwaway camera, so it photographs a mode
the player can be in rather than a rig. It is what confirms the swap is complete
— body back, view model gone — and the still frames above are still the better
place to judge a pose.

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
scripts/player/     player.gd, hand_rig.gd (one gloved hand, shared),
                    view_hands.gd (first-person pair), player_body.gd (humanoid)
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

**Physics interpolation is on**, because physics ticks 60 times a second and the
game renders as fast as the display will take it — without it a 144Hz monitor is
shown the same 60 positions over and over and high frame rates buy nothing but
heat. The rule it imposes: **anything teleported must call
`reset_physics_interpolation()`**, or it is drawn gliding there from wherever it
used to be. That means the respawn and the level's spawn placement, and every
node that is added to the tree and only then positioned — projectiles, impact
FX, spawned enemies, all of which would otherwise streak in from the world
origin on their first frame. A camera driven from `_process` and photographed on
the very next frame, which is the dev capture rig's throwaway camera, has to opt
out instead: `physics_interpolation_mode = PHYSICS_INTERPOLATION_MODE_OFF`. The
price is that the view is one tick behind; if that ever reads as sluggish, the
fix is a faster physics tick rather than turning this off.

**Rate of fire is carried, not reset.** Firing is polled on the idle loop, so a
shot can only start on a frame boundary. `_cooldown` is therefore floored just
*below* zero (`MAX_CARRY`) and `_fire` adds the interval to what is left instead
of assigning it, so the sliver a cooldown overran by is paid back by the next
shot. Assign it outright — the obvious version — and every shot rounds up to a
whole frame, which puts damage per second on the frame rate: the Shredder's
nominal 11/s measured 9.96 at 60fps against 11.00 at 240. The smoke test holds
the trigger and checks the rate, which pins the 60fps end of that.

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
  in `NavigationAgent3D` when levels get interior geometry. Two things about it
  are load-bearing and easy to undo. Chasing is flat but **striking is not**:
  attacks gate on the real distance, or everything standing on the floor is
  within punching range of a player up on a platform. And enemies stop closing
  once they are inside attack range rather than at the player's skin — a grunt
  that keeps shoving walks up the capsule and ends up standing on the player's
  head, riding them wherever they go. Dropping the player off the enemies'
  collision mask looks like the tidier fix and is much worse: they then overlap,
  and the player's own depenetration pushes them out through the floor.
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
- **The trigger arm's carry pose is solved, not authored.** There is a real weapon
  in that fist, so the five angles that place it (`CARRY_*_TRIGGER` in
  `player_body.gd`, including a wrist that exists only for this) have to satisfy
  two things at once: the barrel points where the player faces, and the weapon
  sits far enough off the centre line to clear the chest and the arm in front of
  it — otherwise it is a gun its owner is standing in front of. Those two fight,
  which is what the wrist roll is for, and they cannot be retuned one at a time.
  The smoke test asserts both properties rather than the angles.
- **The third-person view is a review tool, not a game mode.** `V` (or the
  settings checkbox) swaps the current camera for a `SpringArm3D` chase camera on
  the same pivot, offset over the right shoulder so the weapon is not behind its
  owner, puts the whole body back and hides the view model, which is the
  only way to watch a slide, a dash or a mantle while it moves instead of one
  captured still at a time. What it deliberately does not move is aim: shots and
  the interact ray still leave the head down the pivot's direction, so the
  crosshair is right about *which way* and wrong about *where* by the parallax of
  standing 2.5m further back. Expect it to be cut, or earned, before 1.0.
- **No audio or video options** on the title screen or settings menu — only
  sensitivity, FOV, keybinds, the enemy-spawn toggle and the third-person toggle
  exist so far. Progress
  itself auto-loads from `user://devil_horn_save.json`; reset from the
  character menu.
- View models are procedural boxes built by `WeaponController.build_model()` from
  `WeaponData` sizes, and the hands holding them are procedural boxes built in
  `ViewHands`. Replace both with real meshes when art exists. The hands read two
  `Marker3D` anchors on the view model naming the parts that get held, so new
  weapon geometry only has to move those; `WeaponData.support_grip` picks between
  an off hand on the barrel and one cupping the shooting hand, which is the one
  thing that cannot be derived from the sizes.
- **Every weapon is built twice.** `build_model()` is static and has two callers:
  the view model in front of the camera, and a second copy `PlayerBody` puts in
  the humanoid's right fist. The second one exists because the view model is a
  child of the *camera* — from any other camera it hangs in the air beside the
  player's head, which is why third person hides it. They are placed from the same
  numbers rather than posed apart: `model_in_grip_frame()` is the grip anchor
  inverted, so the fist closes on the weapon exactly where `ViewHands` puts the
  view model into the hand. The body's copy casts a shadow and the view model does
  not, which is what puts a rifle in the silhouette on the wall.
- **There is one hand in this game.** `HandRig` builds it — geometry, materials
  and finger curl — and both `ViewHands` and `PlayerBody` instance that same rig,
  the first hanging a pair off the weapon anchors and the second putting a pair on
  the end of real arms. Anything about how a hand *looks* belongs there; anything
  about where a hand *goes* belongs in the caller. `HandRig.make_material()` is
  also what dresses the rest of the body, which is why the suit, the gloves and
  every accent read as one costume.
- **The player has a body, and it is procedural too.** `PlayerBody` is a joint
  hierarchy of boxes at standard proportions for `Player.STAND_HEIGHT`, posed in
  `_process` off stance and velocity — nothing drives it. Two things about it are
  load-bearing. First, the hips are placed at whatever height the leg angles put
  them (`ANKLE_Y + thigh·cos + shin·cos`) rather than at a number, so bending the
  knees keeps the soles on flat ground by construction; there is no IK, so a
  swinging foot can still clip a slope. The dash pose is the deliberate exception
  and is kept out of that sum — it swings the legs out behind a body being flung
  forward, and feeding legs that have left the ground into a formula whose whole
  job is keeping them on it drops the hips half a metre. Second, pitch is quoted
  forward-positive
  throughout, but limbs hang down their pivot's -Y while the spine stands up +Y —
  so the spine's lean is the one place the sign is negated. Get that backwards and
  a crouch becomes a backflop.
- **`PlayerBody` and `HandRig` are `@tool` scripts**, so the body builds in the
  editor's 3D viewport too — open `player.tscn`, or any scene the player is
  instanced into, and there is a humanoid standing on the origin instead of an
  empty `Node3D`. The editor build stops at geometry plus the carry pose: there is
  no `Player` to read a stance off and the autoloads are not instantiated in the
  editor, so `_ready()` returns early and `_process()` does nothing. `first_person`
  is ignored there as well, or the torso would be shadows-only in a viewport with
  nothing to catch a shadow. The boxes are added without an `owner`, which is what
  keeps them out of the saved `.tscn` — `Body` is empty on disk and stays that way,
  so nothing here can be edited in the inspector. It is a preview, not a rig.
  Editing either script from outside Godot will not update a running editor until
  it regains focus; if the viewport is stale, reopen the scene.
- **Two offsets exist so the player can see their own legs**, and they are easy to
  undo by accident. `Player.EYE_FORWARD` moves the camera pivot off the body's
  centre line, because eyes live in the front of a head and a camera on the
  centre line looks straight down *through* the thighs. `CROUCH_SET_BACK` slides
  the hips back as the squat deepens, which is what a squat does anyway and is
  the only thing that ever gets the eye in front of the knees. The smoke test
  asserts the property — eye ahead of knee, crouched — rather than the numbers.
- **The crouch trades depth for knees.** Thighs at 45° read as a squat from above;
  flatter thighs get the hips lower (a real deep squat is nearly flat) but from
  the first-person camera they are a shelf with no knee in them. 45° won, so the
  crouched model stands about 1.35 against a 1.05 collider and its head sits above
  the crouched eye height. A head can therefore poke through a low ceiling — no
  arena geometry is that tight yet. If that ever matters, raising `CROUCH_HEIGHT`
  and `EYE_CROUCH` to meet the model is the cheaper fix than flattening the pose.
- **Animation runs on the idle loop, the body on the physics one.** `ViewHands`
  and `PlayerBody` pose in `_process` while the player moves in
  `_physics_process`, so a coroutine awaiting `physics_frame` can read a torn
  state: this node's new transform with a hand offset built for the old one.
  `ViewHands.hand_position()` and `grab_weight()` report what was last actually
  applied for exactly this reason — do not swap them for live reads.
