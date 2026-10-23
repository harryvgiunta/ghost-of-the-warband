# Ironwood — The Hollow, Frontier, Arena and the Sunken Delve

A Godot 4 third-person action game staged from the Hollow, an out-of-raid depot with a 10-slot inventory, a 20-slot stash and three vendors. From there, deploy to a seamless woodland frontier, a four-combatant multiplayer arena, or a sealed one-room survival delve beneath Hearthstead. A textured, rigged male Ranger with authored human animation, swappable bows, swords, a dagger, a shield, dual wield and armor, free-aim archery, thrown swords and daggers, contact-driven melee attacks, and directional jump-rolls.

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

- **Play.cmd:** the Hollow, the default staging screen, with inventory, stash, vendors and every game mode.
- **Arena.cmd:** the multiplayer lobby directly, or solo practice against bots. The arena lobby's **Return to the Hollow** button reconnects the hub flow.
- **Host Tailscale.cmd:** immediately host an arena on UDP 7777.

Set `GODOT_PATH` to use another existing Godot executable. Linux/macOS users can install Godot 4.7.2, import `project.godot`, and run `menu.tscn`, `arena.tscn` or `main.tscn`; the Windows setup script does not install engines for those platforms.

## The Hollow: the default screen

Every normal launch opens **the Hollow**, the out-of-raid staging depot. The ranger stands in the middle of the screen in the gear you last equipped, with three vendor stalls around the clearing. The HUD carries the inventory, the stash, the selected vendor and every way to deploy, including the Sunken Delve.

| Area | Capacity and behaviour |
| --- | --- |
| Inventory | **10 slots**. Bought gear and the kit you own live here. Equipping a bow, sword or any armor piece applies it on entry to every mode. |
| Stash | **20 slots**. Long-term storage that is never equipped automatically. |
| Purse | Credits earned in the frontier; the starting purse is **200**. |
| Equipped kit | One bow, one sword and **five armor pieces** (head, chest, hands, legs, feet), kept in the inventory and marked with `*`. The only copy of an equipped piece cannot be sold or stashed; equip a replacement first. |

| Vendor | Stock and prices |
| --- | --- |
| Fletcher Orla | Shortbow 120 / Recurve 220 / Longbow 360 |
| Smith Brann | Shortsword 110 / Arming sword 195 / Greatsword 340 |
| Quartermaster Vey | **20 individual armor pieces**: Ranger leather 55 total / Sentinel mail 180 / Warden plate 320 / Emberweave cloth 140 |

Click a slot to inspect its stats and reach **EQUIP**, **TO STASH** / **TO INVENTORY**, or **SELL** at 60% of the purchase price. Click vendor stock, then **BUY**; purchases need a free inventory slot and enough credits. A full inventory or stash rejects the action with a status message instead of dropping gear.

Every change is written to `user://player_state.json` immediately, so gear and credits survive quitting and scene changes. Delete that file to restore the starting kit: shortbow, shortsword, the five Ranger leather pieces, an otherwise empty stash and 200 credits.

| Deploy action | Result |
| --- | --- |
| **Arena Skirmish** | Starts a real four-seat arena on this PC; bots fill empty seats. It claims the first free UDP port from 7777, so an existing host never blocks practice. |
| **Host a Game** | Opens a name and UDP-port form, then hosts the arena. Share the host address privately. |
| **Join a Game** | Opens a name, address and UDP-port form, then joins that host. |
| **Enter the Frontier** | Opens the open PvE world for the waystone hunt. |
| **Descend the Delve** | Hosts a local delve on the first free UDP port and drops the party into the sealed chamber. The button changes to **Resume the Delve** while a cleared-wave checkpoint exists. |
| **Host a Delve** | Opens a name and UDP-port form, then hosts a delve party on that port. Share the address privately. |
| **Join a Delve** | Opens a name, address and UDP-port form, then joins that delve. The joining ranger drops into the host's current phase. |

The equipped bow, sword and five armor pieces become the starting loadout in both the frontier and the arena. Frontier gold is the Hollow's credits: kills and restored waystones grow the same purse. Equipment buttons inside a match still change that session's loadout, but only the Hollow's equipped kit is saved. Drag the 3D view to orbit, use the wheel to zoom, and press `Escape` to close the host or join form.


