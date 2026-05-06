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

