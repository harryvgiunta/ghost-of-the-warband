"""Author the twelve weapon-ability clips into the shipped Ranger GLB.

Run: blender --background --python tools/prepare_ability_animations.py

Append `-- norender` to skip the QA contact sheets (numeric diagnostics only).

The tool imports the game GLB, authors twelve 60 fps full-body actions with
per-bone keys, renders QA contact sheets with throw-away proxy weapons, then
exports a temporary GLB and merges ONLY the new clips into the original
document (tools/glb_animation_merge.py) so every existing node, skin, mesh and
animation stays byte-for-byte untouched.

Authoring conventions (identical to the shipped clips):
  armature space, metres, +X = character left, -Y = forward, +Z = up.
  Arm targets are absolute wrist positions; hand orientations are absolute.
  The sword/staff/dagger follow hand_r * sword_grip: the blade runs along the
  grip's local -Z, so a hand basis of aim_basis * inverse(sword_grip) puts the
  blade on the authored world direction. `aim_basis` is the same basis Godot's
  Basis.looking_at builds, and the JSON socket rotation is Godot's
  Quaternion(x, y, z, w) order, so it must be reordered for Blender.
"""
import json
import math
import subprocess
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from glb_animation_merge import clip_durations, merge_clips, read_glb  # noqa: E402

GLB = ROOT / 'assets' / 'characters' / 'ironwood_ranger.glb'
METADATA = GLB.with_suffix('.json')
TEMP = GLB.with_name('ironwood_ranger_ability_export.glb')
QA_DIR = ROOT / '.runtime' / 'ability_anim'
FPS = 60
RENDER_QA = 'norender' not in sys.argv
DEBUG_PULL = 'debugpull' in sys.argv
DIAG = {}

# --------------------------------------------------------------------------- #
# Import and helpers (same pattern as tools/prepare_consumables.py)
# --------------------------------------------------------------------------- #
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = FPS
bpy.ops.import_scene.gltf(filepath=str(GLB))
rig = next(obj for obj in set(bpy.data.objects) if obj.type == 'ARMATURE')
rig.name = 'Armature'


CLIPS = [
    ('Bow_Barrage', 1.15, None, 'bow'),
    ('Bow_Triple_Volley', 1.0, None, 'bow'),
    ('Bow_Piercing_Shot', 1.25, None, 'bow'),
    ('Sword_Double_Slash', 1.1, None, 'sword'),
    ('Sword_Lunge_Thrust', 1.0, None, 'sword'),
    ('Sword_Spin_Slash', 1.35, None, 'sword'),
    ('Dagger_Dash_Stab', 0.85, None, 'dagger'),
    ('Staff_Fireball_Cast', 1.2, None, 'staff'),
    ('Staff_Bone_Spear_Cast', 1.15, None, 'staff'),
    ('Shield_Bash', 0.8, None, 'shield'),
    ('Shield_Charge', 1.15, None, 'shield'),
    ('Shield_Ground_Slam', 1.1, None, 'shield'),
]
AUTHORED = {name for name, _s, _b, _k in CLIPS}

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


def ramp(t, start, end):
    if end <= start:
        return 1.0 if t >= end else 0.0
    return smooth((t - start) / (end - start))


def pulse(t, center, width):
    """Cosine bump: 1.0 at `center`, 0.0 outside +-width."""
    x = abs(t - center) / width
    return 0.0 if x >= 1.0 else 0.5 + 0.5 * math.cos(math.pi * x)


def envelope(t, ramp_in, ramp_out):
    return ramp(t, 0.0, ramp_in) * (1.0 - ramp(t, 1.0 - ramp_out, 1.0))


def track(t, keys):
    """Smoothstep interpolation through (time, float|Vector) key pairs."""
    if t <= keys[0][0]:
        return keys[0][1].copy() if isinstance(keys[0][1], Vector) else keys[0][1]
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t <= t1:
            u = smooth((t - t0) / (t1 - t0))
            if isinstance(v0, Vector):
                return v0.lerp(v1, u)
            return v0 + (v1 - v0) * u
    last = keys[-1][1]
    return last.copy() if isinstance(last, Vector) else last


def update():
    bpy.context.view_layer.update()


def set_rotation(name, rotation):
    bone = rig.pose.bones[name]
    parent = bone.parent
    origin = (parent.matrix @ parent.bone.matrix_local.inverted() @ bone.bone.matrix_local).translation if parent else bone.bone.matrix_local.translation
    desired = rotation.to_matrix().to_4x4()
    desired.translation = origin
    bone.matrix = desired
    update()


def spin(name, rx=0.0, ry=0.0, rz=0.0):
    """Rotate a posed bone in armature space about its head (degrees)."""
    bone = rig.pose.bones[name]
    rotation = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), 'XYZ').to_quaternion()
    set_rotation(name, rotation @ bone.matrix.to_quaternion())


def shift_bone(name, delta):
    bone = rig.pose.bones[name]
    matrix = bone.matrix.copy()
    matrix.translation += delta
    bone.matrix = matrix
    update()


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
    if hand_rotation is not None:
        set_rotation('hand_' + side, hand_rotation)
    return direction.length


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
    return direction.length


def key_all(action, frame):
    for bone in rig.pose.bones:
        bone.keyframe_insert('location', frame=frame, group=bone.name)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
        bone.keyframe_insert('scale', frame=frame, group=bone.name)


# --------------------------------------------------------------------------- #
# Weapon metadata and base pose
# --------------------------------------------------------------------------- #
metadata = json.loads(METADATA.read_text(encoding='utf-8'))
GRIP_POS = Vector(metadata['sword_grip']['position'])
# archer.gd builds the socket with Quaternion(r[0], r[1], r[2], r[3]), i.e.
# Godot's (x, y, z, w) order. mis-reading it as (w, x, y, z) rotates the whole
# grip by ~90 degrees and makes the runtime blade miss the authored aim.
_grip_x, _grip_y, _grip_z, _grip_w = metadata['sword_grip']['rotation']
GRIP_ROT = Quaternion((_grip_w, _grip_x, _grip_y, _grip_z)).normalized()
MIRROR = Matrix.Diagonal((-1.0, 1.0, 1.0)).to_4x4()
GRIP_ROT_LEFT = (MIRROR @ GRIP_ROT.to_matrix().to_4x4() @ MIRROR).to_quaternion()
PALM_L = Vector(metadata['palms']['left'])
PALM_R = Vector(metadata['palms']['right'])
# Support-hand grip depth along the weapon handle (archer.gd uses 0.32 for a
# staff and 0.05-0.20 for a sword). The authored depth slides toward the sword
# hand if the off arm cannot reach the authored point.

set_action(actions['Idle_Loop'])
scene.frame_set(0)
update()
base_basis = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
base_world_q = {bone.name: bone.matrix.to_quaternion() for bone in rig.pose.bones}
BASE_WRIST = {'l': rig.pose.bones['hand_l'].head.copy(), 'r': rig.pose.bones['hand_r'].head.copy()}
BASE_HAND_Q = dict(base_world_q)
BASE_ANKLE = {'l': rig.pose.bones['foot_l'].head.copy(), 'r': rig.pose.bones['foot_r'].head.copy()}
BASE_FOOT_Q = {'l': rig.pose.bones['foot_l'].matrix.to_quaternion(),
               'r': rig.pose.bones['foot_r'].matrix.to_quaternion()}
BASE_PELVIS = rig.pose.bones['pelvis'].head.copy()
ARM_REACH = (rig.pose.bones['upperarm_l'].bone.length + rig.pose.bones['lowerarm_l'].bone.length)
REACH_LIMIT = ARM_REACH * 0.95
print('BASE', {k: tuple(round(v, 3) for v in w) for k, w in BASE_WRIST.items()},
      {k: tuple(round(v, 3) for v in w) for k, w in BASE_ANKLE.items()})


def clamp_reach(target, shoulder, limit=REACH_LIMIT):
    """Pull an authored wrist target inside the arm's reach sphere."""
    offset = target - shoulder
    if offset.length > limit:
        return shoulder + offset.normalized() * limit, offset.length - limit
    return target, 0.0


def reset_base():
    for bone in rig.pose.bones:
        bone.matrix_basis = base_basis[bone.name]
    update()


