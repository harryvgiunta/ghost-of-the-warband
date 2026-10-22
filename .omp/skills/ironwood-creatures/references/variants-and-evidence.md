# Requested variants and delivery evidence

Read the variant sections **only when size or coat variants are requested**; read delivery/evidence for every creature overhaul. First ship one default grey wolf. A reusable rig and a fur-safe material layout are enough preparation; do not automatically create nine variants or add new gameplay systems.

## 1. Orthogonal variant data, shared production assets

**Input:** accepted default wolf, explicit requested sizes/coats, measured mesh/rig/stride metadata, existing enemy gameplay contract.

1. Keep `size_id` and `coat_id` independent. Proposed size IDs are `small`, `medium`, `big`; proposed coat IDs are `black`, `grey`, `white`. They are not existing APIs. Avoid names such as `large_black_wolf.glb` that encode the Cartesian product into duplicated exports.
2. Share one compatible mesh, Skeleton3D rest hierarchy and animation library when proportions permit. Size data describes a uniform visual scale plus measured collider radius/height/centre, aim point, paw sole/contact offsets and terrain-reach limits. Coat data describes fur palette/mask/texture parameters, not skeleton or speed. Keep clip timings/landmarks in shared animation metadata.
3. A thin instantiable Godot visual scene and per-instance configuration are acceptable if implemented during the authorized variant task. Reuse existing project data/scene patterns; do not invent a generic asset registry, importer framework or network variant protocol unless needed by actual callers.
4. Share immutable textures, meshes and animations across instances. Each visual instance needs its own pose/controller state. If a coat changes material parameters, use an instance shader parameter where the chosen shader supports it, or duplicate the actual material resource for that instance and set a surface override. Never mutate the shared imported material and recolour every wolf in the scene.
5. If changed anatomy actually requires a different mesh, document why, preserve compatible skeleton/rest transforms and UV/mask semantics where possible, and reuse animation resources rather than exporting the same clips per coat. Uniform scaling is a size variation; a puppy's changed proportions are a separate modeling/retargeting request, not just “small”.

**Gate/output:** one authoritative size table and one coat table, default IDs explicit, no duplicated GLB per colour/size, no global mutable coat resource.

## 2. Calibrate size without scaling the physics root

1. Keep the `CharacterBody3D` transform scale `Vector3.ONE`. Apply requested model scale on a dedicated visual child only; keep rotation-only children unit-scale. Configure the root's `CollisionShape3D` with numerical dimensions and identity scale. Do not non-uniformly scale a capsule node or the physics root.
2. Start medium at the accepted baseline. Example prototype scales 0.8/1.0/1.2 are **suggestions**, not shipped balances. If the user hasn't specified sizes, pick documented visual targets based on actual geometry and demonstrate them; do not silently alter health, damage, speed, aggro, reward, attack reach or timing with size.
3. Measure the scaled **skinned** mesh in rest and motion. Choose capsule radius/height/centre around the torso; preserve floor origin and ensure `height >= 2*radius`. A bounding box over tail, ears and bite extension is not a suitable capsule formula. Assign a unique Shape3D resource when dimensions differ per instance; changing a shared capsule resource must not resize other wolves.
4. Calibrate aim height/offset to a reachable torso target and scaled visual anatomy, rather than multiplying an arbitrary head position. Store the deliberate change in variant metadata; update `get_aim_position()` and all aiming/UI/projectile consumers consistently when variants authorize geometry changes. Baseline overhaul keeps the current y=0.68 contract.
5. Convert paw sole offsets and IK targets through the full visual-to-skeleton/world transform exactly once. Record whether each stored offset is unscaled asset-space or scaled runtime-space. Scale contact ray reach and correction limits intentionally; do not multiply a point by the size table and then again by the child transform. Floor contact must remain y=0 for each variant.
6. Record stride distance in asset metres. For uniform scale `s`, runtime stride is `S_runtime = s * S_asset`; use `phase += actual_horizontal_speed * delta / S_runtime`. Clip sampling time remains `phase * clip_duration`. Scaling the model without this cadence change makes small wolves slide and big wolves treadmill.
7. Size alone does **not** alter combat timing: windup impact stays 0.65 s and recovery stays 0.85 s unless the user requests a balance change. Retiming locomotion by travel speed must never accelerate bite/death clips. Avoid scaling all `AnimationPlayer.speed_scale` indiscriminately across actions.
8. Evaluate turns, slopes, capsule separation, aim hits, attack silhouette and death contact at every requested size. If visual size makes unchanged proximity-based attack look implausible, report the specific discrepancy and seek/implement only an explicitly authorized geometry/balance change; do not quietly extend the attack range.

