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
| Shift | Run; consumes stamina |
| Space | Jump |
| Shift + Space | Immediately jump-roll in the movement direction, or forward if stationary |
| F | Post up against nearby solid cover / leave cover |
| Hold right mouse in cover | Peek over low cover or around the selected edge of tall cover |
| X | Smoothly switch between right- and left-shoulder camera views |
| 1 | Equip the selected bow |
| 2 | Equip the selected sword |
| Mouse movement | Mouse-look with a fixed center crosshair; no aim assistance |
| Hold left mouse / Q with bow | Raise and draw while continuing to aim |
| Release left mouse / Q with bow | Launch exactly one arrow; damage occurs only on impact |
| Click left mouse / Q with sword | Perform one uncharged overhand chop |
| Escape / I | Free the cursor for equipment clicks; cancel a held attack |
| Click the world / right mouse | Resume captured mouse-look |
| Mouse wheel | Zoom; right-drag orbits only in frontier inspection view |
| C | Cycle armor |

**1 always equips the selected bow; 2 always equips the selected sword. No number key changes size.** Click the small / medium / large buttons to select each weapon's size independently. Escape frees the cursor; clicking the world resumes aiming. In the frontier, **I** opens equipment, **V** inspects the character, **M** opens the map, **E** interacts, **R** returns to camp, and **N** toggles sound. The arena displays equipment controls and a **Leave Match** button.

## Cover movement and shoulder views

Both Frontier and Arena use the same geometry-driven cover movement. Stand within **1.35 m** of a tree trunk, wall, stone barrier or solid debris and press **F**. The character approaches the surface with normal collision, faces away from it, and stays attached while you look around freely. **WASD** moves along the surface at cover speed; sprinting is disabled. Rounded trunks can be followed, while exposed edges and sharp corners stop movement instead of automatically walking you out of protection. Decorative meshes without collision and the ground are not cover.

Low cover lowers both the skeleton and the real collision capsule. **Hold RMB** to stand and peek over it. At tall cover, move to an edge, then hold RMB to physically step out on the selected shoulder's side. Peek movement stays anchored; release RMB to return behind cover. **X** swaps the camera smoothly and selects the other peek side. The camera uses a swept sphere against world geometry, including during shoulder transitions, so nearby walls cannot be crossed by the camera boom. Shoulder switching changes the view, not the weapon's handedness.

Attack normally with LMB / Q **while exposed**; tucked cover cannot fire through the obstacle. Returning to cover cancels an unreleased draw. **F**, **Space**, or **Shift + Space** leaves cover; jump and roll retain their existing behavior. Cover grants no invulnerability. Death, respawn and returning to camp clear cover state. Arena movement, exposure, collider changes and attacks remain host-authoritative, with cover poses replicated to the other players.

## Bow charge, damage and re-nocking

Aiming behaves like a shooter: the camera turns with the mouse and the crosshair stays in the center. There is **no auto-fire, unit lock-on, target tracking, or automatic gravity compensation**. Hold left mouse to draw and aim; release to launch one arrow along the current crosshair aim. Holding at full draw never fires automatically. Arrows still fall under gravity after launch, and only actual collision applies damage.

```text
arrow damage = bow base damage × clamp(draw amount, 0, 1)
```

Zero draw gives zero damage, half draw gives half damage, and full draw gives full damage. Armor applies its normal reduction afterward. Arrow flight and world obstruction use real swept physics collision.

The charge bar and bowstring animation fill together over the bow's full draw duration, including raising the bow. Release whenever you want: a large bow held for **1.5 seconds deals 50% damage**; holding it for 3 seconds gives full damage.

| Bow | Full draw duration | Full damage before armor |
| --- | --- | --- |
| Small | 1 second | 30 |
| Medium | 2 seconds | 38 |
| Large | 3 seconds | 50 |

There is **no separate bow attack cooldown**. Every release, even at zero or partial draw, plays a 0.28-second follow-through followed by 0.95 seconds to fetch and nock the next arrow. You can start drawing again as soon as that animation finishes. The HUD shows **NOCKING NEXT ARROW** during recovery. Changing weapons, bow size, movement or canceling cannot skip or restart re-nocking. Canceling an unreleased draw does not spend its arrow. Walking and running do not slow charging or re-nocking; you can move while aiming. New attacks cannot begin while airborne or rolling.

