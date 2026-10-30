class_name WarbandFlair
extends RefCounted
## What a mercenary does to the armour he wears, derived from his id and nothing
## else.
##
## Drops are few and the band dresses out of one stash, so eight men often stand
## in the same five pieces. The pieces stay the catalog's; the *man* does not: he
## dyes his cloth in his own livery, wears his own device on his chest and back,
## sews his own border on his hems, stains his leather, blackens or polishes his
## steel and hangs his own trophies on himself. Like the rest of a look this is a
## pure function of the id (`LookHash`), so every peer and every reload agrees and
## nothing travels the wire or needs a save field.
##
## A flair is a plain dictionary (all colours sRGB `#rrggbb`):
##   `field`, `charge`  the livery: the cloth's dye and the colour of its design
##   `design`           index into `DESIGNS` (heraldic partitions and ordinaries)
##   `motif`            index into `MOTIFS`, the device on the breast and the back
##   `hem`              index into `HEMS`, the border sewn along every open edge
##   `thread`, `thread_metal`  the embroidery thread, and how much of it is gilt
##   `leather`          the stain every strap, boot and hide is worked in
##   `finish`           index into `FINISHES`, what he has done to his steel
##   `fittings`         buckles, rivets and trims re-cast in this metal
##   `bone`             how his bone is treated (the salvage set and his trophies)
##   `feather`          the feathers he hangs on himself
##   `surcoat`          a livery surcoat over mail or plate instead of bare steel
##   `trophies`         `[{anchor, kind}]`: what hangs where (`ArmorFlair.ANCHORS`,
##                      `ArmorTrophies`), each shown only while its slot wears a piece
##   `seed`             where the paint on his plate and hide has worn through
##
## The shader (`armor_flair.gdshader`) reads `design`, `motif` and `hem` as these
## tables' indices; keep the orders together.

const LookHash = preload("res://scripts/warband/look_hash.gd")

## Medieval dyes, and the tinctures each one carries a design in: a light charge
## on a dark field and a dark charge on a light one, so the design always reads.
const FIELDS := [
	{"name": "madder", "tone": "#7d2a20", "charges": ["#d9cfb6", "#caa045", "#1f1c19"]},
	{"name": "woad", "tone": "#2b4067", "charges": ["#d9cfb6", "#caa045"]},
	{"name": "lincoln", "tone": "#3c5230", "charges": ["#d9cfb6", "#caa045", "#7d2a20"]},
	{"name": "weld", "tone": "#b68a30", "charges": ["#1f1c19", "#7d2a20", "#2b4067"]},
	{"name": "gall", "tone": "#262320", "charges": ["#d9cfb6", "#caa045", "#8e2b22"]},
	{"name": "murrey", "tone": "#5b2b46", "charges": ["#d9cfb6", "#caa045"]},
	{"name": "undyed", "tone": "#bcae8e", "charges": ["#1f1c19", "#7d2a20", "#2b4067", "#3c5230"]},
	{"name": "russet", "tone": "#8f4b25", "charges": ["#1f1c19", "#d9cfb6"]},
	{"name": "teal", "tone": "#2c5955", "charges": ["#d9cfb6", "#caa045", "#1f1c19"]},
]
## Heraldic designs, in the shader's order.
const DESIGNS := ["plain", "per_pale", "per_fess", "quarterly", "per_bend", "pale", "fess",
	"chevron", "saltire", "cross", "bend", "paly", "barry", "chequy", "lozengy"]
## Devices for the breast and the back, in the shader's order.
const MOTIFS := ["skull", "crossbones", "sun", "crescent", "star", "eye", "antlers", "rune"]
## Borders along the open edges, in the shader's order.
const HEMS := ["band", "double", "zigzag", "beads", "stitch", "crenel"]
const THREADS := [
	{"name": "gold", "tone": "#d4aa4e", "metal": 0.7},
	{"name": "silver", "tone": "#c8cbc6", "metal": 0.6},
	{"name": "linen", "tone": "#e3d8bd", "metal": 0.0},
	{"name": "black", "tone": "#1e1b18", "metal": 0.0},
	{"name": "crimson", "tone": "#9b2a22", "metal": 0.0},
	{"name": "blue", "tone": "#3b5d8f", "metal": 0.0},
]
## Leather stains; entry 0 is the authored strap brown.
const LEATHERS := ["#4a2a1a", "#3a1712", "#1c1917", "#7a5232", "#283224", "#4f3527", "#5c3d2e"]
## What a man does to his steel: a multiplier on the authored metal, a change in
## roughness and a share of the authored metallic.
const FINISHES := [
	{"name": "bright", "tint": "#ffffff", "rough": 0.0, "metal": 1.0},
	{"name": "blackened", "tint": "#4a4c50", "rough": 0.16, "metal": 0.55},
	{"name": "russet", "tint": "#a06e4c", "rough": 0.12, "metal": 0.7},
	{"name": "blued", "tint": "#62749a", "rough": -0.05, "metal": 1.0},
]
## Brass, bronze, silver, gilt, iron and copper.
const FITTINGS := ["#d1b576", "#a8733c", "#ccd0d2", "#e2ba50", "#606366", "#b86a3d"]
## Aged, bleached, smoked, ochre-rubbed and soot-blackened bone.
const BONES := ["#cdbf9f", "#e4dcc6", "#9a7a52", "#8d5a3e", "#4a423c"]
## Crow, swan, hawk and heron.
const FEATHERS := ["#262220", "#e9e4d8", "#7d5a3a", "#646a72"]

