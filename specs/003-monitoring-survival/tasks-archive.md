# Archive: 003-monitoring-survival

## T021 · Custom statusline script for in-terminal ralph progress
Depends on: —
Verify: `bash -n scripts/statusline.sh && test -x scripts/statusline.sh && (cd /tmp && bash /home/steven/vibekit/scripts/statusline.sh) | wc -c | grep -qE "^[[:space:]]*[01][[:space:]]*$"`
Relevant: docs/claude/conventions.md, state/sync.json

**Problem:** The user wants ralph progress visible from within Claude Code's UI (rejecting a separate-pane TUI). Claude Code supports a custom statusline via `~/.claude/settings.json` `statusLine.command`, which is invoked periodically and renders its stdout below the prompt. We can ship a script that reads vibekit state and emits a one-line status — the user wires it into their settings (or wraps their existing ccstatusline) to get in-terminal progress.

**What to do:**

Create a new executable file `scripts/statusline.sh` with the following behavior:

1. **Project detection.** Read `pwd`. If `vibekit.config.sh` is not present in cwd, exit 0 with empty stdout. The script must be safe to run from any directory.

2. **Read state.** When in a vibekit project:
   - Parse `state/sync.json` for `ralph.task_id` and `ralph.last_sentinel` (use Python via `$PYTHON` like `sync-helpers.sh` does, with jq fallback).
   - Read the last 50 lines of `state/ralph.log` (use `tail -n 50`).

3. **Compose the status line** — pick the first matching state in this priority order:

   | State | Detection | Output |
   |---|---|---|
   | QC complete | last sentinel = `[QC_COMPLETE]` OR last log line matches `^=== QC_COMPLETE` | `vibekit · ✓ QC_COMPLETE` |
   | Stalled | last log line matches `^=== Stopped:` | `vibekit · ⚠ STALLED — see ralph.log` |
   | Rate limited | last 50 lines contain `RATE_LIMIT until` from T023 | `vibekit · ⏳ rate limit, resuming MM:SS` (compute remaining seconds from the timestamp) |
   | QC running | recent log shows `QC Round N` and no terminal sentinel after | `vibekit · QC round N` |
   | Running | task_id is set and recent log has `Iteration N/M — TXXX` | `vibekit · TXXX iter N/M` |
   | Idle | task_id is null | `vibekit · idle` |

   If none match (corrupt state etc.), output nothing — never crash the statusline.

