# Ghost of the Warband — session handoff

**Read this first in a new session.** It is the state, the decisions and the next
work. The design/contract document is `docs/warband.md`; the repo skill
`.omp/skills/ironwood-archer/SKILL.md` has the engine-level notes.

- **Repo:** `C:/tmp/ironwood/ghost_of_the_warband` (a fork of
  `C:/tmp/ironwood/ironwood-archer`, which is untouched), branch `main`,
  trunk head at the commit that added this file. `git log --oneline` reads like a
  changelog for the whole overhaul.
- **Engine (already in the repo, git-ignored):**
  `.runtime/godot/Godot_v4.7.2-stable_win64_console.exe`. The `.godot/` import
  cache is present; a new worktree needs both copied in (see §8).
- **Run a test:** `./.runtime/godot/Godot_v4.7.2-stable_win64_console.exe
  --headless --path . --script res://tests/<name>.gd` (prefix `./` in git-bash,
  `.\.runtime\...` in PowerShell). Every test prints
  `<NAME>_REGRESSION checks=N failures=M` and exits non-zero on failure.
- **Play it:** `Play.cmd` (title menu → **GHOST OF THE WARBAND**) or run
  `res://scenes/cage_escape.tscn`, `res://scenes/town_hub.tscn`,
  `res://admin_arena.tscn` directly. Multiplayer arena:
  `res://admin_arena.tscn -- --warband-host 7790` / `-- --warband-join 127.0.0.1 7790`.

---

## 1. What the game is now (player-facing loop)

The campaign is **one world** — `scenes/warband_world.tscn`, one scene, one soul
controller. The cages stand in a clearing inside the dark wood; the wood runs 286 m
to a town cut into the same trees. Nothing between them is a door: walking is the
only way from one to the next, and no key loads a scene. The title's **GHOST OF THE
WARBAND** door is a *new campaign* — it resets the warband and the shared journey
(purse included) and opens at the cages, however the last run ended. **RESUME
WARBAND** is the checkpoint door: it opens the world where the last autosave stands
(disabled until a warband save exists). Autosave writes a **checkpoint** at the two
moments that begin a stretch — the camp's six watchers dead with the squad on the
road (`trail_start`, 60 m past the mouth), and the town square entered (`town`).
A wipe reloads it; the opening itself has no checkpoint, so a tutorial wipe is still
the tutorial's to take.

1. **You wake in the cage.** The player is inside the first of the five
   prisoners (`CAGE_POSTS[OWN_CAGE]`, `OWN_CAGE` 0) and the clamp holds it there
   (`CAGE_CLAMP_RADIUS` 0.95 m). Objective: **Cut your latch**; the tip channel
   (`camp.TIP_CAGE`) names `G`. The player's own padlock is the one that gives up
   to bare hands - a wretch with a nail - and every other cage needs a blade.
2. **The camp, and the objective.** Cutting it is the `LOOSE` beat: out of the
   bars, a tip names `W A S D`, and the gold arrow stands over the camp's only
   blade (the ironwood shiv at `SHIV_POST`). Stepping `BEARINGS_RADIUS` 4.2 m from
   the player's own cage is the whole of "getting your bearings": the sequencer
   turns to `FREEING`, the objective becomes **Free your warband n/5**, and the
   first fight's lesson (`duel_lesson.gd`) starts at its `MOVE` beat. The four
   other cages are scattered through the pocket, so the quest is a walk around it.
3. **The first fight, one line at a time.** There is no card and nothing pauses:
   every beat offers one tip (`scripts/warband/warband_tips.gd`, key tiles plus a
   command, six seconds, gone) and the HUD prompt names the job.
   Walking onto the shiv offers `K`; taking it puts the blade in the hand, raises
   the cuts (LMB diagonal, `WHEEL_UP` stab - the dagger's Prison shank, +200%,
   0.167 s - and `WHEEL_DOWN` overhead) and wakes the pair. The second watcher's
   first windup raises **hold RMB**; a dagger only softens a blow
   (`DEFENSE_WEAK_BLOCK`), so the tip says a guard is a moment, not a wall.
   The pair are the softest bodies in the game: 21 health (two stabs),
   `blow_scale` 0.5, `windup_scale` 2.4 (a 1.3 s telegraph), `swing_gap_scale` 2.2
   and `guard_scale` 0.
4. **The latches, cut by hand.** One latch per cage with `G` in a body holding a
   blade (`LATCH_REACH` 2.2 m) - nothing opens on a possession or a kill. The
   latch arrow rides the *nearest* shut cage, so five scattered cages are five
   walks and not a line. The second cut offers the bodies tip (`F1`..`F5`, `[` `]`).
   The fifth lifts every door, turns the freed prisoners into squad AI that arms
   itself off the ground, and turns the objective over: **Run to the town**.
5. **The fallen.** The first squadmate to go down within 12 m of the player's body
   offers the one unnumbered tip (`lesson_revive`): **HOLD G** - not a tap - for
   five seconds brings a body back from DOWNED, and a blow that lands on the
   reviver breaks the channel. The bleed clock is 30 s; in the campaign no blow
   ends a mercenary outright - a lethal hit only puts the body down - while any
   blow that lands on a downed body finishes it and leaves the corpse where it
   fell. It is offered from `world_scene._on_body_downed`, so the camp and the
   trail share it.
6. **The leaving is the ambush.** Walk the soul's body out of the clearing's mouth
   and **four armed watchers come out of the trees** (each drops its weapon) as the
   state turns to `ESCAPING`. There is no kill quota to open the way; there is no
   gate.
7. **The wood.** The mouth leads onto a **1,374.6 m** road through the same wood —
   torches down both verges every 18 m, ironoak and hollow snags, rag trees and
   gallows trees with charms strung across the track, two bone arches that frame
   the road, wicker effigies, skull stakes, cauldrons, braziers, straw, blood and
   cart ruts. The squad runs it with you. **Twenty-six** wardens hold it — twenty
   on ten posts about 100 m apart plus six archers in two ambushes — and none of
   them is handed a target at spawn. The road answers the leaving: a third of every
   ring takes the soul at `ESCAPING`, the rest notice by sight. A **Hand Torch**
   (45 gold from the quartermaster, off hand) is the answer to the dark: worn, it
   burns in your hand and lights 26 m of wood around you.

   The squad fights for you: it swings the moment its blade is free, holds a guard
   in the gap between swings, and now and then takes a beat to guard and circle
   before coming back in. A downed cultist is worth checking — it drops the blade
   it held and the rag on its back, and once nothing hostile is within 22 m the
   squad walks the field and strips it. **A body is looted with a click**: aim at a
   corpse or a drop and press the left button — the body ducks over it for 0.9 s,
   the container empties into the shared stash, and one line says what came back.
   Nothing is announced piece by piece; that feed is what the warband contract
   keeps off the screen.

   Four **cages** stand off the road on the way down (fractions 0.34 / 0.52 / 0.68
   / 0.86 of the lane, 7.6–8.6 m out), each with a soldier of the band shut inside
   it and a gold `FREE HIM` arrow on the nearest one while the rescue order is
   live. A latch is a cut, not a key: stand at the bars with a blade in your hand
   and press `G`. Every soldier you bring out joins the roster and arms himself out
   of the shared stash. Three **warcamps** of seven hollow wardens apiece sit
   78–96 m off the road (fractions 0.72 / 0.80 / 0.90), past twice a warden's own
   sight of the lane, so the road never drags them into a fight the band did not
   walk into — the map and the camp dressings are what make them findable.
