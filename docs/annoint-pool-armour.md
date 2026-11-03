# The Annointment Pool — 100 armour modifiers

Companion sheet to `docs/annoint-pool.md` (weapons). The roll, the cap and the
edge cases are identical — read §2 there. This sheet is the armour half: what
can be welded to head, chest, hands, legs and feet, and what that costs the
engine.

A body wears five armour pieces. Six annointments each is **30** on armour, plus
12 on the two weapon hands — 42 on a finished body. That number is why §2's
ceilings matter more than any single entry.

## Status — implemented (build of 2026-11-03)

The armour sheet's stat ladders and the receiver-side procs are live; its
**abilities are not** — they need the third slot contest described in §3, so
they are deferred rather than half-wired. `scripts/warband/annoint_catalog.gd`
holds them:

| | |
| --- | --- |
| Armour families | 11 ladders × 5 rungs = 55 entries (`f_armour_*`) |
| Armour bundles | 14 stat rows + 9 rows on shields and focuses (`a_*`, `o_*`) |
| Armour procs | 6 wired (`a_bone_rivets`, `a_return_fire`, `a_iron_retort`, `a_sanguine_board`, `a_second_heart`, `a_snap_stitching`, `o_copper_ward`); 2 deferred |
| Armour skills | **0 of the 8 in this sheet** — deferred, see below |
| Slots | all five armour slots roll from their own pool; shields and focuses roll from theirs |

Every stat this sheet asks for that already has a `TrinketStats` key is
implemented as that key — `guard`, `health`, `stamina`, `stamina_regen`,
`move_speed`, `attack_speed`, `melee_damage`, `ranged_damage`, `throw_damage`,
`stagger`, `cooldown`, `gold_find`, `heal_on_kill`, `stamina_on_kill`. The kit
ceilings in §2 are enforced in `AnnointLedger.CEILINGS` and the armour channel's
0.60 clamp still sits above them.

The 43 ⊕ entries that need new plumbing (sight, sprint, crouch, loot clocks,
revive speed, per-source resist, head-only reduction) are **not** wired. They
stay in this sheet as the backlog; adding one is a row plus the key it names.

## 0. The dials armour sits against

| Knob | Value | Source |
| --- | --- | --- |
| Slots | head · chest · legs · hands · feet | `ArmorData.SLOTS` |
| Set reductions | plate head 0.50 · mail 0.30 · leather 0.20 · body 0.30 / 0.25 / 0.10 | `HEAD_REDUCTION`, `BODY_REDUCTION` |
| Body weights | chest 1.0 · legs 1.0 · hands 0.3 · feet 0.3 | `BODY_WEIGHTS` |
| Reduction cap | **0.60** per channel, armour + worn guard added then clamped | `TrinketStats.GUARD_CAP` |
| Move clamp | `move_scale` 0.5–2.0 · rings already give 8% | `TrinketStats.move_scale` |
| Attack clamp | `attack_rate` 0.5–3.0 · a 12% ring turns a 1.0 s draw into 0.89 s | `TrinketStats.attack_rate` |
| Health / stamina | 100 / 1000 on every mercenary, gear is the only difference | `WarbandContracts` |
| Downed | 30 s bleed-out · 5 s revive channel · revived at 5% health | `WarbandContracts` |
| Loot | one duck of 0.9 s per pile | `WarbandLootHand` |

## 1. What an armour annointment feeds

The cheapest annointments are the ones that write into the stat dictionary
`TrinketStats` already sums. Those need no new aggregation, no new clamp, and
they show up in the paperdoll tooltip for free.

| Family | Key | Status |
| --- | --- | --- |
| damage reduction | `guard` | exists (clamped 0.60 with the armour channel) |
| health / stamina | `health`, `stamina` | exists |
| regen | `stamina_regen` | exists |
| move / sprint | `move_speed` | exists (sprint is separate, see ⊕) |
| attack speed | `attack_speed` | exists |
| damage | `melee_damage`, `ranged_damage`, `throw_damage` | exists |
| cooldowns | `cooldown` | exists |
| stagger taken | `stagger` | exists |
| kill rewards | `heal_on_kill`, `stamina_on_kill`, `gold_find` | exists |

Everything else is new plumbing. Entries marked **⊕** need a key, a trigger or a
buff the game does not have yet:

