extends Node3D
## Owns every blood stain in one scene: surface patches, body and weapon
## coatings, and the short-lived spray bursts. Stains live for 60 seconds,
## fade over the last three, and are recycled oldest-first when a busy fight
## exceeds the render budget. Created lazily by `BloodFx.field_for`.

const BloodFx = preload("res://scripts/blood_fx.gd")
const BloodSurface = preload("res://scripts/blood_surface.gd")

const PATCH_SEGMENTS := 12
const PATCH_RINGS := 2
## Body stains are a coarse grid bent onto the measured cloth surface: enough
## segments to follow a shoulder or a thigh, cheap enough to merge several
## splashes into the single mesh each wound owns.
const BODY_RINGS := 5
const BODY_SEGMENTS := 5
const MAX_BURSTS := 14
const MAX_BODY_STAINS := 10
const MAX_WEAPON_STAINS := 8
const GROUND_MASK := 1
const PATCH_LIFT := 0.012

var max_surface_stains := 160
var lifetime := BloodFx.LIFETIME
var _stains: Array[Dictionary] = []
## Visible-armor signature per rig: when the cloth underneath changes, the stains
## measured against the old surface are dropped instead of floating off it.
var _body_signatures: Dictionary = {}
var _bursts: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _query := PhysicsRayQueryParameters3D.new()

func _ready() -> void:
	_rng.seed = 0xB100D
	set_process(true)

func _process(delta: float) -> void:
	advance(delta)

# --- public field API ------------------------------------------------------

## Directional spray at a real blade/projectile contact plus flung droplets that
## mark the ground and walls around it. Body blood comes from `wound`.
func impact(at: Vector3, direction: Vector3, amount: float, headshot: bool) -> void:
	var dir := direction
	if dir.length_squared() < 0.000001:
		dir = Vector3.UP
	dir = dir.normalized()
	var weight := clampf(amount, 4.0, 60.0)
	_spawn_burst(at, dir, weight, 1.0 + (0.25 if headshot else 0.0))
	# The blow itself leaves a splat where it stopped against scenery.
	var hit := _ray(at - dir * 0.02, at + dir * 0.55, GROUND_MASK)
	if not hit.is_empty():
		var normal: Vector3 = hit.normal
		if absf(normal.y) < 0.72:
			_spawn_patch(hit.position, normal, 0.20 + weight * 0.006, false)
	_fling(at, dir, weight, headshot)

## Flung droplets: short rays away from the contact, each leaving a small patch
## where it lands. A hit reads as a splash only when the blood also hits the
## floor and wall around the victim, not a single decal pinned under it.
func _fling(at: Vector3, direction: Vector3, amount: float, headshot: bool) -> void:
	var radius := clampf(0.06 + amount * 0.0045, 0.07, 0.30)
	var reach := 1.25 + minf(amount, 60.0) * 0.016
	var up := Vector3.UP if absf(direction.y) < 0.94 else Vector3.RIGHT
	var side := direction.cross(up)
	if side.length_squared() < 0.0001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var lift := side.cross(direction).normalized()
	# The drops that fall straight off the blade, so every contact marks the
	# floor beneath it even when the fan finds no wall.
	var below := _ray(at, at + Vector3.DOWN * (0.9 + minf(amount, 40.0) * 0.01),
		GROUND_MASK)
	if not below.is_empty():
		var floor_normal: Vector3 = below.normal
		_spawn_patch(below.position, floor_normal, radius * 0.62, false)
	var count := 3
	if amount >= 20.0:
		count += 1
	if headshot:
		count += 1
	for index in count:
		var spin := _rng.randf() * TAU
		var tilt := _rng.randf_range(0.16, 0.78)
		var flung := (direction * cos(tilt) \
			+ (side * cos(spin) + lift * sin(spin)) * sin(tilt)).normalized()
		var hit := _ray(at, at + flung * reach * _rng.randf_range(0.55, 1.0),
			GROUND_MASK)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit.normal
		_spawn_patch(hit.position, normal, radius * _rng.randf_range(0.45, 1.0), false)

## Damage that actually landed: body coating, floor spatter, and the death
## pool. `rig` may be null for a target with no visible body.
func wound(rig: Node3D, at: Vector3, amount: float, headshot: bool,
		lethal: bool, scale: float) -> void:
	var size_scale := clampf(scale, 0.35, 2.5)
	if is_instance_valid(rig):
		_stain_body(rig, at, amount, headshot, lethal, size_scale)
	var radius := clampf(0.14 + amount * 0.0075, 0.16, 0.62) * size_scale
	_ground_splat(at, radius)
	if lethal:
		_spawn_pool(at, size_scale)
		_spawn_burst(at + Vector3(0.0, 0.12 * size_scale, 0.0), Vector3.UP,
			maxf(amount, 24.0) * 1.6, size_scale * 1.25, 0.55)

