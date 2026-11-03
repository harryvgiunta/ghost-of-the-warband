extends Node
## Autoload `SaveSlots`: one folder per campaign under `user://saves`, and the
## one thing that decides which of them the warband and the purse belong to.
##
## Before this node a machine had exactly one campaign: `Warband` and
## `PlayerState` both wrote a fixed `user://` file, so NEW CAMPAIGN and a hosted
## NEW GAME wrote straight over whatever was saved - one slot for the whole
## machine, whatever friend you happened to be playing with. Now every campaign
## is its own folder, and a new one is a new folder:
##
##   user://saves/index.json                 the ledger of what exists
##   user://saves/c1/warband_state.json      the roster, stash, essence, bookmark
##   user://saves/c1/player_state.json       the campaign's own purse
##
## Nothing else in the game knows about folders. `bind()` points the two
## autoloads' `save_path` at a campaign, so every existing writer - the autosave,
## the bookmark, a purchase, the in-world SAVE GAME - keeps writing exactly one
## file with exactly the code it always had, and can only ever write the
## campaign that was opened.
##
## `index.json` is `{version, active, slots:[{id, name, created, played}]}`: the
## id names the folder and never changes, the name is the label a player typed,
## and `active` is what the next launch binds before the title is built. A folder
## with no row is invisible; a row whose folder is gone reads as an empty
## campaign and opens in the cages.

const WarbandStateScript = preload("res://scripts/warband/warband_state.gd")

const ROOT := "user://saves"
## Script-mode regressions get their own ledger, so a test can never read, move
## or write the campaigns on the machine running it.
const TEST_ROOT := "user://saves_test"
const INDEX_FILE := "index.json"
const WARBAND_FILE := "warband_state.json"
const PURSE_FILE := "player_state.json"
## Where a build before this node kept the one campaign a machine had. It is read
## once, moved into the ledger and never written again; `Warband` and
## `PlayerState` still default to those paths when no campaign exists at all.
const LEGACY_WARBAND := "user://warband_state.json"
const LEGACY_PURSE := "user://player_state.json"
## What the adopted save is called in the list.
const MIGRATED_NAME := "Campaign 1"
const INDEX_VERSION := 1
const NAME_LENGTH := 32

## The ledger's folder. Tests point it at a scratch directory.
var root_path := ROOT
## The campaign the warband and the purse are bound to, "" before any exists.
var active := ""
## `[{id, name, created, played}]`, the ledger as read from `index.json`.
var slots: Array[Dictionary] = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		root_path = TEST_ROOT
	load_index()
	# Only the real ledger adopts this machine's old single save; a scratch
	# ledger (a regression, a capture run) must never move a player's campaign.
	if root_path == ROOT:
		migrate_legacy()

# --- paths ------------------------------------------------------------------

func index_path() -> String:
	return root_path.path_join(INDEX_FILE)

func slot_dir(id: String) -> String:
	return root_path.path_join(id)

func warband_path(id: String) -> String:
	return slot_dir(id).path_join(WARBAND_FILE)

func purse_path(id: String) -> String:
	return slot_dir(id).path_join(PURSE_FILE)

# --- the ledger -------------------------------------------------------------

## Read `index.json`. Anything unreadable is an empty ledger rather than a crash:
## the campaigns' own files are still on disk, and an edit or a bad write must
## not take the title down with it.
func load_index() -> void:
	slots.clear()
	active = ""
	var text := FileAccess.get_file_as_string(index_path())
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("SaveSlots: %s is not a ledger" % index_path())
		return
	var data: Dictionary = parsed
	var raw: Variant = data.get("slots", [])
	if raw is Array:
		for entry in raw:
			if not entry is Dictionary:
				continue
			var id := str((entry as Dictionary).get("id", "")).strip_edges()
			if id.is_empty():
				continue
			slots.append({
				"id": id,
				"name": str((entry as Dictionary).get("name", id)).strip_edges(),
				"created": int((entry as Dictionary).get("created", 0)),
				"played": int((entry as Dictionary).get("played", 0)),
			})
	var wanted := str(data.get("active", ""))
	if find(wanted) >= 0:
		active = wanted

func save_index() -> void:
	_ensure_dir(root_path)
	var file := FileAccess.open(index_path(), FileAccess.WRITE)
	if file == null:
		push_warning("SaveSlots: cannot write %s" % index_path())
		_note("index_failed", {"path": index_path()})
		return
	file.store_string(JSON.stringify(
		{"version": INDEX_VERSION, "active": active, "slots": slots}, "\t"))
	file.close()

## The row for `id`, or -1.
func find(id: String) -> int:
	for index in slots.size():
		if str(slots[index].get("id", "")) == id:
			return index
	return -1

func name_of(id: String) -> String:
	var index := find(id)
	return "" if index < 0 else str(slots[index].get("name", id))

## The campaign a warband file belongs to, "" when the path is not one of the
## ledger's: the in-world SAVE line names the campaign, not the file name every
## campaign now shares.
func campaign_of(path: String) -> String:
	for entry in slots:
		var id := str(entry.get("id", ""))
		if warband_path(id) == path:
			return str(entry.get("name", id))
	return ""

