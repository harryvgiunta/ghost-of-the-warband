extends RefCounted
## Catalog weapon ids carried by humanoid mobs. The role names match
## `devil_visual.gd` and the enemy weapon profiles, so a death drop is always
## the piece the mob was actually holding.

const ITEMS := {
	"dagger":"dagger_iron",
	"sword":"sword_short",
	"bow":"bow_recurve",
}

static func item_id(role: String) -> String:
	return str(ITEMS.get(role.to_lower(), ""))
