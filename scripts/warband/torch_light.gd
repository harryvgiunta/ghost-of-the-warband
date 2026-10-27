extends Node3D
## A worn hand torch: the world's own flame cards and a bright light that follow
## whichever body is carrying it.
##
## The item (`torch_hand`) is catalog data and an off-hand slot; this node is what
## turns it into light. It is deliberately poll-based: gear moves through the
## paperdoll, the stash and the loot sweep, and every one of those paths would
## otherwise need to remember to tell the torch. One body, one cheap poll.
##
## Bright on purpose: the trail's own torches are 3.4 energy over 16 m, which is a
## pool to walk through. A torch in the hand has to light the woods the squad is
## standing in, so it carries more than twice that.

const CampKit = preload("res://scripts/world/camp_kit.gd")
const FireFx = preload("res://scripts/world/fire_fx.gd")

const ITEM_ID := "torch_hand"
const LIGHT_ENERGY := 7.5
const LIGHT_RANGE := 26.0
const LIGHT_COLOR := Color(1.0, 0.63, 0.32)
## Where the brand rides: the off hand, just below the shoulder line.
const HAND := Vector3(-0.36, 1.16, -0.14)
const POLL_SECONDS := 0.2

var actor
var merc_id := -1
var warband
var light: OmniLight3D = null
var flame: Node3D = null
var _elapsed := 0.0
var _lit := false


func setup(body, id: int, warband_node) -> void:
	actor = body
	merc_id = id
	warband = warband_node
	name = "HandTorch"
	position = HAND
	_sync()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < POLL_SECONDS:
		return
	_elapsed = 0.0
	_sync()


## True while the body is holding a burning brand in its off hand.
func worn() -> bool:
	if warband == null or merc_id <= 0:
		return false
	var gear: Dictionary = warband.roster.equipped_of(merc_id)
	return str(gear.get("off", "")) == ITEM_ID


func lit() -> bool:
	return _lit


func light_energy() -> float:
	return light.light_energy if light != null else 0.0


func light_range() -> float:
	return light.omni_range if light != null else 0.0


func flame_visible() -> bool:
	return flame != null and flame.visible


func _sync() -> void:
	var want := worn() and actor != null and is_instance_valid(actor)
	if want == _lit:
		return
	_lit = want
	if want:
		_build()
	else:
		_teardown()


## The brand itself - a pitch-soaked stick with the world's flame cards on it -
## built at the origin so the world can hang it off a hand and the icon studio can
## shoot it on its own.
static func build_visual(seed_value: int = 907) -> Node3D:
	var host := Node3D.new()
	host.name = "Flame"
	var batch := CampKit.Merged.new()
	var mats: Dictionary = CampKit.materials()
	CampKit.add_beam(batch, Vector3(0.0, -0.46, 0.0), Vector3(0.02, 0.06, 0.01), 0.032,
		mats["drift_dark"], 5, 0.028)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	FireFx.flame_cards(batch, mats["flame"], rng, 0.24, 0.06)
	batch.commit(host, "TorchCards", false)
	return host


func _build() -> void:
	if light == null:
		light = OmniLight3D.new()
		light.name = "TorchLight"
		light.position = Vector3(0.0, 0.08, 0.0)
		light.light_color = LIGHT_COLOR
		light.light_energy = LIGHT_ENERGY
		light.omni_range = LIGHT_RANGE
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		add_child(light)
	if flame == null:
		flame = build_visual(907 + merc_id * 13)
		add_child(flame)
	light.visible = true
	flame.visible = true


func _teardown() -> void:
	if light != null:
		light.visible = false
	if flame != null:
		flame.visible = false
