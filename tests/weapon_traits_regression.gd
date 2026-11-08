extends SceneTree
## What a piece of steel does because of what it is, and what a weld does on top.
##
## This owns blunt steel's two native traits and the one annointment the campaign
## issues with them:
##   * the class resolution (club and limb are blunt, a forged blade is not, a
##     staff is its own class) on the rig, in the catalog and on an item card
##   * the club's overhand at twice its profile's clip, while its sweep keeps
##     `DIAGONAL_SECONDS` - the dagger's shank rule, applied to the other end
##   * the blunt stagger: a flat chance on the receiver's own roll and a longer
##     hold, while a blade's figures are exactly what they were
##   * `k_heavy_swing` - 3x the overhand at half again the speed - as a weld, its
##     ceiling, the pieces that can take it, and the club the campaign issues
##
## Run: godot --headless --path . --script res://tests/weapon_traits_regression.gd

const Archer = preload("res://scripts/archer.gd")
const Combat = preload("res://scripts/combat.gd")
const ItemPassives = preload("res://scripts/item_passives.gd")
const State = preload("res://scripts/player_state.gd")
const Catalog = preload("res://scripts/warband/annoint_catalog.gd")
const Ledger = preload("res://scripts/warband/annoint_ledger.gd")
const Card = preload("res://scripts/warband/item_card.gd")
const SeatLoadout = preload("res://scripts/seat_loadout.gd")
const Watcher = preload("res://scripts/warband/cage_watcher.gd")
const Actor = preload("res://scripts/warband/warband_body.gd")
const Thrown = preload("res://scripts/thrown_weapon.gd")

const CLUB := "club_makeshift"
const LIMB := "branch_heavy"
const HEAVY := "k_heavy_swing"
const TEST_SAVE := "user://weapon_traits_test.json"

var checks := 0
var failures := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("WEAPON_TRAITS_FAIL  ", message)
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


## Ids in a pool, so a membership check reads.
static func _ids(pool: Array) -> Array[String]:
	var out: Array[String] = []
	for entry in pool:
		out.append(str(entry.id))
	return out


