extends SceneTree
## The ichor bench: a warden's vial is the price of one sigil, the piece keeps it,
## and the campaign's ichor order is the thing that hears about it.
##
## The bench is the only place a weapon changes shape without essence, so this
## owns three contracts: the vial leaves the shared stash, `WarbandCruor` records
## the same brand the altar would write, and an already-branded piece is refused
## instead of being rerolled for free.

const BenchScript = preload("res://scripts/warband/ichor_bench.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const Catalog = preload("res://scripts/warband/cruor_catalog.gd")

const WARBAND_SAVE := "user://ichor_bench_warband.json"

var warband
var checks := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("ICHOR_FAIL  ", message)

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
	warband.quests.reset()
	warband.add_mercenary("Brann")

	var bench = BenchScript.new()
	bench.name = "IchorBenchPanel"
	root.add_child(bench)
	bench.configure(warband, null)
	check(bench.vial_count() == 0, "a fresh warband has no ichor")
	check(bench.rows().is_empty(), "and no spare steel to bind")
	check(not bool(bench.apply("sword_short").get("ok", true)), "a bind with no vial is refused")

	# The shelf: a vial and two spare weapons, one of which is already branded.
	warband.stash.add("ichor_vial", 2)
	warband.stash.add("sword_short", 1)
	warband.stash.add("bow_short", 1)
	# The altar needs essence to brand; the bench does not, which is the point.
	warband.cruor.add(Contracts.CruorTier.T1_RITUAL_TALLOW, 10)
	warband.cruor.brand("bow_short", Contracts.CruorTier.T1_RITUAL_TALLOW)
	check(warband.cruor.is_branded("bow_short"), "the bow is branded by the altar")
	warband.cruor.counts.clear()
	warband.cruor.counts[Contracts.CruorTier.T1_RITUAL_TALLOW] = 0
	var rows: Array[Dictionary] = bench.rows()
	check(rows.size() == 1, "only the unbranded spare is on the bench (%d)" % rows.size())
	check(str(rows[0]["item_id"]) == "sword_short", "and it is the sword")
	check(not str(rows[0]["ability_name"]).is_empty(), "the row names the sigil it would take")
	var expected := Branded.for_subtype(Contracts.weapon_subtype(
		{"category": "1h", "kind": "sword"}))
	check(str(rows[0]["ability"]) == expected, "and it is the table's own pick (%s)" % expected)

	# The bind.
	check(bench.vial_count() == 2, "two vials on the shelf")
	var bound: Dictionary = bench.apply("sword_short")
	check(bool(bound.get("ok", false)), "the sword takes the vial: %s" % str(bound.get("message", "")))
	check(bench.vial_count() == 1, "one vial is spent")
	check(warband.cruor.is_branded("sword_short"), "the piece is branded in the one ledger")
	check(str(warband.cruor.brand_of("sword_short").get("ability", "")) == expected,
		"with the ability the row promised")
	check(warband.stash.pooled_count("sword_short") == 1, "and it stays in the stash")
	check(bench.rows().is_empty(), "a branded piece leaves the bench")
	check(int(warband.cruor.brand_of("sword_short").get("tier", -1)) ==
		BenchScript.TIER, "at the bench's own tier")
	check(warband.cruor.brand_line("sword_short").contains("Rending"),
		"the tooltip line names the sigil (%s)" % warband.cruor.brand_line("sword_short"))

	# Essence was not touched: the vial is the whole price.
	check(warband.cruor.total() == 0, "binding costs no essence")

	# One piece, one sigil: a second vial cannot reroll it at the bench.
	var again: Dictionary = bench.apply("sword_short")
	check(not bool(again.get("ok", true)), "an already-branded piece is refused")
	check(bench.vial_count() == 1, "and the vial is not spent")

	# The campaign order hears the fact once.
	warband.quests.offer("bind_the_ichor")
	warband.quests.accept("bind_the_ichor")
	check(warband.quests.is_active("bind_the_ichor"), "the ichor order is active")
	warband.stash.add("dagger_iron", 1)
	var second: Dictionary = bench.apply("dagger_iron")
	check(bool(second.get("ok", false)), "a second blade takes the last vial")
	check(warband.quests.is_complete("bind_the_ichor"), "the order is finished by the bind")
	check(bench.vial_count() == 0, "no vials left")
	check(bench.rows().is_empty(), "nothing bindable is left")

	# The bench prop: real furniture with the one green light in the square.
	var host := Node3D.new()
	root.add_child(host)
	var prop: Node3D = BenchScript.build_prop(host)
	check(prop is Node3D and prop.name == "IchorBench", "the bench prop is built")
	check(prop.get_node_or_null("IchorLight") != null, "the brazier light is on it")
	var labels := 0
	for child in prop.get_children():
		if child is Label3D:
			labels += 1
	check(labels == 1, "and one label names it")

	bench.queue_free()
	host.queue_free()
	_remove(WARBAND_SAVE)
	print("ICHOR_BENCH_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
