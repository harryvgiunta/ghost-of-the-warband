# The Annointment Pool — 100 weapon modifiers

A design sheet, not code. Every entry is written to be implementable against
today's systems: `AbilityRules` (damage scales, arcs, rings, cooldowns),
`Combat` (guard stamina, 0.25 s parry window, stagger roll, headshots,
`break_guard`), `WarbandBody` (quiver, sprint, 1000 stamina, downed state) and
the altar (`WarbandCruor`, ichor). Numbers are dials — but they are dialled
against the real base values, listed below.

Armour has its own sheet: `docs/annoint-pool-armour.md`. Kit-wide ceilings that
span both live there, §2.

## Status — implemented (build of 2026-11-03)

This sheet is the review artifact; **the code is the authority** and the ids
below (`#1..#100`) are review numbers, not the ids in the pool. The pool lives in
`scripts/warband/annoint_catalog.gd` and is larger than this sheet:

| | |
| --- | --- |
| Entries in the pool | **163** — 161 wired, 2 deferred (`#5` Gristle, `#21` Cinder Lining, both waiting on a damage-source tag) |
| Blanket ladders | 19 families × 5 rungs = 95 entries (`f_<group>_<key>_<tier>`) |
| Authored bundles | 44 stat/proc rows (`w_*`, `a_*`, `o_*`) |
| Skills | **24** (`k_*`): the 12 catalog skills join the pool, plus 12 annoint-only ones added to `AbilityRules` |
| Applicable pool today | sword 47 · dagger 46 · two-hand 49 · bow 46 · staff 44 · shield 41 · focus 39 |
| Piece cap | 6, and a full piece converts an add into a replace |
| Ritual cost | 1 `ichor_vial`, no destruction, ever |
| Rows implemented | every stat ladder, every stat bundle, the 6 armour/weapon procs that ride the receiver (`HEAL`, `STAMINA`, `REFLECT`, `ABSORB`, `LETHAL_SAVE`, `STAGGER`, `GUARD_BREAK`, `BLEED`) |

The skills that are *not* here are the ones the sheet flags as needing a system
the build lacks — silence, summon, blink-step, throw-and-return, the bleed
threshold on Eviscerate, the "next swing" window on Feint. Everything that maps
onto an existing effect kind (`melee_arc`, `melee_ring`, `barrage`, `piercing_shot`,
`projectile`, `ward`) is written and playable, with placeholder clips and no icon
art (a missing icon is a null texture by design).

What is wired, end to end, and verified by `tests/annoint_regression.gd`:
the pool and its invariants, applicability, the die's four bands, the cap
conversion, per-copy storage and independence, the kit ceilings, the card rows,
the proc verbs, and **99,999 rituals** (~1.8 s) with no piece over six, no
duplicates, no dead entry, and 161 of 161 wired entries welded at least once.

## 0. Units and the dials they sit against

| Notation | Means |
| --- | --- |
| `×N` | multiple of the piece's own base damage (`AbilityRules.ITEM_DAMAGE`) |
| `s`, `cd` | seconds, cooldown |
| `stamina` | out of the 1000-point pool |
| `m`, `°` | metres, degrees of arc |

| Knob | Value |
| --- | --- |
| Weapon damage | dagger 14 · short sword 30 · arming 38 · greatsword 50 · shortbow 30 · recurve 38 · longbow 50 · staff 50 · shield 18 |
| Cadence | dagger 0.5 s · short 1.0 s · arming 2.0 s · great 3.0 s · bow draw 1.0 / 2.0 / 3.0 s |
| Mercenary | 100 health · 1000 stamina · 1 health / 5 s regen · 10% overkill downs |
| Movement | sprint drains 19/s, stamina regens 13/s · a dodge step and a roll both exist |
| Guard | drains 20/s · cannot raise under 25 stamina · shield block 18 · bare 22 · dagger 30 |
| Parry | 0.25 s window · a parry keeps its guard, a bare block is spent |
| Slots | 3 annointed skill slots (plain **1/2/3**); the third is the trinket's |
| Arrows | real GRAVITY −4 m/s² · a shaft leaves the quiver per loose |

