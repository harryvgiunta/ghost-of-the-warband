extends Node3D

signal impacted(enemy_hit: bool, impact_position: Vector3)

const Bow = preload("res://scripts/bow.gd")
const BloodFx = preload("res://scripts/blood_fx.gd")
const Hitbox = preload("res://scripts/hitbox.gd")
const ImpactRules = preload("res://scripts/impact_rules.gd")
const SfxScript = preload("res://scripts/audio/sfx.gd")
const Perf = preload("res://scripts/perf_probe.gd")
const GRAVITY := Vector3(0.0, -4.0, 0.0)
const VISUAL_BLEND_SECONDS := 0.12
var velocity := Vector3.ZERO
var flying := true
var age := 0.0
var damage := 0.0
var source_id := -1
## The body that released this shaft. Mobs read it through `note_attacker` so
## a ranged hit from cover still names the archer.
var shooter: Node3D
var hit_mask := 1 | 2
var authoritative_damage := true
var pierce := 0
## The arena's own reading of this shaft. `crit` is whether the shot rolled one
## (damage is already multiplied by the shooter); `proc_coeff` is the profile's
## coefficient times the run's proc mods; `homing` is a turn rate and `bounces` a
## budget of fresh bodies. None of it is a campaign number, and a campaign shaft
## leaves all of it at the defaults below.
var crit := false
var proc_coeff := 1.0
## Force multiplier for the body it lands in (Heavy Caliber, a heavy profile):
## the corpse's fall and the gore spray read the same figure.
var impact_scale := 1.0
var homing := 0.0
var homing_target: Node3D
var homing_provider: Callable = Callable()
var bounces := 0
var bounce_provider: Callable = Callable()
## The damage a pierced body adds to the next one (`Piercing Wave`: +15% a body).
var pierce_growth := 0.0
## `(target, position, damage, crit, proc_coeff)` on the authority, for the run's
## on-hit chain. Never called on a replica: a guest draws the flight, the host
## rolls the consequence.
var on_hit: Callable = Callable()
var _bounced: Dictionary = {}
## Backward reconciliation for a shaft a client released: how far behind the
## host that peer was drawing, and the history to rewind targets to.
var lag_comp = null
var lag_ticks := 0
var _query := PhysicsRayQueryParameters3D.new()
var _exclude: Array[RID] = []
var _pierced: Dictionary = {}
var _visual: Node3D
var _visual_start := Vector3.ZERO
var _spawn_position := Vector3.ZERO
var _visual_elapsed := VISUAL_BLEND_SECONDS
var _has_visual_start := false

func _ready() -> void:
	_visual = Bow.create_arrow_visual()
	_visual.position.z = Bow.ARROW_LENGTH
	add_child(_visual)
	_query.collision_mask = hit_mask

func launch(origin: Vector3, direction: Vector3, speed: float, shot_damage: float, excluded: Array[RID], visual_start: Vector3 = Vector3.INF, pierce_count: int = 0) -> void:
	global_position = origin
	velocity = direction.normalized() * speed
	damage = shot_damage
	pierce = maxi(pierce_count,0)
	_query.collision_mask = hit_mask
	_exclude = excluded.duplicate()
	_query.exclude = _exclude
	look_at(global_position + direction, Vector3.UP)
	_spawn_position = origin
	_visual_start = visual_start
	_has_visual_start = visual_start.is_finite()
	_visual_elapsed = 0.0
	_place_visual()
	# The bow lets go here, on every machine that owns an arrow: the live one on
	# the authority and the replica that draws the same shot on a guest.
	SfxScript.arrow(origin)

func _physics_process(delta: float) -> void:
	Perf.begin("missile")
	_fly(delta)
	Perf.end()