## What can hang at each kind of anchor (`ArmorFlair.ANCHORS`).
const HEAD_TROPHIES := ["feathers", "plume", "horns"]
const HIP_TROPHIES := ["skull", "beast_skull", "jaw", "bones", "feathers", "bird_skull", "rag",
	"teeth", "vertebrae"]
const SHOULDER_TROPHIES := ["skull", "spikes", "ribs", "feathers"]
const NECK_TROPHIES := ["teeth", "claws", "bones"]
const WRIST_TROPHIES := ["beads", "teeth"]
const THIGH_TROPHIES := ["long_bone", "rag", "jaw"]
const ANKLE_TROPHIES := ["rattles", "beads"]

## Independent hash streams (WarbandLooks owns 1..3).
const STREAM_CHARGE := 20
const STREAM_THREAD := 21
const STREAM_FITTINGS := 22
const STREAM_SURCOAT := 23
const STREAM_FEATHER := 24
const STREAM_SEED := 25
const STREAM_HEAD := 30
const STREAM_HEAD_SIDE := 31
const STREAM_HIP := 32
const STREAM_HIP_KIND := 33
const STREAM_SHOULDER := 34
const STREAM_SHOULDER_SIDE := 35
const STREAM_SHOULDER_KIND := 36
const STREAM_NECK := 37
const STREAM_NECK_KIND := 38
const STREAM_WRIST := 39
const STREAM_WRIST_SIDE := 40
const STREAM_WRIST_KIND := 41
const STREAM_THIGH := 42
const STREAM_THIGH_SIDE := 43
const STREAM_THIGH_KIND := 44
const STREAM_ANKLE := 45
const STREAM_ANKLE_KIND := 46

## A thread has to stand off the cloth it is sewn on by this much luminance.
const THREAD_CONTRAST := 0.22

static var _profiles: Dictionary = {}


## The flair of one mercenary. Memoised: it never changes for an id.
static func profile_for(merc_id: int) -> Dictionary:
	var id := maxi(merc_id, 1)
	if _profiles.has(id):
		return _profiles[id]
	# The livery steps with the id like the looks' palettes do, at offsets of its
	# own: a full deployment of eight wears eight fields, eight designs and eight
	# devices. The rest is hashed so it tracks none of those columns.
	var field: Dictionary = FIELDS[(id - 1) % FIELDS.size()]
	var charges: Array = field["charges"]
	var charge := str(charges[LookHash.pick(id, STREAM_CHARGE, charges.size())])
	var thread: Dictionary = _thread_for(id, str(field["tone"]), charge)
	var profile := {
		"field": str(field["tone"]),
		"charge": charge,
		"design": ((id - 1) * 4 + 5) % DESIGNS.size(),
		"motif": (id - 1 + 3) % MOTIFS.size(),
		"hem": (id - 1 + 4) % HEMS.size(),
		"thread": str(thread["tone"]),
		"thread_metal": float(thread["metal"]),
		"leather": str(LEATHERS[(id - 1 + 2) % LEATHERS.size()]),
		"finish": (id - 1) % FINISHES.size(),
		"fittings": str(FITTINGS[LookHash.pick(id, STREAM_FITTINGS, FITTINGS.size())]),
		"bone": str(BONES[(id - 1 + 1) % BONES.size()]),
		"feather": str(FEATHERS[LookHash.pick(id, STREAM_FEATHER, FEATHERS.size())]),
		"surcoat": LookHash.fraction(id, STREAM_SURCOAT) < 0.55,
		"trophies": _trophies_for(id),
		"seed": snappedf(LookHash.fraction(id, STREAM_SEED) * 16.0, 0.001),
	}
	_profiles[id] = profile
	return profile


