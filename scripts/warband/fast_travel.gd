class_name FastTravel
extends RefCounted
## The band's one way home: the sheet's RETURN TO HEARTHSTEAD, and the three
## reasons it is refused.
##
## The lane is 1,375 m long and the campaign's one settlement stands at its
## northern end, so a band the road has carried a kilometre out - or a band that
## walked the whole lane for a hire - otherwise walks every metre of it back to
## the fire. This is that walk, taken at once.
##
## **Three doors stay shut**, because travelling out of them would be a way to
## cheat a fight the campaign has already said the band cannot walk away from:
##
##   * a party below in the Weeping Hollow (`delve_area.below()`),
##   * a ring holding a fight (`arena.is_open()`),
##   * and a band already standing in the square, which has nowhere to go.
##
## A guest is refused too: the world is the host's, and so is every decision about
## where the warband stands in it.
##
## Nothing here keeps a second copy of the world's bookkeeping. The posts are the
## town's own (`spawn_posts()`), the seating is the town's own
## (`place_warband()`, exactly as the world seats a fresh campaign), the bookmark
## is dropped through the world's own save path (`_save_checkpoint()`), and the
## squad's knowledge of the ground is the squad's own (`relocate()`). A body that
## was down or dead is left exactly where it fell: the trip moves the bodies that
## can walk and wakes nobody.

## The bookmark a trip home writes: the town's own id and label, so a reload from
## it seats the band at the fire like any other town resume.
const CHECKPOINT_ID := "town"
const CHECKPOINT_LABEL := "HEARTHSTEAD"


## Whether the band may make the trip, and the line to give for it. `host` is the
## world scene; anything with the same names - a stub in a regression - answers it.
static func can_travel(host) -> Dictionary:
	if host == null:
		return _no("There is no world to travel.")
	if _flag(host, "_client"):
		return _no("A guest does not travel: the world is the host's.")
	var town = host.get("town")
	if town == null:
		return _no("Hearthstead is not in this world.")
	# The Hollow first: a party below is out of the square in the book's eyes, and
	# the reason to give is the shaft, not the distance.
	var delve = host.get("delve_area")
	if delve != null and delve.has_method("below") and bool(delve.below()):
		return _no("The party is below in the Hollow. It climbs out first.")
	var ring = host.get("arena")
	if ring != null and ring.has_method("is_open") and bool(ring.is_open()):
		return _no("The ring is holding a fight. There is no leaving it.")
	var actor = _focus(host)
	# A band on its back - every body down, dead or freed - would be a trip that
	# moved nobody and emptied the town's own record of the square: it stays where
	# it lies, and the reason says so.
	if actor == null or _standing(host).is_empty():
		return _no("No body of this band is on its feet to make the trip.")
	if town.has_method("in_square") and bool(town.in_square(actor)):
		return _no("The band already stands in the square.")
	return {"ok": true, "reason": ""}


## Take the band home. Returns what `can_travel` returns, plus how many bodies the
## trip moved and whether the bookmark was written; the refusing answer never
## touches the world.
static func travel(host) -> Dictionary:
	var verdict := can_travel(host)
	if not bool(verdict.get("ok", false)):
		return verdict
	var town = host.get("town")
	var moved := _standing(host)
	var posts: Array = town.spawn_posts() if town.has_method("spawn_posts") else []
	if posts.is_empty():
		return _no("Hearthstead has no ground to stand the band on.")
	var centre: Vector3 = (town as Node3D).global_position
	for index in moved.size():
		var post: Vector3 = posts[index % posts.size()]
		_move_into(moved[index], centre + post, centre)
	# The town's own seating, so its record of what stands in the square and every
	# body's own spawn point are the town's answers and not ours. It sets the same
	# posts again: the positions are already there, and the bookkeeping lands.
	if town.has_method("place_warband"):
		town.place_warband(moved)
	_wake_soul(host, moved)
	var written := _drop_bookmark(host, moved, town)
	_forget_the_road(host)
	return {"ok": true, "reason": "The band stands about the fire in Hearthstead.",
		"moved": moved.size(), "checkpoint": written}