### Armor: four sets, five slots

Armor is equipped **per slot**, so a cloth hood can sit over a mail hauberk, leather gloves and plate legs. Every set supplies a head, chest, hands, legs and feet piece:

| Set | Head | Chest | Hands | Legs | Feet | Full-set guard |
| --- | --- | --- | --- | --- | --- | --- |
| Ranger leather | Hood 10 | Jerkin 15 | Gloves 8 | Trousers 12 | Boots 10 | 0% |
| Sentinel mail | Coif 35 | Hauberk 55 | Mittens 25 | Chausses 40 | Sabatons 25 | 15% |
| Warden plate | Sallet 65 | Cuirass 90 | Gauntlets 45 | Cuisses 80 | Sabatons 40 | 30% |
| Emberweave cloth | Hood 25 | Robe 45 | Wraps 20 | Skirt 35 | Boots 15 | 0% |

The leather outfit is the imported Ranger mesh split by region; mail is riveted ring weave, plate is blackened articulated steel, and Emberweave is a layered mage robe with a torn hem and brass trim. Each piece renders on the same 65-bone skeleton as the ranger and follows the authored idle, draw, swing, crouch, slide, roll and cover poses. A dark hose underlayer fills the shin whenever the short leather trousers are mixed with short sabatons.

Each piece contributes its own guard: mail head 3% / chest 5% / hands 2% / legs 3% / feet 2%; plate head 7% / chest 9% / hands 4% / legs 6% / feet 4%. Mixed kits add the pieces actually worn, capped at 45%. The Hollow's Quartermaster sells all 20 pieces; old whole-set items from earlier saves remain valid as full-set bundles and are migrated to the five slots on load.

In a match, the equipment panel lists five slot buttons (**HEAD / CHEST / HANDS / LEGS / FEET**). Click a slot to cycle Leather → Mail → Plate → Cloth for that session. Session changes are not written back; only the Hollow's equipped pieces persist.

## Play with friends over Tailscale

All players should use the same current checkout and be connected to a tailnet that permits them to reach the host.

### Host

```powershell
.\Arena.cmd -- --arena-host --arena-port 7777 --arena-name Host
```

Keep the host window open. Find the address to send privately to your friends:

```powershell
tailscale ip -4
```

### Join

Replace `HOST_TAILSCALE_IP` with the address supplied by the host:

```powershell
.\Arena.cmd -- --arena-join HOST_TAILSCALE_IP --arena-port 7777 --arena-name Buddy
```

Or enter the address and port in the arena lobby and click **Join Game**. Use `127.0.0.1` only when both instances run on the same computer. Host addresses are not stored in this repository.

There are four seats: the host and up to three joining humans. Empty seats use bots. Joining replaces a bot; disconnecting restores one. A fifth human is refused. Health, movement, attacks, thrown weapons, damage, kill/death scores, and respawns are host-authoritative. Clients send input and aim points, not damage or charge claims. The host leaving returns clients to the lobby; there is no host migration or matchmaking service.

The delve uses the same ENet transport and the same **Host a Delve** / **Join a Delve** forms, but a delve host needs no lobby: the party stages on the landing until the host presses **G** to descend. A client joining during a wave drops straight into the sealed chamber; a client joining after a clear lands beside the cache. A fifth ranger is refused. The host owns wave, seal, cache and wipe state; clients only send movement and action intents. If the host leaves, clients see **Connection Lost** and can return to the Hollow.

### Connection troubleshooting