| Need | Entries | Cost |
| --- | --- | --- |
| proc / timed buff / immunity | 9, 19, 22, 37, 46, 47, 63, 64, 71, 73, 75, 94, 97, 99 (14) | one shared trigger system — the same one the weapon sheet already assumes |
| reduction by damage source | 20, 21, 27, 49, 58 (5) | a source tag on the damage call |
| head channel | 31, 34 (2) | one extra key, `guard_head` |
| conditional guard (raised / still / behind) | 48, 56, 81, 92 (4) | a conditional read at the damage call, no save data |
| sight / stealth / map | 14, 32, 35, 36, 89 (5) | reads the aggro cone and the map |
| movement, regen and standing conditions | 15, 26, 80, 82, 90, 91, 96 (7) | movement and regen constants, terrain checks |
| revive / bleed-out / loot / consumables | 23, 24, 29, 30, 70, 86 (6) | scene-level clocks, not the stat dict |
| **total marked** | **43** | |

The other **57** need nothing new: they are keys `TrinketStats` already sums, and
they appear in the paperdoll tooltip the moment they exist.

## 2. Kit ceilings

Every armoured body would otherwise stack 30 annointments, and `WarbandContracts`
exists to keep mercenaries identical. These are the ceilings, counted across all
worn armour, annointments only (armour's own set reduction and rings sit
underneath and are not counted here):

| Family | Ceiling from annointments, whole kit |
| --- | --- |
| damage reduction (`guard`) | rides the existing 0.60 channel cap — **no new cap** |
| max health | +60 |
| max stamina | +250 |
| stamina regen | +50% |
| attack speed | +25% |
| move speed | +20% |
| melee / ranged / throw damage | +30% each |
| cooldown reduction | −30% |
| gold find | +50% |
| conditional reductions (all sources combined) | −50% |

The engine already clamps `move_scale` at 2.0 and `attack_rate` at 3.0. These
ceilings sit well below those on purpose: a player who hits a silent clamp
believes the entry is broken.

## 3. How armour rolls

Same `d100` as the weapon sheet — add ability / add passive / remove / replace,
25% each, cap 6, no destruction. Two armour-only rules:

- **Abilities on armour fight for the third slot.** That slot belongs to the
  trinkets today (`ABILITY_GRANTS`, order neck → ring1 → ring2). Armour extends
  the order: neck → ring1 → ring2 → chest → head → hands → legs → feet. A trinket
  grant always wins; an armour skill with no slot shows greyed **NO SLOT**.
