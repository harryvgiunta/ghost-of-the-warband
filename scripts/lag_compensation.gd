extends RefCounted
## Host-side backward reconciliation: one second of real hitbox geometry.
##
## The host records every damageable body's capsule once per simulation tick.
## When a client reports the tick it was drawing, the host tests the swing, the
## skill or the shaft against those historical capsules instead of against the
## bodies that have moved on since — the strike still lands where the shooter
## saw the target, and a blow aimed at where a body is *now* but was not *then*
## is refused.
##
## Geometry is tested arithmetically rather than by moving the physics bodies:
## Godot rebuilds a body's broadphase entry during the physics step, so a body
## teleported inside a running frame is invisible to a query until the next one.
## Segment-versus-capsule distance has no such lag, is identical on every machine
## and cannot disturb the simulation it is measuring.

## History depth in ticks. The clamp is one second at 60 Hz.
const MAX_HISTORY_TICKS := 60
## Ceiling on frames kept, so a stalled clock cannot grow the buffer.
const MAX_FRAMES := 96
## Slack added to a capsule test when refusing a contact the shooter never saw.
const REJECT_MARGIN := 0.35

var frames: Array = []
var tests := 0
var accepts := 0
var rejects := 0

var _shapes: Dictionary = {}


## Appends `bodies` at `tick` and drops everything older than `history_ticks`.
func record(tick: int, bodies: Array, history_ticks: int = MAX_HISTORY_TICKS) -> void:
	if not frames.is_empty() and int(frames[-1].tick) == tick:
		return
	var nodes: Array = []
	var positions := PackedVector3Array()
	var radii := PackedFloat32Array()
	var axes := PackedFloat32Array()
	var offsets := PackedVector3Array()
	for body in bodies:
		if not is_instance_valid(body):
			continue
		if body.get("alive") == false:
			continue
		var capsule := capsule_of(body)
		nodes.append(body)
		positions.append(body.global_position)
		radii.append(float(capsule.get("radius",0.0)))
		axes.append(float(capsule.get("axis",0.0)))
		offsets.append(capsule.get("offset",Vector3.ZERO))
	frames.append({"tick": tick, "nodes": nodes, "pos": positions,
		"radius": radii, "axis": axes, "offset": offsets})
	var oldest := tick - maxi(history_ticks, 1)
	while frames.size() > 1 and int(frames[0].tick) < oldest:
		frames.pop_front()
	while frames.size() > MAX_FRAMES:
		frames.pop_front()


## The damage volume of one body, read from its own collision shape. The shape
## values are read live every tick so a crouching body records its real height.
func capsule_of(body: Node) -> Dictionary:
	var id := body.get_instance_id()
	var cached: Dictionary = _shapes.get(id,{})
	var shape_node = cached.get("node")
	if not is_instance_valid(shape_node):
		shape_node = null
		for child in body.get_children():
			if child is CollisionShape3D and child.shape != null:
				shape_node = child
				break
		if shape_node == null:
			_shapes.erase(id)
			return {}
		_shapes[id] = {"node": shape_node}
	var shape: Shape3D = shape_node.shape
	var offset: Vector3 = shape_node.position
	if shape is CapsuleShape3D:
		var capsule: CapsuleShape3D = shape
		return {"radius": capsule.radius, "axis": maxf(capsule.height*0.5-capsule.radius,0.0),
			"offset": offset}
	if shape is BoxShape3D:
		var box: BoxShape3D = shape
		return {"radius": maxf(box.size.x,box.size.z)*0.5, "axis": box.size.y*0.5, "offset": offset}
	if shape is SphereShape3D:
		var sphere: SphereShape3D = shape
		return {"radius": sphere.radius, "axis": 0.0, "offset": offset}
	return {}


func latest_tick() -> int:
	return int(frames[-1].tick) if not frames.is_empty() else -1


func oldest_tick() -> int:
	return int(frames[0].tick) if not frames.is_empty() else -1


## The recorded frame the host resolves against for `tick`: the newest one at or
## before it, or the oldest one when the request predates the history.
func frame_for(tick: int) -> Dictionary:
	if frames.is_empty():
		return {}
	var chosen: Dictionary = frames[0]
	for frame in frames:
		if int(frame.tick) <= tick:
			chosen = frame
		else:
			break
	return chosen


func _index_of(frame: Dictionary, instance_id: int) -> int:
	var nodes: Array = frame.nodes
	for index in nodes.size():
		var body = nodes[index]
		if is_instance_valid(body) and body.get_instance_id() == instance_id:
			return index
	return -1


## The capsule axis of one body at `tick`: `a` and `b` are its end caps.
func capsule_at(instance_id: int, tick: int) -> Dictionary:
	var frame := frame_for(tick)
	if frame.is_empty():
		return {}
	var index := _index_of(frame,instance_id)
	if index < 0:
		return {}
	var centre: Vector3 = frame.pos[index] + frame.offset[index]
	var half := float(frame.axis[index])
	return {"a": centre-Vector3.UP*half, "b": centre+Vector3.UP*half,
		"radius": float(frame.radius[index])}


## Where a body stood at `tick`, or `INF` when it was not recorded.
func position_at(instance_id: int, tick: int) -> Vector3:
	var frame := frame_for(tick)
	if frame.is_empty():
		return Vector3.INF
	var index := _index_of(frame,instance_id)
	return frame.pos[index] if index >= 0 else Vector3.INF


## Every body alive in that frame, for a swing that has to find its own victims.
func candidates(tick: int) -> Array:
	var frame := frame_for(tick)
	return (frame.nodes as Array).duplicate() if not frame.is_empty() else []


## Swept blade against a historical capsule.
func segment_hits(instance_id: int, tick: int, from: Vector3, to: Vector3, thickness: float) -> bool:
	var capsule := capsule_at(instance_id,tick)
	if capsule.is_empty():
		return false
	tests += 1
	var reach := float(capsule.radius) + maxf(thickness,0.0)
	var points := Geometry3D.get_closest_points_between_segments(from,to,capsule.a,capsule.b)
	var hit := points.size() == 2 and points[0].distance_to(points[1]) <= reach
	if hit:
		accepts += 1
	return hit


## Radial skill or blast against a historical capsule.
func sphere_hits(instance_id: int, tick: int, centre: Vector3, radius: float) -> bool:
	var capsule := capsule_at(instance_id,tick)
	if capsule.is_empty():
		return false
	tests += 1
	var point := Geometry3D.get_closest_point_to_segment(centre,capsule.a,capsule.b)
	var hit := point.distance_to(centre) <= float(capsule.radius) + radius
	if hit:
		accepts += 1
	return hit


## True when the shooter's own view of `instance_id` cannot explain a contact.
## Used only to refuse contacts the client never had; a body with no recorded
## history is always allowed.
func refuses(instance_id: int, tick: int, from: Vector3, to: Vector3, thickness: float) -> bool:
	var capsule := capsule_at(instance_id,tick)
	if capsule.is_empty():
		return false
	var points := Geometry3D.get_closest_points_between_segments(from,to,capsule.a,capsule.b)
	if points.size() != 2:
		return false
	var missed := points[0].distance_to(points[1]) - float(capsule.radius) - thickness
	if missed > REJECT_MARGIN:
		rejects += 1
		return true
	return false


func clear() -> void:
	frames.clear()
	_shapes.clear()
