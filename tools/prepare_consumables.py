"""Author the bandage-wrap and potion-drink clips into the shipped Ranger GLB.

Run: blender --background --python tools/prepare_consumables.py
The tool imports the existing game GLB and authors two full-body actions in
Blender, then merges only those animations into the original GLB document.
Every existing node, skin, mesh and animation stays untouched; Blender's
round-trip is never allowed to rewrite the shipped clips. It does not need the
external source archives.
"""
import copy
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parent.parent
GLB = ROOT / 'assets' / 'characters' / 'ironwood_ranger.glb'
METADATA = GLB.with_suffix('.json')
FPS = 60
BANDAGE_SECONDS = 3.0
POTION_SECONDS = 0.5

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS
bpy.ops.import_scene.gltf(filepath=str(GLB))
objects = set(bpy.data.objects)
rig = next(obj for obj in objects if obj.type == 'ARMATURE')
rig.name = 'Armature'
AUTHORED = ('Bandage_Wrap', 'Potion_Drink')
for action in list(bpy.data.actions):
    if action.name in AUTHORED or action.name.startswith(tuple(name + '.' for name in AUTHORED)):
        bpy.data.actions.remove(action)
actions = {action.name: action for action in bpy.data.actions}
for action in actions.values():
    action.use_fake_user = True


def set_action(action):
    rig.animation_data_create()
    rig.animation_data.use_nla = False
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]


def smooth(value):
    value = clamp01(value)
    return value * value * (3.0 - 2.0 * value)


def clamp01(value):
    return max(0.0, min(1.0, value))


def set_rotation(name, rotation):
    bone = rig.pose.bones[name]
    parent = bone.parent
    origin = (parent.matrix @ parent.bone.matrix_local.inverted() @ bone.bone.matrix_local).translation if parent else bone.bone.matrix_local.translation
    desired = rotation.to_matrix().to_4x4()
    desired.translation = origin
    bone.matrix = desired
    bpy.context.view_layer.update()


def solve_arm(side, wrist, elbow_hint, hand_rotation):
    upper = rig.pose.bones['upperarm_' + side]
    lower = rig.pose.bones['lowerarm_' + side]
    shoulder = upper.head.copy()
    a, b = upper.bone.length, lower.bone.length
    direction = wrist - shoulder
    distance = min(max(direction.length, abs(a - b) + 0.0001), a + b - 0.0001)
    axis = direction.normalized()
    along = (a * a - b * b + distance * distance) / (2 * distance)
    pole = elbow_hint - shoulder
    pole -= axis * pole.dot(axis)
    if pole.length < 0.00001:
        pole = Vector((0, 1, 0)).cross(axis)
    elbow = shoulder + axis * along + pole.normalized() * math.sqrt(max(0, a * a - along * along))
    for name, destination in [('upperarm_' + side, elbow), ('lowerarm_' + side, wrist)]:
        pb = rig.pose.bones[name]
        old_direction = pb.tail - pb.head
        delta = old_direction.rotation_difference(destination - pb.head)
        set_rotation(name, delta @ pb.matrix.to_quaternion())
    set_rotation('hand_' + side, hand_rotation)


def solve_leg(side, ankle, knee_hint, foot_rotation):
    upper = rig.pose.bones['thigh_' + side]
    lower = rig.pose.bones['calf_' + side]
    hip = upper.head.copy()
    a, b = upper.bone.length, lower.bone.length
    direction = ankle - hip
    distance = min(max(direction.length, abs(a - b) + 0.0001), a + b - 0.0001)
    axis = direction.normalized()
    along = (a * a - b * b + distance * distance) / (2 * distance)
    pole = knee_hint - hip
    pole -= axis * pole.dot(axis)
    if pole.length < 0.00001:
        pole = Vector((0, -1, 0)).cross(axis)
    knee = hip + axis * along + pole.normalized() * math.sqrt(max(0, a * a - along * along))
    for name, destination in [('thigh_' + side, knee), ('calf_' + side, ankle)]:
        pb = rig.pose.bones[name]
        old_direction = pb.tail - pb.head
        delta = old_direction.rotation_difference(destination - pb.head)
        set_rotation(name, delta @ pb.matrix.to_quaternion())
    set_rotation('foot_' + side, foot_rotation)


def key_all(action, frame):
    for bone in rig.pose.bones:
        bone.keyframe_insert('location', frame=frame, group=bone.name)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        bone.keyframe_insert('scale', frame=frame, group=bone.name)


set_action(actions['Idle_Loop'])
bpy.context.scene.frame_set(0)
bpy.context.view_layer.update()
base_basis = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
base_world = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
base_hand_r = rig.pose.bones['hand_r'].matrix.to_quaternion()
base_hand_l = rig.pose.bones['hand_l'].matrix.to_quaternion()
left_wrist = base_world['hand_l'].translation.copy()
right_wrist = base_world['hand_r'].translation.copy()
left_elbow = base_world['lowerarm_l'].translation.copy()
right_elbow = base_world['lowerarm_r'].translation.copy()
left_shoulder = base_world['upperarm_l'].translation.copy()
right_shoulder = base_world['upperarm_r'].translation.copy()