8. **Town.** The trail ends at a **stockade**: 286 planted stakes with one gap and
   a bone-lintel gate over the road, eight roofs inside it (five stick-walled
   halls, two round dwellings, one open stall), a totem pair, the fire ring, and
   the services — shared infinite stash, Sacrificial Altar (unbind / distil 5:1 /
   brand), the **recruiter** (the first eight oaths are free; a hire dresses itself
   from the shared stash), the **quartermaster** (plain steel into the stash, and
   the campaign's orders), the **ichor bench**, three market keepers and the
   expedition gate (deploy up to 8 → arena). Every keeper is an armoured body
   standing behind his own counter, and a gold **TALK TO HIM** arrow rides
   whichever one has something to say. Three watch archers stand on the wall and
   put real arrows into anything hostile inside 26 m. You walk in. Nothing asks for
   a key, and the frame the soul enters the square on writes the `town` checkpoint.
7. **The orders.** The keeper who speaks speaks first, and the campaign is his:
   * **The recruiter** teaches the oath on the first `G` (one card, then the hire
     board underneath it). Eight bodies is the deployment cap, and they cost
     nothing.
   * **The quartermaster** takes the arrow once the band is at the cap and hands
     over the cage line — four soldiers, `G` at each latch. Turn it in and he hands
     over the watcher bounty: twenty hollow wardens. Turn that in and he opens the
     campaign's over-arching order, **FIND THE CRYPT**, which is a shell: there is
     no Crypt in the world yet, and the order stays open until there is.
   * **The vial.** A warden's ichor drops off the wardens themselves (four variants
     in twelve carry it). Walking up to the quartermaster with one in the stash
     raises the card that explains it and then the bench: press `G` at the bench,
     take a spare weapon out of the stash, and it comes back with a sigil bound
     into it — `R` looses it. One vial, one blade, no essence spent.
8. **The map.** `M` opens the wood on one page: the road sampled from the trail's
   own path, the camp's ring, the town's walled square, the order markers (cages,
   warcamps), every hostile within the wood and the souls' own bodies with the one
   you are inside marked and turned. It never pauses the tree.
9. **Arena/expedition.** The one scene change left in the campaign: deploying
   loads the arena. An empty deployment line builds the sandbox brawls (bubble
   demo); a deployed line builds a real five-wave expedition against cultists with
   the Bilewarden at the end, with survivors physically looting the field.
   `Enter` comes back to the world at the town end.

**The band is eight men, not one man eight times.** A mercenary's look is a pure
function of their id (`WarbandLooks.profile_for`): one of eight faces, one of eight
cuts, one of five beards, one of five irises, eight skins, eight shirts, eight
pairs of shorts and a height between 0.86 and 1.14 of the authored rig. It is
derived, not saved and not replicated, so two peers and every reload agree; the
numbers live in `assets/characters/warband/ironwood_warband_looks.json`, which
`python tools/prepare_warband_looks.py` writes from geometry and textures the
repo already ships. Nothing gameplay-facing moved: stats, capsule, reach and
speeds are still the warband's one contract. See `docs/warband.md`
("The band looks like a band") and `tests/warband_appearance_regression.gd`.

**Since the loop above was written**, four surfaces were added on the same world:

- **The way out has teeth.** Seven base briar wolves (`enemy.gd` **kind 0**, no new
  mob class and no stat table) stand on derived posts 122–252 m past the camp
  mouth, 25 m clear of it and outside the pocket, aim at the nearest standing body
  (refreshed every 0.5 s), wander as packs through `MobWander` at a 14 m radius,
  and are parked by the band's own `MobCuller` once no body is within 150 m
  (waking again inside 128 m). The opening fight stays the camp watchers'
  business.
- **The square has three keepers.** Storekeeper Orla (bows and staves), Smith
  Brann (blades, dagger, shields) and Quartermaster Vey (armor, foci, jewelry)
  stand at real counters, each a `G` service (`vendor_orla`/`vendor_brann`/
  `vendor_vey`). One `VendorMenu` board walks keeper to keeper: buying spends gold
  into the shared stash (`Warband.buy_gear`), selling takes a spare copy out of
  the pool for 60% of catalogue (`Warband.sell_gear`), and a piece somebody is
  wearing is not the warband's to sell.
- **Escape is the warband's own window.** `WarbandMenu` has six rows — resume,
  save, load, settings, exit to title, quit — and pauses nothing. SAVE writes
  `Warband.save_state()`; LOAD re-reads that file and re-enters the world;
  SETTINGS swaps in the shared sound page plus the windowed/fullscreen row. Escape
  closes the menu first, then an open panel, then opens the menu; an open tutorial
  card keeps it shut.
- **The campaign is co-op.** The title lobby's HOST/JOIN WARBAND defaults to
  **CAMPAIGN (CO-OP)** (the arena bout is still the first, selectable row) and
  routes to `GameFlow.host_campaign`/`join_campaign`; both machines need the same
  warband save. The host owns the world — its mobs, the loot that hits the ground,
  the missiles in flight and every kill reward — and the guest sees it all through
  the one `WarbandSession`. A guest fields its own save's bodies, has the camp
  lesson dismissed, runs no squad AI and never writes a checkpoint.

