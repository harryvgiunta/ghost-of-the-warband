# Ghost of the Warband

> **The sandbox modes and the expedition are gone.** Ghost of the Warband is the
> only game: `title.tscn` → `GameFlow` → `scenes/warband_world.tscn`. The frontier
> (`main.tscn`), arena (`arena.tscn`), delve (`delve.tscn`) and the expedition
> field (`admin_arena.tscn`) plus their scripts were deleted; `arena_actor.gd` is
> now `scripts/warband/warband_body.gd` (`WarbandBody`) and nothing carries a bot
> AI or a round respawn. This document records the design that was built; where a
> section names one of those deleted files it is **history**, not a live contract.

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
| A death leaves the party | `Warband.reap_dead()` | the dead record is removed at once, its worn gear returns to the shared stash, and the hire cap it held is freed | `scripts/warband/warband_state.gd` |
| Tutorial tips | `WarbandTips.tip()` | the opening teaches with one line at a time: carved key tiles plus a command under the crosshair, up for six seconds and gone. Nothing pauses, nothing takes the pointer, and an id is offered once. `has_shown(id)` is what the quest keepers read | `scripts/warband/warband_tips.gd`, `tests/keybind_screen_regression.gd` |
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
| `scripts/warband/warband_contracts.gd` | `WarbandContracts` | Slot/weapon/health/sim enums, slot ids (`feet`, `main`, `off`), the party's modes (`PARTY_MODES`: `offensive`/`defensive`/`passive`, `DEFAULT_PARTY_MODE` offensive), the party member's dispositions (`DISPOSITIONS` `tank`/`melee`/`bow`, `DEFAULT_DISPOSITION` melee, `disposition_id`/`disposition_exact`/`disposition_label`/`disposition_text`/`next_disposition`, `DISPOSITION_ABILITIES` ranks and `disposition_ability_rank`, `DISPOSITION_GEAR` bonuses and `disposition_gear_score` (a row's `kind` entry wins over its `category`, so a knife does not score as a sword - `gear_kind` is the one reader of that), `DISPOSITION_GEAR_REFUSED` and `disposition_refuses_gear` (the kinds a trade never reaches for: a tank or a melee body never takes a bow or a staff, however empty the hand, and a tank never takes a two-hander, which would lock the shield out of the other hand), `DISPOSITION_OFF_HAND` and `disposition_off_hand_rank` (what each disposition wants in its off hand, ranked before price so a tank's board always beats a second blade)), `resolve_damage`, `finishes_downed`, `damage_multiplier`, all tuning constants |
| `scripts/warband/warband_roster.gd` | `WarbandRoster` | Mercenary records (identical base stats), health/downed/dead, `apply_damage`, `revive`, `tick_downed`, `equip`/`unequip`, the `reserve` flag (`field_ids`/`field_count`/`reserve_ids`), each record's `disposition` (`disposition_of`/`set_disposition`, sanitised on load so an old file or an unknown word comes up melee), deployment cap, save round-trip |
| `scripts/warband/soul_router.gd` | `SoulRouter` | Body registry, one peer per body, `request_transfer`, `cycle`, refusal reasons, alive-only entry |
| `scripts/warband/town_stash_model.gd` | `WarbandStash` | Infinite pooled stash, collective `rows()` sorted by value with `Equipped` tags |
| `scripts/warband/cruor_catalog.gd` | `CruorCatalog` | The five tiers, names/colours/values, `distill`, `unbind_yield` |
| `scripts/warband/cruor_manager.gd` | `WarbandCruor` | Essence wallet, `unbind`, `distill`, `distill_all`, `brand` and the brand map; plus the old catalog-id anointing remains only as `grant_anointing` (the delve's already-woken steel) and the `ANOINT_RECIPES` table the brand's window still reads. The per-copy ritual moved to `Warband` (below). Persistence: `cruor.brands`, and `cruor.anointed` is still re-derived from today's table on load for that legacy path |
| `scripts/warband/annoint_catalog.gd` / `annoint_roll.gd` / `annoint_ledger.gd` / `annoint_runtime.gd` | the annointment pool | **`AnnointCatalog`** — one `Entry` class (id, name, kind `STAT`/`PROC`/`ABILITY`, gear groups, slots, `TrinketStats`-shaped deltas, a proc verb, an AI tag set, a power band, a card line, and the `wired` honesty flag), built once from two shapes of data: `FAMILIES` (the five-rung blanket ladders) and `NAMES` (authored bundles). `for_item`/`for_armour_slot` are the only applicability answer. **`AnnointRoll`** — the die: add ability / add passive / remove / replace at 25% each, converted to a replace at the cap, and deterministic under an injected `RandomNumberGenerator` so a regression can force a band. **`AnnointLedger`** — per-**copy** storage (`"<catalog id>#<ordinal>"`), the kit ceilings, and the three answers the rest of the game asks: `stats_for`, `procs_for`, `abilities_for`. **`AnnointRuntime`** — one per body, armed at dress, playing `HEAL`/`STAMINA`/`REFLECT`/`ABSORB`/`LETHAL_SAVE`/`STAGGER`/`GUARD_BREAK`/`BLEED` off the body's own `take_damage`, `receive_melee` block branch and `struck_by` |
| `scripts/warband/branded_skills.gd` | `BrandedSkills` | The six branded abilities, which item class carries each, tier power curve |
| `scripts/warband/mercenary_vendor.gd` | `WarbandVendor` | Hire price (120 + 35/body), `hire()`, recruiter board |
| `scripts/warband/warband_state.gd` | autoload `Warband` | Owns roster + souls + stash + cruor + delve + the party's mode and each body's hotbar layout (`hotbar_kit`/`hotbar_skills`/`hotbar_layout`, `set_hotbar_order`/`move_hotbar_skill`/`reset_hotbar`, saved per record, defaulting to the kit order - main hand, off hand, then the worn trinkets - with the bandage and the healing potion fixed on keys 9 and 0, and refused on a lent band), gold bridge to `PlayerState.credits`, save/load (`SAVE_VERSION` 13; v13 adds each record's `hotbar_order` (the player's ten-key layout), so a v12 file fires in kit order; v12 adds `annoints` (per-copy lists) and `worn_copies`, so a v11 file loads with plain steel; v6 adds `cruor.anointed`, so a v5 file loads with plain steel; v8 adds `delve`, the packed delve inventory and who is below, so a v7 file loads with an empty pack and nobody below; v9 adds `party_mode`, so a v8 file - or a mode this build does not know - fights offensive; v10 adds `auto_equip_restricted`, the item ids held back from the band's automatic arming, so a v9 file arms from every piece; v11 adds each record's `disposition`, so a v10 file fields every body as melee), possession mirror, the delve verbs (§12), `set_disposition(merc_id, style)`/`cycle_disposition(merc_id)` (one body's disposition: `{ok, disposition, message}`, an unknown word and a mercenary that is not on the books refused, a lent warband refused with `LENT_DISPOSITION_MESSAGE`, and only a real change announced), `set_party_mode(mode)` (`{ok, mode, message}`; an unknown mode and a lent warband are refused, and only a real change emits `changed`, which is what mirrors it to a co-op guest), and `anoint(item_id)`: spends the recipe from the shared stash, writes the ledger, credits APPLY orders through `quests.note_applied` per reagent, emits `anointed(item_id, ability)` and `changed`, and returns `completed` (the orders it finished); a piece that is not the warband's, already anointed, or short of its recipe is refused and nothing is spent |
| `tests/warband_contract_regression.gd` | - | 284 checks over all of the above |

There is no proximity-bubble damage scaler any more (`WarbandDamage` and
`combat_bubble.gd` went with the expedition that needed them): every damage funnel
takes the damage it is given. **Never add a second multiplier.**

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
| `O` | The warband screen: a compact sidebar pinned to the window's right edge (roster in two-line rows - name, state chip, disposition, control; health bar, health and kit under it - with the party list scrolling inside it, and the recruiter board beneath). `TAB` is the quick swap below, exactly as in the open frontier |
| `Tab` | Quick weapon swap: the standing body puts away the set in its hands and takes up the other one. Both pairs live on the mercenary's roster record |
| `1`..`3`, `6`/`7`, mouse, `Space`, `C`, `F`, `G`, `E` | warband controller: plain 1/2/3 fire the three skill slots — an anointed main hand, an anointed shield, the worn trinket (Shift+1..3 is the same press) — 6/7 bandage/potion; mouse, `Space`, `C`, `F` and `E` keep the frontier meanings, `T` throws the held blade, and `G` stays the world's interact key |
| `G` held | Revive the downed body under the crosshair (5 s channel, humans and the squad's own hands) |
| `K` | Quick-loot the drop under the crosshair (battlefield looting) |

## 4. Phase 1 worktree ownership

Six isolated branches off `main`. Each one may create its own files and edit only
the files listed under its name. Anything else is a merge conflict waiting.

| Worktree | Owns (create) | May edit (existing) | Deliverable |
| --- | --- | --- | --- |
| `wt-1-soul-consciousness` | `scripts/warband/possession_controller.gd`, `scripts/warband/possession_camera.gd`, `scripts/warband/possession_sync.gd`, `scripts/warband/warband_body.gd`, `scenes/warband/*.tscn` it needs | `scripts/warband/soul_router.gd` (only if the contract truly needs a field) | Soul controller around `ArenaActor`, camera swoop, hotkey cycling, host/guest transfer lock over ENet, 2-peer test |
| `wt-2-bubble-combat-ai` | `scripts/warband/combat_bubble.gd` (`WarbandBubbleManager`), `scripts/warband/passive_duel_brain.gd` | none | Distance tracker from every human body, ACTIVE/PASSIVE toggling through `WarbandDamage`, 80% guard / circling / occasional-swing choreography |
| `wt-3-downed-revive` | `scripts/warband/downed_state.gd`, `scripts/warband/crawl_to_safety.gd`, `scripts/warband/revive_channel.gd` | `scripts/arena_actor.gd` (health → DOWNED, revive path), `scripts/main.gd` (same for the frontier body) | 10% overkill routing, soul-keyed crawl, human-only 5 s channel |
| `wt-4-stash-autoloot` | `scripts/warband/loot_vacuum.gd`, `scripts/warband/loot_pickup_warband.gd` if needed | `scripts/player_state.gd` (catalog additions only) | Manual quick-loot, end-of-battle sweep to the infinite stash, every gear type covered |
| `wt-5-cruor-altar` | `scripts/warband/sacrificial_altar.gd`, `scripts/warband/altar_menu.gd` (`AltarMenu`) | none | Altar scene/overlay: unbind, distil, brand/reroll with the real wallet |
| `wt-6-warband-ui` | `scripts/warband/warband_screen.gd` (`WarbandScreen`), `scripts/warband/warband_paperdoll.gd` (`WarbandPaperdoll`) | none | A compact warband sidebar pinned to the right edge (two-line rows with HP/downed/gear, a scrolling party list, a disposition chip whose press is `Warband.cycle_disposition` and whose tooltip is `Contracts.disposition_text`, click-to-control) and the mercenary paperdoll over the value-sorted stash |

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
3. In the campaign every lethal hit downs - a mercenary is never killed by the
   blow - and the body bleeds for 30 s. Only a body a soul is inside crawls on
   its keys; an AI-driven body holds the ground it fell on, which is what lets a
   squadmate stand over it for the channel. Holding `G` for 5 s revives it, a
   squadmate does the same once the field is quiet, and any blow that lands on
   the downed body finishes it and leaves a corpse. (The arena's own seats keep
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
| `scripts/warband/possession_controller.gd` (`PossessionController`) | `setup(warband, camera, bodies_root)`, `spawn_mercenaries(points, authoritative)`, `activate/cycle/direct(peer, merc_id)`, `active_body(peer := 0)`, `body_of/merc_of/merc_for_peer`, `set_bot`, `living_merc_ids()`, `physics_step(delta)` (with `auto_simulate = false`), `release_local()`, signals `possession_changed`, `possession_released`, `transfer_refused`. **Ctrl + the wheel** is answered in `_unhandled_input` before the body is: `_zoom_press` hands the notch to `camera_rig.zoom_by` and consumes the event, so the same wheel is a stab or an overhead without the modifier and the camera with it. A panel that owns the pointer is a full-rect `Control`, which eats the press before `_unhandled_input` sees it, and a soul between bodies has no boom to shorten |
| `scripts/warband/possession_camera.gd` (`PossessionCamera`) | adopts the mode's `Camera3D`, `follow(body, snap)`, `swoop_to(body, seconds)`, `rotate_view(delta_yaw, delta_pitch)`, `aim_ray()`, `follow_point()`. **Free look**: yaw wraps and pitch runs `LOOK_UP` -1.4835 .. `LOOK_DOWN` +1.4835 rad (85 degrees either side; the old range was -0.12..+0.95, seven degrees of sky). The view is a basis composed from yaw and pitch (`Basis(UP, yaw) * Basis(RIGHT, -pitch)`), not `look_at` with a world-up hint, because that hint is parallel to the view at a pole. Where the arc resolves the eye inside the body's own column (past ~70 degrees up, where the ground clamp holds the eye at `MIN_HEIGHT`), it slides out to `BODY_STANDOFF` 0.62 m along its own azimuth, probed against the world at the eye's height, so looking up is "past your shoulder" and never "through your own legs" **Zoom**: `Ctrl` + the wheel calls `zoom_by(notches)`; `zoom` is a multiplier on `FOLLOW_DISTANCE` clamped to `ZOOM_MIN` 0.36 (1.6 m over the shoulder) .. `ZOOM_MAX` 2.0 (8.8 m), `ZOOM_STEP` 0.86 per notch, and `boom_length()` is the one distance `_shoulder()` uses, so occlusion, the swoop and the shoulder slide are all measured off the zoomed boom. A notch snaps the boom (`_boom = -1`) instead of easing it at `BOOM_OUT_RATE` 3.5 m/s - that rate exists so a passing trunk cannot shake the frame, and a wheel that kept it would take two seconds to answer. `possession_regression.check_zoom` owns it |
| `scripts/warband/possession_sync.gd` (`PossessionSync`) | host-authoritative transfer RPCs plus `server_apply(peer, merc_id)` |
| `scripts/warband/combat_bubble.gd` (`WarbandBubbleManager`) | `setup(radius, exit_radius)`, `set_humans`, `track/untrack`, `sim_state_of`, `clear`, `sim_changed` |
| `scripts/warband/passive_duel_brain.gd` (`PassiveDuelBrain`) | `attach(body, opponent)`, `set_active`, `step(delta)` for fighter bodies (before `physics_step`) |
| `scripts/warband/downed_state.gd` / `crawl_to_safety.gd` / `revive_channel.gd` / `bleed_drip.gd` | `DownedRules.*` (including `bleed_fraction`, `drip_interval`, `drip_volume`), `CrawlToSafety.attach/manual`, `ReviveChannel.set_bodies/begin/tick/cancel/progress`, `BleedDrip.attach/detach/attached`. `ArenaActor.enter_downed` puts the rig in its prone drag pose (`Archer.set_downed`) and attaches one drip; revive and respawn clear all of it, `apply_snapshot` drives the same three things so a replica lies down and bleeds off the unchanged wire, and `_die` either clears it (arena seats) or holds the corpse - rig visible, lie kept, drip off - for the warband bodies flagged `warband_death`. Those bodies also never die from the blow itself and are finished by any blow that lands while they are down. `bleed_loss` is written from the 30 s clock every downed frame and is the only input the drip reads. |
| `scripts/warband/loot_vacuum.gd` / `warband_pickup.gd` / `corpse_loot_panel.gd` | `WarbandLoot.setup/spawn/quick_loot/sweep/pickups` plus the corpse registry: `register_corpse(enemy) -> int` (one read of `gear_items()`, stable ids, the record dies with the body), `has_corpse/corpse_ids/corpse_items/corpse_value/corpse_at/corpse_position/corpse_label`, `take_from_corpse`, `take_all_from_corpse`, `claim_corpse(id, peer = 0)` (silent, the AI's entry point). Every one of them books through the same `_book_piece()`, so a piece cannot be duplicated and peer 0 never dresses a body. `CorpseLootPanel extends WarbandPaperdoll` adds `open_corpse(loot, id) -> bool`, `showing_corpse()`, `take_piece`, `take_all` and `set_title`; `G` at a corpse opens it and `P` still opens the mercenary paperdoll. `SoldierLootRun.run(pickups)` now also jogs survivors to corpses and claims each once. |
| `scripts/warband/sacrificial_altar.gd` / `altar_menu.gd` | `SacrificialAltar.interact/in_reach/menu/controlled_merc_for` (the body: `_build_body()`); `AltarMenu.configure/page/show_page/anoint_rows/select_anoint_item/selected_anoint_item/anoint_button/press_anoint/unbind_rows/distill_rows/brand_rows/set_controlled`, two pages `PAGE_ANOINT` (every open lands here, and the rack leads with the copies of the body the soul is inside - `interact` reads it off `Warband.souls`, so the square opens on the steel the player is carrying; the bench is **one square** the piece is laid in, the reagent well and its held count beside it, the one brass ANOINT under them, and the altar's own words below - the spend, the skill the piece wakes, the annointments the copy already carries and the four bands of the die; a chip per carried piece whose pool is not empty only lays that piece in the square, `select_anoint_item` re-reads the stash on the press so a vial spent since the last paint refuses out loud, and the button works the square rather than a row) and `PAGE_ESSENCE` |
| `scripts/warband/warband_screen.gd` / `warband_paperdoll.gd` | roster screen with a per-row disposition chip (TANK / MELEE / BOW, cycled, the host's to set on a lent band) and `possess_requested(merc_id)`; mercenary paperdoll over the collective stash, whose worn slot line adds "Anointed - <SKILL> [key]" or, for a plain weapon, "Plain - the altar wakes <SKILL>", plus the brand line when branded; under the stage sits the ten-key **HOTBAR** row - click a skill, then the key it should fire from, or **KIT ORDER** to hand the keys back to the kit - saved with the body and refused on a lent band. The row names the body whose keys it is (`HOTBAR / ASH / THE BODY YOU CONTROL`, or `NOT YOUR BODY` when the stage is another name): the page opens on the body the soul is inside, that body's chip carries `· YOU`, and it follows the soul when the soul changes bodies (`controlled_merc`, `set_controlled`, `follow_controlled`). The bandage and the healing potion keep the last two keys (`9` and `0`) on every body and are not movable - the kit arranges the eight keys before them - so a dressing and a draught are always on the bar. `Contracts.SLOT_ORDER` lists the steel first - main hand, off hand, then the armour, then the trinkets - which is the order a body is armed in and the order an unwritten hotbar takes, and the block is cut to its ten keys (`HOTBAR_WIDTH`), so the header, **KIT ORDER** and the tenth key share one edge. Every item row answers hover with `scripts/warband/item_card.gd` (`WarbandItemCard`, handed out by `item_hover.gd`'s `Row`/`LabelRow` through `_make_custom_tooltip`): the name, type line, the catalogue's `summary`/`detail`, `ArmorData`/`TrinketStats` rows, the brand/anointing, the worth and the row's click instruction |
| `scripts/warband/warband_hud.gd` (`WarbandHud`) | four corner objects and the centre lines. **Bottom left, the soul**: a live bust in the ledger's iron clamp (`CharacterPreview` parked bust-framed on the rig's own `head_hitbox_center()`, re-dressed only when the body or its kit changes and rendered for a few frames), the name in Pirata, the state on the ledger's chip, health over stamina and the ten-key hotbar, laid out in the body's own key order, in the same iron plate - everything about the body the soul is inside, one object. **Top right, the band**: the purse (gold and the quiver) on the header rail, then a row per mercenary in the field - the disposition badge (`icon_sm_shield`/`icon_sm_blade`/`icon_sm_bow`), his name over that word, his health and his state - with the campaign ledger on its own plate under it. Rows are built once and painted in place, so a band taking hits repaints no textures. The centre keeps the reticle, the contextual prompt and the two banners; **there is no standing key line** (`set_hint` is gone, and so are the scenes' `hint_line()`s: the tips and the lesson cards teach the keys, and nothing repeats them over a fight) |
| `scripts/admin_arena.gd` + `admin_arena.tscn` | the gate scene: two three-body brawls 42 m apart, eight roster bodies, two souls, the altar, the stash chest, battlefield loot |

### Gate 1 result

`tests/admin_arena_regression.gd` - 90 checks, 0 failures: 10% far / 100% near,
real guards and swings in the passive brawl, a just-lethal hit Downing, a heavy
hit killing, a five-second human revive at half health with AI refused, the
value-sorted sweep, the altar wallet, the warband-screen click and the two-peer
body lock. `tests/warband_session_regression.gd` covers the real
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
| `scenes/cage_escape.tscn` + `scripts/warband/cage_escape.gd` | the **cold open**, deep in the wood: a ragged 40 x 52 m pocket (`YARD_HALF_WIDTH` 20, front -30, back 22) with no wall and no gate - a broken stake ring, three twig shelters, a fire ring, junk and trees standing inside it, and 170 m of ordinary forest (`CAMP_TO_ROAD_METRES`) before the trail's first torch. **Five cages scattered through the pocket** (`CAGE_POSTS`; the player wakes in `OWN_CAGE` 0) hold the warband; **every latch takes `G` with a blade inside `LATCH_REACH` 2.2 m, the player's own included**, and nothing opens on a possession or a kill. The ironwood shiv lies on the dirt right outside the own cage's door (`SHIV_POST`), taken through the bars with `K` while the clamp still holds the body, with two lit hand torches on the ground beside it; the gold shiv arrow rides that blade; the latch arrow rides the *nearest* shut cage; the run arrow rides the gap in the trees once the fifth latch goes. Two camp watchers sleep until the player is armed (`PAIR_LESSON_HEALTH` 21, `blow_scale` 0.5, `windup_scale` 2.4, no guard) and four more come out of the trees at the leaving. Cards and paragraphs are gone: `TIP_*` + `OPENING_TIPS` are one-line hints through `warband_tips.gd` |
| squad AI (`scripts/warband/squad_drive.gd`) | the one module both areas share: a freed prisoner arms itself from the nearest drop (booked by `WarbandLoot`, worn via `auto_equip`, re-dressed with `refresh_gear`), then runs at the nearest watcher and fights on layer 2 through one explicit ladder - close / swing / guard / circle / reset - resolved on every frame, with the exchange rolled once when the blade frees (55-70% guard for 0.35-0.80 s, guard dropping into the blow), 1-3 swings then a 0.25-0.55 s short rugged circle re-rolled per step, and only `sword`/`dagger` allowed to guard. **A bow is the squad's long arm**: an ally holding one takes the nearest hostile as far as its own shaft flies (`BOW_FLIGHT_SECONDS` 0.55 s of flight - 26 m twig bow to 56 m longbow, `_bow_reach`), so the 34 m `engage_radius` stays the blade's rule and is never the archer's leash; a target past `engage_radius` is taken only down a clean line (`_clear_shot`: world geometry on layer 1 from the body's chest to the target's - the band's own bodies are not in a shaft's way, `PROJECTILE_HIT_MASK`). `_fight_watcher` then looses where it stands at any range inside the reach instead of advancing to `_standoff_for` first, sighting the shot with `_shot_point` - the target's own walk carried forward and the arrow's own `Arrow.GRAVITY` drop lifted back in over twice-solved flight time - and the beat between shots is spent standing beyond `BOW_HOLD_MIN` 5 m, circling inside it. **A quiver with nothing in it is not a weapon**: `_dry_bow` makes the bow body no longer `_armed` (so its errand is steel, exactly like a body with bare hands), and `_keep_bow_range` makes it give ground out of a blade's measure and plant at its own instead of circling a hostile it can never hurt. **A body's disposition** (`Contracts.DISPOSITIONS`, read off the roster every frame by `_disposition` -> `profile_of`) is the same ladder with four intentions in it: `TANK_PROFILE` is up behind a guard (0.92-1.0 of exchanges, 0.45-0.95 s), advances and waits at contact behind it (`_advance(.., keep_guard)`), and never falls back (`withdraw` 0); `MELEE_PROFILE` guards 0.40-0.55, takes its stance from `_close_step`, and falls back below `WITHDRAW_SHARE` 30% (`_withdraw_step`: away from the nearest hostile at a jog, bounded by `WITHDRAW_SECONDS` 8 s, until `_clear_of_hostiles` opens the bandage channel), going at the densest knot (`_densest_of`, the nearest `CLUSTER_CANDIDATES` 3 weighed by `MELEE_CLUSTER_PULL`); `BOW_PROFILE` gives ground when crowded or freshly wounded (`_kite_step`: a jog away to `BOW_HOLD_MIN` + `BOW_KITE_MARGIN`, never out of its own reach, never across a drawn string) and walks the band's back rank (`_escort_post`, one `FORMATION_ROW_GAP` behind the melee wall). `_cast_step` spends the disposition's skill order (`Contracts.disposition_ability_rank`) on the two extra rules of the same table: a tank's ward and shield first, a melee body's ring only on `CAST_TARGETS` 2 hostiles inside 3.2 m, a bow's volley down a clean line, on a cadence of `cast_every` seconds. On the roster screen each row carries a chip whose press is `Warband.cycle_disposition`. A trunk across the line or a target past the bow's reach falls back to the close ladder. Escort clause when nothing is hostile; the field is stripped once `_clear_of_hostiles` at the drop or corpse (22 m), drops through `quick_loot` and bodies through `register_corpse`/`corpse_at`/`claim_corpse`. The player's own body is never driven. **The party's mode** (`party_mode`, handed in by the world from `Warband.party_mode` every frame) decides which watchers are its to fight: OFFENSIVE any inside `engage_radius`; DEFENSIVE only one on the band's book (`_provoked`) - a hostile that struck a band body, soul's included (`WarbandBody.note_attacker` → `struck_by` → `note_struck`; the scenes' three blow handlers and `arrow.gd` name the striker before the blow lands), or whose `last_hitter` is a band body's `slot` (`_note_wounds`, so the soul's own first cut starts the fight; a wound from outside the band, like the town watch's arrow, does not); PASSIVE none, and no arming or stripping errands either - the escort only. The book is kept in every mode and dropped by `relocate()`; the rescue and the bandage are the same in all three. |
| `scripts/warband/cage_watcher.gd` (`CageWatcher`) | the wood's **three creatures** (`extends ForestMob` → `DevilMob`), one species per body: the Hollow warden, the Ossuary stalker and the Gallowsroot. Each is the wood's silhouette to look at and a **human to fight** - `scripts/warband/watcher_visual.gd` puts the creature's own skin on the warband's `Archer` rig, so the body walks, runs, cuts, guards, flinches and falls on the ranger's authored clips. `WATCHER_PROFILES` is the three species' gameplay (the forest's own health, damage, reach, speeds and cadence), `PAIR_HEALTH` 31 / `HARDENED_HEALTH` 71 (the scene owns the pool), `WATCHER_LAYER` 2, pack `camp_watchers`, sight 60. A deterministic 12-entry `VARIANTS` table (seeded by `mob_id` + the node's ordinal, and walked **inside the species**) varies a paint multiplied into the creature's own PBR surfaces, a uniform silhouette scale 0.88-1.30, a main hand from `MAKESHIFT_TIER`, a favourite swing, a guard share and a crouch; its rows are interleaved so consecutive ordinals come back as a mixed squad. **The hit capsule's height follows the build** (`profile.height` × the silhouette; the girth stays the profile's radius, so spacing and reach do not drift): held at the species' own height, a 1.16-1.30 body drew its head - and the Rustcoat its chest - above the capsule every arrow, thrown blade and swing stops on, and a shaft through them flew on untouched. `arm(item_id)` arms the rig's own weapon slot, so the piece in the hand is the catalog model the warband holds (`sword.gd`'s club and branch, `dagger.gd`'s shiv, `bow.gd`'s twig bow) gripped by the hand bones and carried by every clip; `take_weapon_item()` strips it and `gear_items()` lists the blade plus the worn salvage. Per windup it picks one of the three authored cuts (overhead / diagonal slash / dagger lunge); one guard roll per exchange (`guard_chance()` = variant share × `guard_scale`, capped 0.9) holds the authored block loop instead of trading, then drops into the swing; any blow at or above `max(STAGGER_FLOOR 6, STAGGER_SHARE 10 % of health)` plays the rig's recoil and cancels swing and guard; a crouch-armed body rests in the rig's crouch, folded `CROUCH_AMOUNT` 0.62 deep. The three scene dials (`blow_scale`, `guard_scale`, `swing_gap_scale`) weight the blow, the guard share and the cooldown; the strike emits `attacked(self, profile damage × blow_scale, victim)` and a death emits `defeated` exactly once |
| `scripts/warband/watcher_visual.gd` (`WatcherVisual`) | one `Node3D` per watcher between the mob and its body, answering the creature sampler's whole API so no scene changed with the cutover (`set_motion`, `set_combat`, `set_poise`, `die`, `held_item`/`set_held_weapon`, `attack_names`/`attack_clip`/`block_clip`/`stagger_clip`/`crouch_clip`, `has_clip`, `set_tint`/`tint`, `head_hitbox_center`/`head_hit_profile`, `blood_anchor`, `strike_hand_position`, `set_distance`, `set_parked`). It builds the `Archer` rig with `body_skin` = the species' skin and `heading_locked` (a watcher holds its quarry, not its walk direction), dresses every skin surface with a per-body copy of the creature's material and the variant's tint, and drives the fight: a windup calls `begin_melee` with the variant's cut then `retime_melee` to `(windup + strike × 0.34) / BLADE_IMPACT_SHARE` so the strike window opens on the frame `DevilMob` resolves damage; a stagger cuts the swing with the rig's flinch; a bow windup draws and `release_bow()` looses the visual string; death hands the skeleton to `CorpsePhysics.start_limp`. `set_distance` stops the rig past `MobLod.ANIMATE_DISTANCE` (shadows past `SHADOW_DISTANCE`) and `set_parked` stops it entirely while `MobCuller` has the body asleep |
| `scripts/warband/warband_tips.gd` (`WarbandTips`) | the one hint channel: `tip(id, keys, text, seconds)` paints `LedgerKeycap` tiles beside one command, fades on its own clock, and never opens twice. `current_keys()`/`current_text()`/`has_shown()` are what the regressions read. The modal `TutorialCard` and every paragraph it carried are **deleted** |
| `scripts/ui/keybind_page.gd` (`KeybindPage`) | the CONTROLS sheet: the whole keyboard drawn from `LedgerKeycap` tiles (ESC + F1-F12, digits, QWERTY, the bottom row) plus the mouse cluster, every bound key washed blood and every dead one left as bone, and one blood arrowhead per action ending on the action's label (`leaders()`/`action_rect()`). Board units are scaled to the page, so a narrow window shrinks the board instead of stacking labels on keys. Hosted one page deep by `pause_menu.gd`, `warband_menu.gd` and `ui/settings_menu.gd`; `keybind_screen_regression` owns it |
| `scripts/warband/duel_lesson.gd` (`DuelLesson`) | the first fight, four facts and four tips: `MOVE` (an unarmed freed body walks to the blade, woken with `wake()`) -> `FETCH` (it stands on the shiv) -> `FIGHT` with the **cuts** tip raised on the same frame the blade enters the hand (the pair may wake from there, and only there) and the **guard** tip on the second watcher's first windup, then `DONE` on a guarded blow or on the pair falling. The camp's ordinary opening takes the shiv through the bars before the door, so the scene enters the lesson on an armed body and jumps straight to `FIGHT`. No scene lookups: the camp feeds facts and shows the tips `tip_wanted` asks for; every transition is guarded and every fact counts once. `duel_lesson_regression` owns the order |
| `scripts/warband/tutorial_sequencer.gd` (`TutorialSequencer`) | `CAGED -> LOOSE -> FREEING -> WARBAND -> ESCAPING` (there is no TOWN state: the opening ends where the road does); `CAGE_COUNT` 5, `GUARD_COUNT` 6 (the pair + the four at the leaving); **the shiv behind the bars** is booked first (`note_armed()`, which turns the CAGED line from the pickup to the latch), **the player's own latch** is cut first (`note_cage_opened(OWN_CAGE)`), the step away from the cage is `note_looked_around()`, four more latches are `note_cage_opened`, and the fifth is `WARBAND`; objective only - one short line; the per-beat key is the tip the camp raises, not a second string here. Out-of-order calls refused |
| `scripts/warband/branded_runner.gd` (`BrandedRunner`) + `branded_fx.gd` | the six sigils: Arrow Barrage, Shockwave Cleave, Rending Strike, Ember Storm, Hellfire Cone, Blood Ritual Ward; tier scaling, stamina, cooldown, refusal reasons |
| `scenes/town_hub.tscn` + `scripts/warband/town_hub.gd` | dusk square, campfire, stash chest, altar, recruiter desk, gate; `interact_at(peer, point)` resolves the nearest service; one `scene_requested` door |
| `scripts/warband/expedition_gate.gd` (`ExpeditionGate`) | `prompt`, `deploy_and_launch(ids)`, `return_to_town()` |
| `scripts/warband/cultist_guard.gd` (`CultistGuard`) | crimson cultist body, faction filter so guards never fight each other, no arena respawn |
| `scripts/warband/enemy_waves.gd` (`EnemyWaves`) | deterministic waves (3, +1 per wave, capped at 6) with escalating kits, `wave_started/wave_cleared`, `guards()`, `field()`, `living()` |
| `scripts/warband/soldier_loot_run.gd` (`SoldierLootRun`) | survivors physically jog to the drops **and to the bodies**, then the vacuum books each piece into the shared stash exactly once |
| `scripts/warband/warband_session.gd` (`WarbandSession`) | real ENet host/join, body ownership broadcast, 20 Hz body snapshots, guest prediction, AI fallback on leave |
| `scripts/warband/quartermaster_menu.gd` (`QuartermasterMenu`) + `Warband.buy_gear` | base pieces and arrows (priced and sold by the bunch) bought with gold into the collective stash; the same keeper price the stash sort uses |
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

The title is **four doors and nothing else**: **NEW CAMPAIGN** (a campaign name,
then `GameFlow.start_campaign()` - a fresh warband, a fresh purse, the cages, in
a campaign folder of its own), **CAMPAIGNS** (the save-slot ledger, newest first:
every campaign this machine has saved, each row naming the roster it holds, the
bookmark it would open and when it was last played; a row calls `enter_warband()`
on that campaign), **JOIN GAME** and **HOST GAME**. A campaign is a folder
(`SaveSlots`, below), so a door that starts a campaign can never write over one
already saved. Host Game asks one more question, on two buttons: **NEW GAME**
(`host_campaign(port, name, HOST_NEW)`, a fresh warband in the cages in a campaign
of its own, named after the host) and **FROM CHECKPOINT** (`HOST_CHECKPOINT`, the
campaign the panel's selector names, on its bookmark - or the town end when it has
none), with a line under them saying what that checkpoint would open. There is no
skip-tutorial door, no frontier door and no arena lobby on the title any more:
those scenes are reachable through their own launchers (`Arena.cmd`,
`Host World.cmd`) and the title is the campaign.

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
- The paperdoll's stash list shows unequipped copies only: a worn piece is on its
  wearer's slots. Handing one over is two clicks - its worn slot puts it back in
  the pool, then its stash row dresses the selected body. A right-click on a free
  row holds that item id back from every automatic equip (the row says `HELD`);
  a left click still wears it by hand.
- A row's tooltip is the piece, not an instruction: hovering any item row (worn
  slot, stash row, corpse row, delve pouch, loot window, keeper stock or altar
  list) opens `WarbandItemCard`, built from the catalogue's `summary`/`detail`
  and the table that owns each number. The click instruction is the card's last
  line, so a row can never lose its details to make room for it.
- `Warband.arm_warband()` is the band's own dressing. It walks every body the
  field can reach and fills each slot that is empty or still wearing the naked
  set with the dearest legal, unheld spare in `field_stash()` (the off hand by
  stance first, then price - see `Contracts.disposition_off_hand_rank`). It runs
  as a purchase lands (`buy_gear`), so a shopping spree is felt on the bodies; a
  real worn piece is never upgraded, a two-hander never costs an occupied off
  hand, a piece the body's trade refuses never fills a slot at all
  (`Contracts.disposition_refuses_gear`: a melee body leaves the band's spare bow
  in the pool rather than carry what it cannot swing, the pool keeps it for a
  body that draws it, and a tank refuses a two-hander outright - both hands on
  one hilt would lock the shield out of the other hand), and one `changed` plus
  one `armed(merc_ids)` covers the whole pass (`armed` re-dresses exactly those
  live rigs through `PossessionController`).
- `Warband.reequip_merc(id)` is the deliberate re-kit the arming pass is not: the
  arming pass only fills what is empty, this hands a dressed body back. Every real
  piece it wears - both weapon sets - goes into `field_stash()` first, then the
  same choice the pass makes fills the slots again (`_fill_slots` over
  `DRESS_SLOTS`), so a tank comes back in a shield and a one-hander, a bowman in a
  bow, a melee body in the greatsword, and a heavy cuirass beats the salvage tier
  it was wearing. `EquipmentRules.bare_garment` pieces stay on the body: they are
  the mesh the rig draws, not gear, and the fill trades them for real armour. A
  body carrying a second weapon set keeps one (`_refill` fills the set in its
  hands, swaps, fills the other and swaps back). A lent warband, a body outside the
  party and a body that is down are refused with the kit untouched, and the pool is
  worth the same number either side of the press. Answers `{ok, merc_id, released,
  fitted, message}`.
- `Warband.reequip_warband()` runs that over every dressable, living body in two
  loops on purpose: every kit goes back into the pool first, then the roster is
  dressed **one body at a time in recruitment order**, so the oldest name takes the
  pick of the one pool and the next one takes what is left. One `changed` plus one
  `armed(mercs)` cover the pass. Answers `{ok, mercs, released, fitted, message}`.
- The paperdoll's **RE-EQUIP** (under the ranger, naming the body it would hand
  back) and **RE-EQUIP THE BAND** (in the header) are the buttons for those two
  verbs. Both hide on the corpse screen, which shares the same panel.
- `Warband.restrict_auto_equip(item_id, true)` is the player's override: the id
  is held back from `arm_warband`, `dress_recruit` and the loot pickup
  `auto_equip`, for every copy at once, while a manual `equip_merc` is untouched.
  The holds ride the save under `auto_equip_restricted` and are released with
  `restrict_auto_equip(item_id, false)`.
- `Warband.auto_equip(id, item_id)` (used by `WarbandLoot` on a hand pickup) puts
  a looted piece straight into the soul's hands when that slot is empty or the
  new piece is worth more than what is worn there; anything else stays in the
  stash. The post-battle sweep never auto-equips.
- A looted or paperdoll-equipped piece is pushed onto the **live rig** with `PossessionController.refresh_gear(merc_id)`. `seat_loadout()` is the spawn snapshot (the wire shape); using it to re-dress a body silently kept the old kit, so a squadmate "carried" a sword it never drew and `begin_melee` refused it. Cage, arena and town all use `refresh_gear`, and the ally driver re-dresses a body whose roster says armed but whose hands are empty.
- Arena bodies are born with `combat.target_mask = 4` (other fighters). The camp's watchers are wilderness mobs on layer **2**, so the cage sets its squad's mask to 2: their blades bite the watchers and cannot cut the squad itself. Any scene that puts mobs and warband bodies in one fight needs the same line.
- No scene names its keys on a standing hint line any more (`WarbandHud.set_hint`
  and the scenes' `hint_line()`s are deleted): a tip plaque carries a key and a rule
  at the thing it is about, and the one prompt line says what the body can do
  here. A key legend under the crosshair was a second copy of both.
- The opening fight is the player's: taking Corvin hands over empty hands, the
  shiv lies on the dirt outside the cell door - taken through the bars (`K`) and
  used to cut the latch (`G`) - and the two camp watchers wake once the armed body
  leaves the cage. Six more come out of the wood at the leaving, each carrying a
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
carries the bookmark (`Warband.checkpoint`, in the save since version 4):

| Id | Written when | Resume puts the squad |
| --- | --- | --- |
| `trail_start` | the camp's six watchers are dead and the leaving has happened (the tutorial is over, the run starts) | 60 m past the camp mouth, on the road, cages already open |
| `town` | the soul's body first enters Hearthstead's square | the town's own spawn posts, square services live |

The bookmark only ever moves forward through `WorldScene.CHECKPOINT_ORDER`
(`trail_start`, then `town`): a session that played the opening still reads its
camp as cleared, and comparing against the current id alone rewrote `trail_start`
the frame after the square wrote `town` - the status line flipped between the two
labels and the save hit the disk every frame. The trail's `REACH THE TOWN · n m`
prompt counts down to the square's ring (`TownHub.metres_to_square`) and is gone
inside it; counted to the gate arch it reached zero outside the wall and climbed
again across the square.

### One campaign, one folder

`SaveSlots` (autoload, `scripts/warband/save_slots.gd`) is the ledger of the
campaigns on this machine. `user://saves/index.json` holds `{version, active,
slots:[{id, name, created, played}]}` and `user://saves/<id>/` holds that
campaign's `warband_state.json` and `player_state.json`. Nothing else in the game
knows about folders: `bind(id)` points `Warband.save_path` and
`PlayerState.save_path` at the campaign (and reads that campaign's purse), so
every writer that already existed - the autosave, a bookmark, a purchase, an
equip, the in-world SAVE GAME - writes that file with the code it always had, and
cannot reach another campaign. `new_slot(name)` makes a folder and a row (a
repeated name takes a number: "Alex", "Alex 2"); it is what NEW CAMPAIGN and a
hosted NEW GAME call, which is why starting a campaign cannot overwrite one.
`summaries()` is what the title lists - each row peeked with `peek_save`, so it
can say the roster count and the bookmark without loading a warband - and the
`played` stamp is the wall clock but always later than every stamp in the ledger,
so two campaigns started in the same second still list in the right order (and a
clock set backwards cannot reorder them). `migrate_legacy()` adopts the single
`user://warband_state.json` (and its purse) that a build before the ledger wrote:
it moves both into `user://saves/c1/` once, and only when the ledger is empty - a
ledger with any row in it never migrates into. A script-mode run (a regression, a
capture) uses `user://saves_test` and never migrates at all.

`Warband.save_checkpoint(id, area, position, label)` writes the roster, the shared
stash, the Cruor ledger and the bookmark in one `<campaign>/warband_state.json`
write, so a load can never point at a state the file has not held. `sanitise_checkpoint()`
is the only reader (hand-edited or older files drop the bookmark, never half-read
it), and a v3 file simply resumes at the town as before. A wipe calls
`GameFlow.retry_checkpoint()` after `WIPE_BEAT`: the warband reloads, bodies that
were down wake at half health, the dead are not in the file at all (a death takes
its record out of the roster on the frame it happens), and the **purse is not
rolled back** (it belongs to `PlayerState`, and a reload must not replay a
payment). With no bookmark - the opening - the wipe still has no way back. The
title's **CAMPAIGNS** list opens a campaign on its bookmark; **NEW CAMPAIGN** is
still always a new campaign, in a folder of its own. `tests/checkpoint_regression.gd` owns
the whole contract, including the two real world resumes.

### The field and the reserve

The roster can hold more names than the field: `deployment_cap` (8) is the most
bodies standing at once, and a record whose `reserve` flag is set is sworn,
dressed and saved but has **no body**. The rules:

- A name sworn while the field has a place takes it. `Warband.add_mercenary` and
  `Warband.hire` set the flag from `field_room()` at the moment of the oath, and
  `WorldScene._sync_field()` spawns a body for every fielded name that has none on
  the next physics frame: a hire musters at the town's fire ring, a soldier cut
  out of a cage stands up where he walked out (`note_soldier_freed(name, at)`),
  and the body is wired and in the squad at once (`_adopt_body`).
- Past a full field a new name waits in the reserve; his cage figure fades with
  nobody in its place, the HUD says he waits in the town, the squad rows leave him
  out and the roster screen shows **RESERVE** with CONTROL disabled.
- The reserve is only called up in the town: while the party's focus body stands
  in the square and the field has room, `Warband.deploy_reserve()` gives the
  longest-waiting name the place (`_call_up_reserve`).
- A load balances the books (`Warband._balance_field`): a file fielding more
  names than the cap steps the newest back into the reserve, and an empty field
  takes the reserve's oldest, so every load stands the warband up inside the cap.
  A lent co-op copy is never rebalanced - it is the host's books - and a guest
  spawns a replica for every fielded name it has no body for, which the host's
  snapshots then place.

### The newer surface (skills, menu, keepers, wolves, co-op)

These landed on the same world without a second rulebook. Each has one owner:

- **Item skills are still data, and stock steel is plain.** `AbilityRules` is the
  only definition table, and `AbilityRules.granted(rig)` grants a hand's skill
  (slot 0 the main hand, slot 1 a shield in the off hand) only when
  `rig.anointed[hand]` names it — in every mode. A body's hands are anointed by
  the altar: `PossessionController._apply_gear` passes
  `cruor.anointed_among([main, off])` to `SeatLoadout.apply(rig, loadout,
  anointed)` (a trusted local argument, never read from the possibly-remote
  loadout dict), `PlayerState.build_loadout(..., anointed_ids)` resolves each
  listed piece through `AbilityRules.skill_for`/`hand_slot`/`stock_item`, and
  `Archer.apply_loadout` rewrites `Archer.anointed` from `loadout.anointed`.
  `Warband.annointed` makes the controller `refresh_gear` every body holding the
  piece. **Annointments** are the wider half of the same path: `Warband.annoint`
  rolls the altar's die on one copy, the ledger answers
  `annointment_stats`/`annointment_skills`/`annointment_procs` for a body, and
  the controller hands all three to `SeatLoadout.apply(..., annoints)` — the same
  trusted-local rule, so no replica can claim a modifier its steel was never
  given. Stats land in the rig's own `trinket_stats` dictionary (so `attack_rate`,
  `move_scale`, `damage_reduction` and the rest read them for free), skills land
  in `rig.anointed`, and procs are armed on the body's `AnnointRuntime`. An empty main hand still grants the unarmed Charge, and the trinkets'
  grants are worn, not anointed. The warband's scene half is one
  `WarbandAbilities` node in `world_scene.gd` (`setup(world, controller)`,
  `bind_body(actor)`), which turns the possessed body's own `AbilityRunner` cues
  into arrows, spells, the backstab blink/stab and blade presentation, on the
  authority only. The keys are **plain 1/2/3** (Shift+1..3 is the same press —
  the tiles' shared `SHIFT + n` caption is rewritten), and the soul's plate shows
  stamina over the three slots from that body's runner every frame.
- **The cover peek is RMB, in cover only.** Outside cover the same press is the
  guard; the lean ends on release, and leaving cover with `F` drops it. A bare
  guard that stops a blow is **spent**: `Combat.break_guard()` drops it and the
  player presses again for the next blow, so one raised guard buys one block and a
  crowd cannot be stood off by holding a button (a parry inside
  `Combat.PARRY_WINDOW` 0.25 s is a deflection, not a block, and keeps its guard).
  **A shield is the exception**: `WarbandBody.receive_melee` charges the pool
  `Combat.SHIELD_BLOCK_STAMINA` 18 for the blow and leaves the arm where it is, so
  a shield can be blocked on blow after blow until the pool runs out - the pool is
  the wall's whole price, and the same rule holds for the squad's tanks. Holding a
  guard drains `Stamina.GUARD_DRAIN_PER_SECOND` 20/s - faster than the pool's 13/s
  regen, and on top of the block charge - and a body under `Stamina.GUARD_MIN` 25
  cannot raise one at all, so a spent guard cannot be clicked back up.
  `SquadDrive._raise_guard` asks that same floor before an ally's arm goes up.
- **Sticky movement is a press, never a contact.** `F` sticks only to a surface
  inside the frontal cone (`CoverMovement.STICK_ARC`), so a tree behind the player
  is not cover; nothing attaches while walking, and the body comes off when the
  input points to the far side of the surface the press took (`stick_normal`), on
  jump, roll, step, blade, death or lost support. Only a fresh `F` puts it back.
- **Escape is `WarbandMenu`** — six rows (resume, save, load, settings, exit,
  quit) and, under RESUME, THE PARTY: three mode toggles (`party_buttons()`; a
  press is `Warband.set_party_mode`, the lit one is the warband's mode and follows
  `changed`, and a lent warband's press is refused on the status line). One
  ledger frame (500 x 840), the shared sound page. It never pauses the tree, and
  `world_scene` closes it, then an open panel, then opens it.
- **A body's disposition is the roster's own chip**: each mercenary row carries
  TANK / MELEE / BOW beside its gear line, a press is `Warband.cycle_disposition`
  and the answer goes on the status line, and the row repaints from the record so
  the chip and the squad's brain cannot disagree. A real change also re-fits the
  hands: pieces the new trade refuses - the greatsword a melee body was wearing
  when the player makes it a tank - go back into the shared stash and the slots
  are filled again by the arming's own choice (`_release_refused_hands`), so the
  chip never renames a body still holding the kit its old trade wanted. The field
  is on the record, so
  it saves, loads and lends with the band; the squad HUD rows print it too, and a
  lent warband's chip is disabled rather than lying about who obeys.
- **`B` steps the party's mode** in play, menu or no menu: `Warband.cycle_party_mode`
  walks OFFENSIVE, DEFENSIVE, PASSIVE and round again (a lent warband's press is
  refused the same way), the answer goes on the status line, and the squad list
  carries a `PartyMode` line - `PARTY  DEFENSIVE  ·  B changes it` - that follows
  the books. The CONTROLS sheet lists it as PARTY MODE.
- **The three keepers are one board.** `VendorMenu` is re-pointed per seat
  (`vendor_orla`/`vendor_brann`/`vendor_vey`); `Warband.buy_gear` buys into the
  shared stash and `Warband.sell_gear` sells one pooled spare out of it for 60%.
- **The wolves are the base mob.** `WarbandWilderness` places eight `enemy.gd`
  **kind 0** briars in exactly two deep-wood packs of four — no new class, no stat
  table — gives each pack one `MobWander` territory, and parks walked-past ones
  with its own `MobCuller`. There are no wolves on the lane or the camp corridor:
  the packs live 30-50 m off the route, beyond the wolves' own sight of it and
  hundreds of metres apart, so a body only meets one by leaving the trail.
- **Co-op plays one warband, the host's.**
  `GameFlow.host_campaign`/`join_campaign` reuse `WarbandSession`, and the title's
  JOIN GAME connects **before** the world opens: the host answers with its whole
  campaign (`receive_campaign`), the guest lends it (`WarbandState.lend`) and
  fields exactly the host's bodies as replicas, then says `field_ready` and is
  seated in the first free body. The lent copy is read-only on the guest - every
  gear and purse verb answers `LENT_MESSAGE`, `save_state`/`load_state` refuse -
  and the host mirrors every change back (`receive_warband`, 0.25 s at most), so
  the roster, stash, purse and orders on both screens are the host's. The host
  owns the mobs (15 Hz, name-keyed snapshots, and every guard a guest holds is a
  replica that runs no AI), the loot, the missiles and the kill. A guest writes no
  checkpoint, works no keeper, latch, corpse or pickup, and runs no squad AI; its
  TAB and revive travel as intents (`swap_set`, `revive`) and are resolved on the
  host's field. The arena bout still exists in `admin_arena.tscn` for its own
  launcher, but the title no longer offers it.
- **With one body left, the soul inside keeps it.**
  `SoulRouter` stays one peer per body; a death ejects the soul, and
  `WarbandSession` seats it only into a **free** body. Nobody is moved out of the
  last body: the waiting soul watches it (`PossessionController.watching()`, a
  free-look eye on the other player's body, `WarbandHud.set_watching` naming the
  holder) and takes the next body that comes free, in the order the souls lost
  theirs.

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

### Every drop is his own

Drops are paced, the stash is shared and eight men wear the same five pieces, so
a look that stops at the face leaves a band in uniform. The armour is the man's
too: `WarbandFlair.profile_for(id)` (`scripts/warband/warband_flair.gd`, the same
pure function of the id, memoised like the look) decides what he does to whatever
he is wearing.

| Where it comes from | What it changes |
| --- | --- |
| `FIELDS` (nine medieval dyes, each with its own charges) | the **field** his cloth is dyed and the **charge** the design is drawn in. A charge is always a tincture that reads on that field, so a design is never invisible |
| `DESIGNS`, `MOTIFS`, `HEMS` | fifteen heraldic designs (partitions and ordinaries: per pale, quarterly, chevron, saltire, chequy, barry, lozengy...), eight devices (skull, crossbones, sun, crescent, star, eye, antlers, rune) and six borders (band, double, zigzag, beads, stitch, crenel) |
| `THREADS`, `FITTINGS`, `LEATHERS`, `BONES`, `FEATHERS`, `FINISHES` | the embroidery thread (and whether it is gilt), the metal of every buckle and rivet, the stain of every strap and boot, how his bone is treated, the feathers he hangs, and what he has done to his steel: bright, blackened, russet or blued |
| `trophies` | `[{anchor, kind}]`: skulls, beast skulls, bird skulls, jaws, finger bones, vertebrae, teeth, claws, feathers, rags in his livery, shoulder spikes, ribs, a long bone, bone beads, ankle rattles, a horsehair plume and a pair of horns, hung at the belt, the hips, a temple, the crown, a shoulder, the neck, the wrists, a thigh and the ankles |

The livery **steps** with the id and the rest is hashed, so a deployment of eight
wears eight fields, eight designs and eight devices, and a tenth man wraps the
palette rather than running out.

`ArmorFlair` (`scripts/armor_flair.gd`) puts it on the body. One body's kit, one
pass of `dress()` whenever the kit changes:

- **Rest space on the vertices.** Each worn armour mesh is swapped, once per
  session and shared by every body, for a copy that carries each vertex's
  skeleton rest-space position in `CUSTOM0`. The Compatibility renderer skips the
  shader stage for unskinned meshes, and a skinned material would otherwise see
  *posed* positions, so a stripe drawn in view space would slide across the
  chest through a swing, a roll and a ragdoll. Rest space does not move; the
  design stays where it was sewn.
- **One material per worn surface**, a `ShaderMaterial` of
  `scripts/world/shaders/armor_flair.gdshader` numbered by what the surface *is*
  (`ArmorFlair.ROLES`): cloth, lining, the ranger outfit's atlas, leather, hide,
  plate, mail, steel edge, fittings and bone. The authored `StandardMaterial3D`
  is mirrored exactly (albedo map and colour, roughness and metallic maps on
  their own channels, the normal map and its depth) and the flair is laid over
  it, so nothing the artist authored is lost. Surfaces outside `ROLES` - skin,
  the naked shirt and shorts - are left to the look.
- **The weave without the colour.** Every role divides the authored map by the
  mean luminance of the texels it re-colours (`material_stats`, cached per
  material), so a dyed coat keeps its weave, its grain and its grime. The ranger
  outfit is one atlas split by hue: its green cloth takes the livery, its brown
  takes the stain, its bare metal keeps its finish, and its skin patch stays
  skin.
- **The borders ride measurements, not guesses.** `piece_edges` measures each
  set's piece once (the hem of a coat, the end of a sleeve, the cuff of a glove,
  the top of a boot) and the shader sews the border that far in from the edge -
  so a plate tasset gets one too, and a piece with no edge of a kind gets none.
- **Steel and hide get the treatment their material allows**: gilt or latten
  trim along the open edges of plate and mail, a livery **surcoat** drawn over
  mail or plate plate on the trunk (with its own thread border) for the men who
  chose one, the device **painted** on bright plate and **daubed** on the salvage
  set's hide, worn through where it was rubbed.
- **Trophies** hang from a `BoneAttachment3D` per anchor, placed on the measured
  outer surface of whatever is drawn there (never at the anchor) and shown only
  while that slot wears a real piece: a bare body carries nothing. A ring trophy
  (necklace, bracelet, rattles) ties round the **measured cross-section** of the
  neck, wrist or ankle - an oval, because a neck is wider across than deep - and
  the geometry is one merged mesh per trophy, no shadow, no collider.

Cost: the first body pays ~35 ms (mesh copies and the veil measurements are then
shared), later bodies ~12 ms, a full five-piece dress of a set ~1-6 ms and a
single piece swap ~0.1 ms. Everything is presentation - nothing about a flair
reaches the save, the wire or any stat.

`tests/armor_flair_regression.gd` holds it (475 checks: determinism and
distinctness, every authored armour material given a role, the rest space equal
to the mesh's own vertices and shared between bodies, per-body materials, the
measured edges, the trophies shown only with a piece and measured onto the
surface, the oval necklace, and a body with no look left untouched);
`playtest/armor_flair_lookbook.gd` renders the band in one kit per set, and
`--plain` renders the same men as the warband dressed them before.


Short version of the latest tuning (all in the code, all covered by
`tests/cage_escape_regression.gd`):

- the fifth prisoner is **not** forced into the soul; the player takes him (F5 /
  `[` / `]`), and taking him opens nothing - a latch is cut with a blade;
- the shiv lies on the dirt outside the player's own cage, so the first two beats
  are the pickup through the bars (`K`) and the own latch cut with it (`G`); two
  lit hand torches lie on the ground beside it;
- each of the four remaining latches is cut **individually with G**, standing at
  that cage with a blade in hand (`LATCH_REACH` 2.2 m); bare hands are refused
  with a status line, and nothing opens on a possession or a kill;
- once all four are cut the freed squad arms itself off the ground and attacks the
  watchers on its own, silently, through the shared squad ladder;
- watchers are rigged, varied bodies on the warband's own rig (see the
  `CageWatcher`/`WatcherVisual` rows), they hunt the nearest standing body, and
  **four more come out of the trees** as the squad leaves the camp - one of each
  of the wood's three creatures and a second warden;
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
  slot will ever wear it). Every watcher carries one as `carried` gear, and one in
  three also carries a vial of its own ichor (`ichor_slot()` is a pure function of
  the body's id and ordinal, so the same body always carries the same kit), so
  both reach the shared stash through the corpse registry like any other loot.
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
- **the watcher swings the thing it is holding**: the creature's authored attack
  clips raise the arm and then *hold* it, so played straight the club sat over the
  head and the blow landed with no motion. The camp's watchers no longer play
  those clips at all: they stand on the warband's rig, and a windup calls
  `Archer.begin_melee` with the variant's cut and then `retime_melee` so the
  swing's strike window (`(duration - cut) * 0.55` into it) opens on the frame
  `DevilMob` resolves damage (`windup + strike * 0.34`) - `BLADE_IMPACT_SHARE`
  0.55 and `STRIKE_DAMAGE_SHARE` 0.34 in `scripts/warband/watcher_visual.gd`. The
  clipboard of a full swing travels ~2 m and comes down below the shoulder;
  `tests/watcher_variants_regression.check_swing` measures the travel, the drop and
  the impact frame. The frontier's own creatures keep `devil_mob_visual.gd` and
  its `SWING_COCK`/`SWING_THROUGH` arc, which is what the cages used to use;
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
  release. **A body with no soul in it does not crawl at all**: `manual` false
  returns from `CrawlToSafety._physics_process` before the step, so an AI-driven
  squadmate holds the ground it fell on. The autonomous crawl that dragged it
  toward safety is deleted; it walked the patient out of the rescuers' reach on
  the first frame the channel opened. Entering a downed body is still refused
  (`REASON_DOWNED`);
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
  warband's to pick up. The patient holds its ground (no soul, no crawl), so a
  cleared field is enough for the channel to run its whole five seconds: measured
  in the world the soul was up in 5.4 s on 5% health, and a downed AI body is now
  still for the rescuer's hands. A hostile arriving,
  the rescuer going down or walking off breaks it exactly like a human key. An
  AI channel is never opened while a fight is on;
- **wounds knit slowly**: every standing `WarbandBody` recovers
  `HEALTH_REGEN_AMOUNT` **1** health per `HEALTH_REGEN_SECONDS` **5 s** on the
  authority's tick, whether a soul is inside it or not. A full pool takes eight
  minutes, so it buys a long retreat and never a fight; the clock resets at full
  health and when the body falls, and a downed body on the bleed clock heals
  nothing. Replicas read the rise off their snapshots like any other health
  delta;
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
  walks to its own place in the band's **formation** (`_escort_post`) instead of
  onto the soul, and an ally with nothing to do
  takes one short step and then a rest (`_idle_roam`: `ROAM_STEP_MIN/MAX` 0.35-0.60 s
  of stepping, then `ROAM_REST_MIN/MAX` 2.5-5.0 s standing). An escort also keeps
  an arrival band - walk to its post only beyond `ESCORT_ENGAGE` 1.9 m, stop
  `ESCORT_STANDOFF` 0.85 m short - because a body that walked to its post and
  overshot it by the walk's own stopping distance paced back and forth for ever:
  measured on a still soul with no enemies, four allies covered 40-53 m apiece in
  ten seconds and ended 12-20 m from where they started. After the band and the
  rest, the same measurement is 0.9-1.8 m in ten seconds. A squad with nothing to
  do used to stand as one knot - and then, for a while, to walk in circles;
- **the formation** (it was a ring of slots until the disposition became a rank):
  a row is a line of bodies abreast across the soul's own heading and the rows
  stack front to back in `Contracts.DISPOSITIONS` order, so **every tank row is
  ahead of every melee row and every melee row ahead of every bow row** - a rank
  takes the rows after the last row its seniors filled, `FORMATION_PER_ROW` 4
  bodies to a row, so a wide rank turns its overflow into another row instead of
  a fence across the road. Row 0 stands `FORMATION_FRONT` 2.4 m ahead of the soul
  (`ESCORT_STANDOFF` + `PERSONAL_SPACE`, so the arrival band still leaves the
  body its own air instead of inside the soul's capsule) and each row after it is
  `FORMATION_ROW_GAP` 2.2 m further back; the bodies in a row stand
  `FORMATION_LANE` 1.7 apart, centred, and an odd row is shifted half a lane -
  alternating side with the row - so no body ever stands on the soul's own line.
  **The soul's own disposition never enters into it**: the ranks are measured from
  the soul's body, so a soul inside a bow still walks behind its tanks and in
  front of its archers, and a soul inside a tank has nobody in front of it.
  The heading is the soul's **body** facing (the way it last walked), eased at
  `FORMATION_TURN_RATE` 90 deg/s - not the camera's, or the band would swing
  round every time the player glanced sideways - and an escort jogs to its place
  once the soul is moving faster than `ESCORT_JOG_PACE` 6.2 m/s and it is
  `ESCORT_JOG_GAP` 3.0 m off it, because a body left walking behind a jogging
  player loses the formation one rank at a time. A walking or standing soul is
  matched by walking, so the band never sprints to hold a line. Ordering, the
  half-lane offset and the player-as-archer case are
  `tests/squad_disposition_regression.check_escort_rank`'s; distinct places for
  every ally of a five- to eight-body band are
  `tests/squad_steering_regression.check_escort_posts`'s;
- **the camp is mapped for the squad**: `scripts/warband/squad_nav.gd` draws the
  camp's own colliders - cage bars, huts, trunks, with every cage door left off
  because it rises - into half-metre cells, and a walk whose two ends are on that
  map goes round anything solid on an `AStarGrid2D` route instead of pushing at it
  in a straight line. A cage is bars on three sides and a door, and the latch arrow
  hangs on the back bars: a prisoner let out from behind its cage used to shoulder
  the back bars, back out of the door and walk straight back in for as long as the
  soul stood there. Off the map the escort walks the soul's footprints **forwards
  only** - it joins at the nearest one and never drops back to a nearer one, so a
  line that doubles back is walked to its newest footprint instead of being paced;
  choosing the nearest footprint afresh every frame paced two allies on 2.5 m of
  cage 1's approach for a whole run, because the walk to a cage and back lays the
  line out and back over itself;
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
  a water plane on the existing water shader, reeds and snags over the terrain's
  own wet mud, clear of the torches so the route itself is unchanged;

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
| `cage_escape_regression` 305 | the camp, the shiv through the bars, the five latches, the pair, the doors, the corridor to the road |
| `escape_run_regression` 201 | the way through the wood, its cult, and the ambush that follows the leaving |
| `warband_world_regression` 313 | one world, one controller, the ground, the 1,575 m walk, the escort, the budget (~65-100 s: the only long test) |
| `watcher_variants_regression` 1015 | the three skins against their exported metadata, the species-partitioned variant table, the rig behind every body (skin on the ranger skeleton, ranger body hidden, height, head zone), makeshift-only kits, the catalog piece in the rig's hand, the retimed swing (travel, drop, impact frame), a landed blow through `attacked`, the guard/stagger/crouch rules, the shared ragdoll, and the hit capsule standing as tall as every table row's build (a real arrow at each row's drawn head and drawn chest lands) |
| `corpse_loot_regression` 110 | the corpse registry, one booking path, the corpse screen |
| `delve_regression` 139 | the delve on the real world: pack and unpack at the mouth (the amount dial moves exactly its number of copies, clamps to 1..`MAX_AMOUNT`, and a shift-click still moves the whole stack), the descent written at once into a fresh instance, the party landing together in one shaft, the floor's plan (six shafts each in its own area and 50 m or more apart, every landing post open ground in its shaft and out of every rope's reach, a draw that gives every party its own shaft and the second the furthest, the squad's map routing every shaft to the lair and to every other shaft, no sleeper with a sight line to a landing, every den's post open ground, every den crowded to its own `den_crowd` bodies a post inside its own room, the floor's three rings (four ring chambers keeping one demon and its archers each, each corner's arc walking to both chambers it joins, a centre squad of several demon species round Gorehorn, a bow in most of the floor's rooms, and a keeper worth more than 200 health), and exactly the bodies outside `BODY_HIDE_DISTANCE` of the eye culled - hidden, hidden is not dormant, and back when the eye returns), the party-only reach (soul, squad, paperdoll, equip), the quiver as the inventory, a den that sleeps until a body is in its room and wakes whole while every other den sleeps on, a fallen den leaving under half its kit, anointed steel falling marked and waking its skill as it is taken, the right click below taking a whole body and the steel beside it into the delve inventory and dressing nobody, the loot window still booking below, the squad stripping a den on its own, the looted list and the floor's line naming the area, Gorehorn's prize, a member who dies below keeping his kit on his body (booked for nobody, skipped by the squad) until a right click takes it back, the climb out at another shaft's rope into the stash with the Ritual Tallow carried up rendered into the wallet, a fall that strips the party, and a save still below loading as a fall (~25 s) |
| `stash_autoloot_regression` 185 | real drops, quick-loot, the sweep, the stash, the gear-drop rule (both hands empty, nothing banked, a lying piece that never moves) |
| `squad_medicine_regression` 22 | the ally's bandage: the gate, the seconds, the spend, the interrupt, the roster write |
| `squad_party_mode_regression` 13 | the party's mode on the real world with frozen hostiles: OFFENSIVE goes in on a quiet one; DEFENSIVE leaves it, and one a third party wounded, alone, and goes in once it strikes the ally through the world's handler or the soul cuts it first; PASSIVE stays out and keeps to the soul, and back on DEFENSIVE the band answers what struck it while passive |
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
| The stockade | `scripts/warband/town_hub.gd`, `town_dressing.gd`, `town_folk.gd` | `WALL_RADIUS` 22, a `VillageKit.palisade` ring cut for one north gap and a `VillageKit.gate` in it, eight roofs (`keeper_hut` x5, `wattle_hut` x2, `trader_frame` x1) and village dressing with no colliders of its own. The same service ids, points and `G` semantics as before; the town stays inside `town_stockade_regression.LIGHT_BUDGET` 17. Five armoured keeper bodies (`Archer` rigs, `WarbandLooks` profiles, real armor sets) stand behind their counters, unpossessable and unhittable |
| The watch | `scripts/warband/town_guard.gd` | three static archers on the gate: nearest hostile within 26 m from the world's `guards` (or `wild_mobs`), line of sight on layer 1, 0.9 s draw, a real `arrow.gd` on the mob layer, 1.6 s cooldown. They never move or speak |
| The ledger | `scripts/warband/quest_log.gd` | `WarbandQuests` on `Warband.quests`: `KILL` / `RESCUE` / `COLLECT` / `APPLY` / `REACH`, four rows in `DEFS`, one state and one count each, saved as `quests`. `note_kill` / `note_rescue` / `note_collected` / `note_applied` / `note_reached`; `offer` → `accept` → `turn_in` with the chain in each row's `next` |
| The keeper who talks | `scripts/warband/quest_giver.gd`, `quest_marker.gd` | `talk(service, peer)` raises the card that teaches or hands over an order and answers false when the counter should open instead; `marker_service()` decides who wears the gold `TALK TO HIM` arrow (the recruiter while the band is short of the cap, the quartermaster when he has an order, a turn-in or a vial to explain) |
| The cage line | `scripts/warband/soldier_cages.gd` | four caged soldiers off the road, latches cut by hand with a blade (`G`, 2.2 m from the footprint), a door that lifts, a soldier who walks out and one `note_soldier_freed(name, at)` per cage (roster + stash dressing + ledger + HUD); with a place on the field his body stands up at the cage as the figure fades, past a full field he waits in the reserve. A `FREE HIM` arrow rides the nearest shut cage while the order is live |
| The warcamps | `scripts/warband/watcher_warren.gd` | 21 hollow wardens in three camps 78 / 96 / 86 m off the lane, dressed from the village kit, one `MobWander` territory each, wired to the world's kill handler so they count toward the bounty |
| The take-it-all and the loot window | `scripts/warband/loot_hand.gd`, `loot_window.gd`, `loot_feed.gd`, `loot_summary.gd` | a **right click** on lootable ground **in the body's own reach** opens the loot window beside the crosshair on that body and the drops piled within 2 m of it (click a row to take it, shift-click to take the lot; a click off the window, a right click, Escape, a walk out of reach or going down closes it); **Shift + right click** ducks the body for 0.9 s and empties the corpse record or the drop pile, then says one line. **Below, in the delve, a right click is the take itself** (`WarbandLootHand.take_now`): the body and every drop within 2 m of it - or the drop and its pile - go straight into the delve inventory at once, with no window, no channel and nothing dressed onto the taker (`take_all_from_corpse` / `quick_loot` with `dress` false), and one line says what came up. All of these resolve the press through `WarbandLootHand.target_at`, and every take goes through the vacuum's one booking path, which says so (`WarbandLoot.booked`) to the looted list on the HUD - the soul's takes and the squad's alike. The reach is measured from the body, not only from the crosshair: a press on a corpse across the field falls through to the guard instead of stealing it. **A living body on the reticle is never a loot** - `aim_sample()` hands the ray's target to `target_at`, which refuses a body that answers `alive` true, because a mob's aim point is its own chest and a blade at its feet is inside the same arm's reach; a corpse answers `alive` false and stays lootable. The left button is the blade's again |
| The map | `scripts/warband/world_map.gd` | one page, `M`, no pause: the lane sampled from the trail's path, the camp ring, the walled square, hostiles, the warband and the soul's own facing, plus `host.map_markers()` (shut cages, warcamps) |
| The altar | `scripts/warband/sacrificial_altar.gd`, `altar_menu.gd`, `cruor_manager.gd` | `SacrificialAltar` at `ALTAR_POINT` (8, 0, 4): a stepped stone pedestal and stele (`AltarStone`), a `Slab`, one merged `AltarDressing` (reagent bowl of glowing ichor, horned skull with ochre marks, blood, eight tallow candles, two iron stands, eight skull sticks, a bone heap), blood-red `AltarFlames` cards, exactly one light `RitualLight` (warm red, energy 2.6, range 9, no shadows) and an `AltarNameplate` "THE ALTAR" at 2.2 m; no colliders, all within 2.5 m. `AltarMenu` opens on ANOINT: every weapon or shield the warband carries (pooled or worn), worn-first then dearest, with the skill's icon (dim until anointed), piece, skill and key, recipe and an ANOINT button that stays pressable on a short stash so the refusal is printed — or ANOINTED. ESSENCE is unbind / distil 5:1 / brand. `G` there sets "The altar: lay a warden's ichor on a weapon and it wakes into its skill." |

The **orders** the quartermaster hands out, in chain order:

1. `free_the_soldiers` — rescue four caged soldiers.
2. `cull_the_watchers` — kill twenty of the wood's watchers; the row's `targets`
   list accepts all three creatures (a hollow warden, an ossuary stalker or a
   gallowsroot), because the wood fields all three.
3. `find_the_crypt` — a shell: the order exists, the place does not.
4. `bind_the_ichor` (ICHOR IN THE STEEL) — off the chain: appears the moment a
   warden's vial (one watcher in three carries one; catalog detail
   "Carried in the shared stash / anoints a weapon with its skill at the altar")
   is in the shared stash. Line "Anoint a weapon with the warden's
   ichor", hint "G - the altar", keys "G - the altar · 1 / 2 - loose the skill it
   wakes"; the quartermaster's lesson is tip `ichor_altar` ("ANOINT A WEAPON WITH
   THE ICHOR AT THE ALTAR"). While it is active the ledger row and the keeper's tip are where the altar is
   named (`town_hub.prompt_line` still says "G - Sacrificial Altar" at the altar
   itself). Finishing it appends "Tell the
   quartermaster what the steel can do now." to the altar's status.

## 12. The delve: the Weeping Hollow, floor I (shipped)

The loop the town exists for: make up a party at the Hollow's mouth, pack what it
carries, go down one of the floor's six shafts into a fresh instance, take what it
holds and climb out by any rope - or fall below and lose everything the party
carried. Floor I is laid out for an extraction floor's crowd in three rings:
eleven areas, six of them shafts on the outer rim, each a landing and a way up, so
parties come down in different corners and work toward each other through the
dens; inside them the demons' ring, four chambers round the lair with a demon in
each; and at the centre Gorehorn's lair, with a squad of demons on its floor. The player's account is the README's *The delve*; the contracts are here,
and `delve_regression` plays the whole loop on the real world.

| Surface | Module | Contract |
| --- | --- | --- |
| The books | `scripts/warband/delve_state.gd`, `warband_state.gd` | `WarbandDelve` on `Warband.delve`: `active`, `party` (merc ids in the order chosen), `depth` (floor I only) and `inventory` (a `WarbandStash`). `field_stash()` is the inventory while `active` and the town stash otherwise; equip, unequip, every loot take - a fallen squadmate's kit included, once it is taken back off his body - and the quiver go through it, so nothing taken below reaches the stash before the climb. `dressable_ids()` is the party while below. `pack_for_delve` / `unpack_from_delve` move pooled copies between the stash and the pack and refuse while a party is below. `begin_delve(ids)` refuses a dead, reserve or empty party and **saves at once**; `extract_delve()` adds the whole inventory to the stash, except carried essence (`cruor_t1`, Ritual Tallow), which renders into the cruor wallet; `forfeit_delve()` takes every worn piece (both sets, armour, trinkets) off every party member still on the roster and clears the inventory. `load_state` forfeits a record that is still `active`: quitting below is a fall |
| The reach | `scripts/warband/soul_router.gd`, `possession_controller.gd`, `world_scene.gd` | while below, `SoulRouter.set_reach(party)` lets a soul enter only a party body, `living_merc_ids()` (what `F1`..`F8` count) lists only the party, and `_is_free_ally` refuses a body left in the town to the squad: it stands where it was left. The reach is cleared when the instance closes, and a soul with no body is put into the first free one |
| The mouth | `scripts/warband/delve_area.gd`, `delve_prep_menu.gd`, `town_dressing.gd` | a rope pit under an A-frame at `MOUTH_POINT` (8, 0, -6) in the square's frame, where the fingerpost's `THE DELVE` arm points; `G` within `MOUTH_REACH` 3 m opens the prep panel: THE PARTY (every standing body, all chosen by default), THE TOWN STASH and THE DELVE INVENTORY (the dial above the page says how many copies one click moves - one by default, `MAX_AMOUNT` 999 at most, `set_amount()` clamps it - and a shift-click still moves a whole stack, both ways), the loss rule in one line, GO DOWN. `descend(ids, landing_id = "")` refuses a guest, a second party and a body that is not standing, then `begin_delve`, builds the instance, draws the party's shaft (`landing_id` when given, else `Layout.landings_for(1, draw)` on the area's own `_draw` RNG, fresh every descent), puts the party on that shaft's `entry_posts`, sets the reach and moves the soul into the party; `landing` holds the shaft while it is below |
| The plan | `scripts/warband/delve_layout.gd` | pure data and the geometry asked of it, read by the cave and the regression without building anything. `BOUNDS` 320 x 380 m (the authored 160 x 190 at `SCALE` 2), 87 `ROOMS` (axis-aligned rects on the 0.5 m `CELL` raster, each tagged with one of the eleven `AREAS`; rooms connect only by sharing an edge and never overlap, since a lower roof would hang into the taller room), six `LANDINGS` (`mouth`, `gallery`, `workings` on the near rim, `garden`, `mere`, `chapel` on the far rim; each `{area, room, rope, centre, yaw}` with the landing ring 10.8 m in front of the rope - 5.4 m at the authored scale - so no landed body starts inside `EXIT_REACH`; no two closer than 112 m), twenty-two `DENS`, the master, every `LIGHTS` and `PROPS` row. Everything is authored at the drawn size and the floor is built `SCALE` 2 times it - footprints, ceilings, ropes and their rings, den posts, the master's ring, a light's or a prop's spot and the ground it covers - so one number makes the whole Hollow bigger; body-sized constants (the crowd's `CROWD_SPACING`, a lamp's reach, the landing ring's `ENTRY_RADIUS`) do not scale. `landings_for(count, seed)` hands parties different shafts: the first drawn from the seed, each next the shaft whose nearest taken shaft is furthest. `raster()` / `room_index_at` / `area_at` answer where a point is; `rock_rects()` is the colliders, `wall_rects()` the rock each room's shell draws (every rock cell within `WALL_CELLS` 4 of a floor goes to its nearest room, so no face is drawn twice); `doors()` / `door_metres` / `walk_metres` / `nearest_landing` walk the floor door to door |
| The areas | `delve_layout.gd`, `scripts/warband/delve_dressing.gd`, `scripts/world/cave_kit.gd` | THE MOUTH (the old landing), THE WATCHERS' DEN, THE DROWNED GALLERY (black pools under witch-light, a cistern), THE OSSUARY (niches), THE PALE GARDEN (fungus grove and glade, giant caps), THE BLACK MERE (a lake cavern with braziers and a drowned shrine), THE BONE CHAPEL (nave, apse, crypt of coffins), THE ROOTED HALL (roots through the roof round a fire), THE OLD WORKINGS (timber sets, lanterns, carts, rubble), THE DEMONS' RING (four chambers round the lair, one on each of its ways in, joined to each other round the outside of the lair by a bent arc at every corner - a loop, not four spokes - so a party can walk the ring and meet a demon in every chamber) and GOREHORN'S LAIR at the centre, with a way in from all four sides and a squad of demons on its floor. Each area is dressed by its `CaveKit.AREAS` row: the wall rock set (limestone, strata or basalt), rock/silt/dripstone tints, wetness, water streaks, growth, floor pools, and its air (fog colour, haze, ambient), which `delve_cave._settle_air` eases toward as the eye walks between areas; `FORMATIONS` sets how much dripstone, flowstone, breakdown, talus and how many curtains it grows. Every way between a den and a shaft bends |
| The rock | `scripts/warband/delve_rock.gd`, `scripts/world/shaders/cave_rock.gdshader` | presentation over the unchanged collider boxes. `wall_runs(index)` follows every floor/rock edge of a room lattice point by lattice point; `skin(index)` raises a strip on each from `BURY` under the floor to `OVER` over the roof, pushed into the room by `relief()` (always ≥ `PROUD` 0.05 m: a talus skirt, wandering strata, `FOOT_REACH` 0.2 m where bodies walk, up to `HALL_REACH` 0.78 m overhang above head height, a cove into the roof), shares each corner vertex with the next strip (the sum of the faces' normals from the four raster cells round it), fades the room-shaped rock out over `JAMB_BLEND` 2 m toward a jamb so two rooms agree on it and swells the mouth of a way out toward its head (`ARCH_PUSH`), lofts a lintel over every lower way out, dresses the rock back round every wall mount (`DRESSED`), and hangs a vaulted roof (`roof_height`, flattened round each rope). Skins are built once per process and kept. The shader reads the area's set world-triplanar (warped so a scan never prints courses), settles the silt set into the rock's low texels on whatever faces up, and adds water streaks, a damp wall foot, growth and pooled floors |
| The formations and the flora | `delve_dressing.gd`, `assets/world/cave/` | `dress_room(node, index)` places the room's skin and what `_grow(index)` grew from the room's own seed (`GROWTH_SEED` + index, kept per process, so every machine and every descent grows the same): stalactite clusters and curtains with every tip above `HEADROOM` 2.9 m (2.7 m in a way), spires, flowstone, breakdown and talus along the wall feet and a cluster in each hall corner, nothing within `JAMB_CLEAR` 1.8 m of a way out, a landing, a rope, a den's post, the master, a light or a prop. Pieces big enough to stop a body (a tall spire, a big boulder or mound, a corner cluster) get a post collider in a hall and are on the squad's map. Wet rooms drip from their stalactite tips. Fungus lights grow bracket shelves and cap clusters, the garden's giant caps are the kit's, every shaft has a pale cone of night with dust turning in it, and the props' pools, columns, carts and rubble are the kit's breakdown |
| The life | `scripts/warband/delve_fauna.gd`, `scripts/world/shaders/cave_fauna.gdshader`, `cave_glow.gdshader` | presentation only, never replicated, off the hostile list and the squad's map. Per area (`LIFE`), spread over its rooms: bats (roosts on the roofs that stir when a body walks within `STIR` 4.5 m under them and settle once it has gone, and flyers looping under the halls), rats along the wall feet that bolt from a body inside `BOLT` 2.8 m and go to ground, webs across room corners with a spider in about half, glowworm threads on the damp roofs of the gallery, the garden and the mere, and `MOTHS_PER_FLAME` 3 round every warm light. One `MultiMeshInstance3D` per kind per room, animated in the vertex shader; movers step only while `cave.room_lit(index)` |
| The instance | `scripts/warband/delve_cave.gd` | built at `DelveArea.ORIGIN` (0, 0, 1100) on every descent and torn down on both ends; deterministic (fixed plan, seeds and names), so a guest's copy carries the host's body names. The colliders are `rock_rects()` boxes up to `TOP` 22 m (the authored 11 at `SCALE` 2) plus a roof over every room and the formations' posts; each room's node draws its floor, roof and `wall_rects()` share in its area's stone; lamps and haze are at the plan's scale with it - `Dressing._at_plan` gives every lamp `SCALE` times the reach and `SCALE` squared the energy (the same light at twice the distance, a flickering lamp's `base_energy` included) and `_settle_air` keeps the haze density `SCALE` times thinner, so a hall that doubled is lit and fogged as it was, its skin, formations and life, so every mesh stays local to its room and its lights. The renderer's limits are a measured budget: with every light on, no mesh is reached by more than 7 (GL Compatibility draws 8 per object), and `_process` keeps only rooms within `LIGHT_NEAR` 40 m of the eye lit (out past `LIGHT_FAR` 48 m, polled every `LIGHT_POLL` 0.3 s and at once on an `EYE_JUMP`), 8-18 of the 64 lights at any shaft or hall. The first descent in a process builds the skins and the growth (about 1.4 s); every later one reuses them (about 0.4 s). `rope_point` / `exit_at` / `at_exit` / `entry_posts` / `entry_yaw` / `area_at` / `nearest_rope` / `den_mobs` / `lit_count` / `room_lit` are the reading surface. The squad gets the cave's own `SquadNav` (flat floor height instead of the heightfield) and `SquadDrive.relocate()` on both ends. The camera takes `cave.environment` and the sun goes out while the eye is below |
| The descent's load | `delve_cave.gd` (`build`/`build_staged`, `_steps`, `_warm_view`, `_rest_the_quiet`), `delve_area.gd` (`descend`, `_open_instance`, `below`, `building`), `scripts/audio/audio_manager.gd` (`_warm_tracks`, `_resident`) | a descent stops blocking. `build_staged` walks the same steps `build` does (`_build_environment`, the rock a room at a time, each room's dressing, the ropes, the lights, the props, then a den at a time, the master, the fauna, the nav, the sync) inside a `BUILD_FRAME_USEC` 14 ms budget per frame, and `DelveArea.descend` is a coroutine that awaits it: the window keeps painting and the HUD counts `THE WEEPING HOLLOW · GOING DOWN · n%` (`cave.built_share`), the party is placed the frame the floor is whole (`cave.built`), and nothing below is read until then (`below()` = `cave != null and cave.built`; `building()` is the window itself). The physics clock is held to `Engine.max_physics_steps_per_frame` 2 for the whole load - left at 8, the engine paid the load back as a burst of six to eight steps on the frame the eye landed, which was a hundred and seventy milliseconds in one frame. Before the floor is handed over, `_warm_view` stands a camera in the room the party is about to land in, puts the floor's air on the host camera and every lamp on, and draws three frames of it: the first frame a room is drawn is the frame the renderer builds its meshes, pipelines and light-count variants, and paying it here is paying it behind the loading line. Bodies are spawned hidden and resting (`set_culled(true)` + `rest(true)`) and the culler reveals them a batch at a time (`NEAR_REVEAL` 40 m at once - that is where the fight is - then `REVEAL_CHUNK` 12 a poll), because a body's first draw is what the player reads as a room coming into range. Measured: the descent was one frame of 3.4 s (first in a process; 1.4 s after, the skins cached) and is now ~4.6 s of frames at 16-18 ms with a counting line; the frames after it were three of 150-270 ms and are 1.4 s of 16 ms frames plus two of ~130 ms while the cave's colliders enter the physics space. The score is 61 MB in one file and `play_music` used to `load()` it on the frame the party left the square (a second of frozen screen, again after every trip back to town, because `stop_music` purged it): both tracks are requested threaded at startup, kept for the session (`_resident` survives `_purge_streams`) and a track that is not in yet arms itself the frame it lands. `WorldScene._note_hitch` writes any frame over 45 ms to the log (`event("hitch")`, once a second at most) with its steps, draws, objects and guard count, so a session that stuttered can be read back |
| The map | `scripts/warband/delve_map.gd` (`DelveArea.map`) | `M` below opens the Hollow's own sheet instead of the wood's (`world_scene.gd`); a second `M` closes it, and closing the instance closes it. Like `world_map.gd` it never pauses and is pure projection: `map_bounds()` (every room plus `MARGIN_METRES`), `project()` (the cave's -Z up), `rooms()`, `walls()` (the same `wall_runs` the skin is raised on), `areas()`, `markers()` (every rope, the one the shortest walk from the soul reaches flagged `nearest`, the shaft the party came down, Gorehorn, the awake hostiles below, the party and the soul's facing; a sleeping den is not on it), `scale_metres_per_pixel()` and `legend()`; the board's `_draw()` decides nothing. `delve_regression` presses the real `M` below and checks the sheet against the floor |
| The dens | `delve_layout.gd`, `delve_cave.gd`, `scripts/mob_wander.gd` | `DENS` as authored: the den 3, the cistern 2, the ossuary 4, the grove 2, the shrine 2, the crypt 2, the rooted hall 4, the upper workings 2 - 21 posts - and every den fields `DEN_CROWD` 10 bodies a post, **210 watchers** in the eight dens, **plus one archer a den** - a post written `bow` is one body and is never crowded, so each of those rooms keeps a hollow warden with a bow (`watcher_archer.gd`, anchored on its own post and sprung with the den) holding the far side of the fight - **218 bodies in the eight dens**, and **80 more** scattered through the halls, the way on to the ring, the ring's chambers and the lair - **298 watchers and demons below**, 299 bodies with the master - every one of them culled past `BODY_HIDE_DISTANCE` 96 m from the eye (the authored floor's 48 m at `SCALE` 2, which stays past the farthest corner of any room - a body in the room the eye stands in is always drawn) (hidden, rig parked, brain and collision kept) and drawn as **11 surfaces** - six of creature skin, five of baked weapon: `den_members(den)` (pure, cached; the cave, the dressing's clearings and a guest's copy all read it) keeps the authored posts and lays the crowd on a 1 m lattice of the den's own room, each body on the free spot furthest from every body already placed (`CROWD_SPACING` 1.8 m), `CROWD_WALL` 1.5 m in from the rock, `CROWD_DOOR` 3 m from every way out and `CROWD_CLEAR` 2 m past every light and prop footprint (the hanging roots excepted), with the species and the door of the post it repeats. Each den is its own `MobWander.assign_all` pack, every body facing the door named in its row's `face`. A sleeping den is off `host.guards`; every `WAKE_POLL` 0.25 s it wakes whole when one of its own has seen, heard or been struck, or a party body is `WAKE_INSET` 1.5 m inside its room, and then joins `host.guards` and names itself on the HUD (`den_woke`). No sleeper has a line of sight inside its profile's sight to any landing post. Pack groups are numbered across `assign_all` calls, so one den's alarm never reaches another habitat's pack. The crowd costs: a descent builds in ~2.0 s instead of ~1.4 s, and headless the floor's frame is ~18 ms of CPU instead of ~10.6 |
| The halls' own life | `delve_layout.gd` (`den_crowd`, `AUTHORED_DENS`'s last fourteen rows), `delve_cave.gd` (`_rest_the_quiet`) | the floor is not eight crowds seventy metres apart: every hall a party walks through and every way into Gorehorn's lair keeps a scattered few as its own den - the gallery 8, the flooded dark 4, the garden 10, its glade 3, the mere 12, the chapel nave 8, the apse 2, the workings 4 and the den's jog 2 - 53 crowded bodies, with one archer in each of the eight halls - and the ring and the centre: **one demon and two archers in each of the four chambers of the demons' ring (12)**, and **the lair's squad - a demon of every species the floor fields plus two archers (7)** - **80 bodies on top of the dens' 218: 298 below, 299 with Gorehorn**. A demon is a post written `demon` (`delve_demon.gd`), placed once like the archers, so `den_crowd` never multiplies one into a squad of its own. A den's `crowd` is its own number of bodies a post (`den_crowd(spec)`, `DEN_CROWD` 10 when a row names none), and a hall's few are spread across the hall by the same maximin rule, so they read as a scattering rather than a squad. The works hall keeps its bodies west of the neck: `workings_shaft`'s way in is straight, and no sleeper may have a landing in sight (`delve_regression` raycasts every body's eye to every landing post). **A den that has woken rests again**: `_rest_the_quiet` on the same `WAKE_POLL` 0.25 s rests a body the eye has lost (`culled`, past `BODY_HIDE_DISTANCE` 96 m) and that no standing party body is within `REST_FAR` 60 m of, and lifts it on the frame the party comes back inside `REST_DISTANCE` 40 m (a blow lifts it at once, `take_damage` -> `mob_wake`). Without it the awake set only grew: a party that walked the floor paid for every body of every den it had passed until it climbed out. Measured on the walk (a step a frame along the squad's routes through the floor as it then stood - 77 rooms, 284 bodies, every den awake; the demons' ring has added ten rooms and fifteen bodies since): **12-27 ms a frame, p95 28 ms, max 33 ms**, against 34-50 ms mean / 59 ms max before |
| The master | `scripts/warband/delve_demon.gd` | Gorehorn: `devil_mob.gd` as `hell_goat` (the goat's body, rig and clips) with `OVERRIDES` (health 400, damage 21, reach 2.35, sight 34, gold 60, cooldown 1.6, no roaming, no pack) and `SPOILS` (`sword_arming`, `ring_blood`, `focus_skull_death`, two `ichor_vial`) on its corpse as `gear_items`, kept whole by the loot table (which only adds its rare Ritual Tallow); answers `hunt` / `hunting`; a `Hellfire` light under it. It stands on the blood ring at `MASTER_POINT` in the middle of the lair, sleeps as the lair's own den and wakes the same way; its death (`master_slain`) puts one line on the HUD, and the header turns to the climb. **`boss` is the only difference**: the same file and the same AI make every other demon below - the ring's four keepers and the lair's squad of five species - on `KEEPER_OVERRIDES` (health 240, damage 17, sight 30, gold 24, cooldown 1.4, no roaming), one a chamber and one of each species at the centre; they carry no kit and answer `demon()`, so the loot table's demon branch gives them the altar's Ritual Tallow and nothing else |
| The loot below | `scripts/warband/delve_loot.gd`, `delve_cave.gd`, `world_scene.gd`, `loot_vacuum.gd`, `cruor_manager.gd` | every death below runs through the cave (`_on_mob_defeated`, host only) so `Loot.settle(body, demon, loot_rng)` - `loot_rng` drawn afresh each descent - shapes the corpse before the world books it. A watcher keeps each ordinary piece (weapon, every armour rag, everything carried) on its own `KEEP_SHARE` 0.3 roll: **loot below is cut by 70%**, and steel that does not survive leaves the hand empty. Rare finds are their own rolls and never thinned: **Ritual Tallow** (`cruor_t1`, the altar's tier-1 essence as a carried catalog piece) on `WATCHER_ESSENCE_CHANCE` 4% of watchers - they gate the Hollow's demons through to harvest it - and `DEMON_ESSENCE_CHANCE` 10% of demons; **anointed steel** on `ANOINTED_CHANCE` 2% of watchers whose weapon has a skill: the hand drop is marked (`WarbandPickup.anointed`, "Anointed ..." plate) and booking it calls `Warband.grant_anointing` - the piece's skill wakes for every copy the warband owns, no reagent spent, and `anointed` re-dresses the bodies holding one. Gold is unchanged |
| The fallen below | `world_scene.gd` (`_leave_remains`), `loot_vacuum.gd`, `squad_drive.gd`, `delve_cave.gd` | a party member who dies below keeps what he still wore on his body: the world takes it off his books as he dies (his hands included; a body that was downed first already dropped its hands at its feet) and registers it with `WarbandLoot.register_remains(body, items, name)`, so `reap_dead` finds nothing to book and the HUD says to loot him. `corpse_ids(false)` - the list the squad walks - leaves remains out, so only a soul takes the kit back (right click below: the body and the drops beside it). The instance's `teardown` forgets every corpse left inside it, so what nobody took back stays below |
| Climb out and fall | `scripts/warband/delve_area.gd` | `G` within `EXIT_REACH` 2.6 m of any shaft's rope: `extract_delve` (the Ritual Tallow carried up into the wallet, the rest into the stash), every party body still alive (downed included) up onto a ring beside the mouth, the instance freed, one status line with the count and value. With no party body standing, `WIPE_BEAT` 2.5 s later `fall()`: `forfeit_delve`, the downed stand up stripped with the revive's `REVIVE_HEALTH_FRACTION` beside the mouth, the dead stay dead with whatever is still on them, and the checkpoint wipe stands aside while a party is below. Once Gorehorn is dead the crosshair names the rope the shortest walk reaches and how far |
| The looted list and the floor line | `scripts/warband/loot_feed.gd`, `delve_area.gd` | the feed lists every `WarbandLoot.booked` piece; while a party is below its header reads the floor, the area the soul's body stands in, the inventory's pieces and value, `WAY UP · <area> · n M` (the walk to the nearest rope), Gorehorn's blood once the lair is awake, and "GOREHORN IS DEAD · CLIMB OUT BY A ROPE" after |

A co-op guest never decides anything below: `_mirror()` builds the instance as a
replica while the host's books say a party is below and frees it when they say
it is not, and the mouth answers a guest with `GUEST_TEXT`. No two-process test
covers the delve yet.
