extends Node
## Persistent out-of-raid state: the ranger's backpack, stash, purse and the ten
## equipment slots. Equipment is separate from the backpack; the hub owns the
## authoritative copy and matches only read the initial loadout.

signal changed

const ArmorData = preload("res://scripts/armor_data.gd")
const EquipmentRules = preload("res://scripts/equipment_rules.gd")
const TrinketStats = preload("res://scripts/trinket_stats.gd")
const ItemPassives = preload("res://scripts/item_passives.gd")
const Hitbox = preload("res://scripts/hitbox.gd")

const INVENTORY_CAPACITY := 60
const STASH_CAPACITY := 20
## A new-game purse large enough to buy any keeper stock outright.
const STARTING_CREDITS := 99999
const SELL_RATE := 0.6
const SAVE_VERSION := 6
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
	"dagger_makeshift": {"name":"Makeshift Shiv", "short":"Msh Shiv", "kind":"dagger", "index":0, "price":4,
		"category":"1h", "grip":"1h", "slot":"main",
		"summary":"A snapped rib ground to a point and wrapped in hide",
		"detail":"14 damage / 0.5 s stab / 1.2 m reach / weak guard / +200% forward stab / off-hand legal"},
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
	"armor_leather": {"name":"Ranger leather", "short":"Ranger set", "kind":"armor", "index":0, "set":0, "price":55,
		"category":"armor_bundle",
		"summary":"The road-worn ranger outfit",
		"detail":"Legacy full set / migrated to five leather pieces"},
	"armor_mail": {"name":"Sentinel mail", "short":"Sentinel set", "kind":"armor", "index":1, "set":1, "price":180,
		"category":"armor_bundle",
		"summary":"Riveted rings under a wool coat",
		"detail":"Legacy full set / migrated to five mail pieces"},
	"armor_plate": {"name":"Warden plate", "short":"Warden set", "kind":"armor", "index":2, "set":2, "price":320,
		"category":"armor_bundle",
		"summary":"The wardens’ blackened steel",
		"detail":"Legacy full set / migrated to five plate pieces"},
}

## HUD stat lines. Weapon damage is the full-draw/full-swing body hit; the max
## shown to the player is the same hit against the head zone. Keep these in
## sync with Archer's combat profiles and Combat.BASE_DAMAGE; the paperdoll
## regression asserts the pairing for every weapon.
const ITEM_STATS := {
	"bow_short": {"damage":30.0, "attack":1.0},
	"bow_recurve": {"damage":38.0, "attack":2.0},
	"bow_long": {"damage":50.0, "attack":3.0},
	"sword_short": {"damage":30.0, "attack":1.0, "reach":1.8},
	"sword_arming": {"damage":38.0, "attack":2.0, "reach":2.1},
	"sword_great": {"damage":50.0, "attack":3.0, "reach":2.5},
	"dagger_iron": {"damage":14.0, "attack":0.5, "reach":1.2},
	"sword_makeshift": {"damage":30.0, "attack":1.0, "reach":1.8},
	"dagger_makeshift": {"damage":14.0, "attack":0.5, "reach":1.2},
	"staff_fire": {"damage":50.0, "attack":3.0, "reach":1.6},
	"staff_bone": {"damage":50.0, "attack":3.0, "reach":1.5},
	"shield_buckler": {"block":18},
	"shield_kite": {"block":18},
	"shield_tower": {"block":18},
}

## One quoted flavor line per item, shown under the inspector and hover card.
const ITEM_QUOTES := {
	"bow_short": "Short enough to slip past the wood's opinion of you.",
	"bow_recurve": "The horn remembers the beast; the yew remembers the wind.",
	"bow_long": "Some bows ask politely. This one files a complaint.",
	"sword_short": "Opens letters, rations and awkward conversations.",
	"sword_arming": "Every soldier's oldest friend, and the first to be pawned.",
	"sword_great": "A sword with a mortgage and a bad temper.",
	"dagger_iron": "Small, honest, and always closer than you think.",
	"sword_makeshift": "Tree branch, flint, sinew; it will do until it does not.",
	"dagger_makeshift": "Somebody's rib. It still points where you aim it.",
	"staff_fire": "Keeps a little of the campfire angry for you.",
	"staff_bone": "Grandmother's shinbone, promoted to management.",
	"shield_buckler": "A dinner plate with ambitions.",
	"shield_kite": "The arrow's least favorite weather.",
	"shield_tower": "Mostly a wall that learned to walk.",
	"focus_tome": "All the words you'd rather not say aloud.",
	"focus_skull": "A good listener. Never interrupts. Slightly smug.",
	"neck_ember": "Still warm. Do not ask from what.",
	"neck_bone": "A small bone for a small comfort.",
	"ring_copper": "Turned green by good intentions.",
	"ring_silver": "Thornwork outside, soft heart inside.",
	"ring_blood": "The stone is dark. The gold is older.",
	"neck_shield": "A hum you feel in your teeth before the hit lands.",
	"focus_skull_life": "It keeps the last breath. Politely.",
	"focus_skull_death": "It keeps the last step. Greedily.",
	"ring_dash": "Never the first to arrive; always the first to leave.",
	"ring_health": "A second heartbeat that answers for you.",
	"ring_ranged": "Squint once with it on and you will not miss twice.",
	"ring_melee": "The forge remembers what the blade forgot.",
	"ring_swift": "The road notices it before you do.",
	"ring_haste": "Every blow arrives a heartbeat early.",
	"ring_vigor": "It has never once suggested you sit down.",
	"ring_tide": "Rest comes back faster than it should.",
	"ring_ward": "It rings, and the wound does not.",
	"ring_bounty": "Purse first, corpse after.",
	"ring_thrower": "It trusts the air more than your grip.",
	"ring_echo": "The skill remembers itself.",
	"ring_ironhide": "Small armor. Real opinions.",
	"ring_grit": "Shakes once, then refuses entirely.",
	"armor_leather_head": "Hides the face, keeps the gossip.",
	"armor_leather_chest": "Smells of rain, smoke and questionable decisions.",
	"armor_leather_hands": "Fingers free for bowstrings and bad ideas.",
	"armor_leather_legs": "Built for walking away gracefully.",
	"armor_leather_feet": "Cracked soles, dependable strides.",
	"armor_mail_head": "Rings over the ears, rumors over the rings.",
	"armor_mail_chest": "Heavy, drafty, and weirdly comforting.",
	"armor_mail_hands": "Mittens of consequence.",
	"armor_mail_legs": "Riveted hose: fashion's quiet revenge.",
	"armor_mail_feet": "Quiet steel toes. Loud first impression.",
	"armor_plate_head": "Blackened steel, open face: confident.",
	"armor_plate_chest": "Articulated like an argument, stubborn as an anvil.",
	"armor_plate_hands": "A handshake you will not forget.",
	"armor_plate_legs": "Knees of iron, heart of the same.",
	"armor_plate_feet": "Pointed enough to make a point.",
	"armor_cloth_head": "A deep hood for deep thoughts and deeper naps.",
	"armor_cloth_chest": "Wide sleeves, many secrets.",
	"armor_cloth_hands": "Wax, chalk, and the occasional fire.",
	"armor_cloth_legs": "Torn hem, untorn resolve.",
	"armor_cloth_feet": "Soft steps for hard choices.",
	"armor_makeshift_head": "The antler was not asking permission.",
	"armor_makeshift_chest": "Bark, hide and a prayer that holds.",
	"armor_makeshift_hands": "Thorns facing out, as intended.",
	"armor_makeshift_legs": "Knees of a forest that keeps standing up.",
	"armor_makeshift_feet": "Roots grip. That is the whole design.",
	"armor_leather": "The road-worn ranger, folded into one legacy box.",
	"armor_mail": "A hauberk's worth of legacy, now sold by the piece.",
	"armor_plate": "The wardens' steel, itemized and ready to be earned.",
}

