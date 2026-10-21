"""Offline clothed-rig support-arm clearance; no runtime IK or attack generation."""
import math
import bpy
import numpy as np
from mathutils import Quaternion, Vector
from mathutils.bvhtree import BVHTree

SUPPORT_BONES = ('clavicle_l', 'upperarm_l', 'lowerarm_l', 'hand_l')


def torso_tree(body):
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    tree = BVHTree.FromPolygons(
        [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices],
        [list(polygon.vertices) for polygon in mesh.polygons])
    evaluated.to_mesh_clear()
    return tree


def forearm_clear(tree, elbow, wrist, radius, nearest=False):
    along = (wrist - elbow).normalized()
    across = along.cross(Vector((0, 0, 1))).normalized()
    if across.length_squared < 0.01:
        across = along.cross(Vector((1, 0, 0))).normalized()
    second = along.cross(across).normalized()
    for offset in (Vector(), across*radius, -across*radius, second*radius, -second*radius):
        if tree.ray_cast(elbow + offset, along, (wrist - elbow).length)[0] is not None:
            return False
    if nearest:
        for fraction in (0, .25, .5, .75, 1):
            point = elbow.lerp(wrist, fraction)
            surface, normal, _, distance = tree.find_nearest(point)
            if surface is not None and ((point - surface).dot(normal) < 0 or distance < radius):
                return False
    return True


def candidate_pose(base, controls, upper_length, lower_length, palm):
    pole, slide, depression, protraction = controls
    delta = Quaternion(base['up'], math.radians(protraction)) @ Quaternion(base['front'], math.radians(depression))
    shoulder = base['pivot'] + delta @ (base['shoulder'] - base['pivot'])
    wrist = base['grip'] @ Vector((0, 0, slide)) - base['hand_rotation'] @ palm
    vector = wrist - shoulder
    distance = vector.length
    if distance >= upper_length + lower_length - .001 or distance <= abs(upper_length - lower_length) + .001:
        return None
    axis = vector.normalized()
    along = (upper_length**2 - lower_length**2 + distance**2) / (2*distance)
    radial = base['elbow'] - shoulder
    radial -= axis * radial.dot(axis)
    if radial.length < .00001:
        return None
    radial.normalize()
    radial *= math.sqrt(max(0, upper_length**2 - along**2))
    elbow = shoulder + axis*along + Quaternion(axis, math.radians(pole)) @ radial
    return delta, elbow, wrist


def correct_support_arm(rig, body, action, socket, palm, set_rotation, solve_arm):
    """Find a continuous clearance path while the right arm and hilt stay fixed.

    Search anatomical elbow-pole, clavicle and on-handle slide controls against
    the actual deformed shirt. Dynamic programming penalizes changes between
    neighbouring poses; a short symmetric filter removes grid stepping. No
    source body, attacking-arm, finger or timing channel is rewritten.
    """
    rig.animation_data.action = action
    rig.animation_data.action_slot = action.slots[0]
    rig.animation_data.use_nla = False
    last = round(action.frame_range[1])
    upper_length = rig.data.bones['upperarm_l'].length
    lower_length = rig.data.bones['lowerarm_l'].length
    bases, candidates = [], []
    for frame in range(last + 1):
        bpy.context.scene.frame_set(frame)
        chest = rig.pose.bones['spine_03'].matrix.to_quaternion() @ rig.data.bones['spine_03'].matrix_local.to_quaternion().inverted()
        base = {
            'basis': {name: rig.pose.bones[name].matrix_basis.copy() for name in SUPPORT_BONES},
            'pivot': rig.pose.bones['clavicle_l'].head.copy(),
            'clavicle_rotation': rig.pose.bones['clavicle_l'].matrix.to_quaternion(),
            'shoulder': rig.pose.bones['upperarm_l'].head.copy(),
            'elbow': rig.pose.bones['lowerarm_l'].head.copy(),
            'hand_rotation': rig.pose.bones['hand_l'].matrix.to_quaternion(),
            'grip': rig.pose.bones['hand_r'].matrix @ socket,
            'front': chest @ Vector((0, -1, 0)), 'up': chest @ Vector((0, 0, 1)),
        }
        bases.append(base)
        tree = torso_tree(body)
        available = []
        # Idle needs only a changed elbow pole; recovery additionally needs
        # modest scapular depression/protraction and an on-handle palm slide.
        depressions = (0,) if action.name.startswith('Sword_Idle') else (0, -5, -10, -15, -20, -25)
        protractions = (0,) if action.name.startswith('Sword_Idle') else (0, -10, -20)
        for depression in depressions:
            for protraction in protractions:
                for slide in (.08, .09, .10, .11, .12, .13, .14):
                    accepted = 0
                    for pole in range(0, 121, 5):
                        controls = (pole, slide, depression, protraction)
                        pose = candidate_pose(base, controls, upper_length, lower_length, palm)
                        if pose and forearm_clear(tree, pose[1], pose[2], .036, nearest=True):
                            available.append(controls)
                            accepted += 1
                            if accepted == 3:
                                break
        if not available:
            raise RuntimeError(f'{action.name} frame {frame}: no anatomical shirt-clear support grip')
        if frame in (0, last):
            # Common guard endpoints also make idle/attack transitions coherent.
            available = [min(available, key=lambda c: (c[0]-30)**2 + ((c[1]-.12)*1000)**2 + c[2]**2 + c[3]**2)]
        candidates.append(np.asarray(available, dtype=float))

    # Preserve low correction magnitude, but avoid chasing a different nearest
    # collision-free solution at each frame (which would create elbow chatter).
    normalized = [values / np.array([45, .05, 20, 20]) - np.array([0, 2.4, 0, 0]) for values in candidates]
    costs = np.sum(normalized[0]**2, axis=1)
    links = []
    for frame in range(1, last + 1):
        difference = normalized[frame-1][:, None, :] - normalized[frame][None, :, :]
        transitions = costs[:, None] + 60*np.sum(difference*difference, axis=2)
        previous = np.argmin(transitions, axis=0)
        costs = transitions[previous, np.arange(len(previous))] + .05*np.sum(normalized[frame]**2, axis=1)
        links.append(previous)
    index = int(np.argmin(costs))
    path = [candidates[last][index]]
    for frame in range(last-1, -1, -1):
        index = int(links[frame][index])
        path.append(candidates[frame][index])
    path = np.asarray(path[::-1])
    smooth = path.copy()
    for frame in range(1, last):
        smooth[frame] = sum(path[min(last, max(0, frame+offset))]*weight for offset, weight in [(-2,1),(-1,2),(0,3),(1,2),(2,1)]) / 9

    for frame, controls in enumerate(smooth):
        bpy.context.scene.frame_set(frame)
        base = bases[frame]
        for name, basis in base['basis'].items():
            rig.pose.bones[name].matrix_basis = basis
        bpy.context.view_layer.update()
        delta, elbow, wrist = candidate_pose(base, controls, upper_length, lower_length, palm)
        set_rotation('clavicle_l', delta @ base['clavicle_rotation'])
        solve_arm('l', wrist, elbow, base['hand_rotation'])
        # Rebuild after the correction: the shirt has upper-arm skin weights.
        if not forearm_clear(torso_tree(body), rig.pose.bones['lowerarm_l'].head, rig.pose.bones['hand_l'].head, .030):
            raise RuntimeError(f'{action.name} frame {frame}: smoothed support correction intersects shirt')
        for name in SUPPORT_BONES:
            bone = rig.pose.bones[name]
            bone.keyframe_insert('location', frame=frame, group=name)
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=name)
            bone.keyframe_insert('scale', frame=frame, group=name)
    print('SUPPORT_CLEARANCE', action.name, 'pole', float(smooth[:,0].min()), float(smooth[:,0].max()), 'slide', float(smooth[:,1].min()), float(smooth[:,1].max()))
    return {'forearm_radius': .03, 'pole_degrees': [float(smooth[:,0].min()), float(smooth[:,0].max())],
            'handle_slide': [float(smooth[:,1].min()), float(smooth[:,1].max())],
            'clavicle_depression_degrees': [float(smooth[:,2].min()), float(smooth[:,2].max())],
            'clavicle_protraction_degrees': [float(smooth[:,3].min()), float(smooth[:,3].max())]}