func run() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	check_classes()
	check_club_clocks(holder)
	check_new_blows(holder)
	check_loadout_hands(holder)
	check_directional_guard(holder)
	check_nock_stack(holder)
	check_lodged_blade()
	check_stagger_rules(holder)
	check_watcher_line(holder)
	check_annoints()
	check_issued_club()
	holder.queue_free()
	await process_frame
	print("WEAPON_TRAITS_REGRESSION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


# --- 1. what a piece is ----------------------------------------------------

func check_classes() -> void:
	check(ItemPassives.sword_class(0) == "sword", "a shortsword is a sword")
	check(ItemPassives.sword_class(2) == "greatsword",
		"the greatsword is its own class, so its click chain can be its own")
	check(ItemPassives.sword_class(3) == "blunt", "the club is blunt steel")
	check(ItemPassives.sword_class(4) == "blunt", "the whole limb is blunt steel")
	check(ItemPassives.sword_class(5) == "axe", "the axe is edged, not blunt")
	check(ItemPassives.sword_class(2, true) == "staff",
		"a staff is its own class whatever profile it reuses")
	check(ItemPassives.class_of(State.ITEMS[CLUB]) == "blunt", "the club's row reads blunt")
	check(ItemPassives.class_of(State.ITEMS[LIMB]) == "blunt", "the limb's row reads blunt")
	check(ItemPassives.class_of(State.ITEMS["axe_makeshift"]) == "axe",
		"the axe's row reads axe")
	check(ItemPassives.class_of(State.ITEMS["sword_short"]) == "sword",
		"a shortsword's row reads sword")
	check(ItemPassives.class_of(State.ITEMS["dagger_ironwood"]) == "dagger",
		"a shiv's row reads dagger")
	check(ItemPassives.class_of(State.ITEMS["staff_fire"]) == "staff",
		"a staff's row reads staff")
	check(ItemPassives.class_of(State.ITEMS["shield_wood"]).is_empty(),
		"a board is not something a hand swings")
	# The one rate table: the shank is untouched and the club's is its own.
	check(is_equal_approx(ItemPassives.variant_rate("dagger", "stab"), 3.0),
		"the dagger's forward stab is still three times as fast")
	check(is_equal_approx(ItemPassives.variant_rate("dagger", "overhead"), 1.0),
		"the dagger's downward blow is its own clip")
	check(is_equal_approx(ItemPassives.variant_damage_scale("dagger", "overhead"), 2.0),
		"and it drives down for double")
	check(is_equal_approx(ItemPassives.variant_rate("blunt", "overhead"), 1.0),
		"the club's overhand is its profile's own clip, not a sped one")
	check(is_equal_approx(ItemPassives.variant_rate("blunt", "diagonal_right"), 1.0),
		"the club's sweep is not")
	check(is_equal_approx(ItemPassives.variant_rate("sword", "overhead"), 1.0),
		"a forged blade's overhand is untouched")
	check(is_equal_approx(ItemPassives.variant_damage_scale("blunt", "overhead"), 1.0),
		"the class adds no damage on its own")
	# The greatsword's chain and the paired swords.
	check(is_equal_approx(ItemPassives.combo_rate("greatsword"), 1.3),
		"a greatsword's second cut comes round 30% quicker")
	check(is_equal_approx(ItemPassives.combo_rate("sword"), 1.0),
		"a one-hander's does not")
	check(is_equal_approx(ItemPassives.dual_rate("sword", "sword"), 1.2),
		"a matched pair of one-handers swings 20% quicker")
	check(is_equal_approx(ItemPassives.dual_rate("sword", "blunt"), 1.0),
		"a sword beside a club is not a pair")
	check(is_equal_approx(ItemPassives.dual_block_chance("sword", "sword"), 0.25),
		"a matched pair turns a quarter of what reaches the body")
	check(is_zero_approx(ItemPassives.dual_block_chance("sword", "dagger")),
		"a sword and a shiv turn nothing")
	# The axe's balance.
	check(is_equal_approx(ItemPassives.throw_scale("axe"), 2.0),
		"an axe is thrown for double")
	check(is_equal_approx(ItemPassives.throw_scale("sword"), 1.0),
		"a sword is not")


# --- 2. the blow on the rig ------------------------------------------------

func check_club_clocks(holder: Node3D) -> void:
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	rig.set_weapon("sword")
	rig.set_sword(3)
	check(rig.swing_weapon_class("right") == "blunt", "the rig reads the club as blunt steel")
	check(is_equal_approx(float(Archer.SWORD_DATA[3].seconds), 0.9),
		"the catalog still authors the club at 0.9 s")
	check(rig.begin_melee("right", "overhead"), "the club starts its overhand")
	var overhand: float = float(rig.melee_seconds("right"))
	check(is_equal_approx(overhand, 0.9),
		"the club's overhand is its authored clip (%.3f s)" % overhand)
	rig.abort_melee("right")
	check(rig.begin_melee("right", "diagonal_right"), "the club starts its sweep")
	var sweep: float = float(rig.melee_seconds("right"))
	check(is_equal_approx(sweep, 0.55),
		"the club's sweep keeps DIAGONAL_SECONDS (%.3f s)" % sweep)
	rig.abort_melee("right")
	check(is_equal_approx(rig.swing_damage("right"), 6.0),
		"a plain club overhand deals its authored six (%.2f)" % rig.swing_damage("right"))

	# Heavy Swing on the hand that holds it: three times the damage at half
	# again the club's own rate, and never the other hand's.
	rig.set_hand_annointments({"main": {"overhead_damage": 2.0, "overhead_speed": 0.5}})
	check(rig.begin_melee("right", "overhead"), "the annointed club starts its overhand")
	var welded: float = float(rig.melee_seconds("right"))
	check(is_equal_approx(welded, 0.6),
		"Heavy Swing takes half again off the club's own 0.9 s (%.3f s)" % welded)
	check(is_equal_approx(rig.swing_damage("right"), 18.0),
		"Heavy Swing deals three times the club's six (%.2f)" % rig.swing_damage("right"))
	rig.abort_melee("right")
	check(rig.begin_melee("right", "diagonal_right"), "the annointed club starts its sweep")
	check(is_equal_approx(float(rig.melee_seconds("right")), 0.55),
		"Heavy Swing leaves the sweep alone")
	rig.abort_melee("right")
	check(is_equal_approx(rig.melee_damage("right"), 6.0),
		"an item skill still reads the plain blow (%.2f)" % rig.melee_damage("right"))
	check(rig.begin_melee("left", "overhead") == false, "the club is one-handed")
	check(is_equal_approx(rig.variant_annoint_rate("left", "overhead"), 1.0),
		"the weld does not follow into the empty hand")

	# A forged blade inherits neither.
	rig.set_hand_annointments({})
	rig.set_sword(0)
	check(rig.swing_weapon_class("right") == "sword", "a shortsword reads as a sword")
	check(rig.begin_melee("right", "overhead"), "the shortsword starts its overhand")
	check(is_equal_approx(float(rig.melee_seconds("right")), 1.0),
		"a sword's overhand is its own authored clip")
	check(is_equal_approx(rig.swing_damage("right"), 30.0),
		"and deals its own damage (%.2f)" % rig.swing_damage("right"))
	rig.abort_melee("right")

	# A staff is its own class and reads no overhead weld.
	rig.set_staff(0, true)
	check(rig.swing_weapon_class("right") == "staff", "the staff still reads as a staff")
	check(is_equal_approx(rig.variant_annoint_rate("right", "overhead"), 1.0),
		"and a staff is never sped by a blunt weld")
	rig.set_staff(0, false)


# --- 2b. the other three class rules ---------------------------------------

## The dagger's downward blow, the greatsword's click chain and the paired
## one-handers, all read off a real rig.
func check_new_blows(holder: Node3D) -> void:
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)

	# The wheel-down of a shiv is the authored downward strike, for double.
	rig.set_weapon("dagger")
	check(rig.begin_melee("right", "overhead"), "the shiv starts its downward blow")
	check(is_equal_approx(rig.swing_damage("right"), 28.0),
		"the downward blow drives 14 damage down for double (%.2f)"
			% rig.swing_damage("right"))
	check(rig._melee_clip_for("right", "overhead").name
			!= rig._melee_clip_for("right", "stab").name,
		"and it is not the forward lunge's clip")
	rig.abort_melee("right")
	check(rig.begin_melee("right", "stab"), "the shiv's forward lunge still starts")
	check(is_equal_approx(rig.swing_damage("right"), 14.0),
		"the forward lunge is still the plain stab (%.2f)" % rig.swing_damage("right"))
	rig.abort_melee("right")

	# A greatsword's second click comes round 30% quicker; a stab breaks the pair.
	rig.set_weapon("sword")
	rig.set_sword(2)
	check(rig.begin_melee("right", "diagonal_right"), "the first cut starts")
	var first: float = float(rig.melee_seconds("right"))
	check(is_equal_approx(first, 1.02), "the first cut is the authored 1.02 s (%.3f)" % first)
	rig.abort_melee("right")
	check(rig.begin_melee("right", "diagonal_left"), "the second cut starts")
	var second: float = float(rig.melee_seconds("right"))
	check(absf(second - first / 1.3) < 0.0001,
		"the second is 30%% quicker (%.3f s)" % second)
	rig.abort_melee("right")
	check(rig.begin_melee("right", "diagonal_right"), "the third cut starts the pair again")
	check(is_equal_approx(float(rig.melee_seconds("right")), first),
		"and it is the full authored cut again")
	rig.abort_melee("right")
	rig.begin_melee("right", "overhead")
	rig.abort_melee("right")
	check(rig.begin_melee("right", "diagonal_right"), "an overhead breaks the pair")
	check(is_equal_approx(float(rig.melee_seconds("right")), first),
		"so the cut after it is the full one")

	# A matched pair of one-handers: quicker, and a quarter of blows turned.
	rig.set_sword(0)
	rig.off_weapon_kind = "sword"
	rig.off_weapon_index = 0
	rig.off_weapon_active = true
	check(rig.set_weapon("dual"), "a pair of shortswords is a dual loadout")
	check(is_equal_approx(rig.dual_block_chance(), 0.25),
		"the pair turns a quarter of what reaches it (%.2f)" % rig.dual_block_chance())
	check(rig.begin_melee("right", "overhead"), "the pair starts an overhand")
	check(absf(float(rig.melee_seconds("right")) - 1.0 / 1.2) < 0.0001,
		"and swings it 20%% quicker (%.3f s)" % float(rig.melee_seconds("right")))
	rig.abort_melee("right")
	rig.off_weapon_kind = "dagger"
	rig.off_weapon_index = 0
	check(is_zero_approx(rig.dual_block_chance()),
		"a sword beside a shiv turns nothing")

	# The axe leaves the hand for double.
	rig.set_weapon("sword")
	rig.set_sword(5)
	check(rig.swing_weapon_class("right") == "axe", "the axe reads as an axe")
	check(is_equal_approx(rig.throw_scale(), 2.0),
		"the axe's throw is worth double (%.2f)" % rig.throw_scale())
	check(is_equal_approx(rig.throw_speed(), 28.0), "and it flies on its own speed")
	check(rig.begin_melee("right", "overhead"), "the axe starts its overhand")
	check(absf(float(rig.melee_seconds("right")) - 1.0) < 0.0001,
		"on its authored second (%.3f s)" % float(rig.melee_seconds("right")))
	rig.abort_melee("right")


