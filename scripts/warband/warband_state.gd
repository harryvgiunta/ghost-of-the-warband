extends Node
## Autoload `Warband`: the persistent soul, the roster, the infinite stash, the
## Cruor ledger, the recruiter and the campaign ledger, in one place.
##
## Ghost of the Warband is a possession game, so the thing that survives a
## battle is not a character: it is the warband. This node owns that state and
## nothing else - no scene, no camera, no input. The camp, the trail and the town
## read it and write back through it.
##
## Gold is the existing `PlayerState` purse; this node never keeps a second one.

signal changed
## A piece just woke into its skill at the altar. Whatever dresses bodies off the
## roster listens, so every body already holding a copy carries the skill at once.
signal anointed(item_id: String, ability: String)
## A copy's annointment list changed: `[entry ids]`, in weld order.
signal annointed_state(item_id: String, entries: Array)
## The warband armed itself out of the pool: these mercenaries' kits changed, so
## whatever keeps a live rig re-dresses them (`PossessionController`).
signal armed(merc_ids: Array)

const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const RosterScript = preload("res://scripts/warband/warband_roster.gd")
const StashScript = preload("res://scripts/warband/town_stash_model.gd")
const CruorScript = preload("res://scripts/warband/cruor_manager.gd")
const VendorScript = preload("res://scripts/warband/mercenary_vendor.gd")
const SoulScript = preload("res://scripts/warband/soul_router.gd")
const CruorCatalog = preload("res://scripts/warband/cruor_catalog.gd")
const State = preload("res://scripts/player_state.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")
const EquipmentRules = preload("res://scripts/equipment_rules.gd")
const QuestScript = preload("res://scripts/warband/quest_log.gd")
const AnnointScript = preload("res://scripts/warband/annoint_ledger.gd")
const AnnointCatalog = preload("res://scripts/warband/annoint_catalog.gd")
const AnnointRoll = preload("res://scripts/warband/annoint_roll.gd")
const AnnointLedger = preload("res://scripts/warband/annoint_ledger.gd")
const DelveScript = preload("res://scripts/warband/delve_state.gd")

## Item categories a body can wear; the same list `EquipmentRules` enforces.
const EQUIPPABLE_CATEGORIES := ["1h", "2h", "bow", "staff", "shield", "focus", "armor", "jewelry"]

## The order a fresh body is armed in: steel first, then armour, then the
## trinkets. `dress_recruit` walks this list and takes the dearest spare the
## shared stash holds for each slot.
const DRESS_SLOTS := ["main", "off", "head", "chest", "hands", "legs", "feet", "neck", "ring1", "ring2"]

## Additive save format. v3 added each mercenary's two weapon sets (`weapon_sets`
## plus `active_set` per record), the pair `TAB` brings up; v4 added the
## checkpoint bookmark (`checkpoint`), the autosave that remembers which stretch
## of the world the warband has already played; v5 added the campaign ledger
## (`quests`), the objectives the quartermaster has handed over and how far each
## one got; v6 added the altar's anointed pieces (`cruor.anointed`), the stock
## steel that has been given its skill; v7 dropped the expedition's battle ledger
## (`runs`, `run_totals`); v8 added the delve (`delve`): the inventory packed at
## the Hollow's mouth and, while a party is below, who went down; v9 added the
## party's mode (`party_mode`), how the squad picks its fights; v10 added the
## auto-equip holds (`auto_equip_restricted`), the pieces the player keeps out of
## the band's automatic arming; v11 added each record's disposition (the `tank` /
## `melee` / `bow` behaviour the squad AI reads per body and the arming reads when
## it picks a piece); v13 added each record's hotbar layout (`hotbar_order`), the
## sequence of ability ids the player has laid on the ten keys. Older files still
## load: a record with no sets puts
## the pair already in its hands in Set 1 and starts Set 2 empty, a file without a
## checkpoint resumes at the town as it always did, a file without quests opens
## with an empty ledger, a file without anointings carries plain steel, a file
## without a delve has an empty pack and nobody below, a file without a party mode
## fights offensive, a file without holds arms from every piece, as it always did,
## a file without a disposition fields every body as melee, and a file without a
## hotbar layout fires every skill from the key the kit's own order gives it.
const SAVE_VERSION := 14
const DEFAULT_SAVE_PATH := "user://warband_state.json"
## The areas a checkpoint may name. A checkpoint is a *place in the campaign*,
## not a save slot: the camp is the only place a run starts, so it is never a
## checkpoint (the opening is already restartable from the title).
const CHECKPOINT_AREAS := ["trail", "town"]
## What every gear and purse verb answers while the warband is lent (see `lent`).
const LENT_MESSAGE := "This is the host's warband: only the host changes its gear and purse."

var roster: WarbandRoster = RosterScript.new()
var souls: SoulRouter = SoulScript.new()
var stash: WarbandStash = StashScript.new()
var cruor: WarbandCruor = CruorScript.new()
## Per-copy annointments: `"<catalog id>#<ordinal>" -> [entry ids]`.
var annoints: AnnointLedger = AnnointScript.new()
## Which copy a worn piece is: `"<merc id>:<slot>" -> {item, ordinal}`. The
## roster stores catalog ids, so the copy is bookkeeping that lives here.
var worn_copies: Dictionary = {}
## The campaign ledger: which objectives the quartermaster has handed over and
## how far each has got. Pure state (no scene, no node), saved with everything
## else, so a checkpoint restores the orders as they stood.
var quests: WarbandQuests = QuestScript.new()
## The delve: the inventory a party carries below and who went down with it
## (`delve_state.gd`). While a party is below, every verb that moves gear between
## a body and the pool works that inventory instead of the town stash
## (`field_stash`).
var delve = DelveScript.new()
var deployment_cap: int = Contracts.MAX_DEPLOYMENT_CAP
var save_path := DEFAULT_SAVE_PATH
## True when a mode has already handed this warband its starting bodies, so a
## scene reload cannot seed a second copy of the same squad.
var seeded := false
## The mercenary each peer is currently inside, mirrored from the router so a
## scene hand-off can restore control without a live body.
var possession: Dictionary = {}   # peer_id -> merc_id
## Seconds into the current 5 s revive channel, keyed by peer id.
var revive_channels: Dictionary = {}  # peer_id -> {merc_id, seconds}
## The last autosave bookmark: `{id, area, position, label, at}` or `{}`. It is
## written by the world at the moments the campaign becomes a new stretch - the
## camp's six watchers down and the squad on the road, the town square entered -
## and it is what a wipe and the title's campaign list read. The roster, stash and
## essence beside it are the warband as it stood then; the purse is not rolled
## back, because `PlayerState` owns it and a reload must never repay a run.
var checkpoint: Dictionary = {}
## How the squad picks its fights (`Contracts.PARTY_MODES`): set from the warband
## menu with `set_party_mode`, saved with the books and lent with them, so a co-op
## guest's menu shows the host's mode. Only the host's squad acts on it.
var party_mode: String = Contracts.DEFAULT_PARTY_MODE
## True while this warband is a co-op host's, lent to this machine for the length
## of a session (`GameFlow.join_campaign`). A lent warband is shown and played and
## never touches this machine's files: `save_state` and `load_state` refuse, so the
## guest's own campaign is exactly as it was when the session ends. The host is
## the only place the shared warband changes - its gear, its purse, its roll - so
## every gear and purse verb below answers `LENT_MESSAGE` instead, and the host's
## own updates arrive through `lend()`. `end_loan()` gives this machine its own
## warband back.
var lent := false
## Item ids the player has held back from automatic equipping: `arm_warband`,
## `dress_recruit` and a loot pickup leave them in the pool, while a hand on the
## paperdoll may still wear one. Item ids, not copies, so every spare and every
## body's copy obeys the same hold; saved with the warband and lent with it.
var auto_equip_restricted: Dictionary = {}
## True while `arm_warband` is walking the roster, so an equip that emits
## `changed` (or anything listening to it) cannot start a second pass.
var _arming := false
## The host's purse while lent: shown, never spent on this machine.
var _lent_gold := 0

func _ready() -> void:
	set_process(false)
	# The campaign this launch resumes (`SaveSlots`): every writer below - the
	# autosave, a bookmark, a gear change - goes to that folder and no other. A
	# machine with no campaign keeps the single pre-slot path until one is made.
	var slots := get_node_or_null("/root/SaveSlots")
	if slots != null and not str(slots.active).is_empty():
		save_path = str(slots.warband_path(str(slots.active)))
	if not roster.died.is_connected(_on_merc_died):
		roster.died.connect(_on_merc_died)

# --- purse -----------------------------------------------------------------

func gold() -> int:
	if lent:
		return _lent_gold
	var state := get_node_or_null("/root/PlayerState")
	return int(state.credits) if state != null else 0

## False (and nothing spent) when the purse cannot cover it.
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if lent:
		return false
	var state := get_node_or_null("/root/PlayerState")
	if state == null or int(state.credits) < amount:
		return false
	state.add_credits(-amount)
	return true

func award_gold(amount: int) -> void:
	if amount == 0 or lent:
		return
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.add_credits(amount)

# --- the co-op loan ----------------------------------------------------------

## Take a co-op host's warband for the session: the roster, stash, essence,
## orders and bookmark exactly as the host holds them (its `to_dict()`), and the
## host's purse. The host sends it again whenever its warband changes, so this is
## also how the lent copy keeps up.
func lend(data: Dictionary, gold_amount: int) -> void:
	lent = true
	_lent_gold = maxi(0, gold_amount)
	from_dict(data)

## Hand the lent warband back: this machine's own save is read again, or a fresh
## warband stands in when there is none, so the title opens exactly the campaign
## it opened before the session.
func end_loan() -> void:
	if not lent:
		return
	lent = false
	_lent_gold = 0
	clear_possession()
	if not load_state():
		reset_state()

## The refusal every gear and purse verb gives while lent, in the shape that verb
## always answers with.
func _lent_refusal(fields: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "message": LENT_MESSAGE}
	out.merge(fields)
	return out

# --- the quiver ------------------------------------------------------------

## Ammunition is one pool for the whole band, exactly like the shared stash it
## lives in: every shaft a bow looses comes out of it, every bunch a keeper sells
## goes into it, and every archer's corpse gives a few back. A bow with nothing
## in the quiver cannot be drawn, which is the whole of the rule. Below, the
## quiver is the delve inventory: a party shoots what it packed and what it takes.
const ARROW_ITEM := "arrow"
## What a fresh campaign opens with. A body that has to buy its first shaft
## before it may use a bow it just looted would read the bow as broken.
const STARTING_ARROWS := 24

func arrows() -> int:
	return field_stash().pooled_count(ARROW_ITEM)

## False when the quiver is empty. A caller drawing a bow asks this first.
func has_arrows() -> bool:
	return arrows() > 0

## Take up to `count` shafts out of the pool and answer how many actually left
## it: a loosed arrow asks for one and gets 0 or 1, so the count can never go
## negative however many shots a frame resolves.
func take_arrows(count: int = 1) -> int:
	var taken := 0
	while taken < maxi(count, 0) and field_stash().remove(ARROW_ITEM, 1):
		taken += 1
	if taken > 0:
		_notify()
	return taken

## Put shafts back in the pool: a keeper's bunch, an archer's corpse, a test.
func add_arrows(count: int = 1) -> int:
	var added := maxi(count, 0)
	if added <= 0:
		return 0
	field_stash().add(ARROW_ITEM, added)
	_notify()
	return added

