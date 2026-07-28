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

`shot_hands_swap.png` is the odd member of that set: the exact frame one weapon
turns into another, and it is supposed to be an **empty crop**. Anything visible
in it is geometry the player watches change shape.

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

`shot_body_swap.png` is the same moment as `shot_hands_swap.png` from the
outside, and it is the only place the switch pose can actually be *seen* — the
first-person version of the shot is blank on purpose. What it shows is the
weapon down beside the right hip with one arm carrying it and the off hand let
go and hanging.

`shot_body_hold_<weapon id>.png` is one per weapon in the loadout, framed on the
chest from the same throwaway camera. The carry is the only pose in the game that
is solved rather than authored, and it is per weapon — a longer receiver is carried
further out and its support hand slides further back along the barrel — so these
are where you check that the arms which came back are ones a person could have and
that both hands landed on the gun rather than near it.

`shot_body_pitch_up.png` and `shot_body_pitch_down.png` are the same camera taken
square on from the shooting side rather than three-quarter, and close, because
their whole subject is an angle in the plane a three-quarter view foreshortens:
the body aiming steeply up and steeply down. Both are shot at the camera's own
pitch clamp (±1.45) rather than somewhere comfortable, since that is where the
solve is worst. Nothing in first person can show this — the view model hangs off
the camera and pitches with it for free — so these are the only check that the
barrel is on the line of sight, that the chest leans into it, that the elbows are
under the weapon rather than over it, and that the off hand is still on the weapon
at the top of the swing, which is the furthest it is ever asked to reach.

`shot_third_person.png` is the odd one out: taken mid-stride through the game's
own third-person toggle rather than a throwaway camera, so it photographs a mode
the player can be in rather than a rig. It is what confirms the swap is complete
— body back, view model gone — and the still frames above are still the better
place to judge a pose.

`shot_decals.png` is a burst emptied into the arena's **west** wall from a few
metres out — west because the sun travels towards -X, -Y, -Z, so that wall and
the north one are the only two whose inward faces are lit, and a bullet hole on
an unlit wall is a dark shape on a dark shape. Bullet holes are `Decal`s, which
project onto whatever geometry falls inside a box rather than sitting on a quad
in front of it, and every way that goes wrong is invisible in code and obvious
here: a hole projected along the wall instead of into it is a smear, a box too
shallow lands nothing at all, and a texture with anything in its corners puts a
square on the wall. The burst is fired at an angle on purpose — a projection is
only tested by a surface its box is not square with.

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

**Bullet holes are capped, not timed.** Everything else in `CombatFX` frees
itself when its tween ends; a decal is meant to still be there when the player
turns round, so nothing frees it but `DECAL_LIMIT` — oldest out first, faded over
a quarter-second rather than blinked away. That is the only thing standing
between a held trigger and a draw call per bullet for the rest of the level, and
the smoke test asserts it. Two other things about them. Only the environment is
marked: `_resolve_hit` puts a hole where nothing implements `apply_damage`, since
a body is not something a mark stays on and a dying enemy takes it with it. And a
hole is parented to what was shot only when what was shot can *move* — a platform
carries its own — while static geometry goes on the FX host, because the level is
CSG and hanging a child off a CSG shape per bullet invites a mesh rebuild
mid-firefight.

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
origin on their first frame. **The reset has to be the last thing done to the
transform** — rotation included. Turning a node after resetting it re-arms exactly
the interpolation the reset cancelled, and it is drawn sweeping into place over the
next tick. That is why `CombatFX._spawn()` takes a basis instead of letting callers
`look_at()` afterwards: a tracer pivots about its own centre, so a 40m shot swung
its near end through an arc tens of metres wide and read as several tracers fanning
out of thin air behind the shooter. It was invisible in first person, where that arc
falls off the sides of the screen, and obvious from the chase camera. A camera driven
from `_process` and photographed on
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
- **The weapon is authored and the arms are solved.** `CARRY_WEAPON_POS` and
  `CARRY_WEAPON_EULER` in `player_body.gd` say where the weapon is carried, and
  `_solve_arm()` is two-bone IK that works out the shoulder, elbow and wrist that
  put a hand there. That direction matters: the arms were hand-posed once and the
  weapon inherited whatever five joint angles multiplied out to, which was a pistol
  carried twenty degrees off the vertical pointing across the arena. Four things
  about it are load-bearing. The position is quoted in the chest's frame and the
  *angles are not*, so a crouch carries the weapon down without pointing it at the
  floor — leave both in the chest's frame and a squat aims at the ground and a
  slide at the sky. The depth is measured to the back of the receiver with half the
  weapon's own length added on, because these receivers run 0.30 to 0.46 and one
  fixed number either holds the pistol at arm's length or carries the carbine
  through its owner's ribs. **That same depth is the only thing setting how straight
  the arms are** — the wrist goes where the weapon says and the elbow folds by
  whatever is left, so a weapon carried close in is a body hunched around it; the
  useful band is about 0.60 to 0.85 of full reach, and past the top of it the solve
  runs out of arm and starts pointing at the grip instead of holding it. What stops
  the depth going further is the *support* arm, which has to cross the body to a
  weapon carried on the other side: `_support_grip` slides that hand back along the
  weapon until it is in reach, and the slide is bounded by where the other hand
  already is. And the elbow poles spend the one degree of freedom a wrist position
  leaves free — left alone the solve takes the shortest turn from a hanging arm and
  puts the elbow behind the player's back. There are two of them
  (`ELBOW_POLE_TRIGGER`, `ELBOW_POLE_SUPPORT`) rather than one mirrored, because the
  arms are not doing mirrored jobs: the shooting elbow goes down, out and a little
  back, and the support elbow belongs under the weapon it is holding up. Both **swing
  with the weapon**, which is what a shoulder does anyway and is not optional —
  a pole held still while the weapon pitches sweeps into line with the
  shoulder-to-wrist axis, and at that point the circle the elbow is being placed on
  has shrunk to a point and the arm turns inside out. The smoke test asserts the
  properties — points forward, stands upright, clear of the chest, a hand on each
  anchor, the elbow in the same place *in the weapon's frame* at every look angle —
  rather than any angle.