def aim_quat(direction, flat_up=Vector((0.0, 0.0, 1.0))):
    """Rotation mapping local -Z onto `direction`, local +Y toward `flat_up`."""
    z = -Vector(direction).normalized()
    y = Vector(flat_up) - z * Vector(flat_up).dot(z)
    if y.length < 1e-4:
        fallback = Vector((0.0, 1.0, 0.0)) if abs(z.y) < 0.9 else Vector((1.0, 0.0, 0.0))
        y = fallback - z * fallback.dot(z)
    y.normalize()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed().to_4x4().to_quaternion()


def hand_for_direction(direction, flat_up=Vector((0.0, 0.0, 1.0))):
    """hand_r basis that puts hand_r * sword_grip's -Z on `direction`."""
    return aim_quat(direction, flat_up) @ GRIP_ROT.inverted()


def grip_frame(wrist, hand_q):
    """(grip origin, world grip rotation) for a hand pose."""
    return wrist + hand_q @ GRIP_POS, hand_q @ GRIP_ROT


def support_wrist(origin, handle_q, depth):
    """Wrist target that puts the left palm `depth` along the handle (+Z)."""
    support_q = handle_q @ GRIP_ROT_LEFT.inverted()
    handle_dir = handle_q @ Vector((0.0, 0.0, 1.0))
    return origin + handle_dir * depth - support_q @ PALM_L, support_q


# --------------------------------------------------------------------------- #
# Pose application
# --------------------------------------------------------------------------- #
def pose(**kw):
    value = dict(weight=1.0, drop=0.0, shift=(0.0, 0.0, 0.0), yaw=0.0, lean=0.0, side=0.0,
                 twist=0.0, head_pitch=0.0, head_yaw=0.0,
                 ankle_l=None, ankle_r=None, foot_yaw_l=0.0, foot_yaw_r=0.0,
                 wrist_r=None, handq_r=None, wrist_l=None, handq_l=None,
                 support=None, elbow_r=None, elbow_l=None, cue=False)
    value.update(kw)
    return value


def apply_pose(spec):
    w = spec['weight']
    name = spec.get('_clip', '')
    reset_base()
    if w <= 0.0001:
        return
    yaw, lean, side, twist = (spec['yaw'] * w, spec['lean'] * w, spec['side'] * w, spec['twist'] * w)
    spin('pelvis', lean * 0.25, side * 0.20, yaw * 0.40)
    shift_bone('pelvis', Vector(spec['shift']) * w + Vector((0.0, 0.0, -spec['drop'] * w)))
    for bone, factor in (('spine_01', 0.32), ('spine_02', 0.50), ('spine_03', 0.70)):
        spin(bone, lean * factor, side * factor, (yaw * 0.60 + twist) * factor)
    spin('neck_01', spec['head_pitch'] * w * 0.40, 0.0, spec['head_yaw'] * w * 0.35)
    spin('Head', spec['head_pitch'] * w * 0.60, 0.0, spec['head_yaw'] * w * 0.65)

    stats = DIAG.setdefault(name, dict(clamp_r=0.0, clamp_l=0.0, grip_gap=0.0, pull=0.0))
    # Legs: absolute ankle targets, knees re-solved forward.
    for side_name in ('l', 'r'):
        target = spec['ankle_' + side_name]
        base_ankle = BASE_ANKLE[side_name]
        ankle = base_ankle if target is None else base_ankle.lerp(target, w)
        hint = ankle + Vector((0.0, -0.75, 0.28))
        foot_q = Quaternion((0.0, 0.0, 1.0), math.radians(spec['foot_yaw_' + side_name] * w)) @ BASE_FOOT_Q[side_name]
        solve_leg(side_name, ankle, hint, foot_q)

    shoulder_r = rig.pose.bones['upperarm_r'].head.copy()
    shoulder_l = rig.pose.bones['upperarm_l'].head.copy()
    # Right arm (weapon hand), clamped into the arm's real reach.
    wrist_r = BASE_WRIST['r'] if spec['wrist_r'] is None else BASE_WRIST['r'].lerp(spec['wrist_r'], w)
    hand_q_r = BASE_HAND_Q['hand_r'] if spec['handq_r'] is None else BASE_HAND_Q['hand_r'].slerp(spec['handq_r'], w)
    hint_r = spec['elbow_r'] or (shoulder_r + Vector((-0.34, 0.16, -0.26)))
    wrist_r, correction = clamp_reach(wrist_r, shoulder_r)
    stats['clamp_r'] = max(stats['clamp_r'], correction)
    support = spec['support']
    if support is not None and w > 0.97:
        # Keep the shared hilt inside the support arm's reach before solving,
        # otherwise the off hand visibly floats off the grip. The support hand
        # is only authored onto the grip at full blend weight; earlier frames
        # are a blended transit, so moving the weapon hand there would fight
        # the blend instead of helping it. Steps are capped so a pose can never
        # be dragged across the chest.
        for _iteration in range(4):
            origin, handle_q = grip_frame(wrist_r, hand_q_r)
            predicted, _q = support_wrist(origin, handle_q, support['depth'])
            excess = (predicted - shoulder_l).length - REACH_LIMIT
            if excess <= 0.0:
                break
            if DEBUG_PULL and excess > 0.02:
                print('PULL', name, round(w, 2), round(excess, 3),
                      tuple(round(v, 2) for v in wrist_r), tuple(round(v, 2) for v in predicted),
                      tuple(round(v, 2) for v in shoulder_l))
            wrist_r = wrist_r + (shoulder_l - predicted).normalized() * min(excess, 0.05)
            wrist_r, correction = clamp_reach(wrist_r, shoulder_r)
            stats['pull'] = max(stats['pull'], excess)
            stats['clamp_r'] = max(stats['clamp_r'], correction)
    solve_arm('r', wrist_r, hint_r, hand_q_r)
    if support is not None and spec.get('cue') and w > 0.5:
        hand_r_matrix = rig.pose.bones['hand_r'].matrix
        handle_q = hand_r_matrix.to_quaternion() @ GRIP_ROT
        head = hand_r_matrix @ GRIP_POS + handle_q @ Vector((0.0, 0.0, -0.70))
        far = hand_r_matrix @ GRIP_POS + handle_q @ Vector((0.0, 0.0, -1.55))
        print('STAFF_AIM', round(spec['_t'], 3), 'authoredD',
              tuple(round(v, 2) for v in ((spec['handq_r'] @ GRIP_ROT) @ Vector((0, 0, -1)))),
              'actualD',
              tuple(round(v, 2) for v in ((hand_r_matrix.to_quaternion() @ GRIP_ROT) @ Vector((0, 0, -1)))),
              'wrist', tuple(round(v, 2) for v in wrist_r))
        stats['cue_head'] = (round(spec['_t'], 2), tuple(round(v, 2) for v in head),
                             round(head.z, 3), tuple(round(v, 2) for v in far))

    # Left arm: explicit target or the weapon support grip.
    hint_l = spec['elbow_l'] or (shoulder_l + Vector((0.36, 0.10, -0.22)))
    if support is not None:
        hand_r_matrix = rig.pose.bones['hand_r'].matrix
        origin = hand_r_matrix @ GRIP_POS
        handle_q = hand_r_matrix.to_quaternion() @ GRIP_ROT
        depth = support['depth']
        target, support_q = support_wrist(origin, handle_q, depth)
        wrist_l, correction = clamp_reach(target, shoulder_l)
        # Slide the off hand along the hilt/shaft instead of letting it float:
        # every step keeps the palm on the handle, just nearer the sword hand.
        while correction > 0.004 and depth > 0.045:
            depth = max(0.045, depth - 0.02)
            target, support_q = support_wrist(origin, handle_q, depth)
            wrist_l, correction = clamp_reach(target, shoulder_l)
        stats['slide'] = min(stats.get('slide', 1.0), depth / support['depth'])
        if w > 0.9 and correction > stats['grip_gap']:
            stats['grip_gap'] = correction
            stats['gap_detail'] = (round(spec.get('_t', -1.0), 3),
                                   tuple(round(v, 2) for v in target),
                                   tuple(round(v, 2) for v in shoulder_l))
        wrist_l = BASE_WRIST['l'].lerp(wrist_l, w)
        hand_q_l = BASE_HAND_Q['hand_l'].slerp(support_q, w)
        solve_arm('l', wrist_l, hint_l, hand_q_l)
    else:
        wrist_l = BASE_WRIST['l'] if spec['wrist_l'] is None else BASE_WRIST['l'].lerp(spec['wrist_l'], w)
        hand_q_l = BASE_HAND_Q['hand_l'] if spec['handq_l'] is None else BASE_HAND_Q['hand_l'].slerp(spec['handq_l'], w)
        wrist_l, correction = clamp_reach(wrist_l, shoulder_l)
        stats['clamp_l'] = max(stats['clamp_l'], correction)
        solve_arm('l', wrist_l, hint_l, hand_q_l)


