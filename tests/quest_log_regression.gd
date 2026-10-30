extends SceneTree
## The campaign ledger: the two reusable order shapes (kill X of a mob, rescue X
## bodies), the chain from the recruiter's oath to the Crypt shell, the ichor's
## own order, the arrow that decides which keeper has something to say, the HUD
## block the objectives are read from, and the save section they ride in.
##
## This is the contract the world's own hooks (`note_kill`, `note_rescue`,
## `note_applied`) are written against, so it is owned by the foundation and not
## by whichever scene asks next.

const QuestsScript = preload("res://scripts/warband/quest_log.gd")
const VendorScript = preload("res://scripts/warband/mercenary_vendor.gd")
const GiverScript = preload("res://scripts/warband/quest_giver.gd")
const HudScript = preload("res://scripts/warband/warband_hud.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")

const WARBAND_SAVE := "user://quest_log_warband.json"

var warband
var checks := 0
var failures := 0
## What `quest_completed` last said, so the signal is proved and not assumed.
var completed_seen: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("QUEST_LOG_FAIL  ", message)

func _initialize() -> void:
	call_deferred("run")

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func run() -> void:
	_remove(WARBAND_SAVE)
	warband = root.get_node("Warband")
	warband.save_path = WARBAND_SAVE
	warband.reset_state()
	warband.gold()  # touches the purse bridge so a missing PlayerState fails here

	var quests: WarbandQuests = warband.quests
	check(quests != null, "the warband owns a ledger")
	check(quests.state_of("free_the_soldiers") == QuestsScript.State.HIDDEN,
		"a new campaign opens with no orders")

	# --- the two shapes the campaign needs are table rows --------------------
	for quest_id: String in QuestsScript.IDS:
		check(quests.has(quest_id), "the ledger knows " + quest_id)
	var kill_row := QuestsScript.def_of("cull_the_watchers")
	check(int(kill_row.get("kind", -1)) == QuestsScript.Goal.KILL, "the watcher order is a kill count")
	check(str(kill_row.get("target", "")) == "hollow_warden", "it counts the hollow warden")
	check(int(kill_row.get("count", 0)) == QuestsScript.WATCHER_KILLS,
		"twenty watchers is the price")
	var rescue_row := QuestsScript.def_of("free_the_soldiers")
	check(int(rescue_row.get("kind", -1)) == QuestsScript.Goal.RESCUE, "the cage order is a rescue count")
	check(int(rescue_row.get("count", 0)) == QuestsScript.SOLDIER_RESCUES,
		"four bodies is the cage line")
	check(int(QuestsScript.def_of("find_the_crypt").get("kind", -1)) == QuestsScript.Goal.REACH,
		"the Crypt is a place, not a count")
	check(str(QuestsScript.def_of("find_the_crypt").get("target", "")) == "crypt",
		"and the place it names is the crypt")

	# --- offer / accept / progress guards -----------------------------------
	quests.quest_completed.connect(func(quest_id: String): completed_seen.append(quest_id))
	check(not quests.accept("cull_the_watchers").get("ok", true),
		"a quest that was never offered cannot be accepted")
	check(quests.offer("cull_the_watchers"), "the order can be put on the table")
	check(not quests.offer("cull_the_watchers"), "and only once")
	check(quests.is_offered("cull_the_watchers"), "it is offered")
	var accepted := quests.accept("cull_the_watchers")
	check(bool(accepted.get("ok", false)), "the order is taken")
	check(quests.is_active("cull_the_watchers"), "and active")
	check(not quests.accept("cull_the_watchers").get("ok", true), "a double tap takes nothing")

	# --- kill counting only counts the named mob ----------------------------
	check(quests.note_kill("briar_wolf").is_empty(), "a wolf is not a watcher")
	check(quests.note_kill("").is_empty(), "a death with no mob id is not a kill")
	quests.note_kill("hollow_warden")
	check(quests.progress_of("cull_the_watchers") == 1, "one watcher is one")
	for index in 18:
		quests.note_kill("hollow_warden")
	check(quests.progress_of("cull_the_watchers") == 19, "nineteen of twenty")
	check(not quests.is_complete("cull_the_watchers"), "not finished yet")
	check(quests.rows().size() >= 1, "the tracker shows the live order")
	check(str(quests.rows()[0]["detail"]) == "19 / 20", "the row carries the count")
	check(quests.objective().contains("19 / 20"), "the objective line carries the count")
	quests.note_kill("hollow_warden")
	check(quests.is_complete("cull_the_watchers"), "the twentieth finishes it")
	check(completed_seen.has("cull_the_watchers"), "the completion signal fired")
	check(quests.progress_of("cull_the_watchers") == 20, "the count stops at the goal")
	check(quests.note_kill("hollow_warden").is_empty(), "a finished order ignores more kills")
	check(quests.progress_of("cull_the_watchers") == 20, "and cannot overrun")

	# --- turn-in hands over the next row ------------------------------------
	var turned := quests.turn_in("cull_the_watchers")
	check(bool(turned.get("ok", false)), "a finished order is turned in")
	check(quests.is_closed("cull_the_watchers"), "and closed")
	check(str(turned.get("next", "")) == "find_the_crypt", "the chain names the Crypt")
	check(quests.is_offered("find_the_crypt"), "the Crypt order is on the table")
	check(not quests.turn_in("free_the_soldiers").get("ok", true),
		"an unfinished order cannot be turned in")

	# The Crypt is a shell: accepting it starts it, and nothing in the game can
	# finish it yet. It must stay active and count as tracked.
	quests.accept("find_the_crypt")
	check(quests.is_active("find_the_crypt"), "the Crypt order is active")
	check(str(quests.rows()[0]["detail"]) == "NOT FOUND", "and reads as unfound")
	check(quests.note_reached("shrine").is_empty(), "another place does not complete it")
	check(quests.is_active("find_the_crypt"), "the shell stays open")

	# --- rescue counting ----------------------------------------------------
	warband.quests.reset()
	quests.offer("free_the_soldiers")
	quests.accept("free_the_soldiers")
	quests.note_rescue(3)
	check(quests.progress_of("free_the_soldiers") == 3, "three soldiers out of the wood")
	check(not quests.is_complete("free_the_soldiers"), "one cage left")
	quests.note_rescue()
	check(quests.is_complete("free_the_soldiers"), "the fourth frees the line")
	check(quests.note_rescue().is_empty(), "a fifth soldier changes nothing")

	# --- the ichor is an APPLY order, credited once -------------------------
	warband.quests.reset()
	quests.offer("bind_the_ichor")
	quests.accept("bind_the_ichor")
	check(quests.note_applied("wolf_pelt").is_empty(), "a pelt is not a reagent")
	check(quests.note_applied(QuestsScript.ICHOR_ID) == ["bind_the_ichor"],
		"the ichor finishes the order")
	check(quests.is_complete("bind_the_ichor"), "and it is complete")
	check(quests.note_applied(QuestsScript.ICHOR_ID).is_empty(), "one vial credits once")

	# --- persistence --------------------------------------------------------
	warband.quests.reset()
	quests.offer("cull_the_watchers")
	quests.accept("cull_the_watchers")
	for index in 7:
		quests.note_kill("hollow_warden")
	var saved_quests := quests.to_dict()
	check(int(saved_quests.get("version", 0)) == QuestsScript.SAVE_VERSION,
		"the ledger writes its own version")
	var restored := QuestsScript.new()
	restored.from_dict(saved_quests)
	check(restored.is_active("cull_the_watchers"), "an active order survives the round trip")
	check(restored.progress_of("cull_the_watchers") == 7, "and so does its count")

	var garbage := QuestsScript.new()
	garbage.from_dict({"states": {"not_a_quest": 2, "cull_the_watchers": 999},
		"progress": {"cull_the_watchers": 999}})
	check(garbage.state_of("cull_the_watchers") == QuestsScript.State.CLOSED,
		"an out-of-range state is clamped to closed, never half read")
	check(garbage.progress_of("cull_the_watchers") == QuestsScript.WATCHER_KILLS,
		"a complete order is repaired to its goal")
	check(not garbage.has("not_a_quest"), "an unknown quest id is dropped")
	var empty := QuestsScript.new()
	empty.from_dict("not a dictionary")
	check(empty.tracked().is_empty(), "a corrupt section opens with no orders")

	# A whole warband file, written and read back: the ledger rides in it.
	warband.save_state()
	check(FileAccess.file_exists(WARBAND_SAVE), "the warband file is written")
	warband.quests.reset()
	warband.load_state()
	check(warband.quests.progress_of("cull_the_watchers") == 7,
		"the ledger is restored from the warband save")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(WARBAND_SAVE))
		.get("version", 0)) == 5, "the save file is version 5")

	# --- free hires and the stash dressing ---------------------------------
	warband.reset_state()
	warband.quests.reset()
	for index in 5:
		warband.add_mercenary("Veteran %d" % index)
	check(VendorScript.hire_cost(warband.roster) == 0, "the sixth oath is free")
	var purse_before: int = warband.gold()
	warband.stash.add("sword_short", 1)
	warband.stash.add("shield_buckler", 1)
	warband.stash.add("armor_mail_chest", 1)
	warband.stash.add("ring_copper", 1)
	var hired: Dictionary = warband.hire()
	check(bool(hired.get("ok", false)), "the recruiter takes the oath")
	check(int(hired.get("cost", -1)) == 0, "for nothing")
	check(warband.gold() == purse_before, "and the purse does not move")
	var recruit_id := int(hired.get("merc_id", -1))
	check(recruit_id > 0, "a body joins the roster")
	var worn: Dictionary = warband.roster.equipped_of(recruit_id)
	check(str(worn.get("main", "")) == "sword_short", "the recruit is handed a blade from the stash")
	check(str(worn.get("off", "")) == "shield_buckler", "and a shield")
	check(str(worn.get("chest", "")) == "armor_mail_chest", "and the best spare hauberk")
	check(str(worn.get("ring1", "")) == "ring_copper", "and a ring")
	check(warband.stash.pooled_count("sword_short") == 0, "the stash handed the blade over")
	check(warband.stash.pooled_count("armor_mail_chest") == 0, "and the armour")

	# A two-hander locks the off hand even when a shield is spare.
	warband.reset_state()
	for index in 5:
		warband.add_mercenary("Spear %d" % index)
	warband.stash.add("sword_great", 1)
	warband.stash.add("shield_tower", 1)
	var two_handed: Dictionary = warband.hire()
	var two_id := int(two_handed.get("merc_id", -1))
	var two_worn: Dictionary = warband.roster.equipped_of(two_id)
	check(str(two_worn.get("main", "")) == "sword_great", "a two-hander goes in the hands")
	check(str(two_worn.get("off", "")).is_empty(), "and the off hand stays empty")
	check(warband.stash.pooled_count("shield_tower") == 1, "the shield stays in the pool")

	# At the cap the recruiter refuses, and the price curve is back.
	warband.reset_state()
	for index in Contracts.MAX_DEPLOYMENT_CAP:
		warband.add_mercenary("Full %d" % index)
	check(VendorScript.hire_cost(warband.roster) ==
		VendorScript.HIRE_BASE_COST + VendorScript.HIRE_STEP_COST * Contracts.MAX_DEPLOYMENT_CAP,
		"past the free eight the old price returns")
	var refused: Dictionary = warband.hire()
	check(not bool(refused.get("ok", true)), "the cap refuses a ninth body")

	# --- the keeper who talks ----------------------------------------------
	warband.reset_state()
	for index in 5:
		warband.add_mercenary("Oath %d" % index)
	var giver = GiverScript.new()
	root.add_child(giver)
	giver.configure(warband, null)
	check(giver.marker_service() == "recruiter",
		"the arrow starts on the recruiter while the band is short")
	check(not giver.talk("recruiter"),
		"the skipped hire lesson hands the recruiter's talk to his board")
	check(not giver.card.is_open(), "no card is up")
	check(giver.card.has_shown(GiverScript.HIRE_LESSON),
		"but the lesson is recorded as offered")
	check(not giver.talk("recruiter"), "and every later talk opens the board the same way")

	# The band fills to the cap: the quartermaster takes the arrow and offers the
	# cages.
	while warband.roster.count() < warband.deployment_cap:
		warband.hire()
	check(giver.marker_service() == "quartermaster", "the arrow moves to the quartermaster")
	check(not giver.talk("quartermaster"),
		"with the lesson skipped, his counter is the answer")
	check(warband.quests.is_active("free_the_soldiers"), "the cage order is accepted in his hand")
	check(not giver.card.is_open(), "and no offer card opens")

	# Four cages, then the turn-in card names the next order and hands it over.
	for index in QuestsScript.SOLDIER_RESCUES:
		warband.quests.note_rescue()
	check(warband.quests.is_complete("free_the_soldiers"), "the cages are done")
	giver.talk("quartermaster")
	check(warband.quests.is_closed("free_the_soldiers"), "the order is turned in")
	check(warband.quests.is_active("cull_the_watchers"), "and the watcher bounty is taken over")
	check(not giver.card.is_open(), "the skipped turn-in card never opens")

	# The ichor order appears off the chain, the moment the band holds a vial.
	warband.stash.add(QuestsScript.ICHOR_ID, 1)
	giver.refresh_offers()
	check(warband.quests.is_offered("bind_the_ichor"), "a vial in the stash offers its order")
	check(not giver.talk("quartermaster"),
		"the skipped ichor lesson hands the press to his counter")
	check(warband.quests.is_active("bind_the_ichor"), "and the ichor order is taken")
	check(giver.marker_service() == "quartermaster", "the arrow stays on the keeper with work")

	# --- the HUD block ------------------------------------------------------
	var hud = HudScript.new()
	root.add_child(hud)
	hud.set_quests(warband.quests.rows())
	var lines: Array[String] = hud.quest_lines()
	check(lines.size() >= 2, "the ledger paints a title and a line per order")
	check(hud.quest_panel() != null and hud.quest_panel().visible, "and the block is visible")
	hud.set_quests([])
	check(hud.quest_lines().is_empty(), "no orders empties the block")
	check(not hud.quest_panel().visible, "and hides it")

	giver.queue_free()
	hud.queue_free()
	_remove(WARBAND_SAVE)
	print("QUEST_LOG_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