const VENDORS := [
	{"name":"Storekeeper Orla", "tag":"STORE", "line":"Bows, staves and trail goods.", "stock":[
		"bow_short","bow_recurve","bow_long","staff_fire","staff_bone",
	]},
	{"name":"Smith Brann", "tag":"SMITH", "line":"Swords, daggers and shields balanced on the anvil.", "stock":[
		"sword_makeshift","dagger_makeshift",
		"sword_short","sword_arming","sword_great","dagger_iron",
		"shield_buckler","shield_kite","shield_tower",
	]},
	{"name":"Quartermaster Vey", "tag":"QUARTERMASTER", "line":"Armor for the long patrol. Buy the pieces you need.", "stock":[
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

## Every weapon in the catalog starts in the backpack. The shortbow is also the
## starting main hand, so one spare remains in the pack for the second set.
const STARTING_INVENTORY := [
	"bow_short","bow_recurve","bow_long",
	"sword_short","sword_arming","sword_great",
	"dagger_iron",
	"staff_fire","staff_bone",
	"shield_buckler","shield_kite","shield_tower",
]
## TAB is a two-slot weapon swap. Every player carries two complete weapon
## sets - a main hand and an off hand each - and exactly one is active: the
## hands hold its pair. Equipping, unequipping or dropping a weapon rewrites
## the active slot and never touches the other one, so the weapon waiting in
## the other set is always the one you left there. Pressing TAB while Set 1 is
## active brings up Set 2 and the next press brings Set 1 back.
const WEAPON_SET_COUNT := 2
const WEAPON_SETS_DEFAULT := [
	{"main":"bow_short", "off":""},
	{"main":"sword_short", "off":"shield_buckler"},
]
## Versions before 6 stored the pair TAB aimed at under `quick`; a save without
## that key started on this melee set.
const LEGACY_QUICK_DEFAULT := {"main":"sword_short", "off":"shield_buckler"}

const DEFAULTS := {
	"head":"armor_makeshift_head", "chest":"armor_makeshift_chest", "hands":"armor_makeshift_hands",
	"legs":"armor_makeshift_legs", "feet":"armor_makeshift_feet",
	"neck":"", "ring1":"", "ring2":"", "main":"bow_short", "off":"",
}

var credits := STARTING_CREDITS
var inventory: Array[String] = []
var stash: Array[String] = []
var floor_items: Array[String] = []
var equipped: Dictionary = DEFAULTS.duplicate()
var weapon_sets: Array = WEAPON_SETS_DEFAULT.duplicate(true)
var active_set := 0
var save_path := DEFAULT_SAVE_PATH

func _ready() -> void:
	# Script-mode regressions must not read or overwrite a player's real purse.
	if DisplayServer.get_name() == "headless" and OS.get_cmdline_args().has("--script"):
		save_path = "user://player_state_test.json"
		reset(false)
		return
	load_state()

func _item(id: String) -> Dictionary:
	return ITEMS.get(id, {})

func item_definition(id: String) -> Dictionary:
	return _item(id)

func item_name(id: String) -> String:
	return str(_item(id).get("name", id))

func item_short(id: String) -> String:
	return str(_item(id).get("short", id))

func item_kind(id: String) -> String:
	return str(_item(id).get("kind", ""))

func item_detail(id: String) -> String:
	return str(_item(id).get("detail", ""))

func item_summary(id: String) -> String:
	return str(_item(id).get("summary", ""))

func item_price(id: String) -> int:
	return int(_item(id).get("price", 0))

func item_category(id: String) -> String:
	return str(_item(id).get("category", ""))

func item_grip(id: String) -> String:
	return str(_item(id).get("grip", ""))

func item_slot(id: String) -> String:
	return str(_item(id).get("slot", ""))

func item_quote(id: String) -> String:
	return str(ITEM_QUOTES.get(id, ""))

func item_damage_range(id: String) -> Vector2i:
	var damage := float(ITEM_STATS.get(id, {}).get("damage", 0.0))
	if damage <= 0.0:
		return Vector2i.ZERO
	return Vector2i(int(round(damage)), int(round(damage * Hitbox.HEAD_MULTIPLIER)))

func item_attack_seconds(id: String) -> float:
	return float(ITEM_STATS.get(id, {}).get("attack", 0.0))

func item_reach(id: String) -> float:
	return float(ITEM_STATS.get(id, {}).get("reach", 0.0))

func item_block_stamina(id: String) -> int:
	return int(ITEM_STATS.get(id, {}).get("block", 0))

func item_guard_percent(id: String) -> int:
	var item := _item(id)
	if str(item.get("category", "")) != "armor":
		return 0
	var set_index := clampi(int(item.get("set", 0)), 0, ArmorData.SET_IDS.size() - 1)
	return int(round(ArmorData.reduction_for(set_index, str(item.get("slot", ""))) * 100.0))

func item_type_line(id: String) -> String:
	var item := _item(id)
	var category := str(item.get("category", ""))
	var kind := str(item.get("kind", "")).to_upper()
	if category == "bow":
		return "BOW  /  MAIN HAND"
	if category == "1h":
		return "%s  /  ONE-HAND" % kind
	if category == "2h":
		return "%s  /  TWO-HAND" % kind
	if category == "staff":
		return "STAFF  /  TWO-HAND"
	if category == "shield":
		return "SHIELD  /  OFF-HAND"
	if category == "focus":
		return "FOCUS  /  OFF-HAND"
	if category == "armor":
		var set_index := clampi(int(item.get("set", 0)), 0, ArmorData.SET_IDS.size() - 1)
		return "%s ARMOR  /  %s" % [str(ArmorData.SET_IDS[set_index]).to_upper(), ArmorData.slot_label(str(item.get("slot", ""))).to_upper()]
	if category == "jewelry":
		return "JEWELRY  /  " + ("RING" if str(item.get("slot", "")) == "ring" else "NECK")
	if category == "armor_bundle":
		return "LEGACY ARMOR SET"
	return kind

## Rows for the hover card and the inspector: label/value pairs.
func item_stat_rows(id: String) -> Array:
	var item := _item(id)
	var category := str(item.get("category", ""))
	var kind := str(item.get("kind", ""))
	var stats: Dictionary = ITEM_STATS.get(id, {})
	var rows: Array = []
	var damage := float(stats.get("damage", 0.0))
	if damage > 0.0:
		var high := int(round(damage * Hitbox.HEAD_MULTIPLIER))
		var verb := "draw" if category == "bow" else ("stab" if kind == "dagger" else "swing")
		rows.append({"label":"DAMAGE", "value":"%d–%d" % [int(round(damage)), high]})
		rows.append({"label":"ATTACK SPEED", "value":"%.1f s %s" % [float(stats.get("attack", 0.0)), verb]})
		var reach := float(stats.get("reach", 0.0))
		if reach > 0.0:
			rows.append({"label":"REACH", "value":"%.1f m" % reach})
		rows.append_array(ItemPassives.effect_rows(kind,float(stats.get("attack",0.0))))
	elif category == "shield":
		rows.append({"label":"BLOCK", "value":"Full front"})
		rows.append({"label":"STAMINA", "value":"%d per block" % item_block_stamina(id)})
	elif category == "armor":
		if str(item.get("kind", "")) == "head":
			rows.append({"label":"HEAD GUARD", "value":"%d%%" % item_guard_percent(id)})
		else:
			rows.append({"label":"BODY GUARD", "value":"+%d%%" % item_guard_percent(id)})
	elif category == "focus":
		var focus_rows := TrinketStats.effect_rows(id)
		if focus_rows.is_empty():
			rows.append({"label":"EFFECT", "value":"Cosmetic off-hand"})
		else:
			rows.append_array(focus_rows)
	elif category == "jewelry":
		var jewelry_rows := TrinketStats.effect_rows(id)
		if jewelry_rows.is_empty():
			rows.append({"label":"EFFECT", "value":"No combat effect"})
		else:
			rows.append_array(jewelry_rows)
		var grant := TrinketStats.grant_for(id)
		if not grant.is_empty():
			rows.append({"label":"SKILL", "value":"SHIFT + 3  /  %s" % grant.replace("_", " ").to_upper()})
	return rows

## One-line version for the compact inspector header.
func item_compact_stats(id: String) -> String:
	var item := _item(id)
	var category := str(item.get("category", ""))
	var stats: Dictionary = ITEM_STATS.get(id, {})
	var parts := PackedStringArray()
	var damage := float(stats.get("damage", 0.0))
	if damage > 0.0:
		var high := int(round(damage * Hitbox.HEAD_MULTIPLIER))
		parts.append("DMG %d–%d" % [int(round(damage)), high])
		parts.append("SPEED %.1f s" % float(stats.get("attack", 0.0)))
		var passive := ItemPassives.effect_summary(str(item.get("kind", "")))
		if not passive.is_empty():
			parts.append("PASSIVE " + passive)
	elif category == "shield":
		parts.append("BLOCK %d STAM" % item_block_stamina(id))
	elif category == "armor":
		parts.append(("HEAD %d%%" if str(item.get("kind", "")) == "head" else "BODY +%d%%") \
			% item_guard_percent(id))
	elif category == "focus":
		var focus_text := TrinketStats.effect_summary(id)
		parts.append(focus_text if not focus_text.is_empty() else "COSMETIC")
	elif category == "jewelry":
		var jewelry_text := TrinketStats.effect_summary(id)
		parts.append(jewelry_text if not jewelry_text.is_empty() else "NO EFFECT")
	return "  •  ".join(parts)

## Hover card lines. Type / Speed / Damage are the three fixed rows; extras are
## every remaining stat row, in the same order the inspector shows them.
func item_type_text(id: String) -> String:
	return item_type_line(id)

func item_speed_text(id: String) -> String:
	var seconds := item_attack_seconds(id)
	if seconds <= 0.0:
		return "—"
	var verb := "draw" if item_category(id) == "bow" else ("stab" if item_kind(id) == "dagger" else "swing")
	return "%.1f s %s" % [seconds,verb]

func item_damage_text(id: String) -> String:
	var damage := item_damage_range(id)
	if damage == Vector2i.ZERO:
		return "—"
	return "%d–%d" % [damage.x,damage.y]

func item_extra_rows(id: String) -> Array:
	var rows: Array = []
	for row: Dictionary in item_stat_rows(id):
		if str(row.get("label","")) in ["DAMAGE","ATTACK SPEED"]:
			continue
		rows.append(row)
	return rows

## The paperdoll's summary panel. Base pools mirror `main.MAX_HEALTH` and
## `Stamina.MAX`; keep them in step if either pool changes.
const BASE_HEALTH := 100
const BASE_STAMINA := 1000

func main_attack_text() -> String:
	var main := main_item()
	if main.is_empty():
		return "—"
	var damage := item_damage_range(main)
	if damage == Vector2i.ZERO:
		return "—"
	var stats := trinket_stats()
	var key := "ranged_damage" if item_category(main) == "bow" else "melee_damage"
	var scale := TrinketStats.damage_scale(stats,key)
	return "%d–%d" % [int(round(float(damage.x) * scale)),int(round(float(damage.y) * scale))]

func defense_percent() -> int:
	return int(round(TrinketStats.damage_reduction(body_reduction(),trinket_stats()) * 100.0))

func head_guard_percent() -> int:
	return int(round(TrinketStats.damage_reduction(head_reduction(),trinket_stats()) * 100.0))

func life_value() -> int:
	return BASE_HEALTH + int(round(float(trinket_stats().get("health",0.0))))

func stamina_value() -> int:
	return BASE_STAMINA + int(round(float(trinket_stats().get("stamina",0.0))))

## Every worn bonus that actually has a value, for the summary panel. Armor
## guard is folded into the two channel rows; the trinket guard is already part
## of those channels.
func kit_bonus_rows() -> Array:
	var stats := trinket_stats()
	var rows: Array = []
	rows.append({"label":"HEAD GUARD", "value":"%d%%" % head_guard_percent()})
	rows.append({"label":"BODY GUARD", "value":"%d%%" % defense_percent()})
	var rows_by_key := [
		["melee_damage","MELEE DAMAGE",1.0], ["ranged_damage","RANGED DAMAGE",1.0],
		["throw_damage","THROWN DAMAGE",1.0], ["attack_speed","ATTACK SPEED",1.0],
		["move_speed","MOVE SPEED",1.0], ["stamina_regen","STAMINA REGEN",1.0],
		["stagger","STAGGER RESIST",1.0], ["gold_find","KILL GOLD",1.0],
		["cooldown","SKILL COOLDOWN",-1.0],
	]
	for entry: Array in rows_by_key:
		var value := float(stats.get(str(entry[0]),0.0)) * float(entry[2])
		if absf(value) < 0.0001:
			continue
		rows.append({"label":str(entry[1]), "value":"%+d%%" % int(round(value * 100.0))})
	var heal := float(stats.get("heal_on_kill",0.0))
	if heal > 0.0:
		rows.append({"label":"ON KILL", "value":"+%d life" % int(round(heal))})
	var stamina_gain := float(stats.get("stamina_on_kill",0.0))
	if stamina_gain > 0.0:
		rows.append({"label":"ON KILL", "value":"+%d stamina" % int(round(stamina_gain))})
	return rows

func can_equip_in(id: String, slot: String) -> bool:
	return EquipmentRules.allowed(_item(id), slot)

func sell_value(id: String) -> int:
	return int(floor(float(item_price(id)) * SELL_RATE))

func inventory_full() -> bool:
	return inventory.size() >= INVENTORY_CAPACITY

func stash_full() -> bool:
	return stash.size() >= STASH_CAPACITY

func main_item() -> String:
	return str(equipped.get("main", ""))

func off_item() -> String:
	return str(equipped.get("off", ""))

func equipped_id(kind: String) -> String:
	if kind in EquipmentRules.SLOTS:
		return str(equipped.get(kind, ""))
	var main := main_item()
	var main_category := item_category(main)
	if kind == "bow":
		return main if main_category == "bow" else ""
	if kind == "sword":
		return main if item_kind(main) == "sword" and (main_category == "1h" or main_category == "2h") else ""
	return ""

func equipped_index(kind: String) -> int:
	if kind in ArmorData.SLOTS:
		var armor_id := equipped_id(kind)
		return int(_item(armor_id).get("index", 0)) if not armor_id.is_empty() else ArmorData.NONE
	if kind in EquipmentRules.SLOTS:
		return int(_item(equipped_id(kind)).get("index", 0))
	var main := _item(main_item())
	var category := str(main.get("category", ""))
	match kind:
		"bow":
			return int(main.get("index", 0)) if category == "bow" else 0
		"sword":
			if (category == "1h" or category == "2h") and str(main.get("kind", "")) == "sword":
				return int(main.get("index", 0))
			return 2 if category == "staff" else 0
	return 0

func equipped_pieces() -> Dictionary:
	var pieces := {}
	for slot in ArmorData.SLOTS:
		pieces[slot] = equipped_index(slot)
	return pieces

## Armor-only channels: the helmet on a head hit, the body pieces on anything
## else. Trinket guard is not included here; the rig adds it per hit.
func head_reduction() -> float:
	return ArmorData.head_reduction(equipped_pieces())

func body_reduction() -> float:
	return ArmorData.body_reduction(equipped_pieces())

## The four equipment ids the trinket table reads: neck, both rings and the
## off hand (the skulls carry their kill effects there).
func trinkets() -> Dictionary:
	return TrinketStats.kit(equipped)

func trinket_stats() -> Dictionary:
	return TrinketStats.sum(trinkets())

func is_equipped(id: String) -> bool:
	if id.is_empty():
		return false
	for slot in EquipmentRules.SLOTS:
		if str(equipped.get(slot, "")) == id:
			return true
	return false

func owned_in_inventory(id: String) -> int:
	var count := 0
	for entry in inventory:
		if entry == id:
			count += 1
	return count

func owned_in_stash(id: String) -> int:
	var count := 0
	for entry in stash:
		if entry == id:
			count += 1
	return count

## Build the exact loadout shape consumed by Archer.apply_loadout(), arena and
## delve. Pure: derives everything from the ids and the armor index map.
static func build_loadout(main_id: String, off_id: String, armor_pieces: Dictionary,
		trinket_ids: Dictionary = {}) -> Dictionary:
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
	if main_category == "bow":
		weapon = "bow"
		bow = int(main.get("index", 0))
	elif main_kind == "sword" and (main_category == "1h" or main_category == "2h"):
		weapon = "sword"
		sword = int(main.get("index", 0))
	elif main_kind == "dagger":
		weapon = "dagger"
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
		"bow":bow, "sword":sword, "staff":staff,
		"armor":armor, "shield":shield, "off_weapon":off_weapon, "focus":focus,
		"trinkets":TrinketStats.kit(trinket_ids) if not trinket_ids.is_empty() \
			else {"neck":"", "ring1":"", "ring2":"", "off":off_id},
	}

func loadout() -> Dictionary:
	return build_loadout(main_item(), off_item(), equipped_pieces(), equipped)

## The pair stored in one of the two weapon slots. Out-of-range asks answer
## with an empty pair instead of failing, so the paperdoll can draw both.
func weapon_set_pair(index: int) -> Dictionary:
	var source: Dictionary = {}
	if index >= 0 and index < weapon_sets.size() and typeof(weapon_sets[index]) == TYPE_DICTIONARY:
		source = weapon_sets[index]
	return {"main":str(source.get("main", "")), "off":str(source.get("off", ""))}

## The set the hands are carrying. TAB always leaves this slot and reaches the
## other one, so the key alternates instead of guessing from the hands.
func active_weapon_set() -> int:
	return active_set

func weapon_set_label(index: int) -> String:
	var pair := weapon_set_pair(index)
	return _hand_pair_label(str(pair.get("main", "")), str(pair.get("off", "")))

## Swap the hands for the other weapon set. Both sets live in the same carried
## pool (backpack plus hands), so no gear is created or lost, and the set being
## left keeps exactly what the hands were carrying - including a weapon that
## was equipped by hand after the last swap.
func swap_weapon_set() -> Dictionary:
	_sync_active_set()
	var target_index := 1 - active_set
	var target := _legal_pair(weapon_set_pair(target_index))
	var target_main := str(target.get("main", ""))
	var target_off := str(target.get("off", ""))
	if not _pair_bound(target) and not _pair_bound(weapon_sets[active_set]):
		return {"ok":false, "message":"Both weapon sets are empty. Equip a weapon first."}
	var pool := _to_dict_strings(inventory)
	if not main_item().is_empty():
		pool.append(main_item())
	if not off_item().is_empty():
		pool.append(off_item())
	for hand_id in [target_main, target_off]:
		if hand_id.is_empty():
			continue
		var found := pool.find(hand_id)
		if found < 0:
			return {"ok":false, "message":"%s is not carried. Move it from the stash to the backpack." % item_name(hand_id)}
		pool.remove_at(found)
	if pool.size() > INVENTORY_CAPACITY:
		return {"ok":false, "message":"Backpack full (%d / %d). Make room before swapping." % [pool.size(), INVENTORY_CAPACITY]}
	equipped["main"] = target_main
	equipped["off"] = target_off
	inventory = pool
	active_set = target_index
	_commit()
	return {"ok":true, "message":"Set %d ready: %s." % [target_index + 1, _hand_pair_label(target_main, target_off)]}

func _hands_pair() -> Dictionary:
	return {"main":main_item(), "off":off_item()}

## The hands are the active set. Every mutation commits through here, so a
## weapon equipped, dropped or unequipped by hand lands in the slot the player
## is wearing and the other slot keeps the weapon it already remembers.
func _sync_active_set() -> void:
	active_set = clampi(active_set, 0, WEAPON_SET_COUNT - 1)
	weapon_sets[active_set] = _hands_pair()

func _pair_bound(pair: Dictionary) -> bool:
	return not str(pair.get("main", "")).is_empty() or not str(pair.get("off", "")).is_empty()

## Value equality: two dictionaries built from the same ids are not the same
## object, and every set decision asks about the ids.
func _pair_matches(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("main", "")) == str(b.get("main", "")) \
		and str(a.get("off", "")) == str(b.get("off", ""))

## Drop ids the slot cannot take, and an off hand under a two-hander.
func _legal_pair(value: Variant) -> Dictionary:
	var source: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {}
	var main_id := str(source.get("main", ""))
	var off_id := str(source.get("off", ""))
	if main_id.is_empty() or not EquipmentRules.allowed(_item(main_id), "main"):
		main_id = ""
	if off_id.is_empty() or not EquipmentRules.allowed(_item(off_id), "off"):
		off_id = ""
	if EquipmentRules.two_handed(_item(main_id)):
		off_id = ""
	return {"main":main_id, "off":off_id}

func _note(message: String, data: Dictionary = {}) -> void:
	var log := get_node_or_null("/root/Log")
	if log != null:
		log.event("state", message, data)
func _hand_pair_label(main_id: String, off_id: String) -> String:
	var parts := PackedStringArray()
	if not main_id.is_empty():
		parts.append(item_name(main_id))
	if not off_id.is_empty():
		parts.append(item_name(off_id))
	return " + ".join(parts) if not parts.is_empty() else "Unarmed"

func reset(persist: bool = true) -> void:
	_note("reset", {"persist": persist, "path": save_path})
	credits = STARTING_CREDITS
	inventory.assign(STARTING_INVENTORY)
	stash.clear()
	floor_items.clear()
	equipped = DEFAULTS.duplicate()
	weapon_sets = WEAPON_SETS_DEFAULT.duplicate(true)
	active_set = 0
	if persist:
		_commit()
	else:
		changed.emit()

func buy(item_id: String) -> Dictionary:
	if not ITEMS.has(item_id):
		return {"ok":false, "message":"That item is not in any vendor's stock."}
	if inventory_full():
		return {"ok":false, "message":"Inventory full (%d / %d). Move something to the stash first." % [inventory.size(), INVENTORY_CAPACITY]}
	var price := item_price(item_id)
	if credits < price:
		return {"ok":false, "message":"Not enough credits. %s costs %d; you carry %d." % [item_name(item_id), price, credits]}
	credits -= price
	inventory.append(item_id)
	_commit()
	return {"ok":true, "index":inventory.size()-1, "message":"Bought %s for %d credits." % [item_name(item_id), price]}

func sell(location: String, index: int) -> Dictionary:
	var list := _list_for(location)
	if list.is_empty():
		return {"ok":false, "message":"That slot is empty."}
	if index < 0 or index >= list.size():
		return {"ok":false, "message":"That slot is empty."}
	var item_id := str(list[index])
	var value := sell_value(item_id)
	list.remove_at(index)
	credits += value
	_commit()
	return {"ok":true, "value":value, "message":"Sold %s for %d credits." % [item_name(item_id), value]}

func move_to_stash(index: int) -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {"ok":false, "message":"That slot is empty."}
	if stash_full():
		return {"ok":false, "message":"Stash full (%d / %d). Sell something first." % [stash.size(), STASH_CAPACITY]}
	var item_id := inventory[index]
	inventory.remove_at(index)
	stash.append(item_id)
	_commit()
	return {"ok":true, "message":"Stored %s in the stash." % item_name(item_id)}

func move_to_inventory(index: int) -> Dictionary:
	if index < 0 or index >= stash.size():
		return {"ok":false, "message":"That stash slot is empty."}
	if inventory_full():
		return {"ok":false, "message":"Inventory full (%d / %d). Store or sell something first." % [inventory.size(), INVENTORY_CAPACITY]}
	var item_id := stash[index]
	stash.remove_at(index)
	inventory.append(item_id)
	_commit()
	return {"ok":true, "message":"Took %s from the stash." % item_name(item_id)}

## Equip a backpack item. An empty target slot auto-routes the item.
func equip_from_inventory(index: int, target_slot: String = "") -> Dictionary:
	var result := EquipmentRules.plan_equip(equipped, inventory, index, target_slot, ITEMS, INVENTORY_CAPACITY)
	if bool(result.get("ok", false)):
		equipped = result.equipped
		inventory = _to_dict_strings(result.get("inventory", inventory))
		var spilled: Array = result.get("floor", [])
		for entry in spilled:
			floor_items.append(str(entry))
		_commit()
	return result

## Convenience for right-click equip; the plan picks the slot.
func equip(index: int) -> Dictionary:
	return equip_from_inventory(index)

func unequip_to_backpack(slot: String) -> Dictionary:
	if not slot in EquipmentRules.SLOTS:
		return {"ok":false, "message":"That is not an equipment slot."}
	var item_id := equipped_id(slot)
	if item_id.is_empty():
		return {"ok":false, "message":"That slot is empty."}
	if inventory_full():
		return {"ok":false, "message":"Backpack full (%d / %d). Drop or stash something first." % [inventory.size(), INVENTORY_CAPACITY]}
	equipped[slot] = ""
	inventory.append(item_id)
	_commit()
	return {"ok":true, "message":"Moved %s to the backpack." % item_name(item_id)}

func move_equipped(from_slot: String, to_slot: String) -> Dictionary:
	var result := EquipmentRules.plan_move(equipped, from_slot, to_slot, ITEMS)
	if bool(result.get("ok", false)):
		equipped = result.equipped
		_commit()
	return result

func drop_from_inventory(index: int) -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {"ok":false, "message":"That slot is empty."}
	var item_id := inventory[index]
	inventory.remove_at(index)
	floor_items.append(item_id)
	_commit()
	return {"ok":true, "message":"Dropped %s at your feet." % item_name(item_id)}

func drop_equipped(slot: String) -> Dictionary:
	if not slot in EquipmentRules.SLOTS:
		return {"ok":false, "message":"That is not an equipment slot."}
	var item_id := equipped_id(slot)
	if item_id.is_empty():
		return {"ok":false, "message":"That slot is empty."}
	equipped[slot] = ""
	floor_items.append(item_id)
	_commit()
	return {"ok":true, "message":"Dropped %s at your feet." % item_name(item_id)}

## Field world drops: the item leaves the ranger's pack but never joins the
## out-of-raid floor list, because the scene spawns it in the world instead.
func take_from_inventory(index: int) -> Dictionary:
	if index < 0 or index >= inventory.size():
		return {"ok":false, "item_id":"", "message":"That slot is empty."}
	var item_id := inventory[index]
	inventory.remove_at(index)
	_commit()
	return {"ok":true, "item_id":item_id, "message":"Dropped %s." % item_name(item_id)}

func take_equipped(slot: String) -> Dictionary:
	if not slot in EquipmentRules.SLOTS:
		return {"ok":false, "item_id":"", "message":"That is not an equipment slot."}
	var item_id := equipped_id(slot)
	if item_id.is_empty():
		return {"ok":false, "item_id":"", "message":"That slot is empty."}
	equipped[slot] = ""
	_commit()
	return {"ok":true, "item_id":item_id, "message":"Dropped %s." % item_name(item_id)}

func pickup_floor(index: int) -> Dictionary:
	if index < 0 or index >= floor_items.size():
		return {"ok":false, "message":"There is nothing there."}
	if inventory_full():
		return {"ok":false, "message":"Backpack full (%d / %d)." % [inventory.size(), INVENTORY_CAPACITY]}
	var item_id := floor_items[index]
	floor_items.remove_at(index)
	inventory.append(item_id)
	_commit()
	return {"ok":true, "message":"Picked up %s." % item_name(item_id)}

## World loot enters the backpack only; it is never auto-equipped.
func try_pickup(item_id: String) -> Dictionary:
	if not ITEMS.has(item_id):
		return {"ok":false, "message":"Unknown loot."}
	if inventory_full():
		return {"ok":false, "message":"Backpack full (%d / %d)." % [inventory.size(), INVENTORY_CAPACITY]}
	inventory.append(item_id)
	_commit()
	return {"ok":true, "index":inventory.size()-1, "message":"Picked up %s." % item_name(item_id)}

func add_credits(amount: int) -> void:
	if amount == 0:
		return
	credits = maxi(0, credits + amount)
	_commit()

func _list_for(location: String) -> Array[String]:
	if location == "inventory":
		return inventory
	if location == "stash":
		return stash
	return []

func _commit() -> void:
	_sync_active_set()
	changed.emit()
	save_state()

func _to_dict_strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	var entries: Array = value
	for entry in entries:
		out.append(str(entry))
	return out

func _take_from_inventory(item_id: String) -> void:
	var index := inventory.find(item_id)
	if index >= 0:
		inventory.remove_at(index)

func _give_to_inventory(item_id: String) -> void:
	if inventory.size() < INVENTORY_CAPACITY:
		inventory.append(item_id)
	else:
		floor_items.append(item_id)

func save_state() -> void:
	_sync_active_set()
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		_note("save_failed", {"path": save_path, "error": error_string(FileAccess.get_open_error())})
		push_warning("Could not write player state to %s" % save_path)
		return
	file.store_string(JSON.stringify({
		"version":SAVE_VERSION,
		"credits":credits,
		"inventory":inventory,
		"stash":stash,
		"equipped":equipped,
		"weapon_sets":weapon_sets,
		"active_set":active_set,
		"floor":floor_items,
	}))
	file.close()
	_note("save", {"path": save_path, "credits": credits, "inventory": inventory.size(),
		"stash": stash.size(), "floor": floor_items.size(), "version": SAVE_VERSION})

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
	var version := int(data.get("version", 1))
	credits = maxi(0, int(data.get("credits", STARTING_CREDITS)))
	inventory = _read_list(data.get("inventory", []), INVENTORY_CAPACITY)
	stash = _read_list(data.get("stash", []), STASH_CAPACITY)
	floor_items = _read_list(data.get("floor", []), 0)
	equipped = DEFAULTS.duplicate()
	weapon_sets = WEAPON_SETS_DEFAULT.duplicate(true)
	active_set = 0
	var saved_equipped: Variant = data.get("equipped", {})
	if typeof(saved_equipped) == TYPE_DICTIONARY:
		if version >= 3:
			_load_equipped_v3(saved_equipped)
		else:
			_load_equipped_legacy(saved_equipped)
	_normalize_equipped()
	_load_weapon_sets(data, version)
	_normalize_weapon_sets()
	_note("load", {"path": save_path, "version": version, "credits": credits,
		"inventory": inventory.size(), "stash": stash.size(), "floor": floor_items.size()})
	changed.emit()

func _read_list(value: Variant, limit: int) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	var entries: Array = value
	for entry in entries:
		var item_id := str(entry)
		if not ITEMS.has(item_id):
			continue
		if limit > 0 and out.size() >= limit:
			break
		out.append(item_id)
	return out

## Version 3 stores all ten equipment slots directly. Missing keys keep the
## starter default; present-but-invalid values are dropped.
func _load_equipped_v3(saved: Dictionary) -> void:
	for slot in EquipmentRules.SLOTS:
		if not saved.has(slot):
			continue
		var item_id := str(saved.get(slot, ""))
		if item_id.is_empty():
			equipped[slot] = ""
		elif EquipmentRules.allowed(_item(item_id), slot):
			equipped[slot] = item_id
		else:
			equipped[slot] = ""

## Version 1 stored the whole kit under bow/sword/armor; version 2 stored one
## armor piece per slot. Equipped items also lived in the backpack, so one
## matching copy is removed for each item that moves to a slot.
func _load_equipped_legacy(saved: Dictionary) -> void:
	var bow_id := ""
	if saved.has("bow"):
		var candidate := str(saved.get("bow", ""))
		if item_category(candidate) == "bow":
			bow_id = candidate
	var sword_id := ""
	if saved.has("sword"):
		var candidate := str(saved.get("sword", ""))
		var kind := item_kind(candidate)
		if kind == "sword" or kind == "dagger":
			sword_id = candidate
	var armor_ids := {}
	var bundle_ids: Array[String] = []
	# Version 1 stored one whole-set id under "armor"; version 2 replaced it
	# with one piece id per slot.  Expand the bundle first so per-slot values,
	# if both are present, win.
	var legacy_armor := str(saved.get("armor", ""))
	var legacy_category := item_category(legacy_armor)
	if legacy_category == "armor_bundle":
		var set_index := int(_item(legacy_armor).get("set", -1))
		if set_index >= 0:
			bundle_ids.append(legacy_armor)
			for piece_slot in ArmorData.SLOTS:
				armor_ids[piece_slot] = ArmorData.item_id(set_index, piece_slot)
	elif legacy_category == "armor":
		var armor_key_slot := item_slot(legacy_armor)
		if armor_key_slot in ArmorData.SLOTS:
			armor_ids[armor_key_slot] = legacy_armor
	for slot in ArmorData.SLOTS:
		if not saved.has(slot):
			continue
		var candidate := str(saved.get(slot, ""))
		var category := item_category(candidate)
		if category == "armor" and item_slot(candidate) == slot:
			armor_ids[slot] = candidate
		elif category == "armor_bundle":
			var set_index := int(_item(candidate).get("set", -1))
			if set_index < 0:
				continue
			bundle_ids.append(candidate)
			for expanded_slot in ArmorData.SLOTS:
				armor_ids[expanded_slot] = ArmorData.item_id(set_index, expanded_slot)
	if not bow_id.is_empty():
		equipped["main"] = bow_id
	elif not sword_id.is_empty():
		equipped["main"] = sword_id
	for slot in armor_ids:
		equipped[slot] = armor_ids[slot]
	# Old equipped copies were backpack entries; peel one copy per equipped id.
	for slot in EquipmentRules.SLOTS:
		_take_from_inventory(str(equipped.get(slot, "")))
	for bundle_id in bundle_ids:
		_take_from_inventory(bundle_id)
	if not bow_id.is_empty() and not sword_id.is_empty():
		# The bow wins the main hand; the sword returns to the backpack.
		_take_from_inventory(sword_id)
		_give_to_inventory(sword_id)

func _normalize_equipped() -> void:
	for slot in EquipmentRules.SLOTS:
		var item_id := str(equipped.get(slot, ""))
		if not item_id.is_empty() and _item(item_id).is_empty():
			equipped[slot] = ""
	if EquipmentRules.two_handed(_item(main_item())) and not off_item().is_empty():
		var displaced := off_item()
		equipped["off"] = ""
		_give_to_inventory(displaced)

## Version 6 stores both weapon sets and the index of the active one. Versions
## 5 and older stored `quick`/`quick_back`, the two sides of the TAB toggle:
## the pair in hand is the active set and the stored side that is not in hand
## is the other one, so an old save keeps both weapons.
func _load_weapon_sets(saved: Dictionary, version: int) -> void:
	var hands := _hands_pair()
	if version >= 6 and saved.has("weapon_sets"):
		var entries: Variant = saved.get("weapon_sets", [])
		var loaded: Array = []
		for index in WEAPON_SET_COUNT:
			var pair: Variant = {}
			if typeof(entries) == TYPE_ARRAY and index < (entries as Array).size():
				pair = (entries as Array)[index]
			loaded.append(_legal_pair(pair))
		weapon_sets = loaded
		active_set = clampi(int(saved.get("active_set", 0)), 0, WEAPON_SET_COUNT - 1)
		return
	var front := _legal_pair(saved.get("quick", LEGACY_QUICK_DEFAULT))
	var back := _legal_pair(saved.get("quick_back", {}))
	var other := {}
	if _pair_bound(front) and not _pair_matches(front, hands):
		other = front
	elif _pair_bound(back) and not _pair_matches(back, hands):
		other = back
	if version < 5 and not _pair_bound(other):
		# The single-pair era stored the pair TAB aimed at, which was often the
		# pair in hand - the data had no second side at all. A player who still
		# carries the starter melee set gets that set as the second slot.
		other = _carried_default_set()
	weapon_sets = [hands, other]
	active_set = 0

## The starter melee pair, but only when the ranger still carries both pieces
## somewhere in the pack or hands. Migration never invents gear.
func _carried_default_set() -> Dictionary:
	var candidate := _legal_pair(LEGACY_QUICK_DEFAULT)
	if _pair_matches(candidate, _hands_pair()):
		return {}
	var carried := _to_dict_strings(inventory)
	carried.append(main_item())
	carried.append(off_item())
	for hand_id in [str(candidate.get("main", "")), str(candidate.get("off", ""))]:
		if hand_id.is_empty():
			continue
		if not carried.has(hand_id):
			return {}
	return candidate

## Both slots are validated like the hands themselves: an unknown or wrong-hand
## id is dropped, a two-handed main hand cannot keep a paired off hand, and the
## active slot is what the hands carry.
func _normalize_weapon_sets() -> void:
	var rebuilt: Array = []
	for index in WEAPON_SET_COUNT:
		rebuilt.append(_legal_pair(weapon_sets[index] if index < weapon_sets.size() else {}))
	weapon_sets = rebuilt
	active_set = clampi(active_set, 0, WEAPON_SET_COUNT - 1)
	var active_pair: Dictionary = weapon_sets[active_set]
	equipped["main"] = str(active_pair.get("main", ""))
	equipped["off"] = str(active_pair.get("off", ""))
