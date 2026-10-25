# Ironwood — Town, Frontier, Arena and the Endless Sunken Delve

A Godot 4 third-person action game with one in-game world: a main menu, a walkable PvE town with three keepers, a stash and an arena portal, a seamless woodland frontier, an **open world you can host for up to four rangers** (town and frontier together), a four-combatant multiplayer arena, and an endless two-room survival delve beneath the town. The ranger carries a **15-slot backpack**, a **20-slot stash** and **ten independent equipment slots**. A textured, rigged male Ranger with authored human animation, swappable bows, swords, daggers, shields, staffs, foci and jewelry, dual wield and armor, free-aim archery, thrown swords and daggers, contact-driven melee attacks, and directional jump-rolls.

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

- **Play.cmd:** opens the main menu (**Start New Game**, **Load Saved Game**, **Host Open World**, **Join Game**).
- **Arena.cmd:** opens the standalone multiplayer lobby directly, or solo practice against bots. Its **Return to Town** button loads the PvE town.
- **Host World.cmd:** starts the town/frontier as an open world on UDP 7777 with your Windows user name, so friends can join without a delve or arena. **Host Open World** in the main menu does the same on the remembered port.
- **Host Tailscale.cmd:** starts the town/frontier in delve-host mode on UDP 7777 with your Windows user name. Walk into the **Wayfarer Inn** and jump into the Sunken Delve hatch to host on that port. Friends join with the main menu's **Join Game** form, choosing **Delve party**.

Set `GODOT_PATH` to use another existing Godot executable. Linux/macOS users can install Godot 4.7.2, import `project.godot`, and run `title.tscn`, `main.tscn`, `arena.tscn` or `delve.tscn`; the Windows setup script does not install engines for those platforms.

## Main menu and the town

Every launch opens the **main menu** with four doors:

| Menu action | Result |
| --- | --- |
| **Start New Game** | Resets the ranger to the starter kit, purse and empty stash, then starts at the south gate of Hearthstead. |
| **Load Saved Game** | Restores `user://player_state.json` and starts at the town gate. Disabled when no save exists. |
| **Host Open World** | Opens the current town and frontier as a four-ranger host on the remembered UDP port (default 7777). Friends join it with **Join Game**. |
| **Join Game** | Opens the cached name/address/port form and joins an **arena match**, **delve party** or **open world**. |

There is no out-of-game depot. **Hearthstead** is the staging town inside the open PvE world, and every service is a real object you walk up to and press **G** on:

| Town service | Where | What it does |
| --- | --- | --- |
| **Smith Brann** | ForesterHouse, behind the forge counter | Swords, daggers and shields |
| **Storekeeper Orla** | FletcherWorkshop, behind the counter | Bows, staves and trail goods |
| **Quartermaster Vey** | HearthsteadStore, behind the counter | 20 armor pieces plus foci, necklaces and rings |
| **Town Stash** | Open market awning | 20-slot long-term storage, beside your 15-slot backpack |
| **Arena Portal** | Green west of the Wayfarer Inn | Hosts a local four-seat arena on the first free UDP port |
| **Hearthstead Campfire** | Town square | Restores health and stamina |
| **Sunken Delve hatch** | Inside the Wayfarer Inn | A real hole in the floor: jump in to fall into the delve |

The starter kit is the five Ranger leather pieces plus the shortbow in the main hand, **every catalog weapon in the backpack**: three bows, three swords, the iron dagger, two staffs and three shields, and 200 credits. The tab buttons in the town shops are **STORE**, **SMITH** and **QUARTERMASTER**. Bought gear needs a free backpack slot; selling pays 60% of the purchase price.

Press **I** anywhere in the world to open the **inventory** (15 backpack slots plus the ground strip). Press **P** to open the **equipment paperdoll** (10 equipment slots: head, chest, hands, legs, feet, neck, ring 1, ring 2, main hand and off-hand). Right-click a backpack item to equip it to its natural slot, a paperdoll item to return it to the pack, a stash item to take it, or a ground item to pick it up. While a keeper or the stash is open, the same overlay adds their stock or the 20-slot stash beside the pack; **EQUIP**, **TO STASH**, **TO INVENTORY**, **SELL** and **DROP** act on the selected piece. Drag-free controls: click a slot, then use the action buttons.

**TAB swaps one bound weapon pair.** The starter bind is the equipped shortbow against the shortsword and buckler, so TAB alternates ranged and sword-and-board out of the box. The outgoing pair becomes the new bind, so the same key toggles back. Any legal main/off combination works: bow, one- or two-handed sword, dagger, staff, shield, focus or a dual-wield pair. To bind a different pair, equip it, open **P**, select the main or off-hand slot, and press **BIND SWAP**; the paperdoll shows the active bind and every swap is written to the save. Both pairs must be carried in the backpack or hands; a stashed piece blocks the swap with a message.

Dropping a piece in town, the frontier or the delve spawns a physical world pickup at the ranger's feet. It arms only after you step clear, so the dropper cannot scoop it straight back up. Arena drops fall back to the persistent ground list. Every successful change is written to `user://player_state.json` immediately; equipment is stored separately from the backpack, and the main/off hands plus five armor pieces become the starting loadout in every mode. Deleting that file restores the starter kit.

Loot is tuned to **a tenth of its old rate**: a weapon-carrying devil leaves the piece it held 10% of the time, the frontier gear rotation drops on 5% of eligible kills, and a delve cache has a 10% chance of an item. Cache gold, kill gold and waystone rewards are unchanged.

**New-game vs. load:** Start New Game overwrites the save with the starter kit; Load Saved Game re-reads the saved kit, stash, ground items and purse. The delve is an in-session endless run, so it has no resume checkpoint.

### Item taxonomy and hand rules

| Category | Legal slots | Examples |
| --- | --- | --- |
| One-handed (`1h`) | Main hand or off-hand | Shortsword, arming sword, iron dagger |
| Two-handed (`2h`) | Main hand only; locks the off-hand | Greatsword |
| Bow | Main hand only | Shortbow, recurve, longbow |
| Staff | Main hand only; locks the off-hand | Ember Staff, Bone Staff |
| Shield | Off-hand only | Buckler, kite shield, tower shield |
| Focus | Off-hand only | Ash Tome, Bone Skull |
| Armor | Its own head / chest / hands / legs / feet slot | Leather, mail, plate and Emberweave pieces |
| Jewelry | Neck, or either ring slot | Ember Charm, Bone Talisman, three rings |