## A campaign's opening bunch. Seeding never mints: a warband that already counts
## shafts - a resumed save, a keeper's purchase - keeps exactly what it had.
func seed_quiver(count: int = STARTING_ARROWS) -> int:
	if arrows() > 0:
		return 0
	return add_arrows(count)

# --- the field's pool ---------------------------------------------------------

## The pool the field's hands work right now: the town stash, or the delve
## inventory while a party is below. Equipping, unequipping, a loot take, a dead
## squadmate's kit and the quiver all go through this, so nothing taken in the
## cave reaches the stash before the party climbs out with it.
func field_stash() -> WarbandStash:
	return delve.inventory if delve.active else stash

## How a message names that pool.
func field_label() -> String:
	return "the delve inventory" if delve.active else "the shared stash"

## The mercenaries whose gear may be moved right now: the whole roster, or only
## the party while it is below - a body left in the town cannot hand a piece into
## the cave, and nobody in the cave can reach a body in the town.
func dressable_ids() -> Array[int]:
	if not delve.active:
		return roster.ids()
	var out: Array[int] = []
	for merc_id in roster.ids():
		if delve.party.has(merc_id):
			out.append(merc_id)
	return out

# --- roster ----------------------------------------------------------------

func merc_ids() -> Array[int]:
	return roster.ids()

func alive_merc_ids() -> Array[int]:
	return roster.alive_ids()

# --- the field and the reserve ---------------------------------------------
#
# The field is the bodies the warband has standing: at most `deployment_cap` of
# them. A name sworn while the field is full - a soldier cut out of a cage past
# the eighth body - waits in the reserve (`WarbandRoster.is_reserve`) with no body
# at all, and takes a place again only in the town (the world decides where; this
# only keeps the books).

## Places left on the field: the cap less every body already on it.
func field_room() -> int:
	return maxi(0, deployment_cap - roster.field_count())

## The oldest name in the reserve takes a place on the field. Returns its id, or
## -1 when the field is full or nobody waits.
func deploy_reserve() -> int:
	if field_room() <= 0:
		return -1
	var waiting := roster.reserve_ids()
	if waiting.is_empty():
		return -1
	roster.set_reserve(waiting[0], false)
	_notify()
	return waiting[0]

## A file can name more bodies on the field than the cap allows (one written
## before the reserve existed, when every rescue took the field), or none at all
## while names wait in the reserve. The newest fielded names step back into the
## reserve until the field fits, and an empty field takes the reserve's oldest,
## so a load always stands the warband up inside the cap.
func _balance_field() -> void:
	var field := roster.field_ids()
	for index in range(field.size() - 1, deployment_cap - 1, -1):
		roster.set_reserve(field[index], true)
	if roster.field_count() > 0:
		return
	var waiting := roster.reserve_ids()
	for index in mini(waiting.size(), deployment_cap):
		roster.set_reserve(waiting[index], false)

## The dead leave the warband the moment they die: a corpse is not a party member,
## it cannot be deployed or entered, and its record used to sit on the hire cap
## forever - a band that had filled its eight places could never swear another
## body because the fallen still counted. The name leaves the roster, the body
## leaves the soul router, and everything it was still wearing goes back into the
## shared stash, so dying costs the man, never the gear - unless he died below:
## a member of the party below leaves his kit on his corpse (the world takes it
## off his books as he dies, `world_scene._leave_remains`), and the party gets it
## back only by looting the body. Anything still on his books when he is reaped
## below - a save loaded with the party down - joins the delve inventory the fall
## then loses. Returns the fallen records (`[{id, name, health, max_health,
## items}]`); empty when nobody died.
func reap_dead() -> Array[Dictionary]:
	var fallen := roster.take_dead()
	if fallen.is_empty():
		return fallen
	for entry in fallen:
		var merc_id := int(entry.get("id", 0))
		var into: WarbandStash = delve.inventory if delve.is_member(merc_id) else stash
		for item_id in entry.get("items", []):
			into.add(str(item_id), 1)
		delve.party.erase(merc_id)
		if souls.has_body(merc_id):
			souls.unregister_body(merc_id)
		for peer_id in possession.keys():
			if int(possession[peer_id]) == merc_id:
				possession.erase(peer_id)
		for peer_id in revive_channels.keys():
			var channel: Variant = revive_channels[peer_id]
			if channel is Dictionary and int((channel as Dictionary).get("merc_id", 0)) == merc_id:
				revive_channels.erase(peer_id)
	_notify()
	return fallen

func _on_merc_died(_merc_id: int) -> void:
	reap_dead()

## Hack a body into the warband (the cage tutorial's four prisoners, the admin
## arena's eight test bodies, a soldier cut out of a cage). No gold changes hands.
## The body takes the field when there is room for it, and the reserve when not.
func add_mercenary(merc_name: String = "", equipped: Dictionary = {}) -> int:
	var room := field_room() > 0
	var merc_id := roster.create(merc_name, equipped)
	roster.set_reserve(merc_id, not room)
	_notify()
	return merc_id

## Hand a fresh body the best kit the warband already owns.
##
## A body that swears with empty hands is dead weight, so a hire and a rescue
## both walk the equipment slots in the order a fighter would fill them and take
## the dearest spare out of the shared stash for each one. The pool is the only
## source: nothing is minted, a real worn piece is left alone, and the naked set
## a prisoner is born in counts as bare, so a recruit in rags still takes gear.
## A two-hander locks the off hand, exactly as `EquipmentRules` says it does, and
## a piece the player held back from auto-equip stays in the pool.
## Returns `{ok, merc_id, fitted, message}` with the ids that walked across.
func dress_recruit(merc_id: int, slots: Array = DRESS_SLOTS) -> Dictionary:
	var fitted: Array[String] = []
	if lent:
		return _lent_refusal({"merc_id": merc_id, "fitted": fitted})
	if merc_id <= 0 or not roster.is_alive(merc_id):
		return {"ok": false, "merc_id": merc_id, "fitted": fitted, "message": ""}
	for entry in _fill_slots(merc_id, slots):
		fitted.append(str(entry.get("item_id", "")))
	if fitted.is_empty():
		return {"ok": true, "merc_id": merc_id, "fitted": fitted,
			"message": "%s takes the field with what the band had spare." % roster.name_of(merc_id)}
	_notify()
	return {"ok": true, "merc_id": merc_id, "fitted": fitted,
		"message": "%s arms from %s: %s." % [roster.name_of(merc_id), field_label(),
			", ".join(fitted.map(func(item_id: String): return str(
				State.ITEMS.get(item_id, {}).get("name", item_id))))]}

## Arm the whole band out of the pool it can reach. The automatic answer to a
## shopping spree: every body the field can dress fills each slot that is empty
## or still wearing the naked set, taking the dearest legal, unheld spare the
## pool holds. A real worn piece is never upgraded, so a kit the player chose by
## hand is not overruled by a lucky purchase. One notify and one `armed` signal
## are emitted for the pass, never one per piece.
## Returns `{ok, fitted, mercs, message}`; `fitted` is `[{merc_id, slot, item_id}]`.
func arm_warband() -> Dictionary:
	var fitted: Array[Dictionary] = []
	var mercs: Array[int] = []
	if lent or _arming:
		return {"ok": false, "fitted": fitted, "mercs": mercs, "message": ""}
	_arming = true
	for merc_id in dressable_ids():
		if not roster.is_alive(merc_id):
			continue
		var filled := _fill_slots(merc_id, DRESS_SLOTS)
		if filled.is_empty():
			continue
		mercs.append(merc_id)
		fitted.append_array(filled)
	_arming = false
	if fitted.is_empty():
		return {"ok": true, "fitted": fitted, "mercs": mercs, "message": ""}
	_notify()
	armed.emit(mercs)
	return {"ok": true, "fitted": fitted, "mercs": mercs, "message": _arm_message(fitted)}

## Fill every named slot on one body from the field's pool. A slot is open when
## it is empty or still wears the naked set; a real worn piece is left alone. The
## dearest legal, unheld copy wins, and a two-handed main never costs an off-hand
## already in use. Returns `[{merc_id, slot, item_id}]`; the caller owns the one
## notify, which is what keeps a band-wide pass from repainting eight times.
func _fill_slots(merc_id: int, slots: Array) -> Array[Dictionary]:
	var fitted: Array[Dictionary] = []
	var disposition := roster.disposition_of(merc_id)
	for raw_slot in slots:
		var slot_id := str(raw_slot)
		var gear := roster.equipped_of(merc_id)
		var current := str(gear.get(slot_id, ""))
		if not current.is_empty() and not EquipmentRules.bare_garment(current):
			continue
		if slot_id == "off":
			var main_item: Dictionary = State.ITEMS.get(str(gear.get("main", "")), {})
			if Contracts.two_handed_item(main_item):
				continue
		var best := _best_spare(slot_id, gear, disposition)
		if best.is_empty():
			continue
		var result := equip_merc(merc_id, slot_id, best, false)
		if not bool(result.get("ok", false)):
			continue
		fitted.append({"merc_id": merc_id, "slot": slot_id, "item_id": best})
	return fitted

## The best legal spare for one slot as this body would choose it: the one
## decision a recruit dressing, a band-wide arming pass and a pickup's snap-in all
## make. A disposition moves the score rather than the rule - a tank's shield and
## one-hander beat a dearer greatsword, a bow beats everything in a bowman's main
## hand - and the price still decides between two pieces of the same kind. Held
## pieces and naked coverings never compete, and a piece the body's trade refuses
## (`Contracts.disposition_refuses_gear`: a bow to a blade) is not a spare at all
## - the hands wait for what they will use, and the bow waits in the pool.
##
## The off hand is the one slot where the stance outranks the price
## (`Contracts.disposition_off_hand_rank`): a tank takes the board over a second
## blade however much the blade is worth, because holding the line is what the
## hand is for. Inside one kind the dearest still wins, as everywhere else.
func _best_spare(slot_id: String, gear: Dictionary, disposition: String = "") -> String:
	var pool := field_stash()
	var body := Contracts.disposition_id(disposition)
	var off_worn := not str(gear.get("off", "")).is_empty() \
		and not EquipmentRules.bare_garment(str(gear.get("off", "")))
	var best := ""
	var best_score := -INF
	var best_rank := -1
	for item_id in pool.pooled_ids():
		if is_auto_equip_restricted(item_id):
			continue
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty() or not EquipmentRules.allowed(item, slot_id):
			continue
		if EquipmentRules.bare_garment(item_id):
			continue
		if Contracts.disposition_refuses_gear(body, item):
			continue
		if slot_id == "main" and off_worn and EquipmentRules.two_handed(item):
			continue
		var rank := Contracts.disposition_off_hand_rank(body, item, slot_id)
		var score := _gear_score(item_id, item, body)
		if rank < best_rank or (rank == best_rank and score <= best_score):
			continue
		best_rank = rank
		best_score = score
		best = item_id
	return best

## What one piece is worth to one body: its price plus what its kind is worth to
## the body's disposition (`Contracts.disposition_gear_score`). The one scoring
## function the arming and a pickup both read, so a bowman's main hand and a
## tank's shield hand cannot disagree about what they want.
func _gear_score(item_id: String, item: Dictionary, disposition: String) -> float:
	var value := WarbandStash.value_of(item_id, cruor.brand_of(item_id))
	var score := Contracts.disposition_gear_score(disposition, item, value)
	# Annointed steel is worth more to the body it suits: up to 40 gold-equivalent
	# for a six-annoint piece. `want_for` is the only reader, so the pool's tags
	# decide this, not a table here.
	if not annoints.ids(item_id, annoint_copy_for_item(item_id)).is_empty():
		var refs := [AnnointLedger.ref(item_id, annoint_copy_for_item(item_id))]
		score += annoints.want_for(refs, disposition) * 40.0
	return score