Two honesty notes. Swings and draws are **free** — `Stamina` spends only on
sprint, the guard and a block — so entries that give "stamina income" feed the
sprint/guard budget. And every skill's cost is a 1.0 placeholder
(`AbilityRules.TEST_STAMINA_COST`), so the ability stamina figures below assume
those costs get dialled up; if the placeholder stays, only cooldowns gate them.

## 1. What an annointment is

A modifier **welded to one item**, not to a body and not to a catalog entry. Two
Shortbows are two different objects; the one you took to the altar has a history
and the other does not.

**The rack shows copies, not catalog rows.** The altar's ANOINT page lists one
card per copy the warband carries — ten greatswords with ten different sets are
ten cards, each printing its own welded names and its own `n / 6` — sorted by
piece value and then by how much that copy carries. A **WORN ONLY** toggle in
the rack's header narrows it to the copies a body has on right now (the same
answer `Warband.annoint_copy` gives the field, so the rack and the body never
disagree about which sword is worn). `AltarMenu.anoint_rows()` answers that rack
as `{item_id, ordinal, copy_key, …}`; `select_anoint_item(item_id, ordinal)` lays
one copy in the square, `selected_anoint_ordinal()` says which, `rack_filter()`/
`set_rack_filter("all" | "worn")` drive the toggle, and the one ANOINT button
spends a vial on that copy alone. A row hands its ordinal to the hover card
(`WarbandItemCard.annoint_entries(item_id, warband, ordinal)`), so the card and
the card's copy can never disagree.

- Annointments live on **main hand and off hand**: bows, staves, swords,
  daggers, two-handers, shields, tomes, skulls.
- A body's stats stay identical across the warband. Anything granted is read
  **off the piece** — never banked onto the mercenary.
- Two kinds, because the roll only knows two:
  - **Ability** — a slotted skill. Takes one of the three slots while the piece
    is in hand. Four ability annointments on a piece means the fourth idles.
  - **Passive** — everything else, **including every trigger**. An on-hit proc
    is a passive for the purposes of the roll: it takes no slot and is always on.
- An annointment and a **brand** are independent. A piece may carry both.

## 2. The roll

One annointing = one `ichor_vial`. Four outcomes, equal weight, `d100`:

| Roll | Outcome | Detail |
| --- | --- | --- |
| 01–25 | **Add an ability** | Roll one from the piece's **ability pool** (its type's slotted skills + the catalog skills folded in). Exhausted → add a passive. Both exhausted → replace. |
| 26–50 | **Add a passive** | Roll one from the piece's **passive pool**. Exhausted → add an ability. Both exhausted → replace. |
| 51–75 | **Remove** | One annointment, chosen at random, is gone. No annointments → nothing (vial still spent). |
| 76–00 | **Replace** | One annointment, chosen at random, is gone; one new one rolls from the full pool. Empty piece → this is just an add. |

**No destruction.** A piece is never lost to the altar. The cost of the ritual
is churn and ichor, never the item.

**Cap: 6 annointments per piece.** At cap, both add outcomes become **replace** —
the altar never wastes a vial telling you the piece is full, it swaps something
out for something in.

Order of resolution: add/replace first roll the target, then commit. Nothing is
removed until the replacement is known to exist.

### What six attempts actually costs

The altar is now a random walk, not a lottery: `+1` with 50%, `0` with 25%,
`−1` with 25%. Expected vials, solved exactly (reflecting barrier at zero):

| Cap | Vials from empty | Vials for the last slot |
| --- | --- | --- |
| 3 | 8.5 | 3.5 |
| 4 | 12.2 | 3.8 |
| **6** | **20.1** | **3.9** |

So ~20 vials fills a piece, and ~4 more tries at the sixth. The last slot costs
as much as the first four combined. Ichor drops off four of twelve warden
variants: **at 7 annointable pieces a full kit is ~140 vials.** If that supply
is not there, lower the cap to 4 before touching the outcome table.

Converging on a *chosen* six is far more expensive than filling six — replace
and remove are uniform, so the altar is never a crafting bench.

### Edge cases, decided now

