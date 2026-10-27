extends SceneTree
## The hand torch: an off-hand item whose whole point is that it is light.
##
## It has to be a real catalog piece (legal in the off hand, refused in the main),
## buyable from the keeper, and — the part that matters — a burning brand on the
## body that wears it: bright enough to light the wood, gone the moment the piece
## comes off. This drives the real world scene for the last three.

const EquipmentRules = preload("res://scripts/equipment_rules.gd")
const State = preload("res://scripts/player_state.gd")
const QuartermasterScript = preload("res://scripts/warband/quartermaster_menu.gd")

const TEST_SAVE := "user://torch_state.json"
const WARBAND_SAVE := "user://torch_warband.json"
const WORLD := "res://scenes/warband_world.tscn"
## Bright enough to be a torch in a wood, not a glow-worm: the trail's own torches
## are 3.4 over 16 m.
const MIN_ENERGY := 7.0
const MIN_RANGE := 20.0

var warband
var state
var game
var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
		print("TORCH_FAIL  ", message)


func _initialize() -> void:
	call_deferred("run")


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> void:
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	state = root.get_node("PlayerState")
	warband = root.get_node("Warband")
	state.save_path = TEST_SAVE
	state.reset(false)
	warband.save_path = WARBAND_SAVE
	warband.reset_state()

	var watch := Timer.new()
	watch.wait_time = 240.0
	watch.one_shot = true
	watch.timeout.connect(func() -> void:
		check(false, "the torch test did not finish inside its watchdog")
		_finish())
	root.add_child(watch)
	watch.start()

	_check_catalog()
	await _check_world()

	_finish()


# --- the item --------------------------------------------------------------

func _check_catalog() -> void:
	check(State.ITEMS.has("torch_hand"), "the catalog carries a hand torch")
	var item: Dictionary = State.ITEMS.get("torch_hand", {})
	check(str(item.get("name", "")) == "Hand Torch", "the torch is named (%s)" % item.get("name"))
	check(EquipmentRules.allowed(item, "off"), "the torch is legal in the off hand")
	check(not EquipmentRules.allowed(item, "main"), "the torch is never a main hand")
	check(EquipmentRules.auto_slot(item, {}) == "off", "a fresh equip puts it in the off hand")
	check(QuartermasterScript.STOCK.has("torch_hand"), "the quartermaster sells the torch")


# --- the light -------------------------------------------------------------

func _check_world() -> void:
	game = load(WORLD).instantiate()
	root.add_child(game)
	await create_timer(1.6).timeout
	if game.card != null and game.card.is_open():
		game.card.close()
	await create_timer(0.4).timeout

	var merc_id: int = game.controller.merc_for_peer(1)
	check(merc_id > 0, "the soul is in a body (%d)" % merc_id)
	var body = game.controller.active_body(1)
	check(body != null, "the body is live")

	warband.stash.add("torch_hand", 1)
	var worn: Dictionary = warband.equip_merc(merc_id, "off", "torch_hand")
	check(bool(worn.get("ok", false)), "the torch goes into the off hand (%s)" % str(worn.get("reason", "")))
	await create_timer(0.5).timeout

	var torch = body.get_node_or_null("HandTorch")
	check(torch != null, "the body carries its torch")
	if torch == null:
		return
	check(torch.lit(), "a worn torch is lit")
	check(torch.flame_visible(), "the flame is on the rig")
	check(torch.light_energy() >= MIN_ENERGY,
		"the torch is bright (%.1f energy)" % torch.light_energy())
	check(torch.light_range() >= MIN_RANGE,
		"the torch reaches (%.1f m)" % torch.light_range())
	var light := body.get_node_or_null("HandTorch/TorchLight") as Light3D
	check(light != null and light.visible, "the light node is on and visible")

	# Taking it off puts the wood back in the dark. `unequip_merc` is the paperdoll's
	# own path: it empties the slot and hands the piece back to the pool.
	var back: String = warband.unequip_merc(merc_id, "off")
	check(back == "torch_hand", "the off hand gives the torch back (%s)" % back)
	await create_timer(0.5).timeout
	check(not torch.lit(), "an empty off hand is not lit")
	check(not torch.flame_visible(), "the flame is gone with the piece")
	check(warband.stash.pooled_count("torch_hand") == 1, "the torch went back to the pool")


func _finish() -> void:
	if is_instance_valid(game):
		game.queue_free()
	await process_frame
	_remove(TEST_SAVE)
	_remove(WARBAND_SAVE)
	print("TORCH_LIGHT_REGRESSION checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
