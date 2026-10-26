extends RefCounted
## Head/body damage zones shared by projectiles and blades.
##
## A damageable keeps its single physical capsule; a head zone is a logical
## damage volume, so arrows and swords need no extra collision layers, RIDs or
## second hitbox body. Zones read the animated head joint, which keeps crouch,
## cover lean and roll poses honest.
##
## Arrow hits are points on the body capsule and use `is_headshot`. Blade hits
## use `blade_headshot` because a shape query's rest point can sit anywhere in
## the overlap instead of near the head, so the swept blade segment is tested
## against the zone instead.

const HEAD_MULTIPLIER := 2.0
const BODY_MULTIPLIER := 1.0
## Humanoid: centred 0.11 m up the animated Head bone, wide enough to include
## the 0.3 m body capsule surface at head height.
const HUMAN_HEAD_RADIUS := 0.34
const HUMAN_HEAD_HALF_HEIGHT := 0.14
const HUMAN_HEAD_OFFSET := 0.11
## Quadruped: the imported wolf head sits in front of its body capsule, so the
## zone reaches only the front of the capsule; side and rear hits stay body.
const WOLF_HEAD_RADIUS := 0.55
const WOLF_HEAD_HALF_HEIGHT := 0.18
## Cinder devil: the imported skull sits on the thrust-forward neck of a 2.11 m
## frame, so the zone is wider than a human's shoulders would suggest and rides
## the animated head bone.
const DEVIL_HEAD_RADIUS := 0.26
const DEVIL_HEAD_HALF_HEIGHT := 0.16
## The head zone is a band across the body, so it is never narrower than the
## capsule an arrow actually stops on: a shaft that lands on the surface at
## head height has hit the head.
const HEAD_SURFACE_MARGIN := 0.05


static func damage_multiplier(headshot: bool) -> float:
	return HEAD_MULTIPLIER if headshot else BODY_MULTIPLIER


## The zone radius for a body: the authored radius, widened to cover the
## capsule surface at head height. Authored radii that reach past the capsule
## (a muzzle, a wolf skull) still win.
static func head_zone_radius(authored: float, body_radius: float) -> float:
	return maxf(authored, body_radius + HEAD_SURFACE_MARGIN)


static func is_headshot(target: Node, point: Vector3) -> bool:
	if not is_instance_valid(target) or not point.is_finite():
		return false
	if not target.has_method("head_hitbox_center") or not target.has_method("head_hit_profile"):
		return false
	var profile: Vector2 = target.head_hit_profile()
	if profile.x <= 0.0 or profile.y <= 0.0:
		return false
	var offset: Vector3 = point - target.head_hitbox_center()
	if absf(offset.y) > profile.y:
		return false
	var planar := Vector2(offset.x, offset.z)
	return planar.length_squared() <= profile.x * profile.x


static func blade_headshot(target: Node, base: Vector3, tip: Vector3, blade_radius: float) -> bool:
	if not is_instance_valid(target) or not base.is_finite() or not tip.is_finite():
		return false
	if not target.has_method("head_hitbox_center") or not target.has_method("head_hit_profile"):
		return false
	var profile: Vector2 = target.head_hit_profile()
	if profile.x <= 0.0 or profile.y <= 0.0:
		return false
	var center: Vector3 = target.head_hitbox_center()
	var radius: float = profile.x + blade_radius
	var low: float = center.y - profile.y - blade_radius
	var high: float = center.y + profile.y + blade_radius
	# Clip the blade to the head band before measuring its horizontal approach.
	var direction: Vector3 = tip - base
	var start := 0.0
	var end := 1.0
	if absf(direction.y) <= 0.000001:
		if base.y < low or base.y > high:
			return false
	else:
		var enter := (low - base.y) / direction.y
		var leave := (high - base.y) / direction.y
		if enter > leave:
			var swap := enter
			enter = leave
			leave = swap
		start = maxf(start, enter)
		end = minf(end, leave)
		if start > end:
			return false
	var from := base + direction * start
	var to := base + direction * end
	var axis := Vector2(center.x, center.z)
	var closest := Geometry2D.get_closest_point_to_segment(axis, Vector2(from.x, from.z), Vector2(to.x, to.z))
	return closest.distance_squared_to(axis) <= radius * radius
