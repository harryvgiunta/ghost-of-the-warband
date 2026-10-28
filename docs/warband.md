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
| Revive channel | `REVIVE_CHANNEL_SECONDS` | 5.0 s, human only | same |
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
| `Tab`, `1`..`7`, mouse, `Space`, `C`, `F`, `G`, `E` | unchanged from the arena/frontier bindings |
| `E` held | Revive the downed body under the crosshair (5 s channel, humans only) |
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
3. A hit that overkills by <= 10% downs and crawls; a heavier hit kills; holding
   `H` for 5 s revives; AI never revives.
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
| `scripts/warband/possession_camera.gd` (`PossessionCamera`) | adopts the mode's `Camera3D`, `follow(body, snap)`, `swoop_to(body, seconds)`, `rotate_view`, `aim_ray()`, `follow_point()` |
| `scripts/warband/possession_sync.gd` (`PossessionSync`) | host-authoritative transfer RPCs plus `server_apply(peer, merc_id)` |
| `scripts/warband/combat_bubble.gd` (`WarbandBubbleManager`) | `setup(radius, exit_radius)`, `set_humans`, `track/untrack`, `sim_state_of`, `clear`, `sim_changed` |
| `scripts/warband/passive_duel_brain.gd` (`PassiveDuelBrain`) | `attach(body, opponent)`, `set_active`, `step(delta)` for fighter bodies (before `physics_step`) |
| `scripts/warband/downed_state.gd` / `crawl_to_safety.gd` / `revive_channel.gd` / `bleed_drip.gd` | `DownedRules.*` (including `bleed_fraction`, `drip_interval`, `drip_volume`), `CrawlToSafety.attach/set_anchor/set_friends`, `ReviveChannel.set_bodies/begin/tick/cancel/progress`, `BleedDrip.attach/detach/attached`. `ArenaActor.enter_downed` puts the rig in its prone drag pose (`Archer.set_downed`) and attaches one drip; revive, respawn and `_die` clear all of it, and `apply_snapshot` drives the same three things so a replica lies down and bleeds off the unchanged wire. `bleed_loss` is written from the 30 s clock every downed frame and is the only input the drip reads. |
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
| `scenes/cage_escape.tscn` + `scripts/warband/cage_escape.gd` | night camp **deep in the wood**: a ragged 40 x 52 m pocket (`YARD_HALF_WIDTH` 20, front -30, back 22) with no wall and no gate - a broken stake ring, three twig shelters, a fire ring and junk, trees standing inside the pocket, and 170 m of ordinary forest (`CAMP_TO_ROAD_METRES`) before the trail's first torch. Four cages clamped one body each; the rescuer's scripted jog and **the body you have to enter yourself** (F5 / `[ ]`); **one latch per cage, cut by hand with G within `LATCH_REACH` 2.2 m and only with a blade in hand** (`interact`/`latch_target`/`open_latch` - nothing opens on a possession or a kill); two camp watchers (asleep until the player is armed with his own shiv, which lies on the dirt as the lesson's first weapon); three makeshift-tier drops on the ground; the leaving is a walk out of the trees |
| squad AI (`scripts/warband/squad_drive.gd`) | the one module both areas share: a freed prisoner arms itself from the nearest drop (booked by `WarbandLoot`, worn via `auto_equip`, re-dressed with `refresh_gear`), then runs at the nearest watcher and fights on layer 2 through one explicit ladder - close / swing / guard / circle / reset - resolved on every frame, with the exchange rolled once when the blade frees (55-70% guard for 0.35-0.80 s, guard dropping into the blow), 1-3 swings then a 0.25-0.55 s short rugged circle re-rolled per step, and only `sword`/`dagger` allowed to guard. Escort clause when nothing is hostile; the field is stripped once `_clear_of_hostiles` at the drop or corpse (22 m), drops through `quick_loot` and bodies through `register_corpse`/`corpse_at`/`claim_corpse`. The player's own body is never driven. |
| `scripts/warband/cage_watcher.gd` (`CageWatcher`) | the wood's **antlered hollow warden** (`extends ForestMob` → `DevilMob`, `WARDEN_ID` "hollow_warden"), so the camp is guarded by the silhouette the mode is about - and it swings, blocks, staggers and crouches on baked clips. `PAIR_HEALTH` 44 / `HARDENED_HEALTH` 144, `WATCHER_LAYER` 2, pack `camp_watchers`, sight 60. A deterministic 12-entry `VARIANTS` table (seeded by `mob_id` + the node's ordinal) varies a paint multiplied into the body's own PBR surfaces, a uniform silhouette scale 0.88-1.30, a main hand from `MAKESHIFT_TIER`, a favourite swing, a guard share and a crouch. `arm(item_id)` builds the real catalog model (`sword.gd`/`dagger.gd`/`bow.gd`) onto the `hand_r` bone through a `Grip` child of the `BoneAttachment3D` (the attachment rewrites its own transform from the bone every frame, so a grip set on it is discarded) driven by the per-mob `grip_offset`/`grip_rotation`/`grip_scale` entry in `scripts/forest_mob_visual.gd`, with a per-kind `grips.bow` override so a bow stands upright and `take_weapon_item()` strips it; `gear_items()` lists the blade plus the worn salvage. Per windup it picks `Warden_Attack` / `Warden_Attack_Slash` / `Warden_Attack_Stab`; one guard roll per exchange (`guard_chance()` = variant share × `guard_scale`, capped 0.9) plays `Warden_Block` and holds instead of trading, then drops into the swing; any blow at or above `max(STAGGER_FLOOR 6, STAGGER_SHARE 10 % of health)` plays `Warden_Stagger` and cancels swing, guard and step; `Warden_Crouch` is the stance while waiting on the cooldown or hurt. The three scene dials (`blow_scale`, `guard_scale`, `swing_gap_scale`) weight the blow, the guard share and the cooldown; the strike emits `attacked(self, profile damage × blow_scale, victim)` and a death emits `defeated` exactly once |
| `scripts/warband/tutorial_card.gd` (`TutorialCard`) | the modal step card: large title/body/keys, **pauses the tree** while open, one CONTINUE button (or G / Enter / Escape), restores the previous pause and mouse state on close |
| `scripts/warband/duel_lesson.gd` (`DuelLesson`) | the first fight's lesson, four facts and four cards: `MOVE` (the soul enters Corvin) -> `FETCH` (the body stands on the shiv) -> `FIGHT` (the shiv is taken; the pair may wake) with the **swings** card on the player's first cut and the **guard** card on the second watcher's first windup, then `DONE` on a guarded blow or on the pair falling. No scene lookups: the camp feeds facts and shows the cards `card_wanted` asks for; every transition is guarded and every fact counts once. `duel_lesson_regression` owns the order |
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
- **field medicine**: `bandage_linen` is a catalog piece (category `misc`, so no
  slot will ever wear it). Half the watcher variants carry one as `carried` gear,
  so it reaches the shared stash through the corpse registry like any other loot.
  A hurt ally below `BANDAGE_HEALTH_SHARE` (70%) with one in the stash binds its
  wounds for `BANDAGE_SECONDS` (1.8 s) once no hostile is inside
  `LOOT_CLEAR_METRES` (22 m): the dressing leaves the stash, the body gets
  `BANDAGE_HEAL_SHARE` (30%) of its own pool back, and the roster is written on the
  same frame. An interrupted channel spends nothing. `tests/squad_medicine_regression.gd`;