## Someone else's blood on this body: the claw, paw or muzzle that struck. No
## floor decal — the victim's `wound` already owns the ground.
func bloodied(rig: Node3D, at: Vector3, amount: float, scale: float) -> void:
	var size_scale := clampf(scale, 0.35, 2.5)
	if is_instance_valid(rig):
		_stain_body(rig, at, amount, false, false, size_scale)
	_spawn_burst(at, Vector3.UP, maxf(amount, 6.0) * 0.7, size_scale * 0.65, 0.45)

## Wet coating on the blade that dealt the blow. Parented to the weapon node so
## it tracks every swing and socket change.
func stain_weapon(anchor: Node3D, amount: float, scale: float) -> void:
	if not is_instance_valid(anchor):
		return
	var box := _anchor_bounds(anchor)
	if box.size.length_squared() < 0.000001:
		return
	var center := box.get_center()
	var axis := 2
	if box.size.x >= box.size.y and box.size.x >= box.size.z:
		axis = 0
	elif box.size.y >= box.size.z:
		axis = 1
	var tip := Vector3.ZERO
	var component: float = center[axis]
	tip[axis] = -1.0 if component < 0.0 else 1.0
	var thin := 0
	for candidate in 3:
		if candidate == axis:
			continue
		if thin == axis or box.size[candidate] < box.size[thin]:
			thin = candidate
	var wide := 3 - axis - thin
	var thin_axis := Vector3.ZERO
	thin_axis[thin] = 1.0
	var wide_axis := Vector3.ZERO
	wide_axis[wide] = 1.0
	var blade_length: float = box.size[axis]
	var blade_value = anchor.get("blade_length") if "blade_length" in anchor else null
	if blade_value != null:
		blade_length = maxf(float(blade_value), 0.05)
	# Blade-sized droplets rather than whole-hilt AABB fractions.
	var droplet := clampf(blade_length * 0.026, 0.009, 0.024) * scale
	var lateral := clampf(blade_length * 0.045, 0.012, 0.055)
	# Half-thickness of the blade plus the flattened blob's own half-thickness:
	# the coating must sit proud of the steel, not inside it.
	var surface := clampf(blade_length * 0.030, 0.012, 0.026)
	var droplet_count := 3
	if amount >= 22.0:
		droplet_count += 1
	if amount >= 42.0:
		droplet_count += 1
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in droplet_count:
		var side := 1.0 if index % 2 == 0 else -1.0
		var normal := thin_axis * side
		var radius := droplet * _rng.randf_range(0.7, 1.3)
		var side_offset := (1.0 if _rng.randf() < 0.5 else -1.0) \
			* _rng.randf_range(0.35, 0.85)
		var position := tip * blade_length * _rng.randf_range(0.14, 0.46) \
			+ wide_axis * side_offset * lateral \
			+ normal * surface
		var size := Vector3(radius, radius * 0.22, radius * _rng.randf_range(0.8, 1.5))
		tool.append_from(BloodFx.blot_mesh(), 0,
			Transform3D(_basis_from_y(normal) * Basis.from_scale(size), position))
	# One elongated smear on the blade's flat reads as a dragged cut.
	var smear_length := blade_length * _rng.randf_range(0.26, 0.46)
	var smear_width := lateral * _rng.randf_range(1.4, 2.2)
	var smear_side := 1.0 if _rng.randf() < 0.5 else -1.0
	var smear_normal := thin_axis * smear_side
	var smear := Transform3D(
		_basis_yz(smear_normal, tip) * Basis.from_scale(
			Vector3(smear_width, 0.004, smear_length)),
		tip * blade_length * _rng.randf_range(0.16, 0.34) \
			+ wide_axis * _rng.randf_range(0.15, 0.5) * lateral * smear_side \
			+ smear_normal * surface)
	tool.append_from(BloodFx.blot_mesh(), 0, smear)
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodCoating"
	node.set_meta("blood_stain", "coating")
	node.mesh = mesh
	node.material_override = BloodFx.blot_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor.add_child(node)
	node.position = center
	_register_stain(node, anchor, "group", MAX_WEAPON_STAINS)

