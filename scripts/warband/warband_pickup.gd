class_name WarbandPickup
extends Node3D
## One piece of battlefield loot, lying in the world where it fell.
##
## Loot is a physical thing the warband walks up to, not an entry appended to a
## list: the player's quick-loot and the end-of-battle sweep both act on this
## node, and the node leaving the tree is what proves the piece moved. Nothing
## is stored here that the shared stash does not already own, so there is never a
## second, mode-local inventory to reconcile.
##
## A drop is a thing on the ground: a blade lies on its side, a shield lies flat,
## a bundle lies folded, and a name plate stands over it. Nothing here bobs,
## floats or turns - a piece of steel spinning on its point in the dirt was never
## what an enemy dropped, and it is the only thing a player ever had to aim at
## twice.
##
## `armed` is the re-collect interlock. A mercenary who lets go of a piece
## disarms the drop against themselves for `ARM_DELAY` seconds (`disarm`, then
## `WarbandLoot` re-arms it), so the same body cannot scoop it straight back up;
## every other collector may take it that instant.

## Emitted once, right before the node leaves the world, so a battle log can
## record the pick without holding a reference to a freed node.
signal taken(pickup: WarbandPickup)

const State = preload("res://scripts/player_state.gd")

## Seconds a disarmed drop stays locked to the mercenary that dropped it.
const ARM_DELAY := 0.75
## How high the name plate floats over a piece lying on the floor.
const LABEL_HEIGHT := 0.42
const LABEL_SIZE := 42
## A warm iron-gold so a drop reads as loot on dark ground.
const LOOT_ALBEDO := Color(0.78, 0.66, 0.36)
## Steel, haft and cloth, so a drop reads as the thing it is even at a glance.
const STEEL_ALBEDO := Color(0.66, 0.71, 0.73)
const HAFT_ALBEDO := Color(0.34, 0.23, 0.15)
const CLOTH_ALBEDO := Color(0.46, 0.40, 0.31)

## The catalog id this drop is worth; '' for an unbound drop.
var item_id := ""
## True when the drop is open to everyone. A disarmed drop is locked against
## `dropper_peer` alone.
var armed := true
## The peer that let the piece go; 0 for spoils nobody owns.
var dropper_peer := 0
## True once the piece has left the world, so a second collect cannot pay twice.
var collected := false

var _label: Label3D = null
var _arm_timer: Timer = null

## Bind the catalog id and put the visible drop in place. Safe to call again:
## a second call only re-dresses the label, so a reused pickup does not build a
## second heap of geometry.
func setup(id: String, label: String = "") -> void:
	item_id = id
	if _label == null:
		_build()
	_set_label(label if not label.is_empty() else item_name(id))

## The catalog name, falling back to the raw id for a drop whose id is unknown.
static func item_name(id: String) -> String:
	var item: Dictionary = State.ITEMS.get(id, {})
	return str(item.get("name", id))

## The catalogue's own word for what this piece is, so a drop can be drawn as a
## blade, a bow, a shield or a bundle instead of one anonymous block.
static func item_category(id: String) -> String:
	var item: Dictionary = State.ITEMS.get(id, {})
	var category := str(item.get("category", ""))
	if not category.is_empty():
		return category
	if id.begins_with("shield_"):
		return "shield"
	if id.begins_with("staff_"):
		return "staff"
	if id.begins_with("focus_") or id.begins_with("torch_"):
		return "focus"
	if id.begins_with("ring_") or id.begins_with("neck_"):
		return "jewelry"
	if id.begins_with("armor_"):
		return "armor_bundle"
	if id.begins_with("bow_"):
		return "bow"
	if id.begins_with("sword_") or id.begins_with("club_") or id.begins_with("branch_"):
		return "1h"
	if id.begins_with("dagger_"):
		return "1h"
	return "misc"

