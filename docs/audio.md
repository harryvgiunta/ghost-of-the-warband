# Audio

One manager, three buses, two beds of music and one table of one-shots.

| Piece | Owns |
| --- | --- |
| `scripts/audio/audio_manager.gd` (autoload `Audio`) | the `Music`, `SFX` and `Reverb` buses, the levels and mutes, the persisted mix, the two music beds with their crossfade and the soundtrack's managed loop seam, the 3D/2D one-shot voice pools, and which track the current scene wants |
| `scripts/audio/sfx_library.gd` | the event table: folder, take count, level in dB, pitch spread and, when an event wants a tail, the bus for every one-shot |
| `scripts/audio/sfx.gd` | the combat vocabulary: what is blunt, what needs both hands, which guard is wood and which is a knife, and which event a swing, a stab, a landed blow, a guard and a projectile play |
| `scripts/audio/voice_library.gd` | the voice table: which bodies speak, what each cue is for, how loud, how wide the pitch spread, the chance it fires, its cooldown and the share of the pool a damage cue needs |
| `scripts/audio/voice_emitter.gd` | one body's clock, rolls and cooldowns: the difference between "a wolf growls" and "a wolf growls sometimes" |
| `scripts/audio/voice.gd` | the one call a scene makes (`Voice.say`), and the kill credit (`Voice.kill_quip`) |
| `scripts/ui/sound_settings_page.gd` | the sound page itself: a level and a mute for each bus, read from and written to `Audio` |
| `scripts/ui/settings_menu.gd` | the Escape window in the campaign, the title and the sandbox: an index and the SOUND page |
| `tools/slice_game_audio.py` | the one place that says which window of which recording became which file |

## Mix

`Master` → `Music`, `SFX`, and `Reverb` → `SFX`. A slider is a `linear_to_db`
write on its bus, so every stream under it follows, including a take that starts
a moment later; a mute is `AudioServer.set_bus_mute`. `Reverb` is a one-effect
bus (`AudioEffectReverb`, mostly dry) and returns *into* `SFX` rather than into
`Master`, so an event that asks for its tail still answers to the effects
slider and the effects mute. Only a row that names `"bus": "Reverb"` plays
there - the door thud and the soul changing bodies - because a room on every
contact turns a fight into a hall.

The mix is written to
`user://audio_settings.json` (`version`, `music_volume`, `sfx_volume`,
`music_muted`, `sfx_muted`) and read back on boot. A headless run
(`--headless --script`) swaps to `user://audio_settings_test.json` and never
touches a player's mix.

Levels in the table are per take; the bus carries the player's share on top, so
a take's dB is its place in the hierarchy and never the player's setting.

## Music

Two tracks:

| Track | File | Where |
| --- | --- | --- |
| `menu` | `assets/audio/music/menu_theme.ogg` (30 s) | `title.tscn` only |
| `warband` | `assets/audio/music/warband_soundtrack.ogg` (49 min) | every other scene - the camp, the trail, the town, the arena, the delve, the sandbox. The campaign's town *area* is the exception: one scene holds the whole wood, and the square is silent (below) |

`Audio._process` watches `SceneTree.current_scene` and asks
`track_for_scene(path)`; a scene never starts a track itself, so a new scene
cannot be silently silent. A switch is a 1.2 s crossfade between the two beds.

Only the menu theme loops on its stream (`AudioStreamOggVorbis.loop`). The
soundtrack is 49 minutes of master whose Ogg loop point is a cut, so the seam is
managed instead: with the live bed inside `LOOP_FADE_SECONDS` (3 s) of
`get_length()`, the other bed starts the same stream at 0 s and crossfades in
over those three seconds while the outgoing bed is retired. The last seconds of
the score dissolve into its first; no hard boundary is ever heard at full level.

A campaign start cuts instead of crossfading. `Audio.start_campaign_music()`
stops the menu immediately and starts `warband` at position 0; the title's four
campaign doors call it, and the manager remembers which scene instance asked so
`_sync_scene_music` cannot answer that same title with the menu theme and drag
the score backwards before the next scene loads.

