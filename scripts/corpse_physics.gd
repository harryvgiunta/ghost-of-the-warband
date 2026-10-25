extends RefCounted
## Physical death: a corpse falls under gravity and its skeleton goes limp.
##
## Two layers share one path:
## - every dead CharacterBody keeps falling to the ground with only the world
##   collision mask, so a mob killed mid-leap cannot hang in the air;
## - a rigged presentation gets a Godot `PhysicalBoneSimulator3D` ragdoll built
##   from the bone chain it already has. The authored death clip is replaced by
##   real falling limbs. The simulation settles, its pose is baked into the
##   skeleton, and the rigid bodies are freed, so five-minute corpses cost
##   nothing after the fall.
##
## The ragdoll is presentation only: it never owns damage, loot or authority.
## Both host and replica build their own from the replicated death position.

const GRAVITY := 18.0
const MAX_BONES := 32
## The corpse holds still for this long before the settle poll starts: a body
## must not freeze at the apex of its fall.
const SETTLE_MIN := 1.2
const SETTLE_POLL := 0.3
const SETTLE_MAX := 4.5
const SETTLE_SPEED := 0.35
const SETTLE_SLOW_CHECKS := 2


## The at-least contract: a dead body obeys gravity wherever it died. The
## capsule no longer blocks anything (layer 0), so this only reads the world.
static func settle_root(host: CharacterBody3D, delta: float) -> void:
	if host.is_on_floor():
		host.velocity = Vector3.ZERO
		return
	host.velocity.x = move_toward(host.velocity.x, 0.0, 24.0 * delta)
	host.velocity.z = move_toward(host.velocity.z, 0.0, 24.0 * delta)
	host.velocity.y = maxf(host.velocity.y - GRAVITY * delta, -45.0)
	host.move_and_slide()


## Turns the skeleton under `visual` into a limp physical body. Returns the
## simulator, or null when the presentation has no skeleton (procedural mobs
## keep their authored collapse, and the root gravity above still applies).
static func start_limp(visual: Node3D) -> PhysicalBoneSimulator3D:
	var skeleton := _find_skeleton(visual)
	if skeleton == null:
		return null
	if skeleton.has_meta("corpse_ragdoll"):
		var existing = skeleton.get_meta("corpse_ragdoll")
		return existing as PhysicalBoneSimulator3D
	_pause_animation(visual)
	_adopt_stray_bones(skeleton, visual)
	var candidates := _candidates(skeleton)
	if candidates.is_empty():
		return null
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "CorpseRagdoll"
	skeleton.add_child(simulator)
	var made: Array[PhysicalBone3D] = []
	for entry in candidates:
		var physical := _build_bone(entry)
		simulator.add_child(physical)
		physical.bone_name = str(entry[0])
		made.append(physical)
	if made.is_empty():
		simulator.queue_free()
		return null
	var bound := {}
	for physical in made:
		bound[physical.get_bone_id()] = true
	for physical in made:
		var bone_id := physical.get_bone_id()
		var ancestor := skeleton.get_bone_parent(bone_id)
		var jointed := false
		while ancestor >= 0:
			if bound.has(ancestor):
				jointed = true
				break
			ancestor = skeleton.get_bone_parent(ancestor)
		physical.joint_type = PhysicalBone3D.JOINT_TYPE_PIN if jointed \
			else PhysicalBone3D.JOINT_TYPE_NONE
	skeleton.set_meta("corpse_ragdoll", simulator)
	simulator.physical_bones_start_simulation()
	_poll(simulator, skeleton, 0.0, 0)
	return simulator


## True while the visible bones are still driven by physics.
static func is_limp(visual: Node3D) -> bool:
	var skeleton := _find_skeleton(visual)
	return skeleton != null and skeleton.has_meta("corpse_ragdoll")


static func _find_skeleton(visual: Node3D) -> Skeleton3D:
	if visual == null or not is_instance_valid(visual):
		return null
	if visual is Skeleton3D:
		return visual as Skeleton3D
	return _find_node(visual, "Skeleton3D") as Skeleton3D