# --------------------------------------------------------------------------- #
# Shared targets
# --------------------------------------------------------------------------- #
BOW_WRIST_L = Vector((0.155, -0.405, 1.375))
BOW_ELBOW_L = Vector((0.36, -0.18, 1.22))
DRAW_WRIST = Vector((-0.075, -0.105, 1.565))
DRAW_ELBOW = Vector((-0.42, 0.14, 1.62))
ARCHER_L = BASE_ANKLE['l'] + Vector((0.030, -0.010, 0.0))
ARCHER_R = BASE_ANKLE['r'] + Vector((-0.040, 0.020, 0.0))
STAFF_SUPPORT = dict(depth=0.30)
SWORD_SUPPORT = dict(depth=0.13)


def bow_stance(p, hit=0.0):
    p['ankle_l'] = ARCHER_L
    p['ankle_r'] = ARCHER_R
    p['drop'] = 0.032 + 0.012 * hit
    p['yaw'] = -13.0 + 2.5 * hit
    p['lean'] = 4.0 + 2.0 * hit
    p['twist'] = 2.0 * hit
    p['head_yaw'] = 11.0
    p['head_pitch'] = -2.0 - 1.5 * hit
    p['shift'] = (0.0, 0.014 * hit, 0.0)
    p['wrist_l'] = BOW_WRIST_L + Vector((0.0, 0.010 * hit, 0.008 * hit))
    p['elbow_l'] = BOW_ELBOW_L


# --- Bow clips ------------------------------------------------------------- #
def build_barrage(t):
    seconds = 1.15
    releases = [0.22, 0.34, 0.46, 0.58, 0.70, 0.82]
    p = pose(weight=envelope(t, 0.13, 0.19))
    hit = sum(pulse(t, r / seconds, 0.080) for r in releases)
    snap = sum(pulse(t, r / seconds, 0.028) for r in releases)
    bow_stance(p, hit)
    p['wrist_r'] = DRAW_WRIST + Vector((0.018, 0.040, -0.050)) * snap
    p['elbow_r'] = DRAW_ELBOW
    p['ankle_l'] = ARCHER_L + Vector((0.0, -0.008 * hit, 0.0))
    return p


def build_volley(t):
    p = pose(weight=envelope(t, 0.15, 0.20))
    start = Vector((0.030, -0.300, 1.480))
    draw = ramp(t, 0.10, 0.455)
    release = ramp(t, 0.48, 0.60)
    bow_stance(p, 0.7 * release)
    p['drop'] += 0.018 * draw
    p['lean'] += -3.0 * draw + 4.0 * release
    p['yaw'] += -3.0 * draw + 2.0 * release
    p['shift'] = (0.0, 0.020 * draw - 0.010 * release, 0.0)
    p['wrist_r'] = start.lerp(DRAW_WRIST, draw) + Vector((0.02, 0.045, -0.05)) * release
    p['elbow_r'] = DRAW_ELBOW
    p['wrist_l'] = BOW_WRIST_L + Vector((0.0, -0.012 * release, 0.012 * release))
    return p


def build_piercing(t):
    p = pose(weight=envelope(t, 0.14, 0.18))
    start = Vector((0.020, -0.320, 1.470))
    draw = ramp(t, 0.10, 0.555)
    release = ramp(t, 0.576, 0.655)
    settle = ramp(t, 0.655, 0.760)
    pull = draw * (1.0 - 0.35 * settle)
    bow_stance(p, 0.55 * release)
    p['drop'] += 0.030 * draw + 0.020 * release
    p['lean'] += -5.0 * draw + 9.0 * release - 2.0 * settle
    p['yaw'] += -6.0 * draw + 3.0 * release
    p['shift'] = (0.0, 0.030 * draw - 0.030 * release, 0.0)
    heavy = Vector((-0.125, 0.045, 1.520))
    p['wrist_r'] = start.lerp(heavy, pull) + Vector((0.02, 0.055, -0.05)) * release
    p['elbow_r'] = DRAW_ELBOW + Vector((0.0, 0.06, 0.02)) * pull
    p['wrist_l'] = BOW_WRIST_L + Vector((0.0, -0.020 * release, 0.015 * release))
    p['ankle_l'] = ARCHER_L + Vector((0.0, -0.020 * draw, 0.0))
    return p


# --- Sword clips ----------------------------------------------------------- #
# Two-handed poses keep the shared hilt inside BOTH arms' reach spheres, which
# for this rig means a box roughly x -0.22..0.10, y -0.31..0.06, z 1.08..1.60.
# The blade does the reaching; the hands stay near the chest.
def build_double_slash(t):
    p = pose(weight=envelope(t, 0.10, 0.16))
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.10, Vector((-0.160, 0.020, 1.500))),
        (0.22, Vector((-0.180, 0.060, 1.540))),
        (0.40, Vector((0.020, -0.240, 1.160))),
        (0.48, Vector((0.060, -0.180, 1.100))),
        (0.60, Vector((-0.020, -0.220, 1.380))),
        (0.80, Vector((-0.220, -0.160, 1.280))),
        (0.90, Vector((-0.220, -0.100, 1.240))),
        (1.00, BASE_WRIST['r']),
    ])
    blade = track(t, [
        (0.00, Vector((0.10, 0.30, 0.95))),
        (0.10, Vector((-0.42, 0.34, 0.84))),
        (0.22, Vector((-0.50, 0.40, 0.77))),
        (0.40, Vector((0.62, -0.55, -0.56))),
        (0.48, Vector((0.80, -0.35, -0.48))),
        (0.60, Vector((0.90, -0.35, 0.10))),
        (0.80, Vector((-0.88, -0.40, 0.15))),
        (0.90, Vector((-0.70, -0.50, 0.42))),
        (1.00, Vector((0.10, 0.30, 0.95))),
    ])
    p['handq_r'] = hand_for_direction(blade)
    p['support'] = SWORD_SUPPORT
    p['elbow_l'] = Vector((0.34, 0.06, 1.24))
    p['elbow_r'] = Vector((-0.40, 0.10, 1.34))
    p['yaw'] = track(t, [(0.00, 0.0), (0.10, -18.0), (0.22, -25.0), (0.40, 16.0), (0.48, 24.0),
                         (0.60, 20.0), (0.80, -26.0), (0.90, -16.0), (1.00, 0.0)])
    p['lean'] = track(t, [(0.00, 0.0), (0.10, -4.0), (0.22, -5.0), (0.40, 13.0), (0.48, 15.0),
                          (0.60, 5.0), (0.80, 14.0), (0.90, 7.0), (1.00, 0.0)])
    p['drop'] = track(t, [(0.00, 0.0), (0.22, 0.025), (0.40, 0.075), (0.48, 0.085),
                          (0.60, 0.045), (0.80, 0.075), (0.90, 0.040), (1.00, 0.0)])
    p['shift'] = (0.0, track(t, [(0.0, 0.0), (0.22, 0.025), (0.40, -0.045), (0.60, 0.0),
                                 (0.80, -0.050), (1.0, 0.0)]), 0.0)
    p['head_yaw'] = -0.30 * p['yaw']
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.020, -0.040, 0.0))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((-0.030, 0.030, 0.0))
    return p