# --- 3. the weld reaching the hand ----------------------------------------
## The production path from the warband's ledger to the rig: `SeatLoadout.apply`
## is what `PossessionController._apply_gear` and every re-dress call, and its
## `hands` payload is the only way `overhead_*` reaches a hand.
func check_loadout_hands(holder: Node3D) -> void:
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	var kit := {"main": CLUB, "off": "", "bow": 0, "sword": 3, "armor": 0,
		"trinkets": {"neck": "", "ring1": "", "ring2": "", "off": ""}}
	SeatLoadout.apply(rig, kit, [], {"hands": {"main":
		{"overhead_damage": 2.0, "overhead_speed": 0.5}}})
	check(rig.swing_weapon_class("right") == "blunt",
		"the loadout dresses the club (%s)" % rig.swing_weapon_class("right"))
	check(rig.begin_melee("right", "overhead"), "and that hand swings it")
	check(is_equal_approx(float(rig.melee_seconds("right")), 0.6),
		"SeatLoadout lays the weld on the hand (%.3f s)" % float(rig.melee_seconds("right")))
	check(is_equal_approx(rig.swing_damage("right"), 18.0),
		"and the blow it deals (%.2f)" % rig.swing_damage("right"))
	rig.abort_melee("right")
	# A kit dressed with no weld on that hand holds the plain clip again.
	SeatLoadout.apply(rig, kit, [], {"hands": {"main": {}, "off": {}}})
	check(rig.begin_melee("right", "overhead"), "the plain club swings again")
	check(is_equal_approx(float(rig.melee_seconds("right")), 0.9),
		"and the hand holds no weld (%.3f s)" % float(rig.melee_seconds("right")))
	check(is_equal_approx(rig.swing_damage("right"), 6.0),
		"dealing the plain six (%.2f)" % rig.swing_damage("right"))
	rig.abort_melee("right")