4. **Output exactly one line** to stdout. No trailing newline issues, no ANSI escapes (Claude Code's statusline can render plain text).

5. **Performance constraint.** The script will be invoked frequently (every few seconds by ccstatusline-style mechanisms). Keep it under 100ms — avoid heavy processing, no network calls, only one `tail` and one JSON parse.

6. **Standard conventions** per `docs/claude/conventions.md`:
   - `#!/usr/bin/env bash` and `set -e`
   - `SCRIPT_DIR` / `PROJECT_ROOT` computed at top
   - Python interpreter via `PYTHON` variable resolution

7. **README addendum.** Add a section "Wiring statusline into Claude Code" to README.md with two recipes:
   - **Replace ccstatusline:** edit `~/.claude/settings.json` `statusLine.command` to `bash /path/to/vibekit/scripts/statusline.sh`.
   - **Wrap ccstatusline:** create a small wrapper that calls both and concatenates output with ` · ` between them.

   Mention that the script exits silently outside vibekit projects so wrapping is safe.

8. `chmod +x scripts/statusline.sh` after creation.

The verify command checks the script is bash-clean, executable, and outputs ≤1 byte (i.e. effectively empty / one newline) when run outside a vibekit project.

Commit with `[ralph] T021 complete — statusline script for in-terminal ralph progress`.

---

## T022 · Tighten Claude polling pattern in conventions doc
Depends on: T021
Verify: `grep -q "anchored" docs/claude/conventions.md && grep -qF '^\[QC_COMPLETE\]$' docs/claude/conventions.md`
Relevant: docs/claude/conventions.md

**Problem:** The "Running Ralph from an Interactive Session" section in `docs/claude/conventions.md` (added by T012) documents an unanchored grep pattern: `QC_COMPLETE|=== Stopped`. During spec-002, this pattern false-positive-matched the literal text `[QC_COMPLETE]` appearing inside the checkpoint-QC agent's *review prose* (the agent was reviewing its own protocol and quoted the sentinel). The poll loop exited a full task early. This is Bug C3 from the spec-002 retrospective.

**What to do:**

Edit `docs/claude/conventions.md`. Find the "Running Ralph from an Interactive Session" section (the one added by T012 with the `until grep -qE ...` pattern).

1. **Replace the unanchored pattern** with anchored regex:
   ```bash
   until grep -qE '^\[QC_COMPLETE\]$|^=== Stopped' state/ralph.log; do sleep 5; done
   ```

2. **Add an explanatory note** immediately after the pattern:
   > **Why anchored?** The unanchored pattern `QC_COMPLETE|=== Stopped` will false-positive-match the literal sentinel text appearing inside checkpoint-QC review prose (the agent often quotes `[QC_COMPLETE]` while explaining the protocol). Anchored regex (`^...$`) only matches when the sentinel is on its own line — which is how ralph.sh actually emits it. This was Bug C3 from spec-002.

3. **Add a per-task polling alternative** for cases where Claude wants per-task notifications instead of waiting for end-of-spec:
   ```bash
   # Per-task polling — exits after each TASK_COMPLETE so Claude can announce progress
   until grep -qE '^\[TASK_COMPLETE: T[0-9]+\]$|^=== Stopped' state/ralph.log; do sleep 5; done
   ```
   With a one-line note that the caller is responsible for tracking which TASK_COMPLETE was last seen and re-polling for the next one.

The verify command checks for the literal anchored pattern `^\[QC_COMPLETE\]$` and the word "anchored" in the doc.

Commit with `[ralph] T022 complete — anchored polling pattern in conventions doc`.

---

## T023 · Audit + harden ralph.sh rate-limit detection
Depends on: T022
Verify: `bash -n scripts/ralph.sh && grep -q "MAX_RATE_LIMIT_WAITS:-50" scripts/ralph.sh && grep -q "RATE_LIMIT until" scripts/ralph.sh`
Relevant: docs/claude/conventions.md, scripts/ralph.sh

**Problem:** Three issues with the current rate-limit handling:

1. **Pattern coverage** — `is_rate_limited_output()` (lines ~249–260) checks only 4 patterns: `rate limit`, `usage limit`, `too many requests`, `exceeded.*quota`. Claude CLI may emit other phrasings (`5-hour limit`, `weekly limit`, `subscription limit`, `reset at`) that would slip through and be counted as stalls.

2. **Wait cap too low** — `MAX_RATE_LIMIT_WAITS=10` exits ralph after 10 consecutive rate-limit waits. A multi-day spec crossing many quota windows could legitimately need more.

3. **No structured log line** — when a rate limit fires, there's no parseable line in `state/ralph.log` for `scripts/statusline.sh` (T021) to display a countdown. The countdown only renders on stderr/tty.

**What to do:**

In `scripts/ralph.sh`:

1. **Extend `is_rate_limited_output()`** (around lines 249–260) with additional case-insensitive grep patterns:
   - `5-hour limit`
   - `weekly limit`
   - `subscription limit`
   - `reset at`

   Keep the existing 4 patterns. The function should still return 0 (success / is rate-limited) on any match.

2. **Make `MAX_RATE_LIMIT_WAITS` overridable and raise default to 50.** Find the line `MAX_RATE_LIMIT_WAITS=10` (likely near the top with other constants). Replace with:
   ```bash
   MAX_RATE_LIMIT_WAITS=${MAX_RATE_LIMIT_WAITS:-50}
   ```

3. **Add a structured log line** when rate limit is detected and the wait begins. Find the rate-limit handling block (around lines 263–317 per T012/T009 architecture). Just before the live countdown loop, append:
   ```bash
   echo "[$ITERATION] RATE_LIMIT until $RESET_TIME ($SECONDS_TO_WAIT s)" >> "$LOG_FILE"
   ```
   Where `$RESET_TIME` is the absolute wall-clock reset time (already computed) and `$SECONDS_TO_WAIT` is the integer seconds until reset. If those variable names differ in the actual code, adapt to use whatever the existing code computes.

The verify command checks bash syntax, the env-overridable cap, and the new structured log line.

Commit with `[ralph] T023 complete — harden rate-limit detection`.

---

## T024 · Add notify_exit helper + status file + libnotify integration
Depends on: T023
Verify: `bash -n scripts/ralph.sh && [ "$(grep -c 'notify_exit' scripts/ralph.sh)" -ge 11 ] && grep -q "ralph.status" .gitignore`
Relevant: scripts/ralph.sh, .gitignore

**Problem:** When ralph exits — whether `[QC_COMPLETE]`, a stall, a block, or max-iter — the user has no notification. They have to either watch the terminal or come back and check `state/ralph.log`. The user has accepted local notifications as a starting point: write structured events to a file (so the statusline can display them), ring a terminal bell, and call `notify-send` if libnotify is available.

**What to do:**

In `scripts/ralph.sh`:

1. **Add a `notify_exit` helper** near the top of the file, right after the `commit_state_files` helper (added by T019). The helper should be:
   ```bash
   notify_exit() {
     local event="$1" summary="$2"
     local ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
     printf '{"ts":"%s","event":"%s","summary":"%s"}\n' "$ts" "$event" "$summary" \
       >> "$PROJECT_ROOT/state/ralph.status"
     command -v notify-send >/dev/null 2>&1 && \
       notify-send "vibekit/$event" "$summary" 2>/dev/null || true
     printf '\a' > /dev/tty 2>/dev/null || true
   }
   ```
   The `|| true` and `2>/dev/null` make every step graceful — missing libnotify, no TTY (when run as systemd service), missing state directory, none of these should crash ralph.

2. **Hook into all 10 exit paths** in ralph.sh. Per the spec-003 plan, these are at approximately lines:
   - Line ~402: `=== Stopped: interrupted at ...` → `notify_exit "INTERRUPTED" "ralph caught SIGINT/SIGTERM"`
   - Line ~451: `=== Stopped: no task assigned at ...` → `notify_exit "IDLE" "no task_id in sync.json — nothing to do"`
   - Line ~514: `=== Stopped: QC round cap ...` → `notify_exit "QC_ROUND_CAP" "QC exceeded $MAX_QC_ROUNDS rounds without [QC_COMPLETE]"`
   - Line ~529 (and other rate-limit cap exits): `=== Stopped: rate limit wait cap ...` → `notify_exit "RATE_LIMIT_CAP" "ralph hit $MAX_RATE_LIMIT_WAITS consecutive rate-limit waits"`
   - Line ~567: `=== QC_COMPLETE at ...` → `notify_exit "QC_COMPLETE" "spec complete after $ITERATION iterations"`
   - Line ~587: `=== Stopped: QC stalled at ...` → `notify_exit "QC_STALL" "QC produced no [QC_COMPLETE] and no new tasks"`
   - Line ~704: `=== Stopped: $TASK_ID blocked at ...` → `notify_exit "TASK_BLOCKED" "$TASK_ID blocked: $BLOCK_REASON"`
   - Line ~941: `=== Stopped: $TASK_ID verify-failed 3x ...` → `notify_exit "VERIFY_FAILED" "$TASK_ID failed verify_build 3 times"`
   - Line ~973: `=== Stopped: $TASK_ID stalled 3x ...` → `notify_exit "TASK_STALL" "$TASK_ID produced no sentinel 3 times"`
   - Line ~990: `=== Stopped at max iterations ...` → `notify_exit "MAX_ITER" "ralph hit MAX_ITERATIONS=$MAX_ITERATIONS without completion"`

   Place each `notify_exit` call **immediately before** the corresponding `=== Stopped:` / `=== QC_COMPLETE` log line so the order is: notify → log → exit. If exact line numbers have shifted from earlier task work, find the equivalent log line by `grep -n "=== Stopped\|=== QC_COMPLETE" scripts/ralph.sh` and add the call adjacent to each.

3. **Add `state/ralph.status` to `.gitignore`** at the project root. This file is a runtime event log, never committed.

4. **README addendum** under a new "Notifications" subsection (place after the section T021 added for statusline wiring):
   > For desktop popup notifications, install libnotify-bin (Debian/Ubuntu: `sudo apt install libnotify-bin`). Without it, ralph still emits a terminal bell on exit and writes structured events to `state/ralph.status` for the statusline to display.

The verify command checks bash syntax, that `notify_exit` appears at least 11 times (1 definition + 10 callsites), and that the status file is gitignored.

Commit with `[ralph] T024 complete — notify_exit helper for ralph exit paths`.

---

## T025 · systemd --user unit installer for reboot survival
Depends on: T024
Verify: `bash -n scripts/install-service.sh && test -x scripts/install-service.sh && bash scripts/install-service.sh --dry-run 2>&1 | grep -q "loginctl enable-linger"`
Relevant: docs/claude/conventions.md, README.md

**Problem:** Once ralph is launched via `nohup`, it survives terminal close — but not host reboot. For long-running specs (multi-day, crossing rate-limit windows), a reboot loses progress. The user must manually re-launch ralph after every restart. systemd --user with linger enabled solves this: the service auto-starts at boot independent of login state.

**What to do:**

Create a new executable file `scripts/install-service.sh`:

1. **Usage and dry-run flag:**
   - `bash scripts/install-service.sh` — generate the unit, print enable instructions
   - `bash scripts/install-service.sh --dry-run` — print what would be generated and the enable instructions, but do not write any files

2. **Project detection:** Compute `PROJECT_ROOT` via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` and `PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`. Validate `vibekit.config.sh` exists at `PROJECT_ROOT`. If not, print an error and exit 1.

3. **Compute slug:** `SLUG="$(basename "$PROJECT_ROOT")"` — used as the systemd template instance.

4. **Generate the unit file** at `~/.config/systemd/user/vibekit-ralph@.service` (template unit, instance via `%i`). Skip the write in `--dry-run` mode.

   Unit content:
   ```
   [Unit]
   Description=Vibekit ralph for %i
   After=network-online.target

   [Service]
   Type=simple
   WorkingDirectory=PROJECT_ROOT_PLACEHOLDER
   ExecStart=/bin/bash PROJECT_ROOT_PLACEHOLDER/scripts/ralph.sh
   Restart=no
   StandardOutput=append:PROJECT_ROOT_PLACEHOLDER/state/ralph.log
   StandardError=inherit

   [Install]
   WantedBy=default.target
   ```
   Substitute `PROJECT_ROOT_PLACEHOLDER` with the absolute path of `PROJECT_ROOT` before writing. (Don't use `%h` — paths can vary; absolute is safer.)

5. **`Restart=no` is intentional.** Document it in a comment line in the unit and in the script's stdout output. We want reboot survival, not auto-restart on real failures (which would loop forever on a stall).

6. **Print user instructions** (always, regardless of `--dry-run`):
   ```
   Unit written to: ~/.config/systemd/user/vibekit-ralph@.service
   
   To enable reboot survival, run these commands ONCE:
   
     sudo loginctl enable-linger $USER
     systemctl --user daemon-reload
     systemctl --user enable --now vibekit-ralph@<slug>.service
   
   Where <slug> = ${SLUG}
   
   Notes:
   - linger lets your user services run without an active login (required for boot-time start)
   - Restart=no means stalls and failures stop the service — reboots restart it
   - To stop: systemctl --user stop vibekit-ralph@${SLUG}.service
   - Logs: journalctl --user -u vibekit-ralph@${SLUG}.service -f
   ```

7. **README addendum** — add a new section "Reboot Survival":
   > Long-running specs may need to survive host reboots. Vibekit ships a systemd --user unit installer:
   >
   > ```
   > bash scripts/install-service.sh
   > ```
   >
   > Then follow the printed instructions to enable linger and start the service. After that, ralph will auto-resume from `state/sync.json` on every boot. `Restart=no` means stalls and failures still require human review — this is reboot survival, not auto-recovery from real failures.

8. Standard bash conventions — `set -e`, SCRIPT_DIR/PROJECT_ROOT pattern, `chmod +x` after creation.

The verify command checks bash syntax, executability, and that `--dry-run` mode prints the `loginctl enable-linger` instruction (proving the script ran end-to-end without writing files).

Commit with `[ralph] T025 complete — systemd --user installer for reboot survival`.

---
