class_name WarbandGearDrop
extends RefCounted
## What a body lets go of when it goes down, and where it lands.
##
## One rule for both sides of a fight: a body that hits the floor drops what it
## was *holding*. Worn gear stays worn - a shield is strapped on, but it is still
## in the hand - so the two hand slots empty, the roster is the ground truth for
## what a body wears, and the piece is put in the world rather than booked into
## the shared stash. A dropped piece is on the floor, not owned by the warband: it
## has to be picked back up with `K`, or walked to by a squadmate.
##
## Enemies answer the same question through `take_weapon_item()`, which strips the
## model's own hand at the same time, so what a player sees is what a blade on the
## dirt is worth.

## The hand slots, in the order a body lets go of them: the off hand first, so a
## blade is the last thing to leave.
const DROP_SLOTS := ["off", "main"]
## How far off the body a dropped piece lands. Far enough not to be inside the
## capsule the corpse leaves behind, close enough to read as "beside it".
const DROP_OFFSET := 0.55

## Empty a mercenary's hands and answer the pieces that fell, off hand first.
## Nothing is added to the stash here: the caller puts each piece in the world,
## and the warband's worth drops by exactly what is lying in the dirt.
static func strip_hands(warband, merc_id: int) -> Array[String]:
	var out: Array[String] = []
	if warband == null or not is_instance_valid(warband) or merc_id <= 0:
		return out
	for slot in DROP_SLOTS:
		var item_id: String = warband.roster.unequip(merc_id, slot)
		if not item_id.is_empty():
			out.append(item_id)
	return out

## The catalog piece in a mob's hand, taken out of it. Answers "" for a body with
## empty hands, for one that is already gone, and for a kind of body that does not
## carry catalog gear at all.
static func strip_enemy(enemy) -> String:
	if not is_instance_valid(enemy) or not enemy.has_method("take_weapon_item"):
		return ""
	return str(enemy.take_weapon_item())

## Where a dropped piece lands: in front of the body and on the body's own
## ground, so the drop's origin is the floor the corpse lies on.
static func drop_point(body: Vector3, facing: Vector3, offset: float = DROP_OFFSET) -> Vector3:
	var flat := Vector3(facing.x, 0.0, facing.z)
	if flat.length_squared() <= 0.0001:
		return body
	flat = flat.normalized() * offset
	return Vector3(body.x + flat.x, body.y, body.z + flat.z)

## A body's own forward (-Z in Godot), flattened, or ZERO for a body with no
## transform.
static func forward_of(body) -> Vector3:
	if not (body is Node3D):
		return Vector3.ZERO
	return -(body as Node3D).global_transform.basis.z
