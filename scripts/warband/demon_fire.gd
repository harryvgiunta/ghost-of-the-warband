class_name DemonFire
extends RefCounted
## The goatmen's fire: the three spells the Hollow's demons throw, their numbers,
## and the projectile, cone and burning ground each one becomes.
##
## `devil_mob.gd` owns the clock and the tell - a cast is a third action beside a
## swing and a guard, and the windup is what a player answers. This file owns what
## a cast is: how far it reaches, how long it takes, what it costs the demon to
## have spent it, and what it leaves in the world. The two demon overrides name
## which spells their bodies carry (`delve_demon.gd`).
##
## **Fire is not a melee blow.** Everything here wounds a body through its own
## `take_damage`, so the guard, the armour's reduction and the downed rule answer
## it exactly as they answer a blade. It never goes through `receive_melee`, which
## a raised guard turns: nothing blocks a fireball, a party gets out of its way.
##
## A spell resolves at the point and down the line it was loosed on - a target
## that leaves is not chased, which is what makes all three dodgeable. The body
## that threw it applies the damage (`blast`, `burn`, `breath`), handed to the
## projectile and the patch as a `Callable`: fire only ever comes out of a living
## demon's own hands, and a replica's copy of one spawns nothing.
##
## Every visual is `AbilityFx`'s and every cast is heard with the `fire` cue.

const AbilityFx = preload("res://scripts/ability_fx.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")

## Every blow a demon's fire books is attributed to the demon family, beside the
## camp's watchers (90), the trail's cultists (91) and the wilderness (92): the
## reduction and the record name an attacker family by number.
const DAMAGE_SOURCE := 93
## The one sound a cast makes (`SfxLibrary`), at the body that loosed it.
const FIRE_CUE := "fire"
## How far off its own ground a body may stand and still be inside a blast or a
## cone: a step up a stair is still the same fire.
const VERTICAL_SLACK := 2.4

## id -> shape, range, windup, cooldown, damage, radius. `range` is how far the
## demon will begin the cast; `radius` is what the spell covers where it lands.
const SPELLS := {
	# 18 damage in a 1.6 m blast, thrown at 12 m/s. The flight is real, so the
	# blast lands on the ground the target stood on, not on the body.
	"fireball": {"shape": "projectile", "range": 16.0, "windup": 0.7,
		"cooldown": 9.0, "damage": 18.0, "radius": 1.6, "speed": 12.0},
	# 14 damage through everything standing in a 7 m cone 50 degrees wide, after
	# a 1.25 s rear-back the eye can answer.
	"hellfire_breath": {"shape": "cone", "range": 7.0, "windup": 1.25,
		"cooldown": 11.0, "damage": 14.0, "radius": 7.0, "arc_degrees": 50.0},
	# 6 damage a tick every 0.6 s for 3 s in a 2.6 m patch, blooming 1.2 s after
	# the hand comes up: the one the party walks out of.
	"ember_rain": {"shape": "hazard", "range": 13.0, "windup": 1.2,
		"cooldown": 14.0, "damage": 6.0, "radius": 2.6, "tick": 0.6,
		"duration": 3.0},
}


# --- the projectile ---------------------------------------------------------

## A fireball in the air. It travels at the spell's speed to the point it was
## aimed at and then hands that point to `on_land` - the body's own blast. Nothing
## steers it, so a body that has stepped out of the blast is missed and one that
## has not is hit; and a demon freed mid-flight hands nothing anywhere.
class Projectile extends Node3D:
	const Fx = preload("res://scripts/ability_fx.gd")
	const Perf = preload("res://scripts/perf_probe.gd")

	var spell: Dictionary = {}
	## `func(at: Vector3, row: Dictionary)`: the body's blast at the landing point.
	var on_land := Callable()
	## The line it is flying down.
	var velocity := Vector3.ZERO
	var aim := Vector3.ZERO
	## The longest a fireball may stay in the air, whatever the world does to it.
	var life := 6.0
	var _trail: CPUParticles3D

	func _ready() -> void:
		_build()

	func _physics_process(delta: float) -> void:
		Perf.begin("missile")
		_flight(delta)
		Perf.end()

	func _flight(delta: float) -> void:
		life -= delta
		global_position = global_position.move_toward(aim, velocity.length() * delta)
		if global_position.distance_squared_to(aim) <= 0.0001 or life <= 0.0:
			_land()

	func _land() -> void:
		set_physics_process(false)
		global_position = aim
		if is_instance_valid(_trail):
			_trail.emitting = false
		if on_land.is_valid():
			on_land.call(global_position, spell)
		queue_free()

	func _build() -> void:
		var shell := SphereMesh.new()
		shell.radius = 0.26
		shell.height = 0.52
		shell.radial_segments = 18
		shell.rings = 9
		var orb := MeshInstance3D.new()
		orb.mesh = shell
		orb.material_override = Fx.glow_material(Fx.FIRE, 3.2, 0.55)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(orb)
		Fx.sprite_flash(self, Vector3.ZERO, Vector2.ONE * 0.62, Fx.FIRE_CORE)
		add_child(Fx.flash_light(Fx.FIRE, 2.2, 5.0))
		_trail = Fx.soft_spark_particles(Fx.FIRE, 40, 0.4, 1.8, 0.36, 0.05, false)
		add_child(_trail)