- Confirm the host is in a match, not merely at the lobby.
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
| 4 | Equip or stow the shield (dagger or medium arming sword only) |
| 5 | Dual-wield the selected one-handed sword in the right hand and the dagger in the left; press again to return to the sword |
| Mouse movement | Mouse-look with a fixed center crosshair; no aim assistance |
| Hold left mouse with bow | Raise and draw while aiming; automatically expose from cover |
| Release left mouse with bow | Launch one arrow; cover shots wait for exposure without gaining charge |
| Click left mouse with sword or dagger | Break sticky cover and immediately attack: a horizontal swing from the current camera shoulder, or a dagger stab. Repeated horizontal swings rebound to the other side |
| Scroll wheel up with sword or dagger | Forward stab along the crosshair |
| Scroll wheel down with sword or dagger | Overhead chop |
| Hold T with a sword or dagger | Charge a throw while aiming. Damage scales with charge, and a bow-style recovery follows the release |
| Release T with a sword or dagger | Hurl the equipped weapon as a projectile. The endless supply keeps the same weapon equipped |
| Click left mouse while dual wielding | Left-hand dagger stab |
| Click right mouse while dual wielding | Right-hand sword overhead toward the crosshair; never a guard |
| Q / E | Side-step left / right with the shoulders turning into the move; grounded, short cooldown, 7 stamina |
| G | Interact with the campfire or a waystone, begin or resume a delve descent, open a wave cache, descend, or ascend to the surface |
| Escape / I | Free the cursor for equipment clicks; cancel a held attack |
| Click the world / right mouse | Resume captured mouse-look; right mouse also raises a sword guard |
| Mouse wheel | Select the melee variant when armed; hold Ctrl to zoom. Right-drag orbits only in frontier inspection view |
| C | Toggle crouch while grounded; slide when pressed during a sprint |
| Left-drag in the Hollow | Orbit the staging camera around the ranger |
| Mouse wheel in the Hollow | Zoom the staging camera |
| Escape in the Hollow | Close the host or join form |

**1 always equips the selected bow; 2 always equips the selected sword; 3 always equips the single dagger; 4 equips or stows the shield; 5 toggles dual wield. No number key changes size.** In a delve, **R** in the surface staging clears a saved checkpoint and begins a fresh run; movement, combat, cover, rolls and equipment use the same controls as the frontier. The shield is legal only with the dagger or the medium arming sword; switching to a bow, shortsword or greatsword stows it. Dual wield requires a one-handed sword (small shortsword or medium arming sword); selecting the greatsword leaves the mode, and the shield is stowed. Click the small / medium / large buttons to select each weapon's size independently. Escape frees the cursor; clicking the world resumes aiming. In the frontier, **I** opens equipment, **V** inspects the character, **M** opens the map, **G** interacts, **R** returns to camp, **N** toggles sound, and the **Return to the Hollow** button ends the run. The arena displays equipment controls and a **Leave Match** button; the arena lobby returns to the Hollow.

## Running slide

In both Frontier and Arena, **hold Shift while moving, then press C** to slide. The character must already be sprinting on the ground: standing still, walking, exhaustion, rolling and attached cover cannot trigger a running slide.

The slide starts at **10.5 m/s**, slows to crouch speed over **0.75 seconds**, and finishes crouched. Releasing WASD or Shift preserves its momentum; WASD allows limited steering without reversing direction. It uses the normal collision capsule, lowers the camera, and shows a low, planted slide pose instead of cycling running steps. Sprint stamina consumption continues during the slide, and holding Shift cannot automatically repeat it.

Press **C** again to cancel and stand when headroom permits. **Space** jumps and **Shift + Space** rolls out of the slide, also requiring standing clearance. Blocked forward travel or leaving the ground ends the slide; death, respawn and returning to camp clear it. Grounded attacks still work, and sliding grants no invulnerability. Arena derives slide eligibility and movement on the host and replicates the pose to other players.

## Quick steps

**Q** and **E** perform a grounded side step left or right relative to the camera. The step covers about **2.95 m in 0.30 s**, spends **7 stamina**, and enters a **0.55-second cooldown**. It is not a roll and grants no invulnerability. A step cancels a held bow draw, a melee swing, a throw or a guard, exits sticky cover, and ends immediately if the feet leave the ground. The character keeps the facing it had before the step: the hips and shoulders rotate into the travel while the head stays on the target, the leading foot reaches out and lifts, and the trailing foot braces. Q and E no longer draw, attack or interact; **G** interacts with the campfire and waystones.

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

The hand weapon leaves the hand for the release frame and the **endless supply** restores the same equipped weapon as recovery begins. This is temporary: inventory consumption arrives in a separate work stream. **T never replaces melee**; left mouse and the wheel still perform the normal sword or dagger attacks. Throws automatically expose from cover like a bow, and a wall between the hand and the aim line cancels the throw rather than passing the weapon through cover. In the arena the host owns the thrown projectile, its damage and its replication; clients only send the charge/release intent and aim.

## Swords and jump-rolls

Small / medium / large swords keep their **1 / 2 / 3-second** authored windup, strike and recovery. Three swing paths share that timing language:

| Input | Swing | Path |
| --- | --- | --- |
| LMB | Horizontal cut from the camera shoulder | A hip-led lateral arc at chest height. Right shoulder starts right-to-left; left shoulder starts left-to-right. The next LMB rebound cuts from the opposite side unless X selects a new shoulder first |
| Wheel up | Forward stab | The authored dagger thrust clip drives a **0.5-second** sword thrust down the crosshair line, with a short windup and fast recovery |
| Wheel down | Overhead chop | The original authored one-hand or greatsword overhead load and downstroke |

Melee has no held charge; only a head-zone contact doubles damage. A click starts one swing; holding the button does not repeat it. Sword swing durations remain fixed while moving. The LMB horizontal variant layers the lateral hand path over the authored weight transfer and keeps the greatsword's support hand on the hilt; the wheel variants reuse authored motion rather than a procedural body replacement.

The **dagger** (key **3**) is a single close-range weapon: a **0.5-second** authored forward stab with a short windup, a brief blade-contact window and fast recovery. It deals **14** base damage, less than the 30-damage shortsword, and has a thinner, shorter contact volume. The same head-zone multiplier applies. The clip is authored on the Ranger skeleton in Blender; the runtime sweeps the actual dagger blade along the animated hand path rather than using a cone. The right arm and dagger socket aim along the crosshair: the authored chamber and extension run down that line, so the blade goes where you point — low at a wolf's head or level at a humanoid — instead of always thrusting at chest height. The hip and foot stance stays authored; there is no auto-lunge or auto-target.

Damage comes from the **moving blade**, not a fixed percentage of the swing or an attacker-centered cone. During the authored downstroke, continuous blade-volume sweeps detect real contact and block at world cover. Horizontal cuts lower toward the crosshair and carry a small forward/thickness forgiveness envelope, so a short devil at the shortsword's advertised reach is hit; dagger thrusts get a wider short-range envelope of their own. Overheads and sword stabs keep their existing volumes. Each swing damages a target at most once; windup and recovery cannot damage it. Switching weapons or rolling cancels further contacts without resetting sword recovery. Sword recovery continues independently while a bow is equipped; it neither blocks bow charging nor gets cleared by switching back.

## Dual wield

Press **5** with a one-handed sword selected to hold that sword in the right hand and the dagger in the left. The mode requires the small shortsword or medium arming sword; the greatsword is two-handed, so selecting it leaves dual wield. The shield is stowed and cannot be equipped while dual wielding.

Left click performs the left-hand dagger stab; right click performs the right-hand sword overhead. Both face the crosshair; the dagger thrust follows the aim point while the sword uses its normal authored overhead. Scroll up stabs and scroll down cuts overhead with the right-hand sword. Each uses its own weapon's timing, blade geometry and recovery clock and stays socketed in the correct hand. The left stab uses the **0.5-second** dagger profile (**14** damage, **1.2 m** reach); the right chop uses the selected one-handed sword's normal overhead timing and damage. **T** still throws the right-hand sword.

**Recovery is per hand.** You can start the right sword while the left dagger is still winding up or recovering, and you can start the left dagger during a sword swing. Each hand has its own damage window, so the second attack never waits for the first to finish, and the freed hand can attack again as soon as its own clip completes. While the right sword is active it drives the body animation; the left thrust is layered on the same skeleton. The HUD shows **LEFT** and **RIGHT** percentages (or **READY**). A standard block knocks aside only the hand that contacted it; a parry staggers and cancels both.

**Dual wield has no guard.** RMB never raises a block, and a shield cannot be raised. Instead, an attack that has reached its authored blade-contact window parries a front melee hit: no damage and the attacker is staggered for **0.8 s**. Windup, recovery, a hit from behind, or any non-dual attack does not parry. The attack parry does not stop the dual wielder's own swing, and there is no stamina cost.

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

The **shield** (**4**) is a physical off-hand item carried on the left arm and legal only with the dagger or the medium arming sword. Holding RMB raises it in front of the chest and head, overriding the dagger's weak guard or the sword's parry timing with a **full front block**. The shield is a moving collision body in both modes: an arrow that hits it — raised or merely carried — deals **zero damage** to the player and **sticks into the shield**. An arrow that reaches the body still deals damage and **sticks into the player** where it landed. Stowed shields are hidden and inert; switching to a bow, shortsword or greatsword automatically stows the shield.