- **The arms react to movement, and they do it by not being animated.** Running,
  jumping, sliding, dashing and simply standing there each offset *the weapon*
  (`_carry_motion()`), and the arms are whatever `_solve_arm` says still holds it
  where it now is. That direction is the whole trick: pose a shoulder to swing and
  the hand on the end of it slides along the gun it is gripping, so the one thing
  that must never happen here is animating an arm. The first-person view model
  carries its own copy of the same offsets, because the hands in front of the
  camera are nailed to it. Read every amplitude in that block as an **angle at the
  shoulder, not a distance**: the weapon is carried close in to a shoulder half a
  metre away, so a centimetre of weapon is roughly ten degrees of arm. The first
  cut used under three centimetres for the run and produced a soldier pumping his
  arms with a rifle bolted to them. The smoke test bounds it at both ends — the
  motion has to reach the arm, and it has to stop well short of a stride swing —
  and re-checks the grip *mid-stride*, since "the arm moved" and "the arm let go"
  look identical in a still frame.
- **Aiming down sights turns nearly all of that off.** Sights are the game promising
  the muzzle is where the crosshair is, and every offset above is a small lie about
  where the weapon is — free at the hip, where the weapon is scenery in the corner of
  the frame, and the whole picture once the player is looking along the barrel.
  `AIM_SWAY_MULT` (0.15) damps the *oscillations* — breathing, the walk bob, look
  sway, vertical inertia — and `AIM_STANCE_MULT` (0.5) damps the dash and slide
  offsets, which are not sway but where the weapon is carried while the body is doing
  something, and on the body are what holds it clear of knees that have come up in
  front of it. Neither goes to zero: a weapon that is perfectly still reads as a HUD
  element rather than as something being held. Eased through `aim_amount()` rather
  than stepped, because `aiming` flips on one frame and the sine it scales is
  mid-swing when it does. `PlayerBody` reads that same accessor and uses the
  controller's own two constants, so the weapon in the shadow and the weapon at the
  eye hold equally still. Recoil is deliberately *not* damped here — it answers a
  shot, not the player's movement, and `_recoil` already cuts it while aiming.
