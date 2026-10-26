# Unholy Forest mobset

Three frontier mobs — **Hollow warden**, **Ossuary stalker** and **Gallowsroot** —
own the woodland outside Hearthstead. They are original procedural work: no
third-party model, texture or motion is used, and the supplied design sheet
was ink-and-wash inspiration only (not redistributed, not a build input).

The same set supplies the **Makeshift** starter gear: the salvage armour the
ranger begins in and the salvage blades the smith sells beside the forged kit.

## Sources and licensing

| Surface | Origin |
| --- | --- |
| Every mesh, rig and clip | `tools/prepare_forest_mobs.py` (deterministic Blender Python) |
| Every texture | `tools/forest_surface.py` analytic fields, rasterised into per-material UV atlases |
| Palettes, clip timings, budgets | `tools/forest_styles.py` |
| Makeshift armour meshes | `tools/prepare_makeshift_armor.py` |

All of it is authored in this repository and distributed under the same CC0 1.0
dedication as the rest of `assets/characters/` (see `LICENSE.txt` there). No
generated image, photogrammetry scan, paid pack or restricted file is used, and
no download is required to rebuild any of it.

## The three mobs

| Mob | Read | Gameplay |
| --- | --- | --- |
| Hollow warden | Hooded grave-cloth atop a hole in the world, two ember eyes, a branching antler rack growing out of the crown, clawed hands under ragged sleeves | Charger: slow, tall, reach 2.35 m, 96 health, 16 damage |
| Ossuary stalker | A hooded human in a fitted sackcloth tunic and torn skirt, hide bracers and boots, a carved bone mask with **empty black sockets**, and antlers lashed to a brow band | Crawler: fastest of the set, 54 health, 10 damage, closes distance quickly |
| Gallowsroot | A big man in a long tattered coat, bark plates strapped over it, a carved wooden mask with embers in the slit, branches lashed to a brow band, bark mitts and boots | Brute: 168 health, 24 damage, reach 2.55 m, slow and deliberate |

## Repository surfaces

| Surface | Purpose |
| --- | --- |
| `tools/prepare_forest_mobs.py` | Geometry, rig, skin weights, PBR atlas bake, six clips, GLB + JSON export, captures |
| `tools/forest_surface.py` | Analytic surface fields (bark, cloth, bone, antler, moss, void, ember) and tangent normals |
| `tools/forest_styles.py` | Mob recipes, clip timings, palettes, atlas sizes |
| `tools/build_forest.py` | One-command rebuild for one mob or all three |
| `assets/characters/forest/ironwood_<mob>.glb` | Runtime skinned, animated, textured mesh |
| `assets/characters/forest/ironwood_<mob>.json` | Measured bounds, bones, clips, materials, root drift |
| `assets/characters/forest/ironwood_<mob>.glb.import` | Godot import settings (embedded images, 60 Hz sampling) |
| `scripts/forest_mob.gd` | Gameplay profiles; reuses the devil state machine via its virtual hooks |
| `scripts/forest_mob_visual.gd` | Presentation table for the imported GLBs |
| `scripts/range_world.gd` | 19 `forest_spawns`, separate from the 36 legacy and 16 devil tables |
| `tests/forest_mobs_regression.gd` | Asset, presentation, gameplay, head-zone and frontier coverage |

Ignored intermediates live in `.runtime/forest-source/<mob>/` (`textures/`,
`captures/`). Do not commit them.

## Build

```powershell
python tools/build_forest.py all
# or one mob
python tools/build_forest.py gallowsroot
```

The wrapper runs Blender 5.1 in background mode, one process per mob (a fresh
scene keeps the rig globals honest). Override the executable with
`IRONWOOD_BLENDER`. After a rebuild, reimport in Godot and run the regression:

```powershell
$Godot = '.\\.runtime\\godot\\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/forest_mobs_regression.gd
```

## Shipped budgets

Measured from the imported GLB.

| Mob | Height | Footprint | Triangles | Bones | Materials | Images |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Hollow warden | 3.76 m | 1.74 m | 30,234 | 43 | 6 | 19 |
| Ossuary stalker | 2.47 m | 0.98 m | 49,214 | 43 | 6 | 18 |
| Gallowsroot | 2.89 m | 1.31 m | 46,538 | 35 | 8 | 25 |

Height includes the antler crown, which is part of the silhouette but not the
collision capsule (`height` in the gameplay profile covers the body only).
Every mesh is one joined skinned `MeshInstance3D` with one PBR material per
surface. Feet sit at approximately y = 0; the warden's robe hem is authored to
stop above the floor so a tattered edge never sinks into the terrain.

## Clip contract

All clips are baked at 60 Hz, in place, with a stationary root
(`root_translation_drift` in the adjacent JSON is 0). Idle, walk and run loop;
attack, hit and death do not. Loop modes are applied by
`scripts/forest_mob_visual.gd`, not inferred from the glTF: Godot's importer
strips a trailing `_Loop` from animation names, so the clips are named
`<Prefix>_<Clip>` and the runtime owns looping.