| Case | Rule |
| --- | --- |
| At cap (6) | add outcomes become replace |
| Nothing on the piece | remove = nothing; replace = add |
| Rolled entry already on the piece | one reroll inside the sub-pool, then the other kind, then replace |
| Piece worth under 40 (twig bow, club, shiv) | altar refuses it — the same `MAGIC_PRICE` floor already used for rendering junk down |
| 4th ability annointment | the piece's abilities resolve in slot order; the 4th idles, shown greyed as **NO SLOT** |
| Ability grant while the trinket owns slot 3 | trinket wins on the off-hand slot; the armour/weapon skill idles (see armour sheet §3) |
| Rolled annointment is a duplicate of one on the *other* hand | allowed — two Keen Edges (sword and dagger) both count, up to the piece caps |

### Caps on one piece

Six annointments on one weapon is a lot of power. These are the ceilings:

| Knob | Cap on one piece |
| --- | --- |
| Damage bonus (all sources) | +50% |
| Attack / draw speed | +40% |
| Block stamina reduction | −40% |
| Damage reduction | −30% from weapon annointments; armour has its own ceiling sheet (highest single source wins, never stacked) |
| Extra hits from one action | 4 |
| Total proc chance for one action | 35% |
| Heal per hit / per kill | 8 / 25 |
| Bleeds | one per body per item — refresh, never stack |
| Skill slot grants | 3 usable across the whole kit |

## 3. Pool sizes

The 12 catalog skills already in `ANOINT_RECIPES` join their weapon's pool, so a
bow can roll Barrage *or* one of the new bow entries. Daggers are their own pool
and do not roll the sword's.

| Item type | Own entries | Cross-type | Catalog skills folded in | Pool | of which abilities |
| --- | --- | --- | --- | --- | --- |
| Bow | 20 | 3 any main | barrage, triple_volley, piercing_shot | **26** | 8 |
| One-handed sword | 14 | 7 melee + 3 any main | double_slash, lunge_thrust | **26** | 5 |
| Dagger | 8 | 7 melee + 3 any main | backstab | **19** | 4 |
| Two-handed | 12 | 7 melee + 3 any main | spin_slash | **23** | 5 |
| Staff | 14 | 3 any main | fireball, bone_spear | **19** | 6 |
| Shield | 12 | — | shield_bash, shield_charge, shield_slam | **15** | 6 |
| Tome / skull / focus | 10 | — | — | **10** | 3 |

"Abilities" is the sub-pool the 25% *add an ability* outcome draws from;
everything else in the pool is a passive for the roll. Note how thin the shield
and focus ability pools are (6 and 3) — a fifth or sixth annointment on those has
a real chance of a duplicate reroll.

Note: today each skill is bound to one catalog row (`barrage` → `bow_short` only).
The pool model frees it — any bow can wake Barrage — while the *piece* stays the
thing that carries it.

## 4. Bows — pool 26

`#1–20`, plus any main hand `#98–100`, plus the three existing bow skills.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 1 | Warden's Draw | Passive | +20% damage at full draw, +20% draw time (1.0 s → 1.2 s) | only at full draw; half draws unmodified | [ ] |
| 2 | Quick String | Passive | −25% draw time, −15% damage | floor: draw never under 0.5 s | [ ] |
| 3 | Heavy Head | Passive | +20% arrow damage, −15% arrow speed (more drop, more lead) | drop curve stays readable | [ ] |
| 4 | Quiver's Bounty | Passive | 15% of loosed arrows do not consume a shaft | rolled on release, authoritative only | [ ] |
| 5 | Flat Flight | Passive | arrows lose no drop out to 45 m; travel time and lead kept | GRAVITY disabled in flight only | [ ] |
| 6 | Knife Eye | Passive | +40% damage on headshots | headshot hitbox must reach | [ ] |
| 7 | Rain of Ash | Ability · 40 stamina · 18 s | 8 arrows into a 6 m circle at 25 m, 0.4× each, 0.25 s apart | cap 8 bodies per volley | [ ] |
| 8 | Hamstring Shot | Ability · 35 stamina · 10 s | 15 m shot: 0.6×, target −50% move for 2.5 s | misses still cost | [ ] |
| 9 | Skewer | Ability · 50 stamina · 14 s | line shot, pierces 3 bodies, 0.8× each, 0.6 s stagger | max 3 pierce | [ ] |
| 10 | Hunter's Mark | Ability · 30 stamina · 20 s | mark one body 10 s: +20% damage from all sources, visible through walls | one mark at a time | [ ] |
| 11 | String Snap | Ability · 20 stamina · 8 s | point blank 3 m: 1.4×, 1 s stagger, no arrow spent | melee reach, not a shot | [ ] |
| 12 | Double Nock | Passive · on attack 10% | loose a second arrow along the same line at 50% | one extra per loose | [ ] |
| 13 | Warden's Volley | Passive · every 3rd loose | also fires at the nearest other body within 8 m for 60% | target must be in the cone | [ ] |
| 14 | Snap Draw | Passive · on attack 15% | the draw completes instantly | only from a fresh draw | [ ] |
| 15 | Ricochet | Passive · on attack 20% | an arrow that hits bounces to the nearest body within 6 m for 40% | one bounce, no chain | [ ] |
| 16 | Bleed | Passive · on hit 20% | 6 damage over 3 s (a real DoT through combat, not the stain) | one bleed per body per item | [ ] |
| 17 | Shaft Through | Passive · on hit 15% | the arrow continues past the body for 60% | one continuation | [ ] |
| 18 | Cripple | Passive · on hit 20% | target −40% move for 2.5 s | no stack with itself | [ ] |
| 19 | Headhunter's Refund | Passive · on hit 10% on a headshot | refunds the arrow and the draw | headshot only | [ ] |
| 20 | Parting Shot | Passive · on damage 6 s | a body that lands a melee hit on you takes a point-blank arrow for 60% | never interrupts your own draw | [ ] |

