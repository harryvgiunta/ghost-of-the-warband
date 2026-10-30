class_name SacrificialAltar
extends Node3D
## The physical altar - a stepped block of dark wet stone, a reagent bowl on its
## slab, a horned skull, guttering blood-red candles and a ring of skull-topped
## sticks - its one warm red light, the name over it, and the ritual panel it owns.
##
## Everything the panel does lives in `AltarMenu`; this node only says "there is
## something here to kneel at". A scene drops it into the town or the admin arena
## and the interaction code tests `in_reach()` before calling `interact()`, so the
## altar never has to know which mode owns the camera.
##
## The body is presentation in the camp's own house style (`camp_dressing.gd`'s
## cold altar): `CampKit.Merged` batches and `FireFx` candle cards on the shared
## flame shader, asked for a blood palette instead of the camp's cold blue. It is
## a handful of draws, no collider, and stays inside `BODY_RADIUS` of the node.

signal opened(peer_id: int)

const AltarMenuScript = preload("res://scripts/warband/altar_menu.gd")
const CampDressing = preload("res://scripts/warband/camp_dressing.gd")
const TextureLibrary = preload("res://scripts/world/texture_library.gd")
const Geo = preload("res://scripts/geo.gd")

## The word over the altar, in the keepers' plate style (`town_folk.gd`).
const NAMEPLATE_TEXT := "THE ALTAR"
const NAMEPLATE_HEIGHT := 2.2
const NAMEPLATE_COLOR := Color(1.0, 0.78, 0.68)

## Every piece of the body stands within this distance of the node origin.
const BODY_RADIUS := 2.5
## Height of the slab's top face: where the bowl, skull and candles stand.
const SLAB_TOP := 1.14

static var _palette: Dictionary = {}

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
	var mats: Dictionary = CampKit.materials()
	var own := palette()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4013

	# The stone: two shallow steps, a pedestal and the stele standing behind it;
	# the broad face looks down -X, which is the square's side of the altar in town.
	var stone := CampKit.Merged.new()
	CampKit.add_box(stone, Vector3(2.0, 0.14, 2.8), Vector3(0.0, 0.07, 0.0), own["stone_dark"])
	CampKit.add_box(stone, Vector3(1.6, 0.14, 2.2), Vector3(0.0, 0.21, 0.0), own["stone"],
		0.02)
	CampKit.add_box(stone, Vector3(0.95, 0.66, 1.75), Vector3(0.0, 0.61, 0.0), own["stone"])
	CampKit.add_box(stone, Vector3(1.08, 0.08, 1.9), Vector3(0.0, 0.96, 0.0), own["stone_dark"])
	CampKit.add_box(stone, Vector3(0.20, 1.62, 0.80), Vector3(0.86, 0.95, 0.0), own["stone_dark"])
	CampKit.add_box(stone, Vector3(0.26, 0.10, 0.92), Vector3(0.86, 1.78, 0.0), own["stone"])
	stone.commit(self, "AltarStone")

	# The slab the reagent and the weapon are laid on.
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var slab_box := BoxMesh.new()
	slab_box.size = Vector3(1.25, 0.14, 2.05)
	slab.mesh = slab_box
	slab.material_override = own["stone"]
	slab.position = Vector3(0.0, SLAB_TOP - 0.07, 0.0)
	add_child(slab)

	var dressing := CampKit.Merged.new()
	var flames := CampKit.Merged.new()
	_lay_blood(dressing, own, rng)
	_lay_offering(dressing, mats, own)
	# Candles guttering in pairs at the slab's four corners.
	for corner in [Vector2(-0.46, -0.80), Vector2(-0.46, 0.80), Vector2(0.44, -0.84),
			Vector2(0.44, 0.84)]:
		var c: Vector2 = corner
		_candle(dressing, flames, own, rng, Vector3(c.x, SLAB_TOP, c.y),
			rng.randf_range(0.20, 0.30), 0.050)
		_candle(dressing, flames, own, rng,
			Vector3(c.x + rng.randf_range(-0.10, 0.10), SLAB_TOP, c.y * 0.82),
			rng.randf_range(0.10, 0.16), 0.040)
	# Two tall iron stands behind it: the silhouette the square sees first.
	for side in CampKit.SIDES:
		_stand(dressing, flames, own, rng, Vector3(0.62, 0.14, side * 1.18))
	# The ring of skull-topped sticks and a heap of the altar's leavings.
	CampKit.skull_ring(dressing, mats, Vector3.ZERO, 1.92, 8, 523)
	CampKit.bone_heap(dressing, mats, Vector3(-1.38, 0.0, -1.15), 0.7, 619)
	dressing.commit(self, "AltarDressing")
	flames.commit(self, "AltarFlames", false)

	# One light: warm blood-red, enough to find the altar across the square.
	var light := OmniLight3D.new()
	light.name = "RitualLight"
	light.light_color = Color(1.0, 0.30, 0.20)
	light.light_energy = 2.6
	light.omni_range = 9.0
	light.omni_attenuation = 1.3
	light.shadow_enabled = false
	light.position = Vector3(-0.2, 1.75, 0.0)
	add_child(light)

	var plate := Label3D.new()
	plate.name = "AltarNameplate"
	plate.text = NAMEPLATE_TEXT
	plate.font_size = 44
	plate.pixel_size = 0.0046
	plate.modulate = NAMEPLATE_COLOR
	plate.outline_size = 10
	plate.outline_modulate = Color(0.10, 0.02, 0.02, 0.9)
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.render_priority = 1
	plate.position = Vector3(0.0, NAMEPLATE_HEIGHT, 0.0)
	add_child(plate)

