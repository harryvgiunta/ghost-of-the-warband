extends RefCounted
## The one hash every derived look reads: a mercenary's face, cut and height
## (`WarbandLooks`) and his livery and trophies (`WarbandFlair`).
##
## Written out instead of using `hash()` because these numbers decide what a body
## wears on every peer and in every save: they have to come out the same on both
## machines, forever, and `hash()` is free to change. A stream is one independent
## question asked of an id, so a man's shirt has nothing to do with his hair.


## A deterministic index in `0..count-1` for one (id, stream) pair.
static func pick(merc_id: int, stream: int, count: int) -> int:
	if count <= 0:
		return 0
	return value(merc_id, stream) % count


## A deterministic fraction in `0..1` for one (id, stream) pair.
static func fraction(merc_id: int, stream: int) -> float:
	return float(value(merc_id, stream) & 0xFFFFFF) / float(0x1000000)


## The raw 32-bit hash of one (id, stream) pair.
static func value(merc_id: int, stream: int) -> int:
	var mixed: int = merc_id * 2246822519 + stream * 3266489917 + 0x9E3779B1
	return _scramble(mixed) & 0xFFFFFFFF


static func _scramble(seed: int) -> int:
	var x: int = seed & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 0x7FEB352D) & 0xFFFFFFFF
	x = ((x ^ (x >> 15)) * 0x846CA68B) & 0xFFFFFFFF
	x = (x ^ (x >> 16)) & 0xFFFFFFFF
	return x
