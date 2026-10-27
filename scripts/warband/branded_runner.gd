class_name BrandedRunner
extends Node
## Plays the six Sacramental Cruor abilities on a real `ArenaActor`.
##
## `BrandedSkills` owns the identity of every sigil (name, stamina cost,
## cooldown, tier power curve); this node owns the moment one fires. It never
## invents a damage channel: every blow goes through the primitives the body
## already has - `Combat.ability_strike`, `Combat.ability_blast`,
## `ArenaActor.fired` (the scene's arrow spawner), `ArenaActor.start_ward` and
## `ArenaActor.take_damage` for the bleed ticks - so armour, blocks, wards,
## blood, damage numbers and the passive-sim bubble keep behaving exactly as
## they do for an authored swing.
##
## A scene attaches the payload the altar wrote (`Warband.cruor.brand_of(item)`)
## and calls `activate()` from whatever key it binds to. Nothing here binds a
## key or builds a scene.

const Branded = preload("res://scripts/warband/branded_skills.gd")
const Fx = preload("res://scripts/warband/branded_fx.gd")
const Archer = preload("res://scripts/archer.gd")

## Six shafts inside the space of one draw, each carrying half a full draw. The
## charge is scaled by the tier, so T1 is a 50% draw and T5 is a real full one;
## `Combat.damage_for` clamps the charge, so a relic cannot overload the bow.
const BARRAGE_SHAFTS := 6
const BARRAGE_WINDOW := 0.7
const BARRAGE_CHARGE := 0.5
## The cleave's own cut, then the ground answering it.
const CLEAVE_REACH := 2.4
const CLEAVE_ARC := 110.0
const CLEAVE_CUT := 1.35
const CLEAVE_STAGGER := 0.45
const CLEAVE_RADIUS := 3.0
const CLEAVE_BLAST := 0.8
## Rending Strike: the cut, then three beats of bleed as the wound closes.
const REND_REACH := 2.6
const REND_ARC := 120.0
const REND_CUT := 1.1
const REND_TICKS := 3
const REND_SECONDS := 3.0
const REND_BLEED := 0.32
## The wound closes a little each beat: a body that breaks away from the measure
## the cut was made in stops bleeding.
const REND_CLOSE := 0.1
## Ember Storm: a star that comes apart where the crosshair is.
const STORM_RANGE := 16.0
const STORM_RADIUS := 3.2
const STORM_DAMAGE := 1.5
const STORM_STAGGER := 0.5
## Hellfire Cone: everything inside ninety degrees, held still for longer.
const CONE_ARC := 90.0
const CONE_RADIUS := 4.2
const CONE_DAMAGE := 1.25
const CONE_STAGGER := 1.2
## Blood Ritual Ward: the shipped Energy Shield ratio (half of every hit paid in
## stamina at twice the price), with the tier buying the minutes it lasts. The
## half is the promise the HUD makes, so the ratio never scales; time does.
const WARD_SECONDS := 30.0
const WARD_ABSORB := 0.5
const WARD_STAMINA_SCALE := 2.0
## Damage an unarmed body still deals through a sigil, and the floor under a rig
## whose damage table has not been built yet.
const FALLBACK_WEAPON_DAMAGE := 30.0

const FX_COLOR := {
	"rending_strike": Color(0.86, 0.19, 0.21),
	"shockwave_cleave": Color(0.94, 0.74, 0.36),
	"arrow_barrage": Color(0.87, 0.82, 0.62),
	"ember_storm": Color(1.0, 0.53, 0.18),
	"hellfire_cone": Color(1.0, 0.34, 0.1),
	"blood_ward": Color(0.78, 0.2, 0.42),
}

## The body this runner plays for. Untyped on purpose: the runner only uses the
## actor contract (stamina, alive, downed, slot, combat, rig, fired, hurt
## funnels), so a fixture can drive it without being an `ArenaActor`.
var actor
var _brand: Dictionary = {}
var _ability := ""
var _tier := 0
var _power := 1.0
var _cooldown := 0.0
## Seconds since the live activation, for the barrage's beats.
var _operation := 0.0
## Barrage shafts still to leave, in beat order.
var _shots: Array[Dictionary] = []
## Bodies still bleeding from Rending Strike.
var _bleeds: Array[Dictionary] = []
var _effect: Dictionary = {}

# --- attachment ------------------------------------------------------------

## Binds this runner to `target` and the sigil `brand_payload` (the shape
## `Warband.cruor.brand_of()` returns).
func attach(target, brand_payload: Dictionary) -> void:
	actor = target
	set_brand(brand_payload)

## The payload in force, exactly as the altar wrote it.
func brand() -> Dictionary:
	return _brand