Releasing RMB drops the guard; pressing an attack while guarding also drops it. Dual wielders cannot guard at all: RMB attacks with the right-hand sword instead, and defense comes from the timed attack parry above. Guarding pauses stamina recovery, so repeated blocks cannot be turtled for free, and a guard with insufficient stamina still spends what remains. The held pose is a dedicated character-only animation: `Sword_Block_Loop_OneHand` for the dagger, short and arming swords, and the two-handed `Sword_Block_Loop` for the greatsword. Both are **120-sample / 1.983-second** breathing loops with planted feet; the greatsword's support hand stays on the actual hilt. These clips animate the Ranger rig only; the held weapon remains the normal socketed runtime model, and the lower-body crouch/slide layer does not overwrite the guard arms.

If two **sword** users are in their active downstroke at the same time and facing each other, their blades **clash** instead of trading damage: sparks and a loud clang, zero damage in both directions, a small bounce apart, and both swings reset so either fighter can immediately act again. A clash never uses an exact sword-to-sword contact test; simultaneous active hit-frames plus mutual facing are sufficient. A dagger never clashes; it can only weak-block and must rely on its speed and short recovery.

The character uses a 65-bone skinned humanoid and authored animation clips. The greatsword has a genuine two-handed overhead load, accelerating downward cut, whole-body weight transfer, closed hilt grip, follow-through and recovery. Short/medium swords use a separate authored one-handed overhead. Windup and recovery absorb the different weapon durations instead of stretching the cutting stroke into slow motion. Source motions are retargeted and grip/timing corrections baked in Blender; sword elbows are not posed by runtime IK. The textured character and environment remain stylized, not photorealistic rendering.

**Shift + Space** starts a tucked forward tumble and directional burst immediately, either from the ground or during a jump. Space alone only jumps; double-tapping it never rolls. Knees and elbows fold, the chin tucks, the weapon stays clear of the torso, and landing compresses the legs before returning to the normal stance. Running or strafing direction takes priority over facing. Only one roll is allowed before landing; it does not grant invulnerability or ignore world collisions.

[In-engine authored sword, bow, movement and roll preview](media/motion-preview.mp4)

Authored walk, jog and sprint clips follow actual movement speed with a continuous gait phase. The sprint includes knee/heel recovery, flight, body lean and alternating arm drive. Bow aiming and terrain contact use skeletal corrections; the greatsword keeps a coupled two-hand carry. Collisions that stop movement also stop the running gait.

## Multiplayer feel

Remote fighters use **snapshot interpolation** rather than chasing the newest packet. Each replica buffers timestamped host snapshots and renders **0.12 s** behind them, blending position between the two samples that bracket the render time. The local client seat uses a shorter **0.05 s** delay. If packets are late, the last authoritative velocity carries the body for at most **0.15 s**, then it holds instead of inventing a long extrapolation. Teleports and respawns snap and clear the buffer.

Every hit spawns a **scrolling world-space damage number** that rises, drifts and fades; headshots are larger and gold, damage you take is red, and lethal blows are orange. Arena clients derive the number from the authoritative health delta in each snapshot, so all peers see it without a new network message.

Taking damage applies a **hit stagger** of `0.08 s + 0.012 s per damage`, capped at **0.62 s**. A light dagger hit interrupts briefly; a greatsword or headshot interrupts longer. The victim's movement input, guard, draw, throw and swing are interrupted, the torso and head recoil visibly, and the cap still leaves a counter window. The recoil replicates through the animation phase as `STAGGER` without adding a snapshot field.

Fighters no longer hard-collide with each other. Their capsules have a **soft separation** that only pushes when centres are inside **0.46 m**, which lets two players close to stabbing distance without being shoved off their aim. World geometry, cover, blades and projectiles still collide normally.

The Hollow and arena lobby remember the **last player name, host address and UDP port** in `user://net_cache.json`. Joining a game updates the cache after validation, and the next form opens with those values.

## Game modes

**The Hollow:** the default out-of-raid screen. The ranger stands in the depot with a 10-slot inventory, a 20-slot stash, three vendors and the purse. Bought and equipped gear persists across launches, and the equipped kit is the starting loadout for every other mode.

