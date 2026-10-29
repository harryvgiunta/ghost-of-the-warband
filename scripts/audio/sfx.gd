class_name Sfx
extends RefCounted
## The combat sound vocabulary, resolved from the thing that swung.
##
## Call sites say what happened ("a blade landed here"), never which file to
## play: this class owns the weapon reading (blunt, two-handed, blade) and hands
## the event name to the `Audio` autoload. Every entry point is a no-op when the
## autoload is absent, so a headless regression that runs a scene without the
## audio manager still exercises the same combat paths.

## Catalog pieces that are blunt: the makeshift club, the whole tree limb, and
## both staves. Everything else that cuts or pokes is a blade.
const BLUNT_ITEMS := ["club_makeshift", "branch_heavy", "staff_fire", "staff_bone"]
## Catalog pieces that need both hands. The club is one-handed in the table, so
## it gets the short whoosh and the heavy impact - a swing is a swing.
const TWO_HAND_ITEMS := ["branch_heavy", "staff_fire", "staff_bone"]
## Blade span index where `Archer.SWORD_DATA` turns makeshift: club at 3, branch
## at 4. Read as a floor rather than an equality so a new blunt piece is blunt.
const CLUB_INDEX := 3


## Play one loud noise through the manager, at a world point when one is given.
static func play(event: String, at: Variant = null) -> void:
	var audio := _audio()
	if audio == null:
		return
	audio.play_event(event, at)


## A weapon is on its way through the air.
static func swing(source: Variant, at: Variant = null) -> void:
	var kind := kind_of(source)
	play("swing_2h" if bool(kind.get("two_handed")) else "swing_1h", at)


## A blow got through: the blade opens a body, the club crushes one.
static func landed(source: Variant, at: Variant = null) -> void:
	var kind := kind_of(source)
	play("hit_blunt" if bool(kind.get("blunt")) else "hit_blade", at)


## Steel met steel. A parry rings, a held block carries weight.
static func defense(at: Variant = null, parried: bool = false) -> void:
	play("parry" if parried else "block", at)


static func arrow(at: Variant = null) -> void:
	play("arrow", at)


static func thrown(at: Variant = null) -> void:
	play("throw", at)


## What a body is swinging: `{"two_handed": bool, "blunt": bool}`.
##
## Three shapes reach this: the ranger rig (`Archer`, which knows its own catalog
## index), a mob with a catalog piece in hand (`held_weapon_id()` or the watcher's
## `weapon_item`), and a mob with a bare limb - which reads as a blade because
## nothing in the profile says otherwise.
static func kind_of(source: Variant) -> Dictionary:
	var blade := {"two_handed": false, "blunt": false}
	if source == null or not is_instance_valid(source):
		return blade
	var item := ""
	if source.has_method("held_weapon_id"):
		item = str(source.held_weapon_id())
	if item.is_empty() and source.get("weapon_item") != null:
		item = str(source.get("weapon_item"))
	if not item.is_empty():
		return {"two_handed": item in TWO_HAND_ITEMS, "blunt": item in BLUNT_ITEMS}
	if not source.has_method("swings_two_handed"):
		return blade
	var staff := bool(source.get("staff_active")) if source.get("staff_active") != null else false
	var index := 0
	if source.get("sword_index") != null:
		index = int(source.get("sword_index"))
	return {
		"two_handed": bool(source.swings_two_handed()) or staff,
		"blunt": staff or index >= CLUB_INDEX,
	}


static func _audio() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("Audio")
	return null
