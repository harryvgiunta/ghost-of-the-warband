class_name Sfx
extends RefCounted
## The combat sound vocabulary, resolved from the thing that swung.
##
## Call sites say what happened ("a blade landed here"), never which file to
## play: this class owns the weapon reading (dagger, blunt, two-handed, blade)
## and hands the event name to the `Audio` autoload. Every entry point is a
## no-op when the autoload is absent, so a headless regression that runs a scene
## without the audio manager still exercises the same combat paths.
##
## A dagger is its own reading, not a small sword. It is the fastest weapon in
## the game (a 0.5 s swing, and the shank passive makes it 0.167 s), so a sword's
## 0.3 s whoosh arriving under every stab reads as a greatsword being swung by a
## man with a knife. The dagger gets its own short takes, a quieter level and a
## brighter pitch - the same recordings, cut to the flick.

## Catalog pieces that are blunt: the makeshift club, the whole tree limb, and
## both staves. Everything else that cuts or pokes is a blade.
const BLUNT_ITEMS := ["club_makeshift", "branch_heavy", "staff_fire", "staff_bone"]
## Catalog pieces that need both hands. The club is one-handed in the table, so
## it gets the short whoosh and the heavy impact - a swing is a swing.
const TWO_HAND_ITEMS := ["branch_heavy", "staff_fire", "staff_bone"]
## Catalog pieces swung one-handed from a blade that is barely a blade.
const DAGGER_ITEMS := ["dagger_iron", "dagger_ironwood"]
## Blade span index where `Archer.SWORD_DATA` turns makeshift: club at 3, branch
## at 4. Read as a floor rather than an equality so a new blunt piece is blunt.
const CLUB_INDEX := 3
## What a weapon reads as when nothing else can say: an empty answer, not a
## guess at a catalog index.
const UNARMED := {"two_handed": false, "blunt": false, "dagger": false}


## Play one loud noise through the manager, at a world point when one is given.
static func play(event: String, at: Variant = null) -> void:
	var audio := _audio()
	if audio == null:
		return
	audio.play_event(event, at)


## A weapon is on its way through the air. `hand` decides which blade of a dual
## pair swung, because the off hand may be the dagger.
static func swing(source: Variant, at: Variant = null, hand: String = "right") -> void:
	var kind := kind_of(source, hand)
	if bool(kind.get("dagger")):
		play("swing_dagger", at)
		return
	play("swing_2h" if bool(kind.get("two_handed")) else "swing_1h", at)


## A blow got through: the blade opens a body, the club crushes one, and a
## dagger's cut is the same recording held small.
static func landed(source: Variant, at: Variant = null, hand: String = "right") -> void:
	var kind := kind_of(source, hand)
	if bool(kind.get("dagger")):
		play("hit_dagger", at)
	elif bool(kind.get("blunt")):
		play("hit_blunt", at)
	else:
		play("hit_blade", at)


## Steel met steel. A parry rings, a held block carries weight.
static func defense(at: Variant = null, parried: bool = false) -> void:
	play("parry" if parried else "block", at)


static func arrow(at: Variant = null) -> void:
	play("arrow", at)


static func thrown(at: Variant = null) -> void:
	play("throw", at)


## What a body is swinging: `{"two_handed": bool, "blunt": bool, "dagger": bool}`.
##
## Three shapes reach this: the ranger rig (`Archer`, which knows its own catalog
## index and which hand holds what), a mob with a catalog piece in hand
## (`held_weapon_id()` or the watcher's `weapon_item`), and a mob with a bare
## limb - which reads as a blade because nothing in the profile says otherwise.
static func kind_of(source: Variant, hand: String = "right") -> Dictionary:
	if source == null or not is_instance_valid(source):
		return UNARMED
	var item := ""
	if source.has_method("held_weapon_id"):
		item = str(source.held_weapon_id())
	if item.is_empty() and source.get("weapon_item") != null:
		item = str(source.get("weapon_item"))
	if not item.is_empty():
		return {
			"two_handed": item in TWO_HAND_ITEMS,
			"blunt": item in BLUNT_ITEMS,
			"dagger": item in DAGGER_ITEMS,
		}
	# The rig answers for the hand that swung, which is the only way an off-hand
	# dagger behind a main-hand sword is heard as a dagger.
	if source.has_method("swing_weapon_class"):
		var blade_class := str(source.swing_weapon_class(hand))
		if blade_class == "dagger":
			return {"two_handed": false, "blunt": false, "dagger": true}
		if blade_class == "staff":
			return {"two_handed": true, "blunt": true, "dagger": false}
	if not source.has_method("swings_two_handed"):
		return UNARMED
	var staff := bool(source.get("staff_active")) if source.get("staff_active") != null else false
	var index := 0
	if source.get("sword_index") != null:
		index = int(source.get("sword_index"))
	return {
		"two_handed": bool(source.swings_two_handed()) or staff,
		"blunt": staff or index >= CLUB_INDEX,
		"dagger": false,
	}


static func _audio() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Audio")
	return null
