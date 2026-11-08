class_name RunPlayer
extends Node
## One player's run: the mods they carry, the numbers those mods produce, and the
## translation of the proc engine's decisions into effects the island can spawn.
##
## A `RoguelitePlayer` is created by the run director for each body that enters
## the portal and lives as a child of the world for the length of the run. It is
## the body's *second* brain: `WarbandBody` still owns health, downing and the
## rig, and this node owns only what the arena loop adds on top. The body reaches
## it through `body.roguelite`, and the four hook sites in the engine
## (`note_attack_landed`, `take_damage`, a shot's `on_hit`, the world's fire
## callback) are the only places the two touch.
##
## It rolls nothing for damage itself. `RogueliteProcEngine` decides; this node
## asks, and hands the answers to the director to execute.

const EngineScript = preload("res://scripts/roguelite/proc_engine.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const BodyScript = preload("res://scripts/warband/warband_body.gd")

## How often the standing bleed of Slippery Slope is applied. One tick per frame
## would be a hundred tiny damage numbers; four a second reads as a bleed.
const DRAIN_TICK := 0.25

var body = null
var director = null
var peer_id := 1
var merc_id := -1
var engine
var ranged_id := ""
var melee_id := ""
var ranged_profile: Dictionary = {}
var melee_profile: Dictionary = {}
var crystals := 0
var kills := 0
## Set when a Greed mod has locked the hands for the rest of the run.
var hands_locked := false
## Which slot the body is holding: `"ranged"` or `"melee"`. TAB flips it.
var _active_slot := "ranged"

var _base_max_health := 100.0
var _drain_clock := 0.0


func bind(owner_body, run_director, owner_peer: int, owner_merc: int,
		ranged_weapon: String, melee_weapon: String) -> void:
	body = owner_body
	director = run_director
	peer_id = maxi(1, owner_peer)
	merc_id = owner_merc
	name = "RoguelitePlayer%d" % peer_id
	ranged_id = ranged_weapon
	melee_id = melee_weapon
	_set_profiles()
	if body != null:
		body.roguelite = self
		body.roguelite_hold_downed = true
		_base_max_health = body.max_health
	var seed_value := 0
	if director != null:
		seed_value = int(director.get("run_seed"))
	engine = EngineScript.new(seed_value, peer_id)
	apply_stats()


func _set_profiles() -> void:
	ranged_profile = Weapons.resolve(ranged_id)
	melee_profile = Weapons.resolve(melee_id)
	if ranged_profile.is_empty():
		ranged_profile = Weapons.resolve(Weapons.STARTER_RANGED)
	if melee_profile.is_empty():
		melee_profile = Weapons.resolve(Weapons.STARTER_MELEE)


func unbind() -> void:
	if body != null and is_instance_valid(body):
		body.roguelite = null
		body.roguelite_hold_downed = false
		if is_instance_valid(body.rig):
			body.rig.run_rate_scale = 1.0
		body = null
	director = null


func _physics_process(delta: float) -> void:
	if body == null or not is_instance_valid(body):
		return
	_apply_rate()
	_apply_standing_drain(delta)


## The rig reads one rate scale. Which profile it belongs to follows the hands:
## a bow or a staff is the ranged profile, a blade is the melee one.
func _apply_rate() -> void:
	var rig = body.get("rig")
	if rig == null or not is_instance_valid(rig):
		return
	var profile := melee_profile
	var weapon := str(rig.get("weapon"))
	if weapon == "bow" or weapon == "staff":
		profile = ranged_profile
	var want: float = float(engine.attack_scale()) * float(profile.get("attack_mult", 1.0))
	if absf(float(rig.run_rate_scale) - want) > 0.0001:
		rig.run_rate_scale = want


## Slippery Slope: a body that plants its feet in a live wave bleeds. The drain
## is a share of the *pool*, not of current health, so it is a clock a player can
## read rather than a spiral.
func _apply_standing_drain(delta: float) -> void:
	if engine == null or body == null:
		return
	var drain: float = float(engine.stat("standing_drain"))
	if drain <= 0.0:
		return
	if director == null or not bool(director.get("wave_active")):
		_drain_clock = 0.0
		return
	var alive := _flag(body, "alive", true) and not _flag(body, "downed", false)
	if not alive:
		return
	var velocity: Vector3 = body.velocity if body is CharacterBody3D else Vector3.ZERO
	if Vector2(velocity.x, velocity.z).length() > 0.6:
		_drain_clock = 0.0
		return
	_drain_clock += delta
	while _drain_clock >= DRAIN_TICK:
		_drain_clock -= DRAIN_TICK
		var bite: float = maxf(1.0, float(body.max_health) * drain * DRAIN_TICK)
		body.health = maxf(0.0, float(body.health) - bite)
		if float(body.health) <= 0.001:
			if body.has_method("enter_downed"):
				body.enter_downed(-1)
			return


# --- the numbers -----------------------------------------------------------

func apply_stats() -> void:
	if body == null or not is_instance_valid(body) or engine == null:
		return
	var factor: float = float(engine.health_factor()) + float(engine.stat("max_hp_flat")) / maxf(_base_max_health, 1.0)
	var pool := maxf(1.0, _base_max_health * factor)
	if absf(float(body.max_health) - pool) > 0.01:
		body.max_health = pool
		body.health = minf(float(body.health), pool)
	_apply_rate()


func damage_multiplier() -> float:
	return engine.damage_multiplier()


func currency_multiplier() -> float:
	return maxf(0.0, 1.0 + engine.stat("currency_mult"))


func proc_multiplier() -> float:
	return engine.proc_multiplier()


func hands_locked_now() -> bool:
	return hands_locked


## Bloodthirst's contract: nothing mends a body between fights. The body asks
## this before a bandage, a potion or its own slow regen pays a point.
func blocks_passive_healing() -> bool:
	return engine != null and engine.has_flag("bloodthirst")


func is_downed() -> bool:
	return body == null or not is_instance_valid(body) or _flag(body, "downed", false) or not _flag(body, "alive", true)


func heal(amount: float) -> void:
	if body == null or not is_instance_valid(body) or amount <= 0.0:
		return
	# Bloodthirst turns off the passive heals, never the ones a cut pays for:
	# the gore lifesteal and the harvest are exactly what it leaves standing.
	body.health = minf(float(body.max_health), float(body.health) + amount)


# --- the draft -------------------------------------------------------------

## Three offers from the pool, never a mod already at its ceiling. The pedestal
## shows these; taking one is `take_mod`.
func draft(count: int = 3, allow_greed: bool = false) -> Array[String]:
	var exclude: Array = []
	for id in engine.stacks:
		if int(engine.stacks[id]) >= Mods.max_stacks(str(id)):
			exclude.append(str(id))
	return Mods.draft(engine.rng, count, allow_greed, exclude)


func take_mod(mod_id: String) -> Dictionary:
	if engine == null:
		return {"ok": false, "message": "This body has no run."}
	if not Mods.has(mod_id):
		return {"ok": false, "message": "That is not a mod."}
	if int(engine.stacks.get(mod_id, 0)) >= Mods.max_stacks(mod_id):
		return {"ok": false, "message": "%s is already at its ceiling." % Mods.name_of(mod_id)}
	if not engine.add_mod(mod_id):
		return {"ok": false, "message": "That mod will not take."}
	var flags: Dictionary = Mods.get_mod(mod_id).get("flags", {})
	if bool(flags.get("cursed", false)):
		hands_locked = true
	apply_stats()
	return {"ok": true, "id": mod_id, "name": Mods.name_of(mod_id),
		"message": "%s  ·  %s" % [Mods.name_of(mod_id), str(
			(Mods.get_mod(mod_id).get("description", "")))]}


# --- hooks called by the body and the world --------------------------------

## A bow or a staff released. Answers the shot plan(s) the firing controller
## executes: count, fan, crit, pierce, ricochet, homing and proc coefficient.
func fire_plan(origin: Vector3, direction: Vector3) -> Dictionary:
	if engine == null:
		return {}
	var profile := ranged_profile
	return engine.on_weapon_fire(profile, origin, direction)


## One committed melee swing. The caller scales `state.damage` by the returned
## `damage_scale` and carries `crit` into the contact.
func melee_swing(forward: Vector3) -> Dictionary:
	if engine == null:
		return {"crit": false, "damage_scale": 1.0}
	var out: Dictionary = engine.on_melee_swing(melee_profile, forward)
	# The swing's own effects - the crescent - leave at the moment the cut is
	# committed, not when it lands: `Combat` starts its sweep on the same frame
	# and a wave that waited for a contact would arrive behind the blade.
	# The profile's own weight rides the knockback too: a javelin throws a body
	# further than a knife even before a single Heavy Caliber is taken.
	out["knockback"] = float(out.get("knockback", 1.0)) \
		* float(melee_profile.get("gore", 1.0))
	_execute(out.get("requests", []))
	return out


## A staff's bolt, planned by the ability runner: the same damage mods and crit a
## shot gets, expressed as the numbers the projectile needs.
func spell_plan(base_damage: float) -> Dictionary:
	if engine == null:
		return {"damage": base_damage, "crit": false, "proc": 1.0}
	var crit: bool = bool(engine.crit_roll())
	return {
		"damage": base_damage * damage_multiplier() * (2.0 if crit else 1.0),
		"crit": crit,
		"proc": float(ranged_profile.get("proc", 1.0)) * proc_multiplier(),
	}


## The projectile's `on_hit` for a run body: one callable per profile, so a blow
## knows which piece's coefficient it carried.
func hit_hook(profile: Dictionary = {}) -> Callable:
	var resolved := profile if not profile.is_empty() else ranged_profile
	return Callable(self, "projectile_hit").bind(resolved)


## A ranged projectile landed. Called from the arrow's own damage frame on the
## authority only.
func projectile_hit(target, at: Vector3, damage: float, crit: bool, proc: float,
		profile: Dictionary = {}) -> void:
	var resolved := profile if not profile.is_empty() else ranged_profile
	var ctx := {"kind": "ranged", "target": target, "position": at, "damage": damage,
		"crit": crit, "proc": proc, "profile": resolved, "is_melee": false}
	var requests: Array = engine.on_hit(ctx)
	_execute(requests)
	if target != null and is_instance_valid(target) and target.get("alive") == false:
		_kill(ctx)


## A melee blow landed. Called by `WarbandBody.note_attack_landed`, which the
## shared `Combat` resolver already calls for every cut, cleave and skill arc.
func melee_hit(target, hand: String, damage: float, crit: bool) -> void:
	var ctx := {"kind": "melee", "target": target,
		"position": target.global_position if target is Node3D else Vector3.ZERO,
		"damage": damage, "crit": crit, "hand": hand,
		"proc": float(melee_profile.get("proc", 1.0)) * proc_multiplier(),
		"profile": melee_profile, "is_melee": true}
	var requests: Array = engine.on_hit(ctx)
	_execute(requests)
	if target != null and is_instance_valid(target) and target.get("alive") == false:
		_kill(ctx)


## A proc's own blow landed. It never rolls another proc, by construction: the
## fan-out is one deep.
func proc_hit(target, died: bool, damage: float) -> void:
	if died and target != null and is_instance_valid(target):
		_kill({"kind": "proc", "target": target,
			"position": target.global_position if target is Node3D else Vector3.ZERO,
			"damage": damage, "proc": 0.0, "is_melee": false})


func _kill(ctx: Dictionary) -> void:
	kills += 1
	var position: Vector3 = ctx.get("position", Vector3.ZERO)
	# A body that lost its head or was opened in two counts as gibbed; the mob
	# classes carry that as the killing blow's own note (`_sever` for a head,
	# `_split` for a body cut in two), never as a boolean.
	var gibbed := false
	var target = ctx.get("target")
	if target != null and is_instance_valid(target):
		var sever: Variant = target.get("_sever")
		var split: Variant = target.get("_split")
		gibbed = (sever is Vector3 and (sever as Vector3) != Vector3.ZERO) or (split is Vector3 and (split as Vector3) != Vector3.ZERO)
	ctx["gibbed"] = gibbed
	var requests: Array = engine.on_kill(ctx)
	_execute(requests)
	if director != null:
		director.execute_effect(self, {"kind": "kill_credit", "target": target,
			"position": position, "gibbed": gibbed})


## A blow landing on this body, answered before the armour does its work.
func filter_incoming(amount: float, source_id: int) -> Dictionary:
	if engine == null:
		return {"dodged": false, "damage": amount}
	return engine.on_player_damaged(amount, source_id)


func stage_clear() -> void:
	if engine == null:
		return
	# One source of the clear heal: the engine's own `heal_on_clear`, which the
	# request below pays out. Bloodthirst is the one flag that switches it off,
	# and it says so at the engine so the two cannot disagree.
	_execute(engine.on_stage_clear(float(body.max_health) if body else 100.0,
		not engine.has_flag("bloodthirst")))


func revive_for_clear() -> bool:
	if body == null or not is_instance_valid(body):
		return false
	if not _flag(body, "downed", false) or not _flag(body, "alive", true):
		return false
	body.revive_from_downed(0.5)
	return true


# --- execution -------------------------------------------------------------

static func _flag(object, key: String, fallback: bool = false) -> bool:
	if object == null or not is_instance_valid(object):
		return fallback
	var value: Variant = object.get(key)
	return fallback if value == null else bool(value)


func _execute(requests: Array) -> void:
	if requests.is_empty() or director == null:
		return
	for request in requests:
		director.execute_effect(self, request)
