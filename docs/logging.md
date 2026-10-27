# Automatic logging and crash reports

`scripts/log.gd` is the first autoload (`Log`). It runs in every mode — the town,
arena, delve, title menu and a `--script` regression — and records a session
without any code opting in. The game's structured events and the engine's own
messages share one stream, and a crash is reconstructed on the next launch.

## What is captured

| Layer | Detail |
| --- | --- |
| Boot environment | Engine version, build hash, official/debug/editor/template flags, architecture, physics rate; project name, version, main scene, root and features; OS version and alias, locale, time zone, architecture, CPU model and core count, physical/free/available/stack memory, host name and user name, executable and user-data paths; GPU adapter, vendor, API version, rendering method and driver, video memory; window mode, size, vsync, screens, DPI, scale, refresh rate; audio driver, mix rate and devices; connected joypads; full command lines |
| Engine messages | Every `print`, `push_warning`, `push_error`, script error and shader error received through `OS.add_logger`, with `ScriptBacktrace.format()` (call stack, plus any locals/members the engine captured), a structured frame list, the engine's function/file/line/code/rationale, the error-type name and the originating thread |
| Game breadcrumbs | The session arm/clear intent, host/join outcomes, connections and peer changes, open-world descent requests, delve phases/waves/depths/chests/wipes, player deaths, menu actions, saves/loads/resets and display switches. Categories: `net`, `game`, `arena`, `delve`, `menu`, `state` |
| State samples | Every 2 s: FPS, process and physics milliseconds, static/peak memory, object/resource/node/orphan counts, draw calls, video memory, 3D physics bodies/pairs, scene path and class, tree node count, wilderness/cinder counts, input mode, window size, process memory, multiplayer peer/id/count, the scene's role/health/stamina/gold/kills and (main/delve) player position and run state, plus the full backpack/stash/floor item lists and their counts, the TAB quick pair and the ten equipped slots from `PlayerState`, and every scene actor's slot, peer, name, health, alive state and authority |
| Stalls | A watchdog thread reports a main-loop gap over 6 s as `hang`, with the last sample, breadcrumbs and memory, and a `hang_resume` when frames move again |

No frame-by-frame trace is written. The sampler is the periodic cost; everything
else is event-driven.

## Where it lives

All paths are under `user://logs` unless `--log-dir` is set. On Windows this is
`%APPDATA%\Godot\app_userdata\IRONWOOD - The Frontier\logs`; the console prints
the exact folder as `IRONWOOD_LOG_DIR <path>` at boot. All worktrees share the
same Godot project name and therefore the same user folder; use `--log-dir` when
you want a build-isolated stream.

| File | Contents |
| --- | --- |
| `sessions/session-<UTC>-<pid>-<source>.jsonl` | One JSON object per line: `session_start`, `message`, `event`, `sample`, `hang`, `log_truncated`, `session_end`. Every record carries schema, kind, ISO and Unix time, monotonic milliseconds, frame, PID and session id |
| `sessions/session-*.log` | The readable mirror of the same records; engine errors include their GDScript backtrace |
| `sessions/session-*.meta.json` | The boot environment, project/host cards, args and source |
| `sessions/session-*.active.json` | Heartbeat marker: pid, clean flag, beat time, scene, sticky context, last sample, last 32 breadcrumbs, last 8 compact errors and counters. Rewritten every sample |
| `sessions/session-*.reported.json` | Written when a crash report has been generated for that session; stops a second report on later launches |
| `crashes/crash-<UTC>-<session>.json` | The forensic report (see below) |
| `crashes/crash-<UTC>-<session>.txt` | The same report for a bug comment, with a readable environment block, breadcrumbs, error stacks and log tail |
| `crashes/<session>.jsonl` / `.log` | The crashed session's log, copied before retention can touch it |

## Crash detection

A native crash cannot run a GDScript handler, so the logger relies on what is
already on disk:

1. A running session rewrites its marker with a fresh beat every sample.
2. A clean exit writes a `session_end` record and the same marker with
   `"clean": true`.
3. Every launch (and every 60 s) scans the other session markers. A marker that
   is not clean, has no companion `.reported.json`, and is not the current
   session is investigated.
4. An OS process table (`tasklist` on Windows, `ps` on Unix) is read once for the
   scan. Godot's own `OS.is_process_running` only answers for processes created
   by the same `OS` object, so it cannot see a second game instance; the process
   table is what keeps a host and a client from reporting each other. If the
   table cannot be read, the scan falls back to requiring a heartbeat older than
   15 s.
5. A dead session gets a report, its log is archived into `crashes/`, and the
   companion marker prevents duplicates.
6. Sessions without any marker are checked too: a log whose last record is not a
   clean `session_end` and whose file has not changed for 30 s is reported as
   `log_without_clean_exit`.

A torn marker is retried on the next scan once it is 15 s old. A clean marker, a
still-running pid, or an already-reported session is never reported.