- **The body points the weapon where the player is looking**, and it is the one
  part of the pose the first-person view can never catch — the view model is a
  child of the camera and pitches with it for free, so only the body's copy had to
  be told. `PlayerBody._camera_pitch()` reads it off the camera's own basis rather
  than `Player._pitch`, which is what carries recoil and the mantle look-down
  through for free. It is spent in two places. The rotation takes the *whole* angle,
  because the barrel has to end up on the line of sight and nothing else is going to
  put it there. The position is swung about the line between the shoulders — an arm
  raises a weapon by turning at the shoulder, so the muzzle coming up brings the
  receiver down with it, and a weapon pitched where it stands is a gun on a hinge
  welded to the ribs. `LOOK_SPINE_SHARE` splits the swing between the chest and the
  arms: give the arms all of it and a full look up is two arms straight overhead on
  a torso standing bolt upright. The head undoes whatever the chest took, so it goes
  on pointing exactly where the camera does and simply has less neck to do it with.
  `LOOK_REACH` pushes the weapon a little further out along that line as the swing
  steepens, because a weapon can be held in against the shoulder while it is level
  and cannot while it is pointing at the sky. Aiming does *not* damp any of this —
  the whole point of sights is that the weapon goes where you are looking.
- **Both of the body's hands are on the weapon**, at the same two anchors
  `ViewHands` puts the first-person pair on (`WeaponController.wrist_in_model_frame()`,
  which is `ViewHands._hold_pose` hoisted static). The off hand is the awkward one:
  a carbine's foregrip sits further from the shoulder than an arm is long, so
  `_support_grip()` slides it back along the weapon until it is in reach and caches
  how far, per weapon. Sliding rather than stretching is the point — an arm at full
  extension still misses by however far it was short. Two things bound the slide.
  It stops a palm and a half short of the hand on the grip, which is a question
  about the other hand rather than about the barrel — quoting it that way is what
  lets a long receiver be held by the magazine well, where a support hand goes on a
  real carbine, instead of the slide running out on the barrel with the arm still
  short. And it is solved against the *worst* carry pose rather than the standing
  one (`_carry_at()`, which `_solve_carry` also uses so there is only one copy of
  the arithmetic): the look swing is about the line between the shoulders, so a
  weapon carried on the right and swung at the sky is measurably further from the
  left shoulder than the same weapon held level. Solve it at the horizon alone and
  the hand can just reach while the player looks straight ahead and has quietly let
  go by the time the muzzle is up.
- **The third-person view is a review tool, not a game mode.** `V` (or the
  settings checkbox) swaps the current camera for a `SpringArm3D` chase camera on
  the same pivot, offset up and well over the right shoulder, puts the whole body
  back and hides the view model, which is the
  only way to watch a slide, a dash or a mantle while it moves instead of one
  captured still at a time. The offset is the weapon's: carried correctly it sits
  in front of the chest rather than out at arm's length, and from any camera much
  closer to dead-behind its owner is standing in front of it. What it does not move
  is where a shot starts — that is still the head — so the crosshair and the shot
  are two lines a shoulder apart, and parallel lines a shoulder apart meet at the
  vanishing point and nowhere nearer. That is why `aim_direction()` traces the
  *current* camera's centre ray first and aims the shot at the point it lands on
  rather than along its direction: aiming at a point closes the triangle at every
  range, where matching the direction only closes it at infinity. The symptom it
  cures is bullets landing a hand's width left of the crosshair up close while
  looking perfect across the arena. The **interact ray** is still fired straight
  down the pivot and still has the parallax. Expect the whole mode to be cut, or
  earned, before 1.0.
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
- **A weapon switch is an animation, not an assignment.** `equip()` starts one and
  returns; the weapon in hand drops to the right hip, the geometry is rebuilt down
  there where none of it is on screen, and the new one comes back up the same way
  (`HOLSTER_TIME` then `DRAW_TIME`, about a third of a second all told). Three
  things follow. `current()` keeps reporting the **old** weapon for the whole
  descent, so the HUD's ammo, the hands, the body's copy and what a trigger pull
  would fire all change over on the one frame the player sees it happen — read
  `GameState.equipped_index` to find out what is in hand and `target_index()` to
  find out what is coming. The trigger is dead for the duration (`is_swapping()`).
  And the trip to the hip is applied *on top of* the pose smoothing rather than
  through it, because an eased offset is never finished, only close — and "close
  to the hip" is a receiver with its last centimetre still over the bottom edge
  when it changes into a different one. Anything scripted that equips and then
  reads the weapon has to wait the switch out; the dev tools have helpers for it.
  `PlayerBody` makes the same trip off `swap_amount()` rather than a second clock,
  and drops its off hand on the way: the weapon goes to the *far* hip from that
  arm, and an arm sent after it is one stretched straight and still short.
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
  the end of real arms — and both pairs are sent to the same two anchors, so the
  hands you look at and the hands your shadow has hold the same gun in the same
  places. Anything about how a hand *looks* belongs there; anything
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
