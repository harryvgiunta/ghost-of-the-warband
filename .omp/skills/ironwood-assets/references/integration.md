# Godot integration, verification, and delivery

Read after [the asset skill](../SKILL.md). Follow [the creature skill](../../ironwood-creatures/SKILL.md) for skeleton/clip integration. Commands are repository-relative; proposed asset wrappers, metadata and preview scripts below must actually be implemented before invoking them.

## 1. Export a deliberate runtime artifact

1. Save the authoritative source and isolate the intended export objects. Exclude source rigs, high-poly bakes, preview lights/cameras and unused meshes. Explicit selection with `use_selection=True` is suitable for a new exporter; the existing Ranger exporter instead removes non-runtime objects before export. Never delete the user's source objects merely to make export convenient.
2. Use GLB with embedded images for a self-contained runtime model. Blender's portable API is `bpy.ops.export_scene.gltf(...)`; confirm options against the installed operator before using them. Existing `tools/prepare_character.py` uses `export_format='GLB'`, `export_yup=True`, `export_materials='EXPORT'`, `export_image_format='AUTO'`, `export_skins=True`, and for animations `export_animations=True`, `export_animation_mode='NLA_TRACKS'`, `export_nla_strips=True`, `export_force_sampling=True`, `export_frame_range=False`. A static prop does not need skins or animation export. Explicitly include only the intended objects and resources.
3. Creature animation must already be authored and baked. The existing pipeline has named NLA tracks and a 60fps scene; do not blindly copy track muting/slot logic to an unrelated skeleton. Read the installed exporter behavior and peer skill, export each intended clip once, and measure final clip names/durations from the GLB. No shape-key/constraint/procedural motion is assumed to survive without verifying its baked/exported representation.
4. Check the final GLB data: glTF version, image embedding, material references, mesh counts, bounds after node transforms, skins/joint mappings and animation names/durations. A nonempty file is not sufficient. An asset-specific preparation script may parse GLB JSON as the existing Ranger tool does; no generic inspector is provided here. Record exported forward/up axes and ground offset rather than guessing them from Blender's viewport.
5. Package the runtime GLB alongside truthful provenance and measured integration metadata. For a new asset, an adjacent `<asset-id>.json` is a **proposed** contract; define its schema and consumer in that task. Suggested fields: source hashes/version, authoring tool version, meters, exported forward/up, rest bounds, contact/root offset, material/mesh names, UV/normal/ORM conventions, textures, and, for creatures, clip names/durations/contact events and rig identity. Do not duplicate numbers in code and JSON without deciding which is authoritative.

## 2. Import settings and resource ownership

Use the managed engine or `GODOT_PATH`, not a newly downloaded arbitrary engine. Existing Ranger settings in `assets/characters/ironwood_ranger.glb.import` are evidence for these choices:

- `nodes/root_scale=1.0`, `nodes/apply_root_scale=true`; fix authoring units rather than hiding repeated scaling layers.
- `nodes/use_name_suffixes=false` preserves animation names such as `Idle_Loop`. `nodes/use_node_type_suffixes` is a separate current option; inspect generated node types/colliders so a suffix does not create unintended physics nodes.
- `meshes/ensure_tangents=true`, `meshes/generate_lods=true`, `meshes/create_shadow_meshes=true`; inspect normal shading, LOD silhouettes and skin deformation rather than assuming generated LODs are always acceptable.
- `skins/use_named_skins=true`, `animation/import=true`, `animation/fps=60` for the current character. A static prop can omit animation.
- `materials/extract=0`, `gltf/embedded_image_handling=3` keep scene-embedded images/materials. Avoid extracting duplicate PNGs unless a real editing/runtime requirement justifies external textures.

For a new GLB let Godot create its own import identity, UID and cache paths; configure its actual Import dock/options and reimport. Never copy the Ranger's `.glb.import` wholesale: its UID, `[deps]` and `.godot` path identify another asset. Track deliberate per-source import settings; generated `.godot` cache stays ignored. Do not edit the cached `.scn` or rely on a machine's warm cache.

Use a `.tscn` wrapper around an instantiated imported `PackedScene` when the task needs reusable placement, sockets, collision, or script integration. A proposed wrapper is not a current repo feature. Keep modifications outside the generated imported hierarchy where possible so reimport does not erase them. If using Godot MCP scene tools, read each mounted route's actual schema first; no MCP route here can author a Blender mesh or paint a texture.

### Material isolation without copying the entire asset

Meshes, textures and materials loaded from a resource can be shared. `PackedScene.instantiate()` alone does not guarantee every material is private. Keep immutable meshes/textures shared. Duplicate only mutable materials once per independently configured visual (or share immutable preconfigured variants). Never duplicate/rebuild them every physics frame.

