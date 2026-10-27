class_name SacrificialAltar
extends Node3D
## The physical altar: a low block of wet stone with one dim red light over it,
## and the ritual panel it owns.
##
## Everything the panel does lives in `AltarMenu`; this node only says "there is
## something here to kneel at". A scene drops it into the town or the admin arena
## and the interaction code tests `in_reach()` before calling `interact()`, so the
## altar never has to know which mode owns the camera.

signal opened(peer_id: int)

const AltarMenuScript = preload("res://scripts/warband/altar_menu.gd")

## How close a body must stand before the altar can be used.
@export var interact_range: float = 3.0

## The peer that last used the altar, for the mode's own logging.
var last_peer := -1

var _menu: AltarMenu = null
var _owns_menu := false
var _built := false

func _ready() -> void:
	_build_body()

func _exit_tree() -> void:
	# A menu this altar put under the scene root would outlive the altar and
	# reopen over the next scene; one the mode supplied is the mode's to keep.
	if _owns_menu and _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null

## True when `world_position` is inside the kneeling radius.
func in_reach(world_position: Vector3) -> bool:
	return global_position.distance_to(world_position) <= interact_range

## Open the ritual panel for the peer who knelt here.
func interact(peer_id: int) -> void:
	last_peer = peer_id
	var panel := ensure_menu()
	panel.open()
	opened.emit(peer_id)

func is_open() -> bool:
	return _menu != null and is_instance_valid(_menu) and _menu.is_open()

## The panel, created on first use. Scenes that already own a UI can call this and
## add it themselves; otherwise it lands on the scene root as its own CanvasLayer.
func ensure_menu() -> AltarMenu:
	if _menu != null and is_instance_valid(_menu):
		_point_menu_at_warband(_menu)
		return _menu
	var existing := _find_menu(get_tree().root if get_tree() != null else null)
	if existing != null:
		_menu = existing
		_owns_menu = false
		_point_menu_at_warband(_menu)
		return _menu
	var fresh: AltarMenu = AltarMenuScript.new()
	fresh.name = "AltarMenu"
	_menu = fresh
	_owns_menu = true
	_point_menu_at_warband(fresh)
	if get_tree() != null:
		get_tree().root.add_child(fresh)
	return fresh

func menu() -> AltarMenu:
	return _menu

func close() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.close()

## A scene that owns its own panel hands it over here so `interact()` opens it.
func adopt_menu(panel: AltarMenu) -> void:
	_menu = panel
	_owns_menu = false
	_point_menu_at_warband(panel)

func _point_menu_at_warband(panel: AltarMenu) -> void:
	var warband := get_node_or_null("/root/Warband")
	if warband != null:
		panel.configure(warband)

func _find_menu(scan: Node) -> AltarMenu:
	if scan == null:
		return null
	for child in scan.get_children():
		if child.get_script() == AltarMenuScript:
			return child as AltarMenu
		var found := _find_menu(child)
		if found != null:
			return found
	return null

func _build_body() -> void:
	if _built:
		return
	_built = true
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.17, 0.15, 0.15)
	stone.roughness = 0.96
	stone.metallic = 0.05

	var base := MeshInstance3D.new()
	base.name = "Base"
	var base_box := BoxMesh.new()
	base_box.size = Vector3(1.9, 0.18, 1.3)
	base.mesh = base_box
	base.material_override = stone
	base.position = Vector3(0.0, 0.09, 0.0)
	add_child(base)

	var block := MeshInstance3D.new()
	block.name = "Block"
	var block_box := BoxMesh.new()
	block_box.size = Vector3(1.4, 0.62, 0.9)
	block.mesh = block_box
	block.material_override = stone
	block.position = Vector3(0.0, 0.49, 0.0)
	add_child(block)

	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var slab_box := BoxMesh.new()
	slab_box.size = Vector3(1.55, 0.08, 1.0)
	slab.mesh = slab_box
	slab.material_override = stone
	slab.position = Vector3(0.0, 0.84, 0.0)
	add_child(slab)

	# One guttering light: enough to find the altar at night, not enough to read by.
	var light := OmniLight3D.new()
	light.name = "RitualLight"
	light.light_color = Color(0.86, 0.24, 0.20)
	light.light_energy = 1.1
	light.omni_range = 4.0
	light.omni_attenuation = 1.6
	light.position = Vector3(0.0, 1.15, 0.0)
	add_child(light)
