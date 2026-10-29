extends SceneTree
## Audio regression: the two buses, the two tracks, the settings page and the
## weapon reading the combat funnel relies on.
##
## It runs headless, so it never asks for a device. Everything it asserts is the
## part of the mixer a player's move actually changes: the bus levels, the mutes,
## the persisted file, the track a scene asks for, the take a weapon picks, and
## the page that owns the pointer while Escape is open.

const SfxScript = preload("res://scripts/audio/sfx.gd")
const SfxLibraryScript = preload("res://scripts/audio/sfx_library.gd")
const SettingsScript = preload("res://scripts/ui/settings_menu.gd")
const SoundPageScript = preload("res://scripts/ui/sound_settings_page.gd")
const PauseMenuScript = preload("res://scripts/pause_menu.gd")
const FootstepsScript = preload("res://scripts/audio/footsteps.gd")
const VoiceLibraryScript = preload("res://scripts/audio/voice_library.gd")
const VoiceScript = preload("res://scripts/audio/voice.gd")
const VoiceEmitterScript = preload("res://scripts/audio/voice_emitter.gd")

const TEST_SAVE := "user://audio_settings_test.json"

## Every scene the campaign or the sandbox can be in. All of them are the game,
## so all of them carry the soundtrack; only the title is the menu theme.
const GAME_SCENES := [
	"res://main.tscn", "res://arena.tscn", "res://delve.tscn", "res://admin_arena.tscn",
	"res://scenes/warband_world.tscn", "res://scenes/cage_escape.tscn",
	"res://scenes/town_hub.tscn",
]

