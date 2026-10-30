extends Node3D
## Humanoid presentation for the camp's watchers.
##
## A watcher is one of the wood's three creatures - the Hollow warden, the
## Ossuary stalker or the Gallowsroot - standing on the warband's own rig: the
## ranger's 65 bones, its authored walk, run, swing, guard, flinch and fall, and
## a body skin made from the creature's own mesh (`tools/prepare_watcher_skins.py`
## fits that mesh onto this skeleton, so the skin *is* the creature and the
## clips are a human's). That is the whole point of this node: the wood's mobs
## used to play six creature clips and read as stop-motion in a fight, and now
## they trade blows with the same shoulders, hips and feet the warband does.
##
## The mob still owns the fight - `DevilMob` decides when a body notices, winds
## up, strikes, guards, staggers and dies - and this node answers the same API
## the creature sampler did, so no scene had to change:
##
##   * `set_motion` drives the legs (the rig's own locomotion cycle);
##   * `set_combat` opens the swing the state machine just committed to, and the
##     swing's length is stretched onto the mob's own telegraph so the blade is
##     crossing the target on the frame its damage resolves (`retime_melee`);
##   * `set_poise` raises the authored guard loop and folds the body into the
##     crouch a crouch-armed variant rests in;
##   * `die` hands the skeleton to the shared ragdoll, exactly as a ranger's
##     corpse does.
##
## Nothing here decides damage, sight, reach or reward. It decides how a body
## that has already decided looks while it does it.

const Archer = preload("res://scripts/archer.gd")
const CorpsePhysics = preload("res://scripts/corpse_physics.gd")
const Catalog = preload("res://scripts/player_state.gd")
const MobLod = preload("res://scripts/mob_lod.gd")

## The three watcher species, by the mob id a scene sets: the skin the fit tool
## exported, the creature GLB whose PBR atlases it borrows (the skin ships no
## images of its own), and the measured fit scale - the creature's neck height
## over the ranger's, which is both how the skin was authored and how tall the
## body stands at runtime. `tests/watcher_variants_regression.gd` compares the
## three numbers against the exported metadata.
const SPECIES := {
	"hollow_warden": {
		"skin": "res://assets/characters/watchers/ironwood_watcher_hollow_warden.glb",
		"materials": "res://assets/characters/forest/ironwood_hollow_warden.glb",
		"node": "Watcher_HollowWarden",
		"fit": 1.1312,
		"display": "Hollow warden",
	},
	"ossuary_stalker": {
		"skin": "res://assets/characters/watchers/ironwood_watcher_ossuary_stalker.glb",
		"materials": "res://assets/characters/forest/ironwood_ossuary_stalker.glb",
		"node": "Watcher_OssuaryStalker",
		"fit": 1.0260,
		"display": "Ossuary stalker",
	},
	"gallowsroot": {
		"skin": "res://assets/characters/watchers/ironwood_watcher_gallowsroot.glb",
		"materials": "res://assets/characters/forest/ironwood_gallowsroot.glb",
		"node": "Watcher_Gallowsroot",
		"fit": 1.1444,
		"display": "Gallowsroot",
	},
}
## A watcher is a warden whatever an older scene sets.
const WARDEN_ID := "hollow_warden"

## The swing vocabulary the camp speaks, mapped onto the rig's authored cuts. The
## overhead is the plain two-handed chop, the slash is the diagonal cut (the same
## authored heavy clip, driven by the diagonal arm path) and the stab is the
## dagger lunge - the three ways a body in this game actually swings.
const SWINGS := {"overhead": "overhead", "slash": "diagonal_right", "stab": "stab"}

## Where the Archer's swing opens its strike window (see `Archer._melee_window`:
## `windup = (duration - cut) * 0.55`), and how far into the mob's strike state
## its damage resolves (`DevilMob` at `strike * 0.34`). The swing is stretched so
## those two land together: the blade is crossing the target on the damage frame.
const BLADE_IMPACT_SHARE := 0.55
const STRIKE_DAMAGE_SHARE := 0.34

## The rig's flinch is a pose, not a clip: `Archer._apply_hit_react_pose` runs for
## this long and eases out over 0.42 s.
const FLINCH_SECONDS := 0.34

## How far into the rig's crouch a crouch-armed watcher folds. The authored
## pose is a full squat meant for a body taking cover behind a wall; a watcher
## stalking a caged prisoner wants a hunch that keeps its height, so a partial
## crouch is the stance and the line under it is "watching", not "hiding".
const CROUCH_AMOUNT := 0.62

