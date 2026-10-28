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
	await check_throw()

	print("WARBAND_RANGED_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)


func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)


func close_cards() -> void:
	if game != null and game.card != null and game.card.is_open():
		game.card.close()


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
