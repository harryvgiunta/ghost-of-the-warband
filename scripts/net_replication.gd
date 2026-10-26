extends RefCounted
## The client-side netcode primitives every Ironwood scene shares.
##
## `InputRing` is the local ranger's movement history: the owning peer records
## one frame per physics tick and keeps the frames the host has not acknowledged
## yet, so an authoritative correction can be replayed instead of rubber-banding
## the body back to a stale packet.
##
## `SnapshotTimeline` turns uneven arrivals into a smooth playout: it renders a
## remote body by interpolating between two known server states a short delay in
## the past and dead-reckons along its last velocity when a packet drops. The
## playout clock is nudged, never snapped, so a late packet cannot make the body
## jump forward.
##
## Both are pure data structures with no scene access: the same call sequence
## always produces the same result, which is what lets the network regressions
## drive them without a peer.

class InputRing:
	## One unacknowledged movement frame per physics tick, oldest first.
	const LIMIT := 256

	var records: Array = []
	var next_seq := 0
	var acked := -1

	func clear() -> void:
		records.clear()
		next_seq = 0
		acked = -1

	## Stores `record` as the next frame and returns its sequence number.
	func push(record: Dictionary) -> int:
		var entry := record.duplicate()
		entry["seq"] = next_seq
		next_seq += 1
		records.append(entry)
		while records.size() > LIMIT:
			records.pop_front()
		return int(entry["seq"])

	## Frames the host has applied and that must never be replayed again.
	func acknowledge(seq: int) -> void:
		acked = maxi(acked, seq)
		var keep := 0
		while keep < records.size() and int(records[keep].seq) <= acked:
			keep += 1
		if keep > 0:
			records = records.slice(keep)

	## The frame with this sequence number, or `{}` once it has been dropped.
	func record_at(seq: int) -> Dictionary:
		for record in records:
			if int(record.seq) == seq:
				return record
		return {}

	## Every frame recorded after `seq`, in order.
	func after(seq: int) -> Array:
		var out: Array = []
		for record in records:
			if int(record.seq) > seq:
				out.append(record)
		return out

	func latest_seq() -> int:
		return next_seq - 1

	func size() -> int:
		return records.size()


