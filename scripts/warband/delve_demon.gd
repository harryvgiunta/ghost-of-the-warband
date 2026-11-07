extends "res://scripts/devil_mob.gd"
## The Hollow's demons: the imported bodies of `devil_mob.gd`, kept below.
##
## Two things come out of this file, and `boss` says which one a body is.
##
## **The master.** Gorehorn is the Hellish goat man - the frontier devil's own
## body (`devil_mob_visual.gd`, `mob_id` "hell_goat") worn on the warband's rig:
## the ranger's bones and authored clips, the goat's hide fitted onto them, and
## the same authoritative AI. Fought as the floor's master: five and a half times
## the goat's pool, a heavier blow, a longer reach and a longer stare
## (`OVERRIDES`), and a body that holds its post in the lair instead of roaming.
## It carries the floor's prize, so its corpse is a container like a watcher's
## (`gear_items`), and it answers the world's hunt surface (`hunt`, `hunting`) so
## the squad's retarget can point it at a body like any other hostile.
##
## **The floor's other demons.** The same body and the same AI, one per chamber of
## the demons' ring and one of every species in the squad that keeps the lair, on
## `KEEPER_OVERRIDES`. They are kept and fed by the watchers that gate them through
## to harvest Ritual Tallow, which is what makes a keeper worth two and a half of
## the wardens standing beside it and still a long way under the master. Every demon
## bleeds the altar's first essence when it falls, so the loot table asks it
## `demon()`.

const Layout = preload("res://scripts/warband/delve_layout.gd")

const BOSS_ID := "hell_goat"
## The master's numbers, laid over the goat's own profile so the clip timing the
## sampler reads (windup, strike, recover) stays the goat's.
const OVERRIDES := {
	"display": "Gorehorn", "health": 400.0, "damage": 21.0, "reach": 2.35,
	"sight": 34.0, "gold": 60, "cooldown": 1.6, "roam": 0.0, "packed": false,
	# The master fights the ring's ladder, not the wood's grind: it guards,
	# circles, and only commits into an opening.
	"duelist": true,
}
## What the master's body carries: the floor's prize.
const SPOILS := ["sword_arming", "ring_blood", "focus_skull_death", "ichor_vial", "ichor_vial"]

## Everything below the master: the keepers of the demons' ring (one a chamber) and
## the squad that keeps the lair (one of every species). They are fed and kept by
## the watchers that gate them through to harvest their essence, which is why one
## keeper is worth two and a half of the wardens that share its floor; and its
## sight is the floor's own 30 m, past nothing a sleeper in another room could see.
const KEEPER_OVERRIDES := {"health": 240.0, "damage": 17.0, "sight": 30.0, "gold": 24,
	"cooldown": 1.4, "roam": 0.0, "duelist": true}

## What each body carries in fire (`demon_fire.gd`): the master the whole kit, so
## its fight is a fireball, a breath and burning ground between its blows; a keeper
## the two that answer a party at range. The breath is the master's own tell, which
## is what makes the bottom of the Hollow a step up from the ring above it.
const BOSS_FIRE := ["fireball", "hellfire_breath", "ember_rain"]
const KEEPER_FIRE := ["fireball", "ember_rain"]

## True for the floor's master (Gorehorn): its own numbers, its prize, and the
## hellfire under it. Every other demon of the floor takes `KEEPER_OVERRIDES`.
var boss := false
## The pieces still on the body, read once by the loot vacuum when it falls.
var spoils: Array[String] = []


func _init() -> void:
	mob_id = BOSS_ID


func _profiles() -> Dictionary:
	var row: Dictionary = (PROFILES[mob_id] as Dictionary).duplicate(true)
	row.merge(OVERRIDES if boss else KEEPER_OVERRIDES, true)
	return {mob_id: row}


func _ready() -> void:
	# The devil's own `_ready` renames the body after its species. The cave names
	# it, and the name is what a co-op guest's copy is found by on the wire.
	var label := name
	super()
	name = label
	if not boss:
		return
	spoils.assign(SPOILS)
	# A dull hellfire under the body: the lair's master is the one thing in the
	# dark that is lit from where it stands. It hangs off the chest the body is
	# actually drawn at - the fit scale the rig stands at - instead of a metre
	# two that was a guess when the goat was its own creature.
	var chest := 1.12
	if is_instance_valid(_visual) and _visual.has_method("drawn_height"):
		chest *= maxf(0.4, float(_visual.drawn_height()))
	var glow := OmniLight3D.new()
	glow.name = "Hellfire"
	glow.position = Vector3(0.0, chest, 0.0)
	glow.light_color = Color(1.0, 0.28, 0.12)
	# The floor is built `Layout.SCALE` times its drawn size, and the light under the
	# master goes with it: the same glow at twice the distance.
	glow.light_energy = 1.4 * Layout.SCALE * Layout.SCALE
	glow.omni_range = 6.5 * Layout.SCALE
	glow.omni_attenuation = 1.4
	glow.shadow_enabled = false
	add_child(glow)


## What the loot table asks a falling body: a demon bleeds the altar's essence and
## keeps no watcher's kit (see `delve_loot.settle`).
func demon() -> bool:
	return true


## The spells this body throws, in the order its brain tries them. Every number is
## `demon_fire.gd`'s table: which spells a body has is the only thing here.
func _fire_kit() -> Array[String]:
	var kit: Array[String] = []
	kit.assign(BOSS_FIRE if boss else KEEPER_FIRE)
	return kit


## Commit to a body: the world's retarget calls this for a hostile that is not
## already hunting.
func hunt(target: Node3D) -> void:
	if not alive or not is_instance_valid(target) or target.get("alive") == false:
		return
	var body := target as CharacterBody3D
	if body == null:
		return
	mob_wake()
	player = body
	_senses.notice(body, body.global_position)


func hunting() -> bool:
	return alerted()


func gear_items() -> Array[String]:
	return spoils.duplicate()


## Nothing is held in its hands: the prize is carried, not wielded.
func take_weapon_item() -> String:
	return ""
