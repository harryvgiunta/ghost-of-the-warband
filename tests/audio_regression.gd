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
	# Two buses under the master, because the whole settings page is two faders:
	# a missing bus would silently move the wrong thing.
	for bus in ["Music", "SFX"]:
		var index := AudioServer.get_bus_index(bus)
		check(index > 0, "%s bus is missing" % bus)
		check(AudioServer.get_bus_send(index) == "Master", "%s must hang off Master" % bus)


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

	# The main menu's theme is a loop, and so is the 49 minute score: both are set
	# on the stream the manager loads, not left to the file's own metadata.
	for track in ["menu", "warband"]:
		var stream = audio._stream_for(track)
		check(stream != null, "%s track did not load" % track)
		check(stream is AudioStreamOggVorbis, "%s is not a Vorbis stream" % track)
		if stream is AudioStreamOggVorbis:
			check(bool(stream.loop), "%s does not loop" % track)
	check(str(audio.TRACKS["menu"]).ends_with("menu_theme.ogg"), "the menu track path moved")
	check(str(audio.TRACKS["warband"]).ends_with("warband_soundtrack.ogg"),
		"the soundtrack path moved")

	# Headless: the manager still names the track it wants, with no device.
	audio.play_music("menu")
	check(audio.music_track == "menu", "the manager lost the track it was asked for")


func _check_library() -> void:
	var required := ["swing_1h", "swing_2h", "hit_blade", "hit_blunt", "block", "parry", "arrow"]
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
	# Smaller by construction: the flick is shorter and quieter than the sword.
	var flick: Dictionary = SfxLibraryScript.entry("swing_dagger")
	var sword: Dictionary = SfxLibraryScript.entry("swing_1h")
	check(float(flick.get("db")) < float(sword.get("db")),
		"the dagger flick must be quieter than the sword whoosh")
	check(float(flick.get("pitch")[0]) > float(sword.get("pitch")[0]),
		"the dagger flick must be brighter than the sword whoosh")


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
	SfxScript.defense(Vector3(1, 0, 2), true)
	check(audio.last_event == "parry", "a parry did not ask for the parry take")
	SfxScript.defense(Vector3(1, 0, 2), false)
	check(audio.last_event == "block", "a block did not ask for the clash take")
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
