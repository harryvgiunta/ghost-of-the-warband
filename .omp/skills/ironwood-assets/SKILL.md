---
name: ironwood-assets
description: Use when discovering, reusing, sourcing, licensing, modeling, UV-unwrapping, painting, baking, exporting, importing, or integrating Ironwood 3D assets and PBR textures, including replacing runtime primitive visuals and preparing reusable creature materials or coat variants. Pair with ironwood-creatures for character anatomy, skeletons, skinning, and authored animation.
---

# Ironwood Assets

Work from the repository root containing `project.godot`. Commands and code paths are repository-relative unless a Markdown link says otherwise. This skill teaches future asset work. The default Briar wolf GLB, its deterministic authoring script and its runtime controller now exist; other proposed assets or preview scenes still require implementation.

Read [the project skill](../ironwood-archer/SKILL.md) for gameplay and toolchain contracts. Read [the creature skill](../ironwood-creatures/SKILL.md) before making or changing any animated character, including the shipped textured wolf. This skill owns source intake, mesh/material production, packaging, and import/render gates; the creature skill owns anatomy, rigging, clips, and their gameplay timing.

## Read only the relevant references

- [Authoring and PBR](references/authoring.md): before acquiring or creating a model, changing topology/UVs, painting fur, baking maps, or choosing deterministic Blender source storage. Contains the existing Ranger command and the explicit prerequisite for any new authoring script.
- [Godot integration and delivery](references/integration.md): before GLB export/import, changing materials per instance, replacing a runtime object, or verifying/handing off an asset. Contains cold-import and actual-render gates.
- For a reused asset with no geometry changes, read intake in the first reference and all applicable integration gates; do not rebuild a mesh just because Blender is available.

## Repo facts, not proposed features

| Existing surface | Contract |
| --- | --- |
| `assets/characters/ironwood_ranger.glb`, adjacent JSON, `.glb.import`, `LICENSE.txt` | A textured, skinned Ranger with authored humanoid clips; license facts apply only to the recorded sources. |
| `assets/characters/ironwood_wolf.glb`, adjacent JSON, `.glb.import`, wolf section in `LICENSE.txt` | Original textured, skinned default grey wolf: 37 bones, 15,036 triangles, 1024 embedded coat, idle/trot/bite/death clips. |
| `tools/prepare_character.py`, `tools/character_clearance.py` | Ranger-specific source assembly, humanoid retargeting and clearance. **Not** a generic model/wolf builder or quadruped retargeter. |
| `tools/prepare_wolf.py`, `scripts/wolf_visual.gd`, `tests/wolf_regression.gd` | Deterministic wolf mesh/rig/coat/clip authoring, presentation-only runtime sampling, and the real import/pose regression. |
| `scripts/geo.gd` | Primitive mesh helpers; meters, Y-up; materials supplied to `mesh_node()` become `material_override`. |
| `scripts/enemy.gd` | `kind == 0` BriarWolf attaches the imported wolf through `_build_wolf_visual()`; `kind == 1` RuinSentinel keeps its primitive presentation and shares the behavior script. |
| `.runtime/character-source` | Ignored source-download workspace for the existing character. Ignored `.runtime` is not permanent storage for new irreplaceable authored work. |
| Managed Godot / Blender | Existing Windows engine path and Blender 5.1 path appear in the references; honor `GODOT_PATH`. No Blender MCP or image/3D generation service is mounted. |

Re-read affected code before acting: these facts can change. Search unknown behavior with `find`; locate known names with `grep`/`glob`, then read bounded sections. Inventory existing scenes, materials, textures, source metadata, and actual callers before downloading or building anything.

## Bounded task procedure

1. **Identify the requested result.** Record asset ID, object/creature type, destination, intended camera distance, visual references, dimensions, and whether this is standalone delivery or a replacement. Use repository values and the user's scope; do not automatically implement future sizes/coats.
2. **Discover and choose reuse.** Check tracked assets and source manifests first. Choose unchanged reuse, a documented derivative, licensed source intake, or original authoring. Preserve compatible mesh/rig/animations when only a material is changing. Stop intake if redistribution rights cannot be established; choose a lawful available alternative rather than inventing a license.
3. **Freeze integration boundaries.** For standalone work, define its model origin, measured axes, textures, and minimal preview. For replacement, also identify the runtime constructor/callers, collision, sockets, state transitions and cleanup being preserved. A file in `assets/` alone does not replace the live object.
4. **Author reproducibly.** Follow the authoring reference. Save a deterministic script plus its required inputs, or the actual edited `.blend` and texture/mask sources. A background Blender invocation cannot substitute for a missing script. For creatures, complete the peer skill's anatomy/skin/animation steps before export.
5. **Export and integrate.** Follow the integration reference. Commit required runtime resources and truthful provenance; preserve measured metadata and import configuration. Never edit generated `.godot/imported` resources.
6. **Verify when assigned.** After integration, the responsible main agent runs cold import, relevant checks, and actual rendered inspection. Workers told to skip validation must report those gates as unrun, not claim success from exported files alone.
7. **Deliver evidence.** List changed files, source/license, reproducible command and prerequisites, measured bounds/axes/materials/clips, exercised checks/capture locations, and explicit blockers. Update existing user-facing docs when the permanent asset/workflow changes; do not leave temporary preview scripts in the shipping tree.

## Small-agent handoff

Fill this with concrete values before a bounded implementation task; unresolved measurements are work to perform, not guessed facts:

- **Scope / non-goals:** one named asset or material; standalone versus replacement; requested variants only.
- **Inputs:** source filenames and hashes, source/license URLs, license text, references, current code/scene entry point, dimensions and gameplay constraints.
- **Ownership / outputs:** exact model, source, texture, metadata, import, and integration files; list any new script/scene that must first be implemented.
- **Production steps:** intake → blockout → finished topology/UV → PBR/masks → rig/animation if needed → export → integration. Stop at a failed quality gate and repair its cause, not by replacing the desired asset with runtime primitives.
- **Acceptance:** recognizable silhouette at gameplay distance; textured surface without baked lighting; correct scale/origin/axes; complete dependencies; isolated variant materials; live replacement with old visual code removed only where obsolete; rendered proof and clean import.
- **Evidence:** exact commands actually run and results, views/timestamps actually inspected, performance measurements if requested, and any verification intentionally deferred to the integrator.

Recommended texture/triangle budgets in the references are starting targets, not measurements or hard repo rules. Never report a generic test as wolf validation, a render as license proof, or documentation-only work as a completed asset overhaul. For the shipped wolf, `tests/wolf_regression.gd` is the relevant import/pose check; the humanoid regressions do not validate quadruped anatomy.