**Arena:** a 64 × 64 metre woodland free-for-all with a wide spawn ring, new flank trees and stone islands around the original centre cover, four combatants, simple pursuit/attack bots, score tracking, and three-second respawns. Bots use the same damage and attack paths as players. Enter from the Hollow with **Arena Skirmish** (hosts locally on the first free UDP port from 7777), **Host a Game**, or **Join a Game**; `Arena.cmd` still opens the standalone lobby.

**Frontier:** a seamless 290 × 290 metre zone containing a village, enterable houses, forest, ruined fortress, upland shrine, trails and bridge. Defeat wolves, sentinels and cinder devil packs, clear defenders and restore three waystones. The village campfire heals. Mail reduces incoming damage by 15%, plate by 30%. Gold from foes and waystones is added to the Hollow purse immediately. Progress lasts for the play session; death preserves restored waystones. Use **Return to the Hollow** to bank the session and re-equip.

**The Sunken Delve:** a host-authoritative instanced survival room reached from the Hollow's deploy panel or the stone stair beside Hearthstead camp. The party stages on a raised landing, then drops through a shaft into one medium chamber with a 15 m ceiling, a central defence dais, pillars, barricades, crates and four dark archways. The room seals while a wave is alive. **Three waves of two cinder devils** trickle in from alternating archways and hunt the nearest living ranger; downed rangers stay down. A cleared wave opens the gates and, after a short cache-sealing timer, spawns a banded chest at the dais with a gold loot burst. Any ranger can open it; there is deliberately **no inventory, drop or loot-table system in this iteration**. After a clear the party can descend through the south gate (next wave) or ascend through the north gate back to the open frontier. A saved checkpoint records the last cleared wave and cache state, so the next run resumes there; a full-party wipe ends the run and clears the checkpoint. The Hollow and Hearthstead both host a local server, so friends can join any of these runs from **Join a Delve**.

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

## Update

**Close every running game instance, including the host, before updating.** Godot keeps loaded scripts in memory; pulling changes does not update an already-running match. The old ZIP test build used 1/2/3 for bow sizes and must not be used with this revision. Current windows show **0.3.0** in the HUD, and `Play.cmd` opens the Hollow.

```powershell
git pull --ff-only
.\Setup.cmd
.\Play.cmd
```

## Development and tests

`assets/characters/ironwood_ranger.glb` contains the skinned character and authored clips, including the one- and two-handed held guard loops; its adjacent JSON records source timing, guard targets/support clearance and weapon/palm transforms. `scripts/archer.gd` samples these animations on the physics clock, applies bow/terrain corrections, and emits blade sweeps from the same pose used to render the sword. `assets/characters/ironwood_wolf.glb` is the original textured Briar wolf: a continuous skinned quadruped with a 37-bone rig, deterministic grey coat and in-place idle, trot, bite and death clips. `scripts/wolf_visual.gd` samples them and maps the 1.5 s bite to gameplay's 0.65 s impact and 0.85 s recovery; `enemy.gd` keeps AI, collision, damage and the corpse lifetime authoritative. `scripts/devil_visual.gd` builds the half-size cinder devil from primitives and layers its run, leap, slide, side-step, claw and death poses; `_step_devil` in `enemy.gd` owns the orbiting pack AI, dives, two-attacker limit and shared `DodgeStep` side steps. `tests/devil_regression.gd` covers that split. `combat.gd` handles authoritative swept contact, independent sword recovery and bow readiness. `dodge_roll.gd` owns explicit Shift + Space roll state. `main.gd` controls the frontier; `arena.gd` and `arena_actor.gd` implement authoritative ENet multiplayer and replicas. World and weapon geometry remain runtime-generated.

`cover_movement.gd` owns acquisition, supported capsule sweeps, contiguous-surface sliding, bounded firing-corridor search and latched lookout/retuck state. The single authoritative cover snapshot contains physical stance and world-space `lean`; animation snapshots do not duplicate it. `archer.gd` layers the authored pose before foot/weapon corrections. `Combat` checks the actual shaft before a cover release; melee still clears cover before its first swing pose. Arena aim samples carry the observed own-actor snapshot tick, and remote release waits for the current exposure epoch before applying the unchanged shaft collision check. Regressions exercise left/right tree shots, convex and compound cover, slopes/recovery, side swaps/free look, blocked shafts, malformed/stale aim stamps, cancellation, melee exits and observer replication.

