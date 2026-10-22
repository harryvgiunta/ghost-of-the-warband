"""Prepare the licensed Ranger and retarget selected authored character motions.
Run: blender --background --python tools/prepare_character.py -- SOURCE_DIR OUTPUT_GLB
SOURCE_DIR contains the unpacked Standard archives and Gres' original .blend;
see assets/characters/LICENSE.txt for acquisition URLs and original filenames.
Source locomotion/combat is retargeted; additive cover leans are authored here.
"""
import bpy
import bmesh
import json
import math
import struct
import sys
from bisect import bisect_left
from pathlib import Path
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from character_clearance import correct_support_arm, validate_export

SOURCE, OUTPUT = (Path(value).resolve() for value in sys.argv[sys.argv.index('--') + 1:][:2])
FPS = 60
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.render.fps = FPS


def import_gltf(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    added = set(bpy.data.objects) - before
    rig = next(o for o in added if o.type == 'ARMATURE')
    if rig.animation_data:
        rig.animation_data.use_nla = False
    return rig, added


ranger_path = SOURCE / 'Modular Character Outfits - Fantasy[Standard]/Exports/glTF (Godot-Unreal)/Outfits/Male_Ranger.gltf'
rig, ranger_objects = import_gltf(ranger_path)
rig.name = 'Armature'
base_path = SOURCE / 'Universal Base Characters[Standard]/Base Characters/Godot - UE/Superhero_Male_FullBody.gltf'
# Two normal-image URIs in the published base glTF have an extra _png suffix.
# Repair only their filenames in the ignored source directory, not their pixels.
for original, alias in [('T_Hair_1_Normal.png', 'T_Hair_1_Normal_png.png'), ('T_Eye_Normal.png', 'T_Eye_Normal_png.png')]:
    if not (base_path.parent / alias).exists():
        (base_path.parent / alias).write_bytes((base_path.parent / original).read_bytes())
base, base_objects = import_gltf(base_path)
# The free base pack includes the superhero head. Keep only head/eyes/brows;
# remove covered anatomy instead of shipping an invisible full body.
head_rest = base.data.bones['Head'].head_local.copy()
target_head = rig.data.bones['Head'].head_local.copy()
for obj in list(base_objects):
    if obj.type != 'MESH':
        continue
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < head_rest.z - 0.055], context='VERTS')
    if not bm.verts:
        bm.free()
        bpy.data.objects.remove(obj, do_unlink=True)
        continue
    for v in bm.verts:
        v.co = target_head + (v.co - head_rest) * 0.88
    bm.to_mesh(obj.data)
    bm.free()
    obj.name = 'Ranger_Head_' + obj.name
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)
    for modifier in obj.modifiers:
        if modifier.type == 'ARMATURE':
            modifier.object = rig
    ranger_objects.add(obj)
bpy.data.objects.remove(base, do_unlink=True)

ual, ual_objects = import_gltf(SOURCE / 'Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb')
ual.name = 'SourceUAL'
ual_actions = {a.name: a for a in bpy.data.actions}
# Save pristine target rest matrices once. All rotations are retargeted in armature
# space, avoiding importer bone-roll assumptions and Euler elbow discontinuities.
rest = {b.name: b.matrix_local.copy() for b in rig.data.bones}
rig.animation_data_create()
rig.animation_data.use_nla = False
for b in rig.pose.bones:
    b.rotation_mode = 'QUATERNION'


def set_action(source_rig, action):
    source_rig.animation_data_create()
    source_rig.animation_data.use_nla = False
    source_rig.animation_data.action = action
    if action.slots:
        source_rig.animation_data.action_slot = action.slots[0]


def set_rotation(name, rotation):
    bone = rig.pose.bones[name]
    parent = bone.parent
    origin = (parent.matrix @ parent.bone.matrix_local.inverted() @ bone.bone.matrix_local).translation if parent else bone.bone.matrix_local.translation
    desired = rotation.to_matrix().to_4x4()
    desired.translation = origin
    bone.matrix = desired
    bpy.context.view_layer.update()