## 5. One-handed swords — pool 26

`#21–34`, plus melee main hand `#91–97`, any main hand `#98–100`, plus
double_slash / lunge_thrust. Daggers do **not** roll this section.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 21 | Keen Edge | Passive | +15% damage | caps with other sources at +50% | [ ] |
| 22 | Light Hand | Passive | −20% swing time, −10% damage | floor: 0.35 s | [ ] |
| 23 | Long Guard | Passive | +0.25 m reach | reach never exceeds the authored arc | [ ] |
| 24 | Off-hand Harmony | Passive | +20% damage while a second blade is in the off hand | second blade or nothing | [ ] |
| 25 | Cheap Guard | Passive | weapon blocks cost 35% less stamina (22 → 14) | dagger and shield unaffected | [ ] |
| 26 | Ripper | Passive | +30% damage to staggered bodies | staggered only | [ ] |
| 27 | Butcher's Cut | Ability · 25 stamina · 6 s | 100° arc, 0.9×, 3 s bleed at 2/s | melee clip, upright stance only | [ ] |
| 28 | Feint | Ability · 20 stamina · 8 s | 0.4 s setup: next swing within 1.5 s is 1.8× and cannot be parried | spent if the window lapses | [ ] |
| 29 | Gut Hook | Ability · 30 stamina · 10 s | 45° arc, 1.4×, 4 s bleed at 2/s | narrow — a miss costs the cooldown | [ ] |
| 30 | Frenzy | Passive · on attack 5% | 3 extra hits in 0.6 s at 0.5× each, in place, no input | one frenzy per swing | [ ] |
| 31 | Whirling Steel | Passive · every 4th swing | a second body within 2 m takes 70% | must be inside the arc | [ ] |
| 32 | Cruel | Passive · on hit 18% | +50% damage | caps with #21 | [ ] |
| 33 | Warden's Verdict | Passive · on hit 8% | 2× damage | one per hit, no chaining | [ ] |
| 34 | Duelist's Answer | Passive · on parry 4 s | a parry inside the 0.25 s window refunds 40 stamina and makes the next swing within 0.8 s 1.3× | parry only, not a block | [ ] |

## 6. Daggers — pool 19

`#35–42`, plus melee main hand `#91–97`, any main hand `#98–100`, plus backstab.
A knife is not a small sword: its pool is built around the 0.5 s stab, the 1.2 m
reach, the weak guard and the +200% forward stab, not around big arcs.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 35 | Wet Work | Passive | +15% damage on a body that has not seen you | unaware only, expires on their first swing | [ ] |
| 36 | Blade Chatter | Passive · on attack 10% | the swing staggers even when the save rolls | no free stagger on a parry | [ ] |
| 37 | Leech | Passive · on hit 12% | heal 4 | 8 per hit cap | [ ] |
| 38 | Still Hand | Passive | +25% damage on a body at full health | opener only — worthless after the first cut | [ ] |
| 39 | Knife Work | Ability · 20 stamina · 6 s | 3 stabs in 0.5 s at 0.6× each, no input after the press | in place; the third stab can headshot | [ ] |
| 40 | Eviscerate | Ability · 30 stamina · 12 s | 2.2× on a bleeding body; a kill refunds the cost | bleeding only, otherwise 1.0× | [ ] |
| 41 | Red Ribbon | Ability · 25 stamina · 10 s | throw the knife 12 m: 1.0×, pins the body in place 1.5 s, returns | unarmed 0.6 s while it is out | [ ] |
| 42 | Undercut | Passive · on hit 20% | knocks the target's guard down for 2 s (`break_guard`) | no effect on a body with no guard up | [ ] |