- Right-click routing sends one-handers to the **main hand**, shields and foci to the **off-hand**, armor to its own slot, a necklace to the neck and a ring to the first empty ring slot (then ring 1). Alt+right-click and drags onto a slot choose the hand explicitly.
- Equipping a two-handed weapon, bow or staff **overrides both hands**: an existing main-hand and off-hand item are both returned to the backpack. If the backpack has room for only one, the second displaced item lands on the floor.
- Equipping a shield or focus while a two-handed weapon, bow or staff is in the main hand **returns that weapon to the backpack** and leaves the main hand empty.
- Two one-handers may occupy the main and off hand together. The loadout enters dual wield only when a one-handed sword is in the main hand and a dagger or another one-handed sword is in the off hand, with no shield, focus or staff involved.
- The shield pairs with **any one-handed sword or the dagger**, including the shortsword. A bow, greatsword, staff or dual wield stows it. Staffs keep the greatsword's damage and swing clock but use their own **middle grip**, shaft length and 1.6/1.5 m cleave reach; foci are held and cosmetic.
- Dragging between two paperdoll slots moves a piece into an empty legal slot or swaps two pieces. Illegal moves (a ring to the neck, a two-hander to the off-hand) are rejected. Unequipping returns a piece to the backpack; dropping it sends it to the floor.

### Looting in the frontier

Frontier enemies can drop **physical gear** on death. Walk within **1.6 m** of a drop to pick it up; the pickup enters the **backpack first** and is never auto-equipped. A **full backpack leaves the item on the ground**, and a second attempt still refuses it. Loot covers swords, daggers, shields, staffs, foci, armor, necklaces and rings. **A cinder devil carrying a weapon always drops that exact piece** — iron dagger, shortsword or recurve bow — and the corpse releases the mesh; the same rule covers the delve devils' daggers and swords. Claw devils, wolves and sentinels keep the rotating gear drop. Carry loot back to town, open **I**, and equip or sell it at a keeper; unwanted gear can also be dropped at the ranger's feet and picked back up from the world.

Dropping gear from the **inventory** (**I**) in town, the frontier or the delve likewise spawns a `LootPickup` at the ranger's feet. That drop starts **unarmed**: it only arms after the dropper steps out of the 1.6 m pickup radius, so walking back over it later banks it into the backpack normally. The delve copy keeps the same arming rule and local pickup list; a full backpack still leaves it on the ground.

### Armor: four sets, five slots

Armor is equipped **per slot**, so a cloth hood can sit over a mail hauberk, leather gloves and plate legs. Every set supplies a head, chest, hands, legs and feet piece:

| Set | Head | Chest | Hands | Legs | Feet | Full-set guard |
| --- | --- | --- | --- | --- | --- | --- |
| Ranger leather | Hood 10 | Jerkin 15 | Gloves 8 | Trousers 12 | Boots 10 | 0% |
| Sentinel mail | Coif 35 | Hauberk 55 | Mittens 25 | Chausses 40 | Sabatons 25 | 15% |
| Warden plate | Sallet 65 | Cuirass 90 | Gauntlets 45 | Cuisses 80 | Sabatons 40 | 30% |
| Emberweave cloth | Hood 25 | Robe 45 | Wraps 20 | Skirt 35 | Boots 15 | 0% |

The leather outfit is the imported Ranger mesh split by region; mail is riveted ring weave, plate is blackened articulated steel, and Emberweave is a layered mage robe with a torn hem and brass trim. Each piece renders on the same 65-bone skeleton as the ranger and follows the authored idle, draw, swing, crouch, slide, roll and cover poses. A dark hose underlayer fills the shin whenever the short leather trousers are mixed with short sabatons.

Each piece contributes its own guard: mail head 3% / chest 5% / hands 2% / legs 3% / feet 2%; plate head 7% / chest 9% / hands 4% / legs 6% / feet 4%. Mixed kits add the pieces actually worn, capped at 45%. The town Quartermaster sells all 20 pieces alongside the two foci, two necklaces and three rings; old whole-set items from earlier saves are migrated to the five slots on load.

In a match, the arena's session panel lists five slot buttons (**HEAD / CHEST / HANDS / LEGS / FEET**). Click a slot to cycle Leather → Mail → Plate → Cloth for that session. Session changes are not written back; only the equipment paperdoll's pieces persist.

## Play with friends over Tailscale

All players should use the same current checkout and be connected to a tailnet that permits them to reach the host.

### Open world (shared town and frontier)

Press **Host Open World** in the main menu, or run `Host World.cmd`, to open the PvE town and frontier on UDP 7777. The HUD's top-left line reports the session (`OPEN WORLD / UDP 7777 / 2 RANGERS`). Friends pick **Join Game → Open world**, enter the host's Tailscale IP and the port from that line, and arrive at the Hearthstead gate as their own saved ranger. Up to four rangers share the world.

The host is authoritative for every ranger and mob. Clients send movement, aim and action intents, never damage, charge or positions. Mobs chase and strike the nearest ranger; kills, arrows, thrown weapons, loot drops, waystone restorations and gold are replicated to every peer. Keepers, the stash and the backpack stay **per player**: each peer trades against its own `user://player_state.json`, and a world drop is granted to whichever ranger picks it up on their own machine. Only the host can restore a waystone or step into the arena portal; a client that falls through the inn hatch leaves the open world and starts its own delve. If the host leaves or changes scene, clients see the connection message and continue alone with live mobs. There is no host migration.

### Host

```powershell
.\Arena.cmd -- --arena-host --arena-port 7777 --arena-name Host
```

Keep the host window open. Find the address to send privately to your friends:

```powershell
tailscale ip -4
```

For a delve party, run **`Host Tailscale.cmd`** instead. It starts the frontier with `--delve-host --delve-port 7777 --delve-name "%USERNAME%"`: the host walks into the Wayfarer Inn in Hearthstead and jumps into the Sunken Delve hatch, which hosts the delve on the requested port. The host window must stay open through the descent.

### Join

Replace `HOST_TAILSCALE_IP` with the address supplied by the host:

```powershell
.\Arena.cmd -- --arena-join HOST_TAILSCALE_IP --arena-port 7777 --arena-name Buddy
```

Or enter the address and port in the arena lobby and click **Join Game**. Use `127.0.0.1` only when both instances run on the same computer. Host addresses are not stored in this repository.

There are four seats: the host and up to three joining humans. Empty seats use bots. Joining replaces a bot; disconnecting restores one. A fifth human is refused. Health, movement, attacks, thrown weapons, damage, kill/death scores, and respawns are host-authoritative. Clients send input and aim points, not damage or charge claims. The host leaving returns clients to the lobby; there is no host migration or matchmaking service.

