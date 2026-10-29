class_name VoiceEmitter
extends RefCounted
## One body's voice: the clock, the rolls and the cooldowns behind its lines.
##
## A body owns one of these and asks it for a cue when something has happened -
## a bite committed, a blow taken, a kill credited, a body going down. The
## emitter decides whether the cue is worth hearing: a random chance, a cooldown
## before this body may say the same thing again, and a floor between two
## different lines so a body never speaks twice at once. That is the whole point
## of it - "sometimes a wolf growls" is a rule, not a `randf()` at the call site,
## and it is written once where the numbers live.
##
## It is driven by the body's own frame clock (`tick`), not the wall clock: a
## headless regression can therefore step it deterministically, and a body that
## stops ticking (parked far off, or dead) cannot bank lines up.
##
## Cues that describe a *state* the body is in - the death rattle and the moan of
## a body on the ground - are exempt from the between-lines floor: they are the
## only thing that body has to say, and the dying body's last growl must not
## swallow it.

const VoiceLibraryScript = preload("res://scripts/audio/voice_library.gd")

## The floor between two different lines from one body: a body cannot grunt and
## shout on the same frame.
const GAP := 0.35
## The cues that take the floor regardless (see above).
const URGENT := ["death", "downed"]
## A body that has just gone down groans almost at once, then raggedly: the
## first moan is the blow landing, the rest are the bleed clock.
const DOWNED_AFTER := Vector2(2.6, 5.4)

## Which voice this body speaks with ("" for a body with none).
var voice := ""
## Where the line comes from. A body that is not in the tree, or a flat line, has
## no position and is played on the player's own ear instead.
var body: Node3D
## True for the body this machine is looking out of: its lines are flat, not
## placed in the world.
var flat := false
var rng := RandomNumberGenerator.new()
## Seconds of this emitter's own life; every gate is measured on it.
var clock := 0.0

var _next_at: Dictionary = {}
var _last_cue := ""
var _last_at := -1000.0
var _downed := false
var _moan_in := 0.0


## Build a body's voice. `seed_value` keeps two wolves of one pack from rolling
## the same way, which is why every body passes something of its own.
static func create(voice_id: String, node: Node3D, is_flat: bool,
		seed_value: int = 0) -> VoiceEmitter:
	var emitter := VoiceEmitter.new()
	emitter.voice = voice_id
	emitter.body = node
	emitter.flat = is_flat
	emitter.rng.seed = 20261029 + seed_value
	return emitter


## Whether this body can say this cue at all (its takes are on disk).
func has(cue: String) -> bool:
	return not voice.is_empty() and VoiceLibraryScript.has(voice, cue)


## Ask for one cue. False when the body is silent, has no takes for it, rolled
## against it, or said a different line a moment ago.
func say(cue: String) -> bool:
	if not has(cue):
		return false
	# The floor is between two *different* lines. A state cue takes it regardless:
	# a wolf that growled a moment ago and has just been killed must still be
	# heard dying. It still answers to its own cooldown and its own chance, so the
	# row stays the whole truth about how often a body says a thing.
	if not URGENT.has(cue) and _last_cue != cue and clock - _last_at < GAP:
		return false
	if clock < float(_next_at.get(cue, 0.0)):
		return false
	var chance := float(VoiceLibraryScript.row(voice, cue).get("chance", 1.0))
	if chance < 1.0 and rng.randf() >= chance:
		return false
	var at: Variant = null
	if not flat and is_instance_valid(body):
		at = body.global_position + Vector3.UP * 1.35
	if not Voice.say(voice, cue, at):
		return false
	_next_at[cue] = clock + float(VoiceLibraryScript.row(voice, cue).get("cooldown", 0.0))
	_last_cue = cue
	_last_at = clock
	return true


## A blow landed and the body is still standing. The heaviest cue the row allows
## wins: a hit that took a third of the pool is an "oh fuck", a lighter one is a
## grunt, and a graze is nothing at all. The rows carry the thresholds, so a new
## reading of "a lot of damage" is a number in the table.
func damage(share: float) -> bool:
	for cue in ["big_hit", "hurt"]:
		var row: Dictionary = VoiceLibraryScript.row(voice, cue)
		if row.is_empty():
			continue
		if share < float(row.get("share", 0.0)):
			continue
		if say(cue):
			return true
	return false


## This body put something down. Not every kill: the row's chance and cooldown
## are what make a quip land as a quip instead of a catchphrase.
func killed() -> bool:
	return say("kill")


## The body has gone down: the first moan now, the rest on the bleed clock.
func downed() -> bool:
	_downed = true
	_moan_in = rng.randf_range(DOWNED_AFTER.x, DOWNED_AFTER.y)
	return say("downed")


## Back on its feet, or past caring: stop moaning.
func stood_up() -> void:
	_downed = false
	_moan_in = 0.0


## Whether the body is on the ground, which is what paces the moans.
func is_downed() -> bool:
	return _downed


## One frame of this body's clock, and the moans of a body that is down.
func tick(delta: float) -> void:
	var step := maxf(delta, 0.0)
	clock += step
	if not _downed:
		return
	_moan_in -= step
	if _moan_in > 0.0:
		return
	_moan_in = rng.randf_range(DOWNED_AFTER.x, DOWNED_AFTER.y)
	say("downed")