**Gate/output:** measured dimensions/aim/contact placement per size, root/collider scale identity, plausible cadence at the real 3.1 m/s chase and 2 m/s return speeds, no resizing of other live instances.

## 3. Black, grey and white coat construction

1. Use the accepted grey base pattern and dedicated fur mask/surfaces. Preserve eyes/iris, nose, teeth, claws, paw pads and mouth. A global albedo multiplication across the full model is not a coat system.
2. Preserve value structure and fur direction in every palette: black remains dark charcoal with readable shoulder/chest highlights; grey retains dark saddle/light underside; white stays off-white with cool/warm variation, subtle darker roots/ears and a readable muzzle. Do not clamp the texture to black/white, bleach the iris or flatten normal/roughness detail.
3. For a mask workflow, document each channel's meaning, colour space and range; e.g. fur eligibility and saddle/undercoat regions are distinct concepts. Choose palette regions at authoring time rather than guessing masks from brightness (teeth are also bright). Use linear masks and intentional sRGB base colour handling.
4. If a material must be unique, duplicate only the mutable material; retain shared immutable image resources. Use `MeshInstance3D.set_surface_override_material()` on the intended fur surface after confirming surface index/name. Multi-surface meshes can include eyes/teeth: don't override every surface. A shader's per-instance uniform works only if it is actually declared as such; ordinary shared shader parameters still affect all instances.
5. Spawn at least two different coats simultaneously, change one, then inspect both and a newly spawned default. Check despawn/respawn/reuse doesn't inherit a previous wolf's palette. Check colour under neutral lighting and the real outdoor/shadow lighting, not only a bright Blender studio setup.

**Gate/output:** independent, persistent instance appearance, recognizable anatomical features at combat distance, no material/resource bleed or duplicate animation exports.

## 4. Evaluate the requested Cartesian product

Build the matrix from the **requested** size IDs × requested coat IDs. For three sizes and three coats that means nine combinations, not nine authored GLBs. If only a default wolf was requested, the matrix has one row.

Record for each row: silhouette/scale, capsule and aim alignment, front/side/three-quarter texture render, idle, walk/trot contacts, impact at 0.65 s, recovery end, death, flat/slope/edge contact, coexistence with other variants. Automate a deterministic lineup/capture scene if worthwhile, but also use the real gameplay scene. Log actual asset/config identifiers and failures; a table populated from configuration strings without rendering is not evidence.

## Delivery and evidence

The following are acceptance gates for an **implementation** task, not instructions to run tools during a documentation-only assignment. Use the current engine/toolchain and project test guidance in [Ironwood Archer](../../ironwood-archer/SKILL.md). Do not claim a new wolf regression or capture script already exists. If deterministic coverage is needed, implement it against real scenes/rigs first; avoid source-text assertions, mocked clip names or a simplified substitute creature.

### A. Artifact and reproducibility gate

- Track the final runtime GLB, adjacent measured metadata, relevant import settings and exact per-asset license/attribution. Track reusable authoring/baking code and an accessible editable source or reproducible source acquisition description consistent with source rights. A GLB alone is insufficient for an authored animation pipeline.
- Record source and output hashes, Blender version/export settings and Godot version/import configuration. Do not fabricate a download, license, tool invocation, output path or successful check.
- From documented inputs, the authoring process must reproduce the intended clip/mesh/material content. Record determinism expectations: exact bytes only if exporter behavior supports it; otherwise compare measured content (counts, names, durations, hashes of source inputs) rather than promise binary identity without evidence.
- A clean Godot import must succeed without relying on an old `.godot` cache. Check errors as well as exit codes. Confirm the actual skinned mesh, texture images, all required clips, loop flags, non-accumulating root, per-instance materials, scale and metadata agree.

### B. Rendered animation contact sheets

Capture **rendered textured mesh**, not editor bones, from front, side and three-quarter at a stable camera/exposure. Use the actual imported scene in Godot in addition to Blender authoring previews. Suggested sheet layout:

