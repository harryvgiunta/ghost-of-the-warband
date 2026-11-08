class_name RunDirector
extends Node
## The run director: one arena campaign from the Start Run Portal to the last
## portal, and the host-authoritative owner of everything inside it.
##
## What it owns: the stage seed, the island being fought on, the wave budget and
## its queue, the mobs it spawns (their names, factions, elites and bosses), the
## crystals and keys a run pays, the reward chests and pedestals, the Greed Totem,
## the shop island, the biome portals and their votes, and the downed/revive
## contract of co-op.
##
## What it does not own: damage (the shared `Combat` and the mob classes), health
## (the bodies), movement (the possession controller) or the mod engine (each
## player's `RoguelitePlayer`). It asks those systems and reports what happened.
##
## Co-op shape. The host runs the whole loop. Guests receive three kinds of
## reliable event - `state` (which island and wave), `prop` (which chest or
## portal exists, with its serial), and `mob` (a spawned hostile, named so the
## session's snapshots find it) - plus unreliable `fx` flashes. Their inputs
## arrive as requests: start, use a prop, choose a draft, buy a ware, vote a
## portal, swap hands. No guest ever spawns a wave, rolls a chest or applies a
## proc.

signal state_changed

const StageScript = preload("res://scripts/roguelite/roguelite_stage.gd")
const PlayerScript = preload("res://scripts/roguelite/run_player.gd")
const Props = preload("res://scripts/roguelite/roguelite_props.gd")
const ProcFx = preload("res://scripts/roguelite/proc_fx.gd")
const ProcProjectile = preload("res://scripts/roguelite/proc_projectile.gd")
const Mods = preload("res://scripts/roguelite/mod_catalog.gd")
const Weapons = preload("res://scripts/roguelite/weapon_registry.gd")
const State = preload("res://scripts/player_state.gd")
const ArmorData = preload("res://scripts/armor_data.gd")
const CombatScript = preload("res://scripts/combat.gd")
const ArrowScript = preload("res://scripts/arrow.gd")
const PlayerArcher = preload("res://scripts/archer.gd")
const ThrownScript = preload("res://scripts/thrown_weapon.gd")
const WatcherScript = preload("res://scripts/warband/cage_watcher.gd")
const ArcherScript = preload("res://scripts/warband/watcher_archer.gd")
const DevilScript = preload("res://scripts/devil_mob.gd")
const CloneScript = preload("res://scripts/ranger_clone.gd")
const DamageNumbers = preload("res://scripts/damage_numbers.gd")

const MAX_STAGES := 6
const WAVES_PER_STAGE := 3
## The live cap and the spawn cadence: a wave is a queue that feeds the island,
## not a hundred bodies dropped on one frame.
const LIVE_CAP_BASE := 12
const LIVE_CAP_PER_PLAYER := 4
const SPAWN_INTERVAL := 0.42
const WAVE_GAP := 2.2
const FIRST_WAVE_DELAY := 1.6
const INTERACT_REACH := 3.4
const RETARGET_INTERVAL := 0.9
## Bases by island: the budget a stage's wave spends before the party multiplier.
const STAGE_BUDGET := [10.0, 15.0, 21.0, 28.0, 36.0, 45.0]
const WAVE_GROWTH := 1.28

## The three factions and what every biome fields. `cost` is the budget a body
## spends; `kind` is which class builds it.
const FACTIONS := {
	"watchers": [
		{"kind": "watcher", "species": "hollow_runt", "cost": 1.0, "weight": 5},
		{"kind": "watcher", "species": "hollow_warden", "cost": 3.0, "weight": 4},
		{"kind": "archer", "species": "hollow_warden", "cost": 4.0, "weight": 2},
	],
	"demons": [
		{"kind": "devil", "species": "spawn", "cost": 1.0, "weight": 4},
		{"kind": "devil", "species": "hell_goat", "cost": 2.0, "weight": 4},
		{"kind": "devil", "species": "succubus", "cost": 3.0, "weight": 3},
		{"kind": "devil", "species": "beast", "cost": 3.5, "weight": 2},
		{"kind": "devil", "species": "gargoyle", "cost": 4.5, "weight": 1},
	],
	# The pit fields its own: a wave of blood clones, never a watcher. Each
	# biome's table is its faction and nothing borrowed from another island.
	"clones": [
		{"kind": "clone", "species": "", "cost": 3.0, "weight": 5},
		{"kind": "clone", "species": "", "cost": 3.0, "weight": 5},
	],
}

## The boss each faction sends on its last wave.
const BOSSES := {
	"watchers": {"kind": "archer", "species": "hollow_warden", "cost": 10.0, "boss": true},
	"demons": {"kind": "devil", "species": "gargoyle", "cost": 10.0, "boss": true},
	"clones": {"kind": "clone", "species": "", "cost": 10.0, "boss": true},
}

var world = null
var stage = null
var players: Dictionary = {}      # peer_id -> RoguelitePlayer
var run_active := false
var run_seed := 0
var stage_index := 0
var biome_id := "wilderness"
var wave := 0
var waves_this_stage := WAVES_PER_STAGE
var wave_active := false
var stage_cleared := false
var boss_wave := false
var crystals := 0
var total_kills := 0
var keys_earned := 0
var votes: Dictionary = {}        # peer_id -> biome id
var draft_offers: Dictionary = {} # serial -> Array[String]
var shop_wares: Dictionary = {}   # serial -> Array[Dictionary]

var _rng := RandomNumberGenerator.new()
var _saved: Dictionary = {}
var _mobs: Array = []
var _mob_specs: Dictionary = {}   # instance id -> spec
var _props: Array = []
var _props_by_serial: Dictionary = {}
var _opened: Dictionary = {}
## Which peers have already taken a chest's, pedestal's or totem's offer. One
## prop, one helping each: a four-player party does not lose three drafts because
## one body reached the pedestal first.
var _users: Dictionary = {}
var _queue: Array[Dictionary] = []
var _spawn_clock := 0.0
var _wave_clock := 0.0
var _retarget_clock := 0.0
var _serial := 0
var _mob_serial := 0
var _killed: Dictionary = {}
var _down_clock := 0.0
var _throw_clock: Dictionary = {}  # peer -> seconds
var _throw_charges: Dictionary = {}  # peer -> charges
## Each guest's chosen hands, sent to the host because the host is the one that
## dresses every body in a run. Keyed by peer id.
var guest_loadouts: Dictionary = {}
var _loadout_sent_seed := -1
var _client := false


# --- lifecycle -------------------------------------------------------------

func setup(world_node: Node3D) -> void:
	world = world_node
	_client = bool(world.get("_client")) if world != null else false


func is_running() -> bool:
	return run_active


func is_client() -> bool:
	return _client


func player_for(body) -> Variant:
	if body == null or not is_instance_valid(body):
		return null
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run) and run.body == body:
			return run
	return null


func player_of_peer(peer_id: int):
	return players.get(peer_id)


func local_peer() -> int:
	if world == null or world.get("controller") == null:
		return 1
	return int(world.controller.local_peer_id)


func party_size() -> int:
	var session = _session()
	if session != null and session.has_method("peer_count"):
		return maxi(1, int(session.peer_count()))
	# Offline, the wave belongs to one soul even when the square lent a squad:
	# the budget contract is per *connected player*, and an AI body is not one.
	return 1


## BEGIN. Host only: starts a fresh seed, dresses the party in the loadout they
## chose in town, stands the first island under their feet and queues its first
## wave. A guest's press is a request to the host.
func start_run() -> Dictionary:
	if run_active:
		return {"ok": false, "message": "A run is already live."}
	if _client:
		var request := {"t": "start", "loadout": _local_loadout()}
		send_request(request)
		return {"ok": true, "message": "The host is opening a run."}
	if world == null or world.get("controller") == null:
		return {"ok": false, "message": "The arena needs a campaign around it."}
	var built := _collect_party()
	if built.is_empty():
		return {"ok": false, "message": "No body to put in the arena."}
	run_seed = randi() & 0x7fffffff
	_rng.seed = run_seed
	run_active = true
	stage_index = 0
	stage_cleared = false
	wave = 0
	crystals = 0
	total_kills = 0
	keys_earned = 0
	votes.clear()
	draft_offers.clear()
	shop_wares.clear()
	# A run's prop serials start at one again: a stale `_opened` from the last run
	# would spend this run's first chest before it was ever touched.
	_opened.clear()
	_killed.clear()
	_serial = 0
	_mob_serial = 0
	_begin_stage(_first_biome(), built)
	_broadcast_state()
	var line := "THE RUN OPENS  ·  %s  ·  island 1 of %d" % [
		StageScript.biome(biome_id).name, MAX_STAGES]
	_status(line)
	return {"ok": true, "message": line}


func _first_biome() -> String:
	# The wood always opens the run: it is the one island that teaches the loop
	# before a demon or a clone asks a harder question.
	return "wilderness"


func _begin_stage(new_biome: String, field: Array = []) -> void:
	biome_id = new_biome
	wave = 0
	wave_active = false
	stage_cleared = false
	queue_clear()
	_clear_stage_props()
	_free_mobs()
	votes.clear()
	_build_stage()
	_move_party_in(field if not field.is_empty() else _collect_party())
	_spawn_runners()
	waves_this_stage = WAVES_PER_STAGE + (1 if stage_index >= 3 else 0)
	_wave_clock = FIRST_WAVE_DELAY
	stage_cleared = false
	state_changed.emit()


func _build_stage() -> void:
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = StageScript.new()
	stage.name = "RogueliteIsland"
	stage.stage_index = stage_index
	stage.position = StageScript.centre_for(stage_index)
	world.add_child(stage)
	stage.build(biome_id, run_seed, stage_index)


## Bring the whole field onto the island. A body's own world is the campaign's
## 1900 m square; an island is 34 m across, so the bound is lifted and the body
## is put on its entry post. The campaign seat is saved and restored on the way
## out, exactly as the arena ring does it.
func _collect_party() -> Array:
	var out: Array = []
	if world == null or world.get("controller") == null:
		return out
	for body in _world_bodies():
		if is_instance_valid(body) and _flag(body, "alive", true):
			out.append(body)
	return out


