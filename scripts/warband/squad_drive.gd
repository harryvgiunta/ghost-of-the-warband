extends RefCounted
## The warband's side of a fight with the wood: one squad, one behaviour.
##
## The cage escape grew this AI inside the scene - a freed prisoner silently arms
## himself from the cultist steel on the ground and goes for the nearest watcher,
## and the player's own body is never driven. The escape run needs the same squad
## with one clause the cage never needed: the run has somewhere to be, so an ally
## with nothing to fight walks with the soul.
##
## Rather than fork that into a second copy, this module is the one
## implementation. Each scene owns an instance and hands in the facts only it
## knows:
##
##   * `eligible` - who is a squadmate on this frame. The cage answers with its
##     latches (a prisoner still in a cage is not free); the run answers with the
##     roster.
##   * `following` - whether an ally escorts the soul or holds its ground.
##   * `engage_radius` - how far an ally will pick a fight on its own. The cage
##     lets the squad cross the yard; the run keeps them near the soul.
##
## Everything the squad does is silent. Arming itself, taking a drop and swinging
## are the squad's business, not a feed to read; the warband contract forbids a
## loot step in the objective and forbids announcing pickups.
##
## The fight itself is the ranger clones' rhythm with the guard made honest, and
## with every frame accounted for: an ally inside `engage_radius` is closing,
## swinging, holding a short guard window, taking a few steps off the line, or
## re-forming for the next blow. There is no fifth answer, so a body with a
## hostile in reach can never fall back to standing still.

## Read-only sources the scene owns.
var controller
var warband
var loot
## The scene's revive channel: the squad picks a downed soul up with it.
var revive
## Mercenary ids this scene fields as its squad.
var squad_ids: Array[int] = []
## Live arrays owned by the scene, shared by reference so a drop or a watcher
## spawned after setup is seen without a second call.
var watchers: Array = []
var pickups: Array = []

## The body the local soul is inside this frame. Never driven from here.
var player_body = null
## `merc_id -> bool`, defaulting to "every squad id is free".
var eligible := Callable()
var following := false
## How far behind the soul an escorting ally may fall before it closes up.
var follow_slack := 3.2
## Deterministic across runs: the rhythm looks unscripted without making a
## regression flaky.
var _rng := RandomNumberGenerator.new()
var _rng_seeded := false
## The soul's footprints down the road, oldest first: the line the escort walks when
## it has been left behind. `_trail_base` counts the footprints that have fallen off
## the back, so a footprint's number - its index plus the base - is still the same
## footprint after the line is trimmed, and an ally's place on it survives.
var _trail: Array[Vector3] = []
var _trail_base := 0
## The ground an area has mapped for the squad (`squad_nav.gd`), or null. Where it
## covers a body and the place it is walking to, the walk goes round what the map
## knows is solid instead of pushing at it in a straight line; everywhere else the
## squad steers as it always has. The camp owns the one map today.
var nav = null
var engage_radius := 60.0
## How close an ally must stand to swing.
var reach := 2.0
## How close an ally must be to take a drop off the ground, or to bend over a
## fallen body. The player's own reach is 2.6 m, and the squad uses the same
## number: four allies converging on one blade stand in a ring, each pushed out
## by the others, and a 2.0 m reach left the whole ring just short of the piece
## forever. It also covers a drop lying against a trunk that stops the capsule
## just outside an arm's length.
var loot_reach := 2.6
## Where a body stops walking into what it is fighting. Blades are 1.15-2.3 m
## long, so a fighter that keeps pressing forward is inside the mob's own capsule
## long before its swing lands - and a squad that leans on a body shoves it across
## the field. An ally closes to this and no further, and backs off when the press
## has carried it inside `MIN_GAP`.
const STANDOFF := 1.45
const MIN_GAP := 0.95
## Past this gap a body jogs; inside it, it walks in. A wolf-trot into contact is
## what made the squad read as a bulldozer.
const RUN_GAP := 7.0
## Personal space. Every step a squadmate takes is pushed apart from the bodies
## around it, so four allies with nothing to do stand as four bodies instead of
## one knot: a crowd that ends up inside itself is the same bug as a body that
## leans on a mob.
const PERSONAL_SPACE := 1.45
const PERSONAL_WEIGHT := 0.9
## How far the shove may bend a step: never more than this share of the step it
## rides on, so a body always keeps most of the way it meant to go.
const PUSH_SHARE := 0.75
const PUSH_CAP := 0.55
## An escort stands on its own slot around the soul rather than on the soul: the
## ring is what spreads the squad out on the walk instead of stacking it.
##
## Four posts to a ring, and the next ring turned half a slot: the eight allies a
## full warband can field are eight distinct places, each a stride from its
## neighbours. The layout used to key off the body's index in `squad_ids`, which
## spends one of those places on the soul the player is inside - so the ring
## wrapped and two allies were handed the same point, shoved each other off it and
## walked back in. Two bodies orbiting one post is the band circling itself.
const ESCORT_SLOT_ANGLES := 4
const ESCORT_SLOT_GAP := 1.35
## The escort's arrival band. An ally walks to its post only when it is further
## than `ESCORT_ENGAGE` from it and stops `ESCORT_STANDOFF` short, so it arrives
## and stays. Without the band a body walked to its post, overshot it by the
## walk's own stopping distance, turned round and paced back: measured on a still
## soul with no enemies at all, four allies covered 40-53 m apiece in ten seconds
## and ended 12-20 m from where they started - walking in circles.
const ESCORT_ENGAGE := 1.9
const ESCORT_STANDOFF := 0.85
## The escort's line. A body more than `ESCORT_RALLY` behind the soul walks the
## soul's own footprints instead of pointing straight at it: the road the player
## walked is the one stretch of wood the world guarantees is walkable, and a squad
## that beelines at a body two hundred metres away beelines through tree rows.
## `CRUMB_STEP` is how much ground one footprint is worth, `CRUMB_KEEP` how many
## are held (600 m of road), and `ESCORT_RALLY` the distance at which a body stops
## trying to hold its ring slot and starts catching up along the line.
const CRUMB_STEP := 2.5
const CRUMB_KEEP := 240
const ESCORT_RALLY := 9.0
## How far off the line a crumb may be before an ally stops trusting it: past this
## the body is standing somewhere the soul never walked and goes its own way.
const CRUMB_GRIP := 14.0
## The line is walked forwards only. A body within `CRUMB_ARRIVE` of the footprint
## it is walking to has reached it and heads for the next; it never turns back for
## an older one. Picking the nearest footprint afresh every frame is what pinned two
## allies in the camp for the rest of the run: the soul walked to a cage and back
## the same way, so the line ran out and back over itself, and at the turn the
## nearest footprint was on the way out - the body walked to the turn, found the
## outbound footprint nearest again, and paced the same 2.5 m forever. Half a step,
## so a body on the line is always on one footprint or the next.
const CRUMB_ARRIVE := CRUMB_STEP * 0.5
## A walk the map routes round something solid. The route is planned again when the
## place it leads to has moved `ROUTE_SLACK` metres, and every `ROUTE_SECONDS`
## while the body is still on it; the body aims at the furthest of the next
## `ROUTE_LOOKAHEAD` cells it can see, so it cuts each corner the map allows.
const ROUTE_SECONDS := 0.75
const ROUTE_SLACK := 1.0
const ROUTE_LOOKAHEAD := 12
## Idle bodies take one short step and then stand: a waiting squad drifts instead of
## freezing in a heap, and stands still in between instead of pacing. Measured from
## the other direction - a squad that stepped whenever its clock ran out never
## stopped moving, and continuous small steps around a post read as circling.
const ROAM_STEP_MIN := 0.35
const ROAM_STEP_MAX := 0.60
const ROAM_REST_MIN := 2.5
const ROAM_REST_MAX := 5.0
const ROAM_RADIUS_MIN := 0.20
const ROAM_RADIUS_MAX := 0.55
const ROAM_INTENT := 0.30
const ROAM_STOP := 0.12
## True for the rest of the scene once an ally has swung at a watcher.
var engaged := false
## A hurt ally binds its wounds once the field is quiet. The dressing is the body's
## own: a squad's medicine never comes out of the player's shared stash, which is
## the player's to spend with `6`. What the squad needs beyond that is what it takes
## off the bodies it kills, and the camp's altar starts every campaign with a
## handful on the dirt.
const BANDAGE_ITEM := "bandage_linen"
const BANDAGE_SECONDS := 1.8
## Health at or below this share is worth a bandage; above it the squad keeps its
## dressings. Half the pool is deliberately the same number the revive channel
## hands back (`REVIVE_HEALTH_FRACTION`), so a squadmate that has just been stood
## up - the one that needs a dressing most - is exactly on the trigger.
const BANDAGE_HEALTH_SHARE := 0.5
## What one bandage closes, as a share of the body's own pool.
const BANDAGE_HEAL_SHARE := 0.3
## How long an ally may push without moving before it sidesteps, and for how long
## that sidestep lasts.
const BLOCKED_SECONDS := 0.35
const SIDESTEP_SECONDS := 0.55
## How long a window is before a body is asked whether it actually got anywhere.
## A sidestep is enough for a post or a wall; a body wedged between two trunks, or
## two allies shouldering each other hard enough to jitter in place, swaps left for
## right forever and never stands still - which is why the measure is NET
## displacement over a window and not a frame-to-frame step.
const POCKET_SECONDS := 2.0
## Net travel, in metres, that counts as "this errand is going somewhere" over one
## window. A jogging body covers eight; a wedged one covers a tenth of one.
const POCKET_METRES := 0.4
## How long the retreat lasts: long enough to clear a trunk's radius and step back
## into the open, short enough that a squad in a scrape never looks like it flees.
const RETREAT_SECONDS := 0.9
## How clear the field has to be before a squadmate bends over a corpse, and
## before it will stand over a downed body for five seconds. One rule for both:
## a body on the floor is only worth walking to when nothing can cut you for it.
const LOOT_CLEAR_METRES := 22.0
## How far from the soul an ally will wander to strip the field. A squad that
## leaves the escort to fetch a cultist's bow forty metres back up the road is a
## squad the player has to wait for; a squad that picks up what it walks past is
## not. Past this the loot stays on the ground and the body stays with the soul.
const LOOT_SEEK_METRES := 30.0