## Where a body is aimed at: the chest of the authored rig, in metres, times the
## rendered height. Every skin is fitted onto that same rig, so one fraction is
## honest for a stalker and a warden alike.
const CHEST_HEIGHT := 1.50
const FRONT_RANGE := 5.0

var mob_id := WARDEN_ID
var profile: Dictionary = {}
## The rig wearing the skin.
var rig
## The silhouette multiplier this variant was built to, before the species' own
## fit scale.
var silhouette := 1.0

var _species := WARDEN_ID
var _attack := ""
var _state := ""
var _state_time := 0.0
var _speed := 0.0
var _grounded := true
var _dead := false
var _blocking := false
var _crouched := false
var _tint := Color.WHITE
var _paint: Array[StandardMaterial3D] = []
var _base: Array[Color] = []
var _held_item := ""
var _band := -1
var _parked := false

## One harvested set of creature materials per species, per process: the skin
## ships no images, so the atlases come from the creature's own GLB and are
## copied (and tinted) per body.
static var _sources: Dictionary = {}


func _ready() -> void:
	name = "WatcherVisual"
	_species = str(mob_id) if SPECIES.has(str(mob_id)) else WARDEN_ID
	var spec: Dictionary = SPECIES[_species]
	rig = Archer.new()
	rig.name = "WatcherRig"
	# One facing, one quarry: the mob turns this body itself, and the walk cycle
	# may pose the legs but must not snap it onto its velocity while it circles.
	rig.heading_locked = true
	# One piece, built when it is handed over: a watchman carries the club it was
	# given and nothing else, and thirteen weapons per body is ten thousand nodes
	# in a wood that already holds sixty of them.
	rig.sparse_props = true
	rig.body_skin = {"path": str(spec["skin"]), "node": str(spec["node"]),
		"height": _fit() * silhouette}
	add_child(rig)
	_dress_surfaces()


## The species this body is, and the creature it is wearing.
func species() -> String:
	return _species


func species_display() -> String:
	return str((SPECIES[_species] as Dictionary).get("display", _species))


## The measured fit scale of the skin this body wears.
func fit_scale() -> float:
	return _fit()


# --- the mob surface --------------------------------------------------------

## The legs and the gait. Called on every mob tick; the rig's own physics clock
## advances the authored cycle between them.
func set_motion(velocity: Vector3, grounded: bool) -> void:
	_speed = Vector2(velocity.x, velocity.z).length()
	_grounded = grounded
	if not is_instance_valid(rig):
		return
	rig.aim_at(_forward_point())
	rig.set_locomotion(velocity, grounded)


## What the state machine just committed to: a windup opens a swing, a stagger
## breaks one, and the rest is the rig's own clock finishing the arc.
func set_combat(state: String, time: float) -> void:
	var previous := _state
	_state = state
	_state_time = time
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


## A held guard and the crouched rest. Both are stances the rig authors; the
## controller only says which one the body is in.
func set_poise(blocking: bool, crouched: bool) -> void:
	if blocking == _blocking and crouched == _crouched:
		return
	_blocking = blocking
	_crouched = crouched
	if not is_instance_valid(rig):
		return
	rig.set_blocking(blocking, -global_basis.z)
	rig.set_cover(false, Vector3.ZERO, CROUCH_AMOUNT if crouched and not blocking else 0.0,
		false, Vector3.ZERO)