def retarget_frame(source_rig, mapping, scale):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    for target_name, source_name in mapping.items():
        sb = source_rig.pose.bones[source_name]
        rotation = sb.matrix.to_quaternion() @ sb.bone.matrix_local.to_quaternion().inverted() @ rest[target_name].to_quaternion()
        set_rotation(target_name, rotation)
        if target_name == 'pelvis':
            matrix = rig.pose.bones[target_name].matrix.copy()
            matrix.translation += (sb.head - sb.bone.head_local) * scale
            rig.pose.bones[target_name].matrix = matrix
            bpy.context.view_layer.update()


def solve_arm(side, wrist, elbow_hint, hand_rotation):
    upper = rig.pose.bones['upperarm_' + side]
    lower = rig.pose.bones['lowerarm_' + side]
    shoulder = upper.head.copy()
    a, b = upper.bone.length, lower.bone.length
    direction = wrist - shoulder
    distance = min(max(direction.length, abs(a-b)+0.0001), a+b-0.0001)
    axis = direction.normalized()
    along = (a*a - b*b + distance*distance) / (2*distance)
    pole = elbow_hint - shoulder
    pole -= axis * pole.dot(axis)
    if pole.length < 0.00001:
        pole = Vector((0, 1, 0)).cross(axis)
    elbow = shoulder + axis*along + pole.normalized()*math.sqrt(max(0, a*a-along*along))
    for name, destination in [('upperarm_' + side, elbow), ('lowerarm_' + side, wrist)]:
        pb = rig.pose.bones[name]
        old_direction = pb.tail - pb.head
        delta = old_direction.rotation_difference(destination - pb.head)
        set_rotation(name, delta @ pb.matrix.to_quaternion())
    set_rotation('hand_' + side, hand_rotation)


def bake(name, source_rig, segments, mapping, scale, grip=False, source_times=None):
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    output_frame = 0
    for source_action, first, last in segments:
        set_action(source_rig, source_action)
        for frame in range(first, last + 1):
            sample_frame = source_times.get(frame, frame) if source_times else frame
            bpy.context.scene.frame_set(math.floor(sample_frame), subframe=sample_frame % 1)
            retarget_frame(source_rig, mapping, scale)
            if grip:
                # Keep the attacking arm's authored rotations and elbow bend.
                # Forcing a short Ranger arm to the source's longer-arm world
                # target would straighten the elbow during the overhead load.
                shift = rest['pelvis'].translation - source_rig.data.bones['spine'].head_local * scale
                # Ranger palms differ from the source's mitten topology. Keep
                # the support palm on the real hilt while retaining the authored
                # elbow pole and wrist rotation; never alter the attacking arm.
                left_rotation = rig.pose.bones['hand_l'].matrix.to_quaternion()
                grip_world = rig.pose.bones['hand_r'].matrix @ socket_matrix
                support_palm = grip_world @ Vector((0, 0, 0.12))
                support_wrist = support_palm - left_rotation @ left_palm_local
                source_elbow = source_rig.pose.bones['forearm.L'].head * scale + shift
                # A shorter support arm sometimes needs scapular elevation to
                # reach the authored high hilt. Rotate its clavicle minimally;
                # never stretch bones, invert an elbow, or detach the palm.
                shoulder = rig.pose.bones['upperarm_l'].head.copy()
                reach = rig.data.bones['upperarm_l'].length + rig.data.bones['lowerarm_l'].length - 0.004
                if (support_wrist - shoulder).length > reach:
                    clavicle = rig.pose.bones['clavicle_l']
                    radial = shoulder - clavicle.head
                    target = support_wrist - clavicle.head
                    angle = radial.angle(target)
                    cosine = (target.length_squared + radial.length_squared - reach*reach) / (2*target.length*radial.length)
                    allowed = math.acos(max(-1.0, min(1.0, cosine)))
                    correction = radial.rotation_difference(target)
                    fraction = min(1.0, max(0.0, (angle - allowed + 0.002) / max(angle, 0.00001)))
                    correction = Matrix.Identity(3).to_quaternion().slerp(correction, fraction)
                    set_rotation('clavicle_l', correction @ clavicle.matrix.to_quaternion())
                solve_arm('l', support_wrist, source_elbow, left_rotation)
                # Gres uses a mitten palm; supply actual authored finger grips
                # from Quaternius Sword_Idle rather than leaving T-pose fingers.
                for finger_name, rotation in authored_finger_grip.items():
                    rig.pose.bones[finger_name].rotation_quaternion = rotation
                    mirrored = rotation.copy()
                    mirrored.y = -mirrored.y
                    mirrored.z = -mirrored.z
                    rig.pose.bones[finger_name[:-1] + 'l'].rotation_quaternion = mirrored
            for pb in rig.pose.bones:
                pb.keyframe_insert('location', frame=output_frame, group=pb.name)
                pb.keyframe_insert('rotation_quaternion', frame=output_frame, group=pb.name)
                pb.keyframe_insert('scale', frame=output_frame, group=pb.name)
            output_frame += 1
    action.use_fake_user = True
    print('BAKED', name, output_frame, 'frames', (output_frame-1)/FPS, 'seconds')
    return action


