"""Validate an authored devil .blend: mesh budget, weights, clips and contact.

Usage (Blender 5.1):
    blender --background --python-exit-code 1 --python tools/check_devil.py -- hell_goat

The check is deliberately objective. It reports measured bounds, the worst
ground penetration in every clip, unweighted vertices, influence counts and
the exported clip inventory. It does not judge appearance.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    mob = argv[0] if argv else "hell_goat"
    blend = ROOT / ".runtime" / "devil-source" / mob / f"ironwood_{mob}_source.blend"
    if not blend.exists():
        raise SystemExit(f"Missing source blend: {blend}")
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    mesh = next(obj for obj in bpy.data.objects if obj.type == "MESH" and obj.modifiers.get("Armature"))
    rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
    scene = bpy.context.scene
    report = {
        "mob": mob,
        "triangles": sum(len(p.vertices) - 2 for p in mesh.data.polygons),
        "vertices": len(mesh.data.vertices),
        "bones": len(rig.pose.bones),
        "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
        "materials": [material.name for material in mesh.data.materials],
        "clips": {},
        "unweighted_vertices": 0,
        "max_influences": 0,
        "bounds": [
            [round(min(v.co[i] for v in mesh.data.vertices), 4) for i in range(3)],
            [round(max(v.co[i] for v in mesh.data.vertices), 4) for i in range(3)],
        ],
    }
    groups = {group.index: group.name for group in mesh.vertex_groups}
    for vertex in mesh.data.vertices:
        influences = [entry for entry in vertex.groups if entry.weight > 0.0001]
        report["max_influences"] = max(report["max_influences"], len(influences))
        if not influences:
            report["unweighted_vertices"] += 1
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for action in sorted(bpy.data.actions, key=lambda entry: entry.name):
        rig.animation_data.action = action
        if action.slots:
            rig.animation_data.action_slot = action.slots[0]
        end = int(action.frame_end)
        step = max(1, end // 24)
        samples = []
        for frame in range(0, end + 1, step):
            scene.frame_set(frame)
            depsgraph.update()
            evaluated = mesh.evaluated_get(depsgraph)
            data = evaluated.to_mesh()
            low = min(vertex.co.z for vertex in data.vertices)
            high = max(vertex.co.z for vertex in data.vertices)
            evaluated.to_mesh_clear()
            samples.append((frame, low, high))
        report["clips"][action.name] = {
            "duration": round(end / scene.render.fps, 3),
            "min_z": round(min(sample[1] for sample in samples), 4),
            "max_z": round(max(sample[2] for sample in samples), 4),
            "frames": len(samples),
        }
    rig.animation_data.action = None
    print("DEVIL_REPORT " + json.dumps(report))


if __name__ == "__main__":
    main()