## Rebinds the sigil. A rebrand is a new sigil: the old cooldown, the shafts
## still in the air and the wounds still open all belong to the ability being
## replaced, so the new one starts ready.
func set_brand(payload: Dictionary) -> void:
	var clean: Dictionary = payload if payload is Dictionary else {}
	_ability = str(clean.get("ability", ""))
	_tier = int(clean.get("tier", 0))
	if Branded.definition(_ability).is_empty():
		# Plain steel still carries no payload: an empty brand is the same thing
		# as no brand, and both refuse in `can_activate`.
		_ability = ""
		_brand = {}
	else:
		_brand = clean.duplicate(true)
	_power = Branded.power(_tier)
	_cooldown = 0.0
	_operation = 0.0
	_shots.clear()
	_bleeds.clear()

# --- state -----------------------------------------------------------------

## Whether the sigil can fire right now, and why not when it cannot.
func can_activate() -> Dictionary:
	if _ability.is_empty():
		return {"ok": false, "reason": "That weapon carries no brand.",
			"cost": 0.0, "ability": "", "tier": _tier, "power": _power}
	var label := Branded.ability_name(_ability)
	var cost := Branded.scaled(Branded.stamina_cost(_ability), _tier)
	if not is_instance_valid(actor):
		return {"ok": false, "reason": "No body holds this brand.",
			"cost": cost, "ability": _ability, "tier": _tier, "power": _power}
	if actor.get("alive") != true or actor.get("downed") == true:
		return {"ok": false, "reason": "A fallen body cannot call on the brand.",
			"cost": cost, "ability": _ability, "tier": _tier, "power": _power}
	if _cooldown > 0.0:
		return {"ok": false, "reason": "%s ready in %.1f s." % [label, _cooldown],
			"cost": cost, "ability": _ability, "tier": _tier, "power": _power}
	if float(actor.stamina) < cost:
		return {"ok": false, "reason": "Not enough stamina for %s." % label,
			"cost": cost, "ability": _ability, "tier": _tier, "power": _power}
	return {"ok": true, "reason": "", "cost": cost, "ability": _ability,
		"tier": _tier, "power": _power}

func cooldown_left() -> float:
	return _cooldown

## What the last `activate()` did: the HUD reads it for the line under the bar,
## the regression reads it for the numbers. Updated live as delayed beats land.
func last_effect() -> Dictionary:
	return _effect

# --- activation ------------------------------------------------------------

func activate() -> bool:
	var check := can_activate()
	if not bool(check["ok"]):
		_effect = {"ok": false, "reason": str(check["reason"]), "ability": _ability,
			"tier": _tier, "power": _power, "cost": 0.0, "damage": 0.0,
			"victims": 0, "ticks": 0, "arrows": 0, "ward_seconds": 0.0}
		return false
	var cost := float(check["cost"])
	actor.stamina = maxf(0.0, float(actor.stamina) - cost)
	_cooldown = Branded.cooldown(_ability)
	_operation = 0.0
	_shots.clear()
	_bleeds.clear()
	_effect = {"ok": true, "ability": _ability, "tier": _tier, "power": _power,
		"cost": cost, "damage": 0.0, "victims": 0, "ticks": 0, "arrows": 0,
		"ward_seconds": 0.0, "bleed": 0.0, "cooldown": _cooldown}
	match _ability:
		"arrow_barrage":
			_play_barrage()
		"shockwave_cleave":
			_play_cleave()
		"rending_strike":
			_play_rend()
		"ember_storm":
			_play_storm()
		"hellfire_cone":
			_play_cone()
		"blood_ward":
			_play_ward()
	return true

# --- the six sigils --------------------------------------------------------

## Six shafts loosed along the live aim inside 0.7 s. The event is the same one
## a player's release fires, so the scene's arrow spawner flies real arrows and
## the damage lands through the same funnel.
func _play_barrage() -> void:
	var charge := clampf(BARRAGE_CHARGE * _power, 0.0, 1.0)
	var speed := _arrow_speed()
	for index in BARRAGE_SHAFTS:
		# The first shaft leaves on the press and the sixth at the end of the
		# window, so the whole barrage occupies exactly `BARRAGE_WINDOW`.
		_shots.append({"at": BARRAGE_WINDOW * float(index) / float(BARRAGE_SHAFTS - 1),
			"speed": speed, "charge": charge})
	_effect["arrows"] = BARRAGE_SHAFTS
	_loose_due_shafts()

