extends "res://scripts/forest_mob.gd"
## The camp's watchers: the antlered hollow wardens, thinned for the first fight.
##
## The tutorial's two gate guards used to be full arena bodies in cult colours -
## armoured, parrying, hundred-health fighters that read as red statues and took
## a dozen swings. They are now the woodland's own watcher silhouette (the
## antlered hollow warden) with a camp profile: thirty-six health, so three
## dagger stabs (and a headshot coin-flip) put one down, and a slow, light swing
## that cannot delete a prisoner before they learn to block.
##
## Only the profile changes. The state machine, senses, pack alarm and death
## presentation are the shared wilderness ones, so these are real enemies rather
## than props.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const State = preload("res://scripts/player_state.gd")

## Three stabs of a makeshift shiv (14) with no headshot is 42, so 36 health
## leaves a little room for a weak block or a miss without a fourth swing.
const WATCHER_HEALTH := 36.0
const WATCHER_DAMAGE := 5.0

## The catalog weapon this watcher carries, or "" for a bare one. Set by the
## scene when the second wave comes through the gate; the scene spawns it as a
## drop when the body falls.
var weapon_item := ""
var _weapon_socket: Node3D = null

## Put a blade in the watcher's right hand. The forest rig has a real `hand_r`
## bone, so the weapon follows the authored swing; a rig without one keeps the
## item in the roster but shows nothing rather than floating a sword at the hips.
func arm(item_id: String) -> void:
	weapon_item = item_id
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return
	var skeleton: Skeleton3D = null
	for node in find_children("*", "Skeleton3D", true, false):
		skeleton = node as Skeleton3D
		break
	if skeleton == null or skeleton.find_bone("hand_r") < 0:
		return
	var length := 0.86 if str(item.get("kind", "")) == "sword" else 0.52
	var socket := BoneAttachment3D.new()
	socket.name = "WeaponSocket"
	socket.bone_name = "hand_r"
	skeleton.add_child(socket)
	var mesh := MeshInstance3D.new()
	var blade := BoxMesh.new()
	blade.size = Vector3(0.045, length, 0.085)
	mesh.mesh = blade
	mesh.position = Vector3(0.0, length * 0.5, 0.0)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.66, 0.68, 0.70)
	steel.metallic = 0.75
	steel.roughness = 0.32
	mesh.material_override = steel
	socket.add_child(mesh)
	var guard := MeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.2, 0.04, 0.06)
	guard.mesh = bar
	guard.material_override = steel
	socket.add_child(guard)
	_weapon_socket = socket

## Take the carried weapon off the body (the scene drops it) and clear the hand.
## True while a blade is actually attached to the hand bone (the rig has one).
func has_weapon_visual() -> bool:
	return is_instance_valid(_weapon_socket)

func take_weapon_item() -> String:
	var item := weapon_item
	weapon_item = ""
	if is_instance_valid(_weapon_socket):
		_weapon_socket.queue_free()
	_weapon_socket = null
	return item

func _profiles() -> Dictionary:
	# The parent returns its `const` table, which is read-only: duplicate before
	# tuning a camp copy of the warden.
	var table: Dictionary = (super._profiles() as Dictionary).duplicate(true)
	if not table.has("hollow_warden"):
		return table
	var warden: Dictionary = (table["hollow_warden"] as Dictionary).duplicate(true)
	warden["display"] = "Camp watcher"
	warden["health"] = WATCHER_HEALTH
	warden["damage"] = WATCHER_DAMAGE
	warden["cooldown"] = 2.4
	warden["windup"] = 0.45
	warden["recover"] = 0.55
	warden["sight"] = 18.0
	warden["gold"] = 0
	warden["packed"] = false
	warden["run_speed"] = 3.2
	table["hollow_warden"] = warden
	return table
