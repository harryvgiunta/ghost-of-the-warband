class_name QuestGiver
extends Node
## GHOST OF THE WARBAND: the keeper who talks.
##
## The town has two of them and both are the same object here, because the
## difference between them is a table row, not a class:
##
## * **The recruiter** owns the hire lesson. G at his counter tips the one line
##   that says where the hire rows are; after that the counter opens the hire
##   board as it always did.
## * **The quartermaster** owns the campaign. G at his counter hands an order
##   over, takes a finished one back, names the bench for the ichor, and otherwise
##   gets out of the way so his shop can open.
##
## The gold arrow over a head is decided here too (`marker_service`), because it
## is the same question the tips answer: who has something to say right now. The
## rule is one line of the campaign's shape - the recruiter has business while
## the band is short of the cap, the quartermaster has business whenever an order
## is waiting, and whichever is true first wears the arrow.
##
## Nothing here reads a scene: the owner hands in the warband, the HUD and the tip
## channel, and calls `talk()` from its one `G` handler. A standalone town preview
## passes no tips and this node builds its own, so the square is playable in its
## own scene exactly as it is inside the world. Nothing here writes a paragraph:
## an order's title, its key line and its ledger row are the whole of it.

const TipsScript = preload("res://scripts/warband/warband_tips.gd")
const QuestsScript = preload("res://scripts/warband/quest_log.gd")

## The two keepers this node speaks for, by the service ids the town resolves.
const GIVER := "quartermaster"
const RECRUITER := "recruiter"

## Tip ids. A tip is offered once per id, which is what makes "has he taught me
## this yet" a question about the channel and not about a save field.
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
var tips = null
## True when this node made the tip channel itself and must free it with itself.
var _own_tips := false


func configure(warband_in, hud_in = null, tips_in = null) -> void:
	warband = warband_in
	quests = warband.quests if warband != null else null
	hud = hud_in
	if tips_in != null:
		tips = tips_in
	elif tips == null:
		tips = TipsScript.new()
		tips.name = "QuestTips"
		add_child(tips)
		_own_tips = true


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
	if tips != null and not tips.has_shown(HIRE_LESSON):
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

## The vial is in the stash and the line that says what to do with it has not
## been offered.
func _ichor_unexplained() -> bool:
	if warband == null:
		return false
	if tips != null and tips.has_shown(BENCH_LESSON):
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

## The one talk handler. The keeper says his line as a tip on the way in and hands
## the press on, so the counter always opens on the same G: a player is never made
## to press twice to get at the board the line is about. Returns true only when a
## keeper keeps the press for himself, which none of them does today.
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
	if tips != null and not tips.has_shown(HIRE_LESSON):
		tips.tip(HIRE_LESSON, "O", "THE WARBAND SCREEN HIRES")
	spoke.emit(RECRUITER, "greet")
	return false


func _talk_quartermaster() -> bool:
	if tips == null:
		return false
	var done := quests.completed_ids(GIVER)
	if not done.is_empty():
		_turn_in(str(done[0]))
		return false
	var offers := quests.offerable(GIVER)
	if not offers.is_empty():
		_offer(str(offers[0]))
		return false
	if _ichor_unexplained():
		_teach_bench()
	return false


func _turn_in(quest_id: String) -> void:
	var result := quests.turn_in(quest_id)
	var row := QuestsScript.def_of(quest_id)
	var next_id := str(result.get("next", ""))
	if not next_id.is_empty():
		quests.accept(next_id)
	spoke.emit(GIVER, "done")
	quest_finished.emit(quest_id)
	tips.tip("done_%s" % quest_id, "G", "ORDER DONE: %s" % str(row.get("title", quest_id)))


func _offer(quest_id: String) -> void:
	var result := quests.accept(quest_id)
	if not bool(result.get("ok", false)):
		return
	var row := QuestsScript.def_of(quest_id)
	quest_accepted.emit(quest_id)
	spoke.emit(GIVER, "greet")
	tips.tip("offer_%s" % quest_id, "M", "ORDER: %s" % str(row.get("title", quest_id)))


func _teach_bench() -> void:
	spoke.emit(GIVER, "greet")
	tips.tip(BENCH_LESSON, "G", "BIND THE ICHOR AT THE BENCH")


## Whether the ledger has anything to put on the screen. The HUD is written by
## the scene, so this is only a question, never a paint.
func has_orders() -> bool:
	return quests != null and not quests.tracked().is_empty()