## A blade, a haft or a bundle: what a squad wants in its hands beats what it
## would only carry. The squad's own arming rule reads this, never a hard list.
static func is_weapon(id: String) -> bool:
	return item_category(id) in ["1h", "2h", "bow", "staff"]

func label_text() -> String:
	return "" if _label == null else _label.text

## Whether this drop is locked against `peer_id`. Only the dropper of a disarmed
## drop is ever refused; a second collector may always take it.
func blocked_for(peer_id: int) -> bool:
	return not armed and dropper_peer != 0 and peer_id == dropper_peer

func arm() -> void:
	armed = true
	if _arm_timer != null:
		_arm_timer.stop()

## Lock the drop against the mercenary that just let go of it. The lock is timed,
## so a dropper can take the piece back once they have walked away from it.
func disarm(peer_id: int) -> void:
	armed = false
	dropper_peer = peer_id
	if is_inside_tree():
		_start_arm_timer()

## A drop disarmed before it entered the tree (the normal spawn order) starts its
## lock the moment it lands in the world.
func _ready() -> void:
	if not armed and not collected:
		_start_arm_timer()

## Take the piece out of the world. Idempotent, so two loot paths racing for the
## same drop can never pay the warband twice.
func collect() -> void:
	if collected:
		return
	collected = true
	if _arm_timer != null:
		_arm_timer.stop()
	taken.emit(self)
	var host := get_parent()
	if host != null:
		host.remove_child(self)
	queue_free()

## The lock timer lives on the pickup so it dies with the drop; a coroutine
## awaiting a scene timer would outlive the node it belongs to.
func _start_arm_timer() -> void:
	if _arm_timer == null:
		_arm_timer = Timer.new()
		_arm_timer.one_shot = true
		_arm_timer.wait_time = ARM_DELAY
		_arm_timer.timeout.connect(arm)
		add_child(_arm_timer)
	_arm_timer.start()

## One piece of steel on the dirt. Every part is placed at its own height above
## the floor, so the drop's own origin is the ground it fell on: a scene hands in
## the point the body stood on and nothing else has to know how tall a sword is.
func _build() -> void:
	var category := item_category(item_id)
	match category:
		"1h", "2h":
			_build_blade(category == "2h")
		"bow":
			_build_bow()
		"staff":
			_build_pole()
		"shield":
			_build_shield()
		"focus":
			_build_bundle(0.20, 0.06, 0.26)
		"jewelry":
			_build_ring()
		"armor", "armor_bundle":
			_build_bundle(0.32, 0.11, 0.26)
		_:
			_build_bundle(0.22, 0.09, 0.22)
	# The angle is the piece's own, taken off its id: twenty drops of one blade
	# do not all lie pointing at the same tree, and it never changes, because a
	# drop that turns is a drop that is floating.
	rotation.y = float(absi(item_id.hash()) % 360) * 0.017453292
	# The label is the only way a drop names itself in a pile, so it always
	# billboards toward the camera and keeps a dark outline for readability.
	_label = Label3D.new()
	_label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = LABEL_SIZE
	_label.outline_size = 8
	_label.modulate = LOOT_ALBEDO
	add_child(_label)

## A blade lying on its side: point along +X, grip at the -X end, a hand's width
## off the ground on its own guard.
func _build_blade(two_handed: bool) -> void:
	var length := 0.78 if two_handed else 0.50
	var half_width := 0.026 if two_handed else 0.018
	var centre_x := length * 0.5 - 0.16
	_box(Vector3(length, 0.012, half_width * 2.0),
		Vector3(centre_x, 0.012, 0.0), STEEL_ALBEDO, 0.75)
	# The cross-section of a laid blade is its width across the dirt, so the
	# guard lies flat and reads as the widest point of the piece.
	_box(Vector3(0.028, 0.012 if not two_handed else 0.020, 0.15 if two_handed else 0.11),
		Vector3(centre_x - length * 0.5 + 0.01, 0.016, 0.0), LOOT_ALBEDO, 0.65)
	_cylinder(0.021, 0.20 if two_handed else 0.15,
		Vector3(centre_x - length * 0.5 - 0.09 - (0.04 if two_handed else 0.0), 0.021, 0.0),
		HAFT_ALBEDO, 0.05)

