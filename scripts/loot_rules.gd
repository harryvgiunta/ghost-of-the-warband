extends RefCounted
## One balance knob for loot. The scenes keep a tenth of the pre-tune drop rate:
## frontier gear and held weapons, delve weapon drops and the cache item.

const SCALE := 0.1

static func drops() -> bool:
	return randf() < SCALE