def build_lunge_thrust(t):
    p = pose(weight=envelope(t, 0.10, 0.18))
    step = track(t, [(0.00, 0.0), (0.18, 0.0), (0.30, 0.55), (0.44, 1.0), (0.62, 1.0),
                     (0.84, 0.0), (1.00, 0.0)])
    lift = track(t, [(0.00, 0.0), (0.20, 0.0), (0.30, 0.06), (0.42, 0.0), (0.78, 0.0),
                     (0.86, 0.05), (0.94, 0.0), (1.00, 0.0)])
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.12, Vector((-0.200, -0.010, 1.240))),
        (0.28, Vector((-0.220, 0.030, 1.200))),
        (0.44, Vector((0.000, -0.300, 1.320))),
        (0.56, Vector((0.000, -0.310, 1.320))),
        (0.70, Vector((-0.120, -0.180, 1.260))),
        (1.00, BASE_WRIST['r']),
    ])
    blade = track(t, [
        (0.00, Vector((0.10, 0.30, 0.95))),
        (0.12, Vector((0.06, -0.95, 0.30))),
        (0.28, Vector((0.08, -0.99, 0.10))),
        (0.44, Vector((0.01, -1.00, 0.04))),
        (0.56, Vector((0.01, -0.99, 0.10))),
        (0.70, Vector((0.06, -0.95, 0.30))),
        (1.00, Vector((0.10, 0.30, 0.95))),
    ])
    p['handq_r'] = hand_for_direction(blade)
    p['support'] = SWORD_SUPPORT
    p['elbow_l'] = Vector((0.34, 0.02, 1.28))
    p['elbow_r'] = Vector((-0.38, 0.16, 1.30))
    p['yaw'] = track(t, [(0.00, 0.0), (0.12, -10.0), (0.28, -14.0), (0.44, -2.0), (0.56, -1.0),
                         (0.72, -7.0), (1.00, 0.0)])
    p['lean'] = track(t, [(0.00, 0.0), (0.12, -3.0), (0.28, 3.0), (0.44, 16.0), (0.56, 17.0),
                          (0.72, 8.0), (1.00, 0.0)])
    p['drop'] = track(t, [(0.00, 0.0), (0.28, 0.030), (0.44, 0.120), (0.60, 0.125),
                          (0.78, 0.045), (1.00, 0.0)])
    p['shift'] = (0.0, track(t, [(0.0, 0.0), (0.28, 0.020), (0.44, -0.165), (0.62, -0.150),
                                 (0.82, 0.0), (1.0, 0.0)]), 0.0)
    p['head_yaw'] = -0.25 * p['yaw']
    p['head_pitch'] = track(t, [(0.0, 0.0), (0.26, 3.0), (0.46, -6.0), (0.74, -2.0), (1.0, 0.0)])
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.020, -0.360 * step, lift))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((-0.020, 0.0, 0.0))
    p['foot_yaw_r'] = -12.0 * step
    return p


def build_spin_slash(t):
    p = pose(weight=envelope(t, 0.12, 0.20))
    sink = track(t, [(0.00, 0.0), (0.18, 0.85), (0.34, 1.0), (0.78, 1.0), (0.92, 0.5), (1.00, 0.0)])
    angle = track(t, [(0.00, -10.0), (0.18, -78.0), (0.36, -46.0), (0.52, 6.0),
                      (0.68, 46.0), (0.80, 78.0), (0.90, 44.0), (1.00, -10.0)])
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.18, Vector((-0.200, -0.040, 1.340))),
        (0.36, Vector((-0.160, -0.180, 1.280))),
        (0.52, Vector((0.000, -0.280, 1.240))),
        (0.68, Vector((0.080, -0.240, 1.220))),
        (0.80, Vector((0.100, -0.140, 1.200))),
        (0.90, Vector((0.020, -0.060, 1.240))),
        (1.00, BASE_WRIST['r']),
    ])
    blade = Vector((math.sin(math.radians(angle)), -math.cos(math.radians(angle)), 0.030)).normalized()
    p['handq_r'] = hand_for_direction(blade)
    p['support'] = SWORD_SUPPORT
    p['elbow_l'] = Vector((0.34, 0.02, 1.22))
    p['elbow_r'] = Vector((-0.38, 0.12, 1.26))
    p['drop'] = 0.105 * sink
    p['yaw'] = 0.36 * angle
    p['lean'] = 7.0 * sink
    p['side'] = -2.5 * sink
    p['shift'] = (0.070 * math.sin(math.radians(angle)), 0.0, 0.0)
    p['head_yaw'] = -0.45 * p['yaw']
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.085 * sink, -0.050 * sink, 0.0))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((-0.085 * sink, 0.025 * sink, 0.0))
    p['foot_yaw_r'] = -20.0 * sink
    return p


# --- Dagger ---------------------------------------------------------------- #
def build_dash_stab(t):
    p = pose(weight=envelope(t, 0.10, 0.17))
    step = track(t, [(0.00, 0.0), (0.16, 0.0), (0.28, 0.6), (0.40, 1.0), (0.60, 1.0),
                     (0.82, 0.0), (1.00, 0.0)])
    lift = track(t, [(0.00, 0.0), (0.20, 0.0), (0.28, 0.055), (0.38, 0.0), (0.80, 0.0),
                     (0.88, 0.045), (0.96, 0.0), (1.00, 0.0)])
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.14, Vector((-0.255, 0.045, 1.205))),
        (0.26, Vector((-0.235, 0.110, 1.190))),
        (0.40, Vector((-0.075, -0.320, 1.245))),
        (0.54, Vector((-0.080, -0.340, 1.230))),
        (0.70, Vector((-0.205, -0.150, 1.160))),
        (1.00, BASE_WRIST['r']),
    ])
    blade = track(t, [
        (0.00, Vector((0.10, 0.30, 0.95))),
        (0.14, Vector((0.08, -0.96, 0.26))),
        (0.26, Vector((0.10, -0.99, 0.05))),
        (0.40, Vector((0.03, -1.00, 0.00))),
        (0.54, Vector((0.03, -0.99, 0.06))),
        (0.70, Vector((0.08, -0.96, 0.24))),
        (1.00, Vector((0.10, 0.30, 0.95))),
    ])
    p['handq_r'] = hand_for_direction(blade)
    p['wrist_l'] = track(t, [
        (0.00, BASE_WRIST['l']),
        (0.30, Vector((0.395, 0.075, 1.245))),
        (0.60, Vector((0.375, 0.110, 1.220))),
        (1.00, BASE_WRIST['l']),
    ])
    p['elbow_l'] = Vector((0.52, 0.16, 1.24))
    p['elbow_r'] = Vector((-0.40, 0.18, 1.30))
    p['yaw'] = track(t, [(0.00, 0.0), (0.14, -6.0), (0.26, -14.0), (0.40, -6.0), (0.56, -4.0),
                         (0.74, -8.0), (1.00, 0.0)])
    p['lean'] = track(t, [(0.00, 0.0), (0.14, 3.0), (0.26, 1.0), (0.40, 16.0), (0.54, 17.0),
                          (0.72, 6.0), (1.00, 0.0)])
    p['drop'] = track(t, [(0.00, 0.0), (0.26, 0.045), (0.40, 0.090), (0.56, 0.085),
                          (0.76, 0.030), (1.00, 0.0)])
    p['shift'] = (0.0, track(t, [(0.0, 0.0), (0.26, 0.020), (0.40, -0.125), (0.62, -0.100),
                                 (0.84, 0.0), (1.0, 0.0)]), 0.0)
    p['head_pitch'] = track(t, [(0.0, 0.0), (0.26, 3.0), (0.42, -6.0), (0.72, -1.0), (1.0, 0.0)])
    p['head_yaw'] = -0.35 * p['yaw']
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.010, -0.300 * step, lift))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((0.0, 0.030 * step, 0.0))
    return p


