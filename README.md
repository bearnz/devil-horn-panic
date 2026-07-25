# Devil Horn Panic

A 3D first-person shooter with platformer movement and light RPG progression,
built in Godot 4.7.

You are dropped into an arena that spawns escalating waves of horned things.
Killing them pays out XP and scrap. XP buys skill ranks and perks that change how
you move; scrap buys weapon upgrades and new hardware at the workbench. The
platforming course above the arena is gated behind the traversal perks — the wall
shaft at the top is impassable until you have bought Wall Runner.

## Controls

| Action | Key |
| --- | --- |
| Move | `WASD` |
| Sprint | `Shift` |
| Crouch / slide | `Ctrl` (while moving to slide) |
| Jump / double jump / wall jump | `Space` |
| Dash | `Q` (needs the Blink Step perk) |
| Fire | Left mouse |
| Aim down sights | Right mouse |
| Reload | `R` |
| Switch weapon | `1` `2` `3` or mouse wheel |
| Interact | `E` |
| Character sheet / bench | `Tab` |

## Movement

Momentum is preserved rather than clamped: ground acceleration overshoots your
walk speed and bleeds off, so slides and dashes carry. There is coyote time on
ledges and a jump buffer, so late and early inputs both work. Double jump, wall
jump and dash are all perk-gated.

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
