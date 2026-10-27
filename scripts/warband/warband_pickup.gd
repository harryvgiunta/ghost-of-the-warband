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
const MESH_SIZE := Vector3(0.34, 0.24, 0.26)
const MESH_HEIGHT := 0.14
const LABEL_HEIGHT := 0.62
const LABEL_SIZE := 42
## A warm iron-gold so a drop reads as loot on dark ground.
const LOOT_ALBEDO := Color(0.78, 0.66, 0.36)

## The catalog id this drop is worth; '' for an unbound drop.
var item_id := ""
## True when the drop is open to everyone. A disarmed drop is locked against
## `dropper_peer` alone.
var armed := true
## The peer that let the piece go; 0 for spoils nobody owns.
var dropper_peer := 0
## True once the piece has left the world, so a second collect cannot pay twice.
var collected := false

var _visual: MeshInstance3D = null
var _label: Label3D = null
var _arm_timer: Timer = null

## Bind the catalog id and put the visible drop in place. Safe to call again:
## a second call only re-dresses the label so a reused pickup does not build a
## second mesh.
func setup(id: String, label: String = "") -> void:
	item_id = id
	if _visual == null:
		_build()
	_set_label(label if not label.is_empty() else item_name(id))

## The catalog name, falling back to the raw id for a drop whose id is unknown.
static func item_name(id: String) -> String:
	var item: Dictionary = State.ITEMS.get(id, {})
	return str(item.get("name", id))

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

func _build() -> void:
	_visual = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = MESH_SIZE
	_visual.mesh = box
	_visual.position = Vector3(0.0, MESH_HEIGHT, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = LOOT_ALBEDO
	material.metallic = 0.6
	material.roughness = 0.35
	_visual.material_override = material
	add_child(_visual)
	# The label is the only way a drop names itself in a pile, so it always
	# billboards toward the camera and keeps a dark outline for readability.
	_label = Label3D.new()
	_label.position = Vector3(0.0, LABEL_HEIGHT, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = LABEL_SIZE
	_label.outline_size = 8
	_label.modulate = LOOT_ALBEDO
	add_child(_label)

func _set_label(text: String) -> void:
	if _label != null:
		_label.text = text