func surface_stain_count() -> int:
	var count := 0
	for stain in _stains:
		if stain.owner == null and is_instance_valid(stain.node):
			count += 1
	return count

func stain_count() -> int:
	return _stains.size()

func burst_count() -> int:
	return _bursts.size()

func clear_all() -> void:
	for stain in _stains:
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
			_release_attachment(stain.node as Node)
	for burst in _bursts:
		if is_instance_valid(burst.node):
			(burst.node as Node).queue_free()
	_stains.clear()
	_bursts.clear()

# --- lifetime --------------------------------------------------------------

func advance(delta: float) -> void:
	for index in range(_stains.size() - 1, -1, -1):
		var stain: Dictionary = _stains[index]
		var node = stain.node
		if not is_instance_valid(node):
			_stains.remove_at(index)
			continue
		stain.age = float(stain.age) + delta
		var remaining := float(stain.life) - float(stain.age)
		if remaining <= BloodFx.FADE_SECONDS:
			_apply_fade(stain, clampf(remaining / BloodFx.FADE_SECONDS, 0.0, 1.0))
		if remaining <= 0.0:
			(node as Node).queue_free()
			_release_attachment(node as Node)
			_stains.remove_at(index)
	for index in range(_bursts.size() - 1, -1, -1):
		var burst: Dictionary = _bursts[index]
		burst.age = float(burst.age) + delta
		if not is_instance_valid(burst.node) or float(burst.age) >= float(burst.life):
			if is_instance_valid(burst.node):
				(burst.node as Node).queue_free()
			_bursts.remove_at(index)

func _apply_fade(stain: Dictionary, factor: float) -> void:
	var node = stain.node
	if not is_instance_valid(node):
		return
	if str(stain.kind) in ["patch", "soak"]:
		(node as GeometryInstance3D).transparency = 1.0 - factor
	else:
		(node as Node3D).scale = (stain.scale as Vector3) * maxf(factor, 0.001)

func _register_stain(node: Node, stain_owner: Node, kind: String, cap: int) -> void:
	var entry := {"node": node, "owner": stain_owner, "kind": kind, "age": 0.0,
		"life": lifetime, "scale": (node as Node3D).scale if node is Node3D else Vector3.ONE}
	_stains.append(entry)
	_enforce_cap(stain_owner, cap)

func _enforce_cap(stain_owner: Node, cap: int) -> void:
	var count := 0
	for stain in _stains:
		if stain.owner != stain_owner or not is_instance_valid(stain.node):
			continue
		if (stain.node as Node).is_queued_for_deletion():
			continue
		count += 1
	var excess := count - cap
	var index := 0
	while excess > 0 and index < _stains.size():
		var stain: Dictionary = _stains[index]
		if stain.owner != stain_owner or not is_instance_valid(stain.node) \
				or (stain.node as Node).is_queued_for_deletion():
			index += 1
			continue
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
			_release_attachment(stain.node as Node)
		_stains.remove_at(index)
		excess -= 1

func _drop_rig_stains(rig: Node3D) -> void:
	for index in range(_stains.size() - 1, -1, -1):
		var stain: Dictionary = _stains[index]
		if stain.owner != rig:
			continue
		if is_instance_valid(stain.node):
			(stain.node as Node).queue_free()
			_release_attachment(stain.node as Node)
		_stains.remove_at(index)

## Frees the bone attachment a stain was riding on once nothing is left on it,
## so long fights do not leave empty nodes hanging off every skeleton bone.
func _release_attachment(node: Node) -> void:
	var parent := node.get_parent()
	if parent == null or not parent.has_meta("blood_attachment"):
		return
	for other in _stains:
		var sibling = other.node
		if sibling == null or not is_instance_valid(sibling) or sibling == node:
			continue
		if sibling.is_queued_for_deletion():
			continue
		if sibling.get_parent() == parent:
			return
	parent.queue_free()

# --- body and weapon stains ------------------------------------------------