## The body is down: stop the authored clock and hand the skeleton to the shared
## ragdoll, the way every ranger corpse in the game falls.
func die(direction: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	_dead = true
	_state = "DEAD"
	_blocking = false
	_crouched = false
	if not is_instance_valid(rig):
		return
	rig.cancel_draw()
	rig.abort_melee("right")
	rig.set_hit_react(0.0)
	rig.enter_corpse_pose()
	CorpsePhysics.start_limp(rig, direction)


func is_dead() -> bool:
	return _dead


func get_clip_name() -> String:
	return rig.current_clip() if is_instance_valid(rig) else ""


## Range budget, on the same bands every body in the wood uses: the rig is the
## heaviest thing in the world, so past `MobLod.ANIMATE_DISTANCE` it stops
## evaluating tracks and past `SHADOW_DISTANCE` it stops casting.
func set_distance(distance: float) -> void:
	var band := MobLod.band(distance)
	if band == _band:
		return
	_band = band
	_apply_clock()


## Parked by the culler: the body is hidden and parked, so the rig must stop
## posing too - an invisible rig that keeps sampling tracks is the same cost as
## a visible one.
func set_parked(parked: bool) -> void:
	if parked == _parked:
		return
	_parked = parked
	_apply_clock()


func _apply_clock() -> void:
	if not is_instance_valid(rig) or _dead:
		return
	rig.set_physics_process(not _parked and _band < 2)
	rig.set_shadow_casting(not _parked and _band <= 0)


# --- the fight --------------------------------------------------------------

## Open the swing the windup just chose: the bow draws, everything else cuts.
func _open_swing() -> void:
	if not is_instance_valid(rig):
		return
	if rig.weapon == "bow":
		rig.begin_draw()
		return
	if rig.begin_melee("right", str(SWINGS.get(_attack, "overhead"))):
		rig.retime_melee("right", _swing_seconds())


## How long the authored swing must run for its strike window to open on the
## mob's damage frame.
func _swing_seconds() -> float:
	var windup := maxf(0.05, float(profile.get("windup", 0.55)))
	var strike := maxf(0.05, float(profile.get("strike", 0.20)))
	return (windup + strike * STRIKE_DAMAGE_SHARE) / BLADE_IMPACT_SHARE


## A real blow breaks the swing, the draw and the guard: the body takes the
## recoil instead of finishing the cut.
func _flinch() -> void:
	if not is_instance_valid(rig):
		return
	rig.cancel_draw()
	rig.abort_melee("right")
	rig.set_hit_react(FLINCH_SECONDS)


## Loosed the visual string. The arrow itself belongs to the mob that fired it,
## so this only plays the release.
func release_bow() -> void:
	if is_instance_valid(rig) and rig.weapon == "bow":
		rig.release_string()


## Where a shaft leaves the body: the real bow when one is in hand, else chest
## height a hand's width ahead of the body.
func bow_origin() -> Vector3:
	if is_instance_valid(rig) and rig.weapon == "bow" and is_instance_valid(rig.active_bow):
		return rig.get_arrow_origin()
	return global_position + Vector3.UP * (CHEST_HEIGHT * 0.86 * _height()) - global_basis.z * 0.45


# --- the piece in the hand --------------------------------------------------

## Arm this body with a catalog piece: the rig holds the real model the warband
## holds - the club, the shiv, the branch, the twig bow - through its own weapon
## slots, so the piece is gripped by the hand bones and follows every clip.
func set_held_weapon(item_id: String) -> void:
	if item_id == _held_item:
		return
	_held_item = item_id
	_dress_weapon()


## The catalog id the rig is actually holding, or "" when the hand is empty.
func held_item() -> String:
	if _held_item.is_empty() or not is_instance_valid(rig):
		return ""
	var item: Dictionary = Catalog.ITEMS.get(_held_item, {})
	match str(item.get("kind", "")):
		"bow":
			return _held_item if rig.weapon == "bow" else ""
		"dagger":
			return _held_item if rig.weapon == "dagger" else ""
		"sword":
			return _held_item if rig.weapon == "sword" else ""
	return ""


func _dress_weapon() -> void:
	if not is_instance_valid(rig):
		return
	var item: Dictionary = Catalog.ITEMS.get(_held_item, {})
	var kind := str(item.get("kind", ""))
	var index := int(item.get("index", 0))
	# A watcher carries one piece and nothing in the other hand: no focus, no
	# off-hand blade, no shield.
	rig.set_staff(0, false)
	rig.set_off_focus("", 0, false)
	rig.set_off_weapon("", 0, false)
	rig.set_shield(false)
	match kind:
		"sword":
			rig.set_sword(index)
			rig.set_weapon("sword")
		"dagger":
			rig.set_dagger_index(index)
			rig.set_weapon("dagger")
		"bow":
			rig.set_bow(index)
			rig.set_weapon("bow")
		_:
			rig.set_weapon("none")


# --- the variant's own dial -------------------------------------------------

## The body's build: the creature's fit scale times the variant's silhouette.
func set_silhouette(scale: float) -> void:
	silhouette = clampf(scale, 0.50, 2.00)
	if is_instance_valid(rig):
		rig.set_body_height(_fit() * silhouette)


## The paint: every surface of the skin is the body's own copy, so tinting one
## warden cannot repaint the one beside it.
func set_tint(tint: Color) -> void:
	_tint = tint
	for index in _paint.size():
		_paint[index].albedo_color = _base[index] * tint


func tint() -> Color:
	return _tint


## The height the body is actually drawn at, relative to the authored ranger rig.
func body_scale() -> float:
	return rig.body_scale() if is_instance_valid(rig) else _fit() * silhouette


# --- the authored vocabulary ------------------------------------------------

## The swings this body can be told to play.
func attack_names() -> Array[String]:
	var out: Array[String] = []
	for name in SWINGS.keys():
		out.append(str(name))
	out.sort()
	return out


## The rig clip one of those swings plays, for whoever promises a scene it will
## be shown (and for the regression that asks the asset whether it exists).
func attack_clip(name: String) -> String:
	return _clip_for(str(SWINGS.get(name, "")))


func _clip_for(variant: String) -> String:
	if not is_instance_valid(rig):
		return ""
	if variant in ["diagonal_left", "diagonal_right"]:
		# `Archer._melee_clip_for`: a diagonal reuses the authored heavy clip.
		return "Sword_Overhead"
	if variant == "stab" or rig.weapon == "dagger":
		return "Dagger_Stab"
	return "Sword_Overhead" if rig.sword_index == 2 else "Sword_Overhead_OneHand"


func block_clip() -> String:
	if is_instance_valid(rig) and rig.weapon == "sword" and rig.sword_index == 2:
		return "Sword_Block_Loop"
	return "Sword_Block_Loop_OneHand"


## The recoil is a pose on this rig, not a clip: an empty name is honest.
func stagger_clip() -> String:
	return ""


func crouch_clip() -> String:
	return "Crouch_Idle_Loop"


func current_attack() -> String:
	return _attack


func set_attack(name: String) -> void:
	_attack = name


func has_clip(clip: String) -> bool:
	return is_instance_valid(rig) and rig.has_clip(clip)


# --- hit zones and blood ----------------------------------------------------

func head_hitbox_center() -> Vector3:
	if is_instance_valid(rig):
		return rig.head_hitbox_center()
	return global_position + Vector3.UP * _height()


func head_hit_profile() -> Vector2:
	if is_instance_valid(rig):
		return rig.head_hit_profile()
	return Vector2(0.34, 0.14) * _height()


## The skinned monster the blood field measures: the creature's own cloth over
## the live skeleton, so a stain lands on the coat a blade went through.
func blood_anchor() -> Node3D:
	var root: Node3D = rig.skin_root() if is_instance_valid(rig) else null
	return root if root != null else self


## Where the blow came from: the right hand on the belt to the piece's haft.
func strike_hand_position() -> Vector3:
	if not is_instance_valid(rig):
		return global_position
	return rig.get_blade_tip("right")


# --- dressing ---------------------------------------------------------------

func _fit() -> float:
	return float((SPECIES[_species] as Dictionary).get("fit", 1.0))


func _height() -> float:
	return rig.body_scale() if is_instance_valid(rig) else _fit() * silhouette


## A point in front of the body at chest height: what the rig's own aim solve
## turns the chest onto while it cuts, so a watcher holds its quarry instead of
## its walk direction.
func _forward_point() -> Vector3:
	var forward := -global_basis.z
	return global_position + forward * FRONT_RANGE + Vector3.UP * (CHEST_HEIGHT * _height())


## Give every surface of the skin the creature's own material, copied so the
## tint is this body's.
func _dress_surfaces() -> void:
	var sources := _source_materials(_species)
	_paint.clear()
	_base.clear()
	if not is_instance_valid(rig):
		return
	for mesh in rig.skin_meshes():
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			if surface >= sources.size():
				continue
			var source := sources[surface] as StandardMaterial3D
			if source == null:
				continue
			var tuned := source.duplicate() as StandardMaterial3D
			if tuned == null:
				continue
			tuned.emission_energy_multiplier = 1.35
			tuned.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			mesh.set_surface_override_material(surface, tuned)
			_paint.append(tuned)
			_base.append(tuned.albedo_color)


## One harvested material list per species: the skin's slots are the creature
## mesh's slots, in the same order, because the skin *is* that mesh.
static func _source_materials(species_id: String) -> Array:
	if _sources.has(species_id):
		return _sources[species_id]
	var out: Array = []
	var path := str((SPECIES[species_id] as Dictionary).get("materials", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed != null:
			var instance := packed.instantiate() as Node3D
			var found := instance.find_children("*", "MeshInstance3D", true, false)
			var mesh_node := found[0] as MeshInstance3D if not found.is_empty() else null
			if mesh_node != null and mesh_node.mesh != null:
				for surface in mesh_node.mesh.get_surface_count():
					out.append(mesh_node.get_active_material(surface))
			instance.free()
	_sources[species_id] = out
	return out
