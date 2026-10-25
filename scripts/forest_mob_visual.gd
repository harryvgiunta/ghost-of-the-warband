extends "res://scripts/devil_mob_visual.gd"

## Presentation for the three Unholy Forest mobs.
##
## Same sampler as the devils: six authored clips per mob, idle/walk/run
## looping, attack/hit/death one-shot, and the physics clock seeking the
## authored attack so the strike pose lands on the damage frame. Only the
## asset paths, measured clip table and head-zone extents differ.
##
## These values mirror the adjacent GLB metadata; tests/forest_mobs_regression.gd
## compares them against the imported assets.

const FOREST_SCENES := {
	"hollow_warden": "res://assets/characters/forest/ironwood_hollow_warden.glb",
	"ossuary_stalker": "res://assets/characters/forest/ironwood_ossuary_stalker.glb",
	"gallowsroot": "res://assets/characters/forest/ironwood_gallowsroot.glb",
}

const FOREST_DATA := {
	"hollow_warden": {
		"idle": "Warden_Idle", "walk": "Warden_Walk",
		"run": "Warden_Run", "attack": "Warden_Attack",
		"hit": "Warden_Hit", "death": "Warden_Death",
		"walk_speed": 1.35, "run_speed": 3.60, "run_threshold": 2.10,
		"impact": 0.78, "duration": 1.60,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.200, "head_half": 0.140, "organic": false, "hover": 0.0,
	},
	"ossuary_stalker": {
		"idle": "Stalker_Idle", "walk": "Stalker_Walk",
		"run": "Stalker_Run", "attack": "Stalker_Attack",
		"hit": "Stalker_Hit", "death": "Stalker_Death",
		"walk_speed": 1.50, "run_speed": 4.90, "run_threshold": 2.20,
		"impact": 0.55, "duration": 1.25,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.145, "head_half": 0.100, "organic": false, "hover": 0.0,
	},
	"gallowsroot": {
		"idle": "Gallowsroot_Idle", "walk": "Gallowsroot_Walk",
		"run": "Gallowsroot_Run", "attack": "Gallowsroot_Attack",
		"hit": "Gallowsroot_Hit", "death": "Gallowsroot_Death",
		"walk_speed": 1.00, "run_speed": 2.60, "run_threshold": 1.70,
		"impact": 1.05, "duration": 2.10,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.300, "head_half": 0.215, "organic": false, "hover": 0.0,
	},
}


func _scenes() -> Dictionary:
	return FOREST_SCENES


func _data_table() -> Dictionary:
	return FOREST_DATA
