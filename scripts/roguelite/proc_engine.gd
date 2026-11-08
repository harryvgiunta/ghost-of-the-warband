class_name ProcEngine
extends RefCounted
## The deterministic on-hit modifier engine.
##
## One instance per body. It owns that body's mod stacks, turns them into the
## numbers the firing controllers read, and answers the six combat events the
## arena loop hangs its triggers on:
##
##   `on_weapon_fire`   a shot leaving the string
##   `on_melee_swing`   a committed cut leaving the hand
##   `on_hit`           a landed ranged or melee blow
##   `on_kill`          a body put down by that blow
##   `on_player_damaged`  a blow landing on this body
##   `on_stage_clear`   an island finished
##
## It never touches the scene, never spawns a node and never applies damage. It
## *decides* - and answers with effect requests (`{kind, ...}`) that the player's
## runtime executes. That split is what keeps the whole engine testable without a
## world, and what lets the host replicate an effect to its guests as one small
## dictionary.
##
## Stacking rules, and why they are two rules and not one:
##   * `LINEAR` - damage, fire rate, crit chance, max HP, currency, lifesteal.
##     Ten copies of +18% rate is +180%, which is a number a player can read and
##     a design can price.
##   * `HYPERBOLIC` - every *chance* (arc, nova, chain, bomb, bonus chest). These
##     approach a cap and never reach it: `cap * n / (n + half)`. Ten copies of a
##     15% proc is 0.5x, never 1.5x, so no stack count deletes the game.
##
## Every roll is one call on the instance's own seeded generator, in a fixed
## order, so the same run seed and the same event sequence produce the same
## triggers on the host every time.

const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")

## Chance stats and the curve each one rides. `half` is the stack count that
## reaches half the cap.
const HYPERBOLIC := {
	"arc_chance": {"cap": 0.75, "half": 3.0, "per": 0.15},
	"nova_chance": {"cap": 0.60, "half": 3.0, "per": 0.12},
	"chain_chance": {"cap": 0.70, "half": 3.0, "per": 0.15},
	"bomb_chance": {"cap": 0.60, "half": 3.0, "per": 0.12},
	"scatter_chance": {"cap": 0.60, "half": 2.5, "per": 0.20},
	"chest_chance": {"cap": 0.75, "half": 3.0, "per": 0.15},
	"dodge_chance": {"cap": 0.60, "half": 4.0, "per": 0.10},
}

## How much of a max-HP multiplier the greed mods may take away. A stack of
## Glass Cannon at -40% is a real cost; five stacks must not be a corpse.
const MIN_HEALTH_FACTOR := 0.15
## The ceiling on stacked crit chance. A crit is also a doubled proc roll, so a
## guaranteed crit would make every chance mod in the pool guaranteed too.
const CRIT_CAP := 0.85
## Base crit multiplier. Crit Sharpshooter names it; the engine is the one place
## it is applied to damage.
const CRIT_MULTIPLIER := 2.0
## The floor on attack-rate multipliers: a body always gets to swing.
const MIN_ATTACK_SCALE := 0.25

var run_seed := 0
var peer_id := 1
var stacks: Dictionary = {}
var rng := RandomNumberGenerator.new()
var events := 0
var _stats: Dictionary = {}
var _dirty := true


func _init(seed_value: int = 0, owner_peer: int = 1) -> void:
	run_seed = seed_value
	peer_id = maxi(1, owner_peer)
	# Two bodies on one seed must not roll identical sequences: a little death
	# per body would hand a four-stack party the same procs on the same frame.
	rng.seed = int(seed_value) * 31 + peer_id * 7919 + 104729


# --- stacks ---------------------------------------------------------------

func add_mod(mod_id: String, count: int = 1) -> bool:
	if not Mods.has(mod_id) or count <= 0:
		return false
	var cap := Mods.max_stacks(mod_id)
	var have := int(stacks.get(mod_id, 0))
	if have >= cap:
		return false
	stacks[mod_id] = mini(cap, have + count)
	_dirty = true
	return true


func stacks_of(mod_id: String) -> int:
	return int(stacks.get(mod_id, 0))


func total_stacks() -> int:
	var sum := 0
	for id in stacks:
		sum += int(stacks[id])
	return sum


func has_flag(flag: String) -> bool:
	for id in stacks:
		if int(stacks[id]) <= 0:
			continue
		var flags: Dictionary = Mods.get_mod(id).get("flags", {})
		if bool(flags.get(flag, false)):
			return true
	return false


