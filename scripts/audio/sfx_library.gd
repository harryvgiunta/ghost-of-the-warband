class_name SfxLibrary
extends RefCounted
## The one table of one-shots: which built files an event plays, how loud, and
## how wide the take-to-take spread is.
##
## `tools/slice_game_audio.py` builds exactly these names. A count here is the
## number of takes that tool wrote, so adding a window there and a count here is
## the whole of adding a variant.
##
## A row may name its own `dir` (default `DIR`) and a `pool`: `step` for boots
## and `voice` for a line somebody says. `VoiceLibrary` registers the spoken
## rows at run time - the take, the level and the pitch spread are rows here;
## chance, cooldown and threshold belong to that table.

const DIR := "res://assets/audio/sfx/"
## `AudioStreamPlayer3D.AttenuationModel` as this engine numbers it: inverse
## distance is 0 and inverse square is 1, which is the falloff an entry asks for
## when it wants to be heard only up close.
const ATTENUATION_INVERSE_SQUARE := 1

## event -> folder, stem, takes, level (dB on the SFX bus), pitch spread.
## Levels follow the mix hierarchy: a landed blow is the loudest thing in a
## fight, a whoosh is information, steel-on-steel is punctuation.
##
## A row may name a `bus`. The manager routes that event to it instead of `SFX`;
## `Reverb` returns into `SFX`, so the effects slider still owns the level. Only
## the voices that want a tail are rowed there - the menu thud and the soul
## changing bodies - because a reverb on every contact turns a fight into a hall.
const EVENTS := {
	"swing_1h": {"folder": "swing", "stem": "short_whoosh", "count": 13,
		"db": -10.0, "pitch": [0.92, 1.08]},
	# A dagger's air is a whisper, not a sword's whoosh: the impact below is the
	# event a stab is heard as, so the flick only says "something moved".
	"swing_dagger": {"folder": "swing", "stem": "dagger_whoosh", "count": 6,
		"db": -22.0, "pitch": [1.04, 1.14]},
	"stab_dagger": {"folder": "swing", "stem": "dagger_whoosh", "count": 6,
		"db": -26.0, "pitch": [0.9, 1.0]},
	"swing_2h": {"folder": "swing", "stem": "long_whoosh", "count": 1,
		"db": -7.0, "pitch": [0.94, 1.04]},
	"hit_blade": {"folder": "impact", "stem": "slit", "count": 8,
		"db": -3.0, "pitch": [0.96, 1.06]},
	"hit_blunt": {"folder": "impact", "stem": "blunt", "count": 3,
		"db": -1.0, "pitch": [0.94, 1.04]},
	# The stab's own impact is the loud half of the pair: the flick that led to
	# it is nearly silent, this is a blade going into a body.
	"hit_dagger": {"folder": "impact", "stem": "slit", "count": 8,
		"db": -1.5, "pitch": [0.88, 0.98]},
	"block": {"folder": "defense", "stem": "clash", "count": 4,
		"db": -4.0, "pitch": [0.96, 1.04]},
	# A club, a branch or a staff taking a blow: the blunt take, low and short.
	"block_wood": {"folder": "impact", "stem": "blunt", "count": 3,
		"db": -12.0, "pitch": [0.78, 0.9]},
	# A dagger stopping a blade: a bright tink with nothing behind it.
	"block_dagger": {"folder": "defense", "stem": "parry", "count": 4,
		"db": -24.0, "pitch": [1.1, 1.2]},
	"parry": {"folder": "defense", "stem": "parry", "count": 4,
		"db": -3.0, "pitch": [0.98, 1.06]},
	"arrow": {"folder": "bow", "stem": "arrow", "count": 1,
		"db": -4.0, "pitch": [0.97, 1.05]},
	# A padlock and its chain being worked open: the camp's four latches. It is
	# an interaction, so it sits forward of the combat bed and only a few metres
	# of range - the sound of your own hand at the bars.
	"cage_latch": {"folder": "cage", "stem": "cage_latch", "count": 4,
		"db": -7.0, "pitch": [0.94, 1.04],
		"unit_size": 4.0, "max_distance": 30.0, "cutoff": 9000.0},
	"throw": {"folder": "thrown", "stem": "blade", "count": 3,
		"db": -7.0, "pitch": [0.94, 1.06]},
	# The one menu/UI tick: the latch transient cut small, pitched bright and sat
	# well under everything, because a click is the player's own hand, not an
	# event in the world.
	"ui_click": {"folder": "cage", "stem": "cage_latch", "count": 4,
		"db": -12.0, "pitch": [1.34, 1.48]},
	# The four campaign doors. A blunt take pitched down into the floor and sent
	# through the reverb bus: the weight of a door closing, not a drum.
	"menu_thud": {"folder": "impact", "stem": "blunt", "count": 3,
		"db": -2.0, "pitch": [0.62, 0.72], "bus": "Reverb"},
	# The soul leaving one body for another: a short whoosh held low and pushed
	# through the room, so it reads as something passing rather than as a swing.
	"body_swap": {"folder": "swing", "stem": "dagger_whoosh", "count": 6,
		"db": -17.0, "pitch": [0.72, 0.84], "bus": "Reverb"},
	# A piece lifted off the ground: the latch transient, bright and small, at
	# the drop's own position and only inside a room's reach.
	"pickup": {"folder": "cage", "stem": "cage_latch", "count": 4,
		"db": -10.0, "pitch": [1.08, 1.2],
		"unit_size": 4.0, "max_distance": 26.0, "cutoff": 9000.0},
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

## Rows registered at run time. The voice table lives in `VoiceLibrary` because
## a voice is more than a take count - it has a chance, a cooldown and a
## threshold - but which file plays and at what level is this table's business,
## so a voice registers the same row shape an event does and the one mixer below
## plays both.
static var _registered: Dictionary = {}
static var _cache: Dictionary = {}


## Add one event the const table does not carry. Re-registering the same name
## replaces the row, because a voice table rebuilt (or injected by a regression)
## must not leave the previous counts behind.
static func register(event: String, row: Dictionary) -> void:
	if event.is_empty() or row.is_empty():
		return
	_registered[event] = row
	for key in _cache.keys():
		if str(key).begins_with(event + "#"):
			_cache.erase(key)


static func has(event: String) -> bool:
	return EVENTS.has(event) or _registered.has(event)


static func entry(event: String) -> Dictionary:
	var row: Dictionary = EVENTS.get(event, {})
	return row if not row.is_empty() else _registered.get(event, {})


static func path(event: String, index: int = 0) -> String:
	var row := entry(event)
	if row.is_empty():
		return ""
	var take := clampi(index, 0, int(row.get("count", 1)) - 1)
	return "%s%s/%s_%02d.ogg" % [str(row.get("dir", DIR)), row.get("folder", ""),
		row.get("stem", ""), take + 1]


## The loaded take, cached. A missing file returns null and the event is silent
## rather than fatal: audio never takes a scene down.
static func stream(event: String, index: int = 0) -> AudioStream:
	var key := "%s#%d" % [event, clampi(index, 0, int(entry(event).get("count", 1)) - 1)]
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
	var names: Array = EVENTS.keys()
	for event in _registered.keys():
		if not names.has(event):
			names.append(event)
	return names
