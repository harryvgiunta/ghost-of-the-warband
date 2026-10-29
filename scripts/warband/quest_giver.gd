class_name QuestGiver
extends Node
## GHOST OF THE WARBAND: the keeper who talks.
##
## The town has two of them and both are the same object here, because the
## difference between them is a table row, not a class:
##
## * **The recruiter** owns the hire lesson. G at his counter raises the card
##   that explains the oath, the warband screen and the free first eight; after
##   that the counter opens the hire board as it always did.
## * **The quartermaster** owns the campaign. G at his counter hands an order
##   over, takes a finished one back, explains the ichor, and otherwise gets out
##   of the way so his shop can open.
##
## The gold arrow over a head is decided here too (`marker_service`), because it
## is the same question the cards answer: who has something to say right now. The
## rule is one line of the campaign's shape - the recruiter has business while
## the band is short of the cap, the quartermaster has business whenever an order
## is waiting, and whichever is true first wears the arrow.
##
## Nothing here reads a scene: the owner hands in the warband, the HUD and the
## tutorial card, and calls `talk()` from its one `G` handler. A standalone town
## preview passes no card and this node builds its own, so the square is playable
## in its own scene exactly as it is inside the world.

const CardScript = preload("res://scripts/warband/tutorial_card.gd")
const QuestsScript = preload("res://scripts/warband/quest_log.gd")

## The two keepers this node speaks for, by the service ids the town resolves.
const GIVER := "quartermaster"
const RECRUITER := "recruiter"

## Card ids. A card is shown once per step id, which is what makes "has he
## taught me this yet" a question about the card and not about a save field.
const HIRE_LESSON := "recruiter_hire"
const BENCH_LESSON := "ichor_bench"

## `talk()` cues for the voice library, so a keeper's line rides the same path as
## every other cue in the square.
signal spoke(service: String, cue: String)
signal quest_accepted(quest_id: String)
signal quest_finished(quest_id: String)

var warband = null
var quests: WarbandQuests = null
var hud = null
var card = null
## True when this node made the card itself and must free it with itself.
var _own_card := false


func configure(warband_in, hud_in = null, card_in = null) -> void:
	warband = warband_in
	quests = warband.quests if warband != null else null
	hud = hud_in
	if card_in != null:
		card = card_in
	elif card == null:
		card = CardScript.new()
		card.name = "QuestCard"
		add_child(card)
		_own_card = true


# --- who has business ------------------------------------------------------

## The service that should wear the gold arrow right now, or "".
func marker_service() -> String:
	if warband == null or quests == null:
		return ""
	refresh_offers()
	if _quartermaster_business():
		return GIVER
	if _recruiter_business():
		return RECRUITER
	return ""


## Whether one keeper has something to say: an order on the table, one waiting to
## be turned in, a lesson not yet read, or a recruit still to swear.
func business(service: String) -> bool:
	if warband == null or quests == null:
		return false
	refresh_offers()
	match service:
		GIVER:
			return _quartermaster_business()
		RECRUITER:
			return _recruiter_business()
	return false


func _recruiter_business() -> bool:
	if card != null and not card.has_shown(HIRE_LESSON):
		return true
	return _can_hire()

func _can_hire() -> bool:
	if warband == null:
		return false
	return warband.roster.count() < maxi(1, warband.deployment_cap)

func _quartermaster_business() -> bool:
	if quests == null:
		return false
	if not quests.offerable(GIVER).is_empty():
		return true
	if not quests.completed_ids(GIVER).is_empty():
		return true
	if _ichor_unexplained():
		return true
	return false

## The vial is in the stash and the lesson that says what to do with it has not
## been read.
func _ichor_unexplained() -> bool:
	if warband == null:
		return false
	if card != null and card.has_shown(BENCH_LESSON):
		return false
	return warband.stash.pooled_count(QuestsScript.ICHOR_ID) > 0


# --- the orders ------------------------------------------------------------

## Put every order the campaign has earned on the table. Called before a marker
## or a talk is answered, so a band that comes back with the count made finds the
## next order already waiting.
##
## The chain: the recruiter fills the band (eight bodies, the deployment cap),
## then the cages, then the watchers, then the Crypt. The ichor is the one order
## that does not wait on the chain - it appears the moment the band is holding a
## vial, which is what "something that drops from one of the watchers" means.
## Returns the ids opened this call.
func refresh_offers() -> Array[String]:
	var opened: Array[String] = []
	if warband == null or quests == null:
		return opened
	if _can_hire_full() and quests.state_of("free_the_soldiers") == QuestsScript.State.HIDDEN:
		if quests.offer("free_the_soldiers"):
			opened.append("free_the_soldiers")
	if quests.state_of("free_the_soldiers") == QuestsScript.State.CLOSED \
			and quests.state_of("cull_the_watchers") == QuestsScript.State.HIDDEN:
		if quests.offer("cull_the_watchers"):
			opened.append("cull_the_watchers")
	if quests.state_of("cull_the_watchers") == QuestsScript.State.CLOSED \
			and quests.state_of("find_the_crypt") == QuestsScript.State.HIDDEN:
		if quests.offer("find_the_crypt"):
			opened.append("find_the_crypt")
	if warband.stash.pooled_count(QuestsScript.ICHOR_ID) > 0 \
			and quests.state_of("bind_the_ichor") == QuestsScript.State.HIDDEN:
		if quests.offer("bind_the_ichor"):
			opened.append("bind_the_ichor")
	return opened

