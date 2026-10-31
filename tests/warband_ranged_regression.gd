extends SceneTree
## GHOST OF THE WARBAND: bows, arrows and the crosshair.
##
## The warband mode had no projectile spawner. A body could equip a bow, draw it,
## let go - and nothing existed: `combat.shot` was listened to by the frontier and
## the arena, and by nobody here. The camera was also its own design: no shoulder
## offset, and an eye that looked *at* the body's head, so the reticle sat on the
## character you were aiming past. This test owns both halves of that:
##
##   1. **A shot exists.** LMB held and released puts one physical arrow in the
##      world, carrying the bow's own charge damage.
##   2. **It goes where the crosshair points.** The arrow starts on the centre
##      view ray and flies down it - the ray the controller aims the body with is
##      the ray the missile travels.
##   3. **It bites.** A watcher standing on that ray loses health to it.
##   4. **The shoulder.** `X` crosses the eye to the other side of the body (the
##      frontier's 0.70 m, eased), and the reticle ray still resolves its own aim
##      point afterwards.
##   5. **Thrown steel.** T held and released spawns a real thrown blade.
##   6. **A quiver, not a decoration.** Every loosed arrow takes a shaft out of
##      the party's shared quiver, an empty quiver keeps the string down (and says
##      so on the HUD), and a bought bunch puts the bow back in the body's hands.
##   7. **Archers carry arrows.** A trail archer's corpse is a resupply: the bow
##      it fired and the shafts it was drawing from are on the body.
##
## The pair stand on a plate hung in empty air above the camp, so no tree, prop or
## cage bar can be the thing that stopped an arrow.

const WORLD := "res://scenes/warband_world.tscn"
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const CombatScript = preload("res://scripts/combat.gd")

const TEST_SAVE := "user://warband_ranged_state.json"
const WARBAND_SAVE := "user://warband_ranged_warband.json"
## The plate the range stands on, and how far out the dummy is.
const PLATE_Y := 40.0
const RANGE := 12.0
const SETTLE_FRAMES := 40