`hub_regression.gd` drives the out-of-raid loop: 10-slot inventory and 20-slot stash limits, per-slot armor equipping and mixed-set guard, legacy whole-set save migration, the scrollable 20-piece Quartermaster stock, vendor pricing and rejections, equipped-copy protection, save/reload persistence, HUD panel and modal geometry with label clipping, the 3D preview following equipped gear, the frontier's stored loadout and purse hand-off, and the hub-to-arena host session with validated seat loadouts. Script-mode tests start from the authored defaults instead of a player's real save.

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
& $Godot --headless --path . --script res://tests/swing_reach_regression.gd
& $Godot --headless --path . --script res://tests/running_slide_regression.gd
& $Godot --headless --path . --script res://tests/block_clash_regression.gd
& $Godot --headless --path . --script res://tests/hitbox_regression.gd
& $Godot --headless --path . --script res://tests/hub_regression.gd
& $Godot --headless --path . --script res://tests/throw_regression.gd
& $Godot --headless --path . --script res://tests/world_art_regression.gd
& $Godot --headless --path . --script res://tests/delve_regression.gd
& $Godot --headless --path . --script res://tests/delve_entry_regression.gd
& $Godot --headless --path . --script res://tests/delve_network_regression.gd
```

`delve_regression.gd` checks the three-wave/two-devil plan, checkpoint JSON round-trip and corruption rejection, the chamber spawns/ceiling/gates and reachable ascent/descent, the full solo flow (drop, sealed wave, real bow damage, clear timer, cache burst, descend, final cache, explicit revive, party wipe), and checkpoint resume. `delve_entry_regression.gd` drives the Hollow's **Descend the Delve** button, the Hearthstead stair, and the ascent back to `main.tscn`. `delve_network_regression.gd` runs two real ENet processes: a client joins the landing, both see the wave, and both see the cache open.

### Rebuilding character assets

The bundled Ranger model and motions are **CC0**: Ranger/base characters and locomotion by [Quaternius](https://quaternius.com/), with the two-handed heavy attack by [Gres](https://opengameart.org/content/humanoid-soulslike-animations). The Briar wolf is original procedural work authored by `tools/prepare_wolf.py`; it is not derived from those sources. Exact source files, extraction ranges, wolf measurements and modifications are recorded in [the asset provenance](assets/characters/LICENSE.txt). No paid pack or game account is needed.

To re-author the assets, install Blender 5.1+, download and unpack the listed free sources into `.runtime/character-source`, then run:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python tools/prepare_character.py -- .runtime/character-source assets/characters/ironwood_ranger.glb
& $Godot --headless --editor --path . --import
```

Keep the GLB, adjacent JSON/provenance, and `.glb.import` settings together. Import settings preserve authored clip names, use 60 Hz animation sampling, and keep textures embedded rather than duplicating extracted PNGs. The preparation workflow preserves the authored striking arm and body motion, corrects support-hand proportions and clothing clearance, and smooths the one-handed cut's timing. `tools/character_clearance.py` validates interpolated support-arm motion against the deformed outfit before export is accepted.

The same rebuild imports `Crouch_Idle_Loop` and `Crouch_Fwd_Loop` from the existing Quaternius source and authors `Cover_Lean_Top`, `Cover_Lean_Left` and `Cover_Lean_Right` in Blender, plus the **0.5-second** `Dagger_Stab` thrust and the two held guard loops. The three 0.24-second lean clips share an idle reference, with planted feet and unchanged local arm poses for weapon layering. JSON records their asset-space directions, the stab's contact window and the crouch clip's measured stride estimate; runtime cadence follows actual movement rather than requested speed.

Optional Godot MCP tooling is pinned under `tools/`; run `npm ci --ignore-scripts` there if needed. Local MCP configuration, engine binaries, imports, caches and logs are excluded from Git. They are not required from the original development machine.

Godot is downloaded separately under its [MIT license](https://godotengine.org/license/). [Official engine release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Archery stance reference: [World Archery recurve technique](https://extranet.worldarchery.sport/documents/index.php/Media/Information_Sheets/003_Guide_to_Recurve_Technique.pdf).