HUD keys: `[`/`]` cycle body, F1–F8 named body, O warband screen, **M the map**,
TAB quick
weapon swap (the frontier's two sets), P paperdoll, plain 1/2/3 item skills
(Shift+1..3 is the same press), RMB guard — and a cover lean while attached,
released with the button — Escape the campaign menu, G interact and the five
second revive hold, **LMB on a corpse or a drop is the loot** (the body ducks and
takes everything; K still quick-loots one piece),
R branded skill, X shoulder swap (the camera is 0.70 m off the spine, as the
frontier's is - the reticle is not your own head).

Bows and thrown steel spawn through `world_scene` off `combat.shot` /
`combat.thrown` (`PROJECTILE_HIT_MASK` 1 | 2). Nothing in this mode did before:
the arrow was never created, and `aim_sample` masked the mob layer out, so the
crosshair resolved to the dirt behind whatever you were aiming at.

---

## 2. Architecture map

Autoloads (`project.godot`): `Log`, `PlayerState`, `Session`, `NetCache`,
**`Warband`**, **`GameFlow`**.

| Area | Files |
| --- | --- |
| Contract/vocabulary | `scripts/warband/warband_contracts.gd`, `cruor_catalog.gd`, `branded_skills.gd` |
| Persistence | `warband_state.gd` (autoload, `user://warband_state.json`), `warband_roster.gd`, `town_stash_model.gd`, `cruor_manager.gd`, `mercenary_vendor.gd` |
| Possession | `soul_router.gd`, `possession_controller.gd`, `possession_camera.gd`, `possession_sync.gd` |
| Combat bubble | `combat_bubble.gd`, `passive_duel_brain.gd`, `damage_scaler.gd` |
| Downed/revive | `downed_state.gd`, `crawl_to_safety.gd`, `revive_channel.gd` |
| Loot | `loot_vacuum.gd`, `warband_pickup.gd`, `soldier_loot_run.gd` |
| Crafting | `sacrificial_altar.gd`, `altar_menu.gd`, `quartermaster_menu.gd`, `ichor_bench.gd` (the reagent bench: one vial, one sigil, no essence) |
| Campaign ledger | `quest_log.gd` (`WarbandQuests`, `Warband.quests`), `quest_giver.gd` (the keeper's cards and the gold arrow's owner), `quest_marker.gd` (the arrow over a head) |
| The orders' ground | `soldier_cages.gd` (four caged soldiers and the latch), `watcher_warren.gd` (three warcamps of 21 wardens) |
| Loot | `loot_vacuum.gd`, `warband_pickup.gd`, `loot_hand.gd` (the click and the crouch), `loot_summary.gd` (the one line) |
| The map | `world_map.gd` (one page, `M`, fed by `WorldScene.map_markers()`) |
| Town folk | `town_folk.gd` (five armoured keepers), `town_guard.gd` (three static watch archers) |
| UI | `warband_hud.gd`, `warband_screen.gd`, `warband_paperdoll.gd`, `tutorial_card.gd` |
| World | `scenes/warband_world.tscn` + `world_scene.gd`: the one campaign scene. Owns the soul controller, camera, HUD, warband screen, paperdoll, tip channel, loot vacuum, crawl, revive, brand runner and the single ground (`terrain.gd`); builds the three areas and hands each the same controller. `GameFlow.world_start` says where the warband is put down ("camp" on a new game, "town" for a resumed save or the arena's return) |
| Areas | `cage_escape.gd` (the camp clearing: cages, latches, sequencer, watchers, the six that come out of the trees), `escape_run.gd` (the trail: pursuers and its two endings), `town_hub.gd` (the square: stalls, stash, altar, keeper, expedition gate). Each takes `host` — the world — and in `host != null` mode builds only its own content: no controller, no HUD, no environment, no door |
| Camp clearing | `camp_clearing.gd`: the camp as a clearing in the woods — treeline, 196 trees and 155 bushes round the edge, a broken stake fence (10 runs, 357 stakes), 17 torches, the mouth onto the trail |
| The trail | `run_forest.gd` (the 1,374.6 m way through the wood and its dressing — no lane, no walls, a worn line marked by paired torches; returns `{lane, length, width, torches, ...}`) + `squad_drive.gd` (the one follow/fight/retarget behaviour, shared by both areas) |
| Scenes (previews) | `scenes/cage_escape.tscn` and `scenes/town_hub.tscn` stay as area previews for the art and quartermaster tests; the campaign does not load them. `admin_arena.tscn` is the one scene change left |
| Netcode | `warband_session.gd` (+ `possession_sync.gd`) |
| Flow | `game_flow.gd` (the only thing that changes scene) |

Integration seams deliberately placed in the base game:
`WarbandDamage.scale(amount, self)` at the top of every `take_damage`
(`main.gd`, `arena_actor.gd`, `devil_mob.gd`, `enemy.gd`, `ranger_clone.gd`);
`downed` handling in `arena_actor.gd`/`main.gd`; `environment_kit.gd` fog fix.

---

## 3. Decisions that must not be regressed

1. **One shared contract file.** Enums/constants only in `warband_contracts.gd`.
   Never add a second damage multiplier, stash, purse or slot list.
2. **Damage is scaled once, at the victim's `take_damage`.** The bubble sets
   `WarbandDamage` state; never multiply again in combat code.
3. **Bubble = nearest human body.** ACTIVE inside 30 m, PASSIVE beyond 34 m; the
   human list is every peer in `SoulRouter.peers()`, so more players = more
   bubbles.
4. **Possession truth is `SoulRouter`.** One peer per body, ALIVE only, downed
   bodies eject their soul. Transfers are host-authoritative over the wire.
5. **The stash is one collective pool.** `Warband.equip_merc` transfers a worn
   piece off another body (or another slot) instead of refusing; a refused equip
   must never lose gear. `auto_equip` on pickup fills an empty slot or replaces a
   cheaper piece; the post-battle sweep never auto-equips.
6. **`seat_loadout()` is the spawn snapshot.** Put gear on a live body with
   `PossessionController.refresh_gear(merc_id)` (cage/arena/town all do this).
7. **Arena bodies target layer 4 by default.** Scenes that fight wilderness mobs
   (layer 2) must set `combat.target_mask` themselves; the cage uses 2 only, so
   the squad cannot cut itself.
8. **Nothing in the warband pauses the tree.** The tutorial card and its
   paragraphs are gone (the file is deleted): the opening teaches with `WarbandTips` (a key line and a
   command under the crosshair) and `warband_tips.gd` never pauses, never takes
   the pointer and never opens twice. A beat that offers a hint must leave the
   game running - `warband_world_regression` asserts `not paused` on every one.
9. **The player's own latch is the only bare-handed one.** `camp.interact`
   refuses every other cage without a blade ("Nothing to cut the latch with.");
   the own cage (`OWN_CAGE` 0) opens to a fist, because getting out of it is the
   first step of the game. Nothing about the squad AI is gated on a possession any
   more - a body is free the moment its own cage is open (`is_free`), and the
   clamp, not a script, is what holds the rest.
10. **Squad AI is silent about loot.** No pickup messages, no loot step in the
    objective. `K` still works for a human but is not advertised. A walk to a
    piece is abandonable and every errand else is not: `_walk_to_loot` gives a
    drop up when the body has not earned `FETCH_PROGRESS` 0.35 m of headway in
    `FETCH_GIVE_UP` 5 s, and the key joins `_abandoned` for the rest of the scene,
    so the whole squad is on to its next errand on that frame. Without it a freed
    squad that could not cross a cage wall to the shiv stood shouldering the wall
    for the session and the run never started. The piece stays for the player.
11. **Kills landed before the squad is out do not count** (`note_guard_killed`
    refuses pre-FREED). `TutorialSequencer.note_battle_state()` reconciles the
    totals on entering FREED and is silent when nothing changed (recursion guard).
12. **Ground is bigger than the walls, always.** The cage yard is 60 × 68 m inside
    a 100 × 140 m floor plus an invisible catch floor; never put a spawn outside
    a floor.
13. **Scene doors are one signal per scene** (`scene_requested(path)`), bound to
    `GameFlow`; scenes never load other scenes.
14. **The camp's fight tuning is deliberate:** watchers have 72 health / 5 damage
    / run 5.6 / sight 60 / orbit 1.9 and must be pointed at the squad on spawn
    (`CageWatcher.hunt`); the second wave is **six** armed watchers, 2.5 s after
    the first pair, each dropping its weapon; the escape needs eight kills.
15. **The opening never moves the player** (no auto-possession, no auto-walk) and **loot is not announced** —
    both were explicit player requests. Do not reintroduce auto-possession or
    pickup feeds.
16. **One world, and the only travel is a walk.** `scenes/warband_world.tscn` is
    the campaign: camp, trail and town share one scene, one soul controller, one
    HUD and one ground (`terrain.gd`'s heightfield - the camp pocket and the town
    square padded flat into it, the walk between them rolling). No key loads a
    scene to travel — `G` is an interaction
    (latch, stash, altar, keeper, deploy), never a door — and the only scene change
    left is deploying to the arena. Areas never build a controller, a HUD, an
    environment or a door of their own: they take `host`. `run_forest.gd` must keep
    returning a way a body can actually traverse, and `warband_world_regression`
    drives the cage line to the town square asserting that
    `current_scene`, `GameFlow.transitions` and `scene_requested` are untouched — a
    prop, a trunk on the centre line or a bounds clamp that narrows the world is a
    test failure, not a matter of taste.
17. **The warband door is a new campaign.** `GameFlow.start_campaign()` resets the
    warband *and* `PlayerState` (the purse is the shared wallet) and enters at the
    cages; `enter_warband()` is the resume path and is not what the title calls.
    `title_menu_regression` pins it with a saved warband that must not survive the
    click.
19. **The latches are the objective, and the leaving is the ambush.** There is no
    auto-opening and no possession gate: every cage but the player's own takes a
    `G` with a blade in hand, one press each, and the fifth puts the warband on its
    feet (`WARBAND`). `ESCAPING` is the body crossing the mouth, and that frame
    spawns the four armed watchers; `GUARD_COUNT` is a tally, not a gate. The road
    never spawns a cultist with a quarry: `wake_road` hands a third of each ring
    the soul at the leaving, and the rest notice by sight.
21. **Nothing solid stands on the way's centre line.** There is no lane: the route
    is a worn line through standing wood, and `CLEAR_HALF` (1.55 m) either side of
    it holds nothing a body can walk into, so the narrowest gap on the centre line
    is 3.1 m. Torches sit on the verge at 4.4 m, trees and brush stand *inside* the
    walked band beyond that line, and every prop is lifted onto the heightfield's
    ground. A 0.2 m post on the centre line stops a body dead, and the trail's own
    regression measures the clearance off the collision the wood carries.
22. **The squad attacks; circling is punctuation.** The party swings the moment
    its blade is free and holds a guard between swings. It breaks off to circle
    only after a few swings and only sometimes, and it blocks while it circles -
    a squad that orbits while being hit is the failure this rule exists to stop.
20. **No body gets a private health pool.** Every mercenary is 100 health - all
    five prisoners and every soul a cage frees included. A private pool breaks the
    equal-stats contract and carries into the roster. If a scripted fight is too
    costly, fix the fight (the shiv's stab passive is what makes a shiv work), not
    the pool.
18. **The hand torch is one module and one brightness.** `torch_light.gd` owns the
    item's visual (shared with the icon studio through `build_visual`) and its light
    (7.5 energy, 26 m, warm): a carried torch has to be brighter than the trail's
    fixed 3.4/16 m pools. It polls the roster, so every gear path — paperdoll, stash,
    loot — lights or douses it without being told.
23. **A checkpoint is the warband's save, not a second file.** `Warband.save_checkpoint()`
    writes the roster, stash, essence and the `{id, area, position, label, at}`
    bookmark to `user://warband_state.json` in one call (save version 4). It is
    written at exactly two moments — the camp's six watchers down (`trail_start`)
    and the town square entered (`town`) — once per id, so walking back and forth
    cannot hammer the disk; `sanitise_checkpoint()` is the only reader, and a v3
    file (no bookmark) still opens at the town. A wipe reloads it (downed bodies
    wake at half health; dead bodies stay dead) and the **purse is never rolled
    back**, because `PlayerState` owns it and a reload must not replay a payment.
    A checkpoint start never re-runs the lesson: `CageEscape.prepare_resume()` is
    called before the camp enters the tree, `place_resumed()` opens the four
    cages, and no watcher is fielded. `GameFlow.active` still gates the scene
    change, so a regression harness never gets teleported by a wipe.
24. **Co-op is the host's world seen through one window.** The campaign opens as
    host or guest through `GameFlow.host_campaign`/`join_campaign` over the one
    existing `WarbandSession` (never a second socket); `attach_world(world)` is
    called once, by `_seat_warband_link`, for the world scene only, and that one
    call is the whole world half. The host is authoritative for mobs, loot,
    missiles and rewards: snapshots are **keyed by the guard's node name** (never
    an index) and sent at 15 Hz within 70 m of any body through `NetLimits`, so
    the wire can never invent a mob and a repeated batch is a no-op. Every guard a
    guest holds is a `replica`: it runs no AI and `apply_snapshot` is its only
    writer. Loot is announced once, reliably, and re-spawned as the same
    `WarbandPickup`; a replicated missile is a visual with an empty hit mask; and
    **only the host's `defeated` signal pays**, through `receive_reward` into
    `PlayerState`. A guest also writes **no checkpoint and no save of its own**
    (`_check_checkpoints` returns on a client), dismisses the camp's lesson
    (`camp.dismiss_lesson()`) and disables its squad AI. The lobby's mode row
    makes **campaign co-op the default** and keeps the stand-alone arena bout as
    the first, selectable row; the arena field is deliberately not attached.

25. **The first eight oaths are free.** `WarbandVendor.FREE_HIRES` is 8 and
    `hire_cost()` answers 0 under it, because eight bodies *is* the deployment
    cap: the recruiter garrisons a band, he does not sell one. Past that the old
    120 + 35/body curve is still there for the day the cap moves. A hire (and a
    rescue) dresses itself out of the shared stash — `Warband.dress_recruit()`
    walks `DRESS_SLOTS` and takes the dearest spare for each slot it can fill, so
    a body never takes the field empty-handed and nothing is minted to arm it.
26. **One ledger, five goal shapes.** `scripts/warband/quest_log.gd`
    (`class_name WarbandQuests`, `Warband.quests`) is the only place an objective
    lives: `KILL` / `RESCUE` / `COLLECT` / `APPLY` / `REACH`, one row each in
    `DEFS`, progress and state keyed by id and saved as v5 (`quests`). The two
    shapes the campaign leans on — *kill X of a mob*, *rescue X bodies* — are
    table rows, not code paths, so a new bounty is a definition plus one
    `note_*` call. The world counts deaths (`WorldScene.note_kill`, from both the
    wilderness handler and the trail's own) and the cages count rescues
    (`note_soldier_freed`, which is also what joins the body to the roster).
27. **The keeper who speaks speaks first.** `QuestGiver.talk(service, peer)` runs
    before the counter opens: a card for an order, a turn-in, or the vial; the
    counter is the next press. It can be two cards in a row (the ichor order, then
    the bench lesson) and that is correct — a test that presses a counter once
    must close cards until the panel opens rather than assume one press.
28. **A click on lootable ground is the loot, not a swing.** `WorldScene._input`
    reads the press before the soul controller's `_unhandled_input`, so
    `WarbandLootHand.try_click` can consume it; nothing lootable under the
    crosshair falls through and lands as a cut exactly as before. The channel is
    0.9 s with the body crouched, it breaks on a downed body, a walk-off or a
    panel, and the whole container empties through the vacuum's one booking path.
    One line says what came back (`LootSummary`); there is no piece-by-piece feed.
29. **The map is one page drawn from the world.** `world_map.gd` (`WorldMap`,
    `M`) never pauses, has no state of its own and takes its content from the
    host: the lane is sampled from `trail.forest["path"]`, and the orders are
    `host.map_markers()` — the world answers with the shut cages and the warcamps.
    A place that does not exist (the Crypt) is a quest row and never a mark.
30. **Gates span the road; nothing solid stands in it.** A gate or an arch rotated
    with its span *down* the lane stands both posts on the centre line (the bone
    arches and the TOWN gate did, and the kilometre-and-a-third walk drove into a
    post and stopped). `_yaw_facing(forward)` puts the span across the road. The
    contract is measured off *every* collider the lane carries, not just the tree
    rows: nothing may sit within `CLEAR_HALF` 1.55 m of the centre line.
31. **Ichor is item-shaped; essence is a wallet.** A warden's ichor is a carried
    catalog piece (`ichor_vial`), dropped deterministically by four of the twelve
    watcher variants. `IchorBench.apply()` spends one vial and calls
    `WarbandCruor.bind()` — the same brand ledger the altar writes, with the
    essence step removed — so the sigil tile, `R` and the tooltip all work with no
    idea that a reagent paid for them. An already-branded piece is refused there;
    rerolling stays the altar's job.

### Tuning knobs (one place each)

| Knob | Where | Now |
| --- | --- | --- |
| Watcher pools | `cage_watcher.gd` | pair 21 with `blow_scale` 0.5 and `windup_scale` 2.4 (`PAIR_LESSON_HEALTH` / `PAIR_*` in `cage_escape.gd`), the ambush 42, everyone else 144 (braced); damage 5, run 5.6, sight 60, orbit 1.9 |
| Second wave contents and post positions | `cage_escape.gd::REINFORCEMENTS`, `REINFORCE_POSTS` | 6 arms, outside the gate |
| Delay before the second wave | `cage_escape.gd::REINFORCE_DELAY` | 2.5 s |
| Total watchers in the opening | `tutorial_sequencer.gd::GUARD_COUNT` | 6 (the pair + the four at the leaving); a tally for the checkpoint, never a gate |
| Revive / overkill / bubble / cap | `warband_contracts.gd` | 5 s / 10% (arena seats; warband bodies always down, and any blow on a downed one finishes it) / 30-34 m / 8 |
| Clearing size | `camp_dressing.gd` (`YARD_*`), `camp_clearing.gd` | 40 × 52 m pocket padded flat into the heightfield, wood immediately outside: 402 trees and 828 bushes in the band (24 trunks inside the pocket), 97 ragged stakes |
| Camp torches | `cage_escape.gd::CAMP_TORCHES` | 11 (the cage ground, mouth, both flanks, the rim), each on the ground's own height |
| Cages | `cage_escape.gd::CAGE_POSTS` | 5, scattered: own cage at the pocket's centre, four others behind the lean-to, on the far right, deep left by the den and right by the watchers |
| The way through the wood: length, clear line, torches | `run_forest.gd` | **1,374.6 m** (31 waypoints, 45 m z-steps), **154 torches** (a pair every 18 m at 4.4 m, the only thing that marks the route), **no lane and no walls** — 2,467 trees and 3,421 bushes in the band, 581 solid trunks and 327 rocks, and a 3.1 m clear line (`CLEAR_HALF` 1.55 m) down its middle. Two bone arches and the TOWN gate span the road (`_yaw_facing`), never down it |
| Mob guard | `devil_mob.gd::GUARD_REDUCTION`, `cage_watcher.gd` | braced most of its cycle, 65% of a blow turned; warband cultists only (`guard_between_swings`) |
| Squad rhythm | `squad_drive.gd` | one per-ally ladder (close / swing / guard / circle / reset) on every frame; the exchange rolls once when the blade frees: 55-70% guard for 0.35-0.80 s, 1-3 swings then a 0.25-0.55 s short rugged circle re-rolled every 0.12-0.20 s |
| Party start | `cage_escape.gd::_dress_rags` | one brown sack on the chest, nothing else, no weapon anywhere |
| Corpse loot | `cage_watcher.gd::gear_items`, `squad_drive.gd::LOOT_CLEAR_METRES` | a cultist drops its blade and its rag; the squad strips the field only when no hostile is within 22 m |
| The world: night | `run_forest.gd::night_style()` | ambient 2.5, sun 0.55, fog 0.012, filmic, saturation 0.80 |
| The world: pursuers | `cage_escape.gd` (`GATE_WATCHERS`, `REINFORCEMENTS`), `escape_run.gd::ROAD_PER_POST`, `run_forest.gd::CLEARING_FRACTIONS` | 61 in one hostile list: 2 in the clearing, 6 out of the trees at `ESCAPING`, 20 on the road (2 per post, 10 posts: first at 10% of the lane, then 22/44/66/88%), 6 archers in two ambushes, 8 wolves, 21 warcamp wardens. Nobody carries a spawn-time quarry; `wake_road` gives a third of each ring the soul at the leaving |
| Hand torch | `torch_light.gd` | off hand, 45 gold, 7.5 energy / 26 m / attenuation 1.0, polled every 0.2 s |
| The world: budget | `warband_world_regression.gd` caps | nodes ≤ 26000 (now 6151), draws ≤ 800 (604), shapes ≤ 1400 (586), lights ≤ 210 (190: 152 of them the trail's torches) |
| The world: walk | `warband_world_regression.gd` | 49 m opening + 1,575 m through the wood = cage line → town square over the heightfield's slopes, 159 s of game time, 0 scene changes (driven at 4.2x so the whole regression stays inside 72 s) |
| Town lanterns | `town_dressing.gd` | 4 posts, 3.2 energy / 15 m, attenuation 1.1 |
| Wipe | `world_scene.gd::WIPE_BEAT` | 2.5 s after the last body falls, then the last checkpoint; with no bookmark the wood simply takes what is left |
| Loot auto-equip rule | `warband_state.gd::auto_equip` | empty slot or better than worn |
| Checkpoint moments | `world_scene.gd::_check_checkpoints` | `trail_start` when the camp's six are down and the squad is leaving (60 m past the mouth), `town` on entering the square; one write per id |
| The cage line | `soldier_cages.gd` | four cages at lane fractions 0.34 / 0.52 / 0.68 / 0.86, 7.6-8.6 m off the line (alternating sides), `LATCH_REACH` 2.2 m from a footprint edge, `CAGE_BAR_LIFT` 2.6 m, soldiers `Bren / Hask / Ilse / Torvin` |
| The warcamps | `watcher_warren.gd` | three camps of seven hollow wardens at fractions 0.72 / 0.80 / 0.90, **78 / 96 / 86 m** off the lane (past twice a warden's 60 m sight), one shared `MobWander` territory each, dressing from the village kit |
| Free oaths and the dressing | `mercenary_vendor.gd::FREE_HIRES`, `warband_state.gd::dress_recruit` | the first 8 cost nothing (and 8 is the cap); a hire or a rescue takes the dearest spare in the shared stash for `main, off, head, chest, hands, legs, feet, neck, ring1, ring2` |
| The ledger | `quest_log.gd::DEFS` | four rows: `free_the_soldiers` (rescue 4), `cull_the_watchers` (kill 20 `hollow_warden`), `find_the_crypt` (reach `crypt`, a shell with no place), `bind_the_ichor` (apply one `ichor_vial`) |
| The ichor | `cage_watcher.gd::_stamp_carried`, `ichor_bench.gd` | four of twelve variants carry a vial; one vial binds one pooled weapon at `T1_RITUAL_TALLOW` with no essence spent |
| The loot click | `loot_hand.gd` | 0.9 s channel, 0.25 s cooldown, 2.0 m pile radius, 1.5 m walk-off, `LOOT_REACH` 2.6 m |
| The map | `world_map.gd` | one page, `M`, never pauses, `REPAINT_SECONDS` 0.1, marks from `host.map_markers()` |
| Town | `town_hub.gd` | `WALL_RADIUS` 22, 286 palisade stakes with one gap, 8 roofs (5 halls / 2 round huts / 1 stall), 5 armoured keepers, 3 watch archers at 26 m sight, 16 lights |
| Deep-wood wolves | `wilderness.gd::PACKS` | eight **kind 0** briars in two packs of four at 62-80 m and 688-712 m, 30-50 m off the line (one beside the checkpoint corridor, one deep on the lane; both beyond the wolf's sight of the route), nothing on the lane or corridor, `MOUTH_CLEARANCE` 25 m, 0.5 s target refresh, `PACK_RADIUS` 14 m |
| Warband ability keys | `possession_controller.gd::_command` | plain 1/2/3 → slots 0/1/2 (Shift+1..3 is the same press); the HUD tiles read the possessed body's runner every frame and hide an ungranted slot |
| Campaign menu | `warband_menu.gd` | six rows; SAVE `Warband.save_state()`, LOAD re-reads then re-enters the world, SETTINGS the shared sound page + display row, exit label scene-owned (`EXIT TO TITLE`), exit/quit save first, never pauses the tree |
| Expedition waves | `expedition_director.gd` | 5 waves 3/4/4/5/6, tiers makeshift→mail, 2 s gap, boss 2x health + 2 escorts, 175 gold + 6 essence on clear |

### Godot gotchas found the hard way

- Assigning `Environment.fog_mode` **resets `fog_density` to 1.0**; write the
  density after the mode (`environment_kit.gd`).
- A shoulder camera behind a cover tree is pulled in by its own occlusion ray —
  leave the boom room at spawn.
- `super._profiles()` returns a **const** dictionary: duplicate before tuning.
- Preload collisions: a script that already preloads `SeatLoadout` must not
  preload it again.
- Headless tests must not be teleported by a scene door: `GameFlow.active` is
  false until the campaign door is used.
- Animating/stepping: fighter brains run **before** `controller.physics_step`;
  mobs tick themselves.

---

## 4. Test inventory (all headless, all green at handoff)

| Test | Checks | Covers |
| --- | ---: | --- |
| `warband_contract_regression` | 180 | enums/slots, overkill, soul locks, roster, stash, cruor, gear hand-offs, auto-equip, vendor |
| `possession_regression` | 262 | bodies, cycling, camera (including free look: the whole sphere, a composed basis at both poles, and the eye kept out of the body's own column), net transfer, auto-eject |
| `downed_revive_regression` | 67 | 10% overkill, crawl, 5 s channel |
| `combat_bubble_regression` | 73 | 30/34 m, 10%, guard choreography, hysteresis |
| `altar_regression` | 112 | unbind/distil/brand UI over the wallet |
| `stash_autoloot_regression` | 170 | pickups, sweep, infinite value sort |
| `warband_ui_regression` | 99 | roster screen, paperdoll hand-off, recruiter |
| `branded_abilities_regression` | 114 | six sigils, tiers, refusals |
| `enemy_waves_regression` | 108 | cultists, waves, soldier loot run |
| `town_hub_regression` | 71 | services, hire, deploy, paperdoll (the square as an area) |
| `duel_lesson_regression` | 54 | the first fight's machine alone: nothing advances before the body is taken, one card per fact in order, the target watcher's windup does not teach the guard while its partner stands, a block before the card is not booked, the pair falling ends it, `reset()` starts over |
| `cage_escape_regression` | 341 | cards/pause, the four duel cards and their triggers, the shiv pickup, the player's own swing biting a watcher, a raised guard on the second watcher, the revive card on a fallen ally, the four latches cut one G at a time, the squad arming, the six at the mouth, drops |
| `escape_run_regression` | 195 | the trail as an area: a 1,374.6 m lane walked over a 420 m stretch, art budget, the hunters spaced and never handed a quarry at spawn, the leaving waking them, the escort arriving (three within 20 m), both endings |
| `torch_light_regression` | 24 | the torch is a legal off-hand piece, lit on the body that wears it, 7.5 energy / 26 m, and dark again when it comes off |
| `warband_world_regression` | 250 | one scene and one controller, the camp in the trees, the new opening, 1,575 m camp → town with no scene change, the services and the keepers' cards at the far end, no ally abandoned, budget |
| `warband_abilities_regression` | 42 | plain 1/2/3 starts the body's three slots (Shift+1 is the same press, not a requirement), the stamina bar and three tiles read that body, an ungranted slot hides, RMB peeks only in cover and guards everywhere, one authoritative cue spawns exactly one arrow/spell |
| `warband_menu_regression` | 41 | the six rows, SAVE/LOAD over `Warband.save_state`, LOAD gated on a real file, the sound page and back, `resumed` on every close, and the tree never paused |
| `warband_vendors_regression` | 151 | three counters as `G` services in the market ring, each opening its own seat and stock; buy into the shared stash, sell one pooled copy at 60%, a short purse spends nothing, a worn copy is not on the board, closing leaves no panel |
| `warband_wilderness_regression` | 75 | eight kind-0 wolves in two deep packs inside `guards`/`wild_mobs`, clear of the mouth, pocket and lane, aimed at the standing body, pack wander, and one `MobCuller` sweep parks a wolf left 300 m behind |
| `warband_session_world_unit_regression` | 38 | no socket: one name-keyed mob entry, a batch fits one datagram, replica write + tick, an unknown name invents nothing, loot and missile announcements book once, a reward books once, and both campaign doors against a temp save |
| `warband_lobby_campaign_regression` | 48 | the lobby defaults to CAMPAIGN (CO-OP), the arena stays the first selectable row, both payloads name the right scene, and switching back and forth (or a cache read) keeps the mode |
| `warband_integration_regression` | 38 | the real world binds every seated body to `WarbandAbilities`, fields the wolves and their culler, paints the stamina bar and three tiles, opens/closes the menu from a real Escape without pausing, and never hands a human body to squad AI |
| `warband_coop_campaign_regression` | 63 | two real processes: the host opens the campaign on its save, a guest joins and is given a body, its walk reaches the host, the host kills a replicated guard, loot crosses, the reward is paid once, and a leaving guest's body falls back |
| `expedition_regression` | 42 | deployed line, five waves, loot run, return |
| `expedition_director_regression` | 154 | five-wave curve 3/4/4/5/6, boss at 2x with a run-scoped brand, rewards once, wipe pays nothing |
| `branded_world_regression` | 48 | the sigil tile: tier line, cost, cooldown vs READY, rebind, a real `R` hit |
| `warband_art_regression` | 192 | camp/town dressing counts, materials, nothing solid inside the play space |
| `warband_appearance_regression` | 206 | the look table loads and starts each palette at the measured base, a look is a pure function of the id (order- and cache-independent), eight deployed bodies differ in face, cut, skin, shirt and shorts, every named piece exists in the assets, and the rig, an actor and an undressed body all apply or ignore it correctly (hair under a helmet, head zones scaled) |
| `warband_lobby_regression` | 56 | two peers through the title lobby, socket survives the hand-off, refusal verbatim |
| `run_persistence_regression` | 196 | battle ledger, history + lifetime totals, reload pays nothing twice, a v1 save still loads |
| `checkpoint_regression` | 72 | the v4 bookmark round trip, garbage refused, v3 saves still load, a wipe's restore (downed wake, dead stay dead, purse untouched), trail and town resumes in the real world, the retry door, the title's resume door |
| `game_flow_regression` | 22 | world → arena → world on one save |
| `admin_arena_regression` | 98 | bubble, downed, revive, loot, altar, screen, two peers |
| `quartermaster_regression` | 20 | keeper price, purse, refusal |
| `warband_session_regression` | 49 | two real ENet processes |
| `quest_log_regression` | 96 | the ledger alone: the five goal shapes, offer/accept/turn-in guards, kill counting by mob id, the chain to the Crypt shell, the ichor's APPLY order, save v5 round trip, free hires and the stash dressing, and the keeper's tips and arrow |
| `town_stockade_regression` | 239 | the town as a place: the stake ring and its one gap, 8 roofs standing clear of every service ring and the gate lane, 5 armoured keepers that cannot be possessed or hit, the gold arrow moving recruiter → quartermaster, the recruiter's tip then board, the quartermaster's order on the same press, the ichor service, and a watch archer putting a real arrow into a wolf |
| `wild_cages_regression` | 102 | the orders' ground on the real world: four cages on the ground and clear of the lane, the latch refusing bare hands, four names on the roll and four marks on the rescue order, 21 wardens in `guards` (nearest camp 72 m off the lane), a body standing on the lane never waking a camp, and one death counting toward the bounty |
| `loot_wow_regression` | 213 | the wolf's salvage table (deterministic per body), the booking path, `LootSummary` wording, five salvage silhouettes, the click/crouch/cancel gesture on stub bodies, and the wardens' 4-of-12 ichor split |
| `world_map_regression` | 64 | the grown lane and field, and the page: bounds, projection monotonicity, every mark inside the panel, the legend, open/close, metres-per-pixel |
| `ichor_bench_regression` | 28 | one vial, one sigil: the vial leaving the stash, the brand landing in the altar's own ledger at T1, no essence spent, an already-branded piece refused, and the order accounting for the bind |

Relevant legacy tests that must stay green when touching shared files:
`gameplay`, `combat_expansion`, `net_limits`, `world_art`, `mob_aggro`,
`paperdoll`, `town_services`, `title_menu`, `world_ui`, `hitbox`, `block_clash`,
`draw_combat`, `ranger_clone`.

Run the gate (31 tests, none of them socket tests running concurrently):

```bash
GODOT=./.runtime/godot/Godot_v4.7.2-stable_win64_console.exe
OUT=C:/tmp/gres; rm -rf "$OUT"; mkdir -p "$OUT"
LIST="warband_contract possession downed_revive combat_bubble altar stash_autoloot
warband_ui branded_abilities enemy_waves town_hub cage_escape escape_run
warband_world torch_light expedition
expedition_director game_flow admin_arena quartermaster branded_world warband_art
run_persistence gameplay combat_expansion net_limits world_art mob_aggro paperdoll
town_services title_menu world_ui hitbox block_clash draw_combat ranger_clone"
n=0
for t in $LIST; do
  $GODOT --headless --path . --script "res://tests/${t}_regression.gd" > "$OUT/$t.txt" 2>&1 &
  n=$((n+1)); [ $((n % 12)) -eq 0 ] && wait
done; wait
grep -l "failures=[1-9]" "$OUT"/*.txt || echo "gate green"
# then the socket tests, one at a time (they bind ports):
for t in warband_session warband_lobby; do
  $GODOT --headless --path . --script "res://tests/${t}_regression.gd" | tail -1
done
```

**Measure before you wait.** Twelve at a time takes ~90 s for the whole gate on
this machine; six at a time took minutes because the long tests are long, not
because the short ones are. `gameplay`, `world_art` and `title_menu` print
`<NAME>_REGRESSION failures=0` without a `checks=` counter — that is not a
missing result. Never run all 66 `tests/*_regression.gd` as a per-merge gate;
that is the pre-merge full suite, once, at the end.

---

## 5. Known gaps / rough edges

- **Both machines must load the same warband save.** The session replicates the
  bodies, not the roster or stash, so a peer with a different save renders the
  same seats but its own gear and health.
- **Only the campaign world is replicated, not the arena.** `attach_world` is
  wired for `scenes/warband_world.tscn` only, so in the campaign the host owns the
  mobs (15 Hz, name-keyed snapshots), the loot, the missiles and the kill reward,
  and a guest is a participant — its intents ride `PossessionSync` and the host
  resolves them. The arena's own field is deliberately not attached: an arena
  guest still sees its own local `EnemyWaves`.
- **Cultists carry a brand but cannot cast it.** The Bilewarden's sigil is
  identity, kit provenance and a field label (`CultistGuard.brand`) — a
  `BrandedRunner` on a cultist is Phase 4.
- **Prediction has no ack.** `PossessionSync` sends direction, not frame numbers,
  so a guest's copy can be ~0.4 m off the host's (the session test asserts the
  bound, plus no jumps). Fixing it needs a sequenced input channel in
  `possession_sync.gd` + `possession_controller.gd`.
- **Expedition is three fixed waves** with one loot table; no scaling, boss,
  rewards screen, or difficulty by depth.
- **Branded skills are only bound in the arena** (`R`); the town/paperdoll shows
  the sigil line but the expedition uses the same arena scene, so it works there.
  Town has no combat to use it in.
- **No audio pass** for the new mode (the base game's `range_audio` is untouched).
- **The town is authored from the village kit, the cage line is not**: eight roofs,
  a stake wall and five keepers are built out of `VillageKit`; the four cages in
  the wood and the three warcamps are still primitives and kit dressing.
- **The Crypt is a shell.** `find_the_crypt` is offered, accepted and tracked, and
  there is no place in the world that answers it: `note_reached("crypt")` has no
  caller. That is the order the campaign's over-arching test is built on, and it
  is deliberately empty.
- **The map has no fog and no zoom.** It draws the whole wood on one sheet; a
  survey it has not seen (the Crypt) is simply absent.
- **Ichor binds at one tier.** The bench always writes `T1_RITUAL_TALLOW`; deepening
  a sigil is still the altar's job, paid in essence.
- **A rescued soldier joins the roster, not the field.** The body that walks out of
  the cage is a figure that fades; the record appears at the next town or battle,
  because bodies are spawned per scene by the controller.
- **The watch archers only cover the gate.** Three posts, 26 m, line of sight on
  layer 1; nothing else in the town shoots.
- **Roster persistence during a battle** is mirrored every 0.4 s and saved on
  scene exit; a hard kill mid-battle can lose the last moments.
- **`arena.tscn`'s own lobby backdrop** renders washed out in this build; it does
  so in the original repo too and is unrelated (the admin arena looks right).

---

### Phase 4 (landed): the first town and the orders

Four branches and one foundation on one integration tree. The foundation is the
campaign ledger (`quest_log.gd` + `Warband.quests`, save v5), the keeper who talks
(`quest_giver.gd`), the arrow (`quest_marker.gd`), the free first eight oaths and
the stash dressing, and the two material families (wolf salvage, warden ichor).
The branches own the town (palisade, gate, eight roofs, five armoured keepers,
three watch archers), the orders' ground (four caged soldiers, three warcamps of
21 wardens), the loot (wolf drop table, the click-and-crouch hand, one summary
line, five salvage silhouettes) and the world (a kilometre-and-a-third lane, a
grown heightfield, the map sheet). The ichor bench was built with the foundation
because the town needed it to place.

The integration pass found things no unit test could, and all of them are fixed:

* the lane's arches and the TOWN gate were rotated with their span **down** the
  road, so their posts stood on the centre line and the walk drove into a post
  (`run_forest._yaw_facing`);
* the body's own `BODY_BOUNDS` stopped 180 m short of the new town;
* the escort was found standing in the camp's tree band four minutes after the
  soul reached the gate - two allies each moving a centimetre a frame and getting
  nowhere. The squad now follows the **soul's own footprints** when it is more than
  a few strides behind, a body that covers no ground across a two-second window
  backs out of the pocket and tries again, and it does not stop an escort to fetch
  loot it walks past;
* twenty-one wardens patrolled the lane after a squad that never left it, and the
  town's pad was a pale apron eight metres past the wall.

`warband_world_regression` now walks the whole 1,575 m, asserts every ally walked
out on his feet and none is stranded, and reaches the square in about 63-100 s.

## 6. Next phases — ready to parallelise

The workflow that produced the current build: a Phase-0 contract commit on
`main`, then N isolated `git worktree`s (one branch each), one agent per
worktree, merge into `main` in order, run the gate suite. See §8 for commands.

### Phase 3 (landed): depth, rewards and multiplayer UX

All five worktrees are merged and gated. The briefs stay in
**`docs/warband-phase3-briefs.md`** as the record of what each branch owned.

What landed: the expedition is five director-paced waves (3/4/4/5/6) ending in a
Bilewarden at double health, with a once-only gold/essence payout and a mission
summary; the arena HUD shows the soul's sigil (tier line, cost, cooldown) and `R`
works there; the title screen hosts and joins a warband battle and the ENet peer
lives under `GameFlow` so it survives the hand-off; the camp and the town are
dressed from the world kits; and every battle is filed in the warband's save with
a bounded history and lifetime totals shown on the roster screen.

| Worktree | Owns (create/edit ONLY these) | Deliverable / acceptance |
| --- | --- | --- |
| `wt-12-expedition-director` | `scripts/warband/expedition_director.gd`, `tests/expedition_director_regression.gd`, and `admin_arena.gd` (single owner this phase) | Waves come from `EnemyWaves` but are paced and scaled by a director: 3 → 5 waves, kit tiers by wave, a boss wave (one `CultistGuard` at 2× health with a branded weapon), gold + Cruor rewards on clear, and a mission summary (items looted, kills, gold). A test drives wave 1 → boss and asserts the rewards and the summary counts. |
| `wt-13-branded-in-world` | `scripts/warband/branded_hud.gd`, `tests/branded_world_regression.gd`, small hooks in `admin_arena.gd` **only via a signal it exposes** | A brand HUD tile (icon, cooldown ring, tier) on the arena/town HUD, the sigil line in the paperdoll already exists; `R` works in the expedition; an unbranded item shows nothing. Test builds an actor with a brand, asserts the tile text/cooldown and a real hit. |
| `wt-14-warband-lobby` | `scripts/warband/warband_lobby.gd`, `title.tscn`/`title.gd` (single owner this phase), `tests/warband_lobby_regression.gd` | Host/join UI on the title: name, port, HOST WARBAND / JOIN WARBAND; it starts `WarbandSession` and passes the intent through `GameFlow`; a guest's possession works in the arena. Test: two processes, guest asks for a body, host refuses a taken one. |
| `wt-15-camp-and-town-art` | `scripts/warband/camp_dressing.gd`, `scripts/warband/town_dressing.gd`, `tests/warband_art_regression.gd` | Authored-looking camp (cage bars, gibbets, cult banners, ember lights) and town (awning, signpost text, fire), using `Geo`/`TextureLibrary` and the existing world kits; the cage/town tests keep passing and `world_art_regression` stays green. No new collisions inside the play space. |
| `wt-16-run-persistence` | `scripts/warband/run_report.gd`, `tests/run_persistence_regression.gd`, `warband_state.gd` §persistence only | Battle results written to the warband save: roster health/downed at the moment of leaving, gold earned, Cruor earned, a per-run record (wins, wipes, best wave) shown on the roster screen; loading restores it. Test saves mid-run state, reloads, and compares. |

**Gate 3:** merged in the order 13 → 14 → 15 → 12 → 16 (13 and 14 touch no file
12 owns; 12 and 16 each needed one integration fix), gate green after the batch:
the 31-test gate in §4 plus the two socket tests. One integration defect was
caught and fixed at the merge: the report test was written against the
three-wave arena and now walks the director's five.

**Gate 3, rendered:** the camp, its arch, the road (three vantages plus the
player's own shoulder camera), the town and the expedition arena were rendered in
a real window and looked at, which is what caught the two defects no headless
assertion could: the road as a corridor of black (torches at 2.6 energy over 20 m
and 1.15 ambient) and the camp as a night with no vision at all, its torches bare
glowing spheres. Both are fixed (`a8ee1f2`, `9b1b66a`); the road now reads as a
chain of fire and the camp as a lit holding pen.

**Still not exercised on a display:** driving the opening with real input (the
own latch, the bearings step, the blade and the pair, the four cuts, the leaving)
and a second peer through the lobby. Every check for those is headless. Do that
first in the next session.

### Phase 4 (later)

- **Give the arena the world channel**: the campaign's mob/loot/missile/reward
  replication lives behind `WarbandSession.attach_world`, wired only for the
  campaign world; the arena's field is still each peer's own.
- Cult brands that cast: give `CultistGuard` a `BrandedRunner` so the
  Bilewarden's `shockwave_cleave` is a mechanic, not a label.
- Campaign levels reusing the warband loop (the base game's `docs/storyline.md`
  beats mapped onto warband expeditions).
- The run through the woods wants a mid-run beat: a shrine or a camp the squad
  can be pinned at, not only three clearings of pursuit.
- Audio: cage ambience, gate crowd, impact layers for the squad, the woods.
- Balancing pass driven by a bot-only headless run (win rates per wave count).

---

## 7. Session-start checklist for the next agent

1. `cd C:/tmp/ironwood/ghost_of_the_warband && git log --oneline -10 && git status`.
2. Read `docs/warband.md` §§1–3 (numbers + architecture) and this file §§3–4.
3. Run one fast test to prove the toolchain
   (`warband_contract_regression` or `cage_escape_regression`).
4. Pick a Phase 3 worktree from §6, create it (§8), and give the agent the brief
   verbatim plus the shared rules:
   - only its owned files; never the shared `scripts/warband/` libraries;
   - no stubs/TODOs; commit only when its own test is green;
   - run no rendered windows; the merge owner runs the gate suite.
5. Merge order: 12 → 13 → 14 → 15 → 16 (12 first because it owns
   `admin_arena.gd`). Re-run the gate suite after each merge, then the whole list
   in §4.

---

## 8. Worktree recipe (what the earlier phases used)

```bash
cd C:/tmp/ironwood/ghost_of_the_warband
git worktree add ../gotw-wt12 -b wt-12-expedition-director main
cp -r .runtime ../gotw-wt12/ && cp -r .godot ../gotw-wt12/
# agent works in C:/tmp/ironwood/gotw-wt12, runs its own test, commits
cd C:/tmp/ironwood/ghost_of_the_warband
git merge --no-ff wt-12-expedition-director
./.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
# run the gate suite (§4), then:
git worktree remove --force ../gotw-wt12
```

Commit messages in this repo are prose with the *why*; keep that style.
