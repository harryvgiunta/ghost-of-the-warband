extends Node
## One audio authority: three buses, two music beds and the one-shot pool.
##
## Music follows the scene. `title.tscn` is the menu theme and every other scene
## is the warband's soundtrack, so a scene that forgets to start a track is not
## a silent scene - the manager already knows. A crossfade carries the switch,
## and a campaign start is allowed to cut the menu off outright and put the score
## back at zero.
##
## The soundtrack is 49 minutes long and its Ogg loop point is a cut, not a
## composition, so the seam is managed here: when the live bed comes inside
## `LOOP_FADE_SECONDS` of the end the other bed starts the same stream from zero
## and takes over, and the last seconds of the score dissolve into its first.
## Only the menu theme is looped on the stream.
##
## Volume lives on the buses, never on the voices: one slider is one
## `AudioServer` call and every stream under it follows, including a take that
## starts a second later. The value is persisted, because a mix a player set is
## a setting like any other. `Reverb` is a third bus that returns into `SFX`, so
## an event that asks for its tail still answers to the effects slider.
##
## The two streams are big (the soundtrack is a 49 minute master), so a track is
## loaded when it is wanted and dropped when the other bed takes over. Nothing
## here touches the display: a headless run keeps every setting, every bus and
## every event testable with no device to play into.

const SfxLibraryScript = preload("res://scripts/audio/sfx_library.gd")

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_REVERB := "Reverb"
const DEFAULT_SAVE_PATH := "user://audio_settings.json"
const SAVE_VERSION := 1
const MENU_SCENE := "title.tscn"
const TRACKS := {
	"menu": "res://assets/audio/music/menu_theme.ogg",
	"warband": "res://assets/audio/music/warband_soundtrack.ogg",
}
const FADE_SECONDS := 1.2
## How much of the soundtrack's tail the managed seam crossfades: the live bed
## starts the head of the stream on the other bed inside this window, so the
## loop point is never heard as a cut at full level.
const LOOP_FADE_SECONDS := 3.0
const BED_SILENCE_DB := -60.0
const VOICES_3D := 12
const VOICES_2D := 6
## Footfalls have their own pool. A walk in a fight produces two steps a second
## per body, and a footfall must never be the sound that gets cut when a blow
## needs the next voice.
const VOICES_STEP := 6
## Spoken lines have their own pool for the same reason, the other way round: a
## growl or a shout is over a second long, so one line would sit on a combat
## voice for the whole fight and a blow landing under it would be cut instead.
## Four places and four flat lines is a camp of fighters, not a crowd.
const VOICES_VOICE := 4
## The 3D shape a spoken line gets when its row does not ask for another: the
## widest in the mix, because a growl has to carry from the far side of a
## clearing and a shout does not need muffling.
const LINE_UNIT_SIZE := 9.0
const LINE_MAX_DISTANCE := 70.0
const LINE_CUTOFF := 11000.0
## The 3D shape a voice gets when its event does not ask for another: a world
## one-shot heard across the field.
const VOICE_UNIT_SIZE := 7.0
const VOICE_MAX_DISTANCE := 80.0
const VOICE_CUTOFF := 9000.0
const VOICE_ATTENUATION := AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
## Two identical one-shots from the same place inside this window are one
## contact reported twice (an attacker and a defender both noticing the blow),
## not two blows.
const DUPLICATE_WINDOW := 0.02

## Where the mix is remembered. A regression points this at its own file, the
## same way the state autoloads do.
var save_path := DEFAULT_SAVE_PATH

var music_volume := 0.8
var sfx_volume := 0.8
var music_muted := false
var sfx_muted := false
## The track this manager wants playing ("menu", "warband" or "" for silence).
## State, not a side effect: it is set even when there is no device.
var music_track := ""
## The last one-shot asked for and where, kept for the log and for a headless run
## that has no device to hear it. Never read by the mixer.
var last_event := ""
var last_event_position: Variant = null