func _stain_body(rig: Node3D, at: Vector3, amount: float, headshot: bool,
		lethal: bool, scale: float) -> void:
	var body := BloodSurface.body_for(rig)
	if body.is_empty():
		return
	var signature := int(body.get("signature", 0))
	if signature != int(_body_signatures.get(rig.get_instance_id(), signature)):
		_drop_rig_stains(rig)
	if _body_signatures.size() > 256:
		_body_signatures.clear()
	_body_signatures[rig.get_instance_id()] = signature
	var carrier := BloodSurface.nearest_carrier(body, at)
	if carrier.is_empty():
		return
	var anchor := BloodSurface.anchor_for(carrier)
	if anchor == null:
		return
	BloodSurface.prepare_pose(carrier)
	var center := BloodSurface.to_local(carrier, at)
	var down := BloodSurface.down_local(carrier)
	var lift := BloodSurface.LIFT * clampf(scale, 0.6, 2.2)
	# Severity sets both the size of the soak and how many separate splashes
	# land: one hard blow soaks the whole panel, a graze only freckles it.
	var base := clampf(0.034 + amount * 0.0028, 0.038, 0.150) * scale
	var splashes := 4
	if amount >= 14.0:
		splashes += 1
	if amount >= 26.0:
		splashes += 1
	if headshot:
		splashes += 2
	if lethal:
		splashes += 3
	# The splashes are laid out on the measured cloth itself, not around it:
	# a hit has to be readable on the clothes from every side of the fight.
	var limit := BloodSurface.patch_extent(carrier)
	var points := BloodSurface.cluster(carrier, splashes, _rng, center)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed := 0
	for index in points.size():
		var half_up := minf(base * _rng.randf_range(0.70, 1.55), limit.x)
		var half_wide := minf(base * _rng.randf_range(0.50, 1.05), limit.y)
		if index == 0:
			half_up = minf(base, limit.x)
			half_wide = minf(base * 0.92, limit.y)
		if BloodSurface.add_patch(tool, carrier, points[index], down, half_up,
				half_wide, BODY_RINGS, BODY_SEGMENTS, _rng.randf() * TAU, lift):
			placed += 1
	# Gravity runs: narrow streaks under the first splash, the way blood wicks
	# down a belt or a sleeve instead of pooling on it.
	if not points.is_empty():
		var runs := 1 if amount < 26.0 else 2
		for index in runs:
			var half_run := minf(base * _rng.randf_range(1.1, 2.2), limit.x * 1.8)
			var start: Vector3 = points[0] + down * (half_run + limit.x * 0.3)
			if BloodSurface.add_patch(tool, carrier, start, down, half_run,
					minf(base * _rng.randf_range(0.11, 0.19), limit.y * 0.3),
					BODY_RINGS, 2, _rng.randf_range(-0.25, 0.25), lift):
				placed += 1
	if placed == 0:
		tool.clear()
		return
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodSoak"
	node.set_meta("blood_stain", "wound")
	node.mesh = mesh
	node.material_override = BloodFx.soak_material(_rng.randi() % BloodFx.SPLAT_VARIANTS)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor.add_child(node)
	_register_stain(node, rig, "soak", MAX_BODY_STAINS)

## An arrow carries a smear, not a blade coating: a wet skim on the shaft just
## behind the head and two specks. Sized from the shaft, never the fletching.
func stain_projectile(anchor: Node3D, amount: float) -> void:
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var bounds := _anchor_bounds(anchor)
	if bounds.size.length_squared() < 0.000001:
		return
	var center := bounds.get_center()
	var axis := 2
	if bounds.size.x >= bounds.size.y and bounds.size.x >= bounds.size.z:
		axis = 0
	elif bounds.size.y >= bounds.size.z:
		axis = 1
	var shaft := center
	var component: float = center[axis]
	shaft[axis] = -1.0 if component < 0.0 else 1.0
	var thin := 0
	for candidate in 3:
		if candidate == axis:
			continue
		if thin == axis or bounds.size[candidate] < bounds.size[thin]:
			thin = candidate
	var wide := 3 - axis - thin
	var thin_axis := Vector3.ZERO
	thin_axis[thin] = 1.0
	var wide_axis := Vector3.ZERO
	wide_axis[wide] = 1.0
	var length: float = bounds.size[axis]
	var shaft_radius := clampf(length * 0.008, 0.004, 0.011)
	var smear_length := clampf(0.018 + amount * 0.0008, 0.018, 0.05)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side := 1.0 if _rng.randf() < 0.5 else -1.0
	var normal := thin_axis * side
	var smear_center: Vector3 = shaft * length * _rng.randf_range(0.70, 0.88)
	_wrap_shaft(tool, smear_center, normal, wide_axis, shaft, shaft_radius,
		smear_length * 0.5, shaft_radius * 0.9)
	for index in 2:
		var speck_side := 1.0 if _rng.randf() < 0.5 else -1.0
		_wrap_shaft(tool, smear_center + shaft * _rng.randf_range(-0.02, 0.02),
			thin_axis * speck_side, wide_axis, shaft,
			shaft_radius * _rng.randf_range(0.5, 0.9), 0.004, 0.0035)
	var mesh := tool.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var node := MeshInstance3D.new()
	node.name = "BloodSmear"
	node.set_meta("blood_stain", "coating")
	node.mesh = mesh
	node.material_override = BloodFx.soak_material(_rng.randi() % BloodFx.SPLAT_VARIANTS)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	anchor.add_child(node)
	node.position = center
	_register_stain(node, anchor, "group", MAX_WEAPON_STAINS)