# --- Staff ----------------------------------------------------------------- #
# The staff socket puts its head only 0.55 m along local -Z from the grip
# (archer.gd offsets the mesh by length/2 + 0.25), so a cast reads as the ember
# head being thrust forward at shoulder height, not as a long polearm swing.
def build_fireball(t):
    p = pose(weight=envelope(t, 0.12, 0.18))
    # The ember head lifts the staff head to ~1.9 m with the butt swung behind
    # the body; a vertical shaft would stand in front of the face and run its
    # butt through the shins.
    direction = track(t, [
        (0.00, Vector((0.10, 0.30, 0.95))),
        (0.14, Vector((0.10, -0.32, 0.94))),
        (0.28, Vector((0.06, -0.55, 0.83))),
        (0.417, Vector((0.04, -0.90, 0.44))),
        (0.483, Vector((0.04, -0.92, 0.39))),
        (0.60, Vector((0.08, -0.82, 0.57))),
        (0.717, Vector((0.10, -0.55, 0.83))),
        (0.86, Vector((0.10, -0.30, 0.95))),
        (1.00, Vector((0.10, 0.30, 0.95))),
    ])
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.14, Vector((0.030, -0.160, 1.430))),
        (0.28, Vector((0.020, -0.200, 1.420))),
        (0.417, Vector((0.000, -0.280, 1.390))),
        (0.483, Vector((0.000, -0.300, 1.380))),
        (0.60, Vector((0.020, -0.240, 1.360))),
        (0.717, Vector((0.030, -0.180, 1.380))),
        (0.86, Vector((0.030, -0.140, 1.400))),
        (1.00, BASE_WRIST['r']),
    ])
    p['handq_r'] = hand_for_direction(direction)
    p['support'] = STAFF_SUPPORT
    p['cue'] = abs(t - 0.417) < 0.009
    p['elbow_l'] = Vector((0.34, 0.02, 1.16))
    p['elbow_r'] = Vector((-0.38, 0.14, 1.30))
    p['yaw'] = track(t, [(0.00, 0.0), (0.16, 7.0), (0.34, 9.0), (0.50, -6.0), (0.62, -7.0),
                         (0.78, 0.0), (1.00, 0.0)])
    p['lean'] = track(t, [(0.00, 0.0), (0.14, -5.0), (0.30, -6.0), (0.417, 8.0), (0.50, 9.0),
                          (0.64, -3.0), (0.80, -4.0), (1.00, 0.0)])
    p['drop'] = track(t, [(0.00, 0.0), (0.14, 0.010), (0.30, 0.015), (0.417, 0.060), (0.52, 0.065),
                          (0.72, 0.035), (1.00, 0.0)])
    p['shift'] = (0.0, track(t, [(0.0, 0.0), (0.30, 0.025), (0.46, -0.055), (0.72, 0.0), (1.0, 0.0)]), 0.0)
    p['head_pitch'] = track(t, [(0.0, 0.0), (0.20, -7.0), (0.34, -8.0), (0.46, 3.0), (0.66, -3.0), (1.0, 0.0)])
    p['head_yaw'] = -0.40 * p['yaw']
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.020, -0.050, 0.0))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((-0.020, 0.020, 0.0))
    return p


def build_bone_spear(t):
    p = pose(weight=envelope(t, 0.13, 0.20))
    direction = track(t, [
        (0.00, Vector((0.10, 0.30, 0.95))),
        (0.18, Vector((-0.14, -0.26, 0.95))),
        (0.32, Vector((-0.10, -0.18, 0.98))),
        (0.40, Vector((0.06, -0.90, 0.43))),
        (0.47, Vector((0.06, -0.92, 0.39))),
        (0.574, Vector((0.08, -0.86, 0.50))),
        (0.696, Vector((0.10, -0.62, 0.78))),
        (0.80, Vector((0.12, -0.40, 0.91))),
        (1.00, Vector((0.10, 0.30, 0.95))),
    ])
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.18, Vector((-0.070, -0.120, 1.420))),
        (0.32, Vector((-0.060, -0.150, 1.440))),
        (0.40, Vector((0.000, -0.290, 1.380))),
        (0.47, Vector((0.000, -0.300, 1.370))),
        (0.574, Vector((0.010, -0.260, 1.360))),
        (0.696, Vector((0.020, -0.210, 1.380))),
        (0.80, Vector((0.030, -0.170, 1.400))),
        (1.00, BASE_WRIST['r']),
    ])
    p['handq_r'] = hand_for_direction(direction)
    p['support'] = STAFF_SUPPORT
    p['cue'] = abs(t - 0.40) < 0.009
    p['elbow_l'] = Vector((0.34, 0.04, 1.18))
    p['elbow_r'] = Vector((-0.36, 0.18, 1.34))
    p['yaw'] = track(t, [(0.00, 0.0), (0.18, -12.0), (0.32, -14.0), (0.40, 3.0), (0.56, 5.0),
                         (0.80, -2.0), (1.00, 0.0)])
    p['lean'] = track(t, [(0.00, 0.0), (0.18, -6.0), (0.32, -8.0), (0.40, 13.0), (0.50, 14.0),
                          (0.70, 2.0), (0.86, -3.0), (1.00, 0.0)])
    p['drop'] = track(t, [(0.00, 0.0), (0.18, 0.015), (0.32, 0.025), (0.40, 0.080), (0.54, 0.085),
                          (0.80, 0.030), (1.00, 0.0)])
    p['shift'] = (0.0, track(t, [(0.0, 0.0), (0.32, 0.030), (0.48, -0.070), (0.80, 0.0), (1.0, 0.0)]), 0.0)
    p['head_pitch'] = track(t, [(0.0, 0.0), (0.22, -8.0), (0.36, -9.0), (0.50, 4.0), (0.78, -2.0), (1.0, 0.0)])
    p['head_yaw'] = -0.35 * p['yaw']
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.020, -0.060, 0.0))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((-0.025, 0.025, 0.0))
    return p


# --- Shield ---------------------------------------------------------------- #
# The shield rides the left forearm, and its face points forward when that
# forearm lies ACROSS the chest. Every shield pose therefore keeps the wrist
# out to the character's left and the elbow tucked in: the bash drives the
# whole body forward behind an already forward-facing shield.
SHIELD_ELBOW = Vector((0.03, -0.02, 1.12))


def shield_arm(p, wrist, elbow=SHIELD_ELBOW):
    p['wrist_l'] = wrist
    p['elbow_l'] = elbow


def build_shield_bash(t):
    p = pose(weight=envelope(t, 0.09, 0.17))
    step = track(t, [(0.00, 0.0), (0.16, 0.0), (0.26, 0.6), (0.36, 1.0), (0.56, 1.0),
                     (0.80, 0.0), (1.00, 0.0)])
    lift = track(t, [(0.00, 0.0), (0.18, 0.0), (0.26, 0.04), (0.34, 0.0), (0.80, 0.0), (1.00, 0.0)])
    shield_arm(p, track(t, [
        (0.00, BASE_WRIST['l']),
        (0.16, Vector((0.262, 0.030, 1.335))),
        (0.24, Vector((0.268, 0.050, 1.330))),
        (0.34, Vector((0.300, -0.200, 1.300))),
        (0.46, Vector((0.300, -0.180, 1.300))),
        (0.62, Vector((0.272, -0.090, 1.315))),
        (1.00, BASE_WRIST['l']),
    ]))
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.18, Vector((-0.300, 0.070, 1.150))),
        (0.34, Vector((-0.330, 0.120, 1.120))),
        (0.50, Vector((-0.300, 0.080, 1.140))),
        (1.00, BASE_WRIST['r']),
    ])
    p['yaw'] = track(t, [(0.00, 0.0), (0.16, 10.0), (0.24, 11.0), (0.36, -6.0), (0.48, -5.0),
                         (0.66, 0.0), (1.00, 0.0)])
    p['lean'] = track(t, [(0.00, 0.0), (0.16, -2.0), (0.36, 15.0), (0.48, 14.0), (0.70, 3.0), (1.00, 0.0)])
    p['drop'] = track(t, [(0.00, 0.0), (0.16, 0.020), (0.36, 0.075), (0.52, 0.065), (0.78, 0.020), (1.00, 0.0)])
    p['shift'] = (0.0, track(t, [(0.0, 0.0), (0.20, 0.030), (0.36, -0.150), (0.58, -0.110), (0.86, 0.0), (1.0, 0.0)]), 0.0)
    p['head_yaw'] = -0.30 * p['yaw']
    p['head_pitch'] = track(t, [(0.0, 0.0), (0.20, -2.0), (0.40, 4.0), (0.70, 0.0), (1.0, 0.0)])
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.010, -0.190 * step, lift))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((-0.020, 0.030 * step, 0.0))
    return p