A retired bed is stopped, its stream reference released, and any track no live
bed still holds is dropped - the soundtrack is not kept in memory while the menu
is up. (A bed faded to silence is *still playing*, which is why `_retire` stops
it explicitly: the old early-out on `bed.playing` meant every retired bed - and
its stream - lived for the rest of the session.)

### The town has no score

`scenes/warband_world.tscn` is one scene holding the cages, the 915 m trail and
the town, so a scene rule cannot separate them. `WorldScene._sync_town_music`
holds the mix to what the *place* is: the first frame the soul stands in the
square `Audio.stop_music(TOWN_FADE_SECONDS)` fades the soundtrack out over 2.5 s,
and walking back out through the gate starts it again - the trail is still the
wood and still has a chase in it.

The poll is idempotent and runs every physics frame, because the manager answers
a scene change with its own track: asking what the manager wants and correcting
it is the only way this frame's answer cannot be undone by the next one. Between
the two answers sits `TOWN_QUIET_MARGIN` 6 m of hysteresis (`TownHub.in_square`
takes a widening `margin`), so a body standing on the square's line keeps the
track it already has instead of stuttering the whole soundtrack.

This is the campaign's town, not `town_hub.tscn` (a preview of the square on its
own): the standalone scene keeps the scene rule and the soundtrack, because it
has no wood to be chased through.

## One-shots

`Sfx.play(event, at)` → `Audio.play_event`. `at` is a `Vector3` for anything in
the world (a `AudioStreamPlayer3D` from a pool of twelve, `unit_size` 7 m,
80 m cull) and omitted for anything on the player's own body (a flat
`AudioStreamPlayer`). Takes are peak-normalised on disk and then levelled here;
a take never repeats back to back, and each carries a small pitch spread so
repeated blows do not read as a loop.

Footsteps are the exception to the one-pool rule, and the one place the mix
tells the player apart from everybody else. `SfxLibrary` gives both boot entries
`"pool": "step"`, and the manager keeps six voices of its own for them, so a
walk can never be the sound that gets cut when a blow needs the next one.

Spoken lines get the same treatment the other way round. A row with
`"pool": "voice"` plays on four places and four flat lines of its own
(`VOICES_VOICE`), because a growl or a shout is over a second long: on the shared
world pool one line would hold a voice for the whole fight and the blow landing
under it would be cut instead of the line. They are the widest shape in the mix -
`unit_size` 9 m, 70 m cull, 11 kHz - since a dying animal should carry across a
clearing.

| | `footstep` | `footstep_far` |
| --- | --- | --- |
| who | the body this machine is inside | every other body |
| level | -16 dB | -30 dB |
| takes | the 12 cuts, pitch 0.9-1.08 | the same 12, pitch 0.86-1.02 |
| shape | `unit_size` 5 m, 40 m, 7 kHz | `unit_size` 2 m, 11 m, 3 kHz, inverse-square |
| emitter gate | 28 m from the camera | 11 m from the camera |