## 7. Two-handed — pool 23

`#43–54`, plus melee main hand `#91–97`, any main hand `#98–100`, plus
spin_slash.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 43 | Cleaving Weight | Passive | +30% damage, +25% swing time | the trade is the point | [ ] |
| 44 | Momentum | Passive | +8% damage per consecutive hit on the same body, cap +40%, resets on miss or swap | resets on a new body | [ ] |
| 45 | Unstoppable | Passive | cannot be staggered mid-swing by chip damage | a lethal or headshot hit still recoils | [ ] |
| 46 | Headman | Passive | +50% headshot damage | headshot only | [ ] |
| 47 | Ground Breaker | Ability · 80 stamina · 12 s | slam: 3 m ring, 1.2×, 1.5 s stagger | both feet planted | [ ] |
| 48 | Wide Sweep | Ability · 40 stamina · 8 s | 220° arc, 0.8×, knocks back 1 m | never off a ledge | [ ] |
| 49 | Executioner | Ability · 60 stamina · 15 s | 2.5× on a body under 30% health; a kill refunds the cost | below 30% only, otherwise 1.0× | [ ] |
| 50 | Charge Breaker | Ability · 50 stamina · 10 s | 6 m dash into a 120° arc, 1.3× | travels down the crosshair | [ ] |
| 51 | Crushing Blow | Passive · on attack 12% | the swing ignores the guard entirely | not a parry; a parry still deflects | [ ] |
| 52 | Shatter | Passive · on hit 15% | target loses 40 stamina | drains the guard pool, not health | [ ] |
| 53 | Reaper's Rhythm | Passive · on attack 10% | the swing arcs a full circle at 60% | one circle, no repeat | [ ] |
| 54 | Warded Grip | Passive · first blow each 8 s | while both hands are on the haft, that blow is reduced 40% | no effect while the guard is raised | [ ] |

## 8. Staves — pool 19

`#55–68`, plus any main hand `#98–100`, plus fireball / bone_spear.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 55 | Ember Vessel | Passive | +20% spell damage | caps with other sources at +50% | [ ] |
| 56 | Bone Focus | Passive | spell cooldowns −20% | floor 1.0 s | [ ] |
| 57 | Ashen Channel | Passive | spell stamina costs −25% | granted skills included | [ ] |
| 58 | Kindled | Passive | spell hits apply a 3 s burn at 2/s | one burn per body per item | [ ] |
| 59 | Twin Sigil | Passive | spells pierce 1 extra body | +1 only | [ ] |
| 60 | Cinder Lance | Ability · 45 stamina · 10 s | 26 m beam, 1.4×, pierces 4 | straight line only | [ ] |
| 61 | Grave Bloom | Ability · 55 stamina · 14 s | 4 m bloom at 18 m, 1.0×, −60% move for 2 s | does not affect allies | [ ] |
| 62 | Ember Ward | Ability · 40 stamina · 20 s | a 6 s ward absorbing 40 damage | one ward at a time | [ ] |
| 63 | Rift Step | Ability · 35 stamina · 12 s | blink 8 m, leave a 2 m fire patch for 4 s at 5/s | destination preflight, never into rock | [ ] |
| 64 | Overcast | Passive · on cast 12% | the spell casts twice, second at 50% | one echo per cast | [ ] |
| 65 | Wildfire | Passive · on cast 15% | the projectile leaves a 2 m burning patch for 3 s at 4/s | one patch per cast | [ ] |
| 66 | Combustion | Passive · on hit 10% | the spell hit bursts 3 m for 50% | friendly bodies unaffected | [ ] |
| 67 | Soul Burn | Passive · on hit 8% | the spell hit restores 60 stamina | 1000-point pool | [ ] |
| 68 | Cinder Guard | Passive · on damage 15% | an incoming arrow or spell is burned out of the air | projectiles only | [ ] |

