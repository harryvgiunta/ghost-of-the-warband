extends Node
## One audio authority: two buses, two music beds and the one-shot pool.
##
## Music follows the scene. `title.tscn` is the menu theme and every other scene
## is the warband's soundtrack, so a scene that forgets to start a track is not
## a silent scene - the manager already knows. A crossfade carries the switch.
##
## Volume lives on the buses, never on the voices: one slider is one
## `AudioServer` call and every stream under it follows, including a take that
## starts a second later. The value is persisted, because a mix a player set is
## a setting like any other.
##
## The two streams are big (the soundtrack is a 49 minute master), so a track is
## loaded when it is wanted and dropped when the other bed takes over. Nothing
## here touches the display: a headless run keeps every setting, every bus and
## every event testable with no device to play into.

const SfxLibraryScript = preload("res://scripts/audio/sfx_library.gd")

const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const DEFAULT_SAVE_PATH := "user://audio_settings.json"
const SAVE_VERSION := 1
const MENU_SCENE := "title.tscn"
const TRACKS := {
	"menu": "res://assets/audio/music/menu_theme.ogg",
	"warband": "res://assets/audio/music/warband_soundtrack.ogg",
}
const FADE_SECONDS := 1.2
const BED_SILENCE_DB := -60.0
const VOICES_3D := 12
const VOICES_2D := 6
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
var _streams: Dictionary = {}
var _voices_3d: Array[AudioStreamPlayer3D] = []
var _voices_2d: Array[AudioStreamPlayer] = []
var _voice_3d := 0
var _voice_2d := 0
var _last_variant: Dictionary = {}
var _recent: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _fade: Tween
var _scene_id := 0


func _ready() -> void:
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
	var seconds := clampf(fade, 0.05, 8.0)
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(to, "volume_db", 0.0, seconds)
	if from.playing:
		_fade.tween_property(from, "volume_db", BED_SILENCE_DB, seconds)
		_fade.chain().tween_callback(_retire.bind(from))


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
	if at is Vector3:
		var voice := _voices_3d[_voice_3d]
		_voice_3d = (_voice_3d + 1) % _voices_3d.size()
		voice.global_position = at
		voice.volume_db = level
		voice.pitch_scale = pitch
		voice.stream = stream
		voice.play()
		return
	var flat := _voices_2d[_voice_2d]
	_voice_2d = (_voice_2d + 1) % _voices_2d.size()
	flat.volume_db = level
	flat.pitch_scale = pitch
	flat.stream = stream
	flat.play()


# --- internals -------------------------------------------------------------

func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


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
		voice.unit_size = 7.0
		voice.max_db = 3.0
		voice.max_distance = 80.0
		voice.attenuation_filter_cutoff_hz = 9000.0
		voice.panning_strength = 1.0
		add_child(voice)
		_voices_3d.append(voice)
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
	play_music(track_for_scene(path))


func _stream_for(track: String) -> AudioStream:
	if _streams.has(track):
		return _streams[track]
	var loaded := load(str(TRACKS[track])) as AudioStream
	if loaded is AudioStreamOggVorbis:
		# Both beds are beds: the menu theme is a loop by design, the soundtrack
		# is the game's whole 49 minutes and runs round when it ends.
		(loaded as AudioStreamOggVorbis).loop = true
	_streams[track] = loaded
	return loaded


## Park a finished bed and let go of the master it was holding.
func _retire(bed: AudioStreamPlayer) -> void:
	if not is_instance_valid(bed) or bed.playing:
		return
	bed.stream = null
	bed.volume_db = BED_SILENCE_DB
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
