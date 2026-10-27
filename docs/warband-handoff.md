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

1. **Cages.** The soul is in one of four caged prisoners. Shift between all four
   (`[` `]` or F1–F4). A big **card pauses the game** on every beat and names the
   keys; it closes on CONTINUE / G / Enter / Escape.
2. **The rescuer.** Corvin runs in with a shiv and **stands still**. The player
   must take his body themselves (F5 or `[` / `]`); no latch opens before that.
3. **Latches.** Walk to each of the four cages and press **G**. Each cage opens
   individually; freed prisoners become **squad AI**: they pick up the steel on
   the ground by themselves and charge the watchers.
4. **The fight.** Two bare antlered watchers; when both fall, **six armed
   watchers run in through the gate** (each drops the weapon it holds). Watchers
   have 72 health, run at 5.6 m/s and hunt aggressively.
5. **The road.** Walk into the camp arch and press **G** and the gate opens onto
   a 286 m lane of dark voodoo forest — 48 torches down both verges, ironoak and
   hollow snags, rag trees and gallows trees with charms strung across the lane,
   wicker effigies, skull stakes, cauldrons, braziers, straw, blood and cart ruts.
   The squad runs it with you; two armed watchers start on your body and a pair
   waits in each of the three clearings. It is a long run, and it is the escape.
6. **Town.** The lane ends at the town gate; press **G** there. Shared infinite
   stash, Sacrificial Altar (unbind / distil 5:1 / brand), Gold recruiter,
   Quartermaster (buy base gear into the stash), and the expedition gate (deploy
   up to 8 → arena).
7. **Arena/expedition.** An empty deployment line builds the sandbox brawls
   (bubble demo); a deployed line builds a real five-wave expedition against
   cultists with the Bilewarden at the end, with survivors physically looting the
   field. `Enter` back to town.

HUD keys: `[`/`]` cycle body, F1–F8 named body, TAB warband screen, P paperdoll,
G interact, K manual loot (unadvertised; the squad loots itself), E revive,
R branded skill, B end battle, Enter town.

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
| Crafting | `sacrificial_altar.gd`, `altar_menu.gd`, `quartermaster_menu.gd` |
| UI | `warband_hud.gd`, `warband_screen.gd`, `warband_paperdoll.gd`, `tutorial_card.gd` |
| Scenes | `scenes/cage_escape.tscn` + `cage_escape.gd` + `tutorial_sequencer.gd` + `cage_watcher.gd`; `scenes/town_hub.tscn` + `town_hub.gd` + `expedition_gate.gd`; `admin_arena.tscn` + `admin_arena.gd` |
| Enemies | `cultist_guard.gd`, `enemy_waves.gd`, `cage_watcher.gd` (extends the forest mob) |
| The road | `scenes/escape_run.tscn` + `escape_run.gd` (bodies, squad, pursuers, the two endings) + `run_forest.gd` (the 286 m lane and its dressing, returns `{lane, length, width, torches, arch, ...}`) + `squad_drive.gd` (the one follow/fight/retarget behaviour, shared with the cage) |
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
8. **Tutorial cards pause the tree** (`TutorialCard` runs `PROCESS_MODE_ALWAYS`).
   A scene hand-off must clear `paused` (`GameFlow.goto` does).
9. **The rescuer is the player's beat, not the AI's.** No auto-possession; he is
   excluded from the squad AI until the latches are cut.
10. **Squad AI is silent about loot.** No pickup messages, no loot step in the
    objective. `K` still works for a human but is not advertised.
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
15. **The rescuer is not moved for the player** and **loot is not announced** —
    both were explicit player requests. Do not reintroduce auto-possession or
    pickup feeds.
16. **The arch opens the road; the road is walkable.** The camp gate never
    teleports again: `G` there emits `scenes/escape_run.tscn`, and the run's own
    gate emits town. `run_forest.gd` must keep returning a lane a body can
    actually traverse — `escape_run_regression` drives a body end to end and
    fails if it leaves the walkable width or stops closing on the arch, so a prop
    or a wall box that narrows the corridor is a test failure, not a matter of
    taste.

### Tuning knobs (one place each)

