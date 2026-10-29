class_name TownFolk
extends RefCounted
## The town's keepers: five standing, armoured bodies, one behind each counter.
##
## They are the same `Archer` rig the warband fields, dressed out of the same
## catalog tables, and that is the whole point: a settlement where the only
## people are labels over boards reads as a menu, not a market. What they are
## *not* is bodies. No `ArenaActor`, no capsule, no `Combat`, nothing the
## possession controller can hand a soul to and nothing that can be hit - a
## keeper is furniture with a face, and the counter in front of them is still
## the service. That is why every figure here is one `Node3D` the scene can
## point an arrow at and no peer can take over.
##
## The face is `WarbandLooks.profile_for()` on an id of the keeper's own, folded
## out of the name: the band's looks are a pure function of an id, so a keeper
## needs an id that never collides with one of the eight (that is what
## `PROFILE_BASE` is for) and never changes between launches (that is why the
## fold is written out instead of calling `hash()`).

const Archer = preload("res://scripts/archer.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const WarbandLooks = preload("res://scripts/warband/warband_looks.gd")

## How far behind their own counter a keeper stands. The counter is 0.9 m deep
## and the service ring reaches 3 m, so a stride puts the body on the far side of
## the boards without eating either.
const BEHIND := 1.1
## Look ids start here: past the deployment cap, so a keeper never borrows a
## mercenary's face however many bodies the band hires.
const PROFILE_BASE := 101
## The name over the head, in metres. Scaled by the look's own height, so a tall
## keeper's name clears his hair.
const NAMEPLATE_HEIGHT := 2.30
const NAMEPLATE_COLOR := Color(0.96, 0.88, 0.68)

## One row per keeper: the service `interact_at` resolves, the word over the head
## and the kit they wear. The armament is the counter's own trade - Orla's bows,
## Brann's blades, Vey's plate - so the market can be read from across the fire
## without a sign. A shield is an off hand, not a weapon: Vey and the
## quartermaster carry the board they sell and no blade.
const KEEPERS := [
	{"service": "vendor_orla", "name": "ORLA", "main": "bow_short", "off": "",
		"armor": "leather"},
	{"service": "vendor_brann", "name": "BRANN", "main": "sword_short", "off": "dagger_iron",
		"armor": "mail"},
	{"service": "vendor_vey", "name": "VEY", "main": "", "off": "shield_buckler",
		"armor": "plate"},
	{"service": "recruiter", "name": "RECRUITER", "main": "sword_short", "off": "",
		"armor": "mail"},
	{"service": "quartermaster", "name": "QUARTERMASTER", "main": "", "off": "shield_buckler",
		"armor": "mail"},
]


## One standing keeper. The scene keeps these by service id (the arrow is pointed
## at whichever of them has business) and the regression reads them back: the rig
## is present, the kit is worn and there is nothing on the node that a controller
## or a fight could take hold of.
class Keeper extends Node3D:
	var service := ""
	var keeper_name := ""
	var rig = null
	var plate: Label3D = null


## Build every keeper the town's counters have a row for. `counters` maps a
## service id to the counter node the scene placed, and the body goes behind it,
## facing the fire. Returns `service -> Keeper`.
static func build(scene: Node3D, counters: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for row in KEEPERS:
		var service := str(row["service"])
		var counter: Node3D = counters.get(service, null) as Node3D
		if counter == null:
			continue
		var keeper := Keeper.new()
		keeper.name = "Keeper%s" % str(row["name"]).capitalize()
		keeper.service = service
		keeper.keeper_name = str(row["name"])
		var at := _behind(counter.position)
		keeper.position = at
		# The rig's forward is -Z, so this turns the face toward the fire.
		keeper.rotation.y = atan2(at.x, at.z)
		scene.add_child(keeper)
		var profile := WarbandLooks.profile_for(look_seed(keeper.keeper_name))
		keeper.rig = _dress(keeper, profile, row)
		keeper.plate = _nameplate(keeper, keeper.keeper_name, profile)
		out[service] = keeper
	return out


## Where a keeper stands from their counter: a stride further out from the
## square, so the player is always on the outside of the boards.
static func _behind(counter_at: Vector3) -> Vector3:
	var outward := Vector3(counter_at.x, 0.0, counter_at.z)
	if outward.length_squared() < 0.0001:
		return counter_at + Vector3(0.0, 0.0, -BEHIND)
	return counter_at + outward.normalized() * BEHIND


## The body, dressed from one armor set and the kit the counter trades in. The
## two-handed rule is the guard's own (`cultist_guard.gd`): an off hand that the
## main hand forbids is dropped rather than worn illegally.
static func _dress(keeper: Keeper, profile: Dictionary, row: Dictionary) -> Node:
	var rig = Archer.new()
	rig.name = "KeeperBody"
	# The look has to be on the rig before it enters the tree: the height it
	# carries is baked in when the skeleton is measured.
	rig.appearance = profile
	keeper.add_child(rig)
	var set_index := ArmorData.SET_IDS.find(str(row["armor"]))
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = set_index if set_index >= 0 else ArmorData.NONE
	var main_id := str(row["main"])
	var off_id := str(row["off"])
	if off_id.is_empty() or Contracts.two_handed_item(State.ITEMS.get(main_id, {})):
		off_id = ""
	rig.apply_loadout(State.build_loadout(main_id, off_id, pieces))
	return rig


## The word over the keeper's head. `no_depth_test` because a name behind a
## counter, a stall awning and a lit hall would otherwise vanish exactly when a
## player is standing at the counter looking for it.
static func _nameplate(keeper: Keeper, text: String, profile: Dictionary) -> Label3D:
	var plate := Label3D.new()
	plate.name = "Nameplate"
	plate.text = text
	plate.font_size = 44
	plate.pixel_size = 0.0046
	plate.modulate = NAMEPLATE_COLOR
	plate.outline_size = 10
	plate.outline_modulate = Color(0.06, 0.04, 0.02, 0.9)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.render_priority = 1
	plate.position = Vector3(0.0, NAMEPLATE_HEIGHT * float(profile.get("height", 1.0)), 0.0)
	keeper.add_child(plate)
	return plate


## A keeper's look id: a fold of the name into a range the band's ids never
## reach. Stable across launches, different for every keeper.
static func look_seed(name: String) -> int:
	var fold := 7
	for index in name.length():
		fold = (fold * 131 + name.unicode_at(index)) & 0xFFFF
	return PROFILE_BASE + fold % 997
