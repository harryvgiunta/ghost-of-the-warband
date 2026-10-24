# Devil mob authoring workflow

Five frontier mobs — Hellish goat man, Succubus, Devil spawn, Hell beast and
Gargoyle — are shipped as reproducible, source-based Blender assets. This is the
same quality route as the ranger: licensed CC0 Quaternius human bases, outfits,
hair and skeleton clips, with original devil anatomy, materials, rig additions
and attack/death authoring on top.

The earlier procedural metaball pass was retired. It produced complete assets,
but its smooth blob anatomy and packed single-atlas surfaces did not reach the
ranger's authored PBR detail. The current pipeline keeps the deterministic,
offline build and replaces the surfaces with the ranger's CC0 source maps.

## Sources and licensing

Everything below is CC0 1.0 Universal; provenance is recorded in
`assets/characters/LICENSE.txt` and the source archives stay in the ignored
`.runtime/character-source/` workspace.

| Source | Used for |
| --- | --- |
| Quaternius — Universal Base Characters: `Superhero_Female_FullBody`, `Superhero_Male_FullBody` | Body, face, eyes, 65-bone skeleton |
| Quaternius — Modular Character Outfits Fantasy: `Female_Ranger`, `Male_Ranger` | Corset/boots, full ranger leather outfit, hood, belts, source hand skin |
| Quaternius — Universal Base Characters hairstyles: `Hair_Long` | Succubus hair |
| Quaternius — Universal Animation Library 1/2 | Idle, walk, jog/sprint, crouch loops and sword swings re-used for locomotion and attacks |
| Ironwood `ironwood_wolf.glb` | Hell beast body, wolf skeleton and authored idle/trot/attack/death |
| Original authoring in this repository | Horns, skull, wings, tails, claws, fangs, hooves, fur mantle, stone treatment, tinted PBR maps, extra bones, attack/hit/death timing |

The supplied design-reference images informed palette and proportions only.
They are not redistributed and are not build inputs. No generated image,
photogrammetry scan, paid pack or restricted file is used.

## Repository surfaces

| Surface | Purpose |
| --- | --- |
| `tools/build_devils.py` | One-command texture + Blender rebuild for one or all mobs |
| `tools/devil_styles.py` | Source-map paths, palettes and per-mob recipes |
| `tools/devil_source_textures.py` | System-Python PBR pass (Pillow + numpy): source-map tinting and authored horn/bone/membrane/cloth/stone/fur/eye maps |
| `tools/prepare_devil_sources.py` | Blender assembly, extra anatomy, rig additions, clip authoring, GLB/JSON export |
| `tools/devil_source_pipeline.py` | Shared Blender import, material, mesh, skinning, bake, export and measurement helpers |
| `assets/characters/devils/ironwood_<mob>.glb` | Runtime skinned, animated, textured mesh |
| `assets/characters/devils/ironwood_<mob>.json` | Measured bones, bounds, clips, materials, head zone |
| `assets/characters/devils/ironwood_<mob>.glb.import` | Godot import settings (embedded images, 60 Hz sampling) |
| `scripts/devil_mob_visual.gd` | Presentation-only clip sampler, attack impact mapping, material tuning |
| `scripts/devil_mob.gd` | Gameplay AI, collision, damage, parries, gold, corpse hold |
| `scripts/range_world.gd` | 16 `devil_spawns`, including the five-mob starting court |
| `tests/devil_mobs_regression.gd` | Asset, visual, gameplay, head-zone and frontier coverage |

Ignored intermediates live in `.runtime/devil-source/<mob>/` (`textures/`,
`captures/`). Do not commit them.

## Build

```powershell
python tools/build_devils.py all
# or one mob
python tools/build_devils.py succubus
```

The wrapper runs the system-Python texture pass, then Blender 5.1 in
background mode. Override the executable with `IRONWOOD_BLENDER` if needed.
After a rebuild, reimport in Godot and run the regression:

```powershell
$Godot = '.\\.runtime\\godot\\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/devil_mobs_regression.gd
```

## Shipped budgets

Heights and footprints are measured from the imported GLB. The head zone is a
marker bone (`head`) at the face; `jaw` exists on every mob. Extra wing/tail
bones are numbered `wing_01_l`… and `tail_01`…

| Mob | Height | Footprint | Triangles | Bones | Materials | Images |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Hellish goat man | 2.02 m | 2.07 m | 49,292 | 68 | 9 | 21 |
| Succubus | 1.91 m | 2.72 m | 36,286 | 76 | 8 | 20 |
| Devil spawn | 1.09 m | 0.99 m | 16,054 | 70 | 6 | 15 |
| Hell beast | 1.78 m | 2.99 m | 16,436 | 37 | 9 | 7 |
| Gargoyle | 2.08 m | 3.05 m | 17,896 | 76 | 5 | 14 |

All meshes are a single joined skinned MeshInstance with multiple PBR material
surfaces. Feet sit at approximately y = 0; rest minima are within 4 cm of the
ground.

## Clip contract