## 9. Shields — pool 15

`#69–80`, plus shield_bash / shield_charge / shield_slam.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 69 | Banded | Passive | block stamina −35% (18 → 12) | floor 8 | [ ] |
| 70 | Wide Boss | Passive | +15% block arc | cap 200° | [ ] |
| 71 | Spiked Rim | Passive | +8 damage on any shield skill (base 18) | shield skills only | [ ] |
| 72 | Bulwark | Passive | guard drains 35% slower (20/s → 13/s) | the 25-stamina raise floor still applies | [ ] |
| 73 | Aegis Wall | Ability · 60 stamina · 25 s | plant 3 s: blocks all damage from the front 180°, allies behind you included; cannot move | rooted; flank still open | [ ] |
| 74 | Shield Toss | Ability · 30 stamina · 14 s | throw 8 m, 1.5×, 2 s stagger; the board returns after 2 s | cannot raise a guard while it is out | [ ] |
| 75 | Rebuke | Ability · 25 stamina · 10 s | 90° arc, 0.7×, plus 50% of the last blocked hit reflected | needs a block inside 5 s | [ ] |
| 76 | Iron Retort | Passive · on block 15% | the attacker is staggered 0.6 s | a parry is not a block | [ ] |
| 77 | Riposte Plate | Passive · every 4th block | the next swing within 1 s is 2× | expires after 1 s | [ ] |
| 78 | Sanguine Board | Passive · every 3rd block | the board drinks: heal 6 | one heal per block, no crit stacking | [ ] |
| 79 | Warded Face | Passive · on damage 20% on a blocked spell | the spell is reflected at the caster for 100% | blocked spells only | [ ] |
| 80 | Last Board | Passive · on damage once per 60 s | a lethal blow leaves you at 1 health instead | once per item, announced | [ ] |

## 10. Tome, skull, focus — pool 10

`#81–90`. Off hand only; the third slot's home.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 81 | Quiet Words | Passive | +15% spell damage while a staff is in the main hand | staff required | [ ] |
| 82 | Skullward | Passive | +12 max health | gear-derived, never banked | [ ] |
| 83 | Bone Lattice | Passive | stagger time ×0.75 | rides `Combat.stagger_scale`, which scales seconds, not the save | [ ] |
| 84 | Grim Page | Passive · on kill | restores 15 stamina and 3 health | mirrors the skull trinkets | [ ] |
| 85 | Grave Word | Ability · 30 stamina · 12 s | 2 s silence on a body within 12 m: it cannot use skills | one silenced body | [ ] |
| 86 | Bone Choir | Ability · 70 stamina · 25 s | two bone hands fight for 8 s at 9/s each | 2 extra bodies against the body budget | [ ] |
| 87 | Final Word | Ability · 50 stamina · 18 s | a body under 25% health takes 2× and is executed; otherwise 1.0× | threshold only | [ ] |
| 88 | Ink Bloom | Passive · on hit 12% | a spell hit silences for 2 s | spell hits only | [ ] |
| 89 | Skullgnaw | Passive · on hit 10% | a spell hit restores 60 stamina | spell hits only | [ ] |
| 90 | Copper Ward | Passive · on damage 10% | any incoming hit is reduced 30% | caps with armour's ceilings | [ ] |

## 11. Melee main hand — `#91–97`

Sword, dagger, two-hander.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 91 | The Long Hunt | Passive | +10% damage to bodies that have not hit you | resets when they land one | [ ] |
| 92 | Ichor Rite | Passive | +12% damage while below half health | threshold 50 health | [ ] |
| 93 | Butcher's Toll | Passive · on kill | each kill: +15% damage for 8 s, stacks 3 | stacks never refresh the timer | [ ] |
| 94 | Thirst | Passive · on kill | each kill heals 6 | 25 per kill cap | [ ] |
| 95 | Iron Hide | Passive | −25% damage taken while below 30% health | caps with #90 and the armour ceilings | [ ] |
| 96 | Second Wind | Passive · on kill | downing a body refunds 100 stamina | 1000-point pool | [ ] |
| 97 | Grim Focus | Passive | every 3rd landed hit is a guaranteed headshot where the swing can reach the head | counter resets on a miss | [ ] |

