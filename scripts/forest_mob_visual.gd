extends "res://scripts/devil_mob_visual.gd"

## Presentation for the three Unholy Forest mobs.
##
## Same sampler as the devils: six authored clips per mob, idle/walk/run
## looping, attack/hit/death one-shot, and the physics clock seeking the
## authored attack so the strike pose lands on the damage frame. Only the
## asset paths, measured clip table and head-zone extents differ.
##
## The warden's entry also names the clips it alone authors - three swings, a
## guard loop, a stagger and a crouch - so one sampler drives the mobset and the
## camp's armed watchers without a second copy of the playback rules.
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
		# The warden is the one mob with a vocabulary: an overhead, a sweeping cut
		# and a lunging thrust, each landing on its own authored frame; a guard it
		# can hold for a window, a recoil a real blow drives out of it, and a
		# stalking crouch it rests in. The camp's watchers pick between them per
		# variant. `attack` above stays the single swing a caller gets when it
		# names none, and the fallback when the asset has not baked the others.
		"attacks": {
			"overhead": {"clip": "Warden_Attack", "duration": 1.60, "impact": 0.78},
			"slash": {"clip": "Warden_Attack_Slash", "duration": 1.35, "impact": 0.66},
			"stab": {"clip": "Warden_Attack_Stab", "duration": 1.10, "impact": 0.50},
		},
		"block": "Warden_Block",
		"stagger": "Warden_Stagger",
		"crouch": "Warden_Crouch",
		# The hand that holds a club is not a ranger's. A held piece is authored
		# for the warband's socket (haft down its own -Z, grip at the origin) and
		# the warden's hand bone runs down the arm, so the grip is fitted to the
		# bone - forward, a third of the way down and out past the fist, clear of
		# the robe at rest and through the windup and impact frames - and sized to
		# the creature's palm. Units: metres in bone space, degrees (XYZ order).
		"grip_scale": 1.70,
		"grip_offset": Vector3(-0.0084, 0.0404, 0.046),
		"grip_rotation": Vector3(137.512, 8.255, 11.131),
		# A bow's limbs are its own +Y, so the aim that puts a club's haft down the
		# fist lays a bow on its side. A piece that needs its own grip says so in
		# the same entry, and the sampler uses it for that kind only.
		"grips": {
			"bow": {"offset": Vector3(-0.0516, 0.043, 0.4307),
				"rotation": Vector3(162.526, 37.472, 7.321)},
		},
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
