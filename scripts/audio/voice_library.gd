class_name VoiceLibrary
extends RefCounted
## Who in this world has a voice, which lines they have, and how often a body is
## allowed to say them.
##
## A voice is a folder of takes - `assets/audio/voice/<voice>/<stem>_NN.ogg` -
## and one row per cue. The row says what the cue is for: a level, a pitch
## spread, a chance it fires at all, a cooldown before the same body may say it
## again and, for a line that answers a blow, the share of the pool that blow
## has to take. `SfxLibrary` still owns the take itself, so a line is played by
## the same mixer as a sword landing; this table only decides *whether* and
## *which*.
##
## The files are the only thing a new voice needs. `ensure()` probes the folder
## for the takes that are actually there, so a voice whose recording has not
## been delivered registers nothing and every cue for it is a silent no-op -
## no warning per call, no missing-stream spam. `missing()` is the audit: it
## names the voices and stems whose takes are not on disk yet.
##
## This is the healthy mix the game asks for, in one place:
##   * the *trigger* is logical - a wolf that commits a bite, a body that takes
##     a blow over its threshold, a keeper that is spoken to;
##   * the *cue* is picked by the body's own state, never by a timer;
##   * the *decision to speak* is random - `chance`, then a per-cue cooldown, so
##     a fight has breath in it and a kill does not always get a quip;
##   * the *take* is random too, never twice running (`Audio._variant_for`), and
##     every take carries a pitch spread so three growls are nine sounds.

const DIR := "res://assets/audio/voice/"
## The pool a spoken line plays on (see `AudioManager.VOICES_VOICE`): long
## sounds never steal a combat voice, and a blow never cuts a line.
const POOL := "voice"

## The warband's party speaks with five profiles. A profile is not a cue: it is
## the same two beats recorded five ways, so the band sounds like five men
## instead of one man five times. `profile_for()` hands one to each mercenary.
const PROFILES := ["sergeant", "veteran", "bruiser", "scout", "hothead"]

## What the party has to say, and how rarely. One line per engagement at most,
## and a one-in-a-hundred roll at that: the shots are the point, so a squad that
## talked every fight would be a squad nobody listens to. `hurt` reads the same
## - a real bite of the pool, then the roll - and its takes are the scream and
## the curse, so the heavier blow of the two sounds like the heavier blow.
const SQUAD := {
	# Something hostile has come into `engage_radius` and this body has just
	# picked it: "oh shit, here they come", "who... oh", "get ready".
	"aggro": {"stem": "aggro", "count": 3, "db": -9.0, "pitch": [0.96, 1.04],
		"chance": 0.01, "cooldown": 6.0,
		"unit_size": 5.0, "max_distance": 26.0, "cutoff": 9000.0},
	# A blow that took a real bite of the body's pool: "arrghhhh", "fuck".
	"hurt": {"stem": "hurt", "count": 2, "db": -9.0, "pitch": [0.96, 1.04],
		"chance": 0.01, "cooldown": 8.0, "share": 0.18,
		"unit_size": 5.0, "max_distance": 26.0, "cutoff": 9000.0},
}

## The keepers share one line set: the same beats - a greeting when the counter
## is approached, a word after a trade - differ only in whose takes answer them.
const KEEPER := {
	"greet": {"stem": "greet", "count": 3, "db": -9.0, "pitch": [0.94, 1.06],
		"chance": 1.0, "cooldown": 6.0,
		"unit_size": 4.0, "max_distance": 22.0, "cutoff": 9000.0},
	"done": {"stem": "done", "count": 2, "db": -11.0, "pitch": [0.96, 1.04],
		"chance": 0.8, "cooldown": 2.0,
		"unit_size": 4.0, "max_distance": 22.0, "cutoff": 9000.0},
}