# --- the pieces ------------------------------------------------------------

## The bodies a trip carries: standing, fielded, and this world's. Every other one
## - down, dead, freed under us - is left where it is, in the state it is in.
static func _standing(host) -> Array:
	var out: Array = []
	var source = host.get("bodies")
	if not (source is Array):
		return out
	for body in source as Array:
		if body == null or not is_instance_valid(body) or not (body is Node3D):
			continue
		var alive = body.get("alive")
		if alive != null and not bool(alive):
			continue
		var downed = body.get("downed")
		if downed != null and bool(downed):
			continue
		out.append(body)
	return out


## The body a question about "the band" is asked of: the soul's own, and failing
## that the first body on its feet.
static func _focus(host):
	var controller = host.get("controller")
	if controller != null and controller.has_method("focus_body"):
		var actor = controller.focus_body()
		if actor != null and is_instance_valid(actor) and actor is Node3D:
			return actor
	var standing := _standing(host)
	return standing[0] if not standing.is_empty() else null


## One body's end of the trip: the body's own move, so velocity, the timeline and
## the rig all arrive together instead of being interpolated across the whole lane,
## and the posture turned toward the fire it has come back to.
static func _move_into(body, at: Vector3, centre: Vector3) -> void:
	var toward := centre - at
	var yaw := atan2(-toward.x, -toward.z) if toward.length_squared() > 0.0001 else 0.0
	if body.has_method("teleport_to"):
		body.teleport_to(at, yaw)
	else:
		(body as Node3D).global_position = at
	(body as Node3D).velocity = Vector3.ZERO
	if body.get("spawn_point") != null:
		body.spawn_point = at


## The soul goes on riding the body it rode. That body travelled, so the eye snaps
## to where it now stands rather than arcing the length of the road after it; a
## soul whose body was left behind - down on the lane, dead - wakes in a body that
## did travel, because a spectator in a square is not a homecoming.
static func _wake_soul(host, moved: Array) -> void:
	var controller = host.get("controller")
	if controller == null:
		return
	var peer := int(controller.get("local_peer_id"))
	var riding: int = int(controller.merc_for_peer(peer))
	var ridden = controller.body_of(riding) if riding > 0 else null
	if riding > 0 and ridden != null and not moved.has(ridden) and not moved.is_empty():
		controller.direct(peer, int(controller.merc_of(moved[0])))
	var eye = controller.focus_body()
	var rig = controller.get("camera_rig")
	if eye != null and is_instance_valid(eye) and rig != null and rig.has_method("follow"):
		rig.follow(eye, true)


## The bookmark, through the world's own save path and at the square's own feet -
## the exact record `_check_checkpoints()` writes for a band standing in the town,
## so a wipe reloads into the same homecoming.
static func _drop_bookmark(host, moved: Array, town) -> bool:
	if not host.has_method("_save_checkpoint"):
		return false
	var seat = _focus(host)
	if seat == null and not moved.is_empty():
		seat = moved[0]
	var at: Vector3 = (seat as Node3D).global_position if seat != null \
		else (town as Node3D).global_position
	host._save_checkpoint(CHECKPOINT_ID, CHECKPOINT_ID, at, CHECKPOINT_LABEL)
	return true


## The squad's own memory of the lane: footprints, routes, fight clocks and the
## pieces it gave up on all describe ground the band no longer holds, and a brain
## still holding them walks back up the road it just left.
static func _forget_the_road(host) -> void:
	var squad = host.get("squad")
	if squad != null and squad.has_method("relocate"):
		squad.relocate()


static func _flag(host, name: String) -> bool:
	var value = host.get(name)
	return value != null and bool(value)


static func _no(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