## The band is at the cap: the recruiter has nothing left to sell and the
## quartermaster starts handing out the campaign.
func _can_hire_full() -> bool:
	if warband == null:
		return false
	return warband.roster.count() >= maxi(1, warband.deployment_cap)


# --- talking ---------------------------------------------------------------

## The one talk handler. Returns true when this node answered the press (a card
## went up); false means "not mine", and the caller opens the keeper's own board
## (`warband_screen` for the recruiter's hire rows, `quartermaster` for the shop).
func talk(service: String, _peer_id: int = 1) -> bool:
	if warband == null or quests == null:
		return false
	refresh_offers()
	match service:
		RECRUITER:
			return _talk_recruiter()
		GIVER:
			return _talk_quartermaster()
	return false


func _talk_recruiter() -> bool:
	if card == null or card.has_shown(HIRE_LESSON):
		return false
	var shown: bool = card.show_step(HIRE_LESSON, "THE RECRUITER", "EIGHT OATHS, NO GOLD",
		"Every mercenary in the band is the same body: a hundred health, a thousand"
			+ " stamina, and whatever steel it can hold. Stats never change - the kit"
			+ " does.\n\nOpen the warband screen. The recruiter board has a HIRE row"
			+ " for each open place. The first eight oaths cost nothing, and every"
			+ " fresh body arms itself out of the shared stash before it takes the"
			+ " field.",
		"O  -  THE WARBAND SCREEN   ·   HIRE  -  THE RECRUITER BOARD   ·   G  -  TALK",
		"Eight bodies is the whole deployment cap. Pick who marches at the expedition gate.")
	spoke.emit(RECRUITER, "greet")
	return shown


func _talk_quartermaster() -> bool:
	if card == null:
		return false
	var done := quests.completed_ids(GIVER)
	if not done.is_empty():
		return _turn_in(str(done[0]))
	var offers := quests.offerable(GIVER)
	if not offers.is_empty():
		return _offer(str(offers[0]))
	if _ichor_unexplained():
		return _teach_bench()
	return false


func _turn_in(quest_id: String) -> bool:
	var result := quests.turn_in(quest_id)
	var row := QuestsScript.def_of(quest_id)
	var next_id := str(result.get("next", ""))
	var footnote := ""
	if not next_id.is_empty():
		quests.accept(next_id)
		footnote = "NEXT: %s" % str(QuestsScript.def_of(next_id).get("title", next_id))
		quest_accepted.emit(next_id)
	spoke.emit(GIVER, "done")
	quest_finished.emit(quest_id)
	return card.show_step("done_%s" % quest_id, str(row.get("kicker", "THE QUARTERMASTER")),
		str(row.get("title", quest_id)), str(row.get("done", "")),
		"G  -  TALK   ·   M  -  THE MAP", footnote)


func _offer(quest_id: String) -> bool:
	var result := quests.accept(quest_id)
	if not bool(result.get("ok", false)):
		return false
	var row := QuestsScript.def_of(quest_id)
	quest_accepted.emit(quest_id)
	spoke.emit(GIVER, "greet")
	return card.show_step("offer_%s" % quest_id, str(row.get("kicker", "THE QUARTERMASTER")),
		str(row.get("title", quest_id)), str(row.get("body", "")),
		str(row.get("keys", "G  -  TALK")), "ACCEPTED  -  the objective is on the ledger.")


func _teach_bench() -> bool:
	spoke.emit(GIVER, "greet")
	return card.show_step(BENCH_LESSON, "THE QUARTERMASTER", "ICHOR TAKES TO STEEL",
		"You are carrying a watcher's ichor. It is not a relic and it is not worth"
			+ " gold to a keeper - it is a reagent, and the bench at my side is where"
			+ " it is worked.\n\nStand at the bench and press G. Take a spare weapon"
			+ " out of the shared stash, lay the vial to it, and the piece comes back"
			+ " with a sigil bound into it. Press R to loose it. One vial, one blade.",
		"G  -  THE ICHOR BENCH   ·   R  -  LOOSE THE SIGIL",
		"The weapon keeps its sigil for good. It rides the piece, not the body.")


## Whether the ledger has anything to put on the screen. The HUD is written by
## the scene, so this is only a question, never a paint.
func has_orders() -> bool:
	return quests != null and not quests.tracked().is_empty()
