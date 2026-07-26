# Devil Horn Panic

A 3D first-person shooter with platformer movement and light RPG progression,
built in Godot 4.7.

You are dropped into an arena that spawns escalating waves of horned things.
Killing them pays out XP and scrap. XP buys skill ranks and perks that change how
you move; scrap buys weapon upgrades and new hardware at the workbench. The
platforming course above the arena is gated behind the traversal perks: the east
steps and the ferry are open to anyone, the sky chain across the north needs
Blink Step and a double jump to clear its later gaps, and the wall shaft is
impassable until you have bought Wall Runner. Both of the gated routes come out
on the same high ledge.

## Controls

| Action | Key |
| --- | --- |
| Move | `WASD` |
| Crouch / slide | `Ctrl` (while moving to slide) |
| Jump / double jump / wall jump | `Space` |
| Dash | `Shift` (needs the Blink Step perk) |
| Fire | Left mouse |
| Aim down sights | Right mouse |
| Reload | `R` |
| Switch weapon | `1` `2` `3` or mouse wheel |
| Interact | `E` |
| Character sheet / bench | `Tab` |

## Movement

Momentum is preserved rather than clamped: acceleration overshoots your walk
speed and bleeds off, so slides and dashes carry. Running has a ceiling at 1.8×
your move speed — held input cannot climb past it, though a jump pad or a
knockback can, and that momentum decays instead of being clipped. There is
coyote time on ledges and a jump buffer, so late and early inputs both work.
Double jump, wall jump and dash are all perk-gated.

The dash lends you speed rather than setting it. It runs at whatever you were
already doing plus the `dash_boost` stat, holds your height for its duration,
and then hands the borrowed speed back — so it always adds, however fast you
enter, and it pays out most at a run. Kinetic Surge in the Perks tab raises the
boost. On exit, a climb resumes at the speed it had and a fall restarts from
zero, which makes dashing off a ledge a save rather than a faster plummet.

## Progression

Three skill lines — **Brute** (health, armour, damage), **Agile** (speed, jumps,
scrap) and **Tech** (reloads, crits, ammo). Each level grants one skill point and
one perk point. Skill ranks unlock the deeper perks in their line.

Weapons take upgrades in a fixed number of slots. Upgrades trade off rather than
strictly improve — Heavy Rounds adds damage and slows the rate of fire, Hair
Trigger does the reverse, Piercing Core punches through three bodies for slightly
less damage. Progress saves automatically.

## Adding content

Perks, weapons and upgrades are `.tres` resources under `resources/`. Drop a new
one in and it appears in the menus at the next launch — no code changes. See
[CLAUDE.md](CLAUDE.md) for the architecture and the headless test commands.

Levels work the same way. A level is a `LevelData` `.tres` in
`resources/levels/` naming its scene in `scenes/levels/`, and the `Levels`
autoload picks up whatever is in the folder at boot — `main.tscn` contains the
player and the UI but no map, and builds itself around whichever level is
current. Ids carry an ordered prefix so the folder sorts the way the game plays.
There is one so far, `000_poc_1`, the proof-of-concept arena described above;
levels have no completion condition yet, so it runs until you quit.

The sky works the same way too: `resources/sky/` holds `Sky` resources and the
level draws whichever one its `WorldEnvironment` points at. Sky art goes in
`assets/sky/` — [assets/sky/README.md](assets/sky/README.md) has the image
format, which part of a panorama ends up over which side of the arena, and the
command that renders a candidate from inside the level.