## Lays a small textured band around a thin shaft so the stain curves with it.
func _wrap_shaft(tool: SurfaceTool, center: Vector3, normal: Vector3,
		across: Vector3, axis: Vector3, radius: float, half_length: float,
		half_wide: float) -> void:
	# A band, never a full wrap: a shaft painted right round reads as goo.
	var rings := 2
	var segments := 2
	var band := SurfaceTool.new()
	band.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in rings + 1:
		var along := float(row) / float(rings) * 2.0 - 1.0
		for column in segments + 1:
			var sideways := float(column) / float(segments) * 2.0 - 1.0
			var turn := sideways * half_wide / maxf(radius + 0.0015, 0.002)
			var direction := (normal * cos(turn) + across * sin(turn)).normalized()
			var point: Vector3 = center + axis * (along * half_length) \
				+ direction * (radius + 0.0015)
			band.set_normal(direction)
			band.set_uv(Vector2(along * 0.5 + 0.5, sideways * 0.5 + 0.5))
			band.add_vertex(point)
	var stride := segments + 1
	for row in rings:
		for column in segments:
			var a := row * stride + column
			var b := a + 1
			var c := a + stride
			var d := c + 1
			band.add_index(a)
			band.add_index(c)
			band.add_index(b)
			band.add_index(b)
			band.add_index(c)
			band.add_index(d)
	var built := band.commit()
	if built != null and built.get_surface_count() > 0:
		tool.append_from(built, 0, Transform3D())
func _anchor_bounds(anchor: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	for node in anchor.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		var local: AABB = anchor.global_transform.affine_inverse() \
			* mesh_node.global_transform * mesh_node.get_aabb()
		if first:
			combined = local
			first = false
		else:
			combined = combined.merge(local)
	return combined

func _basis_from_y(up: Vector3) -> Basis:
	var y := up.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _basis_yz(y_dir: Vector3, z_dir: Vector3) -> Basis:
	var y := y_dir.normalized()
	if y.length_squared() < 0.0001:
		y = Vector3.UP
	var z := z_dir - y * z_dir.dot(y)
	if z.length_squared() < 0.0001:
		z = y.cross(Vector3.RIGHT)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)

# --- floor patches ---------------------------------------------------------

## One main splat under the wound plus smaller satellites around it, so the
## floor around a hit is speckled instead of carrying a single tidy disc.
func _ground_splat(at: Vector3, radius: float) -> void:
	var specks := 2
	if radius >= 0.30:
		specks += 1
	for index in specks + 1:
		var spread := 0.20 if index == 0 else _rng.randf_range(0.26, 0.95)
		var speck := radius if index == 0 else radius * _rng.randf_range(0.16, 0.44)
		_ground_patch(at, speck, spread)

func _ground_patch(at: Vector3, radius: float, spread: float) -> void:
	var offset := Vector3(_rng.randf_range(-spread, spread), 0.0,
		_rng.randf_range(-spread, spread))
	var hit := _ray(at + Vector3(0.0, 0.8, 0.0) + offset,
		at + Vector3(0.0, -3.0, 0.0) + offset, GROUND_MASK)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.normal
	if normal.y < 0.42:
		return
	_spawn_patch(hit.position, normal, radius, false)

