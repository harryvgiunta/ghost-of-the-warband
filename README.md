# Ironwood — Frontier and Arena

A Godot 4 third-person action game with a seamless woodland frontier and a four-combatant multiplayer arena. Original procedural male character, swappable bows, swords and armor, free-aim archery, overhand melee attacks, and directional jump-rolls.

## Windows quick start

Requires Windows x64, PowerShell, and [Git](https://git-scm.com/download/win). No Godot installation, Node.js, paid assets, or game account is required.

```powershell
git clone https://github.com/harryvgiunta/ironwood-arena.git
cd ironwood-arena
.\Setup.cmd
.\Arena.cmd
```

`Setup.cmd` downloads **Godot 4.7.2 stable** from its official GitHub release, verifies the pinned SHA-256 checksum, and installs it inside the ignored `.runtime/godot` directory. No administrator access or system-wide installation is needed. Running setup again reuses the verified-version installation. The game launchers also run setup automatically if the managed engine is missing.

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
| WASD | Move relative to the camera |
| Shift | Run; consumes stamina |
| Space | Jump |
| Space twice within 0.30 seconds | Jump-roll in the movement direction, or forward if stationary |
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

## Bow damage and cooldowns

Aiming behaves like a shooter: the camera turns with the mouse and the crosshair stays in the center. There is **no auto-fire, unit lock-on, target tracking, or automatic gravity compensation**. Hold left mouse to draw and aim; release to launch one arrow along the current crosshair aim. Holding at full draw never fires automatically. Arrows still fall under gravity after launch, and only actual collision applies damage.

```text
arrow damage = bow base damage × clamp(draw amount, 0, 1)
```

Zero draw gives zero damage, half draw gives half damage, and full draw gives full damage. Base damage is 30 / 38 / 50 for the three bow sizes; armor applies its normal reduction afterward. Arrow flight and world obstruction use real swept physics collision.

Cooldown starts on release. Wait until ready before starting another draw. Changing equipment or movement retains fractional cooldown progress; cancellation cannot reset it.

| Bow | Standing cooldown | Walking cooldown | Running cooldown |
| --- | --- | --- | --- |
| Small | 1 second | 2 seconds | 4 seconds |
| Medium | 2 seconds | 4 seconds | 8 seconds |
| Large | 3 seconds | 6 seconds | 12 seconds |

Walking reduces cooldown recovery rate by 50%; running by 75%. Standing has no penalty. Actual movement determines the penalty, so pushing into a wall counts as standing. You can move while aiming. New attacks cannot begin while airborne or rolling.

## Swords and jump-rolls

Small / medium / large swords perform **1 / 2 / 3-second** overhand chops, including raise, strike and recovery. Melee has no held charge or damage multiplier. A click starts one swing; holding the button does not repeat it. Sword swing durations remain fixed while moving.

The strike checks nearby opposing collision bodies in front of the attacker, with line-of-sight checks so cover blocks damage. Each swing damages a target at most once. Switching weapons or rolling before impact cancels the pending strike without resetting cooldown.

The sword animation uses a staggered stance, hip/shoulder rotation, weight transfer through the downward cut, a closed grip, and recovery. The greatsword stays two-handed. The character art is stylized, not a photorealistic or motion-captured model.

A quick second Space press turns the jump into a tucked forward tumble and directional burst. Knees and elbows fold, the chin tucks, the weapon stays clear of the torso, and landing compresses the legs before returning to the normal stance. Running or strafing direction takes priority over facing. Only one roll is allowed per airborne jump; it does not grant invulnerability or ignore world collisions.

[In-engine sword and jump-roll motion preview](media/motion-preview.mp4)

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

All assets are runtime-generated Godot geometry. `scripts/archer.gd` handles the articulated character and equipment animation; `combat.gd` owns bow cooldowns and sword hit checks; `dodge_roll.gd` owns double-tap roll state. `main.gd` controls the frontier. `arena.gd` and `arena_actor.gd` implement authoritative ENet multiplayer and replicas.

Run the behavior regressions after setup:

```powershell
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --path . --script res://tests/rig_regression.gd
& $Godot --headless --path . --script res://tests/draw_combat_regression.gd
& $Godot --headless --path . --script res://tests/projectile_regression.gd
& $Godot --headless --path . --script res://tests/gameplay_regression.gd
& $Godot --headless --path . --script res://tests/melee_roll_regression.gd
& $Godot --headless --path . --script res://tests/action_pose_regression.gd
& $Godot --headless --path . --script res://tests/weapon_input_regression.gd
& $Godot --headless --path . --script res://tests/network_input_regression.gd
```

Optional Godot MCP tooling is pinned under `tools/`; run `npm ci --ignore-scripts` there if needed. Local MCP configuration, engine binaries, imports, caches and logs are excluded from Git. They are not required from the original development machine.

Godot is downloaded separately under its [MIT license](https://godotengine.org/license/). [Official engine release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable). Archery stance reference: [World Archery recurve technique](https://extranet.worldarchery.sport/documents/index.php/Media/Information_Sheets/003_Guide_to_Recurve_Technique.pdf).