func _fly(delta: float) -> void:
	age += delta
	_visual_elapsed = minf(_visual_elapsed + delta,VISUAL_BLEND_SECONDS)
	if not flying:
		if age > 10.0:
			queue_free()
		return
	if homing > 0.0:
		_steer_homing(delta)
	var next := global_position + velocity * delta + GRAVITY * (0.5 * delta * delta)
	velocity += GRAVITY * delta
	var from := global_position
	_query.from = from
	_query.to = next
	# Sweep the physical arrow tip against terrain, props and enemy bodies.
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty() and authoritative_damage and lag_comp != null and lag_ticks > 0:
		# The impact is judged against the body the shooter saw, not the body
		# that has moved on since. A shaft their screen showed missing passes
		# through here and keeps flying.
		if lag_comp.refuses(int(hit.collider_id),lag_comp.latest_tick() - lag_ticks,
				from,next,0.02):
			global_position = next
			look_at(global_position + velocity, Vector3.UP)
			_place_visual()
			return
	if hit.is_empty() and authoritative_damage and lag_comp != null and lag_ticks > 0:
		if _lag_historical_hit(from,next):
			return
	if not hit.is_empty():
		global_position = hit.position
		var collider: Object = hit.collider
		var is_shield := collider.has_method("is_shield")
		var damage_target: Object = collider.get_meta("ironwood_damage_target") if collider.has_meta("ironwood_damage_target") else null
		var hit_player := damage_target != null and is_instance_valid(damage_target) and damage_target.has_method("take_damage")
		var hit_enemy := collider.has_method("take_damage") and not is_shield
		# A piercing shot punches through intact bodies. Every peer consumes the
		# same budget; only the authority applies damage, but the visual line is
		# identical.
		if hit_enemy and not hit_player and pierce > 0 and not _pierced.has(hit.collider_id):
			var pierced_headshot: bool = Hitbox.is_headshot(collider as Node, hit.position)
			if authoritative_damage:
				_note_attacker(collider)
				_note_impact(collider)
				if pierced_headshot:
					_note_headshot(collider)
				collider.take_damage(damage, source_id, pierced_headshot)
				BloodFx.impact(self, hit.position, velocity, damage, pierced_headshot)
				_notify_hit(collider, hit.position)
			pierce -= 1
			# Piercing Wave pays the next body for every body already opened.
			damage *= 1.0 + maxf(pierce_growth, 0.0)
			_pierced[hit.collider_id] = true
			if not _exclude.has(hit.rid):
				_exclude.append(hit.rid)
			_query.exclude = _exclude
			global_position = hit.position + velocity.normalized() * 0.06
			impacted.emit(true, hit.position)
			return
		flying = false
		var applied_hit := false
		var headshot := false
		if authoritative_damage:
			if hit_player:
				# The frontier controller owns the player's two-argument
				# take_damage; the bare CharacterBody has no damage method.
				damage_target.take_damage(damage)
				applied_hit = true
			elif hit_enemy:
				headshot = Hitbox.is_headshot(collider as Node, hit.position)
				_note_attacker(collider)
				_note_impact(collider)
				if headshot:
					_note_headshot(collider)
				collider.take_damage(damage, source_id, headshot)
				applied_hit = true
		if applied_hit:
			BloodFx.impact(self, hit.position, velocity, damage, headshot)
			# A shaft that still has a bounce folded away leaves this body for
			# the next one instead of settling: it is one projectile with several
			# victims, not several projectiles.
			if hit_enemy and not hit_player and _try_bounce(collider, hit.position):
				return
			_notify_hit(collider, hit.position)
		# A shield intercepts the arrow without transferring damage to its
		# owner. Players and shields keep the shaft so it visibly sticks where
		# it landed; the arrow still times out with the existing age limit.
		if (is_shield or collider.has_meta("ironwood_player")) and collider is Node3D:
			reparent(collider as Node3D, true)
			visible = true
			BloodFx.stain_projectile(_visual, damage)
		elif hit_enemy:
			visible = false
		_visual_elapsed = VISUAL_BLEND_SECONDS
		_place_visual()
		impacted.emit(hit_enemy, global_position)
		return
	global_position = next
	look_at(global_position + velocity, Vector3.UP)
	_place_visual()
	if age > 8.0 or global_position.y < -30.0:
		queue_free()

## Turn the shaft toward the body the provider names. A homing shot re-acquires
## its target once its own is dead or was already pierced; the provider is the
## world's, because a projectile must not sweep the whole hostile list itself.
func _steer_homing(delta: float) -> void:
	if not is_instance_valid(homing_target) or _pierced.has(homing_target.get_instance_id()):
		homing_target = null
		if homing_provider.is_valid():
			var found: Variant = homing_provider.call(global_position, _pierced)
			if found is Node3D and is_instance_valid(found):
				homing_target = found
	if not is_instance_valid(homing_target):
		return
	var speed := velocity.length()
	if speed <= 0.01:
		return
	var wanted: Vector3 = ((homing_target as Node3D).global_position
		+ Vector3.UP * 1.15) - global_position
	if wanted.length_squared() <= 0.04:
		return
	var turn := clampf(homing * delta, 0.0, 1.0)
	velocity = velocity.lerp(wanted.normalized() * speed, turn)