The draw hand uses a cheek-surface landmark on the imported head. Bow raising, shoulder retrieval and re-nocking follow reachable paths outside the torso; the bow is brought in front of the centreline while loading. Geometry regressions check the forearms against the actual skinned outfit, not just whether the bones remain connected.

## Swords and jump-rolls

Small / medium / large swords perform **1 / 2 / 3-second** overhand chops, including raise, strike and recovery. Melee has no held charge or damage multiplier. A click starts one swing; holding the button does not repeat it. Sword swing durations remain fixed while moving.

Damage comes from the **moving blade**, not a fixed percentage of the swing or an attacker-centered cone. During the authored downstroke, continuous blade-volume sweeps detect real contact and block at world cover. Each swing damages a target at most once; windup and recovery cannot damage it. Switching weapons or rolling cancels further contacts without resetting sword recovery. Sword recovery continues independently while a bow is equipped; it neither blocks bow charging nor gets cleared by switching back.

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

`assets/characters/ironwood_ranger.glb` contains the skinned character and authored clips; its adjacent JSON records source timing and weapon/palm transforms. `scripts/archer.gd` samples these animations on the physics clock, applies bow/terrain corrections, and emits blade sweeps from the same pose used to render the sword. `combat.gd` handles authoritative swept contact, independent sword recovery and bow readiness. `dodge_roll.gd` owns explicit Shift + Space roll state. `main.gd` controls the frontier; `arena.gd` and `arena_actor.gd` implement authoritative ENet multiplayer and replicas. World and weapon geometry remain runtime-generated.

`cover_movement.gd` owns surface acquisition, tangential movement, low-cover collision and physical peeking. `shoulder_camera.gd` provides the shared smooth shoulder offset and volume-based camera collision. `cover_movement_regression.gd` exercises walls, curved trunks, rotated surfaces, edge stops, crouch/peek transitions, lifecycle resets and camera obstruction. The four-process `network_input_regression.gd` also exercises remote cover movement, peeking, shoulder input, malformed requests and observer replication.

The repo-local [Ironwood Archer skill](.omp/skills/ironwood-archer/SKILL.md) covers architecture, gameplay contracts, authored skeletal animation, multiplayer integration, testing and safe restarts. OMP discovers it at session startup; invoke `/skill:ironwood-archer` in a new session to load it explicitly.

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
```

### Rebuilding character assets

The bundled model and motions are **CC0**: Ranger/base characters and locomotion by [Quaternius](https://quaternius.com/), with the two-handed heavy attack by [Gres](https://opengameart.org/content/humanoid-soulslike-animations). Exact source files, extraction ranges and modifications are recorded in [the asset provenance](assets/characters/LICENSE.txt). No paid pack or game account is needed.

To re-author the assets, install Blender 5.1+, download and unpack the listed free sources into `.runtime/character-source`, then run:

```powershell
$Blender = 'C:\Program Files\Blender Foundation\Blender 5.1\blender.exe'
& $Blender --background --python tools/prepare_character.py -- .runtime/character-source assets/characters/ironwood_ranger.glb
& $Godot --headless --editor --path . --import
```

Keep the GLB, adjacent JSON/provenance, and `.glb.import` settings together. Import settings preserve authored clip names, use 60 Hz animation sampling, and keep textures embedded rather than duplicating extracted PNGs. The preparation workflow preserves the authored striking arm and body motion, corrects support-hand proportions and clothing clearance, and smooths the one-handed cut's timing. `tools/character_clearance.py` validates interpolated support-arm motion against the deformed outfit before export is accepted.

Optional Godot MCP tooling is pinned under `tools/`; run `npm ci --ignore-scripts` there if needed. Local MCP configuration, engine binaries, imports, caches and logs are excluded from Git. They are not required from the original development machine.

Godot is downloaded separately under its [MIT license](https://godotengine.org/license/). [Official engine release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Archery stance reference: [World Archery recurve technique](https://extranet.worldarchery.sport/documents/index.php/Media/Information_Sheets/003_Guide_to_Recurve_Technique.pdf).
