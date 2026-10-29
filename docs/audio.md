# Audio

One manager, two buses, two beds of music and one table of one-shots.

| Piece | Owns |
| --- | --- |
| `scripts/audio/audio_manager.gd` (autoload `Audio`) | the `Music` and `SFX` buses, the levels and mutes, the persisted mix, the two music beds with their crossfade, the 3D/2D one-shot voice pools, and which track the current scene wants |
| `scripts/audio/sfx_library.gd` | the event table: folder, take count, level in dB and pitch spread for every one-shot |
| `scripts/audio/sfx.gd` | the combat vocabulary: what is blunt, what needs both hands, and which event a swing, a landed blow, a guard and a projectile play |
| `scripts/ui/sound_settings_page.gd` | the sound page itself: a level and a mute for each bus, read from and written to `Audio` |
| `scripts/ui/settings_menu.gd` | the Escape window in the campaign, the title and the sandbox: an index and the SOUND page |
| `tools/slice_game_audio.py` | the one place that says which window of which recording became which file |

## Mix

`Master` → `Music` and `SFX`. A slider is a `linear_to_db` write on its bus, so
every stream under it follows, including a take that starts a moment later; a
mute is `AudioServer.set_bus_mute`. The mix is written to
`user://audio_settings.json` (`version`, `music_volume`, `sfx_volume`,
`music_muted`, `sfx_muted`) and read back on boot. A headless run
(`--headless --script`) swaps to `user://audio_settings_test.json` and never
touches a player's mix.

Levels in the table are per take; the bus carries the player's share on top, so
a take's dB is its place in the hierarchy and never the player's setting.

## Music

Two tracks, both looped on the stream (`AudioStreamOggVorbis.loop`) rather than
by the file:

| Track | File | Where |
| --- | --- | --- |
| `menu` | `assets/audio/music/menu_theme.ogg` (30 s) | `title.tscn` only |
| `warband` | `assets/audio/music/warband_soundtrack.ogg` (49 min) | every other scene - the camp, the trail, the town, the arena, the delve, the sandbox |

`Audio._process` watches `SceneTree.current_scene` and asks
`track_for_scene(path)`; a scene never starts a track itself, so a new scene
cannot be silently silent. A switch is a 1.2 s crossfade between the two beds,
and the bed that finishes drops its stream: the soundtrack is not held in memory
while the menu is up.

## One-shots

`Sfx.play(event, at)` → `Audio.play_event`. `at` is a `Vector3` for anything in
the world (a `AudioStreamPlayer3D` from a pool of twelve, `unit_size` 7 m,
80 m cull) and omitted for anything on the player's own body (a flat
`AudioStreamPlayer`). Takes are peak-normalised on disk and then levelled here;
a take never repeats back to back, and each carries a small pitch spread so
repeated blows do not read as a loop.

Footsteps are the exception to the one-pool rule: `SfxLibrary` gives the
`footstep` entry `"pool": "step"`, and the manager keeps six voices of its own
for it (`unit_size` 4 m, 34 m cull, 6 kHz cutoff). A fight produces two steps a
second per body, and a footfall must never be the sound that gets cut when a
blow needs the next voice. `Footsteps` is a sibling of `bloody_feet.gd`: same
`STEP_DROP` 0.05 m, so the print and the sound are one event seen and heard. It
plays only for a body that is grounded, moving faster than 0.45 m/s and inside
28 m of the camera, and the same boot cannot sound twice inside 180 ms. Two identical events from the same place
inside 20 ms are one contact reported twice and play once.