# --- the burning ground -----------------------------------------------------

## A patch of burning ground. It ticks every `tick` seconds for `duration`, each
## tick handing its own footprint to `on_tick` - the body's own burn - then goes
## out on its own: the party can walk out of it and the demon that made it can die
## beside it, and the patch still puts itself away.
class Patch extends Node3D:
	const Fx = preload("res://scripts/ability_fx.gd")
	## How long the last tick's fire takes to leave the ground, so it goes out
	## instead of blinking: no damage is dealt once the clock has run out.
	const FADE := 0.35

	var spell: Dictionary = {}
	## `func(at: Vector3, row: Dictionary)`: one tick of the body's fire.
	var on_tick := Callable()
	var _left := 3.0
	var _tick_left := 0.6
	var _light: OmniLight3D
	var _glow: StandardMaterial3D
	var _embers: CPUParticles3D

	func _ready() -> void:
		_left = maxf(0.1, float(spell.get("duration", 3.0)))
		_tick_left = maxf(0.05, float(spell.get("tick", 0.6)))
		_build()

	## The ground is placed by the helper that made the patch, so the fire only
	## starts here: the first tick and the ember plume both belong where it stands.
	func start() -> void:
		if _embers != null:
			_embers.emitting = true
		_burn()

	func _physics_process(delta: float) -> void:
		_left -= delta
		if _left <= 0.0:
			_expire()
			return
		_tick_left -= delta
		if _tick_left <= 0.0:
			_tick_left += maxf(0.05, float(spell.get("tick", 0.6)))
			_burn()

	func _burn() -> void:
		if on_tick.is_valid():
			on_tick.call(global_position, spell)

	## Out: the last tick has burned, so the fire stops hurting and fades off the
	## ground. `set_physics_process(false)` is the whole of "no more damage".
	func _expire() -> void:
		set_physics_process(false)
		if _embers != null:
			_embers.emitting = false
		var tween := create_tween()
		tween.set_parallel(true)
		if _light != null:
			tween.tween_property(_light, "light_energy", 0.0, FADE)
		if _glow != null:
			tween.tween_property(_glow, "albedo_color", Color(0.0, 0.0, 0.0, 0.0), FADE)
		tween.set_parallel(false)
		tween.tween_callback(queue_free)

	func _build() -> void:
		var radius := float(spell.get("radius", 2.0))
		_glow = Fx.glow_material(Fx.FIRE, 1.6, 0.28)
		var disc := CylinderMesh.new()
		disc.top_radius = radius
		disc.bottom_radius = radius
		disc.height = 0.02
		disc.radial_segments = 24
		disc.rings = 1
		var ground := MeshInstance3D.new()
		ground.mesh = disc
		ground.material_override = _glow
		ground.position = Vector3(0.0, 0.04, 0.0)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ground)
		var embers := Fx.soft_spark_particles(Fx.FIRE, 30, 0.5, 2.4, 0.7, 0.055, false)
		embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		embers.emission_sphere_radius = radius * 0.8
		embers.gravity = Vector3(0.0, 2.2, 0.0)
		embers.emitting = false
		add_child(embers)
		_embers = embers
		_light = Fx.flash_light(Fx.FIRE, 2.6, radius * 2.6)
		_light.position = Vector3(0.0, 0.5, 0.0)
		add_child(_light)


