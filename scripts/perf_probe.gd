extends RefCounted
## The scope profiler behind F12 (`perf_overlay.gd`): what each of the frame's
## major functions costs, measured in the running game.
##
## Godot's own profiler lives in the editor's debugger: it needs the editor
## attached, and it reports script functions one at a time rather than "every
## watcher's brain, together, this frame". So the frame's entry points - the
## world's physics tick, the soul's body steps, a rig's animation, a mob's brain,
## the HUD, the session's snapshots - call `begin(name)` / `end()`, and every
## call of one name under one parent folds into one row of a call tree.
##
## Off, a pair is two static calls that return on their first line. On (only
## while the overlay is up), a pair is two `Time.get_ticks_usec()` reads, one
## dictionary lookup and a push/pop on preallocated arrays: nothing allocates
## once a scope has been seen.
##
## Scopes nest. A row reports `total` (its whole time, children included) and
## `own` (what is left once its child scopes are taken out), so a wrapped tick
## splits into the steps that actually cost without counting anything twice.
## Main thread only: the open-scope stack is one set of static arrays.

## The master switch. The overlay turns it on while it is up; off, every call
## below returns before it reads the clock.
static var enabled := false

## The call tree: one slot per scope name under one parent, in the order the
## slots were first seen. A slot is never removed, so its index is stable.
static var _names := PackedStringArray()
static var _parents := PackedInt32Array()
static var _depths := PackedInt32Array()
## `_children[parent + 1]` maps a scope name to its slot under that parent;
## entry 0 holds the roots.
static var _children: Array[Dictionary] = [{}]
## The window's counters, per slot, in microseconds.
static var _total := PackedInt64Array()
static var _own := PackedInt64Array()
static var _calls := PackedInt32Array()
static var _peak := PackedInt64Array()
## The frame that hurt: its wall time, and what each scope cost inside it. The
## window's totals are an average, and a frame that runs three times the average
## is what the eye reads as a stutter - the average never shows which scope did
## it. `_prev` is the window total as of the last `tick()`, so a frame's own
## cost is the difference.
static var worst_frame_us := 0
## Frames since the slowest one happened, so the overlay can say how old it is.
static var worst_frames_ago := 0
## How long a recorded worst frame is kept: the same window the fps figure uses.
const WINDOW_FRAMES := 240
static var _prev := PackedInt64Array()
static var _worst := PackedInt64Array()

## The open scopes, innermost last. Parallel packed arrays grown in steps of
## sixteen, so a begin/end pair never allocates.
static var _open_slot := PackedInt32Array()
static var _open_start := PackedInt64Array()
static var _open_child := PackedInt64Array()
static var _depth := 0

## The window the counters cover: frames closed by `tick()` and their summed
## wall time.
static var frames := 0
static var frame_us := 0
## Frames that closed with a scope still open. Non-zero means a `begin` lost its
## `end` (an early return between the two), which books everything after it
## under the wrong parent; the overlay says so instead of trusting the table.
static var imbalanced := 0
static var _last_tick := 0


static func begin(name: String) -> void:
	if not enabled:
		return
	var parent := _open_slot[_depth - 1] if _depth > 0 else -1
	var slot: int = _children[parent + 1].get(name, -1)
	if slot < 0:
		slot = _add(name, parent)
	if _depth == _open_slot.size():
		_open_slot.resize(_depth + 16)
		_open_start.resize(_depth + 16)
		_open_child.resize(_depth + 16)
	_open_slot[_depth] = slot
	_open_child[_depth] = 0
	_open_start[_depth] = Time.get_ticks_usec()
	_depth += 1


static func end() -> void:
	if not enabled or _depth == 0:
		return
	var spent := Time.get_ticks_usec() - _open_start[_depth - 1]
	_depth -= 1
	var slot := _open_slot[_depth]
	_total[slot] += spent
	_own[slot] += spent - _open_child[_depth]
	_calls[slot] += 1
	if spent > _peak[slot]:
		_peak[slot] = spent
	if _depth > 0:
		_open_child[_depth - 1] += spent