static func _find_node(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var hit := _find_node(child, type_name)
		if hit != null:
			return hit
	return null


static func _pause_animation(visual: Node3D) -> void:
	for player in visual.find_children("*", "AnimationPlayer", true, false):
		(player as AnimationPlayer).pause()


## Some source assets carry a leaf helper (the hell goat's `neutral_bone`)
## whose vertices are the eyes but which is parented to the root instead of the
## head. It is too small to simulate and would stay in the air when the body
## falls, so attach it to the nearest simulated bone in its rest position while
## preserving its current global pose. It then follows that limb limp.
static func _adopt_stray_bones(skeleton: Skeleton3D, visual: Node3D) -> void:
	var selected := {}
	for index in skeleton.get_bone_count():
		if _is_candidate(skeleton, index):
			selected[index] = true
	if selected.is_empty():
		return
	# Only leaf bones outside every simulated chain can float. Most rigs have
	# none, so they pay no mesh scan at all.
	var strays := {}
	for index in skeleton.get_bone_count():
		if selected.has(index) or not skeleton.get_bone_children(index).is_empty():
			continue
		var ancestor := skeleton.get_bone_parent(index)
		var simulated := false
		while ancestor >= 0:
			if selected.has(ancestor):
				simulated = true
				break
			ancestor = skeleton.get_bone_parent(ancestor)
		if not simulated:
			strays[index] = true
	if strays.is_empty():
		return
	var bones_weight := {}
	var centroids := {}
	for mesh_node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance.skin == null:
			continue
		if not mesh_instance.is_visible_in_tree():
			continue
		var skin := mesh_instance.skin
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var bones = arrays[Mesh.ARRAY_BONES]
			var weights = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices == null or bones == null or weights == null:
				continue
			var count: int = vertices.size()
			if count == 0:
				continue
			var per_vertex: int = bones.size() / count
			for vertex_index in count:
				var world: Vector3 = mesh_instance.global_transform * vertices[vertex_index]
				for influence in per_vertex:
					var slot := vertex_index * per_vertex + influence
					var weight: float = weights[slot]
					if weight <= 0.001:
						continue
					var bone_id := _bind_bone(skin, bones[slot], skeleton)
					if not strays.has(bone_id):
						continue
					bones_weight[bone_id] = float(bones_weight.get(bone_id, 0.0)) + weight
					var accumulated: Vector3 = centroids.get(bone_id, Vector3.ZERO)
					centroids[bone_id] = accumulated + world * weight
	for bone_id in centroids.keys():
		var total: float = bones_weight.get(bone_id, 0.0)
		if total <= 0.5:
			continue
		var weighted: Vector3 = centroids[bone_id]
		var centroid := weighted / total
		var target := -1
		var best := INF
		for candidate in selected.keys():
			var point: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(candidate).origin
			var distance := point.distance_squared_to(centroid)
			if distance < best:
				best = distance
				target = candidate
		if target < 0:
			continue
		var keep := skeleton.get_bone_global_pose(bone_id)
		var parent_pose := skeleton.get_bone_global_pose(target)
		skeleton.set_bone_parent(bone_id, target)
		skeleton.set_bone_pose(bone_id, parent_pose.affine_inverse() * keep)
	skeleton.force_update_all_bone_transforms()


static func _bind_bone(skin: Skin, bind: int, skeleton: Skeleton3D) -> int:
	var bone_id := skin.get_bind_bone(bind)
	if bone_id >= 0:
		return bone_id
	var bind_name := skin.get_bind_name(bind)
	return skeleton.find_bone(bind_name) if bind_name != StringName() else -1


## Bone chains shared by every rig in the game. Names differ per source asset
## (`upperarm_l` / `upper_arm_l` / `upper_fore_l`), so each limb accepts its
## authored variants. Fingers, jaws and robe cloth stay children of these
## physical bones and follow them limp.
static func _candidates(skeleton: Skeleton3D) -> Array:
	var out: Array = []
	for index in skeleton.get_bone_count():
		if out.size() >= MAX_BONES:
			break
		if not _is_candidate(skeleton, index):
			continue
		var bone_name := skeleton.get_bone_name(index)
		var children := skeleton.get_bone_children(index)
		var offset := skeleton.get_bone_pose(children[0]).origin
		var half := offset.length() * 0.5
		out.append([bone_name, index, offset, half])
	return out


static func _is_candidate(skeleton: Skeleton3D, index: int) -> bool:
	if not _wanted(skeleton.get_bone_name(index).to_lower()):
		return false
	var children := skeleton.get_bone_children(index)
	if children.is_empty():
		return false
	return skeleton.get_bone_pose(children[0]).origin.length() >= 0.016


static func _wanted(lower: String) -> bool:
	if lower == "pelvis" or lower == "chest" or lower == "head":
		return true
	if lower.begins_with("spine"):
		return true
	if lower.begins_with("neck_"):
		return true
	if lower.begins_with("upperarm") or lower.begins_with("upper_arm"):
		return true
	if lower.begins_with("upper_fore"):
		return true
	if lower.begins_with("lowerarm") or lower.begins_with("lower_arm"):
		return true
	if lower.begins_with("lower_fore"):
		return true
	if lower.begins_with("hand_") or lower.begins_with("front_paw"):
		return true
	if lower.begins_with("thigh_") or lower.begins_with("shin_"):
		return true
	if lower.begins_with("calf_") or lower.begins_with("foot_"):
		return true
	if lower.begins_with("hock_"):
		return true
	if lower.begins_with("tail_01") or lower.begins_with("tail_02"):
		return true
	return lower.begins_with("wing_01") or lower.begins_with("wing_02")


static func _build_bone(entry: Array) -> PhysicalBone3D:
	var bone_name := str(entry[0])
	var offset: Vector3 = entry[2]
	var half: float = entry[3]
	var capsule := CapsuleShape3D.new()
	capsule.height = half * 2.0
	capsule.radius = maxf(half * 0.22, 0.02)
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.transform = Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0),
			Vector3(0.0, -1.0, 0.0)), Vector3.ZERO)
	var physical := PhysicalBone3D.new()
	physical.name = "CorpseBone_" + bone_name
	physical.add_child(collision)
	var up := Vector3.UP
	if up.cross(offset).length_squared() < 0.000001:
		up = Vector3.FORWARD
	var basis := Basis.looking_at(offset, up)
	physical.body_offset = Transform3D(basis, basis * Vector3(0.0, 0.0, -half))
	physical.joint_offset = Transform3D(Basis.IDENTITY,
		Vector3(0.0, 0.0, half))
	# Layer 0: a corpse never blocks a ranger, arrow or another mob. Mask 1:
	# it still collides with the terrain that catches it.
	physical.collision_layer = 0
	physical.collision_mask = 1
	physical.mass = 1.0
	physical.can_sleep = true
	physical.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical.linear_damp = 0.08
	physical.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
	physical.angular_damp = 0.25
	return physical


