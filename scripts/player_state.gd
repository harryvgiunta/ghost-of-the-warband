extends Node
## The item catalog every piece of gear is read from, the keepers' stock, and
## the warband's purse (`credits`), persisted in `user://player_state.json`.

signal changed

const ArmorData = preload("res://scripts/armor_data.gd")
const TrinketStats = preload("res://scripts/trinket_stats.gd")
const AbilityRules = preload("res://scripts/ability_rules.gd")

## A new-game purse large enough to buy any keeper stock outright.
const STARTING_CREDITS := 99999
const DEFAULT_SAVE_PATH := "user://player_state.json"

const ITEMS := {
	"bow_short": {"name":"Shortbow", "short":"Shortbow", "kind":"bow", "index":0, "price":120,
		"category":"bow", "grip":"bow", "slot":"main",
		"summary":"Quick ashwood scout bow",
		"detail":"30 damage at full draw / 1.0 s draw / light and fast"},
	"bow_recurve": {"name":"Recurve", "short":"Recurve", "kind":"bow", "index":1, "price":220,
		"category":"bow", "grip":"bow", "slot":"main",
		"summary":"Balanced horn-and-yew recurve",
		"detail":"38 damage at full draw / 2.0 s draw / all-round draw"},
	"bow_long": {"name":"Longbow", "short":"Longbow", "kind":"bow", "index":2, "price":360,
		"category":"bow", "grip":"bow", "slot":"main",
		"summary":"Heavy heartwood war bow",
		"detail":"50 damage at full draw / 3.0 s draw / slow but crushing"},
	"sword_short": {"name":"Shortsword", "short":"Shortswd", "kind":"sword", "index":0, "price":110,
		"category":"1h", "grip":"1h", "slot":"main",
		"summary":"A compact camp blade",
		"detail":"30 damage / 1.0 s swing / 1.8 m reach"},
	"sword_arming": {"name":"Arming sword", "short":"Arming", "kind":"sword", "index":1, "price":195,
		"category":"1h", "grip":"1h", "slot":"main",
		"summary":"A soldier's balanced sidearm",
		"detail":"38 damage / 2.0 s swing / 2.1 m reach"},
	"sword_great": {"name":"Greatsword", "short":"Greatswd", "kind":"sword", "index":2, "price":340,
		"category":"2h", "grip":"2h", "slot":"main",
		"summary":"A deliberate two-handed cut",
		"detail":"50 damage / 3.0 s swing / 2.5 m reach"},
	"dagger_iron": {"name":"Iron Dagger", "short":"Dagger", "kind":"dagger", "index":0, "price":70,
		"category":"1h", "grip":"1h", "slot":"main",
		"summary":"A short iron blade balanced for the off hand",
		"detail":"14 damage / 0.5 s stab / 1.2 m reach / weak guard / +200% forward stab"},
	"sword_makeshift": {"name":"Makeshift Cleaver", "short":"Msh Cleaver", "kind":"sword", "index":0, "price":6,
		"category":"1h", "grip":"1h", "slot":"main",
		"summary":"A split branch with a knapped flint edge, bound in sinew",
		"detail":"30 damage / 1.0 s swing / 1.8 m reach / the salvage short blade"},
	# The makeshift tier: what a prisoner actually carries out of the wood. Every
	# piece is worse than the cheapest forged steel, because the whole point of the
	# opening is that a body is not yet a fighter.
	"dagger_ironwood": {"name":"Ironwood Shiv", "short":"Iwd Shiv", "kind":"dagger", "index":1, "price":4,
		"category":"1h", "grip":"1h", "slot":"main",
		"summary":"A split ironwood stave whittled to a point and bound in gut",
		"detail":"10 damage / 0.55 s stab / 1.15 m reach / weak guard / +200% forward stab / off-hand legal"},
	"bow_twig": {"name":"Twig Bow", "short":"Twig Bow", "kind":"bow", "index":3, "price":3,
		"category":"bow", "grip":"bow", "slot":"main",
		"summary":"A green sapling and a length of cord",
		"detail":"5 damage at full draw / 0.7 s draw / it will put an arrow in the wood"},
	# Ammunition. A shaft is a carried piece, never a worn one: the shared stash
	# counts them, one leaves the quiver for every arrow a bow looses, a trail
	# archer's corpse is worth bending over for, and a keeper sells them by the
	# bunch (`bundle` at the generic price, so a sale still pays per shaft).
	"arrow": {"name":"Arrow", "short":"Arrow", "kind":"arrow", "index":0, "price":2,
		"category":"ammo", "slot":"", "bundle":10, "material":"Shaft",
		"summary":"An ash shaft, an iron head and goose fletching",
		"detail":"One shaft per loosed arrow / sold by the bunch of ten"},
	"club_makeshift": {"name":"Club", "short":"Club", "kind":"sword", "index":3, "price":4,
		"category":"1h", "grip":"1h", "slot":"main",
		"summary":"A knotted length of heartwood with the root still on it",
		"detail":"6 damage / 0.9 s swing / 1.7 m reach / one hand"},
	"branch_heavy": {"name":"Heavy Tree Branch", "short":"Hvy Branch", "kind":"sword", "index":4, "price":5,
		"category":"2h", "grip":"2h", "slot":"main",
		"summary":"A whole limb, bark and all, swung with both hands",
		"detail":"15 damage / 1.6 s swing / 2.0 m reach / two-handed"},
	"shield_wood": {"name":"Wooden Shield", "short":"Wood Shld", "kind":"shield", "index":3, "price":5,
		"category":"shield", "slot":"off",
		"summary":"Planks off a hut wall, lashed to a forearm",
		"detail":"Off hand only / light front block / pairs with a one-hander"},
	"bandage_linen": {"name":"Linen Bandage", "short":"Bandage", "kind":"bandage", "index":0, "price":6,
		"category":"misc", "slot":"", "heal":0.3,
		"summary":"A strip of boiled linen, folded and tied off",
		"detail":"Field dressing / not worn / closes a wound in the shared stash"},
	# Salvage off the briar wolves. They are carried, never worn - the warband
	# strips a pelt in the field and the shared stash counts it - and they are
	# what a kill is worth in the wood now that the wolves have no blade to drop.
	"wolf_pelt": {"name":"Wolf Pelt", "short":"Pelt", "kind":"material", "index":0, "price":12,
		"category":"misc", "slot":"", "material":"Hide",
		"summary":"A briar pelt, still warm off the ribs",
		"detail":"Carried in the shared stash / cut for leather and cloaks"},
	"wolf_bone": {"name":"Wolf Bone", "short":"Bone", "kind":"material", "index":1, "price":9,
		"category":"misc", "slot":"", "material":"Bone",
		"summary":"A long shank split for the marrow",
		"detail":"Carried in the shared stash / stock for hafts and charms"},
	"wolf_tooth": {"name":"Wolf Tooth", "short":"Tooth", "kind":"material", "index":2, "price":14,
		"category":"misc", "slot":"", "material":"Fang",
		"summary":"One briar fang, yellow at the root",
		"detail":"Carried in the shared stash / a ward strung on a thong"},
	"wolf_paw": {"name":"Wolf Paw", "short":"Paw", "kind":"material", "index":3, "price":16,
		"category":"misc", "slot":"", "material":"Trophy",
		"summary":"Four claws on a severed paw, corded to a leather loop",
		"detail":"Carried in the shared stash / proof of the hunt"},
	# The watchers' own blood, drawn off a warden's body: the reagent the altar
	# works into steel. It is a carried item, not a wallet - the wallet is the
	# altar's Cruor, and the two are deliberately different things.
	"ichor_vial": {"name":"Warden's Ichor", "short":"Ichor", "kind":"material", "index":4, "price":60,
		"category":"misc", "slot":"", "material":"Reagent", "reagent":true,
		"summary":"Black ichor in a stoppered vial. It is still moving",
		"detail":"Carried in the shared stash / anoints a weapon with its skill at the altar"},
	"staff_fire": {"name":"Ember Staff", "short":"Ember Stf", "kind":"staff", "index":0, "price":240,
		"category":"staff", "grip":"staff", "slot":"main",
		"summary":"A charred staff crowned with a live ember",
		"detail":"Two-handed / casts from the main hand / locks the off hand"},
	"staff_bone": {"name":"Bone Staff", "short":"Bone Stf", "kind":"staff", "index":1, "price":320,
		"category":"staff", "grip":"staff", "slot":"main",
		"summary":"A tall staff of lashed bone and sinew",
		"detail":"Two-handed / heavier focus / locks the off hand"},
	"shield_buckler": {"name":"Buckler", "short":"Buckler", "kind":"shield", "index":0, "price":90,
		"category":"shield", "slot":"off",
		"summary":"A small steel boss for the off hand",
		"detail":"Off hand only / light front block / pairs with a one-hander"},
	"shield_kite": {"name":"Kite Shield", "short":"Kite Shld", "kind":"shield", "index":1, "price":170,
		"category":"shield", "slot":"off",
		"summary":"A tall shield tapering to a point",
		"detail":"Off hand only / full front block / pairs with a one-hander"},
	"shield_tower": {"name":"Tower Shield", "short":"Tower Shld", "kind":"shield", "index":2, "price":280,
		"category":"shield", "slot":"off",
		"summary":"A door of banded oak and iron",
		"detail":"Off hand only / the heaviest front block"},
	"focus_tome": {"name":"Ash Tome", "short":"Tome", "kind":"focus", "index":0, "price":110,
		"category":"focus", "slot":"off", "focus":"tome",
		"summary":"A soot-stained book of quiet words",
		"detail":"Off hand only / focuses a staff's casting"},
	"torch_hand": {"name":"Hand Torch", "short":"Torch", "kind":"torch", "index":0, "price":45,
		"category":"focus", "slot":"off", "focus":"torch",
		"summary":"A pitch-soaked brand, burning steadily",
		"detail":"Off hand only / lights the wood around you / no block"},
	"focus_skull": {"name":"Bone Skull", "short":"Skull", "kind":"focus", "index":1, "price":150,
		"category":"focus", "slot":"off", "focus":"skull",
		"summary":"A bleached skull bound in copper wire",
		"detail":"Off hand only / a heavy focus for a staff"},
	"focus_skull_life": {"name":"Skull of Life", "short":"Life Skull", "kind":"focus", "index":2, "price":260,
		"category":"focus", "slot":"off", "focus":"skull_life",
		"summary":"A skull with green coals sunk in its sockets",
		"detail":"Off hand only / +15 life on every kill"},
	"focus_skull_death": {"name":"Skull of Death", "short":"Death Skull", "kind":"focus", "index":3, "price":260,
		"category":"focus", "slot":"off", "focus":"skull_death",
		"summary":"A skull lit violet from the inside",
		"detail":"Off hand only / +15 stamina on every kill"},
	"neck_ember": {"name":"Ember Charm", "short":"Ember Chm", "kind":"neck", "index":0, "price":120,
		"category":"jewelry", "slot":"neck",
		"summary":"A warm cinder on a leather cord",
		"detail":"Neck only / keeps a little hearth-fire with you"},
	"neck_bone": {"name":"Bone Talisman", "short":"Bone Talm", "kind":"neck", "index":1, "price":80,
		"category":"jewelry", "slot":"neck",
		"summary":"A knuckle of something old on a thong",
		"detail":"Neck only / a quiet ward against the dark"},
	"neck_shield": {"name":"Amulet of Energy Shield", "short":"Shield Amulet", "kind":"neck", "index":2, "price":340,
		"category":"jewelry", "slot":"neck",
		"summary":"A yellow lodestone humming on a woven cord",
		"detail":"Neck only / grants Energy Shield (SHIFT + 3) / 1 min"},
	"ring_copper": {"name":"Copper Ring", "short":"Cu Ring", "kind":"ring", "index":0, "price":40,
		"category":"jewelry", "slot":"ring",
		"summary":"A soft hammered band",
		"detail":"Ring slot only / fits either hand"},
	"ring_silver": {"name":"Silver Ring", "short":"Ag Ring", "kind":"ring", "index":1, "price":95,
		"category":"jewelry", "slot":"ring",
		"summary":"A pale band etched with thornwork",
		"detail":"Ring slot only / fits either hand"},
	"ring_blood": {"name":"Bloodstone Ring", "short":"Blood Ring", "kind":"ring", "index":2, "price":160,
		"category":"jewelry", "slot":"ring",
		"summary":"A dark stone set in old gold",
		"detail":"Ring slot only / fits either hand"},
	"ring_dash": {"name":"Ring of Dash", "short":"Dash Ring", "kind":"ring", "index":3, "price":260,
		"category":"jewelry", "slot":"ring",
		"summary":"A cold iron band that leans the moment you look away",
		"detail":"Ring slot only / grants the Dash skill (SHIFT + 3)"},
	"ring_health": {"name":"Ring of Health", "short":"Health Ring", "kind":"ring", "index":4, "price":180,
		"category":"jewelry", "slot":"ring",
		"summary":"Warm as a pulse you can hold",
		"detail":"Ring slot only / +25 max health"},
	"ring_ranged": {"name":"Ring of Ranged Damage", "short":"Range Ring", "kind":"ring", "index":5, "price":210,
		"category":"jewelry", "slot":"ring",
		"summary":"A knapped obsidian flake in a horn setting",
		"detail":"Ring slot only / +10% ranged damage"},
	"ring_melee": {"name":"Ring of Melee Damage", "short":"Melee Ring", "kind":"ring", "index":6, "price":210,
		"category":"jewelry", "slot":"ring",
		"summary":"Iron from a broken blade, worn smooth",
		"detail":"Ring slot only / +10% melee damage"},
	"ring_swift": {"name":"Ring of the Swift", "short":"Swift Ring", "kind":"ring", "index":7, "price":200,
		"category":"jewelry", "slot":"ring",
		"summary":"It is always a little ahead of your hand",
		"detail":"Ring slot only / +8% movement speed"},
	"ring_haste": {"name":"Ring of Haste", "short":"Haste Ring", "kind":"ring", "index":8, "price":240,
		"category":"jewelry", "slot":"ring",
		"summary":"The gold never quite settles",
		"detail":"Ring slot only / +12% attack speed"},
	"ring_vigor": {"name":"Ring of Vigor", "short":"Vigor Ring", "kind":"ring", "index":9, "price":200,
		"category":"jewelry", "slot":"ring",
		"summary":"Set with a seed that refuses to dry",
		"detail":"Ring slot only / +150 max stamina"},
	"ring_tide": {"name":"Ring of the Tide", "short":"Tide Ring", "kind":"ring", "index":10, "price":170,
		"category":"jewelry", "slot":"ring",
		"summary":"Green enamel over a spiral of wire",
		"detail":"Ring slot only / +30% stamina regeneration"},
	"ring_ward": {"name":"Ring of Warding", "short":"Ward Ring", "kind":"ring", "index":11, "price":230,
		"category":"jewelry", "slot":"ring",
		"summary":"A ring of blackened silver that rings when struck",
		"detail":"Ring slot only / +6% damage reduction"},
	"ring_bounty": {"name":"Ring of Bounty", "short":"Bounty Ring", "kind":"ring", "index":12, "price":180,
		"category":"jewelry", "slot":"ring",
		"summary":"A merchant's seal melted into a band",
		"detail":"Ring slot only / +25% gold from kills"},
	"ring_thrower": {"name":"Ring of Throwing", "short":"Throw Ring", "kind":"ring", "index":13, "price":190,
		"category":"jewelry", "slot":"ring",
		"summary":"Balanced so well it argues with your wrist",
		"detail":"Ring slot only / +25% thrown damage"},
	"ring_echo": {"name":"Ring of Echoes", "short":"Echo Ring", "kind":"ring", "index":14, "price":230,
		"category":"jewelry", "slot":"ring",
		"summary":"A hollow band that answers a half-breath late",
		"detail":"Ring slot only / -15% skill cooldown"},
	"ring_ironhide": {"name":"Ring of Ironhide", "short":"Iron Ring", "kind":"ring", "index":15, "price":150,
		"category":"jewelry", "slot":"ring",
		"summary":"Three links of a mail shirt that lost the rest",
		"detail":"Ring slot only / +20 max health / +2% damage reduction"},
	"ring_grit": {"name":"Ring of Grit", "short":"Grit Ring", "kind":"ring", "index":16, "price":190,
		"category":"jewelry", "slot":"ring",
		"summary":"Leather and wire, chewed flat",
		"detail":"Ring slot only / -25% stagger suffered"},
	"armor_leather_head": {"name":"Leather Hood", "short":"L Hood", "kind":"head", "index":0, "set":0, "price":10,
		"category":"armor", "slot":"head",
		"summary":"A soft hood stained by the road",
		"detail":"No mobility penalty"},
	"armor_leather_chest": {"name":"Leather Jerkin", "short":"L Jerkin", "kind":"chest", "index":0, "set":0, "price":15,
		"category":"armor", "slot":"chest",
		"summary":"Cured hide over a wool shirt",
		"detail":"The road-worn ranger cut"},
	"armor_leather_hands": {"name":"Leather Gloves", "short":"L Gloves", "kind":"hands", "index":0, "set":0, "price":8,
		"category":"armor", "slot":"hands",
		"summary":"Close-fitting riding gloves",
		"detail":"Fingers stay free for the string"},
	"armor_leather_legs": {"name":"Leather Trousers", "short":"L Trousers", "kind":"legs", "index":0, "set":0, "price":12,
		"category":"armor", "slot":"legs",
		"summary":"Reinforced leather leggings",
		"detail":"Full stride"},
	"armor_leather_feet": {"name":"Leather Boots", "short":"L Boots", "kind":"feet", "index":0, "set":0, "price":10,
		"category":"armor", "slot":"feet",
		"summary":"Tall boots with cracked soles",
		"detail":"Quiet footing"},
	"armor_mail_head": {"name":"Mail Coif", "short":"M Coif", "kind":"head", "index":1, "set":1, "price":35,
		"category":"armor", "slot":"head",
		"summary":"Riveted rings draped over the shoulders",
		"detail":"Rings cover the neck"},
	"armor_mail_chest": {"name":"Mail Hauberk", "short":"M Hauberk", "kind":"chest", "index":1, "set":1, "price":55,
		"category":"armor", "slot":"chest",
		"summary":"A heavy hauberk split for riding",
		"detail":"Sleeves and skirt"},
	"armor_mail_hands": {"name":"Mail Mittens", "short":"M Mittens", "kind":"hands", "index":1, "set":1, "price":25,
		"category":"armor", "slot":"hands",
		"summary":"Ring mittens with leather palms",
		"detail":"Grip stays usable"},
	"armor_mail_legs": {"name":"Mail Chausses", "short":"M Chausses", "kind":"legs", "index":1, "set":1, "price":40,
		"category":"armor", "slot":"legs",
		"summary":"Riveted leg hose with leather straps",
		"detail":"Flexible across the knee"},
	"armor_mail_feet": {"name":"Mail Sabatons", "short":"M Sabatons", "kind":"feet", "index":1, "set":1, "price":25,
		"category":"armor", "slot":"feet",
		"summary":"Ring shoes over stitched leather soles",
		"detail":"Quiet under mail"},
	"armor_plate_head": {"name":"Warden Sallet", "short":"P Sallet", "kind":"head", "index":2, "set":2, "price":65,
		"category":"armor", "slot":"head",
		"summary":"Blackened steel sallet with a raised brow",
		"detail":"Open face for the bow"},
	"armor_plate_chest": {"name":"Warden Cuirass", "short":"P Cuirass", "kind":"chest", "index":2, "set":2, "price":90,
		"category":"armor", "slot":"chest",
		"summary":"Articulated breast, back and faulds",
		"detail":"The wardens’ blackened steel"},
	"armor_plate_hands": {"name":"Warden Gauntlets", "short":"P Gauntlets", "kind":"hands", "index":2, "set":2, "price":45,
		"category":"armor", "slot":"hands",
		"summary":"Articulated finger lames and cuff",
		"detail":"A closed grip around a hilt"},
	"armor_plate_legs": {"name":"Warden Cuisses", "short":"P Cuisses", "kind":"legs", "index":2, "set":2, "price":80,
		"category":"armor", "slot":"legs",
		"summary":"Cuisses, poleyns, greaves and tassets",
		"detail":"Heavy but planted"},
	"armor_plate_feet": {"name":"Warden Sabatons", "short":"P Sabatons", "kind":"feet", "index":2, "set":2, "price":40,
		"category":"armor", "slot":"feet",
		"summary":"Pointed steel lames over the foot",
		"detail":"Weighted heel"},
	"armor_cloth_head": {"name":"Emberweave Hood", "short":"C Hood", "kind":"head", "index":3, "set":3, "price":25,
		"category":"armor", "slot":"head",
		"summary":"A deep hood with a tattered mantle",
		"detail":"Shadow for the face"},
	"armor_cloth_chest": {"name":"Emberweave Robe", "short":"C Robe", "kind":"chest", "index":3, "set":3, "price":45,
		"category":"armor", "slot":"chest",
		"summary":"Layered cloth with wide sleeves",
		"detail":"Woven for long marches"},
	"armor_cloth_hands": {"name":"Emberweave Wraps", "short":"C Wraps", "kind":"hands", "index":3, "set":3, "price":20,
		"category":"armor", "slot":"hands",
		"summary":"Cloth wraps over fingerless gloves",
		"detail":"Chalk and candle wax"},
	"armor_cloth_legs": {"name":"Emberweave Skirt", "short":"C Skirt", "kind":"legs", "index":3, "set":3, "price":35,
		"category":"armor", "slot":"legs",
		"summary":"A long split skirt with a torn hem",
		"detail":"Moves with the stride"},
	"armor_cloth_feet": {"name":"Emberweave Boots", "short":"C Boots", "kind":"feet", "index":3, "set":3, "price":15,
		"category":"armor", "slot":"feet",
		"summary":"Soft boots with cloth cuffs",
		"detail":"Made for quiet steps"},
	"armor_makeshift_head": {"name":"Makeshift Antler Helm", "short":"Msh Helm", "kind":"head", "index":4, "set":4, "price":6,
		"category":"armor", "slot":"head",
		"summary":"A bark shell crowned with a split antler",
		"detail":"Salvage bones lashed over the crown"},
	"armor_makeshift_chest": {"name":"Makeshift Bark Cuirass", "short":"Msh Cuirass", "kind":"chest", "index":4, "set":4, "price":9,
		"category":"armor", "slot":"chest",
		"summary":"Laced bark plates over a cured hide vest",
		"detail":"The first thing the forest gives back"},
	"armor_makeshift_hands": {"name":"Makeshift Thorn Gauntlets", "short":"Msh Gauntlets", "kind":"hands", "index":4, "set":4, "price":5,
		"category":"armor", "slot":"hands",
		"summary":"Hide wraps studded with bone thorns",
		"detail":"Thorns out, fingers free"},
	"armor_makeshift_legs": {"name":"Makeshift Hide Leggings", "short":"Msh Leggings", "kind":"legs", "index":4, "set":4, "price":7,
		"category":"armor", "slot":"legs",
		"summary":"Hide leggings strapped with bark knee plates",
		"detail":"Kneel in the briar, get up again"},
	"armor_makeshift_feet": {"name":"Makeshift Root Boots", "short":"Msh Boots", "kind":"feet", "index":4, "set":4, "price":5,
		"category":"armor", "slot":"feet",
		"summary":"Bark soles held on by living root straps",
		"detail":"Split toe, quiet footing"},
	# The naked set: an old shirt and a pair of shorts, and bare skin everywhere
	# else. It is what the warband is wearing when the game opens, it guards
	# nothing, and the four empty-looking slots exist so a body can be undressed
	# back to skin after looting anything better.
	"armor_naked_head": {"name":"Bare head", "short":"Bare head", "kind":"head", "index":5, "set":5, "price":1,
		"category":"armor", "slot":"head",
		"summary":"Hair, and whatever the wood has left of it",
		"detail":"No cover at all"},
	"armor_naked_chest": {"name":"Old Shirt", "short":"Shirt", "kind":"chest", "index":5, "set":5, "price":1,
		"category":"armor", "slot":"chest",
		"summary":"A washed-out linen shirt, long past its owner",
		"detail":"No cover at all / stops nothing"},
	"armor_naked_hands": {"name":"Bare hands", "short":"Bare hands", "kind":"hands", "index":5, "set":5, "price":1,
		"category":"armor", "slot":"hands",
		"summary":"Rope burns, split knuckles, nothing else",
		"detail":"No cover at all"},
	"armor_naked_legs": {"name":"Tight Shorts", "short":"Shorts", "kind":"legs", "index":5, "set":5, "price":1,
		"category":"armor", "slot":"legs",
		"summary":"Coarse cloth cut off at the thigh",
		"detail":"No cover at all / full stride"},
	"armor_naked_feet": {"name":"Bare feet", "short":"Bare feet", "kind":"feet", "index":5, "set":5, "price":1,
		"category":"armor", "slot":"feet",
		"summary":"Soles hardened by every road in the wood",
		"detail":"No cover at all"},
}
## Item ids that were renamed or folded into another piece. Saves, the warband
## stash and the roster all read ids off disk, so one table maps every dead id to
## the piece that replaced it and nothing is silently dropped on load.
const LEGACY_ITEM_ALIASES := {
	"dagger_makeshift": "dagger_ironwood",
}

