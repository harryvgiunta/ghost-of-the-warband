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
   `E` for 5 s revives; AI never revives.
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
| `scripts/warband/downed_state.gd` / `crawl_to_safety.gd` / `revive_channel.gd` | `DownedRules.*`, `CrawlToSafety.attach/set_anchor/set_friends`, `ReviveChannel.set_bodies/begin/tick/cancel/progress` |
| `scripts/warband/loot_vacuum.gd` / `warband_pickup.gd` | `WarbandLoot.setup/spawn/quick_loot/sweep/pickups`, `WarbandPickup.collect/blocked_for/label_text` |
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
| `scenes/cage_escape.tscn` + `scripts/warband/cage_escape.gd` | night camp over a **60 x 68 m** walled yard (ground 100 x 140 m plus an invisible catch floor, so no body can fall out of the world); the gate is set in the front wall and the four armed reinforcements walk in through it from outside; four cages clamped one body each, the rescuer's scripted jog and **the body you have to enter yourself** (F5 / `[ ]`, he stands still until then and no latch opens), **one latch per cage cut with G**, two antlered camp watchers, three weapon drops that snap into the soul's hands, the gate door (G) |
| squad AI (`_drive_allies` in `cage_escape.gd`) | a freed prisoner arms itself from the nearest drop (booked by `WarbandLoot`, worn via `auto_equip`, re-dressed with `refresh_gear`), then runs at the nearest watcher, aims and swings on layer 2; the player's own body is never driven, the rescuer joins in if the soul leaves him. Watchers hunt the nearest standing body, not just the soul. Kills or pickups that land while the cages are still being cut are refused as progress and then reconciled by `TutorialSequencer.note_battle_state()` when FREED begins, so a fast squad cannot dead-end the tutorial. |
| `scripts/warband/cage_watcher.gd` (`CageWatcher`) | the hollow warden silhouette with a camp profile: 36 health (three shiv stabs), 5 damage, slow telegraph; real wilderness mob, not an arena body. `arm(item_id)` puts a catalog blade on the rig's `hand_r` bone, and `take_weapon_item()` hands it back so the scene can drop it. |
| `scripts/warband/tutorial_card.gd` (`TutorialCard`) | the modal step card: large title/body/keys, **pauses the tree** while open, one CONTINUE button (or G / Enter / Escape), restores the previous pause and mouse state on close |
| `scripts/warband/tutorial_sequencer.gd` (`TutorialSequencer`) | `CAGED -> ALL_SEEN -> RESCUER_ARRIVED -> FREED -> ESCAPING -> TOWN`; six watchers in total (the first pair, then four armed reinforcements), no loot requirement in the objective; `note_rescuer_taken()` (the objective changes from "F5 or [ ]" to the latch count only once the player is in the body), four separate latches (`note_cage_opened`), out-of-order calls refused, objective **and** a per-beat key hint (`hint()`) |
| `scripts/warband/branded_runner.gd` (`BrandedRunner`) + `branded_fx.gd` | the six sigils: Arrow Barrage, Shockwave Cleave, Rending Strike, Ember Storm, Hellfire Cone, Blood Ritual Ward; tier scaling, stamina, cooldown, refusal reasons |
| `scenes/town_hub.tscn` + `scripts/warband/town_hub.gd` | dusk square, campfire, stash chest, altar, recruiter desk, gate; `interact_at(peer, point)` resolves the nearest service; one `scene_requested` door |
| `scripts/warband/expedition_gate.gd` (`ExpeditionGate`) | `prompt`, `deploy_and_launch(ids)`, `return_to_town()` |
| `scripts/warband/cultist_guard.gd` (`CultistGuard`) | crimson cultist body, faction filter so guards never fight each other, no arena respawn |
| `scripts/warband/enemy_waves.gd` (`EnemyWaves`) | deterministic waves (3, +1 per wave, capped at 6) with escalating kits, `wave_started/wave_cleared`, `guards()`, `field()`, `living()` |
| `scripts/warband/soldier_loot_run.gd` (`SoldierLootRun`) | survivors physically jog to the drops, then the vacuum books them |
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
- The opening fight is six watchers: the first pair are bare, the four that come
  through when they die each carry a catalog blade (`arm`) and drop it on death.
  The squad loots silently - the HUD never announces a pickup and the objective
  never asks for one.
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
names the commit, the engine/test commands, the twelve rules that must not be
regressed, the Godot traps already paid for, and the Phase 3 parallel plan.

Short version of the latest tuning (all in the code, all covered by
`tests/cage_escape_regression.gd`):

- the fifth prisoner is **not** forced into the soul; the player takes him (F5 /
  `[` / `]`) and no latch opens before that;
- each cage is cut individually with **G**, then the freed squad arms itself from
  the ground and attacks the watchers on its own, silently;
- watchers carry **72 health** and hunt aggressively (run 5.6 m/s, sight 60,
  orbit 1.9); the first pair is bare, and **six armed watchers** come through the
  gate when they die, each dropping the weapon it held;
- the escape needs all **eight** watchers down and no longer asks for loot;
- the camp yard is **60 x 68 m** inside a 100 x 140 m floor with an invisible
  catch floor, so nothing can fall out of the world.