## Re-equip one body from the pool: everything it wears goes back first, then the
## same choice an arming pass makes fills it again - the dearest legal spare for
## each slot, scored by the body's disposition, so a tank comes back with a shield
## and a one-hander, a bowman with a bow and a melee body with the greatsword.
##
## This is the re-kit `arm_warband` is not: the arming pass only fills what is
## empty, while this hands a dressed body back and lets the band choose again.
## Nothing is minted and nothing is lost - a released piece is a pool row before
## the refill reads it, so the warband is worth the same number either side. The
## rags a body is born in stay on (they are the mesh the rig draws, not gear) and
## are traded for real armour as the fill finds it, and a body that carried an
## alternate weapon set keeps one.
##
## Returns `{ok, merc_id, released, fitted, message}`: `released` the ids that
## went back into the pool, `fitted` the `[{merc_id, slot, item_id}]` that walked
## out of it. A lent warband, a body outside the party and a body that is down
## are all refused with the kit untouched.
func reequip_merc(merc_id: int) -> Dictionary:
	var released: Array[String] = []
	var fitted: Array[Dictionary] = []
	if lent:
		return _lent_refusal({"merc_id": merc_id, "released": released, "fitted": fitted})
	if _arming:
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": ""}
	if merc_id <= 0 or not roster.has(merc_id):
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": "No such mercenary."}
	if not dressable_ids().has(merc_id):
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": "%s is not with the party." % roster.name_of(merc_id)}
	if not roster.is_alive(merc_id):
		return {"ok": false, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": "%s cannot be dressed right now." % roster.name_of(merc_id)}
	var second_set := _second_set_bound(merc_id)
	_arming = true
	released = _release_worn(merc_id, field_stash())
	fitted = _refill(merc_id, second_set)
	_arming = false
	var message := _reequip_message(merc_id, released, fitted)
	if released.is_empty() and fitted.is_empty():
		return {"ok": true, "merc_id": merc_id, "released": released, "fitted": fitted,
			"message": message}
	_notify()
	armed.emit([merc_id])
	return {"ok": true, "merc_id": merc_id, "released": released, "fitted": fitted,
		"message": message}

## Re-equip the whole band in one pass: every dressable body hands its kit back
## into the pool first, then the roster is built one body at a time in recruitment
## order, so the oldest name takes the pick of it. That is the point of the pass
## rather than a flaw in it - the pool is one pile of gear, the first body to be
## dressed gets the plate and the next one gets the mail.
##
## Both halves run in separate loops on purpose: releasing as each body is filled
## would let a body keep a piece the later one is better suited to only because it
## was already wearing it. Returns `{ok, mercs, released, fitted, message}`,
## `mercs` being every body the refill fitted, front of the roster first.
func reequip_warband() -> Dictionary:
	var fitted: Array[Dictionary] = []
	var mercs: Array[int] = []
	var released: Array[String] = []
	if lent:
		return _lent_refusal({"mercs": mercs, "released": released, "fitted": fitted})
	if _arming:
		return {"ok": false, "mercs": mercs, "released": released, "fitted": fitted,
			"message": ""}
	var bodies: Array[int] = []
	for merc_id in dressable_ids():
		if roster.is_alive(merc_id):
			bodies.append(merc_id)
	# Which bodies carried a second weapon set, read before the release empties
	# the one the refill would otherwise only put half a kit back into.
	var seconds: Dictionary = {}
	for merc_id in bodies:
		seconds[merc_id] = _second_set_bound(merc_id)
	var pool := field_stash()
	_arming = true
	for merc_id in bodies:
		released.append_array(_release_worn(merc_id, pool))
	for merc_id in bodies:
		var got := _refill(merc_id, bool(seconds.get(merc_id, false)))
		if got.is_empty():
			continue
		fitted.append_array(got)
		if not mercs.has(merc_id):
			mercs.append(merc_id)
	_arming = false
	var message := _band_reequip_message(mercs, fitted, released)
	if released.is_empty() and fitted.is_empty():
		return {"ok": true, "mercs": mercs, "released": released, "fitted": fitted,
			"message": message}
	_notify()
	armed.emit(mercs)
	return {"ok": true, "mercs": mercs, "released": released, "fitted": fitted,
		"message": message}

## Hand every real piece a body wears back into `pool`, both weapon sets included.
## The rags it is born in stay on: `EquipmentRules.bare_garment` is the mesh the
## rig draws rather than gear, and no arming pass would ever hand it out again.
## Returns the ids released, in wear order. The caller owns the notify.
func _release_worn(merc_id: int, pool: WarbandStash) -> Array[String]:
	var out: Array[String] = []
	if pool == null:
		return out
	for entry in roster.worn_entries(merc_id):
		var item_id := str(entry.get("item", ""))
		if item_id.is_empty() or EquipmentRules.bare_garment(item_id):
			continue
		if roster.take_worn(merc_id, str(entry.get("slot", "")),
				int(entry.get("set", -1))) != item_id:
			continue
		pool.add(item_id, 1)
		out.append(item_id)
	return out

## Fill a body that has just been stripped, from the pool the field works. The set
## in the hands is filled first; a body that carried a second one has it filled
## too, by putting that set in the hands for the length of the fill and swapping
## back after - so what the player set up is re-armed instead of halved.
## Returns `[{merc_id, slot, item_id}]`. The caller owns the notify.
func _refill(merc_id: int, second_set: bool = false) -> Array[Dictionary]:
	var fitted := _fill_slots(merc_id, DRESS_SLOTS)
	if not second_set:
		return fitted
	var swap: Dictionary = roster.swap_weapon_set(merc_id)
	if not bool(swap.get("ok", false)):
		return fitted
	fitted.append_array(_fill_slots(merc_id, RosterScript.HAND_SLOTS))
	roster.swap_weapon_set(merc_id)
	return fitted

## Whether the body carries a pair in the weapon set the hands are not holding.
## Both halves of the pair count: a stowed blade is re-armed like one in hand.
func _second_set_bound(merc_id: int) -> bool:
	var pair := roster.weapon_set_pair(merc_id, 1)
	return not str(pair.get("main", "")).is_empty() \
		or not str(pair.get("off", "")).is_empty()

## One line naming what one body's re-equip took, or why it took nothing.
func _reequip_message(merc_id: int, released: Array, fitted: Array) -> String:
	var merc_name := roster.name_of(merc_id)
	if not fitted.is_empty():
		return "%s re-equips from %s: %s." % [merc_name, field_label(), _fitted_names(fitted)]
	if not released.is_empty():
		return "%s hands everything back; %s holds nothing spare." % [merc_name, field_label()]
	return "%s is down to rags already, and %s holds nothing spare." % [merc_name, field_label()]

## One line for a band-wide pass: how many pieces each body took, roster first. A
## pass that only emptied the bodies says that instead of pretending to have fitted
## something nobody had.
func _band_reequip_message(mercs: Array, fitted: Array, released: Array) -> String:
	if fitted.is_empty():
		if released.is_empty():
			return "There is nothing to re-equip: %s holds nothing spare." % field_label()
		return "The band hands its kit back; %s holds nothing spare." % field_label()
	var counts: Dictionary = {}
	for entry in fitted:
		var merc_id := int((entry as Dictionary).get("merc_id", 0))
		counts[merc_id] = int(counts.get(merc_id, 0)) + 1
	var parts: Array[String] = []
	for merc_id in mercs:
		var count := int(counts.get(int(merc_id), 0))
		if count <= 0:
			continue
		parts.append("%s %d" % [roster.name_of(int(merc_id)), count])
	return "The band re-equips from %s: %s." % [field_label(), ", ".join(parts)]

## The names of the pieces a pass fitted, in fitting order.
func _fitted_names(fitted: Array) -> String:
	var names: Array[String] = []
	for entry in fitted:
		var item_id := str((entry as Dictionary).get("item_id", ""))
		names.append(str(State.ITEMS.get(item_id, {}).get("name", item_id)))
	return ", ".join(names)

## One line naming the bodies an arming pass fitted, and what each took.
func _arm_message(fitted: Array) -> String:
	var parts: Array[String] = []
	for entry in fitted:
		var row: Dictionary = entry
		var merc_id := int(row.get("merc_id", 0))
		var item_id := str(row.get("item_id", ""))
		parts.append("%s %s" % [roster.name_of(merc_id),
			str(State.ITEMS.get(item_id, {}).get("name", item_id))])
	if parts.size() == 1:
		var only: Dictionary = fitted[0]
		return "%s takes it (%s)." % [roster.name_of(int(only.get("merc_id", 0))),
			EquipmentRules.slot_label(str(only.get("slot", "")))]
	return "The band arms itself: %s." % ", ".join(parts)

## Hold an item id back from every automatic equip - a band-wide arming pass, a
## recruit's dressing or a loot pickup. Manual equipping is untouched: a hand on
## the paperdoll may still wear one, so the override steers the AI, not the
## player. Item ids, not copies, so every spare and every worn copy obey it.
## Returns `{ok, item_id, restricted, message}`; a lent warband is refused.
func restrict_auto_equip(item_id: String, restricted: bool = true) -> Dictionary:
	if lent:
		return _lent_refusal({"item_id": item_id, "restricted": false})
	var id := State.migrate_item_id(item_id)
	var item: Dictionary = State.ITEMS.get(id, {})
	if item.is_empty():
		return {"ok": false, "item_id": item_id, "restricted": false,
			"message": "No such piece to hold back."}
	var was := is_auto_equip_restricted(id)
	if restricted:
		auto_equip_restricted[id] = true
	else:
		auto_equip_restricted.erase(id)
	if was != restricted:
		_notify()
	var display := str(item.get("name", id))
	var message := "%s may be auto-equipped again." % display
	if restricted:
		message = "%s is restricted from auto-equip." % display
	return {"ok": true, "item_id": id, "restricted": restricted,
		"message": message}

## Whether the player has held this piece back from automatic equipping.
func is_auto_equip_restricted(item_id: String) -> bool:
	return auto_equip_restricted.has(State.migrate_item_id(item_id))

## Every held item id, sorted - what the save writes and a panel can list.
func restricted_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in auto_equip_restricted:
		out.append(str(item_id))
	out.sort()
	return out

## Buy one catalog item into the shared stash with gold. The price is the same
## keeper price the paperdoll and the stash sort use, so nothing can disagree
## about what a piece is worth. A catalog row that carries a `bundle` (ammunition)
## hands over that many copies for the list price per copy, so one visit to the
## shelf is a quiver's worth of shafts and a sale still pays per shaft. The band
## arms itself from the pool as the purchase lands, so a shopping spree is felt
## on the bodies rather than left sitting in a row.
func buy_gear(item_id: String) -> Dictionary:
	if lent:
		return _lent_refusal({"item_id": item_id, "cost": 0})
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty():
		return {"ok": false, "message": "The quartermaster does not stock that.", "item_id": item_id, "cost": 0, "count": 0}
	var count := State.item_bundle(item_id)
	var cost := int(item.get("price", 0)) * count
	if int(item.get("price", 0)) <= 0:
		return {"ok": false, "message": "That piece has no price.", "item_id": item_id, "cost": 0, "count": 0}
	if not spend_gold(cost):
		return {"ok": false, "item_id": item_id, "cost": cost, "count": count,
			"message": "You need %d gold; you have %d." % [cost, gold()]}
	stash.add(item_id, count)
	var armed: Dictionary = arm_warband()
	_notify()
	var display := str(item.get("name", item_id))
	if count > 1:
		display = "%d × %s" % [count, display]
	var message := "Bought %s for %d gold into the shared stash." % [display, cost]
	var fitted: Array = armed.get("fitted", [])
	if not fitted.is_empty():
		message += " " + str(armed.get("message", ""))
	return {"ok": true, "item_id": item_id, "cost": cost, "count": count,
		"message": message, "armed": fitted}

## Sell one pooled copy back to a keeper. The piece must be in the shared pool:
## a blade somebody is wearing is not the warband's to sell behind their back,
## and the pool is the only place a copy can leave without stripping a body.
##
## The keeper pays `share` of the catalogue price (60% by default), floored to a
## whole coin, so a sale always returns less than the purchase. `price` in the
## reply is what the purse was actually paid, not the catalogue figure.
func sell_gear(item_id: String, share: float = 0.6) -> Dictionary:
	if lent:
		return _lent_refusal({"price": 0, "item_id": item_id})
	var id := State.migrate_item_id(item_id)
	var item: Dictionary = State.ITEMS.get(id, {})
	if item.is_empty():
		return {"ok": false, "message": "No keeper buys that.", "price": 0, "item_id": item_id}
	var list_price := int(item.get("price", 0))
	if list_price <= 0:
		return {"ok": false, "message": "That piece has no price.", "price": 0, "item_id": id}
	var display := str(item.get("name", id))
	# The pool is the authority on whether there is a copy to sell: a worn piece
	# is on a body, not on the keeper's shelf, and a failed removal must never pay.
	# Sell the plainest copy first: an annointed copy is one of a kind and never
	# leaves by accident because its kind was cheaper than its marks.
	var plainest := -1
	var fewest := -1
	for serial in stash.serials_of(id):
		var marks := annoints.count(id, int(serial))
		if fewest < 0 or marks < fewest:
			plainest = int(serial)
			fewest = marks
	if not stash.remove(id, 1, plainest):
		return {"ok": false, "price": 0, "item_id": id,
			"message": "You have no spare %s in the stash." % display}
	var payout := int(floor(float(list_price) * clampf(share, 0.0, 1.0)))
	var state := get_node_or_null("/root/PlayerState")
	if state != null:
		state.add_credits(payout)
	_notify()
	return {"ok": true, "item_id": id, "price": payout,
		"message": "Sold %s for %d gold." % [display, payout]}

## The altar's ritual: one warden's ichor, four equal outcomes, no destruction.
##
##   * add an ability / add a passive / remove one / replace one, 25% each
##   * at six annointments the two add outcomes become a replace
##
## `ordinal` names the copy (see `annoint_copy`); -1 takes the first copy, which
## is what the altar's list presses. `rng` exists so a regression can force a
## band - the game never passes one.
func anoint(item_id: String, ordinal: int = -1, rng: RandomNumberGenerator = null) -> Dictionary:
	if lent:
		return _lent_refusal({"item_id": item_id, "outcome": -1, "entry_id": "",
			"removed_id": "", "count": 0, "max": AnnointCatalog.MAX_PER_PIECE})
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var piece := str(item.get("name", item_id))
	if item.is_empty():
		return {"ok": false, "message": "The altar does not know that piece.",
			"item_id": item_id, "outcome": -1, "entry_id": "", "removed_id": "",
			"count": 0, "max": AnnointCatalog.MAX_PER_PIECE}
	var pool := _annoint_pool(item, str(item.get("slot", "")))
	if int(item.get("price", 0)) < CruorScript.MAGIC_PRICE or pool.is_empty():
		return {"ok": false, "message": "The altar will not take that.",
			"item_id": item_id, "outcome": -1, "entry_id": "", "removed_id": "",
			"count": 0, "max": AnnointCatalog.MAX_PER_PIECE}
	if not stash.available_ids(roster).has(item_id):
		return {"ok": false, "message": "The warband does not carry a %s." % piece,
			"item_id": item_id, "outcome": -1, "entry_id": "", "removed_id": "",
			"count": 0, "max": AnnointCatalog.MAX_PER_PIECE}
	if stash.pooled_count(CruorScript.BASIC_REAGENT) < 1:
		return {"ok": false, "message": "The rite needs %s." % str(State.ITEMS.get(
			CruorScript.BASIC_REAGENT, {}).get("name", CruorScript.BASIC_REAGENT)),
			"item_id": item_id, "outcome": -1, "entry_id": "", "removed_id": "",
			"count": 0, "max": AnnointCatalog.MAX_PER_PIECE}
	var copy := _resolve_copy(item_id, ordinal)
	var existing := annoints.ids(item_id, copy)
	var at_cap := existing.size() >= AnnointCatalog.MAX_PER_PIECE
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var rolled := AnnointRoll.roll(pool, existing, at_cap, rng)
	stash.remove(CruorScript.BASIC_REAGENT, 1)
	var outcome := int(rolled["outcome"])
	var added := str(rolled["entry_id"])
	var removed := str(rolled["removed_id"])
	var committed := false
	var skill := ""
	match outcome:
		AnnointRoll.Outcome.ADD_ABILITY, AnnointRoll.Outcome.ADD_PASSIVE:
			committed = annoints.add(item_id, copy, added)
		AnnointRoll.Outcome.REMOVE:
			committed = annoints.remove_id(item_id, copy, removed)
		AnnointRoll.Outcome.REPLACE:
			committed = annoints.replace(item_id, copy, removed, added)
	var completed: Array[String] = []
	for quest_id in quests.note_applied(CruorScript.BASIC_REAGENT, 1):
		if quests.is_complete(quest_id):
			completed.append(quest_id)
	if committed and not added.is_empty():
		var entry := AnnointCatalog.by_id(added)
		if entry != null and int(entry.kind) == AnnointCatalog.Kind.ABILITY:
			skill = str(entry.ability)
			anointed.emit(item_id, skill)
	annointed_state.emit(item_id, annoints.ids(item_id, copy))
	_notify()
	var message := str(rolled["message"])
	if not committed:
		message += " The piece is unchanged."
	var line := "%s  [%d / %d]" % [message, annoints.count(item_id, copy),
		AnnointCatalog.MAX_PER_PIECE]
	return {"ok": committed, "message": line, "item_id": item_id, "ordinal": copy,
		"outcome": outcome, "converted": bool(rolled["converted"]),
		"entry_id": added, "removed_id": removed, "skill": skill,
		"count": annoints.count(item_id, copy), "max": AnnointCatalog.MAX_PER_PIECE,
		"spent": {CruorScript.BASIC_REAGENT: 1}, "completed": completed}

## What the altar would tell a player before they spend the vial.
func annoint_preview(item_id: String, ordinal: int = -1) -> Dictionary:
	var item: Dictionary = State.ITEMS.get(item_id, {})
	var pool := _annoint_pool(item, str(item.get("slot", "")))
	var copy := _resolve_copy(item_id, ordinal)
	var owned := not item.is_empty() and stash.available_ids(roster).has(item_id)
	var can := owned and int(item.get("price", 0)) >= CruorScript.MAGIC_PRICE \
		and not pool.is_empty() \
		and stash.pooled_count(CruorScript.BASIC_REAGENT) >= 1
	var reason := ""
	if not owned:
		reason = "The warband does not carry one."
	elif int(item.get("price", 0)) < CruorScript.MAGIC_PRICE:
		reason = "The altar will not take that."
	elif pool.is_empty():
		reason = "Nothing fits that piece."
	elif stash.pooled_count(CruorScript.BASIC_REAGENT) < 1:
		reason = "The rite needs %s." % str(State.ITEMS.get(CruorScript.BASIC_REAGENT,
			{}).get("name", CruorScript.BASIC_REAGENT))
	return {"ok": can, "message": reason, "item_id": item_id, "ordinal": copy,
		"pool": pool.size(), "abilities": AnnointCatalog.abilities_of(pool).size(),
		"count": annoints.count(item_id, copy), "max": AnnointCatalog.MAX_PER_PIECE,
		"full": annoints.is_full(item_id, copy), "odds": AnnointRoll.CHANCES,
		"reagent": CruorScript.BASIC_REAGENT}

## The pool a piece rolls from: its type's pool, or its armour slot's.
func _annoint_pool(item: Dictionary, slot: String) -> Array:
	if str(item.get("category", "")) == "armor":
		return AnnointCatalog.for_armour_slot(slot)
	return AnnointCatalog.for_item(item)

# --- copies ----------------------------------------------------------------

## Which copy of `item_id` a mercenary wears in `slot_id`. The roster keeps
## catalog ids, so the copy is resolved here once and remembered: a body wears
## the most-annointed copy that no other slot has claimed, else the lowest free
## ordinal. That is what keeps one annointed bow from being worn twice.
func annoint_copy(merc_id: int, slot_id: String) -> int:
	var key := "%d:%s" % [merc_id, slot_id]
	var item_id := str(roster.equipped_of(merc_id).get(slot_id, ""))
	var held: Variant = worn_copies.get(key, {})
	if held is Dictionary and not item_id.is_empty() \
			and str((held as Dictionary).get("item", "")) == item_id:
		return int((held as Dictionary).get("ordinal", 0))
	var ordinal := _claim_copy(merc_id, slot_id, item_id)
	worn_copies[key] = {"item": item_id, "ordinal": ordinal}
	return ordinal

## The copy a body takes up, named by the serial every physical copy carries.
##
## A body claims a *free* copy from the pool - the plainest one first, so a piece
## bought off a keeper is plain steel even when a relic of the same kind is
## sitting beside it - and the claim takes that copy out of the pool and remembers
## its serial for the slot. The relic is only ever worn by a body that claimed it,
## which is what stops one annointed greatsword turning every greatsword into one.
func _claim_copy(merc_id: int, slot_id: String, item_id: String) -> int:
	if item_id.is_empty():
		return 0
	var key := "%d:%s" % [merc_id, slot_id]
	var best := -1
	var best_marks := -1
	for serial in stash.serials_of(item_id):
		if _serial_is_worn_elsewhere(int(serial), item_id, key):
			continue
		var marks := annoints.count(item_id, int(serial))
		if best_marks < 0 or marks < best_marks:
			best = int(serial)
			best_marks = marks
	if best >= 0:
		stash.remove(item_id, 1, best)
	else:
		# Nothing in the pool to take (the piece was put on a body before the pool
		# ever held it): give the copy an identity of its own, but do not invent a
		# spare - a phantom copy in the pool is a piece the warband does not own.
		best = stash.mint_serial(item_id)
	worn_copies[key] = {"item": item_id, "ordinal": best}
	return best


## Whether another slot's copy is this same serial. A serial is worn by one body
## at a time; a legacy save may name one that two slots still claim.
func _serial_is_worn_elsewhere(serial: int, item_id: String, mine: String) -> bool:
	for key in worn_copies:
		if str(key) == mine:
			continue
		var held: Variant = worn_copies[key]
		if held is Dictionary and str((held as Dictionary).get("item", "")) == item_id \
				and int((held as Dictionary).get("ordinal", 0)) == serial:
			return true
	return false


## A copy leaving a body: the slot forgets it and the caller gets the piece and
## the serial it was worn under, so the weapon that was annointed is the weapon
## that comes off the body. The caller puts it back; this only lets go.
func _release_copy(merc_id: int, slot_id: String) -> Dictionary:
	var key := "%d:%s" % [merc_id, slot_id]
	var held: Variant = worn_copies.get(key, {})
	worn_copies.erase(key)
	if not held is Dictionary:
		return {}
	var item_id := str((held as Dictionary).get("item", ""))
	if item_id.is_empty():
		return {}
	return {"item": item_id, "serial": int((held as Dictionary).get("ordinal", -1))}

## Which copy a card for `item_id` is showing: the first copy that exists, else
## the first one a body wears, else 0. Cards are read off the piece, not a body,
## so this is the least surprising answer for a stash row.
func annoint_copy_for_item(item_id: String) -> int:
	return _resolve_copy(item_id, -1)


## The copy an altar press means when it names none: the copy a body is wearing
## (the piece in the hand is the piece the player walked up with), else the
## plainest spare. A copy is an instance, so a press never reaches across to a
## relic the warband is not wearing, and a purchase is a new weapon with no marks.
## `ordinal >= 0` is taken as given.
func _resolve_copy(item_id: String, ordinal: int) -> int:
	if ordinal >= 0:
		return ordinal
	for key in worn_copies:
		var held: Variant = worn_copies[key]
		if held is Dictionary and str((held as Dictionary).get("item", "")) == item_id:
			return int((held as Dictionary).get("ordinal", 0))
	var best := -1
	var fewest := -1
	for serial in stash.serials_of(item_id):
		var marks := annoints.count(item_id, int(serial))
		if fewest < 0 or marks < fewest:
			best = int(serial)
			fewest = marks
	return maxi(best, 0)

## The annointment-bearing pieces one body wears, as ledger refs. The armour, the
## hands and the worn jewellery: a necklace or a ring is a piece the altar can
## work exactly like steel, and its weld is the cord's own.
func annoint_refs(merc_id: int) -> Array:
	var out: Array = []
	var kit := roster.equipped_of(merc_id)
	for slot in AnnointCatalog.ARMOUR_SLOTS + ["main", "off"] \
			+ AnnointCatalog.JEWELRY_SLOTS:
		var item_id := str(kit.get(slot, ""))
		if item_id.is_empty():
			continue
		out.append(AnnointLedger.ref(item_id, annoint_copy(merc_id, slot)))
	return out

## Every stat this body's annointments add, in `TrinketStats` shape.
func annointment_stats(merc_id: int) -> Dictionary:
	return annoints.stats_for(annoint_refs(merc_id))

## The skills this body's annointments wake, one list per worn slot: a copy may
## carry several ability welds and every one of them reaches the hotbar - a hand's
## from the hand that holds it, a necklace's from the neck that wears it.
func annointment_skills(merc_id: int) -> Dictionary:
	var kit := roster.equipped_of(merc_id)
	var out := {"main": [], "off": []}
	for slot in AnnointCatalog.JEWELRY_SLOTS:
		out[slot] = []
	for slot in ["main", "off"] + AnnointCatalog.JEWELRY_SLOTS:
		var item_id := str(kit.get(slot, ""))
		if item_id.is_empty():
			continue
		out[slot] = annoints.skills_of(item_id, annoint_copy(merc_id, slot))
	return out

## The procs this body's annointments arm: `AnnointRuntime` reads this once per
## dress and rolls the verbs itself.
func annointment_procs(merc_id: int) -> Array:
	return annoints.procs_for(annoint_refs(merc_id))

## How many annointments each held copy carries, per worn slot. The rig draws a
## hand's as inlaid marks on the weapon; the preview draws the necklace's on its
## stone, one per annointment.
func annointment_marks(merc_id: int) -> Dictionary:
	var kit := roster.equipped_of(merc_id)
	var out := {"main": 0, "off": 0}
	for slot in AnnointCatalog.JEWELRY_SLOTS:
		out[slot] = 0
	for slot in ["main", "off"] + AnnointCatalog.JEWELRY_SLOTS:
		var item_id := str(kit.get(slot, ""))
		if item_id.is_empty():
			continue
		out[slot] = annoints.count(item_id, annoint_copy(merc_id, slot))
	return out

## How much this body wants its own annointed kit, 0..1, for the arming pass.
func annointment_want(merc_id: int, disposition: String) -> float:
	return annoints.want_for(annoint_refs(merc_id), disposition)

# --- the hotbar -------------------------------------------------------------
#
# The altar decides which skills a kit grants; the player decides which of the
# ten keys each one sits on. The layout is a sequence of ability ids stored per
# mercenary (`WarbandRoster.KEY_HOTBAR`), and `AbilityRules.granted` lays the kit
# out through it, so the HUD, the runner and the paperdoll all read one order.
# The layout never grants a skill: an id the kit does not wake is skipped.

## The skill ids this body's kit grants right now, in kit order. Mirrors the
## dressing `SeatLoadout` runs, without a rig: a roster record may have no body
## at all (a reserve, a name the scene never spawned) and the paperdoll still
## has to draw the keys that body would fire.
func hotbar_kit(merc_id: int) -> Array[String]:
	var out: Array[String] = []
	var gear := roster.equipped_of(merc_id)
	var main_id := str(gear.get("main", ""))
	var off_id := str(gear.get("off", ""))
	var main := ""
	var off := ""
	var hands := {"main": [], "off": []}
	if not main_id.is_empty():
		main = AbilityRules.stock_item(State.ITEMS.get(main_id, {}))
		hands["main"] = _hotbar_hand(main_id, "main", merc_id)
	# The off hand only performs a skill while it holds a shield: an off-hand
	# blade is a dual-wield partner, and `AbilityRules.off_item` grants nothing
	# for it either.
	if str(State.ITEMS.get(off_id, {}).get("category", "")) == "shield":
		off = AbilityRules.stock_item(State.ITEMS.get(off_id, {}))
		hands["off"] = _hotbar_hand(off_id, "off", merc_id)
	var trinkets := {"neck": str(gear.get("neck", "")),
		"ring1": str(gear.get("ring1", "")), "ring2": str(gear.get("ring2", ""))}
	# A worn necklace or ring wakes the skills the altar welded to that copy,
	# exactly as the rig hears it through `SeatLoadout`; the stock grant rides
	# alongside whichever ids the cord carries.
	for slot in AnnointCatalog.JEWELRY_SLOTS:
		var worn_id := str(gear.get(slot, ""))
		if worn_id.is_empty():
			continue
		var welded := annoints.skills_of(worn_id, annoint_copy(merc_id, slot))
		if not welded.is_empty():
			hands[slot] = welded
	for definition in AbilityRules.grants_for(main, off, hands, trinkets):
		var id := str(definition.get("id", ""))
		if id.is_empty() or out.has(id):
			continue
		out.append(id)
	# The two consumables every body carries, after the kit's own skills - the
	# same order `AbilityRules.granted` lays on the rig, so the page's row and
	# the keys a fight fires cannot disagree about where the bandage sits.
	for id in AbilityRules.CONSUMABLE_IDS:
		if not out.has(id):
			out.append(id)
	return out


## The skills one hand of this body's kit wakes: the copy's own welds when the
## altar welded any, otherwise the piece's catalog anointing - the same two
## sources `SeatLoadout.apply` reads for the live rig.
func _hotbar_hand(item_id: String, hand: String, merc_id: int) -> Array[String]:
	var welded := annoints.skills_of(item_id, annoint_copy(merc_id, hand))
	if not welded.is_empty():
		return welded
	var skill := State.anointed_skill(item_id, 1 if hand == "off" else 0,
		cruor.anointed_among([item_id]))
	var out: Array[String] = []
	if not skill.is_empty():
		out.append(skill)
	return out


## The body's kit skills in the player's own sequence, one per hotbar slot. The
## layout ranks the kit and the eight keys before the consumables take the first
## eight, the same cap `AbilityRules.granted` applies - so a kit with more welds
## than keys draws the same row on the HUD and in the paperdoll. The bandage and
## the potion are not the kit's and are laid by `hotbar_layout`.
func hotbar_skills(merc_id: int) -> Array[String]:
	var kit: Array[String] = []
	for id in hotbar_kit(merc_id):
		if not AbilityRules.CONSUMABLE_IDS.has(id):
			kit.append(id)
	var ordered := AbilityRules.ordered_ids(kit, roster.hotbar_order_of(merc_id))
	var slots := AbilityRules.SLOT_COUNT - AbilityRules.CONSUMABLE_IDS.size()
	var out: Array[String] = []
	for index in mini(ordered.size(), slots):
		out.append(ordered[index])
	return out


## The ten keys exactly as the HUD draws them: the kit's sequence on the first
## eight, the bandage on key 9 and the potion on key 0, "" for a key that fires
## nothing. The two consumables keep their keys whatever the kit or the saved
## sequence says, which is the same rule `AbilityRules._layout` applies to the
## rig - the page and the fight cannot disagree about where the bandage sits.
func hotbar_layout(merc_id: int) -> Array[String]:
	var kit := hotbar_skills(merc_id)
	var kit_slots := AbilityRules.SLOT_COUNT - AbilityRules.CONSUMABLE_IDS.size()
	var out: Array[String] = []
	for index in AbilityRules.SLOT_COUNT:
		out.append("")
	for index in mini(kit.size(), kit_slots):
		out[index] = kit[index]
	var granted := hotbar_kit(merc_id)
	for offset in AbilityRules.CONSUMABLE_IDS.size():
		var id := str(AbilityRules.CONSUMABLE_IDS[offset])
		if granted.has(id):
			out[kit_slots + offset] = id
	return out


## Lay the body's skills out on the ten keys. `order` is a sequence of ability
## ids; ids this body's kit does not grant are dropped, and every grant the
## sequence leaves out is appended in kit order, so what is stored is always a
## permutation of what the body can actually fire. Answers `{ok, message, order}`.
func set_hotbar_order(merc_id: int, order: Array) -> Dictionary:
	if lent:
		return _lent_refusal({"order": []})
	if not roster.has(merc_id):
		return {"ok": false, "message": "No such mercenary.", "order": []}
	var kit := hotbar_kit(merc_id)
	var laid: Array[String] = []
	for item in order:
		var id := str(item)
		if id.is_empty() or not kit.has(id) or laid.has(id):
			continue
		if AbilityRules.CONSUMABLE_IDS.has(id):
			continue
		laid.append(id)
	for id in kit:
		if laid.has(id) or AbilityRules.CONSUMABLE_IDS.has(id):
			continue
		laid.append(id)
	# The last two keys are the consumables' own: the sequence arranges the kit,
	# and the bandage and the potion ride after it wherever the caller named them.
	for id in AbilityRules.CONSUMABLE_IDS:
		if kit.has(id) and not laid.has(id):
			laid.append(id)
	roster.set_hotbar_order(merc_id, laid)
	# The body in the world is dressed from the record, so its own key order
	# follows the write; a body nobody is inside picks it up at its next spawn.
	armed.emit([merc_id])
	_notify()
	return {"ok": true, "message": "The keys are laid out.", "order": laid}


## Move the skill on key `from_slot` to key `to_slot`, swapping whatever was
## there. Slots are the ten keys the number row fires, not indices into the
## stored sequence, so moving a skill into an empty key closes the row up
## behind it. The bandage and the potion keep the last two keys and are not
## movable: a body always has them. Answers `{ok, message, order}`.
func move_hotbar_skill(merc_id: int, from_slot: int, to_slot: int) -> Dictionary:
	if lent:
		return _lent_refusal({"order": []})
	if not roster.has(merc_id):
		return {"ok": false, "message": "No such mercenary.", "order": []}
	if from_slot < 0 or from_slot >= AbilityRules.SLOT_COUNT \
			or to_slot < 0 or to_slot >= AbilityRules.SLOT_COUNT:
		return {"ok": false, "message": "That is not a hotbar key.", "order": []}
	if from_slot == to_slot:
		return {"ok": false, "message": "That skill is already on key %d."
			% (from_slot + 1), "order": []}
	var kit_slots := AbilityRules.SLOT_COUNT - AbilityRules.CONSUMABLE_IDS.size()
	if from_slot >= kit_slots or to_slot >= kit_slots:
		return {"ok": false, "message": "The bandage keeps key 9 and the potion key 0.",
			"order": []}
	var layout := hotbar_layout(merc_id)
	if layout[from_slot].is_empty() and layout[to_slot].is_empty():
		return {"ok": false, "message": "Both keys are empty.", "order": []}
	var held := layout[from_slot]
	layout[from_slot] = layout[to_slot]
	layout[to_slot] = held
	var order: Array[String] = []
	for id in layout:
		if not id.is_empty():
			order.append(id)
	var result := set_hotbar_order(merc_id, order)
	if bool(result.get("ok", false)):
		result["message"] = "Skills swapped." if not layout[from_slot].is_empty() \
			and not layout[to_slot].is_empty() else "Skill moved."
	return result


## Drop the player's layout: the keys follow the kit again - the main hand, the
## off hand, then the necklace, ring 1 and ring 2.
func reset_hotbar(merc_id: int) -> Dictionary:
	if lent:
		return _lent_refusal({"order": []})
	if not roster.has(merc_id):
		return {"ok": false, "message": "No such mercenary.", "order": []}
	roster.set_hotbar_order(merc_id, [])
	armed.emit([merc_id])
	_notify()
	return {"ok": true, "message": "The keys follow the kit again.", "order": []}

## A piece found already anointed - a rare watcher's steel below (`delve_loot.gd`)
## - wakes into its skill the moment the warband takes it, and `anointed` dresses
## the bodies already holding a copy, exactly as the altar's rite does. Nothing is
## spent. False for a lent warband, a piece with no skill, and one already awake.
func grant_anointing(item_id: String) -> bool:
	if lent or not cruor.grant_anointing(item_id):
		return false
	anointed.emit(item_id, cruor.anointed_skill(item_id))
	_notify()
	return true

func hire(merc_name: String = "") -> Dictionary:
	if lent:
		return _lent_refusal({"merc_id": -1, "cost": 0})
	var state := get_node_or_null("/root/PlayerState")
	var room := field_room() > 0
	var result := WarbandVendor.hire(roster, state, merc_name, deployment_cap) if state != null \
		else {"ok": false, "message": "The purse is missing.", "merc_id": -1, "cost": 0}
	if bool(result.get("ok", false)):
		# A body that swears with empty hands is dead weight: the recruiter's
		# oath includes whatever the shared stash can spare.
		var merc_id := int(result.get("merc_id", -1))
		# A hire takes the field at the desk when there is a place for him.
		roster.set_reserve(merc_id, not room)
		var dressed := dress_recruit(merc_id)
		var fitted: Array = dressed.get("fitted", [])
		if not fitted.is_empty():
			result["fitted"] = fitted
			result["message"] = "%s %s" % [str(result.get("message", "")),
				str(dressed.get("message", ""))]
		_notify()
	return result

func hire_cost() -> int:
	return WarbandVendor.hire_cost(roster)

## Equip a mercenary from the collective stash. The stash is one pool, so a
## piece another mercenary is already wearing is a *transfer*, not a refusal:
## the wearer is stripped and the piece walks across. Without that rule the only
## dagger in a fresh warband could never be handed from the rescuer to a
## prisoner, which is exactly what the first scene asks the player to do.
## `announce` false lets a caller that is fitting several pieces in one pass
## (`arm_warband`, `dress_recruit`) emit a single `changed` instead of one per
## slot; the caller then owns the notify.
func equip_merc(merc_id: int, slot_id: String, item_id: String,
		announce: bool = true) -> Dictionary:
	if lent:
		return _lent_refusal({"displaced": {}})
	if item_id.is_empty():
		return {"ok": false, "message": "Choose a piece of gear.", "displaced": {}}
	if delve.active and not delve.party.has(merc_id):
		return {"ok": false, "message": "%s is not with the party." % roster.name_of(merc_id),
			"displaced": {}}
	var pool := field_stash()
	var gear := roster.equipped_of(merc_id)
	if str(gear.get(slot_id, "")) == item_id:
		return {"ok": true, "message": "%s is already worn there." % roster.name_of(merc_id),
			"displaced": {}}
	var was_wearing := str(gear.get(slot_id, ""))
	var moved_from := ""
	var moved_serial := -1
	if pool.pooled_count(item_id) <= 0:
		var taken := _strip_worn(item_id, pool)
		if not bool(taken.get("ok", false)):
			return {"ok": false, "message": "You do not own that piece yet.", "displaced": {}}
		moved_from = str(taken.get("from", ""))
		# The stripped copy comes with the serial it was worn under.
		moved_serial = int(taken.get("serial", -1))
	var result := roster.equip(merc_id, slot_id, item_id)
	if not bool(result.get("ok", false)):
		# Put the stripped piece back where it came from: a refused equip must
		# not quietly pocket somebody else's gear.
		if not moved_from.is_empty():
			pool.remove(item_id, 1, moved_serial)
		return result
	var displaced: Dictionary = result.get("displaced", {})
	if moved_serial < 0:
		# A copy off the shelf: take the plainest one, by its own serial.
		var plainest := -1
		var fewest := -1
		for serial in pool.serials_of(item_id):
			var marks := annoints.count(item_id, int(serial))
			if fewest < 0 or marks < fewest:
				plainest = int(serial)
				fewest = marks
		moved_serial = plainest
	pool.remove(item_id, 1, moved_serial)
	# The copy this body was wearing in that slot, if any, goes back to the pool
	# as itself.
	var let_go := _release_copy(merc_id, slot_id)
	if not let_go.is_empty():
		pool.add(str(let_go.get("item", "")), 1, int(let_go.get("serial", -1)))
	elif not was_wearing.is_empty():
		# A copy that was worn before copies had serials (a dress that never
		# claimed one): the piece itself still comes back to the pool.
		pool.add(was_wearing, 1)
	worn_copies["%d:%s" % [merc_id, slot_id]] = {"item": item_id,
		"ordinal": moved_serial}
	for slot in displaced:
		# The slot being equipped was released above; releasing it twice would hand
		# the newly worn copy straight back to the pool.
		if str(slot) == slot_id:
			continue
		var old_id := str(displaced[slot])
		if old_id.is_empty():
			continue
		var off := _release_copy(merc_id, slot)
		if off.is_empty():
			pool.add(old_id, 1)
		else:
			pool.add(str(off.get("item", old_id)), 1, int(off.get("serial", -1)))
	if not moved_from.is_empty():
		result["message"] = "%s taken from %s." % [str(result.get("message", "")), moved_from]
	if announce:
		_notify()
	return result

## Take one worn copy of `item_id` off whichever mercenary holds it and drop it
## into `pool`. Returns `{ok, from}` where `from` names the mercenary. Only a
## body whose gear may move right now is searched (`dressable_ids`): below, a
## piece is handed between the party's own and never fetched out of the town.
##
## Both weapon sets are searched, not just the hands: a piece waiting in the set
## the body is not carrying is still the warband's to hand over.
func _strip_worn(item_id: String, pool: WarbandStash) -> Dictionary:
	var reachable := dressable_ids()
	for entry in _worn_entries_all():
		if str(entry.get("item", "")) != item_id:
			continue
		var merc_id := int(entry.get("merc", 0))
		if not reachable.has(merc_id):
			continue
		var slot_id := str(entry.get("slot", ""))
		var label := "%s (%s)" % [roster.name_of(merc_id), Contracts.slot_id_label(slot_id)]
		if roster.take_worn(merc_id, slot_id, int(entry.get("set", -1))) != item_id:
			continue
		# The copy leaves the body with the serial it was wearing: a relic handed
		# from one body to another is still the same weapon.
		var let_go := _release_copy(merc_id, slot_id)
		var serial := int(let_go.get("serial", -1))
		pool.add(item_id, 1, serial)
		return {"ok": true, "from": label, "serial": serial}
	return {"ok": false, "from": ""}

## Every worn piece in the warband, both weapon sets included, as `{merc, slot,
## item, set}` records.
func _worn_entries_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for merc in roster.records():
		var merc_id := int(merc.get("id", 0))
		for entry in roster.worn_entries(merc_id):
			var row := entry.duplicate()
			row["merc"] = merc_id
			out.append(row)
	return out

## The piece a loot pickup should snap into the soul's hands if it can. It only
## takes a slot that is empty or holds something clearly worth less *to this body*,
## so a player never loses a good blade to a lucky drop - and a bowman's bow beats
## a dearer sword, a tank's shield beats a dearer second blade, and a melee
## body's greatsword beats a cheaper one-hander. A piece the body's trade refuses
## is never taken at all, even into an empty hand. Anything else stays in the
## stash. Returns `{ok, slot, displaced, message}`.
func auto_equip(merc_id: int, item_id: String) -> Dictionary:
	if lent:
		return _lent_refusal({"slot": ""})
	var item: Dictionary = State.ITEMS.get(item_id, {})
	if item.is_empty() or merc_id <= 0:
		return {"ok": false, "message": "", "slot": ""}
	if not str(item.get("category", "")) in EQUIPPABLE_CATEGORIES:
		return {"ok": false, "message": "", "slot": ""}
	if is_auto_equip_restricted(item_id):
		return {"ok": false, "message": "%s is restricted from auto-equip." % EquipmentRules.item_name(item),
			"slot": ""}
	if not roster.is_alive(merc_id):
		return {"ok": false, "message": "", "slot": ""}
	var disposition := roster.disposition_of(merc_id)
	# A piece this body's trade never carries is not a pickup it can use: a melee
	# body does not trade its blade for the band's spare bow, and does not take one
	# into a hand the blade will fill later. It stays a pool row.
	if Contracts.disposition_refuses_gear(disposition, item):
		return {"ok": false, "message": "", "slot": ""}
	var gear := roster.equipped_of(merc_id)
	var slot_id := EquipmentRules.auto_slot(item, gear)
	if slot_id.is_empty():
		return {"ok": false, "message": "", "slot": ""}
	var worn := str(gear.get(slot_id, ""))
	if not worn.is_empty():
		var worn_score := _gear_score(worn, State.ITEMS.get(worn, {}), disposition)
		if _gear_score(item_id, item, disposition) <= worn_score:
			return {"ok": false, "message": "", "slot": slot_id}
	var result := equip_merc(merc_id, slot_id, item_id)
	if not bool(result.get("ok", false)):
		return {"ok": false, "message": str(result.get("message", "")), "slot": slot_id}
	return {"ok": true, "slot": slot_id, "message": str(result.get("message", "")),
		"displaced": result.get("displaced", {})}

## Strip a worn piece back into the pool the field works.
func unequip_merc(merc_id: int, slot_id: String) -> String:
	if lent:
		return ""
	if delve.active and not delve.party.has(merc_id):
		return ""
	var item_id := roster.unequip(merc_id, slot_id)
	if item_id.is_empty():
		return ""
	# The copy comes off the body as itself: its serial returns with the piece.
	var off := _release_copy(merc_id, slot_id)
	field_stash().add(item_id, 1, int(off.get("serial", -1)))
	_notify()
	return item_id

## `TAB` in the world: the standing body puts away the weapon set in its hands
## and takes up the other one, exactly as the frontier's own swap does. The two
## pairs live on the roster record, so the swap is warband state - it survives a
## body hop, a reload and a scene hand-off - and the scene re-dresses the rig from
## it with `refresh_gear()`.
func swap_weapon_set(merc_id: int) -> Dictionary:
	if lent:
		return _lent_refusal({"set": 0})
	var result := roster.swap_weapon_set(merc_id)
	_notify()
	return result

## What one mercenary's kit is worth. Both weapon sets count: stowing a sword in
## the set the hands are not carrying does not make it leave the warband.
func gear_value(merc_id: int) -> int:
	var total := 0
	for entry in roster.worn_entries(merc_id):
		var item_id := str(entry.get("item", ""))
		if not item_id.is_empty():
			total += WarbandStash.value_of(item_id, cruor.brand_of(item_id))
	return total

## The warband's combined worth - gear, the town stash, the delve inventory and
## essence - for the HUD and tests.
func total_value() -> int:
	var total := 0
	for entry in _worn_entries_all():
		var item_id := str(entry.get("item", ""))
		if not item_id.is_empty():
			total += WarbandStash.value_of(item_id, cruor.brand_of(item_id))
	total += _pool_value(stash)
	total += _pool_value(delve.inventory)
	for tier in CruorCatalog.TIER_ORDER:
		total += cruor.tier_count(tier) * CruorCatalog.tier_value(tier)
	return total

func _pool_value(pool: WarbandStash) -> int:
	var total := 0
	var pooled := pool.pooled_map()
	for item_id in pooled:
		total += WarbandStash.value_of(str(item_id), cruor.brand_of(str(item_id))) * int(pooled[item_id])
	return total

# --- the delve -------------------------------------------------------------
#
# The loop the town exists for: pack supplies out of the stash into the delve
# inventory, send a party down, and either climb out with everything the party
# took (it all goes into the stash) or fall below and lose it - the inventory and
# every piece the party's members still wear. The scene owns the cave and the
# bodies; these verbs own the books, and each of the three moments that changes
# them (going down, climbing out, falling) is written to the save at once.

## Pack copies of a free piece from the town stash into the delve inventory.
## `count` -1 packs every free copy. Refused while a party is below - the pack
## went down with it. Returns `{ok, item_id, count, message}`.
func pack_for_delve(item_id: String, count: int = 1) -> Dictionary:
	return _move_pooled(stash, delve.inventory, item_id, count, "packed for the delve")

## Put packed copies back into the town stash. `count` -1 unpacks every copy.
func unpack_from_delve(item_id: String, count: int = 1) -> Dictionary:
	return _move_pooled(delve.inventory, stash, item_id, count, "back in the town stash")

func _move_pooled(from: WarbandStash, to: WarbandStash, item_id: String, count: int,
		where: String) -> Dictionary:
	if lent:
		return _lent_refusal({"item_id": item_id, "count": 0})
	var display := str(State.ITEMS.get(item_id, {}).get("name", item_id))
	if delve.active:
		return {"ok": false, "item_id": item_id, "count": 0,
			"message": "The party is below: the pack went down with it."}
	var have := from.pooled_count(item_id)
	var moved := have if count < 0 else mini(count, have)
	if moved <= 0:
		return {"ok": false, "item_id": item_id, "count": 0,
			"message": "There is no spare %s to move." % display}
	from.remove(item_id, moved)
	to.add(item_id, moved)
	_notify()
	return {"ok": true, "item_id": item_id, "count": moved,
		"message": "%s%s %s." % [display, " x%d" % moved if moved > 1 else "", where]}

## Send a party down. Every name must be on the field and standing - the scene
## checks the bodies, this checks the books. Going down is the commitment, so it
## is written at once: a load that still finds the party below counts the
## descent as lost (`load_state`), which is what makes a fall cost what it costs.
## Returns `{ok, party, message}`.
func begin_delve(party_ids: Array) -> Dictionary:
	if lent:
		return _lent_refusal({"party": []})
	if delve.active:
		return {"ok": false, "party": delve.party.duplicate(), "message": "A party is already below."}
	var party: Array[int] = []
	for raw_id in party_ids:
		var merc_id := int(raw_id)
		if merc_id <= 0 or party.has(merc_id):
			continue
		if not roster.is_alive(merc_id) or roster.is_reserve(merc_id):
			return {"ok": false, "party": [],
				"message": "%s cannot go down like that." % roster.name_of(merc_id)}
		party.append(merc_id)
	if party.is_empty():
		return {"ok": false, "party": [], "message": "Choose who goes down."}
	delve.begin(party)
	_notify()
	save_state()
	return {"ok": true, "party": party,
		"message": "%d go down with %d piece(s) in the delve inventory." % [party.size(),
			delve.inventory.pooled_total()]}

## The party climbed out alive: every piece in the delve inventory goes into the
## town stash - except the essence it carried up (`cruor_t1`, Ritual Tallow off the
## Hollow's corpses), which renders into the altar's wallet - and the descent is
## over. Returns `{ok, items: {id: count}, count, value}` - what was brought home.
func extract_delve() -> Dictionary:
	if not delve.active:
		return {"ok": false, "items": {}, "count": 0, "value": 0}
	var items: Dictionary = delve.inventory.pooled_map()
	var count := 0
	var value := 0
	for item_id in items:
		var copies := int(items[item_id])
		var tier := CruorCatalog.tier_from_id(str(item_id))
		if tier >= 0:
			cruor.add(tier, copies)
		else:
			stash.add(str(item_id), copies)
		count += copies
		value += WarbandStash.value_of(str(item_id), cruor.brand_of(str(item_id))) * copies
	delve.inventory.clear()
	delve.finish()
	_notify()
	save_state()
	return {"ok": true, "items": items, "count": count, "value": value}

## The party fell below: everything it carried is the Hollow's. Every member still
## on the books is stripped - both weapon sets, armour, trinkets - and the delve
## inventory, with whatever was taken back off the dead, is emptied.
## Returns `{ok, items: {id: count}, count, value}` - what was lost.
func forfeit_delve() -> Dictionary:
	if not delve.active:
		return {"ok": false, "items": {}, "count": 0, "value": 0}
	var lost: Dictionary = {}
	for merc_id in delve.party:
		for entry in roster.worn_entries(merc_id):
			var item_id := roster.take_worn(merc_id, str(entry.get("slot", "")),
				int(entry.get("set", -1)))
			if not item_id.is_empty():
				lost[item_id] = int(lost.get(item_id, 0)) + 1
	var packed: Dictionary = delve.inventory.pooled_map()
	for item_id in packed:
		lost[item_id] = int(lost.get(item_id, 0)) + int(packed[item_id])
	var count := 0
	var value := 0
	for item_id in lost:
		count += int(lost[item_id])
		value += WarbandStash.value_of(str(item_id), cruor.brand_of(str(item_id))) * int(lost[item_id])
	delve.inventory.clear()
	delve.finish()
	_notify()
	save_state()
	return {"ok": true, "items": lost, "count": count, "value": value}

# --- the party's mode ------------------------------------------------------

## What a guest is told when it reaches for the party's mode: the squad it would
## command runs on the host.
const LENT_PARTY_MESSAGE := "This is the host's warband: only the host sets how the party fights."

## Put the party in `mode`. Returns `{ok, mode, message}`, `mode` being the one the
## party is in afterwards. An unknown mode is refused, and so is a lent warband's:
## the squad that would obey it is the host's. Only a real change is announced.
func set_party_mode(mode: String) -> Dictionary:
	if lent:
		return {"ok": false, "mode": party_mode, "message": LENT_PARTY_MESSAGE}
	if not Contracts.PARTY_MODES.has(mode):
		return {"ok": false, "mode": party_mode,
			"message": "The party has no %s mode." % mode.to_upper()}
	if mode != party_mode:
		party_mode = mode
		_notify()
	return {"ok": true, "mode": party_mode, "message": "The party is %s." % mode.to_upper()}

## Step the party to the next mode in `Contracts.PARTY_MODES` order - OFFENSIVE,
## DEFENSIVE, PASSIVE, and round again - which is what the world's `B` key does.
## The same answer and the same refusals as `set_party_mode`.
func cycle_party_mode() -> Dictionary:
	var index := Contracts.PARTY_MODES.find(party_mode)
	return set_party_mode(Contracts.PARTY_MODES[(index + 1) % Contracts.PARTY_MODES.size()])

# --- a party member's disposition ------------------------------------------

## What a guest is told when it reaches for a body's disposition: the squad it
## would command runs on the host.
const LENT_DISPOSITION_MESSAGE := "This is the host's warband: only the host says how its bodies fight."

## Give one mercenary a disposition (`Contracts.DISPOSITIONS`). The party's mode
## says which fights the squad takes; this says how this body takes them, and it
## is per record - saved with the roster and lent with it, so a guest reads the
## host's band. Returns `{ok, disposition, message}` with the body's disposition
## afterwards: an unknown word is refused, and so is a lent warband's, because the
## squad that would obey it is the host's. Only a real change is announced.
##
## A real change can leave a piece in a hand the new stance never carries - the
## band dressed a body as a melee body with the greatsword, and the player has
## just made it the front line. Those pieces go back into the pool and the hands
## are filled again by the same choice an arming pass makes
## (`_release_refused_hands`), so a TANK reads as a shield and a one-hander the
## moment the chip is pressed. A blade a bowman carries is not refused (the bow's
## trade falls back on it), and a piece the player lays in by hand after the
## change is theirs - this runs on the change itself.
func set_disposition(merc_id: int, disposition: String) -> Dictionary:
	var now := roster.disposition_of(merc_id) if roster.has(merc_id) else Contracts.DEFAULT_DISPOSITION
	if lent:
		return _lent_refusal({"disposition": now, "message": LENT_DISPOSITION_MESSAGE})
	if not roster.has(merc_id):
		return {"ok": false, "disposition": now, "message": "No such mercenary."}
	var wanted := Contracts.disposition_exact(disposition)
	if wanted.is_empty():
		return {"ok": false, "disposition": now,
			"message": "%s is not a disposition." % str(disposition).to_upper()}
	roster.set_disposition(merc_id, wanted)
	if wanted != now:
		var refitted := _release_refused_hands(merc_id, wanted)
		_notify()
		if not refitted.is_empty():
			armed.emit([merc_id])
	return {"ok": true, "disposition": wanted,
		"message": "%s fights as %s." % [roster.name_of(merc_id),
			Contracts.disposition_label(wanted)]}

## Take the pieces the new stance refuses out of a body's hands and fill those
## hands again from the pool. A weight would only make a greatsword expensive; a
## refusal is what the arming enforces, and a body that becomes a tank while
## holding one would carry it to the field with the shield it costs already in
## the stash. Only refused pieces move - a bowman's blade is not refused - and
## nothing moves for a body that is down, below with the party, or in a lent
## warband. Answers the ids that went back into the pool.
func _release_refused_hands(merc_id: int, disposition: String) -> Array[String]:
	var released: Array[String] = []
	if lent or not roster.is_alive(merc_id):
		return released
	if delve.active and not delve.party.has(merc_id):
		return released
	for slot_id in ["main", "off"]:
		var item_id := str(roster.equipped_of(merc_id).get(slot_id, ""))
		if item_id.is_empty() or EquipmentRules.bare_garment(item_id):
			continue
		var item: Dictionary = State.ITEMS.get(item_id, {})
		if item.is_empty() or not Contracts.disposition_refuses_gear(disposition, item):
			continue
		if roster.unequip(merc_id, slot_id).is_empty():
			continue
		field_stash().add(item_id, 1)
		released.append(item_id)
	if not released.is_empty():
		_fill_slots(merc_id, ["main", "off"])
	return released

## Step one body to the next disposition in `Contracts.DISPOSITIONS` order -
## what a press on the roster's chip does. TANK, MELEE, BOW and round again.
func cycle_disposition(merc_id: int) -> Dictionary:
	return set_disposition(merc_id, Contracts.next_disposition(roster.disposition_of(merc_id)))

# --- possession bookkeeping ------------------------------------------------

## Mirror a router decision into the persistent map.
func note_possession(peer_id: int, merc_id: int) -> void:
	if merc_id <= 0:
		possession.erase(peer_id)
	else:
		possession[peer_id] = merc_id
	_notify()

func possessed_by(peer_id: int) -> int:
	return int(possession.get(peer_id, -1))

func possessed_ids() -> Dictionary:
	return possession.duplicate()

func clear_possession() -> void:
	possession.clear()
	revive_channels.clear()
	souls.clear()
	_notify()

# --- reset -----------------------------------------------------------------

func reset_state(cap: int = Contracts.MAX_DEPLOYMENT_CAP) -> void:
	# A reset is a fresh warband of this machine's own, never a host's.
	lent = false
	_lent_gold = 0
	_arming = false
	roster.clear()
	stash.clear()
	auto_equip_restricted.clear()
	cruor.clear()
	annoints.clear()
	worn_copies.clear()
	souls.clear()
	quests.reset()
	deployment_cap = maxi(1, cap)
	seeded = false
	possession.clear()
	revive_channels.clear()
	checkpoint.clear()
	delve.clear()
	party_mode = Contracts.DEFAULT_PARTY_MODE
	_notify()

func _notify() -> void:
	changed.emit()

# --- persistence -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"deployment_cap": deployment_cap,
		"roster": roster.to_dict(),
		"stash": stash.to_dict(),
		"cruor": cruor.to_dict(),
		"annoints": annoints.to_dict(),
		"worn_copies": worn_copies.duplicate(true),
		"checkpoint": checkpoint.duplicate(true),
		"quests": quests.to_dict(),
		"delve": delve.to_dict(),
		"party_mode": party_mode,
		"auto_equip_restricted": restricted_ids(),
	}