## A walk to a drop is a walk, not an order. A body that has not earned
## `FETCH_PROGRESS` metres of headway in `FETCH_GIVE_UP` seconds stops walking at
## that piece and the squad never offers it again - it is the whole squad's five
## seconds, not each body's, because one ally stuck on the same wall is every ally
## stuck on the same wall. Loot is the only errand that can be given up: a fight,
## a walk to the soul and the rescue are never abandoned.
##
## The camp showed what the missing rule cost: a freed squad that could not cross
## a cage wall to the shiv on the altar's dirt stood shouldering that wall for the
## rest of the session, and a run that never started had nothing to do with the
## watchers it was meant to fight. The piece stays on the ground for the player.
const FETCH_GIVE_UP := 5.0
const FETCH_PROGRESS := 0.35
## How far an ally looks for steel on the ground or a body worth stripping. Wider
## than the walk-in reach: a squad crosses the clearing for a blade.
const SEARCH_METRES := 40.0

## The fight ladder. Every frame a body spends with a hostile in range resolves
## to one of these, which is what keeps a squadmate from falling through to a
## held body while there is still something to kill.
const FIGHT_CLOSE := 0   ## walking onto the target, blade down
const FIGHT_SWING := 1   ## the blow on this frame
const FIGHT_GUARD := 2   ## a rolled guard window, shuffling in
const FIGHT_CIRCLE := 3  ## a few short steps off the line
const FIGHT_RESET := 4   ## the beat between exchanges: no guard, closing again

## The guard is a window, never a stance: the chance is rolled fresh for every
## exchange and the window is shorter than the rhythm it sits in, so an ally
## never spends the whole fight behind a raised blade.
const GUARD_CHANCE_MIN := 0.55
const GUARD_CHANCE_MAX := 0.70
const GUARD_MIN := 0.35
const GUARD_MAX := 0.80

## A circle is punctuation, not a stance: after 1-3 swings a body may take a few
## steps off the line and then lunge back in for the next blow.
##
## Every window here is long and the lateral bias is small on purpose. A body's
## facing *is* its move direction - `Archer.set_locomotion` snaps the whole rig to
## it - so a step re-rolled every tenth of a second, with a chance of reversing,
## spins the squad on the spot: four bodies whirling in little circles was the
## worst reading of a fight in the game.
const SWINGS_MIN := 1
const SWINGS_MAX := 3
const CIRCLE_CHANCE := 0.5
const CIRCLE_MIN := 0.55
const CIRCLE_MAX := 0.95
const STEP_MIN := 0.40
const STEP_MAX := 0.70
## A body never reverses its own feet: it picks a side when the circle opens and
## keeps it until the exchange is over.
const CIRCLE_REVERSE := 0.0
const CIRCLE_LATERAL_MIN := 0.22
const CIRCLE_LATERAL_MAX := 0.40
const CIRCLE_BACK_MIN := 0.18
const CIRCLE_BACK_MAX := 0.35

## The shuffle a body keeps while it holds a guard or re-forms after an exchange:
## enough movement that it reads as working the angle rather than standing still,
## small enough that the body keeps pointing at what it is fighting.
const GUARD_CLOSE := 0.55
const GUARD_SHUFFLE := 0.14
const RESET_CLOSE := 0.60
const RESET_SHUFFLE := 0.16
## How fast a squadmate may swing its heading round, in degrees per second. The
## intent is turned towards the wanted direction at this rate instead of being
## taken whole, so no roll, sidestep or separation push can snap a body through
## 90 degrees in one frame. Fast enough to come about after a knock or a break-off
## inside half a second, far below the per-frame flips that spun the squad.
const TURN_RATE := 320.0

## Clocks that run down for every ally, whatever it is doing this frame. The
## dressing clock is one of them: a bandage takes its seconds wherever the body
## is, and the channel is abandoned by walking the enemy check, not by a timer
## that keeps running behind a fight.
const TRACK_CLOCKS := ["state_left", "step_left", "side", "retreat", "heal_left", "roam_left",
	"rest_left", "route_left"]

## What a body can swing, and the narrower pair that can also set a guard. What a
## hand can hold at all is the union plus a bow, which the squad's `_armed` test
## asks before anything else.
const BLADES := ["sword", "dagger", "dual"]
const GUARD_BLADES := ["sword", "dagger"]
const HELD_WEAPONS := ["sword", "dagger", "dual", "bow"]
## The two phases in which a bow's string is up.
const DRAW_PHASES := ["DRAWING", "HOLDING"]

## per merc_id: the blocked push, the current fight state, and this body's own
## rolls. Nothing here is read off the instance id: two allies in the same gear
## circle on different beats because each rolled for itself.
var _track: Dictionary = {}
## The mercenary standing over a downed soul this frame, or 0. The rescue owns that
## body's intent, so the fight ladder skips it.
var _rescuer_merc := 0
## The heading each body is turned to this frame, so the next one can be limited
## against it: merc_id -> flat unit vector.
var _heading: Dictionary = {}
## Drops and bodies the squad has given up on: target key -> true. Per scene, so a
## reloaded world offers the same piece again; a key is `_pickup_key` or
## `_corpse_key` and never a position, because a piece that moved is still the same
## piece and a point is not an identity.
var _abandoned: Dictionary = {}


## Point the module at a warband and the controller that owns its bodies.
func setup(warband_state, soul_controller, loot_vacuum) -> void:
	warband = warband_state
	controller = soul_controller
	loot = loot_vacuum