## The id an old save actually means. Unknown ids are returned untouched so the
## caller's own validation stays the only gate.
static func migrate_item_id(item_id: String) -> String:
	return str(LEGACY_ITEM_ALIASES.get(item_id, item_id))

const VENDORS := [
	{"name":"Storekeeper Orla", "tag":"STORE", "line":"Bows, staves and trail goods.", "stock":[
		"bow_short","bow_recurve","bow_long","staff_fire","staff_bone","arrow",
	]},
	{"name":"Smith Brann", "tag":"SMITH", "line":"Swords, daggers and shields balanced on the anvil.", "stock":[
		"sword_makeshift","dagger_ironwood","bow_twig","club_makeshift","branch_heavy",
		"sword_short","sword_arming","sword_great","dagger_iron",
		"shield_buckler","shield_kite","shield_tower","shield_wood","arrow",
	]},
	{"name":"Quartermaster Vey", "tag":"QUARTERMASTER", "line":"Armor for the long patrol. Buy the pieces you need.", "stock":[
		"armor_naked_head","armor_naked_chest","armor_naked_hands","armor_naked_legs","armor_naked_feet",
		"armor_makeshift_head","armor_makeshift_chest","armor_makeshift_hands","armor_makeshift_legs","armor_makeshift_feet",
		"armor_leather_head","armor_leather_chest","armor_leather_hands","armor_leather_legs","armor_leather_feet",
		"armor_mail_head","armor_mail_chest","armor_mail_hands","armor_mail_legs","armor_mail_feet",
		"armor_plate_head","armor_plate_chest","armor_plate_hands","armor_plate_legs","armor_plate_feet",
		"armor_cloth_head","armor_cloth_chest","armor_cloth_hands","armor_cloth_legs","armor_cloth_feet",
		"focus_tome","focus_skull","neck_ember","neck_bone","neck_shield",
		"ring_copper","ring_silver","ring_blood","ring_dash","ring_health","ring_ranged",
		"ring_melee","ring_swift","ring_haste","ring_vigor","ring_tide","ring_ward",
		"ring_bounty","ring_thrower","ring_echo","ring_ironhide","ring_grit",
		"focus_skull_life","focus_skull_death",
	]},
]