def solve_planted_leg(side, ankle, knee_hint, foot_rotation):
    """Rotate a fixed-length leg to its neutral ankle, preserving foot contact."""
    upper = rig.pose.bones['thigh_' + side]
    lower = rig.pose.bones['calf_' + side]
    hip = upper.head.copy()
    a, b = upper.bone.length, lower.bone.length
    direction = ankle - hip
    distance = direction.length
    if not abs(a - b) < distance < a + b:
        raise RuntimeError(f'Cover stance cannot reach planted {side} ankle')
    axis = direction / distance
    along = (a*a - b*b + distance*distance) / (2*distance)
    pole = knee_hint - hip
    pole -= axis * pole.dot(axis)
    knee = hip + axis * along + pole.normalized() * math.sqrt(max(0, a*a - along*along))
    for name, destination in [('thigh_' + side, knee), ('calf_' + side, ankle)]:
        bone = rig.pose.bones[name]
        delta = (bone.tail - bone.head).rotation_difference(destination - bone.head)
        set_rotation(name, delta @ bone.matrix.to_quaternion())
    set_rotation('foot_' + side, foot_rotation)


def author_cover(name, idle, direction, degrees):
    """Key weight transfer and articulated lean; leave arm-local grip untouched.

    Blender +Z is up and -Y is forward. Export converts (x,y,z) to
    (x,z,-y), so anatomical left is asset +X and forward is asset +Z.
    Sixteen full-hierarchy samples are retimed to exactly 0.24 s in the GLB.
    """
    set_action(rig, idle)
    bpy.context.scene.frame_set(0)
    neutral = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
    world = {bone.name: bone.matrix.copy() for bone in rig.pose.bones}
    axis = Vector((0, 0, 1)).cross(direction).normalized()
    action = bpy.data.actions.new(name)
    set_action(rig, action)
    for frame in range(16):
        for bone in rig.pose.bones:
            bone.matrix_basis = neutral[bone.name]
        bpy.context.view_layer.update()
        u = frame / 15
        weight = u*u*(3 - 2*u)
        if frame:
            # Counterbalance the shoulders with the hips; soften knees enough
            # to keep both original ankles reachable without stretching.
            set_rotation('pelvis', Matrix.Rotation(math.radians(-3) * weight, 4, axis).to_quaternion() @ world['pelvis'].to_quaternion())
            pelvis = rig.pose.bones['pelvis']
            matrix = pelvis.matrix.copy()
            matrix.translation = world['pelvis'].translation - direction * (0.02 * weight) + Vector((0, 0, -0.012 * weight))
            pelvis.matrix = matrix
            bpy.context.view_layer.update()
            for bone_name, angle in [('spine_01', degrees * 0.50), ('spine_02', degrees * 0.80), ('spine_03', degrees), ('neck_01', degrees - 2), ('Head', degrees - 5)]:
                rotation = Matrix.Rotation(math.radians(angle) * weight, 4, axis).to_quaternion()
                set_rotation(bone_name, rotation @ world[bone_name].to_quaternion())
            for side in ('l', 'r'):
                solve_planted_leg(side, world['foot_' + side].translation, world['calf_' + side].translation + Vector((0, -0.1, 0)), world['foot_' + side].to_quaternion())
        for bone in rig.pose.bones:
            bone.keyframe_insert('location', frame=frame, group=bone.name)
            bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
            bone.keyframe_insert('scale', frame=frame, group=bone.name)
    action.use_fake_user = True
    print('AUTHORED', name, '16 full-hierarchy samples; export duration 0.24 seconds')
    return action


