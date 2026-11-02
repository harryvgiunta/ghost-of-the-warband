extends RefCounted
## Shared stamina pool and drain rates.
##
## The frontier, arena and delve all spend the same resource. Keep the pool
## here so the HUDs, the actors and the ability costs cannot drift apart.

const MAX := 1000.0
const SPRINT_DRAIN_PER_SECOND := 19.0
const REGEN_PER_SECOND := 13.0
const SPRINT_RESUME := 25.0
const SPRINT_EXHAUSTED := 1.0
## A raised guard is held with the whole body: it drains faster than the pool
## knits back (13/s), so holding one through a fight is a losing trade. The blow
## a guard actually stops is charged again on top of this, in `Combat`.
const GUARD_DRAIN_PER_SECOND := 20.0
## The pool a fighter needs before an arm will come up. Below it the guard is
## refused outright, so a spent body cannot raise one and a break cannot be
## undone by holding the button.
const GUARD_MIN := 25.0
