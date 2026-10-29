class_name SfxLibrary
extends RefCounted
## The one table of one-shots: which built files an event plays, how loud, and
## how wide the take-to-take spread is.
##
## `tools/slice_game_audio.py` builds exactly these names. A count here is the
## number of takes that tool wrote, so adding a window there and a count here is
## the whole of adding a variant.

const DIR := "res://assets/audio/sfx/"

## event -> folder, stem, takes, level (dB on the SFX bus), pitch spread.
## Levels follow the mix hierarchy: a landed blow is the loudest thing in a
## fight, a whoosh is information, steel-on-steel is punctuation.
const EVENTS := {
	"swing_1h": {"folder": "swing", "stem": "short_whoosh", "count": 13,
		"db": -10.0, "pitch": [0.92, 1.08]},
	"swing_dagger": {"folder": "swing", "stem": "dagger_whoosh", "count": 6,
		"db": -15.0, "pitch": [1.04, 1.14]},
	"swing_2h": {"folder": "swing", "stem": "long_whoosh", "count": 1,
		"db": -7.0, "pitch": [0.94, 1.04]},
	"hit_blade": {"folder": "impact", "stem": "slit", "count": 8,
		"db": -3.0, "pitch": [0.96, 1.06]},
	"hit_blunt": {"folder": "impact", "stem": "blunt", "count": 3,
		"db": -1.0, "pitch": [0.94, 1.04]},
	"hit_dagger": {"folder": "impact", "stem": "slit", "count": 8,
		"db": -8.0, "pitch": [1.06, 1.16]},
	"block": {"folder": "defense", "stem": "clash", "count": 4,
		"db": -4.0, "pitch": [0.96, 1.04]},
	"parry": {"folder": "defense", "stem": "parry", "count": 4,
		"db": -3.0, "pitch": [0.98, 1.06]},
	"arrow": {"folder": "bow", "stem": "arrow", "count": 1,
		"db": -4.0, "pitch": [0.97, 1.05]},
	"throw": {"folder": "thrown", "stem": "blade", "count": 3,
		"db": -7.0, "pitch": [0.94, 1.06]},
}

static var _cache: Dictionary = {}


static func has(event: String) -> bool:
	return EVENTS.has(event)


static func entry(event: String) -> Dictionary:
	return EVENTS.get(event, {})


static func path(event: String, index: int = 0) -> String:
	var row: Dictionary = EVENTS.get(event, {})
	if row.is_empty():
		return ""
	var take := clampi(index, 0, int(row.get("count", 1)) - 1)
	return "%s%s/%s_%02d.ogg" % [DIR, row.get("folder", ""), row.get("stem", ""), take + 1]


## The loaded take, cached. A missing file returns null and the event is silent
## rather than fatal: audio never takes a scene down.
static func stream(event: String, index: int = 0) -> AudioStream:
	var key := "%s#%d" % [event, clampi(index, 0, int(EVENTS.get(event, {}).get("count", 1)) - 1)]
	if _cache.has(key):
		return _cache[key]
	var file := path(event, index)
	if not ResourceLoader.exists(file):
		push_warning("SfxLibrary: missing one-shot %s" % file)
		return null
	var loaded := load(file) as AudioStream
	_cache[key] = loaded
	return loaded


static func events() -> Array:
	return EVENTS.keys()