var game
var warband
var controller
var body
var target
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("RANGED_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	var state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	var flow = root.get_node("GameFlow")
	flow.active = false
	# The town start: no cages, no lesson, no card - this is the ranged system.
	flow.world_start = "town"

	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(0.8).timeout
	close_cards()
	controller = game.controller
	check(controller != null, "the world owns a possession controller")

	await build_range()
	await settle(SETTLE_FRAMES)
	await check_bow()
	await check_shoulder()
	await check_quiver()
	await check_throw()
	await check_archer_drop()
	await check_band_breaks_off()

	print("WARBAND_RANGED_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)


func close_cards() -> void:
	# Nothing in the warband pauses the tree any more, so there is no card to
	# close before the fight: the opening teaches with tips.
	pass


func settle(frames: int) -> void:
	for index in frames:
		await physics_frame


# --- the range -------------------------------------------------------------

## A plate in empty air, one body with a bow on it, one watcher straight down the
## view. Nothing in the camp can stand between them.
func build_range() -> void:
	var plate := StaticBody3D.new()
	plate.name = "RangedPlate"
	plate.collision_layer = 1
	plate.collision_mask = 0
	plate.position = Vector3(0.0, PLATE_Y - 0.5, 0.0)
	game.add_child(plate)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(120.0, 1.0, 120.0)
	shape.shape = box
	plate.add_child(shape)

	var merc: int = controller.merc_for_peer(1)
	check(merc > 0, "the soul starts in a body")
	body = controller.body_of(merc)
	check(body != null, "and that body is on the field")
	body.global_position = Vector3(0.0, PLATE_Y + 0.3, 0.0)
	# The camera looks down -Z at yaw 0, which is where the dummy stands.
	controller.camera_rig.yaw = 0.0
	controller.camera_rig.pitch = 0.08
	controller.camera_rig.side = 1
	controller.camera_rig._offset = 0.70

	target = WatcherScript.new()
	target.name = "RangedDummy"
	target.mob_id = "hollow_warden"
	target.health_pool = 400.0
	target.position = Vector3(0.0, PLATE_Y + 0.3, -RANGE)
	game.add_child(target)
	target.global_position = Vector3(0.0, PLATE_Y + 0.3, -RANGE)

	# The bow, worn through the same roster path every gear change uses.
	warband.stash.add("bow_twig", 1)
	var worn: Dictionary = warband.equip_merc(merc, "main", "bow_twig")
	check(bool(worn.get("ok", false)), "the body can wear a bow (%s)" % str(worn.get("message", "")))
	controller.refresh_gear(merc)
	await settle(2)
	check(str(body.rig.weapon) == "bow", "and the rig is holding it (%s)" % str(body.rig.weapon))


# --- 1/2/3. the shot -------------------------------------------------------

func check_bow() -> void:
	for index in 4:
		await physics_frame
	var before: int = game.projectiles.size()

	# Stand the dummy where the crosshair actually points. A shoulder camera's
	# reticle is off the body's own axis, so "in front of the body" is not the
	# same place as "under the crosshair".
	var look: Dictionary = controller.aim_sample()
	var look_origin: Vector3 = look["origin"]
	var look_view: Vector3 = (look["point"] - look_origin).normalized()
	var seen: Vector3 = look["point"]
	var reach: float = look_origin.distance_to(seen)
	var stand: Vector3 = look_origin + look_view * maxf(reach - 6.0, 6.0)
	target.global_position = Vector3(stand.x, float(PLATE_Y) + 0.3, stand.z)
	await settle(8)

	# Now the ray must be on the dummy, and the shot must leave down that ray.
	var aim: Dictionary = controller.aim_sample()
	var origin: Vector3 = aim["origin"]
	var point: Vector3 = aim["point"]
	var view: Vector3 = (point - origin).normalized()
	check((point - (target as Node3D).global_position).length() < 2.0,
		"the crosshair is on the dummy (%.2f m from its feet)"
		% (point - (target as Node3D).global_position).length())

	var quiver_before: int = warband.arrows()
	check(quiver_before > 0,
		"the band opens with shafts in the shared quiver (%d)" % quiver_before)
	check(game.hud.purse_line().contains("%d arrows" % quiver_before),
		"the strip counts the quiver beside the purse (%s)" % game.hud.purse_line())

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	controller._mouse_press(press)
	check(str(body.rig.phase) in ["DRAWING", "HOLDING"],
		"LMB draws the bow (%s)" % str(body.rig.phase))
	# Hold the string to full draw, as a player does before letting go.
	await create_timer(0.7).timeout
	check(float(body.rig.draw_amount) > 0.9,
		"and the string comes to full draw (%.2f)" % float(body.rig.draw_amount))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	controller._mouse_release(release)
	await physics_frame
	await physics_frame

	check(game.projectiles.size() == before + 1,
		"a released string puts an arrow in the world (%d -> %d)"
		% [before, game.projectiles.size()])
	check(warband.arrows() == quiver_before - 1,
		"and one shaft leaves the quiver for it (%d -> %d)"
		% [quiver_before, warband.arrows()])
	var arrow = null
	if game.projectiles.size() > before:
		arrow = game.projectiles[game.projectiles.size() - 1]
	check(arrow != null and bool(arrow.get("flying")), "and it is a flying missile")
	if arrow == null:
		return
	check(body.combat.launch_origin.is_finite(),
		"the shot is relocated onto the camera ray, not fired from the bow")
	var off_ray: float = ((arrow.global_position - origin).cross(view)).length()
	check(off_ray < 0.06, "the arrow starts on the centre view ray (%.3f m off)" % off_ray)
	var along: float = arrow.velocity.normalized().dot(view)
	check(along > 0.999, "and flies down it (%.5f dot)" % along)
	var damage: float = float(arrow.get("damage"))
	check(damage > 0.0, "with the bow's own charge damage (%.1f)" % damage)

	var health_before := float(target.health)
	await create_timer(0.7).timeout
	check(float(target.health) < health_before,
		"the arrow bites the watcher on the ray (%.0f -> %.0f)"
		% [health_before, float(target.health)])
	print("RANGED_SHOT off_ray=%.3f dot=%.5f damage=%.1f health=%.0f"
		% [off_ray, along, damage, float(target.health)])


# --- 4. the shoulder -------------------------------------------------------

func check_shoulder() -> void:
	var start: Dictionary = controller.camera_rig.aim_ray()
	var side_before: int = controller.camera_rig.side
	var keys := InputEventKey.new()
	keys.keycode = KEY_X
	keys.pressed = true
	controller._command(keys)
	check(controller.camera_rig.side == -side_before,
		"X swaps the shoulder (%d -> %d)" % [side_before, controller.camera_rig.side])
	await settle(SETTLE_FRAMES)
	var moved: Dictionary = controller.camera_rig.aim_ray()
	var travel: float = moved["origin"].distance_to(start["origin"])
	check(travel > 1.0 and travel < 2.0,
		"and the eye crosses to the other side of the body (%.2f m)" % travel)

	# The crosshair is still the aim: the point the controller would hand a shot
	# lies on the projected centre ray, whichever shoulder the eye is over.
	var aim: Dictionary = controller.aim_sample()
	var origin: Vector3 = aim["origin"]
	var point: Vector3 = aim["point"]
	var offset: float = ((point - origin).normalized() - moved["direction"]).length()
	check(offset < 0.001, "the aim point is the reticle's own ray (%.5f off)" % offset)
	# The body is off the centre line now: the reticle is not on your own head.
	var to_body: Vector3 = (body.global_position + Vector3.UP * 1.65 - origin).normalized()
	check(to_body.dot(moved["direction"]) < 0.999,
		"the eye is not aimed at its own body any more (%.4f dot)" % to_body.dot(moved["direction"]))
	controller.camera_rig.swap()
	await settle(SETTLE_FRAMES)
	print("RANGED_SHOULDER travel=%.2f" % travel)


# --- 5. thrown steel -------------------------------------------------------

func check_throw() -> void:
	var merc: int = controller.merc_for_peer(1)
	warband.stash.add("dagger_ironwood", 1)
	var worn: Dictionary = warband.equip_merc(merc, "main", "dagger_ironwood")
	check(bool(worn.get("ok", false)), "the body can wear a dagger")
	controller.refresh_gear(merc)
	await settle(3)
	var before: int = game.projectiles.size()
	var keys := InputEventKey.new()
	keys.keycode = KEY_T
	keys.pressed = true
	controller._command(keys)
	var release := InputEventKey.new()
	release.keycode = KEY_T
	release.pressed = false
	controller._input(release)
	await physics_frame
	await physics_frame
	check(game.projectiles.size() == before + 1,
		"a thrown blade is a real missile too (%d -> %d)"
		% [before, game.projectiles.size()])
	if game.projectiles.size() > before:
		var thrown = game.projectiles[game.projectiles.size() - 1]
		check(str(thrown.get("weapon")) == "dagger",
			"and it is the dagger that left the hand (%s)" % str(thrown.get("weapon")))


# --- 6. the empty quiver ---------------------------------------------------

## A bow with nothing behind it is a stick. The quiver is spent down to nothing,
## a press is refused out loud instead of silently, and a keeper's bunch - the
## same write the vendor board makes - puts the string back up.
func check_quiver() -> void:
	await settle(SETTLE_FRAMES)
	check(str(body.rig.weapon) == "bow",
		"the body still holds the bow for the quiver run (%s)" % str(body.rig.weapon))

	var spent: int = warband.take_arrows(warband.arrows())
	check(spent > 0 and not warband.has_arrows(),
		"the quiver can be emptied (%d shafts spent, %d left)" % [spent, warband.arrows()])

	var refusals := [0]
	controller.draw_refused.connect(func(_peer: int) -> void: refusals[0] += 1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	await settle(4)
	var dry_before: int = game.projectiles.size()
	controller._mouse_press(press)
	await physics_frame
	check(bool(body.combat.quiver_empty()), "an empty quiver is the body's own state")
	check(str(body.rig.phase) not in ["DRAWING", "HOLDING"],
		"a dry bow does not draw (%s)" % str(body.rig.phase))
	check(game.projectiles.size() == dry_before, "and no arrow leaves the world")
	check(refusals[0] == 1, "the press says why (%d line(s))" % int(refusals[0]))
	check(game.hud.status_line().contains("Out of arrows"),
		"and the HUD says where to get more (%s)" % game.hud.status_line())
	controller._mouse_release(release)
	await physics_frame
	check(game.projectiles.size() == dry_before, "releasing a string that never drew looses nothing")

	# A bunch off a keeper's shelf: the same `add_arrows` the vendor board calls.
	warband.add_arrows(10)
	await settle(SETTLE_FRAMES)
	check(not bool(body.combat.quiver_empty()), "a bought bunch fills the quiver (%d)" % warband.arrows())
	var loaded_before: int = warband.arrows()
	controller._mouse_press(press)
	await settle(4)
	check(str(body.rig.phase) in ["DRAWING", "HOLDING"],
		"and the string comes up again (%s)" % str(body.rig.phase))
	controller._mouse_release(release)
	await settle(4)
	check(warband.arrows() == loaded_before - 1,
		"the second shot spends its own shaft (%d -> %d)" % [loaded_before, warband.arrows()])
	# The nock-and-recover clock (0.95 s) has to run out before the next section
	# asks the hands for anything else: this test's neighbour throws a blade, and
	# a bow still recovering refuses the throw.
	await create_timer(1.2).timeout
	print("RANGED_QUIVER spent=%d loaded=%d" % [spent, warband.arrows()])


# --- 7. what an archer leaves behind ---------------------------------------

## The trail's archers are the wood's only resupply. A dead one carries the bow it
## was firing and a bunch of its own shafts, and the world registers the body's
## kit so the corpse screen can hand them over.
func check_archer_drop() -> void:
	var archer = load("res://scripts/warband/watcher_archer.gd").new()
	archer.name = "RangedArcherProbe"
	archer.mob_id = "hollow_warden"
	game.add_child(archer)
	await settle(2)
	check(is_instance_valid(archer), "an archer body stands up")
	var kit: Array = []
	if is_instance_valid(archer) and archer.has_method("gear_items"):
		kit = archer.gear_items()
	var shafts := 0
	for entry in kit:
		if str(entry) == "arrow":
			shafts += 1
	check(shafts >= 10 and shafts <= 20,
		"the archer's corpse carries its own quiver of 10-20 shafts (%d)" % shafts)
	check(kit.has("bow_twig"), "and the bow it was firing (%s)" % str(kit))
	check(kit.has("bandage_linen"), "beside the dressing every warden wears")
	var corpse := int(game.loot.register_corpse(archer))
	check(corpse != 0, "the world registers the body as a container")
	var on_body: Array = game.loot.corpse_items(corpse)
	check(on_body.count("arrow") == shafts,
		"and books every shaft on it (%d)" % on_body.count("arrow"))
	# The bunch is the body's own, never a roll at the kill: across a trail's worth
	# of archer names every quiver lands inside 10-20, and both bounds occur.
	var counts: Array[int] = []
	for index in 60:
		counts.append(int(archer.carried_arrows(archer.mob_id, "WardenArcher%d" % index)))
	check(counts.min() == 10 and counts.max() == 20,
		"archer quivers span 10-20 shafts, got %d-%d" % [counts.min(), counts.max()])
	archer.queue_free()
	print("RANGED_ARCHER_DROP kit=%s" % str(kit))


# --- 8. the band breaks off ------------------------------------------------

## The AI squad forks after its own fight, and the player hears about it.
##
## The notifier is proved here because this test owns the one harness in the suite
## that runs the real world scene with a real squad, the real guard list and the
## real HUD: the dummy is stood next to an *ally* (not next to the soul, who is up
## on the plate), the squad's own `_nearest_watcher` picks it up, and everything
## after that is what a player reads.
const BEARINGS := ["ahead", "ahead-left", "ahead-right", "left", "right",
	"back-left", "back-right", "behind"]

func check_band_breaks_off() -> void:
	var ally = null
	var ally_id := 0
	for raw_id in game.squad.squad_ids:
		var merc_id := int(raw_id)
		var candidate = game.controller.body_of(merc_id)
		if candidate == null or not is_instance_valid(candidate) or candidate == body:
			continue
		if not bool(candidate.get("alive")) or bool(candidate.get("downed")):
			continue
		ally = candidate
		ally_id = merc_id
		break
	check(ally != null and ally_id > 0, "the warband has a body the AI drives")
	if ally == null:
		return
	var hunter = WatcherScript.new()
	hunter.name = "AggroDummy"
	hunter.mob_id = "hollow_warden"
	hunter.health_pool = 400.0
	game.add_child(hunter)
	hunter.global_position = (ally as Node3D).global_position + Vector3(6.0, 0.0, 0.0)
	game.guards.append(hunter)
	var engaged: Array = []
	for index in 300:
		await physics_frame
		if index < 10:
			continue
		engaged = game.squad.engaged_allies()
		if not engaged.is_empty():
			break
	check(not engaged.is_empty(), "an ally that goes in on something is reported")
	if engaged.is_empty():
		return
	var report: Dictionary = engaged[0]
	check(str(report["name"]) == warband.roster.name_of(int(report["merc_id"])),
		"the report names the ally (%s)" % str(report["name"]))
	check(str(report["threat"]) == str(hunter.get_display_name()),
		"and what it went in on (%s)" % str(report["threat"]))
	check(int(report["distance"]) > 0,
		"with how far it is from the soul (%d m)" % int(report["distance"]))
	check(str(report["bearing"]) in BEARINGS,
		"and which way the player would turn (%s)" % str(report["bearing"]))
	check(game.hud.aggro_line().contains("IN THE FIGHT"),
		"the HUD keeps the fight on the screen (%s)" % game.hud.aggro_line())
	check(game.hud.aggro_line().contains(str(report["name"])),
		"and names the ally in it")
	var said: String = game.hud.status_line()
	check(said.contains("break off") or said.contains("breaks off"),
		"the break-off was said once in the banner (%s)" % said)
	print("RANGED_AGGRO name=%s threat=%s m=%d bearing=%s"
		% [str(report["name"]), str(report["threat"]), int(report["distance"]),
			str(report["bearing"])])

	# Out of reach is out of the fight: the line clears and the band is told the
	# ally is back. The dummy is walked off the field rather than killed, so no
	# kill payout can be the thing the banner was about.
	hunter.global_position = (ally as Node3D).global_position + Vector3(220.0, 0.0, 0.0)
	for index in 40:
		await physics_frame
		if game.squad.engaged_allies().is_empty():
			break
	check(game.squad.engaged_allies().is_empty(), "an ally out of the fight is no longer reported")
	check(game.hud.aggro_line().is_empty(),
		"and the standing line is put away (%s)" % game.hud.aggro_line())
	check(game.hud.status_line().contains("back with the band"),
		"the HUD says the ally came back (%s)" % game.hud.status_line())
	hunter.queue_free()