def build_shield_charge(t):
    p = pose(weight=envelope(t, 0.12, 0.18))
    drive = track(t, [(0.00, 0.0), (0.18, 0.55), (0.42, 1.0), (0.72, 1.0), (0.9, 0.4), (1.00, 0.0)])
    lead = track(t, [(0.00, 0.0), (0.14, 0.0), (0.30, 0.75), (0.44, 1.0), (0.76, 1.0),
                     (0.92, 0.0), (1.00, 0.0)])
    trail = track(t, [(0.00, 0.0), (0.36, 0.0), (0.56, 0.8), (0.72, 1.0), (0.88, 0.0), (1.00, 0.0)])
    lead_lift = track(t, [(0.00, 0.0), (0.16, 0.0), (0.26, 0.06), (0.36, 0.0), (0.90, 0.0), (1.00, 0.0)])
    trail_lift = track(t, [(0.00, 0.0), (0.46, 0.0), (0.56, 0.06), (0.66, 0.0), (1.00, 0.0)])
    shield_arm(p, track(t, [
        (0.00, BASE_WRIST['l']),
        (0.20, Vector((0.275, -0.120, 1.375))),
        (0.40, Vector((0.292, -0.235, 1.360))),
        (0.66, Vector((0.288, -0.245, 1.350))),
        (0.84, Vector((0.268, -0.150, 1.330))),
        (1.00, BASE_WRIST['l']),
    ]))
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.22, Vector((-0.300, 0.150, 1.130))),
        (0.56, Vector((-0.330, 0.195, 1.100))),
        (0.80, Vector((-0.300, 0.120, 1.160))),
        (1.00, BASE_WRIST['r']),
    ])
    p['yaw'] = 5.0 * drive
    p['lean'] = 17.0 * drive
    p['drop'] = 0.085 * drive
    p['shift'] = (0.0, -0.120 * drive, 0.0)
    p['head_yaw'] = -4.0 * drive
    p['head_pitch'] = -7.0 * drive
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.010, -0.300 * lead, lead_lift))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((0.0, -0.180 * trail, trail_lift))
    p['foot_yaw_l'] = 6.0 * drive
    return p


def build_shield_slam(t):
    p = pose(weight=envelope(t, 0.11, 0.19))
    slam = track(t, [(0.00, 0.0), (0.42, 0.0), (0.52, 1.0), (0.66, 1.0), (0.86, 0.25), (1.00, 0.0)])
    shield_arm(p, track(t, [
        (0.00, BASE_WRIST['l']),
        (0.18, Vector((0.280, -0.160, 1.600))),
        (0.34, Vector((0.262, -0.180, 1.690))),
        (0.46, Vector((0.300, -0.240, 1.200))),
        (0.56, Vector((0.320, -0.220, 0.820))),
        (0.68, Vector((0.318, -0.210, 0.805))),
        (0.82, Vector((0.280, -0.190, 1.020))),
        (1.00, BASE_WRIST['l']),
    ]), Vector((0.06, -0.04, 1.10)))
    p['wrist_r'] = track(t, [
        (0.00, BASE_WRIST['r']),
        (0.24, Vector((-0.235, -0.180, 1.420))),
        (0.36, Vector((-0.245, -0.220, 1.520))),
        (0.54, Vector((-0.310, 0.060, 1.020))),
        (0.68, Vector((-0.320, 0.090, 1.000))),
        (0.86, Vector((-0.300, 0.120, 1.120))),
        (1.00, BASE_WRIST['r']),
    ])
    p['yaw'] = track(t, [(0.0, 0.0), (0.30, 4.0), (0.46, -4.0), (0.60, -6.0), (0.86, -2.0), (1.0, 0.0)])
    p['lean'] = track(t, [(0.00, 0.0), (0.20, 4.0), (0.34, -8.0), (0.44, 8.0), (0.58, 24.0),
                          (0.70, 22.0), (0.88, 6.0), (1.00, 0.0)])
    p['drop'] = track(t, [(0.00, 0.0), (0.20, 0.010), (0.34, -0.020), (0.46, 0.090), (0.58, 0.260),
                          (0.70, 0.250), (0.88, 0.060), (1.00, 0.0)])
    p['shift'] = (0.0, track(t, [(0.0, 0.0), (0.34, 0.020), (0.58, -0.070), (0.80, 0.0), (1.0, 0.0)]), 0.0)
    p['head_pitch'] = track(t, [(0.0, 0.0), (0.24, -10.0), (0.40, -8.0), (0.58, 12.0), (0.72, 9.0), (1.0, 0.0)])
    p['head_yaw'] = -0.3 * p['yaw']
    p['ankle_l'] = BASE_ANKLE['l'] + Vector((0.050 * slam, -0.030 * slam, 0.0))
    p['ankle_r'] = BASE_ANKLE['r'] + Vector((-0.055 * slam, 0.010 * slam, 0.0))
    p['foot_yaw_l'] = 10.0 * slam
    return p


BUILDERS = {
    'Bow_Barrage': build_barrage,
    'Bow_Triple_Volley': build_volley,
    'Bow_Piercing_Shot': build_piercing,
    'Sword_Double_Slash': build_double_slash,
    'Sword_Lunge_Thrust': build_lunge_thrust,
    'Sword_Spin_Slash': build_spin_slash,
    'Dagger_Dash_Stab': build_dash_stab,
    'Staff_Fireball_Cast': build_fireball,
    'Staff_Bone_Spear_Cast': build_bone_spear,
    'Shield_Bash': build_shield_bash,
    'Shield_Charge': build_shield_charge,
    'Shield_Ground_Slam': build_shield_slam,
}
CLIPS = [(name, seconds, BUILDERS[name], kind) for name, seconds, _b, kind in CLIPS]


# --------------------------------------------------------------------------- #
# QA proxy weapons (deleted before export)
# --------------------------------------------------------------------------- #
def proxy_material(obj, color, metallic=0.0, roughness=0.5):
    material = bpy.data.materials.new(obj.name + '_mat')
    material.use_nodes = True
    bsdf = material.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (*color, 1.0)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    obj.data.materials.append(material)


def add_box(bm, center, size):
    matrix = Matrix.Translation(Vector(center)) @ Matrix.Diagonal(Vector((*size, 1.0)))
    bmesh.ops.create_cube(bm, size=1.0, matrix=matrix)


def add_cylinder(bm, radius, start, end, segments=14):
    start, end = Vector(start), Vector(end)
    axis = end - start
    rotation = axis.normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
    matrix = Matrix.Translation((start + end) * 0.5) @ rotation
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments,
                          radius1=radius, radius2=radius, depth=axis.length, matrix=matrix)


def add_blade(bm, root_z, tip_z, root_width, tip_width, thickness):
    verts = []
    for z, width in ((root_z, root_width), (tip_z, tip_width)):
        for sx in (-0.5, 0.5):
            for sy in (-0.5, 0.5):
                verts.append(bm.verts.new((sx * width, sy * thickness, z)))
    r0, r1, r2, r3 = verts[0], verts[1], verts[2], verts[3]
    t0, t1, t2, t3 = verts[4], verts[5], verts[6], verts[7]
    for face in ((r0, r2, r3, r1), (t0, t1, t3, t2), (r0, r1, t1, t0),
                 (r2, t2, t3, r3), (r0, t0, t2, r2), (r1, r3, t3, t1)):
        bm.faces.new(face)


def make_proxy(name, builder, color, metallic=0.0, roughness=0.5):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    builder(bm)
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    proxy_material(obj, color, metallic, roughness)
    return obj


def build_sword(bm, blade_length=1.02, guard=0.24):
    add_cylinder(bm, 0.022, (0, 0, 0.28), (0, 0, -0.02))
    add_box(bm, (0, 0, 0.30), (0.05, 0.05, 0.035))
    add_box(bm, (0, 0, -0.045), (guard, 0.035, 0.045))
    add_blade(bm, -0.06, -0.06 - blade_length, 0.072, 0.028, 0.016)


def build_dagger(bm):
    build_sword(bm, blade_length=0.30, guard=0.13)


