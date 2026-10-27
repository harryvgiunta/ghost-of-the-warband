class_name DownedRules
extends RefCounted
## GHOST OF THE WARBAND: the 10% overkill rule and the crawl geometry, as pure
## helpers shared by both bodies that can be knocked down.
##
## Two different things fight in this game: the arena layer's `ArenaActor`
## (authoritative, predicted, snapshotted) and the frontier controller's raw
## `CharacterBody3D`. Neither can inherit the other, and a shared node would drag
## one mode's lifecycle into the other, so only the arithmetic lives here - the
## state machines stay in `arena_actor.gd` and `main.gd`.
##
## The threshold itself is never re-derived: `WarbandContracts.resolve_damage`
## and `finishes_downed` already own it, and this file is the single place a
## body asks them, so a third spelling of "10% overkill" cannot appear.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## How far ahead of itself a downed body aims, and how close counts as arrived.
## The arrival margin keeps a blocked crawl from jittering against the wall it
## cannot pass.
const CRAWL_DISTANCE := 3.0
const CRAWL_ARRIVAL := 0.08
## Below this the blend of "away from the blow" and "toward safety" has
## collapsed (a friend standing exactly behind the killer) and the blow's own
## bearing is used instead.
const BLEND_FLOOR := 0.05
## A bearing shorter than this is not a bearing: the body is already there.
const MIN_BEARING := 0.0001
## A clock assembled out of frame deltas lands a hair either side of the whole
## second it was meant to measure (fifty 0.1 s ticks sum to 4.999999999999998),
## so the downed clocks finish inside a millisecond of their target. That is far
## below anything a player can feel and far above the rounding, and it never lets
## the previous tenth of a second pass.
const CLOCK_SLACK := 0.001

## One hit on a standing body. Returns the contract's
## `{ok, state, health, damage, overkill, downed, died}` record untouched.
static func resolve(health: float, max_health: float, amount: float) -> Dictionary:
	return Contracts.resolve_damage(health, max_health, amount)

## A blow on an already-downed body: the same 10% threshold, read as a finisher
## rather than as damage.
static func finishes(max_health: float, amount: float) -> bool:
	return Contracts.finishes_downed(max_health, amount)

## Health a revive hands back: the contract's fraction, never more than the
## body's maximum and never less than a single point - a body that stands up at
## zero health would read as downed again on the very next hit.
static func revive_health(max_health: float, fraction: float = Contracts.REVIVE_HEALTH_FRACTION) -> float:
	var ceiling := maxf(1.0, max_health)
	return clampf(ceiling * clampf(fraction, 0.0, 1.0), 1.0, ceiling)

## True once a downed body has been on the ground long enough to bleed out.
static func bled_out(seconds: float) -> bool:
	return seconds >= Contracts.DOWNED_BLEED_SECONDS - CLOCK_SLACK

## Where a downed body drags itself: away from the blow that put it down, biased
## toward the nearest standing friend or a supplied safe anchor.
##
## Both bearings are horizontal, so a body never aims itself into the floor; a
## body with neither bearing (no attacker known, nowhere safe) returns its own
## position, which the crawl reads as "stay put".
static func crawl_target(origin: Vector3, threat: Vector3, has_threat: bool,
		safe: Vector3, has_safe: bool) -> Vector3:
	var away := _bearing(threat, origin) if has_threat else Vector3.ZERO
	var toward_safe := _bearing(origin, safe) if has_safe else Vector3.ZERO
	var direction := away + toward_safe
	# Two safe bearings that cancel out point at nothing; the blow's direction is
	# the one bearing a downed body is sure of.
	if direction.length() < BLEND_FLOOR:
		direction = away
	if direction.length() < MIN_BEARING:
		return origin
	return origin + direction.normalized() * CRAWL_DISTANCE

## The horizontal unit vector from `from` toward `to`, or zero when the two are
## on top of each other.
static func _bearing(from: Vector3, to: Vector3) -> Vector3:
	var planar := Vector3(to.x - from.x, 0.0, to.z - from.z)
	if planar.length() < MIN_BEARING:
		return Vector3.ZERO
	return planar.normalized()
