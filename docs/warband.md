# Ghost of the Warband

A possession-based warband overhaul of Ironwood. There is no main character: the
player is a floating consciousness that enters any living mercenary in their
warband. Every mercenary has identical base stats (`100` health, `1000` stamina);
only the gear they hold differs. This document is the contract every phase and
every parallel worktree builds against.

## 1. The numbers

| Rule | Constant | Value | Where it lives |
| --- | --- | --- | --- |
| Deployment cap $X$ | `MAX_DEPLOYMENT_CAP` | 8 bodies | `scripts/warband/warband_contracts.gd` |
| Downed instead of dead | `OVERKILL_THRESHOLD` | 10% of max health | same |
| Finishing a downed body | `finishes_downed()` | blow > 10% of max health | same |
| Revive channel | `REVIVE_CHANNEL_SECONDS` | 5.0 s: a soul holding `G`, or a squadmate's own hands once the field is clear | same |
| Revive health | `REVIVE_HEALTH_FRACTION` | 50% of max | same |
| Bleed-out while downed | `DOWNED_BLEED_SECONDS` | 30 s | same |
| Crawl pace | `DOWNED_CRAWL_SPEED` | 0.9 m/s backwards | same |
| Active damage | `ACTIVE_DAMAGE_MULTIPLIER` | 1.0 | same |
| Passive damage | `PASSIVE_DAMAGE_MULTIPLIER` | 0.10 | same |
| Presence bubble | `DEFAULT_BUBBLE_RADIUS` / `BUBBLE_EXIT_RADIUS` | 30 m / 34 m | same |
| Distil ratio | `CRUOR_DISTILL_RATIO` | 5:1 (625 T1 -> 1 T5) | same |
| Bleed-out drip | `DownedRules.DRIP_SLOW_SECONDS` / `DRIP_FAST_SECONDS` / `DRIP_VOLUME_MIN` / `DRIP_VOLUME_MAX` | 1.2 s to 0.6 s, volume 2.0 to 8.0 as `bleed_fraction` runs 0..1 | `scripts/warband/downed_state.gd`, presented by `scripts/warband/bleed_drip.gd` |

## 2. What Phase 0 already ships

Everything below is a working, tested library. Worktrees **extend** it; they do
not re-implement it and do not redefine an enum, a slot id or a tier name.

| File | Class | Responsibility |
| --- | --- | --- |
| `scripts/warband/warband_contracts.gd` | `WarbandContracts` | Slot/weapon/health/sim enums, slot ids (`feet`, `main`, `off`), `resolve_damage`, `finishes_downed`, `damage_multiplier`, all tuning constants |
| `scripts/warband/warband_roster.gd` | `WarbandRoster` | Mercenary records (identical base stats), health/downed/dead, `apply_damage`, `revive`, `tick_downed`, `equip`/`unequip`, deployment cap, save round-trip |
| `scripts/warband/soul_router.gd` | `SoulRouter` | Body registry, one peer per body, `request_transfer`, `cycle`, refusal reasons, alive-only entry |
| `scripts/warband/town_stash_model.gd` | `WarbandStash` | Infinite pooled stash, collective `rows()` sorted by value with `Equipped` tags |
| `scripts/warband/cruor_catalog.gd` | `CruorCatalog` | The five tiers, names/colours/values, `distill`, `unbind_yield` |
| `scripts/warband/cruor_manager.gd` | `WarbandCruor` | Essence wallet, `unbind`, `distill`, `distill_all`, `brand`, brand map, persistence |
| `scripts/warband/branded_skills.gd` | `BrandedSkills` | The six branded abilities, which item class carries each, tier power curve |
| `scripts/warband/mercenary_vendor.gd` | `WarbandVendor` | Hire price (120 + 35/body), `hire()`, recruiter board |
| `scripts/warband/damage_scaler.gd` | `WarbandDamage` | The single bubble multiplier, keyed by instance id |
| `scripts/warband/warband_state.gd` | autoload `Warband` | Owns roster + souls + stash + cruor, gold bridge to `PlayerState.credits`, save/load, possession mirror |
| `tests/warband_contract_regression.gd` | - | 140 checks over all of the above |

Damage funnels already call `WarbandDamage.scale(amount, self)` as their first
statement: `main.gd::take_damage`, `arena_actor.gd::take_damage`,
`devil_mob.gd::take_damage` (also covers `forest_mob.gd`), `enemy.gd::take_damage`
and `ranger_clone.gd::take_damage`. **Never add a second multiplier.**

## 3. How the modes are built

There is no possession inside `main.gd`'s frontier: that body is a raw
`CharacterBody3D` owned by the frontier controller. Possession lives on the
**arena actor layer**, which already has authoritative movement, prediction,
snapshots, abilities, parry/block and item sockets:

* every mercenary is an `ArenaActor` (`scripts/arena_actor.gd`) whose loadout is
  applied from its roster record through `SeatLoadout.apply()`;
* the local player drives exactly one actor at a time - the body their soul is in;
* `SoulRouter` is the authority for who is inside what, and `Warband.souls`
  mirrors it for saves and scene hand-offs.

New scenes therefore use the arena's patterns (`arena.gd` is the reference for
host/guest input, snapshots and seat binding), not the frontier's.

### Scene hand-offs

`Warband` survives scene changes (it is an autoload); `SoulRouter` does not,
because bodies do not. Every scene that contains bodies:

1. instantiates `Warband.souls` bodies from `Warband.roster` (deployed ids first),
2. registers each one with `Warband.souls.register_body(merc_id, actor, name)`,
3. after spawning, re-enters the body named by `Warband.possessed_by(peer_id)`
   when it exists and is alive, otherwise the first living body,
4. releases every peer on exit (`Warband.clear_possession()` on a full hand-off,
   or `release_peer` per peer).

### Input map for the new modes