func mod_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in stacks:
		if int(stacks[id]) <= 0:
			continue
		out.append({"id": str(id), "stacks": int(stacks[id]),
			"name": Mods.name_of(str(id)), "rarity": Mods.rarity_of(str(id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.id) < str(b.id))
	return out


## The one aggregate every accessor reads. Recomputed when a stack changes, not
## per shot.
func stats() -> Dictionary:
	if not _dirty:
		return _stats
	_dirty = false
	var out := {
		"damage_mult": 0.0, "attack_mult": 0.0, "knockback_mult": 0.0,
		"proc_coeff_mult": 0.0, "currency_mult": 0.0, "max_hp_flat": 0.0,
		"max_hp_mult": 0.0, "crit_chance": 0.0, "heal_on_kill": 0.0,
		"heal_on_clear": 0.0, "melee_lifesteal": 0.0, "split_shots": 0.0,
		"pierce": 0.0, "ricochet": 0.0, "homing": 0.0, "chain_base": 3.0,
		"wave_damage": 0.0, "standing_drain": 0.0, "enemy_speed_mult": 0.0,
		"enemy_damage_mult": 0.0, "damage_taken_mult": 0.0,
	}
	# Chance stacks are counted first, then curved once. Ten copies of two
	# different chance mods still land on the same cap for their own key.
	var chance_stacks := {}
	for mod_id in stacks:
		var count := int(stacks[mod_id])
		if count <= 0:
			continue
		var row: Dictionary = Mods.get_mod(str(mod_id))
		var row_stats: Dictionary = row.get("stats", {})
		for key in row_stats:
			var value := float(row_stats[key]) * float(count)
			if HYPERBOLIC.has(str(key)):
				chance_stacks[str(key)] = float(chance_stacks.get(str(key), 0.0)) + count
			else:
				out[str(key)] = float(out.get(str(key), 0.0)) + value
	if has_flag("shockwave"):
		# Every melee-swing mod adds a wave; the first stack is the authored
		# 45%, every extra stack widens the cut by another 15 points.
		var wave_stacks := 0
		for mod_id in stacks:
			if bool((Mods.get_mod(str(mod_id)).get("flags", {})).get("shockwave", false)):
				wave_stacks += int(stacks[mod_id])
		out["wave_damage"] = 0.45 + 0.15 * float(maxi(0, wave_stacks - 1))
	for key in chance_stacks:
		var curve: Dictionary = HYPERBOLIC[key]
		var n := float(chance_stacks[key])
		var cap := float(curve.cap)
		var half := maxf(float(curve.half), 0.001)
		out[key] = cap * n / (n + half)
	out["crit_chance"] = minf(CRIT_CAP, float(out["crit_chance"]))
	_stats = out
	return _stats


func stat(key: String) -> float:
	return float(stats().get(key, 0.0))


# --- the numbers the controllers read -------------------------------------

## Weapon damage as a multiplier over the profile's own base. Heavy Caliber,
## Glass Cannon, Cursed Arsenal and any future `damage_mult` stack additively.
func damage_multiplier() -> float:
	return maxf(0.0, 1.0 + stat("damage_mult"))


func attack_scale() -> float:
	return maxf(MIN_ATTACK_SCALE, 1.0 + stat("attack_mult"))


func knockback_multiplier() -> float:
	return maxf(0.0, 1.0 + stat("knockback_mult"))


func proc_multiplier() -> float:
	return maxf(0.0, 1.0 + stat("proc_coeff_mult"))


## Health after the plate and the greed. Floored so a stack of Glass Cannon can
## put a body on its last legs but never on the ground.
func health_factor() -> float:
	var factor := 1.0 + stat("max_hp_mult")
	return maxf(MIN_HEALTH_FACTOR, factor)


func crit_roll() -> bool:
	events += 1
	return rng.randf() < stat("crit_chance")


## One hyperbolic chance roll. `crit` doubles the proc chance, which is the
## engine's own reading of Crit Sharpshooter.
func chance_roll(key: String, crit: bool = false) -> bool:
	var chance := stat(key)
	if crit:
		chance = minf(1.0, chance * 2.0)
	if chance <= 0.0:
		return false
	events += 1
	return rng.randf() < chance


func dodge_roll() -> bool:
	return chance_roll("dodge_chance")


# --- events ----------------------------------------------------------------

## A shot leaving the string. Answers the firing controllers with the whole shot
## plan: how many projectiles, how far off-axis, and what each one carries.
func on_weapon_fire(profile: Dictionary, origin: Vector3, direction: Vector3) -> Dictionary:
	var plan := {
		"shots": 1 + int(round(stat("split_shots"))),
		"scatter": false,
		"spread": float(profile.get("spread", 0.0)),
		"damage_scale": damage_multiplier(),
		"crit": crit_roll(),
		"pierce": int(profile.get("pierce", 0)) + int(round(stat("pierce"))),
		"ricochet": int(profile.get("ricochet", 0)) + int(round(stat("ricochet"))),
		"homing": float(profile.get("homing", 0.0)) + stat("homing") * 18.0,
		"knockback": float(profile.get("knockback", 1.0)) * knockback_multiplier(),
		"gore": float(profile.get("gore", 1.0)),
		"proc": float(profile.get("proc", 1.0)) * proc_multiplier(),
	}
	# Scatter: a chance to turn one trigger into a burst of three. It rides on
	# top of the split count rather than replacing it.
	if chance_roll("scatter_chance", plan["crit"]):
		plan["scatter"] = true
		plan["shots"] = int(plan["shots"]) + 2
		# Scatter pays 60% a bolt, exactly as its row says; Split Shot's own fan
		# is a separate budget and keeps the first arrow whole.
		plan["damage_scale"] = float(plan["damage_scale"]) * 0.6
	plan["origin"] = origin
	plan["direction"] = direction
	return plan


## A committed cut. Answers the melee-swing effects (the crescent) and the crit
## the blow carries, and lets the caller scale the swing's damage.
func on_melee_swing(profile: Dictionary, forward: Vector3) -> Dictionary:
	var crit := crit_roll()
	var requests: Array = []
	if has_flag("shockwave"):
		requests.append({
			"kind": "shockwave", "forward": forward,
			"damage_scale": stat("wave_damage"),
			"pierce": 1 + int(round(stat("pierce"))),
			"crit": crit, "proc": float(profile.get("proc", 1.0)) * proc_multiplier(),
		})
	return {
		"crit": crit,
		# A crit is a doubled blow, exactly as it is for a shot: the controller
		# scales the cut here and carries the flag on to the proc roll.
		"damage_scale": damage_multiplier() * (CRIT_MULTIPLIER if crit else 1.0),
		"knockback": knockback_multiplier(),
		"requests": requests,
	}


## A landed blow. `ctx`:
## `{kind, target, position, damage, crit, profile, hand, is_melee}`.
## Answers the trigger requests that blow earned.
func on_hit(ctx: Dictionary) -> Array:
	var out: Array = []
	var target = ctx.get("target")
	if target == null or not is_instance_valid(target):
		return out
	var crit := bool(ctx.get("crit", false))
	var damage := float(ctx.get("damage", 0.0))
	var position: Vector3 = ctx.get("position", Vector3.ZERO)
	var profile: Dictionary = ctx.get("profile", {})
	var proc := maxf(0.0, float(ctx.get("proc", 1.0)))
	if has_flag("dagger_arc") and chance_roll("arc_chance", crit):
		out.append({"kind": "arc", "target": target, "position": position,
			"damage": damage * 1.4, "proc": proc * 0.5, "crit": false})
	if has_flag("nova") and chance_roll("nova_chance", crit):
		out.append({"kind": "nova", "target": target, "position": position,
			"damage": damage * 0.55, "proc": proc * 0.4, "count": 8})
	if has_flag("chain") and chance_roll("chain_chance", crit):
		out.append({"kind": "chain", "target": target, "position": position,
			"damage": damage * 0.4, "proc": proc * 0.4,
			"targets": 3 + int(round(stat("chain_base") - 3.0)) + stacks_of("chain_lightning")})
	if has_flag("bomb") and chance_roll("bomb_chance", crit):
		out.append({"kind": "bomb", "target": target, "position": position,
			"damage": damage * 1.2, "proc": proc * 0.5, "radius": 3.0, "delay": 1.2})
	if bool(ctx.get("is_melee", false)) and stat("melee_lifesteal") > 0.0:
		out.append({"kind": "heal", "amount": damage * stat("melee_lifesteal"),
			"source": "melee"})
	return out


## A body this blow put down.
func on_kill(ctx: Dictionary) -> Array:
	var out: Array = []
	var position: Vector3 = ctx.get("position", Vector3.ZERO)
	var damage := float(ctx.get("damage", 0.0))
	var proc := maxf(0.0, float(ctx.get("proc", 1.0)))
	var gibbed := bool(ctx.get("gibbed", false))
	var harvest: float = float(stats().get("heal_on_kill", 0.0))
	if harvest > 0.0:
		# Grim Harvest restores `1 + stack`: one point for the kill itself and
		# one per copy of the mod, doubled when the body came apart.
		out.append({"kind": "heal", "amount": (1.0 + harvest) * (2.0 if gibbed else 1.0),
			"source": "harvest"})
	if has_flag("nova"):
		# A kill is a guaranteed nova, which is the whole appeal of the mod.
		out.append({"kind": "nova", "target": ctx.get("target"), "position": position,
			"damage": damage * 0.55, "proc": proc * 0.4, "count": 8})
	return out


## A blow landing on this body. Answers the dodge and the incoming multiplier.
func on_player_damaged(amount: float, _source_id: int) -> Dictionary:
	var dodged := dodge_roll()
	var taken := amount * maxf(0.0, 1.0 + stat("damage_taken_mult"))
	return {"dodged": dodged, "damage": taken}


## An island cleared. Answers the per-clear heals.
func on_stage_clear(max_health: float, allow_heal: bool = true) -> Array:
	var out: Array = []
	if stat("heal_on_clear") > 0.0 and allow_heal:
		out.append({"kind": "heal", "amount": max_health * stat("heal_on_clear"),
			"source": "clear"})
	return out