| Event | Takes | Fires when |
| --- | --- | --- |
| `swing_1h` | 13 | any one-handed weapon commits a swing (`Combat.begin_melee`, `DevilMob`/`Enemy` on the frame they enter `STRIKE`) |
| `swing_dagger` | 6 | the same, with a dagger in the swinging hand (main hand, or the off hand of a dual pair) |
| `swing_2h` | 1 | the same, for a greatsword, the heavy branch or a staff |
| `hit_blade` | 8 | a melee blow that was not blocked or parried landed (`Combat._resolve_melee_contact`, and each scene's mob-to-ranger handler) |
| `hit_blunt` | 3 | the same, with a club, a branch or a staff in the swinging hand |
| `hit_dagger` | 8 | the same, cut by a dagger: the slit takes held small |
| `block` | 4 | a blow landed on a held guard (`Combat._block_feedback`, the arena's replicated `_defense_event`) |
| `parry` | 4 | a blow was parried, and on a blade-vs-blade clash (`Combat._resolve_clash`) |
| `arrow` | 1 | an arrow launches (`Arrow.launch`, on every peer that owns one) |
| `footstep` | 12 | a walking body's boot comes back down (`Footsteps.update`, every fighter body and the frontier ranger) |
| `throw` | 3 | a blade is let go of (`ThrownWeapon.launch`) |

The weapon reading is `Sfx.kind_of(source, hand)`: the ranger rig's own
`swing_weapon_class(hand)` (so the off hand of a dual pair is read as what it
actually holds), its catalog index (`sword_index` 3 is the club, 4 the branch,
plus `staff_active`), or a mob's carried piece (`weapon_item`,
`held_weapon_id()`). It is an id/kind test, never a damage or reach guess: the
catalog files both clubs and swords under `kind: "sword"`.

**A dagger is not a small sword.** It is the fastest weapon in the game - a
0.5 s swing, and the shank passive takes it to 0.167 s - so a sword's 0.33 s
whoosh under every stab reads as a greatsword swung by a man with a knife.
`swing_dagger` is the same thirteen takes cut to their leading third (0.14 s),
5 dB quieter and pitched up; `hit_dagger` is the slit recording 5 dB under the
blade's cut and pitched up. The dagger keeps the same source recordings; only
the window and the mix change.

## Slicing

`python tools/slice_game_audio.py` rebuilds `assets/audio` from the raw library
(`~/Downloads` plus `~/game-audio-lab/outputs`; `--sources` for another root).
Every window is a fixed `(start, end)` in the source, every slice is mono 48 kHz
peak-normalised to -1 dBFS with a 4 ms fade, and the output names are the ones
`SfxLibrary` expects - so `--check` is the whole verification. The encode is
`-bitexact` (no random Ogg stream serial, no encoder tag), so the same window
always writes the same bytes and a re-run is a no-op in git.

| Source | Becomes |
| --- | --- |
| `427979__kinoton__short-whoosh-13x.wav` (13 takes) | `swing/short_whoosh_01..13` |
| the same recording, six takes cut to their attack | `swing/dagger_whoosh_01..06` |
| `855844__sadiquecat__whoosh-long-bamboo-stick-os-st-13.wav` | `swing/long_whoosh_01` |
| `460509__florianreichelt__hitting-in-a-face.mp3` (3 hits) | `impact/blunt_01..03` |
| `873151__artninja__sword_throat_slitting_sound_10032026.wav` (16 takes, 8 kept) | `impact/slit_01..08` |
| `568790__fenodyrie__sword-against-sword.wav` (72 hits) | `defense/parry_01..04` (the short bright ones), `defense/clash_01..04` (the long ringing ones) |
| `334167__loudernoises__flying-blade.wav` | `thrown/blade_01..03` |
| `205563__everheat__arrow.wav` | `bow/arrow_01` |
| `411206__straget__going-on-a-forest-road-gravel-and-grass.wav` (12 plants across 31 s) | `step/footstep_01..12` |

## Verification

`tests/audio_regression.gd` is headless and needs no device: the buses and
their sends, a slider moving the bus and the file, a mute muting only its own
bus, a reload reading the mix back, the track every scene asks for, both streams
looping, every take on disk loading as a stream, the weapon reading for a
shortsword / greatsword / club / branch / staff / a mob's carried piece, the
event each funnel call asks for, and both Escape surfaces opening, mixing and
closing.

    & .\runtime\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/audio_regression.gd

Sound that is not in this table is not in the game: the old synthesised
`scripts/range_audio.gd` still plays the frontier's release, equip, heal and
ability cues, but every steel, wood and arrow cue above replaced its
`parry`/`block`/`clang`/`hit` placeholders.