# --- the table --------------------------------------------------------------

## One spell's row, copied: a caller that reads or scales it cannot write the
## table. An unknown id answers `{}`, which every caller here treats as no cast.
static func spell(spell_id: String) -> Dictionary:
	return (SPELLS.get(spell_id, {}) as Dictionary).duplicate(true)


## Whether a demon at `distance` may begin this spell.
static func in_range(row: Dictionary, distance: float) -> bool:
	return not row.is_empty() and distance <= float(row.get("range", 0.0))


## Whether `point` stands inside the cone a body at `origin` opens down `forward`.
static func in_cone(origin: Vector3, forward: Vector3, point: Vector3,
		row: Dictionary) -> bool:
	if absf(point.y - origin.y) > VERTICAL_SLACK:
		return false
	var offset := Vector3(point.x - origin.x, 0.0, point.z - origin.z)
	var distance := offset.length()
	if distance > float(row.get("radius", 0.0)):
		return false
	var flat := Vector3(forward.x, 0.0, forward.z)
	# A body standing in the demon's own footprint is inside its fire.
	if distance < 0.35 or flat.length_squared() < 0.000001:
		return true
	var half := deg_to_rad(float(row.get("arc_degrees", 50.0))) * 0.5
	return absf(flat.normalized().angle_to(offset / distance)) <= half


## Whether `point` stands inside a blast or a patch of `radius` at `at`.
static func inside(point: Vector3, at: Vector3, radius: float) -> bool:
	if absf(point.y - at.y) > VERTICAL_SLACK:
		return false
	return Vector2(point.x - at.x, point.z - at.z).length() <= radius


## Everyone a demon's fire can burn: the bodies its own melee picks from. The
## caster answers for the list, so a patch reads the live party rather than a copy
## taken when the spell was thrown.
static func bodies(caster: Node3D) -> Array:
	if is_instance_valid(caster) and caster.has_method("fire_targets"):
		return caster.fire_targets()
	return []


## One body takes fire. Fire is routed like any other blow that is not a blade:
## the body's own `take_damage`, with the demon family as its source.
static func wound(victim, amount: float, caster: Node3D) -> bool:
	if not is_instance_valid(victim) or amount <= 0.0:
		return false
	if victim.get("alive") == false:
		return false
	# A body on the ground is out of the fight: the same rule the melee path
	# applies before it books a blow (`world_scene._on_enemy_attack`), so fire
	# cannot finish a body that is already down and cannot walk out.
	if victim.get("downed") == true:
		return false
	if is_instance_valid(caster) and victim.has_method("note_attacker"):
		victim.note_attacker(caster)
	if not victim.has_method("take_damage"):
		return false
	victim.take_damage(amount, DAMAGE_SOURCE)
	return true


# --- the telegraph ----------------------------------------------------------

## The windup's own light: a coal gathering at the body that loosed it, growing
## for the whole tell. It takes itself off the screen if the body that owns it
## never resolves the cast, so an interrupted windup leaves nothing behind.
static func telegraph(parent: Node3D, at: Vector3, row: Dictionary) -> Node3D:
	if not is_instance_valid(parent):
		return null
	var root := Node3D.new()
	root.name = "DemonCastTell"
	parent.add_child(root)
	root.global_position = at
	var seconds := maxf(0.1, float(row.get("windup", 0.5)))
	var light := AbilityFx.flash_light(AbilityFx.FIRE, 0.5, 3.5 + 2.5 * seconds)
	root.add_child(light)
	var core := AbilityFx.sprite_flash(root, Vector3.ZERO, Vector2.ONE * 0.42,
		AbilityFx.FIRE_CORE)
	var tint := AbilityFx.sprite_tint(core)
	var tween := root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(light, "light_energy", 3.4, seconds)
	tween.tween_property(core, "scale", Vector3.ONE * 2.6, seconds)
	if tint != null:
		tween.tween_property(tint, "albedo_color",
			Color(AbilityFx.FIRE.r, AbilityFx.FIRE.g, AbilityFx.FIRE.b, 0.9), seconds)
	tween.set_parallel(false)
	tween.tween_callback(root.queue_free)
	return root