# The wrapping arm cannot reach across the whole chest to the opposite wrist
# while the target arm stays at its side. Bring the left forearm up in front of
# the sternum, then circle the right hand around that forearm with the roll.
wrap_wrist = Vector((-0.02, -0.30, 1.36))
bandage_roll = Vector((-0.04, -0.28, 1.36))
mouth = Vector((-0.03, -0.12, 1.62))


def pose_common(lean, head_pitch, yaw=0.0):
    for bone in rig.pose.bones:
        bone.matrix_basis = base_basis[bone.name]
    bpy.context.view_layer.update()
    if abs(yaw) > 0.0001:
        set_rotation('pelvis', Matrix.Rotation(math.radians(yaw * 0.25), 4, 'Z').to_quaternion() @ base_world['pelvis'].to_quaternion())
    for name, factor in [('spine_01', 0.45), ('spine_02', 0.75), ('spine_03', 1.0)]:
        set_rotation(name, Matrix.Rotation(math.radians(lean * factor), 4, 'X').to_quaternion() @ base_world[name].to_quaternion())
    set_rotation('neck_01', Matrix.Rotation(math.radians(head_pitch * 0.45), 4, 'X').to_quaternion() @ base_world['neck_01'].to_quaternion())
    set_rotation('Head', Matrix.Rotation(math.radians(head_pitch), 4, 'X').to_quaternion() @ base_world['Head'].to_quaternion())


# --- Bandage_Wrap: 3.0 s, left forearm presented, right hand wraps around it. ---
bandage = bpy.data.actions.new('Bandage_Wrap')
set_action(bandage)
bandage_frames = round(BANDAGE_SECONDS * FPS)
for frame in range(bandage_frames + 1):
    t = frame / bandage_frames
    lift = smooth(t / 0.16)
    settle = smooth((t - 0.82) / 0.18)
    weight = lift * (1.0 - settle)
    pose_common(2.0 * weight, 14.0 * weight, 0.0)
    if weight > 0.001:
        # Present the left forearm across the sternum, palm turned up.
        left_target = left_wrist.lerp(wrap_wrist, weight) + Vector((0.0, -0.14, 0.0)) * (math.sin(math.pi * weight) ** 0.35)
        solve_arm('l', left_target, Vector((0.50, -0.45, 1.30)), base_hand_l)
        # Circle the right hand around the lifted forearm. Two revolutions read
        # as deliberate wrapping rather than one ambiguous hand pass.
        turn = math.tau * 2.0 * smooth(clamp01((t - 0.10) / 0.68))
        around = Vector((math.cos(turn) * 0.060, math.sin(turn) * 0.045 - 0.015, 0.03 * math.sin(turn)))
        right_target = right_wrist.lerp(bandage_roll + around, weight)
        solve_arm('r', right_target, Vector((-0.52, -0.42, 1.26)), base_hand_r)
    key_all(bandage, frame)
bandage.use_fake_user = True

# --- Potion_Drink: 0.5 s, bottle raised to the mouth and tipped. ---
potion = bpy.data.actions.new('Potion_Drink')
set_action(potion)
potion_frames = round(POTION_SECONDS * FPS)
for frame in range(potion_frames + 1):
    t = frame / potion_frames
    raise_hand = smooth(t / 0.42)
    tip = smooth((t - 0.28) / 0.34)
    lower = smooth((t - 0.74) / 0.26)
    weight = raise_hand * (1.0 - lower)
    pose_common(3.0 * weight, -14.0 * weight, 0.0)
    if weight > 0.001:
        right_target = right_wrist.lerp(mouth, weight) + Vector((-0.18, -0.16, 0.0)) * math.sin(math.pi * weight)
        tilt = Matrix.Rotation(math.radians(-55.0 * tip * (1.0 - lower)), 4, 'X').to_quaternion()
        solve_arm('r', right_target, Vector((-0.55, -0.28, 1.43)),
                  base_hand_r @ tilt)
        left_target = left_wrist.lerp(left_wrist + Vector((-0.02, -0.03, 0.01)), weight)
        solve_arm('l', left_target, Vector((0.44, -0.18, 1.26)), base_hand_l)
    key_all(potion, frame)
potion.use_fake_user = True


# Rebuild one NLA track per action so the exporter emits exactly the shipped
# clip set plus the two authored additions.
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
rig.animation_data.action = None
for action in list(bpy.data.actions):
    if action not in actions.values() and action not in (bandage, potion):
        bpy.data.actions.remove(action)
ordered = list(actions.values()) + [bandage, potion]
for action in ordered:
    track = rig.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, 0, action)
    track.mute = True
for pose_bone in rig.pose.bones:
    pose_bone.matrix_basis = Matrix.Identity(4)