## The altar's own materials beside the camp kit's: dark wet granite, the camp's
## iron and old blood, fresh gore, the ichor in the bowl, tallow, and the flame
## shader asked for blood instead of firelight. Cached: every altar shares them.
static func palette() -> Dictionary:
	if not _palette.is_empty():
		return _palette
	var metal: Dictionary = CampDressing.metal()
	var m: Dictionary = {}
	m["stone"] = TextureLibrary.granite_material(Color("5d5450"))
	m["stone_dark"] = TextureLibrary.granite_material(Color("433b38"))
	m["iron"] = metal["iron"]
	m["steel"] = metal["steel"]
	m["blood"] = metal["blood"]
	m["gore"] = Geo.material(Color(0.17, 0.012, 0.012), 0.0, 0.28)
	var ichor := Geo.material(Color(0.62, 0.05, 0.05), 0.0, 0.10)
	ichor.emission_enabled = true
	ichor.emission = Color(1.0, 0.14, 0.08)
	ichor.emission_energy_multiplier = 2.2
	m["ichor"] = ichor
	m["tallow"] = Geo.material(Color(0.58, 0.50, 0.38), 0.0, 0.8)
	var flame: ShaderMaterial = TextureLibrary.flame_material().duplicate()
	flame.set_shader_parameter("hot_color", Color(1.0, 0.40, 0.28))
	flame.set_shader_parameter("cool_color", Color(0.72, 0.03, 0.02))
	flame.set_shader_parameter("glow", 1.2)
	flame.set_shader_parameter("waver", 0.14)
	m["flame"] = flame
	_palette = m
	return m

## The slab's stain, the runs down its face, and the pools on the steps and dirt.
func _lay_blood(m: CampKit.Merged, own: Dictionary, rng: RandomNumberGenerator) -> void:
	CampKit.add_box(m, Vector3(0.86, 0.012, 1.30), Vector3(-0.08, SLAB_TOP + 0.006, 0.05),
		own["gore"], 0.06)
	for run in 5:
		var z := -0.62 + float(run) * 0.31 + rng.randf_range(-0.06, 0.06)
		var drop := rng.randf_range(0.10, 0.14)
		CampKit.add_box(m, Vector3(0.012, drop, rng.randf_range(0.05, 0.09)),
			Vector3(-0.631, SLAB_TOP - drop * 0.5, z), own["gore"])
		var trickle := rng.randf_range(0.18, 0.55)
		CampKit.add_box(m, Vector3(0.012, trickle, rng.randf_range(0.04, 0.07)),
			Vector3(-0.481, 0.92 - trickle * 0.5, z + rng.randf_range(-0.03, 0.03)),
			own["gore"])
	CampKit.add_ball(m, 0.34, Vector3(-0.66, 0.285, -0.22), own["blood"],
		Vector3(1.0, 0.04, 1.5), 10, 3)
	CampKit.add_ball(m, 0.66, Vector3(-1.32, 0.02, 0.18), own["blood"],
		Vector3(1.0, 0.05, 1.45), 10, 3)

