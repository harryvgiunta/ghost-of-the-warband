# Devil mob authoring workflow

Five frontier mobs — Hellish goat man, Succubus, Devil spawn, Hell beast and
Gargoyle — are shipped as original, reproducible Blender assets. This document
records the workflow used to produce them and the gates a sixth mob must pass.

## What this pipeline is, and is not

There is no text-to-3D or image-generation service in this repository. The
mobs are not downloaded, photogrammetry-scanned or generated from the supplied
concept images. Those images were used only as design references; the shipped
geometry, textures and motion are authored deterministically from measurements
and procedural fields.

"Photorealistic" here means game-photoreal at a 2–30 m combat distance:

- continuous anatomical surfaces with correct joints and a readable silhouette;
- layered rigid details (horns, claws, teeth, hooves, wings, armour) rather
  than a single smooth blob;
- a packed PBR atlas with albedo, tangent-space normal, roughness, metallic and
  emission channels, not a flat global tint;
- multi-scale surface detail (pores, fur clumps, keratin rings, leather grain,
  membrane veins, granite speckle, lichen, ember cracks);
- authored whole-body motion with contact timing, anticipation and follow-through;
- runtime tuning that the glTF cannot carry (emission energy, anisotropic
  filtering; subsurface scattering is enabled only on Forward+, while this
  project ships the GL Compatibility renderer).

It does not attempt pore-level close-up realism. A capture from 10–30 m in the
frontier is the review surface.

## Repository surfaces

| Surface | Purpose |
| --- | --- |
| `tools/prepare_devils.py` | CLI entry point; builds one or all mobs |
| `tools/devil_pipeline.py` | Shared mesh, rig, weighting, atlas, clip, export and metadata code |
| `tools/devils/<mob>.py` | One `SPEC` + `build_parts()` per creature |
| `tools/check_devil.py` | Objective source-blend validator |
| `assets/characters/devils/ironwood_<mob>.glb` | Runtime skinned, animated, textured mesh |
| `assets/characters/devils/ironwood_<mob>.json` | Measured bones, bounds, clips, texture contract |
| `assets/characters/devils/ironwood_<mob>.glb.import` | Godot import settings (embedded PNG, 60 Hz) |
| `scripts/devil_mob_visual.gd` | Presentation-only clip sampler |
| `scripts/devil_mob.gd` | Gameplay AI, damage, death, loot reward |
| `scripts/range_world.gd` | `devil_spawns` terrain placements |
| `tests/devil_mobs_regression.gd` | Asset, visual, gameplay and world coverage |

Ignore `.runtime/devil-source/<mob>/`: it holds the editable `.blend`, atlas
PNGs and capture sheets. Do not commit it.

## Stage 1 — design and measure

Record the archetype, role, target height, silhouette landmarks, palette and
required actions before writing geometry. The five shipped specs use these
targets:

| Mob | Height / span | Role | Signature |
| --- | --- | --- | --- |
| Hellish goat man | 2.20 m | Charger | Ram horns, cloven hooves, shaggy forearms, headbutt |
| Succubus | 1.88 m | Flyer | Bat wings, spade tail, claw rake, crimson skin |
| Devil spawn | 1.15 m | Crawler | Long arms, exposed ribs, needle teeth, pounce |
| Hell beast | 1.65 m shoulder / 2.7 m long | Brute | Heavy quadruped, mane, tusks, rear-and-slam |
| Gargoyle | 2.35 m | Sentinel | Folded stone wings, ember cracks, double-fist slam |

Coordinates are metres, Blender Z-up, creature facing +Y. glTF export is Y-up,
so +Y Blender becomes -Z in Godot, the gameplay forward axis. The sole plane is
z = 0; the head bone is named exactly `head`.

## Stage 2 — anatomy and details

Build the deforming body as one metaball object. Metaballs give a continuous
skin across shoulders, hips and neck without the welded seams of joined
primitives. Then convert, smooth and decimate to the triangle budget.

Add details as separate meshes with their own surface tag:

- horns, claws, teeth, hooves, tusks and back spikes (keratin/bone);
- eyes as emissive spheres;
- leather harnesses, straps and belts;
- wing membranes (a curved grid, solidified for thickness);
- fur/hair clumps: tapered tubes grown from sampled surface points along the
  local normal, with a length-scaled bend.

Each part is either envelope-weighted to the body skin map or rigidly weighted
to one bone. The shared envelope pass keeps at most four influences per vertex
and smooths across mesh edges to remove shoulder/hip banding.

## Stage 3 — UV and PBR atlas

All parts are joined into one mesh, then smart-projected and packed into one
UV atlas. The pipeline clears any primitive UV layers first: joining objects
that already carry UVs otherwise leaves smart-project output in a different
layer than the one the painter reads.

The atlas is painted in rest space from the actual triangle positions on a
2048² (large mobs) or 1024² (small mobs) grid. Each texel records:

- **Albedo** (sRGB): base/second/accent palette mixed by multi-scale value
  noise, ridged veins, pores, strand fields, growth rings, grain, lichen and
  cavity darkening.
- **Height** (metric): drives the tangent-space normal map. The gradient is
  converted with each triangle's UV-to-metre scale, so detail strength stays
  consistent across automatically packed islands.
