class_name ReviveChannel
extends Node
## GHOST OF THE WARBAND: one human-held revive channel per reviving peer.
##
## A downed body stands up after exactly `WarbandContracts.REVIVE_CHANNEL_SECONDS`
## of continuous channel by a human standing inside `REVIVE_REACH`. "Continuous"
## is the whole design: walking away, being put down yourself or changing target
## throws the clock away and starts again at zero, so a five second save cannot
## be assembled out of short visits.
##
## Two kinds of hands can open a channel. A human's are keyed by its peer id and
## opened with `begin()`; the squad's own are keyed by `ALLY_PEER` and opened with
## `begin_ally()`. A bot body is still refused as a *peer* - peer `0` is the
## router's "nobody" - because a soul has to be the one holding a key, but an ally
## is allowed to pick a body up: the guard is the field, not the keyboard.
## `SquadDrive` refuses the rescue while anything hostile is near, so a squad
## cannot quietly undo the warband's attrition model in the middle of a fight.
##
## The node holds only the channels: `begin()` opens one, `tick(delta)` advances
## every open channel and reports, `progress()` reads one back for a ring or a
## bar. Whoever owns the scene calls `tick` from its own clock.

signal complete(reviver_peer: int, target)
signal cancelled(reviver_peer: int, target, reason: String)
signal progressed(reviver_peer: int, target, progress: float)

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## Why a channel broke. The scene turns these into one line of feedback.
const REASON_RELEASED := "released"
const REASON_NOT_DOWNED := "not_downed"
const REASON_OUT_OF_REACH := "out_of_reach"
const REASON_DEAD := "dead"
const REASON_REVIVER_DOWNED := "reviver_downed"
const REASON_REVIVER_LOST := "reviver_lost"

## The bodies this channel may inspect. The reviver's own body is found here by
## matching `peer_id`, so a caller never has to hand in two nodes per channel.
var bodies: Array = []
## How close a human must stand; the contract's reach, adjustable for a scene
## that enlarges its bodies.
var reach := Contracts.REVIVE_REACH

## The channel the squad's own hands open. It sits outside the peer ids so a soul
## can never collide with it: `0` stays "nobody inside".
const ALLY_PEER := -1

## peer -> {target, elapsed, actor?}. One entry per peer: a human has two hands,
## not two revive channels. An ally channel carries the rescuer's own body, since
## there is no peer to look it up from.
var _channels: Dictionary = {}

func set_bodies(list: Array) -> void:
	bodies = list

## Open a channel from `reviver_peer` onto `target_actor`. Refused - with no
## channel left behind - when the target is not a downed body, is out of reach,
## is already dead, or when the reviver is AI.
func begin(reviver_peer: int, target_actor) -> bool:
	if reviver_peer <= 0:
		# Peer 0 is the router's "nobody": only a bot body answers to it.
		return false
	var reviver = body_of(reviver_peer)
	if not is_instance_valid(reviver) or bool(reviver.get("is_bot")):
		return false
	if not can_revive(reviver, target_actor):
		return false
	_channels[reviver_peer] = {"target": target_actor, "elapsed": 0.0}
	return true

## Open a channel for the squad's own hands: `rescuer_actor` standing over a downed
## squadmate. The reach, the downed check and the break rules are the human ones -
## what differs is who is holding it, and that the caller is responsible for the
## field being clear (see `SquadDrive._rescue_step`).
func begin_ally(rescuer_actor, target_actor) -> bool:
	if not is_instance_valid(rescuer_actor) or not is_instance_valid(target_actor):
		return false
	# Not `can_revive`: a squadmate IS a bot body, and that check exists to keep a
	# keyboard-less body from opening a channel for a *soul*. Standing, revivable
	# and inside the reach are still the rules.
	if not _standing(rescuer_actor) or not _revivable(target_actor):
		return false
	if rescuer_actor.global_position.distance_to(target_actor.global_position) > reach:
		return false
	_channels[ALLY_PEER] = {"target": target_actor, "elapsed": 0.0, "actor": rescuer_actor}
	return true


## The body a channel belongs to: the rescuer itself for an ally channel, the
## routed body for a human's.
func _reviver_of(peer: int, channel: Dictionary):
	if channel.has("actor"):
		return channel["actor"]
	return body_of(peer)

