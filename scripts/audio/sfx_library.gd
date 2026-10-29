class_name SfxLibrary
extends RefCounted
## The one table of one-shots: which built files an event plays, how loud, and
## how wide the take-to-take spread is.
##
## `tools/slice_game_audio.py` builds exactly these names. A count here is the
## number of takes that tool wrote, so adding a window there and a count here is
## the whole of adding a variant.

const DIR := "res://assets/audio/sfx/"
## `AudioStreamPlayer3D.AttenuationModel` as this engine numbers it: inverse
## distance is 0 and inverse square is 1, which is the falloff an entry asks for
## when it wants to be heard only up close.
const ATTENUATION_INVERSE_SQUARE := 1

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
	# Boots, deliberately the quietest thing in the mix and on their own voice
	# pool: a footfall is texture, and it must never steal a voice from a blow.
	# The soul's own step is close to the ear and carries the walk.
	"footstep": {"folder": "step", "stem": "footstep", "count": 12,
		"db": -16.0, "pitch": [0.9, 1.08], "pool": "step",
		"unit_size": 5.0, "max_distance": 40.0, "cutoff": 7000.0},
	# Anybody else's boot: the same takes, far quieter, duller and gone by ten
	# metres (inverse-square falloff). A camp of eight fighters must not sound
	# like a brigade walking through the player's ear.
	"footstep_far": {"folder": "step", "stem": "footstep", "count": 12,
		"db": -30.0, "pitch": [0.86, 1.02], "pool": "step",
		"unit_size": 2.0, "max_distance": 11.0, "cutoff": 3000.0,
		"attenuation": ATTENUATION_INVERSE_SQUARE},
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