# --- 4. where the guard is held -------------------------------------------

## The guard is a cone around the eye, in three dimensions: level answers a blow
## from the front, raised misses it and answers one that falls on the head. The
## poses follow the same line - a raised greatsword's hilt climbs with it.
func check_directional_guard(holder: Node3D) -> void:
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	rig.set_weapon("sword")
	rig.set_sword(2)
	var combat := Combat.new()
	combat.rig = rig
	combat.grounded = true
	holder.add_child(combat)
	check(combat.start_block(Vector3.FORWARD), "a level guard goes up")
	var front: Vector3 = rig.global_position + Vector3(0, 0, -2.0)
	var chest: Vector3 = rig.global_position + Vector3.UP * Combat.BLOCK_CHEST_HEIGHT
	var head: Vector3 = rig.global_position + Vector3.UP * 1.72
	check(combat.resolve_melee_defense(front, chest) != Combat.DEFENSE_NONE,
		"a level guard stops the blow it is set for")
	check(combat.resolve_melee_defense(front, head) != Combat.DEFENSE_NONE,
		"and the one that lands high, inside its cone")
	# Raised: the guard line is the sky now.
	combat.face_block(Vector3.UP)
	check(rig._block_pitch > 1.2, "looking up raises the guard (%.2f rad)" % rig._block_pitch)
	check(combat.resolve_melee_defense(front, chest) == Combat.DEFENSE_NONE,
		"a guard held up does not stop a blow from the front")
	check(combat.resolve_melee_defense(front, head) != Combat.DEFENSE_NONE,
		"it stops the one falling on it")
	# Lowered: the same rule the other way.
	combat.face_block(Vector3.DOWN)
	check(rig._block_pitch < -1.2, "looking down drops it (%.2f rad)" % rig._block_pitch)
	check(combat.resolve_melee_defense(front, chest) == Combat.DEFENSE_NONE,
		"a dropped guard leaves the chest open")
	check(combat.resolve_melee_defense(front, rig.global_position + Vector3.UP * 0.5)
			!= Combat.DEFENSE_NONE, "and covers the legs")
	# A board covers a wider cone than a blade.
	combat.stop_block()
	rig.set_shield(true)
	combat.start_block(Vector3(0.5, 1.0, -1.0).normalized())
	check(combat.resolve_melee_defense(front, chest) != Combat.DEFENSE_NONE,
		"a shield held between the two covers a front blow")
	rig.set_shield(false)

	# The pose follows the line: a raised greatsword lifts its hilt over the head.
	combat.stop_block()
	rig.set_blocking(true, Vector3.FORWARD)
	rig.advance_animation(0.5)
	var level_hilt: float = rig.get_blade_base("right").y - rig.global_position.y
	rig.face_block(Vector3(0.0, 1.0, -0.25).normalized())
	rig.advance_animation(0.5)
	var raised_hilt: float = rig.get_blade_base("right").y - rig.global_position.y
	check(raised_hilt > level_hilt,
		"a raised guard carries the hilt higher (%.2f -> %.2f)" % [level_hilt, raised_hilt])
	rig.set_blocking(false)