var _beds: Array[AudioStreamPlayer] = []
var _bed_index := 0
## Which track each bed holds. Parallel to `_beds`, and cleared when the bed is
## retired: the seam has to know that the live bed is the non-looping score.
var _bed_tracks: Array[String] = ["", ""]
## The scene instance a menu restart started from, so the scene sync cannot ask
## the title for the menu theme and drag the score back while it is still up.
var _restart_scene_id := 0
var _streams: Dictionary = {}
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _voices_step: Array[AudioStreamPlayer3D] = []
var _voices_line: Array[AudioStreamPlayer3D] = []
var _voices_2d: Array[AudioStreamPlayer] = []
var _voices_flat_line: Array[AudioStreamPlayer] = []
var _voice_3d := 0
var _voice_step := 0
var _voice_line := 0
var _voice_2d := 0
var _voice_flat_line := 0
var _last_variant: Dictionary = {}
var _recent: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _fade: Tween
var _scene_id := 0


func _ready() -> void:
	# A tutorial card pauses the tree. The beds already run through it, so the
	# manager's own seam and scene watch have to as well - otherwise a card read
	# over the last seconds of the score leaves a non-looping stream stopped.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20261028
	# A headless run is not the player's session: it must never read or write the
	# mix a person set on this machine.
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = "user://audio_settings_test.json"
	_ensure_buses()
	_build_beds()
	_build_voices()
	_load_settings()
	_apply_buses()
	set_process(true)
	# A scene that is already up when the manager comes online still gets its
	# track, without waiting for the next scene change.
	_scene_id = 0
	_sync_scene_music()


func _process(_delta: float) -> void:
	_sync_scene_music()
	_seam_if_due()


## Whether there is a device to play into. Everything else - buses, volumes,
## mutes, the track the manager wants - works without one.
func is_available() -> bool:
	return DisplayServer.get_name() != "headless"


# --- volume and mutes ------------------------------------------------------

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_buses()
	_save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_buses()
	_save_settings()


func set_music_muted(muted: bool) -> void:
	music_muted = muted
	_apply_buses()
	_save_settings()


func set_sfx_muted(muted: bool) -> void:
	sfx_muted = muted
	_apply_buses()
	_save_settings()


func toggle_music_muted() -> bool:
	set_music_muted(not music_muted)
	return music_muted


func toggle_sfx_muted() -> bool:
	set_sfx_muted(not sfx_muted)
	return sfx_muted


## The dB a bus is actually set to, after the linear slider value.
func music_db() -> float:
	return linear_to_db(maxf(music_volume, 0.0001))


func sfx_db() -> float:
	return linear_to_db(maxf(sfx_volume, 0.0001))


# --- music -----------------------------------------------------------------

## Which track a scene asks for. The title is the menu; everything else - the
## town, the camp, the trail, the arena, the delve, the sandbox - is the game.
func track_for_scene(path: String) -> String:
	return "menu" if path.ends_with(MENU_SCENE) else "warband"


## Start a track, crossfading from whatever bed is up. Idempotent: asking for
## the track that is already playing is a no-op, so a scene can call it freely.
func play_music(track: String, fade: float = FADE_SECONDS) -> void:
	if not TRACKS.has(track):
		return
	if music_track == track and (not is_available() or _beds[_bed_index].playing):
		return
	music_track = track
	_note("music", {"track": track, "available": is_available()})
	if not is_available():
		return
	var from := _beds[_bed_index]
	_bed_index = 1 - _bed_index
	var to := _beds[_bed_index]
	to.stream = _stream_for(track)
	to.volume_db = BED_SILENCE_DB
	to.play()
	_bed_tracks[_bed_index] = track
	var seconds := clampf(fade, 0.05, 8.0)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(to, "volume_db", 0.0, seconds)
	if from.playing:
		_fade.tween_property(from, "volume_db", BED_SILENCE_DB, seconds)
		_fade.chain().tween_callback(_retire.bind(from))


## Start a track from the top, now. The menu uses this to hand the score over:
## the menu theme is stopped outright - no crossfade carrying the title music
## onto the first act - and the campaign track starts at zero, its own beginning
## rather than wherever a bed happened to be.
func start_campaign_music() -> void:
	# The title is still the current scene for the rest of the frame (and until
	# the next scene loads). Remember which scene asked, so `_sync_scene_music`
	# cannot answer it with the menu theme and undo the restart.
	_restart_scene_id = _scene_instance_id()
	_restart_track("warband")


