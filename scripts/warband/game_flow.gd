extends Node
## Autoload `GameFlow`: the door between the warband's scenes.
##
## The campaign is a chain of scenes that each know one next place: the cages
## hand the squad to the town, the town's gate launches an expedition, the arena
## hands the survivors back. No scene loads another directly - each emits
## `scene_requested(path)` and this node is the only thing that changes scene, so
## a test can drive a whole scene without being teleported out of it.
##
## `active` stays false until the flow is entered from the title menu or the
## campaign button, which is what keeps every scene regression able to emit its
## door signal without the tree moving underneath it.

const CAGE_SCENE := "res://scenes/cage_escape.tscn"
const TOWN_SCENE := "res://scenes/town_hub.tscn"
const ARENA_SCENE := "res://admin_arena.tscn"

var active := false
var last_scene := ""
var transitions := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## The title menu's one door: resume a saved warband in town, or start the cages.
func enter_warband() -> void:
	var warband := get_node_or_null("/root/Warband")
	if warband == null:
		return
	active = true
	if warband.load_state() and warband.roster.count() > 0:
		goto(TOWN_SCENE)
		return
	warband.reset_state()
	warband.save_state()
	goto(CAGE_SCENE)

## A brand-new campaign: the four cages, whatever the save says.
func start_campaign() -> void:
	var warband := get_node_or_null("/root/Warband")
	active = true
	if warband != null:
		warband.reset_state()
		warband.save_state()
	goto(CAGE_SCENE)

## Go straight to the hub (debug door, and where a resumed campaign lands).
func enter_town() -> void:
	active = true
	goto(TOWN_SCENE)

func launch_expedition() -> void:
	active = true
	goto(ARENA_SCENE)

## Connect a scene's door to this node. Scenes call this from their own `_ready`;
## connecting is harmless while `active` is false.
func bind(scene: Node) -> void:
	if scene == null or not scene.has_signal("scene_requested"):
		return
	var callable := Callable(self, "_on_scene_requested")
	if not scene.is_connected("scene_requested", callable):
		scene.scene_requested.connect(callable)

func _on_scene_requested(path: String) -> void:
	if not active:
		return
	goto(path)

func goto(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("GameFlow: %s is not a scene" % path)
		return
	var warband := get_node_or_null("/root/Warband")
	if warband != null:
		# Bodies do not survive a scene change, so the soul registry must not
		# either: every next scene re-enters the body its peer already had.
		warband.save_state()
		warband.clear_possession()
	last_scene = path
	transitions += 1
	var tree := get_tree()
	if tree == null:
		return
	# A tutorial card may be holding the tree still; the next scene must not
	# open paused behind it.
	tree.paused = false
	tree.call_deferred("change_scene_to_file", path)
