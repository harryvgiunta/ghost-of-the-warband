# Default grey wolf: authoring recipe

Read this before creating or changing creature geometry, UVs, skinning, or bind transforms. Read [animation and integration](animation-integration.md) before baking motion. Acquisition/export details belong to [Ironwood Assets](../../ironwood-assets/SKILL.md). The default wolf now implements this contract. Use it to review or extend the shipped asset, and re-measure the actual GLB/JSON before changing proportions, axes or clip timing.

## 1. Establish inputs and reproducibility

**Input:** requested default creature, live `scripts/enemy.gd`, approved source/license or an original authoring plan, available Blender executable.

1. Keep downloaded source and extraction under ignored local storage, following `.runtime/character-source` as the existing convention. Track truthful per-asset provenance separately from the Ranger license. Record exact source files, hashes, source URLs, license text/conditions, author, modifications, and any separately licensed motion or textures. Do not guess a license from a search result or model filename.
2. Choose one route: adapt a licensed continuous skinned wolf; model and rig an original wolf; or construct a continuous production mesh with deterministic Blender Python. Combining primitives with smooth shading without joining/remeshing/retopology, UVs and deformation is not the latter route.
3. The reusable entry point is `tools/prepare_wolf.py`, invoked with `-- SOURCE_DIR OUTPUT_GLB`. The shipped version builds the default wolf from deterministic proportions, paints the coat directly into the packed UV atlas, bakes at 60 fps, and fails loudly on missing geometry or an unpacked atlas. It does not use a scene bake or a default cube. A different creature or variant still needs its own implemented authoring path.
4. Retain editable source or a fully reproducible authoring script, not only the compiled GLB. Record Blender version and export options. Keep originals unmodified; generated scratch files and renders remain local.

**Gate/output:** known legal inputs and an executable authoring plan. If source rights are unresolved, do not ship it; use verified alternative inputs or original work and state the decision.

## 2. Build a recognisable continuous animal

Recommended starting dimensions for this game's default wolf, **not anatomical facts or mandatory gameplay changes**: shoulder height around 0.8–0.95 m; torso from rump to shoulder around 0.95–1.15 m; tapered muzzle around 0.25–0.35 m; tail around 0.5–0.65 m. Fit the visual intentionally around the existing capsule (radius 0.40 m, height 0.95 m, centred at y=0.475), floor at y=0, and aim point y=0.68. The capsule need not wrap the muzzle and tail; it must protect the torso without floating feet or hiding most of the silhouette inside the floor.

1. Block side/front/three-quarter silhouettes from real canid references: deep rib cage, tucked abdomen, narrow waist, shoulder blade mass, distinct pelvis, sloping neck/ruff, wedge muzzle, upright ears, and weight-bearing digitigrade legs. Keep eyes on the head sides, not a human face. Hind hock is an ankle; the knee/stifle is higher and bends toward the head.
2. Form one connected body/neck/head/limb skin with smooth anatomical transitions. Eyes, teeth, claws and mouth interior may be separate properly attached pieces; they are not a substitute for continuous body topology. Include a jaw hinge and mouth cavity if the bite opens the mouth; no see-through head or solid lips stretched apart.
3. Put deformation loops across shoulder, elbow, wrist, hip, stifle, hock, neck, jaw and tail base. Route loops around the armpit/groin rather than spanning them with long skinny triangles. Provide joint curvature on both sides of a bend and volume in the chest/haunches. Model paw pads/sole plane and plausible toes; do not use rigid rectangular feet.
4. Make the mane/cheek ruff/tail silhouette through geometry where needed. Texture direction and restrained normal detail supply short fur. Do not use an expensive hair simulation or transparent fur-card layers by default. If cards are requested, separately prove alpha sorting, shadowing and overdraw in the real renderer.
5. Recommended starting runtime budget: roughly 8k–20k triangles, one main fur material plus a small detail material, one 1k–2k body texture set. These are adjustable targets, not acceptance by polygon count. Remove buried duplicate geometry, source rigs and unused materials. Inspect triangulated deformation before export; avoid topology edits after baking weights without revalidation.

**Gate/output:** neutral grey solid-shaded render in front/side/three-quarter view showing all paws at the floor and an unmistakable wolf silhouette. Stop here if it still looks like linked spheres, a bear, a fox, or an elongated humanoid.

