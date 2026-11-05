extends RefCounted
## How hard the Weeping Hollow is, chosen at the mouth before the party goes down.
##
## Three difficulties, and each one turns exactly three dials on the floor the
## descent builds (`delve_cave.gd`):
##
##   * **the crowd** - the share of each den's per-post crowd that stands on the
##     floor (`delve_layout.den_crowd`). Every authored post always stands, so a
##     den keeps the species and the archer it was written with; what thins out is
##     the crowd the plan repeats round it.
##   * **the pool** - what a body's health is multiplied by at spawn
##     (`devil_mob.apply_difficulty`).
##   * **the rate** - what a body's walk and run are multiplied by and what its
##     swing cadence is divided by. The clip's own windup and strike are the
##     animation's, and never scaled: the visual blow still lands on the damage
##     frame the impact table was authored around, only the pause between blows
##     closes.
##
## EASY is one the first time and the default, because the Hollow's own numbers
## (ten bodies a post, ten times a body's kit) are a punishment for a band that
## has never been down it. HARD is the floor as it always was, with twice the pool
## and twice the speed.
##
## The choice is warband state (`WarbandDelve.mode`), saved with the books and lent
## with them, so a host and every guest build the same floor.

const EASY := "easy"
const MEDIUM := "medium"
const HARD := "hard"
## What the mouth opens on, and what a file without a mode reads as.
const DEFAULT := EASY
const ORDER: Array[String] = [EASY, MEDIUM, HARD]

## Each difficulty's three dials and the one line the mouth reads:
##   `crowd` - the share of a den's per-post crowd that stands (rounded, never
##             below one body a post);
##   `life`  - the multiplier on a body's pool;
##   `rate`  - the multiplier on its walk and run, and the divisor of its swing
##             cadence, so 2.0 swings in half the time;
##   `line`  - what the panel says the floor will be.
const TUNING := {
	EASY: {"crowd": 1.0 / 3.0, "life": 0.5, "rate": 1.0,
		"line": "A third of the crowd · half the pool · the speed it always fought at."},
	MEDIUM: {"crowd": 2.0 / 3.0, "life": 1.0, "rate": 1.3,
		"line": "Two thirds of the crowd · the pool it always had · a third again as fast."},
	HARD: {"crowd": 1.0, "life": 2.0, "rate": 2.0,
		"line": "Every body of the crowd · twice the pool · twice the speed."},
}


## The difficulty `mode` names, or the default for a word that is not one: an
## unknown mode in a save is a file from a build that had no difficulties.
static func id_of(mode: String) -> String:
	return mode if TUNING.has(mode) else DEFAULT


static func tuning(mode: String) -> Dictionary:
	return TUNING[id_of(mode)]


## What the mouth prints for a difficulty.
static func label_of(mode: String) -> String:
	return id_of(mode).to_upper()


## The sentence under the toggle: what the floor will be.
static func line_of(mode: String) -> String:
	return str(tuning(mode)["line"])


## How many bodies a post's crowd stands on a floor of this difficulty: `base` (the
## den's own per-post crowd) scaled by the difficulty's share, rounded, and never
## below one - a hall that fields one body still fields one.
static func crowd_of(base: int, mode: String) -> int:
	return maxi(1, roundi(float(maxi(1, base)) * float(tuning(mode)["crowd"])))


## What a body's pool is multiplied by.
static func life_of(mode: String) -> float:
	return float(tuning(mode)["life"])


## What a body's walk, run and swing cadence are multiplied by (the cadence is
## divided by it: a rate of 2.0 is twice as many blows).
static func rate_of(mode: String) -> float:
	return float(tuning(mode)["rate"])
