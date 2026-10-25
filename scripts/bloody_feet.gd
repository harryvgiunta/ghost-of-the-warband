extends RefCounted
## Bloody footprints for a controllable fighter.
##
## A foot that comes down while the body is standing in a death pool leaves a
## print on the floor, using the blood already in the scene: the per-scene
## `BloodField` owns the pools and the print itself, so a trail fades with the
## spatter it came from and never outlives it. Shared by the frontier
## (`main.gd._physics_process`) and the arena/delve fighter (`arena_actor.gd`),
## so every mode a body can be standing in blood behaves the same.
##
## Presentation only: nothing here reads or writes damage, health or authority.

## A foot must fall this far below its tracked peak to count as a footfall.
const STEP_DROP := 0.05
## Seconds between two prints from the same foot. Run and walk clips bob a foot
## several times per stride; without this the trail is a smear.
const PRINT_GAP := 0.30
## How much of the pool's blood one step takes off the boot, and how fast a
## boot dries out of a pool. A soaking is ~6 prints and then clean.
const BLOOD_PER_PRINT := 0.15
const DRY_PER_SECOND := 0.01

var _field = null
var _blood := 0.0
var _peak: Array[float] = [0.0, 0.0]
var _gap: Array[float] = [0.0, 0.0]

## Call once per physics tick, after the body has moved and the rig is posed.
func update(delta: float, body: CharacterBody3D, rig: Node3D) -> void:
	if not is_instance_valid(body) or not is_instance_valid(rig):
		return
	_blood = maxf(_blood - delta * DRY_PER_SECOND, 0.0)
	_gap[0] = maxf(_gap[0] - delta, 0.0)
	_gap[1] = maxf(_gap[1] - delta, 0.0)
	var field = _field if is_instance_valid(_field) else null
	if field == null:
		# The field is created on the scene's first wound, so resolve it once
		# instead of doing a node lookup every physics frame.
		var tree := body.get_tree() if body.is_inside_tree() else null
		var scene: Node = tree.current_scene if tree != null else null
		field = scene.get_node_or_null("BloodField") if scene != null else null
		_field = field
		if field == null:
			return
	if not body.is_on_floor():
		_peak[0] = 0.0
		_peak[1] = 0.0
		return
	# Cheap pre-filter: only a body near a pool needs its foot joints sampled.
	if _blood <= 0.0 and not field.is_in_blood(body.global_position):
		return
	var joints: Dictionary = rig.get_joint_positions()
	var feet := [joints.get("left_foot", body.global_position),
		joints.get("right_foot", body.global_position)]
	for probe in feet:
		if field.is_in_blood(probe):
			_blood = 1.0
			break
	for side in 2:
		var foot: Vector3 = feet[side]
		var peak: float = _peak[side]
		# Track the lift; the print lands when the foot comes back down.
		if foot.y > peak:
			_peak[side] = foot.y
			continue
		if peak <= 0.0 or foot.y >= peak - STEP_DROP:
			continue
		_peak[side] = 0.0
		if _blood <= 0.0 or _gap[side] > 0.0:
			continue
		var travel: Vector3 = body.velocity
		travel.y = 0.0
		field.footprint(foot, travel, _blood)
		_blood = maxf(_blood - BLOOD_PER_PRINT, 0.0)
		_gap[side] = PRINT_GAP