- **two body layers, and the chest picks one**: `Archer._apply_armor_visibility`
  draws the **naked** body (bare skin, old shirt, shorts) when the chest slot is
  empty or naked, and the imported ranger outfit as the base the forged sets were
  fitted around when it is anything else. Every slot still draws its own worn set
  on top, so a prisoner in mail trousers is a bare body with mail on the legs. An
  empty slot used to fall through to the imported leather outfit, which made a
  naked body a man in full green leather;
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
  cover all hold the authored grip. A two-hander shouldered into a sprint used to
  reach through the head; `arm_clearance_regression.check_carry_clearance`
  measures the shaft clearing the skull (0.10 m before, 0.35 m after);
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
  and the trail head, a 915 m way through the trees and a town cut into the same
  trees at the far end. There is no door key and no load between them — you walk —
  and the only scene change left is deploying to the arena;
- the world stands on **one heightfield** (`scripts/warband/terrain.gd`): three
  octaves of value noise on a fixed seed, ±1.9 m over 64/40/31 m wavelengths, baked
  as one `ArrayMesh` (25,440 triangles, 7 m grid) with one trimesh collider and a
  `height_at()` every prop samples. The camp pocket and the town square are padded
  flat and blended into the slope; the walk between them is not. There is no lane:
  the way through the wood is a faint worn line marked by a **pair of torches every
  12 m** (152 lights), with trunks standing in the walked band and a 3.1 m clear
  line down its middle, so a body always has 2.5 m to pass through.

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
| `warband_world_regression` 198 | one world, one controller, the ground, the 1,117 m walk, the budget (~65 s: the only long test) |
| `watcher_variants_regression` 587 | the variant table, makeshift-only kits, a landed blow through `attacked`, the guard/stagger/crouch rules, and the warden's three swings + block + stagger + crouch clips |
| `corpse_loot_regression` 110 | the corpse registry, one booking path, the corpse screen |
| `stash_autoloot_regression` 185 | real drops, quick-loot, the sweep, the stash, the gear-drop rule (both hands empty, nothing banked, a lying piece that never moves) |
| `squad_medicine_regression` 22 | the ally's bandage: the gate, the seconds, the spend, the interrupt, the roster write |
| `downed_bleedout_regression` 46 | the prone pose, the drip, 30 s to DEAD, revive clears it |

- the camp is a **40 x 52 m ragged pocket** - broken stakes, three twig shelters,
  a fire ring, trees inside the footprint - padded flat into the world's heightfield
  (420 x 1484 m, with an invisible catch floor under its lowest point), so the cages
  stand level and nothing can fall out of the world.