## One frame of squad intent. Called before `controller.physics_step` so the
## brains have written a body's intent for the tick that integrates it.
func drive(delta: float) -> void:
	if controller == null or warband == null:
		return
	# The body the squad walks with: the soul's own, or - while the soul watches
	# a co-op friend in the last body standing - that one.
	player_body = controller.focus_body()
	_drop_crumb()
	if _rescue_step(delta):
		# The rescue has already written its rescuer's intent for this frame; the
		# rest of the squad still gets its turn below.
		pass
	for raw_id in squad_ids:
		var merc_id := int(raw_id)
		if not _is_free(merc_id):
			continue
		var actor = controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor):
			continue
		# The soul's own body is the player's business, never the AI's.
		if actor == player_body:
			continue
		# The alley already walking or standing over the soul is not fighting.
		if merc_id == _rescuer_merc:
			continue
		if not bool(actor.get("alive")) or bool(actor.get("downed")):
			_hold(actor)
			continue
		actor.combat.damage_enabled = true
		var track := _track_for(merc_id, actor, delta)
		# 0. A hurt ally binds its wounds when nothing is close enough to punish
		#    it. The channel is the squad's own: no announcement, no prompt.
		if _bandage_step(actor, merc_id, track, delta):
			continue
		# 1. An unarmed ally looks for steel first: the steel is how a prisoner
		#    becomes a fighter, not a buff the scene hands out. A weapon on the
		#    ground is worth the walk; a rag or a ring is not. A walk that stops
		#    getting anywhere is abandoned and the body is on to its next errand on
		#    the same frame (`_walk_to_loot`), so a blade on the far side of a wall
		#    costs the squad one wait, not its session.
		if not _armed(actor, merc_id):
			var steel = _nearest_weapon_pickup(actor)
			if steel != null:
				if _in_loot_reach(actor, steel.global_position):
					_hold(actor)
					_take(actor, merc_id, steel)
					continue
				if _walk_to_loot(actor, steel.global_position, _pickup_key(steel), track):
					continue
			var armed_body := _nearest_corpse_with_weapon(actor)
			if armed_body != 0:
				var held_at: Vector3 = loot.corpse_position(armed_body)
				if _clear_of_hostiles(held_at):
					if _in_loot_reach(actor, held_at):
						_hold(actor)
						_strip_weapon(actor, merc_id, armed_body)
						continue
					if _walk_to_loot(actor, held_at, _corpse_key(armed_body), track):
						continue
		# 2. Armed, or nothing left to grab: go at the nearest watcher.
		var watcher = _nearest_watcher(actor)
		if watcher != null:
			# Finding one is when the party talks. The latch makes it the moment
			# this body goes from out of the fight to in it - the first hostile to
			# come inside `engage_radius` since it was last clear - not every
			# frame of the fight and not the third target in a scrum. How rare
			# the line is belongs to the row (`VoiceLibrary.SQUAD.aggro`).
			if not bool(track.get("engaged", false)):
				actor.voice_aggro()
			track["engaged"] = true
			# Held for the notifier: `engaged_allies()` reads it back so the band
			# can say what an ally went in on, not just that it left.
			track["threat"] = watcher
			_fight(actor, watcher, track)
			continue
		track["engaged"] = false
		track["threat"] = null
		# 3. Nothing hostile close: check the bodies. A squad strips the field when
		#    the fighting has stopped, never mid-swing - and never further from the
		#    soul than an escort may stray to do it.
		if _clear_of_hostiles(actor.global_position) and _near_soul(actor):
			var spoil = _nearest_pickup(actor)
			if spoil != null:
				if _in_loot_reach(actor, spoil.global_position):
					_hold(actor)
					_take(actor, merc_id, spoil)
					continue
				if _walk_to_loot(actor, spoil.global_position, _pickup_key(spoil), track):
					continue
			var fallen := _nearest_corpse(actor)
			# The body has to be clear in its own right, not just the body
			# walking to it: the rule is about the fight near the corpse.
			if fallen != 0 and loot.has_corpse(fallen):
				var at: Vector3 = loot.corpse_position(fallen)
				if _clear_of_hostiles(at):
					if _in_loot_reach(actor, at):
						_hold(actor)
						_claim(fallen)
						continue
					if _walk_to_loot(actor, at, _corpse_key(fallen), track):
						continue
		# 4. No fight: an escort stands on its own slot in the ring around the
		#    soul, and a squad with nowhere to be roams its own post in small
		#    steps. Nobody walks onto the soul, and nothing stands still.
		if following and is_instance_valid(player_body):
			# Far behind, the soul's line outranks the ring slot: walking the way the
			# player walked is what keeps a squad together in a wood this size. On
			# mapped ground the map already knows the way round, so the body goes
			# straight for its slot instead of retracing every turn the soul took.
			var soul_at: Vector3 = (player_body as Node3D).global_position
			var to_soul: Vector3 = soul_at - actor.global_position
			to_soul.y = 0.0
			if to_soul.length() > ESCORT_RALLY and not _mapped(actor.global_position, soul_at):
				var crumb: Variant = _crumb_for(actor, track)
				if crumb != null:
					track["to_post"] = true
					_advance(actor, crumb, track, 0.9)
					continue
			# Off the line: the next time this body falls behind it rejoins from
			# where it stands, not from a footprint it left a fight ago.
			track["crumb"] = -1
			var post := _escort_post(actor, track)
			var gap: Vector3 = post - actor.global_position
			gap.y = 0.0
			var walking := bool(track.get("to_post", false))
			if gap.length() > (ESCORT_STANDOFF if walking else ESCORT_ENGAGE):
				track["to_post"] = true
				_advance(actor, post, track, ESCORT_STANDOFF)
				continue
			track["to_post"] = false
		_idle_roam(actor, track)



## How many free squadmates are actually holding something. The roster alone is
## not the answer: a body can outlive the gear the roster says it wears.
func armed_count() -> int:
	if controller == null or warband == null:
		return 0
	var count := 0
	var soul_body = controller.focus_body()
	for raw_id in squad_ids:
		var merc_id := int(raw_id)
		if not _is_free(merc_id):
			continue
		var actor = controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor):
			continue
		if actor == soul_body or not bool(actor.get("alive")):
			continue
		var gear: Dictionary = warband.roster.equipped_of(merc_id)
		var in_roster := not str(gear.get("main", "")).is_empty() \
			or not str(gear.get("off", "")).is_empty()
		if in_roster and _holds_weapon(actor):
			count += 1
	return count


# --- the notifier's facts ---------------------------------------------------

## Every ally that is in a fight right now, as the HUD reads it: who broke off,
## what it went in on, how far it is from the soul and which way the player would
## have to turn.
##
## The squad forked in silence before this. `voice_aggro()` is the only cue a
## break-off had, and the row rolls that line at one in a hundred, so the player
## learned the band was gone by turning round and finding it a hundred metres
## back. This is the fact the notifier paints - nothing here is announced from the
## AI, and a body that stops swinging leaves the list on the same frame.
##
## Rows: `{merc_id, name, threat, distance, bearing}`. Empty while the band is
## whole, and empty while the soul is between bodies: a split needs somebody to be
## split from.
func engaged_allies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if controller == null or warband == null:
		return out
	var soul = controller.active_body(1)
	if soul == null or not is_instance_valid(soul):
		return out
	var forward := _view_forward(soul)
	var soul_at: Vector3 = (soul as Node3D).global_position
	for raw_id in squad_ids:
		var merc_id := int(raw_id)
		if not _is_free(merc_id):
			continue
		var actor = controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor) or actor == soul:
			continue
		# Only a standing body is in a fight; a downed ally is the wipe's problem,
		# and the banner that names a downed body is the scene's own.
		if not bool(actor.get("alive")) or bool(actor.get("downed")):
			continue
		var track: Variant = _track.get(merc_id, null)
		if not (track is Dictionary) or not bool((track as Dictionary).get("engaged", false)):
			continue
		var offset: Vector3 = (actor as Node3D).global_position - soul_at
		out.append({
			"merc_id": merc_id,
			"name": warband.roster.name_of(merc_id),
			"threat": _threat_name((track as Dictionary).get("threat")),
			"distance": int(round(Vector3(offset.x, 0.0, offset.z).length())),
			"bearing": bearing_word(forward, offset),
		})
	return out


## What a squadmate is fighting, in the words the game already uses for it. A
## threat that died or left the tree during the frame is still named: the body did
## go in on something, and "something in the wood" beats an empty word.
static func _threat_name(threat) -> String:
	if not is_instance_valid(threat):
		return "something in the wood"
	if threat.has_method("get_display_name"):
		var named := str(threat.call("get_display_name"))
		if not named.is_empty():
			return named
	return str((threat as Node).name)


## The way the player's eye is pointing, flat. The camera owns the aim ray, so
## "behind you" means behind the view and not behind the feet of a body that is
## walking sideways; a harness with no camera falls back to the soul's facing.
func _view_forward(soul) -> Vector3:
	if controller != null and controller.has_method("view_forward"):
		var aimed: Variant = controller.call("view_forward")
		if typeof(aimed) == TYPE_VECTOR3 and (aimed as Vector3).length_squared() > 0.01:
			return (aimed as Vector3).normalized()
	if soul is Node3D:
		return -(soul as Node3D).global_basis.z
	return Vector3.FORWARD


## The word for where a point lies relative to the way the player is looking:
## eight sectors, so the notifier can say "34 m back-left" and mean a place to turn
## to. A positive angle is to the player's left (Godot's `signed_angle_to` measures
## against `UP`, so a target on the right answers negative).
static func bearing_word(forward: Vector3, offset: Vector3) -> String:
	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() < 0.0001:
		return "here"
	var heading := Vector3(forward.x, 0.0, forward.z)
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD
	var angle := rad_to_deg(heading.normalized().signed_angle_to(flat.normalized(),
		Vector3.UP))
	var side := "left" if angle > 0.0 else "right"
	var magnitude := absf(angle)
	if magnitude <= 22.5:
		return "ahead"
	if magnitude <= 67.5:
		return "ahead-" + side
	if magnitude <= 112.5:
		return side
	if magnitude <= 157.5:
		return "back-" + side
	return "behind"


