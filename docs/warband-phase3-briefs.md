# Phase 3 briefs — paste into `task`

Five self-contained briefs for the next parallel phase. Read
`docs/warband-handoff.md` first: it has the state, the rules, the test commands
and the merge order. Create each worktree with the recipe in §8 of that file.

**Shared context for every brief** (paste this into the `context` argument):

```
Repo: C:/tmp/ironwood/ghost_of_the_warband (Godot 4.7.2, branch main).
Engine: .runtime/godot/Godot_v4.7.2-stable_win64_console.exe ; .godot/ cache present.

Read first: docs/warband-handoff.md (state, rules, test commands),
docs/warband.md §§1-3 + §10 (numbers, architecture), scripts/admin_arena.gd
(the reference scene assembly), .omp/skills/ironwood-archer/SKILL.md (warband section).

Hard rules:
- Edit ONLY the files listed under your worktree. The shared libraries in
  scripts/warband/ (contracts, roster, stash, cruor, vendor, damage scaler, soul
  router, possession controller/camera/sync, bubble, brain, crawl, revive, loot,
  altar, screen, paperdoll, hud, card, session, game flow) belong to everyone -
  change one only if the ticket says so, and say why in the commit.
- No stubs, TODOs, placeholder screens or fake data. Ship the behaviour, then a
  headless regression that proves it.
- Tests: `./.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless
  --path . --script res://tests/<name>.gd`; print
  `<NAME>_REGRESSION checks=N failures=M`, quit 0/1. Do not run rendered windows
  or the whole suite. Commit only when your own test is green.
- Never regress the 15 rules in docs/warband-handoff.md §3.
```

---

## wt 12 — expedition director

```
# Target
Worktree ../gotw-wt12, branch wt-12-expedition-director.
Owns: scripts/warband/expedition_director.gd, tests/expedition_director_regression.gd,
and admin_arena.gd (you are the only owner of that file this phase).

# Change
- `ExpeditionDirector extends Node`: owns the pacing of an expedition on top of
  the existing EnemyWaves. `setup(controller, warband, waves, loot, parent)`.
- Five waves: counts 3/4/4/5/6, kit tiers by wave (reuse EnemyWaves' tiers), a
  two-second breathing gap between waves, and a **boss wave** as wave 5: one
  `CultistGuard` at double health with a branded weapon plus two escort guards.
- Rewards on clear: gold (wave-scaled) through `Warband.award_gold`, Cruor through
  `Warband.cruor.add` (T1 per wave, T2 at the boss), and a mission summary
  `{waves, kills, items, gold, cruor}` exposed for the HUD.
- `admin_arena.gd`: replace the hard-coded `MAX_WAVES`/`_start_wave` block with the
  director; keep the sandbox mode and every existing behaviour (bubble, branded
  skill, altar, stash, `Enter` town, the guard-loot drop).

# Acceptance (tests/expedition_director_regression.gd, real scene)
- A deployed line builds five waves in order; the boss wave's guard has double
  health and a brand; the summary matches the kills/rewards.
- Clearing the fifth wave ends the expedition and pays gold + Cruor exactly once.
- A wipe (all bodies down) ends it with `wiped` and pays nothing.
- `expedition_regression` still passes unchanged; `admin_arena_regression` too.
```

---

## wt 13 — branded skill HUD and world use

```
# Target
Worktree ../gotw-wt13, branch wt-13-branded-world.
Owns: scripts/warband/branded_hud.gd, tests/branded_world_regression.gd.
May add ONE signal hook to admin_arena.gd only after messaging wt-12 (who owns it).

# Change
- `BrandedHud extends CanvasLayer`: a tile for the soul's branded weapon - ability
  name, tier, a cooldown ring/bar and the stamina cost; hidden when the piece is
  unbranded. `configure(warband, runner)`, `set_runner(runner)`, `refresh()`.
- Wire it in the arena through a signal the arena already emits
  (`possession_changed`) plus `branded.cooldown_left()`/`brand()`.
- Keep `R` working in the expedition; the tile must show "READY" vs a countdown
  and the sigil line from `Warband.cruor.brand_line(item_id)`.

# Acceptance
- With a branded sword the runner reports ready, pressing the verb starts the
  cooldown and the tile counts down; an unbranded body hides the tile; switching
  bodies rebinds the tile; the tier text matches `BrandedSkills.tier_line`.
- A real hit from the sigil lands on a watcher/cultist in the test scene.
```

---

## wt 14 — warband lobby and session in the loop

```
# Target
Worktree ../gotw-wt14, branch wt-14-warband-lobby.
Owns: scripts/warband/warband_lobby.gd, title.tscn/title.gd (only owner this phase),
tests/warband_lobby_regression.gd.

# Change
- A lobby panel on the title: name, port, HOST WARBAND and JOIN WARBAND. Hosting
  starts a real `WarbandSession` and carries the intent into the cage/town via
  `GameFlow`; joining connects and enters the same mode, taking the first free
  body.
- The session must survive the scene hand-off: create the ENet peer once and
  re-attach it to the new scene's `WarbandSession` (or own it in an autoload -
  decide and document which in the commit).
- Refuse a second peer taking an occupied body with the router's reason, shown in
  the lobby/HUD.