## 12. Any main hand — `#98–100`

Bow, staff, sword, dagger, two-hander.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 98 | Blood Price | Passive | +18% damage; each landed hit costs 3 health | cannot kill you — floors at 1 health | [ ] |
| 99 | Warden's Brand | Passive · on hit | 3 hits on the same body applies 4/s bleed for 6 s | one bleed per body per item | [ ] |
| 100 | Bound Ink | Passive | annointed skills on this piece cost 50% less stamina | this piece's skills only | [ ] |

## 13. Balance math

One swing of a 30-damage weapon is the unit. Expected value per 100 swings:

| Modifier | EV per 100 swings | Read |
| --- | --- | --- |
| Keen Edge (+15%) | +450 damage | the floor a passive must clear |
| Cruel (18% × +50%) | +270 | a proc pays less than a passive on purpose |
| Warden's Verdict (8% × +100%) | +240 | spikier, slightly below Cruel |
| Frenzy (5% × 3 × 0.5×) | +225 | the showpiece is not the best DPS |
| Double Nock (10% × 50% arrow) | +5 arrows | throughput, plus ammo pressure |
| Warden's Volley (every 3rd × 60%) | +33% damage when a second body is in 8 m | conditional, not raw DPS |
| Shatter (15% × 40) | 600 stamina off the target | the anti-guard pick |

Target bands: passives 8–15%, procs 5–10% EV, abilities balanced on cooldown
rather than per swing. A proc should never out-EV its passive cousin; the
variance is what the player is buying.

Six annointments at +50% damage, +25% damage on kills and a 15% double-damage
proc is where the caps do their work — the ceilings, not the pool, decide how
strong a finished weapon is.

## 14. Implementation notes

- **Per-item identity is the one real change.** `cruor.anointed` is keyed by
  catalog id, so every Shortbow in the stash shares one skill, and
  `anointed_among([main, off])` answers catalog ids. Individual annointments need
  a copy identity — minted on acquisition, carried through roster kits and stash
  rows — and one save version bump. Migration that costs nobody a purchase: seed
  every owned copy with whatever its catalog id was anointed with, then diverge.
- **Six annointments needs a list, not a field.** The ledger becomes
  `copy id → [{id, kind, rolled_at}]`, capped at 6, and the altar needs a scroll
  or a second page to show them.
- **The 0.25 s parry window, 18/22/30 block costs and `stagger_scale` are
  existing knobs** — `#25`, `#34`, `#42`, `#69`, `#72`, `#76`, `#83` should ride
  them rather than invent parallel numbers.
- **`break_guard()` exists** — `#42` Undercut calls it instead of modelling a
  guard break of its own.
- **Blood is presentation.** `BloodFx` must not change damage; `#16`, `#27`,
  `#29`, `#39`'s bleed cousins and `#99` need a real damage-over-time path.
- **Authority.** Every proc rolls on the authoritative body only — the rule
  `WarbandAbilities` already enforces (`MAX_MISSILES`, standing + authoritative).
  A guest rolling Double Nock is a second arrow nobody asked for.
- **Resolve the roll once, server-side of the item, and write it to the save.**
  No reroll-on-reload. Because there is no destruction, a client-side reroll is
  now pure gain — this is the new exploit surface, not the old one.
- Annointment and brand are separate ledgers; `#100` and the brand's own cost
  reductions must be read together, not double-counted.
- Quests: `bind_the_ichor` and the `APPLY` goal count applications; with no
  destroy outcome every vial credits, so the goal's target may need to rise.

## 15. Open questions for your review

1. **Ichor supply** — is ~20 vials a piece affordable? If not, cap 4 (12.2
   vials) or 3 (8.5) before touching the outcome table.
2. **At cap** — add-becomes-replace as written, or should a full piece give
   nothing on the add outcomes (harsher, but wastes a vial)?
3. **Remove** — random as written, or does the player choose which one burns?
4. **Six abilities** — should abilities be capped separately (say 2 per piece)
   so the slot pressure stays meaningful?
5. **Dagger reach** — is a 1.2 m knife allowed `#23`-style reach or `#41`'s
   throw, or does the dagger pool stay purely close and quiet?
