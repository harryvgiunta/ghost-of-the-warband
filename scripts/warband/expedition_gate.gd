class_name ExpeditionGate
extends Node3D
## The expedition gate: the stone arch that turns a marked battle line into a
## scene request.
##
## The hub owns the square and `Warband` owns the roster, so this node only reads
## the deployment state (`prompt`), writes the battle line through the real
## `Warband.deploy_battle` and asks for the next scene. It never loads the arena
## itself: the game-flow owner connects `scene_requested`, which keeps the town
## walkable in a test and leaves the hand-off in one place.

signal scene_requested(path: String)

const Geo = preload("res://scripts/geo.gd")
const WarbandState = preload("res://scripts/warband/warband_state.gd")

const ARENA_SCENE := "res://admin_arena.tscn"
const TOWN_SCENE := "res://scenes/town_hub.tscn"

## How close a body must stand before the gate reports itself open.
@export var open_radius: float = 4.0

var _warband: WarbandState = null
var _controller = null
var _built := false

func _ready() -> void:
	_build_arch()

## Bind the gate to the warband and the controller whose bodies can stand here.
func setup(warband: WarbandState, controller) -> void:
	_warband = warband
	_controller = controller

## True when `world_position` is inside the arch's ring.
func in_reach(world_position: Vector3) -> bool:
	return global_position.distance_to(world_position) <= open_radius

## What a player standing in the arch is told: whether the gate answers, the
## battle line already marked, and the deployment cap that line obeys.
func prompt(peer_id: int) -> Dictionary:
	var warband := _state()
	if warband == null:
		return {"ok": false, "message": "There is no warband to march.",
			"deployed_ids": [], "cap": 0}
	var deployed: Array[int] = warband.deployed_merc_ids()
	var cap := int(warband.deployment_cap)
	if _body_at_gate(peer_id) == null:
		return {"ok": false,
			"message": "The gate is sealed. Step inside the arch to march.",
			"deployed_ids": deployed, "cap": cap}
	if deployed.is_empty():
		return {"ok": true,
			"message": "The gate is open. Mark up to %d of the %d sworn for the field."
				% [cap, int(warband.roster.alive_count())],
			"deployed_ids": deployed, "cap": cap}
	return {"ok": true,
		"message": "The gate is open: %d of %d sworn march with you."
			% [deployed.size(), cap],
		"deployed_ids": deployed, "cap": cap}

## Mark the battle line and ask for the field. `ids` keeps its own order, and the
## roster's cap still decides how many of it can actually march.
func deploy_and_launch(ids: Array) -> Dictionary:
	var warband := _state()
	if warband == null:
		return {"ok": false, "message": "There is no warband to march.",
			"deployed_ids": [], "cap": 0}
	var cap := int(warband.deployment_cap)
	if ids.is_empty():
		return {"ok": false, "message": "Mark at least one sworn body for the field.",
			"deployed_ids": warband.deployed_merc_ids(), "cap": cap}
	var deployed: Array[int] = warband.deploy_battle(ids)
	if deployed.is_empty():
		return {"ok": false, "message": "None of those can march.",
			"deployed_ids": deployed, "cap": cap}
	scene_requested.emit(ARENA_SCENE)
	return {"ok": true, "message": "%d sworn step through the gate." % deployed.size(),
		"deployed_ids": deployed, "cap": cap}

## The other direction of the loop: back to the square.
func return_to_town() -> Dictionary:
	scene_requested.emit(TOWN_SCENE)
	return {"ok": true, "message": "Back to the square.", "path": TOWN_SCENE}

# --- reading ---------------------------------------------------------------

func _state() -> WarbandState:
	if _warband != null and is_instance_valid(_warband):
		return _warband
	return get_node_or_null("/root/Warband") as WarbandState

## The peer's own body when it stands in the ring, otherwise any standing body.
## The second case is what lets a second peer's body hold the gate open.
func _body_at_gate(peer_id: int):
	if _controller == null or not is_instance_valid(_controller):
		return null
	var actor = _controller.active_body(peer_id)
	if _standing(actor):
		return actor
	for body in _controller.bodies():
		if _standing(body):
			return body
	return null

func _standing(body) -> bool:
	return body != null and is_instance_valid(body) \
		and bool(body.get("alive")) and not bool(body.get("downed")) \
		and in_reach(body.global_position)

# --- the arch --------------------------------------------------------------

func _build_arch() -> void:
	if _built:
		return
	_built = true
	var stone := Geo.material(Color(0.24, 0.22, 0.20), 0.02, 0.92)
	var wood := Geo.material(Color(0.20, 0.14, 0.09), 0.0, 0.86)
	var ember := StandardMaterial3D.new()
	ember.albedo_color = Color(0.96, 0.64, 0.26)
	ember.emission_enabled = true
	ember.emission = Color(1.0, 0.56, 0.18)
	ember.emission_energy_multiplier = 2.4

	for side in [-1.0, 1.0]:
		var x: float = 2.6 * float(side)
		Geo.box(self, Vector3(0.9, 4.4, 0.9), Vector3(x, 2.2, 0.0), stone)
		Geo.box(self, Vector3(1.5, 0.28, 1.5), Vector3(x, 0.14, 0.0), stone)
		Geo.box(self, Vector3(0.22, 0.8, 0.22), Vector3(x, 4.9, 0.0), wood)
		Geo.box(self, Vector3(0.34, 0.44, 0.34), Vector3(x, 4.45, 0.0), ember)
		var light := OmniLight3D.new()
		light.name = "GateLight"
		light.light_color = Color(1.0, 0.62, 0.30)
		light.light_energy = 1.5
		light.omni_range = 7.0
		light.omni_attenuation = 1.4
		light.position = Vector3(x, 4.3, 0.0)
		add_child(light)

	Geo.box(self, Vector3(6.9, 0.7, 1.1), Vector3(0.0, 4.75, 0.0), stone)
	Geo.box(self, Vector3(6.2, 0.2, 0.9), Vector3(0.0, 5.2, 0.0), wood)
	# A torn banner over the lintel: warm cloth, no collider, reads at a glance.
	Geo.box(self, Vector3(2.8, 1.6, 0.06), Vector3(0.0, 3.9, 0.5),
		Geo.material(Color(0.42, 0.13, 0.10), 0.0, 0.95))

	var label := Label3D.new()
	label.text = "THE FIELD"
	label.font_size = 64
	label.pixel_size = 0.007
	label.modulate = Color(0.96, 0.74, 0.42)
	label.position = Vector3(0.0, 5.6, 0.0)
	add_child(label)

	# The pillars are solid, so the arch is walked through and not around.
	var body := StaticBody3D.new()
	body.name = "ArchCollision"
	add_child(body)
	for side in [-1.0, 1.0]:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.9, 4.4, 0.9)
		shape.shape = box
		shape.position = Vector3(2.6 * float(side), 2.2, 0.0)
		body.add_child(shape)
