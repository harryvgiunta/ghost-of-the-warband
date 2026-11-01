extends RefCounted
## The Weeping Hollow's loot table: what a body below leaves when it falls.
##
## The world books a kill the same way above and below - the steel out of the hand
## onto the dirt, everything else a corpse to search (`world_scene._on_enemy_defeated`).
## Below, the cave settles the body first (`settle`), on the host and once per
## death, so what a corpse holds is this table's answer:
##
##   * a thin share of the kit. A watcher below leaves `KEEP_SHARE` of what the same
##     body leaves above - its weapon, every rag of armour and everything it carries
##     each kept on its own roll - so a floor crowded ten times over is not a stash
##     filled ten times over. The floor's master keeps its prize whole;
##   * the altar's first essence. Demons bleed Ritual Tallow when they die, and the
##     watchers have caught on - they gate demons through to harvest it for
##     themselves - so a rare corpse of either carries a piece of it
##     (`DEMON_ESSENCE_CHANCE`, `WATCHER_ESSENCE_CHANCE`). It is a carried piece in
##     the delve inventory until the climb out renders it into the wallet;
##   * steel already anointed. A rare watcher's weapon comes out of its hand
##     anointed (`ANOINTED_CHANCE`): its drop is marked, and the warband that takes
##     it has the piece's skill awake on every copy it owns, no reagent spent
##     (`Warband.grant_anointing`). Only a piece that has a skill can be.
##
## The rare finds are their own rolls and are never thinned: an anointed weapon
## always falls, and essence already on a body stays on it. These are rolls, not
## properties of a post - every descent is a fresh instance, so the same body does
## not carry the same prize twice - and only the host's world books a corpse.

const Cruor = preload("res://scripts/warband/cruor_manager.gd")

## The essence a corpse carries: the catalog's Ritual Tallow, the wallet's tier 1.
const ESSENCE := "cruor_t1"
const WATCHER_ESSENCE_CHANCE := 0.04
const DEMON_ESSENCE_CHANCE := 0.10
const ANOINTED_CHANCE := 0.02
## Each ordinary piece on a watcher below survives its fall on this roll: the
## Hollow's loot is cut by 70%.
const KEEP_SHARE := 0.3


## Settle what a fallen body leaves. `demon` is the floor's master (its prize is
## `spoils`); every other body below is a watcher (`weapon_item`, `armor_items`,
## `carried`).
static func settle(body, demon: bool, rng: RandomNumberGenerator) -> void:
	if body == null or not is_instance_valid(body) or rng == null:
		return
	if demon:
		if rng.randf() < DEMON_ESSENCE_CHANCE:
			body.spoils.append(ESSENCE)
		return
	var weapon := str(body.weapon_item)
	if not weapon.is_empty() and not bool(body.weapon_anointed):
		if rng.randf() < ANOINTED_CHANCE and not Cruor.anoint_skill(weapon).is_empty():
			body.weapon_anointed = true
		elif rng.randf() >= KEEP_SHARE:
			# The steel does not survive the fall: the hand lets go of nothing.
			body.take_weapon_item()
	body.armor_items.assign(_thinned(body.armor_items, rng))
	body.carried.assign(_thinned(body.carried, rng))
	if rng.randf() < WATCHER_ESSENCE_CHANCE:
		body.carried.append(ESSENCE)


## The pieces that survive the fall, each kept on its own `KEEP_SHARE` roll. A
## piece of essence already on the body is a rare find, never thinned.
static func _thinned(pieces: Array, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	for piece in pieces:
		if str(piece) == ESSENCE or rng.randf() < KEEP_SHARE:
			out.append(str(piece))
	return out