## The reason the altar is visited: an iron bowl of ichor at the front of the
## slab where a weapon is laid, under the horned skull nailed to the stele.
func _lay_offering(m: CampKit.Merged, mats: Dictionary, own: Dictionary) -> void:
	var bowl_at := Vector3(-0.20, SLAB_TOP, 0.0)
	for foot in 3:
		var angle := TAU * float(foot) / 3.0 + 0.5
		CampKit.add_beam(m, bowl_at + Vector3(cos(angle) * 0.16, 0.0, sin(angle) * 0.16),
			bowl_at + Vector3(cos(angle) * 0.10, 0.07, sin(angle) * 0.10), 0.018,
			own["iron"], 4, 0.014)
	var bowl := CylinderMesh.new()
	bowl.bottom_radius = 0.12
	bowl.top_radius = 0.23
	bowl.height = 0.12
	bowl.radial_segments = 14
	bowl.rings = 1
	m.add(bowl, Transform3D(Basis.IDENTITY, bowl_at + Vector3(0.0, 0.12, 0.0)), own["iron"])
	CampKit.add_ring(m, bowl_at + Vector3(0.0, 0.18, 0.0), 0.0, 0.215, 0.25, own["steel"],
		0.0, 14, 4)
	CampKit.add_ball(m, 0.21, bowl_at + Vector3(0.0, 0.172, 0.0), own["ichor"],
		Vector3(1.0, 0.06, 1.0), 12, 3)
	# The horned skull nailed to the stele's face, looking down at the bowl, and
	# the ochre marks daubed either side of it.
	CampKit.add_skull(m, mats, Vector3(0.58, 1.50, 0.0), PI * 0.5, 1.3, true)
	for side in CampKit.SIDES:
		for mark in 3:
			CampKit.add_box(m, Vector3(0.012, 0.16, 0.035),
				Vector3(0.752, 1.28 + float(mark) * 0.17, side * (0.27 + float(mark % 2) * 0.03)),
				mats["ochre"], 0.0, side * 0.25)

## A tallow candle standing on `at`, with its own small blood flame.
func _candle(m: CampKit.Merged, flames: CampKit.Merged, own: Dictionary,
		rng: RandomNumberGenerator, at: Vector3, height: float, radius: float) -> void:
	CampKit.add_ball(m, radius * 1.6, at, own["tallow"], Vector3(1.0, 0.30, 1.0), 7, 3)
	CampKit.add_beam(m, at, at + Vector3(0.0, height, 0.0), radius, own["tallow"], 6,
		radius * 0.9)
	var saved := flames.push(Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.z)))
	FireFx.flame_cards(flames, own["flame"], rng, 0.16, at.y + height)
	flames.group = saved

## A tall iron candle stand: three splayed feet, a shaft, a drip pan and a fat
## candle burning well above head height of the slab.
func _stand(m: CampKit.Merged, flames: CampKit.Merged, own: Dictionary,
		rng: RandomNumberGenerator, foot: Vector3) -> void:
	var top := foot + Vector3(0.0, 1.50, 0.0)
	for leg in 3:
		var angle := TAU * float(leg) / 3.0 + 0.2
		CampKit.add_beam(m, foot + Vector3(cos(angle) * 0.20, 0.0, sin(angle) * 0.20),
			foot + Vector3(0.0, 0.22, 0.0), 0.024, own["iron"], 4, 0.018)
	CampKit.add_beam(m, foot, top, 0.030, own["iron"], 5, 0.022)
	CampKit.add_ring(m, top, 0.0, 0.07, 0.13, own["iron"], 0.0, 10, 3)
	_candle(m, flames, own, rng, top + Vector3(0.0, 0.01, 0.0), 0.26, 0.060)