## Closes one frame of the window and returns its wall time in microseconds: 0
## for the first frame after `reset()`, which has nothing to be measured from.
## The overlay calls it once per drawn frame, so the window is in drawn frames
## and a physics scope that ran twice in one of them counts twice.
static func tick() -> int:
	var now := Time.get_ticks_usec()
	if _depth != 0:
		imbalanced += 1
		_depth = 0
	var spent := now - _last_tick if _last_tick > 0 else 0
	_last_tick = now
	if spent > 0:
		frames += 1
		frame_us += spent
		# Kept across `restart()`: the scope table is rebuilt every quarter
		# second, and the frame that stutters lands once every few seconds - a
		# record that dies with the table can never catch one.
		worst_frames_ago += 1
		if spent > worst_frame_us:
			worst_frame_us = spent
			worst_frames_ago = 0
			for slot in _worst.size():
				_worst[slot] = _total[slot] - _prev[slot]
		elif worst_frame_us > 0 and worst_frames_ago > WINDOW_FRAMES:
			# The frame that hurt has left the window the headline reads.
			worst_frame_us = 0
			worst_frames_ago = 0
	for slot in _prev.size():
		_prev[slot] = _total[slot]
	return spent


## Starts a fresh window: every counter back to zero, the tree and the frame
## clock kept, so the next `tick()` measures from the last one.
static func restart() -> void:
	_total.fill(0)
	_own.fill(0)
	_calls.fill(0)
	_peak.fill(0)
	_prev.fill(0)
	# `_worst` and `worst_frame_us` deliberately survive a restart: they are the
	# record of one frame, not a window total.
	frames = 0
	frame_us = 0
	imbalanced = 0


## A fresh window with nothing open and no frame clock: what turning the
## profiler on starts from. A scope still open when it was last switched off
## would otherwise be closed by the first `end()` it sees.
static func reset() -> void:
	_depth = 0
	_last_tick = 0
	_worst.fill(0)
	worst_frame_us = 0
	worst_frames_ago = 0
	restart()


## The window as a call tree: one dictionary per scope that ran, parents before
## their children and siblings heaviest first. `depth` is 0 for a root.
static func rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_append_rows(-1, out)
	return out


## The scopes of the slowest frame of the window, heaviest first, as
## `{name, depth, us}`. What the average cannot show: the one frame the eye read
## as a stutter, and what was running inside it.
static func worst_rows(limit: int = 4) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if worst_frame_us <= 0:
		return out
	var order: Array[int] = []
	for slot in _worst.size():
		if _worst[slot] > 0:
			order.append(slot)
	order.sort_custom(func(a: int, b: int) -> bool: return _worst[a] > _worst[b])
	# Only roots and their heaviest children: a list of nested duplicates under
	# a couple of parents says less than the parents themselves.
	for slot in order:
		if out.size() >= limit:
			break
		var nested := false
		for row in out:
			var parent: int = _parents[slot]
			if parent >= 0 and (parent == int(row["slot"]) or _under(parent, int(row["slot"]))):
				nested = true
				break
		if nested:
			continue
		out.append({"name": _names[slot], "depth": _depths[slot], "slot": slot,
			"us": _worst[slot]})
	return out


static func _under(slot: int, ancestor: int) -> bool:
	var walk := slot
	while walk >= 0:
		if walk == ancestor:
			return true
		walk = _parents[walk]
	return false


## Time spent inside any scope this window: the sum of the roots, so nested
## scopes are not counted twice.
static func scoped_us() -> int:
	var sum := 0
	for slot: int in _children[0].values():
		sum += _total[slot]
	return sum


## Every begin/end pair the window closed. The pairs are what the profiler
## itself costs, so the overlay prints this next to the times they produced.
static func pairs() -> int:
	var sum := 0
	for count in _calls:
		sum += count
	return sum


static func _add(name: String, parent: int) -> int:
	var slot := _names.size()
	_names.append(name)
	_parents.append(parent)
	_depths.append(_depths[parent] + 1 if parent >= 0 else 0)
	_total.append(0)
	_own.append(0)
	_calls.append(0)
	_peak.append(0)
	_prev.append(0)
	_worst.append(0)
	_children[parent + 1][name] = slot
	_children.append({})
	return slot


static func _append_rows(parent: int, out: Array[Dictionary]) -> void:
	var slots: Array = _children[parent + 1].values()
	slots.sort_custom(func(a: int, b: int) -> bool: return _total[a] > _total[b])
	for slot: int in slots:
		if _calls[slot] == 0:
			continue
		out.append({
			"name": _names[slot],
			"depth": _depths[slot],
			"total_us": _total[slot],
			"own_us": _own[slot],
			"calls": _calls[slot],
			"peak_us": _peak[slot],
		})
		_append_rows(slot, out)
