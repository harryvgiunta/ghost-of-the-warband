extends Node
## The one sweep that parks the wilderness.
##
## A body past `MobLod.DORMANT_DISTANCE` from every ranger cannot be seen and
## cannot see: at that range the frontier's fog is already opaque. Left on its
## tick budget it still costs a tick twenty-four frames in three, for a body
## nobody is looking at. This node is what replaces that cost: three sweeps a
## second over the `wild_mobs` group, and a parked body has no physics process,
## no draw call and no state change until a ranger walks back inside
## `MobLod.WAKE_DISTANCE`.
##
## The rule stays with the body (`mob_lod_sweep`): only a body knows its
## rangers, whether something is hunting it, whether its feet are down and
## which node to hide. This node owns the clock, so a new mob family only has
## to answer that one call.

const MobSenses = preload("res://scripts/mob_senses.gd")
const Perf = preload("res://scripts/perf_probe.gd")

## Seconds between sweeps. A sprinting ranger covers 2.5 m in this time and the
## hysteresis band is 20 m wide, so nothing can pass through the band unseen.
const INTERVAL := 0.35

## Sweeps run so far, and bodies found parked by the last one: diagnostics for
## the budget regression and the session log.
var sweeps := 0
var parked := 0

var _elapsed := 0.0
## Where the eyes are: the warband's bodies, whoever is inside them. A sweep that
## measures from the host's own body alone parks a mob standing in front of a
## guest two hundred metres away - a frozen wolf with no brain behind it, on the
## screen of the soul that is looking straight at it. The scene hands its own
## controller over (`attach`); without one every body keeps its own ranger check.
var souls = null


## Point the sweeps at the warband whose bodies are the eyes.
func attach(controller) -> void:
	souls = controller


## How far `point` is from the nearest body on the field, or -1 when there is no
## field to measure from.
func nearest_eye(point: Vector3) -> float:
	if souls == null:
		return -1.0
	var best := INF
	for actor in souls.bodies():
		if not is_instance_valid(actor):
			continue
		best = minf(best, point.distance_squared_to((actor as Node3D).global_position))
	if best == INF:
		return -1.0
	return sqrt(best)


## How far `point` is from the eye *this machine draws through*, or -1 when there
## is no camera (a headless run, a scene with no eye yet).
##
## The two distances answer two different questions and must not be one number.
## The tick budget follows every soul, because a guest's fight has to be real on
## the host. What a body is *drawn* at - its shadow pass, its animation solve,
## whether its rig keeps its own clock - follows this camera alone: a host whose
## own ranger stands two hundred metres from the guest's was paying full detail
## for the whole of that fight, on a body at the edge of nothing.
func view_distance(point: Vector3) -> float:
	if not is_inside_tree():
		return -1.0
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return -1.0
	return point.distance_to(camera.global_position)


func _process(delta: float) -> void:
	Perf.begin("mob.cull")
	_tick_sweep(delta)
	Perf.end()


func _tick_sweep(delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = fmod(_elapsed, INTERVAL)
	sweep()


## One pass over every wilderness body: each works out for itself whether it
## parks or wakes. Bodies from other families (a sealed delve wave, an arena
## bot) simply do not answer `mob_lod_sweep` and are left alone.
func sweep() -> void:
	sweeps += 1
	var sleeping := 0
	# The eye list once per sweep: three sweeps a second over three hundred bodies
	# is three hundred walks of the party per sweep otherwise.
	var eyes: Array = []
	if souls != null:
		for actor in souls.bodies():
			if is_instance_valid(actor):
				eyes.append((actor as Node3D).global_position)
	# The drawing eye once, not once a body: three hundred bodies walked the
	# viewport three hundred times a sweep for one camera.
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	for body in get_tree().get_nodes_in_group(MobSenses.GROUP):
		if not is_instance_valid(body):
			continue
		if not body.has_method("mob_lod_sweep"):
			continue
		var at: Vector3 = (body as Node3D).global_position
		var nearest := -1.0
		var best := INF
		for eye in eyes:
			best = minf(best, at.distance_squared_to(eye))
		if best != INF:
			nearest = sqrt(best)
		var view := -1.0
		if camera != null:
			view = at.distance_to(camera.global_position)
		body.mob_lod_sweep(nearest, view)
		if bool(body.get("dormant")):
			sleeping += 1
	parked = sleeping