## A bow lies curved: the belly is off the ground, the tips rest on it. Three
## short segments are enough at the distance a drop is read from.
func _build_bow() -> void:
	_box(Vector3(0.34, 0.016, 0.026), Vector3(0.0, 0.026, 0.0), HAFT_ALBEDO, 0.05)
	for side in [-1.0, 1.0]:
		var tip := MeshInstance3D.new()
		var limb := BoxMesh.new()
		limb.size = Vector3(0.30, 0.016, 0.022)
		tip.mesh = limb
		tip.material_override = _material(HAFT_ALBEDO, 0.05)
		tip.position = Vector3(side * 0.30, 0.020, 0.0)
		tip.rotation.z = side * 0.16
		add_child(tip)
	_box(Vector3(0.62, 0.004, 0.004), Vector3(0.0, 0.008, -0.012), CLOTH_ALBEDO, 0.0)

## A stave on the dirt, its own length along +X.
func _build_pole() -> void:
	_cylinder(0.020, 1.04, Vector3(0.0, 0.020, 0.0), HAFT_ALBEDO, 0.05, true)

## A shield face down on the ground: no boss, no rim standing up, nothing to
## look like a plate on a stand.
func _build_shield() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = 0.30
	disc.bottom_radius = 0.30
	disc.height = 0.045
	disc.radial_segments = 24
	disc.rings = 1
	var face := MeshInstance3D.new()
	face.mesh = disc
	face.material_override = _material(LOOT_ALBEDO, 0.55)
	face.position = Vector3(0.0, 0.023, 0.0)
	add_child(face)

## Cloth, leather and a scrap of lashing folded on the ground.
func _build_bundle(w: float, h: float, d: float) -> void:
	_box(Vector3(w, h, d), Vector3(0.0, h * 0.5, 0.0), CLOTH_ALBEDO, 0.0)
	_box(Vector3(w * 0.45, h * 0.45, d * 0.7),
		Vector3(w * 0.16, h * 1.14, 0.02), LOOT_ALBEDO, 0.3, 0.22)

## A ring or a bead: one small loop on the dirt.
func _build_ring() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.045
	ring.outer_radius = 0.072
	ring.rings = 18
	ring.ring_segments = 8
	var band := MeshInstance3D.new()
	band.mesh = ring
	band.material_override = _material(LOOT_ALBEDO, 0.9)
	# Laid flat: the loop's own axis points at the sky, so it reads as a ring
	# lying on the ground and not as one stood up on its edge.
	band.rotation.x = PI * 0.5
	band.position = Vector3(0.0, 0.016, 0.0)
	add_child(band)

func _box(size: Vector3, at: Vector3, color: Color, metallic: float,
		yaw: float = 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	var part := MeshInstance3D.new()
	part.mesh = box
	part.material_override = _material(color, metallic)
	part.position = at
	part.rotation.y = yaw
	add_child(part)

## A shaft laid along +X (a blade's grip, a stave) or standing in its own axis.
func _cylinder(radius: float, length: float, at: Vector3, color: Color,
		metallic: float, along_x: bool = true) -> void:
	var shaft := CylinderMesh.new()
	shaft.top_radius = radius
	shaft.bottom_radius = radius
	shaft.height = length
	shaft.radial_segments = 8
	var part := MeshInstance3D.new()
	part.mesh = shaft
	part.material_override = _material(color, metallic)
	part.position = at
	if along_x:
		part.rotation.z = PI * 0.5
	add_child(part)

func _material(color: Color, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.52
	# A little of the piece's own colour, so a drop in deep shade still reads as
	# loot under the lamps without glowing like a spell effect.
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.12
	return material

func _set_label(text: String) -> void:
	if _label != null:
		_label.text = text
