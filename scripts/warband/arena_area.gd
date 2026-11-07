extends Node3D
## GHOST OF THE WARBAND: the arena, and the warband it puts in the ring with you.
##
## The third door out of Hearthstead, and the only one that is a *fight* and
## nothing else. `enter()` builds the ring (`arena_ring.gd`) far above the
## campaign's own ground, moves the whole field into it and stands a mirrored
## warband on the far arc: the same bodies, the same ten slots, the same skills -
## a tank, a blade and a bow, dressed to the difficulty and driven by the same
## honest rules a squadmate is.
##
## **Three tiers, three different fights.**
##
##   * **EASY** - makeshift steel and rags: clubs, a wooden shield, no anoint at
##     all. The AI closes in a straight line, swings on a long beat and almost
##     never guards.
##   * **MEDIUM** - leather and mail, real blades and a proper bow, one anointed
##     piece between the three. It guards on half its exchanges, holds a beat
##     before it swings and steps off the line, and the bow works the range it
##     wants instead of standing.
##   * **HARD** - plate, greatswords and a longbow, an annointed piece on every
##     body. It guards most exchanges, leads its swings at where the body is
##     going, casts what its steel knows and never stands still for free.
##
## Nothing here is a quest and nothing is gated: the ring is a place a warband
## walks into to find out whether its gear and its hands are good enough, and the
## purse it can make is the only thing it keeps.
##
## How a foe fights is not this file's: the ladder - close, guard, step off the
## line, swing into the beat - is `duel_brain.gd`, and the Hollow's own demon
## lords fight on the same one. This scene only dresses the bodies, hands the
## ladder its tier and writes the answer into the foe's hands.

