"""Merge authored animations from a temporary GLB into a shipped GLB document.

Blender's glTF round-trip perturbs existing clip channels even when the rest
transforms look equivalent. Authoring tools therefore export a temporary GLB
that contains the new clips, then use `merge_clips` to copy only those clips
into the original document, leaving every existing node, skin, mesh and
animation byte-for-byte untouched.

The module only needs the standard library so it can be imported from inside
Blender (``--background --python``) and from plain CPython verification scripts.
"""
import copy
import json
import struct

COMPONENT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
COMPONENT_COUNT = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16}


def read_glb(path):
    """Return (json document, binary chunk) for a GLB file."""
    raw = path.read_bytes()
    if struct.unpack_from('<I', raw, 0)[0] != 0x46546C67:
        raise RuntimeError(f'{path} is not a GLB file')
    json_size = struct.unpack_from('<I', raw, 12)[0]
    document = json.loads(raw[20:20 + json_size])
    return document, bytearray(raw[28 + json_size:])


def write_glb(path, document, binary):
    """Serialise (json document, binary chunk) back to a GLB file."""
    document['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(document, separators=(',', ':')).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    while len(binary) % 4:
        binary.append(0)
    path.write_bytes(struct.pack('<III', 0x46546C67, 2, 28 + len(encoded) + len(binary))
                     + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded
                     + struct.pack('<II', len(binary), 0x004E4942) + binary)


def clip_durations(document):
    """Map animation name to its sampled duration in seconds."""
    return {animation['name']: max(document['accessors'][sampler['input']]['max'][0]
                                   for sampler in animation['samplers'])
            for animation in document.get('animations', [])}


def merge_clips(base_path, authored_path, clip_names, remove_clips=()):
    """Replace/append only `clip_names` from `authored_path` inside `base_path`.

    Validates that node order matches, copies the referenced accessors into the
    base binary chunk, then rewrites the base file. `remove_clips` names are
    dropped from the base first, which retires renamed clips. Every animation
    not named in either set is left untouched. Returns the merged names in
    authored order.
    """
    clip_names = set(clip_names)
    remove_clips = set(remove_clips)
    base, base_binary = read_glb(base_path)
    authored, authored_binary = read_glb(authored_path)
    if [n.get('name') for n in base['nodes']] != [n.get('name') for n in authored['nodes']]:
        raise RuntimeError('Authored GLB node order differs from the shipped rig')
    base_names = [n.get('name') for n in base['nodes']]
    drop = clip_names | remove_clips
    base['animations'] = [a for a in base.get('animations', []) if a.get('name') not in drop]
    merged = []
    for animation in authored.get('animations', []):
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
            element_size = COMPONENT_SIZE[accessor['componentType']] * COMPONENT_COUNT[accessor['type']]
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
            if base_names[node_index] != authored['nodes'][node_index].get('name'):
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
        merged.append(animation['name'])
    write_glb(base_path, base, base_binary)
    return merged