def validate_export(filepath, metadata):
    """Inspect the exported, reimported skin at 240 Hz and across clip joins."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 60
    bpy.ops.import_scene.gltf(filepath=str(filepath))
    rig = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
    body = bpy.data.objects['Male_Ranger_Body']
    rig.animation_data.use_nla = False
    grip_data = metadata['sword_grip']
    q = grip_data['rotation']
    grip = Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4()
    grip.translation = Vector(grip_data['position'])
    palm = Vector(metadata['palms']['left'])
    count, maximum_grip_error = 0, 0.0
    endpoints = {}

    def inspect(label):
        nonlocal count, maximum_grip_error
        bpy.context.view_layer.update()
        tree = torso_tree(body)
        for side in ('l', 'r'):
            if not forearm_clear(tree, rig.pose.bones['lowerarm_' + side].head, rig.pose.bones['hand_' + side].head, .03):
                raise RuntimeError(f'{label}: {side} forearm intersects actual skinned shirt at 30 mm radial clearance')
        hand_local = (rig.pose.bones['hand_r'].matrix @ grip).inverted() @ (rig.pose.bones['hand_l'].matrix @ palm)
        error = math.hypot(hand_local.x, hand_local.y)
        maximum_grip_error = max(maximum_grip_error, error)
        if error > .008 or not .075 <= hand_local.z <= .265:
            raise RuntimeError(f'{label}: support palm has left the handle: {tuple(hand_local)}')
        count += 1

    for name in ('Sword_Idle', 'Sword_Overhead'):
        action = bpy.data.actions[name]
        rig.animation_data.action = action
        rig.animation_data.action_slot = action.slots[0]
        last = round(action.frame_range[1])
        for quarter in range(last*4 + 1):
            frame = quarter / 4
            bpy.context.scene.frame_set(math.floor(frame), subframe=frame % 1)
            inspect(f'{name} frame {frame}')
            if quarter in (0, last*4):
                endpoints[(name, quarter == 0)] = [bone.matrix_basis.copy() for bone in rig.pose.bones]
    rig.animation_data.action = None
    for label, start, finish in (
        ('idle loop', endpoints[('Sword_Idle', False)], endpoints[('Sword_Idle', True)]),
        ('guard to windup', endpoints[('Sword_Idle', True)], endpoints[('Sword_Overhead', True)]),
        ('recovery to guard', endpoints[('Sword_Overhead', False)], endpoints[('Sword_Idle', True)]),
    ):
        for step in range(25):
            for bone, first, last in zip(rig.pose.bones, start, finish):
                bone.matrix_basis = first.lerp(last, step / 24)
            inspect(f'{label} blend {step}/24')
    print('EXPORTED_SUPPORT_CLEARANCE', count, 'samples; maximum hilt error', maximum_grip_error)
    return {'sample_hz': 240, 'samples': count, 'forearm_radius': .03,
            'radial_axes': 2, 'maximum_support_hilt_error': maximum_grip_error,
            'transitions': ['idle loop', 'guard to windup', 'recovery to guard']}
