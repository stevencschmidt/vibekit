# Tasks: 003-monitoring-survival

- [x] T021 · Custom statusline script for in-terminal ralph progress
- [x] T022 · Tighten Claude polling pattern in conventions doc
- [x] T023 · Audit + harden ralph.sh rate-limit detection
- [x] T024 · Add notify_exit helper + status file + libnotify integration
- [ ] T025 · systemd --user unit installer for reboot survival

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
