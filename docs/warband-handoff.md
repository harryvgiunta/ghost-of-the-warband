| `altar_regression` | 257 | unbind/distil/brand UI over the wallet; every catalog weapon/shield has a rite of catalog reagents, the real panel anoints a worn bow and refuses a short stash out loud, a controller-dressed body carries the skill without a manual refresh, the ichor order completes, and the ledger survives the save |
| `stash_autoloot_regression` | 170 | pickups, sweep, infinite value sort |
| `warband_ui_regression` | 116 | roster screen, paperdoll hand-off, recruiter |
| `branded_abilities_regression` | 114 | six sigils, tiers, refusals |
| `enemy_waves_regression` | 108 | cultists, waves, soldier loot run |
| `town_hub_regression` | 71 | services, hire, deploy, paperdoll (the square as an area) |
| `duel_lesson_regression` | 54 | the first fight's machine alone: nothing advances before the body is taken, one card per fact in order, the target watcher's windup does not teach the guard while its partner stands, a block before the card is not booked, the pair falling ends it, `reset()` starts over |
| `cage_escape_regression` | 305 | the two ground torches at the starting cage, the shiv taken through the bars while clamped, a bare-handed G opening nothing, the own latch cut with the blade, the pair waking on the armed body, a raised guard on the second watcher, the revive lesson on a fallen ally, the four latches cut one G at a time, the squad arming, the four at the mouth (one of each creature), drops |
| `escape_run_regression` | 201 | the trail as an area: a 1,374.6 m lane walked over a 420 m stretch, art budget, the hunters spaced and never handed a quarry at spawn, the leaving waking them, the escort arriving (three within 20 m), both endings |
| `torch_light_regression` | 24 | the torch is a legal off-hand piece, lit on the body that wears it, 7.5 energy / 26 m, and dark again when it comes off |
| `warband_world_regression` | 305 | one scene and one controller, the camp in the trees, the new opening, 1,575 m camp → town with no scene change, the services and the keepers' cards at the far end, no ally abandoned, budget |
| `warband_abilities_regression` | 46 | plain 1/2/3 starts the body's three slots (Shift+1 is the same press, not a requirement), a stock kit shows no hand tiles and the anointed kit grants all three, the stamina bar and three tiles read that body, an ungranted slot hides, RMB peeks only in cover and guards everywhere, one authoritative cue spawns exactly one arrow/spell |
| `warband_menu_regression` | 41 | the six rows, SAVE/LOAD over `Warband.save_state`, LOAD gated on a real file, the sound page and back, `resumed` on every close, and the tree never paused |
| `warband_vendors_regression` | 151 | three counters as `G` services in the market ring, each opening its own seat and stock; buy into the shared stash, sell one pooled copy at 60%, a short purse spends nothing, a worn copy is not on the board, closing leaves no panel |
| `warband_wilderness_regression` | 75 | eight kind-0 wolves in two deep packs inside `guards`/`wild_mobs`, clear of the mouth, pocket and lane, aimed at the standing body, pack wander, and one `MobCuller` sweep parks a wolf left 300 m behind |
| `warband_session_world_unit_regression` | 54 | no socket: one name-keyed mob entry, a batch fits one datagram, replica write + tick, an unknown name invents nothing, loot and missile announcements book once, the lent warband (host's roster and purse, gear and purse verb refusals, no write and no read of the guest's own file, the loan's return), and the campaign doors (new, checkpoint, a join that opens nothing until the host answers) |
| `warband_integration_regression` | 38 | the real world binds every seated body to `WarbandAbilities`, fields the wolves and their culler, paints the stamina bar and three tiles, opens/closes the menu from a real Escape without pausing, and never hands a human body to squad AI |
| `warband_coop_campaign_regression` | 43 | two real processes on one warband: the host opens its save on HOST GAME, the guest joins from the title, is lent the host's campaign and fields the host's bodies as replicas, is seated in a free body, keeps its own save byte-identical, and is given a third body when one comes free; with the last body standing the soul inside keeps it and the other soul watches it (eye + HUD line naming the holder) |
| `expedition_regression` | 42 | deployed line, five waves, loot run, return |
| `warband_art_regression` | 196 | camp/town dressing counts, materials, nothing solid inside the play space |
| `warband_appearance_regression` | 206 | the look table loads and starts each palette at the measured base, a look is a pure function of the id (order- and cache-independent), eight deployed bodies differ in face, cut, skin, shirt and shorts, every named piece exists in the assets, and the rig, an actor and an undressed body all apply or ignore it correctly (hair under a helmet, head zones scaled) |
| `armor_flair_regression` | 475 | the armour flair: the tables and the thread that reads on them, a flair that is a pure function of the id, eight bodies with eight fields and eight devices, every authored armour material given a role, the rest space on the vertices equal to the mesh's own and shared by every body while the materials are each body's own, the measured piece edges, the surcoat following the flair, the veils measured, every trophy shown only with a real piece and placed on the measured surface (an oval necklace, a hip outside the waist), every trophy kind building, and a body with no look left untouched |
| `checkpoint_regression` | 78 | the bookmark round trip, garbage refused, v3 saves still load, a wipe's restore (downed wake, dead stay dead, purse untouched), trail and town resumes in the real world, the retry door, the title's resume door |
| `game_flow_regression` | 17 | the four title doors through the real flow: new campaign opens at the cages with a fresh warband and purse, the roster round-trips through the save, RESUME opens at the bookmark |
| `warband_netcode_regression` | 62 | the co-op smoothing on shipped bodies: the primitives, one numbered host frame per tick and a hold on a frame-less tick, the acknowledgement, prediction + model glide, the capsule rewind and `arm_lag`, and a body batch inside `NetLimits.PAYLOAD` |
| `quartermaster_regression` | 20 | keeper price, purse, refusal |
| `warband_session_regression` | 49 | two real ENet processes |
| `quest_log_regression` | 95 | the ledger alone: the five goal shapes, offer/accept/turn-in guards, kill counting by mob id, the chain to the Crypt shell, the ichor's APPLY order, the ledger's save round trip, free hires and the stash dressing, and the keeper's tips and arrow |
| `town_stockade_regression` | 234 | the town as a place: the stake ring and its one gap, 8 roofs standing clear of every service ring and the gate lane, 5 armoured keepers that cannot be possessed or hit, the gold arrow moving recruiter → quartermaster, the recruiter's tip then board, the quartermaster's order on the same press, the altar service where the ichor is laid, the light budget of 17, and a watch archer putting a real arrow into a wolf |
| `wild_cages_regression` | 102 | the orders' ground on the real world: four cages on the ground and clear of the lane, the latch refusing bare hands, four names on the roll and four marks on the rescue order, 21 wardens in `guards` (nearest camp 72 m off the lane), a body standing on the lane never waking a camp, and one death counting toward the bounty |
| `loot_wow_regression` | 213 | the wolf's salvage table (deterministic per body), the booking path, `LootSummary` wording, five salvage silhouettes, the click/crouch/cancel gesture on stub bodies, and the wardens' 4-of-12 ichor split |
| `world_map_regression` | 64 | the grown lane and field, and the page: bounds, projection monotonicity, every mark inside the panel, the legend, open/close, metres-per-pixel |

The runner is the authority on the lists (`tools/run_tests.py`). The campaign
suite is the default; `--base` runs the shared-layer harness (`rig`, `draw_combat`,
`projectile`, `melee_roll`, `action_pose`, `arm_clearance`, `cover_movement`,
`running_slide`, `wolf`, `devil`, `swing_reach`, `hitbox`, `logging`, `corpse`,
`backstab`).

Run the suites:

```bash
python tools/run_tests.py          # the campaign
python tools/run_tests.py --base   # the shared-layer harness
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
- **Every rite costs the same vial.** `WarbandCruor.ANOINT_RECIPES` prices all
  twelve weapon/shield skills at `{ichor_vial: 1}` for now; balancing them apart
  is that one table. The frontier/arena/delve sandbox has no altar, so its
  weapons carry no skill.
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
campaign ledger (`quest_log.gd` + `Warband.quests`, saved as `quests`), the keeper who talks
(`quest_giver.gd`), the arrow (`quest_marker.gd`), the free first eight oaths and
the stash dressing, and the two material families (wolf salvage, warden ichor).
The branches own the town (palisade, gate, eight roofs, five armoured keepers,
three watch archers), the orders' ground (four caged soldiers, three warcamps of
21 wardens), the loot (wolf drop table, the click-and-crouch hand, one summary
line, five salvage silhouettes) and the world (a kilometre-and-a-third lane, a
grown heightfield, the map sheet).

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
| `wt-14-warband-lobby` | `scripts/warband/game_flow.gd`, `title.tscn`/`title.gd`, `tests/warband_coop_campaign_regression.gd` | **Superseded by wt-26**: the lobby panel is gone and the title's HOST GAME / JOIN GAME carry the same intent into `GameFlow`, with one warband shared by every soul. The two-process test is the campaign one. |
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
shiv through the bars, the own latch, the bearings step, the pair, the four cuts,
the leaving)
and a second peer through HOST GAME. Every check for those is headless. Do that
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
