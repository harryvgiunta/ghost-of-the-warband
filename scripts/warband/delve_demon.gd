extends "res://scripts/devil_mob.gd"
## Gorehorn: the thing at the bottom of the Weeping Hollow's first floor.
##
## It is the Hellish goat man - the same imported body, rig and clips as the
## frontier devil (`devil_mob_visual.gd`, `mob_id` "hell_goat") and the same
## authoritative AI - fought as the floor's master: five and a half times the
## goat's pool, a heavier blow, a longer reach and a longer stare, and a body that
## holds its post in the lair instead of roaming. It carries the floor's prize, so
## its corpse is a container like a watcher's (`gear_items`), and it answers the
## world's hunt surface (`hunt`, `hunting`) so the squad's retarget can point it
## at a body like any other hostile.

const Layout = preload("res://scripts/warband/delve_layout.gd")

const BOSS_ID := "hell_goat"
## The master's numbers, laid over the goat's own profile so the clip timing the
## sampler reads (windup, strike, recover) stays the goat's.
const OVERRIDES := {
	"display": "Gorehorn", "health": 400.0, "damage": 21.0, "reach": 2.35,
	"sight": 34.0, "gold": 60, "cooldown": 1.6, "roam": 0.0, "packed": false,
}
## What the body carries: the floor's prize.
const SPOILS := ["sword_arming", "ring_blood", "focus_skull_death", "ichor_vial", "ichor_vial"]

## The pieces still on the body, read once by the loot vacuum when it falls.
var spoils: Array[String] = []


func _init() -> void:
	mob_id = BOSS_ID


func _profiles() -> Dictionary:
	var master: Dictionary = (PROFILES[BOSS_ID] as Dictionary).duplicate(true)
	master.merge(OVERRIDES, true)
	return {BOSS_ID: master}


func _ready() -> void:
	# The devil's own `_ready` renames the body after its species. The cave names
	# it, and the name is what a co-op guest's copy is found by on the wire.
	var label := name
	super()
	name = label
	spoils.assign(SPOILS)
	# A dull hellfire under the body: the lair's master is the one thing in the
	# dark that is lit from where it stands.
	var glow := OmniLight3D.new()
	glow.name = "Hellfire"
	glow.position = Vector3(0.0, 1.2, 0.0)
	glow.light_color = Color(1.0, 0.28, 0.12)
	# The floor is built `Layout.SCALE` times its drawn size, and the light under the
	# master goes with it: the same glow at twice the distance.
	glow.light_energy = 1.4 * Layout.SCALE * Layout.SCALE
	glow.omni_range = 6.5 * Layout.SCALE
	glow.omni_attenuation = 1.4
	glow.shadow_enabled = false
	add_child(glow)


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