| Sheet | Required samples |
| --- | --- |
| Idle | Start, inhale apex, exhale apex, loop boundary; four paws planted |
| Walk/trot | At least eight evenly spaced phases per clip plus a loop-boundary pair; annotate LF/RF/LH/RH stance/swing and measured root travel |
| Attack | 0.00, 0.30, 0.55, **0.65**, 0.85, 1.25 and **1.50** s; annotate gameplay state and impact |
| Death | 0.00, mid-collapse, 0.45 s final collapse, held corpse and visual disappearance |
| Terrain | Actual flat ground, supported slope, uneven/edge contact and turn; show paw close-ups and whole-body posture |
| Variants when requested | Every requested size × coat, same camera/lighting/reference scale; coexistence shot |

Capture a real window/rendering viewport, await `RenderingServer.frame_post_draw` before `get_viewport().get_texture().get_image().save_png(...)`, and save captures under ignored local storage. Do not use a headless dummy render as visual evidence. A temporary harness may instantiate `main.tscn` and inject actual inputs; it must not bypass the enemy's real AI/damage path for combat evidence. Remove throwaway harnesses when finished. Report exact capture paths so another agent/user can inspect them.

Suggested initial quality tolerances at default scale (record deviations and why): less than about 2 cm horizontal sole drift during stable flat-ground stance; no sustained sole penetration over about 1 cm; no visible 180-degree joint flips, joint stretching, root double travel, or loop pop. These are recommended review thresholds, not existing automated tests. Quantify stance drift against root travel in world space, not only paw motion inside an in-place clip. At slopes/edges document supported/released contacts rather than applying a flat-ground threshold blindly.

### C. Real in-world gameplay gate

Run the actual changed scene, not just a model viewer. Exercise:

1. Idle, chase at ordinary and changing distances, return-home motion (IDLE can move), stopping against a wall and steering around obstacles. Cadence follows achieved travel; no running in place against collision.
2. Approaching from multiple angles and turning during movement. Check facing, shoulders/hips, paw roll, support transitions, leg reach and mesh intersections from close and normal gameplay cameras.
3. Attack entry/telegraph/0.65 s hit/recovery; player remains in range, escapes before impact, enters safe area, and has excessive vertical separation. Existing damage decisions and one-hit/recovery behavior stay unchanged. Frame-step/record hit time alongside the rendered bite; don't infer synchronization from clip names.
4. Lethal damage in idle, locomotion, windup and recovery. Verify immediate authority cancellation, exactly one reward, collision shutdown, complete visible death animation despite the dead early return, held corpse and original removal timing. Do not replay queued attacks after death.
5. Flat ground, ordinary slopes, uneven ground and edges. Verify body height, four-paw contact, no sinking/drift after repeated state transitions and no stretching. Test repeated transition cycles long enough to expose cumulative authored/solved-pose contamination.
6. Sentinel spawn, chase, windup/damage, recovery and death. Its primitives, limb/arm motion, health/damage/reward/collider and timing remain unchanged. A wolf improvement that deletes shared sentinel behavior fails acceptance.
7. Bow/projectile and melee interaction with the wolf through the existing paths, aim label placement, collision with other enemies/world and safe-zone behavior. If a future change touches shared arena/replication code, exercise the affected modes and host/client authority; do not claim wolves already participate in arena networking without checking callers.

Supplement rendered play with deterministic assertions for real state boundaries, animation names/durations, root/bone invariants, repeat transitions, death ticking and material isolation when implementing those features. Existing humanoid regressions do not automatically validate a quadruped. Run the relevant project regressions after integration when the implementation assignment authorizes verification, and report only those actually exercised.

### D. Handoff template

```text
Scope: default grey wolf only / exact requested sizes × coats
Changed files: runtime assets, integration, authoring code, metadata/import/provenance/docs
Sources: exact model/motion/texture URL or original-authored description; license; hashes
Tools: observed Blender/Godot versions; commands actually run; exit/error observations
Asset: mesh/material/bone counts; units/axes; root scale; bounds; skeleton/animation paths
Clips: actual names, durations/loops, stride and contact table; impact/recovery landmarks
Integration: physics/AI owner, sampling clock, authored-before-correction ordering,
             preserved sentinel and damage/death contracts; removed obsolete wolf paths
Variants (if requested): size/coat data, measured geometry/aim/contact, material isolation,
                         complete combination matrix with observed results
Evidence: rendered contact sheet/video paths; real gameplay scenarios and observations
Checks: exact exercised checks and results; explicitly unexercised gates
Remaining blocker: exact missing prerequisite and what was tried, or none
Reproduce: source retrieval/authoring/import/play steps using implemented tools only
```

Do not substitute “export succeeded” for finished anatomy, real animation or gameplay/render proof. Do not say tests passed if only the instructions were written. A handoff must distinguish recommended contracts from observed shipped facts.