| Mob | Idle | Walk | Run | Attack (impact) | Hit | Death |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Hollow warden | 2.800 | 1.400 | 0.800 | 1.60 (0.78) | 0.50 | 1.45 |
| Ossuary stalker | 2.400 | 1.100 | 0.700 | 1.25 (0.55) | 0.40 | 1.10 |
| Gallowsroot | 3.200 | 1.800 | 1.000 | 2.10 (1.05) | 0.60 | 1.80 |

Attack timings are authored to the gameplay clock so
`DevilMobVisual._seek_attack()` places the strike pose on the damage frame:
windup, strike and recover are scaled onto the measured impact. No clip event
deals damage.

Locomotion is a planted-foot cycle: each foot's ankle target is solved with
two-bone IK in the sagittal plane (knee forward), so vertical body bob never
lifts a planted foot. The warden's robe and the stalker's shroud carry their own
bone fans (`robe_*`, `shroud_*`) so a swinging arm cannot drag the hem; the
gallowsroot's root legs are planted the same way.

## Material design

Every surface is an analytic field evaluated at each texel's rest-space
position and rasterised into that material's own UV atlas, so bark fissures,
cloth weave and bone grain are continuous across UV seams and carry
texel-scale detail:

- **Bark** — furrowed ridges over a near-black core, broken plates, growth
  striations, weathered lavender-grey crests, lichen flecks; 2048².
- **Cloth** — grave-cloth weave at ~1.2 mm pitch, slubs, dropped stitches,
  vertical thread streaks, frayed hem threads; 2048².
- **Bone** — pale ivory with pores, pitting, a hairline crack network and brown
  stain settling into low relief; 1024².
- **Antler** — keratin growth rings and longitudinal striations, dark stained
  base grading to a pale warm tip; 1024².
- **Moss** — clumped cushion growth with shadowed gaps and dry tips, density
  falling off with height; 1024².
- **Leather** — cured hide: a 4 mm pebble grain with dark creases, fat sheen
  on the crowns, scuffed dye, and stitched seam holes along the panel edge;
  1024². It carries the stalker's body wrap and the tree's lashings.
- **Void** — the black inside of a hood or chest: a faint rim gradient and
  smoke, deliberately no readable detail; 512².
- **Ember** — the hot interior light: cream core, orange iris with radial
  fibres, dark outer ring, plus an emissive map; 256².

Each material carries albedo, normal and roughness maps (the two emissive
surfaces also carry an emissive map), all embedded in the GLB. Normal maps are
derived from the sampled height field with a per-surface strength from
`forest_styles.SURFACES`.

## Geometry notes

- The warden's hood is a scooped cowl: the front is pushed back over a hard
  rim to open a face cavity, with a black void cup and two ember eyes seated in
  it. The antler racks grow from the crown with three recursive tine levels and
  a swept rear tine pair; tine tips keep a real radius so they do not render as
  floating lines.
- Both are **people in costumes**, and the costume follows the body. The stalker
  wears a *fitted* tunic built from metaball volumes — shoulders wider than the
  waist, chest, waist, hips — with a separate short skirt for the torn hem; a
  lathe over the torso reads as a soda can. The Gallowsroot wears a long coat
  with a hide cape over it (the two layers differ in value, or the costume reads
  as one brown bodysuit). Both get ragged sleeves with frayed cuffs, cloth
  trousers, hide bracers and boots, crushed along their normals with layered 3D
  noise so they read as cloth that has been worn and slept in, not as lathes.
- The stalker's head is a carved **bone mask** under a hood with empty black
  sockets — nothing burns in it — and antlers lashed to a hide brow band. Its
  neck is a tapered neck with trapezius mass and a cloth collar, never a pipe.
  Bone is used in small amounts and sewn on: three uneven rib bars and one flat,
  hand-cut pauldron.
- The gallowsroot's head is a carved **wooden mask** with an ember slit, hooded,
  with branches lashed to a brow band. Its plates are flat-shaded, hand-cut bark
  slabs strapped over the coat, and its mitts and boots are bark shells over
  human hands and feet.
- Skinning is per-layer: organic parts use distance envelopes restricted to the
  bones that own them, stiff detail parts are rigidly bound, and no envelope is
  allowed to steal a neighbouring layer's vertices.

## Gameplay integration

- `scripts/forest_mob.gd` extends `scripts/devil_mob.gd` through its virtual
  `_profiles()`, `_group_name()`, `_node_prefix()` and `_visual_script()` hooks.
  One state machine (IDLE/RETURN/CIRCLE/WINDUP/STRIKE/RECOVER/STAGGER/DEAD)
  drives both mobsets; the devils keep their defaults.
- Kinds are 9 (warden), 10 (stalker) and 11 (gallowsroot): 0 is the wolf, 2
  the cinder devil, 3–7 the devils, and 8 is `RangerClone.KIND`, so the forest
  set continues past the clone rather than colliding with it.
