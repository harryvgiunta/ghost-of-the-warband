"""Prepare the licensed Ranger and retarget selected authored character motions.
Run: blender --background --python tools/prepare_character.py -- SOURCE_DIR OUTPUT_GLB
SOURCE_DIR contains the unpacked Standard archives and Gres' original .blend;
see assets/characters/LICENSE.txt for acquisition URLs and original filenames.
No motion is generated: source poses are sampled and rest-axis retargeted.
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


set_action(ual, ual_actions['Sword_Idle'])
bpy.context.scene.frame_set(0)
authored_finger_grip = {bone.name: bone.rotation_quaternion.copy() for bone in ual.pose.bones if bone.name.endswith('_r') and bone.name.startswith(('index_', 'middle_', 'ring_', 'pinky_', 'thumb_'))}

identity = {b.name:b.name for b in rig.data.bones}
clips = ['Idle_Loop', 'Walk_Loop', 'Jog_Fwd_Loop', 'Sprint_Loop', 'Jump_Start', 'Jump_Loop', 'Jump_Land', 'Roll']
finished = []
for name in clips:
    source_action = ual_actions[name]
    # Imported glTF samples already use the scene's 60 fps timebase.
    finished.append(bake(name + '_prepared', ual, [(source_action, round(source_action.frame_range[0]), round(source_action.frame_range[1]))], identity, 1.0))
    finished[-1]['export_name'] = name

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
    },
    'animations': durations,
    'authoring_fps': FPS,
    'gres_height_scale': scale,
    'support_clearance': support_clearance,
}
# Store the editable prepared scene outside the repository for visual inspection.
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE / 'prepared_ranger.blend'))
metadata['support_clearance_validation'] = validate_export(OUTPUT, metadata)
OUTPUT.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
print('OUTPUT', OUTPUT)