# --- 5. the wire, and the blade that stays in a body -----------------------

## Nock-stacking: the wheel inside a draw pulls a shaft at a time, the release
## fires the whole bundle fanned, and a fresh draw starts with one.
func check_nock_stack(holder: Node3D) -> void:
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	rig.set_weapon("bow")
	rig.aim_at(Vector3(0.0, 1.7, -30.0))
	check(rig.nock_arrows() == 1, "a bow carries one shaft on the string")
	check(rig.stack_nock(1) == 1, "the wheel does nothing outside a draw")
	rig.begin_draw()
	check(rig.phase == "DRAWING", "the string comes back (%s)" % str(rig.phase))
	check(rig.stack_nock(1) == 2, "a notch forward pinches a second shaft")
	check(rig.stack_nock(1) == 3, "and a third")
	check(rig.stack_nock(1) == 4, "and a fourth")
	check(rig.stack_nock(1) == 4, "the bundle is capped at one plus three")
	check(rig.stack_nock(-1) == 3, "a notch back puts one away")
	var shots: Array[Vector3] = []
	rig.arrow_released.connect(func(_origin: Vector3, direction: Vector3,
			_speed: float, _charge: float) -> void:
		shots.append(direction))
	rig.release_string()
	check(shots.size() == 3, "the release fires one missile per shaft (%d)" % shots.size())
	check(shots.size() == 3 and shots[0].angle_to(shots[2]) > 0.02,
		"and the bundle opens out rather than firing one line three times")
	check(rig.nock_arrows() == 1, "the stack is spent")
	# The shot's own recovery: a bow cannot be drawn again until the last shaft
	# has left and the arms have settled.
	rig.advance_animation(1.4)
	check(rig.phase == "READY", "the shot recovers (%s)" % str(rig.phase))
	rig.begin_draw()
	check(rig.nock_arrows() == 1, "and a fresh draw starts with one shaft again")
	rig.cancel_draw()
	check(rig.nock_arrows() == 1, "a cancelled draw leaves nothing on the string")

	# The visor of the whole thing: the extras are real nodes on the string hand.
	rig.begin_draw()
	rig.stack_nock(2)
	var shown := 0
	for prop in rig._nock_props:
		if prop.visible:
			shown += 1
	check(shown == 2, "two more shafts are drawn between the fingers (%d)" % shown)
	rig.cancel_draw()