The delve uses the same ENet transport. A delve host needs no lobby: the party falls into the chamber and waits at the altar until any survivor presses **G**. A host launched with **`Host Tailscale.cmd`** starts in town and opens the party from the inn hatch, which reports the same requested port. A client joining during a wave drops into the chamber; a client joining after a clear lands beside the cache. A fifth ranger is refused. The host owns depth, wave, seal, cache, rope, hole and wipe state; clients only send movement and action intents. If the host leaves, clients see **Connection Lost** and can return to town.

### Connection troubleshooting

- Confirm the host is actually hosting: an open-world session shows `OPEN WORLD / UDP <port> / N RANGERS` at the top left; for an arena it must be in a match rather than merely the lobby, and for a delve after the hatch/descend press rather than still standing in the frontier or on the landing.
- Run `tailscale ping HOST_TAILSCALE_IP` from the joining PC. This checks tailnet connectivity, not the game's UDP port.
- Permit UDP **7777** in any custom tailnet access policy and allow the host executable through its local firewall.
- If necessary, run `Allow Tailscale Host.ps1` in an elevated PowerShell on the **host only**. It creates a narrowly scoped rule for this engine, UDP 7777, the Tailscale adapter, and Tailscale IPv4 addresses. It is optional and never runs automatically.
- **Tailscale needs no router port forwarding.** Direct public-IP play without Tailscale requires the host to arrange forwarding and firewall access.
- After pulling updates, restart all game instances. An old running host cannot use newly changed scripts or network contracts.