var credits := STARTING_CREDITS
var save_path := DEFAULT_SAVE_PATH

func _ready() -> void:
	# Script-mode regressions must not read or overwrite a player's real purse.
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = "user://player_state_test.json"
		reset(false)
		return
	load_state()

## How many copies one visit to a keeper's shelf hands over. Ammunition is the
## only piece sold in a bunch; every other row is one piece at a time. Static
## because the warband and the keeper board both ask it without an instance.
static func item_bundle(id: String) -> int:
	return maxi(int((ITEMS.get(id, {}) as Dictionary).get("bundle", 1)), 1)

## Build the exact loadout shape consumed by Archer.apply_loadout(). Pure:
## derives everything from the ids and the armor index map.
## `anointed_ids` are the catalog ids the altar has anointed: a held piece in
## that list carries its skill onto the rig (`anointed`); every other piece,
## stock steel included, is plain.
static func build_loadout(main_id: String, off_id: String, armor_pieces: Dictionary,
		trinket_ids: Dictionary = {}, anointed_ids: Array = []) -> Dictionary:
	var armor := {}
	for slot in ArmorData.SLOTS:
		armor[slot] = int(armor_pieces.get(slot, ArmorData.NONE))
	var main: Dictionary = ITEMS.get(main_id, {})
	var main_category := str(main.get("category", ""))
	var main_kind := str(main.get("kind", ""))
	var weapon := ""
	var bow := 0
	var sword := 0
	var staff := -1
	var dagger := 0
	if main_category == "bow":
		weapon = "bow"
		bow = int(main.get("index", 0))
	elif main_kind == "sword" and (main_category == "1h" or main_category == "2h"):
		weapon = "sword"
		sword = int(main.get("index", 0))
	elif main_kind == "dagger":
		weapon = "dagger"
		dagger = int(main.get("index", 0))
	elif main_category == "staff":
		weapon = "sword"
		sword = 2
		staff = int(main.get("index", 0))
	var off: Dictionary = ITEMS.get(off_id, {})
	var off_category := str(off.get("category", ""))
	var shield := false
	var focus := {}
	var off_weapon := {}
	if off_category == "shield":
		shield = true
	elif off_category == "focus":
		focus = {"kind":str(off.get("focus", "tome")), "index":int(off.get("index", 0))}
	elif off_category == "1h":
		var off_kind := str(off.get("kind", ""))
		if off_kind == "sword" or off_kind == "dagger":
			off_weapon = {"kind":off_kind, "index":int(off.get("index", 0))}
	return {
		"main":main_id, "off":off_id, "weapon":weapon,
		"bow":bow, "sword":sword, "staff":staff, "dagger":dagger,
		"armor":armor, "shield":shield, "off_weapon":off_weapon, "focus":focus,
		"trinkets":TrinketStats.kit(trinket_ids) if not trinket_ids.is_empty() \
			else {"neck":"", "ring1":"", "ring2":"", "off":off_id},
		"anointed":{"main":_anointed_skill(main_id, 0, anointed_ids),
			"off":_anointed_skill(off_id, 1, anointed_ids)},
	}