The near/far split is deliberate: eight fighters walking together at full level
is a brigade in the player's ear, and a footfall is only information when it is
somebody close enough to matter. `ArenaActor.is_local` (already the flag behind
`DamageNumbers`' "self" vs "hit" number) decides which one a body makes, so the
arena, the delve, the campaign and the frontier all answer correctly without a
second notion of "the player".

`Footsteps` is a sibling of `bloody_feet.gd`: same `STEP_DROP` 0.05 m, so the
print and the sound are one event seen and heard. It plays only for a body that
is grounded, moving faster than 0.45 m/s and inside the gate above, and the same
boot cannot sound twice inside 180 ms. Two identical events from the same place
inside 20 ms are one contact reported twice and play once.

| Event | Takes | Fires when |
| --- | --- | --- |
| `swing_1h` | 13 | any one-handed weapon commits a swing (`Combat.begin_melee`, `DevilMob`/`Enemy` on the frame they enter `STRIKE`) |
| `swing_dagger` | 6 | the same, with a dagger in the swinging hand (main hand, or the off hand of a dual pair) and any variant but `stab`: a faint whisper under the impact |
| `stab_dagger` | 6 | the same, with a dagger and the `stab` variant: the quietest take in the table, because the push itself is not the event |
| `swing_2h` | 1 | the same, for a greatsword, the heavy branch or a staff |
| `hit_blade` | 8 | a melee blow that was not blocked or parried landed (`Combat._resolve_melee_contact`, and each scene's mob-to-ranger handler) |
| `hit_blunt` | 3 | the same, with a club, a branch or a staff in the swinging hand |
| `hit_dagger` | 8 | the same, cut by a dagger: the slit takes, pitched down and at the top of the impact hierarchy |
| `block` | 4 | a blow landed on a held guard with nothing else to say - a metal shield or an empty hand (`Combat._block_feedback`, the arena's replicated `_defense_event`) |
| `block_wood` | 3 | the same, against a wooden shield (`Archer.shield_variant == 3`) or a club/branch/staff in the defender's hand: the blunt take, low and quiet |
| `block_dagger` | 4 | the same, against a dagger: a bright tink with nothing behind it |
| `parry` | 4 | a blow was parried, and on a blade-vs-blade clash (`Combat._resolve_clash`) |
| `arrow` | 1 | an arrow launches (`Arrow.launch`, on every peer that owns one) |
| `footstep` | 12 | the body this machine is inside puts its boot down (`Footsteps.update`, every fighter body and the frontier ranger) |
| `footstep_far` | 12 | any *other* body's boot: the same takes, quiet and close-range |
| `cage_latch` | 4 | the soul cuts a cage latch (`CageEscape.interact`; never inside `open_latch`, which a resumed campaign calls four times) |
| `throw` | 3 | a blade is let go of (`ThrownWeapon.launch`) |
| `ui_click` | 4 | a menu or card plate is pressed (`Sfx.ui_click`): the latch transient, pitched bright and quiet |
| `menu_thud` | 3 | a campaign door opens - NEW CAMPAIGN, CONTINUE, GHOST OF THE WARBAND, RESUME WARBAND (`title._enter_campaign_score`): a blunt take pitched into the floor, on the `Reverb` bus |
| `body_swap` | 6 | the soul actually enters a different mercenary (`PossessionController._wire`, once per real change; a re-wire of the same body is silent), on the `Reverb` bus |
| `pickup` | 4 | a drop is taken (`WarbandLoot.quick_loot`, `WarbandLoot.sweep`), at the drop's position, once per piece |

The weapon reading is `Sfx.kind_of(source, hand)`: the ranger rig's own
`swing_weapon_class(hand)` (so the off hand of a dual pair is read as what it
actually holds), its catalog index (`sword_index` 3 is the club, 4 the branch,
plus `staff_active`), or a mob's carried piece (`weapon_item`,
`held_weapon_id()`). It is an id/kind test, never a damage or reach guess: the
catalog files both clubs and swords under `kind: "sword"`.

A guard is read the same way, by `Sfx.defense(at, parried, defender)`: the
defender may be the rig itself or a body that wears one (`ArenaActor`), and it
is unwrapped to the rig before anything is read. A wooden shield answers with
`block_wood`, a club/branch/staff answers with `block_wood`, a dagger with
`block_dagger`, and only steel, an empty hand or a replicated defence event
(the arena and the delve, where the peer has no defender to name) keeps the
`block` clash. `Combat._block_feedback` and the frontier's mob-to-ranger paths
pass the defender; the arena's and the delve's replicated events do not.

**A dagger is not a small sword.** It is the fastest weapon in the game - a
0.5 s swing, and the shank passive takes it to 0.167 s - so a sword's 0.33 s
whoosh under every stab reads as a greatsword swung by a man with a knife.
`swing_dagger` is six takes cut from those thirteen, at -22 dB, and
`stab_dagger` is the same flick at -26 dB: with a dagger, the *impact* is the
event. `hit_dagger` is the slit recording pitched
down (0.88-0.98) and raised to -1.5 dB - as loud as a club landing - so a stab
is heard where the knife goes in, not where it came from. The dagger keeps the
same source recordings; only the window and the mix change.

## Voices

Everything that makes a noise with its throat goes through one framework. The
four pieces are separate on purpose: **who** speaks (`VoiceLibrary`), **when** a
body is allowed to (`VoiceEmitter`), **the call** a scene makes (`Voice.say`),
and **the mixer** that plays the take (`Audio`, unchanged).

The healthy mix is a division of labour, not a vibe:

* the **trigger is logical** - a committed bite, a blow that took a share of the
  pool, a credited kill, a counter walked up to. Nothing speaks on a timer;
* the **cue is chosen by state** - the heaviest cue whose threshold the event
  clears (`big_hit` before `hurt`), so a heavy blow never gets a light grunt;
* **whether to speak is random** - `chance`, then a per-cue `cooldown`, then the
  emitter's floor between two different lines. This is what keeps a pack from
  sounding like one animal and a kill from always getting a quip;
* the **take is random too**, never the same one twice running
  (`Audio._variant_for`), and every take carries a pitch spread.

A voice is a folder of takes and a row per cue:

    assets/audio/voice/<voice>/<stem>_NN.ogg     # stereo-mixed, -1 dBFS, Vorbis
    VoiceLibrary.VOICES[voice][cue] = {stem, count, db, pitch, chance, cooldown, share, ...}

`VoiceLibrary.ensure()` probes the folder once per process and registers what is
actually there with `SfxLibrary` (`dir` + folder + stem + count), so spoken lines
are played by the *same* mixer as a sword landing, on their own voice pool. A cue
with no takes registers nothing: `Voice.say` is a silent no-op, a scene never
asks whether the recording has been delivered, and `VoiceLibrary.missing()` is
the audit of what a delivery still owes.

| Voice | Cue | Fires when | Chance / cooldown |
| --- | --- | --- | --- |
| `wolf` | `attack` | the wolf commits a bite (`Enemy` entering `WINDUP`; a replica reads the same state change off the wire) | 0.45 / 5 s |
| `wolf` | `death` | the wolf enters `DEAD`, on every machine that runs the body | 1.0 / - |
| `player` | `hurt` | a blow took >= 18% of max health and the body is still standing (`ArenaActor.take_damage`, and the guest's own body off the snapshot) | 0.55 / 3.5 s |
| `player` | `big_hit` | the same, at >= 35%: the line a player remembers | 0.70 / 8 s |
| `player` | `kill` | a hostile died with this body named as `last_hitter` (`Voice.kill_quip` from the mob's own death) | 0.35 / 7 s |
| `player` | `downed` | the body goes down, then again on the bleed clock every 2.6-5.4 s | 0.90 / - |
| `sergeant`, `veteran`, `bruiser`, `scout`, `hothead` | `aggro` | a party body picks its first hostile since it was last out of the fight (`SquadDrive.drive`, the `engaged` latch) | 0.01 / 6 s |
| `sergeant`, `veteran`, `bruiser`, `scout`, `hothead` | `hurt` | a blow took >= 18% of the pool and the body is still standing (`ArenaActor.take_damage`) | 0.01 / 8 s |
| `orla`, `brann`, `vey`, `quartermaster` | `greet` | the counter is used (`TownHub.interact_at`) | 1.0 / 6 s |
| `orla`, `brann`, `vey`, `quartermaster` | `done` | a purchase went through (`VendorMenu.purchased`, `QuartermasterMenu.purchased`) | 0.8 / 2 s |

**The party speaks with five profiles, one per mercenary.** A profile is not extra
content: it is the same two beats - finding something to hit, being hit - recorded
five ways, so a squad of five reads as five men instead of one. The assignment is
a pure function of the mercenary id (`VoiceLibrary.profile_for`: round robin over
`PROFILES`, so the first five bodies field all five voices before any of them
repeats), made in `PossessionController._spawn_body` beside
`WarbandLooks.profile_for(merc_id)` and *before* the body enters the tree, because
`ArenaActor._ready` builds the emitter from `voice_id`. Nothing else about the
body changes, every peer and every reload agrees, and no save field or wire field
carries it.

One in a hundred is deliberate on both cues: a roll per body per engagement and
per blow that took a real bite, so a fight is usually silent and a line lands as
a line. The number lives in `VoiceLibrary.SQUAD`, which is the one place to turn
it up.

Which body hears what: a line is made by the machine that runs the body. The
authority makes every mob's and every squadmate's; a replica makes the two cues
it can read off a snapshot (a bite being committed, a death); the peer's own body
makes its lines flat, in the player's ear, even when the host applied the blow.
Every peer renders its own copy - audio is never sent over the wire.

A party line is also **near-field by construction**: `SQUAD` asks for
`unit_size` 5 m and `max_distance` 26 m, where a wolf's growl asks for 9 m and 48
m and its death 56 m, because a growl has to carry across a clearing and a shout
does not. So an ally engaging 40 m up the lane is silence, not a voice in your
ear - the row's shape, not a distance test at the call site. The line itself is
placed at the body (`VoiceEmitter.say` hands `Audio` the body's chest position), and
the local body is the one exception: it plays flat, because it is the ear the line
comes from.

Two cues take the floor regardless of the gap between lines (`URGENT` in
`VoiceEmitter`): the death cry and the moan of a body going down. A wolf that
growled 0.1 s ago and has just died must still be heard dying. A blow that puts a
body down does *not* also grunt - the going-down line is the readable event, and
two lines on one frame would be one cut off.

**The wolf is the reference voice.** `assets/audio/voice/wolf/growl_01..03` is
one continuous growl cut into three windows that each start in a dip of the
envelope, and `death_01..06` is six separate vocalisations out of a single take,
pitched down 0.80-0.90 by the runtime so a dog reads as a wolf. Adding a voice
(say the five devils, which already ask for `voice_id() == mob_id`) is a folder
of takes, one row, and nothing else: `DevilMob`/`ForestMob` name their voice by
profile and `Enemy` by species, so no controller carries a list of creatures.

### What a delivery has to fill

The bodies and the keepers already ask for their lines; the takes are what is
missing. Dropping files at these paths is the whole of it - `VoiceLibrary.ensure()`
probes them, and `VoiceLibrary.missing()` (and the `audio_regression` check that
reads it) turns green as they arrive:

| Path | Takes | Line |
| --- | --- | --- |
| `voice/player/hurt_01..03.ogg` | 3 | the effort-and-pain grunt of a blow that took a real share (>= 18%) |
| `voice/player/big_hit_01..02.ogg` | 2 | the one a player remembers on a hit that could have ended it (>= 35%) - "oh fuck" |
| `voice/player/kill_01..03.ogg` | 3 | said over a kill, not every kill |
| `voice/player/downed_01..03.ogg` | 3 | the first gasp and the ragged moans of a body bleeding on the ground |
| `voice/orla/greet_01..03.ogg`, `voice/brann/...`, `voice/vey/...`, `voice/quartermaster/...` | 3 | the keeper as their counter is used |
| `voice/orla/done_01..02.ogg`, same four folders | 2 | the keeper after a trade |

**The party's five profiles shipped**, so they are not on that list any more:
`voice/{sergeant,veteran,bruiser,scout,hothead}/aggro_01..03.ogg` (the three
sightings - "oh shit here they come", "who... oh", "get ready") and
`hurt_01..02.ogg` (the scream, the curse), 25 takes. They are one performance
converted once per profile with `tools/vc.py` (f0-conditioned, the profile's
`vc_shift` applied before conversion: sergeant 0, veteran -2, bruiser -4, hothead
+5, scout +8), normalised to -16 LUFS - the source batch and its cue sheet live in
`voice_batch/` outside the tree.

Same rules as every other take: mono 48 kHz, peak -1 dBFS, a few ms of fade at
each end, one file per take. `--fetch` does not know about these (they are
authored, not sourced), so cut them with `python tools/slice_game_audio.py
--only voices --sources DIR` after adding their windows to `VOICE_SLICED`, or
drop the finished files in and let git take them.

## Slicing

`python tools/slice_game_audio.py` rebuilds `assets/audio` from the raw library
(`~/Downloads` plus `~/game-audio-lab/outputs`; `--sources` for another root).
Every window is a fixed `(start, end)` in the source, every slice is mono 48 kHz
peak-normalised to -1 dBFS with a 4 ms fade, and the output names are the ones
`SfxLibrary` and `VoiceLibrary` expect - so `--check` is the whole verification.
The encode is `-bitexact` (no random Ogg stream serial, no encoder tag), so the
same window always writes the same bytes and a re-run is a no-op in git.

`--only voices` (and `--only sfx`, `--only music`) builds one part of the tree,
which is what a machine without the whole raw library needs. `--fetch` downloads
the licensed voice recordings from their pinned URLs first
(`python tools/slice_game_audio.py --fetch --only voices --sources DIR`).

| Source | Becomes |
| --- | --- |
| `427979__kinoton__short-whoosh-13x.wav` (13 takes) | `sfx/swing/short_whoosh_01..13` |
| the same recording, six takes cut to their attack | `sfx/swing/dagger_whoosh_01..06` |
| `855844__sadiquecat__whoosh-long-bamboo-stick-os-st-13.wav` | `sfx/swing/long_whoosh_01` |
| `460509__florianreichelt__hitting-in-a-face.mp3` (3 hits) | `sfx/impact/blunt_01..03` |
| `873151__artninja__sword_throat_slitting_sound_10032026.wav` (16 takes, 8 kept) | `sfx/impact/slit_01..08` |
| `568790__fenodyrie__sword-against-sword.wav` (72 hits) | `sfx/defense/parry_01..04` (the short bright ones), `sfx/defense/clash_01..04` (the long ringing ones) |
| `334167__loudernoises__flying-blade.wav` | `sfx/thrown/blade_01..03` |
| `205563__everheat__arrow.wav` | `sfx/bow/arrow_01` |
| `411206__straget__going-on-a-forest-road-gravel-and-grass.wav` (12 plants across 31 s) | `sfx/step/footstep_01..12` |
| `330635__leonelmail__padlock-chain-lock-unlock.mp3` (the four events at 43-45 s) | `sfx/cage/cage_latch_01..04` |
| `338674__newagesoup__wolf-growl.mp3` - "wolf-growl" by newagesoup, CC BY 4.0 | `voice/wolf/growl_01..03` |
| `277195__coral-island-studios__dog-begging.mp3` - "Dog Begging" by Coral_Island_Studios, CC BY 4.0 | `voice/wolf/death_01..06` |

The two voice recordings are the creators' 48 kHz preview masters, fetched from
their CDN URLs by `--fetch`; a real download from the sound page needs an account.
Attribution, the exact windows and every change are in `assets/audio/LICENSE.txt`.

## Verification

`tests/audio_regression.gd` is headless and needs no device: the buses and
their sends (the reverb bus returning into `SFX` with its one effect), a slider
moving the bus and the file, a mute muting only its own bus, a reload reading
the mix back, the track every scene asks for, the menu stream looping while the
soundtrack does not, the seam window, a campaign restart naming `warband` at
zero, every take on disk loading as a stream, the weapon reading for a
shortsword / greatsword / club / branch / staff / a mob's carried piece, the
guard reading for a wooden shield / club / dagger / steel, the event each funnel
call asks for, and both Escape surfaces opening, mixing and closing.

It also owns the voices: the wolf's takes and their event names, the mixer's own
line pool, the rule invariants (a growl is not certain, a death is; the heavy
blow needs a bigger share of the pool than a grunt and cools down longer; a kill
is not narrated every time), a body's rolls and cooldown on its own clock, a voice
whose takes have not been delivered staying silent, the audit naming those, and
the kill credit resolving a real body by instance id.

`tests/wolf_regression.gd` closes the loop on the reference voice: a wolf that
closes and commits a bite growls (on a planted seed, so the coin always lands),
and the lethal blow asks the mixer for the death cry.

    & .\runtime\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/audio_regression.gd

Sound that is not in this table is not in the game: the old synthesised
`scripts/range_audio.gd` still plays the frontier's release, equip, heal and
ability cues, but every steel, wood and arrow cue above replaced its
`parry`/`block`/`clang`/`hit` placeholders.
