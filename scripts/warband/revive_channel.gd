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
## AI never revives. The souls router's peer `0` means "nobody inside", and an
## `ArenaActor` with `is_bot` has no player holding a key, so both are refused
## before a channel is ever opened - a bot dragging a body back up would quietly
## undo the warband's whole attrition model.
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

## peer -> {target, elapsed}. One entry per peer: a human has two hands, not two
## revive channels.
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
		var reviver = body_of(int(peer))
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