## The skill a held piece carries onto the rig: its own, fired from the hand it
## is held in, and only while the altar's ledger lists it. An off-hand blade
## carries nothing, because its skill is a main-hand one.
static func _anointed_skill(item_id: String, slot: int, anointed_ids: Array) -> String:
	if item_id.is_empty() or not anointed_ids.has(item_id):
		return ""
	var entry: Dictionary = ITEMS.get(item_id, {})
	if AbilityRules.hand_slot(entry) != slot:
		return ""
	return str(AbilityRules.skill_for(entry).get("id", ""))

func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("state", message, data)

## A new campaign starts with the starting purse.
func reset(persist: bool = true) -> void:
	_note("reset", {"persist": persist, "path": save_path})
	credits = STARTING_CREDITS
	if persist:
		_commit()
	else:
		changed.emit()

func add_credits(amount: int) -> void:
	if amount == 0:
		return
	credits = maxi(0, credits + amount)
	_commit()

func _commit() -> void:
	changed.emit()
	save_state()

func save_state() -> void:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_note("save_failed", {"path": save_path, "error": error_string(FileAccess.get_open_error())})
		push_warning("Could not write player state to %s" % save_path)
		return
	file.store_string(JSON.stringify({"credits":credits}))
	file.close()
	_note("save", {"path": save_path, "credits": credits})

## Only the purse is read back; any other key an older file carries is ignored.
func load_state() -> void:
	if not FileAccess.file_exists(save_path):
		_note("load_missing", {"path": save_path})
		reset(false)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_note("load_failed", {"path": save_path})
		push_warning("Ignoring unreadable player state at %s" % save_path)
		reset(false)
		return
	var data: Dictionary = parsed
	credits = maxi(0, int(data.get("credits", STARTING_CREDITS)))
	_note("load", {"path": save_path, "credits": credits})
	changed.emit()