func from_dict(data: Dictionary) -> void:
	roster.from_dict(data.get("roster", {}))
	stash.from_dict(data.get("stash", {}))
	# v12 adds per-copy annointments; a v11 file has none and every piece is
	# plain steel, which is exactly what an unannointed warband is.
	annoints.from_dict(data.get("annoints", {}))
	worn_copies.clear()
	var saved_copies: Variant = data.get("worn_copies", {})
	if saved_copies is Dictionary:
		for key in saved_copies:
			var held: Variant = saved_copies[key]
			if held is Dictionary:
				worn_copies[str(key)] = {"item": str((held as Dictionary).get("item", "")),
					"ordinal": int((held as Dictionary).get("ordinal", 0))}
	# The holds are item ids, not rows in a pool, so they outlive a copy moving
	# between the stash, a body and the delve inventory. A v9 file has none.
	auto_equip_restricted.clear()
	var holds: Variant = data.get("auto_equip_restricted", [])
	if holds is Array:
		for raw_id in holds:
			var held_id := State.migrate_item_id(str(raw_id))
			if not held_id.is_empty() and State.ITEMS.has(held_id):
				auto_equip_restricted[held_id] = true
	cruor.from_dict(data.get("cruor", {}))
	# Read before the dead are reaped below: a member still on the books of a party
	# below is reaped into the delve inventory, which the load's fall then loses,
	# never into the stash. A v7 file has no delve at all.
	delve.from_dict(data.get("delve", {}))
	deployment_cap = clampi(int(data.get("deployment_cap", Contracts.MAX_DEPLOYMENT_CAP)),
		1, Contracts.MAX_DEPLOYMENT_CAP)
	# A v3 file has no checkpoint: it resumes at the town, which is what every
	# save written before autosave existed meant.
	checkpoint = sanitise_checkpoint(data.get("checkpoint", {}))
	# A v4 file has no ledger: it opens with no orders, which is exactly the
	# quartermaster's slate before he speaks.
	quests.from_dict(QuestScript.sanitise(data.get("quests", {})))
	# A v8 file has no party mode: the squad fights offensive, as it always did,
	# and so does a mode this build has never heard of.
	var mode := str(data.get("party_mode", Contracts.DEFAULT_PARTY_MODE))
	party_mode = mode if Contracts.PARTY_MODES.has(mode) else Contracts.DEFAULT_PARTY_MODE
	# A file written before the dead left the books still carries their records.
	# They leave now, and whatever they wore joins the stash that was just read:
	# opening an old warband must free the hire cap, not inherit a graveyard.
	reap_dead()
	# The field fits the cap on every load. A lent copy is the host's books as the
	# host keeps them, never rebalanced here, so both machines field one squad.
	if not lent:
		_balance_field()
	# Nothing is ever paid here: the purse and the essence wallet already hold
	# what a run earned, so a save/load cycle cannot pay one twice.
	seeded = roster.count() > 0
	_notify()

