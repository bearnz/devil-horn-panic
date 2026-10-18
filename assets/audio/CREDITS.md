# Audio credits

Every candidate under `candidates/` is **CC0 1.0** (public domain
dedication): free for commercial use with no attribution required. It is
recorded here anyway, because the obligation being zero is a fact about
these files rather than about the next ones — a pack dropped in later
under CC-BY looks identical on disk, and the only place that difference
can live is a list.

Nothing here is wired into the game yet. See `README.md` in this folder.

## Sources

| Pack | Author | License | Files used |
| --- | --- | --- | ---: |
| [RPG Audio](https://kenney.nl/assets/rpg-audio) | Kenney | CC0 1.0 | 21 |
| [Interface Sounds](https://kenney.nl/assets/interface-sounds) | Kenney | CC0 1.0 | 21 |
| [Impact Sounds](https://kenney.nl/assets/impact-sounds) | Kenney | CC0 1.0 | 20 |
| [Digital Audio](https://kenney.nl/assets/digital-audio) | Kenney | CC0 1.0 | 19 |
| [The Free Firearm Sound Library](https://opengameart.org/content/the-free-firearm-sound-library) | Ben Jaszczak, et al. | CC0 1.0 | 14 |
| [Sci-Fi Sounds](https://kenney.nl/assets/sci-fi-sounds) | Kenney | CC0 1.0 | 14 |
| [80 CC0 creature SFX](https://opengameart.org/content/80-cc0-creature-sfx) | rubberduck | CC0 1.0 | 10 |
| [80 CC0 creature SFX 2](https://opengameart.org/content/80-cc0-creture-sfx-2) | rubberduck | CC0 1.0 | 8 |
| [Music Jingles](https://kenney.nl/assets/music-jingles) | Kenney | CC0 1.0 | 6 |
| [100 CC0 SFX](https://opengameart.org/content/100-cc0-sfx) | rubberduck | CC0 1.0 | 4 |
| [UI Audio](https://kenney.nl/assets/ui-audio) | Kenney | CC0 1.0 | 3 |
| [Gun reload sounds](https://opengameart.org/content/gun-reload-sounds) | SpringySpringo | CC0 1.0 | 3 |
| [25 CC0 bang / firework SFX](https://opengameart.org/content/25-cc0-bang-firework-sfx) | rubberduck | CC0 1.0 | 2 |
| [Chunky Explosion](https://opengameart.org/content/chunky-explosion) | Joth | CC0 1.0 | 1 |

### A note on the gunshots

Every weapon-fire candidate comes from *The Free Firearm Sound Library*,
and none of them are the files as published. The originals are 96kHz
24-bit stereo **montages** — two to five rounds fired into one take, six
to thirty seconds long — because that is what is useful to a sound
designer with a DAW open, and useless to a game. Each was put through
`tools/audio/split_shots.py`, which slices out one file per transient,
downsamples to 48kHz/16-bit through an anti-alias filter, and peak
normalises to -1 dBFS. That last step is worth knowing about when
judging them: it deliberately discards the real loudness difference
between a .22 and a .45, because a candidate that merely arrives louder
wins a listening test it did not deserve. Only the *near distance* takes
were used — the library also has a mid-distance pair for every weapon,
which is the wrong perspective for a gun in the player's own hands.

### `_reference/`

Not candidates. Real long bursts from the three automatic weapons in the
library, downsampled and folded to mono, kept as a reference for what an
automatic actually sounds like at rate — which is what the audition
tool's `F` key is trying to reproduce for the Shredder. The leading
underscore is what keeps the folder out of the pickable event list.

## Every candidate

| Event | File | Length | Pack |
| --- | --- | ---: | --- |
| 10_fire_sidearm | 01_colt_1911_45.wav | 0.69s | The Free Firearm Sound Library |
| 10_fire_sidearm | 02_walther_ppq_9mm.wav | 0.69s | The Free Firearm Sound Library |
| 10_fire_sidearm | 03_sw_642_revolver.wav | 0.69s | The Free Firearm Sound Library |
| 10_fire_sidearm | 04_scifi_small.ogg | 0.25s | Sci-Fi Sounds |
| 11_fire_shredder | 01_ppsh_smg.wav | 0.70s | The Free Firearm Sound Library |
| 11_fire_shredder | 02_carl_gustav_smg.wav | 0.70s | The Free Firearm Sound Library |
| 11_fire_shredder | 03_ak47.wav | 0.70s | The Free Firearm Sound Library |
| 11_fire_shredder | 04_sks_carbine.wav | 0.70s | The Free Firearm Sound Library |
| 11_fire_shredder | 05_scifi_retro.ogg | 0.23s | Sci-Fi Sounds |
| 12_fire_hellmouth | 01_mossberg_12ga.wav | 0.69s | The Free Firearm Sound Library |
| 12_fire_hellmouth | 02_model12_pump_12ga.wav | 0.69s | The Free Firearm Sound Library |
| 12_fire_hellmouth | 03_mosin_nagant_boom.wav | 0.69s | The Free Firearm Sound Library |
| 12_fire_hellmouth | 04_nova_pump_12ga.wav | 0.69s | The Free Firearm Sound Library |
| 12_fire_hellmouth | 05_cannon.ogg | 0.86s | 25 CC0 bang / firework SFX |
| _reference | 01_ppsh_long_burst.wav | 5.79s | The Free Firearm Sound Library |
| _reference | 02_carl_gustav_long_burst.wav | 9.08s | The Free Firearm Sound Library |
| _reference | 03_ak47_long_burst.wav | 9.94s | The Free Firearm Sound Library |
| 13_dry_fire | 01_metal_click.ogg | 0.45s | RPG Audio |
| 13_dry_fire | 02_metal_latch.ogg | 0.26s | RPG Audio |
| 13_dry_fire | 03_ui_click.ogg | 0.10s | Interface Sounds |
| 13_dry_fire | 04_switch.ogg | 0.30s | UI Audio |
| 14_reload_start | 01_mag_out_belt.ogg | 0.28s | RPG Audio |
| 14_reload_start | 02_rifle_reload.wav | 1.56s | Gun reload sounds |
| 14_reload_start | 03_gun_reload.wav | 1.58s | Gun reload sounds |
| 15_reload_finish | 01_bolt_home.wav | 0.47s | Gun reload sounds |
| 15_reload_finish | 02_metal_latch.ogg | 0.26s | RPG Audio |
| 15_reload_finish | 03_draw_knife_snap.ogg | 0.40s | RPG Audio |
| 15_reload_finish | 04_confirm.ogg | 0.29s | Interface Sounds |
| 16_weapon_swap | 01_cloth_belt.ogg | 0.72s | RPG Audio |
| 16_weapon_swap | 02_draw_knife.ogg | 0.45s | RPG Audio |
| 16_weapon_swap | 03_belt_handle.ogg | 0.48s | RPG Audio |
| 16_weapon_swap | 04_cloth.ogg | 0.66s | RPG Audio |
| 20_impact_world | 01_concrete_light.ogg | 0.87s | Impact Sounds |
| 20_impact_world | 02_metal_light.ogg | 0.24s | Impact Sounds |
| 20_impact_world | 03_plate_light.ogg | 0.54s | Impact Sounds |
| 20_impact_world | 04_generic_light.ogg | 0.14s | Impact Sounds |
| 21_impact_flesh | 01_punch_medium.ogg | 0.41s | Impact Sounds |
| 21_impact_flesh | 02_punch_heavy.ogg | 0.46s | Impact Sounds |
| 21_impact_flesh | 03_wet_hit.ogg | 0.27s | 100 CC0 SFX |
| 21_impact_flesh | 04_squelch.ogg | 0.50s | Sci-Fi Sounds |
| 22_crit | 01_bell_ping.ogg | 1.48s | Impact Sounds |
| 22_crit | 02_hit_jingle.ogg | 0.28s | Music Jingles |
| 22_crit | 03_glass_ping.ogg | 0.28s | Interface Sounds |
| 22_crit | 04_pluck.ogg | 0.10s | Interface Sounds |
| 23_explosion | 01_crunch.ogg | 0.78s | Sci-Fi Sounds |
| 23_explosion | 02_low_freq.ogg | 1.00s | Sci-Fi Sounds |
| 23_explosion | 03_oga_explosion.ogg | 0.56s | 100 CC0 SFX |
| 23_explosion | 04_chunky.mp3 | 5.62s | Chunky Explosion |
| 23_explosion | 05_cannon_boom.ogg | 1.24s | 25 CC0 bang / firework SFX |
| 24_shell_drop | 01_metal_tink_a.ogg | 0.29s | 100 CC0 SFX |
| 24_shell_drop | 02_metal_tink_b.ogg | 0.35s | 100 CC0 SFX |
| 24_shell_drop | 03_plate_light.ogg | 0.49s | Impact Sounds |
| 24_shell_drop | 04_coins.ogg | 0.34s | RPG Audio |
| 30_enemy_hurt | 01_hurt_a.ogg | 0.49s | 80 CC0 creature SFX |
| 30_enemy_hurt | 02_hurt_b.ogg | 0.35s | 80 CC0 creature SFX |
| 30_enemy_hurt | 03_grunt_short.ogg | 0.54s | 80 CC0 creature SFX |
| 30_enemy_hurt | 04_grunt_deep.ogg | 0.57s | 80 CC0 creature SFX 2 |
| 31_enemy_death | 01_die_a.ogg | 0.47s | 80 CC0 creature SFX 2 |
| 31_enemy_death | 02_die_b.ogg | 0.66s | 80 CC0 creature SFX 2 |
| 31_enemy_death | 03_die_c.ogg | 0.78s | 80 CC0 creature SFX 2 |
| 31_enemy_death | 04_roar_death.ogg | 0.90s | 80 CC0 creature SFX |
| 32_enemy_attack | 01_attack_a.ogg | 0.19s | 80 CC0 creature SFX 2 |
| 32_enemy_attack | 02_attack_b.ogg | 0.51s | 80 CC0 creature SFX 2 |
| 32_enemy_attack | 03_roar_short.ogg | 0.37s | 80 CC0 creature SFX |
| 32_enemy_attack | 04_roar_long.ogg | 1.13s | 80 CC0 creature SFX 2 |
| 33_enemy_spit | 01_spit_a.ogg | 0.49s | 80 CC0 creature SFX |
| 33_enemy_spit | 02_spit_b.ogg | 0.36s | 80 CC0 creature SFX |
| 33_enemy_spit | 03_slime_lob.ogg | 0.50s | Sci-Fi Sounds |
| 33_enemy_spit | 04_scifi_lob.ogg | 0.47s | Digital Audio |
| 40_player_jump | 01_cloth_hop.ogg | 0.41s | RPG Audio |
| 40_player_jump | 02_footstep_push.ogg | 0.11s | Impact Sounds |
| 40_player_jump | 03_scifi_hop.ogg | 0.39s | Digital Audio |
| 40_player_jump | 04_creature_effort.ogg | 0.61s | 80 CC0 creature SFX |
| 41_player_double_jump | 01_phase_jump.ogg | 0.47s | Digital Audio |
| 41_player_double_jump | 02_phaser_up.ogg | 0.50s | Digital Audio |
| 41_player_double_jump | 03_force_field.ogg | 0.95s | Sci-Fi Sounds |
| 41_player_double_jump | 04_thruster.ogg | 5.00s | Sci-Fi Sounds |
| 42_player_land | 01_concrete_heavy.ogg | 0.35s | Impact Sounds |
| 42_player_land | 02_footstep_land.ogg | 0.11s | Impact Sounds |
| 42_player_land | 03_mining_thud.ogg | 0.99s | Impact Sounds |
| 42_player_land | 04_punch_heavy.ogg | 0.65s | Impact Sounds |
| 43_player_dash | 01_thruster.ogg | 5.00s | Sci-Fi Sounds |
| 43_player_dash | 02_engine_small.ogg | 5.00s | Sci-Fi Sounds |
| 43_player_dash | 03_phase_jump.ogg | 0.47s | Digital Audio |
| 43_player_dash | 04_cloth_whoosh.ogg | 0.48s | RPG Audio |
| 44_player_slide | 01_scratch.ogg | 0.14s | Interface Sounds |
| 44_player_slide | 02_engine_low.ogg | 5.00s | Sci-Fi Sounds |
| 44_player_slide | 03_cloth_drag.ogg | 0.41s | RPG Audio |
| 44_player_slide | 04_force_field.ogg | 0.95s | Sci-Fi Sounds |
| 45_player_mantle | 01_cloth_haul.ogg | 0.66s | RPG Audio |
| 45_player_mantle | 02_leather_grab.ogg | 0.34s | RPG Audio |
| 45_player_mantle | 03_effort_grunt.ogg | 0.65s | 80 CC0 creature SFX |
| 45_player_mantle | 04_footstep_scuff.ogg | 0.11s | Impact Sounds |
| 46_footstep | 01_concrete_0.ogg | 0.11s | Impact Sounds |
| 46_footstep | 02_concrete_1.ogg | 0.11s | Impact Sounds |
| 46_footstep | 03_concrete_2.ogg | 0.11s | Impact Sounds |
| 46_footstep | 04_concrete_3.ogg | 0.11s | Impact Sounds |
| 46_footstep | 05_concrete_4.ogg | 0.11s | Impact Sounds |
| 47_player_hurt | 01_human_hurt.ogg | 0.48s | 80 CC0 creature SFX |
| 47_player_hurt | 02_punch_taken.ogg | 0.46s | Impact Sounds |
| 47_player_hurt | 03_low_thud.ogg | 0.78s | Digital Audio |
| 47_player_hurt | 04_error.ogg | 0.17s | Interface Sounds |
| 48_player_death | 01_low_down.ogg | 1.02s | Digital Audio |
| 48_player_death | 02_phaser_down.ogg | 0.50s | Digital Audio |
| 48_player_death | 03_jingle_lose.ogg | 0.80s | Music Jingles |
| 48_player_death | 04_creature_die.ogg | 0.66s | 80 CC0 creature SFX 2 |
| 50_jump_pad | 01_phaser_up.ogg | 0.52s | Digital Audio |
| 50_jump_pad | 02_power_up.ogg | 0.44s | Digital Audio |
| 50_jump_pad | 03_force_field.ogg | 0.96s | Sci-Fi Sounds |
| 50_jump_pad | 04_phase_jump.ogg | 0.42s | Digital Audio |
| 51_checkpoint | 01_jingle_nes.ogg | 1.76s | Music Jingles |
| 51_checkpoint | 02_confirm.ogg | 0.54s | Interface Sounds |
| 51_checkpoint | 03_power_up.ogg | 1.20s | Digital Audio |
| 51_checkpoint | 04_bong.ogg | 0.12s | Interface Sounds |
| 52_ammo_pickup | 01_coins.ogg | 0.85s | RPG Audio |
| 52_ammo_pickup | 02_metal_latch.ogg | 0.26s | RPG Audio |
| 52_ammo_pickup | 03_pep.ogg | 0.52s | Digital Audio |
| 52_ammo_pickup | 04_drop.ogg | 0.19s | Interface Sounds |
| 53_workbench | 01_open.ogg | 0.15s | Interface Sounds |
| 53_workbench | 02_maximize.ogg | 0.26s | Interface Sounds |
| 53_workbench | 03_book_open.ogg | 0.15s | RPG Audio |
| 53_workbench | 04_door_open.ogg | 0.53s | Sci-Fi Sounds |
| 60_ui_click | 01_click_a.ogg | 0.10s | Interface Sounds |
| 60_ui_click | 02_click_b.ogg | 0.01s | Interface Sounds |
| 60_ui_click | 03_select.ogg | 0.04s | Interface Sounds |
| 60_ui_click | 04_mouse_click.ogg | 0.09s | UI Audio |
| 61_ui_hover | 01_rollover.ogg | 0.23s | UI Audio |
| 61_ui_hover | 02_select_soft.ogg | 0.38s | Interface Sounds |
| 61_ui_hover | 03_scroll.ogg | 1.00s | Interface Sounds |
| 61_ui_hover | 04_tick.ogg | 0.01s | Interface Sounds |
| 62_level_up | 01_jingle_nes.ogg | 0.75s | Music Jingles |
| 62_level_up | 02_jingle_steel.ogg | 0.93s | Music Jingles |
| 62_level_up | 03_power_up.ogg | 0.52s | Digital Audio |
| 62_level_up | 04_phaser_up.ogg | 0.31s | Digital Audio |
| 63_perk_unlock | 01_jingle_pizzi.ogg | 0.49s | Music Jingles |
| 63_perk_unlock | 02_power_up.ogg | 0.65s | Digital Audio |
| 63_perk_unlock | 03_confirm.ogg | 0.49s | Interface Sounds |
| 63_perk_unlock | 04_three_tone.ogg | 1.20s | Digital Audio |
| 64_upgrade_install | 01_metal_latch.ogg | 0.26s | RPG Audio |
| 64_upgrade_install | 02_metal_click.ogg | 0.45s | RPG Audio |
| 64_upgrade_install | 03_confirm.ogg | 0.32s | Interface Sounds |
| 64_upgrade_install | 04_pot.ogg | 1.46s | RPG Audio |
| 65_low_ammo | 01_two_tone.ogg | 0.72s | Digital Audio |
| 65_low_ammo | 02_low_random.ogg | 0.55s | Digital Audio |
| 65_low_ammo | 03_error_soft.ogg | 0.10s | Interface Sounds |
| 65_low_ammo | 04_question.ogg | 0.49s | Interface Sounds |
