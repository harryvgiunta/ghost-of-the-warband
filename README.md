# Ironwood — Frontier and Arena

A Godot 4 third-person action game with a seamless woodland frontier and a four-combatant multiplayer arena. A textured, rigged male Ranger with authored human animation, swappable bows, swords and armor, free-aim archery, contact-driven overhand melee attacks, and directional jump-rolls.

## Windows quick start

Requires Windows x64, PowerShell, and [Git](https://git-scm.com/download/win). No Godot installation, Node.js, paid assets, or game account is required.

```powershell
git clone https://github.com/harryvgiunta/ironwood-arena.git
cd ironwood-arena
.\Setup.cmd
.\Arena.cmd
```

`Setup.cmd` downloads **Godot 4.7.2 stable** from its official GitHub release, verifies the pinned SHA-256 checksum, and installs it inside the ignored `.runtime/godot` directory. No administrator access or system-wide installation is needed. Running setup again reuses the verified-version installation. The game launchers also run setup automatically if the managed engine is missing.

The launchers import the bundled character assets before starting the game, so a fresh checkout does not need an existing `.godot` cache. Subsequent launches reuse imported assets. Blender is not required to play.

- **Arena.cmd:** multiplayer lobby, or solo practice against bots.
- **Play.cmd:** the single-player frontier.
- **Host Tailscale.cmd:** immediately host an arena on UDP 7777.

Set `GODOT_PATH` to use another existing Godot executable. Linux/macOS users can install Godot 4.7.2, import `project.godot`, and run `arena.tscn` or `main.tscn`; the Windows setup script does not install engines for those platforms.

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

There are four seats: the host and up to three joining humans. Empty seats use bots. Joining replaces a bot; disconnecting restores one. A fifth human is refused. Health, movement, attacks, damage, kill/death scores, and respawns are host-authoritative. Clients send input and aim points, not damage or charge claims. The host leaving returns clients to the lobby; there is no host migration or matchmaking service.

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
| Hold right mouse in cover | Guard and peek over low cover or around the selected edge of tall cover |
| X | Swap shoulder camera and select the left/right lookout while in cover |
| 1 | Equip the selected bow |
| 2 | Equip the selected sword |
| Mouse movement | Mouse-look with a fixed center crosshair; no aim assistance |
| Hold left mouse / Q with bow | Raise and draw while aiming; automatically expose from cover |
| Release left mouse / Q with bow | Launch one arrow; cover shots wait for exposure without gaining charge |
| Click left mouse / Q with sword | Break sticky cover and immediately perform one uncharged overhand chop |
| Escape / I | Free the cursor for equipment clicks; cancel a held attack |
| Click the world / right mouse | Resume captured mouse-look; right mouse also raises a sword guard |
| Mouse wheel | Zoom; right-drag orbits only in frontier inspection view |
| C | Toggle crouch while grounded; slide when pressed during a sprint |

**1 always equips the selected bow; 2 always equips the selected sword. No number key changes size.** Click the small / medium / large buttons to select each weapon's size independently. Escape frees the cursor; clicking the world resumes aiming. In the frontier, **I** opens equipment, **V** inspects the character, **M** opens the map, **E** interacts, **R** returns to camp, and **N** toggles sound. The arena displays equipment controls and a **Leave Match** button.

## Running slide

In both Frontier and Arena, **hold Shift while moving, then press C** to slide. The character must already be sprinting on the ground: standing still, walking, exhaustion, rolling and attached cover cannot trigger a running slide.

The slide starts at **10.5 m/s**, slows to crouch speed over **0.75 seconds**, and finishes crouched. Releasing WASD or Shift preserves its momentum; WASD allows limited steering without reversing direction. It uses the normal collision capsule, lowers the camera, and shows a low, planted slide pose instead of cycling running steps. Sprint stamina consumption continues during the slide, and holding Shift cannot automatically repeat it.

Press **C** again to cancel and stand when headroom permits. **Space** jumps and **Shift + Space** rolls out of the slide, also requiring standing clearance. Blocked forward travel or leaving the ground ends the slide; death, respawn and returning to camp clear it. Grounded attacks still work, and sliding grants no invulnerability. Arena derives slide eligibility and movement on the host and replicates the pose to other players.

## Cover movement and shoulder views

Both Frontier and Arena use the same geometry-driven cover movement. Stand within **1.35 m** of a tree trunk, wall, stone barrier or solid debris and press **F**. The character approaches with normal collision, faces away from the surface, and stays attached while you look around freely. **WASD** slides along the surface at **2.2 m/s**; hold **Shift** to slide at **4.2 m/s**, spending stamina with normal exhaustion rules. Both speeds work while crouched. Contiguous rounded, faceted and compound surfaces can be followed without treating collider-shape seams as cover edges. Genuine edges, hard corners and unsupported ground still stop movement. Decorative meshes without collision and the ground are not cover.

**X selects the left or right lookout**; the HUD shows **LEFT LOOKOUT**, **RIGHT LOOKOUT** or **TOP LOOKOUT** when exposed. Hold **RMB** to look out. Low cover uses a standing top peek; tall or rounded cover uses the selected side. The controller chooses the shortest supported, capsule-safe step with a clear firing corridor: **0.45 m**, extending to **0.55 m** or **0.65 m** only when the geometry requires it. A wide object may require sliding to its flank first. Trees, rotated props and convex rocks use the same clearance checks, not object-specific exceptions.

Lookouts keep one protected anchor and one selected destination through hold and return. Free look and button release do not silently switch the physical side; a new request or explicit X swap captures a new view frame. Ground-supported capsule sweeps follow slopes instead of treating floor contact as a wall, and a small floor-recovery displacement cannot leave the return latch stuck. Authored top/left/right poses follow actual exposure. The camera retains swept-volume collision during shoulder changes. Shoulder selection does not change weapon handedness.

**C** toggles manual crouch on the ground, in or out of cover; it never changes armor. Crouching lowers the camera, skeleton and collision capsule together. Authored crouch idle and stepping animations support attached movement at both slide speeds, including curved surfaces. Side peeks preserve crouch; a top peek temporarily rises, then restores the tucked posture. Outside cover, crouched movement is **2.2 m/s** and Shift does not sprint. Leaving with **F** preserves manual crouch. Standing waits for clear headroom rather than expanding the capsule through a ceiling.

**LMB / Q attacks directly out of cover; RMB is not required.** A bow draw automatically exposes over low cover or around the selected edge. Releasing early freezes charge while the character finishes exposing and raising the bow, then fires exactly once. The character retucks after follow-through. Blocked edges and insufficient headroom reject bow exposure rather than storing a shot that fires later.

**Melee breaks sticky cover immediately.** A valid sword click releases attachment and starts the normal swing without waiting for a peek, including at the solid middle of a tall wall. You can move away from the wall during the attack and remain detached afterward; press **F** to attach again. The exit does not teleport, force standing, or clear manual crouch. Cooldown, airborne and rolling restrictions still apply, and a rejected attack does not detach you. The blade still collides with world cover; attacking does not allow damage through walls.

A draw begun during a manual RMB peek leaves that peek under manual control: release RMB to retuck without canceling the held draw; releasing the bow afterward exposes again before firing. Holding RMB keeps the manual peek after a bow attack finishes; it cannot reattach a melee attacker. Cover releases check the visible arrow shaft from nock to tip, including an initially buried nock. A genuinely obstructed shaft cancels its pending shot instead of firing through the obstacle or storing a latent release. Clear shots launch from the rendered arrow tip, never from a replacement chest position. Actual projectile collisions still block obstacles.

**Space** and **Shift + Space** leave cover, clear manual crouch and attack/peek intent, then jump or roll; insufficient standing headroom blocks takeoff. Cover grants no invulnerability. Cancellation, equipment changes, death, respawn and returning to camp clear pending attacks. Arena remains host-authoritative: clients send validated movement, lookout context, crouch intent and the snapshot used to sample aim—not trusted collider sizes or cover positions. Remote releases wait for a fresh aim sample from the current exposed pose, without adding charge. Lost input cancels automatic/frozen cover intent, so it cannot fire later when input resumes.

## Bow charge, damage and re-nocking

Aiming behaves like a shooter: the camera turns with the mouse and the crosshair stays in the center. There is **no auto-fire, unit lock-on, target tracking, or automatic gravity compensation**. Hold left mouse to draw and aim; release to launch one arrow along the current crosshair aim. Holding at full draw never fires automatically. Arrows still fall under gravity after launch, and only actual collision applies damage.

Both shoulder views aim at the world point under the crosshair, independently of the character's previous facing. Aim queries start at the character's view-height plane and skip only the cover body you are posted against. Raising or turning the bow cannot make the query skip a nearby target. Arrows still launch from the visible tip and collide normally.

```text
arrow damage = bow base damage × clamp(draw amount, 0, 1)
```

Zero draw gives zero damage, half draw gives half damage, and full draw gives full damage. Armor applies its normal reduction afterward. Arrow flight and world obstruction use real swept physics collision.

Hits in the animated **head zone** deal **double damage**; body hits keep the base value. The zone follows the head joint through crouch, cover lean and rolls. It applies to arena players and bots plus the frontier wolf and sentinel, and the multiplier is resolved before armor. A blade that sweeps through the head zone also doubles, even when the shape query reports the contact elsewhere; the zone is a damage volume on the normal body capsule, not a second collider.

The charge bar and bowstring animation fill together over the bow's full draw duration, including raising the bow. Release whenever you want: a large bow held for **1.5 seconds deals 50% damage**; holding it for 3 seconds gives full damage.

| Bow | Full draw duration | Full damage before armor |
| --- | --- | --- |
| Small | 1 second | 30 |
| Medium | 2 seconds | 38 |
| Large | 3 seconds | 50 |

There is **no separate bow attack cooldown**. Every release, even at zero or partial draw, plays a 0.28-second follow-through followed by 0.95 seconds to fetch and nock the next arrow. You can start drawing again as soon as that animation finishes. The HUD shows **NOCKING NEXT ARROW** during recovery. Changing weapons, bow size, movement or canceling cannot skip or restart re-nocking. Canceling an unreleased draw does not spend its arrow. Walking and running do not slow charging or re-nocking; you can move while aiming. New attacks cannot begin while airborne or rolling.

The draw hand uses a cheek-surface landmark on the imported head. Bow raising, shoulder retrieval and re-nocking follow reachable paths outside the torso; the bow is brought in front of the centreline while loading. Geometry regressions check the forearms against the actual skinned outfit, not just whether the bones remain connected.

## Swords and jump-rolls

Small / medium / large swords perform **1 / 2 / 3-second** overhand chops, including raise, strike and recovery. Melee has no held charge; only a head-zone contact doubles damage. A click starts one swing; holding the button does not repeat it. Sword swing durations remain fixed while moving.

Damage comes from the **moving blade**, not a fixed percentage of the swing or an attacker-centered cone. During the authored downstroke, continuous blade-volume sweeps detect real contact and block at world cover. Each swing damages a target at most once; windup and recovery cannot damage it. Switching weapons or rolling cancels further contacts without resetting sword recovery. Sword recovery continues independently while a bow is equipped; it neither blocks bow charging nor gets cleared by switching back.

## Guarding, parries and clashes

Equip a sword with **2** and hold **RMB** while grounded and ready to guard. The character faces the camera, stops rotating with movement, and does not regenerate stamina while guarding. A hit from the front resolves from the guard timer, not exact blade geometry:

| Outcome | Trigger | Result |
| --- | --- | --- |
| Parry | Block began at most **0.25 s** before the hit | No damage. The attacker is staggered for **0.8 s**, leaving a guaranteed counter-hit. |
| Standard block | Guard held longer than **0.25 s** before the hit | No damage, **22 stamina** spent, and the defender is pushed slightly away. Both sides return to neutral. |
| Unblocked | Guard down, wrong facing, rolling, attacking, or no sword | Normal damage applies. |

Releasing RMB drops the guard; pressing an attack while guarding also drops it. Guarding pauses stamina recovery, so repeated blocks cannot be turtled for free, and a guard with insufficient stamina still spends what remains. The held pose is a dedicated character-only animation: `Sword_Block_Loop_OneHand` for short and arming swords, and the two-handed `Sword_Block_Loop` for the greatsword. Both are **120-sample / 1.983-second** breathing loops with planted feet; the greatsword's support hand stays on the actual hilt. These clips animate the Ranger rig only; the sword remains the normal socketed runtime weapon, and the lower-body crouch/slide layer does not overwrite the guard arms.

If two sword users are in their active downstroke at the same time and facing each other, their blades **clash** instead of trading damage: sparks and a loud clang, zero damage in both directions, a small bounce apart, and both swings reset so either fighter can immediately act again. A clash never uses an exact sword-to-sword contact test; simultaneous active hit-frames plus mutual facing are sufficient.

The character uses a 65-bone skinned humanoid and authored animation clips. The greatsword has a genuine two-handed overhead load, accelerating downward cut, whole-body weight transfer, closed hilt grip, follow-through and recovery. Short/medium swords use a separate authored one-handed overhead. Windup and recovery absorb the different weapon durations instead of stretching the cutting stroke into slow motion. Source motions are retargeted and grip/timing corrections baked in Blender; sword elbows are not posed by runtime IK. The textured character and environment remain stylized, not photorealistic rendering.

**Shift + Space** starts a tucked forward tumble and directional burst immediately, either from the ground or during a jump. Space alone only jumps; double-tapping it never rolls. Knees and elbows fold, the chin tucks, the weapon stays clear of the torso, and landing compresses the legs before returning to the normal stance. Running or strafing direction takes priority over facing. Only one roll is allowed before landing; it does not grant invulnerability or ignore world collisions.

[In-engine authored sword, bow, movement and roll preview](media/motion-preview.mp4)

Authored walk, jog and sprint clips follow actual movement speed with a continuous gait phase. The sprint includes knee/heel recovery, flight, body lean and alternating arm drive. Bow aiming and terrain contact use skeletal corrections; the greatsword keeps a coupled two-hand carry. Collisions that stop movement also stop the running gait.

## Game modes

**Arena:** a small woodland free-for-all with trees and stone cover, four combatants, simple pursuit/attack bots, score tracking, and three-second respawns. Bots use the same damage and attack paths as players.

**Frontier:** a seamless 290 × 290 metre zone containing a village, enterable houses, forest, ruined fortress, upland shrine, trails and bridge. Defeat wolves and sentinels, clear defenders and restore three waystones. The village campfire heals. Mail reduces incoming damage by 15%, plate by 30%. Progress lasts for the play session; death preserves restored waystones.

## Update

**Close every running game instance, including the host, before updating.** Godot keeps loaded scripts in memory; pulling changes does not update an already-running match. The old ZIP test build used 1/2/3 for bow sizes and must not be used with this revision. Current windows show **0.2.0** in the HUD.

```powershell
git pull --ff-only
.\Setup.cmd
.\Arena.cmd
```

## Development and tests

`assets/characters/ironwood_ranger.glb` contains the skinned character and authored clips, including the one- and two-handed held guard loops; its adjacent JSON records source timing, guard targets/support clearance and weapon/palm transforms. `scripts/archer.gd` samples these animations on the physics clock, applies bow/terrain corrections, and emits blade sweeps from the same pose used to render the sword. `assets/characters/ironwood_wolf.glb` is the original textured Briar wolf: a continuous skinned quadruped with a 37-bone rig, deterministic grey coat and in-place idle, trot, bite and death clips. `scripts/wolf_visual.gd` samples them and maps the 1.5 s bite to gameplay's 0.65 s impact and 0.85 s recovery; `enemy.gd` keeps AI, collision, damage and the corpse lifetime authoritative. `combat.gd` handles authoritative swept contact, independent sword recovery and bow readiness. `dodge_roll.gd` owns explicit Shift + Space roll state. `main.gd` controls the frontier; `arena.gd` and `arena_actor.gd` implement authoritative ENet multiplayer and replicas. World and weapon geometry remain runtime-generated.

`cover_movement.gd` owns acquisition, supported capsule sweeps, contiguous-surface sliding, bounded firing-corridor search and latched lookout/retuck state. The single authoritative cover snapshot contains physical stance and world-space `lean`; animation snapshots do not duplicate it. `archer.gd` layers the authored pose before foot/weapon corrections. `Combat` checks the actual shaft before a cover release; melee still clears cover before its first swing pose. Arena aim samples carry the observed own-actor snapshot tick, and remote release waits for the current exposure epoch before applying the unchanged shaft collision check. Regressions exercise left/right tree shots, convex and compound cover, slopes/recovery, side swaps/free look, blocked shafts, malformed/stale aim stamps, cancellation, melee exits and observer replication.

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
& $Godot --headless --path . --script res://tests/running_slide_regression.gd
& $Godot --headless --path . --script res://tests/block_clash_regression.gd
& $Godot --headless --path . --script res://tests/hitbox_regression.gd
```

### Rebuilding character assets

The bundled Ranger model and motions are **CC0**: Ranger/base characters and locomotion by [Quaternius](https://quaternius.com/), with the two-handed heavy attack by [Gres](https://opengameart.org/content/humanoid-soulslike-animations). The Briar wolf is original procedural work authored by `tools/prepare_wolf.py`; it is not derived from those sources. Exact source files, extraction ranges, wolf measurements and modifications are recorded in [the asset provenance](assets/characters/LICENSE.txt). No paid pack or game account is needed.

To re-author the assets, install Blender 5.1+, download and unpack the listed free sources into `.runtime/character-source`, then run:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python tools/prepare_character.py -- .runtime/character-source assets/characters/ironwood_ranger.glb
& $Godot --headless --editor --path . --import
```

Keep the GLB, adjacent JSON/provenance, and `.glb.import` settings together. Import settings preserve authored clip names, use 60 Hz animation sampling, and keep textures embedded rather than duplicating extracted PNGs. The preparation workflow preserves the authored striking arm and body motion, corrects support-hand proportions and clothing clearance, and smooths the one-handed cut's timing. `tools/character_clearance.py` validates interpolated support-arm motion against the deformed outfit before export is accepted.

The same rebuild imports `Crouch_Idle_Loop` and `Crouch_Fwd_Loop` from the existing Quaternius source and authors `Cover_Lean_Top`, `Cover_Lean_Left` and `Cover_Lean_Right` in Blender. The three 0.24-second lean clips share an idle reference, with planted feet and unchanged local arm poses for weapon layering. JSON records their asset-space directions and the crouch clip's measured stride estimate; runtime cadence follows actual movement rather than requested speed.

Optional Godot MCP tooling is pinned under `tools/`; run `npm ci --ignore-scripts` there if needed. Local MCP configuration, engine binaries, imports, caches and logs are excluded from Git. They are not required from the original development machine.

Godot is downloaded separately under its [MIT license](https://godotengine.org/license/). [Official engine release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Archery stance reference: [World Archery recurve technique](https://extranet.worldarchery.sport/documents/index.php/Media/Information_Sheets/003_Guide_to_Recurve_Technique.pdf).
