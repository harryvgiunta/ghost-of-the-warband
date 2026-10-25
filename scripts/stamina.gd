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
