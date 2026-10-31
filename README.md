# Ghost of the Warband

A Godot 4 third-person possession campaign. There is no main character: you are
a floating soul that enters any living mercenary of a warband, and every
mercenary is a real body with identical base stats - gear is the only thing that
makes one different from another. One world holds the cages you wake in, a
kilometre and a third of trail, and the walled town of Hearthstead; a warband
carries a shared **stash**, a shared **purse** and a **Cruor** ledger, and one
save remembers the roster, the gear, the essence, the orders and the last
checkpoint. It plays solo, or **hosted over Tailscale** for up to four souls who
all share the host's warband.

## Ghost of the Warband (possession campaign)

The same engine, a second game on top of it. There is no main character: you are
a floating soul that enters any living mercenary of your warband. Every mercenary
has identical base stats - **100 health, 1000 stamina**, gear is the only
difference - and the warband is the thing that survives a battle.

- **Saving:** the mode has its own save (`user://warband_state.json`, version 6,
  which also remembers every piece the altar has anointed);
  **RESUME WARBAND** opens it where the last checkpoint stands (the town square,
  or 60 m past the camp's mouth once the watchers there are down). The ranger's
  kit is untouched.
- **Start here, and play it:** the title's **GHOST OF THE WARBAND** puts you
  inside the **first of five** prisoners, shut in a cage. The opening teaches by
  being played, not by being read:
  * **take the ironwood shiv through the bars** (**K**) - it lies on the dirt
    right outside your cell door, with two lit hand torches on the ground beside
    it - and **cut your own latch** with it (**G**); bare hands open nothing;
  * **get your bearings**: the fire, the shelters, and the four other cages
    scattered through the wood;
  * the objective arrives - **free your warband** - and the first fight teaches
    itself in one-line tips under the crosshair, never a paused page: the three
    cuts (**LMB** diagonal, **WHEEL UP** stab, **WHEEL DOWN** overhead) are named
    as the armed body steps out and wake the pair, and the guard (**hold RMB**)
    comes on the second watcher's raised club. The pair are two of the wood's
    creatures - a **hollow warden** and an **ossuary stalker** - and they sleep
    until you are armed and out of the cage, and are the softest bodies in the
    game: a 1.3 s telegraph, half their blow, no guard.
  * Then **one latch per press** at each of the four remaining cages (a blade in
    hand and `G` at the bars; bare hands are refused, your own cage included).
    The last latch puts five bodies on their feet, turns them into squad AI that
    arms itself off the ground, and the objective turns over: **run to the town**.
- **Controls:** **Esc → KEYS** (in the quick menu, the warband menu and the
  title's settings) opens the CONTROLS sheet: the keyboard itself, drawn in the
  ledger's carved bone keycaps, every bound key washed in blood, and an arrow from
  each key to the action it serves.
- **The fallen:** a squadmate who goes down near you is brought back by **holding
  G** for five seconds (30 s bleed clock; a blow on the reviver breaks the
  channel). No blow ends a mercenary outright in the campaign - a lethal hit puts
  the body down, and any blow on a downed body finishes it.
- **Every drop is his own:** the band dresses out of one stash, so two men often
  wear the same five pieces - and still do not dress alike. Each mercenary dyes
  his cloth in his own livery (one of nine medieval dyes with a design in a
  charge that reads on it: per pale, quarterly, chevron, saltire, chequy, barry,
  lozengy...), wears his own device on the breast and the back (skull,
  crossbones, sun, crescent, star, eye, antlers, rune), sews his own border
  along every hem and cuff, stains his leather, blackens, blues or polishes his
  steel, re-casts his buckles - and hangs his own trophies on himself (a skull or
  a jaw at the belt, teeth at the neck, a plume or a pair of horns on the helm,
  feathers at a temple, beads at a wrist, rattles at an ankle). Nothing about it
  is saved, replicated or rolled at spawn: it is a pure function of the man's id,
  so every peer and every reload dresses him the same. A bare body carries
  nothing.
- **Hearthstead hub:** the shared **infinite stash** (value-sorted, unequipped
  pieces only - a worn piece is on its wearer's slots), the **Sacrificial Altar** — a
  blood-stained stone stele under candles and skull sticks, named **THE ALTAR** —
  whose ANOINT page lays a warden's ichor on a weapon or shield the warband
  carries so every copy wakes into its skill, and whose ESSENCE page unbinds spare
  magic items into Cruor, distils 5:1 up five tiers and brands weapons with active
  sigils; the **Gold recruiter** (bodies up to the deployment cap of 8), the
  **quartermaster** (plain steel and arrows bought into the shared stash) and the
  **expedition gate** (pick up to 8 bodies, then launch).
- **A sworn body takes the field:** a hire stands up in the square beside the
  band, and a soldier cut out of a cage stands up where he walked out, while the
  field is under its cap of 8. Past a full field a new name waits in the
  **reserve** - **RESERVE** on the roster screen, with no body - and takes the
  first place that opens once the band is back in the town; the reserve is
  never called up out in the wood.
- **Steel is plain until anointed:** no stock weapon carries a skill. Four of the
  twelve hollow-warden variants carry a vial of ichor; with one in the stash the
  quartermaster hands over **ICHOR IN THE STEEL**, and one vial at the altar wakes
  a piece into its skill (a twig bow into Long Piercing Shot, a club or heavy
  branch into Spinning AOE Spin, the ironwood shiv into Backstab, the wooden shield
  into Ground Shield Slam). The paperdoll names it: "Anointed - <SKILL> [key]", or
  "Plain - the altar wakes <SKILL>".
- **The field:** cultist waves in three escalating size/kit tiers. Combat near a
  human-possessed body is real (100% damage); every fight more than ~30 m from
  any human runs as a convincing background brawl at **10% damage**, so distant
  squads do not wipe each other off-screen. Walk over and it goes live.
- **Downed, not dead:** no blow takes a mercenary off the field. Any hit that
  empties a pool leaves the body **Downed** at 0 health - crawling backwards to
  cover, bleeding out in **30 s**. A soul can pick that body up with **G held for
  five seconds**, and a squadmate walks over and does the same once the field is
  quiet. A body that is struck again while it lies there dies, and a body that
  dies **keeps its corpse on the ground** instead of vanishing.
- **The makeshift tier:** the wood hands out nothing better than an **Ironwood
  Shiv** (10), a **Twig Bow** (10), a **Club** (6), a **Heavy Tree Branch** (15,
  two-handed) and a **Wooden Shield**. Forged steel is bought later, from the
  quartermaster, with a stash to pay for it.
- **Bodies are lootable:** every fallen cultist and watcher is a corpse you can
  open with **G** - their character screen, their slots, and each piece moved into
  the infinite stash (or **TAKE ALL**). The squad strips bodies on its own once
  the field is quiet, silently, into the same stash.
- **The band's fights are not silent:** when an AI squadmate breaks off after
  something, the HUD says it once - **Sorn breaks off: Briar wolf, 34 m
  back-left** - and keeps **IN THE FIGHT · Sorn, Dorn · 34 m back-left** under
  the roster until that ally is out of it, then **Sorn is back with the band.**
  The bearing is measured from where you are looking, so the line is a place to
  turn round for, and a body pacing in and out of reach is announced once.
- **Arrows are a resource:** one shared quiver for the whole band, one shaft per
  loosed arrow (skills included), and a dead trail archer's corpse is the only
  resupply out on the road - 10-20 shafts and the twig bow it fired. Keepers sell
  them by the bunch of ten. With the quiver empty the string stays down.
- **Loot:** quick-loot during the fight (K). A picked-up piece goes straight into
  the soul's hands when it fills an empty slot or beats what is worn there, and
  otherwise into the shared stash. When the field goes quiet the surviving
  soldiers physically jog to the drops before everything lands in the stash.

| Key | Warband mode |
| --- | --- |
| `[` / `]` | previous / next living, unoccupied body |
| `F1`..`F8` | enter a named body directly |
| `O` | warband screen (health, downed state, gear, click to control, hiring) |
| `TAB` | quick weapon swap: the body puts away the set in its hands and takes up the other one |
| `P` | mercenary paperdoll over the shared stash (click a worn slot to take it off into the stash; click a stash piece to wear it; **SWAP SET** or `TAB` changes the weapon set) |
| `G` | cut a cage latch, or use the altar / stash / quartermaster / recruiter you stand at |
| `1` / `2` / `3` | loose the skill of an anointed main hand / an anointed shield / the worn trinket (Shift+1..3 is the same press) |
| `K` | quick-loot the drop at your feet |
| `G` (hold) | revive the downed body beside you: five seconds, and a blow breaks the channel |
| `R` | fire the branded ability on your weapon |

**Multiplayer:** host and join from the title screen. Read from the host's gate
line. The host is authoritative for every body; ownership transfers are
validated by the soul router (one peer per body,
living bodies only), and each peer predicts the body it is inside. See
`docs/warband.md` for the architecture, `docs/warband-handoff.md` for the current
state and the next-phase plan, and `tests/warband_session_regression.gd` for the
two-process proof.

## Windows quick start

Requires Windows x64, PowerShell, and [Git](https://git-scm.com/download/win). No Godot installation, Node.js, paid assets, or game account is required.

```powershell
git clone https://github.com/harryvgiunta/ironwood-arena.git
cd ironwood-arena
.\Setup.cmd
.\Play.cmd
```

`Setup.cmd` downloads **Godot 4.7.2 stable** from its official GitHub release, verifies the pinned SHA-256 checksum, and installs it inside the ignored `.runtime/godot` directory. No administrator access or system-wide installation is needed. Running setup again reuses the verified-version installation. The game launchers also run setup automatically if the managed engine is missing.

The launchers import the bundled character assets before starting the game, so a fresh checkout does not need an existing `.godot` cache. Subsequent launches reuse imported assets. Blender is not required to play.

- **Play.cmd:** opens the main menu (**New Campaign**, **Resume Campaign**, **Join Game**, **Host Game**). It is the whole game: one scene opens the campaign, and hosting and joining are the same door with a socket.

Set `GODOT_PATH` to use another existing Godot executable. Linux/macOS users can install Godot 4.7.2, import `project.godot`, and run `title.tscn`; the Windows setup script does not install engines for those platforms.

## Main menu and the town

Every launch opens the **main menu**: Ghost of the Warband, four doors.

| Menu action | Result |
| --- | --- |
| **New Campaign** | A fresh warband and a fresh purse, starting in the five cages of the camp with the shiv in the dirt. |
| **Resume Campaign** | Opens your save where its last autosave stands: the trail checkpoint or Hearthstead. Disabled until a warband save exists. |
| **Join Game** | Name, host address and UDP port, reread from the cache every time the form opens. You connect first and play **from the host's warband** - you need no save of your own. |
| **Host Game** | Name and the port you open. **New Game** starts a fresh campaign; **From Checkpoint** opens the save on its bookmark (or in Hearthstead when it has none). The line under the buttons says what that checkpoint would open. |

**Hosting shares one warband.** Everyone who joins plays from the host's roster, stash, purse and orders: the guest is sent the host's campaign, keeps its own save untouched for as long as the session lasts, and gets it back when the session ends. Only the host changes gear, buys, hires, loots a corpse or works a keeper; a guest's own TAB, revive and combat verbs are resolved on the host's field, so a swap or a revive still lands on the shared warband.

Bodies are the shared pool, and every soul hops freely between the free ones (`[` and `]`, or `F1..F8`). The only way a soul loses a body is dying in it. With one body left standing the soul already inside keeps it, and everyone else watches that body in free look - the body panel names who is inside - and takes the next body that comes free, in the order the souls lost theirs.

There is no out-of-game depot. **Hearthstead** is the staging town inside the open PvE world, and every service is a real object you walk up to and press **G** on:

| Town service | Where | What it does |
| --- | --- | --- |
| **Smith Brann** | ForesterHouse, behind the forge counter | Swords, daggers and shields |
| **Storekeeper Orla** | FletcherWorkshop, behind the counter | Bows, staves and trail goods |
| **Quartermaster Vey** | HearthsteadStore, behind the counter | 20 armor pieces plus foci, necklaces and rings |
| **Town Stash** | Open market awning | The warband's shared, uncapped storage |
| **Hearthstead Campfire** | Town square | Restores health and stamina |

The warband starts in the cages with nothing worth the name: an old shirt, tight shorts, bare hands and a shiv in the dirt. Every piece a run carries came off a corpse, out of the shared stash or off a keeper's counter; the tab buttons in the town shops are **STORE**, **SMITH** and **QUARTERMASTER**, and selling pays 60% of the purchase price.

Press **P** anywhere in the world to open the **paperdoll**: the ten worn slots, a live ranger wearing them, the trinket rail and the kit's derived attack, guard, life and stamina summary over the **shared stash** - the warband's one pool of unequipped gear, uncapped and sorted by value; a piece a body is wearing shows on that body's slots, never in the list. Click a worn slot to take a piece off into the stash; click a stash piece to wear it (handing gear between mercenaries is those two clicks); drag between slots to move or swap. The **QUARTERMASTER**, **SMITH** and **STORE** keepers open their own counters over the same stash, and the corpse screen opens the dead the same way.

Every catalog item keeps its data row in `scripts/player_state.gd` (`ITEMS`), and the paperdoll, the tooltips, the vendors and the loot all read that one table.

**TAB swaps between two weapon sets.** Every mercenary carries two complete weapon sets — a main hand and an off hand each — and exactly one is active: the hands hold its pair, and the pair lives on the roster record so a swap survives a body hop and a reload. Pressing TAB while Set 1 is active brings up Set 2; the next press brings Set 1 back, and the paperdoll always says which set is active. Equipping, unequipping or dropping a weapon rewrites **the active set only**: the other set keeps the weapon waiting in it, and a weapon you equip by hand comes back when you TAB back to that set. Any legal main/off combination works: bow, one- or two-handed sword, dagger, staff, shield, focus or a dual-wield pair. Both sets are written to the save, and both pairs must be carried in the backpack or hands; a stashed piece blocks the swap with a message.

Dropping a piece in the camp, on the trail or in town spawns a physical world pickup at the body's feet. It arms only after you step clear, so the dropper cannot scoop it straight back up. Every successful gear change is written to `user://warband_state.json` with the rest of the warband.

Loot is tuned to **a tenth of the engine's old rate**: a weapon-carrying hostile leaves the piece it held 10% of the time, and a corpse can be worked for everything it carried.

**New Campaign vs. Resume Campaign:** a new campaign resets the warband *and* the shared purse and opens in the cages; Resume Campaign re-reads `user://warband_state.json` and puts the warband on its last autosave bookmark. The campaign autosaves at two moments - the trail once the camp's watchers are down, and the first entry into Hearthstead - and a wipe reloads the bookmark (bodies that were merely down get up at half health; the dead stay dead; the purse is never rolled back). A co-op guest writes no checkpoint and no save of its own while it plays the host's warband.

### Item taxonomy and hand rules

| Category | Legal slots | Examples |
| --- | --- | --- |
| One-handed (`1h`) | Main hand or off-hand | Shortsword, arming sword, iron dagger |
| Two-handed (`2h`) | Main hand only; locks the off-hand | Greatsword |
| Bow | Main hand only | Shortbow, recurve, longbow |
| Staff | Main hand only; locks the off-hand | Ember Staff, Bone Staff |
| Shield | Off-hand only | Buckler, kite shield, tower shield |
| Focus | Off-hand only | Ash Tome, Bone Skull, Skull of Life, Skull of Death |
| Armor | Its own head / chest / hands / legs / feet slot | Leather, mail, plate and Emberweave pieces |
| Jewelry | Neck, or either ring slot | Ember Charm, Amulet of Energy Shield, seventeen rings |
| Ammunition (`ammo`) | Carried, never worn | Arrow (sold by the bunch of ten) |

- Right-click routing sends one-handers to the **main hand**, shields and foci to the **off-hand**, armor to its own slot, a necklace to the neck and a ring to the first empty ring slot (then ring 1). Alt+right-click and drags onto a slot choose the hand explicitly.
- Equipping a two-handed weapon, bow or staff **overrides both hands**: an existing main-hand and off-hand item are both returned to the backpack. If the backpack has room for only one, the second displaced item lands on the floor.
- Equipping a shield or focus while a two-handed weapon, bow or staff is in the main hand **returns that weapon to the backpack** and leaves the main hand empty.
- Two one-handers may occupy the main and off hand together. The loadout enters dual wield only when a one-handed sword is in the main hand and a dagger or another one-handed sword is in the off hand, with no shield, focus or staff involved.
- The shield pairs with **any one-handed sword or the dagger**, including the shortsword. A bow, greatsword, staff or dual wield stows it. Staffs keep the greatsword's damage and swing clock but use their own **middle grip**, shaft length and 1.6/1.5 m cleave reach; foci are held and cosmetic.
- Dragging between two paperdoll slots moves a piece into an empty legal slot or swaps two pieces. Illegal moves (a ring to the neck, a two-hander to the off-hand) are rejected. Unequipping returns a piece to the backpack; dropping it sends it to the floor.

### Trinkets: necklaces, rings and the held skulls

A **neck** piece, either **ring** and the **off hand** can change the ranger's numbers. `scripts/trinket_stats.gd` is the single table; the controllers only read its aggregate, so a new trinket is one catalog row plus one entry there.

| Slot | Item | Effect |
| --- | --- | --- |
| Neck | **Amulet of Energy Shield** | Grants **ENERGY SHIELD** on **SHIFT + 3**: a yellow bubble that absorbs **50%** of every hit and takes **twice** that share from stamina instead. Lasts **60 s**, the bubble pops when the pool cannot pay |
| Ring | **Ring of Dash** | Grants **DASH** on **SHIFT + 3** (double speed for 1 s, down the crosshair) |
| Off hand | **Skull of Life** | **+15 life** on every kill you land |
| Off hand | **Skull of Death** | **+15 stamina** on every kill you land |
| Ring | **Ring of Health** | +25 max health |
| Ring | **Ring of Ironhide** | +20 max health, +2% damage reduction |
| Ring | **Ring of Ranged Damage** | +10% ranged damage (arrows, bow skills, spells) |
| Ring | **Ring of Melee Damage** | +10% melee damage (blades, blade skills, backstab) |
| Ring | **Ring of Throwing** | +25% thrown weapon damage |
| Ring | **Ring of the Swift** | +8% movement speed |
| Ring | **Ring of Haste** | +12% attack speed (bow draw and swing clocks) |
| Ring | **Ring of Vigor** | +150 max stamina |
| Ring | **Ring of the Tide** | +30% stamina regeneration |
| Ring | **Ring of Warding** | +6% damage reduction, added to the armor total |
| Ring | **Ring of Grit** | -25% stagger suffered |
| Ring | **Ring of Bounty** | +25% gold from kills |
| Ring | **Ring of Echoes** | -15% skill cooldown |

- The three worn trinkets add up: two health rings and the ironhide band give **145** max health on a 100 base.
- The **necklace wins the third ability slot**, then ring 1, then ring 2, so a kit always resolves one skill deterministically. A stat-only ring leaves that tile hidden and **SHIFT + 3** inert.
- **Skulls pay out on every kill** — the killer is recorded on every mob, and only that body's own skulls refill. Both skulls are off-hand holds, so they are unavailable while a bow, staff, greatsword, shield or dual-wield pair is out.
- The plain **Ember Charm**, **Bone Talisman** and the three cheap rings remain flavor pieces with no combat effect.
- Health and stamina maxima are per-actor now: **125/125** and **1150** read that way on every HUD, and a removed ring clamps the live pool back down instead of leaving an over-full bar.

### Looting the dead

A hostile leaves a **corpse you can work**: walk up to it, press **P**, and take what it carried into the shared stash. The corpse screen lists every carried piece - and a trail archer leaves the twig bow it fired plus four of its own shafts - and a stripped body is never offered twice. **K** quick-loots the drop at your feet. Loot covers swords, daggers, shields, staffs, foci, armor, necklaces and rings; the stash is shared, so any body in the warband can then be dressed from it at the paperdoll.

Dropping gear from the paperdoll in town or on the trail spawns a pickup at the body's feet. That drop starts **unarmed**: it arms only after the dropper steps out of the pickup radius, so walking back over it later banks it into the stash normally.

### Armor: four sets, five slots

Armor is equipped **per slot**, so a cloth hood can sit over a mail hauberk, leather gloves and plate legs. Every set supplies a head, chest, hands, legs and feet piece:

| Set | Head | Chest | Hands | Legs | Feet | Head guard | Body guard |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Ranger leather | Hood | Jerkin | Gloves | Trousers | Boots | 20% | 10% |
| Sentinel mail | Coif | Hauberk | Mittens | Chausses | Sabatons | 30% | 25% |
| Warden plate | Sallet | Cuirass | Gauntlets | Cuisses | Sabatons | 50% | 30% |
| Emberweave cloth | Hood | Robe | Wraps | Skirt | Boots | 5% | 5% |

The leather outfit is the imported Ranger mesh split by region; mail is riveted ring weave, plate is blackened articulated steel, and Emberweave is a layered mage robe with a torn hem and brass trim. Each piece renders on the same 65-bone skeleton as the ranger and follows the authored idle, draw, swing, crouch, slide, roll and cover poses. A dark hose underlayer fills the shin whenever the short leather trousers are mixed with short sabatons.

Reduction runs on **two channels**. The helmet alone answers a **head** hit, which is what makes the head zone readable: a 50% plate sallet turns a **2x headshot back into a normal hit**, a 30% mail coif leaves **1.4x** and a 5% cloth hood **1.9x**. The other four pieces add up for **every other hit** — chest and legs carry 1/2.6 of the set's body figure each, hands and feet 0.3/2.6 — so full plate adds 11.5% + 11.5% + 3.5% + 3.5% = **30%**, full mail 9.6% + 9.6% + 2.9% + 2.9% = **25%**, and a mixed kit adds exactly the pieces worn. Trinket guard is added to whichever channel a hit uses and capped at **60%**. An empty slot draws the naked body — bare skin, the old shirt, the shorts — and guards nothing: the leather outfit is the leather *set*, never an underlayer, so a body in one mail piece is not a ranger in green leather underneath. The town Quartermaster sells all 20 pieces alongside the four foci, three necklaces and seventeen rings; old whole-set items from earlier saves are migrated to the five slots on load.

Armor is equipped per slot at the paperdoll, one catalog piece at a time; what a body wears is the roster record the save holds.

## Play with friends over Tailscale

All players run the same checkout and must be on a tailnet that lets them reach
the host. Hosting and joining both start on the title screen:

| Door | What it does |
| --- | --- |
| **Host Game** | Name and UDP port. **New Game** opens a fresh campaign for the party; **From Checkpoint** opens the save on its bookmark (or in Hearthstead when it has none). |
| **Join Game** | Name, host address and UDP port, reread from the cache every time the form opens. You connect while still on the title and the world opens when the host answers. |

**One warband, the host's.** A guest is sent the host's campaign and plays that
roster, stash, purse and orders; its own save is untouched for the session and
is handed back when the session ends. Only the host changes gear, buys, hires,
loots a corpse or works a keeper - a guest's TAB, revive and combat verbs travel
as intents and are resolved on the host's field. Everyone fields exactly the
host's bodies.

Find the address to send privately to your friends:

```powershell
tailscale ip -4
```

Keep the host window open. If the host leaves, guests see the session end and
are returned to the title. Host addresses are not stored in this repository.

### Connection troubleshooting

- Confirm the host is hosting: the HUD's top-left line reports the session and
  the port (`WARBAND / UDP 7777 / 2 RANGERS`).
- Compare the **UDP port** in that line with the port in the joining form. They
  must match; a timeout names the address and port it tried.
- Run `tailscale ping HOST_TAILSCALE_IP` from the joining PC. This checks tailnet
  connectivity, not the game's UDP port. Use `127.0.0.1` only for two instances
  on one computer.
- Permit UDP **7777** in any custom tailnet access policy and allow the host
  executable through its local firewall. `Allow Tailscale Host.ps1`, run
  elevated on the **host only**, creates a narrowly scoped rule for this engine,
  UDP 7777, the Tailscale adapter and Tailscale IPv4 addresses.
- **Tailscale needs no router port forwarding.** After pulling updates, restart
  every instance: Godot keeps loaded scripts in memory.

See [Tailscale's firewall guidance](https://tailscale.com/docs/reference/faq/firewall-ports).

### Networking configuration

There is no separate config file. The remembered player name and host port live
in `scripts/net_cache.gd` (`user://net_cache.json`), and the campaign's one
`ENetMultiplayerPeer` is owned by `WarbandSession` (`scripts/warband/warband_session.gd`),
opened by `GameFlow`. Bodies snapshot at **20 Hz**, the world's mobs at **15 Hz**,
and loot, missiles and ammo spends are announced once.

Every packet is clamped by `scripts/net_limits.gd`: **1200-byte `MTU`**, a
**1100-byte payload budget** after the RPC/ENet envelope. Multi-body batches are
sized by encoded bytes rather than a fixed body count, so the game never asks
ENet to fragment. `tests/warband_netcode_regression.gd` measures a real body
batch against that budget.

### Prediction, reconciliation and lag compensation

Movement is **client-side predicted and host reconciled**
(`scripts/net_replication.gd`, `scripts/lag_compensation.gd`). The peer that owns
a body integrates its own movement frame immediately - the same
`_resolve_motion`/`_integrate` pair the host runs - and records every frame in a
bounded ring buffer. Each intent carries its frame number, the simulation tick
the peer was drawing and the previous three frames, so a dropped datagram cannot
leave the host permanently short of that peer's travel. The host simulates
exactly one numbered frame per tick and drains any backlog in the same tick; a
tick that brought no frame holds the pose instead of repeating the last intent,
because a repeated intent walks the authority ahead of the frames that own it.

The owner compares its own recorded pose for the following frame. Agreement
within a couple of frames of its own travel moves nothing; a larger disagreement
is applied as a **displacement** (the authoritative pose minus the pose this peer
recorded for the same instant), with the unacknowledged ring dropped. What the
player sees is separated from that: the model is drawn at its previous pose and
moved toward the corrected one at most 0.35 m a frame, so a correction reads as
the character stepping into place.

Everyone else is drawn **in the past**: a body, mob or clone keeps a short buffer
of host states and renders a delay behind the newest one, interpolating between
two known poses and dead-reckoning along the last velocity when a packet drops.
The playout clock is nudged toward its delay target rather than snapped, and only
a genuine discontinuity - a revive, a backstab blink, a scene hand-off - restarts
the buffer. The guest's render tick is also what its actions are named by: the
host records one second of every awake damageable capsule and resolves a blow
against the bodies that peer saw, so a strike that landed on a guest's screen
still lands.

`tests/warband_netcode_regression.gd` drives the primitives, the frame stream,
the prediction and the rewind on the shipped bodies; `warband_session_regression`
and `warband_coop_campaign_regression` run two real ENet processes.

## Controls

| Control | Action |
| --- | --- |
| WASD | Move relative to the camera; slide along the surface while in cover |
| Shift | Run, or slide faster while in cover; consumes stamina |
| Space | Jump |
| Shift + Space | Immediately jump-roll in the movement direction, or forward if stationary |
| F | Post up against solid cover in front of you / leave cover. Nothing sticks without this press |
| Hold right mouse with a sword | Guard. The first 0.25 s is a parry; holding longer standard-blocks each hit and spends stamina |
| Hold right mouse with a dagger | Weak guard only: no parry, and blocked hits deal half damage while spending more stamina |
| Hold right mouse with a shield | Raise the shield. Full front block, no parry, **18 stamina**; arrows that hit it deal no damage and stick in the shield |
| Hold right mouse in cover | Guard and peek over low cover or around the selected edge of tall cover |
| X | Swap shoulder camera and select the left/right lookout while in cover |
| 1 | Equip the selected bow |
| 2 | Equip the selected sword |
| 3 | Equip the dagger |
| 4 | Equip or stow the shield (any one-handed sword or the dagger) |
| 5 | Dual-wield the selected one-handed sword in the right hand and the dagger in the left; press again to return to the sword |
| TAB | Swap between the two weapon sets; the active set's pair is stowed and the other set's pair is equipped |
| 6 | Use a bandage: three-second channel, then 35 health over the next three seconds |
| 7 | Drink a healing potion: half-second channel, then 50 health |
| Mouse movement | Mouse-look with a fixed center crosshair; no aim assistance |
| Hold left mouse with bow | Raise and draw while aiming; automatically expose from cover |
| Release left mouse with bow | Launch one arrow; cover shots wait for exposure without gaining charge |
| Click left mouse with sword or dagger | Break sticky cover and cut diagonally from the current camera shoulder; accepted cuts alternate sides, and X resets the next side |
| Scroll wheel up with sword or dagger | Forward stab along the crosshair |
| Scroll wheel down with sword or dagger | Authored overhead chop (dagger uses its precision stab) |
| Hold T with a sword or dagger | Charge a throw while aiming. Damage scales with charge, and a bow-style recovery follows the release |
| Release T with a sword or dagger | Hurl the equipped weapon as a projectile. The endless supply keeps the same weapon equipped |
| Click left mouse while dual wielding | Left-hand diagonal cut from the left |
| Click right mouse while dual wielding | Right-hand diagonal cut from the right; never a guard |
| Q / E | Side-step left / right with the shoulders turning into the move; grounded, short cooldown, 7 stamina |
| Shift + 1 / Shift + 2 / Shift + 3 | Cast the skill of an anointed main hand / anointed off-hand shield, or the worn trinket's grant; stock steel carries no skill, so a piece that has never been to the altar grants nothing; each costs 1 stamina for testing |
| G | Interact with a keeper, the stash, the campfire, a cage latch or a corpse the squad may revive |
| P | Open or close the equipment screen (ten worn slots, a live ranger, the shared stash and the kit summary); while open it owns the cursor and blocks movement, attacks and interactions |
| I | Open the same screen |
| Escape | Close the paperdoll, keeper or stash panel first; otherwise open the **quick menu** with the pointer free. It never pauses the world, so a hosted session stays connected while it is up: **RESUME**, **SAVE GAME**, the window mode switch, **KEYS**, the SOUND page, **EXIT TO TITLE** and **EXIT GAME**. It opens by itself when a host disappears |
| Click the world / right mouse | Resume captured mouse-look; right mouse also raises a sword guard |
| Mouse wheel | Select the melee variant when armed; hold Ctrl to zoom |
| C | Toggle crouch while grounded; slide when pressed during a sprint |

### Abilities and stamina

The base stamina pool is **1000**. Sprinting and sliding drain **19/s**, standing recovery is **13/s**, and guarding pauses recovery; block and step costs are unchanged. The HUD shows the pool and three ability slots: **SHIFT + 1** for the main hand, **SHIFT + 2** for the off-hand shield and **SHIFT + 3** for the worn trinket, each with its icon, stamina cost and cooldown.

Abilities are data-driven by `scripts/ability_rules.gd`. Stock weapons carry no skill: `AbilityRules.granted(rig)` wakes a weapon's skill in the main hand, or a shield's in the off hand, only once the warband's altar has anointed that piece (`rig.anointed`), so looted steel is plain until it is taken to the altar. Wearing the amulet or the dash ring grants its skill to the trinket slot. The table below is the skill each piece wakes into; the makeshift tier resolves through the same class/index (twig bow → Long Piercing Shot, club and heavy branch → Spinning AOE Spin, ironwood shiv → Backstab, wooden shield → Ground Shield Slam, makeshift cleaver → Double Slash). A definition carries the stock item it belongs to, hand slot, keybind, stamina cost, cooldown, durations, travel window, a `move` flag, animation clip, lean or spin, sound, icon and an effect block; `scripts/ability_runner.gd` owns eligibility, spend, cooldown, committed travel, timed effect cues and replication. Every weapon skill currently costs **1 stamina** and has a short cooldown so the set can be exercised back to back. Swapping the granted weapon clears that slot's trailing cooldown; the cooldown exists so swapping cannot become a free damage loop. An empty main hand keeps the legacy unarmed **Charge** (10 stamina, 200% walk speed for one second).

`move` decides what the feet do. **Double Slash, Lunging Thrust, Spinning AOE Spin, Headbutt, Shield Charge and Ground Shield Slam** keep normal walking input; **Barrage, Triple Fan Volley, Long Piercing Shot, Fireball, Bone Spear**, the unarmed **Charge** and **Backstab** stay planted. Committed travel still wins during its window (**0.24 s** lunge, **0.16 s** headbutt, **0.48 s** shield charge), and the walk resumes once it ends; no ability allows sprinting or jumping. A definition's `aim` flag makes that committed step travel down the live crosshair instead of the heading the key was pressed from, so the lunge, the headbutt and the shield charge all turn the body onto the crosshair and dash along it. Skills that cannot be performed from a crouch — every blade, shield and dagger skill plus the unarmed Charge — are performed standing: activating one cancels a manual crouch, snaps the capsule upright and only spends the skill once the body has headroom to stand, so the authored clip always owns the whole pose. The planted bow and staff casts still layer over a crouch.

| Main hand | Skill | Feet | Effect |
| --- | --- | --- | --- |
| Shortbow | **BARRAGE** | Planted | Six rapid arrows at 50% damage, each leaving along the live crosshair in a 4° fan |
| Recurve | **TRIPLE FAN VOLLEY** | Planted | Three arrows in one wide fan at 70% damage |
| Longbow | **LONG PIERCING SHOT** | Planted | One heavy arrow at 200% that punches through three bodies |
| Shortsword | **DOUBLE SLASH** | Walks | Two fast front-arc cuts at 90% each, landing at 0.26 s and 0.52 s |
| Arming sword | **LUNGING THRUST** | Walks | A 0.24 s dash at 405% travel (5.34 m at 22.3 m/s) that cuts its whole 1.35 m lane once, then a 180% thrust |
| Greatsword | **SPINNING AOE SPIN** | Walks | A 0.3166667 s full turn that cuts everything within 2.9 m, trailed by a steel-cyan blade trail and a dim warm dust ring |
| Iron Dagger | **BACKSTAB** | Planted | Blinks behind the aimed foe in a black smoke burst and plunges for 28 (2x dagger), bypassing a front guard |
| Ember Staff | **FIREBALL** | Planted | A burning orb that bursts for 80 damage in a 3 m blast |
| Bone Staff | **BONE SPEAR** | Planted | A spectral lance at 180% that impales three bodies |
| Buckler (off hand) | **HEADBUTT** | Walks | A boss-first head shove that damages and staggers the front arc |
| Kite Shield (off hand) | **SHIELD CHARGE** | Walks | A shield-first drive that bowls over the front arc |
| Tower Shield (off hand) | **GROUND SHIELD SLAM** | Walks | A ground slam that damages and staggers everything within 2.9 m |

Barrage, volley and piercing shots solve both bow arms from a data draw curve, so every shot visibly reaches full draw and releases on its cue. The greatsword spin turns the visual model a full turn while the data-ring damages all around - up to ten bodies, nearest first, like every item skill's activation; replicas derive the same turn from the ability clock. The spin now runs in a **third of its old time — 0.3166667 s** — with a presentation-only `wind` cue at **0.06 s** and the damage `ring` cue at **0.16 s**, so the beats crowd the start of the turn. The arming-sword **LUNGING THRUST** travels **three times as far**: **0.24 s** at **405%** of the 5.5 m/s walk (about **22.3 m/s**, **5.34 m**), woken by a takeoff `dash` cue at **0.0** and followed by the thrust `arc` at **0.42 s**. The dash sweeps a **1.35 m / 170°** lane every tick and damages each body it passes through once for **68.4** (the arming sword's 1.8x), sharing that victim set with the final thrust so nothing is hit twice; a gold ground ribbon, a dust plume, skid smears, afterimage wisps and speed streaks trail the dash. Arena, delve and the open world validate the action on the host and replicate the active ability, cooldowns and animation through the existing actor snapshots; effect cues are clock-driven on every peer, and only the host applies damage and projectiles. The three shield skills present the disc ahead of the body: the disc's plane is pushed clear of the chest, head and legs and the left arm is solved onto it, so a clip that draws the hand back cannot pull the boss through the torso or the helmet.

**Bow skills turn the body onto the live crosshair** before the shot, and every arrow leaves along that line with the authored spread, so an off-axis target is solved by facing it rather than by floating the pose. The arming sword's **LUNGING THRUST**, the buckler **HEADBUTT** and the kite **SHIELD CHARGE** do the same before their committed step, so the dash lands where the player is pointing rather than where the body happened to be facing. The dagger's **BACKSTAB** needs a body under the crosshair within **8 m**: it preflights that target, teleports the ranger behind it at **0.20 s** inside a large black charcoal smoke cloud (roughly **4 m** wide and **3.6 m** tall, built from **130** soft billboards that last about **0.8 s**; the ranger is clear of it by about **0.7 s**), then plunges for double dagger damage (**28**) at **0.50 s** in a 0.9 s skill, bypassing a raised front guard. The blink lands behind the foe's back, so a front guard never covers the hit.

**1 (without Shift) always equips the selected bow; 2 always equips the selected sword; 3 equips the single dagger; 4 equips or stows the shield; 5 toggles dual wield; TAB swaps the two weapon sets. No number key changes size.** The equipment paperdoll's main and off hands determine the starting kit for a session; these keys change what the body holds now, while TAB reads and writes the persisted pair. **P** opens the equipment/paperdoll screen; **I** is the same screen The shield is legal with **any one-handed sword or the dagger**, including the shortsword; switching to a greatsword, staff, bow or dual wield stows it. Mail is a 30% helmet and a 25% body kit, plate 50% and 30%; mixed sets add the pieces actually worn, and a helmet only answers head hits. The town's keepers and stash are the only places to buy or store gear; the arena portal and the delve hatch are the two other ways out of town.

## Running slide

In both Frontier and Arena, **hold Shift while moving, then press C** to slide. The character must already be sprinting on the ground: standing still, walking, exhaustion, rolling and attached cover cannot trigger a running slide.

The slide starts at **10.5 m/s**, slows to crouch speed over **0.75 seconds**, and finishes crouched. Releasing WASD or Shift preserves its momentum; WASD allows limited steering without reversing direction. It uses the normal collision capsule, lowers the camera, and shows a low, planted slide pose instead of cycling running steps. Sprint stamina consumption continues during the slide, and holding Shift cannot automatically repeat it.

Press **C** again to cancel and stand when headroom permits. **Space** jumps and **Shift + Space** rolls out of the slide, also requiring standing clearance. Blocked forward travel or leaving the ground ends the slide; death, respawn and returning to camp clear it. Grounded attacks still work, and sliding grants no invulnerability. Arena derives slide eligibility and movement on the host and replicates the pose to other players.

## Quick steps

**Q** and **E** perform a grounded side step left or right relative to the camera. The step covers about **2.95 m in 0.30 s**, spends **7 stamina**, and enters a **0.55-second cooldown**. It is not a roll and grants no invulnerability. A step cancels a held bow draw, a melee swing, a throw or a guard, exits sticky cover, and ends immediately if the feet leave the ground. The character keeps the facing it had before the step: the hips and shoulders rotate into the travel while the head stays on the target, the leading foot reaches out and lifts, and the trailing foot braces. Q and E no longer draw, attack or interact; **G** interacts with the campfire, waystones and the Sunken Delve hatch inside the Wayfarer Inn.

`playtest/sidestep_lab.tscn` opens an isolated plaza for tuning this move: a facing tree, a metre grid and a measured trace of the last step. Launch it with **`playtest/Sidestep Lab.cmd`** or run the scene directly. It uses the real `Archer` and `DodgeStep` code; only the camera and the test props are local to the lab.

## Cover movement and shoulder views

Both Frontier and Arena use the same geometry-driven cover movement. Stand within **1.35 m** of a tree trunk, wall, stone barrier or solid debris, with it **in front of you**, and press **F**. A surface behind the view is never cover, however close it stands, and nothing sticks on its own: walking past a tree does not attach you to it. The character approaches with normal collision, faces away from the surface, and stays attached while you look around freely. **WASD** slides along the surface at **2.2 m/s**; hold **Shift** to slide at **4.2 m/s**, spending stamina with normal exhaustion rules. Both speeds work while crouched. **Input that points away from the surface releases it** and leaves the body free, and it stays free until you press **F** on something again - so does jumping, rolling, the side step, a blade, death and lost support. Contiguous rounded, faceted and compound surfaces can be followed without treating collider-shape seams as cover edges. Genuine edges, hard corners and unsupported ground still stop movement. Decorative meshes without collision and the ground are not cover.

Tree trunks carry the bark you can see: `TreeKit` cuts trunk collision from the tube's own profile — one cylinder on the flare's footprint at the ground, never the species table's taper (a fifth narrower than the flare) and never the trunk mesh's box (which carries the branch tips out to the crown) — so the body and the protected anchor measured off that surface stand against the tree instead of inside it or a metre off it.

**X selects the left or right lookout**; the HUD shows **LEFT LOOKOUT**, **RIGHT LOOKOUT** or **TOP LOOKOUT** when exposed. Hold **RMB** to look out. Low cover uses a standing top peek; tall or rounded cover uses the selected side. The controller chooses the shortest supported, capsule-safe step with a clear firing corridor: **0.45 m**, extending to **0.55 m** or **0.65 m** only when the geometry requires it. A wide object may require sliding to its flank first. Trees, rotated props and convex rocks use the same clearance checks, not object-specific exceptions.

Lookouts keep one protected anchor and one selected destination through hold and return. Free look and button release do not silently switch the physical side; a new request or explicit X swap captures a new view frame. Ground-supported capsule sweeps follow slopes instead of treating floor contact as a wall, and a small floor-recovery displacement cannot leave the return latch stuck. Authored top/left/right poses follow actual exposure. The camera retains swept-volume collision during shoulder changes. Shoulder selection does not change weapon handedness.

**C** toggles manual crouch on the ground, in or out of cover; it never changes armor. Crouching lowers the camera, skeleton and collision capsule together. Starting a melee skill cancels the crouch first: the capsule stands when there is headroom, then the authored clip plays. Authored crouch idle and stepping animations support attached movement at both slide speeds, including curved surfaces. Side peeks preserve crouch; a top peek temporarily rises, then restores the tucked posture. Outside cover, crouched movement is **2.2 m/s** and Shift does not sprint. Leaving with **F** preserves manual crouch. Standing waits for clear headroom rather than expanding the capsule through a ceiling.

**LMB attacks directly out of cover; RMB is not required.** A bow draw automatically exposes over low cover or around the selected edge. Releasing early freezes charge while the character finishes exposing and raising the bow, then fires exactly once. The character retucks after follow-through. Blocked edges and insufficient headroom reject bow exposure rather than storing a shot that fires later.

**Melee breaks sticky cover immediately.** A valid sword click releases attachment and starts the normal swing without waiting for a peek, including at the solid middle of a tall wall. You can move away from the wall during the attack and remain detached afterward; press **F** to attach again. The exit does not teleport, force standing, or clear manual crouch. Cooldown, airborne and rolling restrictions still apply, and a rejected attack does not detach you. The blade still collides with world cover; attacking does not allow damage through walls.

A draw begun during a manual RMB peek leaves that peek under manual control: release RMB to retuck without canceling the held draw; releasing the bow afterward exposes again before firing. Holding RMB keeps the manual peek after a bow attack finishes; it cannot reattach a melee attacker. Cover releases check the visible arrow shaft from nock to tip, including an initially buried nock. A genuinely obstructed shaft cancels its pending shot instead of firing through the obstacle or storing a latent release. Clear shots follow the center crosshair ray: the physics arrow starts at a validated point on that ray, and the rendered shaft blends from the bow tip to the authoritative path over 0.12 s. If that camera-ray point would be buried in the cover the character is posted against, the shot keeps the rendered tip rather than firing through geometry. Actual projectile collisions still block obstacles.

**Space** and **Shift + Space** leave cover, clear manual crouch and attack/peek intent, then jump or roll; insufficient standing headroom blocks takeoff. Cover grants no invulnerability. Cancellation, equipment changes, death, respawn and returning to camp clear pending attacks. Arena remains host-authoritative: clients send validated movement, lookout context, crouch intent and the snapshot used to sample aim—not trusted collider sizes or cover positions. Remote releases wait for a fresh aim sample from the current exposed pose, without adding charge. Lost input cancels automatic/frozen cover intent, so it cannot fire later when input resumes.

## Bow charge, damage and re-nocking

Aiming behaves like a shooter: the camera turns with the mouse and the crosshair stays in the center. There is **no auto-fire, unit lock-on, target tracking, or automatic gravity compensation**. Hold left mouse to draw and aim; release to launch one arrow along the current crosshair aim. Holding at full draw never fires automatically. Arrows still fall under gravity after launch, and only actual collision applies damage.

Both shoulder views aim at the world point under the crosshair, independently of the character's previous facing. Aim queries start at the character's view-height plane and skip the shooter and only the cover body you are posted against. Raising or turning the bow cannot make the query skip a nearby target. Arrows launch along the exact center-crosshair ray instead of converging from the bow tip, and the visible shaft blends from the bow to that ray over 0.12 s, so shoulder swaps and bow poses cannot bend the trajectory. Arrows still fall under gravity and collide normally.

```text
arrow damage = bow base damage × clamp(draw amount, 0, 1)
```

Zero draw gives zero damage, half draw gives half damage, and full draw gives full damage. The hit's own armor channel applies afterward: the helmet on a head hit, the body kit on the rest. Arrow flight and world obstruction use real swept physics collision. Full-draw arrows leave at **66 m/s**, **84 m/s** and **102 m/s** for the shortbow, recurve and longbow; partial draws scale speed from 45% to 100%.

**Every loosed arrow costs one shaft.** In the warband campaign the party carries one shared quiver (`Warband.arrows()`, the `arrow` item in the shared stash), and each release - a plain bow shot or a shaft from **Barrage**, **Triple Volley** or **Piercing Shot** - takes one out of it. At zero the string will not come up at all: the HUD strip shows `gold · arrows`, a refused press prints **Out of arrows**, and the two ways to fill the quiver are a keeper's bunch (ten shafts for 20 gold at **Storekeeper Orla** or **Smith Brann**) or a dead trail archer, whose corpse carries the twig bow it fired and four of its own shafts. The frontier, arena and delve rangers have no quiver and are unaffected.

Hits in the animated **head zone** deal **double damage**; body hits keep the base value. The zone follows the head joint through crouch, cover lean and rolls. It applies to arena players and bots plus every ranger clone, the wolf and cinder devil, the five imported devils, the three forest mobs and the delve wave (imported species included). The zone is a **band across the body and never narrower than the capsule an arrow stops on**: an authored radius wins when it reaches past the capsule (a wolf skull, a beast muzzle), otherwise the zone is widened to the body radius plus 5 cm, so a shaft that lands on the head height of the visible body is always a headshot. A head hit then resolves the helmet's **head guard** instead of the body kit, so plate's 50% sallet brings a headshot back down to a normal hit. A blade that sweeps through the head zone also doubles, even when the shape query reports the contact elsewhere; the zone is a damage volume on the normal body capsule, not a second collider.

The charge bar and bowstring animation fill together over the bow's full draw duration, including raising the bow. Release whenever you want: a large bow held for **1.5 seconds deals 50% damage**; holding it for 3 seconds gives full damage.

| Bow | Full draw duration | Full damage before armor |
| --- | --- | --- |
| Small | 1 second | 30 |
| Medium | 2 seconds | 38 |
| Large | 3 seconds | 50 |

There is **no separate bow attack cooldown**. Every release, even at zero or partial draw, plays a 0.28-second follow-through followed by 0.95 seconds to fetch and nock the next arrow. You can start drawing again as soon as that animation finishes. The HUD shows **NOCKING NEXT ARROW** during recovery. Changing weapons, bow size, movement or canceling cannot skip or restart re-nocking. Canceling an unreleased draw does not spend its arrow. Walking and running do not slow charging or re-nocking; you can move while aiming. New attacks cannot begin while airborne or rolling.

The draw hand uses a cheek-surface landmark on the imported head. Bow raising, shoulder retrieval and re-nocking follow reachable paths outside the torso; the bow is brought in front of the centreline while loading. Geometry regressions check the forearms against the actual skinned outfit, not just whether the bones remain connected.

## Thrown weapons

Hold **T** with a sword or dagger equipped to charge a throw, then release to hurl the weapon. Throwing reuses the bow's attack shape: the crosshair aim is the flight line, damage is multiplied by the actual charge, and a release spends a **0.28-second** follow-through plus **0.95 seconds** of recovery before another throw, swing or draw can start. Holding at full charge never throws automatically.

```text
thrown damage = weapon base damage × clamp(charge, 0, 1)
```

Charge time follows the equipped weapon's own attack duration: **1 / 2 / 3 seconds** for the shortsword, arming sword and greatsword, and **0.5 seconds** for the dagger. Full damage is the weapon's normal melee base damage (30 / 38 / 50 for swords, 14 for the dagger), halved at half charge and zero at zero charge. A thrown weapon falls under the same gravity as an arrow, uses swept physics collision, stops on the first world or body contact, and applies the normal **2x head-zone** multiplier before armor. It cannot be parried as melee; it uses the projectile damage path.

The hand weapon leaves the hand for the release frame and the **endless supply** restores the same equipped weapon as recovery begins. Throwing does not remove gear from the paperdoll or backpack. **T never replaces melee**; left mouse and the wheel still perform the normal sword or dagger attacks. Throws automatically expose from cover like a bow, and a wall between the hand and the aim line cancels the throw rather than passing the weapon through cover. In the arena the host owns the thrown projectile, its damage and its replication; clients only send the charge/release intent and aim.

## Swords and jump-rolls

Standard sword attacks are fast, descending **diagonal cleaves**: **0.60 / 0.78 / 1.02 seconds** for the shortsword, arming sword and greatsword. Larger weapons cut a wider arc with longer reach. Explicit overheads retain their **1 / 2 / 3-second** authored timing; precision stabs remain **0.5 seconds**, and throw charging is unchanged.

| Input | Swing | Path |
| --- | --- | --- |
| LMB | Diagonal cut from the camera shoulder | Cock the blade up and behind the striking shoulder, unwind the hips then the chest, and cut down across the front into a low opposite-side follow-through. Right shoulder starts right-to-left; left shoulder starts left-to-right. Subsequent cuts alternate; X resets the next side to the selected shoulder |
| Wheel up | Forward stab | The authored dagger thrust clip drives a **0.5-second** sword thrust down the crosshair line, with a short windup and fast recovery |
| Wheel down | Overhead chop | The original authored one-hand or greatsword overhead load and downstroke |

Melee has no held charge: each click starts one attack, never a held-button repeat. Every diagonal runs a **four-phase kinetic chain**: **0-30% wind-up** (both feet stay planted in the stance the attack started in — the swing pivots over them instead of stepping — weight settles onto the back foot, the pelvis coils about 27 degrees and the chest twists to roughly 50 degrees, and the weapon lifts out of the carry it is already in — out and up, never presented forward first — until the hands cock behind the striking shoulder while the free off hand reaches forward for balance), **30-45% release** (the hips snap first, the chest follows, the right shoulder drives past the left, the elbow leads and the wrist snaps through the apex), **45-65% follow-through** (the chest leans about 15 degrees forward into the strike over the planted feet — never back — the hilt crosses the body and the blade carries past the centre line to the low opposite hip while the head keeps the target in view), and **65-100% recovery** (the torso unwinds and the weapon returns to guard). The damage sector uses the same release curve as the visible arm, so contact timing and the blade agree. While moving, crouched or sliding, the pelvis stays owned by locomotion and the coil lives in Spine 01/02/03 and the right clavicle. Diagonals also sample the heavy overhead's authored leg drive, bend into the load and settle over the leading foot. Left/right cuts mirror the footwork. Wheel attacks retain their authored precision paths. A rejected local or host attack does not consume the next side; remote clients alternate dispatched attack intents without a new acknowledgement RPC.

The **dagger** (key **3**) uses the same alternating LMB diagonals, with a **0.42-second** cut, **14** base damage, **1.2 m** reach and a **150-degree** full frontal arc. Wheel up uses its **0.5-second** authored aim-directed stab; wheel down also uses that precision stab because the dagger has no authored overhead. The thrust follows the crosshair rather than auto-targeting: low aim angles toward a wolf, high aim stays high.

The dagger's **Prison shank** passive speeds the **forward lunge only**: wheel up runs at **+200% attack speed** (**0.167 s** per stab, three stabs in the time one used to take), while wheel down keeps the authored 0.5 s. `scripts/item_passives.gd` owns the row and `Archer.variant_attack_rate()` applies it, so both daggers carry it, a sword never inherits it, trinket attack speed multiplies with it, and the item tooltip on either dagger lists it.

During the active diagonal stroke, damage sweeps a **frontal sector** in the cut's direction, rather than requiring a thin blade to touch every body. Shortsword / arming sword / greatsword reach is **1.8 / 2.1 / 2.5 m**, with full arcs of **160 / 170 / 180 degrees**. Staffs use the same damage and swing clock but a swing of their own rather than the two-handed sword's: the right hand sits just below the shaft centre and the left hand grips **0.32 m** above it, both hands drive forward as a piston, the shaft barrells through a wider arc than the hands travel, the leading end finishes ahead and low while the rear end counterweights up and behind, and the ember/bone shafts reach **1.6 / 1.5 m** (the catalog and HUD show the same values). This catches short enemies across the front while excluding targets behind or beyond reach. **One attack strikes a capped number of bodies** (`Combat.ONE_HAND_MAX_VICTIMS` / `TWO_HAND_MAX_VICTIMS` / `ABILITY_MAX_VICTIMS`): every one-handed piece - swords, clubs, daggers, either hand of a dual pair - strikes **one** body per swing, a two-hander (greatsword, heavy branch, staff) **two**, and one item-skill activation (every beat of a spin, one blast) at most **ten**, nearest first. A capped cut is spent on the bodies it crosses first: from the loaded side along the sweep, nearest first among bodies on one line, whatever the frame rate. Every victim is checked separately against world cover, so a wall protects the target behind it without spending the cut's strike. Each hand damages each victim **once per swing**, only during the active stroke, with normal **base body damage** (30 / 38 / 50 for swords, 14 for daggers)—never incidental cleave headshots. Precision stabs, authored overheads, arrows and thrown weapons retain actual-contact **2x headshots**. Guards, parries, clashes, cancellation and host-only damage remain in force. Switching weapons or rolling cancels further hits without erasing melee recovery; bow readiness stays independent.

## Dual wield

Press **5** with a one-handed sword selected and a **dagger or another one-handed sword in the paperdoll's off hand**. The off-hand piece determines the left weapon and its profile; the mode requires the small shortsword or medium arming sword in the right hand, so the greatsword leaves dual wield. A raised shield is stowed when dual begins, and the shield cannot be raised while dual wielding.

Left click performs **diagonal_left** with the left-hand weapon; right click performs **diagonal_right** with the right-hand sword. Both face the crosshair and use the equipped hand's diagonal timing, reach, arc and base cleave damage: an off-hand dagger uses **0.42 s / 14 damage / 1.2 m**, while an off-hand sword uses its corresponding sword profile. Scroll up stabs and scroll down performs the authored overhead with the right-hand sword; these remain precision attacks with headshots. **T** still throws the right-hand sword.

**Recovery is per hand.** You can start either hand while the other winds up, strikes or recovers; the freed hand can attack again when its own action completes. While the right sword is active it drives the body animation, with the left cut layered on the same skeleton. The HUD shows **LEFT** and **RIGHT** percentages (or **READY**). A standard block knocks aside only the contacting hand; a parry staggers and cancels both.

**Dual wield has no guard.** RMB never raises a block, and a shield cannot be raised. Instead, an attack inside its active strike window parries a front melee hit: no damage and the attacker is staggered for **0.8 s**. Windup, recovery, a hit from behind, or any non-dual attack does not parry. The attack parry does not stop the dual wielder's own swing, and there is no stamina cost.

## Guarding, parries and clashes

Equip a sword with **2** or the dagger with **3** and hold **RMB** while grounded and ready to guard. The character faces the camera, stops rotating with movement, and does not regenerate stamina while guarding. A hit from the front resolves from the guard timer and weapon, not exact blade geometry:

| Outcome | Trigger | Result |
| --- | --- | --- |
| Parry | Block began at most **0.25 s** before the hit | No damage. The attacker is staggered for **0.8 s**, leaving a guaranteed counter-hit. |
| Standard block | Guard held longer than **0.25 s** before the hit | No damage, **22 stamina** spent, and the defender is pushed slightly away. The contacting hand resets; a dual wielder's other hand keeps swinging. |
| Weak dagger block | Any hit into a raised dagger | **Half damage** still applies, **30 stamina** spent, no parry, and the attacker's swing continues. |
| Shield block | Any front hit into a raised shield | **No damage**, **18 stamina** spent, the defender is pushed back, and no parry is possible. |
| Attack parry | Dual wield and the strike is inside its contact window and facing the attacker | No damage and the attacker is staggered for **0.8 s**; the dual wielder's swing continues. No stamina cost. |
| Unblocked | Guard down, wrong facing, rolling, attacking outside a dual strike window, or no weapon | Normal damage applies. |

The **shield** (**4**) is a physical off-hand item carried on the left arm and legal with the dagger or any one-handed sword, including the shortsword. Holding RMB raises it in front of the chest and head, overriding the dagger's weak guard or the sword's parry timing with a **full front block**. The shield is a moving collision body in both modes: an arrow that hits it — raised or merely carried, whether it came from a player bow, a cinder devil's bow or a ranger clone — deals **zero damage** to the player and **sticks into the shield**. An arrow that reaches the body still deals damage and **sticks into the player** where it landed. Stowed shields are hidden and inert; switching to a bow, greatsword, staff or dual wield automatically stows the shield.

Releasing RMB drops the guard; pressing an attack while guarding also drops it. Dual wielders cannot guard at all: RMB attacks with the right-hand sword instead, and defense comes from the timed attack parry above. Guarding pauses stamina recovery, so repeated blocks cannot be turtled for free, and a guard with insufficient stamina still spends what remains. The held pose is a dedicated character-only animation: `Sword_Block_Loop_OneHand` for the dagger, short and arming swords, and the two-handed `Sword_Block_Loop` for the greatsword. Both are **120-sample / 1.983-second** breathing loops with planted feet; the greatsword's support hand stays on the actual hilt. These clips animate the Ranger rig only; the held weapon remains the normal socketed runtime model, and the lower-body crouch/slide layer does not overwrite the guard arms.

If two **sword** users are in their active downstroke at the same time and facing each other, their blades **clash** instead of trading damage: sparks and a loud clang, zero damage in both directions, a small bounce apart, and both swings reset so either fighter can immediately act again. A clash never uses an exact sword-to-sword contact test; simultaneous active hit-frames plus mutual facing are sufficient. A dagger never clashes; it can only weak-block and must rely on its speed and short recovery.

The character uses a 65-bone skinned humanoid and authored animation clips. The greatsword has a genuine two-handed overhead load, accelerating downward cut, whole-body weight transfer, closed hilt grip, follow-through and recovery. Short/medium swords use a separate authored one-handed overhead. Source motions are retargeted and grip/timing corrections baked in Blender. Overheads and stabs keep their authored elbows; diagonal cuts pose the striking and support arms at runtime over the authored body, cocking high and behind the shoulder, then finishing low across the front. The staff is socketed by its middle with both hands spaced around the shaft centre, so both ends sweep during standard cuts and the guard; the authored overhead and thrust slide to an end grip over their wind-up so the long shaft stays clear of the floor and head. The textured character and environment remain stylized, not photorealistic rendering.

**Shift + Space** starts a tucked forward tumble and directional burst immediately, either from the ground or during a jump. Space alone only jumps; double-tapping it never rolls. Knees and elbows fold, the chin tucks, the weapon stays clear of the torso, and landing compresses the legs before returning to the normal stance. Running or strafing direction takes priority over facing. Only one roll is allowed before landing; it does not grant invulnerability or ignore world collisions.

[In-engine authored sword, bow, movement and roll preview](media/motion-preview.mp4)

Authored walk, jog and sprint clips follow actual movement speed with a continuous gait phase. The sprint includes knee/heel recovery, flight, body lean and alternating arm drive. Bow aiming and terrain contact use skeletal corrections; the greatsword keeps a coupled two-hand carry. Collisions that stop movement also stop the running gait.

## Multiplayer feel

Remote fighters use **snapshot interpolation** rather than chasing the newest packet. Each replica buffers timestamped host snapshots and renders **0.12 s** behind them, blending position between the two samples that bracket the render time. The local client seat uses a shorter **0.05 s** delay. If packets are late, the last authoritative velocity carries the body for at most **0.15 s**, then it holds instead of inventing a long extrapolation. Teleports and respawns snap and clear the buffer.

Every hit spawns a **scrolling world-space damage number** that rises, drifts and fades; headshots are larger and gold, damage you take is red, and lethal blows are orange. Arena clients derive the number from the authoritative health delta in each snapshot, so all peers see it without a new network message.

Taking damage rolls an **attack interruption** against the share of max health the hit removed. A hit under **5%** never breaks a swing; a hit at **50%** or more always does; the chance ramps linearly between, so three small enemies can be traded through while a heavy hit lands with weight. A landed roll staggers for `0.08 s + 1.2 s × damage share of max health`, capped at **0.62 s**. The victim's movement input, guard, draw, throw and swing are interrupted, the torso and head recoil visibly, and the cap still leaves a counter window. A shrugged-off hit still rocks the pose and cancels a consumable but leaves the swing running. The recoil replicates through the animation phase as `STAGGER` without adding a snapshot field.

**Coming back from a death clears the interruption.** The killing blow staggers the body it kills, and a downed body never drains that clock, so a revive would otherwise hand the ranger back for the rest of the stagger with every left click refused. The revive — the frontier respawn, an arena round and the delve's raise — clears the stagger, drops any half-finished swing, draw, release, recovery, guard or consumable, and restores the collision its scene configured (the frontier ranger still collides with mobs). The first click after coming back attacks. Both peers get this: the host's own respawn clears the same state.

Fighters no longer hard-collide with each other. Their capsules have a **soft separation** that only pushes when centres are inside **0.46 m**, which lets two players close to stabbing distance without being shoved off their aim. World geometry, cover, blades and projectiles still collide normally.

The title's **Join Game** and **Host Game** forms remember the **last player name, the join address and UDP port, and the port this machine hosts on** in `user://net_cache.json`. Joining a game updates the join side after validation, and **Join Game** rereads that file every time its form opens, so a session that joined somewhere else never leaves stale values on screen. **Host Game** writes its own `host_port` instead, which is why a remembered join port cannot move the host socket onto a port nobody else knows.

## Blood and wounds

This is an 18+ game: unmitigated damage now leaves persistent gore. **Every mob bleeds** — the Briar wolf, cinder devil packs, the five imported devils and the delve devils all take body stains, floor spatter and a death pool; the ranger does too. A real contact throws a spray of droplets from the wound, flings smaller drops onto the ground and walls around the victim, speckles the floor beneath it, soaks blood into the victim's clothes, and marks the attacker: a drawn blade takes a coating, a claw, paw or muzzle takes a soak on the limb that struck, and an arm's-length melee kill throws the victim's blood back over the killer's chest and face. Lethal blows add an arterial burst and a growing pool under the corpse that stays for as long as the body does. Blocked, parried and weak-blocked hits draw no impact spray; only weak blocks still leave the half damage's wound. A defeated body then **lies where it fell for five minutes** (`scripts/corpse_hold.gd`) holding its authored death pose, before a short dissolve frees it.

Blood is laid on the garment, not beside it. `scripts/blood_surface.gd` measures a rig once — every visible skinned-mesh vertex is binned into its dominant bone as a radial profile of the cloth around that bone — and keeps a thinned sample of the whole garment. A wound scatters several textured splashes across that measured strip, then uses the current pose to find the **outermost** layer under each splash and lifts it clear, so a belt, a sleeve cuff or a second armour layer cannot swallow the stain. The Sunken Delve's primitive depth roles are measured as their own triangles instead. Patch samples clamp to the measured strip, so a stain never rings the air past a cuff or the crown (the old extrapolation drew red "feathers" off hoods), and the cloth soak is a small ragged core with round satellite droplets rather than one large splat. An arrow carries only a short wet smear behind its head, never a blade-sized coating. Stains ride the nearest skeleton bone, so they travel with the limb.

Stains last **60 seconds**, then fade over the final three and are released — except for death pools. A lethal blow pools blood under the body, adds two lobes draining out past the corpse and keeps creeping outward for a few seconds; that pool holds for **five minutes**, the same clock as the corpse lying in it, and lives in its own **60-pool** budget so the sixty-second spatter recycling can never erase the pool a body is resting in. Surface spatter follows slopes and steps because each patch is conformed to the real collision surface, and weapon blood is parented to the drawn weapon so it moves through every swing. A scene owns at most **160 surface stains** and **10 wounds per fighter** (8 per weapon); the oldest stain is recycled first when a large fight exceeds that budget. Blood is presentation only — it never changes damage, hit detection or network authority, and a hit that applies no damage spawns none.

The project renders with the **GL Compatibility** backend, which has no decal support, so blood does not use `Decal` nodes: `scripts/blood_fx.gd` owns procedural splat, pool and soaked-cloth textures plus their materials, `scripts/blood_surface.gd` measures garments and builds conformed patches, and the per-scene `scripts/blood_field.gd` owns stain lifetime, weapon coatings and capped particle bursts. The first blood event on a rig costs a one-off ~30 ms measurement; later wounds are single-millisecond work. The host spawns blood where it applies damage; arena and delve clients derive wounds and the weapon-blood tally from the snapshot health delta and `weapon_blood` field, so all peers see the same result without a dedicated network message.

## Audio

The game has a real soundtrack and a real mix. **The menu** (`title.tscn`) plays `assets/audio/music/menu_theme.ogg` on a loop; **every other scene** — the camp, the trail, the town — carries `assets/audio/music/warband_soundtrack.ogg`, the 49 minute master, also looped. A scene never starts a track: the `Audio` autoload watches the current scene and crossfades over 1.2 s, so a new scene cannot be silently silent. The bed that finishes drops its stream, so the score is not held in memory while the menu is up.

**Escape opens a ledger window** everywhere it opens a menu: on the title screen it is the settings page with an index and a **SOUND** sub menu, and the campaign's quick menu carries the same SOUND page one row in. The page has a level and a mute for **music** and for **effects** separately — a slider is one bus write, so everything under it follows — and the mix is remembered in `user://audio_settings.json`.

Combat is scored from the recordings, not from placeholders: a swing whooshes (the short take for one hand, a flick cut from the same takes for a dagger, the long bamboo arc for a greatsword, the heavy branch or a staff), a blade that lands opens a body while a club thuds and a dagger's cut stays small, a guard rings with steel on steel, a parry snaps, an arrow or a thrown blade leaves the hand with its own sound, boots on the forest road are the quietest thing in the mix - a footfall on its own voice pool, so a walk can never cut a blow, and other bodies' boots are quieter, duller and gone by eleven metres - and a cage latch is a real padlock and chain being worked open. The weapon reading is the piece in the hand (catalog index or a mob's carried item), so a makeshift club is blunt and steel is not. `docs/audio.md` has the whole mapping, the bus layout and the slicing tool; `tests/audio_regression.gd` proves it headless.

**Bodies have voices.** A wolf growls going into its bite - not on every bite - and cries when it dies, the death six cuts out of one recording pitched down until it reads as a wolf. The player's body grunts on a blow that took a real share of its health, says the line a player remembers when a hit could have ended it, sometimes says something over a kill, and moans while it bleeds on the ground; the town's keepers answer the counter you walk up to. Every one of those is a table row: a logical trigger (a committed bite, a blow over a threshold, a kill, a counter used), a chance, a cooldown, a threshold, and a set of takes picked at random and never twice running. `VoiceLibrary` (`scripts/audio/voice_library.gd`) holds the voices and their rules, `VoiceEmitter` the per-body clock and rolls, and `Voice` the one call a scene makes. **The party has five recorded profiles** - sergeant, veteran, bruiser, scout, hothead - one set of lines recorded five ways and handed to a mercenary by id, so every body in the band sounds like its own man: something hostile coming into its reach takes a one-in-a-hundred roll on "oh shit, here they come", "who... oh" or "get ready", and a blow that took a real bite of its health takes the same roll on a scream or a curse. Those lines are placed at the body and die off inside 26 m, so a squadmate shouting across the field is heard from where it stands and not at all from further off. The takes live in `assets/audio/voice/<voice>/` and are cut from licensed recordings by `python tools/slice_game_audio.py --only voices --fetch` (the party's five profiles are the author's own takes, converted per profile); a voice whose recordings have not been delivered simply says nothing. The wolf's two recordings are by [newagesoup](https://freesound.org/people/newagesoup/sounds/338674/) and [Coral_Island_Studios](https://freesound.org/people/Coral_Island_Studios/sounds/277195/), both CC BY 4.0 - the attribution and every change are in `assets/audio/LICENSE.txt`.

## The campaign

**One world, three places.** The campaign is a single scene: the cage camp, a
1,374 m trail through the wood, and the walled town of Hearthstead. Walking is the
only way between them - nothing in the world changes scene.

**The cages** are where a run starts: five prisoners in five cages, one shiv in
the dirt outside your own door, and watchers asleep in the trees. Cut a latch with
a blade in hand and **G**, fight the pair that wakes, then free the other four -
each freed body arms itself off the ground and joins the squad.

**The trail** is the wood the squad walks: torch pairs every eighteen metres,
briar walls, the cinder cult's watcher camps and the briar wolves that hunt off
the lane. Three small checkpoints mark how far the warband got.

**Hearthstead** is the staging town inside the same walk: three keeper counters
(**Smith Brann**, **Storekeeper Orla**, **Quartermaster Vey**), the market stash
chest, the **quartermaster's orders**, the recruiter's board, the wardens' altar
where an anointed piece wakes into a skill, and the fire.

**The orders** are the campaign's own goal track (`scripts/warband/quest_log.gd`):
one of five goal shapes (`KILL`, `RESCUE`, `COLLECT`, `APPLY`, `REACH`), offered,
accepted and turned in at a keeper, with the chain in `next`.

**The wood's creatures.** The campaign's hostiles are the **hollow warden**,
**ossuary stalker** and **gallowsroot** on the warband's own skeleton (one AI and
one sampler, three profiles), the trail's **archer ambushers**, and eight briar
wolves in two deep-wood packs. They share the engine's one rule set:

- `scripts/mob_senses.gd` - a 140 degree sight cone, line of sight to the chest,
  a 15 s pursuit memory, and an enraged pursuit when something hits them;
- `scripts/mob_steering.gd` - one avoidance rule: probe the lane, commit to a
  side, hold it so a body never dithers;
- `scripts/mob_wander.gd` - a territory per pack, one goal on a shared clock;
- `scripts/mob_lod.gd` + `mob_culler.gd` - 1/3/12/24-frame tick bands by distance
  and a body parked past 150 m.

## World art

The frontier and arena are dressed by a small, data-driven world-art kit rather than per-scene primitives:

- **Textured sky.** A photoreal 4096 × 2048 equirectangular panorama (`assets/world/textures/sky_frontier.png`) supplies the sky background: a Rayleigh-like blue gradient, a real-sized sun disc and aureole at the key light's exact direction, a perspective cumulus deck with self-shadowing, thin cirrus and aerial haze. Fog, ambient light, filmic grade and saturation are tuned to it.
- **Hill country.** The wood has real elevation: three octaves of value noise at **190/100/58 m**, normalised to **±22 m** either side of level, so the walk to town crosses a crest every eighty metres or so and never climbs harder than about **15 degrees**. The camp pocket and the town square are held flat - `RELIEF_HOLD_INNER` 40 m of level ground around each pad, the swells reaching full height by `RELIEF_HOLD_OUTER` 260 m - and the mountain rim and the one swamp are unchanged, so the trail is a road between hills rather than a plank 1,375 m long.
- **Textured terrain.** The continuous heightfield keeps its authored routes and clearings and renders through one world-space shader (`scripts/world/shaders/terrain.gdshader`) over four tiled layers - grass, forest-floor leaf litter, trodden dirt and rock/scree - each an albedo with its height in alpha plus a normal map. Where two layers meet, the taller texel wins (grass blades stand in the soil, stones break through it), so a worn edge is ragged and soft instead of a cross-fade; every layer is read twice, the second read turned and scaled, so a tile never prints the same patch in a row. Rock follows slope, litter lies in broad noise patches and dirt is the worn ground. In the warband world that is a half-metre **ground map** baked by `scripts/warband/terrain.gd` from the lane, the camp's corridor, its yard, cages, fire, shelters and cart ruts, and the town's ring (wear in red, wet in green - the swamp's mud and the ruts), and `Terrain.wear_at()` lets the grass be trodden out of it; the frontier keeps its per-vertex path weights. Nothing is laid on top of the ground any more: the camp's dirt discs and the lane's trodden patches are gone, and ground blood is a soft-edged splat card. Grass is four bent alpha cards per clump lit as a mound (bases in shade, light through the blades), wildflowers and ferns are chunked alpha-cut cards, and all of it sways in the wind and fades out at its visibility range; along the trail the cover runs the whole verge instead of two meadows.
- **Textured trees.** A species library builds deterministic mesh variants: oaken trunks with real branches and leaf-card crowns, layered briar pines, slim silver birches, amber rowans and bare snags. Bark and leaf textures are separate authored PNGs with normal maps and per-instance tint, so one mesh family yields many colours and silhouettes. Sizes, species weights and shape parameters live in code, not in the mesh files.
- **Natural stone.** Scattered rock is authored, not repeated: `scripts/world/rock_kit.gd` deforms a faceted ellipsoid with a seeded noise field, narrows the crown and cuts a flat fracture face near the base, then smooth-shades it so the silhouette is broken but the surface reads as weathered granite. Five archetypes (rounded boulder, bedding slab, ledged outcrop, standing spire, cobble) are produced in variants, scattered in loose clusters, sized independently, bedded at their own angle and set into the terrain below the lowest ground under their real footprint, so a boulder breaks out of a slope instead of resting on it. Each variant's convex hull is its collision. Boulders and heaped fire stones use the natural `granite.png` surface (quartz and feldspar speckle, weathered veins, moss in the cracks); the coursed `rock.png` stays on carved stonework and dungeon walls. Village timber, plaster, roof shingles, bridge timbers and woven wattle panels share the other triplanar materials, and the pond uses a ripple normal map and a cheap sky-tinted fresnel shader.
- **The forest camp.** A narrow footpath leaves the west cross road and runs ~110 m into the deep western stand, where a fifth of the world's trees are packed into one belt so the walk in is through real woods. `scripts/world/camp_kit.gd` builds what waits at the end, out of cached primitives merged into one multi-surface mesh per shelter and one batch for all its clutter: six shelters of saplings bent at a kink, cross-hatched with twigs and heaped with twig piles and straw (1.9-2.9 m wide, 1.2-1.6 m tall - child-sized, never a building), split into clusters: three dens west, two south and a hunter's den out in the trees; clootie trees, a bone arch, painted mask stakes, skull rings, a bound straw figure, a wicker effigy, a strung web of cords, driftwood, drying racks, an offering stone, brush windbreaks, a bound-stick idol, pots, cauldrons, bone heaps, and eleven shapes of hanging charm (bone chime, skull string, pot string, antler, wicker cage, rag fetish, rib bundle, rune board, cloth bundle, bone mobile, mask chime) - over 400 of them, two to four per tree on the 130-odd trees around the camp and down the path, plus two per shelter eave. Every prop is deterministic from its seed.
- **Undergrowth.** `scripts/world/bush_kit.gd` builds bushes as fists of leaf cards (three silhouettes per foliage atlas) with the same UV2 wind and vertex tint as the tree crowns, batched through `WorldScatter` and fading at 82 m. They are placed thickest round the camp and along both footpaths and thin out in the open, with no collision.
- **Fire.** A ring of bedded stones, an ash bed, charred logs and a live flame. The 2x2 tongue atlas (`flame.png`) is soft-edged gradient fire - an orange body, a white-hot core and a coal bed under it - rather than flat polygons. `scripts/world/fire_fx.gd` builds the cards for both fires (four staggered rings plus a low apron that keeps the burning bed continuous), bakes a phase into each card's vertex colour and adds the embers, the smoke plume and the lamp. `scripts/world/shaders/flame.gdshader` cross-fades two neighbouring tongues so the fire morphs instead of stepping, warps the tongue with a rising noise field that grows toward the tip, ramps the heat down the flame, breathes globally, and fades out against whatever geometry a card cuts through. `scripts/world/fire_flicker.gd` makes the light wander with the flame instead of sitting at constant energy.
- **Gallowgarth.** A second footpath leaves the ruin road and runs into the north-eastern woods, where `scripts/world/village_kit.gd` builds the wardens' village: a 15 m stake palisade with an antler gate and a torn hide banner, three stick-walled longhouses, three round wattle huts, carved totems, a great firepit with a cauldron tripod, an offering ground with a gibbet and mark stones, a bound wicker effigy, a clootie gallows tree, drying racks, a hanging frame, woodpiles, skull stakes, carved idols and charms. This is the fuller bushcraft set - the deep camp keeps its own cruder, smaller one.

Everything is batched into per-chunk `MultiMesh` instances with explicit AABBs and visibility ranges. Grass and leaf cards use alpha scissor (no sorting), cast no grass shadows, and vary tint per instance; there is no per-frame scenery script. Measured on the development machine at 1280 × 800 with the GL Compatibility renderer (uncapped, GTX 1080), the frontier holds about 155 FPS at the village and 270 FPS in dense forest, drawing roughly 720k and 704k visible primitives. The previous flat-colour primitives drew about 1M primitives at roughly 196 / 376 FPS; the extra draw calls come from shadowed alpha foliage. The arena is far lighter at about 280 draw calls and 46k primitives.

### Editing the world look

`scripts/world/` contains the re-usable kit:

| File | Responsibility |
| --- | --- |
| `world_style.gd` | Data for the frontier and arena: sky/grade, ground textures and tints, tree species, grass/cover densities, prop tints. Add a species here or append one at runtime. |
| `tree_kit.gd` | Seeded trunk/branch/foliage mesh generation for the four tree forms. |
| `texture_library.gd` | Cached texture loading and shared materials/shaders. |
| `scatter.gd` | Chunked MultiMesh batching with instance colours and visibility ranges. |
| `grass_field.gd` | Grass, flower and fern placement with slope/reserved-area rejection. |
| `environment_kit.gd` | Panorama sky, fog, ambient, tonemap and sun/shadow setup. |
| `camp_kit.gd` | The Unholy Forest camp's art: merged-mesh builder, palette, bent-twig shelters, fire ring, clootie trees, bone arches, mask stakes, skull rings, straw figures, wicker effigy, charm web, chopping block, driftwood, drying racks, offering stone, idols and the eleven hanging charms. |
| `bush_kit.gd` | Woodland undergrowth: leaf-card bushes with three silhouettes per atlas, scattered with `WorldScatter` and tinted/winded like tree foliage. |
| `village_kit.gd` | Gallowgarth's art: the same merged-mesh builder with the heavier set - stick-walled longhouse shells over a fixed 7 x 6 m collider contract, round wattle huts, stake palisade, antler gate, totems, great firepit, offering ground, wicker effigy, gallows tree, frames, racks and idols. |
| `shaders/` | Foliage, grass, terrain, arena-ground, water and flame shaders. |

To add a tree species, append a dictionary to `WorldStyle.default_trees()` (or to a scene's cloned style) with `id`, `form` (`broadleaf`, `conifer`, `birch`, `snag`), bark and leaf texture ids, height range, trunk/crown ratios, tint pools, wind and variant count. `TreeKit` and `WorldScatter` do the rest. The frontier scatters species by the weights in that list.

All world textures are original procedural work generated by `tools/world_textures.py` (Python + numpy + Pillow, deterministic). Regenerate and reimport after changing the generator:

```powershell
python tools/world_textures.py
& $Godot --headless --editor --path . --import
```

The manifest is `assets/world/world_textures.json`; provenance and the CC BY-NC-SA 4.0 terms are in `assets/world/LICENSE.txt`. World textures import lossless with mipmaps (they are alpha-scissored cards and tiled ground/bark surfaces, so mipmaps are required and block compression is intentionally disabled).

## Devil court

Five imported devil-themed mobs are kept in the tree as art and mob code, and **none of them is spawned by any scene** now that the campaign is the only game: the **Hellish goat man** (jet-black armorless goat demon with empty skull sockets and black horns/hooves), **Succubus** (half-open-wing, black-horned raider), **Devil spawn** (low skittering nest-hunter), **Hell beast** (heavy quadruped brute) and **Gargoyle** (carved stone brute with ember-slit sockets, a fanged muzzle, crown horns, half-raised bat wings and a spiked spine). The placements they were fielded on went with the sandbox world; `devil_mob.gd`, `devil_mob_visual.gd` and the profiles are kept for when the campaign wants them, and `devil_mobs_regression` still validates the assets. The old court was inspectable immediately without aggro.

**Crimson ranger clones:** four patrols hold the outer frontier trails, and from **cycle two** three to four join every delve wave. Each clone wears the player Ranger rig **heavily tinted crimson-black** with its own random paperdoll — a rolled main hand (any bow, sword, dagger or staff), an optional shield or focus, and a mixed armor set per slot — so no two read alike. They fight like the arena bots rather than the mobs, but they **close**: outside 11 m the bow is the weapon and the clone keeps walking the gap down between shots (it only plants its feet while the string is drawn), inside 11 m it puts the blade away and charges to reach, then cuts, guards and side-steps like a duelist. They lead their arrows, switch targets, react to an incoming swing with a raised guard or a quick side step, and answer a **12 m pack alarm** like any wilderness mob — a clone woken by a sighting or a cry joins the hunt, and a landed blow on a clone makes it chase the ranger that hit it for the full 90 s pursuit, past its own aggro range and leash. Their armor reduces damage like a player's, they can be parried, and they drop the main-hand weapon they rolled when they fall.

They are built from the same licensed CC0 Quaternius sources as the ranger — the male/female bases, ranger outfits, long hair and 65-bone animation library — with original devil anatomy and paint on top. No generated image, photogrammetry scan or restricted file is used. Each mob is one imported GLB with:

- a real skinned Quaternius body (the goat deliberately uses no ranger outfit) or the original Briar wolf for the beast, plus authored goat skull, horns, clean membrane wings, tails, claws, fangs, hoof boots, fur and stone spikes;
- source PBR skin, leather, hair and eye maps (2048/1024 px) tinted while retaining pores, grain and iris detail, plus authored bone, horn, membrane, stone and fur maps;
- six baked 60 Hz clips: idle, walk, run, attack, hit and death, using the ranger/wolf authored locomotion and time-warped attacks;
- extra `head`/`jaw`, wing and tail bones where the silhouette needs them.

The result is the ranger's authored PBR quality on a demon silhouette rather than a procedural blob.

`scripts/devil_mob_visual.gd` is presentation only: it samples the clips, scales cadence from actual post-collision movement, and maps the physics attack clock onto the authored impact frame. `scripts/devil_mob.gd` owns the shared state machine, per-mob profiles, collision, damage, parries/staggers, gold, blood and the five-minute corpse hold. The existing frontier loot rotation and HUD feedback are unchanged.

The full authoring workflow, budgets and gates are documented in [docs/devil-mobs.md](docs/devil-mobs.md). Rebuild all five assets with:

```powershell
python tools/build_devils.py all
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/devil_mobs_regression.gd
& $Godot --headless --path . --script res://tests/mob_aggro_regression.gd
& $Godot --headless --path . --script res://tests/mob_wander_regression.gd
& $Godot --headless --path . --script res://tests/mob_budget_regression.gd
```

Tinted source maps, authored PBR maps, preview renders and capture sheets are written to the ignored `.runtime/devil-source/<mob>/` workspace; source archives stay in `.runtime/character-source/`. Keep each shipped GLB, its adjacent JSON and its `.glb.import` together; import settings embed the textures and sample animation at 60 Hz.

### The Cinder devil (original route)

The **Cinder devil** is the sixth devil and takes the **original route** — no
download. The CC0 Quaternius archives that the five mobs above rebuild from are not
present in a clean checkout, so `tools/prepare_cinder_devil.py` authors it from
nothing. That script imports `tools/prepare_forest_mobs.py` and rebinds its
`styles`/`surfaces`/`SEED`/`FPS` globals to `tools/cinder_devil_styles.py` and
`tools/cinder_devil_surface.py`, so rig building, skinning, the per-material
atlas bake, clip baking, export and captures are literally the Unholy Forest
code path rather than a fork.

It ships as `assets/characters/devils/ironwood_cinder_devil.glb` plus its
adjacent JSON: **43,366 triangles, 38 bones, eight `Cinder_*` materials, 26
embedded images, 2.242 m to the horn tips** (the crown is 2.11 m), soles at
y 0.007 and no root drift. Seven baked 60 Hz clips — `Cinder_Idle` (2.200 loop),
`Cinder_Walk` (0.900 loop), `Cinder_Run` (0.617 loop), `Cinder_Attack` (0.800,
impact 0.380), `Cinder_Shoot` (0.550, release 0.300), `Cinder_Hit` (0.367) and
`Cinder_Death` (0.900) — on a stationary root. `scripts/cinder_devil_visual.gd`
is its presentation-only sampler and the pack AI stays in `enemy.gd` kind 2.
Like the five mobs above it is **unspawned**: no scene fields a cinder devil now,
and the campaign's only `enemy.gd` bodies are the briar wolves (kind 0).

```powershell
python tools/build_cinder_devil.py
& $Godot --headless --path . --script res://tests/devil_regression.gd
```

Ignored intermediates land in `.runtime/cinder-source/cinder_devil/`; keep the
shipped GLB, its JSON and its `.glb.import` together.

## Unholy Forest

Three creature sets were authored for the woodland: the **Hollow warden** (hooded
grave-cloth atop a hole in the world, two ember eyes and a branching antler rack
growing out of its crown), the **Ossuary stalker** (a hooded human in a fitted
sackcloth tunic and torn skirt — carved bone mask with empty black sockets,
antlers lashed to a brow band) and the
**Gallowsroot** (a big man in a long tattered coat with bark plates strapped over
it, a carved wooden mask with an ember slit, branches lashed to a brow band, bark
mitts and boots). In the campaign these three fight as **watchers** on the
warband's own skeleton (see below), fielded by the trail's camps and its archer
ambushers. The creature-shaped mob classes stay in the tree as the art's own
reference; no scene spawns them.

They are **original procedural work**, not source-based: `tools/prepare_forest_mobs.py`
authors every mesh, rig and clip in Blender, and `tools/forest_surface.py`
rasterises seven analytic PBR surfaces (bark, cloth, bone, antler, moss, void and
the emissive ember) into per-material UV atlases, so fissures, weave and bone
grain are continuous across seams and carry texel-scale detail. No third-party
model, texture or motion is used and nothing has to be downloaded to rebuild them.

Each mob ships one imported GLB with a real skinned mesh (30k / 49k / 47k
triangles), six baked 60 Hz clips (idle, walk, run, attack, hit, death) with a
stationary root and planted-foot locomotion solved with two-bone leg IK, and its
own measured JSON. `scripts/forest_mob_visual.gd` is presentation only and maps
the physics attack clock onto the authored impact frame; `scripts/forest_mob.gd`
reuses the devil state machine through its virtual profile/group/visual hooks, so
there is one AI, not two.

The same set supplies the **Makeshift** starter gear: the salvage armour the
ranger begins in — bone over cured hide, matching the stalker's kit, with a bone
antler helm, a hide vest under bone rib bars, hide bracers with bone knuckle
spikes, hide leggings with bone knee cops and hide boots with bone toe caps —
and the salvage blades the smith sells beside the forged kit (a knapped flint
cleaver and a ground-rib shiv). Makeshift is set index 4 in
`scripts/armor_data.gd`; five sets need three bits per slot, so
`ArmorData.PIECE_MASK` and `ArmorData.SHIELD_BIT` are one shared contract across
the HUD, the arena, the delve and host-authoritative snapshots.

### Watcher skins (the wood on a human's rig)

The campaign's watchers are these same three creatures, and they fight on the
warband's own skeleton: `tools/prepare_watcher_skins.py` turns each shipped
creature mesh into a whole-body skin for `ironwood_ranger.glb`'s 65 bones —
`assets/characters/watchers/ironwood_watcher_<species>.glb` plus its measured
JSON. Nothing is remodelled: the creature's vertices, UVs and material slots are
carried across, the ranger's arms are posed onto the creature's hanging arms to
become the bind, every creature bone is fitted onto its ranger counterpart, and
the skin is weighted with the creature's own weights renamed onto ranger bones.
The runtime scales the rig by the skin's measured fit scale, so a watcher stands
exactly as tall as the creature it was; the skin ships no images and borrows the
creature GLB's PBR atlases, tinted per body.

```powershell
python tools/build_watcher_skins.py all
```

`scripts/warband/watcher_visual.gd` is the presentation: it holds the rig, opens
the authored cut a windup commits to and retimes it onto the mob's telegraph so
the blade crosses the target on the damage frame, plays the guard loop and the
crouch as stances, and hands the skeleton to the shared ragdoll on death.
`scripts/warband/cage_watcher.gd` fields the three species (the intro pair and
the leaving's ambush mix them), while `RangeWorld.forest_spawns` keeps the
frontier's own creature versions untouched.

Ignored intermediates and the review captures land in
`.runtime/watcher-skins/<species>/`; keep the shipped GLB, its JSON and its
`.glb.import` together.

The workflow, budgets and gates are documented in
[docs/forest-mobs.md](docs/forest-mobs.md). Rebuild with:

```powershell
python tools/build_forest.py all
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/forest_mobs_regression.gd
```

Captures and baked atlases land in the ignored `.runtime/forest-source/<mob>/`
workspace. Keep each shipped GLB, its adjacent JSON and its `.glb.import`
together; the import settings embed the textures and sample animation at 60 Hz.

## Logs and crash reports

Every run writes its own session under `user://logs/sessions/`: a machine-readable
`.jsonl` stream, a readable `.log` mirror, a boot-environment card and a
two-second heartbeat marker. When a run ends without its clean marker, the next
launch reconstructs a report in `user://logs/crashes/` with the environment, the
last state sample, breadcrumbs, recent engine errors and their GDScript stacks,
and the tail of the archived log. The main menu shows a crash notice with buttons
to open the folder and the newest report.

On Windows the folder is `%APPDATA%\Godot\app_userdata\IRONWOOD - The Frontier\logs`;
the exact path is printed at boot. Logs are local and never uploaded. Use
`--no-log`, `--log-level=…`, `--log-dir=…`, `--log-verbose`, `--log-keep=N` or
`--no-hang-watch` to control a run, or the matching `IRONWOOD_LOG*` environment
variables. Multi-instance runs are safe: a live host or client is never reported
as crashed. Full file and report anatomy, retention and the `Log.event`
integration API: [docs/logging.md](docs/logging.md).

## Update

**Close every running game instance, including the host, before updating.** Godot keeps loaded scripts in memory; pulling changes does not update an already-running match. `Play.cmd` opens the main menu, which is the whole game.

```powershell
git pull --ff-only
.\Setup.cmd
.\Play.cmd
```

## Development and tests

`assets/characters/ironwood_ranger.glb` contains the skinned character and authored clips, including the one- and two-handed held guard loops; its adjacent JSON records source timing, guard targets/support clearance and weapon/palm transforms. `scripts/archer.gd` samples these animations on the physics clock, applies bow/terrain corrections, and emits blade sweeps from the same pose used to render the sword. A replicated rig keeps the wire as the authority for its loops (motion, stride, air, landing all advance between samples already) but runs the **flip clock locally**: a roll is one continuous turn sampled at 20 Hz, so holding the last sample froze the pose for two frames in three and read as stop-motion. `tests/replica_animation_regression.gd` drives a 20 Hz stream into a replica and fails if any frame holds the flip pose, if the flip clock rewinds, or if a new roll cannot take over from a finished one. `assets/characters/ironwood_wolf.glb` is the original textured Briar wolf: a continuous skinned quadruped with a 37-bone rig, deterministic grey coat and in-place idle, trot, bite and death clips. `scripts/wolf_visual.gd` samples them and maps the 1.5 s bite to gameplay's 0.65 s impact and 0.85 s recovery; `enemy.gd` keeps AI, collision, damage and the corpse lifetime authoritative. `scripts/cinder_devil_visual.gd` samples the imported Cinder devil GLB's seven clips; `_step_devil` in `enemy.gd` owns the orbiting pack AI, dives, the three-attacker cap and shared `DodgeStep` side steps, and the Sunken Delve's primitive depth roles keep `scripts/devil_visual.gd`. `tests/devil_regression.gd` covers that split. `combat.gd` handles authoritative swept contact, independent sword recovery and bow readiness. `dodge_roll.gd` owns explicit Shift + Space roll state. `main.gd` controls the frontier; `arena.gd` and `arena_actor.gd` implement authoritative ENet multiplayer and replicas. World and weapon geometry remain runtime-generated.

`cover_movement.gd` owns acquisition, supported capsule sweeps, contiguous-surface sliding, bounded firing-corridor search and latched lookout/retuck state. The single authoritative cover snapshot contains physical stance and world-space `lean`; animation snapshots do not duplicate it. `archer.gd` layers the authored pose before foot/weapon corrections. `Combat` checks the actual shaft before a cover release; melee still clears cover before its first swing pose. Arena aim samples carry the observed own-actor snapshot tick, and remote release waits for the current exposure epoch before applying the unchanged shaft collision check. Regressions exercise left/right tree shots, convex and compound cover, slopes/recovery, side swaps/free look, blocked shafts, malformed/stale aim stamps, cancellation, melee exits and observer replication.

Standard melee uses a dedicated **world-only occlusion ray**; camera projectile-lane checks include fighters and never share that query. This prevents normal crosshair aiming from turning a victim into its own melee blocker. `swing_reach_regression.gd` covers that aim-to-attack transition, lone point-blank, flank and far-edge targets, mirrored frontal crowds that lose exactly the swing's cap (one body for a one-hander, club or dagger, two for a greatsword, heavy branch or staff) from the loaded flank, weapon/staff reach, a 40-enemy crowd, thin walls, the ten-body cap on a skill's ring and blast, guards, cancellation and one hit per victim. Rendered checks exercise actual frontier clicks, while `network_input_regression.gd` verifies the remote greatsword's single authoritative base-damage hit.

`paperdoll_regression.gd` drives the equipment system and the combined equipment screen (sixty backpack cells, ten slots in order, every catalog item's screenshot, the live preview, the hover card's type line, weapon-only Speed and Damage, extra modifiers and quote, click-pick/click-place, drag-and-drop and the derived summary): the every-weapon starter kit, item taxonomy and legal-slot rules, right-click routing, the two-handed main/off override and its backpack/floor overflow, the off-hand override that returns a two-handed main to the backpack, dual-wield routing, ring slots, drops and floor pickups, a full backpack rejecting loot, version-6 save round-trip with floor items and version-1/2/3/4/5 migration, the two weapon sets (TAB alternating Set 1 and Set 2, both hands moving together, no weapon duplicated or lost across swaps, a weapon equipped by hand staying in its own set while the other set keeps its pair, a two-hander filling only its own slot, an emptied set staying reachable and a stashed piece blocking the swap) plus the version-4 save whose single pair matched the hands, a cinder devil's held-shortsword ground drop, rig loadouts for bow, staff, focus, shield, dual and empty hands with middle-grip staff reach matching the catalog, and the in-world paperdoll's ten slots, panel containment, live-rig equipping and right-click unequip. Script-mode tests start from the authored defaults instead of a player's real save.

Repo-local skills provide step-by-step instructions for coding and asset-authoring agents:

- [Ironwood Archer](.omp/skills/ironwood-archer/SKILL.md): gameplay, controls, shared animation/combat, multiplayer, verification and safe restarts.
- [Ironwood Assets](.omp/skills/ironwood-assets/SKILL.md): sourcing/licensing, new models, UVs, PBR textures, Blender export, Godot import and material isolation.
- [Ironwood Creatures](.omp/skills/ironwood-creatures/SKILL.md): character anatomy, skeletons, skinning, authored animation, the wolf-overhaul workflow, and independent size/coat variants.

OMP discovers these at session startup. Invoke `/skill:ironwood-assets` and `/skill:ironwood-creatures` for a character task, or ask an agent to read those files explicitly. The default grey wolf overhaul is implemented (`assets/characters/ironwood_wolf.glb`, `scripts/wolf_visual.gd`, `tools/prepare_wolf.py`); small/medium/big and black/grey/white variants remain a separate requested expansion.

### Test budget — a hard rule

**No test run may take more than a couple of minutes. Target one to two.**

- A single test that cannot finish inside `TIMEOUT` 90 s is a bug in the test or
  in what it measures, not a machine that needs more time. `tools/run_tests.py`
  kills it at the ceiling, reports `OVER BUDGET`, and fails the run.
- The whole run has a `TOTAL_BUDGET` of 180 s and fails the run if it is
  exceeded. Only a release build — and this repository has no releases yet — is
  ever an exception.
- Run suites in parallel: `python tools/run_tests.py` is the **warband** game
  suite by default (the campaign, roster, stash, camp, trail, cult and
  possession layers), one pool with an isolated `APPDATA` per process, and
  the two ENet tests serially afterwards because parallel sockets on one
  machine produce flakes that are not the code's fault.
- The base suite is a **shared-layer harness** for the rig, combat, body and
  netcode code, not a scene of the game. It does not run by default; use
  `--base` only for a change that touches that layer, and
  `--only <test,...>` to run the two or three that actually cover it.
- The band is **60-120 s per test**, 120 s being the absolute ceiling anywhere;
  600 s or 900 s is never acceptable, not even on a release.
- Verifying a change by hand follows the same rule: exercise the one path, look
  at the output, and stop. Do not re-run a whole suite to confirm what a single
  script already proved.
- If a measurement genuinely needs more, make the measured thing cheaper first —
  park what is off screen, drop the body count, skip impossible frames — and teach
  the test to assert that from the cheap instrument. `cover_movement_regression`
  and `melee_roll_regression` are the only two that drive a fixed 240 Hz clock,
  and both stay under two minutes by that rule.

Run the suites after setup:

```powershell
python tools/run_tests.py            # the campaign (the game)
python tools/run_tests.py --base     # the shared rig / combat / body harness
```

`python tools/run_tests.py` runs the full suite in parallel with isolated `APPDATA` per test, unique fixed UDP ports and a fixed simulated clock for the two long deterministic tests; it retries a timing failure once.

The shared-layer suite (`--base`) drives the rig, combat, body and netcode
primitives on their own, with no game scene: `blood_regression.gd` checks the 60-second stain lifetime and fade, surface/body/weapon coverage, projectile and melee hooks, the per-rig and per-scene budgets, and the bleed path for the cinder devil, the five imported devils and the claw-armed attackers. `corpse_regression.gd` checks that a wolf, a cinder devil, an imported devil and a delve devil all outlive the old four-second free, stop blocking collision while still catching the world, and dissolve through the shared five-minute hold. It also checks the death physics: a rigged wolf, imported devil and delve species build a Godot physical-bone ragdoll under `scripts/corpse_physics.gd`, get an attack-style force from `scripts/impact_rules.gd`, fall onto the floor without folding their torso into a pile or spinning the head, settle and bake their limp pose, while a procedural delve devil killed in the air still obeys gravity through the dead CharacterBody root. `ability_regression.gd` checks the definitions, the anointed shortbow's Barrage grant, both hand slots, trivial stamina spend, cooldown swap reset, cue timing, the 1000-stamina pool, rejection cases, the packed ability index across animation/snapshot replication, the snapshot budget, the Shift + 1 / Shift + 2 frontier bindings, both HUD slots, the backstab sound and the hosted arena cue landing real damage. `weapon_abilities_regression.gd` covers all twelve catalog weapon/shield skills, a plain piece granting nothing, every catalog weapon/shield's anointed skill agreeing with the rig's class/index resolution, their effect data and icons/sounds, the `move` feet rule (a held walk continues through a move-enabled melee skill and stops dead for a bow cast, on both a host arena fighter and the frontier ranger), the long lunge's 5.34 m lane that cuts a near and a far body once each without the closing thrust landing again, the 0.3166667 s spin and its crowded 0.06/0.16 cues, radial/arc/block/blast damage, the fireball and bone-spear projectiles, Barrage and piercing end-to-end damage, the off-axis bow that turns the body onto the live crosshair, the backstab blink behind the aimed body with its 28 damage, the spin dust ring and the MTU budget. Both anoint their rigs by hand (`build_loadout(..., [ids])`, or `rig.anointed` on the frontier controller), since the sandbox has no altar. `backstab_regression.gd` checks the crosshair target preflight, the behind-the-back landing spot, the blink and the guard-bypassing strike on a frozen arena rig.

### Rebuilding character assets

The bundled Ranger model and motions are built from **CC0** sources — Ranger/base characters and locomotion by [Quaternius](https://quaternius.com/), with the two-handed heavy attack by [Gres](https://opengameart.org/content/humanoid-soulslike-animations) — and the shipped GLB is licensed under **CC BY-NC-SA 4.0** like the rest of `assets/` ([LICENSE.md](LICENSE.md)); the sources stay CC0. The Briar wolf is original procedural work authored by `tools/prepare_wolf.py`; it is not derived from those sources. Exact source files, extraction ranges, wolf measurements and modifications are recorded in [the asset provenance](assets/characters/LICENSE.txt). No paid sources were used.

To re-author the assets, install Blender 5.1+, download and unpack the listed free sources into `.runtime/character-source`, then run:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python tools/prepare_character.py -- .runtime/character-source assets/characters/ironwood_ranger.glb
python tools/build_naked_armor.py
& $Godot --headless --editor --path . --import
```

The naked set (the old shirt and shorts the warband starts in) is rebuilt by
`tools/build_naked_armor.py` from the same CC0 Quaternius Universal Base
Characters pack: its body is that pack's `Superhero_Male_FullBody` sculpt on the
Ranger's own 65-bone skeleton, with a measured neck fit into the Ranger head, a
slimmed ribcage, and shirt and shorts cut from the body's own surface.

Keep the GLB, adjacent JSON/provenance, and `.glb.import` settings together. Import settings preserve authored clip names, use 60 Hz animation sampling, and keep textures embedded rather than duplicating extracted PNGs. The preparation workflow preserves the authored striking arm and body motion, corrects support-hand proportions and clothing clearance, and smooths the one-handed cut's timing. `tools/character_clearance.py` validates interpolated support-arm motion against the deformed outfit before export is accepted.

`tools/prepare_consumables.py` imports the shipped GLB and merges the authored **3.0-second `Bandage_Wrap`** and **0.5-second `Potion_Drink`** clips into the original document, leaving every existing node, skin, mesh and animation untouched.

The same rebuild imports `Crouch_Idle_Loop` and `Crouch_Fwd_Loop` from the existing Quaternius source and authors `Cover_Lean_Top`, `Cover_Lean_Left` and `Cover_Lean_Right` in Blender, plus the **0.5-second** `Dagger_Stab` thrust and the two held guard loops. The three 0.24-second lean clips share an idle reference, with planted feet and unchanged local arm poses for weapon layering. JSON records their asset-space directions, the stab's contact window and the crouch clip's measured stride estimate; runtime cadence follows actual movement rather than requested speed.

Optional Godot MCP tooling is pinned under `tools/`; run `npm ci --ignore-scripts` there if needed. Local MCP configuration, engine binaries, imports, caches and logs are excluded from Git. They are not required from the original development machine.

Godot is downloaded separately under its [MIT license](https://godotengine.org/license/). [Official engine release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Archery stance reference: [World Archery recurve technique](https://extranet.worldarchery.sport/documents/index.php/Media/Information_Sheets/003_Guide_to_Recurve_Technique.pdf).

## License

**Non-Commercial Source-Available Dual License** — see [LICENSE.md](LICENSE.md) for the full terms.

| Part | License | What it means |
| --- | --- | --- |
| Game code (`scripts/`, `tools/`, `tests/`, scenes, shaders) | PolyForm Noncommercial 1.0.0 | Read, run, study, modify and share for personal, hobby, research, educational or other noncommercial use, keeping the `Required Notice:` line. No commercial use. |
| Game assets (models, textures, animation, audio, UI art, levels, docs) | CC BY-NC-SA 4.0 | Play, stream, remix and mod for free with credit. No selling, and modifications must be shared under the same terms. |
| Names, logos, trailer, store page and the compiled Steam build | All rights reserved | Forks may not use the "Ironwood" / "Ghost of the Warband" names or imply endorsement, and only the copyright holder may sell the game. |

Third-party material keeps its own license (Quaternius and Gres CC0 sources, CC BY Freesound takes, SIL OFL fonts, the MIT Godot engine) — the credits that must ship with a build are in `assets/audio/LICENSE.txt`, `assets/characters/LICENSE.txt` and `assets/ui/fonts/`. Contributions are accepted under the [contributor terms](LICENSE.md#6-contributions-contributor-license-agreement), which keep the commercial build possible.