The title menu shows **PREVIOUS SESSION ENDED UNEXPECTEDLY** with buttons to open
the crash-report folder and the newest `.txt` report. Reports found by the
periodic scan after the menu has opened are still written and announced on the
console as `IRONWOOD_CRASH_REPORT <path> session=<id> reason=<reason>`.

## Report anatomy

The JSON report contains:

- `previous` — the raw heartbeat marker (pid, times, scene, context, sample,
  breadcrumbs, errors, counters), retained even if the marker was polluted.
- `evidence` — reason, marker presence, pid, heartbeat age, whether the log ends
  cleanly, log existence and modification time.
- `environment`, `project`, `host`, `meta` — the crashed run's boot card,
  including GPU/CPU/memory/OS/args.
- `context`, `last_sample`, `breadcrumbs`, `errors`, `counters`.
- `log` — original and archived paths, byte count, line count and the last 400
  lines.
- `notes`, `text_path` and the detector's own session/engine.

The `.txt` report renders the environment, context, sample, breadcrumbs, error
stacks, log tail and counters. Attach the `.txt`, the `.json` and the archived
`.jsonl`/`.log` to a bug report.

## Flags and environment

| Flag | Effect |
| --- | --- |
| `--no-log` | Disable logging for this run; no session files are created |
| `--log-dir=<path>` | Use another folder (`user://…` or an absolute path) |
| `--log-level=<trace\|debug\|info\|warn\|error\|off>` | Game-event level; engine errors are always written, engine prints/samples are not filtered |
| `--log-verbose` | Same as `--log-level=trace` |
| `--log-keep=<n>` | Session retention count (default 40) |
| `--no-hang-watch` | Do not start the watchdog thread |
| `--log-hang-ms=<n>` | Watchdog threshold (default 6000; minimum 250) |
| `IRONWOOD_LOG=0`, `IRONWOOD_LOG_LEVEL`, `IRONWOOD_LOG_DIR`, `IRONWOOD_LOG_KEEP`, `IRONWOOD_LOG_HANG_MS` | Environment equivalents; they are applied after the flags |

Script regressions default to `user://logs/test` so a test run does not mix with
a play session. The folder is still isolated per test by
`tools/run_tests.py`'s `APPDATA`.

## Retention

- A session is capped at **32 MiB**; after that, messages, events and samples are
  dropped with a `log_truncated` record, and errors/shutdown continue up to
  **64 MiB**.
- The folder keeps **40 sessions** and **60 crash reports**, and is trimmed to
  **256 MiB** in total, oldest first. The session currently writing is never
  deleted, and a session or report modified in the last **90 s** is never
  pruned, so a live second instance or a just-crashed session keeps its files.
- The newest session files are kept on shutdown; pruning also runs at boot.

## Instrumenting a new system

Use the logger for meaningful state changes, not per-frame values:

```gdscript
var log := get_node_or_null("/root/Log")
if log != null:
    log.event("net", "descent_requested", {"peer": peer_id})
    log.context("delve_depth", depth)   # sticky; lands in the next marker
```

`event()` sanitizes dictionaries, arrays, vectors, colors and objects into
JSON-safe values; payloads are capped. `context()` is included in the marker and
therefore in the next crash report. The existing helpers in `main.gd`,
`arena.gd`, `delve.gd`, `session.gd`, `title.gd`, `pause_menu.gd` and
`player_state.gd` show the intended granularity.

## Verifying

```powershell
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --headless --path . --script res://tests/logging_regression.gd
```

The regression covers environment capture, JSONL validity, prints/warnings/
errors/script errors with stacks, immediate flushing, samples, the marker,
level filtering, thread-safe writes, the watchdog, retention, synthetic and real
crash detection (including a live child that must not be reported), the archive
and text report, the title notice, and the `--no-log` switch.

Manual crash check:

```powershell
$Godot = '.\.runtime\godot\Godot_v4.7.2-stable_win64_console.exe'
& $Godot --path . --log-dir=user://logs/verify
# close the game process from Task Manager (End task), then
& $Godot --path . --log-dir=user://logs/verify --quit-after 120
```

The second launch prints `IRONWOOD_CRASH_REPORT …` and the first run's folder is
archived under `logs/verify/crashes/`. Do not kill an unrelated engine or editor.

## Limits and privacy

- Official Godot release builds do not emit a minidump. The report reconstructs
  the final seconds from synchronously flushed messages and the marker; a crash
  in the last fraction of a second can therefore be missing its final line.
- A debugger pause, a long level load, or a blocking shutdown longer than the
  watchdog threshold is recorded as a `hang` (not a crash); that is intentional.
- Logs and reports stay on the machine and are never uploaded. They contain the
  computer and user names, project paths, peer addresses/ports and the local
  player name; review before attaching them to a public issue.
- GPU fields are empty under `--headless`; run windowed to capture the adapter.