## A blade thrown into a body stays there and is the thrower's to pull back out.
func check_lodged_blade() -> void:
	var body = Actor.new()
	body.authoritative = true
	var blade = Thrown.new()
	blade.piece_id = "axe_makeshift"
	blade.weapon_index = 5
	check(body.lodge_weapon(blade, "axe_makeshift"), "the axe sticks in the body")
	check(body.lodged_pieces() == ["axe_makeshift"], "the body is carrying a piece (%s)"
		% str(body.lodged_pieces()))
	check(bool(blade.get("lodged")), "and the missile knows it is not flying")
	check(body.lodged_pieces().size() == 1, "one blade, one entry")
	for index in body.LODGED_LIMIT:
		var extra = Thrown.new()
		body.lodge_weapon(extra, "sword_short")
	check(body.lodged_pieces().size() == body.LODGED_LIMIT,
		"a body wears only so many blades (%d)" % body.lodged_pieces().size())
	check(str(body.take_lodged()) == "sword_short", "the newest comes out first")
	check(body.lodged_pieces().size() == body.LODGED_LIMIT - 1, "and the body keeps the rest")
	check(str(body.take_lodged(0)) == "axe_makeshift", "the first one comes out by index")
	check(body.lodged_pieces().size() == body.LODGED_LIMIT - 2, "two blades left")
	while not body.lodged_pieces().is_empty():
		body.take_lodged()
	check(body.take_lodged().is_empty(), "an empty body hands back nothing")
	body.free()


# --- 6. the roll a blow earns ---------------------------------------------

func check_stagger_rules(holder: Node3D) -> void:
	var blade := Combat.stagger_chance_for(6.0, 100.0, "sword")
	check(is_equal_approx(blade, 0.02222222),
		"a six-point blade hit rolls its own small chance (%.4f)" % blade)
	var blunt := Combat.stagger_chance_for(6.0, 100.0, "blunt")
	check(absf(blunt - (blade + 0.35)) < 0.000001,
		"the club adds its own weight on top (%.4f)" % blunt)
	var blade_seconds := Combat.stagger_seconds(6.0, 100.0, "sword")
	var blunt_seconds := Combat.stagger_seconds(6.0, 100.0, "blunt")
	check(is_equal_approx(blade_seconds, 0.152),
		"an edge's stagger is the damage ramp alone (%.3f s)" % blade_seconds)
	check(is_equal_approx(blunt_seconds, 0.228),
		"the club holds a body half again as long (%.3f s)" % blunt_seconds)
	check(Combat.stagger_seconds(200.0, 100.0, "blunt") <= Combat.HIT_STAGGER_MAX + 0.000001,
		"the longer hold never leaves the ceiling")

	# A mob: an edge never breaks its line, a club's head does.
	var blades := 0
	var blunt_lands := 0
	var blunt_wrong := 0
	for roll in 400:
		if Combat.blunt_stagger(6.0, 100.0, "sword") > 0.0:
			blades += 1
		var landed := Combat.blunt_stagger(6.0, 100.0, "blunt")
		if landed > 0.0:
			blunt_lands += 1
			if absf(landed - blunt_seconds) > 0.000001:
				blunt_wrong += 1
	check(blades == 0, "a blade never staggers a devil (%d of 400)" % blades)
	check(blunt_lands > 0, "a club does (%d of 400)" % blunt_lands)
	check(blunt_lands < 400, "and it is still a roll, not a certainty (%d of 400)" % blunt_lands)
	check(blunt_wrong == 0, "every landed blunt stagger is the rolled figure")

	# The campaign body's own roll, which the note feeds.
	var rig := Archer.new()
	holder.add_child(rig)
	rig.set_physics_process(false)
	var combat := Combat.new()
	combat.rig = rig
	holder.add_child(combat)
	var staggered := 0
	for roll in 400:
		combat.stagger_time = 0.0
		combat.stagger_from_damage(0.0, 100.0, "blunt")
		if combat.stagger_time > 0.0:
			staggered += 1
			if absf(combat.stagger_time - Combat.HIT_STAGGER_MIN * 1.5) > 0.000001:
				check(false, "a landed chip stagger is the blunt hold (%.3f)"
					% combat.stagger_time)
	check(staggered > 0, "the club's weight lands a stagger (%d of 400)" % staggered)
	var edged := 0
	for roll in 400:
		combat.stagger_time = 0.0
		combat.stagger_from_damage(0.0, 100.0, "sword")
		if combat.stagger_time > 0.0:
			edged += 1
	check(edged == 0, "a chip from an edge never staggers (%d of 400)" % edged)


