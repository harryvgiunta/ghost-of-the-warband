class_name WarbandVendor
extends RefCounted
## The Gold Mercenary Recruiter. Every mercenary is identical at base stats, so
## the only thing being bought is a body: the price rises with the size of the
## warband and the roster can never exceed the deployment cap.
##
## Gold is the `PlayerState` purse, frozen by `Wallet` so this class stays pure
## and testable: pass anything with a `credits` property and `add_credits(int)`.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

const HIRE_BASE_COST := 120
## Each mercenary already on the books makes the next one dearer, so a wipe
## costs more than a top-up and the early loop stays affordable.
const HIRE_STEP_COST := 35

## Names the recruiter cycles through, so a fresh warband reads as people.
const NAMES := [
	"Aldous", "Brine", "Cael", "Dorn", "Edda", "Fenwick", "Grist", "Hale",
	"Ilsa", "Jory", "Kestrel", "Lorn", "Maud", "Nev", "Orla", "Pike",
	"Quill", "Rask", "Sable", "Thorn", "Ulric", "Vane", "Wren", "Ysolde",
]

## The price of the next body, given how many are already standing.
static func hire_cost(roster) -> int:
	var count: int = roster.count() if roster != null else 0
	return HIRE_BASE_COST + HIRE_STEP_COST * count

## A replacement costs the same as a hire while the warband is under the cap.
static func replacement_cost(roster) -> int:
	return hire_cost(roster)

static func next_name(roster) -> String:
	var used: Dictionary = {}
	if roster != null:
		for merc in roster.records():
			used[str(merc.get("name", "")).to_lower()] = true
	for candidate in NAMES:
		if not used.has(candidate.to_lower()):
			return candidate
	return "Mercenary %d" % (roster.count() + 1 if roster != null else 1)

## Hire one body. `wallet` needs `credits` and `add_credits(int)`.
## Returns `{ok, message, merc_id, cost}`.
static func hire(roster, wallet, merc_name: String = "", cap: int = Contracts.MAX_DEPLOYMENT_CAP) -> Dictionary:
	if roster == null:
		return {"ok": false, "message": "No warband to hire into.", "merc_id": -1, "cost": 0}
	if roster.count() >= maxi(0, cap):
		return {"ok": false, "message": "The warband already fields %d. No more can be sworn." % cap,
			"merc_id": -1, "cost": 0}
	var cost := hire_cost(roster)
	if wallet == null:
		return {"ok": false, "message": "The purse is missing.", "merc_id": -1, "cost": cost}
	if int(wallet.credits) < cost:
		return {"ok": false, "message": "You need %d gold; you have %d." % [cost, int(wallet.credits)],
			"merc_id": -1, "cost": cost}
	var chosen := merc_name.strip_edges()
	if chosen.is_empty():
		chosen = next_name(roster)
	wallet.add_credits(-cost)
	var merc_id: int = roster.create(chosen)
	return {"ok": true, "merc_id": merc_id, "cost": cost,
		"message": "%s swears to the warband for %d gold." % [chosen, cost]}

## The recruiter's board: three fresh names and their price.
static func board(roster, wallet) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var cost := hire_cost(roster)
	var remaining := int(wallet.credits) if wallet != null else 0
	var names := NAMES.duplicate()
	var start: int = roster.count() if roster != null else 0
	for index in 3:
		var peer_name := str(names[(start + index) % names.size()])
		rows.append({"name": peer_name, "cost": cost,
			"affordable": remaining >= cost,
			"room": roster != null and roster.count() < Contracts.MAX_DEPLOYMENT_CAP})
	return rows