def measure_crouch(action, standing_pelvis_height):
    set_action(rig, action)
    heights, feet = [], {'l': [], 'r': []}
    for frame in range(int(action.frame_range[0]), int(action.frame_range[1]) + 1):
        bpy.context.scene.frame_set(frame)
        heights.append(rig.pose.bones['pelvis'].head.z)
        for side in feet:
            feet[side].append(rig.pose.bones['foot_' + side].head.copy())
    result = {
        'pelvis_drop': standing_pelvis_height - sum(heights) / len(heights),
        'pelvis_drop_range': [standing_pelvis_height - max(heights), standing_pelvis_height - min(heights)],
        'foot_fore_aft_excursion': {side: max(point.y for point in values) - min(point.y for point in values) for side, values in feet.items()},
        'measurement': 'Metres, mean/min/max pelvis drop relative to Idle_Loop frame 0; ankle +Z excursion is not full-cycle stride distance',
    }
    if action.get('export_name') == 'Crouch_Fwd_Loop':
        # An in-place clip has no root travel. Infer authored travel from the
        # backwards ankle speed during grounded stance, not swing excursion.
        stance_speeds = []
        for values in feet.values():
            contact_height = min(point.z for point in values) + 0.025
            for start, end in zip(values, values[1:]):
                speed = (end.y - start.y) * FPS
                if max(start.z, end.z) <= contact_height and speed > 0.03:
                    stance_speeds.append(speed)
        if not stance_speeds:
            raise RuntimeError('Crouch forward clip has no measurable backwards stance travel')
        stance_speeds.sort()
        middle = len(stance_speeds) // 2
        speed = (stance_speeds[middle] + stance_speeds[(len(stance_speeds) - 1) // 2]) / 2
        result.update(nominal_speed=speed, stride=speed * (action.frame_range[1] - action.frame_range[0]) / FPS,
                      stride_measurement='Estimated full-cycle travel: median backwards ankle speed within 25 mm of lowest contact, multiplied by cycle duration')
    print('CROUCH_MEASUREMENTS', action.get('export_name'), result)
    return result


def retime_cover_export(path, names):
    """Retain 60 Hz production export, then rescale only lean sample times.

    0.24 seconds is 14.4 frames at 60 Hz; integer NLA baking would otherwise
    truncate the last pose. No bone values, other clips or sockets are changed.
    """
    raw = path.read_bytes()
    json_size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + json_size])
    binary = bytearray(raw[28 + json_size:])
    lean_inputs = {sampler['input'] for animation in document['animations'] if animation['name'] in names for sampler in animation['samplers']}
    other_inputs = {sampler['input'] for animation in document['animations'] if animation['name'] not in names for sampler in animation['samplers']}
    if lean_inputs & other_inputs:
        raise RuntimeError('Cover sample times unexpectedly share another clip accessor')
    for index in lean_inputs:
        accessor = document['accessors'][index]
        view = document['bufferViews'][accessor['bufferView']]
        if accessor['componentType'] != 5126 or accessor['type'] != 'SCALAR':
            raise RuntimeError('Cover time accessor is not float scalar')
        offset = view.get('byteOffset', 0) + accessor.get('byteOffset', 0)
        stride = view.get('byteStride', 4)
        factor = 0.24 / accessor['max'][0]
        for sample in range(accessor['count']):
            at = offset + sample * stride
            struct.pack_into('<f', binary, at, struct.unpack_from('<f', binary, at)[0] * factor)
        accessor['min'] = [struct.unpack_from('<f', binary, offset)[0]]
        accessor['max'] = [struct.unpack_from('<f', binary, offset + (accessor['count'] - 1) * stride)[0]]
    encoded = json.dumps(document, separators=(',', ':')).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary)) + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + struct.pack('<II', len(binary), 0x004E4942) + binary)