| Key | Action |
| --- | --- |
| `[` / `]` | Previous / next living, unoccupied body |
| `F1`..`F8` | Enter the n-th living body directly |
| `O` | The warband screen (roster, state chips, click to control, hiring). `TAB` is the quick swap below, exactly as in the open frontier |
| `Tab` | Quick weapon swap: the standing body puts away the set in its hands and takes up the other one. Both pairs live on the mercenary's roster record |
| `1`..`3`, `6`/`7`, mouse, `Space`, `C`, `F`, `G`, `E` | warband controller: plain 1/2/3 fire the three item-skill slots (Shift+1..3 is the same press), 6/7 bandage/potion; mouse, `Space`, `C`, `F` and `E` keep the frontier meanings, `T` throws the held blade, and `G` stays the world's interact key |
| `G` held | Revive the downed body under the crosshair (5 s channel, humans and the squad's own hands) |
| `K` | Quick-loot the drop under the crosshair (battlefield looting) |

## 4. Phase 1 worktree ownership

Six isolated branches off `main`. Each one may create its own files and edit only
the files listed under its name. Anything else is a merge conflict waiting.

| Worktree | Owns (create) | May edit (existing) | Deliverable |
| --- | --- | --- | --- |
| `wt-1-soul-consciousness` | `scripts/warband/possession_controller.gd`, `scripts/warband/possession_camera.gd`, `scripts/warband/possession_sync.gd`, `scripts/warband/warband_body.gd`, `scenes/warband/*.tscn` it needs | `scripts/warband/soul_router.gd` (only if the contract truly needs a field) | Soul controller around `ArenaActor`, camera swoop, hotkey cycling, host/guest transfer lock over ENet, 2-peer test |
| `wt-2-bubble-combat-ai` | `scripts/warband/combat_bubble.gd` (`WarbandBubbleManager`), `scripts/warband/passive_duel_brain.gd` | none | Distance tracker from every human body, ACTIVE/PASSIVE toggling through `WarbandDamage`, 80% guard / circling / occasional-swing choreography |
| `wt-3-downed-revive` | `scripts/warband/downed_state.gd`, `scripts/warband/crawl_to_safety.gd`, `scripts/warband/revive_channel.gd` | `scripts/arena_actor.gd` (health → DOWNED, revive path), `scripts/main.gd` (same for the frontier body) | 10% overkill routing, AI crawl to safe anchors, human-only 5 s channel |
| `wt-4-stash-autoloot` | `scripts/warband/loot_vacuum.gd`, `scripts/warband/loot_pickup_warband.gd` if needed | `scripts/player_state.gd` (catalog additions only) | Manual quick-loot, end-of-battle sweep to the infinite stash, every gear type covered |
| `wt-5-cruor-altar` | `scripts/warband/sacrificial_altar.gd`, `scripts/warband/altar_menu.gd` (`AltarMenu`) | none | Altar scene/overlay: unbind, distil, brand/reroll with the real wallet |
| `wt-6-warband-ui` | `scripts/warband/warband_screen.gd` (`WarbandScreen`), `scripts/warband/warband_paperdoll.gd` (`WarbandPaperdoll`) | none | Tactical warband screen (HP/downed/gear, click-to-control) and the mercenary paperdoll over the value-sorted stash |

**Untouchable shared files:** `scripts/warband/warband_contracts.gd`,
`warband_roster.gd`, `warband_state.gd`, `town_stash_model.gd`,
`cruor_catalog.gd`, `cruor_manager.gd`, `branded_skills.gd`,
`mercenary_vendor.gd`, `damage_scaler.gd`, `tests/warband_contract_regression.gd`.
If a contract genuinely must change, edit it minimally and say so in the commit
message; the merge owner resolves it.

Every worktree must also:

* run `godot --headless --path . --script res://tests/<its own>_regression.gd`;
* not run the whole suite (the merge owner does that once);
* not add a second enum, slot list, tier table, damage multiplier or gold wallet;
* update this document's own section only if it changes a contract.

## 5. Phase gate 1 - Admin Arena

`admin_arena.tscn` + `scripts/admin_arena.gd` (built at the gate, not by a
worktree) is the verification surface: a flat walled yard with two fighting
pairs 40 m apart, eight roster bodies, the altar and a stash chest.

Gate checks:

1. Spawn 8 bodies, two peers; `[`/`]`/`F1..F8` and a warband-screen click swap
   bodies cleanly, and a second peer cannot enter the occupied body.
2. The far pair takes 10% damage and keeps a convincing block/circle pattern;
   walking a human body to them flips them to full damage.
3. In the campaign every lethal hit downs and crawls - a mercenary is never
   killed by the blow - and the body bleeds for 30 s; holding `G` for 5 s revives
   it, a squadmate does the same once the field is quiet, and any blow that lands
   on the downed body finishes it and leaves a corpse. (The arena's own seats keep
   the 10% overkill contract; only the warband's bodies hold that line.)
4. End-of-battle sweep lands loot in the stash sorted by value; unbind, distil
   5:1 and brand all work from the same wallet the HUD shows.

## 6. Phase 2 worktrees

| Worktree | Owns | Deliverable |
| --- | --- | --- |
| `wt-7-cage-tutorial-escape` | `scenes/cage_escape.tscn`, `scripts/warband/cage_escape.gd`, `scripts/warband/tutorial_sequencer.gd` | Four caged prisoners, shift through all four, the fifth prisoner in rags cuts them out, forced possession of the rescuer, free the squad, loot cultist steel, reach the gate |
| `wt-8-branded-abilities` | `scripts/warband/branded_runner.gd`, `scripts/warband/branded_fx.gd` | The six abilities actually firing: barrage, shockwave, cone, ward, storm, rend; tier scaling |
| `wt-9-town-sanctuary-hub` | `scenes/town_hub.tscn`, `scripts/warband/town_hub.gd`, `scripts/warband/expedition_gate.gd` | Walkable hub wiring stash, altar, recruiter and the expedition gate into the loop |
| `wt-10-cultist-enemy-waves` | `scripts/warband/cultist_guard.gd`, `scripts/warband/enemy_waves.gd`, `scripts/warband/soldier_loot_run.gd` | Cultist guards for the cages, expedition waves, visible soldier jog-to-loot at battle end |

## 7. Verification

```powershell
& .\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/warband_contract_regression.gd
```

Tests are SceneTree scripts: accumulate `checks`/`failures`, `quit(0|1)`.
Visual proof still requires launching the scene: a regression test is not a
rendered frame. Avoid editing `tests/warband_contract_regression.gd` to make a
failure pass; fix the contract instead.

## 8. Shipped in Phase 1 (merged and green)

| Module | Public surface |
| --- | --- |
| `scripts/warband/possession_controller.gd` (`PossessionController`) | `setup(warband, camera, bodies_root)`, `spawn_mercenaries(points, authoritative)`, `activate/cycle/direct(peer, merc_id)`, `active_body(peer := 0)`, `body_of/merc_of/merc_for_peer`, `set_bot`, `living_merc_ids()`, `physics_step(delta)` (with `auto_simulate = false`), `release_local()`, signals `possession_changed`, `possession_released`, `transfer_refused` |
| `scripts/warband/possession_camera.gd` (`PossessionCamera`) | adopts the mode's `Camera3D`, `follow(body, snap)`, `swoop_to(body, seconds)`, `rotate_view(delta_yaw, delta_pitch)`, `aim_ray()`, `follow_point()`. **Free look**: yaw wraps and pitch runs `LOOK_UP` -1.4835 .. `LOOK_DOWN` +1.4835 rad (85 degrees either side; the old range was -0.12..+0.95, seven degrees of sky). The view is a basis composed from yaw and pitch (`Basis(UP, yaw) * Basis(RIGHT, -pitch)`), not `look_at` with a world-up hint, because that hint is parallel to the view at a pole. Where the arc resolves the eye inside the body's own column (past ~70 degrees up, where the ground clamp holds the eye at `MIN_HEIGHT`), it slides out to `BODY_STANDOFF` 0.62 m along its own azimuth, probed against the world at the eye's height, so looking up is "past your shoulder" and never "through your own legs" |
| `scripts/warband/possession_sync.gd` (`PossessionSync`) | host-authoritative transfer RPCs plus `server_apply(peer, merc_id)` |
| `scripts/warband/combat_bubble.gd` (`WarbandBubbleManager`) | `setup(radius, exit_radius)`, `set_humans`, `track/untrack`, `sim_state_of`, `clear`, `sim_changed` |
| `scripts/warband/passive_duel_brain.gd` (`PassiveDuelBrain`) | `attach(body, opponent)`, `set_active`, `step(delta)` for fighter bodies (before `physics_step`) |
| `scripts/warband/downed_state.gd` / `crawl_to_safety.gd` / `revive_channel.gd` / `bleed_drip.gd` | `DownedRules.*` (including `bleed_fraction`, `drip_interval`, `drip_volume`), `CrawlToSafety.attach/set_anchor/set_friends`, `ReviveChannel.set_bodies/begin/tick/cancel/progress`, `BleedDrip.attach/detach/attached`. `ArenaActor.enter_downed` puts the rig in its prone drag pose (`Archer.set_downed`) and attaches one drip; revive and respawn clear all of it, `apply_snapshot` drives the same three things so a replica lies down and bleeds off the unchanged wire, and `_die` either clears it (arena seats) or holds the corpse - rig visible, lie kept, drip off - for the warband bodies flagged `warband_death`. Those bodies also never die from the blow itself and are finished by any blow that lands while they are down. `bleed_loss` is written from the 30 s clock every downed frame and is the only input the drip reads. |
| `scripts/warband/loot_vacuum.gd` / `warband_pickup.gd` / `corpse_loot_panel.gd` | `WarbandLoot.setup/spawn/quick_loot/sweep/pickups` plus the corpse registry: `register_corpse(enemy) -> int` (one read of `gear_items()`, stable ids, the record dies with the body), `has_corpse/corpse_ids/corpse_items/corpse_value/corpse_at/corpse_position/corpse_label`, `take_from_corpse`, `take_all_from_corpse`, `claim_corpse(id, peer = 0)` (silent, the AI's entry point). Every one of them books through the same `_book_piece()`, so a piece cannot be duplicated and peer 0 never dresses a body. `CorpseLootPanel extends WarbandPaperdoll` adds `open_corpse(loot, id) -> bool`, `showing_corpse()`, `take_piece`, `take_all` and `set_title`; `G` at a corpse opens it and `P` still opens the mercenary paperdoll. `SoldierLootRun.run(pickups)` now also jogs survivors to corpses and claims each once. |
| `scripts/warband/sacrificial_altar.gd` / `altar_menu.gd` | `SacrificialAltar.interact/in_reach/menu`, `AltarMenu.configure/unbind_rows/distill_rows/brand_rows` |
| `scripts/warband/warband_screen.gd` / `warband_paperdoll.gd` | roster screen with `possess_requested(merc_id)`; mercenary paperdoll over the collective stash |
| `scripts/warband/warband_hud.gd` (`WarbandHud`) | body panel, squad rows, prompts, status banners |
| `scripts/admin_arena.gd` + `admin_arena.tscn` | the gate scene: two three-body brawls 42 m apart, eight roster bodies, two souls, the altar, the stash chest, battlefield loot |

### Gate 1 result

`tests/admin_arena_regression.gd` - 90 checks, 0 failures: 10% far / 100% near,
real guards and swings in the passive brawl, a just-lethal hit Downing and
crawling, a heavy hit killing, a five-second human revive at half health with AI
refused, the value-sorted sweep, the altar wallet, the warband-screen click and
the two-peer body lock. `tests/warband_session_regression.gd` covers the real
ENet session (Phase 2).

The full Phase 1 library suite (`warband_contract`, `possession`, `downed_revive`,
`combat_bubble`, `altar`, `stash_autoloot`, `warband_ui`, `admin_arena`) is green,
as are the pre-existing regressions the shared edits could break (`gameplay`,
`combat_expansion`, `net_limits`, `mob_aggro`, `world_art`, `ranger_clone`,
`hitbox`, `paperdoll`, `town_services`, `block_clash`, `draw_combat`).

### One engine trap worth remembering

Assigning `Environment.fog_mode` in Godot 4.7 resets `fog_density` to `1.0`.
`scripts/world/environment_kit.gd` now writes the density after the mode; before
that fix every exponential-fog style (the arena) rendered as a white-out.

## 9. Shipped in Phase 2 (merged and green)

| Module | Surface |
| --- | --- |
| `scenes/cage_escape.tscn` + `scripts/warband/cage_escape.gd` | night camp **deep in the wood**: a ragged 40 x 52 m pocket (`YARD_HALF_WIDTH` 20, front -30, back 22) with no wall and no gate - a broken stake ring, three twig shelters, a fire ring and junk, trees standing inside the pocket, and 170 m of ordinary forest (`CAMP_TO_ROAD_METRES`) before the trail's first torch. Four cages clamped one body each; the rescuer's scripted jog and **the body you have to enter yourself** (F5 / `[ ]`); **one latch per cage, cut by hand with G within `LATCH_REACH` 2.2 m and only with a blade in hand** (`interact`/`latch_target`/`open_latch` - nothing opens on a possession or a kill); two camp watchers (asleep until the player is armed with his own shiv, which lies on the dirt at the cold altar as the lesson's first weapon); three makeshift-tier drops on the ground; the leaving is a walk out of the trees |
| squad AI (`scripts/warband/squad_drive.gd`) | the one module both areas share: a freed prisoner arms itself from the nearest drop (booked by `WarbandLoot`, worn via `auto_equip`, re-dressed with `refresh_gear`), then runs at the nearest watcher and fights on layer 2 through one explicit ladder - close / swing / guard / circle / reset - resolved on every frame, with the exchange rolled once when the blade frees (55-70% guard for 0.35-0.80 s, guard dropping into the blow), 1-3 swings then a 0.25-0.55 s short rugged circle re-rolled per step, and only `sword`/`dagger` allowed to guard. Escort clause when nothing is hostile; the field is stripped once `_clear_of_hostiles` at the drop or corpse (22 m), drops through `quick_loot` and bodies through `register_corpse`/`corpse_at`/`claim_corpse`. The player's own body is never driven. |
| `scripts/warband/cage_watcher.gd` (`CageWatcher`) | the wood's **antlered hollow warden** (`extends ForestMob` → `DevilMob`, `WARDEN_ID` "hollow_warden"), so the camp is guarded by the silhouette the mode is about - and it swings, blocks, staggers and crouches on baked clips. `PAIR_HEALTH` 44 / `HARDENED_HEALTH` 144, `WATCHER_LAYER` 2, pack `camp_watchers`, sight 60. A deterministic 12-entry `VARIANTS` table (seeded by `mob_id` + the node's ordinal) varies a paint multiplied into the body's own PBR surfaces, a uniform silhouette scale 0.88-1.30, a main hand from `MAKESHIFT_TIER`, a favourite swing, a guard share and a crouch. `arm(item_id)` builds the real catalog model (`sword.gd`/`dagger.gd`/`bow.gd`) onto the `hand_r` bone through a `Grip` child of the `BoneAttachment3D` (the attachment rewrites its own transform from the bone every frame, so a grip set on it is discarded) driven by the per-mob `grip_offset`/`grip_rotation`/`grip_scale` entry in `scripts/forest_mob_visual.gd`, with a per-kind `grips.bow` override so a bow stands upright and `take_weapon_item()` strips it; `gear_items()` lists the blade plus the worn salvage. Per windup it picks `Warden_Attack` / `Warden_Attack_Slash` / `Warden_Attack_Stab`; one guard roll per exchange (`guard_chance()` = variant share × `guard_scale`, capped 0.9) plays `Warden_Block` and holds instead of trading, then drops into the swing; any blow at or above `max(STAGGER_FLOOR 6, STAGGER_SHARE 10 % of health)` plays `Warden_Stagger` and cancels swing, guard and step; `Warden_Crouch` is the stance while waiting on the cooldown or hurt. The three scene dials (`blow_scale`, `guard_scale`, `swing_gap_scale`) weight the blow, the guard share and the cooldown; the strike emits `attacked(self, profile damage × blow_scale, victim)` and a death emits `defeated` exactly once |
| `scripts/warband/tutorial_card.gd` (`TutorialCard`) | the modal step card: large title/body/keys, **pauses the tree** while open, one CONTINUE button (or G / Enter / Escape), restores the previous pause and mouse state on close |
| `scripts/warband/duel_lesson.gd` (`DuelLesson`) | the first fight's lesson, four facts and four cards: `MOVE` (the soul enters Corvin) -> `FETCH` (the body stands on the shiv) -> `FIGHT` with the **cuts** card raised on the same frame the shiv enters the hand (the pair may wake from there, and only there) and the **guard** card on the second watcher's first windup, then `DONE` on a guarded blow or on the pair falling. No scene lookups: the camp feeds facts and shows the cards `card_wanted` asks for; every transition is guarded and every fact counts once. `duel_lesson_regression` owns the order |
| `scripts/warband/tutorial_sequencer.gd` (`TutorialSequencer`) | `CAGED -> ALL_SEEN -> RESCUER_ARRIVED -> FREED -> ESCAPING` (there is no TOWN state: the lesson ends where the road does); eight watchers in total (the pair the player puts down, then six out of the trees), no loot requirement in the objective; `note_rescuer_taken()` changes the objective to the latch count; **four separate latches, one per `G` press** (`note_cage_opened`, which no longer requires a prior beat and frees the squad only at four); out-of-order calls refused; objective **and** a per-beat key hint (`hint()`) |
| `scripts/warband/branded_runner.gd` (`BrandedRunner`) + `branded_fx.gd` | the six sigils: Arrow Barrage, Shockwave Cleave, Rending Strike, Ember Storm, Hellfire Cone, Blood Ritual Ward; tier scaling, stamina, cooldown, refusal reasons |
| `scenes/town_hub.tscn` + `scripts/warband/town_hub.gd` | dusk square, campfire, stash chest, altar, recruiter desk, gate; `interact_at(peer, point)` resolves the nearest service; one `scene_requested` door |
| `scripts/warband/expedition_gate.gd` (`ExpeditionGate`) | `prompt`, `deploy_and_launch(ids)`, `return_to_town()` |
| `scripts/warband/cultist_guard.gd` (`CultistGuard`) | crimson cultist body, faction filter so guards never fight each other, no arena respawn |
| `scripts/warband/enemy_waves.gd` (`EnemyWaves`) | deterministic waves (3, +1 per wave, capped at 6) with escalating kits, `wave_started/wave_cleared`, `guards()`, `field()`, `living()` |
| `scripts/warband/soldier_loot_run.gd` (`SoldierLootRun`) | survivors physically jog to the drops **and to the bodies**, then the vacuum books each piece into the shared stash exactly once |
| `scripts/warband/warband_session.gd` (`WarbandSession`) | real ENet host/join, body ownership broadcast, 20 Hz body snapshots, guest prediction, AI fallback on leave |
| `scripts/warband/quartermaster_menu.gd` (`QuartermasterMenu`) + `Warband.buy_gear` | ten base pieces bought with gold into the collective stash; the same keeper price the stash sort uses |
| `scripts/warband/game_flow.gd` (autoload `GameFlow`) | the only thing that changes scene; `enter_warband()`, `start_campaign()`, `enter_town()`, `launch_expedition()`, `bind(scene)` |
| `admin_arena.tscn` | doubles as the Play Arena: an empty deployment line builds the two sandbox brawls, a deployed line builds a real expedition against the cult (three waves, guard loot, soldier loot run, `Enter` back to town) |

The arena decides the mode from the warband's own deployment line: the town gate
writes `Warband.deploy_battle(ids)`, so the field never needs a second flag.

### The loop, as wired

`title -> GameFlow.enter_warband()` -> **cages** (`TutorialSequencer` through the
four bodies, the rescuer **you take yourself** with F5 / `[ ]`, four G-cut
latches, the watchers, G at the gate)
-> **town** (stash, altar, recruiter, quartermaster, gate) ->
**arena expedition** (three waves, the field sweeps itself) -> **town** (`Enter`).
Every hand-off goes through one `scene_requested(path)` signal per scene, bound to
`GameFlow`; a scene never loads another scene. `GameFlow.active` is false until
the campaign door is used, which is why every scene regression can emit its door
without being teleported out of the test.

### Multiplayer

`admin_arena.tscn` with `--warband-host <port>` hosts; `--warband-join <address>
<port>` joins. Both machines must carry the same warband save (same roster ids),
exactly as the arena's seats already require a shared roster. The host is
authoritative for every body; a client asks to enter a body and the host's soul
router answers (one peer per body, alive only), then broadcasts the ownership map.
Bodies are served at 20 Hz through `NetLimits.batches`, the guest predicts the
body it is inside, and a leaving peer's body falls back to its own AI.

### Gate 2 result

| Test | Result |
| --- | --- |
| `cage_escape_regression` | 80 checks, 0 failures |
| `town_hub_regression` | 58 checks, 0 failures |
| `expedition_regression` | 18 checks, 0 failures |
| `game_flow_regression` | 22 checks, 0 failures (four real scene transitions on one save) |
| `branded_abilities_regression` | 114 checks, 0 failures |
| `enemy_waves_regression` | 108 checks, 0 failures |
| `warband_session_regression` | 49 checks, 0 failures (two real ENet processes) |
| `admin_arena_regression` | 98 checks, 0 failures (sandbox gate + the branded verb) |
| `quartermaster_regression` | 20 checks, 0 failures (keeper price, spent purse, refused shortfall) |

Rendered inspection (not just headless): the cage camp, the town square and the
arena were each launched with a real window and captured; the arena capture is
what exposed the engine fog trap above.

### Gear rules (the stash is one pool)

- `Warband.equip_merc(id, slot, item_id)` equips from the pool **or takes a worn
  copy off whoever holds it**: handing the rescuer's only shiv to a prisoner is a
  transfer, and a piece can also move between slots on the same body. A refused
  equip never pockets somebody else's gear.
- The paperdoll therefore never disables a worn row: clicking it hands the piece
  over. Clicking a worn slot takes it off.
- `Warband.auto_equip(id, item_id)` (used by `WarbandLoot` on a hand pickup) puts
  a looted piece straight into the soul's hands when that slot is empty or the
  new piece is worth more than what is worn there; anything else stays in the
  stash. The post-battle sweep never auto-equips.
- A looted or paperdoll-equipped piece is pushed onto the **live rig** with `PossessionController.refresh_gear(merc_id)`. `seat_loadout()` is the spawn snapshot (the wire shape); using it to re-dress a body silently kept the old kit, so a squadmate "carried" a sword it never drew and `begin_melee` refused it. Cage, arena and town all use `refresh_gear`, and the ally driver re-dresses a body whose roster says armed but whose hands are empty.
- Arena bodies are born with `combat.target_mask = 4` (other fighters). The camp's watchers are wilderness mobs on layer **2**, so the cage sets its squad's mask to 2: their blades bite the watchers and cannot cut the squad itself. Any scene that puts mobs and warband bodies in one fight needs the same line.
- Every scene names its keys on a standing hint line (`WarbandHud.set_hint`, 16 px
  under a 20 px prompt): the tutorial's per-beat hint comes from
  `TutorialSequencer.hint()`, the town names its screens and the counter you stand
  at, the field names the fight verbs.
- The opening fight is the player's: taking Corvin hands over empty hands, the
  shiv lies in the dirt (`K`), and the two camp watchers wake only once a body is
  holding it. Six more come out of the wood at the leaving, each carrying a
  catalog blade (`arm`) and dropping it on death. The squad loots silently - the
  HUD never announces a pickup and the objective never asks for one.
- One card is not a beat of the chapter: the first squadmate to go down within
  `REVIVE_LESSON_RADIUS` (12 m) raises `lesson_revive`, which teaches **HOLD G**
  for five seconds (no numeral, no stamp - it can happen anywhere). It is pushed
  from `world_scene._on_body_downed`, so the camp and the trail share it.
- The cage tutorial raises a `TutorialCard` on each new beat. The card is modal
  and pauses the tree (`PROCESS_MODE_ALWAYS` so its own button still works), shows
  the lesson at 34/20/24 px, and closes on CONTINUE / G / Enter / Escape. A card
  never re-opens for a beat already read, and `GameFlow.goto` clears any pause
  before a scene hand-off. One engine quirk is pre-existing and
unrelated to this subsystem: `arena.tscn`'s lobby renders over a bright sky and
reads washed out at this camera, while the admin arena (same world kit) renders
correctly after the fog fix.

## 10. Current state (read this before changing anything)

The shipped loop, the decision log, the test inventory and the next-phase
worktree briefs live in **`docs/warband-handoff.md`**. Start a session there: it
names the commit, the engine/test commands, the eighteen rules that must not be
regressed, the Godot traps already paid for, and the phase plan.

### Checkpoints (autosave)

The campaign autosaves at the two moments that begin a stretch, and the same file
carries the bookmark (`Warband.checkpoint`, save version 4):

| Id | Written when | Resume puts the squad |
| --- | --- | --- |
| `trail_start` | the camp's six watchers are dead and the leaving has happened (the tutorial is over, the run starts) | 60 m past the camp mouth, on the road, cages already open |
| `town` | the soul's body first enters Hearthstead's square | the town's own spawn posts, square services live |

`Warband.save_checkpoint(id, area, position, label)` writes the roster, the shared
stash, the Cruor ledger and the bookmark in one `user://warband_state.json` write,
so a load can never point at a state the file has not held. `sanitise_checkpoint()`
is the only reader (hand-edited or older files drop the bookmark, never half-read
it), and a v3 file simply resumes at the town as before. A wipe calls
`GameFlow.retry_checkpoint()` after `WIPE_BEAT`: the warband reloads, bodies that
were down wake at half health, bodies that were dead stay dead, and the **purse is
not rolled back** (it belongs to `PlayerState`, and a reload must not replay a
payment). With no bookmark - the opening - the wipe still has no way back. The
title's **RESUME WARBAND** door opens the world on the bookmark; **GHOST OF THE
WARBAND** is still always a new campaign. `tests/checkpoint_regression.gd` owns
the whole contract, including the two real world resumes.

### The newer surface (skills, menu, keepers, wolves, co-op)

These landed on the same world without a second rulebook. Each has one owner:

- **Item skills are still data.** `AbilityRules` is the only definition table;
  the warband's scene half is one `WarbandAbilities` node in `world_scene.gd`
  (`setup(world, controller)`, `bind_body(actor)`), which turns the possessed
  body's own `AbilityRunner` cues into arrows, spells, the backstab blink/stab and
  blade presentation, on the authority only. The keys are **plain 1/2/3** (Shift+1..3
  is the same press — the tiles' shared `SHIFT + n` caption is rewritten), and the
  HUD shows stamina plus the three slots from that body's runner every frame.
- **The cover peek is RMB, in cover only.** Outside cover the same press is the
  guard; the lean ends on release, and leaving cover with `F` drops it.
- **Escape is `WarbandMenu`** — six rows (resume, save, load, settings, exit,
  quit), one ledger frame, the shared sound page. It never pauses the tree, and
  `world_scene` closes it, then an open panel, then opens it.
- **The three keepers are one board.** `VendorMenu` is re-pointed per seat
  (`vendor_orla`/`vendor_brann`/`vendor_vey`); `Warband.buy_gear` buys into the
  shared stash and `Warband.sell_gear` sells one pooled spare out of it for 60%.
- **The wolves are the base mob.** `WarbandWilderness` places eight `enemy.gd`
  **kind 0** briars in exactly two deep-wood packs of four — no new class, no stat
  table — gives each pack one `MobWander` territory, and parks walked-past ones
  with its own `MobCuller`. There are no wolves on the lane or the camp corridor:
  the packs live 30-50 m off the route, beyond the wolves' own sight of it and
  hundreds of metres apart, so a body only meets one by leaving the trail.
- **Co-op is one `attach_world` on the existing session.**
  `GameFlow.host_campaign`/`join_campaign` reuse `WarbandSession`; the host owns
  the mobs (15 Hz, name-keyed snapshots, and every guard a guest holds is a
  replica that runs no AI), the loot, the missiles and the kill reward, while a
  guest writes no checkpoint or save of its own, dismisses the camp lesson and
  runs no squad AI. The lobby's mode row defaults to campaign co-op; the arena
  bout remains selectable.

### The band looks like a band

Eight mercenaries fielded on one skeleton used to be eight of the same man. A
mercenary's **look** is now a pure function of their id - `WarbandLooks.profile_for`
(`scripts/warband/warband_looks.gd`) - so every peer, every reload and every save
dresses him identically without a byte on the wire and without a field in the
save. The numbers and the labels live in
`assets/characters/warband/ironwood_warband_looks.json`, written by
`python tools/prepare_warband_looks.py` from geometry and textures the repository
already ships (no download, no Blender):

| Where the look comes from | What it changes |
| --- | --- |
| `ironwood_faces.glb` | one of eight faces: an analytic warp of the Ranger head (jaw, chin, cheekbones, nose, brow ridge, eye spacing, mouth, lips), windows confined to the *front* of the face so every helmet and hood still fits. Brows follow the same field; each eyeball is translated rigidly |
| `ironwood_hair.glb` | one of eight cuts (bare, buzz, crop, fringe, widow, **afro**, mop, bob) plus one of five beards (none, moustache, stubble, chinstrap, full). A short cut is a **thin shell of the skull's own triangles** - a buzz cut has to be the man's head with colour on it, and a smooth proxy bulges where a forehead recedes - and the **afro** is the one lofted mass: rings from a crown disc down to its own measured hairline, swelling to a cloud and settling flush onto the skin, so the volume is sealed and there is no rim to gape. A beard is a sheet over the jaw cut by its **own alpha design** - a cheek line that leaves the cheek clear, an arched moustache, an open mouth and a jawline bottom edge - so the silhouette is a texel and not a triangle edge. Everything binds rigidly to `Head` |
| `warband_skin_basecolor.png`, `warband_shirt_basecolor.png`, `warband_shorts_basecolor.png` | the *veiled* maps: authored detail divided by the colour that carried it, so one texture serves every tone and the tone is one `albedo_color` |
| `warband_eye_<n>_basecolor.png` | one of five iris tones |
| `WarbandLooks.HEIGHT_MIN..HEIGHT_MAX` | the rig's uniform scale, `0.86`..`1.14` of the authored 1.87 m |

Palette entry 0 of skin, shirt and shorts is the *measured base* of the shipped
texture, so a mercenary wearing it looks exactly as the warband shipped; the
seven entries after it are the variation. Faces, haircuts and the three colour
palettes **step** with the id at four different offsets, so a full deployment of
eight fields eight different faces, cuts, skins, shirts and pairs of shorts; the
heights, beards and irises are hashed so they do not track any of those columns.

What a look is *not* allowed to change: health, stamina, the capsule, reach,
speeds, or anything else the warband's contract fixes. A height is presentation -
`Archer` bakes it into the model before the rig measures its own legs, so the
authored foot contact survives at both ends of the band, and `ArenaActor`,
`PossessionCamera`, the name plate, the chest aim point and the head hit zone all
read the same scale. A helmet hides the hair rather than the hair poking through
it, and a body with no look at all - the frontier ranger, an arena fighter, every
mob rig - is untouched by any of this.

`tests/warband_appearance_regression.gd` holds the contract (determinism,
distinctness across the deployment cap, every named piece present in the assets,
the rig applying them, hair under a helmet, head zones scaled);
`playtest/warband_lookbook.gd` and `playtest/warband_band.gd` render the band for
the eye.

Short version of the latest tuning (all in the code, all covered by
`tests/cage_escape_regression.gd`):

- the fifth prisoner is **not** forced into the soul; the player takes him (F5 /
  `[` / `]`), and taking him opens nothing - a latch is cut by hand;
- each of the four latches is cut **individually with G**, standing at that cage
  with a blade in hand (`LATCH_REACH` 2.2 m); bare hands are refused with a status
  line, and nothing opens on a possession or a kill;
- once all four are cut the freed squad arms itself off the ground and attacks the
  watchers on its own, silently, through the shared squad ladder;
- watchers are rigged, varied bodies (see the `CageWatcher` row), they hunt the
  nearest standing body, and **six more come out of the trees** as the squad
  leaves the camp;
- **the steel falls out of the hand**: a body that dies - a watcher or a cultist -
  drops the catalog piece it was swinging onto the dirt in front of it, and that
  drop joins the one loot list (`WarbandGearDrop.strip_enemy` /
  `world_scene.drop_held_weapon`). What the corpse keeps is the rag on its back
  and whatever it carried, so nothing is on offer twice, and the blade is taken
  back with `K` (or walked to by a squadmate) instead of being read off a panel;
- **a body on the floor lets go of its own steel**: `ArenaActor.downed_started`
  and `killed` both walk `WarbandGearDrop.strip_hands` through
  `world_scene.drop_merc_gear`, which empties the two hand slots on the roster and
  puts each piece on the ground beside the body. A dropped piece is *not* booked
  into the stash - it is on the floor until somebody picks it up - and the body is
  re-dressed (`refresh_gear`) so its hands are visibly empty;
- **a drop is a thing lying on the ground**: `WarbandPickup` draws the catalog
  piece - a blade on its side, a bow curved on the dirt, a shield face down, a
  bundle folded - with the name plate floating over it, and nothing bobs, spins or
  floats. The shared frontier drop (`scripts/loot_pickup.gd`) follows the same
  rule: its shape is authored up the piece's own axis and laid down by its holder;
- **the cult is the salvage tier**: watchers and the trail's cultists carry
  `MAKESHIFT_TIER` (`dagger_ironwood`, `club_makeshift`, `branch_heavy`,
  `bow_twig`, `shield_wood`) and the expedition's waves escalate by more bodies and
  better salvage, never by forged arming swords - a mob with a smithed blade was a
  knight in rags whose corpse out-valued the battle;
- **the first scenario pays in salvage, on the back as well as in the hand**: a
  corpse in the camp or on the road carries the **makeshift** set or nothing at
  all. `CageWatcher._pick_variant` holds that rule (`WATCHER_ARMOUR` is
  `["naked", "makeshift"]`, and a set outside it is pulled to salvage), the variant
  table's own `armor`/`pieces` say the same thing, and `escape_run.CULTIST_RAG`
  gives every blade cultist and hidden archer the same makeshift chest. The slots
  still vary, so two corpses are not identical - the tier does not. A leather,
  cloth or mail piece off the first six cultists used to put a forged kit in the
  squad's pack before the trail's second torch;
- **field medicine**: `bandage_linen` is a catalog piece (category `misc`, so no
  slot will ever wear it). Half the watcher variants carry one as `carried` gear,
  so it reaches the shared stash through the corpse registry like any other loot.
  A hurt ally below `BANDAGE_HEALTH_SHARE` (70%) with one in the stash binds its
  wounds for `BANDAGE_SECONDS` (1.8 s) once no hostile is inside
  `LOOT_CLEAR_METRES` (22 m): the dressing leaves the stash, the body gets
  `BANDAGE_HEAL_SHARE` (30%) of its own pool back, and the roster is written on the
  same frame. An interrupted channel spends nothing. `tests/squad_medicine_regression.gd`;
- **one body layer, and it is the naked set**: `Archer._apply_armor_visibility`
  draws a slot's own worn set, and the **naked** region underneath it only while
  that slot wears nothing: bare skin, the old shirt and the shorts. The imported
  leather outfit is the *leather set's* meshes, never an underlayer - a chest that
  wore mail, plate or cloth used to put the green leather hood, torso, bracers,
  calf wraps and boots on screen for every slot that wore nothing, so putting one
  piece on looked like the body reverting to green leather. The naked set is four
  pieces, one per body region (`Armor_Naked_Chest`, `_Hands`, `_Legs`, `_Feet`),
  and the arms and feet bridge two slots each, so they stay on screen while
  *either* neighbour is bare: a hauberk with bare hands keeps its hands and mail
  legs with bare feet keep their feet. `tools/prepare_naked_armor.py` builds it
  from the CC0 Quaternius `Superhero_Male_FullBody` body on the Ranger's own
  65-bone skeleton: the sculpt is split by dominant bone, its head is removed at
  the neck (the Ranger head stays on screen outside every slot), the neck is
  tapered into the head's measured opening and the ribcage is slimmed out of the
  source's superhero barrel. The shirt and shorts are cut from the body's own
  surface, relaxed and pushed outside it, so they are fitted by construction;
  the skin keeps the source's painted 2048 maps and the cloth gets its own baked
  linen (shirt) and charcoal twill (shorts) maps. The measured neck taper, torso
  slim, garment extents and cloth-to-skin gaps are recorded in
  `ironwood_naked.json`;
- **the watcher swings the thing it is holding**: the warden's authored attack
  clips raise the arm and then *hold* it, so played straight the club sat over the
  head and the blow landed with no motion. `devil_mob_visual.gd` now lays its own
  arc over the clip on the mob's own clock - `SWING_COCK` (the club up and forward)
  through `SWING_THROUGH` (arm down and across, club head below the shoulder) with
  a front-loaded whip at 34% of the strike window, an `SWING_OVERSHOOT` follow
  through and a settle - applied by *setting* the arm bones from the pose the
  windup opened in (`process_priority` 20, after the AnimationPlayer), so the clip
  cannot drag the club back up. The club head travels ~2 m per swing.
  `tests/watcher_variants_regression.check_swing_arc` measures it;
- **the gear page dresses the ranger from ids**: `ArmorData.set_of_item(id)` reads
  the set back out of an `armor_<set>_<slot>` id. The paperdoll held item ids and
  fed them to `ArmorData.pack()` - which reads ints - so every slot packed as code
  0 and the preview was the leather set whatever the body wore, including nothing;
- **the quiver is kit**: `Archer._sync_weapon_visibility` shows it only while a bow
  is in the hands, so a prisoner with a club is not carrying arrows;
- **the branch is a two-hander held like one**: `Sword.BRANCH_GRIP_INSET` 0.20 m
  puts the fist up the limb instead of on its butt end, and the profile is
  `length` 1.16 / `reach` 2.0 / 1.6 s swing (`Items` detail and `ITEM_STATS` keep
  the same 2.0 m reach);
- **a downed body keeps its soul**: `SoulRouter.set_body_state` only frees the
  peer on `DEAD`, and `PossessionController._on_body_state_changed` only ejects on
  `DEAD`. A player who goes down still has hands: `CrawlToSafety.manual` (set for
  the soul's body every frame by `world_scene._sync_crawl_control`) reads the
  player's own `move_direction` and stands still with no key held, at the same
  `DOWNED_CRAWL_SPEED` and through the same capsule, so a wall still stops it.
  Measured in the world: 0.00 m of drift in two idle seconds (the old auto-crawl
  slid the body away under the player), 0.67 m while a key is held, 0.00 m after
  release. Entering a downed body is still refused (`REASON_DOWNED`);
- **the revive key is a hold**: `G` held for `REVIVE_CHANNEL_SECONDS` (5 s) picks a
  downed squadmate up, and the body stands on `REVIVE_HEALTH_FRACTION` - **5%** of
  its own pool, enough to walk out and not enough to trade. `G` is only consumed
  on press when a downed body is actually in reach, so a tap still cuts a latch,
  opens a counter or searches a corpse. `world_scene._input` and
  `admin_arena._input` both bind it; releasing cancels and spends nothing;
- **the squad rescues the soul**: `SquadDrive._rescue_step` picks the nearest
  ally on its feet when a squad body is downed and nothing hostile is inside
  `LOOT_CLEAR_METRES` (22 m), walks it inside `revive.reach`, and opens the
  scene's channel on the squad's own hands (`ReviveChannel.begin_ally`, keyed
  `ALLY_PEER` - the bot refusal is for *peer* channels only). `_rescue_patient`
  reads *any* downed squadmate, preferring the body the soul is inside: the soul
  hops bodies and a downed mercenary whose soul has moved on is still the
  warband's to pick up. Measured in the world with the field cleared: the soul was
  up in 5.4 s on 5% health. A hostile arriving,
  the rescuer going down or walking off breaks it exactly like a human key. An
  AI channel is never opened while a fight is on;
- **the crosshair is back**: `WarbandHud` draws its own `Reticle` (four arms and a
  dot) at the screen centre, visible only while the pointer is captured and the
  soul is in a body - nothing else in the warband says where the soul is aiming;
- **the weapon is carried low at a run**: `Archer.CARRY_DEGREES` (64) tips the
  held piece toward the floor as speed passes a jog (`_carry_blend`, eased at
  `CARRY_RATE`), and only then: a swing, a guard, a roll, a slide, a consumable or
  cover all hold the authored grip. The pitch is applied about the **actor's own
  right axis**, not the hand socket's local X: the hand rolls through a run, and a
  local-X pitch turned a long piece out to the right as much as toward the dirt.
  A two-hander shouldered into a sprint used to reach through the head;
  `arm_clearance_regression.check_carry_clearance` measures the shaft clearing the
  skull (0.10 m before, 0.35 m after);
- **the squad stands off**: an ally closes to `STANDOFF` 1.45 m and no further,
  walks itself back out if the press carries it inside `MIN_GAP` 0.95 m, and jogs
  only past `RUN_GAP` 7 m. The old ladder walked to the mob's own origin on every
  frame and ran the last metres in, which is why the squad read as a bulldozer
  shoving the pack across the clearing;
- **personal space and roaming**: every movement intent `_steer` writes is pushed
  apart from squadmates and the soul inside `PERSONAL_SPACE` 1.45 m, an escort
  stands on its own slot of a ring around the soul (`_escort_post`, slot from its
  place in `squad_ids`) instead of on the soul, and an ally with nothing to do
  takes one short step and then a rest (`_idle_roam`: `ROAM_STEP_MIN/MAX` 0.35-0.60 s
  of stepping, then `ROAM_REST_MIN/MAX` 2.5-5.0 s standing). An escort also keeps
  an arrival band - walk to its post only beyond `ESCORT_ENGAGE` 1.9 m, stop
  `ESCORT_STANDOFF` 0.85 m short - because a body that walked to its post and
  overshot it by the walk's own stopping distance paced back and forth for ever:
  measured on a still soul with no enemies, four allies covered 40-53 m apiece in
  ten seconds and ended 12-20 m from where they started. After the band and the
  rest, the same measurement is 0.9-1.8 m in ten seconds. A squad with nothing to
  do used to stand as one knot - and then, for a while, to walk in circles;
- an unarmed ally looks for **steel** first - a weapon on the ground inside
  `SEARCH_METRES`, or a blade still on a corpse (`WarbandGearDrop`/`take_from_corpse`)
  - and does not cross the clearing for a rag, a ring or a bundle;
- the opening does not ask for loot, and the escape is a walk, not a quota;
- the whole campaign is **one world**: `scenes/warband_world.tscn` holds the cages
  in a camp pocket **deep in the wood**, 170 m of ordinary forest between the camp
  and the trail head, a **1,374.6 m** way through the trees (four caged soldiers
  beside it at fractions 0.34-0.86 and three warcamps 78-96 m off it) and a
  **stockade town** cut into the same trees at the far end: 286 stakes, one gap, a
  gate, eight roofs, five armoured keepers and three watch archers. There is no
  door key and no load between them — you walk — and the only scene change left is
  deploying to the arena;
- the world stands on **one heightfield** (`scripts/warband/terrain.gd`): three
  octaves of value noise on a fixed seed, ±1.9 m over 64/40/31 m wavelengths, baked
  as one `ArrayMesh` (42,658 triangles, 77 x 277 cells on a 7 m grid, x -268..271 and
  z -1695..244) with one trimesh collider and a
  `height_at()` every prop samples. The camp pocket and the town square are padded
  flat and blended into the slope; the walk between them is not. There is no lane:
  the way through the wood is a faint worn line marked by a **pair of torches every
  12 m** (152 lights), with trunks standing in the walked band and a 3.1 m clear
  line down its middle, so a body always has 2.5 m to pass through;
- the valley is **closed and deep**: thirteen tree rows a side run out to
  `WOOD_EDGE` 156 m, and after normalisation the heightfield raises a noise-varied
  34-58 m mountain rim along all four edges. The face is steeper than the 46-degree
  `floor_max_angle`, so the trimesh itself is the boundary - no invisible wall and
  no extra collider. A shallow **swamp** is cut into the wood at `SWAMP_FRACTION`
  0.515 of the lane, on one side, 6.4-26 m off the centre line: a sunken bowl with
  a water plane on the existing water shader, reeds, snags and mist, clear of the
  torches so the route itself is unchanged;

### Running the tests

`python tools/run_tests.py` is the **warband** suite - the game - one pool of
isolated processes, with the two ENet tests serial afterwards. The frontier,
arena and delve suites are a sandbox harness for the shared rig and combat code;
they run with `--base`, only when a change touches that layer.

**Hard rule: a test run is a couple of minutes, never more.** Per test 90 s
(120 s is the absolute ceiling anywhere), whole run 180 s; the runner kills a
test at the ceiling and fails the run when the total is exceeded. Nothing here is
allowed to grow to ten minutes.

| test | what it owns |
| --- | --- |
| `cage_escape_regression` 263 | the camp, the four latches, the pair, the doors, the corridor to the road |
| `escape_run_regression` 248 | the way through the wood, its cult, and the ambush that follows the leaving |
| `warband_world_regression` 250 | one world, one controller, the ground, the 1,575 m walk, the escort, the budget (~65-100 s: the only long test) |
| `watcher_variants_regression` 587 | the variant table, makeshift-only kits, a landed blow through `attacked`, the guard/stagger/crouch rules, and the warden's three swings + block + stagger + crouch clips |
| `corpse_loot_regression` 110 | the corpse registry, one booking path, the corpse screen |
| `stash_autoloot_regression` 185 | real drops, quick-loot, the sweep, the stash, the gear-drop rule (both hands empty, nothing banked, a lying piece that never moves) |
| `squad_medicine_regression` 22 | the ally's bandage: the gate, the seconds, the spend, the interrupt, the roster write |
| `downed_bleedout_regression` 46 | the prone pose, the drip, 30 s to DEAD, revive clears it |

- the camp is a **40 x 52 m ragged pocket** - broken stakes, three twig shelters,
  a fire ring, trees inside the footprint - padded flat into the world's heightfield
  (420 x 1484 m, with an invisible catch floor under its lowest point), so the cages
  stand level and nothing can fall out of the world.


## 11. The first town, the orders and the road out (shipped)

The campaign now has a destination, a reason to leave it and a way to read the map
between the two. Everything below is a module with its own regression; the numbers
and the rules they cannot break live in `docs/warband-handoff.md` §§1-4.

| Surface | Module | Contract |
| --- | --- | --- |
| The stockade | `scripts/warband/town_hub.gd`, `town_dressing.gd`, `town_folk.gd` | `WALL_RADIUS` 22, a `VillageKit.palisade` ring cut for one north gap and a `VillageKit.gate` in it, eight roofs (`keeper_hut` x5, `wattle_hut` x2, `trader_frame` x1) and village dressing with no colliders of its own. The same service ids, points and `G` semantics as before, plus `ichor`. Five armoured keeper bodies (`Archer` rigs, `WarbandLooks` profiles, real armor sets) stand behind their counters, unpossessable and unhittable |
| The watch | `scripts/warband/town_guard.gd` | three static archers on the gate: nearest hostile within 26 m from the world's `guards` (or `wild_mobs`), line of sight on layer 1, 0.9 s draw, a real `arrow.gd` on the mob layer, 1.6 s cooldown. They never move or speak |
| The ledger | `scripts/warband/quest_log.gd` | `WarbandQuests` on `Warband.quests`: `KILL` / `RESCUE` / `COLLECT` / `APPLY` / `REACH`, four rows in `DEFS`, one state and one count each, saved as `quests` in save v5. `note_kill` / `note_rescue` / `note_collected` / `note_applied` / `note_reached`; `offer` → `accept` → `turn_in` with the chain in each row's `next` |
| The keeper who talks | `scripts/warband/quest_giver.gd`, `quest_marker.gd` | `talk(service, peer)` raises the card that teaches or hands over an order and answers false when the counter should open instead; `marker_service()` decides who wears the gold `TALK TO HIM` arrow (the recruiter while the band is short of the cap, the quartermaster when he has an order, a turn-in or a vial to explain) |
| The cage line | `scripts/warband/soldier_cages.gd` | four caged soldiers off the road, latches cut by hand with a blade (`G`, 2.2 m from the footprint), a door that lifts, a soldier who walks out and one `note_soldier_freed` per cage (roster + stash dressing + ledger + HUD). A `FREE HIM` arrow rides the nearest shut cage while the order is live |
| The warcamps | `scripts/warband/watcher_warren.gd` | 21 hollow wardens in three camps 78 / 96 / 86 m off the lane, dressed from the village kit, one `MobWander` territory each, wired to the world's kill handler so they count toward the bounty |
| The click | `scripts/warband/loot_hand.gd`, `loot_summary.gd` | a left click on lootable ground ducks the body for 0.9 s and empties a corpse record or a drop pile through the vacuum's one booking path, then says one line. `_input` reads it before the soul controller, so a click on loot is never also a swing |
| The map | `scripts/warband/world_map.gd` | one page, `M`, no pause: the lane sampled from the trail's path, the camp ring, the walled square, hostiles, the warband and the soul's own facing, plus `host.map_markers()` (shut cages, warcamps) |
| The bench | `scripts/warband/ichor_bench.gd` | `IchorBench.build_prop()` (furniture with the town's one cold-green light) and the panel: pooled unbranded weapons, one vial per blade, `WarbandCruor.bind()` writing the altar's own brand ledger without touching the essence wallet |

The **orders** the quartermaster hands out, in chain order:

1. `free_the_soldiers` — rescue four caged soldiers.
2. `cull_the_watchers` — kill twenty hollow wardens.
3. `find_the_crypt` — a shell: the order exists, the place does not.
4. `bind_the_ichor` — off the chain: appears the moment a warden's vial is in the
   shared stash, and teaches the bench that turns it into a weapon's sigil.
