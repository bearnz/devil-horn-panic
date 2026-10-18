# Audio

The project had **no audio at all**. This is the first step towards some, and it
is deliberately only the first: 143 candidate sound effects are sitting in
`candidates/`, none of them wired to anything. The next step is choosing, and the
step after that is a system to play what was chosen.

## What is here

```
candidates/<nn>_<event>/<nn>_<label>.<ext>   143 candidates across 35 events
candidates/_reference/                       not candidates — see below
picks.json                                   what was chosen, written by the audition tool
CREDITS.md                                   every source, author and licence
```

`_reference/` holds real long bursts from three automatic weapons, kept for
comparison rather than for choosing: they are what the audition tool's `F` key is
trying to reproduce. Folders beginning with an underscore are skipped by the
event list, so they never sit in the picked-so-far count waiting to be chosen.

Every candidate is **CC0 1.0** — public domain, commercial use, no attribution
required. `CREDITS.md` lists them anyway; see the note at the top of it for why.

The event folders carry an ordered numeric prefix, same convention as
`resources/levels/`, so the folder sorts the way a review would want to go
through it: weapons first, then impacts, enemies, the player, the world, the UI.
The number is for ordering only — `picks.json` is keyed on the whole folder name.

## Reviewing

```bash
godot --path . res://scenes/dev/sound_audition.tscn
```

Left column is the events, right column the candidates for the selected one.

| key | |
| --- | --- |
| up / down | previous / next candidate — **plays it**, since stepping is how you choose |
| left / right | previous / next event |
| space | replay the selected candidate |
| `A` | play every candidate for this event back to back |
| `F` (hold) | repeat at the weapon's real fire rate |
| `1`–`9` | pick that candidate for this event |
| backspace | un-pick this event |
| `.` | stop everything |
| `S` / escape | save (it also saves on every pick) |

`A` and `F` are the two that matter, and they are why this is a tool rather than
a folder of files to double-click.

`A` exists because a sound effect has no absolute quality — it is only ever
better or worse than the other four, and the candidates were curated to be
*different from each other* rather than merely plausible. Judged one at a time
you are comparing each against a memory of the last.

`F` exists because of the Shredder. It fires **11 rounds a second**, so each shot
has 90 milliseconds before the next one lands on top of it. Nearly every gunshot
recording in the world is longer than that, which means a candidate that sounds
superb once can be an undifferentiated wall held down — and that is the only way
this weapon is ever actually heard. The interval is read live off the weapon's
own `.tres`, so retuning `fire_rate` in the editor changes what `F` plays. The
same key works on any other event at a fixed 0.35s, which is a rough stand-in for
a footstep cadence.

Picks are written to `picks.json` on every keypress rather than on exit, because
the way a session like this ends is Alt+F4.

## What is deliberately not done

**Nothing is wired in.** No `AudioStreamPlayer` in a scene, no sound fields on
`WeaponData`, no bus layout. Choosing first is the cheap order: wiring 35 events
and then discovering the Shredder's shot does not survive being repeated means
doing it twice.

**The candidates are not pruned.** Once `picks.json` is filled in, the unchosen
~110 files should be deleted and the picks promoted to stable names — a repo does
not want four rejected takes per event sitting in it forever. That deletion is
not automatic on purpose; it is not reversible and it is not mine to make.

**Nothing has been levelled, except the gunshots.** The candidates come from
eleven different sources and their loudness is all over the place, so a
comparison in the audition tool is partly a comparison of gain. Judge character,
not volume; matching levels is a mixing pass that belongs after the picks, and
Godot's per-player `volume_db` plus a bus layout is where it goes.

The weapon-fire candidates are the exception, and only because they had to be:
they are studio masters cut with headroom, and they arrived far quieter than the
pack material beside them. `split_shots.py` peak-normalises them to -1 dBFS,
which throws away the real loudness difference between a .22 and a .45 — a
mixing decision, made later and per weapon, not one a listening test should be
deciding by accident.

## A few things the shortlist assumes

**The three weapons want three different answers.** The Horn Iron is a semi-auto
service pistol at 4.5/s, the Shredder a full-auto carbine at 11/s, the Hellmouth
a break-action grenade launcher at 0.9/s with `heft` 0.9 and `recoil` 2.4. Each
event folder holds three or four *real firearm* options and one *sci-fi* one,
because that choice — whether this game's guns are recorded or synthesised — is
one decision that ought to be made once across all three rather than three times.

The real ones were chosen to match what each weapon is rather than to be
gunshots in general: pistols for the Horn Iron (a 1911, a Walther PPQ, a .38
revolver), **submachine guns** for the Shredder (a PPSh and a Carl Gustav M45,
plus an AK-47 and an SKS for something heavier), and 12-gauge shotguns plus a
Mosin Nagant for the Hellmouth's launch thump. The library has a mid-distance
take of every one of these and none of them are used — mid distance is the
perspective of someone standing near a shooter, and the player *is* the shooter.

**The Hellmouth fires twice.** `12_fire_hellmouth` is the *launch*, and it should
be a hollow thump rather than a bang — the shell then flies, bounces, rolls, and
goes off up to `projectile_fuse` (2.2s) later, which is `23_explosion` and a
different sound in a different place. Picking an explosion for both is the easy
mistake, and it makes the weapon read as hitting instantly.

**`21_impact_flesh` and `31_enemy_death` are separate on purpose.** `CombatFX`
already distinguishes them, and the damage numbers go to some trouble to mark a
kill as different from a hit — the audio wants the same split or it undoes that.

**Nothing here covers the dry fire's other half.** `WeaponController._dry_fire()`
has had a comment since it was written saying the click it needs is audio and
there is none. `13_dry_fire` is that click. It is the one candidate in this set
that closes a hole the code already knew about.
