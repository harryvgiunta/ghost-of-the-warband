class_name Voice
extends RefCounted
## The one door every spoken line goes through.
##
## Call sites name *what happened*, never a file: `Voice.say("wolf", "attack")`,
## `Voice.say(keeper, "greet", counter_position)`. Which take plays, how loud and
## how it is shaped is `VoiceLibrary` + `SfxLibrary` + `Audio`; whether it is
## spoken at all is `VoiceEmitter`, which is what a body keeps for itself.
##
## `at` is a `Vector3` for a line made somewhere in the world and omitted for a
## line on the player's own body - the same split `Sfx.play` uses. A cue with no
## takes on disk is a silent no-op, so a scene never has to ask whether its
## recordings have been delivered.

const VoiceLibraryScript = preload("res://scripts/audio/voice_library.gd")


## Ask for one cue. True when the line was handed to the mixer.
static func say(voice_id: String, cue: String, at: Variant = null) -> bool:
	if not VoiceLibraryScript.has(voice_id, cue):
		return false
	var audio := _audio()
	if audio == null:
		return false
	audio.play_event(VoiceLibraryScript.event_name(voice_id, cue), at)
	return true


## Whoever landed the killing blow says something about it, if they have a voice
## and feel like it. The mob names its killer by instance id (`last_hitter`),
## which is the only record a death carries, and a body that is not one of ours
## answers nothing - a wolf can kill a ranger without speaking.
static func kill_quip(hitter_id: int) -> bool:
	if hitter_id <= 0 or not is_instance_id_valid(hitter_id):
		return false
	var killer := instance_from_id(hitter_id)
	if not is_instance_valid(killer):
		return false
	if not killer.has_method("voice_kill_quip"):
		return false
	killer.call("voice_kill_quip")
	return true


## The mixer autoload, or null in a run that has none (a bare script, a scene
## pressed together by a regression). Every entry point above is a no-op then,
## so a headless scene exercises the same paths with the same silence.
static func _audio() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Audio")
	return null