## 3. UVs and a finished grey coat

1. UV unwrap the body with seams along belly/inner limbs and hidden neck/tail undersides. Keep muzzle/eye/ear detail readable, texel density consistent, and sufficient dilation padding for the target mip chain (start around 8–16 pixels at 2k and inspect distant mips). Mirror only areas where symmetry is intentional; do not accidentally overlap unique face marks or a future coat mask.
2. Author a directional coat: darker charcoal back/saddle and outer ears, mid-grey flanks, lighter warm-grey cheeks/chest/belly/inner legs, subtle mottled transitions rather than a flat global tint. Fur strokes follow growth: away from the nose, down/back over the neck and ribs, down legs, and toward the tail tip. Use broad pattern first, fine strand impression second; avoid noisy speckling that flickers at game distance.
3. Supply base colour in sRGB; normal/roughness/metallic/masks in linear/non-colour data. Use non-metal fur and relatively rough response (starting roughness 0.75–0.95); nose/pads and eyes get separate calibrated response. Bake Blender procedural shading into supported images before GLB export. Do not assume arbitrary Blender shader nodes survive glTF.
4. Keep eyes/iris, teeth, claws, mouth and nose outside the fur recolour region, by separate surfaces or a measured mask. A future black/white coat must preserve amber eyes and distinct teeth/nose. Keep a neutral grey default attractive without introducing a variant framework yet.
5. Check UV checker stretch on shoulder/hip/muzzle and seam visibility under both neutral light and actual world light. Check normal-map handedness by lighting a known raised detail; do not invert a channel because the texture filename says “DirectX” without inspecting the source and render.

**Gate/output:** textured neutral and in-world preview with readable anatomy, no checker distortion, smeared seams, shiny metallic fur, missing textures, or crushed all-black/all-white silhouette. Export embeds the actual runtime textures; an external Blender node graph is not a delivered texture.

## 4. True quadruped rest skeleton

Use a documented asset-space convention. Blender is Z-up; Godot/glTF output is Y-up. Gameplay faces -Z; the Ranger happens to import facing +Z and rotates by PI. **Measure this wolf's exported axes**, do not inherit that correction blindly. Choose one visual-child conversion and record it; do not rotate mesh, skeleton, and root independently until they appear aligned.

A proposed deformation hierarchy (names are an implementation choice):

```text
root                         # stationary export/root-motion reference
  pelvis
    spine_01
      spine_02
        chest
          neck_01
            neck_02
              head
                jaw
                ear_l / ear_r
          scapula_l / scapula_r
            upper_fore_l/r
              lower_fore_l/r
                carpus_l/r
                  front_paw_l/r
                    front_toes_l/r
    thigh_l / thigh_r
      shin_l/r
        hock_l/r
          hind_paw_l/r
            hind_toes_l/r
    tail_01 -> tail_02 -> tail_03 -> tail_04
```

Each `/` denotes **separate left/right chains**, not literal shared parenting. Add more spine/tail segments only if needed for the silhouette. IK controllers, poles and helpers are authoring controls, not weighted deformation bones or arbitrary glTF nodes.

1. Establish dimensions and apply object rotation/scale **before** binding. Mesh and armature object scales should be positive and uniform (prefer identity); remove negative-scale mirrors before skinning. Do not apply transforms to an already skinned/animated source without compensating bind/rest matrices and rebaking the entire rig.
2. Use a relaxed four-foot stance with a slight elbow/stifle bend, paws parallel to the ground and facing forward. Place joint heads at anatomical pivots, tail root at the pelvis, jaw at the hinge. No zero-length bones. Record each rest matrix, parent, bone length, and relevant paw sole offset; mesh centre and bone origin are not sole contact points.
3. In Blender each bone's local Y follows head-to-tail. Choose consistent bone roll so the local flexion axis is measurable. Mirrored limbs need deliberate mirrored frames, not copied Euler angles. In Godot use imported rest transforms and quaternions; imported bone axes need not match Blender's displayed axes after export.
4. Forelimb: scapula translates/rotates modestly against the chest; elbow bends back relative to the direction of travel, carpus flexes as the paw lifts. Hindlimb: stifle bends toward the head and hock points back; the elevated hock is not a backwards knee. Keep fixed bone lengths.
5. Put fore elbow poles behind and slightly outside their shoulder-to-paw plane, hind stifle poles forward and slightly outside the hip-to-paw plane. Derive each rest bend plane from the actual joint chain, then set Blender IK pole angles so the neutral pose is preserved. Move every target through its full reach envelope and side-step to detect 180-degree pole flips; don't patch flips with stretched limbs.
6. If solving a two-link hind chain, solve hip→stifle→hock with an independently oriented hock/foot chain and sole target; do not collapse the whole digitigrade limb into a human thigh/shin. Bake the resulting full chain. Separate front carpus/toe and hind hock/toe articulation makes ground roll and toe-off visible.