See [Tailscale's firewall guidance](https://tailscale.com/docs/reference/faq/firewall-ports).

## Controls

| Control | Action |
| --- | --- |
| WASD | Move relative to the camera; slide along the surface while in cover |
| Shift | Run, or slide faster while in cover; consumes stamina |
| Space | Jump |
| Shift + Space | Immediately jump-roll in the movement direction, or forward if stationary |
| F | Post up against nearby solid cover / leave cover |
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
| TAB | Swap the equipped main/off pair with the bound quick-swap pair; the displaced pair becomes the new bind |
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
| Shift + 1 | **Charge**: lunge forward at 200% walk speed for one second; costs 10 stamina with a 2.5 s cooldown |
| G | Interact with a keeper, the stash, the campfire or a waystone; open a wave cache, descend, or ascend |
| I | Open or close the in-world inventory (15 backpack slots plus the ground strip); while open it owns the cursor and blocks movement, attacks and interactions |
| P | Open or close the equipment paperdoll (ten equipped slots); while open it owns the cursor and blocks movement, attacks and interactions |
| Escape | Close the inventory, paperdoll, keeper or stash panel first; otherwise free the cursor for equipment clicks, cancel a held attack, or toggle the captured cursor in the arena and delve |
| Click the world / right mouse | Resume captured mouse-look; right mouse also raises a sword guard |
| Mouse wheel | Select the melee variant when armed; hold Ctrl to zoom |
| C | Toggle crouch while grounded; slide when pressed during a sprint |

### Abilities and stamina

The base stamina pool is **1000**. Sprinting and sliding drain **19/s**, standing recovery is **13/s**, and guarding pauses recovery; block and step costs are unchanged. The HUD shows the pool and a **SHIFT + 1** ability slot with its icon, stamina cost and cooldown.

Abilities are data-driven by `scripts/ability_rules.gd`. A definition carries an id, slot, keybind, stamina cost, cooldown, duration, speed scale, animation clip, forward lean, sound and icon; `scripts/ability_runner.gd` owns the shared eligibility, spend, cooldown and committed-travel state. The first ability is **Charge**: grounded and out of any other action, it snaps facing and drives the ranger forward for **1 s** at **11 m/s** (200% of the 5.5 m/s walk), spending **10 stamina**. It plays the authored sprint cycle with a forward charging lean. A hit that staggers cancels it; a 5% chip does not, so the charge survives a pack of small attackers. Arena and delve validate the action on the host and replicate the active ability through the existing animation phase and snapshot; every client hears the whoosh.

**1 (without Shift) always equips the selected bow; 2 always equips the selected sword; 3 equips the single dagger; 4 equips or stows the shield; 5 toggles dual wield; TAB toggles the bound quick-swap pair. No number key changes size.** The equipment paperdoll's main and off hands determine the starting kit for a session; these keys then change only the current match, while TAB reads and writes the persistent pair in every mode. **I** is the backpack and **P** is the equipment paperdoll in all three modes. The shield is legal with **any one-handed sword or the dagger**, including the shortsword; switching to a greatsword, staff, bow or dual wield stows it. Mail reduces incoming damage by 15%, plate by 30%; mixed sets add the pieces actually worn. The town's keepers and stash are the only places to buy or store gear; the arena portal and the delve hatch are the two other ways out of town.

## Running slide

In both Frontier and Arena, **hold Shift while moving, then press C** to slide. The character must already be sprinting on the ground: standing still, walking, exhaustion, rolling and attached cover cannot trigger a running slide.

The slide starts at **10.5 m/s**, slows to crouch speed over **0.75 seconds**, and finishes crouched. Releasing WASD or Shift preserves its momentum; WASD allows limited steering without reversing direction. It uses the normal collision capsule, lowers the camera, and shows a low, planted slide pose instead of cycling running steps. Sprint stamina consumption continues during the slide, and holding Shift cannot automatically repeat it.

Press **C** again to cancel and stand when headroom permits. **Space** jumps and **Shift + Space** rolls out of the slide, also requiring standing clearance. Blocked forward travel or leaving the ground ends the slide; death, respawn and returning to camp clear it. Grounded attacks still work, and sliding grants no invulnerability. Arena derives slide eligibility and movement on the host and replicates the pose to other players.

## Quick steps

**Q** and **E** perform a grounded side step left or right relative to the camera. The step covers about **2.95 m in 0.30 s**, spends **7 stamina**, and enters a **0.55-second cooldown**. It is not a roll and grants no invulnerability. A step cancels a held bow draw, a melee swing, a throw or a guard, exits sticky cover, and ends immediately if the feet leave the ground. The character keeps the facing it had before the step: the hips and shoulders rotate into the travel while the head stays on the target, the leading foot reaches out and lifts, and the trailing foot braces. Q and E no longer draw, attack or interact; **G** interacts with the campfire, waystones and the Sunken Delve hatch inside the Wayfarer Inn.

`playtest/sidestep_lab.tscn` opens an isolated plaza for tuning this move: a facing tree, a metre grid and a measured trace of the last step. Launch it with **`playtest/Sidestep Lab.cmd`** or run the scene directly. It uses the real `Archer` and `DodgeStep` code; only the camera and the test props are local to the lab.

## Cover movement and shoulder views

Both Frontier and Arena use the same geometry-driven cover movement. Stand within **1.35 m** of a tree trunk, wall, stone barrier or solid debris and press **F**. The character approaches with normal collision, faces away from the surface, and stays attached while you look around freely. **WASD** slides along the surface at **2.2 m/s**; hold **Shift** to slide at **4.2 m/s**, spending stamina with normal exhaustion rules. Both speeds work while crouched. Contiguous rounded, faceted and compound surfaces can be followed without treating collider-shape seams as cover edges. Genuine edges, hard corners and unsupported ground still stop movement. Decorative meshes without collision and the ground are not cover.

**X selects the left or right lookout**; the HUD shows **LEFT LOOKOUT**, **RIGHT LOOKOUT** or **TOP LOOKOUT** when exposed. Hold **RMB** to look out. Low cover uses a standing top peek; tall or rounded cover uses the selected side. The controller chooses the shortest supported, capsule-safe step with a clear firing corridor: **0.45 m**, extending to **0.55 m** or **0.65 m** only when the geometry requires it. A wide object may require sliding to its flank first. Trees, rotated props and convex rocks use the same clearance checks, not object-specific exceptions.

Lookouts keep one protected anchor and one selected destination through hold and return. Free look and button release do not silently switch the physical side; a new request or explicit X swap captures a new view frame. Ground-supported capsule sweeps follow slopes instead of treating floor contact as a wall, and a small floor-recovery displacement cannot leave the return latch stuck. Authored top/left/right poses follow actual exposure. The camera retains swept-volume collision during shoulder changes. Shoulder selection does not change weapon handedness.

**C** toggles manual crouch on the ground, in or out of cover; it never changes armor. Crouching lowers the camera, skeleton and collision capsule together. Authored crouch idle and stepping animations support attached movement at both slide speeds, including curved surfaces. Side peeks preserve crouch; a top peek temporarily rises, then restores the tucked posture. Outside cover, crouched movement is **2.2 m/s** and Shift does not sprint. Leaving with **F** preserves manual crouch. Standing waits for clear headroom rather than expanding the capsule through a ceiling.

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

Zero draw gives zero damage, half draw gives half damage, and full draw gives full damage. Armor applies its normal reduction afterward. Arrow flight and world obstruction use real swept physics collision. Full-draw arrows leave at **66 m/s**, **84 m/s** and **102 m/s** for the shortbow, recurve and longbow; partial draws scale speed from 45% to 100%.

Hits in the animated **head zone** deal **double damage**; body hits keep the base value. The zone follows the head joint through crouch, cover lean and rolls. It applies to arena players and bots plus the frontier wolf, sentinel and cinder devil, and the multiplier is resolved before armor. A blade that sweeps through the head zone also doubles, even when the shape query reports the contact elsewhere; the zone is a damage volume on the normal body capsule, not a second collider.

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

Standard sword attacks are fast, descending **diagonal crowd-cleaves**: **0.60 / 0.78 / 1.02 seconds** for the shortsword, arming sword and greatsword. Larger weapons cut a wider arc with longer reach. Explicit overheads retain their **1 / 2 / 3-second** authored timing; precision stabs remain **0.5 seconds**, and throw charging is unchanged.

| Input | Swing | Path |
| --- | --- | --- |
| LMB | Diagonal cut from the camera shoulder | Cock the blade up and behind the striking shoulder, unwind the hips then the chest, and cut down across the front into a low opposite-side follow-through. Right shoulder starts right-to-left; left shoulder starts left-to-right. Subsequent cuts alternate; X resets the next side to the selected shoulder |
| Wheel up | Forward stab | The authored dagger thrust clip drives a **0.5-second** sword thrust down the crosshair line, with a short windup and fast recovery |
| Wheel down | Overhead chop | The original authored one-hand or greatsword overhead load and downstroke |

Melee has no held charge: each click starts one attack, never a held-button repeat. Every diagonal runs a **four-phase kinetic chain**: **0-30% wind-up** (both feet stay planted in the stance the attack started in — the swing pivots over them instead of stepping — weight settles onto the back foot, the pelvis coils about 27 degrees and the chest twists to roughly 50 degrees, and the weapon lifts out of the carry it is already in — out and up, never presented forward first — until the hands cock behind the striking shoulder while the free off hand reaches forward for balance), **30-45% release** (the hips snap first, the chest follows, the right shoulder drives past the left, the elbow leads and the wrist snaps through the apex), **45-65% follow-through** (the chest leans about 15 degrees forward into the strike over the planted feet — never back — the hilt crosses the body and the blade carries past the centre line to the low opposite hip while the head keeps the target in view), and **65-100% recovery** (the torso unwinds and the weapon returns to guard). The damage sector uses the same release curve as the visible arm, so contact timing and the blade agree. While moving, crouched or sliding, the pelvis stays owned by locomotion and the coil lives in Spine 01/02/03 and the right clavicle. Diagonals also sample the heavy overhead's authored leg drive, bend into the load and settle over the leading foot. Left/right cuts mirror the footwork. Wheel attacks retain their authored precision paths. A rejected local or host attack does not consume the next side; remote clients alternate dispatched attack intents without a new acknowledgement RPC.

The **dagger** (key **3**) uses the same alternating LMB diagonals, with a **0.42-second** cut, **14** base damage, **1.2 m** reach and a **150-degree** full frontal arc. Wheel up uses its **0.5-second** authored aim-directed stab; wheel down also uses that precision stab because the dagger has no authored overhead. The thrust follows the crosshair rather than auto-targeting: low aim angles toward a wolf, high aim stays high.

During the active diagonal stroke, damage sweeps a **frontal sector** in the cut's direction, rather than requiring a thin blade to touch every body. Shortsword / arming sword / greatsword reach is **1.8 / 2.1 / 2.5 m**, with full arcs of **160 / 170 / 180 degrees**. Staffs use the same damage and swing clock but a swing of their own rather than the two-handed sword's: the right hand sits just below the shaft centre and the left hand grips **0.32 m** above it, both hands drive forward as a piston, the shaft barrells through a wider arc than the hands travel, the leading end finishes ahead and low while the rear end counterweights up and behind, and the ember/bone shafts reach **1.6 / 1.5 m** (the catalog and HUD show the same values). This catches short enemies and crowds across the front while excluding targets behind or beyond reach. Every victim is checked separately against world cover, so a wall protects the target behind it without stopping the cut from hitting other visible targets. Each hand damages each victim **once per swing**, only during the active stroke, with normal **base body damage** (30 / 38 / 50 for swords, 14 for daggers)—never incidental cleave headshots. Precision stabs, authored overheads, arrows and thrown weapons retain actual-contact **2x headshots**. Guards, parries, clashes, cancellation and host-only damage remain in force. Switching weapons or rolling cancels further hits without erasing melee recovery; bow readiness stays independent.

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

The **shield** (**4**) is a physical off-hand item carried on the left arm and legal with the dagger or any one-handed sword, including the shortsword. Holding RMB raises it in front of the chest and head, overriding the dagger's weak guard or the sword's parry timing with a **full front block**. The shield is a moving collision body in both modes: an arrow that hits it — raised or merely carried — deals **zero damage** to the player and **sticks into the shield**. An arrow that reaches the body still deals damage and **sticks into the player** where it landed. Stowed shields are hidden and inert; switching to a bow, greatsword, staff or dual wield automatically stows the shield.

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

Fighters no longer hard-collide with each other. Their capsules have a **soft separation** that only pushes when centres are inside **0.46 m**, which lets two players close to stabbing distance without being shoved off their aim. World geometry, cover, blades and projectiles still collide normally.

The title menu and arena lobby remember the **last player name, host address, UDP port and join mode** in `user://net_cache.json`. Joining a game updates the cache after validation, and the next form opens with those values.

## Blood and wounds

This is an 18+ game: unmitigated damage now leaves persistent gore. **Every mob bleeds** — the Briar wolf, the stone Ruin sentinel, cinder devil packs, the five imported devils and the delve devils all take body stains, floor spatter and a death pool; the ranger does too. A real contact throws a spray of droplets from the wound, flings smaller drops onto the ground and walls around the victim, speckles the floor beneath it, soaks blood into the victim's clothes, and marks the attacker: a drawn blade takes a coating, a claw, paw or muzzle takes a soak on the limb that struck, and an arm's-length melee kill throws the victim's blood back over the killer's chest and face. Lethal blows add an arterial burst and a growing pool under the corpse that stays for as long as the body does. Blocked, parried and weak-blocked hits draw no impact spray; only weak blocks still leave the half damage's wound. A defeated body then **lies where it fell for five minutes** (`scripts/corpse_hold.gd`) holding its authored death pose, before a short dissolve frees it.

Blood is laid on the garment, not beside it. `scripts/blood_surface.gd` measures a rig once — every visible skinned-mesh vertex is binned into its dominant bone as a radial profile of the cloth around that bone — and keeps a thinned sample of the whole garment. A wound scatters several textured splashes across that measured strip, then uses the current pose to find the **outermost** layer under each splash and lifts it clear, so a belt, a sleeve cuff or a second armour layer cannot swallow the stain. Primitive-built fighters (the cinder devil, the ruin sentinel) are measured as their own triangles instead. Patch samples clamp to the measured strip, so a stain never rings the air past a cuff or the crown (the old extrapolation drew red "feathers" off hoods), and the cloth soak is a small ragged core with round satellite droplets rather than one large splat. An arrow carries only a short wet smear behind its head, never a blade-sized coating. Stains ride the nearest skeleton bone, so they travel with the limb.

Stains last **60 seconds**, then fade over the final three and are released — except for death pools. A lethal blow pools blood under the body, adds two lobes draining out past the corpse and keeps creeping outward for a few seconds; that pool holds for **five minutes**, the same clock as the corpse lying in it, and lives in its own **60-pool** budget so the sixty-second spatter recycling can never erase the pool a body is resting in. Surface spatter follows slopes and steps because each patch is conformed to the real collision surface, and weapon blood is parented to the drawn weapon so it moves through every swing. A scene owns at most **160 surface stains** and **10 wounds per fighter** (8 per weapon); the oldest stain is recycled first when a large fight exceeds that budget. Blood is presentation only — it never changes damage, hit detection or network authority, and a hit that applies no damage spawns none.

The project renders with the **GL Compatibility** backend, which has no decal support, so blood does not use `Decal` nodes: `scripts/blood_fx.gd` owns procedural splat, pool and soaked-cloth textures plus their materials, `scripts/blood_surface.gd` measures garments and builds conformed patches, and the per-scene `scripts/blood_field.gd` owns stain lifetime, weapon coatings and capped particle bursts. The first blood event on a rig costs a one-off ~30 ms measurement; later wounds are single-millisecond work. The host spawns blood where it applies damage; arena and delve clients derive wounds and the weapon-blood tally from the snapshot health delta and `weapon_blood` field, so all peers see the same result without a dedicated network message.

## Game modes

**Hearthstead / Open PvE:** the main world. New games start at the south gate; walk north into the square. The town has enterable houses, three keeper counters, the market stash chest, the arena portal, the campfire and the delve hatch. Beyond the safe ring lie forest, a ruined fortress, an upland shrine, trails and the bridge. Defeat wolves, sentinels and cinder devil packs, clear defenders and restore three waystones. Gold from foes and waystones enters the same purse immediately, and defeated enemies drop physical gear that is picked up into the backpack. Death returns you to the town gate with restored health; restored waystones stay restored for the session.

**Arena:** a 64 × 64 metre woodland free-for-all with a wide spawn ring, flank trees and stone islands around the centre cover, four combatants, simple pursuit/attack bots, score tracking and three-second respawns. Bots use the same damage and attack paths as players. Step into the **Arena Portal** in town to host a local match on the first free UDP port from 7777; the main menu's **Join Game** connects to a host. `Arena.cmd` still opens the standalone lobby, whose **Return to Town** button loads Hearthstead.

**The Sunken Delve:** a host-authoritative, endless survival run beneath the town, reached by **falling through the hatch in the Wayfarer Inn**. The floor cell is physically open; jump in and the scene hands off as you drop. The party falls onto the landing of the **sanctuary**: a 15 m stone chamber with a central dais, pillars, barricades and four dark archways, and no gates. Walk to the **altar** and press **G**; a five-pointed **pentagram** ignites on the dais, and a 3.2 s ritual of light columns, embers and point-orbs plays. Then **33 enemies — the sixteen-imp and ten-devil base plus the five starting-court devils and two crimson clones** — spawn from random points all over the room across 30 seconds, with the spawn times weighted toward the back end of the window so the room fills late. Every wave, cycle one included, adds one of each **starting-court devil** from the frontier — the hellish goat man, succubus, devil spawn, hell beast and gargoyle — scattered through the schedule in their authored rigs and claw cadence, at a court scale (`0.45 ×` frontier health, `0.65 ×` damage) so the first wave stays a first wave; health, damage and speed still grow with depth; from cycle two the base ladder also grows and a third and fourth clone join. Clear them and the cache appears after a short delay, a **rope drops from the ceiling**, and a **floor plate opens**; glowing, shimmering **beacons** label the altar, the rope (`ROPE OUT`) and the hatch (`DESCEND`) so every choice is obvious. Open the cache for gold (`40 + 30 × depth`) plus a 10% chance of one deterministic piece from a depth-scaled loot tier, climb the rope to return to town, or drop through the floor into the **Ossuary Pit**: a claustrophobic, organic charnel with a lower ceiling, rib-arc walls, stacked-skull niches, bone totems, gore pools and bone-dust floor. It starts the moment every delver lands — the summoning continues for **33 enemies — the same base plus the five court devils and two clones**. Clear it and the rope and hatch return. Dropping again returns to a **new instance** of the sanctuary (odd depths) and then the ossuary (even depths), each cycle with a fresh room palette, more enemies and heavier devils. Health, damage and chase speed scale with depth. There is no fixed wave count and no resume checkpoint — the loop is the run. `Host Tailscale.cmd` starts the town in delve-host mode, so the same hatch opens a hosted party on UDP 7777; friends choose **Join Game → Delve party**.

**Cinder devil packs:** half-height ember-skinned humanoids with horns, claws and ember eyes. **Five packs (20 devils)** hunt the frontier: a mixed five-devil pack in the glade north-west of the camp beyond the safe ring, a three-devil pack in the western woods, and four-devil packs in the northern woods, the southern meadow and the ridge approach. Each pack mixes roles: **claw**, **dagger**, **short sword** and **bow**. They do not charge in a straight line: they orbit at different radii and directions, leap, slide, and make quick half-distance side steps (**1.48 m in 0.22 s**) to reach a flank. Melee devils dive in with a telegraphed strike; bow devils kite at range and release real arrows, aiming with a small ballistic lead. Up to **three** pack members commit to an attack at once, and attacks come faster than the first pass. All devils have **24 health** and award **6 gold**; claw hits deal **8** (**10** on a landing pounce), daggers **6**, short swords **11**, and bow arrows **7**. Their compact head zone makes headshots harder but still doubles damage.

## World art

The frontier and arena are dressed by a small, data-driven world-art kit rather than per-scene primitives:

- **Textured sky.** A photoreal 4096 × 2048 equirectangular panorama (`assets/world/textures/sky_frontier.png`) supplies the sky background: a Rayleigh-like blue gradient, a real-sized sun disc and aureole at the key light's exact direction, a perspective cumulus deck with self-shadowing, thin cirrus and aerial haze. Fog, ambient light, filmic grade and saturation are tuned to it.
- **Textured terrain.** The continuous heightfield keeps its authored routes and clearings, but now renders through a world-space splat shader: grass, trail dirt and rock/scree textures blended by vertex dirt weights and slope, with low-frequency macro variation. Grass clumps, wildflowers and ferns are chunked alpha-cut cards that sway in the wind and fade out at their visibility range.
- **Textured trees.** A species library builds deterministic mesh variants: oaken trunks with real branches and leaf-card crowns, layered briar pines, slim silver birches, amber rowans and bare snags. Bark and leaf textures are separate authored PNGs with normal maps and per-instance tint, so one mesh family yields many colours and silhouettes. Sizes, species weights and shape parameters live in code, not in the mesh files.
- **Textured props.** Boulders, pebbles, village timber, plaster, roof shingles, bridge timbers and stonework share triplanar materials. The pond uses a ripple normal map and a cheap sky-tinted fresnel shader.

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
| `shaders/` | Foliage, grass, terrain, arena-ground and water shaders. |

To add a tree species, append a dictionary to `WorldStyle.default_trees()` (or to a scene's cloned style) with `id`, `form` (`broadleaf`, `conifer`, `birch`, `snag`), bark and leaf texture ids, height range, trunk/crown ratios, tint pools, wind and variant count. `TreeKit` and `WorldScatter` do the rest. The frontier scatters species by the weights in that list.

All world textures are original procedural work generated by `tools/world_textures.py` (Python + numpy + Pillow, deterministic). Regenerate and reimport after changing the generator:

```powershell
python tools/world_textures.py
& $Godot --headless --editor --path . --import
```

The manifest is `assets/world/world_textures.json`; provenance and the CC0 dedication are in `assets/world/LICENSE.txt`. World textures import lossless with mipmaps (they are alpha-scissored cards and tiled ground/bark surfaces, so mipmaps are required and block compression is intentionally disabled).

## Devil court

Five devil-themed mobs inhabit the frontier outside Hearthstead: the **Hellish goat man** (jet-black armorless goat demon with empty skull sockets and black horns/hooves), **Succubus** (half-open-wing, black-horned raider), **Devil spawn** (low skittering nest-hunter), **Hell beast** (heavy quadruped brute) and **Gargoyle** (carved stone brute with ember-slit sockets, a fanged muzzle, crown horns, half-raised bat wings and a spiked spine). Their placements are authored in `RangeWorld.devil_spawns`, deliberately separate from the legacy 36-entry `enemy_spawns` contract. Five of the sixteen spawns form a starting court inside the town’s safe ring — one of each species, about 10 m ahead of the south-gate spawn — so all five can be inspected immediately without aggro.

**Crimson ranger clones:** four patrols hold the outer frontier trails, and from **cycle two** three to four join every delve wave. Each clone wears the player Ranger rig **heavily tinted crimson-black** with its own random paperdoll — a rolled main hand (any bow, sword, dagger or staff), an optional shield or focus, and a mixed armor set per slot — so no two read alike. They fight like the arena bots rather than the mobs: **bow beyond nine metres, blade inside it**, strafing and keeping range, leading their arrows, switching targets, and reacting to an incoming swing with a raised guard or a quick side step. Their armor reduces damage like a player's, they can be parried, and they drop the main-hand weapon they rolled when they fall.

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
```

Tinted source maps, authored PBR maps, preview renders and capture sheets are written to the ignored `.runtime/devil-source/<mob>/` workspace; source archives stay in `.runtime/character-source/`. Keep each shipped GLB, its adjacent JSON and its `.glb.import` together; import settings embed the textures and sample animation at 60 Hz.

## Unholy Forest

Three mobs own the woodland outside Hearthstead: the **Hollow warden** (hooded
grave-cloth atop a hole in the world, two ember eyes and a branching antler rack
growing out of its crown), the **Ossuary stalker** (a hooded human in a fitted
sackcloth tunic and torn skirt — carved bone mask with empty black sockets,
antlers lashed to a brow band) and the
**Gallowsroot** (a big man in a long tattered coat with bark plates strapped over
it, a carved wooden mask with an ember slit, branches lashed to a brow band, bark
mitts and boots). Their placements live in
`RangeWorld.forest_spawns`, a third table beside the legacy 36 `enemy_spawns` and
the 16 `devil_spawns`. Three of the nineteen spawns sit inside the town's safe
ring about 14 m ahead of the south gate, so all three are inspectable at once and
stay idle until the ranger leaves the ring.

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

## Update

**Close every running game instance, including the host, before updating.** Godot keeps loaded scripts in memory; pulling changes does not update an already-running match. Current windows show **0.4.0** in the HUD, and `Play.cmd` opens the main menu.

```powershell
git pull --ff-only
.\Setup.cmd
.\Play.cmd
```

## Development and tests

`assets/characters/ironwood_ranger.glb` contains the skinned character and authored clips, including the one- and two-handed held guard loops; its adjacent JSON records source timing, guard targets/support clearance and weapon/palm transforms. `scripts/archer.gd` samples these animations on the physics clock, applies bow/terrain corrections, and emits blade sweeps from the same pose used to render the sword. `assets/characters/ironwood_wolf.glb` is the original textured Briar wolf: a continuous skinned quadruped with a 37-bone rig, deterministic grey coat and in-place idle, trot, bite and death clips. `scripts/wolf_visual.gd` samples them and maps the 1.5 s bite to gameplay's 0.65 s impact and 0.85 s recovery; `enemy.gd` keeps AI, collision, damage and the corpse lifetime authoritative. `scripts/devil_visual.gd` builds the half-size cinder devil from primitives and layers its run, leap, slide, side-step, claw and death poses; `_step_devil` in `enemy.gd` owns the orbiting pack AI, dives, two-attacker limit and shared `DodgeStep` side steps. `tests/devil_regression.gd` covers that split. `combat.gd` handles authoritative swept contact, independent sword recovery and bow readiness. `dodge_roll.gd` owns explicit Shift + Space roll state. `main.gd` controls the frontier; `arena.gd` and `arena_actor.gd` implement authoritative ENet multiplayer and replicas. World and weapon geometry remain runtime-generated.

`cover_movement.gd` owns acquisition, supported capsule sweeps, contiguous-surface sliding, bounded firing-corridor search and latched lookout/retuck state. The single authoritative cover snapshot contains physical stance and world-space `lean`; animation snapshots do not duplicate it. `archer.gd` layers the authored pose before foot/weapon corrections. `Combat` checks the actual shaft before a cover release; melee still clears cover before its first swing pose. Arena aim samples carry the observed own-actor snapshot tick, and remote release waits for the current exposure epoch before applying the unchanged shaft collision check. Regressions exercise left/right tree shots, convex and compound cover, slopes/recovery, side swaps/free look, blocked shafts, malformed/stale aim stamps, cancellation, melee exits and observer replication.

Standard melee uses a dedicated **world-only occlusion ray**; camera projectile-lane checks include fighters and never share that query. This prevents normal crosshair aiming from turning a victim into its own melee blocker. `swing_reach_regression.gd` covers that aim-to-attack transition, mirrored frontal crowds, point-blank and short targets, weapon/staff reach, a 40-enemy cleave, thin walls, guards, cancellation and one hit per victim. Rendered checks exercise actual frontier clicks, while `network_input_regression.gd` verifies the remote greatsword's single authoritative base-damage hit.

`paperdoll_regression.gd` drives the equipment system: the ten slots and every-weapon starter kit, item taxonomy and legal-slot rules, right-click routing, the two-handed main/off override and its backpack/floor overflow, the off-hand override that returns a two-handed main to the backpack, dual-wield routing, ring slots, drops and floor pickups, a full backpack rejecting loot, version-4 save round-trip with floor items and version-1/2/3 migration, the TAB quick-swap pair and its BIND SWAP path, a cinder devil's held-shortsword ground drop, rig loadouts for bow, staff, focus, shield, dual and empty hands with middle-grip staff reach matching the catalog, and the in-world paperdoll's ten slots, panel containment, live-rig equipping and right-click unequip. Script-mode tests start from the authored defaults instead of a player's real save.

Repo-local skills provide step-by-step instructions for coding and asset-authoring agents:

- [Ironwood Archer](.omp/skills/ironwood-archer/SKILL.md): gameplay, controls, shared animation/combat, multiplayer, verification and safe restarts.
- [Ironwood Assets](.omp/skills/ironwood-assets/SKILL.md): sourcing/licensing, new models, UVs, PBR textures, Blender export, Godot import and material isolation.
- [Ironwood Creatures](.omp/skills/ironwood-creatures/SKILL.md): character anatomy, skeletons, skinning, authored animation, the wolf-overhaul workflow, and independent size/coat variants.

OMP discovers these at session startup. Invoke `/skill:ironwood-assets` and `/skill:ironwood-creatures` for a character task, or ask an agent to read those files explicitly. The default grey wolf overhaul is implemented (`assets/characters/ironwood_wolf.glb`, `scripts/wolf_visual.gd`, `tools/prepare_wolf.py`); small/medium/big and black/grey/white variants remain a separate requested expansion.

Run the behavior regressions after setup:

```powershell
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --editor --path . --import
& $Godot --headless --path . --script res://tests/rig_regression.gd
& $Godot --headless --path . --script res://tests/draw_combat_regression.gd
& $Godot --headless --path . --script res://tests/projectile_regression.gd
& $Godot --headless --path . --script res://tests/gameplay_regression.gd
& $Godot --headless --path . --script res://tests/melee_roll_regression.gd
& $Godot --headless --path . --script res://tests/action_pose_regression.gd
& $Godot --headless --path . --script res://tests/arm_clearance_regression.gd
& $Godot --headless --path . --script res://tests/weapon_input_regression.gd
& $Godot --headless --path . --script res://tests/network_input_regression.gd
& $Godot --headless --path . --script res://tests/cover_movement_regression.gd
& $Godot --headless --path . --script res://tests/wolf_regression.gd
& $Godot --headless --path . --script res://tests/devil_regression.gd
& $Godot --headless --path . --script res://tests/devil_mobs_regression.gd
& $Godot --headless --path . --script res://tests/swing_reach_regression.gd
& $Godot --headless --path . --script res://tests/running_slide_regression.gd
& $Godot --headless --path . --script res://tests/block_clash_regression.gd
& $Godot --headless --path . --script res://tests/hitbox_regression.gd
& $Godot --headless --path . --script res://tests/title_menu_regression.gd
& $Godot --headless --path . --script res://tests/town_services_regression.gd
& $Godot --headless --path . --script res://tests/paperdoll_regression.gd
& $Godot --headless --path . --script res://tests/world_ui_regression.gd
& $Godot --headless --path . --script res://tests/throw_regression.gd
& $Godot --headless --path . --script res://tests/world_art_regression.gd
& $Godot --headless --path . --script res://tests/delve_regression.gd
& $Godot --headless --path . --script res://tests/delve_entry_regression.gd
& $Godot --headless --path . --script res://tests/delve_network_regression.gd
& $Godot --headless --path . --script res://tests/world_network_regression.gd
& $Godot --headless --path . --script res://tests/ranger_clone_regression.gd
& $Godot --headless --path . --script res://tests/consumable_regression.gd
& $Godot --headless --path . --script res://tests/blood_regression.gd
& $Godot --headless --path . --script res://tests/corpse_regression.gd
& $Godot --headless --path . --script res://tests/ability_regression.gd
```

`python tools/run_tests.py` runs the full suite in parallel with isolated `APPDATA` per test, unique fixed UDP ports and a fixed simulated clock for the two long deterministic tests; it retries a timing failure once.

`blood_regression.gd` checks the 60-second stain lifetime and fade, surface/body/weapon coverage, projectile and melee hooks, the per-rig and per-scene budgets, and the bleed path for the five imported devils, the stone sentinel and the claw-armed attackers. `corpse_regression.gd` checks that a wolf, a sentinel, a cinder devil, an imported devil and a delve devil all outlive the old four-second free, keep their authored death pose, stop colliding, and dissolve through the shared five-minute hold. `ability_regression.gd` checks the charge definition and 1000-stamina pool, committed travel and animation/replication, chip versus half-health cancellation, rejection cases, the snapshot budget, the Shift + 1 frontier binding and the arena host action.

`delve_regression.gd` checks the endless loop: the fall-in start, the sanctuary altar phase, the pentagram ritual, the cycle-one **33-enemy** wave (sixteen imps, ten devils, all five court devils and two clones) from random spawn points, the delve's bandage/potion keys and heal, the cycle-two growth with three crimson clones (imported rigs, court-scaled health, complete head and strike anchors), the clear delay, cache spawn, rope and floor-hole beacons, chest rewards, the Ossuary Pit's 33 enemies, depth-three sanctuary recycling with a new palette, and the rope return to town. `ranger_clone_regression.gd` covers the frontier's four clones: red-black tint, random main hands and armor, the arena-bot range discipline, the guard reaction, a real bow release, the one-time reward and corpse, and both snapshot shapes. `delve_entry_regression.gd` drives the town gate, the physical inn hatch fall, the arena portal host, and the rope return to `main.tscn`. `delve_network_regression.gd` runs two real ENet processes: a client joins the altar, both see the ritual, room, wave and cache, the client builds the species and clone replicas, and both observe the descent into the ossuary. `world_network_regression.gd` runs two real ENet processes for the open world: the host opens the town/frontier, the client joins seat one, both mobs and rangers replicate, the client's weapon/jump/melee intents drive its host-authoritative ranger, damage and health reach both peers, the host's mob arrow and loot drop appear on the client, every client mob is a host-driven replica, and the seat is freed when the client leaves.

`world_ui_regression.gd` drives the in-world **I/P kit** in the real delve and arena scenes. It checks that **I** opens the backpack and frees the cursor, that **P** opens the paperdoll, that an equip updates `PlayerState` and the live rig (`Archer.apply_loadout`), that `Escape` closes the kit and recaptures the mouse, and that arena drops fall back to the persistent ground list. `town_services_regression.gd` walks the PvE town: the three keeper counters, the stash chest, the arena portal, the open hatch cell, the town-gate spawn, I/P panel switching, vendor buying, stash transfers and unarmed world drops. `title_menu_regression.gd` covers Start New Game, Load Saved Game, the disabled-load state and the cached Join form.

### Rebuilding character assets

The bundled Ranger model and motions are **CC0**: Ranger/base characters and locomotion by [Quaternius](https://quaternius.com/), with the two-handed heavy attack by [Gres](https://opengameart.org/content/humanoid-soulslike-animations). The Briar wolf is original procedural work authored by `tools/prepare_wolf.py`; it is not derived from those sources. Exact source files, extraction ranges, wolf measurements and modifications are recorded in [the asset provenance](assets/characters/LICENSE.txt). No paid pack or game account is needed.

To re-author the assets, install Blender 5.1+, download and unpack the listed free sources into `.runtime/character-source`, then run:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python tools/prepare_character.py -- .runtime/character-source assets/characters/ironwood_ranger.glb
& $Godot --headless --editor --path . --import
```

Keep the GLB, adjacent JSON/provenance, and `.glb.import` settings together. Import settings preserve authored clip names, use 60 Hz animation sampling, and keep textures embedded rather than duplicating extracted PNGs. The preparation workflow preserves the authored striking arm and body motion, corrects support-hand proportions and clothing clearance, and smooths the one-handed cut's timing. `tools/character_clearance.py` validates interpolated support-arm motion against the deformed outfit before export is accepted.

`tools/prepare_consumables.py` imports the shipped GLB and merges the authored **3.0-second `Bandage_Wrap`** and **0.5-second `Potion_Drink`** clips into the original document, leaving every existing node, skin, mesh and animation untouched.

The same rebuild imports `Crouch_Idle_Loop` and `Crouch_Fwd_Loop` from the existing Quaternius source and authors `Cover_Lean_Top`, `Cover_Lean_Left` and `Cover_Lean_Right` in Blender, plus the **0.5-second** `Dagger_Stab` thrust and the two held guard loops. The three 0.24-second lean clips share an idle reference, with planted feet and unchanged local arm poses for weapon layering. JSON records their asset-space directions, the stab's contact window and the crouch clip's measured stride estimate; runtime cadence follows actual movement rather than requested speed.

Optional Godot MCP tooling is pinned under `tools/`; run `npm ci --ignore-scripts` there if needed. Local MCP configuration, engine binaries, imports, caches and logs are excluded from Git. They are not required from the original development machine.

Godot is downloaded separately under its [MIT license](https://godotengine.org/license/). [Official engine release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Archery stance reference: [World Archery recurve technique](https://extranet.worldarchery.sport/documents/index.php/Media/Information_Sheets/003_Guide_to_Recurve_Technique.pdf).
