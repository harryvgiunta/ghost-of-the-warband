extends SceneTree
## GHOST OF THE WARBAND: the first fight's lesson as a machine.
##
## `duel_lesson.gd` is the one state machine between the player waking in the
## camp and the two watchers falling. The camp drives it with facts - the wake, a
## step onto the blade, the pickup, a windup, a blow on a raised guard - and this
## test fires those facts in order and out of it:
##
##   * nothing advances before the player is awake and free;
##   * each tip is asked for exactly once, and in the order the player meets it;
##   * a windup on the watcher the cuts tip was about does not open the guard tip
##     while its partner is still standing, and does when only one is left;
##   * a block that lands before the guard tip was ever offered does not finish the
##     lesson, because nobody was told what to press;
##   * the pair falling ends it wherever the tips were;
##   * `reset()` starts a fresh campaign at the first beat.
##
## The scene-side wiring (which body is "the second watcher", which tip holds
## which key) is `cage_escape_regression`'s - this is the machine alone, and it
## runs in a second.

const DuelScript = preload("res://scripts/warband/duel_lesson.gd")

var checks := 0
var failures := 0
var tips: Array[int] = []

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
	lesson.tip_wanted.connect(func(slot: int) -> void: tips.append(slot))
	root.add_child(lesson)

	# --- dormant ------------------------------------------------------------
	check(not lesson.active(), "the lesson is inert until the player is awake")
	check(not lesson.fighting(), "and the pair may not wake for it")
	check(lesson.objective().is_empty() and lesson.hint().is_empty(),
		"with nothing to say on the HUD")
	check(not lesson.note_shiv_near(), "a step onto the blade before the wake is not progress")
	check(not lesson.note_shiv_taken(), "and neither is a pickup")
	check(not lesson.note_guarded(), "nor a guard")
	check(tips.is_empty(), "and no tip was asked for (%s)" % str(tips))

	# --- the feet -----------------------------------------------------------
	check(lesson.wake(), "waking in the camp starts the lesson")
	check(lesson.step() == DuelScript.Step.MOVE, "at the feet (%s)" % lesson.step_name())
	check(lesson.active() and not lesson.fighting(),
		"the keys are the lesson's and the pair are still asleep")
	check(tips == [DuelScript.Tip.MOVE], "one walking tip was asked for (%s)" % str(tips))
	check(lesson.hint().contains("W A S D"), "which names walking")
	check(lesson.hint().contains("SHIFT"), "and running")
	check(not lesson.wake(), "a second wake cannot restart it")

	# --- the steel ----------------------------------------------------------
	check(lesson.note_shiv_near(), "standing on the blade asks for the pickup")
	check(lesson.step() == DuelScript.Step.FETCH, "at the steel (%s)" % lesson.step_name())
	check(tips == [DuelScript.Tip.MOVE, DuelScript.Tip.FETCH],
		"the pickup tip follows the walking tip (%s)" % str(tips))
	check(lesson.hint().contains("K"), "and names K")
	check(not lesson.note_shiv_near(), "the pickup tip is asked for once")
	check(not lesson.note_guarded(), "a block before anybody was told does not count")

	# --- the fight ----------------------------------------------------------
	check(lesson.note_shiv_taken(), "a body picking the blade up starts the fight")
	check(lesson.step() == DuelScript.Step.FIGHT and lesson.fighting(),
		"and only now may the pair wake (%s)" % lesson.step_name())
	check(lesson.armed(), "the lesson knows the player is armed")
	check(lesson.cuts_tip(), "the pickup itself asks for the cuts tip")
	check(tips.size() == 3 and tips[2] == DuelScript.Tip.SWING,
		"the cuts tip is the third one asked for (%s)" % str(tips))
	check(lesson.hint().contains("LMB"), "which names the cut")
	check(lesson.hint().contains("WHEEL_UP") and lesson.hint().contains("WHEEL_DOWN"),
		"and both wheel swings (%s)" % lesson.hint())
	check(not lesson.note_shiv_taken(), "the cuts tip is asked for once")

	# --- the guard ----------------------------------------------------------
	check(not lesson.note_windup(77, 2),
		"the first watcher to wind up does not teach the guard while its partner stands")
	check(not lesson.guard_tip(), "so no guard tip was asked for")
	check(lesson.note_windup(88, 2), "the second watcher's windup does")
	check(lesson.guard_tip(), "and the guard tip is up")
	check(tips.size() == 4 and tips[3] == DuelScript.Tip.GUARD,
		"it is the fourth tip asked for (%s)" % str(tips))
	check(lesson.hint().contains("RMB"), "which names the guard key")
	check(lesson.hint().to_lower().contains("hold"), "and says it is held (%s)" % lesson.hint())
	check(not lesson.note_windup(88, 2), "the guard tip is asked for once")
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
	last.tip_wanted.connect(func(slot: int) -> void: tips.append(slot))
	root.add_child(last)
	last.wake()
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
	carried.wake()
	check(carried.note_shiv_taken(),
		"a body that already holds a blade skips the pickup beat")
	check(carried.step() == DuelScript.Step.FIGHT, "and goes straight to the fight")
	check(carried.cuts_tip(), "with the cuts tip raised on that same frame")

	# --- the copy ----------------------------------------------------------
	# Nothing in this lesson is a paragraph: every line it says is a command, and
	# every one of them is short enough to read over a fight.
	var lines: Array[String] = []
	var probe := DuelScript.new()
	root.add_child(probe)
	probe.wake()
	lines.append(probe.objective())
	lines.append(probe.hint())
	probe.note_shiv_near()
	lines.append(probe.objective())
	lines.append(probe.hint())
	probe.note_shiv_taken()
	lines.append(probe.objective())
	lines.append(probe.hint())
	check(probe.note_windup(5, 1), "the guard beat can be probed on one watcher")
	lines.append(probe.objective())
	lines.append(probe.hint())
	for line in lines:
		check(not line.contains("\n"), "no lesson line is more than one line (%s)" % line)
		check(line.length() <= 84, "every lesson line fits one read (%d: %s)" % [line.length(), line])
		check(not line.ends_with("."), "commands are not sentences (%s)" % line)

	# --- reset -------------------------------------------------------------
	lesson.reset()
	check(lesson.step() == DuelScript.Step.DORMANT and not lesson.fighting(),
		"reset puts the lesson back on the first beat")
	check(not lesson.cuts_tip() and not lesson.guard_tip() and not lesson.guarded(),
		"and forgets every tip the player had already seen")
	check(lesson.wake(), "a fresh campaign starts it again")

	_finish()


func _finish() -> void:
	print("DUEL_LESSON_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
