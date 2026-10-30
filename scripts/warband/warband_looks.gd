class_name WarbandLooks
extends RefCounted
## Who a mercenary is to look at, derived from their id and nothing else.
##
## The band fields up to eight bodies on one rig, and until this existed two of
## them were the same man twice. A look is a pure function of the mercenary id:
## every peer and every reload agrees on it, so nothing about it travels the wire
## and nothing about it needs a save field. The tables come from the authoring
## tool (`tools/prepare_warband_looks.py` -> `ironwood_warband_looks.json`), so
## the palettes and the geometry variants have one source of truth.
##
## A look is a plain dictionary:
##   `height`       the rig's uniform scale, `HEIGHT_MIN`..`HEIGHT_MAX`
##   `face`         index into the authored faces (`Face<n>_Skin/Brows/Eyes`)
##   `hair`, `beard` indexes into the authored pieces; a style with no geometry
##                  (the shaved head) resolves to a name the rig simply won't find
##   `skin`, `shirt`, `shorts`, `hair_tone`  albedo tints as `#rrggbb` strings
##   `eye`          index into the authored iris tones
##   `flair`        what he does to the armour he wears (`WarbandFlair.profile_for`)
##
## The tints are sRGB hex; the rig converts them to linear once, because
## `albedo_color` multiplies in linear space.

const LookHash = preload("res://scripts/warband/look_hash.gd")
const WarbandFlair = preload("res://scripts/warband/warband_flair.gd")

const LOOKS_PATH := "res://assets/characters/warband/ironwood_warband_looks.json"
## Height as a fraction of the authored 1.87 m rig: 1.61 m to 2.13 m of man. That
## is the range the warband's own cages and camp already read as "a squad", and
## it is the only measure that changes -- stats, capsule and reach do not.
const HEIGHT_MIN := 0.86
const HEIGHT_MAX := 1.14
const HEIGHT_STEP := 0.01

## Independent hash streams, so a mercenary's shirt has nothing to do with their
## hair, and two tall men are not always the same tall.
const STREAM_HEIGHT := 1
const STREAM_BEARD := 2
const STREAM_EYE := 3

static var _looks: Dictionary = {}
static var _profiles: Dictionary = {}


## The authored tables: faces, hair styles, beards and the tone palettes.
static func data() -> Dictionary:
	if _looks.is_empty():
		var text := FileAccess.get_file_as_string(LOOKS_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_looks = parsed
		else:
			push_error("Warband look table is missing or unreadable: " + LOOKS_PATH)
	return _looks


## The look of one mercenary. Memoised: a look never changes for an id, and a
## scene fields the same bodies again on every reload.
static func profile_for(merc_id: int) -> Dictionary:
	var id := maxi(merc_id, 1)
	if _profiles.has(id):
		return _profiles[id]
	var table := data()
	if table.is_empty():
		return {}
	var faces: Array = table.get("faces", [])
	var hairs: Array = table.get("hair", [])
	var beards: Array = table.get("beards", [])
	var eye_tones: Array = table.get("eye_tones", [])
	var tones: Dictionary = table.get("tones", {})
	var height := lerpf(HEIGHT_MIN, HEIGHT_MAX, LookHash.fraction(id, STREAM_HEIGHT))
	var profile := {
		"merc_id": id,
		"height": snappedf(height, HEIGHT_STEP),
		# Face and hair step with the id instead of hashing: the eight bodies a
		# warband can deploy therefore never share a face, while everything else
		# is free to collide (two men may wear the same colour).
		"face": (id - 1) % maxi(faces.size(), 1),
		"hair": (id - 1 + 2) % maxi(hairs.size(), 1),
		"beard": LookHash.pick(id, STREAM_BEARD, beards.size()),
		"eye": LookHash.pick(id, STREAM_EYE, eye_tones.size()),
		# The colours step too, at four different offsets: a full deployment is
		# therefore eight different skins in eight different shirts over eight
		# different pairs of shorts, which is the picture the band is for. Past
		# eight bodies the palettes wrap, and two hired men may match.
		"skin": cycled(tones.get("skin", []), id, 1),
		"shirt": cycled(tones.get("shirt", []), id, 3),
		"shorts": cycled(tones.get("shorts", []), id, 5),
		"hair_tone": cycled(tones.get("hair", []), id, 2),
		"flair": WarbandFlair.profile_for(id),
	}
	profile["face_name"] = "Face%d" % (int(profile["face"]) + 1)
	profile["hair_name"] = _name_of(hairs, int(profile["hair"]), "Hair_")
	profile["beard_name"] = _name_of(beards, int(profile["beard"]), "Beard_")
	profile["eye_material"] = "Warband_Eye_%d" % int(profile["eye"])
	_profiles[id] = profile
	return profile


static func _name_of(table: Array, index: int, prefix: String) -> String:
	if index < 0 or index >= table.size():
		return ""
	var entry: Variant = table[index]
	if not entry is Dictionary:
		return ""
	if bool((entry as Dictionary).get("bare", false)):
		return ""
	return prefix + str((entry as Dictionary).get("name", ""))


## One palette entry for a mercenary, stepping with the id so a deployment's first
## bodies never share a colour.
static func cycled(palette: Array, merc_id: int, offset: int) -> String:
	if palette.is_empty():
		return "#ffffff"
	return str(palette[(merc_id - 1 + offset) % palette.size()])