func _spawn_pool(at: Vector3, scale: float) -> void:
	var hit := _ray(at + Vector3(0.0, 0.6, 0.0), at + Vector3(0.0, -3.0, 0.0),
		GROUND_MASK)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.35:
		return
	var pool := _spawn_patch(hit.position, hit.normal, 0.46 * scale, true)
	pool.scale = Vector3.ONE * 0.30
	var tween := pool.create_tween()
	tween.tween_property(pool, "scale", Vector3.ONE, 0.95) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _spawn_patch(center: Vector3, normal: Vector3, radius: float,
		pool: bool) -> MeshInstance3D:
	var variant := _rng.randi() % BloodFx.SPLAT_VARIANTS
	var mesh := _conform_patch(center, normal, radius, variant * 37 + _rng.randi() % 97)
	var patch := MeshInstance3D.new()
	patch.name = "BloodPool" if pool else "BloodSplat"
	patch.set_meta("blood_stain", "pool" if pool else "splat")
	patch.mesh = mesh
	patch.material_override = BloodFx.pool_material() if pool \
		else BloodFx.patch_material(variant)
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	patch.position = center
	add_child(patch)
	_register_stain(patch, null, "patch", max_surface_stains)
	return patch

## Builds a small radial patch whose vertices are dropped onto the real surface
## so blood follows slopes and steps instead of clipping through the ground.
func _conform_patch(center: Vector3, normal: Vector3, radius: float,
		phase_seed: int) -> ArrayMesh:
	var up := normal.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var back := side.cross(up).normalized()
	var phase := float(phase_seed % 628) * 0.01
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.append(Vector3.ZERO)
	normals.append(up)
	uvs.append(Vector2(0.5, 0.5))
	var ring_starts: Array[int] = []
	for ring in range(1, PATCH_RINGS + 1):
		var fraction := float(ring) / float(PATCH_RINGS)
		ring_starts.append(vertices.size())
		for segment in PATCH_SEGMENTS:
			var angle := TAU * float(segment) / float(PATCH_SEGMENTS) + phase
			var tangent := side * cos(angle) + back * sin(angle)
			var target := center + tangent * radius * fraction
			var hit := _ray(target + up * 0.9, target - up * 0.75, GROUND_MASK)
			var point := target
			if not hit.is_empty():
				point = (hit.position as Vector3) + up * PATCH_LIFT
			else:
				point += up * PATCH_LIFT
			vertices.append(point - center)
			normals.append(up)
			uvs.append(Vector2(0.5, 0.5) + Vector2(cos(angle), sin(angle)) * 0.5 * fraction)
	var first_ring := ring_starts[0]
	for segment in PATCH_SEGMENTS:
		indices.append(0)
		indices.append(first_ring + segment)
		indices.append(first_ring + (segment + 1) % PATCH_SEGMENTS)
	for ring in range(1, PATCH_RINGS):
		var inner := ring_starts[ring - 1]
		var outer := ring_starts[ring]
		for segment in PATCH_SEGMENTS:
			var next := (segment + 1) % PATCH_SEGMENTS
			indices.append(inner + segment)
			indices.append(outer + segment)
			indices.append(inner + next)
			indices.append(inner + next)
			indices.append(outer + segment)
			indices.append(outer + next)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	if not is_inside_tree():
		return {}
	_query.from = from
	_query.to = to
	_query.collision_mask = mask
	_query.exclude = []
	return get_world_3d().direct_space_state.intersect_ray(_query)

# --- spray -----------------------------------------------------------------

func _spawn_burst(at: Vector3, direction: Vector3, amount: float, scale: float,
		up_bias: float = 0.0) -> void:
	while _bursts.size() >= MAX_BURSTS:
		var oldest: Dictionary = _bursts.pop_front()
		if is_instance_valid(oldest.node):
			(oldest.node as Node).queue_free()
	var burst := CPUParticles3D.new()
	burst.name = "BloodSpray"
	burst.one_shot = true
	burst.amount = clampi(int(round(26.0 + amount * 2.2)), 28, 120)
	burst.lifetime = _rng.randf_range(0.42, 0.80)
	burst.explosiveness = 0.92
	burst.direction = (direction + Vector3.UP * up_bias).normalized()
	burst.spread = 58.0
	burst.initial_velocity_min = 1.7 * scale
	burst.initial_velocity_max = 4.4 * scale
	burst.gravity = Vector3(0.0, -10.4, 0.0)
	# Drops, not motes: sub-millimetre specks vanished against the terrain, so
	# the spray uses pebble-to-marble droplets that read at combat distance.
	burst.scale_amount_min = 0.005 * scale
	burst.scale_amount_max = 0.012 * scale
	burst.mesh = BloodFx.drop_mesh()
	burst.material_override = BloodFx.drop_material()
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.color = Color(1.0, 1.0, 1.0, 1.0)
	burst.local_coords = false
	burst.position = at
	add_child(burst)
	burst.emitting = true
	_bursts.append({"node": burst, "age": 0.0, "life": burst.lifetime + 0.6})
