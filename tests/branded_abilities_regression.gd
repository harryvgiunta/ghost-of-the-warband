extends SceneTree
## GHOST OF THE WARBAND - the six Sacramental Cruor brands, fired on real bodies.
##
## Every check runs on authoritative `ArenaActor` bodies in a real scene and
## measures the health the blow actually removed, not the number a helper
## returned. The barrage is proven through the same `fired` event the arena's
## arrow spawner listens to: the test installs that listener itself and flies
## real `Arrow` nodes, so a shaft that would not hit a body in the game cannot
## pass here either.

const Actor = preload("res://scripts/warband/warband_body.gd")
const Arrow = preload("res://scripts/arrow.gd")
const Combat = preload("res://scripts/combat.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const RunnerScript = preload("res://scripts/warband/branded_runner.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## The blow a victim did not land itself: `take_damage` refuses `source == slot`.
const KILLER_SLOT := 9
## Victims start with a deep pool, so six shafts and a blast both fit and the
## tier comparison measures damage instead of a puddle capped at 100.
const POOL_HEALTH := 400.0
const TIER_LOW := Contracts.CruorTier.T1_RITUAL_TALLOW
const TIER_HIGH := Contracts.CruorTier.T3_COAGULATED_CRUOR

var failures := 0
var checks := 0
var scene: Node3D
var cruor
var caster
var target_a
var target_b
var target_c
var killer
var runner
var _fired_events := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("BRANDED_FAIL  ", message)

func _frames(count: int) -> void:
	for frame in count:
		await physics_frame

## One real frame's worth of wall clock: a `SceneTreeTimer` and the ability's
## own `_process` clock advance on the same frame loop.
func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

func box(size: Vector3, centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = centre
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	scene.add_child(body)
	return body

## A live authoritative fighter. `slot` must be set before the node enters the
## tree: the combat source id is bound in `_ready`.
func make_body(slot: int, point: Vector3):
	var body = Actor.new()
	body.slot = slot
	body.authoritative = true
	body.max_health = POOL_HEALTH
	scene.add_child(body)
	body.configure(slot, "Branded %d" % slot, point)
	return body

## Puts a body back on its feet at `point` with a full pool, a full stamina bar
## and no ward, so every ability is measured against the same fresh victim.
func place(body, point: Vector3) -> void:
	body.max_health = POOL_HEALTH
	body.spawn_point = point
	body.revive()

func aim(body, point: Vector3) -> void:
	body.combat.aim_point = point

## Brands a real item through the altar's own verb and attaches the payload the
## altar wrote, so the runner is proven against `Warband.cruor.brand_of()`.
func _equip(ability: String, item: String, tier: int) -> void:
	cruor.add(tier, 10)
	var result: Dictionary = cruor.brand(item, tier)
	check(bool(result["ok"]), "the altar brands %s at tier %d: %s"
		% [item, tier, str(result.get("message", ""))])
	var payload: Dictionary = cruor.brand_of(item)
	check(str(payload.get("ability", "")) == ability, "%s grants %s" % [item, ability])
	runner.attach(caster, payload)
	check(runner.brand() == payload, "the runner holds the altar's own payload")

## The scene's arrow spawner, cut down to what the arena's `_on_fired` does: the
## shooter's bow decides the damage, the shaft flies and the impact lands.
func _on_fired(slot: int, origin: Vector3, direction: Vector3, speed: float,
		charge: float) -> void:
	_fired_events += 1
	var damage := Combat.damage_for(caster.rig.bow_index, charge, caster.rig.ranged_scale())
	var arrow := Arrow.new()
	arrow.source_id = slot
	arrow.hit_mask = 1 | 4
	arrow.authoritative_damage = true
	arrow.shooter = caster
	scene.add_child(arrow)
	arrow.launch(origin, direction, speed, damage, [caster.get_rid()])

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	box(Vector3(120, 1, 160), Vector3(0, -0.5, 0))
	cruor = root.get_node("Warband").cruor
	cruor.clear()

	caster = make_body(1, Vector3.ZERO)
	caster.fired.connect(_on_fired)
	target_a = make_body(2, Vector3(0, 0, 6))
	target_b = make_body(3, Vector3(2, 0, 4))
	target_c = make_body(4, Vector3(-2, 0, 4))
	killer = make_body(KILLER_SLOT, Vector3(0, 0, 24))
	runner = RunnerScript.new()
	caster.add_child(runner)
	await _frames(4)

	await check_barrage()
	await check_cleave()
	await check_rend()
	await check_storm()
	await check_cone()
	await check_ward()
	await check_refusals()
	await check_tier_scaling()

	print("BRANDED_ABILITIES_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)

# --- arrow_barrage ----------------------------------------------------------

func check_barrage() -> void:
	_equip("arrow_barrage", "bow_short", TIER_HIGH)
	caster.rig.set_weapon("bow")
	place(caster, Vector3.ZERO)
	place(target_a, Vector3(0, 0, 6))
	place(target_b, Vector3(9, 0, 0))
	place(target_c, Vector3(-9, 0, 0))
	await _frames(4)
	aim(caster, target_a.global_position + Vector3.UP * 1.1)
	_fired_events = 0
	var before: float = target_a.health
	check(runner.activate(), "Rapid-Fire Arrow Barrage fires")
	var cost := float(runner.last_effect().get("cost", 0.0))
	check(is_equal_approx(float(caster.stamina), 1000.0 - cost),
		"the barrage spends its scaled cost")
	await _seconds(1.4)
	check(_fired_events == 6, "the barrage emits exactly six shafts (got %d)" % _fired_events)
	check(target_a.health < before - 0.5, "at least one shaft lands on the body in the line")
	check(is_equal_approx(target_b.health, POOL_HEALTH) and is_equal_approx(target_c.health, POOL_HEALTH),
		"no shaft lands off the aim line")
	check(int(runner.last_effect().get("arrows", 0)) == 6, "the report counts six shafts")

# --- shockwave_cleave -------------------------------------------------------

func check_cleave() -> void:
	_equip("shockwave_cleave", "sword_great", TIER_HIGH)
	caster.rig.set_weapon("sword")
	place(caster, Vector3.ZERO)
	place(target_a, Vector3(0, 0, 1.6))
	place(target_b, Vector3(1.2, 0, 4.2))
	place(target_c, Vector3(-1.2, 0, 4.2))
	await _frames(4)
	aim(caster, Vector3(0, 1.1, 6))
	var stamina_before: float = caster.stamina
	var expected_cost := Branded.scaled(Branded.stamina_cost("shockwave_cleave"), TIER_HIGH)
	check(runner.activate(), "Shockwave Cleave fires")
	check(is_equal_approx(stamina_before - caster.stamina, expected_cost),
		"the cleave spends %.1f stamina" % expected_cost)
	await _seconds(0.9)
	check(target_a.health < POOL_HEALTH - 0.5, "the body the blade crossed is cut")
	check(target_b.health < POOL_HEALTH - 0.5 and target_c.health < POOL_HEALTH - 0.5,
		"the blast reaches both bodies standing inside three metres of the impact")
	check(target_a.health < target_b.health,
		"the body the blade crossed takes more than the ring alone")

# --- rending_strike ---------------------------------------------------------

func check_rend() -> void:
	_equip("rending_strike", "dagger_iron", TIER_HIGH)
	caster.rig.set_weapon("sword")
	place(caster, Vector3.ZERO)
	place(target_a, Vector3(0, 0, 1.2))
	place(target_b, Vector3(1.0, 0, 1.0))
	place(target_c, Vector3(0, 0, -8))
	await _frames(4)
	aim(caster, Vector3(0, 1.1, 6))
	check(runner.activate(), "Rending Strike fires")
	var bleed := float(runner.last_effect().get("bleed", 0.0))
	check(bleed > 0.0, "the wound carries a bleed number")
	await _seconds(3.6)
	check(int(runner.last_effect().get("ticks", 0)) == 6,
		"both struck bodies bleed three times each (got %d)" % int(runner.last_effect().get("ticks", 0)))
	check(target_a.health < POOL_HEALTH - bleed * 3.0,
		"the three beats of bleed cost health on top of the cut")
	check(is_equal_approx(target_c.health, POOL_HEALTH), "a body the cut never crossed does not bleed")

# --- ember_storm ------------------------------------------------------------

func check_storm() -> void:
	_equip("ember_storm", "staff_fire", TIER_HIGH)
	place(caster, Vector3.ZERO)
	place(target_a, Vector3(0, 0, 5.4))
	place(target_b, Vector3(1.4, 0, 6.2))
	place(target_c, Vector3(0, 0, -7))
	await _frames(4)
	aim(caster, Vector3(0, 1.1, 6))
	check(runner.activate(), "Ember Storm fires")
	await _seconds(0.3)
	check(target_a.health < POOL_HEALTH - 0.5 and target_b.health < POOL_HEALTH - 0.5,
		"the star comes apart on both bodies at the aim point")
	check(is_equal_approx(target_c.health, POOL_HEALTH),
		"a body seven metres behind the caster is outside the blast")
	check(int(runner.last_effect().get("victims", 0)) == 2, "the storm reports the two bodies it covered")

# --- hellfire_cone ----------------------------------------------------------

func check_cone() -> void:
	_equip("hellfire_cone", "focus_skull", TIER_HIGH)
	place(caster, Vector3.ZERO)
	place(target_a, Vector3(0, 0, 2.6))
	place(target_b, Vector3(1.6, 0, 2.4))
	place(target_c, Vector3(-2.6, 0, 1.0))
	await _frames(4)
	aim(caster, Vector3(0, 1.1, 5))
	check(runner.activate(), "Hellfire Cone fires")
	await _seconds(0.2)
	check(target_a.health < POOL_HEALTH - 0.5 and target_b.health < POOL_HEALTH - 0.5,
		"both bodies inside ninety degrees burn")
	check(is_equal_approx(target_c.health, POOL_HEALTH),
		"a body standing sixty-nine degrees off the aim is outside the cone")
	check(target_a.combat.stagger_time > 0.5,
		"the cone holds the body it crosses (%.2f s)" % target_a.combat.stagger_time)

# --- blood_ward -------------------------------------------------------------

func check_ward() -> void:
	_equip("blood_ward", "focus_tome", TIER_HIGH)
	place(caster, Vector3.ZERO)
	await _frames(4)
	check(runner.activate(), "Blood Ritual Ward fires")
	check(caster.ward_seconds > 0.0, "the body carries a real ward")
	var before_health: float = caster.health
	var before_stamina: float = caster.stamina
	caster.receive_melee(40.0, KILLER_SLOT, caster.global_position + Vector3(5, 0, 0))
	var taken: float = before_health - caster.health
	var paid: float = before_stamina - caster.stamina
	check(is_equal_approx(taken, 20.0), "half of a 40 hit reaches health (%.2f)" % taken)
	check(is_equal_approx(paid, 40.0), "the other half is paid in stamina (%.2f)" % paid)

# --- refusals ---------------------------------------------------------------

func check_refusals() -> void:
	# An unbranded body asks for a sigil it does not have.
	runner.attach(caster, {})
	var plain: Dictionary = runner.can_activate()
	check(not bool(plain["ok"]), "an unbranded body refuses")
	check(str(plain["reason"]).contains("no brand"), "the refusal names the missing brand: %s" % plain["reason"])
	check(not runner.activate(), "an unbranded body cannot fire")

	# A second press inside the cooldown is refused without spending stamina.
	_equip("rending_strike", "dagger_iron", TIER_HIGH)
	caster.rig.set_weapon("sword")
	place(caster, Vector3.ZERO)
	await _frames(2)
	aim(caster, Vector3(0, 1.1, 6))
	check(runner.activate(), "the rending sigil is ready again after a rebrand")
	var armed: float = caster.stamina
	var cooldown: Dictionary = runner.can_activate()
	check(not bool(cooldown["ok"]), "a second activation is refused by the cooldown")
	check(str(cooldown["reason"]).contains("ready in"), "the refusal counts the cooldown: %s" % cooldown["reason"])
	check(not runner.activate(), "the refused press does nothing")
	check(is_equal_approx(caster.stamina, armed), "the refused press spends no stamina")
	check(runner.cooldown_left() > 0.0, "the cooldown is still running")

	# A body with no stamina left cannot pay for the sigil.
	caster.stamina = 10.0
	runner.set_brand(cruor.brand_of("dagger_iron"))
	var broke: Dictionary = runner.can_activate()
	check(not bool(broke["ok"]), "a body short of stamina refuses")
	check(str(broke["reason"]).contains("stamina"), "the refusal names stamina: %s" % broke["reason"])
	check(not runner.activate(), "a body short of stamina cannot fire")

	# A downed body is still alive but cannot act; a dead one is gone.
	caster.stamina = 1000.0
	caster.receive_melee(420.0, KILLER_SLOT, caster.global_position + Vector3(5, 0, 0))
	check(caster.downed and caster.alive, "a 5% overkill leaves the caster DOWNED")
	var downed: Dictionary = runner.can_activate()
	check(not bool(downed["ok"]), "a downed body refuses")
	check(not runner.activate(), "a downed body cannot fire")
	caster.receive_melee(600.0, KILLER_SLOT, caster.global_position + Vector3(5, 0, 0))
	check(not caster.alive, "a heavier blow kills the caster")
	var dead: Dictionary = runner.can_activate()
	check(not bool(dead["ok"]), "a dead body refuses")
	check(not runner.activate(), "a dead body cannot fire")
	place(caster, Vector3.ZERO)
	await _frames(2)

# --- tier scaling -----------------------------------------------------------

## Total health removed from two identical fresh bodies by one activation at one
## tier, with the same geometry and the same settle window every time.
func measure(ability: String, item: String, tier: int) -> float:
	_equip(ability, item, tier)
	place(caster, Vector3.ZERO)
	var settle := 0.9
	if ability == "arrow_barrage":
		caster.rig.set_weapon("bow")
		place(target_a, Vector3(0, 0, 6))
		place(target_b, Vector3(0.9, 0, 6))
		aim(caster, Vector3(0, 1.1, 6))
		await _frames(4)
		settle = 1.4
	else:
		caster.rig.set_weapon("sword")
		place(target_a, Vector3(0, 0, 1.2))
		place(target_b, Vector3(0.9, 0, 1.2))
		await _frames(4)
		aim(caster, Vector3(0, 1.1, 2.6))
	var before: float = target_a.health + target_b.health
	if not runner.activate():
		return 0.0
	await _seconds(settle)
	return before - (target_a.health + target_b.health)

func check_tier_scaling() -> void:
	var rows := [
		["arrow_barrage", "bow_short"],
		["shockwave_cleave", "sword_great"],
		["rending_strike", "dagger_iron"],
		["ember_storm", "staff_fire"],
		["hellfire_cone", "focus_skull"],
	]
	for row in rows:
		var ability := str(row[0])
		var item := str(row[1])
		var low := await measure(ability, item, TIER_LOW)
		var high := await measure(ability, item, TIER_HIGH)
		check(low > 0.0, "%s at tier 1 does real damage (%.1f)" % [ability, low])
		check(high > low + 0.5, "%s: tier 3 out-damages tier 1 (%.1f vs %.1f)"
			% [ability, high, low])

	# The ward buys minutes, not ratio: the tier lengthens it and the half stays
	# the half the HUD promises.
	_equip("blood_ward", "focus_tome", TIER_LOW)
	place(caster, Vector3.ZERO)
	await _frames(2)
	runner.activate()
	var short_ward: float = caster.ward_seconds
	_equip("blood_ward", "focus_tome", TIER_HIGH)
	place(caster, Vector3.ZERO)
	await _frames(2)
	runner.activate()
	check(caster.ward_seconds > short_ward,
		"the tier lengthens the ward (%.1f s vs %.1f s)" % [caster.ward_seconds, short_ward])