All clips are baked/sampled at 60 Hz, in-place, with a stationary root. Idle,
walk and run loop; attack, hit and death do not. Attack durations and impact
times are authored to the gameplay clock so `DevilMobVisual._seek_attack()`
places the authored strike on the damage frame.

| Mob | Idle | Walk | Run | Attack (impact) | Hit | Death |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Hellish goat man | 2.500 | 1.333 | 0.667 | 1.45 (0.62) | 0.50 | 1.25 |
| Succubus | 2.500 | 1.333 | 0.667 | 1.35 (0.58) | 0.45 | 1.20 |
| Devil spawn | 2.933 | 2.000 | 0.667 | 1.10 (0.48) | 0.40 | 1.00 |
| Hell beast | 2.400 | 0.600 | 0.600 | 1.60 (0.82) | 0.50 | 0.45 |
| Gargoyle | 2.500 | 1.333 | 0.933 | 1.80 (0.95) | 0.50 | 1.40 |

Locomotion comes from the Quaternius loops (spawn uses the crouch loops; beast
uses the wolf trot for both walk and run, with speed-scaled playback). Attacks:
one-handed overhead for the succubus, two-handed overhead for the goat man and
gargoyle, dagger thrust for the spawn, authored wolf bite for the beast. Hit
and death are baked from the idle pose with authored spine/jaw/wing/tail
overlays; the death clips add a grounded pelvis drop.

## Material design

Source skin, leather, hair and eye maps are retained at their authored detail
and recoloured in display space, so pores, leather grain, weave and iris
structure survive. The authored extras use deterministic PBR sets:

- **Skin** — source albedo/normal/roughness, tinted; mottling, subtle veins and
  scars; 2048².
- **Leather** — 4096² ranger base/normal/ORM resampled to 2048², tinted oxblood
  (succubus/spawn) or weathered brown (goat man).
- **Hair** — 2048² source cards resampled to 1024² and tinted near-black.
- **Eyes** — 256² iris recoloured amber/red with an emissive iris mask.
- **Horn** — 1024² keratin with growth rings, longitudinal striations, stained
  base and pale tip; normal + roughness.
- **Bone** — 1024² pale bone with pores, stains and crack networks; normal +
  roughness.
- **Membrane** — 1024² wing membrane with branching vessels, wrinkles and a
  raised normal map.
- **Cloth** — 1024² weave with slub and fuzz.
- **Stone** — 2048² basalt with cracks, pits, moss/lichen and an ember-fissure
  emission map.
- **Fur** — 1024² root-to-tip strand gradient with clump normal/roughness.

Runtime tuning (`devil_mob_visual.gd`) enables subsurface scattering only on
skin/membrane/fur material names and anisotropic filtering on every surface.
Emission energy is raised for eyes/stone/fur. The glTF carries the maps; the
runtime carries only values glTF cannot express.

## Animation and rig notes

- The 65-bone Quaternius skeleton is retained for every humanoid. Extra bones:
  `head`, `jaw`, and for winged mobs `wing_01_l/r`…`wing_03_l/r`; tails use
  `tail_01`…`tail_03`.
- The male base/outfit shares the ranger skeleton, so idle/walk/sprint clips
  apply directly. The female base is 17 mm lower at the pelvis; the build adds
  that offset to the pelvis location keys for the succubus/spawn.
- The finished character is rotated 180° around Blender Z and scaled once, so
  the exported asset faces glTF −Z. Source action locations are scaled by the
  same factor. The mesh is unparented during transform application and
  reparented afterwards; this avoids baking the parent scale twice.
- Attack bakes time-warp the source clip so the authored strike lands on the
  measured `impact`; the visual then maps the physics WINDUP/STRIKE/RECOVER
  clock onto that same pose. No clip event deals damage.
- Hit/death are full-skeleton bakes from the idle pose; the death action gets a
  grounded pelvis drop. Root translation stays zero, which the regression
  checks at the start, midpoint and end of every clip.

## Verification gates

`tests/devil_mobs_regression.gd` loads each GLB and checks:

- exactly six clips, names, durations (±0.08 s) and loop modes;
- 24–96 bones, `root`/`pelvis`/`head`/`jaw`, head rest on the −Z forward side
  and above the pelvis;
- stationary root at clip start/mid/end;
- rest sole near y = 0, height and footprint ranges;
- at least one albedo/normal/roughness/metallic/emission map across the
  multi-material mesh;
- idle → walk → run selection, attack/hit/death clip selection, head-zone
  center/profile and death reward;
- the 16-entry `devil_spawns` table, the unchanged 36-entry legacy
  `enemy_spawns`, all five kinds live in the frontier, and the starting court
  (one of each species, inside the safe ring, on screen and idle).

Visual review is still required. The build has no image-capable critic; it
verifies source provenance, map presence/resolution, silhouette bounds, bone
placement, clip timing and contact. Render the preview and the in-game captures
in `.runtime/devil-source/<mob>/captures/` and `.runtime/devil-captures/` and
inspect them at combat distance before shipping.