func _restart_track(track: String) -> void:
	if not TRACKS.has(track):
		return
	music_track = track
	_note("music", {"track": track, "available": is_available(), "restart": true})
	if not is_available():
		return
	if _fade != null and _fade.is_valid():
		_fade.kill()
	# Both beds stop on the spot: a restart is a cut, and a half-faded bed left
	# playing would keep the menu's tail under the first bar.
	for index in _beds.size():
		var bed := _beds[index]
		bed.stop()
		bed.stream = null
		bed.volume_db = BED_SILENCE_DB
		_bed_tracks[index] = ""
	var live := _beds[_bed_index]
	live.stream = _stream_for(track)
	live.volume_db = 0.0
	_bed_tracks[_bed_index] = track
	live.play(0.0)
	_purge_streams()


## Whether the soundtrack's managed seam is due for a bed at `position` on a
## `length`-second stream. Pure, so the headless regression can prove the window
## without a device.
func seam_due(position: float, length: float) -> bool:
	if length <= LOOP_FADE_SECONDS * 2.0:
		return false
	return position >= length - LOOP_FADE_SECONDS


## The managed loop seam. The score does not loop on its stream, so when the
## live bed comes inside the fade window the other bed starts the same stream at
## zero and crossfades in over the window; the outgoing bed is retired when the
## fade lands, by which time the head of the track is already at its level.
func _seam_if_due() -> void:
	if not is_available() or music_track != "warband":
		return
	var live := _beds[_bed_index]
	if _bed_tracks[_bed_index] != "warband" or live.stream == null:
		return
	if not live.playing:
		# The score ran out before the seam could fire - a stall longer than the
		# fade window leaves a non-looping stream stopped - so start it again
		# rather than leaving the campaign silent. A deliberate stop has cleared
		# `music_track` and never gets here.
		live.volume_db = 0.0
		live.play(0.0)
		return
	if not seam_due(live.get_playback_position(), live.stream.get_length()):
		return
	_seam()


func _seam() -> void:
	var from := _beds[_bed_index]
	var track := _bed_tracks[_bed_index]
	_bed_index = 1 - _bed_index
	var to := _beds[_bed_index]
	to.stream = _stream_for(track)
	to.volume_db = BED_SILENCE_DB
	to.play(0.0)
	_bed_tracks[_bed_index] = track
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(to, "volume_db", 0.0, LOOP_FADE_SECONDS)
	_fade.tween_property(from, "volume_db", BED_SILENCE_DB, LOOP_FADE_SECONDS)
	_fade.chain().tween_callback(_retire.bind(from))
	_note("music", {"track": track, "seam": true})


func stop_music(fade: float = 0.4) -> void:
	music_track = ""
	_note("music", {"track": "", "available": is_available()})
	if not is_available():
		return
	var seconds := clampf(fade, 0.05, 8.0)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	for bed in _beds:
		if bed.playing:
			_fade.tween_property(bed, "volume_db", BED_SILENCE_DB, seconds)
			_fade.chain().tween_callback(_retire.bind(bed))


## The bed this manager is actually playing into ("" when silent). Tests and the
## settings panel read it to say what is up without asking the mixer.
func playing_track() -> String:
	if not is_available():
		return music_track
	return music_track if _beds[_bed_index].playing else ""


# --- one-shots -------------------------------------------------------------

## Play one event from `SfxLibrary`. `at` places it in the world; without it the
## take is played flat, which is right for anything on the player's own body.
func play_event(event: String, at: Variant = null) -> void:
	if not SfxLibraryScript.has(event):
		return
	last_event = event
	last_event_position = at
	if not is_available():
		return
	var row := SfxLibraryScript.entry(event)
	var key := event
	if at is Vector3:
		var point: Vector3 = at
		key = "%s@%.1f,%.1f,%.1f" % [event, point.x, point.y, point.z]
	var now := Time.get_ticks_msec() / 1000.0
	if _recent.has(key) and now - float(_recent[key]) < DUPLICATE_WINDOW:
		return
	_recent[key] = now
	if _recent.size() > 96:
		_prune_recent(now)
	var stream := SfxLibraryScript.stream(event, _variant_for(event, int(row.get("count", 1))))
	if stream == null:
		return
	var spread: Array = row.get("pitch", [1.0, 1.0])
	var pitch := _rng.randf_range(float(spread[0]), float(spread[1]))
	var level := float(row.get("db", 0.0))
	# A row may ask for another bus (`Reverb` for the menu thud and the soul
	# changing bodies). Voices are pooled, so the bus is re-stated on every play:
	# a voice that last carried a tail must not swallow the next blade.
	var bus_name := str(row.get("bus", BUS_SFX))
	var pool := str(row.get("pool", "world"))
	if at is Vector3:
		var voice: AudioStreamPlayer3D
		if pool == "step":
			voice = _voices_step[_voice_step]
			_voice_step = (_voice_step + 1) % _voices_step.size()
		elif pool == "voice":
			voice = _voices_line[_voice_line]
			_voice_line = (_voice_line + 1) % _voices_line.size()
		else:
			voice = _voices_3d[_voice_3d]
			_voice_3d = (_voice_3d + 1) % _voices_3d.size()
		voice.global_position = at
		voice.bus = bus_name
		voice.volume_db = level
		voice.pitch_scale = pitch
		voice.stream = stream
		_shape(voice, row)
		voice.play()
		return
	var flat := _voices_2d[_voice_2d] if pool != "voice" else _voices_flat_line[_voice_flat_line]
	if pool == "voice":
		_voice_flat_line = (_voice_flat_line + 1) % _voices_flat_line.size()
	else:
		_voice_2d = (_voice_2d + 1) % _voices_2d.size()
	flat.bus = bus_name
	flat.volume_db = level
	flat.pitch_scale = pitch
	flat.stream = stream
	flat.play()


