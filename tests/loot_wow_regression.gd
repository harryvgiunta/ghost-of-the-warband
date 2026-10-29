extends SceneTree
## World-of-Warcraft looting for the warband: the click that ducks the body, works
## the ground and takes everything - corpse or pile - into the shared stash with
## one line said about it; the wolf's salvage table and the wardens' ichor behind
## it; and the drop silhouettes that make the two readable on dark ground.
##
## Nothing here reads a helper in isolation where a live body will do. The wolf
## table is asked of `enemy.gd` bodies spawned the way the wilderness spawns them,
## the booking is the vacuum's own corpse path, the hand is driven on a stub body
## and a stub world (it duck-types both), and the wardens are instantiated exactly
## as the camp instantiates them.

const LootScript = preload("res://scripts/warband/loot_vacuum.gd")
const PickupScript = preload("res://scripts/warband/warband_pickup.gd")
const SummaryScript = preload("res://scripts/warband/loot_summary.gd")
const HandScript = preload("res://scripts/warband/loot_hand.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const WolfScript = preload("res://scripts/enemy.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const StateScript = preload("res://scripts/player_state.gd")

const TEST_SAVE := "user://loot_wow_state.json"
## The four parts a briar wolf is cut into, and the wardens' reagent.
const SALVAGE := ["wolf_pelt", "wolf_bone", "wolf_tooth", "wolf_paw"]
const ICHOR := "ichor_vial"
const PELT := "wolf_pelt"
const WOLF_SAMPLE := 7
const WATCHER_SAMPLE := 12

## A body that can duck and be knocked down. The hand only duck-types the crouch,
## so this is everything a body has to be to work the ground.
class StubBody extends Node3D:
	## The two the world's bodies raise when a fight ends one of them.
	signal downed_started(slot: int)
	signal killed(slot: int, source: int)

	var downed := false
	var alive := true
	var crouching := false

	func set_crouch(requested: bool) -> void:
		crouching = requested

## A fallen body as the vacuum sees one: the kit it answers with, and where it
## lies.
class StubCorpse extends Node3D:
	var carried: Array[String] = []

	func gear_items() -> Array[String]:
		return carried.duplicate()

	func get_display_name() -> String:
		return "Briar wolf"

## The world's own plumbing, cut down to the four things the hand adopts.
class StubWorld extends Node3D:
	## The campaign publishes 2.6; this one is deliberately different, so a reach
	## read off the world is proved to be the world's and not the hand's default.
	const LOOT_REACH := 3.40
	var loot = null
	var hud = null
	var controller = null
	var _client := false

## The controller surface the hand re-dresses a looted body through.
class StubController extends Node:
	var refreshed: Array[int] = []

	func merc_for_peer(_peer: int) -> int:
		return 3

	func refresh_gear(merc_id: int) -> bool:
		refreshed.append(merc_id)
		return true

var checks := 0
var failures := 0

var _warband = null
var _field: Node3D = null
var _loot: WarbandLoot = null
## The wolf the booking check strips, and its registered corpse id.
var _wolf = null
var _corpse := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("LOOT_WOW_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))


func run() -> void:
	_remove_test_save()
	var state = root.get_node("PlayerState")
	var warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = TEST_SAVE
	warband.reset_state()
	_warband = warband

	_field = Node3D.new()
	_field.name = "LootField"
	root.add_child(_field)
	_loot = LootScript.new()
	_loot.name = "Loot"
	_field.add_child(_loot)
	_loot.setup(warband, _field)

	check_wolf_table()
	check_booking()
	check_summary()
	await check_silhouettes()
	await check_hand()
	await check_watchers()

	_field.queue_free()
	await process_frame
	_remove_test_save()
	print("LOOT_WOW_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


# --- the wolf's salvage table ---------------------------------------------

## A briar wolf is a container of parts, and the parts are its own: two or three
## distinct pieces, a pelt every time, the same answer from the same body however
## often it is asked, and the same answer again for a body that stood on the same
## ground with the same number - which is what makes a replay and the other
## machine agree.
func check_wolf_table() -> void:
	var sets := {}
	var table: Array[String] = []
	for index in WOLF_SAMPLE:
		var wolf = _spawn_wolf(index)
		var parts: Array[String] = wolf.gear_items()
		var label := "%s at %d/%d" % [wolf.name, int(wolf.global_position.x),
			int(wolf.global_position.z)]
		check(parts.size() >= 2 and parts.size() <= 3,
			"%s yields two or three parts, got %d" % [label, parts.size()])
		check(parts.has(PELT), "%s always gives up its pelt" % label)
		var distinct := {}
		for part in parts:
			distinct[part] = true
			check(SALVAGE.has(part), "%s yields only wolf parts, got %s" % [label, part])
			check(StateScript.ITEMS.has(part), "%s is a carried catalog piece" % part)
		check(distinct.size() == parts.size(), "%s yields distinct parts, got %s"
			% [label, str(parts)])
		check(wolf.gear_items() == parts, "%s answers the same pieces twice" % label)
		check(WolfScript.parts_for(wolf.name, wolf.global_position) == parts,
			"%s replays to the same pieces" % label)
		# A corpse that slid a step in its ragdoll is still the same corpse.
		wolf.global_position += Vector3(0.3, 0.0, -0.2)
		check(wolf.gear_items() == parts, "%s keeps its pieces after it settles" % label)
		sets[str(parts)] = true
		table.append("%s -> %s" % [wolf.name, str(parts)])
		_wolf = wolf
	check(sets.size() >= 3, "the table is not one body copied: %d distinct rolls"
		% sets.size())
	print("LOOT_WOW_TABLE wolves=%d sets=%d" % [WOLF_SAMPLE, sets.size()])
	for line in table:
		print("LOOT_WOW_TABLE ", line)

	# Killed the way a blow kills one, then registered the way the world does it.
	var expected: Array[String] = _wolf.gear_items()
	_wolf.take_damage(_wolf.max_health + 20.0, 1)
	check(not bool(_wolf.alive), "the wolf is dead")
	_corpse = _loot.register_corpse(_wolf)
	check(_corpse != 0, "a fallen wolf is a container")
	check(_loot.corpse_items(_corpse) == expected,
		"the corpse holds the parts the body rolled, got %s"
			% str(_loot.corpse_items(_corpse)))
	check(_loot.corpse_ids().has(_corpse), "the body is offered to a searcher")

	# A cinder devil carries no salvage of its own: the scene that spawns its steel
	# owns that, and this table must not invent a second one.
	var devil = WolfScript.new()
	devil.kind = 2
	devil.name = "CinderDevil"
	_field.add_child(devil)
	check(devil.gear_items().is_empty(), "a cinder devil has no salvage table")


## One wolf, spawned the way the wilderness spawns one: kind set before the tree,
## the species name numbered after it, the post its own.
func _spawn_wolf(index: int):
	var wolf = WolfScript.new()
	wolf.kind = 0
	wolf.position = Vector3(120.0 + float(index) * 18.0, 0.0, -8.0)
	_field.add_child(wolf)
	wolf.global_position = Vector3(120.0 + float(index) * 18.0, 0.0, -8.0)
	wolf.name = "BriarWolf%d" % (index + 1)
	return wolf


# --- the one way into the stash --------------------------------------------

## Stripping the body books every part and leaves the record empty, and a second
## strip cannot pay twice.
func check_booking() -> void:
	var items := _loot.corpse_items(_corpse)
	var stash: WarbandStash = _warband.stash
	var before := stash.pooled_total()
	var taken: Dictionary = _loot.take_all_from_corpse(_corpse, 0)
	check(bool(taken.get("ok", false)), "the body can be stripped in one go")
	check(taken.get("ids", []) == items, "the take names every part the body held")
	check(int(taken.get("count", -1)) == items.size(), "the take counts them")
	var value := 0
	for part in items:
		check(stash.pooled_count(part) == 1, "%s is a stash row" % part)
		value += StashScript.value_of(part)
	check(int(taken.get("value", -1)) == value, "the take values the batch the stash's way")
	check(stash.pooled_total() == before + items.size(), "the stash gained exactly the parts")
	check(_loot.corpse_items(_corpse).is_empty(), "the record is empty")
	check(not _loot.corpse_ids().has(_corpse), "a stripped body is not offered again")
	var again: Dictionary = _loot.take_all_from_corpse(_corpse, 0)
	check(not bool(again.get("ok", true)), "a second strip takes nothing")
	check(stash.pooled_total() == before + items.size(), "and books nothing")


# --- the one line ----------------------------------------------------------

func check_summary() -> void:
	var batch := ["wolf_tooth", PELT, PELT]
	var summary := SummaryScript.of(batch)
	var counts: Dictionary = summary.get("counts", {})
	check(int(summary.get("count", -1)) == 3, "three pieces in the batch")
	check(int(counts.get(PELT, 0)) == 2, "two pelts collapse into one count")
	check(int(counts.get("wolf_tooth", 0)) == 1, "and the fang counts once")
	var value := StashScript.value_of(PELT) * 2 + StashScript.value_of("wolf_tooth")
	check(int(summary.get("value", -1)) == value,
		"the batch is worth the keeper price (%d vs %d)" % [int(summary.get("value", -1)), value])
	var names: Array = summary.get("names", [])
	check(names.size() == 2, "two distinct names")
	check(str(names[0]) == "Wolf Pelt" and str(names[1]) == "Wolf Tooth",
		"the names are in catalog order, got %s" % str(names))

	var line := SummaryScript.describe(batch)
	check(line.begins_with("Looted 3"), "the line opens with the count, got %s" % line)
	check(line.contains("Wolf Pelt x2"), "a run of one piece is written as a count")
	check(line.contains("Wolf Tooth x1"), "a single piece is still counted")
	check(line.ends_with("%d G" % value), "the line ends with what it was worth, got %s" % line)

	var wide := ["wolf_pelt", "wolf_bone", "wolf_tooth", "wolf_paw", ICHOR]
	var capped := SummaryScript.describe(wide)
	check(capped.contains("and 1 more"),
		"a batch of five names four and counts the rest, got %s" % capped)
	check(not capped.contains("Warden's Ichor"), "the fifth name is the one dropped")

	check(SummaryScript.describe([]) == "Nothing to loot.", "an empty batch says so")
	check(SummaryScript.describe(["", ""]) == "Nothing to loot.",
		"an empty-id batch is empty too")


# --- what a salvage drop looks like ---------------------------------------

## The wolf's parts and the ichor are drawn as themselves: a real mesh, low
## enough to lie under the name plate, and small enough not to be a sculpture.
func check_silhouettes() -> void:
	for item_id in SALVAGE + [ICHOR]:
		var pickup = _loot.spawn(item_id, Vector3(-60.0, 0.0, 20.0))
		check(pickup != null, "%s drops as a node" % item_id)
		if pickup == null:
			continue
		var triangles := _triangles(pickup)
		check(triangles > 0, "%s has a visible shape" % item_id)
		check(triangles < 40, "%s stays under 40 triangles, got %d" % [item_id, triangles])
		check(_tallest(pickup) < PickupScript.LABEL_HEIGHT,
			"%s lies under its name plate (%.2f m)" % [item_id, _tallest(pickup)])
		pickup.collect()
		await process_frame


func _triangles(node: Node3D) -> int:
	var total := 0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh: Mesh = (child as MeshInstance3D).mesh
			if mesh != null and mesh.get_surface_count() > 0:
				var arrays := mesh.surface_get_arrays(0)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if not indices.is_empty():
					total += indices.size() / 3
				else:
					var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					total += points.size() / 3
		total += _triangles(child)
	return total


func _tallest(node: Node3D) -> float:
	var top := 0.0
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh: Mesh = (child as MeshInstance3D).mesh
			var instance := child as MeshInstance3D
			if mesh != null:
				var box := mesh.get_aabb()
				var at: Vector3 = instance.position + box.position
				top = maxf(top, at.y + box.size.y * 0.5)
		top = maxf(top, _tallest(child))
	return top


# --- the click -------------------------------------------------------------

## The whole gesture: a click on a fallen body starts a channel, the body ducks,
## the channel ends and everything on the body is in the stash with one line said
## about it; a click on a drop gathers the pile it fell in; a click with nothing in
## reach is an attack; and a cancelled click books nothing at all.
func check_hand() -> void:
	var world := StubWorld.new()
	world.name = "StubWorld"
	root.add_child(world)
	var hud := HudScript.new()
	world.add_child(hud)
	var controller := StubController.new()
	world.add_child(controller)
	var loot = LootScript.new()
	world.add_child(loot)
	loot.setup(_warband, _field)
	world.loot = loot
	world.hud = hud
	world.controller = controller

	var body := StubBody.new()
	body.name = "Looter"
	world.add_child(body)
	body.global_position = Vector3(400.0, 0.0, 400.0)

	var hand = HandScript.new()
	hand.name = "LootHand"
	world.add_child(hand)
	hand.setup(world)
	check(is_equal_approx(hand._reach, StubWorld.LOOT_REACH),
		"the hand reads the world's own reach (%.2f)" % hand._reach)

	var stash: WarbandStash = _warband.stash
	var corpse := StubCorpse.new()
	corpse.carried = [PELT, "wolf_tooth"]
	_field.add_child(corpse)
	corpse.global_position = body.global_position + Vector3(0.7, 0.0, 0.0)
	var corpse_id := loot.register_corpse(corpse)
	check(corpse_id != 0, "the fallen body is registered")
	var pelts_before := stash.pooled_count(PELT)
	var fangs_before := stash.pooled_count("wolf_tooth")

	check(hand.try_click(body, corpse.global_position), "a click on the body begins a loot")
	check(body.crouching, "the body ducks over the corpse")
	check(hand.active() and hand.target_kind() == "corpse", "the channel names what it works")
	check(hand.progress() < 0.1, "the channel starts at nothing")
	check(not hand.try_click(body, corpse.global_position), "a second click opens no second channel")

	hand.tick(0.4)
	check(hand.active(), "the channel is still running mid-way")
	check(hand.progress() > 0.3 and hand.progress() < 0.9,
		"progress tracks the beat, got %.2f" % hand.progress())
	hand.tick(0.6)
	check(not hand.active(), "the channel ends")
	check(not body.crouching, "the body stands up again")
	check(loot.corpse_items(corpse_id).is_empty(), "the body was emptied")
	check(stash.pooled_count(PELT) == pelts_before + 1, "the pelt is a stash row")
	check(stash.pooled_count("wolf_tooth") == fangs_before + 1, "and so is the fang")
	check(controller.refreshed.has(3), "the looted body was re-dressed")
	var summary := hand.last_summary()
	check(summary.contains("Wolf Pelt") and summary.contains("Looted 2"),
		"one line says what came up, got %s" % summary)
	var status_label: Label = hud.get("_status_label")
	check(status_label != null and status_label.text == summary,
		"the HUD raised that line")

	# The ground is bare: a click is an attack again, and the hand must say so.
	hand.tick(0.3)
	check(not hand.try_click(body, corpse.global_position),
		"a click on a stripped body in bare ground is not a loot")

	# A guest never books the host's loot.
	var guest_corpse := StubCorpse.new()
	guest_corpse.carried = ["wolf_bone"]
	_field.add_child(guest_corpse)
	guest_corpse.global_position = body.global_position + Vector3(0.6, 0.0, 0.0)
	world._client = true
	check(not hand.try_click(body, guest_corpse.global_position),
		"a guest's click falls through to an attack")
	check(not hand.active(), "and no channel opened")
	world._client = false

	# A drop, and the pile it fell in. One click gathers the pile, not one piece.
	var drop = loot.spawn(ICHOR, body.global_position + Vector3(0.9, 0.0, 0.0))
	var pile = loot.spawn("wolf_bone", body.global_position + Vector3(1.3, 0.0, 0.4))
	var far = loot.spawn("wolf_paw", body.global_position + Vector3(8.0, 0.0, 0.0))
	check(drop != null and pile != null and far != null, "the drops are real nodes")
	hand.tick(0.3)
	check(hand.try_click(body, drop.global_position), "a click on a drop begins a loot")
	check(hand.target_kind() == "drop", "the channel names the drop")
	check(body.crouching, "the body ducks over a drop too")
	hand.tick(1.0)
	check(drop.collected and pile.collected, "the pile around the clicked drop was taken")
	check(not far.collected, "a drop across the clearing was not")
	check(stash.pooled_count(ICHOR) >= 1, "the ichor is in the shared stash")
	check(hand.last_summary().contains("Warden's Ichor"),
		"the line names the reagent, got %s" % hand.last_summary())

	# Cancelled: a blow, a panel or a walk takes nothing.
	var second := StubCorpse.new()
	second.carried = ["wolf_paw"]
	_field.add_child(second)
	second.global_position = body.global_position + Vector3(0.6, 0.0, 0.0)
	var second_id := loot.register_corpse(second)
	var banked := stash.pooled_total()
	hand.tick(0.3)
	check(hand.try_click(body, second.global_position), "a second body can be worked")
	hand.cancel()
	check(not hand.active() and not body.crouching, "cancel straightens the body")
	check(stash.pooled_total() == banked, "and books nothing")
	check(loot.corpse_items(second_id) == ["wolf_paw"], "the corpse is untouched")

	# A body that walks off the spot cannot still be working it.
	hand.tick(0.3)
	check(hand.try_click(body, second.global_position), "the channel opens again")
	body.global_position += Vector3(0.0, 0.0, HandScript.LEAVE_DISTANCE + 1.0)
	hand.tick(0.1)
	check(not hand.active() and not body.crouching, "walking away breaks the channel")
	check(stash.pooled_total() == banked, "and books nothing")
	body.global_position -= Vector3(0.0, 0.0, HandScript.LEAVE_DISTANCE + 1.0)

	# A body that goes down mid-channel drops the work.
	hand.tick(0.3)
	check(hand.try_click(body, second.global_position), "the channel opens once more")
	body.downed = true
	hand.tick(0.1)
	check(not hand.active() and not body.crouching, "going down breaks the channel")
	check(stash.pooled_total() == banked, "and books nothing")
	check(not hand.try_click(body, second.global_position),
		"a downed body cannot start a loot")
	body.downed = false

	# A blow that puts the body down ends the channel on the frame it lands, not a
	# tick later.
	hand.tick(0.3)
	check(hand.try_click(body, second.global_position), "the channel opens once more")
	body.downed_started.emit(1)
	check(not hand.active() and not body.crouching,
		"the body's own downed signal breaks the channel")
	check(stash.pooled_total() == banked, "and books nothing")

	# Not a body at all: the hand only duck-types, and only a crouching body loots.
	var prop := Node3D.new()
	world.add_child(prop)
	check(not hand.try_click(prop, second.global_position), "a prop is not a looter")
	check(not hand.try_click(null, second.global_position), "no body, no loot")
	check(not hand.try_click(body, Vector3(9000.0, 0.0, 9000.0)),
		"nothing within reach is an attack")
	check(stash.pooled_total() == banked, "no refused click booked anything")

	world.queue_free()
	await process_frame


# --- the wardens' ichor ----------------------------------------------------

## One warden in three carries a vial of its own ichor, and it is the variant's
## property, not a roll at the kill: the table slot decides it, so the same body
## always carries the same kit and a clearing has both kinds in it.
func check_watchers() -> void:
	check(StateScript.ITEMS.has(ICHOR), "the ichor is a catalog piece")
	var field := Node3D.new()
	field.name = "WatcherField"
	root.add_child(field)
	var carriers := 0
	var empty := 0
	for index in WATCHER_SAMPLE:
		var watcher = WatcherScript.new()
		watcher.name = "Watcher%d" % index
		watcher.mob_id = "hollow_warden"
		watcher.health_pool = WatcherScript.HARDENED_HEALTH
		watcher.position = Vector3(4.0 * float(index), 0.1, 0.0)
		field.add_child(watcher)
		var items: Array[String] = watcher.gear_items()
		var carries := items.has(ICHOR)
		var slot := WatcherScript.variant_index_for(WatcherScript.WARDEN_ID, watcher.name)
		check(slot == WatcherScript.variant_index_for(WatcherScript.WARDEN_ID, watcher.name),
			"%s's slot is the same every time it is asked" % watcher.name)
		check(carries == (slot % WatcherScript.ICHOR_EVERY == WatcherScript.ICHOR_EVERY - 1),
			"%s carries ichor off its variant, got %s" % [watcher.name, str(items)])
		if carries:
			carriers += 1
		else:
			empty += 1
		# The vial is carried, not worn: the corpse lists it and the bandage rule
		# is untouched beside it.
		check(watcher.carried.has(ICHOR) == carries,
			"%s lists the vial as carried kit when it has one" % watcher.name)
	check(carriers >= 3 and empty >= 3,
		"a warband of wardens has both kinds: %d carry ichor, %d do not" % [carriers, empty])
	field.queue_free()
	await process_frame