func _move_party_in(field: Array) -> void:
	var posts: Array[Vector3] = stage.entry_posts(field.size()) if stage != null else []
	for index in field.size():
		var body = field[index]
		if not is_instance_valid(body):
			continue
		# The seat to return to is the campaign's, saved on the first island and
		# never overwritten by an island post on the way through.
		if not _saved.has(body):
			_saved[body] = {
				"position": (body as Node3D).global_position,
				"bounds": _num(body, "bounds", 31.5),
				"mask": int(body.combat.target_mask) if body.combat != null else 2,
				"weapon": str(body.rig.get("weapon")) if body.get("rig") != null else "",
			}
		body.bounds = 6000.0
		if body.combat != null:
			body.combat.target_mask = 2
		var post: Vector3 = posts[index] if index < posts.size() else stage.floor_point(Vector2.ZERO)
		(body as Node3D).global_position = post
		(body as Node3D).velocity = Vector3.ZERO
		if body.has_method("revive_from_downed") and _flag(body, "downed", false):
			body.revive_from_downed(1.0)


## One runtime per body. The loadout it applies is the one the rack bound: the
## body's hands become the ranged piece, and TAB reaches the melee piece, without
## the campaign's roster ever being written.
func _spawn_runners() -> void:
	# A body that already has a runtime keeps it: the mods are the *run's*, not
	# the island's, and a fresh engine on every portal would delete the draft the
	# party just fought for.
	var previous := players
	players.clear()
	for body in _world_bodies():
		if not is_instance_valid(body) or not _flag(body, "alive", true):
			continue
		var merc := _merc_of(body)
		var peer := _peer_of_merc(merc)
		var run = null
		for old_peer in previous:
			var candidate = previous[old_peer]
			if candidate != null and is_instance_valid(candidate) and candidate.body == body:
				run = candidate
				break
		if run != null and is_instance_valid(run):
			run.director = self
			run.peer_id = peer
			run.merc_id = merc
			players[peer] = run
			if body.get("combat") != null:
				body.combat.ammo_gate = Callable()
			_apply_hands(run, "ranged")
			_throw_charges[peer] = int(Weapons.resolve(run.melee_id).get("throw_charges", 0))
			_throw_clock[peer] = 0.0
			run.apply_stats()
			continue
		var ranged := _loadout_for(peer, "ranged")
		var melee := _loadout_for(peer, "melee")
		run = PlayerScript.new()
		world.add_child(run)
		run.bind(body, self, peer, merc, ranged, melee)
		run._active_slot = "ranged"
		players[peer] = run
		if body.get("combat") != null:
			body.combat.ammo_gate = Callable()
		_apply_hands(run, "ranged")
		_throw_charges[peer] = int(Weapons.resolve(melee).get("throw_charges", 0))
		_throw_clock[peer] = 0.0
		run.apply_stats()
		if float(body.health) <= 1.0:
			body.health = float(body.max_health)


func _merc_of(body) -> int:
	if world == null or world.get("controller") == null:
		return -1
	return int(world.controller.merc_of(body))


func _peer_of_merc(merc_id: int) -> int:
	if world == null or world.get("controller") == null:
		return 1
	for peer in world.controller.possessing_peers():
		if int(world.controller.merc_for_peer(peer)) == merc_id:
			return int(peer)
	# An unpossessed squadmate fights under its own mercenary id.
	return 1000 + maxi(1, merc_id)


func _roster_loadout(slot: String) -> String:
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("loadout_for"):
		return str(meta.loadout_for(slot))
	return "bow_twig" if slot == "ranged" else "hatchet_makeshift"


## The hands a body enters with. A guest's own choice is the guest's: it arrives
## with the start request (or a moment after the first state), is validated
## against the registry, and only then becomes that body's pair.
func _loadout_for(peer_id: int, slot: String) -> String:
	if peer_id != local_peer() and guest_loadouts.has(peer_id):
		var table: Dictionary = guest_loadouts[peer_id]
		var id := str(table.get(slot, ""))
		if Weapons.has(id) and Weapons.slot_of(id) == slot:
			return id
	return _roster_loadout(slot)


func _local_loadout() -> Dictionary:
	var meta = get_node_or_null("/root/Roguelite")
	if meta == null:
		return {"ranged": "bow_twig", "melee": "hatchet_makeshift"}
	return {"ranged": str(meta.loadout_for("ranged")),
		"melee": str(meta.loadout_for("melee"))}


func remember_loadout(peer_id: int, table: Variant) -> void:
	if typeof(table) != TYPE_DICTIONARY:
		return
	var raw: Dictionary = table
	var clean := {}
	for slot in ["ranged", "melee"]:
		var id := str(raw.get(slot, ""))
		if Weapons.has(id) and Weapons.slot_of(id) == slot:
			clean[slot] = id
	if clean.size() == 2:
		guest_loadouts[peer_id] = clean


## Dress the body for one hand without touching the roster: the campaign's kit
## keeps its armour, trinkets and copies; only the held piece and the pose change.
func _apply_hands(run, slot: String) -> void:
	if run == null or not is_instance_valid(run) or run.body == null:
		return
	var weapon_id := str(run.ranged_id) if slot == "ranged" else str(run.melee_id)
	if _dress_weapon(run.body, run.merc_id, weapon_id):
		run._active_slot = slot


## Put one weapon in a body's hands while keeping everything else it wears. The
## roster is never written: a run's weapons are the run's, and the piece the
## campaign gave the body is still in its ledger when the island is done with it.
func _dress_weapon(body, merc_id: int, weapon_id: String) -> bool:
	if body == null or not is_instance_valid(body) or weapon_id.is_empty():
		return false
	var profile := Weapons.resolve(weapon_id)
	if profile.is_empty():
		return false
	var gear: Dictionary = {}
	if world != null and world.get("warband") != null and merc_id > 0:
		gear = world.warband.roster.equipped_of(merc_id)
	var pieces := {}
	for armor_slot in ArmorData.SLOTS:
		var item_id := str(gear.get(str(armor_slot), ""))
		pieces[armor_slot] = int((State.ITEMS.get(item_id, {}) as Dictionary).get("set", ArmorData.NONE))
	var trinkets := {
		"neck": str(gear.get("neck", "")),
		"ring1": str(gear.get("ring1", "")),
		"ring2": str(gear.get("ring2", "")),
		"off": "",
	}
	var loadout: Dictionary = State.build_loadout(weapon_id, "", pieces, trinkets, [])
	if body.get("rig") != null and body.rig.has_method("apply_loadout"):
		body.rig.apply_loadout(loadout)
	if body.get("combat") != null:
		body.combat.stop()
	return true


## The Town Hub's own dress: a body standing in the square holds the ranged
## piece the rack bound, so what is chosen at the rack is what is seen and what
## the portal then carries onto the island. The world calls this on entry and
## calls `controller.refresh_gear` on exit - the campaign's kit is never
## overwritten, only set aside while the body is inside the walls.
func dress_body_ranged(body) -> void:
	if world == null or run_active or not is_instance_valid(body):
		return
	var merc := _merc_of(body)
	if merc <= 0:
		return
	_dress_weapon(body, merc, _roster_loadout("ranged"))


## TAB inside a run. The campaign's swap is a roster verb; an arena run's swap is
## the other hand of the same choice, and it is the host's to make for a guest.
func swap_hands(body) -> void:
	var run = player_for(body)
	if run == null:
		return
	# Cursed Arsenal locks the *pieces*, not the hands: the pair cannot be
	# replaced for the rest of the run, but a body still reaches both of them.
	var next := "melee" if str(run._active_slot) == "ranged" else "ranged"
	if _client:
		send_request({"t": "swap"})
		_apply_hands(run, next)
		return
	_apply_hands(run, next)
	_broadcast({"t": "hands", "peer": run.peer_id, "slot": next})


# --- the frame -------------------------------------------------------------

func tick(delta: float) -> void:
	if not run_active:
		return
	_tick_throw_regen(delta)
	if _client:
		state_changed.emit()
		return
	if stage_cleared:
		_tick_down_check(delta)
		state_changed.emit()
		return
	if not wave_active:
		_wave_clock -= delta
		if _wave_clock <= 0.0:
			_begin_wave()
		state_changed.emit()
		return
	_spawn_clock -= delta
	if _spawn_clock <= 0.0 and not _queue.is_empty() and _live_mobs() < _live_cap():
		_spawn_clock = SPAWN_INTERVAL
		_spawn_from_queue()
	_retarget_clock += delta
	if _retarget_clock >= RETARGET_INTERVAL:
		_retarget_clock = 0.0
		_retarget_mobs()
	_tick_down_check(delta)
	if _queue.is_empty() and _live_mobs() == 0:
		_clear_wave()
	state_changed.emit()


func _tick_throw_regen(delta: float) -> void:
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		var def: Dictionary = Weapons.resolve(run.melee_id)
		var regen := float(def.get("throw_regen", 0.0))
		var cap := int(def.get("throw_charges", 0))
		if regen <= 0.0 or cap <= 0:
			continue
		_throw_clock[peer] = float(_throw_clock.get(peer, 0.0)) + delta
		if float(_throw_clock[peer]) >= regen:
			_throw_clock[peer] = 0.0
			_throw_charges[peer] = mini(cap, int(_throw_charges.get(peer, 0)) + 1)


func _tick_down_check(_delta: float) -> void:
	var standing := 0
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		if not run.is_downed():
			standing += 1
	# A cleared island is not a wipe: bodies on the dirt are waiting for the
	# chest to raise them. Only a live wave with nobody standing ends the run.
	if standing == 0 and not players.is_empty() and wave_active:
		_finish_run(false)


# --- waves -----------------------------------------------------------------

func _begin_wave() -> void:
	wave += 1
	wave_active = true
	boss_wave = wave == waves_this_stage and stage_index in [2, 5]
	_queue.clear()
	var budget := wave_budget()
	if boss_wave:
		_queue.append(BOSSES.get(StageScript.biome(biome_id).faction, BOSSES["watchers"]))
		budget -= 10.0
	# Elites from the second wave on: a heavier body every other wave, and the
	# last wave of a stage always carries one.
	if wave >= 2 and not boss_wave:
		var elite_spec := _pick_spec(true)
		if not elite_spec.is_empty():
			_queue.append(elite_spec)
			budget -= float(elite_spec.cost)
	while budget > 0.0:
		var spec := _pick_spec(false)
		if spec.is_empty():
			break
		_queue.append(spec)
		budget -= maxf(0.5, float(spec.cost))
	_wave_clock = 0.0
	_spawn_clock = 0.0
	var line := "WAVE %d / %d  ·  %d bodies inbound" % [wave, waves_this_stage, _queue.size()]
	if boss_wave:
		line = "FINAL WAVE  ·  %s STIRS" % str(StageScript.biome(biome_id).name)
	_status(line)
	_broadcast_state()