## `GameFlow.goto()` and every scene's `_exit_tree()` call this, so the file is
## written with the roster as the world last mirrored it.
func save_state() -> void:
	# A lent warband is the host's: writing it here would put somebody else's
	# campaign over this machine's own save.
	if lent:
		return
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("Warband: cannot write %s" % save_path)
		return
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()

func load_state() -> bool:
	# Reading this machine's file into a lent warband would swap the host's
	# campaign for the guest's in the middle of a session.
	if lent:
		return false
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Warband: %s is not a saved warband" % save_path)
		return false
	if int(parsed.get("version", 0)) > SAVE_VERSION:
		push_warning("Warband: %s is from a newer build" % save_path)
		return false
	from_dict(parsed)
	# A party still below in the file never climbed out: the game was left while
	# it was down there (a quit, an exit, a crash). That is a fall, not a pause -
	# otherwise leaving the game would be the way to keep what a fall costs.
	if delve.active:
		forfeit_delve()
	return true

## What a warband file holds, read without adopting it: `{exists, roster,
## checkpoint}`. The title says what HOST GAME's checkpoint door would open with
## this, and must not load a save into the live warband just to describe one.
static func peek_save(path: String) -> Dictionary:
	var out := {"exists": false, "roster": 0, "checkpoint": {}}
	if path.is_empty() or not FileAccess.file_exists(path):
		return out
	out["exists"] = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return out
	var roster_data: Variant = (parsed as Dictionary).get("roster", {})
	if roster_data is Dictionary and (roster_data as Dictionary).get("mercenaries", []) is Array:
		out["roster"] = ((roster_data as Dictionary)["mercenaries"] as Array).size()
	out["checkpoint"] = sanitise_checkpoint((parsed as Dictionary).get("checkpoint", {}))
	return out