var checks := 0
var failures := 0
var audio


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("AUDIO_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


class StubRig:
	var sword_index := 0
	var staff_active := false
	var weapon := "sword"
	var off_hand := ""
	var weapon_item: Variant = null
	## The guard half of the rig: what a block is heard as.
	var shield_equipped := false
	var shield_variant := 1

	func swings_two_handed() -> bool:
		return sword_index in [2, 4]

	## The rig's own answer for a hand, exactly as `Archer` gives it.
	func swing_weapon_class(hand: String) -> String:
		if weapon == "dagger":
			return "dagger"
		if hand == "left":
			return off_hand
		if weapon == "dual":
			return "staff" if staff_active else "sword"
		return "sword"


## A body that wears a rig, exactly as `ArenaActor` does: it answers nothing
## about a guard itself, so `Sfx` has to read the rig it carries.
class StubGuardBody:
	var rig: Variant = null


class StubMob:
	var weapon_item := ""
	var weapon := ""


## A body that walks: the emitter only reads its velocity and its footing.
class StubBody:
	var velocity := Vector3(2.0, 0.0, 0.0)
	var global_position := Vector3.ZERO
	var on_floor := true

	func is_on_floor() -> bool:
		return on_floor

	func is_inside_tree() -> bool:
		return false


## A rig's feet, at whatever height the test puts them.
class StubFeet:
	var left := 0.40
	var right := 0.40

	func get_joint_positions() -> Dictionary:
		return {
			"left_foot": Vector3(0.0, left, 0.0),
			"right_foot": Vector3(2.0, right, 0.0),
		}


## A body that can answer for a kill: the mob's death resolves its killer by
## instance id and asks the body, which is how a player or a squadmate gets a line
## over something it put down.
class StubKiller:
	extends Node3D
	var asked := false

	func voice_kill_quip() -> void:
		asked = true


func run() -> void:
	_remove_test_save()
	audio = root.get_node_or_null("Audio")
	check(audio != null, "the Audio autoload is missing")
	if audio == null:
		quit(1)
		return
	audio.save_path = TEST_SAVE
	_check_buses()
	_check_volume_and_persistence()
	_check_tracks()
	_check_library()
	_check_voices()
	_check_weapon_reading()
	_check_footsteps()
	_check_settings_menu()
	_check_pause_menu()
	audio.set_music_volume(0.8)
	audio.set_sfx_volume(0.8)
	audio.set_music_muted(false)
	audio.set_sfx_muted(false)
	_remove_test_save()
	print("AUDIO_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func _check_buses() -> void:
	# Two faders plus the room: a missing bus would silently move the wrong
	# thing, and a reverb that did not return into SFX would escape the effects
	# slider.
	for bus in ["Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus)
		check(index > 0, "%s bus is missing" % bus)
		check(AudioServer.get_bus_send(index) == "Master", "%s must hang off Master" % bus)
	var reverb := AudioServer.get_bus_index("Reverb")
	check(reverb > 0, "Reverb bus is missing")
	check(AudioServer.get_bus_send(reverb) == "SFX",
		"Reverb must return into SFX so the effects slider still owns it")
	check(AudioServer.get_bus_effect_count(reverb) == 1, "Reverb must carry exactly one effect")
	if AudioServer.get_bus_effect_count(reverb) == 1:
		check(AudioServer.get_bus_effect(reverb, 0) is AudioEffectReverb,
			"the Reverb bus effect is not a reverb")


func _check_volume_and_persistence() -> void:
	audio.set_music_volume(0.42)
	audio.set_sfx_volume(0.17)
	var music_bus := AudioServer.get_bus_index("Music")
	var sfx_bus := AudioServer.get_bus_index("SFX")
	check(absf(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.42)) < 0.01,
		"music bus is not at the slider's level")
	check(absf(AudioServer.get_bus_volume_db(sfx_bus) - linear_to_db(0.17)) < 0.01,
		"sfx bus is not at the slider's level")
	check(FileAccess.file_exists(TEST_SAVE), "the mix was not written to disk")

	audio.set_music_muted(true)
	check(AudioServer.is_bus_mute(music_bus), "muting music did not mute the bus")
	check(not AudioServer.is_bus_mute(sfx_bus), "muting music muted the effects too")
	audio.set_music_muted(false)
	check(not AudioServer.is_bus_mute(music_bus), "unmuting music left the bus muted")

	# A fresh manager reading the same file (a relaunch) must come back with the
	# mix the player set, not the defaults.
	var reload = load("res://scripts/audio/audio_manager.gd").new()
	reload.name = "AudioReload"
	root.add_child(reload)
	reload.save_path = TEST_SAVE
	reload._load_settings()
	check(absf(reload.music_volume - 0.42) < 0.001, "music level did not survive a reload")
	check(absf(reload.sfx_volume - 0.17) < 0.001, "sfx level did not survive a reload")
	check(not reload.music_muted and not reload.sfx_muted, "mute state did not survive a reload")
	reload.queue_free()

	# Out-of-range values are clamped, never handed to the mixer raw.
	audio.set_sfx_volume(4.0)
	check(audio.sfx_volume == 1.0, "an over-range level was not clamped")
	audio.set_sfx_volume(0.17)


func _check_tracks() -> void:
	check(audio.track_for_scene("res://title.tscn") == "menu", "the title must ask for the menu theme")
	for path in GAME_SCENES:
		check(audio.track_for_scene(path) == "warband", "%s must carry the soundtrack" % path)

	# Only the menu theme loops on its stream. The 49 minute score is stitched by
	# the manager's seam, so the stream itself must not loop.
	var menu_stream = audio._stream_for("menu")
	check(menu_stream != null, "menu track did not load")
	check(menu_stream is AudioStreamOggVorbis, "menu track is not a Vorbis stream")
	if menu_stream is AudioStreamOggVorbis:
		check(bool(menu_stream.loop), "the menu theme does not loop")
	var score_stream = audio._stream_for("warband")
	check(score_stream != null, "warband track did not load")
	check(score_stream is AudioStreamOggVorbis, "warband track is not a Vorbis stream")
	if score_stream is AudioStreamOggVorbis:
		check(not bool(score_stream.loop), "the soundtrack must not loop on its stream")
	check(float(audio.LOOP_FADE_SECONDS) >= 2.0 and float(audio.LOOP_FADE_SECONDS) <= 5.0,
		"the loop seam window is not a few seconds")
	check(str(audio.TRACKS["menu"]).ends_with("menu_theme.ogg"), "the menu track path moved")
	check(str(audio.TRACKS["warband"]).ends_with("warband_soundtrack.ogg"),
		"the soundtrack path moved")

	# The seam window itself: not due at the top, due inside the last seconds,
	# and never on a stream shorter than two windows.
	check(not audio.seam_due(0.0, 2940.0), "the seam is due at the start of the score")
	check(not audio.seam_due(2940.0 - float(audio.LOOP_FADE_SECONDS) - 1.0, 2940.0),
		"the seam fired before its window")
	check(audio.seam_due(2940.0 - float(audio.LOOP_FADE_SECONDS), 2940.0),
		"the seam did not fire inside its window")
	check(audio.seam_due(2939.0, 2940.0), "the seam did not fire at the end of the score")
	check(not audio.seam_due(1.0, 4.0), "a stream shorter than two windows seamed")

	# A campaign start takes the score back to zero and names the soundtrack,
	# with no device: the manager's intent is testable headless.
	audio.play_music("menu")
	audio.start_campaign_music()
	check(audio.music_track == "warband", "a campaign start did not ask for the soundtrack")

	# Headless: the manager still names the track it wants, with no device.
	audio.play_music("menu")
	check(audio.music_track == "menu", "the manager lost the track it was asked for")


func _check_library() -> void:
	var required := ["swing_1h", "swing_2h", "hit_blade", "hit_blunt", "block", "parry",
		"arrow", "swing_dagger", "stab_dagger", "hit_dagger", "block_wood",
		"block_dagger", "ui_click", "menu_thud", "body_swap", "pickup"]
	for event in required:
		check(SfxLibraryScript.has(event), "the library lost %s" % event)
	for event in SfxLibraryScript.events():
		var count := int(SfxLibraryScript.entry(event).get("count", 0))
		check(count > 0, "%s has no takes" % event)
		for index in count:
			var path := SfxLibraryScript.path(event, index)
			check(ResourceLoader.exists(path), "missing take %s" % path)
			check(SfxLibraryScript.stream(event, index) is AudioStream,
				"%s take %d did not load as a stream" % [event, index])
	# Thirteen whooshes, three thumps, four of each steel sound: the counts the
	# slicing tool writes and the only reason a swing does not read as a loop.
	check(int(SfxLibraryScript.entry("swing_1h").get("count")) == 13, "whoosh takes changed")
	check(int(SfxLibraryScript.entry("hit_blunt").get("count")) == 3, "blunt takes changed")
	check(int(SfxLibraryScript.entry("swing_dagger").get("count")) == 6, "dagger takes changed")
	# Smaller by construction: the flick is a whisper and the stab is quieter
	# still, because the dagger's impact is the event.
	var flick: Dictionary = SfxLibraryScript.entry("swing_dagger")
	var sword: Dictionary = SfxLibraryScript.entry("swing_1h")
	var stab: Dictionary = SfxLibraryScript.entry("stab_dagger")
	check(float(flick.get("db")) < float(sword.get("db")),
		"the dagger flick must be quieter than the sword whoosh")
	check(float(stab.get("db")) < float(flick.get("db")),
		"a dagger stab must be the quietest swing in the table")
	check(float(flick.get("pitch")[0]) > float(sword.get("pitch")[0]),
		"the dagger flick must be brighter than the sword whoosh")
	# The stab's impact is the loud half of the pair, low and wet.
	var hit_dagger: Dictionary = SfxLibraryScript.entry("hit_dagger")
	check(float(hit_dagger.get("db")) > float(SfxLibraryScript.entry("hit_blade").get("db")),
		"the dagger impact must sit above the blade's cut")
	check(float(hit_dagger.get("pitch")[1]) < 1.0, "the dagger impact must be pitched down")

	# The wood and the knife are their own blocks, and only the tail events ask
	# for the reverb bus.
	check(float(SfxLibraryScript.entry("block_wood").get("db"))
		< float(SfxLibraryScript.entry("block").get("db")),
		"a wooden block must be quieter than steel")
	check(float(SfxLibraryScript.entry("block_dagger").get("db")) < -20.0,
		"a dagger block must be a whisper")
	check(str(SfxLibraryScript.entry("menu_thud").get("bus")) == "Reverb",
		"the door thud must use the reverb bus")
	check(str(SfxLibraryScript.entry("body_swap").get("bus")) == "Reverb",
		"the body swap must use the reverb bus")
	check(not SfxLibraryScript.entry("block").has("bus"),
		"a combat block must stay dry")


func _check_weapon_reading() -> void:
	var short := StubRig.new()
	var great := StubRig.new()
	great.sword_index = 2
	var club := StubRig.new()
	club.sword_index = 3
	var branch := StubRig.new()
	branch.sword_index = 4
	var staff := StubRig.new()
	staff.staff_active = true

	check(SfxScript.kind_of(short) == {"two_handed": false, "blunt": false, "dagger": false},
		"a shortsword must read as a one-handed blade")
	check(SfxScript.kind_of(great) == {"two_handed": true, "blunt": false, "dagger": false},
		"a greatsword must read as a two-handed blade")
	check(SfxScript.kind_of(club) == {"two_handed": false, "blunt": true, "dagger": false},
		"a club must read as a one-handed blunt")
	check(SfxScript.kind_of(branch) == {"two_handed": true, "blunt": true, "dagger": false},
		"a tree branch must read as a two-handed blunt")
	check(SfxScript.kind_of(staff) == {"two_handed": true, "blunt": true, "dagger": false},
		"a staff must read as a two-handed blunt")

	# The dagger is its own reading, in the main hand and behind a sword.
	var dagger := StubRig.new()
	dagger.weapon = "dagger"
	check(SfxScript.kind_of(dagger) == {"two_handed": false, "blunt": false, "dagger": true},
		"a dagger must read as a dagger")
	var dual := StubRig.new()
	dual.weapon = "dual"
	dual.off_hand = "dagger"
	check(bool(SfxScript.kind_of(dual, "left").get("dagger")),
		"an off-hand dagger must read as a dagger")
	check(not bool(SfxScript.kind_of(dual, "right").get("dagger")),
		"the main-hand sword of a dual pair must not read as a dagger")

	var club_mob := StubMob.new()
	club_mob.weapon_item = "club_makeshift"
	check(bool(SfxScript.kind_of(club_mob).get("blunt")), "a mob club must read as blunt")
	var sword_mob := StubMob.new()
	sword_mob.weapon_item = "sword_makeshift"
	check(not bool(SfxScript.kind_of(sword_mob).get("blunt")), "a mob blade must not read as blunt")
	var shiv_mob := StubMob.new()
	shiv_mob.weapon_item = "dagger_ironwood"
	check(bool(SfxScript.kind_of(shiv_mob).get("dagger")), "a mob shiv must read as a dagger")

	# The funnel itself: what the combat code calls, and what the manager hears.
	audio.last_event = ""
	SfxScript.swing(short, Vector3(1, 0, 2))
	check(audio.last_event == "swing_1h", "a one-handed swing did not ask for the short whoosh")
	SfxScript.swing(branch, Vector3(1, 0, 2))
	check(audio.last_event == "swing_2h", "a two-handed swing did not ask for the long whoosh")
	SfxScript.landed(branch, Vector3(1, 0, 2))
	check(audio.last_event == "hit_blunt", "a landed branch did not ask for the blunt hit")
	SfxScript.landed(short, Vector3(1, 0, 2))
	check(audio.last_event == "hit_blade", "a landed blade did not ask for the slit")
	# A dagger is not a sword swung by a smaller man: it asks for its own takes,
	# and its landed cut is the same recording held small.
	SfxScript.swing(dagger, Vector3(1, 0, 2))
	check(audio.last_event == "swing_dagger", "a dagger swing did not ask for the dagger flick")
	SfxScript.swing(dual, Vector3(1, 0, 2), "left")
	check(audio.last_event == "swing_dagger", "an off-hand dagger swing did not ask for the flick")
	SfxScript.swing(dual, Vector3(1, 0, 2), "right")
	check(audio.last_event == "swing_1h", "the main-hand sword of a dual pair lost its whoosh")
	SfxScript.landed(dagger, Vector3(1, 0, 2))
	check(audio.last_event == "hit_dagger", "a landed dagger did not ask for the small cut")
	SfxScript.swing(shiv_mob, Vector3(1, 0, 2))
	check(audio.last_event == "swing_dagger", "a mob shiv swing did not ask for the flick")
	# The melee variant is threaded through: a dagger stab is a push, and the
	# quietest take in the table, while the diagonals stay a whisper.
	SfxScript.swing(dagger, Vector3(1, 0, 2), "right", "stab")
	check(audio.last_event == "stab_dagger", "a dagger stab did not ask for the stab take")
	SfxScript.swing(dagger, Vector3(1, 0, 2), "right", "diagonal_left")
	check(audio.last_event == "swing_dagger", "a dagger diagonal did not ask for the flick")
	SfxScript.swing(short, Vector3(1, 0, 2), "right", "stab")
	check(audio.last_event == "swing_1h", "a sword stab must keep the sword whoosh")
	SfxScript.defense(Vector3(1, 0, 2), true)
	check(audio.last_event == "parry", "a parry did not ask for the parry take")
	SfxScript.defense(Vector3(1, 0, 2), false)
	check(audio.last_event == "block", "a block did not ask for the clash take")

	# The guard is read from what the defender holds, not from a single clash.
	var wooden := StubRig.new()
	wooden.shield_equipped = true
	wooden.shield_variant = 3
	SfxScript.defense(Vector3(1, 0, 2), false, wooden)
	check(audio.last_event == "block_wood", "a wooden shield did not answer with wood")
	var metal := StubRig.new()
	metal.shield_equipped = true
	metal.shield_variant = 1
	SfxScript.defense(Vector3(1, 0, 2), false, metal)
	check(audio.last_event == "block", "a metal shield must ring with the clash")
	var club_guard := StubRig.new()
	club_guard.sword_index = 3
	SfxScript.defense(Vector3(1, 0, 2), false, club_guard)
	check(audio.last_event == "block_wood", "a club guard did not answer with wood")
	var dagger_guard := StubRig.new()
	dagger_guard.weapon = "dagger"
	SfxScript.defense(Vector3(1, 0, 2), false, dagger_guard)
	check(audio.last_event == "block_dagger", "a dagger guard did not whisper")
	# A body that wears a rig is unwrapped to it: this is how the warband's
	# bodies and the frontier's seats are read.
	var worn := StubGuardBody.new()
	worn.rig = wooden
	SfxScript.defense(Vector3(1, 0, 2), false, worn)
	check(audio.last_event == "block_wood", "a body wearing a wooden shield was read as steel")
	# No defender at all keeps the old default: the arena and the delve replicate
	# defence events without one.
	SfxScript.defense(Vector3(1, 0, 2), false, null)
	check(audio.last_event == "block", "a defenderless block lost its metal default")

	SfxScript.ui_click()
	check(audio.last_event == "ui_click", "a UI click did not ask for the click take")
	SfxScript.body_swap(Vector3(1, 0, 2))
	check(audio.last_event == "body_swap", "a body swap did not ask for the swap take")
	SfxScript.pickup(Vector3(1, 0, 2))
	check(audio.last_event == "pickup", "a pickup did not ask for the pickup take")
	SfxScript.arrow(Vector3(1, 0, 2))
	check(audio.last_event == "arrow", "an arrow did not ask for the bow take")
	SfxScript.thrown(Vector3(1, 0, 2))
	check(audio.last_event == "throw", "a thrown blade did not ask for the throw take")


## The boots: a plant sounds, the same boot cannot machine-gun, and a body that
## is airborne, standing or far away makes no sound at all.
func _check_footsteps() -> void:
	check(int(SfxLibraryScript.entry("footstep").get("count")) == 12, "footstep takes changed")
	check(float(SfxLibraryScript.entry("footstep").get("db")) < float(SfxLibraryScript.entry("swing_1h").get("db")),
		"a footfall must sit under the quietest swing")
	check(str(SfxLibraryScript.entry("footstep").get("pool")) == "step",
		"footfalls must use their own voice pool")
	check(audio._voices_step.size() == 6, "the step voice pool is not built")
	# Somebody else's boots: the same takes, heard much smaller and only close.
	var own: Dictionary = SfxLibraryScript.entry("footstep")
	var other: Dictionary = SfxLibraryScript.entry("footstep_far")
	check(int(other.get("count")) == 12, "the far footstep lost its takes")
	check(float(other.get("db")) < float(own.get("db")) - 8.0,
		"another body's boot must be much quieter than the soul's")
	check(float(other.get("unit_size")) < float(own.get("unit_size")),
		"another body's boot must fall off sooner")
	check(float(other.get("max_distance")) <= 12.0,
		"another body's boot must be gone by a dozen metres")
	check(int(other.get("attenuation")) == SfxLibraryScript.ATTENUATION_INVERSE_SQUARE,
		"another body's boot must use the sharpest falloff")

	var body := StubBody.new()
	var feet := StubFeet.new()
	var steps = FootstepsScript.new()
	body.velocity = Vector3(2.0, 0.0, 0.0)
	audio.last_event = ""
	steps.update(0.016, body, feet)
	check(audio.last_event == "", "a footfall fired before any boot came down")

	audio.last_event = ""
	feet.left = 0.30
	steps.update(0.016, body, feet, true)
	check(audio.last_event == "footstep", "a planted boot made no sound")

	audio.last_event = ""
	feet.left = 0.40
	steps.update(0.016, body, feet)
	feet.left = 0.30
	steps.update(0.016, body, feet)
	check(audio.last_event == "", "one boot sounded twice inside its own gap")

	audio.last_event = ""
	feet.left = 0.40
	steps.update(0.20, body, feet, true)
	feet.left = 0.30
	steps.update(0.016, body, feet, true)
	check(audio.last_event == "footstep", "the boot went silent for good after its gap")

	audio.last_event = ""
	body.on_floor = false
	feet.left = 0.45
	steps.update(0.016, body, feet)
	feet.left = 0.30
	steps.update(0.016, body, feet)
	check(audio.last_event == "", "a body in the air made a footstep")

	# Another body's boot is the far, quiet take - never the soul's own.
	var other_body := StubBody.new()
	var other_feet := StubFeet.new()
	var other_steps = FootstepsScript.new()
	other_body.velocity = Vector3(2.0, 0.0, 0.0)
	audio.last_event = ""
	other_steps.update(0.016, other_body, other_feet, false)
	other_feet.left = 0.30
	other_steps.update(0.016, other_body, other_feet, false)
	check(audio.last_event == "footstep_far", "another body's boot was not the far take")

	body.on_floor = true
	body.velocity = Vector3.ZERO
	audio.last_event = ""
	feet.left = 0.45
	steps.update(0.016, body, feet)
	feet.left = 0.30
	steps.update(0.016, body, feet)
	check(audio.last_event == "", "a standing body made a footstep")



## The voices: who has one, which takes are on disk, and the rules that turn an
## event into "sometimes" - a chance, a cooldown, a threshold - without a wolf
## growling on every bite or every kill getting a line.
func _check_voices() -> void:
	VoiceLibraryScript.ensure()
	var voices: Array = VoiceLibraryScript.voices()
	check(voices.has("wolf"), "the wolf has no voice")
	check(VoiceLibraryScript.cues("wolf").has("attack"), "the wolf lost its attack cue")
	check(VoiceLibraryScript.cues("wolf").has("death"), "the wolf lost its death cue")

	# The takes the slicing tool wrote, and the event name the mixer plays them
	# under. A count here and a window in `tools/slice_game_audio.py` are the same
	# fact, so a re-cut that changes one without the other fails here.
	check(VoiceLibraryScript.takes("wolf", "attack") == 3, "the wolf growl take count changed")
	check(VoiceLibraryScript.takes("wolf", "death") == 6, "the wolf death take count changed")
	for cue in VoiceLibraryScript.cues("wolf"):
		var event := VoiceLibraryScript.event_name("wolf", cue)
		check(SfxLibraryScript.has(event), "the mixer does not know %s" % event)
		var row: Dictionary = SfxLibraryScript.entry(event)
		check(str(row.get("dir")) == VoiceLibraryScript.DIR,
			"%s is not read out of the voice tree" % event)
		check(str(row.get("pool")) == "voice", "%s must use the voice pool" % event)
		for index in VoiceLibraryScript.takes("wolf", cue):
			var path := SfxLibraryScript.path(event, index)
			check(ResourceLoader.exists(path), "missing take %s" % path)
			check(SfxLibraryScript.stream(event, index) is AudioStream,
				"%s take %d did not load" % [event, index])

	# A dead wolf cries, an attacking one sometimes does not: the chance and the
	# cooldown are the difference between a world with animals in it and a world
	# that repeats itself.
	var growl: Dictionary = VoiceLibraryScript.row("wolf", "attack")
	var death: Dictionary = VoiceLibraryScript.row("wolf", "death")
	check(float(growl.get("chance")) < 1.0, "a wolf must not growl at every bite")
	check(float(growl.get("cooldown")) >= 2.0, "a wolf must not growl twice a second")
	check(float(death.get("chance")) == 1.0, "a wolf's death must always be heard")
	check(float(death.get("db")) > float(growl.get("db")),
		"a death must sit above the growl in the mix")
	check(float(death.get("pitch")[1]) < 1.0,
		"the death takes must be pitched down to read as a wolf, not a dog")

	# The player's four readings: a grunt, the line on a heavy blow, a word over a
	# kill, and the moans of a body on the ground. The thresholds are the table's:
	# a big hit asks for a bigger share of the pool than a grunt does.
	var hurt: Dictionary = VoiceLibraryScript.row("player", "hurt")
	var big_hit: Dictionary = VoiceLibraryScript.row("player", "big_hit")
	var kill: Dictionary = VoiceLibraryScript.row("player", "kill")
	var downed: Dictionary = VoiceLibraryScript.row("player", "downed")
	check(not hurt.is_empty() and not big_hit.is_empty(), "the player lost a damage cue")
	check(float(big_hit.get("share")) > float(hurt.get("share")),
		"a big hit must need a heavier blow than a grunt")
	check(float(big_hit.get("cooldown")) > float(hurt.get("cooldown")),
		"the heavy-blow line must be rarer than the grunt")
	check(float(kill.get("chance")) < 1.0, "a body must not quip on every kill")
	check(float(kill.get("cooldown")) >= 4.0, "kills must not be narrated back to back")
	check(float(downed.get("chance")) > 0.5 and float(downed.get("cooldown")) == 0.0,
		"a body on the ground must actually moan")

	# Delivered takes play; a voice nobody has recorded yet is silence, not a
	# warning per call. These are the lines the delivery still owes.
	audio.last_event = ""
	check(VoiceScript.say("wolf", "attack", Vector3(3, 0, 4)), "a wolf growl did not play")
	check(audio.last_event == "voice_wolf_attack", "the growl asked for the wrong event")
	check(audio.last_event_position != null, "a growl in the world must be placed")
	audio.last_event = ""
	check(VoiceScript.say("wolf", "death"), "a flat wolf death did not play")
	check(audio.last_event == "voice_wolf_death", "the death asked for the wrong event")
	audio.last_event = ""
	check(not VoiceScript.say("orla", "greet", Vector3(1, 0, 1)),
		"a keeper with no takes must not play anything")
	check(not VoiceScript.say("player", "hurt", Vector3(1, 0, 1)),
		"a body with no takes must not play anything")
	check(audio.last_event == "", "a voice with no takes still reached the mixer")
	var absent: Array[String] = VoiceLibraryScript.missing()
	check(absent.has("orla/greet"), "the audit must name the missing keeper lines")
	check(absent.has("player/hurt"), "the audit must name the missing body lines")
	check(not absent.has("wolf/growl"), "the audit named the wolf growl, which ships")
	check(not absent.has("wolf/death"), "the audit named the wolf death, which ships")
	# The lines are on their own pool, so a growl cannot steal a blow's voice and
	# a blow cannot cut a line.
	check(audio._voices_line.size() == audio.VOICES_VOICE, "the 3D line pool is not built")
	check(audio._voices_flat_line.size() == audio.VOICES_VOICE,
		"the flat line pool is not built")

	# The emitter's rules, driven on its own clock. A growl is a coin toss and
	# then a cooldown: many attempts in one instant produce one line.
	var emitter := VoiceEmitterScript.create("wolf", null, false, 11)
	var played := 0
	for _attempt in 200:
		if emitter.say("attack"):
			played += 1
	check(played == 1, "the growl fired %d times in one instant" % played)
	check(emitter.say("death"), "a death on the same frame was swallowed")
	# Five seconds later the cooldown is spent: the next 200 attempts give one
	# more growl, not zero (the roll is per attempt) and not two (the cooldown).
	emitter.tick(5.0)
	played = 0
	for _attempt in 200:
		if emitter.say("attack"):
			played += 1
	check(played == 1, "the growl's cooldown did not open after its window")

	# A body with no voice, an unknown cue and a silenced emitter are all no-ops.
	var mute := VoiceEmitterScript.create("", null, false, 3)
	check(not mute.say("attack"), "a body with no voice spoke")
	check(not emitter.say("nonsense"), "an unknown cue spoke")
	check(not emitter.has("nonsense"), "an unknown cue reported takes")

	# The kill credit: a mob names its killer by instance id, and the body that
	# can speak answers.
	var killer := StubKiller.new()
	root.add_child(killer)
	check(VoiceScript.kill_quip(killer.get_instance_id()), "a killer with a voice was not asked")
	check(killer.asked, "the killer's voice hook was not called")
	check(not VoiceScript.kill_quip(0), "a kill with no hitter asked for a line")
	# A killer that has already been freed: the id is stale, not a guess.
	var gone := Node3D.new()
	var gone_id := gone.get_instance_id()
	gone.free()
	check(not VoiceScript.kill_quip(gone_id), "a freed hitter id asked for a line")
	var tongueless := Node3D.new()
	root.add_child(tongueless)
	check(not VoiceScript.kill_quip(tongueless.get_instance_id()),
		"a body without a voice answered a kill")
	tongueless.queue_free()
	killer.queue_free()


func _check_settings_menu() -> void:
	var menu = SettingsScript.new()
	menu.name = "TestSettings"
	root.add_child(menu)
	check(not menu.is_open(), "the settings window starts closed")
	menu.open()
	check(menu.is_open(), "the settings window did not open")
	check(menu.page() == "root", "the window must open on its index")
	check(menu.sound_button != null and menu.sound_button.is_visible_in_tree(),
		"the index has no SOUND entry")

	# The sub menu: one page in, with a level and a mute for each bus.
	menu.sound_button.pressed.emit()
	check(menu.page() == "sound", "the SOUND entry did not open the sound page")
	var page = menu.sound_page
	check(page != null, "the sound page is missing")
	check(page.is_visible_in_tree(), "the sound page was not shown")
	check(page.music_slider != null and page.sfx_slider != null,
		"the sound page needs a slider per bus")
	check(page.music_mute != null and page.sfx_mute != null,
		"the sound page needs a mute per bus")

	page.music_slider.value = 35.0
	check(absf(audio.music_volume - 0.35) < 0.001, "the music slider did not move the mix")
	page.sfx_slider.value = 60.0
	check(absf(audio.sfx_volume - 0.60) < 0.001, "the sfx slider did not move the mix")

	page.music_mute.pressed.emit()
	check(audio.music_muted, "the music mute button did not mute music")
	check(not audio.sfx_muted, "the music mute button muted the effects too")
	check(page.music_mute.text == "MUTED", "the muted plate does not say so")
	page.music_mute.pressed.emit()
	check(not audio.music_muted, "the music mute button did not unmute music")

	page.sfx_mute.pressed.emit()
	check(audio.sfx_muted, "the sfx mute button did not mute the effects")
	var shown: Dictionary = menu.values()
	check(absf(float(shown["music"]) - 0.35) < 0.001, "the page is not showing the music level")
	check(absf(float(shown["sfx"]) - 0.60) < 0.001, "the page is not showing the effects level")
	check(bool(shown["sfx_muted"]) and not bool(shown["music_muted"]),
		"the page is not showing the mute it set")
	page.sfx_mute.pressed.emit()
	check(not audio.sfx_muted, "the sfx mute button did not unmute the effects")

	menu.show_page("root")
	check(menu.page() == "root", "the window did not walk back to its index")
	var closed := [false]
	menu.closed.connect(func(): closed[0] = true)
	menu.close()
	check(closed[0], "closing the window did not announce it")
	check(not menu.is_open(), "the window stayed open")
	menu.queue_free()


func _check_pause_menu() -> void:
	var menu = PauseMenuScript.new()
	menu.name = "TestPauseMenu"
	root.add_child(menu)
	menu.configure("LEAVE MATCH")
	menu.open("")
	check(menu.is_open(), "the quick menu did not open")
	check(not menu.showing_sound(), "the quick menu opened on a sub page")
	check(menu.sound_button != null, "the quick menu has no SOUND row")
	menu.sound_button.pressed.emit()
	check(menu.showing_sound(), "the SOUND row did not open the sound page")
	check(menu.sound_page != null and menu.sound_page.is_visible_in_tree(),
		"the quick menu's sound page was not shown")
	menu.sound_page.sfx_slider.value = 25.0
	check(absf(audio.sfx_volume - 0.25) < 0.001, "the quick menu's slider did not move the mix")
	menu.back()
	check(not menu.showing_sound(), "BACK did not return to the menu")
	menu.close()
	check(not menu.is_open(), "the quick menu did not close")
	menu.queue_free()