- **Roughness / metallic**: material-specific values plus noise; eyes are very
  smooth, metal is metallic, stone and fur are rough.
- **Emission** (sRGB): ember irises, molten gargoyle cracks, spawn skin seams.
- **Cavity**: baked from vertex concavity into albedo and roughness; no
  separate AO texture is shipped.

Fur/hair clumps are painted with directional strand fields, not a flat colour.
The single packed material carries all five maps, so each mob is one primitive
and one draw call per instance.

## Stage 4 — rig, weights and clips

Each creature declares an explicit semantic bone map and five-bone leg chains.
The shared solver places the ankle/foot at a target, keeps the cannon and sole
world-level, and supports a foot pitch and toe flex. It is a sagittal solve:
every bone in a leg chain must share one X coordinate. Arms, wings, tails and
ears are authored with armature-space pitch/yaw/roll.

Bake six clips at 60 Hz:

| Clip | Loop | Purpose |
| --- | --- | --- |
| idle | yes | breathing, weight shift, head scan, wing/tail drift |
| walk | yes | low-speed locomotion, planted contacts |
| run | yes | high-speed locomotion, longer stride and clearance |
| attack | no | anticipation, fast strike, follow-through, recovery |
| hit | no | flinch/stagger |
| death | no | collapse and held corpse |

Walk/run stride and duty are exported so runtime cadence can be derived from
actual movement. The attack JSON records the impact time; the visual controller
maps the physics attack clock onto that frame instead of letting the clip free-run.

## Stage 5 — export and import

`tools/prepare_devils.py` writes the GLB with NLA tracks (one per clip),
Y-up conversion, embedded PNG textures, tangents and skins. It triangulates
before export so tangents can be calculated. The adjacent JSON is generated by
parsing the GLB, not by hand.

Godot import settings must keep:

- `animation/fps=60`;
- `gltf/embedded_image_handling=2` (embed, do not extract duplicate PNGs);
- `nodes/use_name_suffixes=false` (stable `Skeleton3D` / `AnimationPlayer` names);
- `meshes/ensure_tangents=true`.

## Stage 6 — runtime integration

`DevilMobVisual` loads only the requested GLB at spawn, verifies all six clips,
sets loop modes, tunes the material (emission energy, anisotropic filtering,
optional SSS) and samples clips. It never moves the character root.

`DevilMob` owns a shared state machine: IDLE, RETURN, CIRCLE, WINDUP, STRIKE,
RECOVER, STAGGER, DEAD. Per-mob profiles change health, damage, reach, speed,
orbit radius, aggression/leash, cadence, lunge speed, turn rate and gold. The
existing `attacked`, `defeated`, `take_damage`, `stagger`, head-zone and loot
contracts are unchanged, so parries, blocks, headshots, damage numbers and the
frontier loot rotation work without special cases.

## Stage 7 — validation gates

Run, in order:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python-exit-code 1 --python tools/prepare_devils.py -- all
& $Blender --background --python-exit-code 1 --python tools/check_devil.py -- hell_goat
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/devil_mobs_regression.gd
```

`check_devil.py` reports triangle count, bones, bounds, unweighted vertices,
maximum influences and per-clip ground penetration. Gates:

- 20k–55k triangles; 24–48 bones; ≤4 influences; no unweighted vertices.
- rest sole within ±0.05 m of z = 0;
- idle/walk/run/hit minimum z ≥ −0.03 m;
- attack/death minimum z ≥ −0.06 m;
- six clips with the exact names and durations declared in JSON;
- embedded albedo, normal, roughness, metallic and emission maps;
- root bone stationary in every clip; the GLB may carry constant sampled root translation tracks, so the test checks the posed root origin rather than the channel count.

`devil_mobs_regression.gd` additionally checks the imported clip inventory,
loop modes, head zone, visual state mapping, gameplay death/reward, the
16-entry devil spawn table (five of them in the starting safe-ring court), the
unchanged 36-entry legacy spawn table, and 16 live mobs in the frontier with all
five kinds present.

Tests are not visual proof. Render the PBR hero and contact sheets into
`.runtime/devil-source/<mob>/captures/`, inspect opposing stride phases, the
attack impact, the death hold and the silhouette at the intended camera
distance, and report what was actually inspected.

## Adding a sixth mob

1. Copy `tools/devils/hell_goat.py` and change `SPEC`.
2. Keep the height, bone map, chains, skin map, palette, eye data and six clip
   records explicit; do not infer them from the goat.
3. Keep leg-chain X constant and target the fourth bone's rest head.
4. Author geometry with `part(obj, tag, rigid=...)`; list every tag in
   `paint_tags`.
5. Run the build, then `check_devil.py`; fix pose or weights, never the checker.
6. Add the mob to `DevilMobVisual.SCENES`/`DATA`, `DevilMob.PROFILES`,
   `RangeWorld.devil_spawns` and the regression table.
7. Re-run the asset, visual, gameplay and world checks.

## Provenance

The five GLBs, their atlases and their clips are original procedural work
authored by `tools/prepare_devils.py`. No third-party model, texture, motion
or generated image is included. The authored `.blend` files, atlas PNGs and
capture sheets remain in ignored `.runtime` storage; the tracked deliverables
are the GLBs, adjacent JSON, import settings, authoring code and tests.
