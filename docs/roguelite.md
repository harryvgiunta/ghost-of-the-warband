# The Arena — roguelite mode

A wave-based, multiplayer-first roguelite built on the campaign's own bodies,
weapons, rig, gore and Host/Join session. The town is the hub; the portal takes a
party through six bounded islands, three factions and one mod draft at a time.

## The loop in one breath

**Hearthstead** → **Start Run Portal** → three waves on an island → clear it →
open the **reward chest** (which also raises downed players at 50% HP) → choose a
**pedestal mod** → bargain at the **Greed Totem**, spend crystals at the **shop
island** when one is offered → take one of two **portals** → repeat until six
islands are cleared.

Keys are meta-currency and are banked on the ledger (`user://roguelite_meta.json`),
not spent in a run: elites pay 1, bosses pay 3, a cleared island pays 2–4. The
**Unlock Totem** in the square rolls a random locked weapon for 3 keys. The
**Weapon Rack** binds one ranged and one melee piece; the portal dresses every
body in that pair. The twig bow and the makeshift hatchet are free forever.

## Controls

| Key | In the run |
| --- | --- |
| Mouse / movement | unchanged from the campaign |
| `TAB` | swap between the ranged and melee pieces |
| `T` | throw the melee piece (throwing weapons have charges) |
| `G` | chest, pedestal, Greed Totem, shop, portal |
| `ESC` | close the draft or shop window before anything else |
| `K` | loot a corpse or a drop, as in the campaign |

## The three islands and their factions

| Island | Art | Faction | Bodies |
| --- | --- | --- | --- |
| **The Briarwood** | `TreeKit` / `WorldStyle` wood | Watchers | hollow runts, wardens, high wardens with bows |
| **The Hollow Beneath** | `CaveKit` dripstone, glow fungus | Demons | spawn, hell goats, succubi, beasts, gargoyles |
| **The Blood Pit** | stone colonnade, braziers, `RockKit` cover | Blood Clones | ranger clones, warden archers |

Every island is its own node at `y = 620 + 210 × index` — clear of the campaign
and of the old arena ring at 260 — with a solid rim wall behind a fog sheet. The
rim keeps the fight in; the fog keeps the world out. A **boss wave** closes the
third and sixth islands. Elites arrive from the second wave on.

Wave budgets come from the island's base (`STAGE_BUDGET`) times `1.28^(wave-1)`
times `1 + 0.5 × (connected players − 1)`. The queue feeds the island at a bounded
live cap so a wave is a fight, not a frame spike.

## The mod engine

`scripts/roguelite/proc_engine.gd` owns one body's stacks and answers six events:
`on_weapon_fire`, `on_melee_swing`, hit (ranged and melee), kill, damaged, island
clear. It never spawns a node: it returns effect requests, and `run_director.gd`
executes them.

Stacking is deliberately two rules:

- **Linear** — damage, fire/melee rate, crit chance, max HP, currency, lifesteal.
- **Hyperbolic** — every chance (Hatchet Arc, Thorn Nova, Blood Arc, Blood
  Charge, Scatter Burst, Buried Cache, dodge): `cap × n / (n + half)`. Ten copies
  of a 15% proc approach a cap and never reach certainty.

Crits deal `2.0×` and roll their procs twice. Damage from a proc never rolls
another proc (the fan-out is one deep by construction), and Glass Cannon's health
penalty is floored so no stack count can put the pool at zero. The full pool is
`scripts/roguelite/mod_catalog.gd`, tiered common / epic / legendary / greed.

## Weapon archetypes

`scripts/roguelite/weapon_registry.gd` derives a row for **every** bow, blade,
dagger and staff in `PlayerState.ITEMS`, then overrides the pieces whose arena
identity is specific:

- **Twig Bow** — single shaft, 1.0 proc.
- **Makeshift Hatchet** — fast melee, melee proc chain, two throw charges.
- **Heavy Crossbow** — slow, 45 base, pierces one body, 1.5 proc.
- **Automatic Crossbow** — 16 base, wide spread, fastest trigger, 0.5 proc.
- **Throwing Axe / Makeshift Axe** — three charging arcs, heavy, gore ×2.2.
- **Throwing Knife** — five quick throws on a short recharge.
- **Iron Javelin** — two heavy throws, long spear, gore ×2.4.

Crossbows are built from a bow's data with `bow.style = "crossbow"`; the javelin
is the sword family's `"spear"`. The rig, ammo, headshot and gore pipelines are the
campaign's unchanged.

## Multiplayer

The existing Host/Join ENet session stays the transport. The **host** owns the
seed, the island, the waves, the mob spawns, chest and draft rolls, the greed
bargain and every damage number. Guests receive:

| Event | Channel | Meaning |
| --- | --- | --- |
| `state` | reliable | island, biome, wave, clear state, crystals, kills |
| `mob` | reliable | a spawned hostile, its name, species, elite/boss flags |
| `prop` | reliable | a chest, pedestal, portal, totem or shop, with a serial |
| `prop_gone` | reliable | a prop was spent, and which flash to play |
| `mod` | reliable | a mod landed on a peer's body |
| `keys` / `crystals` / `sold` / `vote` / `revived` | reliable | the run's books |
| `fx` | reliable | arc, nova, chain, wave and bomb visuals |
| `pool` | reliable | the host's unlocked armory, lent to the rack |