# --- checkpoints (the autosave bookmark) ------------------------------------
#
# A checkpoint is the campaign's own memory of "how far we got", written at the
# moments that begin a new stretch: the camp's six watchers down with the squad
# on the road (`trail_start`), and the town square entered (`town`). It rides in
# the same `warband_state.json` as everything else, so one file is one truthful
# picture - a wiped run loads the roster, stash and essence as they stood there
# and puts the warband back on that ground. A v3 file has no checkpoint and
# resumes at the town, exactly as it did before.

func has_checkpoint() -> bool:
	return not checkpoint.is_empty()

func checkpoint_id() -> String:
	return str(checkpoint.get("id", ""))

## `"trail"` or `"town"`, or `""` when there is no bookmark.
func checkpoint_area() -> String:
	return str(checkpoint.get("area", ""))

func checkpoint_label() -> String:
	return str(checkpoint.get("label", ""))

## The ground the bookmark was taken on. Zero when there is none; callers that
## need a standable point snap it to the terrain.
func checkpoint_position() -> Vector3:
	return checkpoint_vector(checkpoint)

## The moment the bookmark was taken, as a unix stamp.
func checkpoint_at() -> int:
	return int(checkpoint.get("at", 0))

## Write a checkpoint and the whole warband with it. The warband is saved at the
## same time on purpose: a bookmark that points at a state the file has never
## held is a lie the reload cannot honour. Returns the stored record.
func save_checkpoint(id: String, area: String, position: Vector3, label: String = "") -> Dictionary:
	var wanted_id := id.strip_edges()
	var wanted_area := area if CHECKPOINT_AREAS.has(area) else "town"
	if wanted_id.is_empty():
		wanted_id = wanted_area
	checkpoint = {
		"id": wanted_id,
		"area": wanted_area,
		"position": [position.x, position.y, position.z],
		"label": label,
		"at": int(Time.get_unix_time_from_system()),
	}
	save_state()
	_notify()
	return checkpoint.duplicate(true)