class SnapshotTimeline:
	## One remote body's server states, keyed by the host's simulation tick.
	const MAX_SAMPLES := 48
	const MIN_DELAY_TICKS := 1.5
	const MAX_DELAY_TICKS := 12.0
	const EXTRAPOLATION_TICKS := 8.0
	const CATCHUP_TICKS := 24.0
	const JITTER_GAIN := 2.0
	const JITTER_SMOOTHING := 0.2
	const DISCONTINUITY_METRES := 4.0

	var samples: Array = []
	var tick_seconds := 1.0 / 60.0
	var delay_ticks := MIN_DELAY_TICKS
	## A caller-imposed floor: the scene's `interp_delay`, or two snapshot
	## intervals for a mob stream that arrives slower than the sim tick.
	var floor_delay_ticks := MIN_DELAY_TICKS
	## Movement this big between two samples cannot be travel: it is a blink,
	## a respawn or a scene hand-off, so the buffer restarts there.
	var discontinuity_metres := DISCONTINUITY_METRES
	var playout := 0.0
	var started := false
	var jitter := 0.0
	var restarts := 0
	var _newest := -1
	var _arrival := 0.0
	var _previous_arrival := 0.0
	var _previous_tick := -1

	func configure(rate: float) -> void:
		tick_seconds = 1.0 / maxf(rate, 1.0)

	func clear() -> void:
		samples.clear()
		started = false
		playout = 0.0
		_newest = -1
		_previous_tick = -1
		jitter = 0.0

	## Restarts the buffer at a known pose (mode changes, first packet).
	func reset_to(position: Vector3, velocity: Vector3 = Vector3.ZERO, yaw: float = 0.0,
			tick: int = 0, now: float = 0.0) -> void:
		clear()
		samples.append({"tick": tick, "pos": position, "vel": velocity, "yaw": yaw})
		_newest = tick
		_arrival = now
		started = true
		playout = float(tick) - delay_ticks

	func newest_tick() -> int:
		return _newest

	func oldest_tick() -> int:
		return int(samples[0].tick) if not samples.is_empty() else -1

	## The server tick this body is currently drawn at.
	func render_tick() -> float:
		return playout

	## True while the buffer is empty ahead of the playout clock.
	func extrapolating() -> bool:
		return not samples.is_empty() and playout > float(samples[-1].tick)

	## Adds one authoritative state. `tick` must increase; a repeated or stale
	## tick is ignored so a reordered datagram cannot rewind the body.
	func push(tick: int, position: Vector3, velocity: Vector3, yaw: float, now: float) -> bool:
		if tick <= _newest:
			return false
		if _previous_tick >= 0:
			var expected := float(tick - _previous_tick) * tick_seconds
			var actual := now - _arrival
			jitter = lerpf(jitter, absf(actual - expected), JITTER_SMOOTHING)
			delay_ticks = clampf(maxf(MIN_DELAY_TICKS + jitter / tick_seconds * JITTER_GAIN,
				floor_delay_ticks), MIN_DELAY_TICKS, MAX_DELAY_TICKS)
		if velocity.is_zero_approx() and not samples.is_empty():
			# A stream without a velocity field (the delve's devils) still gets
			# dead reckoning from the distance it covered between samples.
			var previous: Dictionary = samples[-1]
			var span := float(tick - int(previous.tick)) * tick_seconds
			if span > 0.0001:
				var implied: Vector3 = (position - Vector3(previous.pos)) / span
				if implied.length() < 24.0:
					velocity = implied
		var entry := {"tick": tick, "pos": position, "vel": velocity, "yaw": yaw}
		if not samples.is_empty():
			var previous: Dictionary = samples[-1]
			var span := float(tick - int(previous.tick)) * tick_seconds
			var explained := Vector3(previous.vel).length() * span * 1.5 + discontinuity_metres
			if Vector3(previous.pos).distance_to(position) > explained:
				# A teleport, not motion: restart so the body appears at the new
				# pose instead of sliding across the gap.
				samples.clear()
				started = false
				restarts += 1
		samples.append(entry)
		while samples.size() > MAX_SAMPLES:
			samples.pop_front()
		_newest = tick
		_previous_tick = tick
		_previous_arrival = _arrival
		_arrival = now
		if not started:
			started = true
			playout = float(tick) - delay_ticks
		return true

	## Advances the playout clock by a render frame, easing toward the delay
	## target instead of jumping when a packet arrives late or early.
	func advance(delta: float) -> void:
		if not started or samples.is_empty():
			return
		var target := float(_newest) - delay_ticks
		var error := target - playout
		if absf(error) > CATCHUP_TICKS:
			playout = target
			return
		playout += (delta / tick_seconds) * (1.0 + clampf(error * 0.25, -0.25, 0.35))

	## The body's pose at the playout clock.
	func sample() -> Dictionary:
		if samples.is_empty():
			return {"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "extrapolated": false}
		var newest: Dictionary = samples[-1]
		if playout >= float(newest.tick):
			var over := minf(playout - float(newest.tick), EXTRAPOLATION_TICKS)
			var velocity: Vector3 = newest.vel
			return {"pos": Vector3(newest.pos) + velocity * (over * tick_seconds),
				"vel": velocity, "yaw": float(newest.yaw), "extrapolated": over > 0.001}
		var oldest: Dictionary = samples[0]
		if playout <= float(oldest.tick):
			return {"pos": Vector3(oldest.pos), "vel": Vector3(oldest.vel),
				"yaw": float(oldest.yaw), "extrapolated": false}
		for index in range(1, samples.size()):
			var after: Dictionary = samples[index]
			if playout > float(after.tick):
				continue
			var before: Dictionary = samples[index - 1]
			var span := maxf(float(after.tick) - float(before.tick), 0.0001)
			var weight := clampf((playout - float(before.tick)) / span, 0.0, 1.0)
			return {
				"pos": Vector3(before.pos).lerp(Vector3(after.pos), weight),
				"vel": Vector3(before.vel).lerp(Vector3(after.vel), weight),
				"yaw": lerp_angle(float(before.yaw), float(after.yaw), weight),
				"extrapolated": false,
			}
		var last: Dictionary = samples[-1]
		return {"pos": Vector3(last.pos), "vel": Vector3(last.vel),
			"yaw": float(last.yaw), "extrapolated": false}


## A render buffer for a mob stream. Mobs arrive at their own unthrottled
## cadence, so the delay floor is two intervals rather than one sim tick.
static func mob_timeline() -> SnapshotTimeline:
	var timeline := SnapshotTimeline.new()
	timeline.floor_delay_ticks = 6.0
	timeline.discontinuity_metres = 2.0
	return timeline


## The shared playout clock: one timeline fed by every snapshot arrival, so a
## peer can say which server tick it was looking at when it acted.
class NetClock:
	## The clock is a timeline with no body: the tuning lives on the timeline.
	var timeline: SnapshotTimeline = SnapshotTimeline.new()

	func configure(rate: float, delay_seconds: float) -> void:
		timeline.configure(rate)
		timeline.floor_delay_ticks = clampf(delay_seconds / timeline.tick_seconds,
			SnapshotTimeline.MIN_DELAY_TICKS, SnapshotTimeline.MAX_DELAY_TICKS)

	func ingest(tick: int, now: float) -> bool:
		return timeline.push(tick, Vector3.ZERO, Vector3.ZERO, 0.0, now)

	func advance(delta: float) -> void:
		timeline.advance(delta)

	func render_tick() -> int:
		return int(floor(timeline.render_tick()))

	func newest_tick() -> int:
		return timeline.newest_tick()

	func clear() -> void:
		timeline.clear()

## A simulated link for the high-frequency streams. Localhost hides netcode
## defects because the past and the present are the same frame: prediction,
## interpolation and the hitbox rewind all look correct at 0.1 ms. Holding every
## high-frequency packet for `lag` seconds (± `jitter`) reproduces a real link —
## including the reordering jitter causes — so a two-window local match shows
## what a Tailscale match shows. Disabled means each callback runs inline and
## costs one comparison.
class LagQueue:
	## The delay applied to each deferred callback, in seconds.
	var lag := 0.0
	## Uniform spread added or subtracted from `lag`, in seconds.
	var jitter := 0.0
	## Callbacks still waiting, for a QC readout.
	var held := 0
	var _items: Array = []
	var _rng := RandomNumberGenerator.new()

	func configure(seconds: float, spread_seconds: float) -> void:
		lag = maxf(seconds,0.0)
		jitter = clampf(spread_seconds,0.0,lag)
		# Seeded so a repeated run measures the same link.
		_rng.seed = 0x51ED
		_items.clear()
		held = 0

	func active() -> bool:
		return lag > 0.0 or jitter > 0.0

	func defer(call: Callable) -> void:
		if not active():
			call.call()
			return
		var now := Time.get_ticks_msec()/1000.0
		_items.append({"at":now+maxf(0.0,lag+_rng.randf_range(-jitter,jitter)),"call":call})
		held = _items.size()

	## Runs every callback whose delay has elapsed. Due calls are collected
	## first, so a callback may queue more work without disturbing the sweep.
	func release(now: float) -> void:
		if _items.is_empty():
			return
		var due: Array = []
		var pending: Array = []
		for item in _items:
			if float(item.at) <= now:
				due.append(item.call)
			else:
				pending.append(item)
		_items = pending
		held = _items.size()
		for call in due:
			(call as Callable).call()

	func clear() -> void:
		_items.clear()
		held = 0