set_action(ual, ual_actions['Sword_Idle'])
bpy.context.scene.frame_set(0)
authored_finger_grip = {bone.name: bone.rotation_quaternion.copy() for bone in ual.pose.bones if bone.name.endswith('_r') and bone.name.startswith(('index_', 'middle_', 'ring_', 'pinky_', 'thumb_'))}

identity = {b.name:b.name for b in rig.data.bones}
clips = ['Idle_Loop', 'Walk_Loop', 'Jog_Fwd_Loop', 'Sprint_Loop', 'Jump_Start', 'Jump_Loop', 'Jump_Land', 'Roll', 'Crouch_Idle_Loop', 'Crouch_Fwd_Loop']
finished = []
for name in clips:
    source_action = ual_actions[name]
    # Imported glTF samples already use the scene's 60 fps timebase.
    finished.append(bake(name + '_prepared', ual, [(source_action, round(source_action.frame_range[0]), round(source_action.frame_range[1]))], identity, 1.0))
    finished[-1]['export_name'] = name

set_action(rig, finished[0])
bpy.context.scene.frame_set(0)
standing_pelvis_height = rig.pose.bones['pelvis'].head.z
crouch_measurements = {name: measure_crouch(action, standing_pelvis_height) for name, action in zip(clips, finished) if name.startswith('Crouch_')}
cover_specs = {
    'cover_left': ('Cover_Lean_Left', Vector((1, 0, 0)), 18.0, [1, 0, 0]),
    'cover_right': ('Cover_Lean_Right', Vector((-1, 0, 0)), 18.0, [-1, 0, 0]),
    'cover_top': ('Cover_Lean_Top', Vector((0, -1, 0)), 14.0, [0, 0, 1]),
}
for name, direction, degrees, _ in cover_specs.values():
    finished.append(author_cover(name, finished[0], direction, degrees))

# The Quaternius heavy combo ends in a right-handed overhead cut. Extract its
# final load/downstroke/recovery only; preceding combo hits are not exported.
ual2, ual2_objects = import_gltf(SOURCE / 'Universal Animation Library 2[Standard]/Unreal-Godot/UAL2_Standard.glb')
ual2.name = 'SourceUAL2'
# The source concentrates most shoulder/elbow motion into frames 152–158:
# its elbow travels 0.240 m in 9.47 ms. Redistribute the SAME ordered poses
# across the existing active interval, not a new pose curve or a slower clip.
# Cumulative multi-joint travel avoids retaining that pathological speed spike;
# smoothstep keeps loaded acceleration and low-follow-through deceleration.
one_hand_source = bpy.data.actions['Sword_Heavy_Combo']
set_action(ual2, one_hand_source)
sample_frames = [150 + index / 4 for index in range(61)]
travel = [0.0]
previous = None
for sample_frame in sample_frames:
    bpy.context.scene.frame_set(math.floor(sample_frame), subframe=sample_frame % 1)
    positions = [ual2.pose.bones[name].head.copy() for name in ['pelvis', 'spine_03', 'upperarm_r', 'lowerarm_r', 'hand_r']]
    if previous is not None:
        travel.append(travel[-1] + max((current - old).length for current, old in zip(positions, previous)))
    previous = positions