For a `MeshInstance3D` using surface materials, the relevant pattern is:

```gdscript
# Run once during setup, with a real imported MeshInstance3D named mesh_instance.
for surface in mesh_instance.mesh.get_surface_count():
    var source := mesh_instance.get_active_material(surface)
    if source == null:
        continue
    var local_material := source.duplicate() as Material
    mesh_instance.set_surface_override_material(surface, local_material)
```

This is an API illustration, not an existing helper. If `material_override` is set, it takes precedence over surface overrides: duplicate/modify that override instead, or deliberately migrate its semantics before using per-surface overrides. `scripts/geo.gd` currently uses `material_override`; imported glTF commonly uses surface materials. Do not flatten a textured multi-surface model into one `Geo.material()` color.

`duplicate()` isolates material parameters while preserving shared texture resources; duplicate texture/image resources too only if actually editing their pixels. For a `ShaderMaterial`, keep shared shader code but set per-instance material parameters on the isolated material. `resource_local_to_scene` is another scene-authoring option when configured before instantiation, not a retroactive fix for instances already sharing a mutated material. Never call `mesh.surface_set_material()` on a shared mesh to recolor one animal.

Requested coat variants should reuse compatible geometry, UVs, rig and clips. Bake alternative palette atlases or use explicit region-mask shader parameters; retain normal/roughness detail and anatomical masks. Do not create nine GLBs for three sizes times three colors. Verify two different instances side-by-side: changing one must not recolor the other. Never scale a `CharacterBody3D` root to implement size variants; the creature skill specifies visual sizing and explicit physics/contact adjustments when sizes are actually requested.

## 3. Standalone asset versus runtime replacement

### Standalone asset

Deliver the reusable GLB, required textures/materials, source/provenance/metadata, import settings and any requested wrapper. Preview in a minimal scene with a measured ground plane, reference scale, neutral lighting and camera. A temporary preview scene/script must be created before it can be run and removed after evidence capture unless requested as a permanent tool. Do not silently spawn a new asset throughout gameplay, and do not claim the existing wolf was replaced unless the actual `enemy.gd` visual branch was cut over and verified.

### Runtime primitive replacement

1. Find the construction site and every affected caller. Identify gameplay root, collision, navigation/targeting, equipment/socket consumers, animation hooks, death/cleanup and instancing. Keep collision/behavior separate from rendering. Replace the actual visual branch; adding a disconnected GLB to `assets/` is incomplete.
2. For the shipped wolf, read `scripts/enemy.gd`: `kind == 0` calls `_build_wolf_visual()` beneath `_body`, which attaches `scripts/wolf_visual.gd` and the imported GLB; `kind == 2` calls `_build_devil_visual()` for the imported Cinder devil. Preserve shared gameplay. The wolf root is `CharacterBody3D`, forward -Z, layer 2, mask `1 | 2 | 4`, capsule radius 0.40/height 0.95 and aim height 0.68; the cinder devil keeps capsule radius 0.34/height 2.15 and aim height 1.25. Do not infer collision from the detailed mesh or rescale the root. Changes to these gameplay values require explicit scope.
3. Route new skeleton/animation through the creature skill's state/clip integration. The retired primitive bob and limb-sine presentation is gone from the frontier kinds: `_body` is the visual container and each imported controller (`wolf_visual.gd`, `cinder_devil_visual.gd`) owns its own clips. Keep those controllers separate from the gameplay state timing and damage authority; do not move damage onto animation callbacks unless deliberately redesigning that contract.
4. Adapt every wolf visual consumer, including death. The shipped wolf branch calls `_wolf.die()` and holds the corpse for the existing lifetime; old tweens must not rotate the imported subtree or double-drive a pose. The obsolete wolf primitive construction is removed; do not reintroduce it as a fallback. Preserve signal behavior, warning display, reward and lifetime unless requested otherwise.
5. Render the replacement in the actual gameplay scene as well as the neutral preview. A good asset preview can still have wrong in-game scale, forward axis, lighting, grounding or camera readability.

## 4. Performance and colliders

- Use simple gameplay shapes for moving bodies; static environment may use simplified convex pieces or suitable static concave collision. Do not put a dense concave trimesh on a moving creature. Avoid invisible duplicate imported collisions; retain the controller's existing capsule when doing a visual-only replacement.
- Record actual vertices, triangles, surfaces/materials, texture sizes, skin influence counts and visible-instance count. Material surfaces affect draw calls; excessive tiny eye/teeth/fur surfaces cost more than their triangle count suggests. Keep body topology appropriate for deformation, not merely low-poly by count.
- Budget texture memory with mipmaps and compression, not PNG filesize. An uncompressed 1024-square RGBA8 image is about 4 MiB, approximately 5.33 MiB with a full mip chain; imported GPU formats can differ. Reuse textures across variants. Never infer frame time from triangle count alone.
- Use `MultiMeshInstance3D` for suitable repeated static props when justified by the existing world pattern; it is not a drop-in renderer for independently posed skeletons. Avoid new allocations/material copies/mesh rebuilding in per-frame animation. Profile representative scenes only when assigned performance verification, using measured results.