## Fold away to another body inside the arena's 12 m ricochet reach. The arrow
## keeps one projectile's worth of life, loses a tenth of its damage per bounce
## and never returns to a body it has already opened.
func _try_bounce(collider: Object, at: Vector3) -> bool:
	if bounces <= 0 or not bounce_provider.is_valid():
		return false
	if collider != null and collider is Node:
		_bounced[(collider as Node).get_instance_id()] = true
	var found: Variant = bounce_provider.call(at, _bounced, 12.0)
	if not (found is Node3D) or not is_instance_valid(found):
		return false
	var target: Node3D = found
	var direction: Vector3 = (target.global_position + Vector3.UP * 1.1) - at
	if direction.length_squared() <= 0.0001:
		return false
	bounces -= 1
	damage *= 0.9
	flying = true
	global_position = at + direction.normalized() * 0.08
	velocity = direction.normalized() * maxf(velocity.length(), 12.0)
	look_at(global_position + velocity, Vector3.UP)
	_exclude.append(target.get_rid())
	_query.exclude = _exclude
	homing_target = target
	impacted.emit(true, at)
	return true


## Tell the shooter's run what this shaft struck, once, on the authority.
func _notify_hit(collider: Object, at: Vector3) -> void:
	if not authoritative_damage or not on_hit.is_valid():
		return
	if collider == null or not (collider is Node):
		return
	on_hit.call(collider, at, damage, crit, proc_coeff)


## A body the shooter's frame put under this swept shaft, resolved now. The
## first such body takes the impact exactly like a present-time hit would.
func _lag_historical_hit(from: Vector3, to: Vector3) -> bool:
	var tick: int = lag_comp.latest_tick() - lag_ticks
	for candidate in lag_comp.candidates(tick):
		if not is_instance_valid(candidate) or not candidate.has_method("take_damage"):
			continue
		if candidate.get("alive") != true or candidate.has_meta("ironwood_player"):
			continue
		if _exclude.has(candidate.get_rid()) \
				or not lag_comp.segment_hits(candidate.get_instance_id(),tick,from,to,0.02):
			continue
		var point: Vector3 = lag_comp.position_at(candidate.get_instance_id(),tick)
		if not point.is_finite():
			continue
		global_position = to
		flying = false
		visible = false
		if authoritative_damage:
			var headshot := Hitbox.is_headshot(candidate,point+Vector3.UP*1.1)
			_note_attacker(candidate)
			_note_impact(candidate)
			if headshot:
				_note_headshot(candidate)
			candidate.take_damage(damage,source_id,headshot)
			BloodFx.impact(self,point,velocity,damage,headshot)
			_notify_hit(candidate, point)
		impacted.emit(true,point)
		return true
	return false


## Hands the shooter to a mob that implements `note_attacker` before the blow
## lands. Bodies that do not care (arena fighters, the player) are untouched.
func _note_attacker(collider: Object) -> void:
	if not is_instance_valid(shooter) or not is_instance_valid(collider):
		return
	if collider.has_method("note_attacker"):
		collider.note_attacker(shooter)


## The arrow's flight direction is the corpse's fall force.
func _note_impact(collider: Object) -> void:
	if collider != null and collider.has_method("note_impact"):
		collider.note_impact(ImpactRules.projectile_force(velocity) * impact_scale)


## A shaft that lands on the head names the headshot on the body before the blow
## lands, so a killing shot can take the head off with the arrow still in it.
## Bodies that do not care (the player, arena fighters) are untouched.
func _note_headshot(collider: Object) -> void:
	if is_instance_valid(collider) and collider.has_method("note_arrow_headshot"):
		collider.note_arrow_headshot(velocity, damage)

func _place_visual() -> void:
	if not is_instance_valid(_visual):
		return
	var tip := global_position
	if _has_visual_start and _visual_elapsed < VISUAL_BLEND_SECONDS:
		var blend := smoothstep(0.0,1.0,_visual_elapsed / VISUAL_BLEND_SECONDS)
		tip += (_visual_start - _spawn_position) * (1.0 - blend)
	# The visual mesh's own tip sits ARROW_LENGTH behind its origin, so place
	# its origin that far ahead along the actual flight axis.
	_visual.global_transform = Transform3D(global_basis,tip + global_basis.z * Bow.ARROW_LENGTH)