# Acceptance (tests/warband_lobby_regression.gd, two real processes)
- Host + client reach the cages/town scene together; each has one body; the
  client's movement reaches the host; a taken body is refused; leaving releases
  the body to AI. `title_menu_regression` and `warband_session_regression` stay
  green.
```

---

## wt 15 — camp and town dressing

```
# Target
Worktree ../gotw-wt15, branch wt-15-camp-town-art.
Owns: scripts/warband/camp_dressing.gd, scripts/warband/town_dressing.gd,
tests/warband_art_regression.gd.

# Change
- `CampDressing`: add cages' hardware (locks, chains, straw, bone charms),
  cult banners on the palisade, gibbets, a cold altar dressing, ember braziers
  that use the existing flame shader, ground scatter (straw, blood stains, cart
  ruts). Build with `Geo` + `TextureLibrary`/`WorldStyle` material helpers; no new
  collision inside the play space.
- `TownDressing`: the quartermaster and recruiter counters with hanging goods,
  an awning over the stash, a signpost with real text, the campfire ring, and
  lantern pools.
- Both are called from the existing scenes' `_ready` (one line each in
  cage_escape.gd / town_hub.gd - allowed: the ticket is the art).

# Acceptance
- `warband_art_regression` builds both scenes, asserts the dressing nodes exist
  with their expected counts and materials, that no added StaticBody sits inside
  the playable radius, and that the scene renders (headless: no errors).
- `cage_escape_regression`, `town_hub_regression` and `world_art_regression` stay
  green. Take one rendered screenshot of each scene and describe what you saw.
```

---

## wt 16 — run persistence and reports

```
# Target
Worktree ../gotw-wt16, branch wt-16-run-persistence.
Owns: scripts/warband/run_report.gd, tests/run_persistence_regression.gd.
May edit warband_state.gd inside the persistence section only (marked block).

# Change
- `RunReport` records a battle: start/end, mode, waves, kills, items looted, gold,
  cruor, downed/dead bodies by name. `Warband` persists a bounded history
  (last 20) plus lifetime totals (wins, wipes, best wave).
- On leaving the arena, write the roster's real health/downed state (the arena
  already mirrors it every 0.4 s) and the report.
- The roster screen gains a small "LAST RUN" block (one label is enough) fed by
  the report; loading the save restores the history.

# Acceptance
- A battle writes a report with exact counts, persists across `reset_state` +
  `load_state`, and the lifetime totals accumulate.
- A wipe is recorded separately from a clear; gold/cruor are never double-paid on
  reload. Existing `warband_contract_regression` / `warband_ui_regression` stay green.
```

---

## Gate 3 checklist (merge owner)

1. Merge 12 → 13 → 14 → 15 → 16; after each merge run `--import` and the full test
   list in `docs/warband-handoff.md` §4.
2. Launch `res://scenes/cage_escape.tscn`, play the tutorial on a real window:
   cards pause, F5 takes Corvin, four G latches, squad arms and fights, six armed
   watchers charge in, drops land, gate G → town.
3. Town: hire, equip a piece onto another body, buy from the quartermaster, brand
   an item, deploy three, launch.
4. Expedition: five waves + boss, rewards, `Enter` → town; save/reload shows the
   report; host a second peer in the lobby and take a body.
5. Update `docs/warband-handoff.md` §4/§5 and the skill's test list with the new
   counts, then tag the state in the commit message.

---

## wt 17 — the road (added mid-phase, at the owner's request)

```
# Target
Worktree ../gotw-wt17, branch wt-17-escape-run.
Owns: scenes/escape_run.tscn, scripts/warband/escape_run.gd, run_forest.gd,
squad_drive.gd, tests/escape_run_regression.gd, plus the gate hand-off in
cage_escape.gd, the gate transition in tutorial_sequencer.gd and the gate
assertions in tests/cage_escape_regression.gd.

# Why
The arch at the camp gate was a teleport: press G and the game skipped the escape
it had just spent a tutorial building up to. The owner asked for a long, bloody
run back to town through dark voodoo woods - torches everywhere, doodads, trees
with things hanging - assembled from art the repo already ships.

# Change
- `G` at the camp arch now emits `scenes/escape_run.tscn`; the tutorial no longer
  ends there (no TOWN state), and the run's own gate emits the town.
- `RunForest.build(parent)` returns `{root, lane, length, width, torches,
  spawn_posts, arch, clearings, ...}`: a 286 m lane, 11 m walkable, torches down
  both verges, tree/bramble walls with real collision outside the lane, rag trees,
  gallows trees, charm ropes and bone arches over the road, wicker effigies, skull
  stakes, cauldrons, braziers, straw/blood/ruts - all from the world kits, night
  from EnvironmentKit.
- Eight armed `CageWatcher`s: two on the soul at spawn, a pair per clearing.
- Both endings are one door: G at the town arch, or a wipe after 2.5 s.

# Acceptance
`escape_run_regression` 116: the arch's single door, the lane's measured length
and width, torch count and 1:1 lights, an art/node/draw budget, a body driven the
whole lane (52.8 s of game time, never off the walkable width, distance always
falling), the pursuers hunting the soul, the squad following, both endings.
`cage_escape_regression` re-pointed, not weakened. `town_hub`, `warband_art`,
`game_flow`, `warband_contract` green.
```