## The wave's spend. Co-op scales it by +50% for every player past the first,
## which is the contract the brief names: two bodies do not fight the same wave.
func wave_budget() -> float:
	var base: float = float(STAGE_BUDGET[clampi(stage_index, 0, STAGE_BUDGET.size() - 1)])
	var growth := pow(WAVE_GROWTH, float(maxi(0, wave - 1)))
	var party := 1.0 + 0.5 * float(maxi(0, party_size() - 1))
	return base * growth * party


func _pick_spec(force_elite: bool) -> Dictionary:
	var faction := str(StageScript.biome(biome_id).faction)
	var pool: Array = FACTIONS.get(faction, FACTIONS["watchers"])
	var rows: Array[Dictionary] = []
	var total := 0.0
	for raw in pool:
		var row: Dictionary = (raw as Dictionary).duplicate(true)
		rows.append(row)
		total += float(row.get("weight", 1.0))
	if rows.is_empty():
		return {}
	var roll := _rng.randf_range(0.0, total)
	var chosen: Dictionary = rows[rows.size() - 1]
	for row in rows:
		roll -= float(row.get("weight", 1.0))
		if roll <= 0.0:
			chosen = row
			break
	chosen = chosen.duplicate(true)
	if force_elite:
		chosen["elite"] = true
		chosen["cost"] = float(chosen.get("cost", 2.0)) * 1.6
	return chosen


func _live_cap() -> int:
	return LIVE_CAP_BASE + LIVE_CAP_PER_PLAYER * maxi(0, party_size() - 1)


func queue_clear() -> void:
	_queue.clear()


func _spawn_from_queue() -> void:
	# Two bodies a beat: enough that a wave arrives as pressure, few enough that
	# the frame a dozen capsules appear on is not the frame a player loses to it.
	var spawned := 0
	while not _queue.is_empty() and spawned < 2:
		var spec: Dictionary = _queue.pop_front()
		var at: Vector3 = stage.random_point(_rng, 6.0) if stage != null else Vector3.ZERO
		_spawn_spec(spec, at)
		spawned += 1
		if _live_mobs() >= _live_cap():
			return


func _live_mobs() -> int:
	var live := 0
	for mob in _mobs:
		if is_instance_valid(mob) and _flag(mob, "alive", true) and not _flag(mob, "replica", false):
			live += 1
	return live


func _retarget_mobs() -> void:
	var bodies := _body_targets()
	for mob in _mobs:
		if not is_instance_valid(mob) or not _flag(mob, "alive", true):
			continue
		if _flag(mob, "replica", false):
			continue
		var nearest = _nearest_body(mob.global_position)
		if "player" in mob:
			mob.player = nearest
		if "targets" in mob:
			mob.targets = bodies


## The bodies a typed mob can hold: `devil_mob.gd` declares its quarry list as
## `Array[CharacterBody3D]`, so an untyped array is a type error at the assignment,
## not a missing property.
func _body_targets() -> Array[CharacterBody3D]:
	var out: Array[CharacterBody3D] = []
	for body in _standing_bodies():
		if body is CharacterBody3D:
			out.append(body)
	return out


func _standing_bodies() -> Array:
	var out: Array = []
	for body in _world_bodies():
		if is_instance_valid(body) and _flag(body, "alive", true) and not _flag(body, "downed", false):
			out.append(body)
	return out


func _nearest_body(at: Vector3):
	var best = null
	var best_distance := INF
	for body in _standing_bodies():
		var distance: float = (body as Node3D).global_position.distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


func _clear_wave() -> void:
	wave_active = false
	_queue.clear()
	if wave < waves_this_stage:
		_wave_clock = WAVE_GAP
		_status("WAVE %d CLEARED  ·  the island breathes" % wave, 2.5)
		return
	_clear_stage()


# --- mob spawning ----------------------------------------------------------

func _spawn_spec(spec: Dictionary, at: Vector3) -> void:
	var life := 1.0 + 0.14 * float(stage_index) + 0.05 * float(wave)
	var rate := 1.0 + 0.05 * float(stage_index) + 0.02 * float(wave)
	if bool(spec.get("elite", false)):
		life *= 1.9
		rate *= 1.12
	if bool(spec.get("boss", false)):
		life *= 3.1
		rate *= 1.15
	# The greed mods that make enemies crueller are the party's own: the worst
	# case of every player is what the island answers with.
	var enemy_damage := 1.0
	var enemy_speed := 1.0
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		enemy_damage = maxf(enemy_damage, 1.0 + run.engine.stat("enemy_damage_mult"))
		enemy_speed = maxf(enemy_speed, 1.0 + run.engine.stat("enemy_speed_mult"))
	rate *= enemy_speed
	var mob = null
	match str(spec.get("kind", "watcher")):
		"devil":
			mob = _build_devil(spec, at, life, rate, enemy_damage)
		"archer":
			mob = _build_watcher(spec, at, life, rate, enemy_damage, true)
		"clone":
			mob = _build_clone(spec, at, life, rate)
		_:
			mob = _build_watcher(spec, at, life, rate, enemy_damage, false)
	if mob == null:
		return
	_mobs.append(mob)
	_mob_specs[mob.get_instance_id()] = spec
	if world != null and world.get("guards") is Array:
		world.guards.append(mob)
	_broadcast({"t": "mob", "name": str(mob.name), "spec": spec,
		"at": mob.global_position, "life": life, "rate": rate,
		"damage": enemy_damage})
	if bool(spec.get("elite", false)) or bool(spec.get("boss", false)):
		_mark_elite(mob, bool(spec.get("boss", false)))


func _mob_name(prefix: String) -> String:
	_mob_serial += 1
	return "Rogue%s_%02d_%04d" % [prefix, stage_index, _mob_serial]


func _build_watcher(spec: Dictionary, at: Vector3, life: float, rate: float,
		damage_scale: float, is_archer: bool):
	var mob = (ArcherScript.new() if is_archer else WatcherScript.new())
	mob.name = _mob_name("A" if is_archer else "W")
	mob.mob_id = str(spec.get("species", "hollow_warden"))
	# The pool is read by `_ready`; the multiplier has to land before the body
	# enters the tree.
	if mob.get("health_pool") != null:
		mob.health_pool = float(mob.get("health_pool")) * life
	mob.position = at
	world.add_child(mob)
	mob.global_position = at
	mob.home = at
	mob.safe_center = stage.global_position
	mob.player = _nearest_body(at)
	# A watcher hunts the nearest body through `player`; only the clone reads a
	# `targets` list, and a class that has no such field is left alone.
	if "targets" in mob:
		mob.targets = _body_targets()
	if is_archer:
		mob.elite = bool(spec.get("elite", false)) or bool(spec.get("boss", false))
		mob.set_anchor(at)
		mob.host = world
	mob.defeated.connect(_on_enemy_defeated)
	if world.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(world, "_on_enemy_attack"))
	# The watcher's dials, after the body exists: the blow it lands and how often.
	if "blow_scale" in mob:
		mob.blow_scale = damage_scale * (1.35 if bool(spec.get("elite", false)) else 1.0)
	if "swing_gap_scale" in mob:
		mob.swing_gap_scale = 1.0 / maxf(rate, 0.05)
	if "windup_scale" in mob:
		mob.windup_scale = 1.0 / maxf(rate, 0.12)
	if mob.has_method("mob_wake"):
		mob.mob_wake()
	if mob.has_method("arm"):
		mob.arm(_watcher_arm())
	return mob


func _watcher_arm() -> String:
	var arms := ["club_makeshift", "axe_makeshift", "sword_short", "dagger_iron"]
	return str(arms[_rng.randi_range(0, arms.size() - 1)])


func _build_devil(spec: Dictionary, at: Vector3, life: float, rate: float,
		damage_scale: float):
	var mob := DevilScript.new()
	var label := _mob_name("D")
	mob.name = label
	mob.mob_id = str(spec.get("species", "hell_goat"))
	mob.position = at
	world.add_child(mob)
	# The mob class renames itself in `_ready`; the stream finds a body by name,
	# so the run's own name has to be the last word.
	mob.name = label
	mob.global_position = at
	mob.home = at
	mob.safe_center = stage.global_position
	mob.player = _nearest_body(at)
	mob.targets = _body_targets()
	mob.defeated.connect(_on_enemy_defeated)
	if world.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(world, "_on_enemy_attack"))
	if mob.has_method("apply_difficulty"):
		mob.apply_difficulty(life, rate)
	if damage_scale > 1.0:
		mob.profile["damage"] = float(mob.profile.get("damage", 8.0)) * damage_scale
	return mob


func _build_clone(spec: Dictionary, at: Vector3, life: float, rate: float):
	var mob := CloneScript.new()
	world.add_child(mob)
	mob.name = _mob_name("C")
	mob.configure(_mob_serial, stage_index + 1 + (2 if bool(spec.get("boss", false)) else 0),
		true, "scene")
	mob.spawn_at(at, at.direction_to(stage.global_position + Vector3(0.0, 0.0, 1.0)))
	mob.targets = _body_targets()
	mob.defeated.connect(_on_enemy_defeated)
	if world.has_method("_on_enemy_attack"):
		mob.attacked.connect(Callable(world, "_on_enemy_attack"))
	if mob.has_method("apply_difficulty"):
		mob.apply_difficulty(life, rate)
	mob.aggro_range = 60.0
	mob.leash = 80.0
	return mob


## Guest-side replica of a host spawn. The session's snapshot stream finds a body
## by name, so the copy must exist before the first state arrives; it runs no AI
## and writes nothing but what the wire says.
func _spawn_replica(event: Dictionary) -> void:
	var spec: Dictionary = event.get("spec", {})
	var at: Vector3 = event.get("at", Vector3.ZERO)
	var mob = null
	var kind := str(spec.get("kind", "watcher"))
	if kind == "devil":
		mob = DevilScript.new()
		mob.mob_id = str(spec.get("species", "hell_goat"))
		world.add_child(mob)
		mob.global_position = at
	elif kind == "clone":
		mob = CloneScript.new()
		world.add_child(mob)
		mob.configure(int(event.get("serial", 0)), stage_index + 1, false, "scene")
		mob.spawn_at(at)
	else:
		mob = (ArcherScript.new() if kind == "archer" else WatcherScript.new())
		# A species is read by `_ready`; a replica must be told before it enters
		# the tree, exactly as a host spawn is.
		mob.mob_id = str(spec.get("species", "hollow_warden"))
		if mob.get("health_pool") != null:
			mob.health_pool = float(mob.get("health_pool")) * maxf(0.1,
				float(event.get("life", 1.0)))
		world.add_child(mob)
		mob.global_position = at
	if mob == null:
		return
	mob.name = str(event.get("name", _mob_name("R")))
	if mob.has_method("mark_replica"):
		mob.mark_replica()
	else:
		mob.set("replica", true)
	if "safe_center" in mob:
		mob.safe_center = stage.global_position
	if bool(spec.get("elite", false)) or bool(spec.get("boss", false)):
		_mark_elite(mob, bool(spec.get("boss", false)))
	_mobs.append(mob)
	if world.get("guards") is Array:
		world.guards.append(mob)


