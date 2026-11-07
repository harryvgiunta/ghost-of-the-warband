extends Node3D

## Presentation for the devils, worn on the warband's own body.
##
## A devil is no longer a puppet on six clips. It stands on the ranger's 65
## bones, in the ranger's authored idle, walk, run, swing, guard, flinch and fall,
## wearing its own mesh as a body skin: `tools/prepare_devil_skins.py` fits that
## mesh onto this skeleton - the creature *is* the body, the clips are a human's -
## and `SPECIES` names the four bipeds whose skin is on disk, with the fit scale
## the tool measured. It is the same presentation `scripts/warband/watcher_visual.gd`
## gives the wood's wardens, for the same reason: six creature clips at a coarse
## clock read as stop-motion the moment a body closes on a ranger.
##
## The fitted path is per species, not per mobset. A body whose species names no
## skin - the quadruped Hell beast, a forest mobset overriding `_scenes()` - keeps
## the imported GLB and the authored creature clips it always had, sampled here by
## the same node, and nothing outside this file learns which path a body is on.
## A fitted body's death is the shared ragdoll (`CorpsePhysics`) exactly as a
## ranger's is.
##
## Gameplay owns root motion, damage and death. On the imported path this node
## samples the authored GLB clips, maps the six gameplay states onto
## idle/walk/run/attack/hit/death, and adjusts the physics-clock attack playback
## so the authored impact frame always coincides with the gameplay strike. On the
## fitted path the same states drive the rig: a windup opens the authored swing
## and stretches it onto the mob's own telegraph, so the claw crosses the target
## on the frame its damage resolves.
##
## The table entry may name more than the six: `attacks` is a dictionary of
## named swings (each with its own clip, duration and impact, so a lunge and a
## sweep each land on their own frame), `block` a guard loop, `stagger` the
## one-shot a heavy blow drives the body back onto and `crouch` the stance it
## rests in. A body that names none of them is the same single-swing mob it was,
## and the sampler is the only place that knows the difference - controllers say
## what the body is doing (`set_attack`, `set_poise`) and the table decides how
## that looks. A catalog piece in the hand (`set_held_weapon`) and the body's own
## paint (`set_tint`) are the other two things a variant can change without
## forking any of this.