Guest inputs are requests (`start`, `use`, `choose`, `buy`, `vote`, `swap`) and
are attributed on arrival by `multiplayer.get_remote_sender_id()`. Mobs are
spawned on the host and copied by name on the guest, so the session's existing
15 Hz snapshot stream drives them with no second protocol. Proc projectiles are
drawn on guests from `fx` events and never deal damage (`visual_only`).

A downed body cannot bleed out or be finished while a run holds it. When the
survivors open the island's reward chest, every downed player stands up at 50% HP.
If a live wave ends with nobody standing, the run is lost.

Reward props are shared but their helpings are per player: one chest, pedestal and
Greed Totem stand on the island, and each connected player may take one share of
each before the prop disappears. The portals unseal on the first chest opened, so
a party is never held hostage by one body that walks away from the reward.

## Where it hooks into the campaign

| Existing system | Path | Hook |
| --- | --- | --- |
| Host/Join ENet session | `scripts/warband/warband_session.gd` | `host`/`join`, `attach_world`, `apply_mob_states`; new `receive_roguelite`, `roguelite_request`, `send_roguelite_event`, `send_roguelite_request`, `sync_roguelite_pool` |
| Scene owner | `scripts/warband/world_scene.gd` | builds `RogueliteDirector` + plate, ticks the run, routes shots (`_on_body_shot`), throws, `G`, `TAB`, prompts, and holds the square's dress |
| Player body | `scripts/warband/warband_body.gd` | `roguelite`, `roguelite_hold_downed`, `note_attack_landed` → melee proc, `take_damage` → dodge/incoming, downed clock hold |
| Player rig / controller | `scripts/archer.gd`, `scripts/warband/possession_controller.gd` | `run_rate_scale`, weapon data tables, existing spawn/adopt verbs |
| Damage pipeline | `scripts/combat.gd` | `_on_melee_started` asks the run for the cut; `_resolve_melee_contact` carries the crit; `BASE_DAMAGE` extended for the crossbows |
| Projectiles | `scripts/arrow.gd`, `scripts/thrown_weapon.gd`, `scripts/spell_projectile.gd` | `on_hit`, crit, proc coefficient, homing, ricochet, pierce growth, gore cleave |
| Abilities | `scripts/warband/warband_abilities.gd` | volley arrows and staff bolts roll the same run damage/crit/proc hooks |
| Weapon catalog | `scripts/player_state.gd` | five arena pieces in `ITEMS`; every existing bow/blade/staff auto-registers |
| Gore | `scripts/blood_fx.gd`, `severed_head.gd`, `severed_body.gd` | untouched: the mob classes call them exactly as in the campaign |
| Town | `scripts/warband/town_hub.gd` | three fixtures, three services, prompt lines, `town_forge_panel.gd` |
| Enemy rigs | `cage_watcher.gd`, `watcher_archer.gd`, `devil_mob.gd`, `ranger_clone.gd` | spawned by faction, wired to `defeated`/`attacked`, booked into `world.guards` for the session stream |

## Files

| File | Owns |
| --- | --- |
| `roguelite_meta.gd` | autoload `Roguelite`: keys, unlocks, loadout, JSON ledger |
| `weapon_registry.gd` | every weapon's arena firing profile |
| `mod_catalog.gd` | the full mod and greed pool, drafts, greed offers |
| `proc_engine.gd` | stacking rules and the six event answers |
| `run_player.gd` | one body's run: mods, stats, hand slot, hooks |
| `run_director.gd` | islands, waves, mobs, rewards, props, portals, wire |
| `roguelite_stage.gd` | the bounded island and its recycled dressing |
| `roguelite_props.gd` | chest, pedestal, Greed Totem, shop, portal meshes |
| `proc_projectile.gd` | blade, splinter, crescent, blood charge |
| `proc_fx.gd` | lightning, rings, flares |
| `roguelite_hud.gd` | the island/wave plate, mod stack, draft and shop windows |
| `town_forge_panel.gd` | the town's three-page arena board |

Integration points in the campaign code are small and guarded: `warband_body.gd`
carries `roguelite`/`roguelite_hold_downed` and forwards landed blows and incoming
damage; `combat.gd` scales a committed cut; `world_scene.gd` routes shots, throws,
`G`, `TAB`, prompts and the frame; `town_hub.gd` owns the three fixtures;
`warband_session.gd` carries the event and request RPCs. With no run active every
one of those paths is the campaign's original path.

## Verifying

```powershell
.runtime/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . `
  --script tests/roguelite_regression.gd
```

`tests/roguelite_regression.gd` covers the ledger, the armory and its new
archetypes, the stacking curves, the town's three services, a full island clear
with waves and procs, the chest's revive, the pedestal draft, the Greed Totem,
the shop, a portal transition, all three island builds, a boss wave, and closing
the run back onto the square.