## Point every living watcher at the nearest standing squad body and put it on
## the hunt. Shared because a watcher that has calmed down is a scene bug in both
## the camp and the run, and the answer is the same in both.
##
## `radius` bounds how far a watcher will take a *new* target. In the one world
## the camp's guards, the six that come out of the trees and the road's cultists
## all live on one list, so without a bound a watcher in the camp would run the
## whole nine hundred metres of trail after a squad that had already left it - and
## the road's cultists would come up to the town to fight. A watcher already hunting
## is left alone: this only decides who it notices.
static func retarget(watchers: Array, bodies: Array, radius: float = INF) -> void:
	for watcher in watchers:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		var nearest = null
		var best := INF
		for body in bodies:
			if not is_instance_valid(body) or not bool(body.get("alive")):
				continue
			if bool(body.get("downed")):
				continue
			var distance: float = body.global_position.distance_to(watcher.global_position)
			if distance < best:
				best = distance
				nearest = body
		if nearest == null:
			continue
		if radius < INF and watcher.global_position.distance_to(nearest.global_position) > radius:
			continue
		watcher.player = nearest
		# `hunt` only re-arms the senses when the pursuit lapsed, so calling it
		# every frame never resets a watcher that is already running somebody down.
		if not bool(watcher.hunting()):
			watcher.hunt(nearest)


# --- answers ---------------------------------------------------------------

func _is_free(merc_id: int) -> bool:
	if merc_id <= 0:
		return false
	if not eligible.is_valid():
		return true
	return bool(eligible.call(merc_id))


## Whether the body is actually swinging something: the rig, not the roster. A
## body whose roster says armed but whose hands are empty is wearing a stale
## loadout, so it is re-dressed once instead of being written off as unarmed.
func _armed(actor, merc_id: int) -> bool:
	var gear: Dictionary = warband.roster.equipped_of(merc_id)
	var roster_armed := not str(gear.get("main", "")).is_empty() \
		or not str(gear.get("off", "")).is_empty()
	if roster_armed and not _holds_weapon(actor):
		controller.refresh_gear(merc_id)
	return roster_armed and _holds_weapon(actor)


func _holds_weapon(actor) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if str(actor.rig.weapon) in HELD_WEAPONS:
		return true
	return bool(actor.rig.staff_active) or bool(actor.rig.off_weapon_active)


## Whether a blow could start on this frame: the same gate `Combat.begin_melee`
## applies, asked *before* the exchange is rolled so a body still recovering is
## never handed a guard window it did not earn.
func _blade_free(actor) -> bool:
	if str(actor.rig.weapon) not in BLADES:
		return false
	return float(actor.combat.clash_cooldown) <= 0.0 \
		and float(actor.combat.attack_progress) >= 0.999 \
		and bool(actor.rig.can_begin_melee("right"))


## Only a blade can set a guard: `Combat.start_block` refuses a bow, a staff and a
## dual pair, so a body that cannot guard never spends an exchange on one.
func _can_guard(actor) -> bool:
	return str(actor.rig.weapon) in GUARD_BLADES


func _nearest_pickup(actor):
	var best = null
	var best_distance := SEARCH_METRES
	for pickup in pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		if _abandoned.has(_pickup_key(pickup)):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup
	return best


## The nearest piece on the ground that could actually be a weapon. An unarmed
## ally is not walking across a clearing for a rag, a ring or a bundle: those are
## the stash's business and somebody else's walk.
func _nearest_weapon_pickup(actor):
	var best = null
	var best_distance := SEARCH_METRES
	for pickup in pickups:
		if not is_instance_valid(pickup) or bool(pickup.collected):
			continue
		if _abandoned.has(_pickup_key(pickup)):
			continue
		if not WarbandPickup.is_weapon(str(pickup.item_id)):
			continue
		var distance: float = actor.global_position.distance_to(pickup.global_position)
		if distance < best_distance:
			best_distance = distance
			best = pickup
	return best


## The nearest body still carrying a weapon in its own record, or 0. A corpse
## registers the kit it fell with, so a watcher that was killed before this
## module existed still has steel on it.
func _nearest_corpse_with_weapon(actor) -> int:
	if loot == null or not loot.has_method("corpse_items"):
		return 0
	var best := 0
	var best_distance := SEARCH_METRES
	for corpse_id in loot.corpse_ids():
		var id := int(corpse_id)
		if _abandoned.has(_corpse_key(id)):
			continue
		var has_weapon := false
		for item_id in loot.corpse_items(id):
			if WarbandPickup.is_weapon(str(item_id)):
				has_weapon = true
				break
		if not has_weapon:
			continue
		var distance: float = actor.global_position.distance_to(loot.corpse_position(id))
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


## Take only the blade off a body - the rag and the rest stay on it for whoever
## searches it properly - and wear it. The piece is booked into the shared stash
## first, exactly as every take is, so the warband's worth never disagrees.
func _strip_weapon(actor, merc_id: int, corpse_id: int) -> void:
	if loot == null or not loot.has_method("take_from_corpse"):
		return
	for item_id in loot.corpse_items(corpse_id):
		var id := str(item_id)
		if not WarbandPickup.is_weapon(id):
			continue
		var result: Dictionary = loot.take_from_corpse(corpse_id, id, 0)
		if not bool(result.get("ok", false)):
			continue
		warband.auto_equip(merc_id, id)
		controller.refresh_gear(merc_id)
		actor.combat.stop()
		return


# --- the rescue ------------------------------------------------------------

## The squad picks a body up. A downed squadmate is not a corpse: with the field
## clear of hostiles, the nearest ally standing on its feet walks over, stands
## inside the revival reach and opens the scene's channel on the squad's own hands
## (`ReviveChannel.ALLY_PEER`). Five seconds later the body stands up on a
## twentieth of its pool - enough to walk out, not enough to fight on.
##
## The body it saves is *any* downed squadmate's, not only the one the soul is
## inside. The soul hops bodies as soon as it likes, and a downed mercenary whose
## soul is elsewhere is still the warband's to pick up; when the soul is the body
## on the floor it is simply first in line.
##
## Nothing here is announced and nothing here is a quota: a hostile inside
## `LOOT_CLEAR_METRES` drops the work instantly, and the mercenary goes back to the
## fight with the squad. Answers true when the rescue owns this frame.
func _rescue_step(delta: float) -> bool:
	_rescuer_merc = 0
	if revive == null or controller == null:
		return false
	var patient = _rescue_patient()
	# The channel is only ever open because a body is down and the field is clear;
	# anything else closes it and the squad goes back to what it was doing.
	if patient == null:
		revive.cancel(ReviveChannel.ALLY_PEER)
		return false
	if not _clear_of_hostiles((patient as Node3D).global_position):
		revive.cancel(ReviveChannel.ALLY_PEER)
		return false
	var rescuer = _rescue_ally(patient)
	if rescuer == null:
		revive.cancel(ReviveChannel.ALLY_PEER)
		return false
	var merc_id := int(controller.merc_of(rescuer))
	_rescuer_merc = merc_id
	var track := _track_for(merc_id, rescuer, delta)
	var gap: Vector3 = (patient as Node3D).global_position - (rescuer as Node3D).global_position
	gap.y = 0.0
	var stand := maxf(0.35, float(revive.reach) - 0.35)
	if gap.length() > stand:
		# Walk to the body, stopping inside the reach that opens the channel.
		_advance(rescuer, (patient as Node3D).global_position, track, stand)
		revive.cancel(ReviveChannel.ALLY_PEER)
		return true
	_hold(rescuer)
	if revive.channeling(ReviveChannel.ALLY_PEER) \
			and revive.target_of(ReviveChannel.ALLY_PEER) == patient:
		return true
	revive.cancel(ReviveChannel.ALLY_PEER)
	revive.begin_ally(rescuer, patient)
	return true


## The downed squadmate to save: the body the soul is inside if it is on the floor,
## otherwise the downed body nearest a standing ally. 0 candidates answers null.
func _rescue_patient():
	var candidates: Array = []
	for raw_id in squad_ids:
		var merc_id := int(raw_id)
		if not _is_free(merc_id):
			continue
		var body = controller.body_of(merc_id)
		if body == null or not is_instance_valid(body):
			continue
		if not bool(body.get("downed")) or not bool(body.get("alive")):
			continue
		candidates.append(body)
	if candidates.is_empty():
		return null
	if is_instance_valid(player_body) and candidates.has(player_body):
		return player_body
	var best = null
	var best_distance := INF
	for body in candidates:
		for raw_id in squad_ids:
			var ally = controller.body_of(int(raw_id))
			if ally == null or not is_instance_valid(ally) or ally == body:
				continue
			if not bool(ally.get("alive")) or bool(ally.get("downed")):
				continue
			var distance: float = (ally as Node3D).global_position.distance_to(
				(body as Node3D).global_position)
			if distance < best_distance:
				best_distance = distance
				best = body
	return best if best != null else candidates[0]