- **Abilities are the minority of this pool on purpose** — 8 of 100 (#50–52,
  #65–66, #83–84, #93). A kit that stacks armour skills mostly idles them.

## 4. Any armour — 30

Every slot.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 1 | Case-Hardened | Passive | guard +3% (both channels) | fits under the 0.60 cap | [ ] |
| 2 | Sewn Doubling | Passive | +12 max health | counts to the +60 ceiling | [ ] |
| 3 | Deep Lungs | Passive | +80 max stamina | counts to +250 | [ ] |
| 4 | Knitted Gait | Passive | +15% stamina regen | counts to +50% | [ ] |
| 5 | Braced | Passive | stagger time ×0.85 | rides `stagger`, which shortens the recoil, not the save | [ ] |
| 6 | Iron Seams | Passive | +8 max health, guard +1% | two small ones | [ ] |
| 7 | Warded Stitch | Passive | guard +2%, +6% stamina regen | — | [ ] |
| 8 | Salvage Plates | Passive | guard +4% on a mail or plate piece | reads the set, not the slot | [ ] |
| 9 | Bone Rivets ⊕ | On damage taken · 8% | regain 15 stamina | one proc per hit | [ ] |
| 10 | Blooded Padding | Passive · on kill | heal 2 | counts to 25 per kill | [ ] |
| 11 | Gristle | Passive | guard +6% while under 30% health | conditional reduction | [ ] |
| 12 | Second Skin | Passive | +10 health, −5% move | the trade is the point | [ ] |
| 13 | Hunter's Weave | Passive | +5% move | counts to +20% | [ ] |
| 14 | Soft Tread ⊕ | Passive | bodies acquire you 15% later | aggro cone only | [ ] |
| 15 | Long Watch ⊕ | Passive | +10% stamina regen while standing still | loses the buff on any step | [ ] |
| 16 | Ritual Threads | Passive | annointed skill cooldowns −8% | counts to −30% | [ ] |
| 17 | Warden's Mark | Passive | +10% gold from kills | `gold_find` | [ ] |
| 18 | Dead Weight | Passive | +15 stamina on kill | `stamina_on_kill` | [ ] |
| 19 | Snap Stitching ⊕ | On damage taken · first each 10 s | that hit is reduced 20% | one absorb per 10 s | [ ] |
| 20 | Boiled Leather ⊕ | Passive | incoming arrows −15% | arrows only | [ ] |
| 21 | Ash Coat ⊕ | Passive | incoming spells −20% | spells only | [ ] |
| 22 | Return Fire ⊕ | On damage taken · 10% | the attacker takes 4 | never on a blocked hit | [ ] |
| 23 | Grim Hold ⊕ | Passive | bleed-out 30 s → 40 s | one revive window longer | [ ] |
| 24 | Slow Harvest ⊕ | Passive | revive channel 5 s → 4 s | floor 3.5 s with #86 | [ ] |
| 25 | Iron Constitution | Passive | +8 health, +40 stamina | — | [ ] |
| 26 | Closing Flesh ⊕ | Passive | out-of-combat health regen 1 hp / 5 s → 1 hp / 3 s | combat cancels it; #96 is stamina, this is health | [ ] |
| 27 | Cinder Lining ⊕ | Passive | burn / bleed damage −25% | DoTs only, not hits | [ ] |
| 28 | Hollow Ward | Passive | spells cost 10% less stamina | granted skills included | [ ] |
| 29 | Quartermaster's Knot ⊕ | Passive | loot duck 0.9 s → 0.6 s | per pile | [ ] |
| 30 | Sanguine Draught ⊕ | Passive | consumable heals ×1.25 | bandage 0.3 → 0.375 | [ ] |

## 5. Head — 12

Perception and precision. Note that plate already sits at 0.50 of a 0.60 head
cap, so head-only reduction is nearly worthless on a plate helm and worth real
money on cloth.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 31 | Nose Guard ⊕ | Passive | head hits 5% less (`guard_head`) | only 0.10 of plate's head budget left | [ ] |
| 32 | Open Faced ⊕ | Passive | +10% sight range | scout utility | [ ] |
| 33 | Helmed Focus | Passive | +5% melee and ranged damage | counts to +30% each | [ ] |
| 34 | Pig Iron Brow ⊕ | Passive | head hits 12% less | the anti-headshot pick | [ ] |
| 35 | Hooded ⊕ | Passive | bodies acquire you 15% later | stacks with #14 to −30% cap | [ ] |
| 36 | Whisper Wire ⊕ | Passive | hostiles show on the map 5 m further | map only, no live ping | [ ] |
| 37 | Crown of Teeth ⊕ | On kill within 8 m | +5% damage for 4 s | refreshes, does not stack | [ ] |
| 38 | Warden's Pendulum | Passive | annointed skill cooldowns −6% | counts to −30% | [ ] |
| 39 | Beaten Coif | Passive | +6% stamina regen | counts to +50% | [ ] |
| 40 | Iron Jaw | Passive | +10 max health | counts to +60 | [ ] |
| 41 | Bone Cage | Passive | stagger time ×0.8 | rides `stagger` | [ ] |
| 42 | Keen Sight | Passive | +10% ranged damage | counts to +30% | [ ] |

## 6. Chest — 16

The body channel, the health pool, and the two loud defensive skills.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 43 | Plated Ribs | Passive | guard +4% | plate body is 0.30 of a 0.60 cap | [ ] |
| 44 | Bulwark Plate | Passive | +20 max health | counts to +60 | [ ] |
| 45 | Iron Lungs | Passive | +120 max stamina | counts to +250 | [ ] |
| 46 | Second Heart ⊕ | On damage taken · once per 60 s | a lethal blow leaves you at 1 health | once per kit, announced | [ ] |
| 47 | Grave Ward ⊕ | On damage taken · 10% | reflect 25% of melee damage | melee only, no spell reflect | [ ] |
| 48 | Banded Hide ⊕ | Passive | guard +10% while the guard is raised | gone the moment it drops | [ ] |
| 49 | War Coat ⊕ | Passive | bleed / burn damage −20% | with #27 to a 35% cap | [ ] |
| 50 | Bulwark Breath | Ability · 40 stamina · 20 s | 2 s plant: damage taken −50%, stamina regen ×3 | rooted; no block while planted | [ ] |
| 51 | War Cry | Ability · 50 stamina · 30 s | allies within 8 m +10% damage for 6 s | allies only, never self | [ ] |
| 52 | Steady Heart | Ability · 30 stamina · 20 s | clear stagger, immune to stagger for 2 s | does not clear a downed state | [ ] |
| 53 | Oiled Mail | Passive | weapon blocks −15% stamina | shield blocks included | [ ] |
| 54 | Deep Chest | Passive | +20% stamina regen while not sprinting | — | [ ] |
| 55 | Bone Lattice Corset | Passive | guard +5%, −3% move | — | [ ] |
| 56 | Quilted Back ⊕ | Passive | attacks from behind −12% | behind = outside the front 90° | [ ] |
| 57 | Bound Ribs | Passive | revived allies return with +10 health | rides the revive, not the body | [ ] |
| 58 | Cinder Slot ⊕ | Passive | incoming spells −10% | stacks with #21 to −35% cap | [ ] |

## 7. Hands — 18

The offensive slot. Gloves are where attack speed, procs and casting live —
a hands piece contributes only 0.3 weight to the set's body reduction, so guard
numbers here are wasted on the sheet.

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 59 | Quick Knuckles | Passive | +8% attack speed | `attack_rate`; counts to +25% | [ ] |
| 60 | Gripped Haft | Passive | +5% melee damage | counts to +30% | [ ] |
| 61 | Steady Draw | Passive | +6% ranged damage | counts to +30% | [ ] |
| 62 | Thrower's Grip | Passive | +10% throw damage | counts to +30% | [ ] |
| 63 | Bloody Knuckles ⊕ | On melee hit · 12% | +20% damage on that hit | one proc per swing | [ ] |
| 64 | Feathered Fingers ⊕ | On loose · 10% | the arrow costs no shaft | authoritative only | [ ] |
| 65 | Overhand Cast | Ability · 30 stamina · 12 s | the next spell within 3 s deals +50% | spent if the window lapses | [ ] |
| 66 | Quick Hands | Ability · 40 stamina · 18 s | 4 s: draw and nock instantly | does not raise the guard | [ ] |
| 67 | Grip of Ash | Passive | +6% attack speed, −4% damage | the trade is the point | [ ] |
| 68 | Rosined Palm | Passive | +8% melee damage with a two-hander | two-hander required | [ ] |
| 69 | Bracer Plates | Passive | blocks −10% stamina, guard +2% | small and cheap | [ ] |
| 70 | Thief's Fingers ⊕ | Passive | loot 25% faster | per pile | [ ] |
| 71 | Whetstone Palm ⊕ | On melee hit · 15% | 2/s bleed for 3 s | one bleed per body per item | [ ] |
| 72 | Bone Knuckles | Passive | +4 flat melee damage | before multipliers | [ ] |
| 73 | Sure Grip ⊕ | Passive | swings are not interrupted by chip damage | a lethal hit still recoils | [ ] |
| 74 | Trigger Finger | Passive | +6% attack speed, +4% ranged damage | — | [ ] |
| 75 | Hooked Palm ⊕ | On melee hit · 8% | pull the body 1 m closer | never through a wall | [ ] |
| 76 | Casting Glove | Passive | spells pierce 1 more body | +1 only | [ ] |

## 8. Legs — 10

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 77 | Padded Thighs | Passive | guard +2%, +3% move | — | [ ] |
| 78 | Long Stride | Passive | +6% move | counts to +20% | [ ] |
| 79 | Knee Plates | Passive | guard +3% | — | [ ] |
| 80 | Sprinter's Cut ⊕ | Passive | sprint drain 19/s → 16/s | ~16% longer sprint | [ ] |
| 81 | Braced Stance ⊕ | Passive | guard +15% while standing still | gone on the first step | [ ] |
| 82 | Crouch Weave ⊕ | Passive | crouch move speed +20% | crouch only | [ ] |
| 83 | Burst | Ability · 25 stamina · 12 s | 2 s: +40% move | stacks with the +20% ceiling, clamped | [ ] |
| 84 | Root Down | Ability · 30 stamina · 25 s | 4 s: cannot be shoved off the spot | still takes damage | [ ] |
| 85 | Binder Straps | Passive | +6% stamina regen | counts to +50% | [ ] |
| 86 | Field Dressing ⊕ | Passive | revive channel 5 s → 4.25 s | floor 3.5 s with #24 | [ ] |

## 9. Feet — 14

| # | Modifier | Trigger | Effect | Guardrail | Keep |
| --- | --- | --- | --- | --- | --- |
| 87 | Soft Leather | Passive | +7% move | counts to +20% | [ ] |
| 88 | Iron Caps | Passive | guard +2%, +4 max health | small and cheap | [ ] |
| 89 | Quiet Tread ⊕ | Passive | bodies acquire you 10% later | with #14 and #35 to a −30% cap | [ ] |
| 90 | Sure Footing ⊕ | Passive | keep full speed on an 18° slope | slopes only | [ ] |
| 91 | Sprint Straps ⊕ | Passive | +10% sprint speed | sprint only, not walk | [ ] |
| 92 | Heel Plates ⊕ | Passive | attacks from behind −10% | stacks with #56 | [ ] |
| 93 | Skirmish Step | Ability · 20 stamina · 10 s | a 4 m quick step in the facing direction | the dodge step's own lane | [ ] |
| 94 | Bloodied Spurs ⊕ | On kill | +15% move for 3 s | refreshing buff | [ ] |
| 95 | Hobnails | Passive | +6% move, +2% guard | — | [ ] |
| 96 | Long Marches ⊕ | Passive | out-of-combat stamina regen ×2 | 13/s → 26/s, combat cancels | [ ] |
| 97 | Arrow Catch ⊕ | On damage taken · 12% vs an arrow | the arrow misses | arrows only | [ ] |
| 98 | Rag Wraps | Passive | +10% stamina regen | counts to +50% | [ ] |
| 99 | Turned Heel ⊕ | On damage taken · 20% when struck from behind | +25% move for 2 s | one per hit | [ ] |
| 100 | Grim March | Passive | +10% move while under 30% health | conditional | [ ] |

## 10. Balance math

Damage reduction is multiplicative, so a percentage of it is worth more the more
you already have. Effective health = `pool / (1 − reduction)`:

| Reduction | Effective health (100 pool) | +5% more is worth |
| --- | --- | --- |
| 0.10 | 111 | +5.9% |
| 0.30 | 143 | +7.7% |
| 0.50 | 200 | +11.1% |
| 0.60 (cap) | 250 | — |

That is why the numbers in this sheet are small and why the cap is not raised:
a plate helm at 0.50 is already double effective health on a head hit, and every
point past it is worth more than the point before.

Health versus guard, on a plate body (0.30):

| Pick | Effective health | Read |
| --- | --- | --- |
| +20 max health (#44) | 171 | the early pick; also helps against DoTs |
| +4% guard (#43) | 151 | the late pick; worth more on an already-armoured body |
| +12 health (#2) | 160 | the safe, slot-agnostic middle |

Attack speed on gloves is a rate, not a sum: `attack_rate` = 1 + value, so **+8%**
turns a 1.0 s draw into 0.926 s and a 2.0 s arming swing into 1.852 s. At the +25%
kit ceiling a 1.0 s draw is 0.8 s — fast, still one arrow per loose.

Move speed is the entry that changes how the game feels, so it has the widest
support and the tightest ceiling: 8% already sits on a ring, `move_scale` clamps
at 2.0, and the kit ceiling here is +20%.

## 11. Open questions for your review

1. **Should armour carry abilities at all?** They fight the trinket for slot 3
   and mostly idle. Keeping only 8 of 100 is a compromise, not a position.
2. **Plate saturation** — a plate helm has 0.10 of head budget left, which makes
   #31 and #34 dead entries on the best helm in the game. Reroll them into
   something else, or leave them as the reason cloth is playable?
3. **Health ceiling** — +60 on 100 is a 60% pool increase across six annointments
   per piece. Correct, or should health annointments be rarer (weighted) rather
   than capped?
4. **The ⊕ list** — 43 of the 100 need plumbing, 14 of those are one shared
   proc system. Ship the 57 free ones first, or build the trigger layer now and
   take the whole sheet?
5. **Jewelry** — neck and rings are deliberately absent. Their table already owns
   the 0.60 guard ceiling and the third slot; annointing them would double-count
   both. Confirm that stays out.