**Gate/output:** documented forward/up/unit/bind contract; four target/pole tests with no flips, correct bends, no bone scaling, feet on measured sole planes, and intact mesh alignment after a test export/import.

## 5. Skin and deform before animating

1. Assign vertex groups to deformation bones only. Normalize weights; cap at four effective influences per vertex for a straightforward runtime skinning budget, then verify that pruning did not break shoulders. No unweighted vertices, negative weights, or vertices bound to the control rig.
2. Blend shoulder/scapula and hip transitions across several loops; do not weld the entire foreleg rigidly to chest rotation. Preserve chest/haunch volume at peak flexion. Tail weights taper smoothly along the chain. Keep eyes rigid to head, teeth to head/jaw as appropriate, and ears deforming at their base without sliding across the skull.
3. Exercise maximal planned fore reach/back extension, hind compression, spine arch, head turn, jaw open and tail curl. Render the **skinned mesh**, not just bones. Repair collapsed armpits, candy-wrapper twists, stretched belly triangles, paw-pad inversion and jaw/neck intersections.
4. When retargeting, map each source rest frame to the target rest frame and transfer relative rotation with explicit basis conversion. Resolve root translation separately in metres. Inspect both rigs' hierarchies/axes; similar names do not prove compatible rest transforms. Humanoid Ranger maps cannot drive this quadruped. If source motion is unusable, author real Blender keys instead of substituting runtime sine waves.

**Gate/output:** finished weighted rig plus recorded deformation screenshots and no unhandled skin defects. Proceed to the animation reference only after this gate.

## 6. Reproducible export boundary

The authoring script exists. Regenerate the shipped default with:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python-exit-code 1 --python tools/prepare_wolf.py -- .runtime/character-source/wolf assets/characters/ironwood_wolf.glb
if ($LASTEXITCODE -ne 0) { throw 'Wolf authoring/export failed' }
```

The runtime outputs are `assets/characters/ironwood_wolf.glb`, adjacent measured JSON, provenance and `.glb.import`, plus the thin `scripts/wolf_visual.gd` controller. The shipped import uses `nodes/use_name_suffixes=false`, `animation/fps=60` and `gltf/embedded_image_handling=2` so the 1024 coat is embedded in the imported scene without an extracted duplicate PNG. Follow the Ranger export conventions in `tools/prepare_character.py`: `bpy.context.scene.render.fps = 60`, one intentional named baked action/NLA track per clip, packed image data, GLB/Y-up/skins/forced animation sampling, no source/preview objects. The current exporter uses `bpy.ops.export_scene.gltf` with `export_animation_mode='NLA_TRACKS'`, `export_nla_strips=True`, `export_force_sampling=True`, `export_frame_range=False`, `export_yup=True`, `export_skins=True`; re-read it and the installed Blender operator options rather than inventing flags. Blender action slots must be assigned correctly when setting an action; the Ranger script shows the installed-version pattern.

Metadata must derive from the **exported** asset: skeleton path and bone names, imported forward/up/unit, bounds/shoulder height, contact offsets/rest axes, actual clip names/durations, loop flags, stride distances, attack landmark times, source/license identities and hashes. JSON claims do not replace inspecting the GLB. Do not manually duplicate hand-entered durations that drift from the baked keys. The shipped wolf metadata records 37 bones, 15,036 triangles, a 1024 coat, a 1.15 m trot stride and a 0.65 s impact; `tests/wolf_regression.gd` checks the imported names, durations, loop flags, facing, scale and held death.