## Advance every open channel. Out-of-reach and downed revivers cancel their own
## channel; a completed channel stands the target up through
## `ArenaActor.revive_from_downed()` and emits `complete`.
##
## Returns `{progress: {peer: 0..1}, revived: [target...]}` so a scene can draw
## every ring and swing the camera in one pass.
func tick(delta: float) -> Dictionary:
	var status := {}
	var revived: Array = []
	for peer in _channels.keys():
		var channel: Dictionary = _channels[peer]
		var target = channel.target
		var reviver = _reviver_of(int(peer), channel)
		var reason := _break_reason(reviver, target)
		if reason != "":
			_channels.erase(peer)
			cancelled.emit(int(peer), target, reason)
			continue
		channel.elapsed = float(channel.elapsed) + maxf(delta, 0.0)
		var ratio := clampf(float(channel.elapsed) / Contracts.REVIVE_CHANNEL_SECONDS, 0.0, 1.0)
		# A frame-by-frame clock lands a hair either side of the fifth second, so
		# completion is read within a millisecond (`DownedRules.CLOCK_SLACK`).
		# 4.9 seconds is still nowhere near it.
		if float(channel.elapsed) >= Contracts.REVIVE_CHANNEL_SECONDS - DownedRules.CLOCK_SLACK:
			# Drop the channel before standing the body up: a revive that fired a
			# signal back into `begin()` would otherwise find itself still open.
			_channels.erase(peer)
			target.revive_from_downed()
			revived.append(target)
			complete.emit(int(peer), target)
			continue
		status[int(peer)] = ratio
		progressed.emit(int(peer), target, ratio)
	return {"progress": status, "revived": revived}

## Give up the channel (the key came up, the body was swapped, the scene ended).
func cancel(reviver_peer: int) -> void:
	if not _channels.has(reviver_peer):
		return
	var target = _channels[reviver_peer].target
	_channels.erase(reviver_peer)
	cancelled.emit(reviver_peer, target, REASON_RELEASED)

func cancel_all() -> void:
	for peer in _channels.keys():
		cancel(int(peer))

## 0..1 of the contract's five seconds; 0 for a peer with no channel.
func progress(reviver_peer: int) -> float:
	if not _channels.has(reviver_peer):
		return 0.0
	return clampf(float(_channels[reviver_peer].elapsed) / Contracts.REVIVE_CHANNEL_SECONDS, 0.0, 1.0)

func channeling(reviver_peer: int) -> bool:
	return _channels.has(reviver_peer)

func target_of(reviver_peer: int):
	if not _channels.has(reviver_peer):
		return null
	return _channels[reviver_peer].target

## The body a peer's soul is in, as far as this node's body list knows.
func body_of(peer: int) -> Object:
	for body in bodies:
		if is_instance_valid(body) and int(body.get("peer_id")) == peer:
			return body
	return null

## Whether `reviver` could open a channel on `target` this instant: both alive,
## the target downed, and the two bodies inside `reach`.
func can_revive(reviver, target) -> bool:
	if not is_instance_valid(reviver) or not is_instance_valid(target):
		return false
	if bool(reviver.get("is_bot")) or not _standing(reviver):
		return false
	if not _revivable(target):
		return false
	return reviver.global_position.distance_to(target.global_position) <= reach

## Why an open channel must break this tick, or "" while it holds.
func _break_reason(reviver, target) -> String:
	if not is_instance_valid(reviver):
		return REASON_REVIVER_LOST
	if not _standing(reviver):
		return REASON_REVIVER_DOWNED
	if not is_instance_valid(target) or not bool(target.get("alive")):
		return REASON_DEAD
	if not bool(target.get("downed")):
		return REASON_NOT_DOWNED
	if reviver.global_position.distance_to(target.global_position) > reach:
		return REASON_OUT_OF_REACH
	return ""

## A body that can be brought back: present, alive and downed.
static func _revivable(target) -> bool:
	return is_instance_valid(target) and bool(target.get("alive")) and bool(target.get("downed"))

## A body on its feet: alive and not downed.
static func _standing(body) -> bool:
	return is_instance_valid(body) and bool(body.get("alive")) and not bool(body.get("downed"))