## A swing, a cut and the ground answering under it.
##
## `begin_melee` is only the visible half - the blade's pose and its own contact
## sweep - so its result is not gated on: a body whose rig cannot swing still
## gets the sigil's cut, which is the ability's own damage.
func _play_cleave() -> void:
	actor.combat.begin_melee("right", "diagonal_right")
	var weapon := _weapon_damage()
	var cut := weapon * CLEAVE_CUT * _power
	var struck: Dictionary = {}
	var hits: int = actor.combat.ability_strike(CLEAVE_REACH, CLEAVE_ARC, cut,
			CLEAVE_STAGGER, false, true, struck)
	var impact := _impact_point(CLEAVE_REACH)
	var radius := Branded.scaled(CLEAVE_RADIUS, _tier)
	var blast := weapon * CLEAVE_BLAST * _power
	hits += actor.combat.ability_blast(impact, radius, blast, CLEAVE_STAGGER * 0.5)
	_effect["damage"] = cut + blast
	_effect["victims"] = hits
	Fx.ring(_root(), impact, radius, _colour(), 0.55)

## A cut that keeps opening: the arc strike records who it crossed, then three
## beats of bleed follow them while the wound is still within reach. The pressed
## swing is presentation, exactly as in the cleave.
func _play_rend() -> void:
	actor.combat.begin_melee("right", "diagonal_left")
	var weapon := _weapon_damage()
	var cut := weapon * REND_CUT * _power
	var struck: Dictionary = {}
	var hits: int = actor.combat.ability_strike(REND_REACH, REND_ARC, cut, 0.0,
			false, true, struck)
	var bleed := weapon * REND_BLEED * _power
	var interval := REND_SECONDS / float(REND_TICKS)
	for key in struck:
		_bleeds.append({"id": int(key), "left": REND_TICKS, "tick": 0,
			"at": interval, "interval": interval, "reach": REND_REACH,
			"damage": bleed})
	_effect["damage"] = cut
	_effect["bleed"] = bleed
	_effect["victims"] = hits
	Fx.ring(_root(), actor.global_position, REND_REACH, _colour(), 0.32)

## The staff coughs a star at the crosshair and the star comes apart.
func _play_storm() -> void:
	var centre := _impact_point(STORM_RANGE)
	var radius := Branded.scaled(STORM_RADIUS, _tier)
	var damage := _weapon_damage() * STORM_DAMAGE * _power
	var hits: int = actor.combat.ability_blast(centre, radius, damage, STORM_STAGGER)
	_effect["damage"] = damage
	_effect["victims"] = hits
	Fx.flash(_root(), centre, radius * 0.4, _colour(), 0.3)
	Fx.ring(_root(), centre, radius, _colour(), 0.6)

## Ninety degrees in front of the skull, and everything in it stays put longer.
func _play_cone() -> void:
	var radius := Branded.scaled(CONE_RADIUS, _tier)
	var damage := _weapon_damage() * CONE_DAMAGE * _power
	var hits: int = actor.combat.ability_strike(radius, CONE_ARC, damage,
			CONE_STAGGER, false, false)
	_effect["damage"] = damage
	_effect["victims"] = hits
	Fx.cone(_root(), _origin(), _forward(), radius, CONE_ARC, _colour(), 0.5)

## A real ward on the body: half of every hit is paid in stamina while it runs.
func _play_ward() -> void:
	var seconds := Branded.scaled(WARD_SECONDS, _tier)
	actor.start_ward({"effect": {"kind": "ward", "absorb": WARD_ABSORB,
		"stamina_scale": WARD_STAMINA_SCALE, "seconds": seconds}})
	_effect["ward_seconds"] = float(actor.ward_seconds)
	Fx.ring(_root(), actor.global_position, 1.5, _colour(), 0.9)

# --- the tick ---------------------------------------------------------------

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if _shots.is_empty() and _bleeds.is_empty():
		return
	if not _body_can_act():
		# A body that falls mid-barrage does not keep casting: the shafts it had
		# left and the wounds it was holding open die with its intent.
		_shots.clear()
		_bleeds.clear()
		return
	_operation += delta
	_loose_due_shafts()
	_tick_bleeds(delta)

func _body_can_act() -> bool:
	return is_instance_valid(actor) and actor.get("alive") == true \
		and actor.get("downed") != true

func _loose_due_shafts() -> void:
	while not _shots.is_empty() and _operation >= float(_shots[0]["at"]):
		var beat: Dictionary = _shots.pop_front()
		_loose_shaft(beat)

func _loose_shaft(beat: Dictionary) -> void:
	var origin := _origin()
	var direction := (_aim_point() - origin).normalized()
	if direction.length_squared() < 0.5:
		direction = _forward()
	actor.fired.emit(int(actor.slot), origin, direction, float(beat["speed"]),
			float(beat["charge"]))
	Fx.flash(_root(), origin, 0.2, _colour(), 0.18)