## Every campaign, newest first, with the file peeked so a row can say what
## opening it would put the warband on. Read fresh on every call: a campaign
## written or deleted while the title stood is never stale.
func summaries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in slots:
		var id := str(entry.get("id", ""))
		if id.is_empty():
			continue
		var peek: Dictionary = WarbandStateScript.peek_save(warband_path(id))
		out.append({
			"id": id,
			"name": str(entry.get("name", id)),
			"created": int(entry.get("created", 0)),
			"played": int(entry.get("played", 0)),
			"exists": bool(peek.get("exists", false)),
			"roster": int(peek.get("roster", 0)),
			"checkpoint": peek.get("checkpoint", {}),
			"active": id == active,
		})
	out.sort_custom(_newest_first)
	return out

static func _newest_first(a: Dictionary, b: Dictionary) -> bool:
	if int(a["played"]) != int(b["played"]):
		return int(a["played"]) > int(b["played"])
	return str(a["name"]).to_lower() < str(b["name"]).to_lower()

# --- campaigns --------------------------------------------------------------

## Make a campaign folder and its ledger row. `name` is the label a player chose;
## a name already in the ledger takes a number ("Alex", "Alex 2") so two rows are
## never told apart by a suffix nobody typed. Returns the id; the caller binds it.
func new_slot(campaign_name: String) -> String:
	var id := _next_id()
	var clean := _unique_name(campaign_name)
	_ensure_dir(slot_dir(id))
	slots.append({"id": id, "name": clean, "created": _stamp(), "played": _stamp()})
	save_index()
	_note("created", {"slot": id, "name": clean})
	return id

## Point the warband and the purse at `id`, read the campaign's purse, and make it
## the one the next launch resumes. False when the ledger has no such row.
func bind(id: String) -> bool:
	var index := find(id)
	if index < 0:
		return false
	active = id
	slots[index]["played"] = _stamp()
	var warband := get_node_or_null("/root/Warband")
	if warband != null:
		warband.save_path = warband_path(id)
	var purse := get_node_or_null("/root/PlayerState")
	if purse != null:
		purse.save_path = purse_path(id)
		# The purse belongs to the campaign - two campaigns are two wallets, and
		# binding a campaign is the moment this one's gold is read back.
		purse.load_state()
	save_index()
	_note("bound", {"slot": id, "warband": warband_path(id)})
	return true

## Adopt the pre-ledger save into the ledger: move `user://warband_state.json` and
## its purse into the first campaign folder and make it the active one. Returns
## the new id, or "" when there was nothing to adopt (or the move failed, leaving
## the old files exactly where they were). One-shot by construction: a ledger with
## any row at all is never migrated into.
func migrate_legacy(from_warband: String = LEGACY_WARBAND,
		from_purse: String = LEGACY_PURSE) -> String:
	if not slots.is_empty() or not FileAccess.file_exists(from_warband):
		return ""
	var id := _next_id()
	if not _move_file(from_warband, warband_path(id)):
		_note("migrate_failed", {"from": from_warband})
		return ""
	if FileAccess.file_exists(from_purse):
		_move_file(from_purse, purse_path(id))
	slots.append({"id": id, "name": _unique_name(MIGRATED_NAME),
		"created": _stamp(), "played": _stamp()})
	active = id
	save_index()
	_note("migrated", {"slot": id, "warband": warband_path(id)})
	return id

func describe() -> String:
	return "slots=%d active=%s" % [slots.size(), active]

# --- internals --------------------------------------------------------------

func _now() -> int:
	return int(Time.get_unix_time_from_system())

## The next moment to write into the ledger: the wall clock, but always later than
## every stamp already in it. Two campaigns started in the same second would
## otherwise tie, and the list's "newest first" would be the folder order rather
## than what happened - and a clock set backwards must not reorder campaigns.
func _stamp() -> int:
	var newest := 0
	for entry in slots:
		newest = maxi(newest, int(entry.get("played", 0)))
	return maxi(_now(), newest + 1)

func _next_id() -> String:
	var next := 1
	for entry in slots:
		var id := str(entry.get("id", ""))
		if id.begins_with("c") and id.substr(1).is_valid_int():
			next = maxi(next, int(id.substr(1)) + 1)
	return "c%d" % next

func _unique_name(campaign_name: String) -> String:
	var clean := campaign_name.strip_edges().replace("\n", " ").replace("\t", " ").left(NAME_LENGTH)
	if clean.is_empty():
		clean = "Campaign %d" % (slots.size() + 1)
	var taken := {}
	for entry in slots:
		taken[str(entry.get("name", "")).to_lower()] = true
	var candidate := clean
	var suffix := 2
	while taken.has(candidate.to_lower()):
		candidate = "%s %d" % [clean, suffix]
		suffix += 1
	return candidate

func _ensure_dir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))

## Move one file by reading and rewriting it, so a save is only ever absent from
## both places for the moment between the write and the unlink - never half
## copied, and never left behind as a second, stale copy of the same campaign.
func _move_file(from: String, to: String) -> bool:
	var text := FileAccess.get_file_as_string(from)
	if text.is_empty():
		return false
	_ensure_dir(to.get_base_dir())
	var file := FileAccess.open(to, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(from))
	return true

func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("save_slots", message, data)