func clear_checkpoint() -> void:
	if checkpoint.is_empty():
		return
	checkpoint.clear()
	_notify()

## How many bodies the bookmark can put on the field. A checkpoint whose whole
## squad is dead is not a checkpoint: the wipe path must not loop on it.
func checkpoint_standing() -> int:
	var count := 0
	for merc_id in roster.ids():
		if roster.state_of(merc_id) != Contracts.HealthState.DEAD:
			count += 1
	return count

## The same check a reader gets out of the file: malformed data is dropped, never
## half-read. Static because a save's checkpoint is untrusted input.
static func sanitise_checkpoint(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var record: Dictionary = data
	var id := str(record.get("id", "")).strip_edges()
	var area := str(record.get("area", ""))
	if id.is_empty() or not CHECKPOINT_AREAS.has(area):
		return {}
	if not is_standable(record.get("position", null)):
		return {}
	var point := checkpoint_vector(record)
	return {
		"id": id,
		"area": area,
		"position": [point.x, point.y, point.z],
		"label": str(record.get("label", "")),
		"at": int(record.get("at", 0)),
	}

## A checkpoint's position, read from a record or from the live field.
static func checkpoint_vector(record: Dictionary) -> Vector3:
	var value: Variant = record.get("position", [])
	if not (value is Array) or (value as Array).size() != 3:
		return Vector3.ZERO
	var values: Array = value
	for index in 3:
		if typeof(values[index]) not in [TYPE_INT, TYPE_FLOAT]:
			return Vector3.ZERO
	var point := Vector3(float(values[0]), float(values[1]), float(values[2]))
	return point if point.is_finite() else Vector3.ZERO

static func is_standable(value: Variant) -> bool:
	if not (value is Array) or (value as Array).size() != 3:
		return false
	for entry in value as Array:
		if typeof(entry) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		if not is_finite(float(entry)):
			return false
	return true

## One line for the log card and for tests.
func describe() -> String:
	return "mercs=%d alive=%d cap=%d gold=%d cruor=%d brands=%d stash=%d checkpoint=%s" % [
		roster.count(), roster.alive_count(), deployment_cap,
		gold(), cruor.total(), cruor.brands.size(), stash.pooled_total(),
		checkpoint_id() if has_checkpoint() else "-"]
