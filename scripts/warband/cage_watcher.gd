extends "res://scripts/forest_mob.gd"
## The camp's watchers: the antlered hollow wardens, thinned for the first fight.
##
## The tutorial's two gate guards used to be full arena bodies in cult colours -
## armoured, parrying, hundred-health fighters that read as red statues and took
## a dozen swings. They are now the woodland's own watcher silhouette (the
## antlered hollow warden) with a camp profile: thirty-six health, so three
## dagger stabs (and a headshot coin-flip) put one down, and a slow, light swing
## that cannot delete a prisoner before they learn to block.
##
## Only the profile changes. The state machine, senses, pack alarm and death
## presentation are the shared wilderness ones, so these are real enemies rather
## than props.

const Contracts = preload("res://scripts/warband/warband_contracts.gd")

## Three stabs of a makeshift shiv (14) with no headshot is 42, so 36 health
## leaves a little room for a weak block or a miss without a fourth swing.
const WATCHER_HEALTH := 36.0
const WATCHER_DAMAGE := 5.0

func _profiles() -> Dictionary:
	# The parent returns its `const` table, which is read-only: duplicate before
	# tuning a camp copy of the warden.
	var table: Dictionary = (super._profiles() as Dictionary).duplicate(true)
	if not table.has("hollow_warden"):
		return table
	var warden: Dictionary = (table["hollow_warden"] as Dictionary).duplicate(true)
	warden["display"] = "Camp watcher"
	warden["health"] = WATCHER_HEALTH
	warden["damage"] = WATCHER_DAMAGE
	warden["cooldown"] = 2.4
	warden["windup"] = 0.45
	warden["recover"] = 0.55
	warden["sight"] = 18.0
	warden["gold"] = 0
	warden["packed"] = false
	warden["run_speed"] = 3.2
	table["hollow_warden"] = warden
	return table