one_hand_times = {}
for frame in range(150, 166):
    u = (frame - 150) / 15
    distance = u*u*(3 - 2*u) * travel[-1]
    upper = min(len(travel) - 1, max(1, bisect_left(travel, distance)))
    fraction = (distance - travel[upper - 1]) / max(travel[upper] - travel[upper - 1], 1e-12)
    one_hand_times[frame] = sample_frames[upper - 1] + fraction * (sample_frames[upper] - sample_frames[upper - 1])
finished.append(bake('Sword_Overhead_OneHand', ual2, [(one_hand_source,135,260)], identity, 1.0, source_times=one_hand_times))
finished.append(bake('Sword_Idle_OneHand', ual, [(ual_actions['Sword_Idle'],0,100)], identity, 1.0))

# Gres authored two-handed motion is 60 fps and has a distinct skeletal rig.
with bpy.data.libraries.load(str(SOURCE / 'playerstraightswordanimations.blend'), link=False) as (data_from, data_to):
    data_to.objects = ['Human', 'Longsword']
    data_to.actions = ['Idle_SS_TH', 'SS_TH_Charge02_Start', 'SS_TH_Charge02_Heavy']
source = data_to.objects[0]
bpy.context.collection.objects.link(source)
source.name = 'SourceGres'
source_weapon = data_to.objects[1]
bpy.context.collection.objects.link(source_weapon)
gres_actions = {a.name:a for a in data_to.actions}
mapping = {'root':'Root', 'pelvis':'spine', 'spine_01':'spine.001', 'spine_02':'spine.002', 'spine_03':'spine.003', 'neck_01':'spine.005', 'Head':'spine.006'}
for side, suffix in [('l','L'),('r','R')]:
    mapping.update({f'clavicle_{side}':f'shoulder.{suffix}', f'upperarm_{side}':f'upper_arm.{suffix}', f'lowerarm_{side}':f'forearm.{suffix}', f'hand_{side}':f'hand.{suffix}', f'thigh_{side}':f'thigh.{suffix}', f'calf_{side}':f'shin.{suffix}', f'foot_{side}':f'foot.{suffix}', f'ball_{side}':f'toe.{suffix}'})
# Anatomical height conversion (heads, not source control-bone lengths).
scale = rest['Head'].translation.z / source.data.bones['spine.006'].head_local.z