## The ally that does the picking up: the nearest free squadmate on its feet, so
## the body closest to the patient is the one that stops.
func _rescue_ally(patient):
	if controller == null:
		return null
	var best = null
	var best_distance := INF
	for raw_id in squad_ids:
		var merc_id := int(raw_id)
		if not _is_free(merc_id):
			continue
		var actor = controller.body_of(merc_id)
		if actor == null or not is_instance_valid(actor) or actor == patient:
			continue
		if not bool(actor.get("alive")) or bool(actor.get("downed")):
			continue
		var distance: float = (actor as Node3D).global_position.distance_to(
			(patient as Node3D).global_position)
		if distance < best_distance:
			best_distance = distance
			best = actor
	return best


# --- field medicine --------------------------------------------------------

## One frame of a hurt ally's own dressing. Answers true when the bandage owns
## this frame's intent: the channel has just started, is still running, or has
## just closed a wound. A hostile inside `LOOT_CLEAR_METRES` drops the work
## unfinished.
func _bandage_step(actor, merc_id: int, track: Dictionary, _delta: float) -> bool:
	if bool(track.get("bandaging", false)):
		if not _clear_of_hostiles(actor.global_position):
			# Interrupted: nothing was spent.
			track["bandaging"] = false
			track["heal_left"] = 0.0
			return false
		if float(track.get("heal_left", 0.0)) > 0.0:
			_hold(actor)
			return true
		track["bandaging"] = false
		_finish_bandage(actor, merc_id)
		return false
	if not _wants_bandage(actor, merc_id):
		return false
	if not _clear_of_hostiles(actor.global_position):
		return false
	track["bandaging"] = true
	track["heal_left"] = BANDAGE_SECONDS
	_hold(actor)
	actor.combat.stop()
	return true


## Hurt enough to spend a dressing - half the pool or less, which is where a body
## comes back from the floor - on a body that can still be saved.
func _wants_bandage(actor, merc_id: int) -> bool:
	if warband == null:
		return false
	if not warband.roster.is_alive(merc_id):
		return false
	var pool := float(actor.get("max_health"))
	if pool <= 0.0:
		return false
	return float(actor.get("health")) <= pool * BANDAGE_HEALTH_SHARE


## Close the wound: the body gets its share of its own pool back, and the roster is
## written on the same frame so a save taken mid-battle records the patched body,
## not the wound. Nothing leaves the shared stash - that is the player's.
func _finish_bandage(actor, merc_id: int) -> void:
	if warband == null:
		return
	var pool := float(actor.get("max_health"))
	var healed := minf(pool, float(actor.get("health")) + pool * BANDAGE_HEAL_SHARE)
	actor.health = healed
	warband.roster.set_health(merc_id, healed)
	warband.changed.emit()


## The nearest fallen body this ally may search, or 0 for none. The vacuum holds
## the bodies a scene registered (`register_corpse`) and stops offering one it has
## already been emptied, so the module asks it rather than keeping corpses of its
## own - and a scene whose vacuum predates `claim_corpse` simply has nothing to
## offer, which leaves the squad's fight and escort untouched.
##
## Walked by hand rather than through `corpse_at` so a body the squad has given up
## on is not the answer: the next reachable one is, which a single nearest-body
## query cannot express.
func _nearest_corpse(actor) -> int:
	if loot == null or not loot.has_method("claim_corpse"):
		return 0
	if not loot.has_method("corpse_ids"):
		return 0
	var best := 0
	var best_distance := SEARCH_METRES
	for corpse_id in loot.corpse_ids():
		var id := int(corpse_id)
		if _abandoned.has(_corpse_key(id)):
			continue
		var distance: float = actor.global_position.distance_to(loot.corpse_position(id))
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


## True when no living cultist is close enough to interrupt a body bending over a
## corpse. `LOOT_CLEAR_METRES` is wider than the reach, so a squad does not strip
## gear in the middle of a ring. Measured at the thing being looted - the drop or
## the body - because that is where the fight would have to be over.
func _clear_of_hostiles(point: Vector3) -> bool:
	for watcher in watchers:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		if point.distance_to(watcher.global_position) <= LOOT_CLEAR_METRES:
			return false
	return true


func _nearest_watcher(actor):
	var best = null
	var best_distance := engage_radius
	for watcher in watchers:
		if not is_instance_valid(watcher) or not bool(watcher.get("alive")):
			continue
		var distance: float = actor.global_position.distance_to(watcher.global_position)
		if distance < best_distance:
			best_distance = distance
			best = watcher
	return best


# --- intent ----------------------------------------------------------------

func _fight(actor, watcher, track: Dictionary) -> void:
	var to: Vector3 = watcher.global_position - actor.global_position
	to.y = 0.0
	var distance := to.length()
	var direction := to.normalized() if distance > 0.001 else Vector3.FORWARD
	actor.combat.set_aim(watcher.get_aim_position())
	var state := int(track.get("state", FIGHT_CLOSE))
	var left := float(track.get("state_left", 0.0))
	# A window that is still running is what the body is doing this frame. A
	# circle keeps its steps even when they carry the body just outside reach:
	# cutting it short is what made a break-off read as a stumble.
	if state == FIGHT_CIRCLE and left > 0.0:
		_circle_step(actor, direction, track)
		return
	# A guard holds from slightly beyond reach too - a body does not drop its
	# blade the instant its target steps back - but a target that has broken
	# clean away is a chase, and a chase is not shielded.
	if state == FIGHT_GUARD and left > 0.0 and distance <= reach * 1.35:
		_guard_step(actor, direction, track, distance)
		return
	# A window that has run out is the body's own signal to attack: the guard
	# drops to the swing, and a circle ends in the lunge back in.
	if state == FIGHT_GUARD or state == FIGHT_CIRCLE:
		actor.combat.stop_block()
		track["swing_due"] = true
	# Out of reach there is nothing to strike: close in to the standoff and stop
	# there. A fighter that walks to the mob's own origin leans on it, and a squad
	# of them shoves a whole pack across the clearing.
	var standoff := _standoff_for(actor)
	if distance > standoff:
		_enter(track, FIGHT_CLOSE)
		actor.combat.stop_block()
		_advance(actor, watcher.global_position, track, standoff)
		return
	if str(actor.rig.weapon) == "bow":
		_fight_bow(actor, track, direction)
		return
	# An exchange this body has already rolled and not yet landed: swing the
	# moment the blade is free. Re-rolling here is how a body that cannot swing
	# this frame ends up guarding forever.
	if not bool(track.get("swing_due", false)) and _blade_free(actor):
		_roll_exchange(actor, track)
		var rolled := int(track.get("state", FIGHT_CLOSE))
		if not bool(track.get("swing_due", false)) and rolled == FIGHT_GUARD:
			# Show the window on the frame it opens, so a guard is never an
			# invisible state that only exists in a timer.
			_guard_step(actor, direction, track, distance)
			return
		if not bool(track.get("swing_due", false)) and rolled == FIGHT_CIRCLE:
			_circle_step(actor, direction, track)
			return
	if _swing(actor, track, direction):
		return
	_enter(track, FIGHT_CLOSE)
	actor.combat.stop_block()
	_close_step(actor, direction, track, distance)



## What this exchange is, rolled once at the moment the blade comes free, which is
## the only moment the choice costs anything. A guard is drawn with a fresh chance
## every exchange - never a cooldown-gated certainty - and the blow is never
## withheld, only delayed by the short window it was rolled behind.
func _roll_exchange(actor, track: Dictionary) -> void:
	if _can_guard(actor) and _rng.randf() < _rng.randf_range(GUARD_CHANCE_MIN, GUARD_CHANCE_MAX):
		_enter(track, FIGHT_GUARD, _rng.randf_range(GUARD_MIN, GUARD_MAX))
		return
	if int(track.get("swings_left", 0)) <= 0:
		track["swings_left"] = _rng.randi_range(SWINGS_MIN, SWINGS_MAX)
		if _rng.randf() < CIRCLE_CHANCE:
			_begin_circle(track)
			return
	track["swing_due"] = true