## The campaign's own mobs: a watcher has no `Combat`, so `Combat.blunt_stagger`
## is its roll and `stagger` its state. A blow of no damage isolates it - the
## watcher's own tenth-of-the-pool rule cannot fire, so only the piece's weight
## can break its line.
func check_watcher_line(holder: Node3D) -> void:
	var club: Variant = _watcher(holder, "Runt_Club")
	var edge: Variant = _watcher(holder, "Runt_Edge")
	check(club != null and edge != null, "two watchers stand on the plate")
	if club == null or edge == null:
		return
	for swing in 60:
		club.note_strike("blunt")
		club.take_damage(0.0, 99)
		edge.note_strike("sword")
		edge.take_damage(0.0, 99)
	check(str(club.state) == "STAGGER",
		"a club's blow breaks a watcher's line (%s)" % str(club.state))
	check(str(edge.state) != "STAGGER",
		"an edge of the same weight never does (%s)" % str(edge.state))
	club.queue_free()
	edge.queue_free()


func _watcher(parent: Node3D, label: String):
	var watcher = Watcher.new()
	watcher.name = label
	watcher.mob_id = Watcher.RUNT_ID
	watcher.health_pool = Watcher.RUNT_HEALTH
	parent.add_child(watcher)
	watcher.set_physics_process(false)
	return watcher


# --- 5. the weld -----------------------------------------------------------

func check_annoints() -> void:
	var entry := Catalog.by_id(HEAVY)
	check(entry != null, "the pool knows Heavy Swing")
	if entry == null:
		return
	check(entry.wired, "and it is a weld the game can play")
	check(int(entry.kind) == Catalog.Kind.STAT, "it is a stat weld, not a skill")
	check(is_equal_approx(float(entry.stats.get("overhead_damage", 0.0)), 2.0),
		"Heavy Swing carries three times the overhand")
	check(is_equal_approx(float(entry.stats.get("overhead_speed", 0.0)), 0.5),
		"and half again its speed")
	check(not str(entry.line).is_empty(), "the card has a line for it")

	var club_groups := Catalog.groups_of(State.ITEMS[CLUB])
	check(club_groups.has("blunt"), "the club carries the blunt group (%s)" % str(club_groups))
	var limb_groups := Catalog.groups_of(State.ITEMS[LIMB])
	check(limb_groups.has("blunt"), "so does the whole limb (%s)" % str(limb_groups))
	check(not Catalog.groups_of(State.ITEMS["sword_short"]).has("blunt"),
		"a forged blade does not")
	check(_ids(Catalog.for_item(State.ITEMS[CLUB])).has(HEAVY),
		"the club's rack offers Heavy Swing")
	check(_ids(Catalog.for_item(State.ITEMS[LIMB])).has(HEAVY),
		"the limb's rack offers it too")
	for forged in ["sword_short", "sword_arming", "sword_great", "dagger_ironwood"]:
		check(not _ids(Catalog.for_item(State.ITEMS[forged])).has(HEAVY),
			"%s cannot take Heavy Swing" % forged)
	# A club takes everything a sword class takes; the new group narrows nothing.
	check(_ids(Catalog.for_item(State.ITEMS[CLUB])).has("f_weapon_attack_speed_3"),
		"the club's blade-class welds are still offered")

	var ledger := Ledger.new()
	check(ledger.add(CLUB, 0, HEAVY), "a club's copy takes Heavy Swing")
	check(not ledger.add(CLUB, 0, HEAVY), "and never takes it twice")
	var hand := ledger.hand_stats_for(CLUB, 0)
	check(is_equal_approx(float(hand.get("overhead_damage", 0.0)), 2.0),
		"the ledger hands that hand three times the overhand")
	check(is_equal_approx(float(hand.get("overhead_speed", 0.0)), 0.5),
		"and half again its speed")
	# The weld rides the copy in one hand: the kit's own stats never carry it, so
	# the greatsword in the other set swings on its own clock.
	var kit := ledger.stats_for([Ledger.ref(CLUB, 0)])
	check(not kit.has("overhead_damage") and not kit.has("overhead_speed"),
		"the kit's stats leave the hand keys to the hand (%s)" % str(kit))
	check(ledger.hand_stats_for(CLUB, 1).is_empty(), "a spare club's hand is plain")
	check(ledger.hand_stats_for(LIMB, 0).is_empty(), "so is a limb nobody welded")
	check(is_equal_approx(float(Ledger.CEILINGS.get("overhead_damage", 0.0)), 2.0),
		"the ceiling is the one piece's figure")
	check(is_equal_approx(float(Ledger.CEILINGS.get("overhead_speed", 0.0)), 0.5),
		"and the one piece's speed")

	# The card says what the piece does.
	var club_rows := Card.detail_rows(CLUB, State.ITEMS[CLUB])
	var labels := PackedStringArray()
	for row in club_rows:
		labels.append(str(row.get("label", "")))
	check(labels.has("PASSIVE"), "the club's card names its passive (%s)" % str(labels))
	# The club's card names its weight, not an overhand rule: the class grants no
	# rate at all now, so the only rows it can show are the passive and the stagger.
	check(labels.has("STAGGER"), "and the stagger")
	var sword_rows := Card.detail_rows("sword_short", State.ITEMS["sword_short"])
	var paired := PackedStringArray()
	for row in sword_rows:
		paired.append(str(row.get("label", "")))
	check(paired.has("TWIN BLADES") and paired.has("TWIN GUARD"),
		"a one-hander's card names the pair's rules (%s)" % str(paired))
	var dagger_rows := Card.detail_rows("dagger_ironwood", State.ITEMS["dagger_ironwood"])
	var shiv := PackedStringArray()
	for row in dagger_rows:
		shiv.append(str(row.get("label", "")))
	check(shiv.has("FORWARD STAB") and shiv.has("OVERHEAD DAMAGE"),
		"the shiv's card names its lunge and its downward blow (%s)" % str(shiv))
	var axe_rows := Card.detail_rows("axe_makeshift", State.ITEMS["axe_makeshift"])
	var hurled := PackedStringArray()
	for row in axe_rows:
		hurled.append(str(row.get("label", "")))
	check(hurled.has("THROWN"), "the axe's card names its throw (%s)" % str(hurled))