# Derive the socket from the actual source weapon constraint, not a guessed
# hand axis. The source sword points +Z; the game sword points -Z.
set_action(source, gres_actions['SS_TH_Charge02_Heavy'])
bpy.context.scene.frame_set(1)
source_hand = source.pose.bones['hand.R']
weapon_local = source_hand.matrix.inverted() @ source_weapon.matrix_world
rest_correction = rest['hand_r'].to_quaternion().inverted() @ source_hand.bone.matrix_local.to_quaternion()
socket_rotation = rest_correction @ weapon_local.to_quaternion() @ Matrix.Rotation(math.pi, 4, 'X').to_quaternion()
# The source pommel is at z=0 and its right-palm grip centre at z=27.85
# (source sword mesh units, with authored object scale 0.01).
socket_origin = rest_correction @ (weapon_local @ Vector((0, 0, 27.85))) * scale
socket_matrix = socket_rotation.to_matrix().to_4x4()
socket_matrix.translation = socket_origin
left_knuckles = sum((rig.data.bones[f'{finger}_01_l'].head_local for finger in ['index', 'middle', 'ring', 'pinky']), Vector()) / 4
left_palm_local = rest['hand_l'].inverted() @ ((left_knuckles + rig.data.bones['hand_l'].head_local) / 2)
finished.append(bake('Sword_Idle', source, [(gres_actions['Idle_SS_TH'],1,145)], mapping, scale, grip=True))
finished[-1]['export_name'] = 'Sword_Idle'
finished.append(bake('Sword_Overhead', source, [(gres_actions['SS_TH_Charge02_Start'],1,23),(gres_actions['SS_TH_Charge02_Heavy'],2,55)], mapping, scale, grip=True))
body_mesh = next(obj for obj in ranger_objects if obj.type == 'MESH' and obj.name == 'Male_Ranger_Body')
support_clearance = {
    'Sword_Idle': correct_support_arm(rig, body_mesh, finished[-2], socket_matrix, left_palm_local, set_rotation, solve_arm),
    'Sword_Overhead': correct_support_arm(rig, body_mesh, finished[-1], socket_matrix, left_palm_local, set_rotation, solve_arm),
}
socket = bpy.data.objects.new('SwordSocket', None)
bpy.context.collection.objects.link(socket)
socket.parent = rig
socket.parent_type = 'BONE'
socket.parent_bone = 'hand_r'
socket.matrix_parent_inverse = Matrix.Identity(4)
# glTF converts object local axes from Z-up to Y-up, but bone local axes are
# retained. Compensate here so the exported helper uses game-local -Z blade.
socket.matrix_basis = Matrix.Translation((0, -rig.data.bones['hand_r'].length, 0)) @ socket_matrix @ Matrix.Rotation(-math.pi / 2, 4, 'X')
ranger_objects.add(socket)
print('SWORD_SOCKET_HAND_LOCAL', [list(row) for row in socket_matrix])

# Remove sources and their animation tracks. Export only baked required actions.
for obj in list(bpy.data.objects):
    if obj not in ranger_objects:
        bpy.data.objects.remove(obj, do_unlink=True)
for action in list(bpy.data.actions):
    if action not in finished:
        bpy.data.actions.remove(action)
for action in finished:
    if 'export_name' in action:
        action.name = action['export_name']
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
rig.animation_data.action = None
for action in finished:
    track = rig.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, 0, action)
    track.mute = True

# Keep a practical embedded texture footprint, retaining source materials.
for image in bpy.data.images:
    if image.size[0] > 1024 or image.size[1] > 1024:
        ratio = 1024 / max(image.size)
        image.scale(round(image.size[0]*ratio), round(image.size[1]*ratio))
    if image.source == 'FILE':
        image.pack()
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format='GLB', export_animations=True, export_animation_mode='NLA_TRACKS', export_nla_strips=True, export_force_sampling=True, export_frame_range=False, export_yup=True, export_materials='EXPORT', export_image_format='AUTO', export_skins=True)
retime_cover_export(OUTPUT, {spec[0] for spec in cover_specs.values()})

# Read final GLB values rather than duplicating export name/time conventions.
raw = OUTPUT.read_bytes()
document = json.loads(raw[20:20 + struct.unpack_from('<I', raw, 12)[0]])
durations = {a['name']: max(document['accessors'][s['input']]['max'][0] for s in a['samplers']) for a in document['animations']}
socket_node = next(n for n in document['nodes'] if n.get('name') == 'SwordSocket')
palms = {}
for side, label in [('l', 'left'), ('r', 'right')]:
    knuckles = sum((rig.data.bones[f'{finger}_01_{side}'].head_local for finger in ['index', 'middle', 'ring', 'pinky']), Vector()) / 4
    centre = (knuckles + rig.data.bones['hand_' + side].head_local) / 2
    palms[label] = list(rest['hand_' + side].inverted() @ centre)