## The blow itself. False means the blade was not free this frame, so the caller
## keeps the body moving instead of pretending a swing happened.
func _swing(actor, track: Dictionary, direction: Vector3) -> bool:
	if not _blade_free(actor):
		return false
	# A dagger swings its stab, not the overhead chop: that is the variant the
	# item's own passive speeds up (Prison shank, +200%), and it is what makes
	# a shiv a shiv. Every other blade keeps the overhead.
	var variant := "stab" if str(actor.rig.weapon) == "dagger" else "overhead"
	actor.combat.stop_block()
	if not actor.combat.begin_melee("right", variant):
		return false
	engaged = true
	track["swing_due"] = false
	track["swings_left"] = int(track.get("swings_left", 0)) - 1
	_enter(track, FIGHT_SWING)
	# The swing is a step as well as a cut: the body keeps its weight going in
	# rather than cutting from a standstill.
	_steer(actor, direction, track, false)
	return true


## A bow cannot guard and cannot swing, so it keeps the draw/hold/release path and
## spends the beat between shots on a step. Only a string that is up plants the
## feet: a draw cannot be rushed.
func _fight_bow(actor, track: Dictionary, direction: Vector3) -> void:
	if actor.combat.can_draw():
		_enter(track, FIGHT_SWING)
		_hold(actor)
		actor.combat.begin_draw()
		return
	if str(actor.rig.phase) in DRAW_PHASES or float(actor.rig.draw_amount) > 0.0:
		_enter(track, FIGHT_SWING)
		_hold(actor)
		if float(actor.rig.draw_amount) >= 0.85:
			actor.combat.release_draw()
		return
	# The beat between shots is the same short steps a blade's circle uses, but it
	# is not a circle: a bow is never breaking off, so it must not leave a window
	# clock behind for the melee ladder to read.
	_enter(track, FIGHT_RESET)
	_circle_step(actor, direction, track)


## A break-off beat: a quarter to a half second of steps, each with its own
## direction and length, then the body lunges back in on the target for its next
## blow - the clear-distance check above turns the end of the circle into a run.
func _begin_circle(track: Dictionary) -> void:
	_enter(track, FIGHT_CIRCLE, _rng.randf_range(CIRCLE_MIN, CIRCLE_MAX))
	_roll_step(track)


## One step of a circle. A reversal is possible on any step but is not the norm: a
## body that flips every step reads as a glitch, one that never does reads as a
## script.
func _roll_step(track: Dictionary) -> void:
	var orbit := float(track.get("orbit", 1.0))
	if _rng.randf() < CIRCLE_REVERSE:
		orbit = -orbit
	track["orbit"] = orbit
	track["lateral"] = _rng.randf_range(CIRCLE_LATERAL_MIN, CIRCLE_LATERAL_MAX)
	track["back"] = _rng.randf_range(CIRCLE_BACK_MIN, CIRCLE_BACK_MAX)
	track["step_left"] = _rng.randf_range(STEP_MIN, STEP_MAX)


## Sideways with a backward bias, re-rolled every step, so the path is rugged and
## very short instead of an orbit.
func _circle_step(actor, direction: Vector3, track: Dictionary) -> void:
	if float(track.get("step_left", 0.0)) <= 0.0:
		_roll_step(track)
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	var intent := across * float(track.get("lateral", 0.7)) \
		- direction * float(track.get("back", 0.35))
	_steer(actor, intent, track, false)


## The guard window: up, pointed at the target, and the body still walking its
## angle in. The block is raised once and dropped by the swing that follows. The
## walk in is the same standoff the closing step keeps: a guard is a blade in the
## way, not a body driving its shoulder into the target.
func _guard_step(actor, direction: Vector3, track: Dictionary, distance: float = STANDOFF) -> void:
	if not actor.combat.blocking:
		actor.combat.start_block(direction)
	actor.combat.face_block(direction)
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	_steer(actor, direction * GUARD_CLOSE * _press(distance) + across * GUARD_SHUFFLE,
		track, false)


## The beat between exchanges with no guard up: work the angle from the standoff,
## never lean on the body in front of it.
func _close_step(actor, direction: Vector3, track: Dictionary, distance: float = STANDOFF) -> void:
	var across := direction.cross(Vector3.UP) * float(track.get("orbit", 1.0))
	_steer(actor, direction * RESET_CLOSE * _press(distance) + across * RESET_SHUFFLE,
		track, false)


## Where this body wants to stand: its own blade's reach, less a hand's width -
## a shiv does not stand where a two-hander does - kept between `MIN_GAP` and
## `STANDOFF` so no weapon pushes and none stands out of its own swing.
func _standoff_for(actor) -> float:
	var wanted := STANDOFF
	var rig = actor.get("rig")
	if rig != null and is_instance_valid(rig) and rig.has_method("profile_for_hand"):
		var profile: Dictionary = rig.profile_for_hand("right")
		var blade_reach := float(profile.get("reach", 0.0))
		if blade_reach > 0.0:
			wanted = clampf(blade_reach * 0.78, MIN_GAP + 0.15, STANDOFF)
	return wanted


## How much of a forward step the distance allows: 1 at the outer edge of the
## standoff, 0 across the whole range a body should be holding, and a negative
## share when the press has carried it inside `MIN_GAP`, which walks it back out.
func _press(distance: float) -> float:
	if distance >= STANDOFF:
		return 1.0
	if distance <= MIN_GAP:
		return -0.9
	return 0.0


## Put the body in a fight state, with the window it holds when the state has one.
func _enter(track: Dictionary, state: int, seconds: float = 0.0) -> void:
	track["state"] = state
	track["state_left"] = seconds


# --- fetching a drop -------------------------------------------------------

## Whether a body is close enough to take what it walked to. One predicate for
## both halves of the trip, so a walk that ends and a hand that reaches are the
## same moment.
func _in_loot_reach(actor, point: Vector3) -> bool:
	return actor.global_position.distance_to(point) <= loot_reach


## The key a drop is remembered by. Instance ids live as long as the node does,
## which is as long as the piece is on the floor.
func _pickup_key(pickup) -> String:
	return "p%d" % pickup.get_instance_id()


func _corpse_key(corpse_id: int) -> String:
	return "c%d" % corpse_id


## The squad has given up on a target: it leaves every selector at once, because
## the wall that stopped one body stops the next.
func _abandon(key: String) -> void:
	_abandoned[key] = true


## Walk to a drop or a body, and stop walking when it stops being reachable.
## Answers true while the trip owns this frame; false the frame it is given up, so
## the caller can fall through to its next errand without repeating the walk.
##
## `FETCH_PROGRESS` metres closer is what counts as getting somewhere - a body
## shuffling along a wall at a crawl earns nothing and loses its trip - and the
## clock is the body's own, so a fight that interrupts a walk does not spend it.
func _walk_to_loot(actor, point: Vector3, key: String, track: Dictionary) -> bool:
	if _abandoned.has(key):
		return false
	var distance: float = actor.global_position.distance_to(point)
	if str(track.get("fetch_key", "")) != key:
		track["fetch_key"] = key
		track["fetch_best"] = distance
		track["fetch_left"] = FETCH_GIVE_UP
	elif distance <= float(track["fetch_best"]) - FETCH_PROGRESS:
		track["fetch_best"] = distance
		track["fetch_left"] = FETCH_GIVE_UP
	else:
		track["fetch_left"] = float(track.get("fetch_left", FETCH_GIVE_UP)) \
			- float(track.get("delta", 0.0))
		if float(track["fetch_left"]) <= 0.0:
			track["fetch_key"] = ""
			_abandon(key)
			return false
	_advance(actor, point, track, loot_reach)
	return true


## Walk or jog to a point, stopping `stop_at` short of it. A drop, a corpse and
## the soul are places to stand next to; a watcher is a body to stand *away* from.
## On mapped ground the walk goes round what stands in the way (`_route_aim`); the
## stop is still measured to the point itself.
func _advance(actor, point: Vector3, track: Dictionary, stop_at: float = 0.0) -> void:
	var to: Vector3 = point - actor.global_position
	to.y = 0.0
	var gap := to.length() - maxf(stop_at, 0.0)
	if gap <= 0.08 or to.length_squared() <= 0.0001:
		_hold(actor)
		return
	# Walking is not fighting: a guard left up while crossing the yard to a drop
	# would be a pose nobody set.
	actor.combat.stop_block()
	var heading: Vector3 = _route_aim(actor, point, track) - actor.global_position
	heading.y = 0.0
	if heading.length_squared() <= 0.0001:
		heading = to
	# Far out is a jog; the last few metres into contact are a walk, so a squad
	# arrives beside a body instead of running it over.
	_steer(actor, heading.normalized(), track, gap > RUN_GAP)