def build_staff(bm):
    # staff.gd builds the shaft from -0.09 down to -1.84 in its own space and
    # archer.gd shifts it by length/2 + 0.25 along the socket +Z, so the ember
    # head ends up 0.71 m along local -Z from the grip and the butt 1.04 m
    # along +Z. That is what the proxy must show.
    add_cylinder(bm, 0.026, (0, 0, 1.04), (0, 0, -0.70))
    add_cylinder(bm, 0.036, (0, 0, 0.32), (0, 0, 0.24))
    add_cylinder(bm, 0.036, (0, 0, 0.12), (0, 0, 0.04))
    add_cylinder(bm, 0.036, (0, 0, -0.44), (0, 0, -0.50))
    bmesh.ops.create_uvsphere(bm, u_segments=14, v_segments=8, radius=0.068,
                              matrix=Matrix.Translation((0, 0, -0.72)))


def build_bow(bm):
    steps = 10
    span = 0.56
    previous = None
    for index in range(steps + 1):
        x = -span + 2.0 * span * index / steps
        y = -0.020 - 0.075 * (1.0 - (x / span) ** 2)
        current = Vector((x, y, 0.0))
        if previous is not None:
            add_cylinder(bm, 0.013, previous, current, segments=8)
        previous = current
    # Straight string between the tips, on the archer's side of the stave.
    add_cylinder(bm, 0.008, (-span, -0.020, 0.0), (span, -0.020, 0.0), segments=6)
    add_cylinder(bm, 0.028, (-0.09, -0.048, 0.0), (0.09, -0.048, 0.0), segments=8)
    add_box(bm, (span, -0.02, 0.0), (0.05, 0.05, 0.09))
    add_box(bm, (-span, -0.02, 0.0), (0.05, 0.05, 0.09))


def build_shield(bm):
    bmesh.ops.create_cone(bm, cap_ends=True, segments=28, radius1=0.335, radius2=0.335,
                          depth=0.045, matrix=Matrix.Identity(4))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.095, radius2=0.055,
                          depth=0.10, matrix=Matrix.Translation((0, 0, 0.06)))
    for z in (0.035, -0.035):
        bmesh.ops.create_cone(bm, cap_ends=True, segments=28, radius1=0.345, radius2=0.345,
                              depth=0.02, matrix=Matrix.Translation((0, 0, z)))


PROXIES = {
    'sword': make_proxy('Proxy_Sword', lambda bm: build_sword(bm), (0.62, 0.64, 0.68), 0.85, 0.32),
    'dagger': make_proxy('Proxy_Dagger', build_dagger, (0.60, 0.62, 0.66), 0.85, 0.30),
    'staff': make_proxy('Proxy_Staff', build_staff, (0.36, 0.24, 0.13), 0.05, 0.6),
    'bow': make_proxy('Proxy_Bow', build_bow, (0.30, 0.19, 0.10), 0.05, 0.55),
    'shield': make_proxy('Proxy_Shield', build_shield, (0.32, 0.22, 0.13), 0.05, 0.55),
}
for key, obj in PROXIES.items():
    # Parenting to the rig keeps the proxies in the character hierarchy while
    # the QA pass drives them from the live bone matrices every frame; bone
    # parenting would re-apply the parent transform on top of those matrices.
    obj.parent = rig
    obj.parent_type = 'OBJECT'
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.hide_render = True
BOW_BASIS = Matrix((Vector((0.0, 0.0, 1.0)), Vector((0.0, 1.0, 0.0)), Vector((-1.0, 0.0, 0.0)))).transposed()


def place_proxies(kind):
    for key, obj in PROXIES.items():
        obj.hide_render = key != kind
    if not RENDER_QA:
        return
    rig_world = rig.matrix_world
    if kind in ('sword', 'dagger', 'staff'):
        obj = PROXIES[kind]
        grip_matrix = Matrix.Translation(GRIP_POS) @ GRIP_ROT.to_matrix().to_4x4()
        obj.matrix_world = rig_world @ rig.pose.bones['hand_r'].matrix @ grip_matrix
    elif kind == 'bow':
        palm = rig.pose.bones['hand_l'].matrix @ PALM_L
        PROXIES['bow'].matrix_world = rig_world @ Matrix.Translation(palm) @ BOW_BASIS.to_4x4()
    else:
        forearm = rig.pose.bones['lowerarm_l']
        head, tail = forearm.head.copy(), forearm.tail.copy()
        forward_dir = (tail - head).normalized()
        normal = forward_dir.cross(Vector((0.0, 0.0, 1.0)))
        if normal.length < 1e-3:
            normal = Vector((0.0, -1.0, 0.0))
        normal.normalize()
        lateral = normal.cross(forward_dir).normalized()
        basis = Matrix((forward_dir, lateral, normal)).transposed()
        PROXIES['shield'].matrix_world = rig_world @ Matrix.Translation((head + tail) * 0.5 + normal * 0.07) @ basis.to_4x4()


# --------------------------------------------------------------------------- #
# Author the clips
# --------------------------------------------------------------------------- #
authored = {}
for index, (name, seconds, builder, kind) in enumerate(CLIPS):
    frames = round(seconds * FPS)
    action = bpy.data.actions.new(name)
    set_action(action)
    DIAG[name] = dict(clamp_r=0.0, clamp_l=0.0, grip_gap=0.0, pull=0.0)
    for frame in range(frames + 1):
        t = frame / frames
        spec = builder(t)
        spec['_clip'] = name
        spec['_t'] = t
        apply_pose(spec)
        key_all(action, frame)
    action.use_fake_user = True
    # Verify the first/last frame return to the idle pose so the blend cannot pop.
    stats = DIAG[name]
    print('CLIP', name, 'frames', frames + 1, 'seconds', seconds,
          {k: (round(v, 4) if isinstance(v, float) else v) for k, v in stats.items()})
    authored[name] = action

# Assert frame 0 and the last frame equal the base pose.
for name, _seconds, builder, _kind in CLIPS:
    action = authored[name]
    set_action(action)
    frames = round(_seconds * FPS)
    for frame in (0, frames):
        scene.frame_set(frame)
        update()
        worst = max((rig.pose.bones[b].matrix_basis.to_translation() - base_basis[b].to_translation()).length
                    for b in ('pelvis', 'spine_03', 'hand_r', 'foot_l', 'foot_r'))
        worst_q = max(abs(1.0 - abs(rig.pose.bones[b].matrix_basis.to_quaternion().dot(base_basis[b].to_quaternion())))
                      for b in ('pelvis', 'spine_03', 'hand_r', 'foot_l', 'foot_r'))
        assert worst < 0.002 and worst_q < 0.002, f'{name} frame {frame} does not return to base: {worst:.4f} {worst_q:.4f}'


# --------------------------------------------------------------------------- #
# QA renders
# --------------------------------------------------------------------------- #
QA_TARGET = Vector((0.0, -0.04, 1.02))
QA_VIEWS = {
    # Front three-quarter from the character's right (-X) so the weapon arm,
    # hilt and blade root are not hidden behind the robe.
    'front': Vector((-1.78, -2.42, 1.60)),
    # Front three-quarter from the character's left (+X) for the shield/bow.
    'alt': Vector((1.95, -2.30, 1.58)),
}


def aim_camera(camera, view):
    location = QA_VIEWS[view]
    camera.location = location
    camera.rotation_euler = (QA_TARGET - location).to_track_quat('-Z', 'Y').to_euler()


def setup_qa_scene():
    for engine in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE', 'BLENDER_WORKBENCH'):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    print('QA_ENGINE', scene.render.engine)
    try:
        scene.eevee.taa_render_samples = 16
    except AttributeError:
        pass
    scene.render.resolution_x = 512
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('QAWorld')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.055, 0.062, 0.075, 1.0)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value = 1.0
    scene.world = world

    floor_mesh = bpy.data.meshes.new('QAFloor')
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=6.0)
    bm.to_mesh(floor_mesh)
    bm.free()
    floor = bpy.data.objects.new('QAFloor', floor_mesh)
    bpy.context.collection.objects.link(floor)
    proxy_material(floor, (0.18, 0.18, 0.19), 0.0, 0.85)

    camera_data = bpy.data.cameras.new('QACamera')
    camera_data.lens = 55.0
    camera = bpy.data.objects.new('QACamera', camera_data)
    bpy.context.collection.objects.link(camera)
    scene.camera = camera
    aim_camera(camera, 'front')

    def area(name, location, energy, size, color=(1.0, 1.0, 1.0)):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = energy
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector((0.0, 0.0, 1.05)) - Vector(location)).to_track_quat('-Z', 'Y').to_euler()
        return obj

    area('QAKey', (-2.4, -2.6, 3.1), 950.0, 3.0, (1.0, 0.96, 0.9))
    area('QAFill', (2.8, -1.8, 1.7), 340.0, 3.5, (0.80, 0.85, 1.0))
    area('QARim', (0.4, 3.0, 2.7), 700.0, 2.6, (1.0, 0.9, 0.78))
    return [floor, camera, camera_data] + [o for o in bpy.data.objects if o.name.startswith('QA')]


