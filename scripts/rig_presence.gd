extends Node
## A scenery rig's pose clock, kept to the eye. A body that only stands about - a
## keeper at his counter, a watchman on the wall, a soldier in his cage - has no
## brain for `MobLod` to budget, so nothing stopped its rig: the town's bodies
## posed sixty times a second for a camera a kilometre away down the Hollow. Past
## `MobLod.ANIMATE_DISTANCE` from the camera the rig rests and its skeleton holds
## the last pose, the distance where every body in the wood stops animating.
##
## Presentation only. What these bodies do - a watchman's draw and his shot - runs
## on their owners' clocks and muzzles, never on the pose.

const MobLod = preload("res://scripts/mob_lod.gd")

## Seconds between two looks at the camera, the culler's own sweep: a sprint
## covers 2.5 m of the 62 m radius between two looks.
const INTERVAL := 0.35

## The rig this node rests and wakes. Owned by the caller; a freed rig is left
## alone.
var rig: Node3D

var _elapsed := 0.0
## Whether this node has the rig's clock on. Its own memory, not the rig's: a
## corpse pose or a scene that stops the rig for its own reasons is not this
## node's to undo.
var _posing := true


func _init(target: Node3D = null) -> void:
	rig = target
	name = "RigPresence"


func _ready() -> void:
	# Spread the looks, so a whole town never measures on the same frame.
	_elapsed = INTERVAL * float(get_instance_id() % 16) / 16.0
	_look()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < INTERVAL:
		return
	_elapsed = fmod(_elapsed, INTERVAL)
	_look()


func _look() -> void:
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(rig) or camera == null:
		return
	var posing := rig.global_position.distance_to(camera.global_position) <= MobLod.ANIMATE_DISTANCE
	if posing == _posing:
		return
	_posing = posing
	rig.set_physics_process(posing)
