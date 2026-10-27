class_name CultistGuard
extends "res://scripts/arena_actor.gd"
## One cultist guard: a real arena fighter wearing the cult's colours.
##
## The cage yard and the expedition waves both field these, so the body is the
## same `ArenaActor` the warband uses - rig, melee sweeps, reach, armor, the 10%
## overkill rule - and only three things here are cult: the kit it is handed, the
## crimson paint, and the faction tag that decides who it is willing to fight.
##
## The faction rule exists because `ArenaActor._bot_step` always aims at the
## nearest body in the array it is given. A wave hands every guard the whole
## field (`EnemyWaves.field()`), so without this filter the closest "enemy" would
## often be the cultist standing beside it.

## The arena body already preloads `ArmorData`; the cult kit reuses that constant
## instead of shadowing it.
const Contracts = preload("res://scripts/warband/warband_contracts.gd")
const State = preload("res://scripts/player_state.gd")
const Branded = preload("res://scripts/warband/branded_skills.gd")

## Everyone the cult fields carries this tag; `is_allied` compares it, so any
## future cult body joins the pack by wearing the tag alone.
const FACTION := "cult"
## The cult's roster of names. A wave picks from it; nothing is generated.
const NAMES := [
	"Acolyte Vesh", "Acolyte Sorn", "Acolyte Marn", "Acolyte Kessa",
	"Acolyte Tholl", "Acolyte Issa", "Acolyte Brack", "Acolyte Nara",
]
## Heavy crimson-black, close to the ranger clone's pack tint: a dark body with
## a low ember glow so a cultist reads as hostile at range without new assets.
const TINT := Color(0.24, 0.02, 0.035)
const TINT_EMISSION := Color(0.42, 0.015, 0.015)
const TINT_ENERGY := 0.25

## The faction tag this guard answers to.
var faction := FACTION
## The catalog kit this guard was handed: `main`, `off`, `armor` (set id) and the
## per-slot `pieces` code the rig wears.
var kit: Dictionary = {}
## One material shared by every mesh under this guard's rig, so the paint costs
## one resource per guard and never recolours another body's surfaces.
var cult_material: StandardMaterial3D = null
## The sigil this guard's blade carries for this battle, or `{}`. Brands in
## Warband are item properties kept in the warband's ledger; a cult anointment is
## not the warband's to keep, so it lives on the body that carries it, dies with
## the body, and never touches `Warband.cruor`. Phase 4 owns teaching a cultist to
## *cast* it - this body only tells the field that the steel is anointed.
var brand: Dictionary = {}
var _sigil_label: Label3D = null

## Dress the guard from the cult's catalog: a main hand, the off hand the
## contract allows with it, and one armor set. The off hand is dropped for a
## two-handed or ranged main, which is the only legality rule a kit needs.
func apply_kit(main_id: String, off_id: String, armor_set: String) -> void:
	var off := off_id
	if off.is_empty() or Contracts.two_handed_item(State.ITEMS.get(main_id, {})):
		off = ""
	var set_index := ArmorData.SET_IDS.find(armor_set)
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = set_index if set_index >= 0 else ArmorData.NONE
	kit = {"main": main_id, "off": off, "armor": armor_set, "pieces": pieces.duplicate()}
	rig.apply_loadout(State.build_loadout(main_id, off, pieces))
	_paint()

## Anoint the steel this guard is already holding. `spec` is `{tier, ability}`;
## any item id it names is ignored, because the brand belongs to the blade in the
## guard's hands and to nothing else. An unknown ability leaves the guard plain.
func set_brand(spec: Dictionary) -> void:
	var ability := str(spec.get("ability", ""))
	if ability.is_empty() or Branded.definition(ability).is_empty():
		return
	var held := str(kit.get("main", ""))
	if held.is_empty():
		return
	var tier := int(spec.get("tier", Contracts.CruorTier.T1_RITUAL_TALLOW))
	brand = {"item": held, "tier": tier, "ability": ability,
		"name": Branded.ability_name(ability), "line": Branded.tier_line(ability, tier)}
	_show_sigil()

## The brand this guard carries, or `{}`.
func brand_of() -> Dictionary:
	return brand

## The line drawn under the nameplate, or "" for an ordinary guard.
func brand_line() -> String:
	return str(brand.get("line", ""))

## On their feet: alive and not bleeding out. A downed cultist is a body to step
## over, not a fighter, so the wave manager counts it as neither.
func standing() -> bool:
	return alive and not downed

## Whether `other` fights beside this guard. Same faction only; a warband body
## wears no tag and is therefore always a target.
func is_allied(other: Object) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	var tag: Variant = other.get("faction")
	return tag != null and str(tag) == faction

## The bodies this guard is willing to fight, filtered out of a whole-field actor
## list. Anything that cannot take a hit is scenery and never becomes a target.
func opponents(actors: Array) -> Array:
	var foes: Array = []
	for other in actors:
		if other == self or not (other is Node3D) or not other.has_method("take_damage"):
			continue
		if is_allied(other):
			continue
		foes.append(other)
	return foes

## A guard gets no round reset. The inherited step counts a dead fighter's
## respawn clock down and revives it after three seconds, which in a wave would
## refill a yard the warband just cleared; a cultist that falls stays down.
func step(delta: float, actors: Array, simulation_tick: int = 0) -> void:
	if not alive:
		return
	super.step(delta, actors, simulation_tick)

## The arena's bot step decides stance and swings; the cult only decides who it
## is allowed to see. Everything else - reach, weapon mode, cooldowns - stays the
## shared arena behaviour so a guard fights exactly like a warband bot.
func _bot_step(delta: float, actors: Array) -> void:
	super._bot_step(delta, opponents(actors))

## Draw the sigil under the nameplate. A label of its own, because the arena
## rewrites the nameplate ("name  health") every frame; this one is written once
## and never fights it.
func _show_sigil() -> void:
	if _sigil_label == null:
		_sigil_label = Label3D.new()
		_sigil_label.name = "BrandedSigil"
		_sigil_label.position.y = 2.02
		_sigil_label.font_size = 26
		_sigil_label.pixel_size = 0.006
		_sigil_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_sigil_label.no_depth_test = true
		_sigil_label.modulate = Color(0.95, 0.35, 0.34)
		add_child(_sigil_label)
	_sigil_label.text = brand_line()
	_sigil_label.visible = not brand.is_empty()

## Paint every mesh under the rig with the cult's single material. Run after the
## kit: the rig builds all three bows and swords in `_ready`, so no weapon mesh
## appears later and escapes the paint.
func _paint() -> void:
	if cult_material == null:
		cult_material = StandardMaterial3D.new()
		cult_material.resource_name = "CultCrimson"
		cult_material.albedo_color = TINT
		cult_material.metallic = 0.15
		cult_material.roughness = 0.58
		cult_material.emission_enabled = true
		cult_material.emission = TINT_EMISSION
		cult_material.emission_energy_multiplier = TINT_ENERGY
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = cult_material
	if _label != null:
		_label.text = display_name
		_label.modulate = Color(0.95, 0.35, 0.34)
