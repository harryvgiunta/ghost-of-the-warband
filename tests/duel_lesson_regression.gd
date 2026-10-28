extends SceneTree
## GHOST OF THE WARBAND: the first fight's lesson as a machine.
##
## `duel_lesson.gd` is the one state machine between the soul taking Corvin's
## body and the two watchers falling. The camp drives it with facts - a possession,
## a step onto the shiv, a swing, a windup, a blow on a raised guard - and this
## test fires those facts in order and out of it:
##
##   * nothing advances before the soul is in his body;
##   * each card is asked for exactly once, and in the order the player meets it;
##   * a windup on the watcher the swings card was about does not open the guard
##     card while its partner is still standing, and does when only one is left;
##   * a block that lands before the guard card was ever read does not finish the
##     lesson, because nobody was told what to press;
##   * the pair falling ends it wherever the cards were;
##   * `reset()` starts a fresh campaign at the first beat.
##
## The scene-side wiring (which body is "the second watcher", which card holds
## which key) is `cage_escape_regression`'s - this is the machine alone, and it
## runs in a second.

const DuelScript = preload("res://scripts/warband/duel_lesson.gd")

var checks := 0
var failures := 0
var cards: Array[int] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("DUEL_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var lesson := DuelScript.new()
	lesson.card_wanted.connect(func(slot: int) -> void: cards.append(slot))
	root.add_child(lesson)

	# --- dormant ------------------------------------------------------------
	check(not lesson.active(), "the lesson is inert until a soul steps in")
	check(not lesson.fighting(), "and the pair may not wake for it")
	check(lesson.objective().is_empty() and lesson.hint().is_empty(),
		"with nothing to say on the HUD")
	check(not lesson.note_shiv_near(), "a step onto the shiv before the body is not progress")
	check(not lesson.note_shiv_taken(), "and neither is a pickup")
	check(not lesson.note_guarded(), "nor a guard")
	check(cards.is_empty(), "and no card was asked for (%s)" % str(cards))

	# --- the feet -----------------------------------------------------------
	check(lesson.note_taken(), "stepping into the body starts the lesson")
	check(lesson.step() == DuelScript.Step.MOVE, "at the feet (%s)" % lesson.step_name())
	check(lesson.active() and not lesson.fighting(),
		"the keys are the lesson's and the pair are still asleep")
	check(cards == [DuelScript.Card.MOVE], "one walking card was asked for (%s)" % str(cards))
	check(lesson.hint().contains("W A S D"), "which names walking")
	check(lesson.hint().contains("SHIFT"), "and running")
	check(not lesson.note_taken(), "a second possession cannot restart it")

	# --- the steel ----------------------------------------------------------
	check(lesson.note_shiv_near(), "standing on the shiv asks for the pickup")
	check(lesson.step() == DuelScript.Step.FETCH, "at the steel (%s)" % lesson.step_name())
	check(cards == [DuelScript.Card.MOVE, DuelScript.Card.FETCH],
		"the pickup card follows the walking card (%s)" % str(cards))
	check(lesson.hint().contains("K"), "and names K")
	check(not lesson.note_shiv_near(), "the pickup card is asked for once")
	check(not lesson.note_guarded(), "a block before anybody was told does not count")

	# --- the fight ----------------------------------------------------------
	check(lesson.note_shiv_taken(), "a body picking the shiv up starts the fight")
	check(lesson.step() == DuelScript.Step.FIGHT and lesson.fighting(),
		"and only now may the pair wake (%s)" % lesson.step_name())
	check(lesson.armed(), "the lesson knows the player is armed")
	check(lesson.cuts_card(), "the pickup itself asks for the cuts card")
	check(cards.size() == 3 and cards[2] == DuelScript.Card.SWING,
		"the cuts card is the third one asked for (%s)" % str(cards))
	check(lesson.hint().contains("LMB"), "which names the cut")
	check(lesson.hint().contains("WHEEL_UP") and lesson.hint().contains("WHEEL_DOWN"),
		"and both wheel swings (%s)" % lesson.hint())
	check(lesson.hint().contains("RMB"), "and the guard it can already use")
	check(not lesson.note_shiv_taken(), "the cuts card is asked for once")

	# --- the guard ----------------------------------------------------------
	check(not lesson.note_windup(77, 2),
		"the first watcher to wind up does not teach the guard while its partner stands")
	check(not lesson.guard_card(), "so no guard card was asked for")
	check(lesson.note_windup(88, 2), "the second watcher's windup does")
	check(lesson.guard_card(), "and the guard card is up")
	check(cards.size() == 4 and cards[3] == DuelScript.Card.GUARD,
		"it is the fourth card asked for (%s)" % str(cards))
	check(lesson.hint().contains("RMB"), "which names the guard key")
	check(lesson.hint().to_lower().contains("hold"), "and says it is held (%s)" % lesson.hint())
	check(not lesson.note_windup(88, 2), "the guard card is asked for once")
	check(lesson.note_guarded(), "a blow on the raised guard ends the lesson")
	check(lesson.guarded() and lesson.step() == DuelScript.Step.DONE,
		"the lesson is done (%s)" % lesson.step_name())
	check(not lesson.active() and not lesson.fighting(),
		"and it hands the keys back to the camp")
	check(lesson.objective().is_empty() and lesson.hint().is_empty(),
		"with nothing left to say (%s / %s)" % [lesson.objective(), lesson.hint()])
	check(not lesson.note_guarded(), "a second block is not booked again")

	# --- the last of the pair ----------------------------------------------
	var last := DuelScript.new()
	last.card_wanted.connect(func(slot: int) -> void: cards.append(slot))
	root.add_child(last)
	last.note_taken()
	last.note_shiv_taken()
	check(not last.note_windup(11, 2),
		"the survivor of a full pair waits its turn to teach the guard")
	check(last.note_windup(11, 1),
		"but the last standing watcher teaches it too")
	check(last.note_fight_over(), "the pair falling ends the lesson")
	check(last.step() == DuelScript.Step.DONE, "at the same beat (%s)" % last.step_name())
	check(not last.note_guarded(), "and a later block changes nothing")

	# --- a picked-up body skips the fetch ----------------------------------
	var carried := DuelScript.new()
	root.add_child(carried)
	carried.note_taken()
	check(carried.note_shiv_taken(),
		"a body that already holds a blade skips the pickup beat")
	check(carried.step() == DuelScript.Step.FIGHT, "and goes straight to the fight")
	check(carried.cuts_card(), "with the cuts card raised on that same frame")

	# --- reset -------------------------------------------------------------
	lesson.reset()
	check(lesson.step() == DuelScript.Step.DORMANT and not lesson.fighting(),
		"reset puts the lesson back on the first beat")
	check(not lesson.cuts_card() and not lesson.guard_card() and not lesson.guarded(),
		"and forgets every card the player had already read")
	check(lesson.note_taken(), "a fresh campaign starts it again")

	_finish()


func _finish() -> void:
	print("DUEL_LESSON_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