## The thread a man sews with: his hashed favourite, unless it would vanish into
## his own cloth, in which case the next one that reads on both his field and
## his charge.
static func _thread_for(id: int, field: String, charge: String) -> Dictionary:
	var start := LookHash.pick(id, STREAM_THREAD, THREADS.size())
	var best: Dictionary = THREADS[start]
	var best_score := -1.0
	for step in THREADS.size():
		var entry: Dictionary = THREADS[(start + step) % THREADS.size()]
		var tone := Color(str(entry["tone"]))
		var score := minf(absf(tone.get_luminance() - Color(field).get_luminance()),
			absf(tone.get_luminance() - Color(charge).get_luminance()))
		if score >= THREAD_CONTRAST:
			return entry
		if score > best_score:
			best_score = score
			best = entry
	return best


## What hangs where. Every man carries something at his belt; the rest is a roll
## per place, so two men with a skull at the hip differ at the neck or the wrist.
static func _trophies_for(id: int) -> Array:
	var out: Array = []
	var hip_kind := str(HIP_TROPHIES[(id - 1) % HIP_TROPHIES.size()])
	out.append({"anchor": "hip_l", "kind": hip_kind})
	if LookHash.fraction(id, STREAM_HIP) < 0.5:
		var other := str(HIP_TROPHIES[LookHash.pick(id, STREAM_HIP_KIND, HIP_TROPHIES.size())])
		if other == hip_kind:
			other = str(HIP_TROPHIES[(HIP_TROPHIES.find(hip_kind) + 3) % HIP_TROPHIES.size()])
		out.append({"anchor": "hip_r", "kind": other})
	var head_roll := LookHash.fraction(id, STREAM_HEAD)
	if head_roll < 0.75:
		var head_kind := str(HEAD_TROPHIES[int(head_roll / 0.75 * HEAD_TROPHIES.size())
			% HEAD_TROPHIES.size()])
		var anchor := "crown"
		if head_kind == "feathers":
			anchor = "temple_l" if LookHash.fraction(id, STREAM_HEAD_SIDE) < 0.5 else "temple_r"
		out.append({"anchor": anchor, "kind": head_kind})
	if LookHash.fraction(id, STREAM_SHOULDER) < 0.45:
		var side := "shoulder_l" if LookHash.fraction(id, STREAM_SHOULDER_SIDE) < 0.5 else "shoulder_r"
		out.append({"anchor": side, "kind": str(SHOULDER_TROPHIES[
			LookHash.pick(id, STREAM_SHOULDER_KIND, SHOULDER_TROPHIES.size())])})
	if LookHash.fraction(id, STREAM_NECK) < 0.5:
		out.append({"anchor": "neck", "kind": str(NECK_TROPHIES[
			LookHash.pick(id, STREAM_NECK_KIND, NECK_TROPHIES.size())])})
	var wrist_roll := LookHash.fraction(id, STREAM_WRIST)
	if wrist_roll < 0.6:
		var wrist_kind := str(WRIST_TROPHIES[LookHash.pick(id, STREAM_WRIST_KIND, WRIST_TROPHIES.size())])
		if wrist_roll < 0.2:
			out.append({"anchor": "wrist_l", "kind": wrist_kind})
			out.append({"anchor": "wrist_r", "kind": wrist_kind})
		else:
			var wrist := "wrist_l" if LookHash.fraction(id, STREAM_WRIST_SIDE) < 0.5 else "wrist_r"
			out.append({"anchor": wrist, "kind": wrist_kind})
	if LookHash.fraction(id, STREAM_THIGH) < 0.35:
		var thigh := "thigh_l" if LookHash.fraction(id, STREAM_THIGH_SIDE) < 0.5 else "thigh_r"
		out.append({"anchor": thigh, "kind": str(THIGH_TROPHIES[
			LookHash.pick(id, STREAM_THIGH_KIND, THIGH_TROPHIES.size())])})
	if LookHash.fraction(id, STREAM_ANKLE) < 0.35:
		var ankle_kind := str(ANKLE_TROPHIES[LookHash.pick(id, STREAM_ANKLE_KIND, ANKLE_TROPHIES.size())])
		out.append({"anchor": "ankle_l", "kind": ankle_kind})
		out.append({"anchor": "ankle_r", "kind": ankle_kind})
	return out