func _mark_elite(mob, boss: bool) -> void:
	if mob == null or not is_instance_valid(mob):
		return
	var label := Label3D.new()
	label.text = "BOSS" if boss else "ELITE"
	label.font_size = 64 if boss else 40
	label.pixel_size = 0.006
	label.modulate = Color(1.0, 0.42, 0.26) if boss else Color(1.0, 0.78, 0.35)
	label.outline_modulate = Color(0.05, 0.03, 0.02, 0.9)
	label.outline_size = 14
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 3.1 if boss else 2.6, 0.0)
	mob.add_child(label)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.4, 0.2)
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position = Vector3(0.0, 2.0, 0.0)
	mob.add_child(light)


func _free_mobs() -> void:
	for mob in _mobs:
		if is_instance_valid(mob):
			if world != null and world.get("guards") is Array and world.guards.has(mob):
				world.guards.erase(mob)
			(mob as Node).queue_free()
	_mobs.clear()
	_mob_specs.clear()


func _on_enemy_defeated(enemy, reward: int) -> void:
	if _client or not is_instance_valid(enemy):
		return
	var id: int = (enemy as Node).get_instance_id()
	if _killed.has(id):
		return
	_killed[id] = true
	var spec: Dictionary = _mob_specs.get(id, {})
	_mobs.erase(enemy)
	if world != null and world.get("guards") is Array and world.guards.has(enemy):
		world.guards.erase(enemy)
	total_kills += 1
	# The kill is the run's, not the campaign's: gold is not paid and a body is
	# not re-armed from it, but the steel still comes out of its hand and the
	# corpse is still searchable, because that is what a fallen thing looks like.
	if world != null:
		if world.has_method("drop_held_weapon"):
			world.drop_held_weapon(enemy)
		if world.get("loot") != null and world.loot.has_method("register_corpse"):
			world.loot.register_corpse(enemy)
	var killer = _killer_of(enemy)
	var mult := 1.0
	if killer != null and is_instance_valid(killer):
		mult = (killer as Object).currency_multiplier()
	var gain := int(ceil(maxf(1.0, float(reward)) * 2.5 * mult))
	_award_crystals(gain)
	# Elites and bosses pay keys; the stage clear pays the rest.
	if bool(spec.get("elite", false)):
		_award_keys(1, "an elite falls")
	elif bool(spec.get("boss", false)):
		_award_keys(3, "the boss falls")
	if bool(spec.get("elite", false)) or bool(spec.get("boss", false)):
		ProcFx.flare(stage, (enemy as Node3D).global_position + Vector3.UP, Color(1.0, 0.7, 0.3), 1.2)
	state_changed.emit()
	# The living count and the purse are on the state: a kill is exactly the
	# moment a guest's plate has to hear about them.
	_broadcast_state()


func _killer_of(enemy) -> Variant:
	var last := int(enemy.get("last_hitter")) if "last_hitter" in enemy else -1
	if last < 0:
		return null
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run) or run.body == null:
			continue
		if int(run.body.get("slot")) == last:
			return run
	return null


func _award_crystals(amount: int) -> void:
	if amount <= 0:
		return
	crystals += amount
	# The party's crystals are one shared purse: the wire carries the new total,
	# not a delta, so a lost or reordered event cannot leave two peers counting
	# different purses.
	_broadcast({"t": "crystals", "total": crystals})