## Whether the map covers both ends of a walk.
func _mapped(from: Vector3, to: Vector3) -> bool:
	return nav != null and nav.covers(from) and nav.covers(to)


## Where a walk to `point` aims this frame: straight at it off the map, or when
## nothing the map knows of stands in the line; otherwise at the furthest of the
## next `ROUTE_LOOKAHEAD` cells of a route round it that the body can see from
## where it stands. The route is kept on the track and planned again when the
## point moves or the route grows old, so a chase round a cage follows the body
## it is chasing.
func _route_aim(actor, point: Vector3, track: Dictionary) -> Vector3:
	var here: Vector3 = (actor as Node3D).global_position
	if not _mapped(here, point) or nav.clear_line(here, point):
		# Clear ground: the next blocked line plans on its first frame.
		track["route"] = PackedVector3Array()
		track["route_left"] = 0.0
		return point
	var route: PackedVector3Array = track.get("route", PackedVector3Array())
	var planned: Vector3 = track.get("route_goal", point)
	var moved := Vector2(planned.x - point.x, planned.z - point.z).length()
	# The clock, not an empty answer, decides when to ask again: a goal the map
	# cannot reach answers empty, and asking every frame searches the whole map
	# every frame.
	if float(track.get("route_left", 0.0)) <= 0.0 or moved > ROUTE_SLACK:
		route = nav.route(here, point)
		track["route"] = route
		track["route_goal"] = point
		track["route_left"] = ROUTE_SECONDS
		track["route_at"] = 0
	if route.is_empty():
		return point
	var at := clampi(int(track.get("route_at", 0)), 0, route.size() - 1)
	for index in range(at + 1, mini(route.size(), at + 1 + ROUTE_LOOKAHEAD)):
		if not nav.clear_line(here, route[index]):
			break
		at = index
	track["route_at"] = at
	return route[at]


## One intent write for every kind of movement the squad makes. A body whose push
## is going nowhere takes the sidestep instead, so a squadmate caught on a wall
## tries both ways round rather than shouldering it for the rest of the fight.
func _steer(actor, direction: Vector3, track: Dictionary, running: bool) -> void:
	if float(track.get("retreat", 0.0)) > 0.0:
		# Back out of the pocket first; the sidestep and the heading wait until the
		# body is clear of whatever it walked into.
		direction = -direction
	elif float(track.get("side", 0.0)) > 0.0:
		direction = direction.cross(Vector3.UP) * float(track.get("sign", 1.0))
	# Every step is pushed apart from the bodies around it. This is the one place
	# the whole module writes movement, so the personal space applies to the fight,
	# the walk to a drop, the escort and the idle drift alike.
	#
	# The push is capped below the step it rides on, never just added: a body's
	# move direction is a *direction and a share of its walk speed*
	# (`ArenaActor._integrate` scales velocity by it), so an uncapped shove from a
	# queue of squadmates behind one ally cancels that ally's travel outright. A
	# squad in single file stalled at the camp mouth that way, 1 km behind the
	# soul, with every body still on its feet and pushing.
	var push := _separation(actor, int(track.get("merc_id", 0))) * PERSONAL_WEIGHT
	var cap := minf(PUSH_CAP, direction.length() * PUSH_SHARE)
	if push.length() > cap:
		push = push.normalized() * cap
	direction += push
	if direction.length_squared() <= 0.0001:
		actor.accept_network_input(Vector2.ZERO, false)
		return
	var speed_share := clampf(direction.length(), 0.0, 1.0)
	var merc_id := int(track.get("merc_id", 0))
	var heading := limited_heading(_heading.get(merc_id, Vector3.ZERO),
		Vector3(direction.x, 0.0, direction.z), float(track.get("delta", 1.0 / 60.0)))
	_heading[merc_id] = heading
	actor.accept_network_input(Vector2(heading.x, heading.z) * speed_share, running)


## The heading after one frame of turning: `wanted` approached from `current` at no
## more than `TURN_RATE` degrees a second. Pure and deterministic, so a regression
## can hold the cap without a live fight.
static func limited_heading(current: Vector3, wanted: Vector3, delta: float) -> Vector3:
	var flat_wanted := Vector3(wanted.x, 0.0, wanted.z)
	if flat_wanted.length_squared() <= 0.000001:
		return current
	flat_wanted = flat_wanted.normalized()
	var flat_current := Vector3(current.x, 0.0, current.z)
	if flat_current.length_squared() <= 0.000001:
		return flat_wanted
	flat_current = flat_current.normalized()
	var max_step := deg_to_rad(TURN_RATE) * maxf(delta, 0.0)
	var turn := flat_current.signed_angle_to(flat_wanted, Vector3.UP)
	if absf(turn) <= max_step:
		return flat_wanted
	return flat_current.rotated(Vector3.UP, signf(turn) * max_step)


## The push away from every squadmate (and the soul) inside `PERSONAL_SPACE`, as
## a flat direction. Zero when a body has room, which is the usual case.
func _separation(actor, merc_id: int) -> Vector3:
	var away := Vector3.ZERO
	if controller == null or not is_instance_valid(actor):
		return away
	var here: Vector3 = (actor as Node3D).global_position
	var others: Array = []
	for raw_id in squad_ids:
		var other_id := int(raw_id)
		if other_id == merc_id or not _is_free(other_id):
			continue
		var other = controller.body_of(other_id)
		if is_instance_valid(other) and other != actor:
			others.append(other)
	if is_instance_valid(player_body) and player_body != actor:
		others.append(player_body)
	for other in others:
		if not is_instance_valid(other) or not bool(other.get("alive")) or bool(other.get("downed")):
			continue
		var delta: Vector3 = here - (other as Node3D).global_position
		delta.y = 0.0
		var distance := delta.length()
		if distance >= PERSONAL_SPACE:
			continue
		if distance <= 0.02:
			# Two bodies in the same spot: pick a side from the ids, never from the
			# wall clock, so the same pair always parts the same way.
			var angle := TAU * float((merc_id * 7 + int(other_id_hint(other))) % 12) / 12.0
			away += Vector3(cos(angle), 0.0, sin(angle)) * 1.4
			continue
		away += delta / distance * (1.0 - distance / PERSONAL_SPACE) * 1.4
	return away


## A stable number for a body with no mercenary id of its own (the soul's body may
## be any of ours): its node name is enough to split a stack.
func other_id_hint(body) -> int:
	var merc := int(controller.merc_of(body)) if controller != null else 0
	if merc > 0:
		return merc
	return absi(str(body.name).hash()) % 12


## Whether the soul is close enough for an ally to spend a moment on the ground it
## is walking over. Without an escort (`following` false) the squad owns the field
## and there is nothing to keep up with.
func _near_soul(actor) -> bool:
	if not following or player_body == null or not is_instance_valid(player_body):
		return true
	var gap: Vector3 = (player_body as Node3D).global_position - (actor as Node3D).global_position
	gap.y = 0.0
	return gap.length() <= LOOT_SEEK_METRES


## Record the soul's road one footprint at a time. Cheap on purpose: one distance
## check per frame, an append every 2.5 m, and the oldest crumb falls off the back
## once the line is 600 m long.
func _drop_crumb() -> void:
	if player_body == null or not is_instance_valid(player_body):
		return
	var at: Vector3 = (player_body as Node3D).global_position
	if not _trail.is_empty() and _trail[_trail.size() - 1].distance_to(at) < CRUMB_STEP:
		return
	_trail.append(at)
	while _trail.size() > CRUMB_KEEP:
		_trail.remove_at(0)
		_trail_base += 1


## The footprint an ally should walk to. A body joins the line at the footprint
## nearest it - the newest of two on the same spot, so a line that doubled back is
## joined on its way out - and from then on only ever walks it forwards: reaching a
## footprint hands it the next, and nothing older is offered again while it holds
## its place (`track["crumb"]`, a footprint number that survives the line being
## trimmed). Null when the body is nowhere near the line the soul walked.
##
## A footprint already in hand is *kept* however far away it is: the grip is a rule
## about where to start walking the line, not a leash that snaps back to the nearest
## footprint, and a body dropped from its footprint mid-stride just paces between
## the two it keeps swapping. "Reached" is arrival or progress - the next footprint
## closer to the body than the one it is walking to - because the line is laid where
## the soul stood, and two of those can be a stride or a hundred metres apart.
func _crumb_for(actor, track: Dictionary) -> Variant:
	if _trail.size() < 2:
		return null
	var here: Vector3 = (actor as Node3D).global_position
	var index := int(track.get("crumb", -1)) - _trail_base
	if index < 0 or index >= _trail.size():
		index = -1
		var best_distance := CRUMB_GRIP
		for probe in _trail.size():
			var distance: float = _trail[probe].distance_to(here)
			if distance <= best_distance:
				best_distance = distance
				index = probe
		if index < 0:
			track["crumb"] = -1
			return null
	while index < _trail.size() - 1:
		var to_this: Vector3 = _trail[index] - here
		to_this.y = 0.0
		var ahead: Vector3 = _trail[index + 1] - _trail[index]
		ahead.y = 0.0
		var next_is_nearer := _trail[index + 1].distance_to(here) < to_this.length()
		var walked_past := ahead.length_squared() > 0.01 and to_this.dot(ahead) < 0.0
		var reached := to_this.length() <= CRUMB_ARRIVE or next_is_nearer or walked_past
		if not reached:
			break
		index += 1
	track["crumb"] = _trail_base + index
	return _trail[index]