# --- the three shapes -------------------------------------------------------

## A fireball from `from` to the point the target stood on when the cast began.
## `on_land` is the body's blast; the projectile frees itself once it has handed
## the point over, whether the demon that threw it still lives or not.
static func launch(parent: Node3D, from: Vector3, aim: Vector3, row: Dictionary,
		on_land: Callable) -> Node3D:
	if not is_instance_valid(parent) or row.is_empty():
		return null
	var shot := Projectile.new()
	shot.spell = row
	shot.on_land = on_land
	shot.aim = aim
	shot.velocity = (aim - from).normalized() * float(row.get("speed", 12.0))
	parent.add_child(shot)
	shot.global_position = from
	SfxScript.play(FIRE_CUE, from)
	return shot


## The breath: a cone `radius` long and `arc_degrees` wide down `forward`, burning
## everything standing in it. `origin` is the body's own feet - the ground the cone
## is measured on. Returns the number of bodies it caught.
static func breath(parent: Node3D, origin: Vector3, forward: Vector3, row: Dictionary,
		caster: Node3D) -> int:
	var reach := float(row.get("radius", 0.0))
	var caught := 0
	for victim in bodies(caster):
		if not is_instance_valid(victim) or not (victim is Node3D):
			continue
		if not in_cone(origin, forward, (victim as Node3D).global_position, row):
			continue
		if wound(victim, float(row.get("damage", 0.0)), caster):
			caught += 1
	if is_instance_valid(parent):
		var flat := Vector3(forward.x, 0.0, forward.z)
		if flat.length_squared() > 0.000001:
			# The cone itself, as fire the eye can still read a beat later: the
			# crescent opens out to the reach the damage used, so the light and the
			# hit volume are the same shape.
			AbilityFx.wave_ripple(parent, origin, flat, reach,
				float(row.get("arc_degrees", 50.0)), 0.0, AbilityFx.FIRE)
			AbilityFx.burst(parent, origin + flat.normalized() * (reach * 0.55)
				+ Vector3.UP * 1.1, AbilityFx.FIRE, 1.3)
	SfxScript.play(FIRE_CUE, origin)
	return caught


## The blast where a fireball lands: everything of `radius` round the point takes
## the spell's damage, and the ground is lit for the beat it takes to read.
## Returns the number of bodies it caught.
static func blast(parent: Node3D, at: Vector3, row: Dictionary, caster: Node3D) -> int:
	var caught := scorch(at, row, caster)
	if is_instance_valid(parent):
		AbilityFx.explosion(parent, at, float(row.get("radius", 0.0)))
	SfxScript.play(FIRE_CUE, at)
	return caught


## One tick of burning ground. A patch is a place, not an explosion: the same wound
## without a bloom, because one that flashed on every tick would read as five
## fireballs. Returns the number of bodies it burned.
static func burn(at: Vector3, row: Dictionary, caster: Node3D) -> int:
	return scorch(at, row, caster)


## Everything of the spell's `radius` round `at`, wounded once.
static func scorch(at: Vector3, row: Dictionary, caster: Node3D) -> int:
	var radius := float(row.get("radius", 0.0))
	var caught := 0
	for victim in bodies(caster):
		if not is_instance_valid(victim) or not (victim is Node3D):
			continue
		if not inside((victim as Node3D).global_position, at, radius):
			continue
		if wound(victim, float(row.get("damage", 0.0)), caster):
			caught += 1
	return caught


## Ember rain: burning ground blooms at `at` - the point the target stood on when
## the hand went up - and ticks its damage to whoever is still standing in it.
## `on_tick` is the body's burn.
static func ember_rain(parent: Node3D, at: Vector3, row: Dictionary,
		on_tick: Callable) -> Node3D:
	if not is_instance_valid(parent) or row.is_empty():
		return null
	var patch := Patch.new()
	patch.spell = row
	patch.on_tick = on_tick
	parent.add_child(patch)
	patch.global_position = at
	# The bloom: the ground catching, once, where it caught - and the first tick,
	# burned where the patch actually stands rather than at the node's origin.
	AbilityFx.explosion(parent, at, float(row.get("radius", 2.0)) * 0.55)
	patch.start()
	SfxScript.play(FIRE_CUE, at)
	return patch