func _award_keys(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	keys_earned += amount
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("award_keys"):
		meta.award_keys(amount, reason)
	_broadcast({"t": "keys", "amount": amount, "reason": reason})


# --- the island's furniture ------------------------------------------------

func _spawn_prop(kind: String, at: Vector3, payload: Dictionary) -> Node3D:
	var node: Node3D = null
	match kind:
		"chest":
			node = Props.chest(stage, at, str(payload.get("tier", "chest")), payload)
		"pedestal":
			node = Props.pedestal(stage, at, payload.get("offers", []), payload)
		"greed":
			node = Props.greed_totem(stage, at, payload)
		"shop":
			node = Props.shop(stage, at, payload.get("wares", []), payload)
		"portal":
			node = Props.portal(stage, at, str(payload.get("biome", "wilderness")),
				str(payload.get("name", "PORTAL")), payload)
	if node == null:
		return null
	_serial += 1
	node.set_meta("serial", _serial)
	_props.append(node)
	_props_by_serial[_serial] = node
	return node


func _broadcast_prop(node: Node3D, kind: String, payload: Dictionary) -> void:
	if node == null:
		return
	_broadcast({"t": "prop", "serial": int(node.get_meta("serial")), "kind": kind,
		"at": node.global_position, "payload": payload})


func _clear_stage_props() -> void:
	for prop in _props:
		if is_instance_valid(prop):
			(prop as Node).queue_free()
	_props.clear()
	_props_by_serial.clear()
	_opened.clear()
	_users.clear()


func _clear_stage() -> void:
	stage_cleared = true
	wave_active = false
	queue_clear()
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		run.stage_clear()
	var key_pay := 2 + int(stage_index / 2)
	_award_keys(key_pay, "island %d cleared" % (stage_index + 1))
	_award_crystals(30 + 12 * stage_index)
	# The reward chest, and the extra mini-chest Buried Cache rolls for.
	var chest_at: Vector3 = stage.rim_point(0, 4)
	var chest = _spawn_prop("chest", chest_at, {"tier": "chest", "stage": stage_index})
	_broadcast_prop(chest, "chest", {"tier": "chest", "stage": stage_index})
	var extra_chance := 0.0
	for peer in players:
		var run = players[peer]
		if run != null and is_instance_valid(run):
			extra_chance = maxf(extra_chance, run.engine.stat("chest_chance"))
	if extra_chance > 0.0 and _rng.randf() < extra_chance:
		var mini = _spawn_prop("chest", stage.rim_point(1, 4), {"tier": "mini"})
		_broadcast_prop(mini, "chest", {"tier": "mini"})
	# The choice: three mods on a pedestal. This is the draft loop.
	var offers := _draft_for_any()
	var pedestal = _spawn_prop("pedestal", stage.rim_point(2, 5), {"offers": offers})
	_broadcast_prop(pedestal, "pedestal", {"offers": offers})
	# The Greed Totem stands on every island, one bargain per run per island.
	var greed := _spawn_prop("greed", stage.rim_point(3, 5), {})
	if greed != null:
		_broadcast_prop(greed, "greed", {})
	# Every second island, a shop: the crystals have somewhere to go.
	if stage_index in [1, 3]:
		var wares := _shop_wares()
		var shop_serial_payload := {"wares": wares}
		var shop = _spawn_prop("shop", stage.rim_point(4, 5), shop_serial_payload)
		shop_wares[int(shop.get_meta("serial"))] = wares
		_broadcast_prop(shop, "shop", shop_serial_payload)
	# Two portals out, until the chest has been opened.
	var choices := _next_biomes()
	for index in choices.size():
		var payload := {"biome": choices[index],
			"name": str(StageScript.biome(choices[index]).name)}
		var portal = _spawn_prop("portal", stage.rim_point(5 + index, 6), payload)
		_broadcast_prop(portal, "portal", payload)
	_status("ISLAND CLEARED  ·  open the chest  ·  the portals wait", 5.0)
	_broadcast_state()


func _draft_for_any() -> Array[String]:
	# The offers are the party's shared draft: rolled once, shown to everyone,
	# and the first player to choose takes one. Excluding a mod already maxed on
	# any body keeps the pedestal from offering a dead row.
	var exclude: Array = []
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		for id in run.engine.stacks:
			if int(run.engine.stacks[id]) >= Mods.max_stacks(str(id)) and not exclude.has(str(id)):
				exclude.append(str(id))
	return Mods.draft(_rng, 3, false, exclude)


func _shop_wares() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := Mods.draft(_rng, 3, false, [])
	for id in ids:
		var price := int(round(28.0 + 14.0 * float(stage_index)
			+ (18.0 if Mods.rarity_of(id) != Mods.RARITY_COMMON else 0.0)))
		out.append({"id": id, "name": Mods.name_of(id), "price": price,
			"rarity": Mods.rarity_of(id)})
	return out


func _next_biomes() -> Array[String]:
	var all := ["wilderness", "caves", "arena"]
	all.erase(biome_id)
	if all.is_empty():
		all = ["arena"]
	# Two distinct choices, in a stable order for the seed.
	all.sort()
	while all.size() < 2:
		all.append(all[0])
	return [all[0], all[1]]


# --- interaction -----------------------------------------------------------

func nearest_prop(at: Vector3, reach: float = INTERACT_REACH) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for prop in _props:
		if not is_instance_valid(prop):
			continue
		var distance: float = (prop as Node3D).global_position.distance_to(at)
		if distance <= best_distance:
			best_distance = distance
			best = prop
	return best


## `G` on the island. True when the press belonged to the arena; the world's own
## loot, cages and town services are then never reached.
func interact(actor) -> bool:
	if not run_active or actor == null or not is_instance_valid(actor):
		return false
	var prop := nearest_prop((actor as Node3D).global_position)
	if prop == null:
		return false
	var kind := Props.prop_kind(prop)
	if kind.is_empty():
		return false
	var serial := int(prop.get_meta("serial", 0))
	if _client:
		var payload := Props.payload_of(prop)
		# The two choices are local windows over host-owned facts: the offers and
		# the wares already arrived with the prop, so the guest picks here and
		# the press that spends anything still goes to the host.
		if kind == "pedestal":
			var hud = world.get("roguelite_hud")
			if hud != null and hud.has_method("open_draft"):
				hud.open_draft(serial, payload.get("offers", []))
				return true
		elif kind == "shop":
			var shop_hud = world.get("roguelite_hud")
			if shop_hud != null and shop_hud.has_method("open_shop"):
				shop_hud.open_shop(serial, payload.get("wares", []))
				return true
		send_request({"t": "use", "serial": serial})
		# A chest opens for everyone at once in the wire's own time; locally the
		# prop stays until the host's `prop_gone` arrives.
		_status("Sent to the host.", 1.5)
		return true
	match kind:
		"chest":
			_open_chest(serial, actor)
		"pedestal":
			_open_draft(serial, actor)
		"greed":
			_open_greed(serial, actor)
		"shop":
			_open_shop(serial, actor)
		"portal":
			_vote_portal(serial, actor, local_peer())
		_:
			return false
	return true


func prompt_line(actor) -> String:
	if not run_active or actor == null or not is_instance_valid(actor):
		return ""
	var prop := nearest_prop((actor as Node3D).global_position)
	if prop == null:
		if stage_cleared:
			return "ISLAND CLEARED  ·  find the chest and the portals"
		return ""
	match Props.prop_kind(prop):
		"chest":
			if _opened.has(int(prop.get_meta("serial", 0))):
				return ""
			return "G  -  OPEN THE CHEST"
		"pedestal":
			return "G  -  CHOOSE A MOD"
		"greed":
			return "G  -  BARGAIN WITH THE GREED TOTEM"
		"shop":
			return "G  -  SPEND %d CRYSTALS" % crystals
		"portal":
			if not _opened.has("chest"):
				return "THE PORTAL IS SEALED  ·  open the chest first"
			var payload := Props.payload_of(prop)
			var line := "G  -  TAKE THE PORTAL TO %s" % str(payload.get("name", "THE NEXT ISLAND"))
			if not votes.is_empty():
				var marks: PackedStringArray = []
				for peer in votes:
					marks.append("%s:%s" % [_peer_label(int(peer)),
						str(votes[peer]).to_upper()])
				line += "   ·   VOTES %s" % " ".join(marks)
			return line
	return ""


func _open_chest(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or not is_instance_valid(prop) or _opened.has(serial):
		return
	var run = player_for(actor)
	if run == null:
		return
	var peer := int(run.peer_id)
	if not _claim_use(serial, peer):
		_status("That chest has already given you its share.", 2.0)
		return
	var payload := Props.payload_of(prop)
	var tier := str(payload.get("tier", "chest"))
	var mult: float = float(run.currency_multiplier())
	var pay_base := 24 if tier == "mini" else (60 if tier == "elite" else 38)
	var pay := int(round(float(pay_base + 10 * stage_index) * mult))
	_award_crystals(pay)
	# The chest also hands its opener one random mod. It is not a choice; the
	# pedestal is. A chest is the floor of the run's power, not its ceiling.
	var roll := Mods.draft(_rng, 1, bool(stage_index >= 2), [])
	if not roll.is_empty():
		var result: Dictionary = run.take_mod(roll[0])
		if bool(result.get("ok", false)):
			_broadcast({"t": "mod", "peer": peer, "id": roll[0],
				"message": str(result.get("message", ""))})
			_status(str(result.get("message", "")), 4.0)
	# A chest is the co-op contract's revive: whoever was on the dirt stands up
	# at half the pool the first time the party opens the reward.
	if tier != "mini" and not _opened.has("chest"):
		_opened["chest"] = true
		for other_peer in players:
			var other = players[other_peer]
			if other != null and is_instance_valid(other) and other.revive_for_clear():
				_broadcast({"t": "revived", "peer": other_peer})
		_broadcast({"t": "unseal"})
		_status("THE CHEST IS OPEN  ·  the portals wake", 4.0)
	_release_if_spent(serial, "chest", prop)
	state_changed.emit()


## Book one peer's use of a shared prop. False when this peer has already had
## its helping.
func _claim_use(serial: int, peer_id: int) -> bool:
	var users: Dictionary = _users.get(serial, {})
	if users.has(peer_id):
		return false
	users[peer_id] = true
	_users[serial] = users
	return true


## Free a shared prop once every connected player has had a helping. The chest
## only disappears on the last body; a pedestal stays until all have drafted.
func _release_if_spent(serial: int, fx_kind: String, prop: Node3D) -> bool:
	var users: Dictionary = _users.get(serial, {})
	if users.size() < maxi(1, party_size()):
		return false
	if prop == null or not is_instance_valid(prop):
		prop = _props_by_serial.get(serial)
	_opened[serial] = true
	_users.erase(serial)
	draft_offers.erase(serial)
	if prop != null and is_instance_valid(prop):
		_props.erase(prop)
		_props_by_serial.erase(serial)
		_broadcast({"t": "prop_gone", "serial": serial, "fx": fx_kind})
		match fx_kind:
			"chest":
				ProcFx.ring(stage, prop.global_position, Color(1.0, 0.8, 0.4), 2.4)
			"pedestal":
				ProcFx.flare(stage, prop.global_position + Vector3.UP,
					Color(0.7, 0.85, 1.0), 0.8)
			"greed":
				ProcFx.ring(stage, prop.global_position, Color(0.8, 0.16, 0.12), 2.2)
		prop.queue_free()
	return true


func _open_draft(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or _opened.has(serial):
		return
	var payload := Props.payload_of(prop)
	var offers: Array = payload.get("offers", [])
	if offers.is_empty():
		return
	var run = player_for(actor)
	if run == null:
		return
	var users: Dictionary = _users.get(serial, {})
	if users.has(run.peer_id):
		_status("You have already taken your choice from this pedestal.", 2.0)
		return
	draft_offers[serial] = offers
	var hud = world.get("roguelite_hud")
	if hud != null and hud.has_method("open_draft"):
		hud.open_draft(serial, offers)
	else:
		# Without a panel (a headless harness, a body with no HUD) the first
		# offer is taken: a press must never do nothing.
		choose_draft(run.peer_id, serial, 0)


## A draft choice, host side. `peer` is the chooser (a guest's request carries
## the sender, never a claimed id).
func choose_draft(peer_id: int, serial: int, index: int) -> Dictionary:
	if _client:
		send_request({"t": "choose", "serial": serial, "index": index})
		return {"ok": true, "message": "Sent to the host."}
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or _opened.has(serial):
		return {"ok": false, "message": "That pedestal is spent."}
	var offers: Array = draft_offers.get(serial, Props.payload_of(prop).get("offers", []))
	if index < 0 or index >= offers.size():
		return {"ok": false, "message": "That is not one of the offers."}
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "That body is not in this run."}
	var users: Dictionary = _users.get(serial, {})
	if users.has(peer_id):
		return {"ok": false, "message": "You have already taken your choice."}
	var result: Dictionary = run.take_mod(str(offers[index]))
	if not bool(result.get("ok", false)):
		return result
	_claim_use(serial, peer_id)
	_broadcast({"t": "mod", "peer": peer_id, "id": str(offers[index]),
		"message": str(result.get("message", ""))})
	_release_if_spent(serial, "pedestal", prop)
	return result


func _open_greed(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null or _opened.has(serial):
		return
	var run = player_for(actor)
	if run == null:
		return
	var users: Dictionary = _users.get(serial, {})
	if users.has(run.peer_id):
		_status("The totem has already taken its cut from you.", 2.0)
		return
	var offer := Mods.greed_offer(_rng, run.engine.stacks)
	if offer.is_empty():
		_status("The totem has nothing left to sell you.", 3.0)
		return
	# The bargain: the mod is free, and the body pays a fifth of its own pool in
	# blood on the spot. A body on its last legs cannot take the deal.
	var price := float(run.body.max_health) * 0.2
	if float(run.body.health) <= price + 1.0:
		_status("The totem will not take a body that is already dying.", 3.0)
		return
	var result: Dictionary = run.take_mod(offer)
	if not bool(result.get("ok", false)):
		return
	# The price is paid only for a bargain that was actually struck.
	run.body.health = maxf(1.0, float(run.body.health) - price)
	_claim_use(serial, run.peer_id)
	_broadcast({"t": "mod", "peer": run.peer_id, "id": offer,
		"message": str(result.get("message", ""))})
	_release_if_spent(serial, "greed", prop)
	_status("THE TOTEM TAKES ITS CUT  ·  %s" % Mods.name_of(offer), 4.0)


func _open_shop(serial: int, actor) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return
	var wares: Array = shop_wares.get(serial, Props.payload_of(prop).get("wares", []))
	var hud = world.get("roguelite_hud")
	if hud != null and hud.has_method("open_shop"):
		hud.open_shop(serial, wares)
		return
	# No panel: the first ware is the press.
	var buyer = player_for(actor)
	var buyer_peer := int(buyer.peer_id) if buyer != null else local_peer()
	buy(serial, 0, buyer_peer)


func buy(serial: int, index: int, peer_id: int) -> Dictionary:
	if _client:
		send_request({"t": "buy", "serial": serial, "index": index})
		return {"ok": true, "message": "Sent to the host."}
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return {"ok": false, "message": "That stall is gone."}
	var wares: Array = shop_wares.get(serial, [])
	if index < 0 or index >= wares.size():
		return {"ok": false, "message": "That is not one of the wares."}
	var ware: Dictionary = wares[index]
	if bool(ware.get("sold", false)):
		return {"ok": false, "message": "That one is already sold."}
	var run = players.get(peer_id)
	if run == null or not is_instance_valid(run):
		return {"ok": false, "message": "That body is not in this run."}
	var price := int(ware.get("price", 0))
	if crystals < price:
		return {"ok": false, "message": "The stall wants %d crystals; the party holds %d." % [
			price, crystals]}
	var result: Dictionary = run.take_mod(str(ware.get("id", "")))
	if not bool(result.get("ok", false)):
		return result
	crystals -= price
	_broadcast({"t": "crystals", "total": crystals})
	ware["sold"] = true
	wares[index] = ware
	shop_wares[serial] = wares
	_broadcast({"t": "sold", "serial": serial, "index": index, "price": price,
		"peer": peer_id})
	_broadcast({"t": "mod", "peer": peer_id, "id": str(ware.get("id", "")),
		"message": str(result.get("message", ""))})
	return result


func _vote_portal(_serial: int, _actor, peer_id: int) -> void:
	var prop: Node3D = _props_by_serial.get(_serial)
	if prop == null:
		return
	if not _opened.has("chest"):
		_status("The portal does not open until the chest is opened.", 3.0)
		return
	var payload := Props.payload_of(prop)
	var target := str(payload.get("biome", ""))
	if target.is_empty():
		return
	votes[peer_id] = target
	_broadcast({"t": "vote", "peer": peer_id, "biome": target})
	_status("%s votes %s" % [
		_peer_label(peer_id), str(StageScript.biome(target).name)], 2.0)
	# The host's own press is the decision, not a vote: the host owns the
	# transition and can take the party through without waiting on a guest who
	# never walks to a portal.
	if peer_id == local_peer():
		advance_to(target)
		return
	# When every soul has voted the same way, the party has chosen: the host
	# takes the portal without a second press.
	var needed := party_size()
	if votes.size() >= needed:
		var first := str(votes.values()[0])
		var same := true
		for value in votes.values():
			if str(value) != first:
				same = false
				break
		if same:
			advance_to(first)


func _peer_label(peer_id: int) -> String:
	if peer_id == local_peer():
		return "YOU"
	if world != null and world.get("warband") != null:
		return world.warband.roster.name_of(_merc_for_peer(peer_id)).to_upper()
	return "P%d" % peer_id


func _merc_for_peer(peer_id: int) -> int:
	if world == null or world.get("controller") == null:
		return -1
	return int(world.controller.merc_for_peer(peer_id))


## Take the portal. Host only; a guest's portal press is a vote.
func advance_to(new_biome: String) -> void:
	if not run_active or _client or not stage_cleared:
		return
	if not _valid_biome(new_biome):
		return
	stage_index += 1
	if stage_index >= MAX_STAGES:
		_finish_run(true)
		return
	_begin_stage(new_biome)
	_broadcast_state()
	_status("%s  ·  island %d of %d" % [
		str(StageScript.biome(new_biome).name), stage_index + 1, MAX_STAGES], 4.0)


static func _valid_biome(name: String) -> bool:
	return name in ["wilderness", "caves", "arena"]


# --- ending ----------------------------------------------------------------

func _finish_run(won: bool) -> void:
	if not run_active:
		return
	var cleared := mini(stage_index + 1, MAX_STAGES)
	var bonus := (6 + stage_index * 2) if won else maxi(1, stage_index / 2)
	_award_keys(bonus, "the run closes")
	var meta = get_node_or_null("/root/Roguelite")
	if meta != null and meta.has_method("note_run"):
		meta.note_run(cleared, total_kills)
	_broadcast({"t": "end", "won": won, "stage": cleared})
	_close_run()
	_status(("THE RUN IS WON  ·  %d keys  ·  back to Hearthstead" % bonus) if won
		else ("THE ISLAND TAKES THE BAND  ·  %d keys banked" % bonus), 6.0)


func _close_run() -> void:
	run_active = false
	wave_active = false
	stage_cleared = false
	queue_clear()
	_clear_stage_props()
	_free_mobs()
	if stage != null and is_instance_valid(stage):
		stage.queue_free()
	stage = null
	for peer in players:
		var run = players[peer]
		if run == null or not is_instance_valid(run):
			continue
		# A run is over; nobody leaves it on the dirt. The roster, the HUD and
		# the world's wipe rule all expect a party that is still standing.
		if run.body != null and is_instance_valid(run.body) \
				and _flag(run.body, "downed", false):
			run.body.revive_from_downed(1.0)
		run.unbind()
		run.queue_free()
	players.clear()
	for body in _saved.keys():
		if not is_instance_valid(body):
			continue
		var spot: Dictionary = _saved[body]
		(body as Node3D).global_position = spot.get("position", (body as Node3D).global_position)
		body.bounds = float(spot.get("bounds", 31.5))
		if body.combat != null:
			body.combat.target_mask = int(spot.get("mask", 2))
		if body.has_method("accept_network_input"):
			body.accept_network_input(Vector2.ZERO, false)
		var merc := _merc_of(body)
		if merc > 0 and world != null and world.get("controller") != null:
			world.controller.refresh_gear(merc)
		if world != null and world.has_method("_wire_projectiles"):
			# The campaign's quiver gate goes back on the body with its own kit.
			world._wire_projectiles(body)
	_saved.clear()
	_throw_clock.clear()
	_throw_charges.clear()
	votes.clear()
	_killed.clear()
	var hud = world.get("roguelite_hud") if world != null else null
	if hud != null and hud.has_method("close_all"):
		hud.close_all()
	state_changed.emit()


# --- firing and throwing ---------------------------------------------------

## A run body released a bow or a staff. Answers true when the run owned the
## shot; false leaves the campaign's own firing path to spend it.
func fire(actor, origin: Vector3, direction: Vector3, speed: float, charge: float) -> bool:
	var run = player_for(actor)
	if run == null or not is_instance_valid(run):
		return false
	if run.is_downed():
		return true
	var plan: Dictionary = run.fire_plan(origin, direction)
	if plan.is_empty():
		return false
	# The arena has no quiver: a run is fought with the weapon, not the campaign's
	# stock of shafts. `_spawn_runners` clears the body's ammo gate for the run and
	# `_close_run` hands the campaign's gate back.
	var rig = actor.rig
	var base := float(CombatScript.damage_for(int(rig.bow_index), charge,
		rig.ranged_scale(), rig.flat_bonus("flat_ranged")))
	var profile: Dictionary = run.ranged_profile
	var shots := maxi(1, int(plan.get("shots", 1)))
	var spread := deg_to_rad(float(plan.get("spread", 0.0)))
	# A split fan needs a fan: a bow with no spread of its own still looses its
	# extra shafts a couple of degrees apart, or they would fly as one arrow.
	if shots > 1:
		spread = maxf(spread, deg_to_rad(2.5))
	var damage_scale := float(plan.get("damage_scale", 1.0)) * float(profile.get("damage_mult", 1.0))
	var crit := bool(plan.get("crit", false))
	if crit:
		damage_scale *= 2.0
	for index in shots:
		var angle := 0.0
		if shots > 1:
			angle = spread * (float(index) - float(shots - 1) * 0.5) * 0.5
		else:
			angle = _rng.randf_range(-spread, spread) * 0.5
		var shot_direction := direction.rotated(Vector3.UP, angle)
		# The first arrow carries the full number; the fan's extras carry 85%.
		var damage := base * damage_scale * (1.0 if index == 0 else 0.85)
		var arrow := ArrowScript.new()
		arrow.source_id = int(actor.slot)
		arrow.shooter = actor
		arrow.hit_mask = 1 | 2
		arrow.authoritative_damage = true
		arrow.crit = crit
		arrow.proc_coeff = float(plan.get("proc", 1.0))
		arrow.pierce_growth = 0.15
		arrow.bounces = int(plan.get("ricochet", 0))
		arrow.homing = float(plan.get("homing", 0.0))
		arrow.impact_scale = maxf(0.0, float(plan.get("knockback", 1.0))
			* float(profile.get("gore", 1.0)))
		arrow.homing_provider = Callable(self, "nearest_enemy")
		arrow.bounce_provider = Callable(self, "bounce_target")
		arrow.on_hit = run.hit_hook(profile)
		world._arm_projectile(arrow, actor)
		world.add_child(arrow)
		# `launch` owns the pierce budget (it resets it from its own argument), so
		# the profile's pierce is handed there rather than written before it.
		arrow.launch(origin, shot_direction, speed, damage,
			world._projectile_exclude(actor), rig.last_arrow_visual_origin,
			int(plan.get("pierce", 0)))
		world._keep_projectile(arrow)
	if shots > 1 or bool(plan.get("scatter", false)):
		ProcFx.flare(stage, origin, Color(0.85, 0.9, 1.0), 0.2)
	return true


## A run body let a blade go. Multi-charge throwing weapons keep their own clock;
## anything else is one throw on a rhythm, exactly as the campaign has it.
func throw_weapon(actor, origin: Vector3, direction: Vector3, speed: float,
		charge: float, weapon: String, weapon_index: int) -> bool:
	var run = player_for(actor)
	if run == null or not is_instance_valid(run):
		return false
	if run.is_downed():
		return true
	var profile: Dictionary = run.melee_profile
	var peer: int = int(run.peer_id)
	var cap: int = int(profile.get("throw_charges", 0))
	if cap > 0:
		var have := int(_throw_charges.get(peer, cap))
		if have <= 0:
			_status("No throw left in the hand  ·  it comes back.", 1.5)
			return true
		_throw_charges[peer] = have - 1
	var crit: bool = bool(run.engine.crit_roll())
	var damage: float = float(CombatScript.throw_damage(weapon, weapon_index, charge,
		actor.rig.throw_scale()))
	damage *= run.damage_multiplier() * float(profile.get("damage_mult", 1.0))
	if crit:
		damage *= 2.0
	var thrown := ThrownScript.new()
	thrown.weapon = weapon
	thrown.weapon_index = weapon_index
	thrown.source_id = int(actor.slot)
	thrown.shooter = actor
	thrown.hit_mask = 1 | 2 | 4
	thrown.authoritative_damage = true
	thrown.crit = crit
	thrown.proc_coeff = float(profile.get("proc", 1.0)) * run.proc_multiplier()
	thrown.gore_mult = float(profile.get("gore", 1.0))
	thrown.impact_scale = maxf(0.0, float(profile.get("knockback", 1.0))
		* run.engine.knockback_multiplier())
	thrown.gravity_scale = 1.35 if str(profile.get("archetype", "")) in [
		"throwing_axe", "javelin"] else 1.0
	thrown.on_hit = run.hit_hook(profile)
	thrown.blade_length = float(PlayerArcher.dagger_profile(weapon_index).length) if weapon == "dagger" else float(PlayerArcher.SWORD_DATA[
			clampi(weapon_index, 0, PlayerArcher.SWORD_DATA.size() - 1)].length)
	world._arm_projectile(thrown, actor)
	world.add_child(thrown)
	thrown.piece_id = ""
	thrown.launch(origin, direction, speed, damage, world._projectile_exclude(actor))
	world._keep_projectile(thrown)
	return true


## The nearest hostile a homing shot may turn toward: alive, not a replica and
## not already pierced.
func nearest_enemy(from: Vector3, exclude: Dictionary = {}) -> Node3D:
	var best: Node3D = null
	var best_distance := 30.0
	for mob in _mobs:
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if not _flag(mob, "alive", true) or _flag(mob, "replica", false):
			continue
		if exclude.has((mob as Node).get_instance_id()):
			continue
		var distance := (mob as Node3D).global_position.distance_to(from)
		if distance <= best_distance:
			best_distance = distance
			best = mob
	return best


## A ricochet's next body: inside `reach` of the impact and not already struck.
func bounce_target(at: Vector3, taken: Dictionary = {}, reach: float = 12.0) -> Node3D:
	var best: Node3D = null
	var best_distance := reach
	for mob in _mobs:
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if not _flag(mob, "alive", true) or _flag(mob, "replica", false):
			continue
		if taken.has((mob as Node).get_instance_id()):
			continue
		var distance := (mob as Node3D).global_position.distance_to(at)
		if distance <= best_distance and distance > 0.3:
			best_distance = distance
			best = mob
	return best


# --- effects ---------------------------------------------------------------

## The proc engine's decisions become things in the world here. Host only: a
## guest's own effects arrive as the host's `fx` broadcast.
func execute_effect(run, effect: Dictionary) -> void:
	if run == null or not is_instance_valid(run) or effect.is_empty():
		return
	match str(effect.get("kind", "")):
		"heal":
			run.heal(float(effect.get("amount", 0.0)))
		"currency":
			_award_crystals(int(round(float(effect.get("amount", 0.0))
				* run.currency_multiplier())))
		"kill_credit":
			pass
		"arc":
			_spawn_arc(run, effect)
		"nova":
			_spawn_nova(run, effect)
		"chain":
			_spawn_chain(run, effect)
		"bomb":
			_spawn_bomb(run, effect)
		"shockwave":
			_spawn_shockwave(run, effect)


func _proc_projectile(run, effect: Dictionary, kind: String, origin: Vector3,
		direction: Vector3, speed: float, radius: float = 0.0) -> Node:
	var node = ProcProjectile.new()
	node.name = "Proc%s" % kind.capitalize()
	node.kind = kind
	node.source_id = int(run.body.slot) if run.body != null else -1
	node.shooter = run.body
	node.hit_mask = 1 | 2
	node.damage = float(effect.get("damage", 0.0))
	node.crit = bool(effect.get("crit", false))
	node.proc = float(effect.get("proc", 1.0))
	node.pierce = int(effect.get("pierce", 0))
	node.radius = radius
	node.life = 1.1
	node.delay = float(effect.get("delay", 0.0))
	node.hit_callback = Callable(run, "proc_hit")
	world.add_child(node)
	node.launch(origin, direction, speed, float(effect.get("damage", 0.0)))
	return node


func _spawn_arc(run, effect: Dictionary) -> void:
	var target = effect.get("target")
	if target == null or not is_instance_valid(target):
		return
	var at: Vector3 = effect.get("position", run.body.global_position)
	var target_at: Vector3 = (target as Node3D).global_position + Vector3.UP * 1.1
	var aim := (target_at - at)
	if aim.length_squared() < 0.001:
		return
	var node = _proc_projectile(run, effect, "dagger", at + Vector3.UP * 1.2,
		aim.normalized(), 26.0, 0.3)
	node.homing_target = target
	node.homing_turn = 8.0
	ProcFx.flare(world, at + Vector3.UP * 1.2, Color(0.95, 0.55, 0.3), 0.3)
	_broadcast_fx("arc", at, [target_at])


func _spawn_nova(run, effect: Dictionary) -> void:
	var at: Vector3 = effect.get("position", run.body.global_position)
	var count := maxi(3, int(effect.get("count", 8)))
	var base := _rng.randf_range(0.0, TAU)
	for index in count:
		var angle := base + TAU * float(index) / float(count)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		_proc_projectile(run, effect, "splinter", at + Vector3.UP * 1.1,
			direction, 20.0, 0.45)
	ProcFx.ring(world, at, Color(0.9, 0.5, 0.3), 1.6, 0.22)
	_broadcast_fx("nova", at, [])


func _spawn_chain(run, effect: Dictionary) -> void:
	var from: Vector3 = effect.get("position", run.body.global_position)
	var targets := int(effect.get("targets", 3))
	var damage := float(effect.get("damage", 0.0))
	var hit := {}
	var cursor := from + Vector3.UP * 1.2
	var last = effect.get("target")
	if last != null and is_instance_valid(last):
		hit[(last as Node).get_instance_id()] = true
		cursor = (last as Node3D).global_position + Vector3.UP * 1.2
	var points: Array = []
	for _index in targets:
		var found = _nearest_hostile_excluding(cursor, hit, 14.0)
		if found == null:
			break
		var point: Vector3 = (found as Node3D).global_position + Vector3.UP * 1.2
		points.append(point)
		hit[(found as Node).get_instance_id()] = true
		ProcFx.lightning(world, cursor, point, Color(0.95, 0.25, 0.18))
		if found.has_method("take_damage"):
			if run.body != null and found.has_method("note_attacker"):
				found.note_attacker(run.body)
			found.take_damage(damage, int(run.body.slot) if run.body != null else -1, false)
			if _flag(found, "alive", true) == false:
				run.proc_hit(found, true, damage)
		cursor = point
	if not points.is_empty():
		_broadcast_fx("chain", from, points)


func _nearest_hostile_excluding(from: Vector3, taken: Dictionary, reach: float):
	var best = null
	var best_distance := reach
	for mob in _mobs:
		if not is_instance_valid(mob) or not (mob is Node3D):
			continue
		if not _flag(mob, "alive", true) or _flag(mob, "replica", false):
			continue
		if taken.has((mob as Node).get_instance_id()):
			continue
		var distance := (mob as Node3D).global_position.distance_to(from)
		if distance <= best_distance:
			best_distance = distance
			best = mob
	return best


func _spawn_bomb(run, effect: Dictionary) -> void:
	var target = effect.get("target")
	var at: Vector3 = effect.get("position", run.body.global_position)
	if target != null and is_instance_valid(target):
		at = (target as Node3D).global_position + Vector3.UP * 1.0
	var node = _proc_projectile(run, effect, "bomb", at,
		Vector3.ZERO, 0.0, float(effect.get("radius", 3.0)))
	node.delay = float(effect.get("delay", 1.2))
	node.life = node.delay + 0.5
	_broadcast_fx("bomb", at, [])


func _spawn_shockwave(run, effect: Dictionary) -> void:
	if run.body == null:
		return
	var forward: Vector3 = effect.get("forward", Vector3.FORWARD)
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = -run.body.global_transform.basis.z
	forward = forward.normalized()
	var damage: float = float(effect.get("damage_scale", 0.45)) * float(run.melee_profile.get("proc", 1.0)) * 60.0 * run.damage_multiplier()
	var node = _proc_projectile(run, {"damage": damage, "pierce": effect.get("pierce", 1),
		"crit": bool(effect.get("crit", false))}, "wave",
		run.body.global_position + Vector3.UP * 0.9 + forward * 1.2,
		forward, 18.0, 1.4)
	node.life = 0.42
	_broadcast_fx("wave", run.body.global_position,
		[run.body.global_position + forward * 6.0])


func _broadcast_fx(kind: String, at: Vector3, points: Array) -> void:
	_broadcast({"t": "fx", "kind": kind, "at": at, "points": points})


# --- wire ------------------------------------------------------------------

func _session():
	if world == null:
		return null
	var flow = world.get("flow")
	if flow == null:
		return null
	return flow.get("session")


func _broadcast(event: Dictionary) -> void:
	if _client:
		return
	var session = _session()
	if session != null and session.has_method("send_roguelite_event"):
		session.send_roguelite_event(event)


func _broadcast_state() -> void:
	_broadcast({"t": "state", "seed": run_seed, "stage": stage_index,
		"biome": biome_id, "wave": wave, "waves": waves_this_stage,
		"active": wave_active, "cleared": stage_cleared, "boss": boss_wave,
		"crystals": crystals, "living": _live_mobs(), "kills": total_kills})


func send_request(request: Dictionary) -> void:
	var kind := str(request.get("t", ""))
	if kind in ["start", "sync"] and not request.has("loadout"):
		request["loadout"] = _local_loadout()
	var session = _session()
	if session != null and session.has_method("send_roguelite_request"):
		session.send_roguelite_request(request)


## Host: a guest's request, already attributed by the wire's sender id.
func handle_request(peer_id: int, request: Dictionary) -> void:
	if _client or not run_active:
		return
	var body = world.controller.body_for_peer(peer_id) if world != null else null
	match str(request.get("t", "")):
		"start":
			remember_loadout(peer_id, request.get("loadout"))
			start_run()
		"loadout":
			remember_loadout(peer_id, request.get("loadout"))
			var runner = players.get(peer_id)
			if runner != null and is_instance_valid(runner):
				runner.ranged_id = _loadout_for(peer_id, "ranged")
				runner.melee_id = _loadout_for(peer_id, "melee")
				runner._set_profiles()
				_apply_hands(runner, str(runner._active_slot))
		"sync":
			remember_loadout(peer_id, request.get("loadout"))
			# A guest that joined under a live run is owed the whole picture:
			# which island, which wave, what is standing on it and what is lying
			# on it.
			if run_active:
				_broadcast_state()
				for serial in _props_by_serial:
					var prop: Node3D = _props_by_serial[serial]
					if prop != null and is_instance_valid(prop):
						_broadcast({"t": "prop", "serial": serial,
							"kind": Props.prop_kind(prop),
							"at": prop.global_position,
							"payload": Props.payload_of(prop)})
				for mob in _mobs:
					if not is_instance_valid(mob) or _flag(mob, "replica", false):
						continue
					var spec: Dictionary = _mob_specs.get((mob as Node).get_instance_id(), {})
					_broadcast({"t": "mob", "name": str((mob as Node).name), "spec": spec,
						"at": (mob as Node3D).global_position, "life": 1.0, "rate": 1.0,
						"damage": 1.0})
		"swap":
			if body != null:
				swap_hands(body)
		"use":
			if body != null:
				_use_serial(int(request.get("serial", 0)), body, peer_id)
		"choose":
			choose_draft(peer_id, int(request.get("serial", 0)), int(request.get("index", 0)))
		"buy":
			buy(int(request.get("serial", 0)), int(request.get("index", 0)), peer_id)
		"vote":
			var serial := int(request.get("serial", 0))
			var prop: Node3D = _props_by_serial.get(serial)
			var target := str(request.get("biome", ""))
			if prop != null and not target.is_empty():
				votes[peer_id] = target
				_broadcast({"t": "vote", "peer": peer_id, "biome": target})


func _use_serial(serial: int, actor, peer_id: int = 1) -> void:
	var prop: Node3D = _props_by_serial.get(serial)
	if prop == null:
		return
	match Props.prop_kind(prop):
		"chest":
			_open_chest(serial, actor)
		"pedestal":
			_open_draft(serial, actor)
		"greed":
			_open_greed(serial, actor)
		"shop":
			_open_shop(serial, actor)
		"portal":
			_vote_portal(serial, actor, peer_id)


## Guest: a reliable event from the host.
func apply_event(event: Dictionary) -> void:
	match str(event.get("t", "")):
		"state":
			_apply_state(event)
		"prop":
			_apply_prop(event)
		"prop_gone":
			_apply_prop_gone(event)
		"mod":
			_apply_mod(event)
		"crystals":
			crystals = maxi(0, int(event.get("total", crystals)))
			state_changed.emit()
		"keys":
			var meta = get_node_or_null("/root/Roguelite")
			if meta != null:
				meta.award_keys(int(event.get("amount", 0)), str(event.get("reason", "")))
		"pool":
			var ledger = get_node_or_null("/root/Roguelite")
			if ledger != null and ledger.has_method("share_pool"):
				ledger.share_pool(event.get("ids", []))
		"mob":
			if _client:
				_spawn_replica(event)
		"hands":
			var run = players.get(int(event.get("peer", 0)))
			if run != null and is_instance_valid(run):
				_apply_hands(run, str(event.get("slot", "ranged")))
		"fx":
			_apply_fx(event)
		"vote":
			votes[int(event.get("peer", 0))] = str(event.get("biome", ""))
		"revived":
			var run = players.get(int(event.get("peer", 0)))
			if run != null and is_instance_valid(run):
				run.body.revive_from_downed(0.5)
		"unseal":
			_opened["chest"] = true
		"sold":
			var serial := int(event.get("serial", 0))
			var wares: Array = shop_wares.get(serial, [])
			var index := int(event.get("index", 0))
			if index >= 0 and index < wares.size():
				var ware: Dictionary = wares[index]
				ware["sold"] = true
				wares[index] = ware
			crystals = maxi(0, crystals - int(event.get("price", 0)))
		"notice":
			_status(str(event.get("text", "")), float(event.get("seconds", 3.0)))
		"end":
			if _client:
				var meta = get_node_or_null("/root/Roguelite")
				if meta != null and meta.has_method("note_run"):
					meta.note_run(int(event.get("stage", 0)), total_kills)
				_close_run()
				_status("THE RUN IS OVER  ·  back to Hearthstead", 5.0)


func _apply_state(event: Dictionary) -> void:
	var was_running := run_active
	run_seed = int(event.get("seed", run_seed))
	var new_stage := int(event.get("stage", 0))
	var new_biome := str(event.get("biome", biome_id))
	if not was_running or new_stage != stage_index or not is_instance_valid(stage):
		stage_index = new_stage
		run_active = true
		wave = int(event.get("wave", 0))
		waves_this_stage = int(event.get("waves", WAVES_PER_STAGE))
		wave_active = bool(event.get("active", false))
		stage_cleared = bool(event.get("cleared", false))
		boss_wave = bool(event.get("boss", false))
		if new_biome != biome_id or not is_instance_valid(stage):
			biome_id = new_biome
			_build_stage()
			_spawn_runner_replicas()
		_clear_stage_props()
	else:
		wave = int(event.get("wave", wave))
		wave_active = bool(event.get("active", wave_active))
		stage_cleared = bool(event.get("cleared", stage_cleared))
		boss_wave = bool(event.get("boss", boss_wave))
		waves_this_stage = int(event.get("waves", waves_this_stage))
	crystals = int(event.get("crystals", crystals))
	total_kills = int(event.get("kills", total_kills))
	if _client and run_active and _loadout_sent_seed != run_seed:
		# The host dressed this body before it heard from this machine; tell it
		# the pair the rack actually bound here.
		_loadout_sent_seed = run_seed
		send_request({"t": "loadout", "loadout": _local_loadout()})
	state_changed.emit()


func _spawn_runner_replicas() -> void:
	# Guests do not simulate, but their HUD needs a runtime per body for the mod
	# list and the local hand's profile. The body's own hooks are the host's.
	if players.is_empty():
		for body in _world_bodies():
			if not is_instance_valid(body):
				continue
			var merc := _merc_of(body)
			var peer := _peer_of_merc(merc)
			var run = PlayerScript.new()
			world.add_child(run)
			run.bind(body, self, peer, merc, _roster_loadout("ranged"),
				_roster_loadout("melee"))
			players[peer] = run
			if body.get("combat") != null:
				body.combat.ammo_gate = Callable()
			_apply_hands(run, "ranged")


func _apply_prop(event: Dictionary) -> void:
	if not is_instance_valid(stage):
		return
	var at: Vector3 = event.get("at", Vector3.ZERO)
	var kind := str(event.get("kind", ""))
	var payload: Dictionary = event.get("payload", {})
	var node := _spawn_prop(kind, at, payload)
	if node == null:
		return
	var serial := int(event.get("serial", 0))
	if serial > 0:
		node.set_meta("serial", serial)
		_props_by_serial[serial] = node
	if kind == "shop":
		shop_wares[serial] = payload.get("wares", [])


func _apply_prop_gone(event: Dictionary) -> void:
	var serial := int(event.get("serial", 0))
	var prop: Node3D = _props_by_serial.get(serial)
	_opened[serial] = true
	_props_by_serial.erase(serial)
	_props.erase(prop)
	if prop != null and is_instance_valid(prop):
		prop.queue_free()
	var kind := str(event.get("fx", ""))
	if is_instance_valid(stage):
		match kind:
			"chest":
				ProcFx.ring(stage, (prop as Node3D).global_position if prop != null else stage.global_position,
					Color(1.0, 0.8, 0.4), 2.4)
			"pedestal":
				ProcFx.flare(stage, stage.global_position, Color(0.7, 0.85, 1.0), 0.8)


func _apply_mod(event: Dictionary) -> void:
	var peer := int(event.get("peer", 0))
	var run = players.get(peer)
	if run == null or not is_instance_valid(run):
		return
	run.take_mod(str(event.get("id", "")))
	if peer == local_peer():
		_status(str(event.get("message", Mods.name_of(str(event.get("id", ""))))), 4.0)
	state_changed.emit()


func _apply_fx(event: Dictionary) -> void:
	if not is_instance_valid(stage):
		return
	var kind := str(event.get("kind", ""))
	var at: Vector3 = event.get("at", Vector3.ZERO)
	var points: Array = event.get("points", [])
	match kind:
		"arc":
			ProcFx.flare(world, at, Color(0.95, 0.55, 0.3), 0.3)
			if not points.is_empty():
				var aim: Vector3 = (points[0] as Vector3) - at
				if aim.length_squared() > 0.001:
					_spawn_visual_proc("dagger", at + Vector3.UP * 1.2,
						aim.normalized(), 26.0, 0.3)
		"nova":
			ProcFx.ring(world, at, Color(0.9, 0.5, 0.3), 1.6, 0.22)
			for index in 8:
				var angle := TAU * float(index) / 8.0
				_spawn_visual_proc("splinter", at + Vector3.UP * 1.1,
					Vector3(cos(angle), 0.0, sin(angle)), 20.0, 0.45)
		"chain":
			var cursor := at
			for point in points:
				ProcFx.lightning(world, cursor, point, Color(0.95, 0.25, 0.18))
				cursor = point
		"bomb":
			ProcFx.ring(world, at, Color(0.9, 0.2, 0.12), 3.0, 0.3)
			_spawn_visual_proc("bomb", at, Vector3.ZERO, 0.0, 3.0)
		"wave":
			var wave_forward := Vector3.FORWARD
			if not points.is_empty():
				wave_forward = ((points[0] as Vector3) - at).normalized()
			_spawn_visual_proc("wave", at + Vector3.UP * 0.9 + wave_forward * 1.2,
				wave_forward, 18.0)
			ProcFx.ring(world, at, Color(0.75, 0.1, 0.08), 1.4, 0.2)


## A guest's copy of a proc: the same body, the same flight, no damage.
func _spawn_visual_proc(kind: String, origin: Vector3, direction: Vector3,
		speed: float, radius: float = 0.0) -> void:
	var node = ProcProjectile.new()
	node.visual_only = true
	node.kind = kind
	node.radius = radius
	node.life = 1.0
	if kind == "bomb":
		node.delay = 1.2
		node.life = 1.7
	world.add_child(node)
	node.launch(origin, direction, speed, 0.0)


# --- reporting -------------------------------------------------------------

func state() -> Dictionary:
	return {
		"active": run_active,
		"biome": biome_id,
		"biome_name": str(StageScript.biome(biome_id).name),
		"stage": stage_index + 1,
		"stages": MAX_STAGES,
		"wave": wave,
		"waves": waves_this_stage,
		"wave_active": wave_active,
		"cleared": stage_cleared,
		"boss": boss_wave,
		"crystals": crystals,
		"keys": keys_earned,
		"kills": total_kills,
		"living": _live_mobs(),
		"party": players.size(),
		"queue": _queue.size(),
		"boss_wave": boss_wave,
		"local_peer": local_peer(),
	}


func _status(text: String, seconds: float = 3.0) -> void:
	if world != null and world.get("hud") != null and world.hud.has_method("set_status"):
		world.hud.set_status(text, seconds)
	# A refusal or a bargain is the party's news, not the host's alone: the same
	# line goes to every guest so a press that did nothing says why there too.
	if not _client and not text.is_empty():
		_broadcast({"t": "notice", "text": text, "seconds": seconds})


## `Object.get` takes a property name and nothing else, while `Dictionary.get`
## takes a fallback. These three helpers keep the arena's many `bool(body.get(...,
## true))` reads from becoming a runtime error on a Node.
static func _flag(object, key: String, fallback: bool = false) -> bool:
	if object == null or not is_instance_valid(object):
		return fallback
	var value: Variant = object.get(key)
	return fallback if value == null else bool(value)


static func _num(object, key: String, fallback: float = 0.0) -> float:
	if object == null or not is_instance_valid(object):
		return fallback
	var value: Variant = object.get(key)
	return fallback if value == null else float(value)


func _world_bodies() -> Array:
	if world == null:
		return []
	var found: Variant = world.get("bodies")
	return found if found is Array else []