# --- internals -------------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX, BUS_REVERB]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
	# The reverb bus returns *into* the effects bus rather than into Master: its
	# tail then passes through the SFX slider like everything else, and muting
	# the effects mutes the reverb with them.
	var reverb_bus := AudioServer.get_bus_index(BUS_REVERB)
	if reverb_bus >= 0:
		AudioServer.set_bus_send(reverb_bus, BUS_SFX)
		if AudioServer.get_bus_effect_count(reverb_bus) == 0:
			AudioServer.add_bus_effect(reverb_bus, _make_reverb())


## The one room the mix owns: a short, dark tail, mostly dry so a door thud is
## still a door and a soul's passage still has a direction.
func _make_reverb() -> AudioEffectReverb:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.58
	reverb.damping = 0.62
	reverb.spread = 0.7
	reverb.dry = 0.92
	reverb.wet = 0.34
	reverb.predelay_msec = 18.0
	return reverb


func _build_beds() -> void:
	for _index in 2:
		var bed := AudioStreamPlayer.new()
		bed.name = "MusicBed%d" % _beds.size()
		bed.bus = BUS_MUSIC
		bed.volume_db = BED_SILENCE_DB
		# A menu that pauses the tree still sings.
		bed.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(bed)
		_beds.append(bed)


func _build_voices() -> void:
	for index in VOICES_3D:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "Voice3D%d" % index
		voice.bus = BUS_SFX
		voice.unit_size = VOICE_UNIT_SIZE
		voice.max_db = 3.0
		voice.max_distance = VOICE_MAX_DISTANCE
		voice.attenuation_filter_cutoff_hz = VOICE_CUTOFF
		voice.panning_strength = 1.0
		add_child(voice)
		_voices_3d.append(voice)
	for index in VOICES_STEP:
		var step := AudioStreamPlayer3D.new()
		step.name = "VoiceStep%d" % index
		step.bus = BUS_SFX
		# Feet are close-range: a smaller unit size and no far field at all.
		step.unit_size = 4.0
		step.max_db = 0.0
		step.max_distance = 34.0
		step.attenuation_filter_cutoff_hz = 6000.0
		step.panning_strength = 1.0
		add_child(step)
		_voices_step.append(step)
	# Spoken lines: the widest shape in the mix, because a growl has to carry
	# from the far side of a clearing and a shout does not need muffling.
	for index in VOICES_VOICE:
		var line := AudioStreamPlayer3D.new()
		line.name = "VoiceLine%d" % index
		line.bus = BUS_SFX
		line.unit_size = LINE_UNIT_SIZE
		line.max_db = 3.0
		line.max_distance = LINE_MAX_DISTANCE
		line.attenuation_filter_cutoff_hz = LINE_CUTOFF
		line.panning_strength = 1.0
		add_child(line)
		_voices_line.append(line)
		var flat_line := AudioStreamPlayer.new()
		flat_line.name = "VoiceFlatLine%d" % index
		flat_line.bus = BUS_SFX
		add_child(flat_line)
		_voices_flat_line.append(flat_line)
	for index in VOICES_2D:
		var flat := AudioStreamPlayer.new()
		flat.name = "Voice2D%d" % index
		flat.bus = BUS_SFX
		add_child(flat)
		_voices_2d.append(flat)