def montage(paths, out_path):
    if len(paths) == 1:
        return
    command = ['ffmpeg', '-y']
    for path in paths:
        command += ['-i', str(path)]
    command += ['-filter_complex', f'hstack=inputs={len(paths)}', str(out_path)]
    try:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.CalledProcessError) as error:
        print('MONTAGE_FAILED', out_path, error)


def render_clip(name, samples, strip=False, view='front'):
    action = authored[name]
    set_action(action)
    seconds = dict((n, s) for n, s, _b, _k in CLIPS)[name]
    kind = dict((n, k) for n, _s, _b, k in CLIPS)[name]
    frames = round(seconds * FPS)
    aim_camera(scene.camera, view)
    suffix = 'strip' if strip else ('sheet' if view == 'front' else view + '_sheet')
    paths = []
    for index, t in enumerate(samples):
        frame = int(round(t * frames))
        scene.frame_set(frame)
        update()
        place_proxies(kind)
        update()
        path = QA_DIR / f'{name}_{suffix}_{index}.png'
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        paths.append(path)
    out = QA_DIR / f'{name}_{suffix}.png'
    montage(paths, out)
    print('QA_SHEET', out)


qa_objects = []
if RENDER_QA:
    QA_DIR.mkdir(parents=True, exist_ok=True)
    qa_objects = setup_qa_scene()
    for name, _seconds, _builder, _kind in CLIPS:
        render_clip(name, (0.0, 0.25, 0.5, 0.75, 1.0))
        render_clip(name, (0.0, 0.25, 0.5, 0.75, 1.0), view='alt')
    for name in ('Bow_Barrage', 'Sword_Spin_Slash', 'Staff_Fireball_Cast'):
        render_clip(name, tuple(i / 5.0 for i in range(6)), strip=True)

# QA-only geometry never reaches the export.
doomed = {o.name for o in qa_objects if isinstance(o, bpy.types.Object)}
doomed.update(o.name for o in PROXIES.values())
for object_name in doomed:
    doomed_object = bpy.data.objects.get(object_name)
    if doomed_object is not None:
        bpy.data.objects.remove(doomed_object, do_unlink=True)
for light in list(bpy.data.lights):
    if light.name.startswith('QA'):
        bpy.data.lights.remove(light)
for camera_data in list(bpy.data.cameras):
    if camera_data.name.startswith('QA'):
        bpy.data.cameras.remove(camera_data)
for mesh in list(bpy.data.meshes):
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
for material in list(bpy.data.materials):
    if material.users == 0:
        bpy.data.materials.remove(material)

# --------------------------------------------------------------------------- #
# Export the authored clips and merge only them into the shipped GLB
# --------------------------------------------------------------------------- #
for track in list(rig.animation_data.nla_tracks):
    rig.animation_data.nla_tracks.remove(track)
rig.animation_data.action = None
for action in list(bpy.data.actions):
    if action.name not in actions and action.name not in authored:
        bpy.data.actions.remove(action)
ordered = list(actions.values()) + [authored[name] for name, _s, _b, _k in CLIPS]
scene.frame_start = 0
scene.frame_end = max(round(seconds * FPS) for _n, seconds, _b, _k in CLIPS)
for action in ordered:
    track = rig.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, 0, action)
    track.mute = True
for pose_bone in rig.pose.bones:
    pose_bone.matrix_basis = Matrix.Identity(4)
bpy.ops.export_scene.gltf(
    filepath=str(TEMP), export_format='GLB', export_animations=True,
    export_animation_mode='NLA_TRACKS', export_nla_strips=True,
    export_force_sampling=True, export_frame_range=False, export_yup=True,
    export_materials='EXPORT', export_image_format='AUTO', export_skins=True)

merged = merge_clips(GLB, TEMP, AUTHORED)
TEMP.unlink()
if sorted(merged) != sorted(AUTHORED):
    raise RuntimeError(f'Authored clip mismatch: {sorted(merged)}')

document, _binary = read_glb(GLB)
durations = clip_durations(document)
missing = [name for name in ('Idle_Loop', 'Bandage_Wrap', 'Potion_Drink') if name not in durations]
if missing:
    raise RuntimeError(f'Shipped clips disappeared: {missing}')
if len(durations) != len(actions) + len(AUTHORED):
    raise RuntimeError(f'Unexpected clip count {len(durations)}')
for name, seconds, _builder, _kind in CLIPS:
    assert abs(durations[name] - seconds) < 1.0 / FPS + 1e-6, (name, durations[name], seconds)

# --------------------------------------------------------------------------- #
# Metadata
# --------------------------------------------------------------------------- #
metadata = json.loads(METADATA.read_text(encoding='utf-8'))
for name, seconds, _builder, _kind in CLIPS:
    metadata['animations'][name] = round(float(durations[name]), 10)

RUNTIME_OVERRIDES = {
    'bow': 'Both bow arms and the bow aim are solved procedurally at runtime from the draw curve, and an archery stance is planted. The authored bow-arm poses are presentation only; the lower body, pelvis and spine rhythm stay authored.',
    'sword': 'The blade follows hand_r * sword_grip; a hand basis of aim * inverse(sword_grip) points the blade at the authored world direction. Greatsword and staff are two-handed: the support (left) hand is authored onto the grip and is not re-solved during abilities.',
    'staff': 'The staff is socketed on hand_r and runs along its local -Z from the grip; the support hand is authored onto the shaft 0.32 m along the handle.',
    'shield': 'The shield is carried on the left forearm automatically; the left arm is authored to raise, punch or slam the shield face.',
    'spin_slash': 'The runtime rotates the visual model a full 360 degrees from 10% to 86% of Sword_Spin_Slash. The clip authors only a low wide pivot stance with a horizontal sweep arc and a committed weight shift, never a full turn.',
    'blend': 'Every clip starts and ends at the Idle_Loop frame-0 pose so the 0.12 s runtime blend does not pop. The root bone is never moved.',
    'feet': 'Legs are authored as ankle targets; the runtime re-solves knees to terrain. Ankles stay at their shipped 84-86 mm height and only leave it for deliberate step lifts.',
    'barrage_beats': 'Six draw-release pulses peaking at 0.22, 0.34, 0.46, 0.58, 0.70 and 0.82 s with visible weight pulses and small recoils.',
    'volley_beats': 'One draw releasing at 0.48 s.',
    'piercing_beats': 'A long heavy draw releasing at 0.72 s.',
}
clip_rows = {}
for name, seconds, _builder, kind in CLIPS:
    clip_rows[name] = {
        'duration': round(float(durations[name]), 10),
        'frames': round(seconds * FPS) + 1,
        'weapon': kind,
        'two_handed': kind in ('sword', 'staff'),
        'proxy': kind if kind != 'dagger' else 'dagger',
    }
metadata['ability_authoring'] = {
    'authoring_fps': FPS,
    'source': 'tools/prepare_ability_animations.py',
    'merge': 'tools/glb_animation_merge.py copies only these clips into the shipped GLB',
    'clips': clip_rows,
    'durations': {name: round(float(durations[name]), 10) for name, _s, _b, _k in CLIPS},
    'runtime_overrides': RUNTIME_OVERRIDES,
    'qa_renders': '.runtime/ability_anim/<clip>_sheet.png (t=0, 25, 50, 75, 100 %), <clip>_strip.png for Bow_Barrage, Sword_Spin_Slash, Staff_Fireball_Cast',
}
METADATA.write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
print('ABILITY_CLIPS', {name: round(durations[name], 4) for name in sorted(AUTHORED)})
print('TOTAL_CLIPS', len(durations))
print('DIAG', json.dumps(DIAG, default=str))