| Knob | Where | Now |
| --- | --- | --- |
| Watcher health / damage / speed / sight / orbit | `cage_watcher.gd::_profiles()` | 72 / 5 / 5.6 / 60 / 1.9 |
| Second wave contents and post positions | `cage_escape.gd::REINFORCEMENTS`, `REINFORCE_POSTS` | 6 arms, outside the gate |
| Delay before the second wave | `cage_escape.gd::REINFORCE_DELAY` | 2.5 s |
| Total watchers for the escape | `tutorial_sequencer.gd::GUARD_COUNT` | 8 |
| Revive / overkill / bubble / cap | `warband_contracts.gd` | 5 s / 10% / 30-34 m / 8 |
| Yard size | `cage_escape.gd::YARD_*` | 60 × 68 m inside 100 × 140 |
| The road: length, width, torches | `run_forest.gd` | 286 m lane, 11 m walkable, 48 torches every 12 m a side (3.4 energy / 16 m), 763→826 nodes |
| The road: pursuers | `escape_run.gd::WATCHER_*`, `run_forest.gd` clearing posts | 8 armed watchers — 2 on the soul at spawn, a pair in each clearing |
| The road: town ground | `escape_run.gd::safe_center` | the town arch — the last ~19 m of the lane is safe ground |
| The road: both endings | `escape_run.gd::ARCH_RADIUS`, `WIPE_BEAT` | G at the arch → town; a wipe waits 2.5 s → town, nobody revived, nothing gathered |
| Loot auto-equip rule | `warband_state.gd::auto_equip` | empty slot or better than worn |
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
| `possession_regression` | 236 | bodies, cycling, camera, net transfer, auto-eject |
| `downed_revive_regression` | 67 | 10% overkill, crawl, 5 s channel |
| `combat_bubble_regression` | 73 | 30/34 m, 10%, guard choreography, hysteresis |
| `altar_regression` | 112 | unbind/distil/brand UI over the wallet |
| `stash_autoloot_regression` | 170 | pickups, sweep, infinite value sort |
| `warband_ui_regression` | 99 | roster screen, paperdoll hand-off, recruiter |
| `branded_abilities_regression` | 114 | six sigils, tiers, refusals |
| `enemy_waves_regression` | 108 | cultists, waves, soldier loot run |
| `town_hub_regression` | 58 | services, hire, deploy, paperdoll |
| `cage_escape_regression` | 159 | cards/pause, rescuer, four latches, squad AI, 72 HP watchers, six runners, drops, arch opens the road |
| `escape_run_regression` | 116 | the arch's one door, a 286 m walkable lane (52.8 s driven end to end), art budget, 8 hunters, both endings |
| `expedition_regression` | 42 | deployed line, five waves, loot run, return |
| `expedition_director_regression` | 154 | five-wave curve 3/4/4/5/6, boss at 2x with a run-scoped brand, rewards once, wipe pays nothing |
| `branded_world_regression` | 48 | the sigil tile: tier line, cost, cooldown vs READY, rebind, a real `R` hit |
| `warband_art_regression` | 192 | camp/town dressing counts, materials, nothing solid inside the play space |
| `warband_lobby_regression` | 56 | two peers through the title lobby, socket survives the hand-off, refusal verbatim |
| `run_persistence_regression` | 196 | battle ledger, history + lifetime totals, reload pays nothing twice, a v1 save still loads |
| `game_flow_regression` | 22 | cage → town → arena → town on one save |
| `admin_arena_regression` | 98 | bubble, downed, revive, loot, altar, screen, two peers |
| `quartermaster_regression` | 20 | keeper price, purse, refusal |
| `warband_session_regression` | 49 | two real ENet processes |

Relevant legacy tests that must stay green when touching shared files:
`gameplay`, `combat_expansion`, `net_limits`, `world_art`, `mob_aggro`,
`paperdoll`, `town_services`, `title_menu`, `world_ui`, `hitbox`, `block_clash`,
`draw_combat`, `ranger_clone`.

Run the gate (31 tests, none of them socket tests running concurrently):

```bash
GODOT=./.runtime/godot/Godot_v4.7.2-stable_win64_console.exe
OUT=C:/tmp/gres; rm -rf "$OUT"; mkdir -p "$OUT"
LIST="warband_contract possession downed_revive combat_bubble altar stash_autoloot
warband_ui branded_abilities enemy_waves town_hub cage_escape escape_run expedition
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
- **A guest cannot hurt anything yet.** `WarbandSession` replicates the warband's
  bodies (20 Hz snapshots) and nothing else: a guest's swings are refused locally
  (`damage_enabled` is false for a replica, by the base game's own rule) and there
  is no melee-intent channel to the host, while the cultists a guest sees are its
  own local `EnemyWaves` — the host's cultists never reach it. The lobby makes
  this reachable by a normal player, so say it plainly: hosting works, being the
  guest is a spectator with a body until the intent channel and a mob snapshot
  channel land. This is the same missing ack channel listed under prediction.
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
- **Cage/town art is primitives** (Geo boxes/materials); no authored props.
- **Roster persistence during a battle** is mirrored every 0.4 s and saved on
  scene exit; a hard kill mid-battle can lose the last moments.
- **`arena.tscn`'s own lobby backdrop** renders washed out in this build; it does
  so in the original repo too and is unrelated (the admin arena looks right).

---

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

Still open from Gate 3, and the reason it is written down rather than hidden: the
**rendered** playthrough (a real window: cards pause, F5 takes Corvin, four
latches, the squad fights, six armed watchers, gate → woods → town) and the
**two-peer** lobby run were never exercised on a display in this session — every
check above is headless. Do that first in the next session.

### Phase 4 (later)

- **Make a guest a participant**: a mob snapshot channel (cultists and watchers
  are the guest's own local spawn today) and a melee/ability intent channel, so
  the second peer fights instead of watching. Same work as the prediction ack.
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