const MobLod = preload("res://scripts/mob_lod.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const Sword = preload("res://scripts/sword.gd")
const Dagger = preload("res://scripts/dagger.gd")
const Bow = preload("res://scripts/bow.gd")
## The catalog, so a mob holds the piece its id names rather than a shape that
## only resembles it, and the rig's own weapon dimensions, so the club in a
## warden's hand is the club the warband swings.
const Catalog = preload("res://scripts/player_state.gd")
const Archer = preload("res://scripts/archer.gd")
const Perf = preload("res://scripts/perf_probe.gd")

const SCENES := {
	"hell_goat": "res://assets/characters/devils/ironwood_hell_goat.glb",
	"succubus": "res://assets/characters/devils/ironwood_succubus.glb",
	"spawn": "res://assets/characters/devils/ironwood_spawn.glb",
	"beast": "res://assets/characters/devils/ironwood_beast.glb",
	"gargoyle": "res://assets/characters/devils/ironwood_gargoyle.glb",
}

## Clip inventory, measured playback speeds and head-zone extents.
## These mirror the adjacent GLB metadata; tests/devil_mobs_regression.gd
## compares them against the imported assets.
const DATA := {
	"hell_goat": {
		"idle": "HellGoat_Idle_Loop", "walk": "HellGoat_Walk_Loop",
		"run": "HellGoat_Run_Loop", "attack": "HellGoat_Attack",
		"hit": "HellGoat_Hit", "death": "HellGoat_Death",
		"walk_speed": 1.50, "run_speed": 4.00, "run_threshold": 2.15,
		"impact": 0.62, "duration": 1.45,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.20, "head_half": 0.15, "organic": true, "hover": 0.0,
	},
	"succubus": {
		"idle": "Succubus_Idle_Loop", "walk": "Succubus_Walk_Loop",
		"run": "Succubus_Run_Loop", "attack": "Succubus_Attack",
		"hit": "Succubus_Hit", "death": "Succubus_Death",
		"walk_speed": 1.40, "run_speed": 4.20, "run_threshold": 2.00,
		"impact": 0.58, "duration": 1.35,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.135, "head_half": 0.095, "organic": true, "hover": 0.0,
	},
	"spawn": {
		"idle": "Spawn_Idle_Loop", "walk": "Spawn_Walk_Loop",
		"run": "Spawn_Run_Loop", "attack": "Spawn_Attack",
		"hit": "Spawn_Hit", "death": "Spawn_Death",
		"walk_speed": 1.30, "run_speed": 4.60, "run_threshold": 1.95,
		"impact": 0.48, "duration": 1.10,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.165, "head_half": 0.13, "organic": true, "hover": 0.0,
	},
	"beast": {
		"idle": "Beast_Idle_Loop", "walk": "Beast_Walk_Loop",
		"run": "Beast_Run_Loop", "attack": "Beast_Attack",
		"hit": "Beast_Hit", "death": "Beast_Death",
		"walk_speed": 1.40, "run_speed": 3.80, "run_threshold": 2.40,
		"impact": 0.82, "duration": 1.60,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.38, "head_half": 0.20, "organic": true, "hover": 0.0,
	},
	"gargoyle": {
		"idle": "Gargoyle_Idle_Loop", "walk": "Gargoyle_Walk_Loop",
		"run": "Gargoyle_Run_Loop", "attack": "Gargoyle_Attack",
		"hit": "Gargoyle_Hit", "death": "Gargoyle_Death",
		"walk_speed": 1.00, "run_speed": 2.80, "run_threshold": 1.80,
		"impact": 0.95, "duration": 1.80,
		"head_offset": Vector3.ZERO,
		"head_radius": 0.30, "head_half": 0.20, "organic": false, "hover": 0.0,
	},
}

const MOVE_THRESHOLD := 0.22

## The species worn on the warband's rig: the skin the fit tool exported, the
## creature GLB whose PBR atlases it borrows (a skin ships no images of its own),
## the node, and the measured fit scale - the creature's neck height over the
## ranger's, which is both how the skin was authored and how tall the body stands.
## `fur` is the one creature whose coat used to be a shell of spike geometry: its
## body surface wears the strand tile `tools/devil_fur.py` authors instead.
const SPECIES := {
	"hell_goat": {
		"skin": "res://assets/characters/devils/fitted/ironwood_devil_hell_goat.glb",
		"materials": "res://assets/characters/devils/ironwood_hell_goat.glb",
		"node": "Devil_HellGoat",
		"fit": 1.0800,
		"fur": {
			"material": "Skin_HellGoat",
			"albedo": "res://assets/characters/devils/ironwood_devil_fur.png",
			"normal": "res://assets/characters/devils/ironwood_devil_fur_n.png",
			"roughness": 0.88, "specular": 0.22, "tiles": 2.0,
		},
	},
	"succubus": {
		"skin": "res://assets/characters/devils/fitted/ironwood_devil_succubus.glb",
		"materials": "res://assets/characters/devils/ironwood_succubus.glb",
		"node": "Devil_Succubus",
		"fit": 0.9766,
	},
	"spawn": {
		"skin": "res://assets/characters/devils/fitted/ironwood_devil_spawn.glb",
		"materials": "res://assets/characters/devils/ironwood_spawn.glb",
		"node": "Devil_Spawn",
		"fit": 0.5664,
	},
	"gargoyle": {
		"skin": "res://assets/characters/devils/fitted/ironwood_devil_gargoyle.glb",
		"materials": "res://assets/characters/devils/ironwood_gargoyle.glb",
		"node": "Devil_Gargoyle",
		"fit": 1.6200,
	},
}

## The swing vocabulary a fitted body speaks, mapped onto the rig's authored
## cuts: the overhead is the two-handed chop (on an empty hand, the slam a devil
## attacks with), the slash the diagonal cut, the stab the dagger lunge.
const SWINGS := {"overhead": "overhead", "slash": "diagonal_right", "stab": "stab"}

## Where the rig's swing opens its strike window (see `Archer._melee_window`:
## `windup = (duration - cut) * 0.55`), and how far into the mob's strike state
## its damage resolves (`DevilMob` at `strike * 0.34`). The swing is stretched so
## those two land together: the claw is crossing the target on the damage frame.
const BLADE_IMPACT_SHARE := 0.55
const STRIKE_DAMAGE_SHARE := 0.34
## The rig's flinch is a pose, not a clip: `Archer._apply_hit_react_pose` runs for
## this long and eases out over 0.42 s.
const FLINCH_SECONDS := 0.34
## How far into the rig's crouch a crouch-armed body folds. The authored pose is a
## full squat; a devil that hunts from a crouch wants a hunch that keeps its
## height, so a partial crouch is the stance.
const CROUCH_AMOUNT := 0.62
## Where a body is aimed at and where a shaft would leave it: the chest of the
## authored rig, in metres, times the drawn height. Every skin is fitted onto that
## same rig, so one fraction is honest for a goat and a gargoyle alike.
const CHEST_HEIGHT := 1.50
const FRONT_RANGE := 5.0

var mob_id := "hell_goat"
var profile: Dictionary = {}

## Whether this body wears the warband's rig, and the species whose skin it is.
var _fitted := false
var _species := ""
var _spec: Dictionary = {}
## The rig wearing the skin.
var _rig
## The state machine's own answer, kept for the fitted path's edge detection.
var _state := ""
var _state_time := 0.0
## Render budget: the band the body is being presented in, whether it is close
## enough to pose every frame, and whether the culler has parked it.
var _band := -1
var _near := true
var _parked := false
## One harvested set of creature materials per species, per process: a skin ships
## no images, so the atlases come from the creature's own GLB and are copied (and
## painted) per body.
static var _sources: Dictionary = {}
## One loaded copy of each tile the fitted bodies wear, per process.
static var _tiles: Dictionary = {}

var _data: Dictionary
var _instance: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone := -1
var _strike_bone := -1
var _clip := ""
var _speed := 0.0
var _grounded := true
var _attack_playing := false
var _combat_state := ""
var _combat_time := 0.0
var _last_state := ""
var _hit_playing := false
var _hit_time := 0.0
var _hit_duration := 0.5
var _dead := false
var _death_time := 0.0
var _death_held := false
var _hover_time := 0.0
## The named swing the next windup plays ("" is the body's single attack).
var _attack := ""
## The stance the controller asked for: a held guard, a crouched rest.
var _blocking := false
var _crouched := false
## The per-body paint. Every surface material is duplicated for this instance in
## `_tune_materials`, so tinting one warden cannot repaint the one beside it.
var _tint := Color.WHITE
var _paint: Array[StandardMaterial3D] = []
var _paint_base: Array[Color] = []
## The catalog piece in the hand, the bone attachment that follows the hand and
## the fitted grip under it.
## The swing the sampler lays over the clip. The mobset's attack clips raise the
## weapon arm and then hold it up: played straight they read as a statue with a
## club over its head, and the piece in the hand never travels. So the sampler
## owns the arc - a cock-back through the windup, a fast whip that peaks on the
## frame the blow lands, and a settle through the recovery - applied on top of
## whatever the clip did, on the same clock the damage uses.
##
## Axes are bone-local, measured on the warden's rig: `clavicle_r` +Y lifts the
## arm overhead, +X drops it forward, +Z crosses it behind the body.
const SWING_COCK := {
	"clavicle_r": Vector3(0.0, -60.0, -60.0),
	"upperarm_r": Vector3(0.0, 0.0, -60.0),
	"lowerarm_r": Vector3(-10.0, 0.0, 0.0),
	"hand_r": Vector3(-40.0, 0.0, 40.0),
	"spine_02": Vector3(0.0, 0.0, 10.0),
	"spine_03": Vector3(0.0, 0.0, 14.0),
}
const SWING_THROUGH := {
	"clavicle_r": Vector3(-70.0, 10.0, 30.0),
	"upperarm_r": Vector3(30.0, 0.0, 40.0),
	"lowerarm_r": Vector3(18.0, 0.0, 0.0),
	"hand_r": Vector3(60.0, 0.0, -24.0),
	"spine_02": Vector3(0.0, 0.0, -14.0),
	"spine_03": Vector3(0.0, 0.0, -18.0),
}
## How far into the strike state the blow lands. The mob resolves its damage at
## 34% of the strike window, and the weapon is at full extension on that frame.
const SWING_IMPACT_SHARE := 0.34
## How far past the through pose the follow-through carries the arm before it
## settles: a swing that stops dead on the target reads as a pose, not a blow.
const SWING_OVERSHOOT := 0.18
## The rest pose every other table is interpolated against.
const ZERO_SWING := {}

var _held_item := ""
var _held: Node3D
var _hold: BoneAttachment3D
var _grip: Node3D
var _grip_scale := 1.0
var _swing_bones: Dictionary = {}
## The pose each swing bone had when the windup opened. The arc is authored on
## top of that snapshot and *replaces* the clip's own arm pose while the swing
## runs: the mobset's attack clips raise the arm and hold it, so adding to them
## pushed the arm past vertical and the club dropped during the windup instead of
## travelling on the strike.
var _swing_base: Dictionary = {}


func _ready() -> void:
	var spec := _fitted_spec()
	if not spec.is_empty():
		_build_fitted(spec)
		return
	_build_sampler()


## The species this body wears on the warband's rig, or `{}` for a body that
## keeps its imported creature.
func _fitted_spec() -> Dictionary:
	if not SPECIES.has(str(mob_id)):
		return {}
	return SPECIES[str(mob_id)] as Dictionary


## The imported creature, sampled on its own clips. Every devil that has no
## fitted skin of its own - and every mobset that inherits this node - lands here.
func _build_sampler() -> void:
	var scenes := _scenes()
	if not scenes.has(mob_id):
		push_error("Unknown mob: " + mob_id)
		return
	_data = _data_table()[mob_id]
	# The weapon models are authored for a ranger's palm; a body whose hand is
	# bigger says so in its own entry rather than every call passing it in.
	_grip_scale = maxf(0.1, float(_data.get("grip_scale", 1.0)))
	var packed: PackedScene = load(str(scenes[mob_id]))
	if packed == null:
		push_error("Missing mob scene: " + str(scenes[mob_id]))
		return
	_instance = packed.instantiate()
	add_child(_instance)
	_player = _instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_skeleton = _instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if _player == null or _skeleton == null:
		push_error("Mob visual is missing its AnimationPlayer or Skeleton3D: " + mob_id)
		return
	_head_bone = _skeleton.find_bone("head")
	# The swing's own bones, resolved once: a body whose rig names none of them
	# simply gets the clip it always had.
	for key in SWING_COCK:
		var index := _skeleton.find_bone(str(key))
		if index >= 0:
			_swing_bones[str(key)] = index
	# The overlay has to land after the AnimationPlayer has written this frame's
	# pose, or the clip erases it: a later process priority is later in the frame.
	process_priority = 20
	# The limb that lands the blow: hand for the bipeds, front paw for the
	# quadruped beast, head as the last resort.
	_strike_bone = _skeleton.find_bone("hand_r")
	if _strike_bone < 0:
		_strike_bone = _skeleton.find_bone("front_paw_r")
	if _strike_bone < 0:
		_strike_bone = _head_bone
	for key in ["idle", "walk", "run", "attack", "hit", "death"]:
		if not _player.has_animation(str(_data[key])):
			push_error("Mob visual is missing clip %s for %s" % [_data[key], mob_id])
			return
	for key in ["idle", "walk", "run"]:
		_player.get_animation(str(_data[key])).loop_mode = Animation.LOOP_LINEAR
	for key in ["attack", "hit", "death"]:
		_player.get_animation(str(_data[key])).loop_mode = Animation.LOOP_NONE
	# The optional vocabulary: a body that authors several swings, a guard, a
	# stagger or a crouch names them in its own table entry. A body that names
	# none - the Hell beast, the stalker, the root - stays the single-swing mob it
	# always was, and the loop semantics are set here because the importer does
	# not carry them.
	for name in attack_names():
		if has_clip(attack_clip(name)):
			_player.get_animation(attack_clip(name)).loop_mode = Animation.LOOP_NONE
	for clip in [block_clip(), crouch_clip()]:
		if has_clip(clip):
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	if has_clip(stagger_clip()):
		_player.get_animation(stagger_clip()).loop_mode = Animation.LOOP_NONE
	_hit_duration = _player.get_animation(str(_data["hit"])).length
	_clip = str(_data["idle"])
	_player.play(_clip, 0.0)
	_player.speed_scale = 1.0
	_tune_materials()


## Virtual so a second mobset reuses this sampler instead of forking it:
## scripts/forest_mob_visual.gd overrides both tables.
func _scenes() -> Dictionary:
	return SCENES


func _data_table() -> Dictionary:
	return DATA


# --- the fitted body --------------------------------------------------------

## Build the body on the warband's rig: the ranger's 65 bones and authored
## library, the creature's own mesh fitted onto that skeleton as a skin, and the
## same distance budget every other rig in the wood lives on.
func _build_fitted(spec: Dictionary) -> void:
	_fitted = true
	_species = str(mob_id)
	_spec = spec
	_data = _data_table().get(mob_id, {})
	_rig = Archer.new()
	_rig.name = "DevilRig"
	# One facing, one quarry: the mob turns this body itself, and the walk cycle
	# may pose the legs but must not snap it onto its velocity while it circles.
	_rig.heading_locked = true
	# Nothing is built in the hand up front: a devil carries nothing, and the one
	# piece the rig needs to open a cut is made on demand (`_dress_claws`).
	_rig.sparse_props = true
	# Its pose is only ever looked at - the brain owns the blows - so the rig may
	# pose on the drawn frame, and more coarsely where the camera cannot see it.
	_rig.view_paced = true
	_rig.body_skin = {"path": str(spec.get("skin", "")),
		"node": str(spec.get("node", "DevilSkin")), "height": fit_scale()}
	add_child(_rig)
	_dress_skin()
	_dress_claws()


## Whether this body wears the warband's rig rather than its imported creature.
func is_fitted() -> bool:
	return _fitted


## The measured fit scale of the skin this body wears: the creature's neck height
## over the ranger's. The rig stands at that scale, so it is also the number every
## measurement taken off the body multiplies by.
func fit_scale() -> float:
	return float(_spec.get("fit", 1.0))


## The height the body is drawn at, relative to the authored ranger rig.
func drawn_height() -> float:
	return _rig.body_scale() if is_instance_valid(_rig) else fit_scale()


## Every surface of the skin wears the creature's own material, copied so this
## body's paint is its own. A skin ships no images: the PBR atlases come from the
## creature's shipped GLB, matched by the material names the fit tool carried
## across - which is why the fur tile is applied here, on the surface the removed
## spike proxy used to stand in front of.
func _dress_skin() -> void:
	_paint.clear()
	_paint_base.clear()
	if not is_instance_valid(_rig):
		return
	var sources := _source_materials(_species)
	var fur: Dictionary = _spec.get("fur", {})
	for mesh in _rig.skin_meshes():
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var named := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			var key := named.resource_name if named != null else ""
			var source: StandardMaterial3D = sources.get(key, named)
			if source == null:
				continue
			var tuned := source.duplicate() as StandardMaterial3D
			if tuned == null:
				continue
			tuned.emission_energy_multiplier = 1.35
			tuned.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			if not fur.is_empty() and str(fur.get("material", "")) == key:
				_dress_fur(tuned, fur)
			mesh.set_surface_override_material(surface, tuned)
			_paint.append(tuned)
			_paint_base.append(tuned.albedo_color)


## The coat: a tiling strand tile where the body's atlas used to be, with hair's
## roughness and no metallic push, so the hide reads as black fur rather than a
## black plastic shell. The relief is the tile's own normal map, and the atlas's
## vertex tint is turned off - the coat is the tile's colour, not the old one's.
func _dress_fur(tuned: StandardMaterial3D, fur: Dictionary) -> void:
	tuned.albedo_color = Color.WHITE
	tuned.albedo_texture = _tile(str(fur.get("albedo", "")))
	tuned.vertex_color_use_as_albedo = false
	tuned.vertex_color_is_srgb = false
	tuned.metallic = 0.0
	tuned.metallic_specular = float(fur.get("specular", 0.22))
	tuned.roughness = float(fur.get("roughness", 0.88))
	var normal := _tile(str(fur.get("normal", "")))
	if normal != null:
		tuned.normal_enabled = true
		tuned.normal_texture = normal
		tuned.normal_scale = 0.8
	var tiles := maxf(1.0, float(fur.get("tiles", 1.0)))
	tuned.uv1_scale = Vector3(tiles, tiles, 1.0)


## One shared texture per path: sixty bodies wear the same two tiles, and a load
## per body would be sixty copies of the same 512 square.
static func _tile(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tiles.has(path):
		return _tiles[path] as Texture2D
	var loaded: Texture2D = null
	if ResourceLoader.exists(path):
		loaded = load(path) as Texture2D
	if loaded == null:
		push_error("Missing devil fur tile: " + path)
	_tiles[path] = loaded
	return loaded


## One harvested material list per species: the skin's surfaces are the creature
## mesh's surfaces under the same names, because the skin *is* that mesh.
static func _source_materials(species_id: String) -> Dictionary:
	if _sources.has(species_id):
		return _sources[species_id] as Dictionary
	var out := {}
	var path := str((SPECIES[species_id] as Dictionary).get("materials", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var instance := packed.instantiate() as Node3D
			for node in instance.find_children("*", "MeshInstance3D", true, false):
				var mesh := node as MeshInstance3D
				if mesh.mesh == null:
					continue
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as StandardMaterial3D
					if material != null and not material.resource_name.is_empty():
						out[material.resource_name] = material
			instance.free()
	_sources[species_id] = out
	return out


# --- the claw in the hand ---------------------------------------------------

## The claw stance: hands empty and the body still able to cut. `Archer` opens a
## melee only for a hand that carries a piece, so the lightest sword is built and
## kept out of every render pass: the arm solves the authored overhead - which on
## an empty hand is the slam a devil attacks with - and nothing is drawn. A
## devil's fist is its weapon; nothing here deals or takes a point of damage.
func _dress_claws() -> void:
	if not is_instance_valid(_rig):
		return
	_rig.set_staff(0, false)
	_rig.set_off_focus("", 0, false)
	_rig.set_off_weapon("", 0, false)
	_rig.set_shield(false)
	_rig.set_sword(0)
	_rig.set_weapon("sword")
	_set_drawn(_rig.active_sword, false)


## The piece in the hand when one is asked for: the catalog model through the
## rig's own weapon slots, so it is gripped by the hand bones and follows every
## clip. `""` is the claw stance.
func _dress_weapon() -> void:
	if not is_instance_valid(_rig):
		return
	var item: Dictionary = Catalog.ITEMS.get(_held_item, {})
	var kind := str(item.get("kind", ""))
	if kind.is_empty():
		_dress_claws()
		return
	var index := int(item.get("index", 0))
	_rig.set_staff(0, false)
	_rig.set_off_focus("", 0, false)
	_rig.set_off_weapon("", 0, false)
	_rig.set_shield(false)
	match kind:
		"sword":
			_rig.set_sword(index)
			_rig.set_weapon("sword")
			_set_drawn(_rig.active_sword, true)
		"dagger":
			_rig.set_dagger_index(index)
			_rig.set_weapon("dagger")
			_set_drawn(_rig.active_dagger, true)
		"bow":
			_rig.set_bow(index)
			_rig.set_weapon("bow")
			_set_drawn(_rig.active_bow, true)
		_:
			_dress_claws()


## Whether a piece of kit is drawn. A hidden piece still solves, follows the hand
## and takes a stain; only the draw call goes away.
func _set_drawn(node: Node3D, drawn: bool) -> void:
	if node == null or not is_instance_valid(node):
		return
	for child in node.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).layers = 1 if drawn else 0


## The rig clip a named swing plays, for whoever promises a scene it will be
## shown. A diagonal reuses the authored heavy clip (`Archer._melee_clip_for`).
func _clip_for(variant: String) -> String:
	if not is_instance_valid(_rig):
		return ""
	if variant in ["diagonal_left", "diagonal_right"]:
		return "Sword_Overhead"
	if variant == "stab" or _rig.weapon == "dagger":
		return "Dagger_Stab"
	return "Sword_Overhead" if _rig.sword_index == 2 else "Sword_Overhead_OneHand"


# --- the fitted fight -------------------------------------------------------

## The states the rig answers, on the mob's own clock: a windup opens a swing, a
## stagger breaks one, and the rest is the rig finishing the arc it started.
func _fitted_combat(state: String, time: float) -> void:
	var previous := _state
	_state = state
	_state_time = time
	_combat_state = state
	_combat_time = time
	if _dead:
		return
	if state == "DEAD":
		die()
		return
	if state == "WINDUP":
		if previous != "WINDUP":
			_open_swing()
	elif state == "STAGGER":
		if previous != "STAGGER":
			_flinch()


## Open the swing the windup just chose. The rig's strike window is stretched onto
## the mob's own telegraph, so the claw is crossing the target on the frame its
## damage resolves.
func _open_swing() -> void:
	if not is_instance_valid(_rig):
		return
	if _rig.weapon == "bow":
		_rig.begin_draw()
		return
	if _rig.begin_melee("right", str(SWINGS.get(_attack, "overhead"))):
		_rig.retime_melee("right", _swing_seconds())


## How long the authored swing must run for its strike window to open on the
## mob's damage frame.
func _swing_seconds() -> float:
	var windup := maxf(0.05, float(profile.get("windup", 0.55)))
	var strike := maxf(0.05, float(profile.get("strike", 0.20)))
	return (windup + strike * STRIKE_DAMAGE_SHARE) / BLADE_IMPACT_SHARE


## A real blow breaks the swing and the guard: the body takes the recoil instead
## of finishing the cut.
func _flinch() -> void:
	if not is_instance_valid(_rig):
		return
	_rig.cancel_draw()
	_rig.abort_melee("right")
	_rig.set_hit_react(FLINCH_SECONDS)


## A point in front of the body at chest height: what the rig's own aim solve
## turns the chest onto, so a devil holds its quarry instead of its walk
## direction.
func _forward_point() -> Vector3:
	var forward := -global_basis.z
	return global_position + forward * FRONT_RANGE \
		+ Vector3.UP * (CHEST_HEIGHT * drawn_height())


## Range budget, on the same bands every body in the wood uses: past
## `MobLod.ANIMATE_DISTANCE` the rig stops evaluating tracks, past
## `SHADOW_DISTANCE` it stops casting, and a parked body stops posing at all.
func _apply_clock() -> void:
	if not _fitted or not is_instance_valid(_rig) or _dead:
		return
	# A body that has not been banded yet is drawn at full detail, not ignored:
	# the last thing this node may do is leave a rig unposed because nobody has
	# measured it since it spawned.
	var band := maxi(_band, 0)
	_rig.set_physics_process(not _parked and band < 2)
	_rig.set_pose_stride(1 if _near else 2 if band <= 0 else MobLod.MID_FRAMES)
	_rig.set_shadow_casting(not _parked and band <= 0)


# --- the authored vocabulary ----------------------------------------------

## The swings this body authors, by name. Empty for a mob that has one swing:
## the table's single `attack` is then the whole of its vocabulary. A fitted body
## authors whatever the rig can cut with, because the rig is what swings it.
func attack_names() -> Array[String]:
	if _fitted:
		var swings: Array[String] = []
		for name in SWINGS.keys():
			swings.append(str(name))
		swings.sort()
		return swings
	var out: Array[String] = []
	for name in (_data.get("attacks", {}) as Dictionary).keys():
		out.append(str(name))
	out.sort()
	return out


## The clip a named swing plays, or "" when the body does not author it.
func attack_clip(name: String) -> String:
	if _fitted:
		return _clip_for(str(SWINGS.get(name, "")))
	var authored: Dictionary = _data.get("attacks", {})
	return str((authored.get(name, {}) as Dictionary).get("clip", ""))


## The guard loop this body holds, or "" when it has no guard of its own.
func block_clip() -> String:
	if _fitted:
		return "Sword_Block_Loop" if is_instance_valid(_rig) and _rig.sword_index == 2 \
			else "Sword_Block_Loop_OneHand"
	return str(_data.get("block", ""))


## The one-shot a heavy blow drives the body back onto. A mob with no stagger of
## its own takes the hit react: the same recoil, shorter. On the rig the recoil is
## a pose rather than a clip, so a fitted body names none.
func stagger_clip() -> String:
	if _fitted:
		return ""
	return str(_data.get("stagger", _data.get("hit", "")))


## The stance this body rests in, or "" when it never crouches.
func crouch_clip() -> String:
	if _fitted:
		return "Crouch_Idle_Loop"
	return str(_data.get("crouch", ""))


## Whether the imported player carries `clip` at all. The table promises the
## names; this is the asset keeping the promise. Playback falls back on its own,
## so nothing silent happens at runtime - the regression is what fails when a
## promised clip is not baked. A fitted body is answered by the rig's own library.
func has_clip(clip: String) -> bool:
	if _fitted:
		return is_instance_valid(_rig) and _rig.has_clip(clip)
	return _player != null and not clip.is_empty() and _player.has_animation(clip)


## Choose what the next windup plays: "" is the body's single authored attack,
## a name from `attack_names()` is one of several.
func set_attack(name: String) -> void:
	_attack = name


func current_attack() -> String:
	return _attack


## The stance the controller wants: a held guard and a crouched rest.
## `_select_locomotion` picks the authored clip for both, so a controller only
## says what the body is doing and the sampler decides how it looks. A fitted
## body is asked the same question and answers it on the rig: the authored guard
## loop, and a partial crouch rather than the full squat the ranger authors.
func set_poise(blocking: bool, crouched: bool) -> void:
	if blocking == _blocking and crouched == _crouched:
		return
	_blocking = blocking
	_crouched = crouched
	if _dead:
		return
	if _fitted:
		if not is_instance_valid(_rig):
			return
		_rig.set_blocking(blocking, -global_basis.z)
		_rig.set_cover(false, Vector3.ZERO,
			CROUCH_AMOUNT if crouched and not blocking else 0.0, false, Vector3.ZERO)
		return
	if _attack_playing or _hit_playing:
		return
	_select_locomotion()


## The paint this body wears. Each instance owns duplicates of its surfaces, so a
## tint is the body's own and the body beside it keeps its colour.
func set_tint(tint: Color) -> void:
	_tint = tint
	for index in _paint.size():
		_paint[index].albedo_color = _paint_base[index] * tint


func tint() -> Color:
	return _tint


# --- the piece in the hand -------------------------------------------------

## Put a catalog piece in this body's right hand. The model is the one the
## warband holds - `Sword`/`Dagger`/`Bow` built from the catalog's own kind and
## index - hung off the hand bone so it follows every authored clip, and the
## physical bones the corpse becomes. `""` leaves the hand empty: on the
## imported path that is the arm hanging, and on the fitted path it is the claw
## stance the rig cuts with (`_dress_claws`).
func set_held_weapon(item_id: String) -> void:
	if item_id == _held_item:
		return
	_held_item = item_id
	if _fitted:
		_dress_weapon()
		return
	if _held != null and is_instance_valid(_held):
		_held.queue_free()
	_held = null
	if item_id.is_empty():
		return
	var item: Dictionary = Catalog.ITEMS.get(item_id, {})
	if item.is_empty():
		return
	var kind := str(item.get("kind", ""))
	var piece: Node3D = _weapon_node(kind, int(item.get("index", 0)))
	if piece == null:
		return
	var hand := _hand(kind)
	if hand == null:
		piece.queue_free()
		return
	hand.add_child(piece)
	piece.scale = Vector3.ONE * _grip_scale
	# A piece in a mob's hand is carried, not used: a bow is not nocked until it
	# is drawn, and nothing here draws one.
	if piece.has_method("set_arrow_visible"):
		piece.set_arrow_visible(false)
	_held = piece


## The catalog id the hand is actually holding, or "" when it is empty.
func held_item() -> String:
	if _fitted:
		return _held_item if _rig_holds_piece() else ""
	return _held_item if _held != null else ""


## Whether the rig is in the mode the catalog piece needs: a body told to hold a
## club is only holding it if the rig is carrying one.
func _rig_holds_piece() -> bool:
	if _held_item.is_empty() or not is_instance_valid(_rig):
		return false
	var item: Dictionary = Catalog.ITEMS.get(_held_item, {})
	var kind := str(item.get("kind", ""))
	match kind:
		"bow":
			return _rig.weapon == "bow"
		"dagger":
			return _rig.weapon == "dagger"
		"sword":
			return _rig.weapon == "sword"
	return false


func _weapon_node(kind: String, index: int) -> Node3D:
	match kind:
		"sword":
			var sword = Sword.new()
			sword.sword_kind = index
			sword.blade_length = float(Archer.SWORD_DATA[
				clampi(index, 0, Archer.SWORD_DATA.size() - 1)].length)
			return sword
		"dagger":
			var dagger = Dagger.new()
			dagger.dagger_kind = index
			dagger.blade_length = float(Archer.dagger_profile(index).length)
			return dagger
		"bow":
			var bow = Bow.new()
			bow.bow_kind = index
			bow.bow_length = float(Archer.BOW_DATA[
				clampi(index, 0, Archer.BOW_DATA.size() - 1)].length)
			return bow
	return null


## The hand bone's attachment and the grip under it, built on first use.
##
## A `BoneAttachment3D` rewrites its own transform from the bone every frame, so
## a rotation set on it is discarded: the grip therefore lives on a child. The
## attachment follows the hand (including the limp physical bones the corpse
## becomes) and the grip owns the rotation and offset that put a catalog piece -
## authored for the warband's socket, haft down its own -Z with the grip at the
## origin - into this creature's fist, aimed by its own table entry.
func _hand(kind: String) -> Node3D:
	if _grip == null or not is_instance_valid(_grip):
		if _skeleton == null or _strike_bone < 0:
			return null
		_hold = BoneAttachment3D.new()
		_hold.name = "HeldWeapon"
		_hold.bone_name = _skeleton.get_bone_name(_strike_bone)
		_skeleton.add_child(_hold)
		_grip = Node3D.new()
		_grip.name = "Grip"
		_hold.add_child(_grip)
	_apply_grip(kind)
	return _grip


## The grip the entry gives this kind of piece: the flat `grip_*` keys are every
## piece's, and `grips` overrides them per catalog kind - a bow's limbs are its
## own +Y, so it cannot share the aim that puts a club's haft down the fist.
func _apply_grip(kind: String) -> void:
	var override: Dictionary = (_data.get("grips", {}) as Dictionary).get(kind, {})
	_grip.position = override.get("offset", _data.get("grip_offset", Vector3.ZERO))
	var degrees: Vector3 = override.get("rotation", _data.get("grip_rotation", Vector3.ZERO))
	_grip.basis = Basis.from_euler(Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y),
		deg_to_rad(degrees.z)), EULER_ORDER_XYZ)


## The swing the current windup plays, with its authored impact and length. A
## body with one attack falls back to its single entry, so nothing that never
## asked for a named swing changes.
func _attack_entry() -> Dictionary:
	var authored: Dictionary = _data.get("attacks", {})
	var entry: Dictionary = authored.get(_attack, {})
	if entry.is_empty() or not has_clip(str(entry.get("clip", ""))):
		return {"clip": _data["attack"], "duration": _data["duration"],
			"impact": _data["impact"]}
	return entry


func _block_target() -> String:
	return block_clip() if has_clip(block_clip()) else str(_data["idle"])


func _crouch_target() -> String:
	return crouch_clip() if has_clip(crouch_clip()) else str(_data["idle"])


func _stagger_target() -> String:
	return stagger_clip() if has_clip(stagger_clip()) else str(_data["hit"])


func _tune_materials() -> void:
	if _instance == null:
		return
	_paint.clear()
	_paint_base.clear()
	for mesh_instance in _instance.find_children("*", "MeshInstance3D", true, false):
		var node := mesh_instance as MeshInstance3D
		for surface in node.mesh.get_surface_count():
			var material := node.get_active_material(surface)
			if material is StandardMaterial3D:
				var tuned := (material as StandardMaterial3D).duplicate() as StandardMaterial3D
				tuned.emission_energy_multiplier = 1.35
				tuned.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				var mat_name := tuned.resource_name.to_lower()
				var fleshy := mat_name.contains("skin") or mat_name.contains("membrane") \
						or mat_name.contains("fur") or mat_name.contains("flesh")
				if bool(_data.get("organic", false)) and fleshy \
						and RenderingServer.get_current_rendering_method() == "forward_plus":
					tuned.subsurf_scatter_enabled = true
					tuned.subsurf_scatter_strength = 0.06
				node.set_surface_override_material(surface, tuned)
				_paint.append(tuned)
				_paint_base.append(tuned.albedo_color)


## Range budget for this body: animation tracks stop past
## `MobLod.ANIMATE_DISTANCE`, the shadow pass past `MobLod.SHADOW_DISTANCE`.
## Called only when the band flips, never per frame.
func set_distance(distance: float) -> void:
	if not _fitted:
		MobLod.present(_instance, _player, distance)
		return
	var band := MobLod.band(distance)
	var near := distance <= MobLod.POSE_NEAR
	if band == _band and near == _near:
		return
	_band = band
	_near = near
	_apply_clock()


## Parked by the culler: the body is hidden and parked, so the rig must stop
## posing too - an invisible rig that keeps sampling tracks costs the same as a
## visible one.
func set_parked(parked: bool) -> void:
	if parked == _parked:
		return
	_parked = parked
	_apply_clock()


func set_motion(velocity: Vector3, grounded: bool) -> void:
	if _fitted:
		if not is_instance_valid(_rig):
			return
		# A view-paced rig poses from the drawn frame, after this tick, so its
		# turn is taken there (`Archer._process`).
		_rig.aim_at(_forward_point(), not _rig.view_paced)
		_rig.set_locomotion(velocity, grounded)
		return
	_speed = Vector2(velocity.x, velocity.z).length()
	_grounded = grounded


func set_combat(state: String, time: float) -> void:
	if _fitted:
		_fitted_combat(state, time)
		return
	if _player == null:
		return
	var previous := _last_state
	_last_state = state
	_combat_state = state
	_combat_time = time
	if _dead:
		return
	if state == "DEAD":
		die()
		return
	if state == "STAGGER":
		if previous != "STAGGER":
			_attack_playing = false
			_hit_playing = true
			_hit_time = 0.0
			_clip = _stagger_target()
			_hit_duration = _player.get_animation(_clip).length
			_player.speed_scale = 1.0
			_player.play(_clip, 0.06)
		return
	if state in ["WINDUP", "STRIKE", "RECOVER"]:
		if _hit_playing:
			_hit_playing = false
		if not _attack_playing:
			_attack_playing = true
			_clip = str(_attack_entry()["clip"])
			_player.speed_scale = 1.0
			_player.play(_clip, 0.05)
			_snapshot_swing_base()
		return
	if _attack_playing:
		_attack_playing = false
	_select_locomotion()


func die(direction: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	if _fitted:
		_dead = true
		_state = "DEAD"
		_blocking = false
		_crouched = false
		if is_instance_valid(_rig):
			_rig.cancel_draw()
			_rig.abort_melee("right")
			_rig.set_hit_react(0.0)
			_rig.enter_corpse_pose()
			Perf.begin("corpse.limp")
			CorpsePhysics.start_limp(_rig, direction)
			Perf.end()
		return
	if _player == null:
		return
	_dead = true
	_attack_playing = false
	_hit_playing = false
	_death_time = 0.0
	# The authored death pose gives way to the shared ragdoll. Pausing the
	# player first pins the lethal pose the physical bones are built from.
	_death_held = true
	_clip = str(_data["death"])
	_player.pause()
	CorpsePhysics.start_limp(self, direction)


func head_hitbox_center() -> Vector3:
	if _fitted:
		# The skull the rig is actually holding: the fit carries the creature's
		# head rigidly on the neck, so its bone is the hit zone.
		if is_instance_valid(_rig):
			return _rig.head_hitbox_center()
		return global_position + Vector3.UP * drawn_height()
	if _skeleton == null or _head_bone < 0:
		return global_position + Vector3(0.0, 1.0, 0.0)
	var pose := _skeleton.get_bone_global_pose(_head_bone)
	var offset: Vector3 = _data.get("head_offset", Vector3.ZERO)
	return _skeleton.global_transform * (pose.origin + pose.basis * offset)


func head_hit_profile() -> Vector2:
	var authored := Vector2(float(_data.get("head_radius", 0.25)),
		float(_data.get("head_half", 0.12)))
	if _fitted:
		# The zone is measured on the creature's own skull and the body is drawn at
		# the fit scale, so the zone is that measurement times it.
		return authored * fit_scale()
	return authored


## Skinned body the blood field measures: the imported GLB root owns the
## Skeleton3D and the skinned mesh, so stains are placed on the real cloth - and
## on the fitted path the creature's own cloth over the live skeleton.
func blood_anchor() -> Node3D:
	if _fitted:
		var root: Node3D = _rig.skin_root() if is_instance_valid(_rig) else null
		return root if root != null else self
	if is_instance_valid(_instance):
		return _instance
	return self


## World point of the limb that landed the blow, so a claw comes away wet. A
## fitted body holds no blade: the wrist it swings from is the point.
func strike_hand_position() -> Vector3:
	if _fitted:
		if not is_instance_valid(_rig):
			return global_position
		var joints: Dictionary = _rig.get_joint_positions()
		return joints.get("right_wrist", global_position)
	if _skeleton == null:
		return global_position
	var index := _strike_bone if _strike_bone >= 0 else _head_bone
	if index < 0:
		return global_position
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(index).origin


func get_clip_name() -> String:
	if _fitted:
		return _rig.current_clip() if is_instance_valid(_rig) else ""
	return _clip


func is_dead() -> bool:
	return _dead


func _process(delta: float) -> void:
	# A fitted body is posed by its own rig on the drawn frame; the sampler below
	# is the only clock this node owns.
	if _fitted:
		return
	Perf.begin("mob.anim")
	_animate(delta)
	Perf.end()


func _animate(delta: float) -> void:
	if _player == null:
		return
	_hover_time += delta
	if _instance != null:
		var hover := float(_data.get("hover", 0.0))
		if hover > 0.0:
			var target_height := 0.0 if _dead else hover + sin(_hover_time * 2.2) * 0.025
			_instance.position.y = lerpf(_instance.position.y, target_height,
				minf(1.0, delta * 8.0))
	if _dead:
		_advance_death(delta)
		return
	if _attack_playing:
		_seek_attack()
		_apply_swing()
		return
	if _hit_playing:
		_hit_time += delta
		if _hit_time >= _hit_duration:
			_hit_playing = false
			_select_locomotion()
		return
	_select_locomotion()


## The stance the arc is measured from: whatever pose the clip had on the frame
## the windup opened.
func _snapshot_swing_base() -> void:
	_swing_base.clear()
	if _skeleton == null:
		return
	for bone_name in _swing_bones:
		var index := int(_swing_bones[bone_name])
		_swing_base[bone_name] = _skeleton.get_bone_pose_rotation(index)


## How far through the swing the body is: 0 at the start of the windup, 1 at the
## end of the recovery, with the impact on its own share of the strike window.
func _swing_phase() -> Dictionary:
	var windup := maxf(0.01, float(profile.get("windup", 0.45)))
	var strike := maxf(0.01, float(profile.get("strike", 0.18)))
	var recover := maxf(0.01, float(profile.get("recover", 0.55)))
	var impact := windup + strike * SWING_IMPACT_SHARE
	var stagger_end := windup + strike
	var total := windup + strike + recover
	var elapsed := 0.0
	match _combat_state:
		"WINDUP":
			elapsed = minf(_combat_time, windup)
		"STRIKE":
			elapsed = windup + minf(_combat_time, strike)
		"RECOVER":
			elapsed = windup + strike + minf(_combat_time, recover)
		_:
			return {}
	return {"elapsed": elapsed, "windup": windup, "impact": impact,
		"stagger_end": stagger_end, "total": total}


## Where the weapon is on its arc: 0 is the stance the windup opened in, 1 is
## fully cocked, 2 is through the target, and the follow-through overshoots to
## `SWING_OVERSHOOT` before settling home.
func _swing_arc(phase: Dictionary) -> float:
	var elapsed := float(phase["elapsed"])
	var windup := float(phase["windup"])
	var impact := float(phase["impact"])
	var stagger_end := float(phase["stagger_end"])
	var total := float(phase["total"])
	if elapsed <= windup:
		return smoothstep(0.0, 1.0, clampf(elapsed / windup, 0.0, 1.0))
	if elapsed <= impact:
		# The whip is front-loaded: most of the arc is crossed in the first frames
		# of the strike window, so the piece is already coming down on the frame the
		# blow lands - a slow linear whip would still be at the cock when the damage
		# resolved, and the swing would read as happening after the hit.
		var share := clampf((elapsed - windup) / maxf(0.001, impact - windup), 0.0, 1.0)
		return 1.0 + pow(share, 0.45)
	if elapsed <= stagger_end:
		var share := clampf((elapsed - impact) / maxf(0.001, stagger_end - impact), 0.0, 1.0)
		return 2.0 + SWING_OVERSHOOT * share
	var settle := smoothstep(0.0, 1.0,
		clampf((elapsed - stagger_end) / maxf(0.01, total - stagger_end), 0.0, 1.0))
	return (2.0 + SWING_OVERSHOOT) * (1.0 - settle)


## Layer the cock-back, the whip and the follow-through over the clip: a body
## with the swing bones and a named attack arc gets one, the single-swing mobs keep
## their authored clip untouched.
func _apply_swing() -> void:
	if _swing_bones.is_empty() or _skeleton == null:
		return
	var phase := _swing_phase()
	if phase.is_empty():
		return
	var arc := _swing_arc(phase)
	for bone_name in _swing_bones:
		var index := int(_swing_bones[bone_name])
		var cock: Vector3 = SWING_COCK.get(bone_name, Vector3.ZERO)
		var through: Vector3 = SWING_THROUGH.get(bone_name, Vector3.ZERO)
		var angles: Vector3
		if arc <= 1.0:
			angles = cock * arc
		elif arc <= 2.0:
			angles = cock.lerp(through, arc - 1.0)
		else:
			angles = through * (1.0 + (arc - 2.0))
		var base: Quaternion = _swing_base.get(bone_name,
			_skeleton.get_bone_pose_rotation(index))
		# Set, not add: the arc is the arm's whole pose for as long as the swing
		# lasts, so the clip cannot drag the club back up behind the head.
		var extra := Quaternion(Vector3.RIGHT, deg_to_rad(angles.x)) \
			* Quaternion(Vector3.UP, deg_to_rad(angles.y)) \
			* Quaternion(Vector3.BACK, deg_to_rad(angles.z))
		_skeleton.set_bone_pose_rotation(index, base * extra)


func _seek_attack() -> void:
	if profile.is_empty():
		return
	var entry := _attack_entry()
	var impact := float(entry.get("impact", 0.6))
	# The clip's own length is the timeline the strike pose is authored on, so a
	# short lunge and a long sweep each land on their own impact frame.
	var total := maxf(0.05, _player.get_animation(_clip).length)
	var windup := maxf(0.05, float(profile.get("windup", 0.45)))
	var strike := maxf(0.05, float(profile.get("strike", 0.18)))
	var recover := maxf(0.05, float(profile.get("recover", 0.55)))
	var post_impact := maxf(0.05, total - impact)
	var t := impact
	if _combat_state == "WINDUP":
		t = impact * clampf(_combat_time / windup, 0.0, 1.0)
	elif _combat_state == "STRIKE":
		t = impact + clampf(_combat_time / strike, 0.0, 1.0) * 0.10
	elif _combat_state == "RECOVER":
		t = impact + 0.10 + clampf(_combat_time / recover, 0.0, 1.0) * maxf(0.05, post_impact - 0.10)
	_player.seek(clampf(t, 0.0, total), true)


func _select_locomotion() -> void:
	var target := str(_data["idle"])
	var scale := 1.0
	if _blocking:
		# The guard is a stance, not a step: the authored block loop holds while
		# the window is open, and the feet are the body's business.
		target = _block_target()
	elif _speed > MOVE_THRESHOLD:
		var threshold := float(_data.get("run_threshold", 2.0))
		if _speed >= threshold:
			target = str(_data["run"])
			scale = clampf(_speed / maxf(0.1, float(_data["run_speed"])), 0.55, 1.9)
		else:
			target = str(_data["walk"])
			scale = clampf(_speed / maxf(0.1, float(_data["walk_speed"])), 0.55, 1.9)
	elif _crouched:
		# A crouched body standing still rests low: the crouch IS its idle, and it
		# stands up for the swing (the attack states take the clip).
		target = _crouch_target()
	if _clip != target:
		_clip = target
		_player.play(target, 0.18)
	_player.speed_scale = scale


func _advance_death(delta: float) -> void:
	if _death_held:
		return
	_death_time += delta
	var duration := _player.get_animation(str(_data["death"])).length
	if _death_time >= duration:
		_death_held = true
		_player.seek(duration, true)
		_player.pause()