static func _poll(simulator: PhysicalBoneSimulator3D, skeleton: Skeleton3D,
		elapsed: float, slow_checks: int) -> void:
	if not is_instance_valid(simulator) or not is_instance_valid(skeleton):
		return
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = SETTLE_POLL
	timer.timeout.connect(_on_poll.bind(timer, simulator, skeleton,
		elapsed + SETTLE_POLL, slow_checks))
	skeleton.add_child(timer)
	timer.start()


static func _on_poll(timer: Timer, simulator: PhysicalBoneSimulator3D,
		skeleton: Skeleton3D, elapsed: float, slow_checks: int) -> void:
	timer.queue_free()
	if not is_instance_valid(simulator) or not is_instance_valid(skeleton):
		return
	var fastest := 0.0
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			var physical := child as PhysicalBone3D
			fastest = maxf(fastest, physical.linear_velocity.length())
			fastest = maxf(fastest, physical.angular_velocity.length() * 0.25)
	var slow := fastest < SETTLE_SPEED
	var next_slow := slow_checks + 1 if slow else 0
	if elapsed >= SETTLE_MAX \
			or (elapsed >= SETTLE_MIN and next_slow >= SETTLE_SLOW_CHECKS):
		_freeze(simulator, skeleton)
		return
	_poll(simulator, skeleton, elapsed, next_slow)


## Bakes the rigid bodies' last world pose into the skeleton, then retires them.
## Without the bake the renderer would snap back to the paused animation pose.
static func _freeze(simulator: PhysicalBoneSimulator3D, skeleton: Skeleton3D) -> void:
	var targets := {}
	for child in simulator.get_children():
		if child is PhysicalBone3D:
			var physical := child as PhysicalBone3D
			var bone_id := physical.get_bone_id()
			if bone_id < 0:
				continue
			targets[bone_id] = skeleton.get_global_transform().affine_inverse() \
				* (physical.global_transform * physical.body_offset.affine_inverse())
	for bone_id in targets.keys():
		var parent := skeleton.get_bone_parent(bone_id)
		var parent_pose := Transform3D.IDENTITY
		if parent >= 0:
			parent_pose = targets.get(parent, skeleton.get_bone_global_pose(parent))
		skeleton.set_bone_pose(bone_id, parent_pose.affine_inverse() * targets[bone_id])
	skeleton.force_update_all_bone_transforms()
	simulator.physical_bones_stop_simulation()
	skeleton.set_meta("corpse_limp_pose", true)
	skeleton.remove_meta("corpse_ragdoll")
	simulator.queue_free()