## 5. Verification gates for the integration owner

These are future implementation acceptance gates, not claims that this documentation task executed them. A worker instructed not to verify reports them as pending to the parent.

1. **Source/export:** confirm required source/licensing is durable and the documented real preparation/export command succeeds without hidden files. Inspect final GLB contents, bounds, axes, material channels and clip list. A Blender render alone cannot prove Godot import compatibility.
2. **Cold import:** use a disposable staging checkout/copy with all intended changed runtime files and import settings, no preexisting `.godot`, and no dependency on ignored source downloads. Do not delete the user's working cache or use destructive git cleanup. From that staging project root, resolve the engine outside the copy if its managed binary was not copied:

   ```powershell
   # Run at the staging project root; set this to the real existing managed path
   # if staging did not include .runtime. Honor GODOT_PATH when configured.
   $Godot = if ($env:GODOT_PATH) { $env:GODOT_PATH } else { '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe' }
   & $Godot --headless --editor --path . --import
   if ($LASTEXITCODE -ne 0) { throw 'Godot asset import failed' }
   ```

   Inspect parse/import errors as well as exit status. Confirm textures and all external dependencies are tracked, correctly cased, and available in staging. Blender must not be needed merely to play a shipped GLB.
3. **Actual render:** launch a real rendered Godot process with the correct project/scene, not headless rendering, using the CLI or the mounted `run_project` route after reading its schema. Capture front, side, rear and three-quarter views in neutral lighting, plus the actual gameplay camera. Include a close material/UV view and distant/mipmapped view. Rotate the key light: pigment stays fixed, highlights move, normals do not invert. Inspect silhouettes, UV seams, texture sharpness, black/pink/missing surfaces, ground contact, scale and orientation.
4. **Animation and instances:** for creatures use the peer skill's opposing stride/contact/action/death views and gameplay timing checks. For material variants show simultaneously instantiated different coats, then change only one. For a replacement verify the other enemy type is unchanged. Do not call still images evidence of continuous motion; inspect an actual rendered sequence or playback as required.
5. **Capture mechanism:** a purpose-built temporary Godot script may await `RenderingServer.frame_post_draw`, obtain `viewport.get_texture().get_image()` and call `save_png(...)`. It must first exist and use a rendered viewport; do not invent a preview command or capture result. Save captures/logs under ignored `.runtime` storage, report their locations, and remove temporary scripts/scenes when done. A game launch with no inspection is not visual acceptance.
6. **Regression:** run the checks relevant to the actual changed consumers and any new deterministic asset/animation regression added by the implementation. Existing humanoid tests are not automatic quadruped coverage. The [project skill](../../ironwood-archer/SKILL.md) lists current commands; integration owner runs broader checks once when shared gameplay changes warrant them. Report only checks actually exercised.

## Troubleshooting by cause

| Symptom | Inspect / repair |
| --- | --- |
| Missing model or stale old wolf | Runtime constructor/callers, PackedScene path, restarted process, import errors; do not hide the error with a primitive fallback. |
| Tiny, huge, sideways, backward | Exported bounds/node transforms/axes and visual wrapper transform; fix the single conversion point, not root physics scale. |
| Pink/black or plain-color mesh | Missing image/material references, active surface versus material override, UVs, export-compatible graph and texture colorspace. |
| Recesses appear raised | Tangents, final triangulation and normal +Y convention; do not flip green twice. |
| Coat looks dirty/plastic under moving light | Lit color bake, excessive AO/normal strength, wrong roughness/metallic channels or sRGB data texture. |
| UV seams at distance | Padding/dilation, mirrored tangent basis, mipmaps and texture compression, not merely higher texture resolution. |
| Recoloring one changes all | Shared material/texture mutations or editing the shared mesh; isolate the correct resource once. |
| Clip name changes or missing motion | Import suffix setting, NLA/action slots and exporter inclusion, baked constraints, actual GLB clip list. Refer to creature skill. |
| Floating/sliding paws or double bob | Origin/ground offset, imported axes, root-motion policy, actual velocity/contact phase and leftover primitive sine/tweens. |

## Delivery record

List changed runtime/source/import/license/metadata/integration files; exact reproduction command plus real prerequisites; measured scale/axes/counts and texture channel conventions; requested variants completed; actual cold-import/runtime/regression results and capture paths; and any explicit unresolved gate. Do not claim a missing tool, unlicensed source, unimplemented script, or an uninspected render is complete.