## Where an escort stands: its own slot on a ring around the soul.
##
## The slot is the body's place among the *allies* on the ring, not its place in
## `squad_ids`: the soul's own record holds no post, and counting it left a hole
## that wrapped the last body onto the first body's point - two allies shoving each
## other round one spot forever, which is the squad circling itself. The slot comes
## from the squad order, so two allies never claim the same place and the ring is
## what spreads them on the walk. On mapped ground a slot that falls inside a trunk
## or a cage wall moves to the nearest ground a body can stand on, so the arrival
## band is measured to somewhere reachable.
func _escort_post(actor, track: Dictionary) -> Vector3:
	var soul: Vector3 = (player_body as Node3D).global_position
	var merc_id := int(track.get("merc_id", 0))
	var slot := 0
	var seen := 0
	for index in squad_ids.size():
		var other_id := int(squad_ids[index])
		if not _is_free(other_id):
			continue
		var other = controller.body_of(other_id) if controller != null else null
		if other != null and is_instance_valid(other) and other == player_body:
			continue
		if other_id == merc_id:
			slot = seen
		seen += 1
	var ring := slot / ESCORT_SLOT_ANGLES
	# Ring 0 sits on the four cardinals; ring 1 is turned half a slot, so a full
	# band is a staggered double ring instead of an outer one in the inner one's
	# shadow.
	var half_slot := PI / float(ESCORT_SLOT_ANGLES)
	var angle := TAU * float(slot % ESCORT_SLOT_ANGLES) / float(ESCORT_SLOT_ANGLES) \
		+ half_slot * float(ring % 2)
	var radius := follow_slack + ESCORT_SLOT_GAP * 0.5 * float(ring + 1)
	var post := soul + Vector3(cos(angle), 0.0, sin(angle)) * radius
	if _mapped(soul, post):
		post = nav.free_point(post)
	return post


## Nothing to fight, nothing to fetch: drift around the post in short steps. Every
## step is re-rolled when its clock runs out, so a waiting squad reads as bodies
## shifting their weight rather than statues in a row.
func _idle_roam(actor, track: Dictionary) -> void:
	# One step, then a rest. The step clock runs only while the body is stepping;
	# when it expires the body stands until the rest expires, and only then picks
	# the next step. A squad that re-rolled a step the moment the last one ended
	# never stopped walking, and small steps around a post are a circle.
	if float(track.get("roam_left", 0.0)) <= 0.0:
		_hold(actor)
		if float(track.get("rest_left", 0.0)) > 0.0:
			return
		track["roam_left"] = _rng.randf_range(ROAM_STEP_MIN, ROAM_STEP_MAX)
		track["rest_left"] = _rng.randf_range(ROAM_REST_MIN, ROAM_REST_MAX)
		var angle := _rng.randf_range(0.0, TAU)
		var reach := _rng.randf_range(ROAM_RADIUS_MIN, ROAM_RADIUS_MAX)
		var here: Vector3 = (actor as Node3D).global_position
		track["roam_to"] = here + Vector3(cos(angle), 0.0, sin(angle)) * reach
		return
	var target: Vector3 = track.get("roam_to", (actor as Node3D).global_position)
	var to: Vector3 = target - (actor as Node3D).global_position
	to.y = 0.0
	if to.length() <= ROAM_STOP:
		# Arrived early: the rest of the step clock is spent standing.
		_hold(actor)
		return
	_steer(actor, to.normalized() * ROAM_INTENT, track, false)


## Blocked-detection for one ally, plus the fight clocks and this body's own rolls.
## Everything here is per mercenary: two allies in the same gear still circle on
## different beats because neither side is read off an id.
func _track_for(merc_id: int, actor, delta: float) -> Dictionary:
	if not _rng_seeded:
		_rng_seeded = true
		# Fixed, never the wall clock: a scene replays the same rhythm and a
		# regression that fails does so for a reason.
		_rng.seed = 9173
	if not _track.has(merc_id):
		_track[merc_id] = {"last": actor.global_position, "stuck": 0.0, "side": 0.0,
			"sign": 1.0, "state": FIGHT_CLOSE, "state_left": 0.0, "step_left": 0.0,
			"heal_left": 0.0, "bandaging": false, "merc_id": merc_id,
			"roam_left": 0.0, "rest_left": 0.0, "to_post": false,
			"roam_to": actor.global_position, "delta": delta,
			"fetch_key": "", "fetch_best": 0.0, "fetch_left": 0.0,
			"swings_left": 0, "swing_due": false, "retreat": 0.0,
			"anchor": actor.global_position, "anchor_left": POCKET_SECONDS,
			"crumb": -1, "route": PackedVector3Array(), "route_goal": actor.global_position,
			"route_left": 0.0, "route_at": 0,
			"orbit": 1.0 if _rng.randf() < 0.5 else -1.0, "lateral": 0.7, "back": 0.35}
	var track: Dictionary = _track[merc_id]
	track["delta"] = delta
	for key in TRACK_CLOCKS:
		track[key] = maxf(0.0, float(track.get(key, 0.0)) - delta)
	var moved: float = actor.global_position.distance_to(track["last"])
	track["last"] = actor.global_position
	var wanted: bool = Vector2(actor.move_direction).length_squared() > 0.01
	track["stuck"] = float(track["stuck"]) + delta if wanted and moved < 0.02 else 0.0
	if float(track["stuck"]) >= BLOCKED_SECONDS and float(track["side"]) <= 0.0:
		track["stuck"] = 0.0
		track["side"] = SIDESTEP_SECONDS
		track["sign"] = -float(track["sign"])
	# The pocket. A sidestep answers a post; it does not answer a body shoved into a
	# notch between two trunks, and it does not answer two allies pressing on each
	# other hard enough to jitter in place - which is what stranded the escort at the
	# trail's head with the whole wood still to walk. Once a window has passed the
	# question is NET displacement: a body that wants to move and has covered next to
	# nothing is wedged, so it backs out the way it came and tries again from there.
	# A body in a fight is exempt: circling an opponent is a step, not a journey.
	track["anchor_left"] = float(track.get("anchor_left", 0.0)) - delta
	if float(track["anchor_left"]) <= 0.0:
		var net: float = actor.global_position.distance_to(
			track.get("anchor", actor.global_position))
		track["anchor"] = actor.global_position
		track["anchor_left"] = POCKET_SECONDS
		if wanted and not bool(track.get("engaged", false)) and net < POCKET_METRES \
				and float(track.get("retreat", 0.0)) <= 0.0:
			track["retreat"] = RETREAT_SECONDS
			track["side"] = 0.0
	return track


func _hold(actor) -> void:
	actor.combat.stop_block()
	actor.accept_network_input(Vector2.ZERO, false)


## A squadmate takes a drop for themselves: the vacuum books the piece into the
## shared stash and the body wears it, because the player's pickup rule would arm
## the soul instead. Silent on purpose.
func _take(actor, merc_id: int, pickup) -> void:
	if loot == null:
		return
	var item_id := str(pickup.item_id)
	var result: Dictionary = loot.quick_loot(pickup, 0)
	if not bool(result.get("ok", false)):
		return
	warband.auto_equip(merc_id, item_id)
	controller.refresh_gear(merc_id)
	actor.combat.stop()


## Book a fallen body's gear into the shared stash. The vacuum walks it as the
## squad's own silent sweep (peer 0: no soul's hands are involved) and the scene
## re-dresses the body; nothing here touches the paperdoll, and nothing is
## announced. The body itself forgets each piece as it is booked, so a corpse is
## offered once and then stops being a target - no bookkeeping of ours.
func _claim(corpse_id: int) -> void:
	loot.claim_corpse(corpse_id, 0)