## Advances every open wound. A beat that lands while the body is still inside
## the closing radius costs `damage` through `take_damage`, which means armour,
## the ward and the bubble multiplier all apply exactly as they do to a blade.
func _tick_bleeds(delta: float) -> void:
	if _bleeds.is_empty():
		return
	var open: Array[Dictionary] = []
	for wound in _bleeds:
		wound["at"] = float(wound["at"]) - delta
		if float(wound["at"]) > 0.0:
			open.append(wound)
			continue
		if _bleed_once(wound):
			wound["left"] = int(wound["left"]) - 1
			wound["tick"] = int(wound["tick"]) + 1
			wound["at"] = float(wound["interval"])
			if int(wound["left"]) > 0:
				open.append(wound)
	_bleeds = open

## One beat on one recorded body. Returns false when the wound is finished: the
## body is gone, dead, or has broken away beyond the closing radius.
func _bleed_once(wound: Dictionary) -> bool:
	var id := int(wound["id"])
	if not is_instance_id_valid(id):
		return false
	var victim = instance_from_id(id)
	if not is_instance_valid(victim) or victim.get("alive") != true:
		return false
	var reach := float(wound["reach"]) * (1.0 - REND_CLOSE * float(wound["tick"]))
	if victim.global_position.distance_to(actor.global_position) > reach:
		return false
	victim.take_damage(float(wound["damage"]), int(actor.slot))
	_effect["ticks"] = int(_effect.get("ticks", 0)) + 1
	Fx.ring(_root(), actor.global_position, reach, _colour(), 0.28)
	return true

# --- geometry ---------------------------------------------------------------

func _colour() -> Color:
	return FX_COLOR.get(_ability, Color(0.9, 0.9, 0.9))

## The world the primitives live in. A scene hands the runner a body that is
## already in the tree; a body with no parent just draws nothing.
func _root() -> Node3D:
	if not is_instance_valid(actor):
		return null
	var parent: Node = actor.get_parent()
	return parent if parent is Node3D else null

## The weapon's own damage, so a greatsword's cleave beats a shortsword's and a
## trinket that raises melee damage raises the sigil too.
func _weapon_damage() -> float:
	if is_instance_valid(actor):
		var rig = actor.get("rig")
		if is_instance_valid(rig) and rig.has_method("melee_damage"):
			return maxf(float(rig.melee_damage("right")), 1.0)
	return FALLBACK_WEAPON_DAMAGE

## Where the sigil leaves the body: the staff head, the bow's nock or the blade's
## hand, so the flash and the shafts start where the weapon is.
func _origin() -> Vector3:
	if is_instance_valid(actor):
		var rig = actor.get("rig")
		if is_instance_valid(rig) and rig.has_method("cast_origin"):
			return rig.cast_origin()
		return actor.global_position + Vector3.UP * 1.4
	return Vector3.ZERO

func _aim_point() -> Vector3:
	if is_instance_valid(actor):
		var combat = actor.get("combat")
		if is_instance_valid(combat):
			return combat.aim_point
		return actor.global_position + _forward() * 10.0
	return Vector3.ZERO

## The horizontal heading the body is looking down.
func _forward() -> Vector3:
	var facing := Vector3.FORWARD
	if is_instance_valid(actor):
		var rig = actor.get("rig")
		if is_instance_valid(rig):
			facing = -rig.global_basis.z
		facing.y = 0.0
		if facing.length_squared() < 0.000001:
			facing = _aim_point() - actor.global_position
			facing.y = 0.0
	if facing.length_squared() < 0.000001:
		return Vector3.FORWARD
	return facing.normalized()

## The aim point pulled back to `reach` and lifted to chest height: an impact
## has to fall somewhere inside the weapon's measure, not at the horizon.
func _impact_point(reach: float) -> Vector3:
	if not is_instance_valid(actor):
		return Vector3.ZERO
	var offset: Vector3 = _aim_point() - actor.global_position
	offset.y = 0.0
	return actor.global_position + offset.limit_length(reach) + Vector3.UP * 0.9

## A shaft flies at the speed the bow in this body's hands produces, so a
## longbow's barrage is faster than a shortbow's.
func _arrow_speed() -> float:
	var index := 0
	if is_instance_valid(actor):
		var rig = actor.get("rig")
		if is_instance_valid(rig):
			index = clampi(int(rig.get("bow_index")), 0, Archer.BOW_DATA.size() - 1)
	return float(Archer.BOW_DATA[index]["speed"])