const RingScript = preload("res://scripts/warband/arena_ring.gd")
const BodyScript = preload("res://scripts/warband/warband_body.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const WarbandLooks = preload("res://scripts/warband/warband_looks.gd")
const DuelBrainScript = preload("res://scripts/warband/duel_brain.gd")
const VoiceLibrary = preload("res://scripts/audio/voice_library.gd")
const AnnointCatalog = preload("res://scripts/warband/annoint_catalog.gd")

const DIFFICULTIES := ["easy", "medium", "hard"]
const DEFAULT_DIFFICULTY := "easy"

## What the three foes are: a tank, a blade and a bow, in that order.
const ROLES := ["tank", "melee", "bow"]

## The three kits. `armor` is an `ArmorData.SET_IDS` entry worn on every slot the
## set has; `annoints` says how many ability welds the body's main hand carries.
const KITS := {
	"easy": [
		{"main": "club_makeshift", "off": "shield_wood", "armor": "makeshift", "annoints": 0},
		{"main": "dagger_ironwood", "off": "", "armor": "makeshift", "annoints": 0},
		{"main": "dagger_ironwood", "off": "", "armor": "makeshift", "annoints": 0},
	],
	"medium": [
		{"main": "sword_arming", "off": "shield_buckler", "armor": "mail", "annoints": 1},
		{"main": "dagger_iron", "off": "sword_short", "armor": "leather", "annoints": 0},
		{"main": "bow_short", "off": "", "armor": "leather", "annoints": 0},
	],
	"hard": [
		{"main": "sword_great", "off": "", "armor": "plate", "annoints": 2},
		{"main": "sword_short", "off": "dagger_iron", "armor": "plate", "annoints": 1},
		{"main": "bow_long", "off": "", "armor": "mail", "annoints": 1},
	],
}

## How each tier behaves. `guard` is the share of exchanges a body raises its
## guard on, `beat` the pause it holds before a swing, `step` the seconds it
## spends circling between blows, `lead` how far it aims ahead of a moving body,
## `range` where it stops closing. These are the numbers `duel_brain.gd` fights
## on; a temper without `window` swings on its beat alone, which is the ring's own
## rule - only the Hollow's duelists wait for an opening.
const TEMPER = {
	"easy": {"guard": 0.15, "beat": 0.85, "step": 0.35, "lead": 0.0, "range": 1.6},
	"medium": {"guard": 0.5, "beat": 0.45, "step": 0.6, "lead": 0.35, "range": 2.4},
	"hard": {"guard": 0.85, "beat": 0.15, "step": 0.85, "lead": 0.8, "range": 3.2},
}

## The purse a win pays, by tier.
const PURSE := {"easy": 40, "medium": 120, "hard": 300}

var host = null
var ring: Node3D = null
var active := false
var finished := ""
var difficulty := DEFAULT_DIFFICULTY
var foes: Array = []
var party: Array = []
## `{body: {position, bounds, mask}}` for the field as it was before the ring.
var _saved: Dictionary = {}
## `{foe: DuelBrain}` - each foe's own clock inside the fight's ladder.
var _tracks: Dictionary = {}
## The squad's own hostile list as it was before the ring borrowed it.
var _squad_watchers = null
var _clock := 0.0


func setup(world: Node3D) -> void:
	host = world


func is_open() -> bool:
	return active


## Which difficulty the ring will be fought on. Unknown words are refused.
func set_difficulty(tier: String) -> bool:
	if not DIFFICULTIES.has(tier):
		return false
	difficulty = tier
	return true


## Walk the field into the ring. The whole field goes: a demo that let a player
## leave two bodies at the gate would be a fight the warband wins with a roster
## the ring never sees.
func enter(tier: String = "") -> Dictionary:
	if active:
		return {"ok": false, "message": "The ring is already holding a fight."}
	if host == null:
		return {"ok": false, "message": "The ring needs a campaign."}
	if not tier.is_empty():
		set_difficulty(tier)
	var built := _collect_party()
	if built.is_empty():
		return {"ok": false, "message": "No body to put in the ring."}
	_build_ring()
	_party_into_ring(built)
	_foes_into_ring()
	_lend_the_squad()
	active = true
	finished = ""
	_clock = 0.0
	if host.hud != null:
		host.hud.set_status("THE ARENA  ·  %s  ·  the gate is G when it is over" % difficulty.to_upper(), 4.0)
	return {"ok": true, "message": "The ring holds %d." % foes.size()}


## Out of the ring, back to where the party stood. Safe to call when it is not
## open (a scene reload, a guest leaving).
func leave() -> void:
	if ring != null and is_instance_valid(ring):
		ring.queue_free()
	ring = null
	for foe in foes:
		if is_instance_valid(foe):
			(foe as Node).queue_free()
	foes.clear()
	for entry in _saved.keys():
		var body = entry
		if not is_instance_valid(body):
			continue
		var spot: Dictionary = _saved[entry]
		(body as Node3D).global_position = spot["position"]
		body.bounds = float(spot["bounds"])
		if body.combat != null:
			body.combat.target_mask = int(spot["mask"])
		if body.has_method("accept_network_input"):
			body.accept_network_input(Vector2.ZERO, false)
	_restore_the_squad()
	_saved.clear()
	_tracks.clear()
	party.clear()
	active = false
	finished = ""


## The gate's own press: only a finished fight lets a body out.
func try_leave() -> bool:
	if not active:
		return false
	if finished.is_empty():
		if host != null and host.hud != null:
			host.hud.set_status("Not yet: somebody is still standing across the ring.", 2.5)
		return true
	leave()
	if host != null and host.hud != null:
		host.hud.set_status("THE ARENA  ·  out of the ring", 3.0)
	return true


func foes_standing() -> int:
	var count := 0
	for foe in foes:
		if is_instance_valid(foe) and bool(foe.get("alive")) and not bool(foe.get("downed")):
			count += 1
	return count


func party_standing() -> int:
	var count := 0
	for body in party:
		if is_instance_valid(body) and bool(body.get("alive")) and not bool(body.get("downed")):
			count += 1
	return count


# --- the frame -------------------------------------------------------------

func tick(delta: float) -> void:
	if not active:
		return
	_clock += delta
	_drive_foes(delta)
	# The foes are bodies this scene owns, not the soul controller's: nothing else
	# steps them, so the ring is where they are integrated - intent first, then
	# the one `step()` a frame the controller gives its own squad.
	var actors: Array = _actors()
	for foe in foes:
		if not is_instance_valid(foe):
			continue
		# A foe on its chest is out of the fight, and the ring is not a place to
		# leave somebody bleeding: the body is finished where it lies so the ring
		# reads as a ring and the loot window has a corpse to open.
		if bool(foe.get("downed")):
			foe.take_damage(1.0, 99)
			continue
		if not bool(foe.get("alive")):
			continue
		foe.step(delta, actors, int(_clock * 60.0))
	if finished.is_empty():
		if foes_standing() == 0:
			_finish("won")
		elif party_standing() == 0:
			_finish("lost")


func _finish(result: String) -> void:
	finished = result
	if host == null or host.hud == null:
		return
	if result == "won":
		var purse := int(PURSE.get(difficulty, 0))
		if host.warband != null and purse > 0:
			host.warband.award_gold(purse)
		host.hud.set_status("THE RING IS YOURS  ·  %d gold  ·  G at the gate" % purse, 6.0)
	else:
		host.hud.set_status("THE RING TAKES THE BAND  ·  G at the gate", 6.0)


# --- the ring and the field ------------------------------------------------

func _collect_party() -> Array:
	var out: Array = []
	if host.controller == null:
		return out
	for merc_id in host.warband.alive_merc_ids():
		if host.warband.roster.is_reserve(merc_id):
			continue
		var body = host.controller.body_of(merc_id)
		if body != null and is_instance_valid(body) and bool(body.get("alive")):
			out.append(body)
	return out


func _build_ring() -> void:
	if ring != null and is_instance_valid(ring):
		return
	ring = RingScript.new()
	ring.name = "ArenaRing"
	# The ring's geometry is authored around its own origin; the pad's height is
	# the node's position, so a body's post (`RingScript.entry_post`) is world
	# space and the floor it lands on is exactly under it.
	ring.position = RingScript.centre()
	host.add_child(ring)


func _party_into_ring(field: Array) -> void:
	party = field
	for index in field.size():
		var body = field[index]
		_saved[body] = {
			"position": (body as Node3D).global_position,
			"bounds": float(body.get("bounds")),
			"mask": int(body.combat.target_mask) if body.combat != null else 1,
		}
		# The campaign's bodies carry a 31.5 m square around the origin as their
		# whole world, and the ring stands 260 m up and 26 m across: a body that
		# kept its bound could not take a step in it.
		body.bounds = 6000.0
		if body.combat != null:
			body.combat.target_mask = 4
		(body as Node3D).global_position = RingScript.entry_post(index, field.size())
		(body as Node3D).velocity = Vector3.ZERO
	if host.controller != null:
		var soul_id: int = host.controller.merc_for_peer(host.controller.local_peer_id)
		if soul_id > 0:
			var soul = host.controller.body_of(soul_id)
			if soul != null and is_instance_valid(soul):
				host.controller.activate(host.controller.local_peer_id, soul_id)


func _foes_into_ring() -> void:
	foes.clear()
	_tracks.clear()
	var kits: Array = KITS.get(difficulty, KITS[DEFAULT_DIFFICULTY])
	for index in kits.size():
		var kit: Dictionary = kits[index]
		var body = BodyScript.new()
		body.name = "ArenaFoe%d" % (index + 1)
		body.appearance = WarbandLooks.profile_for(90 + index)
		body.voice_id = VoiceLibrary.profile_for(90 + index)
		host.add_child(body)
		body.authoritative = true
		body.combat.damage_enabled = true
		body.configure(index, "Foe %d" % (index + 1), RingScript.foe_post(index, kits.size()))
		body.bounds = 6000.0
		body.combat.target_mask = 4
		body.is_local = false
		_dress(body, kit)
		foes.append(body)
		# One `DuelBrain` per foe: its own guard window, beat and circling side.
		_tracks[body] = DuelBrainScript.new()



## Put a tier's kit on a body: the set on every slot it has, the blade in the
## main hand, and as many ability welds on that blade as the tier pays for.
func _dress(body, kit: Dictionary) -> void:
	var set_id := str(kit.get("armor", "makeshift"))
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = ArmorData.NONE
	var set_index: int = ArmorData.SET_IDS.find(set_id)
	if set_index >= 0:
		for slot in ArmorData.SLOTS:
			pieces[str(slot)] = set_index
	var main_id := str(kit.get("main", ""))
	var off_id := str(kit.get("off", ""))
	var anointed: Array[String] = []
	var wanted := int(kit.get("annoints", 0))
	if wanted > 0 and not main_id.is_empty():
		for entry in AnnointCatalog.for_item(State.ITEMS.get(main_id, {})):
			if anointed.size() >= wanted:
				break
			if int(entry.kind) == AnnointCatalog.Kind.ABILITY:
				anointed.append(str(entry.id))
	body.rig.apply_loadout(State.build_loadout(main_id, off_id, pieces, {}, anointed))


# --- the foes' brains ------------------------------------------------------

func _drive_foes(delta: float) -> void:
	var temper: Dictionary = TEMPER.get(difficulty, TEMPER[DEFAULT_DIFFICULTY])
	for foe in foes:
		if not is_instance_valid(foe):
			continue
		if not bool(foe.get("alive")) or bool(foe.get("downed")):
			continue
		_drive_foe(foe, temper, delta)


## One foe's tick: the ladder in `duel_brain.gd` decides, this scene only hands
## the decision to the body's own hands - a guard, a draw, a swing, a step.
func _drive_foe(foe, temper: Dictionary, delta: float) -> void:
	var brain = _tracks.get(foe)
	if brain == null:
		brain = DuelBrainScript.new()
		_tracks[foe] = brain
	var target = _nearest_body(foe)
	if target == null:
		foe.accept_network_input(Vector2.ZERO, false)
		return
	var here: Vector3 = (foe as Node3D).global_position
	var at: Vector3 = (target as Node3D).global_position
	var weapon := str(foe.rig.weapon)
	var answer: Dictionary = brain.tick(delta, temper, {
		"position": here,
		"target": at,
		"target_velocity": _velocity_of(target),
		"weapon": weapon,
		"ready": _blade_free(foe),
		"can_draw": bool(foe.combat.can_draw()),
		"blocking": bool(foe.combat.blocking),
		"swing": "stab" if weapon == "dagger" else "overhead",
	})
	if bool(answer["guard"]):
		foe.combat.start_block(at - here)
	else:
		foe.combat.stop_block()
	if bool(answer["draw"]):
		foe.combat.begin_draw()
		foe.accept_network_input(Vector2.ZERO, false)
		return
	var variant := str(answer["swing"])
	if not variant.is_empty():
		foe.combat.begin_melee("right", variant)
	var move: Vector3 = answer["move"]
	_steer(foe, move, bool(answer["run"]))


## Walk a body: the one movement write. `running` decides the pace.
func _steer(foe, direction: Vector3, running: bool) -> void:
	if direction.length_squared() <= 0.000001 or foe.has_method("accept_network_input") == false:
		return
	foe.accept_network_input(Vector2(direction.x, direction.z), running)


## How a body is moving this tick, for the brain's lead: a body that is not one
## of the field's (a fixture, a corpse) is standing still.
func _velocity_of(target) -> Vector3:
	var velocity = target.get("velocity")
	return Vector3(velocity.x, 0.0, velocity.z) if velocity != null else Vector3.ZERO


## The band's own squad fights what is in front of it, and the world's one hostile
## list is the wood's: the ring hands the allies the foes for the length of the
## fight and takes them back afterwards, so a camp of wardens is not hunted
## through a stone wall.
func _lend_the_squad() -> void:
	if host.squad == null:
		return
	_squad_watchers = host.squad.watchers
	host.squad.watchers = foes
	host.squad.following = true
	host.squad.engage_radius = 60.0


func _restore_the_squad() -> void:
	if host == null or host.squad == null:
		return
	if _squad_watchers != null:
		host.squad.watchers = _squad_watchers
	_squad_watchers = null


## Every body in the ring, for the step's own collision and reach queries.
func _actors() -> Array:
	var out: Array = []
	for body in party:
		if is_instance_valid(body):
			out.append(body)
	for foe in foes:
		if is_instance_valid(foe):
			out.append(foe)
	return out


func _nearest_body(foe):
	var best = null
	var best_distance := INF
	for body in party:
		if not is_instance_valid(body) or not bool(body.get("alive")) or bool(body.get("downed")):
			continue
		var distance: float = (foe as Node3D).global_position.distance_to(
			(body as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## The same gate `Combat.begin_melee` applies, asked before the swing so a body
## still recovering is never handed a blow that would be refused.
func _blade_free(foe) -> bool:
	if str(foe.rig.weapon) not in ["sword", "dagger", "dual"]:
		return false
	return float(foe.combat.clash_cooldown) <= 0.0 \
		and float(foe.combat.attack_progress) >= 0.999 \
		and bool(foe.rig.can_begin_melee("right"))