## voice -> cue -> the row.
##
## `stem`/`count` name the takes (`count` is the cap; the probe stops at the
## first missing index). `db` is the line's place in the mix. `chance` is the
## odds it fires when asked, `cooldown` the seconds before the same body may say
## that cue again, and `share` the fraction of max health a blow must take for a
## damage cue to answer it at all.
const VOICES := {
	## The briar wolf: the framework's reference voice, and the only one whose
	## recordings are shipped today.
	"wolf": {
		# A growl going into the bite, not on the swing: the telegraph is what
		# the player is being asked to answer, so the sound gives the windup away
		# to a player who cannot see the body behind a tree.
		"attack": {"stem": "growl", "count": 3, "db": -9.0, "pitch": [0.94, 1.06],
			"chance": 0.45, "cooldown": 5.0,
			"unit_size": 9.0, "max_distance": 48.0, "cutoff": 11000.0},
		# The death: every time, and once. It carries furthest in the mix because
		# a pack that hears one go down is information the player earned.
		"death": {"stem": "death", "count": 6, "db": -4.0, "pitch": [0.80, 0.90],
			"chance": 1.0, "cooldown": 0.0,
			"unit_size": 10.0, "max_distance": 56.0, "cutoff": 11000.0},
	},
	## The player characters: the soul's body and every squadmate, one voice.
	## `ArenaActor.voice_id` names the voice a body speaks with, so a mercenary
	## with its own delivered lines only has to be pointed at a new row.
	"player": {
		# A blow that took a real bite: a grunt of effort and pain.
		"hurt": {"stem": "hurt", "count": 3, "db": -8.0, "pitch": [0.92, 1.04],
			"chance": 0.55, "cooldown": 3.5, "share": 0.18},
		# A hit that could have ended it: the line the player will remember, so
		# it is rare in both senses - it needs a heavy blow and then the roll.
		"big_hit": {"stem": "big_hit", "count": 2, "db": -5.0, "pitch": [0.94, 1.02],
			"chance": 0.70, "cooldown": 8.0, "share": 0.35},
		# The body just put something down: not every kill, and never twice in a
		# breath (`cooldown`), because a body that narrates every swing is noise.
		"kill": {"stem": "kill", "count": 3, "db": -11.0, "pitch": [0.94, 1.06],
			"chance": 0.35, "cooldown": 7.0},
		# Downed: the first gasp, then a ragged moan while the bleed clock runs
		# (`VoiceEmitter.DOWNED_AFTER` paces the rest).
		"downed": {"stem": "downed", "count": 3, "db": -12.0, "pitch": [0.90, 0.98],
			"chance": 0.90, "cooldown": 0.0},
	},
	## The party's five profiles. `ArenaActor.voice_id` is set from
	## `profile_for(merc_id)` when a warband body is spawned, and nothing else
	## about the body changes: same stats, same look, one man's mouth.
	"sergeant": SQUAD,
	"veteran": SQUAD,
	"bruiser": SQUAD,
	"scout": SQUAD,
	"hothead": SQUAD,
	## The town's keepers. They answer the one interaction the square has: a
	## counter being used. `greet` is what they say when you walk up, `done` is
	## the short answer after they have taken your coin - dialogue, not a quest
	## journal, so a quest line is a new cue in this row and nothing else.
	"orla": KEEPER,
	"brann": KEEPER,
	"vey": KEEPER,
	"quartermaster": KEEPER,
}

static var _built := false
static var _events: Dictionary = {}
static var _absent: Array[String] = []


## Probe the folders and register what is actually there with `SfxLibrary`. Runs
## once per process: the table is const, so the only thing that can change the
## answer during a session is a recording appearing on disk, which is a restart.
static func ensure() -> void:
	if _built:
		return
	_built = true
	_events.clear()
	_absent.clear()
	for voice in VOICES.keys():
		var cues: Dictionary = VOICES[voice]
		for cue in cues.keys():
			var spec: Dictionary = cues[cue]
			var stem := str(spec.get("stem", cue))
			var present := _take_count(voice, stem, int(spec.get("count", 1)))
			if present <= 0:
				_absent.append("%s/%s" % [voice, stem])
				continue
			var event := event_name(voice, cue)
			var row := {"dir": DIR, "folder": voice, "stem": stem, "count": present,
				"pool": POOL, "db": float(spec.get("db", 0.0)),
				"pitch": spec.get("pitch", [1.0, 1.0])}
			# The 3D shape and the bus are the take's business, so a row that
			# asks for them passes them through unchanged.
			for key in ["bus", "unit_size", "max_distance", "cutoff", "attenuation"]:
				if spec.has(key):
					row[key] = spec[key]
			SfxLibrary.register(event, row)
			if not _events.has(voice):
				_events[voice] = {}
			_events[voice][cue] = event


## The voice one mercenary speaks with, derived from their id and nothing else -
## the same rule `WarbandLooks.profile_for` uses for a body's look. Every peer and
## every reload agrees on it, so a voice is not a save field and does not travel
## the wire. Round-robin rather than a hash: five profiles over up to eight
## bodies, so the band gets all five voices before any of them repeats.
static func profile_for(merc_id: int) -> String:
	var id := maxi(merc_id, 1)
	return PROFILES[(id - 1) % PROFILES.size()]


## The mixer's name for one cue: `voice_wolf_death`.
static func event_name(voice: String, cue: String) -> String:
	return "voice_%s_%s" % [voice, cue]


## Whether this body's cue can be heard at all - the voice exists and at least
## one take of that cue is on disk.
static func has(voice: String, cue: String) -> bool:
	ensure()
	var table: Dictionary = _events.get(voice, {})
	return table.has(cue)


## The row that owns the policy for one cue, whether or not its takes exist.
static func row(voice: String, cue: String) -> Dictionary:
	var table: Dictionary = VOICES.get(voice, {})
	return table.get(cue, {})


## The takes the mixer will actually play for one cue (0 when it is silent).
static func takes(voice: String, cue: String) -> int:
	if not has(voice, cue):
		return 0
	return int(SfxLibrary.entry(event_name(voice, cue)).get("count", 0))


static func voices() -> Array:
	ensure()
	return _events.keys()


static func cues(voice: String) -> Array:
	ensure()
	return (_events.get(voice, {}) as Dictionary).keys()


## The voices and stems whose recordings are not in the tree: what a delivery
## has to fill. Sorted so the audit reads the same twice.
static func missing() -> Array[String]:
	ensure()
	var absent := _absent.duplicate()
	absent.sort()
	return absent


## How many consecutive takes of one stem are on disk, capped at `count`. The
## probe stops at the first gap so a folder that ships one take of the three a
## row expects still registers one.
static func _take_count(voice: String, stem: String, count: int) -> int:
	var present := 0
	for index in maxi(count, 1):
		if not ResourceLoader.exists(take_path(voice, stem, index)):
			break
		present += 1
	return present


static func take_path(voice: String, stem: String, index: int) -> String:
	return "%s%s/%s_%02d.ogg" % [DIR, voice, stem, index + 1]
