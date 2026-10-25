extends "res://scripts/devil_mob.gd"

## Gameplay profiles for the three Unholy Forest mobs.
##
## This is the same authoritative frontier state machine as the devils
## (`scripts/devil_mob.gd`), with its own profile table, collision sizes,
## group and presentation script. Nothing here changes the devil or cinder
## devil contracts: `RangeWorld.forest_spawns` is a third table beside the
## legacy 36 `enemy_spawns` and the 16 `devil_spawns`.
##
## The mobs own the woodland outside Hearthstead:
##   The hollow warden holds a lane: slow, tall, and reaching far.
##   The ossuary stalker hunts: fast, low health, closes distance quickly.
##   The gallowsroot is terrain that walks: huge, slow, devastating.
##
## Attack cadences are authored around the measured clip impact times so the
## visual strike lands on the damage frame (see `impact` in each GLB JSON):
##   warden 0.78 s of a 1.60 s attack, stalker 0.55 / 1.25, root 1.05 / 2.10.

const FOREST_PROFILES := {
	"hollow_warden": {
		"display": "Hollow warden", "kind": 9,
		"health": 96.0, "damage": 16.0, "reach": 2.35,
		"walk_speed": 1.35, "run_speed": 3.60, "orbit": 5.0,
		"aggro": 30.0, "leash": 52.0, "gold": 13,
		"radius": 0.50, "height": 2.20, "aim": 1.72,
		"windup": 0.55, "strike": 0.20, "recover": 0.65,
		"cooldown": 1.50, "lunge": 5.6, "turn": 8.0,
		"behaviour": "charger", "strafe": 0.85, "blood": 1.00,
	},
	"ossuary_stalker": {
		"display": "Ossuary stalker", "kind": 10,
		"health": 54.0, "damage": 10.0, "reach": 1.95,
		"walk_speed": 1.50, "run_speed": 4.90, "orbit": 6.0,
		"aggro": 32.0, "leash": 46.0, "gold": 10,
		"radius": 0.34, "height": 2.05, "aim": 1.50,
		"windup": 0.30, "strike": 0.13, "recover": 0.42,
		"cooldown": 1.00, "lunge": 7.6, "turn": 11.0,
		"behaviour": "crawler", "strafe": 1.30, "blood": 0.80,
	},
	"gallowsroot": {
		"display": "Gallowsroot", "kind": 11,
		"health": 168.0, "damage": 24.0, "reach": 2.55,
		"walk_speed": 1.00, "run_speed": 2.60, "orbit": 4.4,
		"aggro": 22.0, "leash": 34.0, "gold": 20,
		"radius": 0.46, "height": 2.10, "aim": 1.85,
		"windup": 0.85, "strike": 0.26, "recover": 0.95,
		"cooldown": 2.40, "lunge": 3.4, "turn": 5.0,
		"behaviour": "brute", "strafe": 0.0, "blood": 1.50,
	},
}


func _profiles() -> Dictionary:
	return FOREST_PROFILES


func _group_name() -> String:
	return "forest_mobs"


func _node_prefix() -> String:
	return "Forest_"


func _visual_script():
	return preload("res://scripts/forest_mob_visual.gd")