func _sync_scene_music() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null:
		return
	var id := scene.get_instance_id()
	if id == _scene_id:
		return
	_scene_id = id
	var path := scene.scene_file_path
	if path.is_empty():
		return
	# The title that started a campaign is not a title that wants its theme any
	# more: it stays current for a frame or two after the restart, and asking it
	# for the menu track would fade the score back into the menu.
	if id == _restart_scene_id and track_for_scene(path) == "menu":
		return
	play_music(track_for_scene(path))


func _scene_instance_id() -> int:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return 0
	return tree.current_scene.get_instance_id()


func _stream_for(track: String) -> AudioStream:
	if _streams.has(track):
		return _streams[track]
	var loaded := load(str(TRACKS[track])) as AudioStream
	if loaded is AudioStreamOggVorbis:
		# The menu theme is a loop by design. The soundtrack is not: its 49
		# minutes are stitched by `_seam_if_due`, so the stream is left to run
		# out and the manager decides what the seam sounds like.
		(loaded as AudioStreamOggVorbis).loop = track != "warband"
	_streams[track] = loaded
	return loaded


## Park a finished bed and let go of the master it was holding. A bed faded to
## `BED_SILENCE_DB` is still playing, which is what used to keep every retired
## bed (and its stream) alive for the rest of the session: silence is not a stop.
func _retire(bed: AudioStreamPlayer) -> void:
	if not is_instance_valid(bed):
		return
	var index := _beds.find(bed)
	bed.stop()
	bed.stream = null
	bed.volume_db = BED_SILENCE_DB
	if index >= 0:
		_bed_tracks[index] = ""
	_purge_streams()


## Every stream a live bed still holds stays; everything else is memory the game
## does not need until the next track.
func _purge_streams() -> void:
	for track in _streams.keys():
		var held := false
		for bed in _beds:
			if bed.playing and bed.stream == _streams[track]:
				held = true
				break
		if not held:
			_streams.erase(track)


## Per-event 3D shape. The same pool serves the soul's own boots (close, full
## range) and another body's (small, dull, gone by ten metres), so every entry
## that overrides one of these must be able to override all four. A spoken line
## defaults to the line shape rather than the world one.
func _shape(voice: AudioStreamPlayer3D, row: Dictionary) -> void:
	var line := str(row.get("pool", "world")) == "voice"
	voice.unit_size = float(row.get("unit_size", LINE_UNIT_SIZE if line else VOICE_UNIT_SIZE))
	voice.max_distance = float(row.get("max_distance", LINE_MAX_DISTANCE if line else VOICE_MAX_DISTANCE))
	voice.attenuation_filter_cutoff_hz = float(row.get("cutoff", LINE_CUTOFF if line else VOICE_CUTOFF))
	voice.attenuation_model = int(row.get("attenuation", VOICE_ATTENUATION))


func _variant_for(event: String, count: int) -> int:
	if count <= 1:
		return 0
	var index := _rng.randi_range(0, count - 1)
	if index == int(_last_variant.get(event, -1)):
		# Never the same take twice running: a repeated hit reads as a loop.
		index = (index + 1 + _rng.randi_range(0, count - 2)) % count
	_last_variant[event] = index
	return index


func _prune_recent(now: float) -> void:
	for key in _recent.keys():
		if now - float(_recent[key]) > 1.0:
			_recent.erase(key)


func _apply_buses() -> void:
	_set_bus(BUS_MUSIC, music_volume, music_muted)
	_set_bus(BUS_SFX, sfx_volume, sfx_muted)


func _set_bus(bus_name: String, volume: float, muted: bool) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(index, muted)


func _load_settings() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Ignoring unreadable audio settings at %s" % save_path)
		return
	var data: Dictionary = parsed
	music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(data.get("sfx_volume", sfx_volume)), 0.0, 1.0)
	music_muted = bool(data.get("music_muted", music_muted))
	sfx_muted = bool(data.get("sfx_muted", sfx_muted))


func _save_settings() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write audio settings to %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"music_muted": music_muted,
		"sfx_muted": sfx_muted,
	}))
	file.close()


func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("audio", message, data)