# Head is a neck-base joint, not the face centre. Anchor the drawing hand at the
# actual cheek surface, with room for the palm, instead of below the neck.
head_mesh = next(obj for obj in ranger_objects if obj.type == 'MESH' and obj.name == 'Ranger_Head_SuperHero_Male')
jaw_hint = Vector((-0.08, -0.07, 1.625))
jaw_surface = min((vertex.co for vertex in head_mesh.data.vertices), key=lambda point: (point - jaw_hint).length_squared).copy()
jaw_palm = jaw_surface + Vector((-0.03, 0.005, 0.0))
bow_anchor = list(rest['Head'].inverted() @ jaw_palm)
# All exported skinned meshes share the identity mesh transform. Measure their
# actual Y-up POSITION bounds, excluding removed source/preview objects.
position_bounds = [document['accessors'][primitive['attributes']['POSITION']] for mesh in document['meshes'] for primitive in mesh['primitives']]
rest_height = max(a['max'][1] for a in position_bounds) - min(a['min'][1] for a in position_bounds)
metadata = {
    'asset': OUTPUT.name,
    'skeleton': 'Armature/Skeleton3D',
    'bone_count': len(rig.data.bones),
    'forward': [0, 0, 1],
    'up': [0, 1, 0],
    'unit': 'metres',
    'rest_height': rest_height,
    'palms': palms,
    'palm_measurement': 'Midpoint of wrist and mean index/middle/ring/pinky proximal knuckles in bone-local coordinates',
    'bow_anchor': {'bone': 'Head', 'position': bow_anchor, 'measurement': 'Right cheek surface near the jaw, offset 30 mm outward for palm clearance'},
    'sword_grip': {'position': socket_node['translation'], 'rotation': socket_node['rotation']},
    'sword_axes': {'blade': [0, 0, -1], 'handle': [0, 0, 1], 'thickness': [0, 1, 0]},
    'clips': {
        'overhead': {'name': 'Sword_Overhead', 'duration': durations['Sword_Overhead'], 'strike_start': 41/60, 'strike_end': 56/60},
        'overhead_one_hand': {'name': 'Sword_Overhead_OneHand', 'duration': durations['Sword_Overhead_OneHand'], 'strike_start': 15/60, 'strike_end': 30/60},
        'crouch_idle': {'name': 'Crouch_Idle_Loop', 'duration': durations['Crouch_Idle_Loop'], 'loop': True, **crouch_measurements['Crouch_Idle_Loop']},
        'crouch_forward': {'name': 'Crouch_Fwd_Loop', 'duration': durations['Crouch_Fwd_Loop'], 'loop': True, **crouch_measurements['Crouch_Fwd_Loop']},
        **{key: {'name': name, 'duration': durations[name], 'loop': False, 'lean_direction': axis, 'torso_degrees': degrees, 'pelvis_counterbalance': 0.02, 'pelvis_lowering': 0.012} for key, (name, _, degrees, axis) in cover_specs.items()},
    },
    'animations': durations,
    'authoring_fps': FPS,
    'gres_height_scale': scale,
    'support_clearance': support_clearance,
    'cover_authoring': {
        'reference': 'Identical Idle_Loop frame 0 for all lean clips; additive world-space bone deltas',
        'axes': 'Asset Y-up/+Z-forward: left +X, right -X, top +Z; Blender (x,y,z) exports as (x,z,-y)',
        'rotation_axes': 'Left -Z, right +Z, top +X in asset space; pelvis -3 degrees, spine chain 50/80/100 percent of torso_degrees, neck -2 and head -5 degrees relative to chest',
        'contact': 'Fixed-length leg rotation solve keeps neutral ankles and foot orientation planted; arm-local transforms remain neutral',
        'timing': 'Smoothstep weight transfer, 16 samples from neutral to exposed; exported sample times uniformly retimed to 0.24 seconds without looping',
    },
}
# Store the editable prepared scene outside the repository for visual inspection.
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'prepared_ranger.blend'))
metadata['support_clearance_validation'] = validate_export(OUTPUT, metadata)
OUTPUT.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
print('OUTPUT', OUTPUT)