# --- 6. the club a campaign is issued --------------------------------------

func check_issued_club() -> void:
	var warband := root.get_node_or_null("Warband")
	check(warband != null, "the warband autoload is there to seed")
	if warband == null:
		return
	warband.save_path = TEST_SAVE
	warband.reset_state()
	check(int(warband.seed_starting_band()) == 1, "a campaign opens with one body")
	var ids: Array[int] = warband.roster.ids()
	var merc := int(ids[0])
	check(str(warband.roster.equipped_of(merc).get("main", "")) == CLUB,
		"and its one club is in his hand")
	var copy := int(warband.annoint_copy(merc, "main"))
	check(warband.annoints.has(CLUB, copy, HEAVY),
		"the issued club carries Heavy Swing (copy %d)" % copy)
	var hands: Dictionary = warband.annointment_hands(merc)
	check(is_equal_approx(float(hands.get("main", {}).get("overhead_damage", 0.0)), 2.0),
		"the hand holding it reads three times the overhand")
	check(is_equal_approx(float(hands.get("main", {}).get("overhead_speed", 0.0)), 0.5),
		"and half again its speed")
	check(not warband.annointment_stats(merc).has("overhead_damage"),
		"the body's own kit does not carry it")
	check(warband.annointment_procs(merc).is_empty(),
		"a stat weld arms no proc")
	# Put a forged blade in the same hand: the weld does not follow the body.
	warband.stash.add("sword_great", 1)
	var swapped: Dictionary = warband.equip_merc(merc, "main", "sword_great")
	check(bool(swapped.get("ok", false)), "the body takes a greatsword")
	check(warband.annointment_hands(merc).get("main", {}).is_empty(),
		"and that hand swings the greatsword's own overhead (%s)"
			% str(warband.annointment_hands(merc)))
	# A spare club bought later is plain steel.
	warband.stash.add(CLUB, 1)
	var plain := 0
	for serial in warband.stash.serials_of(CLUB):
		if int(serial) != copy:
			plain += 1
			check(warband.annoints.count(CLUB, int(serial)) == 0,
				"a spare club is not annointed (serial %d)" % int(serial))
			break
	check(plain == 1, "the pool holds the spare beside the relic")
	# The roster is the game's; a test never leaves its own band behind.
	warband.reset_state()
	var save := ProjectSettings.globalize_path(TEST_SAVE)
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(save)
