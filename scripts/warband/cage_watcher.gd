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

## The pair Corvin puts down are thinned mooks; everything else that holds the
## road is twice what a camp watcher used to be (a shiv needs a dozen stabs).
const PAIR_HEALTH := 44.0
const HARDENED_HEALTH := 144.0
const WATCHER_DAMAGE := 5.0
## Set before the body enters the tree. The two the rescuer fights are weak; the
## rest are hardened.
var health_pool := HARDENED_HEALTH

## The catalog weapon this watcher carries, or "" for a bare one. Set by the
## scene when the second wave comes through the gate; the scene spawns it as a
## drop when the body falls.
var weapon_item := ""
## Armour the cultist was wearing. A corpse is worth checking: this is what the
## squad or the player finds on it once the fighting stops.
var armor_items: Array[String] = []
var _weapon_socket: Node3D = null

## Every warband cultist guards between its own swings; the frontier's mobs do not
## opt in, so the base game keeps the fight it was tuned for.
func _ready() -> void:
	super()
	# Only the hardened cultists brace. The pair Corvin puts down are mooks: they
	# are cheaper to kill than to out-wait.
	guard_between_swings = health_pool >= HARDENED_HEALTH


## Everything worth taking off this body: the blade in its hand and the rag on
## its back. The scene spawns each as a drop where it fell.
func gear_items() -> Array[String]:
	var out: Array[String] = []
	if not weapon_item.is_empty():
		out.append(weapon_item)
	for piece in armor_items:
		if not piece.is_empty():
			out.append(piece)
	return out


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

## Commit to a body and run straight at it. The camp calls this on spawn and
## whenever a watcher calms down, so the pack never stands around waiting to be
## noticed: `hear_alert` gives the senses a target without needing line of sight.
func hunt(target: Node3D) -> void:
	if not alive or is_instance_valid(target) == false:
		return
	player = target
	if not _senses.aggressive():
		hear_alert(target, target.global_position)

## True while this watcher has a live pursuit.
func hunting() -> bool:
	return _senses.aggressive()

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
	warden["health"] = health_pool
	warden["damage"] = WATCHER_DAMAGE
	warden["cooldown"] = 1.1
	warden["windup"] = 0.42
	warden["recover"] = 0.45
	warden["sight"] = 60.0
	warden["gold"] = 0
	warden["packed"] = false
	# A camp watcher does not circle: it runs the body down.
	warden["run_speed"] = 5.6
	warden["walk_speed"] = 2.2
	warden["orbit"] = 1.9
	table["hollow_warden"] = warden
	return table