- These are natural-weapon mobs: `held_weapon_id()` is empty, so a kill pays
  gold and the standard alternating loot roll, and `blood_strike_point()` is
  the striking hand (`hand_r`) so a claw comes away wet.
- Death clears collision immediately and hands the body to
  `scripts/corpse_hold.gd` (the shared five-minute corpse lifetime).
- The threshold trio spawns about 14 m ahead of the south gate, inside the
  town's 19 m safe ring, so all three are inspectable immediately and idle
  until the ranger leaves the ring. Threshold positions are offsets from
  `town_entry`, so they cannot drift out of view if the gate moves.

## Verification gates

`tests/forest_mobs_regression.gd` loads each GLB and checks:

- exactly six clips, names, durations (±0.08 s) and stationary root at clip
  start/mid/end; the runtime controller forces loop modes on idle/walk/run and
  one-shot on attack/hit/death;
- 24–96 bones with `root`/`pelvis`/`head`/`jaw`, head rest on the −Z forward
  side and above the pelvis;
- rest sole near y = 0, height and footprint ranges, and that the adjacent JSON
  agrees with the imported mesh height;
- the deformed locomotion mesh stays on the floor across idle/walk/run, and
  each loop holds its height between first and last sample;
- authored surfaces only, with an albedo, normal and roughness map, and at
  least one emissive surface per mob;
- metadata: mob id, triangle budget, embedded image count, clip names, and
  constant root translation;
- visual controller selection through idle → walk → run → attack → hit →
  death, head hitbox and profile, and a skinned blood anchor;
- gameplay: own kind, display name, natural weapons, `forest_mobs` group
  membership (and not `devil_mobs`), gold on death, held corpse pose;
- AI closing from six metres into an attack state;
- the frontier: 19 `forest_spawns`, the unchanged 36 legacy `enemy_spawns` and
  16 `devil_spawns`, 19 live forest mobs across kinds 9–11, and the threshold
  trio idle, on screen and in the spawn camera frustum.

Visual review is still required. The build has no image-capable critic: render
the captures in `.runtime/forest-source/<mob>/captures/` and inspect them at
combat distance before shipping.

## Makeshift gear

The salvage set the ranger starts in, and the blades the smith sells beside the
forged kit. It is the forest's own material language applied to worn gear.

- **Armour** — five slots, set index 4 in `scripts/armor_data.gd`, and it is
  **bone over cured hide**, matching the stalker's own kit: a bone helm with
  lapped crown plates, brow band, cheek guards and a split-antler crown; a hide
  vest with bone rib bars, sternum, spine ridge, one bone spaulder and one bare
  strapped shoulder; hide bracers with a bone knuckle plate and spikes; hide
  leggings with domed bone knee cops, a bone shin plate and a hanging loin
  panel; hide boots with bone toe caps and heel spurs. Built by
  `tools/prepare_makeshift_armor.py` (one-command rebuild:
  `python tools/build_makeshift_armor.py`) into
  `assets/characters/armor/ironwood_makeshift.glb` — 17,732 triangles, 65 bones,
  3 materials (leather, bone, antler), 9 embedded images, inside a
  22,000-triangle budget, measured in the adjacent JSON. The pieces are skinned to a copy of the ranger's 65-bone skeleton and
  named `Armor_Makeshift_<Slot>`; `Archer._attach_makeshift_armor()` repoints
  each skin at the live ranger skeleton and registers it per slot, so the set
  comes and goes with `_apply_armor_visibility()` exactly like the four forged
  sets. Do not hide the imported skeleton node: the pieces hang off it.
- **Guard** — the salvage skin is a tier-0 starter set: it changes what the
  ranger looks like, not what a blow costs. Ranger leather and Makeshift both
  guard 0%; mail and plate are the sets that matter.
- **Blades** — `sword_makeshift` (split branch haft, knapped flint edge, sinew
  lashing) and `dagger_makeshift` (ground rib, hide wrap, chipped stone tied at
  the guard). They are class-equivalent to the iron pieces: the HUD stats are
  derived from `Archer.SWORD_DATA[0]` / `DAGGER_DATA`, and `tests/paperdoll_regression.gd`
  asserts that pairing.
- **Model family** — `scripts/sword.gd` and `scripts/dagger.gd` carry a `skin`
  property (`""` for forged steel, `"makeshift"` for salvage).
  `Archer.apply_loadout()` derives it from the equipped item id and
  `Archer.set_blade_skins()` swaps the model without touching the combat
  profile.
- **Verification** — `tests/makeshift_gear_regression.gd` proves the catalog,
  set index and packing round-trip, the starter kit and vendor stock, the
  imported pieces' skins, their visibility in the scene tree (not just their own
  flag), the salvage blade model swaps and the class-profile reuse.
- **Packing** — five sets need three bits per slot. `ArmorData.PIECE_MASK`
  (15 bits) and `ArmorData.SHIELD_BIT` (bit 15) are one contract shared by the
  HUD, the arena, the delve and the host-authoritative snapshots; never
  hardcode either mask.