TEMP = GLB.with_name('ironwood_ranger_consumables_export.glb')
bpy.ops.export_scene.gltf(
    filepath=str(TEMP), export_format='GLB', export_animations=True,
    export_animation_mode='NLA_TRACKS', export_nla_strips=True,
    export_force_sampling=True, export_frame_range=False, export_yup=True,
    export_materials='EXPORT', export_image_format='AUTO', export_skins=True)

# Do not re-export the shipped rig. Blender's glTF round-trip perturbs the
# existing clip channels even when the rest transforms look equivalent, which
# changes cover/aim presentation. Merge only the two authored animations into
# the original GLB document and leave every existing node, skin, mesh and
# animation byte-for-byte untouched.
import struct


def read_glb(path):
    raw = path.read_bytes()
    json_size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + json_size])
    return document, bytearray(raw[28 + json_size:])


def write_glb(path, document, binary):
    document['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(document, separators=(',', ':')).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    while len(binary) % 4:
        binary.append(0)
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary))
                     + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
                     + struct.pack('<II', len(binary), 0x004E4942) + binary)


def merge_clips(base_path, authored_path, clip_names):
    base, base_binary = read_glb(base_path)
    authored, authored_binary = read_glb(authored_path)
    if [n.get('name') for n in base['nodes']] != [n.get('name') for n in authored['nodes']]:
        raise RuntimeError('Authored GLB node order differs from the shipped rig')
    base['animations'] = [a for a in base.get('animations', []) if a.get('name') not in clip_names]
    component_size = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    components = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16}
    for animation in authored['animations']:
        if animation.get('name') not in clip_names:
            continue
        accessor_map = {}

        def copy_accessor(index):
            if index in accessor_map:
                return accessor_map[index]
            accessor = copy.deepcopy(authored['accessors'][index])
            if 'sparse' in accessor:
                raise RuntimeError('Sparse animation accessors are not supported')
            view = authored['bufferViews'][accessor['bufferView']]
            element_size = component_size[accessor['componentType']] * components[accessor['type']]
            stride = view.get('byteStride', element_size)
            size = element_size if accessor['count'] == 0 else stride * (accessor['count'] - 1) + element_size
            start = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
            data = bytes(authored_binary[start:start + size])
            while len(base_binary) % 4:
                base_binary.append(0)
            new_view = {'buffer': 0, 'byteOffset': len(base_binary), 'byteLength': size}
            if 'target' in view:
                new_view['target'] = view['target']
            if 'byteStride' in view:
                new_view['byteStride'] = view['byteStride']
            base_binary.extend(data)
            base['bufferViews'].append(new_view)
            accessor['bufferView'] = len(base['bufferViews']) - 1
            accessor['byteOffset'] = 0
            base['accessors'].append(accessor)
            accessor_map[index] = len(base['accessors']) - 1
            return accessor_map[index]

        channels = []
        for channel in animation['channels']:
            channel = copy.deepcopy(channel)
            node_index = channel['target']['node']
            if base['nodes'][node_index].get('name') != authored['nodes'][node_index].get('name'):
                raise RuntimeError('Animation channel targets an unexpected node')
            channels.append(channel)
        samplers = []
        for sampler in animation['samplers']:
            samplers.append({
                'input': copy_accessor(sampler['input']),
                'output': copy_accessor(sampler['output']),
                'interpolation': sampler.get('interpolation', 'LINEAR'),
            })
        base['animations'].append({'name': animation['name'], 'channels': channels, 'samplers': samplers})
    write_glb(base_path, base, base_binary)


merge_clips(GLB, TEMP, {'Bandage_Wrap', 'Potion_Drink'})
TEMP.unlink()

raw = GLB.read_bytes()
json_size = struct.unpack_from('<I', raw, 12)[0]
document = json.loads(raw[20:20 + json_size])
metadata = json.loads(METADATA.read_text(encoding='utf-8'))
durations = {animation['name']: max(document['accessors'][sampler['input']]['max'][0] for sampler in animation['samplers'])
             for animation in document['animations']}
metadata['clips']['bandage'] = {
    'name': 'Bandage_Wrap', 'duration': durations['Bandage_Wrap'], 'loop': False,
    'use_seconds': BANDAGE_SECONDS, 'heal': 35.0, 'heal_seconds': 3.0,
}
metadata['clips']['potion'] = {
    'name': 'Potion_Drink', 'duration': durations['Potion_Drink'], 'loop': False,
    'use_seconds': POTION_SECONDS, 'heal': 50.0,
}
metadata['consumable_authoring'] = {
    'authoring_fps': FPS,
    'bandage_frames': bandage_frames,
    'bandage_description': 'Left forearm raised across the sternum; right hand makes two wrapping loops around it.',
    'potion_description': 'Right hand raises a bottle to the mouth, hand and head tip for the drink, then lower.',
}
METADATA.write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
print('CONSUMABLE_CLIPS', {name: durations[name] for name in ('Bandage_Wrap', 'Potion_Drink')})
print('EXISTING_CLIP_COUNT', len(durations))
